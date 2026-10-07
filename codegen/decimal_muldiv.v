// Run-time multiplication of the decimal floating types.
//
// The reader and the type model carry `_Decimal32`, `_Decimal64` and
// `_Decimal128` as far as the value of a constant. A program that multiplies two
// of them at run time needs a routine the emitter writes, the way a conversion
// does, because no register holds a decimal value: the operands are objects in
// memory and the result is written into an object.
//
// The algorithm here is the one decimal/decimal.v's mul describes, measured
// against gcc 16.2.1 byte for byte: the exponents add, the coefficient is carried
// as decimal digits, and the rounding is round half to even with a sticky bit for
// everything shifted out. gcc reaches libgcc's __bid_* routines for the same
// operation, and its bytes are the specification this follows.
//
// A routine takes the destination's address in rdi and the two operands'
// addresses in rsi and rdx, and writes the result into the destination. The
// formats differ in their field widths and in nothing else of consequence, so
// each format gets a routine of its own assembled from the same pieces here, with
// the format's constants inlined.
module codegen

import backend
import ast
import decimal

// The scratch frame one multiplication routine opens. Everything below is an offset
// from rbp, which the routine sets to the base of the frame on entry. The
// buffers are sized for the widest format: a 34-digit product of 34-digit
// coefficients, and a remainder that never outgrows its divisor.
const md_dest = 0
const md_signa = 8
const md_expb = 16
const md_expa = 24
const md_signb = 32
const md_lena = 40
const md_lenb = 48
const md_lenq = 56
const md_f = 64
const md_sticky = 72
const md_dropped = 80
const md_special = 88
const md_ptra = 96
const md_ptrb = 104
const md_ptrq = 112
const md_sigq = 120
const md_lenr = 128
const md_ptrr = 136
const md_i = 144
const md_count = 152
const md_bufa = 176
const md_bufb = 224
const md_bufq = 272
const md_bufr = 368
const md_accs = 560
const md_frame = 896

// MulDivFormat is one decimal format's constants in the form the emitted code
// wants them: the field widths, the bias, and the range the exponent field and
// the coefficient hold.
struct MulDivFormat {
	bytes   int
	digits  int
	cbits   int
	ebits   int
	bias    int
	maxb    int
	emax    int
	total   int
	lowbits int
}

fn muldiv_format(format decimal.Format) MulDivFormat {
	return match format {
		.decimal32 {
			MulDivFormat{
				bytes:   4
				digits:  7
				cbits:   23
				ebits:   8
				bias:    101
				maxb:    191
				emax:    96
				total:   32
				lowbits: 21
			}
		}
		.decimal64 {
			MulDivFormat{
				bytes:   8
				digits:  16
				cbits:   53
				ebits:   10
				bias:    398
				maxb:    767
				emax:    384
				total:   64
				lowbits: 51
			}
		}
		.decimal128 {
			MulDivFormat{
				bytes:   16
				digits:  34
				cbits:   113
				ebits:   14
				bias:    6176
				maxb:    12287
				emax:    6144
				total:   128
				lowbits: 111
			}
		}
	}
}

// decimal_muldiv_name is the label one format and operator enters.
fn decimal_muldiv_name(format decimal.Format) string {
	return 'vcc_decimal_mul_${format.bytes()}'
}

// decimal_muldiv_of says whether an expression is a decimal multiply
// whose two operands are objects this back end can take the address of, and
// whose operands and result are plain locals. Anything else is refused by name
// where the initialiser is stored.
fn (e Emitter) decimal_muldiv_of(expr ast.Expr) bool {
	if expr is ast.Binary {
		if expr.op != '*' {
			return false
		}
		if !expr.typ.kind.is_decimal() {
			return false
		}
		if !e.names_an_object(expr.left) || !e.names_an_object(expr.right) {
			return false
		}
		if !expr.left.typ.kind.is_decimal() || !expr.right.typ.kind.is_decimal() {
			return false
		}
		return e.decimal_operand_reachable(expr.left) && e.decimal_operand_reachable(expr.right)
	}
	return false
}

// decimal_operand_reachable says whether an operand's address can be worked out
// without reaching through a static chain, which the parked addresses of the
// routine's arguments cannot survive. A name of the running function is fine; a
// name an enclosing function owns is not.
fn (e Emitter) decimal_operand_reachable(expr ast.Expr) bool {
	if expr is ast.Ident {
		if slot := e.lookup(expr.name) {
			return !slot.captured
		}
	}
	return true
}

// emit_decimal_muldiv writes a product at run time. The expression is a
// multiply of two decimal objects; the routine the format and
// the operator name takes the destination's address in rdi and the two operands'
// addresses in rsi and rdx, and writes the result into the destination, leaving
// its address in the accumulator the way a value of the expression would.
fn (mut e Emitter) emit_decimal_muldiv(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	binary := expr as ast.Binary
	format := expr.typ.kind.decimal_format()
	name := decimal_muldiv_name(format)
	e.decimal_used[name] = true
	// The left operand's address waits in a value slot while the right is
	// reached, since reaching the right can use the registers.
	e.emit_address(ast.Unary{
		op:   '&'
		expr: binary.left
		typ:  binary.left.typ
		line: line
		col:  col
	}, depth + 1)!
	parked := e.value_slot(depth)
	e.store_accumulator(parked, line, col)!
	e.emit_address(ast.Unary{
		op:   '&'
		expr: binary.right
		typ:  binary.right.typ
		line: line
		col:  col
	}, depth + 1)!
	accumulator := e.accumulator(line, col)!
	right := e.target.reg('rdx') or {
		e.diagnostics << problem(line, col, 'internal: no register named rdx for a decimal operation')
		return error('no rdx')
	}
	e.append(e.target.move_register64(right, accumulator)!)
	e.load_accumulator(parked, line, col)!
	left := e.target.reg('rsi') or {
		e.diagnostics << problem(line, col, 'internal: no register named rsi for a decimal operation')
		return error('no rsi')
	}
	e.append(e.target.move_register64(left, accumulator)!)
	dest := e.target.reg('rdi') or {
		e.diagnostics << problem(line, col, 'internal: no register named rdi for a decimal operation')
		return error('no rdi')
	}
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.address_of_slot(base, slot.offset, dest))
	e.reference(e.target.call_near(0), .call_local, name, '')
	e.append(e.target.move_register64(accumulator, dest)!)
}

