// Decimal floating point through the emitter.
//
// The reader and the type model carry GNU C's _Decimal32, _Decimal64 and
// _Decimal128 as far as the value of a constant: their sizes, their alignments
// and the bytes a constant keeps are all settled before this back end sees them.
// What is left is the two things a program does with an object of one: it writes
// a constant into it, and it converts it to a double.
//
// The conversion is the part that has to be right rather than fast. Multiplying
// and dividing a double by ten rounds at every step and disagrees with gcc in the
// last bits, which is why the types were refused outright rather than guessed at.
// The routine here follows decimal/convert.v's to_f64_bits, which is the measured
// specification of gcc's own answer: it keeps sixty-four significant bits of the
// coefficient in a mantissa, scales by ten nineteen digits at a time with a
// sticky bit for whatever it drops, and rounds once at the end to the fifty-three
// bits a double keeps, or fewer for a subnormal. In machine code that is two-word
// integer arithmetic: multiply the pair by a power of ten and keep the leading
// sixty-four significant bits, divide a scaled numerator by a power of ten, and
// round once.
//
// The routine is emitted only for the formats a unit actually converts, so a
// program with no decimal value pays nothing for it. Its two halves are the
// format-specific decode, a few loads and shifts, and one shared core that scales
// and rounds. The core takes the coefficient in rax:rdx, the exponent in rcx and
// the sign in r8, and leaves the double's bits in xmm0.
//
// A constant is written into its object by storing the bytes the decimal module
// encodes, which is what gcc stores: the same little-endian BID form its own
// tests record.
module codegen

import ast
import backend
import decimal
import types

// decimal_routine_name is the label a conversion of one format enters. The width
// names it, and the three widths differ, so the names do not collide.
fn decimal_routine_name(format decimal.Format) string {
	return 'vcc_decimal_to_double_${format.bytes()}'
}

// decimal_core_name is the one shared scaling and rounding core every format
// enters after its own decode.
const decimal_core_name = 'vcc_decimal_to_double_core'

// decimal_of says whether an expression has one of the decimal floating types.
fn (e Emitter) decimal_of(expr ast.Expr) bool {
	return expr.typ.kind.is_decimal()
}

// decimal_format_of is the format a decimal spelling names, or none for a type
// that is not one. A spelling carries its qualifiers, so it is read the way the
// rest of this back end reads a written type.
fn (e Emitter) decimal_format_of(written string) ?decimal.Format {
	typ := types.from_words(written.split(' ')) or { return none }
	if !typ.kind.is_decimal() {
		return none
	}
	return typ.kind.decimal_format()
}

// A DecimalReloc is one four-byte distance inside the emitted routine that is
// filled in once every label of the routine is placed.
struct DecimalReloc {
	at   int
	name string
}

// A DecimalRoutine is the machine code of the conversion routines while it is
// being built: the bytes, the labels within it, and the distances to fill in.
struct DecimalRoutine {
	t   &backend.Target
	reg DecimalRegisters
mut:
	bytes  []u8
	labels map[string]int
	relocs []DecimalReloc
	// pre is the prefix a routine's own labels carry. Several routines are built
	// into one DecimalRoutine and share the label map, and every routine names
	// its internal labels the same way, so without a prefix the second routine's
	// `zero`, `round` and `done` would overwrite the first's and the first
	// routine would jump into the second.
	pre string
}

// DecimalRegisters is the registers the routine works in, taken from the target
// once so the code below names them rather than looking them up. rbp and rsp are
// here because an arithmetic routine holds its decimal digits in a frame of its
// own, while the conversion routine needs neither.
struct DecimalRegisters {
	rax  backend.Register
	rbx  backend.Register
	rcx  backend.Register
	rdx  backend.Register
	rsi  backend.Register
	rdi  backend.Register
	rbp  backend.Register
	rsp  backend.Register
	r8   backend.Register
	r9   backend.Register
	r10  backend.Register
	r11  backend.Register
	r12  backend.Register
	r13  backend.Register
	r14  backend.Register
	r15  backend.Register
	xmm0 backend.Register
}

fn decimal_registers(t &backend.Target) ?DecimalRegisters {
	rax := t.reg('rax') or { return none }
	rbx := t.reg('rbx') or { return none }
	rcx := t.reg('rcx') or { return none }
	rdx := t.reg('rdx') or { return none }
	rsi := t.reg('rsi') or { return none }
	rdi := t.reg('rdi') or { return none }
	rbp := t.reg('rbp') or { return none }
	rsp := t.reg('rsp') or { return none }
	r8 := t.reg('r8') or { return none }
	r9 := t.reg('r9') or { return none }
	r10 := t.reg('r10') or { return none }
	r11 := t.reg('r11') or { return none }
	r12 := t.reg('r12') or { return none }
	r13 := t.reg('r13') or { return none }
	r14 := t.reg('r14') or { return none }
	r15 := t.reg('r15') or { return none }
	xmm0 := t.float_reg('xmm0') or { return none }
	return DecimalRegisters{
		rax:  rax
		rbx:  rbx
		rcx:  rcx
		rdx:  rdx
		rsi:  rsi
		rdi:  rdi
		rbp:  rbp
		rsp:  rsp
		r8:   r8
		r9:   r9
		r10:  r10
		r11:  r11
		r12:  r12
		r13:  r13
		r14:  r14
		r15:  r15
		xmm0: xmm0
	}
}