// emit_decimal_muldiv_routines writes the routines a unit used, and no others.
fn (mut e Emitter) emit_decimal_muldiv_routines() !void {
	for format in [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128] {
		name := decimal_muldiv_name(format)
		if name in e.decimal_used {
			e.emit_decimal_muldiv_routine(format)!
		}
	}
}

// emit_decimal_muldiv_routine assembles and appends one operation's routine.
fn (mut e Emitter) emit_decimal_muldiv_routine(format decimal.Format) !void {
	f := muldiv_format(format)
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(1, 1, 'internal: the target has no register a decimal operation needs')
		return error('decimal registers')
	}
	mut r := DecimalRoutine{
		t:      &e.target
		reg:    registers
		labels: map[string]int{}
	}
	g := registers
	frame := e.target.reg('rbp') or {
		e.diagnostics << problem(1, 1, 'internal: no register named rbp for the decimal operation frame')
		return error('no rbp')
	}
	stack := e.target.reg('rsp') or {
		e.diagnostics << problem(1, 1, 'internal: no register named rsp for the decimal operation frame')
		return error('no rsp')
	}
	name := decimal_muldiv_name(format)
	r.place(name)
	// The frame: the callee-saved registers the routine works in, and the
	// scratch below them.
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(frame))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	r.op(r.t.frame_reserve(md_frame))
	// The frame's base sits under the reserved scratch, so the scratch cannot
	// tread on the registers that were pushed.
	r.op(r.t.move_register64(frame, stack)!)
	r.op(r.t.move_register64(g.r12, g.rdi)!) // destination address
	r.op(r.t.move_register64(g.rbx, g.rsi)!) // first operand's address
	r.op(r.t.move_register64(g.r15, g.rdx)!) // second operand's address
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(frame, md_lenq, g.rax, 8)!)
	r.op(r.t.store_slot(frame, md_sticky, g.rax, 8)!)
	// Decode the two operands into a coefficient, an exponent, a sign and a
	// special marker, then the coefficients into digits.
	muldiv_decode(mut r, f, g.rbx, md_signa, md_expa, 'da')!
	// The special marker of the first operand waits in md_special while the
	// second is decoded, which overwrites it; park it while the second is read.
	// The coefficient decoded out of the first operand is still in rax and rdx,
	// and to_digits reads it next, so the parking uses a register of its own.
	r.op(r.t.load_slot(frame, md_special, g.r11, 8)!)
	r.op(r.t.store_slot(frame, md_sigq, g.r11, 8)!)
	muldiv_to_digits(mut r, f, g, md_lena, md_ptra, md_bufa, 'ta')!
	muldiv_decode(mut r, f, g.r15, md_signb, md_expb, 'db')!
	muldiv_to_digits(mut r, f, g, md_lenb, md_ptrb, md_bufb, 'tb')!
	// A special operand decides the whole result: no coefficient arithmetic is
	// right for it, and the answers are the specification's own.
	muldiv_specials(mut r, f, 'sp_skip')!
	muldiv_multiply(mut r, g)!
	muldiv_combine_exponents(mut r, g)!
	r.place('sp_skip')
	// Round to the format's precision, ties to even, and put the result into the
	// format's range.
	muldiv_round(mut r, g, f)!
	muldiv_apply_dropped(mut r, g)!
	muldiv_finish(mut r, g, f)!
	muldiv_encode(mut r, g, f)!
	r.op(r.t.stack_release(md_frame))
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(frame))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
	at := e.program.text.len
	bytes := r.resolved()
	e.program.text << bytes
	e.program.labels[name] = at
}

// muldiv_decode reads one operand's word or two words, takes the sign off, biases
// the exponent out and leaves the coefficient in rax, with the high half in rdx
// for the 128-bit format. A special encoding leaves a marker in md_special and a
// zero coefficient; the marker is 1 for an infinity and 2 for a NaN.
fn muldiv_decode(mut r DecimalRoutine, f MulDivFormat, addr backend.Register, sign_off int, exp_off int, tag string) !void {
	base := muldiv_base(r)!
	g := r.reg
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.op(r.t.store_slot(base, i32(md_special), g.r8, 8)!)
	match f.bytes {
		4 {
			r.op(r.t.load_indirect(addr, g.rsi, 4)!)
			r.op(r.t.move_register64(g.r8, g.rsi)!)
			r.op(r.t.shift_right_word(g.r8, 31)!)
			r.op(r.t.store_slot(base, i32(sign_off), g.r8, 8)!)
			r.op(r.t.move_register64(g.r9, g.rsi)!)
			r.op(r.t.shift_right_word(g.r9, 26)!)
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			muldiv_special_check(mut r, g, tag)!
			r.op(r.t.move_register64(g.r9, g.rsi)!)
			r.op(r.t.shift_right_word(g.r9, 29)!)
			r.op(r.t.and_immediate(g.r9, 3)!)
			r.op(r.t.move_register64(g.r10, g.r9)!)
			r.op(r.t.add_immediate(g.r10, -3))
			r.branch(.equal, '${tag}_large')
			r.op(r.t.move_register64(g.rax, g.rsi)!)
			r.op(r.t.and_immediate(g.rax, 0x7fffff)!)
			r.op(r.t.move_register64(g.rcx, g.rsi)!)
			r.op(r.t.shift_right_word(g.rcx, 23)!)
			r.op(r.t.and_immediate(g.rcx, 0xff)!)
			r.op(r.t.add_immediate(g.rcx, -101))
			r.op(r.t.store_slot(base, i32(exp_off), g.rcx, 8)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.op(r.t.move_register64(g.rax, g.rsi)!)
			r.op(r.t.and_immediate(g.rax, 0x1fffff)!)
			r.op(r.t.move_immediate64(g.rcx, 0x800000)!)
			r.op(r.t.or_word(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rsi)!)
			r.op(r.t.shift_right_word(g.rcx, 21)!)
			r.op(r.t.and_immediate(g.rcx, 0xff)!)
			r.op(r.t.add_immediate(g.rcx, -101))
			r.op(r.t.store_slot(base, i32(exp_off), g.rcx, 8)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.jump('${tag}_done')
			muldiv_special_leaves(mut r, g, tag)!
			r.place('${tag}_done')
		}
		8 {
			r.op(r.t.load_indirect(addr, g.rsi, 8)!)
			r.op(r.t.move_register64(g.r8, g.rsi)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.store_slot(base, i32(sign_off), g.r8, 8)!)
			r.op(r.t.move_register64(g.r9, g.rsi)!)
			r.op(r.t.shift_right_word(g.r9, 58)!)
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			muldiv_special_check(mut r, g, tag)!
			r.op(r.t.move_register64(g.r9, g.rsi)!)
			r.op(r.t.shift_right_word(g.r9, 61)!)
			r.op(r.t.and_immediate(g.r9, 3)!)
			r.op(r.t.move_register64(g.r10, g.r9)!)
			r.op(r.t.add_immediate(g.r10, -3))
			r.branch(.equal, '${tag}_large')
			r.op(r.t.move_register64(g.rax, g.rsi)!)
			r.op(r.t.move_immediate64(g.rcx, 0x1fffffffffffff)!)
			r.op(r.t.and_word(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rsi)!)
			r.op(r.t.shift_right_word(g.rcx, 53)!)
			r.op(r.t.move_immediate64(g.rdx, 0x3ff)!)
			r.op(r.t.and_word(g.rcx, g.rdx)!)
			r.op(r.t.add_immediate(g.rcx, -398))
			r.op(r.t.store_slot(base, i32(exp_off), g.rcx, 8)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.op(r.t.move_register64(g.rax, g.rsi)!)
			r.op(r.t.move_immediate64(g.rcx, 0x7ffffffffffff)!)
			r.op(r.t.and_word(g.rax, g.rcx)!)
			r.op(r.t.move_immediate64(g.rcx, 0x20000000000000)!)
			r.op(r.t.or_word(g.rax, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.rsi)!)
			r.op(r.t.shift_right_word(g.rcx, 51)!)
			r.op(r.t.move_immediate64(g.rdx, 0x3ff)!)
			r.op(r.t.and_word(g.rcx, g.rdx)!)
			r.op(r.t.add_immediate(g.rcx, -398))
			r.op(r.t.store_slot(base, i32(exp_off), g.rcx, 8)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.jump('${tag}_done')
			muldiv_special_leaves(mut r, g, tag)!
			r.place('${tag}_done')
		}
		else {
			r.op(r.t.load_indirect(addr, g.rax, 8)!)
			r.op(r.t.load_slot(addr, 8, g.rdx, 8)!)
			r.op(r.t.move_register64(g.r8, g.rdx)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.store_slot(base, i32(sign_off), g.r8, 8)!)
			r.op(r.t.move_register64(g.r9, g.rdx)!)
			r.op(r.t.shift_right_word(g.r9, 58)!)
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			muldiv_special_check(mut r, g, tag)!
			r.op(r.t.move_register64(g.r9, g.rdx)!)
			r.op(r.t.shift_right_word(g.r9, 61)!)
			r.op(r.t.and_immediate(g.r9, 3)!)
			r.op(r.t.move_register64(g.r10, g.r9)!)
			r.op(r.t.add_immediate(g.r10, -3))
			r.branch(.equal, '${tag}_large')
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.move_immediate64(g.r11, 0x1ffffffffffff)!)
			r.op(r.t.and_word(g.rcx, g.r11)!)
			r.op(r.t.move_register64(g.r9, g.rdx)!)
			r.op(r.t.shift_right_word(g.r9, 49)!)
			r.op(r.t.move_immediate64(g.r11, 0x3fff)!)
			r.op(r.t.and_word(g.r9, g.r11)!)
			r.op(r.t.add_immediate(g.r9, -6176))
			r.op(r.t.store_slot(base, i32(exp_off), g.r9, 8)!)
			r.op(r.t.move_register64(g.rdx, g.rcx)!)
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.move_immediate64(g.r11, 0x7fffffffffff)!)
			r.op(r.t.and_word(g.rcx, g.r11)!)
			r.op(r.t.move_immediate64(g.r11, 0x2000000000000)!)
			r.op(r.t.or_word(g.rcx, g.r11)!)
			r.op(r.t.move_register64(g.r9, g.rdx)!)
			r.op(r.t.shift_right_word(g.r9, 47)!)
			r.op(r.t.move_immediate64(g.r11, 0x3fff)!)
			r.op(r.t.and_word(g.r9, g.r11)!)
			r.op(r.t.add_immediate(g.r9, -6176))
			r.op(r.t.store_slot(base, i32(exp_off), g.r9, 8)!)
			r.op(r.t.move_register64(g.rdx, g.rcx)!)
			r.jump('${tag}_done')
			muldiv_special_leaves(mut r, g, tag)!
			r.place('${tag}_done')
		}
	}
}

// muldiv_special_check branches away when the five bits below the sign are an
// infinity or a NaN marker. r9 holds those five bits.
fn muldiv_special_check(mut r DecimalRoutine, g DecimalRegisters, tag string) !void {
	r.op(r.t.move_register64(g.r10, g.r9)!)
	r.op(r.t.add_immediate(g.r10, -30))
	r.branch(.equal, '${tag}_inf')
	r.op(r.t.move_register64(g.r10, g.r9)!)
	r.op(r.t.add_immediate(g.r10, -31))
	r.branch(.equal, '${tag}_nan')
}

// muldiv_special_leaves writes the three leaves of a decode: the marker and the
// zero coefficient a special operand contributes, for an infinity and a NaN.
fn muldiv_special_leaves(mut r DecimalRoutine, g DecimalRegisters, tag string) !void {
	base := muldiv_base(r)!
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.store_slot(base, i32(md_special), g.r10, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.jump('${tag}_done')
	r.place('${tag}_inf')
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.store_slot(base, i32(md_special), g.r10, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.jump('${tag}_done')
	r.place('${tag}_nan')
	r.op(r.t.move_immediate64(g.r10, 2)!)
	r.op(r.t.store_slot(base, i32(md_special), g.r10, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.jump('${tag}_done')
}

// muldiv_to_digits turns the coefficient in rax (with its high half in rdx) into
// decimal digits, most significant first, ending at buf_end. It leaves the
// pointer to the first digit in ptr_off and the count in len_off; a zero
// coefficient leaves a count of zero.
fn muldiv_to_digits(mut r DecimalRoutine, f MulDivFormat, g DecimalRegisters, len_off int, ptr_off int, buf_end int, tag string) !void {
	base := muldiv_base(r)!
	r.op(r.t.move_register64(g.rdi, base)!)
	r.op(r.t.add_immediate(g.rdi, buf_end))
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.op(r.t.move_immediate64(g.r9, 10)!)
	r.place('${tag}_loop')
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.or_word(g.r10, g.rdx)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, '${tag}_done')
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.rdx)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.divide_pair(g.r9)!)
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.divide_pair(g.r9)!)
	r.op(r.t.add_immediate(g.rdi, -1))
	r.op(r.t.store_indirect(g.rdi, g.rdx, 1)!)
	r.op(r.t.add_immediate(g.r8, 1))
	r.op(r.t.move_register64(g.rdx, g.r10)!)
	r.jump('${tag}_loop')
	r.place('${tag}_done')
	r.op(r.t.store_slot(base, i32(ptr_off), g.rdi, 8)!)
	r.op(r.t.store_slot(base, i32(len_off), g.r8, 8)!)
}

// muldiv_strip removes leading zero digits from a digit string whose buffer, in
// rbp-relative terms, starts at buf_off, and writes the pointer and the length.
fn muldiv_strip(mut r DecimalRoutine, g DecimalRegisters, ptr_off int, len_off int, tag string) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, i32(len_off), g.rcx, 8)!)
	r.op(r.t.load_slot(base, i32(ptr_off), g.rsi, 8)!)
	r.place('${tag}_st_loop')
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, '${tag}_st_done')
	r.op(r.t.load_indirect_unsigned(g.rsi, g.rax, 1)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${tag}_st_done')
	r.op(r.t.add_immediate(g.rsi, 1))
	r.op(r.t.add_immediate(g.rcx, -1))
	r.jump('${tag}_st_loop')
	r.place('${tag}_st_done')
	r.op(r.t.store_slot(base, i32(ptr_off), g.rsi, 8)!)
	r.op(r.t.store_slot(base, i32(len_off), g.rcx, 8)!)
}