// op appends the bytes of one instruction. Every instruction encoder is
// fallible, so the result is unwrapped here rather than at each call site, and an
// instruction that cannot be written becomes the routine's error.
fn (mut r DecimalRoutine) op(bytes []u8) {
	r.bytes << bytes
}

fn (mut r DecimalRoutine) place(name string) {
	r.labels[r.pre + name] = r.bytes.len
}

// entry places a label that is the routine's own name in the image, which a call
// site reaches, so it is not prefixed.
fn (mut r DecimalRoutine) entry(name string) {
	r.labels[name] = r.bytes.len
}

fn (mut r DecimalRoutine) call(name string) {
	r.op(r.t.call_near(0))
	r.relocs << DecimalReloc{
		at:   r.bytes.len - 4
		name: name
	}
}

fn (mut r DecimalRoutine) jump(name string) {
	r.op(r.t.jump(0))
	r.relocs << DecimalReloc{
		at:   r.bytes.len - 4
		name: r.pre + name
	}
}

fn (mut r DecimalRoutine) branch(condition backend.Condition, name string) {
	r.op(r.t.jump_condition(condition, 0))
	r.relocs << DecimalReloc{
		at:   r.bytes.len - 4
		name: r.pre + name
	}
}

// resolved fills every distance in and returns the routine's bytes. A distance is
// from the end of its instruction, which is four bytes past the field, and every
// label is within the routine, so the difference is signed and small.
fn (mut r DecimalRoutine) resolved() []u8 {
	for fix in r.relocs {
		to := r.labels[fix.name]
		disp := u32(i32(to - (fix.at + 4)))
		r.bytes[fix.at] = u8(disp & 0xff)
		r.bytes[fix.at + 1] = u8((disp >> 8) & 0xff)
		r.bytes[fix.at + 2] = u8((disp >> 16) & 0xff)
		r.bytes[fix.at + 3] = u8((disp >> 24) & 0xff)
	}
	return r.bytes
}

// emit_decimal_routines writes the conversion routines a unit used, and no
// others, behind the functions of the image. It is called once, after the
// functions, so the name a call site wrote finds a label the layout will place.
fn (mut e Emitter) emit_decimal_routines() !void {
	mut wanted := []decimal.Format{}
	for format in [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128] {
		if decimal_routine_name(format) in e.decimal_used {
			wanted << format
		}
	}
	if wanted.len == 0 {
		return
	}
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(1, 1, 'internal: the target has no register a decimal conversion needs')
		return error('decimal registers')
	}
	mut r := DecimalRoutine{
		t:      &e.target
		reg:    registers
		labels: map[string]int{}
	}
	e.decimal_core(mut r)!
	for format in wanted {
		e.decimal_wrapper(mut r, format)!
	}
	base := e.program.text.len
	bytes := r.resolved()
	e.program.text << bytes
	e.program.labels[decimal_core_name] = base + r.labels[decimal_core_name]
	for format in wanted {
		name := decimal_routine_name(format)
		e.program.labels[name] = base + r.labels[name]
	}
}