// muldiv_multiply multiplies the two digit strings and leaves the exact product
// in md_bufq, with its length in md_lenq.
fn muldiv_multiply(mut r DecimalRoutine, g DecimalRegisters) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_lena, g.r10, 8)!)
	r.op(r.t.load_slot(base, md_lenb, g.r11, 8)!)
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.or_word(g.rax, g.r11)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'mp_zero')
	// The accumulator is one 32-bit entry per position: lenA + lenB digits.
	r.op(r.t.move_register64(g.rcx, g.r10)!)
	r.op(r.t.add_reg64(g.rcx, g.r11))
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.place('mp_zloop')
	r.op(r.t.move_register64(g.rax, g.r8)!)
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.greater_or_equal, 'mp_zdone')
	r.op(r.t.address_of_element(base, g.r8, 4, md_accs, g.rdi)!)
	r.op(r.t.move_immediate32(g.rdx, 0)!)
	r.op(r.t.store_indirect(g.rdi, g.rdx, 4)!)
	r.op(r.t.add_immediate(g.r8, 1))
	r.jump('mp_zloop')
	r.place('mp_zdone')
	r.op(r.t.load_slot(base, md_ptra, g.rbx, 8)!)
	r.op(r.t.load_slot(base, md_ptrb, g.r15, 8)!)
	r.op(r.t.move_register64(g.r8, g.r10)!)
	r.op(r.t.add_immediate(g.r8, -1))
	r.place('mp_iloop')
	r.op(r.t.move_register64(g.rax, g.r8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.less, 'mp_idone')
	r.op(r.t.address_of_element(g.rbx, g.r8, 1, 0, g.rdi)!)
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rax, 1)!)
	r.op(r.t.move_register64(g.r9, g.r11)!)
	r.op(r.t.add_immediate(g.r9, -1))
	r.place('mp_jloop')
	r.op(r.t.move_register64(g.rdx, g.r9)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.less, 'mp_jdone')
	r.op(r.t.address_of_element(g.r15, g.r9, 1, 0, g.rdi)!)
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rdx, 1)!)
	r.op(r.t.multiply(g.rax, g.rdx)!)
	r.op(r.t.move_register64(g.rcx, g.r8)!)
	r.op(r.t.add_reg64(g.rcx, g.r9))
	r.op(r.t.add_immediate(g.rcx, 1))
	r.op(r.t.address_of_element(base, g.rcx, 4, md_accs, g.rdi)!)
	r.op(r.t.load_indirect(g.rdi, g.rsi, 4)!)
	r.op(r.t.add(g.rsi, g.rax)!)
	r.op(r.t.store_indirect(g.rdi, g.rsi, 4)!)
	// The multiply spent rax, so the digit of A is reloaded for the next pass.
	r.op(r.t.address_of_element(g.rbx, g.r8, 1, 0, g.rdi)!)
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rax, 1)!)
	r.op(r.t.add_immediate(g.r9, -1))
	r.jump('mp_jloop')
	r.place('mp_jdone')
	r.op(r.t.add_immediate(g.r8, -1))
	r.jump('mp_iloop')
	r.place('mp_idone')
	// Carry the accumulators down into single digits.
	r.op(r.t.move_register64(g.rcx, g.r10)!)
	r.op(r.t.add_reg64(g.rcx, g.r11))
	r.op(r.t.add_immediate(g.rcx, -1))
	r.place('mp_nloop')
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.less_or_equal, 'mp_ndone')
	r.op(r.t.address_of_element(base, g.rcx, 4, md_accs, g.rdi)!)
	r.op(r.t.load_indirect(g.rdi, g.rax, 4)!)
	r.op(r.t.move_immediate64(g.rsi, 10)!)
	r.op(r.t.divide_unsigned(g.rsi)!) // eax = quotient, edx = remainder
	r.op(r.t.store_indirect(g.rdi, g.rdx, 4)!)
	r.op(r.t.move_register64(g.rsi, g.rcx)!)
	r.op(r.t.add_immediate(g.rsi, -1))
	r.op(r.t.address_of_element(base, g.rsi, 4, md_accs, g.rdi)!)
	r.op(r.t.load_indirect(g.rdi, g.rsi, 4)!)
	r.op(r.t.add(g.rsi, g.rax)!)
	r.op(r.t.store_indirect(g.rdi, g.rsi, 4)!)
	r.op(r.t.add_immediate(g.rcx, -1))
	r.jump('mp_nloop')
	r.place('mp_ndone')
	// The digits go into the buffer, and the leading zeros come off.
	r.op(r.t.move_register64(g.rsi, base)!)
	r.op(r.t.add_immediate(g.rsi, md_bufq))
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.op(r.t.move_register64(g.r9, g.r10)!)
	r.op(r.t.add_reg64(g.r9, g.r11))
	r.place('mp_wloop')
	r.op(r.t.move_register64(g.rax, g.r8)!)
	r.op(r.t.subtract_word(g.rax, g.r9)!)
	r.branch(.greater_or_equal, 'mp_wdone')
	r.op(r.t.address_of_element(base, g.r8, 4, md_accs, g.rdi)!)
	r.op(r.t.load_indirect(g.rdi, g.rax, 4)!)
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_reg64(g.rdi, g.r8))
	r.op(r.t.store_indirect(g.rdi, g.rax, 1)!)
	r.op(r.t.add_immediate(g.r8, 1))
	r.jump('mp_wloop')
	r.place('mp_wdone')
	r.op(r.t.store_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.store_slot(base, md_lenq, g.r9, 8)!)
	muldiv_strip(mut r, g, md_ptrq, md_lenq, 'mq')!
	r.jump('mp_end')
	r.place('mp_zero')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.op(r.t.move_register64(g.rax, base)!)
	r.op(r.t.add_immediate(g.rax, md_bufq))
	r.op(r.t.store_slot(base, md_ptrq, g.rax, 8)!)
	r.place('mp_end')
}

// muldiv_combine_exponents adds the two exponents for a product, and takes the
// sign of the result from the two signs.
fn muldiv_combine_exponents(mut r DecimalRoutine, g DecimalRegisters) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_expb, g.rcx, 8)!)
	r.op(r.t.add_reg64(g.rax, g.rcx))
	r.op(r.t.store_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_signa, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_signb, g.rcx, 8)!)
	r.op(r.t.xor_word(g.rax, g.rcx)!)
	r.op(r.t.store_slot(base, md_signa, g.rax, 8)!)
}

// muldiv_apply_dropped moves the exponent up by the digits the rounding
// dropped.
fn muldiv_apply_dropped(mut r DecimalRoutine, g DecimalRegisters) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_dropped, g.rcx, 8)!)
	r.op(r.t.add_reg64(g.rax, g.rcx))
	r.op(r.t.store_slot(base, md_expa, g.rax, 8)!)
}

// muldiv_specials answers a product with a special operand, and leaves the
// result's marker and exponent in place for the encode, jumping past the digits.
fn muldiv_specials(mut r DecimalRoutine, f MulDivFormat, skip string) !void {
	g := r.reg
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_sigq, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_special, g.rcx, 8)!)
	r.op(r.t.move_register64(g.rdx, g.rax)!)
	r.op(r.t.or_word(g.rdx, g.rcx)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'sp_none')
	// The sign of the result is the exclusive or of the two signs.
	r.op(r.t.load_slot(base, md_signa, g.rax, 8)!)
	r.op(r.t.load_slot(base, md_signb, g.rdx, 8)!)
	r.op(r.t.xor_word(g.rax, g.rdx)!)
	r.op(r.t.store_slot(base, md_signa, g.rax, 8)!)
	// A NaN operand makes a NaN.
	r.op(r.t.load_slot(base, md_sigq, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.equal, 'sp_nan')
	r.op(r.t.load_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.equal, 'sp_nan')
	// A finite zero times an infinity is a NaN; any other infinity is one.
	r.op(r.t.load_slot(base, md_sigq, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, -1))
	r.branch(.not_equal, 'sp_check_a')
	r.op(r.t.load_slot(base, md_lenb, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'sp_nan')
	r.jump('sp_inf')
	r.place('sp_check_a')
	r.op(r.t.load_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, -1))
	r.branch(.not_equal, 'sp_none')
	r.op(r.t.load_slot(base, md_lena, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'sp_nan')
	r.jump('sp_inf')
	r.place('sp_nan')
	r.op(r.t.move_immediate64(g.rax, 2)!)
	r.op(r.t.store_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump(skip)
	r.place('sp_inf')
	r.op(r.t.move_immediate64(g.rax, 1)!)
	r.op(r.t.store_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump(skip)
	r.place('sp_none')
}

// muldiv_round rounds the digit string in md_bufq to the format's precision,
// ties to even, with md_sticky saying whether anything was dropped before the
// string was built. It leaves the count of dropped digits in md_dropped.
fn muldiv_round(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_lenq, g.rcx, 8)!)
	r.op(r.t.move_immediate64(g.rax, u64(f.digits))!)
	r.op(r.t.subtract_word(g.rcx, g.rax)!)
	r.branch(.less_or_equal, 'rd_none')
	r.op(r.t.store_slot(base, md_dropped, g.rcx, 8)!)
	r.op(r.t.load_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_immediate(g.rdi, f.digits))
	r.op(r.t.load_indirect_unsigned(g.rdi, g.r11, 1)!)
	// rest = sticky, or any nonzero digit after the first dropped one
	r.op(r.t.load_slot(base, md_sticky, g.r8, 8)!)
	r.op(r.t.add_immediate(g.rdi, 1))
	r.op(r.t.move_immediate64(g.r10, u64(f.digits + 1))!)
	r.place('rd_restloop')
	// r10 is the index, rdx the length, and both are remade each pass.
	r.op(r.t.move_register64(g.rdx, g.rcx)!)
	r.op(r.t.add_immediate(g.rdx, f.digits))
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.subtract_word(g.rax, g.rdx)!)
	r.branch(.greater_or_equal, 'rd_restdone')
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rdx, 1)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'rd_restnext')
	r.op(r.t.move_immediate64(g.r8, 1)!)
	r.place('rd_restnext')
	r.op(r.t.add_immediate(g.rdi, 1))
	r.op(r.t.add_immediate(g.r10, 1))
	r.jump('rd_restloop')
	r.place('rd_restdone')
	// up = first > 5, or first == 5 with something below it or an odd last digit
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.add_immediate(g.rax, -5))
	r.branch(.greater, 'rd_up')
	r.branch(.less, 'rd_kept')
	r.op(r.t.test_word(g.r8)!)
	r.branch(.not_equal, 'rd_up')
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_immediate(g.rdi, f.digits - 1))
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rax, 1)!)
	r.op(r.t.and_immediate(g.rax, 1)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'rd_up')
	r.jump('rd_kept')
	r.place('rd_up')
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_immediate(g.rdi, f.digits - 1))
	r.op(r.t.move_immediate64(g.r9, u64(f.digits))!)
	r.place('rd_carryloop')
	r.op(r.t.move_register64(g.rax, g.r9)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'rd_carryout')
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rax, 1)!)
	r.op(r.t.add_immediate(g.rax, 1))
	r.op(r.t.move_register64(g.rdx, g.rax)!)
	r.op(r.t.add_immediate(g.rdx, -10))
	r.branch(.equal, 'rd_carryten')
	r.op(r.t.store_indirect(g.rdi, g.rax, 1)!)
	r.jump('rd_kept')
	r.place('rd_carryten')
	r.op(r.t.move_immediate64(g.rax, 0)!)
	r.op(r.t.store_indirect(g.rdi, g.rax, 1)!)
	r.op(r.t.add_immediate(g.rdi, -1))
	r.op(r.t.add_immediate(g.r9, -1))
	r.jump('rd_carryloop')
	r.place('rd_carryout')
	r.op(r.t.move_immediate64(g.rax, 1)!)
	r.op(r.t.store_indirect(g.rsi, g.rax, 1)!)
	r.op(r.t.load_slot(base, md_dropped, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, 1))
	r.op(r.t.store_slot(base, md_dropped, g.rax, 8)!)
	r.place('rd_kept')
	r.op(r.t.move_immediate64(g.rax, u64(f.digits))!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump('rd_end')
	r.place('rd_none')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_dropped, g.rax, 8)!)
	r.place('rd_end')
}