// decimal_core scales and rounds. On entry rax:rdx is the coefficient, rcx the
// exponent of its least significant digit and r8 the sign as zero or one; on
// exit xmm0 is the double's bits. It matches decimal/convert.v's to_f64_bits
// case for case: the coefficient is put in the top of a word with its dropped
// bits in the sticky, the exponent is consumed nineteen digits at a time, and the
// rounding once at the end is to nearest with ties to even.
fn (e Emitter) decimal_core(mut r DecimalRoutine) !void {
	g := r.reg
	r.place(decimal_core_name)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	r.op(r.t.move_register64(g.r9, g.rax)!) // c_lo
	r.op(r.t.move_register64(g.r10, g.rdx)!) // c_hi
	r.op(r.t.move_register64(g.rsi, g.rcx)!) // exp10
	r.op(r.t.xor_word(g.r13, g.r13)!) // sticky = 0
	// The coefficient is put in the top of a word. When its high word is set the
	// mantissa is the leading sixty-four significant bits taken at the top; the
	// bits below them are the sticky. Otherwise the single word is shifted up to
	// the top and the shift is the exponent's adjustment.
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, 'core_low')
	r.op(r.t.count_leading(g.rcx, g.r10, true)!) // clz of the high word
	r.op(r.t.move_immediate64(g.r14, 64)!)
	r.op(r.t.subtract_word(g.r14, g.rcx)!) // drop = 64 - clz
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r15)!) // 1 << drop
	r.op(r.t.add_immediate(g.r15, -1))
	r.op(r.t.move_register64(g.rax, g.r9)!)
	r.op(r.t.and_word(g.rax, g.r15)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'core_hi_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('core_hi_clean')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.move_register64(g.rax, g.r9)!)
	r.op(r.t.shift_right_word_register(g.rax)!) // c_lo >> drop
	r.op(r.t.move_register64(g.r11, g.r10)!)
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r11)!) // c_hi << (64 - drop)
	r.op(r.t.or_word(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rbx, g.r11)!) // mant
	r.op(r.t.move_register64(g.r12, g.r14)!) // e2 = drop
	r.jump('core_scaled')
	r.place('core_low')
	r.op(r.t.test_word(g.r9)!)
	r.branch(.equal, 'core_zero')
	r.op(r.t.count_leading(g.rcx, g.r9, true)!)
	r.op(r.t.move_register64(g.rbx, g.r9)!)
	r.op(r.t.shift_left_word_register(g.rbx)!) // mant = c_lo << clz
	r.op(r.t.negate_word(g.rcx)!)
	r.op(r.t.move_register64(g.r12, g.rcx)!) // e2 = -clz
	r.place('core_scaled')
	// Scale up: consume the positive exponent nineteen digits at a time,
	// multiplying the mantissa by ten to the chunk and keeping its leading
	// sixty-four significant bits, with the dropped bits in the sticky.
	r.place('core_up')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.less_or_equal, 'core_down')
	r.op(r.t.move_register64(g.rcx, g.rsi)!)
	r.op(r.t.add_immediate(g.rcx, -19))
	r.branch(.less_or_equal, 'core_up_exp')
	r.op(r.t.move_immediate64(g.r9, 19)!)
	r.jump('core_up_chunk')
	r.place('core_up_exp')
	r.op(r.t.move_register64(g.r9, g.rsi)!)
	r.place('core_up_chunk')
	r.op(r.t.move_immediate64(g.r14, 1)!)
	r.op(r.t.move_register64(g.r15, g.r9)!)
	r.place('core_up_power')
	r.op(r.t.test_word(g.r15)!)
	r.branch(.equal, 'core_up_powered')
	r.op(r.t.imul_immediate(g.r14, 10))
	r.op(r.t.add_immediate(g.r15, -1))
	r.jump('core_up_power')
	r.place('core_up_powered')
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.multiply_pair(g.r14)!) // rdx:rax = mant * d
	r.op(r.t.count_leading(g.rcx, g.rdx, true)!) // clz of the product's high word
	r.op(r.t.move_immediate64(g.r14, 64)!)
	r.op(r.t.subtract_word(g.r14, g.rcx)!) // drop
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, -64))
	r.branch(.equal, 'core_up_full')
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r15)!) // 1 << drop
	r.op(r.t.add_immediate(g.r15, -1))
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.and_word(g.r11, g.r15)!)
	r.op(r.t.test_word(g.r11)!)
	r.branch(.equal, 'core_up_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('core_up_clean')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.shift_right_word_register(g.r11)!) // product_lo >> drop
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.rdx)!) // product_hi << (64 - drop)
	r.op(r.t.or_word(g.rdx, g.r11)!)
	r.op(r.t.move_register64(g.rbx, g.rdx)!)
	r.op(r.t.add_reg64(g.r12, g.r14))
	r.op(r.t.subtract_word(g.rsi, g.r9)!)
	r.jump('core_up')
	r.place('core_up_full')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'core_up_full_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('core_up_full_clean')
	r.op(r.t.move_register64(g.rbx, g.rdx)!)
	r.op(r.t.add_immediate(g.r12, 64))
	r.op(r.t.subtract_word(g.rsi, g.r9)!)
	r.jump('core_up')
	// Scale down: consume the negative exponent, dividing a numerator scaled by
	// the top bit of the divisor. A quotient below two to the sixty-second cannot
	// be a double's leading bits and underflows to zero, matching the reference.
	r.place('core_down')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, 'core_round')
	r.op(r.t.move_register64(g.rcx, g.rsi)!)
	r.op(r.t.negate_word(g.rcx)!)
	r.op(r.t.add_immediate(g.rcx, -19))
	r.branch(.less_or_equal, 'core_down_exp')
	r.op(r.t.move_immediate64(g.r9, 19)!)
	r.jump('core_down_chunk')
	r.place('core_down_exp')
	r.op(r.t.move_register64(g.r9, g.rsi)!)
	r.op(r.t.negate_word(g.r9)!)
	r.place('core_down_chunk')
	r.op(r.t.move_immediate64(g.r14, 1)!)
	r.op(r.t.move_register64(g.r15, g.r9)!)
	r.place('core_down_power')
	r.op(r.t.test_word(g.r15)!)
	r.branch(.equal, 'core_down_powered')
	r.op(r.t.imul_immediate(g.r14, 10))
	r.op(r.t.add_immediate(g.r15, -1))
	r.jump('core_down_power')
	r.place('core_down_powered')
	r.op(r.t.count_leading(g.rcx, g.r14, true)!) // clz of the divisor
	r.op(r.t.move_immediate64(g.r11, 63)!)
	r.op(r.t.subtract_word(g.r11, g.rcx)!) // k = 63 - clz
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.shift_left_word_register(g.rax)!) // numerator_lo = mant << k
	r.op(r.t.move_register64(g.r15, g.rbx)!)
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r11)!)
	r.op(r.t.shift_right_word_register(g.r15)!) // numerator_hi = mant >> (64 - k)
	r.op(r.t.move_register64(g.rdx, g.r15)!)
	r.op(r.t.subtract_word(g.r12, g.r11)!) // e2 -= k
	r.op(r.t.divide_pair(g.r14)!) // rax = quotient, rdx = remainder
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'core_down_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('core_down_clean')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'core_zero')
	r.op(r.t.count_leading(g.rcx, g.rax, true)!)
	r.op(r.t.move_register64(g.r15, g.rcx)!)
	r.op(r.t.shift_left_word_register(g.rax)!) // normalize
	r.op(r.t.subtract_word(g.r12, g.r15)!)
	r.op(r.t.move_register64(g.rbx, g.rax)!)
	r.op(r.t.add_reg64(g.rsi, g.r9))
	r.jump('core_down')
	// Round once, to nearest with ties to even, from the sixty-four bit mantissa.
	r.place('core_round')
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.shift_right_word(g.rax, 11)!) // significand
	r.op(r.t.move_register64(g.rcx, g.rbx)!)
	r.op(r.t.and_immediate(g.rcx, 0x7ff)!) // rest
	r.op(r.t.move_immediate64(g.r15, 0x400)!)
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.subtract_word(g.r11, g.r15)!)
	r.branch(.below, 'core_kept') // rest < half
	r.branch(.above, 'core_carry') // rest > half
	r.op(r.t.test_word(g.r13)!)
	r.branch(.not_equal, 'core_carry') // half and anything dropped rounds up
	r.op(r.t.move_register64(g.rcx, g.rax)!)
	r.op(r.t.and_immediate(g.rcx, 1)!) // the significand's low bit
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.not_equal, 'core_carry') // half and an odd significand rounds up
	r.jump('core_kept')
	r.place('core_carry')
	r.op(r.t.add_immediate(g.rax, 1))
	r.place('core_kept')
	r.op(r.t.move_register64(g.r14, g.r12)!)
	r.op(r.t.add_immediate(g.r14, 63)) // unbiased = e2 + 63
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_immediate64(g.r9, 53)!)
	r.op(r.t.shift_left_word_register(g.r15)!) // 2^53
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.subtract_word(g.r11, g.r15)!)
	r.branch(.not_equal, 'core_no_carry')
	r.op(r.t.shift_right_word(g.rax, 1)!) // the rounding carried out
	r.op(r.t.add_immediate(g.r14, 1))
	r.place('core_no_carry')
	r.op(r.t.move_register64(g.r11, g.r14)!)
	r.op(r.t.add_immediate(g.r11, -1024))
	r.branch(.greater_or_equal, 'core_infinity')
	r.op(r.t.move_register64(g.r11, g.r14)!)
	r.op(r.t.add_immediate(g.r11, 1022))
	r.branch(.greater_or_equal, 'core_normal')
	r.jump('core_subnormal')
	r.place('core_normal')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, 1023))
	r.op(r.t.shift_left_word(g.rcx, 52)!)
	r.op(r.t.move_immediate64(g.r15, 0xfffffffffffff)!)
	r.op(r.t.and_word(g.rax, g.r15)!)
	r.op(r.t.or_word(g.rcx, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 63)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.jump('core_finish')
	r.place('core_infinity')
	r.op(r.t.move_immediate64(g.rcx, 0x7ff0000000000000)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 63)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.jump('core_finish')
	r.place('core_zero')
	r.op(r.t.move_register64(g.rax, g.r8)!)
	r.op(r.t.shift_left_word(g.rax, 63)!)
	r.jump('core_finish')
	// A subnormal keeps fewer bits: the significand is shifted down and rounded at
	// the bit it drops, and a value that rounds up to the smallest normal is one.
	r.place('core_subnormal')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, 1022))
	r.op(r.t.negate_word(g.rcx)!) // shift = -(unbiased + 1022)
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.add_immediate(g.r11, -64))
	r.branch(.greater_or_equal, 'core_zero')
	r.op(r.t.move_register64(g.rdi, g.rcx)!)
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.shift_left_word_register(g.r10)!) // 1 << shift
	r.op(r.t.add_immediate(g.r10, -1)) // mask
	r.op(r.t.move_register64(g.r9, g.rax)!)
	r.op(r.t.and_word(g.r9, g.r10)!) // rem
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.shift_right_word_register(g.r11)!) // denormal
	r.op(r.t.move_register64(g.rcx, g.rdi)!)
	r.op(r.t.add_immediate(g.rcx, -1))
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.shift_left_word_register(g.r15)!) // h = 1 << (shift - 1)
	r.op(r.t.move_register64(g.rcx, g.r9)!)
	r.op(r.t.subtract_word(g.rcx, g.r15)!)
	r.branch(.above, 'core_sub_carry')
	r.branch(.below, 'core_sub_kept')
	r.op(r.t.test_word(g.r13)!)
	r.branch(.not_equal, 'core_sub_carry')
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.and_immediate(g.rcx, 1)!) // the denormal's low bit
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.not_equal, 'core_sub_carry')
	r.jump('core_sub_kept')
	r.place('core_sub_carry')
	r.op(r.t.add_immediate(g.r11, 1))
	r.place('core_sub_kept')
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_immediate64(g.rcx, 52)!)
	r.op(r.t.shift_left_word_register(g.r15)!) // 2^52
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.subtract_word(g.rcx, g.r15)!)
	r.branch(.not_equal, 'core_sub_not_one')
	r.op(r.t.move_register64(g.r11, g.r15)!)
	r.place('core_sub_not_one')
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 63)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.place('core_finish')
	r.op(r.t.move_word_to_double(g.xmm0, g.rax)!)
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// decimal_wrapper decodes one format's bytes into the core's arguments. The
// address is in rax; the word or two words at it are read, the sign is taken off,
// the exponent is biased out, and the special encodings leave before the core.
// The field widths differ by format and nothing else does.
fn (e Emitter) decimal_wrapper(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	name := decimal_routine_name(format)
	r.place(name)
	match format {
		.decimal32 {
			// One word: the sign is the top bit, the next five bits are the
			// special markers, the coefficient and exponent share the rest. A
			// coefficient that fills the coefficient bits takes the large form,
			// where the two bits under the sign are the marker and the exponent
			// moves down.
			r.op(r.t.load_indirect(g.rax, g.rax, 4)!)
			r.op(r.t.move_register64(g.r8, g.rax)!)
			r.op(r.t.shift_right_word(g.r8, 31)!)
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.shift_right_word(g.r10, 26)!)
			r.op(r.t.and_immediate(g.r10, 0x1f)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -30))
			r.branch(.equal, 'dec32_inf')
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -31))
			r.branch(.equal, 'dec32_nan')
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.shift_right_word(g.r10, 29)!)
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -3))
			r.branch(.equal, 'dec32_large')
			r.op(r.t.move_register64(g.rcx, g.rax)!)
			r.op(r.t.and_immediate(g.rcx, 0x7fffff)!)
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.shift_right_word(g.rdx, 23)!)
			r.op(r.t.move_immediate64(g.r10, 0xff)!)
			r.op(r.t.and_word(g.rdx, g.r10)!)
			r.op(r.t.add_immediate(g.rdx, -101))
			r.op(r.t.move_register64(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			r.place('dec32_large')
			r.op(r.t.move_register64(g.rcx, g.rax)!)
			r.op(r.t.and_immediate(g.rcx, 0x1fffff)!)
			r.op(r.t.move_immediate64(g.r10, 0x800000)!)
			r.op(r.t.add_reg64(g.rcx, g.r10))
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.shift_right_word(g.rdx, 21)!)
			r.op(r.t.move_immediate64(g.r10, 0xff)!)
			r.op(r.t.and_word(g.rdx, g.r10)!)
			r.op(r.t.add_immediate(g.rdx, -101))
			r.op(r.t.move_register64(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			e.decimal_special(mut r, 'dec32_inf', 'dec32_nan')!
		}
		.decimal64 {
			// One word: the same shape with the sign at bit sixty-three, the
			// markers below it, and a fifty-three bit coefficient.
			r.op(r.t.load_indirect(g.rax, g.rax, 8)!)
			r.op(r.t.move_register64(g.r8, g.rax)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.shift_right_word(g.r10, 58)!)
			r.op(r.t.and_immediate(g.r10, 0x1f)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -30))
			r.branch(.equal, 'dec64_inf')
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -31))
			r.branch(.equal, 'dec64_nan')
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.shift_right_word(g.r10, 61)!)
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -3))
			r.branch(.equal, 'dec64_large')
			r.op(r.t.move_immediate64(g.r11, 0x1fffffffffffff)!)
			r.op(r.t.move_register64(g.rcx, g.rax)!)
			r.op(r.t.and_word(g.rcx, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.shift_right_word(g.rdx, 53)!)
			r.op(r.t.move_immediate64(g.r11, 0x3ff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -398))
			r.op(r.t.move_register64(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			r.place('dec64_large')
			r.op(r.t.move_immediate64(g.r11, 0x7ffffffffffff)!)
			r.op(r.t.move_register64(g.rcx, g.rax)!)
			r.op(r.t.and_word(g.rcx, g.r11)!)
			r.op(r.t.move_immediate64(g.r11, 0x20000000000000)!)
			r.op(r.t.or_word(g.rcx, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.shift_right_word(g.rdx, 51)!)
			r.op(r.t.move_immediate64(g.r11, 0x3ff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -398))
			r.op(r.t.move_register64(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			e.decimal_special(mut r, 'dec64_inf', 'dec64_nan')!
		}
		.decimal128 {
			// Two words: the sign and markers live in the high word, the low
			// word is the bottom of the coefficient. The exponent is taken from
			// the high word, and the coefficient's high part is what is left.
			r.op(r.t.load_indirect(g.rax, g.r9, 8)!)
			r.op(r.t.load_slot(g.rax, 8, g.r10, 8)!)
			r.op(r.t.move_register64(g.r8, g.r10)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.move_register64(g.r11, g.r10)!)
			r.op(r.t.shift_right_word(g.r11, 58)!)
			r.op(r.t.and_immediate(g.r11, 0x1f)!)
			r.op(r.t.move_register64(g.rcx, g.r11)!)
			r.op(r.t.add_immediate(g.rcx, -30))
			r.branch(.equal, 'dec128_inf')
			r.op(r.t.move_register64(g.rcx, g.r11)!)
			r.op(r.t.add_immediate(g.rcx, -31))
			r.branch(.equal, 'dec128_nan')
			r.op(r.t.move_register64(g.r11, g.r10)!)
			r.op(r.t.shift_right_word(g.r11, 61)!)
			r.op(r.t.and_immediate(g.r11, 3)!)
			r.op(r.t.move_register64(g.rcx, g.r11)!)
			r.op(r.t.add_immediate(g.rcx, -3))
			r.branch(.equal, 'dec128_large')
			r.op(r.t.move_immediate64(g.r11, 0x1ffffffffffff)!)
			r.op(r.t.move_register64(g.rax, g.r10)!)
			r.op(r.t.and_word(g.rax, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 49)!)
			r.op(r.t.move_immediate64(g.r11, 0x3fff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -6176))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.move_register64(g.rax, g.r9)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			r.place('dec128_large')
			r.op(r.t.move_immediate64(g.r11, 0x7fffffffffff)!)
			r.op(r.t.move_register64(g.rax, g.r10)!)
			r.op(r.t.and_word(g.rax, g.r11)!)
			r.op(r.t.move_immediate64(g.r11, 0x2000000000000)!)
			r.op(r.t.or_word(g.rax, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 47)!)
			r.op(r.t.move_immediate64(g.r11, 0x3fff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -6176))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.move_register64(g.rdx, g.rax)!)
			r.op(r.t.move_register64(g.rax, g.r9)!)
			r.call(decimal_core_name)
			r.op(r.t.ret())
			e.decimal_special(mut r, 'dec128_inf', 'dec128_nan')!
		}
	}
}

// decimal_special writes the two leaves for a format's infinity and NaN. The bits
// are the double's own infinity and quiet NaN, with the sign the decimal carried;
// this matches decimal/convert.v, which gives the same two answers.
fn (e Emitter) decimal_special(mut r DecimalRoutine, infinity string, nan string) !void {
	g := r.reg
	r.place(infinity)
	r.op(r.t.move_immediate64(g.rax, 0x7ff0000000000000)!)
	r.op(r.t.move_register64(g.rcx, g.r8)!)
	r.op(r.t.shift_left_word(g.rcx, 63)!)
	r.op(r.t.or_word(g.rax, g.rcx)!)
	r.op(r.t.move_word_to_double(g.xmm0, g.rax)!)
	r.op(r.t.ret())
	r.place(nan)
	r.op(r.t.move_immediate64(g.rax, 0x7ff8000000000000)!)
	r.op(r.t.move_word_to_double(g.xmm0, g.rax)!)
	r.op(r.t.ret())
}

// decimal_constant_bytes is the encoding of a decimal constant, with a leading
// minus folded into the sign bit, or none for an expression that is not one. The
// reader keeps `-1.5df` as the negation of the constant rather than a constant
// with a negative sign, and the sign the encoding carries is the top bit of the
// last byte, so negating it is that bit's flip.
fn decimal_constant_bytes(expr ast.Expr) ?[]u8 {
	mut negated := false
	mut constant := expr
	if expr is ast.Unary {
		if expr.op != '-' && expr.op != '+' {
			return none
		}
		negated = expr.op == '-'
		constant = expr.expr
	}
	if constant is ast.FloatLit {
		if constant.decimal_value.kind.is_decimal() && constant.typ.kind.is_decimal() {
			format := constant.typ.kind.decimal_format()
			mut bytes := decimal.encode(constant.decimal_value.value(), format)
			if negated {
				bytes[bytes.len - 1] ^= 0x80
			}
			return bytes
		}
	}
	return none
}

// DecimalStep is how an implemented routine covers a decimal step. An object
// routine writes a decimal result into an object through a destination address;
// a value routine leaves its result in the accumulator. uncovered is a step no
// routine writes, which is refused by name where it is written.
enum DecimalStep {
	uncovered
	object
	value
}

// decimal_step is the one place that answers whether an implemented decimal
// routine covers a step, and of which shape. The run-time addition and
// subtraction answer .object here, and a negation whose operand is an object
// with them, because the routine reads each operand where it lives. Negation of
// anything else - a constant, or another step - is not an object routine: it is
// a sign flip the value path writes for every operand shape, so it is reached
// there and not here. A comparison of two decimals answers .value: the routine
// orders the two objects and leaves its order code in the accumulator, which the
// call site turns into one of the six operators. A comparison whose operands are
// not both decimals is not a step this back end has, and is left uncovered so it
// stays refused. A lane that adds a routine adds its step to this one function
// and its emitter beside the others, so the step is reached instead of meeting a
// refusal written for a tree with no routine at all: the multiply and divide lane
// will answer .object here.
fn (e Emitter) decimal_step(expr ast.Expr) DecimalStep {
	match expr {
		ast.Binary {
			if e.decimal_of(expr.left) && e.decimal_of(expr.right) {
				if expr.op == '+' || expr.op == '-' {
					return .object
				}
				if expr.op in ['==', '!=', '<', '>', '<=', '>='] {
					return .value
				}
			}
		}
		ast.Unary {
			if expr.op == '-' && e.decimal_of(expr.expr) && e.names_an_object(expr.expr) {
				return .object
			}
		}
		else {}
	}
	return .uncovered
}

// store_decimal writes a decimal object's value from the initializer of a
// declaration or the value of an assignment to a name. A constant goes in as the
// bytes the encoding gives it; a step decimal_step answers .object for is written
// by the arithmetic routine, which reads its operands where they live;
// everything else is a value of the same decimal type, which the value path reads
// into the floating accumulator and stores, and refuses by name what it cannot
// write. depth is the level the caller writes at, which the value path turns into
// the level below it for the value it reads.
fn (mut e Emitter) store_decimal(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	if bytes := decimal_constant_bytes(expr) {
		if bytes.len == slot.width {
			return e.put_decimal_bytes(slot, bytes, line, col)
		}
	}
	if e.decimal_step(expr) == .object {
		if decimal_width_of(expr.typ) != slot.width {
			e.diagnostics << problem(line, col, 'unsupported: a value of ${expr.typ.describe()} is stored in an object of a different decimal width')
			return error('decimal width mismatch')
		}
		match expr {
			ast.Binary {
				return e.store_decimal_arith(slot, expr, line, col, depth)
			}
			ast.Unary {
				return e.store_decimal_negate(slot, expr.expr, line, col, depth)
			}
			else {}
		}
	}
	return e.store_decimal_value(slot, expr, line, col, depth)
}

// store_decimal_through_object writes a decimal value through an address the
// caller has already parked: what a dereference, a member or an element is
// assigned. A step decimal_step answers .object for is written by the arithmetic
// routine through the same address; every other value is the value path's store,
// which refuses by name what it cannot write.
fn (mut e Emitter) store_decimal_through_object(address Slot, expr ast.Expr, width int, line int, col int, depth int) !void {
	if e.decimal_step(expr) == .object {
		if decimal_width_of(expr.typ) != width {
			e.diagnostics << problem(line, col, 'unsupported: a value of ${expr.typ.describe()} is stored in a decimal object of a different width')
			return error('decimal store width')
		}
		match expr {
			ast.Binary {
				return e.store_decimal_arith_at(address, expr, line, col, depth)
			}
			ast.Unary {
				return e.store_decimal_negate_at(address, expr.expr, line, col, depth)
			}
			else {}
		}
	}
	return e.store_decimal_through_address(address, expr, width, line, col, depth)
}

// address_of builds the address expression the emitter reads an object through.
fn address_of(expr ast.Expr, line int, col int) ast.Unary {
	return ast.Unary{
		op:   '&'
		expr: expr
		typ:  expr.typ
		line: line
		col:  col
	}
}

// decimal_destination puts the destination object's address into the register the
// arithmetic routine reads it from. A frame slot is the frame plus its offset; an
// address a caller parked already holds the address, which is read into the
// register.
fn (mut e Emitter) decimal_destination(frame Slot, through ?Slot, into backend.Register, line int, col int) !void {
	if address := through {
		e.load_argument(address, into, e.target.word_size, line, col)!
		return
	}
	base := e.slot_base_register(frame, line, col)!
	e.append(e.target.address_of_slot(base, i32(frame.offset), into))
}

// store_decimal_arith writes a run-time sum or difference of two decimal objects
// into a frame slot. The operand addresses are computed one level below the
// destination, which is not a value slot, so nothing collides with it.
fn (mut e Emitter) store_decimal_arith(slot Slot, binary ast.Binary, line int, col int, depth int) !void {
	return e.emit_decimal_arith(slot, none, binary, line, col, depth)
}

// store_decimal_arith_at writes the same sum or difference through an address the
// caller parked at depth. The operand addresses are computed one level deeper, so
// they cannot reuse the slot the parked address lives in.
fn (mut e Emitter) store_decimal_arith_at(address Slot, binary ast.Binary, line int, col int, depth int) !void {
	return e.emit_decimal_arith(Slot{}, address, binary, line, col, depth)
}

// emit_decimal_arith writes a run-time sum or difference of two decimal objects.
// The operands are read where they live, so each has to be an object, and the
// routine is called with the destination in rdi and the two operands in rsi and
// rdx. The operand addresses are pushed while the second one is computed, then
// read back into the argument registers.
fn (mut e Emitter) emit_decimal_arith(frame Slot, through ?Slot, binary ast.Binary, line int, col int, depth int) !void {
	if !e.names_an_object(binary.left) || !e.names_an_object(binary.right) {
		e.diagnostics << problem(line, col, 'unsupported: a ${binary.typ.describe()} is added here from a value that is not an object, and the routine reads each operand where it lives')
		return error('decimal operand')
	}
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(line, col, 'internal: the target has no register a decimal operation needs')
		return error('decimal registers')
	}
	format := binary.typ.kind.decimal_format()
	name := decimal_arith_name(format, binary.op == '-')
	e.decimal_used[name] = true
	accum := e.accumulator(line, col)!
	e.emit_address(address_of(binary.left, line, col), depth + 1)!
	e.append(e.target.push_register(accum))
	e.emit_address(address_of(binary.right, line, col), depth + 1)!
	e.append(e.target.push_register(accum))
	e.decimal_destination(frame, through, registers.rdi, line, col)!
	e.append(e.target.pop_register(registers.rdx))
	e.append(e.target.pop_register(registers.rsi))
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// store_decimal_negate writes the negation of a decimal object into a frame slot.
// gcc compiles `-a` to a sign flip on the stored word, which is what the routine
// does.
fn (mut e Emitter) store_decimal_negate(slot Slot, operand ast.Expr, line int, col int, depth int) !void {
	return e.emit_decimal_negate(slot, none, operand, line, col, depth)
}

// store_decimal_negate_at writes the same negation through an address the caller
// parked at depth.
fn (mut e Emitter) store_decimal_negate_at(address Slot, operand ast.Expr, line int, col int, depth int) !void {
	return e.emit_decimal_negate(Slot{}, address, operand, line, col, depth)
}

// emit_decimal_negate writes the negation of a decimal object. On entry the
// operand's address is in rsi and the destination's in rdi.
fn (mut e Emitter) emit_decimal_negate(frame Slot, through ?Slot, operand ast.Expr, line int, col int, depth int) !void {
	if !e.names_an_object(operand) {
		e.diagnostics << problem(line, col, 'unsupported: a ${operand.typ.describe()} is negated here, and the routine reads its operand where it lives')
		return error('decimal operand')
	}
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(line, col, 'internal: the target has no register a decimal operation needs')
		return error('decimal registers')
	}
	format := operand.typ.kind.decimal_format()
	name := decimal_arith_negate_name(format)
	e.decimal_used[name] = true
	accum := e.accumulator(line, col)!
	e.emit_address(address_of(operand, line, col), depth + 1)!
	e.append(e.target.push_register(accum))
	e.decimal_destination(frame, through, registers.rdi, line, col)!
	e.append(e.target.pop_register(registers.rsi))
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// put_decimal_bytes writes the encoded bytes into the object, a word at a time,
// with a four-byte last store for the thirty-two bit format.
fn (mut e Emitter) put_decimal_bytes(slot Slot, bytes []u8, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	register := e.accumulator(line, col)!
	mut at := 0
	for at < bytes.len {
		chunk := if bytes.len - at >= 8 { 8 } else { 4 }
		mut word := u64(0)
		for i in 0 .. chunk {
			word |= u64(bytes[at + i]) << (8 * i)
		}
		e.append(e.target.move_immediate64(register, word)!)
		e.append(e.target.store_slot(base, i32(slot.offset + at), register, chunk)!)
		at += chunk
	}
}

// emit_decimal_to_double converts an object of a decimal type to a double at run
// time. The object has to be a name, a member or an element, because the routine
// reads it where it lives; anything else is refused by name. The call is left
// local, so the routine is carried only by a unit that makes the conversion.
fn (mut e Emitter) emit_decimal_to_double(expr ast.Expr, line int, col int, depth int) !void {
	if !e.names_an_object(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a ${expr.typ.describe()} is converted to double here, and only an object of one can be, because the conversion reads it where it lives')
		return error('decimal value')
	}
	e.emit_address(ast.Unary{
		op:   '&'
		expr: expr
		typ:  expr.typ
		line: line
		col:  col
	}, depth + 1)!
	name := decimal_routine_name(expr.typ.kind.decimal_format())
	e.decimal_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}