// muldiv_finish puts the rounded result into the format's range: a result past
// the largest becomes an infinity, and one below the smallest subnormal rounds
// into the subnormal range or to zero.
fn muldiv_finish(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_lenq, g.rcx, 8)!)
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.equal, 'fi_end')
	// adjusted exponent = exp + len - 1
	r.op(r.t.load_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.add_reg64(g.rax, g.rcx))
	r.op(r.t.add_immediate(g.rax, -1))
	r.op(r.t.move_immediate64(g.rdx, u64(f.emax))!)
	r.op(r.t.subtract_word(g.rax, g.rdx)!)
	r.branch(.greater, 'fi_overflow')
	// exp + bias >= 0 is the normal range
	r.op(r.t.load_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rdx, u64(f.bias))!)
	r.op(r.t.add_reg64(g.rax, g.rdx))
	r.op(r.t.test_word(g.rax)!)
	r.branch(.greater_or_equal, 'fi_end')
	// Below the normal range: drop = -(exp + bias)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.subtract_word(g.rdx, g.rax)!)
	// rax = len - drop
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.op(r.t.subtract_word(g.rax, g.rdx)!)
	r.branch(.less, 'fi_allbelow')
	r.branch(.equal, 'fi_exactdrop')
	// kept_len = len - drop, in rax; first = ptr[kept_len]
	r.op(r.t.load_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.address_of_element(g.rsi, g.rax, 1, 0, g.rdi)!)
	r.op(r.t.load_indirect_unsigned(g.rdi, g.r11, 1)!)
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.op(r.t.add_immediate(g.rdi, 1))
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.place('fi_restloop')
	// The comparison is remade each pass: r10 is the index and rcx the length.
	r.op(r.t.move_register64(g.r9, g.r10)!)
	r.op(r.t.subtract_word(g.r9, g.rcx)!)
	r.branch(.greater_or_equal, 'fi_restdone')
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rdx, 1)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'fi_restnext')
	r.op(r.t.move_immediate64(g.r8, 1)!)
	r.place('fi_restnext')
	r.op(r.t.add_immediate(g.rdi, 1))
	r.op(r.t.add_immediate(g.r10, 1))
	r.jump('fi_restloop')
	r.place('fi_restdone')
	r.op(r.t.move_register64(g.rdx, g.r11)!)
	r.op(r.t.add_immediate(g.rdx, -5))
	r.branch(.greater, 'fi_doup')
	r.branch(.less, 'fi_setlen')
	r.op(r.t.test_word(g.r8)!)
	r.branch(.not_equal, 'fi_doup')
	// first == 5 and nothing below: round to even on the last kept digit
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_immediate(g.rdi, -1))
	r.op(r.t.add_reg64(g.rdi, g.rax))
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rdx, 1)!)
	r.op(r.t.and_immediate(g.rdx, 1)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'fi_doup')
	r.jump('fi_setlen')
	r.place('fi_doup')
	r.op(r.t.move_register64(g.rdi, g.rsi)!)
	r.op(r.t.add_immediate(g.rdi, -1))
	r.op(r.t.add_reg64(g.rdi, g.rax))
	r.op(r.t.move_register64(g.r9, g.rax)!)
	r.place('fi_carryloop')
	r.op(r.t.test_word(g.r9)!)
	r.branch(.equal, 'fi_carryout')
	r.op(r.t.load_indirect_unsigned(g.rdi, g.rdx, 1)!)
	r.op(r.t.add_immediate(g.rdx, 1))
	r.op(r.t.move_register64(g.r11, g.rdx)!)
	r.op(r.t.add_immediate(g.r11, -10))
	r.branch(.equal, 'fi_carryten')
	r.op(r.t.store_indirect(g.rdi, g.rdx, 1)!)
	r.jump('fi_setlen')
	r.place('fi_carryten')
	r.op(r.t.move_immediate64(g.rdx, 0)!)
	r.op(r.t.store_indirect(g.rdi, g.rdx, 1)!)
	r.op(r.t.add_immediate(g.rdi, -1))
	r.op(r.t.add_immediate(g.r9, -1))
	r.jump('fi_carryloop')
	r.place('fi_carryout')
	r.op(r.t.move_immediate64(g.rdx, 1)!)
	r.op(r.t.store_indirect(g.rdi, g.rdx, 1)!)
	r.op(r.t.add_immediate(g.rax, 1))
	r.place('fi_setlen')
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump('fi_setexp')
	r.place('fi_exactdrop')
	// drop == len: the whole coefficient is dropped, the first digit decides
	r.op(r.t.load_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.load_indirect_unsigned(g.rsi, g.r11, 1)!)
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.add_immediate(g.rsi, 1))
	r.place('fi_one_restloop')
	r.op(r.t.add_immediate(g.r10, -1))
	r.branch(.equal, 'fi_one_restdone')
	r.op(r.t.load_indirect_unsigned(g.rsi, g.rdx, 1)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'fi_one_restnext')
	r.op(r.t.move_immediate64(g.r8, 1)!)
	r.place('fi_one_restnext')
	r.op(r.t.add_immediate(g.rsi, 1))
	r.jump('fi_one_restloop')
	r.place('fi_one_restdone')
	r.op(r.t.move_register64(g.rdx, g.r11)!)
	r.op(r.t.add_immediate(g.rdx, -5))
	r.branch(.greater, 'fi_one_up')
	r.branch(.less, 'fi_one_zero')
	r.op(r.t.test_word(g.r8)!)
	r.branch(.not_equal, 'fi_one_up')
	r.jump('fi_one_zero')
	r.place('fi_one_up')
	r.op(r.t.load_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.move_immediate64(g.rax, 1)!)
	r.op(r.t.store_indirect(g.rsi, g.rax, 1)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump('fi_setexp')
	r.place('fi_one_zero')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.jump('fi_setexp')
	r.place('fi_allbelow')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.place('fi_setexp')
	r.op(r.t.move_immediate64(g.rax, u64(f.bias))!)
	r.op(r.t.negate_word(g.rax)!)
	r.op(r.t.store_slot(base, md_expa, g.rax, 8)!)
	r.jump('fi_end')
	r.place('fi_overflow')
	r.op(r.t.move_immediate64(g.rax, 1)!)
	r.op(r.t.store_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.store_slot(base, md_lenq, g.rax, 8)!)
	r.place('fi_end')
}

// muldiv_digits_to_int reads the digit string in md_ptrq back into a coefficient
// in rax, with its high half in rdx.
fn muldiv_digits_to_int(mut r DecimalRoutine, g DecimalRegisters) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_ptrq, g.rsi, 8)!)
	r.op(r.t.load_slot(base, md_lenq, g.rcx, 8)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_immediate64(g.r9, 10)!)
	r.place('ei_loop')
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.equal, 'ei_done')
	r.op(r.t.load_indirect_unsigned(g.rsi, g.r8, 1)!)
	r.op(r.t.move_register64(g.r10, g.rdx)!)
	r.op(r.t.multiply_pair(g.r9)!)
	r.op(r.t.imul_immediate(g.r10, 10))
	r.op(r.t.add_reg64(g.rdx, g.r10))
	r.op(r.t.add_reg64(g.rax, g.r8))
	r.op(r.t.add_with_carry_immediate(g.rdx, 0)!)
	r.op(r.t.add_immediate(g.rsi, 1))
	r.op(r.t.add_immediate(g.rcx, -1))
	r.jump('ei_loop')
	r.place('ei_done')
}

// muldiv_enc_store applies the result's sign and writes the object. For the
// 128-bit format the coefficient and the exponent field are in rdx above rax;
// for the narrower ones the whole word is rdx.
fn muldiv_enc_store(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	// r12 holds the destination, and r12 needs a SIB byte to be a base with no
	// displacement, so the address moves to a register that does not.
	r.op(r.t.move_register64(g.r9, g.r12)!)
	r.op(r.t.load_slot(base, md_signa, g.r10, 8)!)
	if f.bytes == 16 {
		r.op(r.t.shift_left_word(g.r10, 63)!)
		r.op(r.t.or_word(g.rdx, g.r10)!)
		r.op(r.t.store_indirect(g.r9, g.rax, 8)!)
		r.op(r.t.store_slot(g.r9, 8, g.rdx, 8)!)
	} else {
		r.op(r.t.shift_left_word(g.r10, u8(f.total - 1))!)
		r.op(r.t.or_word(g.rdx, g.r10)!)
		r.op(r.t.store_indirect(g.r9, g.rdx, f.bytes)!)
	}
}

// muldiv_encode_finite_64 builds the coefficient and the exponent field for the
// 32- and 64-bit formats, whose coefficient fits a word.
fn muldiv_encode_finite_64(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	muldiv_digits_to_int(mut r, g)!
	r.op(r.t.load_slot(base, md_lenq, g.rcx, 8)!)
	r.op(r.t.load_slot(base, md_expa, g.r8, 8)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.bias))!)
	r.op(r.t.add_reg64(g.r8, g.r9))
	// Walk the exponent into the field's range while there is room for digits.
	r.place('ef_l1')
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.maxb))!)
	r.op(r.t.subtract_word(g.r10, g.r9)!)
	r.branch(.less_or_equal, 'ef_l1done')
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.digits))!)
	r.op(r.t.subtract_word(g.r10, g.r9)!)
	r.branch(.greater_or_equal, 'ef_l1done')
	r.op(r.t.imul_immediate(g.rax, 10))
	r.op(r.t.add_immediate(g.rcx, 1))
	r.op(r.t.add_immediate(g.r8, -1))
	r.jump('ef_l1')
	r.place('ef_l1done')
	// Take the coefficient's trailing zeros back out while the exponent is below
	// zero, which is what decimal/decimal.v's encode does.
	r.place('ef_l2')
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, 'ef_l2done')
	r.op(r.t.move_register64(g.rsi, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_immediate64(g.r9, 10)!)
	r.op(r.t.divide_pair(g.r9)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'ef_l2restore')
	r.op(r.t.add_immediate(g.r8, 1))
	r.jump('ef_l2')
	r.place('ef_l2restore')
	r.op(r.t.move_register64(g.rax, g.rsi)!)
	r.place('ef_l2done')
	// The coefficient fits the smaller field, or it does not.
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.shift_left_word(g.r10, u8(f.cbits))!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.subtract_word(g.r11, g.r10)!)
	r.branch(.below, 'ef_canon')
	r.op(r.t.move_register64(g.rdx, g.r8)!)
	r.op(r.t.shift_left_word(g.rdx, u8(f.lowbits))!)
	r.op(r.t.move_immediate64(g.r10, 3)!)
	r.op(r.t.shift_left_word(g.r10, u8(f.total - 3))!)
	r.op(r.t.or_word(g.rdx, g.r10)!)
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.shift_left_word(g.r10, u8(f.lowbits))!)
	r.op(r.t.add_immediate(g.r10, -1))
	r.op(r.t.and_word(g.r10, g.rax)!)
	r.op(r.t.or_word(g.rdx, g.r10)!)
	r.jump('ef_built')
	r.place('ef_canon')
	r.op(r.t.move_register64(g.rdx, g.r8)!)
	r.op(r.t.shift_left_word(g.rdx, u8(f.cbits))!)
	r.op(r.t.or_word(g.rdx, g.rax)!)
	r.place('ef_built')
	muldiv_enc_store(mut r, g, f)!
}

// muldiv_encode_finite_128 builds the coefficient and the exponent field for the
// 128-bit format, whose coefficient needs both words.
fn muldiv_encode_finite_128(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	muldiv_digits_to_int(mut r, g)!
	r.op(r.t.load_slot(base, md_lenq, g.rcx, 8)!)
	r.op(r.t.load_slot(base, md_expa, g.r8, 8)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.bias))!)
	r.op(r.t.add_reg64(g.r8, g.r9))
	r.place('eg_l1')
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.maxb))!)
	r.op(r.t.subtract_word(g.r10, g.r9)!)
	r.branch(.less_or_equal, 'eg_l1done')
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.move_immediate64(g.r9, u64(f.digits))!)
	r.op(r.t.subtract_word(g.r10, g.r9)!)
	r.branch(.greater_or_equal, 'eg_l1done')
	// the coefficient times ten, in both words
	r.op(r.t.move_register64(g.r10, g.rdx)!)
	r.op(r.t.move_immediate64(g.r9, 10)!)
	r.op(r.t.multiply_pair(g.r9)!)
	r.op(r.t.imul_immediate(g.r10, 10))
	r.op(r.t.add_reg64(g.rdx, g.r10))
	r.op(r.t.add_immediate(g.rcx, 1))
	r.op(r.t.add_immediate(g.r8, -1))
	r.jump('eg_l1')
	r.place('eg_l1done')
	r.place('eg_l2')
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, 'eg_l2done')
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.move_register64(g.r11, g.rdx)!)
	r.op(r.t.move_register64(g.rax, g.rdx)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_immediate64(g.r9, 10)!)
	r.op(r.t.divide_pair(g.r9)!)
	r.op(r.t.move_register64(g.rsi, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.divide_pair(g.r9)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'eg_l2restore')
	r.op(r.t.move_register64(g.rdx, g.rsi)!)
	r.op(r.t.add_immediate(g.r8, 1))
	r.jump('eg_l2')
	r.place('eg_l2restore')
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.move_register64(g.rdx, g.r11)!)
	r.place('eg_l2done')
	// The 128-bit coefficient always fits the wider field, so the exponent field
	// is the only thing left to place.
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.shift_left_word(g.r10, u8(f.cbits - 64))!)
	r.op(r.t.or_word(g.rdx, g.r10)!)
	muldiv_enc_store(mut r, g, f)!
}

// muldiv_enc_zero writes a zero with the exponent's difference, clamped into the
// exponent field's range.
fn muldiv_enc_zero(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_expa, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.r10, u64(f.bias))!)
	r.op(r.t.add_reg64(g.rax, g.r10))
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, 'ez_notbelow')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.place('ez_notbelow')
	r.op(r.t.move_immediate64(g.r10, u64(f.maxb))!)
	r.op(r.t.subtract_word(g.r10, g.rax)!)
	r.branch(.greater_or_equal, 'ez_notabove')
	r.op(r.t.move_immediate64(g.rax, u64(f.maxb))!)
	r.place('ez_notabove')
	if f.bytes == 16 {
		r.op(r.t.move_register64(g.rdx, g.rax)!)
		r.op(r.t.shift_left_word(g.rdx, u8(f.cbits - 64))!)
		r.op(r.t.xor_word(g.rax, g.rax)!)
	} else {
		r.op(r.t.move_register64(g.rdx, g.rax)!)
		r.op(r.t.shift_left_word(g.rdx, u8(f.cbits))!)
	}
	muldiv_enc_store(mut r, g, f)!
}

// muldiv_enc_special writes the infinity or NaN field pattern the specification
// gives, with the sign.
fn muldiv_enc_special(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.equal, 'es_nan')
	r.op(r.t.move_immediate64(g.rdx, 0b11110)!)
	r.jump('es_pat')
	r.place('es_nan')
	r.op(r.t.move_immediate64(g.rdx, 0b11111)!)
	r.place('es_pat')
	if f.bytes == 16 {
		r.op(r.t.shift_left_word(g.rdx, u8(f.total - 6 - 64))!)
		r.op(r.t.xor_word(g.rax, g.rax)!)
	} else {
		r.op(r.t.shift_left_word(g.rdx, u8(f.total - 6))!)
	}
	muldiv_enc_store(mut r, g, f)!
}

// muldiv_encode writes the result object. A NaN and an infinity are the field
// patterns the specification gives; a finite result is the coefficient and the
// exponent field, with the exponent walked into the field's range and the
// trailing zeros of the coefficient taken back out, exactly as decimal/decimal.v
// encodes a value.
fn muldiv_encode(mut r DecimalRoutine, g DecimalRegisters, f MulDivFormat) !void {
	base := muldiv_base(r)!
	r.op(r.t.load_slot(base, md_special, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'en_special')
	r.op(r.t.load_slot(base, md_lenq, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'en_zero')
	if f.bytes == 16 {
		muldiv_encode_finite_128(mut r, g, f)!
	} else {
		muldiv_encode_finite_64(mut r, g, f)!
	}
	r.jump('en_end')
	r.place('en_zero')
	muldiv_enc_zero(mut r, g, f)!
	r.jump('en_end')
	r.place('en_special')
	muldiv_enc_special(mut r, g, f)!
	r.place('en_end')
}

// muldiv_base is the frame the routine works in.
fn muldiv_base(r DecimalRoutine) !backend.Register {
	return r.t.reg('rbp') or { error('no rbp register') }
}
