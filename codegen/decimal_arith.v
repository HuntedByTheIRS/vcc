// Decimal floating point addition and subtraction through the emitter.
//
// An object of a decimal type is not a value a register holds: it is storage, and
// an operation on two of them is a routine that reads both where they live and
// writes its answer into a third place. This file emits that routine, and the
// call site hands it the three addresses. The arithmetic is the algorithm
// decimal/decimal.v's add and sub describe, carried out on the digits of the
// format's coefficient, because that module's arithmetic is the measured
// specification of what gcc 16.2.1 does at run time.
//
// The routine decodes each operand's BID encoding into a sign, a power of ten and
// a run of decimal digits, aligns the two to the smaller power of ten the way the
// module's align does, adds or subtracts the runs, rounds to the format's digit
// count with ties to even, and encodes the result back into BID. The result's
// exponent is the smaller of the two operands' exponents, and a result that is
// exactly zero carries that exponent too, which is what gcc's runtime routines
// do and what decimal/decimal.v's zero_at records.
//
// The one hard part is that the two exponents can be far apart: `1e6144dl` and
// `1e-6176dl` are 12320 powers of ten apart, and ten to that power has no room in
// any register. So the routine takes one of two paths, chosen at run time from
// the exponent difference d and the format's digit count p:
//
//   * d < p. Both operands have at most p digits, the aligned sum has at most 2p,
//     the whole of it fits a fixed buffer, and the arithmetic is exact.
//
//   * d >= p. The operand with the larger exponent then dominates and the two
//     never overlap: the larger's digits sit above a gap of d powers of ten and
//     the smaller's below it. Only the leading p+1 digits and a sticky bit for
//     whatever is below them can change the rounding, so the routine builds that
//     window directly and never materialises the gap.
//
// A digit run is one byte per digit, most significant first. This precision is
// not what this compiler exists to run fast; it is what it exists to get right,
// and a program that never adds two decimal objects pays for none of it, because
// the routine is emitted only when a call site names it.
module codegen

import backend
import decimal

// decimal_arith_name is the label a call site enters for one format and one of
// the two operators. The width and the operator name it, so no two collide.
fn decimal_arith_name(format decimal.Format, subtract bool) string {
	op := if subtract { 'sub' } else { 'add' }
	return 'vcc_decimal_${op}_${format.bytes()}'
}

// decimal_arith_negate_name is the label unary minus enters. It is its own
// routine because the negation is a sign flip on the encoding rather than an
// arithmetic: measured on gcc 16.2.1, `-a` on a decimal object flips the sign
// bit of the stored word and changes nothing else, at every width.
fn decimal_arith_negate_name(format decimal.Format) string {
	return 'vcc_decimal_neg_${format.bytes()}'
}

// DecArithWanted is one routine a unit asked for.
struct DecArithWanted {
	format   decimal.Format
	subtract bool
}

// DecArithFrame is the layout of an arithmetic routine's own frame: where each
// scalar and each digit buffer sits below rbp. It is computed from the format's
// digit count once, before the routine is written.
struct DecArithFrame {
mut:
	dest    int
	aptr    int
	bptr    int
	signa   int
	signb   int
	speca   int
	specb   int
	ea      int
	eb      int
	ida     int
	idb     int
	subflag int
	lsign   int
	lexp    int
	llen    int
	lptr    int
	hsign   int
	hexp    int
	hlen    int
	hptr    int
	d       int
	hilarg  int
	rlen    int
	rexp    int
	rsign   int
	sticky  int
	t0      int
	t1      int
	t2      int
	t3      int
	t4      int
	total   int
	chi     int
	clo     int
	cqh     int
	pre     string
	da      int
	db      int
	ba      int
	bb      int
	br      int
	wb      int
	rb      int
	size    int
}

// dec_arith_frame lays the routine's frame out below rbp. Every scalar is one
// word; the digit buffers are as wide as the path that fills them: the decode
// buffers hold one operand's p+2 digits, the path-A buffers hold 2p+4 so an
// aligned sum fits, and the window and result buffers hold p+3.
fn dec_arith_frame(p int) DecArithFrame {
	mut f := DecArithFrame{}
	mut o := 0
	mut scalars := 0
	for scalars < 35 {
		o += 8
		scalars++
	}
	// The scalar slots are assigned by name below; the loop above only reserves
	// the room, and each name is given its own displacement here.
	names := [8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136, 144, 152,
		160, 168, 176, 184, 192, 200, 208, 216, 224, 232, 240, 248, 256, 264, 272, 280]
	f.dest = -names[0]
	f.aptr = -names[1]
	f.bptr = -names[2]
	f.signa = -names[3]
	f.signb = -names[4]
	f.speca = -names[5]
	f.specb = -names[6]
	f.ea = -names[7]
	f.eb = -names[8]
	f.ida = -names[9]
	f.idb = -names[10]
	f.subflag = -names[11]
	f.lsign = -names[12]
	f.lexp = -names[13]
	f.llen = -names[14]
	f.lptr = -names[15]
	f.hsign = -names[16]
	f.hexp = -names[17]
	f.hlen = -names[18]
	f.hptr = -names[19]
	f.d = -names[20]
	f.hilarg = -names[21]
	f.rlen = -names[22]
	f.rexp = -names[23]
	f.rsign = -names[24]
	f.sticky = -names[25]
	f.t0 = -names[26]
	f.t1 = -names[27]
	f.t2 = -names[28]
	f.t3 = -names[29]
	f.t4 = -names[30]
	f.total = -names[31]
	f.chi = -names[32]
	f.clo = -names[33]
	f.cqh = -names[34]
	o = align(o, 16)
	maxd := p + 2
	arr := 2 * p + 4
	win := p + 3
	o += maxd
	f.da = -o
	o += maxd
	f.db = -o
	o += arr
	f.ba = -o
	o += arr
	f.bb = -o
	o += arr
	f.br = -o
	o += win
	f.wb = -o
	o += win
	f.rb = -o
	o = align(o, 16)
	f.size = o
	return f
}

// The small emitted instructions the code below is built from. Each appends the
// machine's bytes to the routine being written.
fn (mut r DecimalRoutine) mv(dst backend.Register, src backend.Register) !void {
	r.op(r.t.move_register64(dst, src)!)
}

fn (mut r DecimalRoutine) li(dst backend.Register, v u64) !void {
	r.op(r.t.move_immediate64(dst, v)!)
}

fn (mut r DecimalRoutine) ai(dst backend.Register, v i32) !void {
	r.op(r.t.add_immediate(dst, v))
}

fn (mut r DecimalRoutine) ld(base backend.Register, disp int, dst backend.Register, w int) !void {
	r.op(r.t.load_slot(base, i32(disp), dst, w)!)
}

fn (mut r DecimalRoutine) st(base backend.Register, disp int, src backend.Register, w int) !void {
	r.op(r.t.store_slot(base, i32(disp), src, w)!)
}

fn (mut r DecimalRoutine) adr(base backend.Register, disp int, dst backend.Register) !void {
	r.op(r.t.address_of_slot(base, i32(disp), dst))
}

fn (mut r DecimalRoutine) subw(dst backend.Register, src backend.Register) !void {
	r.op(r.t.subtract_word(dst, src)!)
}

fn (mut r DecimalRoutine) addw(dst backend.Register, src backend.Register) !void {
	r.op(r.t.add_reg64(dst, src))
}

fn (mut r DecimalRoutine) andw(dst backend.Register, src backend.Register) !void {
	r.op(r.t.and_word(dst, src)!)
}

fn (mut r DecimalRoutine) orw(dst backend.Register, src backend.Register) !void {
	r.op(r.t.or_word(dst, src)!)
}

fn (mut r DecimalRoutine) xorw(dst backend.Register, src backend.Register) !void {
	r.op(r.t.xor_word(dst, src)!)
}

fn (mut r DecimalRoutine) testw(reg backend.Register) !void {
	r.op(r.t.test_word(reg)!)
}

fn (mut r DecimalRoutine) shl(dst backend.Register, n u8) !void {
	r.op(r.t.shift_left_word(dst, n)!)
}

fn (mut r DecimalRoutine) shr(dst backend.Register, n u8) !void {
	r.op(r.t.shift_right_word(dst, n)!)
}

// byl loads one byte through an address into a register, widened to the word.
fn (mut r DecimalRoutine) byl(addr backend.Register, dst backend.Register) !void {
	r.op(r.t.load_indirect(addr, dst, 1)!)
}

// bys stores the low byte of a register through an address.
fn (mut r DecimalRoutine) bys(addr backend.Register, src backend.Register) !void {
	r.op(r.t.store_indirect(addr, src, 1)!)
}

// sti stores a value through an address at a width.
fn (mut r DecimalRoutine) sti(addr backend.Register, src backend.Register, w int) !void {
	r.op(r.t.store_indirect(addr, src, w)!)
}

// emit_decimal_arith_routines writes the addition and subtraction routines a
// unit used, and no others. It is called once, after the functions.
fn (mut e Emitter) emit_decimal_arith_routines() !void {
	mut wanted := []DecArithWanted{}
	for format in [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128] {
		for subtract in [false, true] {
			if decimal_arith_name(format, subtract) in e.decimal_used {
				wanted << DecArithWanted{
					format:   format
					subtract: subtract
				}
			}
		}
	}
	mut negate := []decimal.Format{}
	for format in [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128] {
		if decimal_arith_negate_name(format) in e.decimal_used {
			negate << format
		}
	}
	if wanted.len == 0 && negate.len == 0 {
		return
	}
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(1, 1, 'internal: the target has no register a decimal operation needs')
		return error('decimal registers')
	}
	mut r := DecimalRoutine{
		t:      &e.target
		reg:    registers
		labels: map[string]int{}
	}
	for entry in wanted {
		e.decimal_arith_routine(mut r, entry.format, entry.subtract)!
	}
	for format in negate {
		e.decimal_arith_negate_routine(mut r, format)!
	}
	base := e.program.text.len
	bytes := r.resolved()
	e.program.text << bytes
	for entry in wanted {
		name := decimal_arith_name(entry.format, entry.subtract)
		e.program.labels[name] = base + r.labels[name]
	}
	for format in negate {
		name := decimal_arith_negate_name(format)
		e.program.labels[name] = base + r.labels[name]
	}
}

// decimal_arith_negate_routine writes the negation of one operand. On entry rsi
// is the operand and rdi the destination; the routine copies the stored word
// with the sign bit flipped, which is what gcc's `-a` compiles to.
fn (e Emitter) decimal_arith_negate_routine(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	r.pre = 'n${format.bytes()}_'
	r.entry(decimal_arith_negate_name(format))
	match format {
		.decimal32 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 4)!)
			r.li(g.r10, 0x80000000)!
			r.xorw(g.rax, g.r10)!
			r.op(r.t.store_indirect(g.rdi, g.rax, 4)!)
		}
		.decimal64 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 8)!)
			r.li(g.r10, 0x8000000000000000)!
			r.xorw(g.rax, g.r10)!
			r.op(r.t.store_indirect(g.rdi, g.rax, 8)!)
		}
		.decimal128 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 8)!)
			r.op(r.t.load_slot(g.rsi, 8, g.rcx, 8)!)
			r.li(g.r10, 0x8000000000000000)!
			r.xorw(g.rcx, g.r10)!
			r.op(r.t.store_indirect(g.rdi, g.rax, 8)!)
			r.op(r.t.store_slot(g.rdi, 8, g.rcx, 8)!)
		}
	}
	r.op(r.t.ret())
}

// decimal_arith_routine writes one format's addition or subtraction. On entry
// rdi is the destination object, rsi the left operand and rdx the right; the
// routine reads both operands and writes the result into the destination.
fn (e Emitter) decimal_arith_routine(mut r DecimalRoutine, format decimal.Format, subtract bool) !void {
	g := r.reg
	mut f := dec_arith_frame(format.digits())
	f.pre = 'a${format.bytes()}${if subtract { 'S' } else { 'A' }}_'
	p := format.digits()
	r.pre = f.pre
	r.entry(decimal_arith_name(format, subtract))
	r.op(r.t.frame_prologue())
	r.li(g.rax, u64(f.size))!
	r.op(r.t.sub_rsp_register(g.rax)!)
	r.st(g.rbp, f.dest, g.rdi, 8)!
	r.st(g.rbp, f.aptr, g.rsi, 8)!
	r.st(g.rbp, f.bptr, g.rdx, 8)!
	if subtract {
		r.li(g.rax, 1)!
	} else {
		r.li(g.rax, 0)!
	}
	r.st(g.rbp, f.subflag, g.rax, 8)!
	e.dec_arith_decode(mut r, f, format, 0)!
	e.dec_arith_decode(mut r, f, format, 1)!
	// A subtraction takes the sign off the right operand, which is what the
	// module's sub does before it adds.
	r.ld(g.rbp, f.subflag, g.rax, 8)!
	r.ld(g.rbp, f.signb, g.rcx, 8)!
	r.xorw(g.rcx, g.rax)!
	r.st(g.rbp, f.signb, g.rcx, 8)!
	// A special on either side takes its own path.
	r.ld(g.rbp, f.speca, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.not_equal, 'spec')
	r.ld(g.rbp, f.specb, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.not_equal, 'spec')
	// Two zeros: a zero at the smaller exponent, negative only if both were.
	r.ld(g.rbp, f.ida, g.rax, 8)!
	r.ld(g.rbp, f.idb, g.rcx, 8)!
	r.orw(g.rax, g.rcx)!
	r.testw(g.rax)!
	r.branch(.equal, 'zero')
	// The operand with the smaller exponent is L, the other H; on a tie the left
	// one is L, which the module's align does too.
	r.ld(g.rbp, f.ea, g.rax, 8)!
	r.ld(g.rbp, f.eb, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, 'lowa')
	r.adr(g.rbp, f.db, g.r11)!
	r.st(g.rbp, f.lptr, g.r11, 8)!
	r.ld(g.rbp, f.signb, g.rax, 8)!
	r.st(g.rbp, f.lsign, g.rax, 8)!
	r.ld(g.rbp, f.eb, g.rax, 8)!
	r.st(g.rbp, f.lexp, g.rax, 8)!
	r.ld(g.rbp, f.idb, g.rax, 8)!
	r.st(g.rbp, f.llen, g.rax, 8)!
	r.adr(g.rbp, f.da, g.r11)!
	r.st(g.rbp, f.hptr, g.r11, 8)!
	r.ld(g.rbp, f.signa, g.rax, 8)!
	r.st(g.rbp, f.hsign, g.rax, 8)!
	r.ld(g.rbp, f.ea, g.rax, 8)!
	r.st(g.rbp, f.hexp, g.rax, 8)!
	r.ld(g.rbp, f.ida, g.rax, 8)!
	r.st(g.rbp, f.hlen, g.rax, 8)!
	r.jump('have_lh')
	r.place('lowa')
	r.adr(g.rbp, f.da, g.r11)!
	r.st(g.rbp, f.lptr, g.r11, 8)!
	r.ld(g.rbp, f.signa, g.rax, 8)!
	r.st(g.rbp, f.lsign, g.rax, 8)!
	r.ld(g.rbp, f.ea, g.rax, 8)!
	r.st(g.rbp, f.lexp, g.rax, 8)!
	r.ld(g.rbp, f.ida, g.rax, 8)!
	r.st(g.rbp, f.llen, g.rax, 8)!
	r.adr(g.rbp, f.db, g.r11)!
	r.st(g.rbp, f.hptr, g.r11, 8)!
	r.ld(g.rbp, f.signb, g.rax, 8)!
	r.st(g.rbp, f.hsign, g.rax, 8)!
	r.ld(g.rbp, f.eb, g.rax, 8)!
	r.st(g.rbp, f.hexp, g.rax, 8)!
	r.ld(g.rbp, f.idb, g.rax, 8)!
	r.st(g.rbp, f.hlen, g.rax, 8)!
	r.place('have_lh')
	// d = Hexp - Lexp, and the result exponent is the smaller one.
	r.ld(g.rbp, f.hexp, g.rax, 8)!
	r.ld(g.rbp, f.lexp, g.rcx, 8)!
	r.subw(g.rax, g.rcx)!
	r.st(g.rbp, f.d, g.rax, 8)!
	r.ld(g.rbp, f.lexp, g.rax, 8)!
	r.st(g.rbp, f.rexp, g.rax, 8)!
	// When the operand with the larger exponent is a zero it holds no magnitude,
	// so the whole result is the other operand, unchanged, at the shared smaller
	// exponent. Its sign is that operand's: if the two signs agree they are the
	// same sign, and if they differ this one is the larger magnitude.
	r.ld(g.rbp, f.hlen, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.equal, 'low_only')
	// Same sign: the magnitudes add. A subtraction of zero is the same as an
	// addition of zero, so a zero low operand takes the add path either way.
	r.ld(g.rbp, f.lsign, g.rax, 8)!
	r.ld(g.rbp, f.hsign, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.xorw(g.r10, g.rcx)!
	r.testw(g.r10)!
	r.branch(.equal, 'adds')
	r.ld(g.rbp, f.llen, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.equal, 'adds')
	// Different signs with a nonzero low operand: the magnitudes subtract. In
	// path B (d >= p) H is larger; in path A the subtraction says which borrowed.
	r.ld(g.rbp, f.d, g.rax, 8)!
	r.li(g.rcx, u64(p))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.greater_or_equal, 'pathB_sub')
	r.jump('pathA_sub')
	r.place('adds')
	r.ld(g.rbp, f.d, g.rax, 8)!
	r.li(g.rcx, u64(p))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.greater_or_equal, 'pathB_add')
	r.jump('pathA_add')

	// -- path A --------------------------------------------------------------
	// Both operands have at most p digits and the exponents are less than p
	// apart, so the aligned magnitudes fit a buffer of 2p+4 digits and the
	// arithmetic is exact. The aligned buffers are built once, at a shared
	// entry, and a flag says whether the magnitudes then add or subtract.
	r.place('pathA_add')
	r.li(g.rax, 0)!
	r.st(g.rbp, f.hilarg, g.rax, 8)!
	r.jump('pathA_setup')

	r.place('pathA_sub')
	r.li(g.rax, 1)!
	r.st(g.rbp, f.hilarg, g.rax, 8)!

	r.place('pathA_setup')
	e.dec_arith_patha_setup(mut r, f)!
	r.ld(g.rbp, f.hilarg, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.not_equal, 'pathA_sub_go')
	r.ld(g.rbp, f.hsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	e.dec_arith_patha_add(mut r, f, format)!
	r.jump('round')

	r.place('pathA_sub_go')
	e.dec_arith_patha_sub(mut r, f, format)!
	r.jump('round')

	// -- path B --------------------------------------------------------------
	r.place('pathB_add')
	r.ld(g.rbp, f.hsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	e.dec_arith_pathb_add(mut r, f, format)!
	r.jump('round')

	r.place('pathB_sub')
	r.ld(g.rbp, f.hsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	e.dec_arith_pathb_sub(mut r, f, format)!
	r.jump('round')

	// -- rounding ------------------------------------------------------------
	r.place('round')
	e.dec_arith_round(mut r, f, format)!
	r.jump('encode')

	// -- specials ------------------------------------------------------------
	r.place('spec')
	e.dec_arith_specials(mut r, f, format)!
	r.jump('ret')

	// -- a zero result -------------------------------------------------------
	r.place('zero')
	r.ld(g.rbp, f.ea, g.rax, 8)!
	r.ld(g.rbp, f.eb, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, 'zero_a')
	r.mv(g.rax, g.rcx)!
	r.place('zero_a')
	r.st(g.rbp, f.rexp, g.rax, 8)!
	r.ld(g.rbp, f.signa, g.rax, 8)!
	r.ld(g.rbp, f.signb, g.rcx, 8)!
	r.andw(g.rax, g.rcx)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	r.li(g.rax, 0)!
	r.st(g.rbp, f.rlen, g.rax, 8)!
	r.jump('encode')

	// -- the larger-exponent operand was a zero ------------------------------
	r.place('low_only')
	r.ld(g.rbp, f.lsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	r.li(g.r9, 0)!
	r.place('lo_c')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.mv(g.rax, g.r9)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'lo_cd')
	r.ld(g.rbp, f.lptr, g.r11, 8)!
	r.addw(g.r11, g.r9)!
	r.byl(g.r11, g.rcx)!
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r9)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r9, 1)!
	r.jump('lo_c')
	r.place('lo_cd')
	r.ld(g.rbp, f.llen, g.rax, 8)!
	r.st(g.rbp, f.total, g.rax, 8)!
	r.st(g.rbp, f.rlen, g.rax, 8)!
	r.li(g.rax, 0)!
	r.st(g.rbp, f.sticky, g.rax, 8)!
	r.jump('round')

	// -- encoding ------------------------------------------------------------
	r.place('encode')
	e.dec_arith_encode(mut r, f, format)!
	r.place('ret')
	r.op(r.t.frame_epilogue())
}

// dec_arith_decode reads one operand's BID bytes into a sign, a special marker, a
// power of ten and a run of decimal digits. `which` is 0 for the left operand and
// 1 for the right; each has its own slots and its own labels.
fn (e Emitter) dec_arith_decode(mut r DecimalRoutine, f DecArithFrame, format decimal.Format, which int) !void {
	g := r.reg
	ptr_slot := if which == 0 { f.aptr } else { f.bptr }
	sign_slot := if which == 0 { f.signa } else { f.signb }
	spec_slot := if which == 0 { f.speca } else { f.specb }
	exp_slot := if which == 0 { f.ea } else { f.eb }
	len_slot := if which == 0 { f.ida } else { f.idb }
	buf := if which == 0 { f.da } else { f.db }
	pre := if which == 0 { 'dca_' } else { 'dcb_' }
	r.ld(g.rbp, ptr_slot, g.r11, 8)!
	match format {
		.decimal32 {
			r.op(r.t.load_indirect(g.r11, g.rax, 4)!)
			r.mv(g.r8, g.rax)!
			r.shr(g.r8, 31)!
			r.mv(g.r10, g.rax)!
			r.shr(g.r10, 26)!
			r.op(r.t.and_immediate(g.r10, 0x1f)!)
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -30)!
			r.branch(.equal, pre + 'inf')
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -31)!
			r.branch(.equal, pre + 'nan')
			r.mv(g.r10, g.rax)!
			r.shr(g.r10, 29)!
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -3)!
			r.branch(.equal, pre + 'large')
			r.mv(g.rcx, g.rax)!
			r.op(r.t.and_immediate(g.rcx, 0x7fffff)!)
			r.st(g.rbp, f.clo, g.rcx, 8)!
			r.li(g.r9, 0)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.mv(g.rdx, g.rax)!
			r.shr(g.rdx, 23)!
			r.op(r.t.and_immediate(g.rdx, 0xff)!)
			r.ai(g.rdx, -101)!
			r.jump(pre + 'decoded')
			r.place(pre + 'large')
			r.mv(g.rcx, g.rax)!
			r.op(r.t.and_immediate(g.rcx, 0x1fffff)!)
			r.ai(g.rcx, 0x800000)!
			r.st(g.rbp, f.clo, g.rcx, 8)!
			r.li(g.r9, 0)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.mv(g.rdx, g.rax)!
			r.shr(g.rdx, 21)!
			r.op(r.t.and_immediate(g.rdx, 0xff)!)
			r.ai(g.rdx, -101)!
			r.jump(pre + 'decoded')
		}
		.decimal64 {
			r.op(r.t.load_indirect(g.r11, g.rax, 8)!)
			r.mv(g.r8, g.rax)!
			r.shr(g.r8, 63)!
			r.mv(g.r10, g.rax)!
			r.shr(g.r10, 58)!
			r.op(r.t.and_immediate(g.r10, 0x1f)!)
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -30)!
			r.branch(.equal, pre + 'inf')
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -31)!
			r.branch(.equal, pre + 'nan')
			r.mv(g.r10, g.rax)!
			r.shr(g.r10, 61)!
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.mv(g.rcx, g.r10)!
			r.ai(g.rcx, -3)!
			r.branch(.equal, pre + 'large')
			r.mv(g.rcx, g.rax)!
			r.li(g.r9, 0x1fffffffffffff)!
			r.andw(g.rcx, g.r9)!
			r.st(g.rbp, f.clo, g.rcx, 8)!
			r.li(g.r9, 0)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.mv(g.rdx, g.rax)!
			r.shr(g.rdx, 53)!
			r.op(r.t.and_immediate(g.rdx, 0x3ff)!)
			r.ai(g.rdx, -398)!
			r.jump(pre + 'decoded')
			r.place(pre + 'large')
			r.mv(g.rcx, g.rax)!
			r.li(g.r9, 0x7ffffffffffff)!
			r.andw(g.rcx, g.r9)!
			r.li(g.r9, 0x20000000000000)!
			r.orw(g.rcx, g.r9)!
			r.st(g.rbp, f.clo, g.rcx, 8)!
			r.li(g.r9, 0)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.mv(g.rdx, g.rax)!
			r.shr(g.rdx, 51)!
			r.op(r.t.and_immediate(g.rdx, 0x3ff)!)
			r.ai(g.rdx, -398)!
			r.jump(pre + 'decoded')
		}
		.decimal128 {
			r.op(r.t.load_indirect(g.r11, g.rax, 8)!)
			r.ld(g.r11, 8, g.r10, 8)!
			r.mv(g.r8, g.r10)!
			r.shr(g.r8, 63)!
			r.mv(g.r9, g.r10)!
			r.shr(g.r9, 58)!
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			r.mv(g.rcx, g.r9)!
			r.ai(g.rcx, -30)!
			r.branch(.equal, pre + 'inf')
			r.mv(g.rcx, g.r9)!
			r.ai(g.rcx, -31)!
			r.branch(.equal, pre + 'nan')
			r.mv(g.r9, g.r10)!
			r.shr(g.r9, 61)!
			r.op(r.t.and_immediate(g.r9, 3)!)
			r.mv(g.rcx, g.r9)!
			r.ai(g.rcx, -3)!
			r.branch(.equal, pre + 'large')
			r.mv(g.r9, g.r10)!
			r.li(g.r11, 0x1ffffffffffff)!
			r.andw(g.r9, g.r11)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.st(g.rbp, f.clo, g.rax, 8)!
			r.mv(g.rdx, g.r10)!
			r.shr(g.rdx, 49)!
			r.op(r.t.and_immediate(g.rdx, 0x3fff)!)
			r.ai(g.rdx, -6176)!
			r.jump(pre + 'decoded')
			r.place(pre + 'large')
			r.mv(g.r9, g.r10)!
			r.li(g.r11, 0x7fffffffffff)!
			r.andw(g.r9, g.r11)!
			r.li(g.r11, 0x2000000000000)!
			r.orw(g.r9, g.r11)!
			r.st(g.rbp, f.chi, g.r9, 8)!
			r.st(g.rbp, f.clo, g.rax, 8)!
			r.mv(g.rdx, g.r10)!
			r.shr(g.rdx, 47)!
			r.op(r.t.and_immediate(g.rdx, 0x3fff)!)
			r.ai(g.rdx, -6176)!
			r.jump(pre + 'decoded')
		}
	}
	r.place(pre + 'decoded')
	r.st(g.rbp, sign_slot, g.r8, 8)!
	r.st(g.rbp, exp_slot, g.rdx, 8)!
	r.li(g.rax, 0)!
	r.st(g.rbp, spec_slot, g.rax, 8)!
	e.dec_arith_to_digits(mut r, f, buf, len_slot, if which == 0 { 'dga_' } else { 'dgb_' })!
	r.jump(pre + 'done')
	r.place(pre + 'inf')
	r.st(g.rbp, sign_slot, g.r8, 8)!
	r.li(g.rax, 1)!
	r.st(g.rbp, spec_slot, g.rax, 8)!
	r.li(g.rax, 0)!
	r.st(g.rbp, len_slot, g.rax, 8)!
	r.jump(pre + 'done')
	r.place(pre + 'nan')
	r.st(g.rbp, sign_slot, g.r8, 8)!
	r.li(g.rax, 2)!
	r.st(g.rbp, spec_slot, g.rax, 8)!
	r.li(g.rax, 0)!
	r.st(g.rbp, len_slot, g.rax, 8)!
	r.jump(pre + 'done')
	r.place(pre + 'done')
}

// dec_arith_to_digits turns the coefficient in chi:clo into decimal digits, most
// significant first, at the buffer `buf`, and stores the count in `len_slot`. A
// zero coefficient leaves the count at zero.
fn (e Emitter) dec_arith_to_digits(mut r DecimalRoutine, f DecArithFrame, buf int, len_slot int, tag string) !void {
	g := r.reg
	r.adr(g.rbp, buf, g.r11)!
	r.li(g.r8, 0)!
	r.place(tag + 'dig_loop')
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.ld(g.rbp, f.clo, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.orw(g.r10, g.rcx)!
	r.testw(g.r10)!
	r.branch(.equal, tag + 'dig_done')
	r.xorw(g.rdx, g.rdx)!
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.li(g.rcx, 10)!
	r.op(r.t.divide_pair(g.rcx)!)
	r.st(g.rbp, f.cqh, g.rax, 8)!
	r.ld(g.rbp, f.clo, g.rax, 8)!
	r.op(r.t.divide_pair(g.rcx)!)
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.ld(g.rbp, f.cqh, g.rax, 8)!
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.bys(g.r11, g.rdx)!
	r.ai(g.r11, 1)!
	r.ai(g.r8, 1)!
	r.jump(tag + 'dig_loop')
	r.place(tag + 'dig_done')
	r.st(g.rbp, len_slot, g.r8, 8)!
	r.adr(g.rbp, buf, g.rdi)!
	r.li(g.r9, 0)!
	r.mv(g.r10, g.r8)!
	r.ai(g.r10, -1)!
	r.place(tag + 'rev_loop')
	r.mv(g.rax, g.r9)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, tag + 'rev_done')
	r.mv(g.rax, g.rdi)!
	r.addw(g.rax, g.r9)!
	r.byl(g.rax, g.rcx)!
	r.mv(g.rdx, g.rdi)!
	r.addw(g.rdx, g.r10)!
	r.byl(g.rdx, g.r11)!
	r.bys(g.rdx, g.rcx)!
	r.bys(g.rax, g.r11)!
	r.ai(g.r9, 1)!
	r.ai(g.r10, -1)!
	r.jump(tag + 'rev_loop')
	r.place(tag + 'rev_done')
}

// dec_arith_patha_setup builds ba and bb, the two aligned magnitudes most
// significant first, with enough leading zeros that both are n digits wide where
// n is the larger of the two aligned lengths. That is what lets the add and the
// subtract below work one column at a time.
fn (e Emitter) dec_arith_patha_setup(mut r DecimalRoutine, f DecArithFrame) !void {
	g := r.reg
	// halen = Hlen + d
	r.ld(g.rbp, f.hlen, g.rax, 8)!
	r.ld(g.rbp, f.d, g.rcx, 8)!
	r.addw(g.rax, g.rcx)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	// lalen = Llen
	r.ld(g.rbp, f.llen, g.rax, 8)!
	r.st(g.rbp, f.t1, g.rax, 8)!
	// n = max(halen, lalen)
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.ld(g.rbp, f.t1, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.greater_or_equal, 'n_is_halen')
	r.mv(g.rax, g.rcx)!
	r.place('n_is_halen')
	r.st(g.rbp, f.t2, g.rax, 8)!
	e.dec_arith_zero_buf(mut r, f.ba, f.t2, 'zba')!
	e.dec_arith_zero_buf(mut r, f.bb, f.t2, 'zbb')!
	// ba[n - halen + k] = H[k]
	r.ld(g.rbp, f.t2, g.rax, 8)!
	r.ld(g.rbp, f.t0, g.rcx, 8)!
	r.subw(g.rax, g.rcx)!
	r.mv(g.r9, g.rax)!
	r.ld(g.rbp, f.hptr, g.r11, 8)!
	r.adr(g.rbp, f.ba, g.rdi)!
	r.addw(g.rdi, g.r9)!
	e.dec_arith_place_digits(mut r, g.r11, g.rdi, f.hlen, 'phd')!
	// bb[n - lalen + k] = L[k]
	r.ld(g.rbp, f.t2, g.rax, 8)!
	r.ld(g.rbp, f.t1, g.rcx, 8)!
	r.subw(g.rax, g.rcx)!
	r.mv(g.r9, g.rax)!
	r.ld(g.rbp, f.lptr, g.r11, 8)!
	r.adr(g.rbp, f.bb, g.rdi)!
	r.addw(g.rdi, g.r9)!
	e.dec_arith_place_digits(mut r, g.r11, g.rdi, f.llen, 'pld')!
}

// dec_arith_zero_buf clears n bytes of a buffer, where n is in a slot.
fn (e Emitter) dec_arith_zero_buf(mut r DecimalRoutine, buf int, n_slot int, prefix string) !void {
	g := r.reg
	r.adr(g.rbp, buf, g.r11)!
	r.li(g.r8, 0)!
	r.li(g.rcx, 0)!
	r.place(prefix + '_loop')
	r.ld(g.rbp, n_slot, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, prefix + '_done')
	r.bys(g.r11, g.rcx)!
	r.ai(g.r11, 1)!
	r.ai(g.r8, 1)!
	r.jump(prefix + '_loop')
	r.place(prefix + '_done')
}

// dec_arith_place_digits copies a source's digit run, whose length is in a slot,
// to a destination whose first byte the caller has already addressed.
fn (e Emitter) dec_arith_place_digits(mut r DecimalRoutine, src backend.Register, dst backend.Register, len_slot int, prefix string) !void {
	g := r.reg
	r.li(g.r8, 0)!
	r.place(prefix + '_loop')
	r.ld(g.rbp, len_slot, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, prefix + '_done')
	r.mv(g.rcx, src)!
	r.addw(g.rcx, g.r8)!
	r.byl(g.rcx, g.rdx)!
	r.mv(g.rcx, dst)!
	r.addw(g.rcx, g.r8)!
	r.bys(g.rcx, g.rdx)!
	r.ai(g.r8, 1)!
	r.jump(prefix + '_loop')
	r.place(prefix + '_done')
}

// dec_arith_patha_add adds the two aligned magnitudes into br and hands the
// result to dec_arith_finish, which strips the leading zeros and builds the
// rounding window.
fn (e Emitter) dec_arith_patha_add(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	r.li(g.r9, 0)!
	r.ld(g.rbp, f.t2, g.r8, 8)!
	r.ai(g.r8, -1)!
	r.place('paa_loop')
	r.testw(g.r8)!
	r.branch(.less, 'paa_done')
	r.adr(g.rbp, f.ba, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.adr(g.rbp, f.bb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rdx)!
	r.addw(g.rcx, g.rdx)!
	r.addw(g.rcx, g.r9)!
	r.mv(g.rax, g.rcx)!
	r.xorw(g.rdx, g.rdx)!
	r.li(g.r10, 10)!
	r.op(r.t.divide_pair(g.r10)!)
	r.mv(g.r9, g.rax)!
	r.adr(g.rbp, f.br, g.rax)!
	r.addw(g.rax, g.r8)!
	r.ai(g.rax, 1)!
	r.bys(g.rax, g.rdx)!
	r.ai(g.r8, -1)!
	r.jump('paa_loop')
	r.place('paa_done')
	r.adr(g.rbp, f.br, g.rax)!
	r.bys(g.rax, g.r9)!
	r.ld(g.rbp, f.t2, g.rax, 8)!
	r.ai(g.rax, 1)!
	r.st(g.rbp, f.t3, g.rax, 8)!
	e.dec_arith_finish(mut r, f, format, f.br, f.t3, 'fa')!
}

// dec_arith_patha_sub subtracts the two aligned magnitudes. It tries ba - bb
// first; if that borrowed, bb was the larger, the sign is L's and the
// subtraction is redone the other way. A result of zero takes the zero path.
fn (e Emitter) dec_arith_patha_sub(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	r.ld(g.rbp, f.t2, g.rax, 8)!
	r.ai(g.rax, 1)!
	r.st(g.rbp, f.t3, g.rax, 8)!
	e.dec_arith_patha_dosub(mut r, f, f.ba, f.bb, 's1')!
	r.ld(g.rbp, f.t4, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.equal, 'pas_ok')
	r.ld(g.rbp, f.lsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	e.dec_arith_patha_dosub(mut r, f, f.bb, f.ba, 's2')!
	r.jump('pas_fin')
	r.place('pas_ok')
	r.ld(g.rbp, f.hsign, g.rax, 8)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	r.place('pas_fin')
	e.dec_arith_finish(mut r, f, format, f.br, f.t3, 'fs')!
}

// dec_arith_patha_dosub subtracts `to` from `from` column by column and leaves
// the final borrow in t4.
fn (e Emitter) dec_arith_patha_dosub(mut r DecimalRoutine, f DecArithFrame, from int, to int, prefix string) !void {
	g := r.reg
	r.li(g.r9, 0)!
	r.ld(g.rbp, f.t2, g.r8, 8)!
	r.ai(g.r8, -1)!
	r.place(prefix + '_loop')
	r.testw(g.r8)!
	r.branch(.less, prefix + '_done')
	r.adr(g.rbp, from, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.adr(g.rbp, to, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rdx)!
	r.subw(g.rcx, g.rdx)!
	r.subw(g.rcx, g.r9)!
	r.branch(.less, prefix + '_neg')
	r.xorw(g.r9, g.r9)!
	r.jump(prefix + '_st')
	r.place(prefix + '_neg')
	r.ai(g.rcx, 10)!
	r.li(g.r9, 1)!
	r.place(prefix + '_st')
	r.adr(g.rbp, f.br, g.rax)!
	r.addw(g.rax, g.r8)!
	r.ai(g.rax, 1)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r8, -1)!
	r.jump(prefix + '_loop')
	r.place(prefix + '_done')
	r.adr(g.rbp, f.br, g.rax)!
	r.li(g.rcx, 0)!
	r.bys(g.rax, g.rcx)!
	r.st(g.rbp, f.t4, g.r9, 8)!
}

// dec_arith_finish strips the leading zeros of a result buffer, copies the top
// p+1 digits into the window, and records the sticky bit for whatever is below
// them. A result that is all zeros is a cancellation and takes the zero path.
fn (e Emitter) dec_arith_finish(mut r DecimalRoutine, f DecArithFrame, format decimal.Format, buf int, len_slot int, prefix string) !void {
	g := r.reg
	// k = the first nonzero index.
	r.li(g.r8, 0)!
	r.place(prefix + '_k')
	r.ld(g.rbp, len_slot, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, prefix + '_kd')
	r.adr(g.rbp, buf, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.testw(g.rcx)!
	r.branch(.not_equal, prefix + '_kd')
	r.ai(g.r8, 1)!
	r.jump(prefix + '_k')
	r.place(prefix + '_kd')
	r.ld(g.rbp, len_slot, g.rax, 8)!
	r.subw(g.rax, g.r8)!
	r.st(g.rbp, f.total, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.equal, 'zero')
	// nwin = min(total, p+1), the number of digits that go into the window
	r.li(g.rcx, u64(format.digits() + 1))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, prefix + '_nwt')
	r.st(g.rbp, f.t1, g.rcx, 8)!
	r.jump(prefix + '_nwd')
	r.place(prefix + '_nwt')
	r.st(g.rbp, f.t1, g.rax, 8)!
	r.place(prefix + '_nwd')
	// The window holds nwin digits and the sticky stands for the rest, so the
	// count the encoder reads is nwin and not the total.
	r.ld(g.rbp, f.t1, g.rax, 8)!
	r.st(g.rbp, f.rlen, g.rax, 8)!
	// copy buf[k .. k+nwin-1] into the window
	r.li(g.r9, 0)!
	r.place(prefix + '_c')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.mv(g.rax, g.r9)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, prefix + '_cd')
	r.adr(g.rbp, buf, g.rax)!
	r.addw(g.rax, g.r8)!
	r.addw(g.rax, g.r9)!
	r.byl(g.rax, g.rcx)!
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r9)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r9, 1)!
	r.jump(prefix + '_c')
	r.place(prefix + '_cd')
	// sticky = OR of buf[k+nwin .. len-1]
	r.li(g.r9, 0)!
	r.mv(g.r11, g.r8)!
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.addw(g.r11, g.r10)!
	r.place(prefix + '_s')
	r.ld(g.rbp, len_slot, g.r10, 8)!
	r.mv(g.rax, g.r11)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, prefix + '_sd')
	r.adr(g.rbp, buf, g.rax)!
	r.addw(g.rax, g.r11)!
	r.byl(g.rax, g.rcx)!
	r.orw(g.r9, g.rcx)!
	r.ai(g.r11, 1)!
	r.jump(prefix + '_s')
	r.place(prefix + '_sd')
	r.st(g.rbp, f.sticky, g.r9, 8)!
}

// dec_arith_pathb_add adds the smaller operand's digits, below the gap, to the
// larger's, above it. The gap itself is zeros and is never written.
fn (e Emitter) dec_arith_pathb_add(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	// total = Hlen + d
	r.ld(g.rbp, f.hlen, g.rax, 8)!
	r.ld(g.rbp, f.d, g.rcx, 8)!
	r.addw(g.rax, g.rcx)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	// compstart = total - Llen
	r.ld(g.rbp, f.llen, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.st(g.rbp, f.t2, g.r10, 8)!
	e.dec_arith_nwin(mut r, f, format, 'ban')!
	// fill the window
	r.li(g.r8, 0)!
	r.place('baf')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bafd')
	r.ld(g.rbp, f.hlen, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.less, 'baf_h')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.testw(g.r10)!
	r.branch(.equal, 'baf_0')
	r.ld(g.rbp, f.t2, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'baf_c')
	r.jump('baf_0')
	r.place('baf_h')
	r.ld(g.rbp, f.hptr, g.rdx, 8)!
	r.addw(g.rdx, g.r8)!
	r.byl(g.rdx, g.rcx)!
	r.jump('baf_s')
	r.place('baf_c')
	r.ld(g.rbp, f.t2, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.ld(g.rbp, f.lptr, g.rdx, 8)!
	r.addw(g.rdx, g.rax)!
	r.byl(g.rdx, g.rcx)!
	r.jump('baf_s')
	r.place('baf_0')
	r.li(g.rcx, 0)!
	r.place('baf_s')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r8, 1)!
	r.jump('baf')
	r.place('bafd')
	// sticky: nothing below the window is nonzero unless a digit of L is.
	r.ld(g.rbp, f.llen, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.equal, 'bas0')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.ld(g.rbp, f.t2, g.rcx, 8)!
	r.mv(g.rax, g.r10)!
	r.subw(g.rax, g.rcx)!
	r.branch(.less_or_equal, 'bas1')
	r.ld(g.rbp, f.t1, g.rax, 8)!
	r.ld(g.rbp, f.t2, g.rcx, 8)!
	r.subw(g.rax, g.rcx)!
	r.mv(g.r8, g.rax)!
	r.li(g.r9, 0)!
	r.place('bas_l')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bas_ld')
	r.ld(g.rbp, f.lptr, g.r11, 8)!
	r.addw(g.r11, g.r8)!
	r.byl(g.r11, g.rcx)!
	r.orw(g.r9, g.rcx)!
	r.ai(g.r8, 1)!
	r.jump('bas_l')
	r.place('bas_ld')
	r.st(g.rbp, f.sticky, g.r9, 8)!
	r.jump('bas_fin')
	r.place('bas0')
	r.li(g.r9, 0)!
	r.st(g.rbp, f.sticky, g.r9, 8)!
	r.jump('bas_fin')
	r.place('bas1')
	r.li(g.r9, 1)!
	r.st(g.rbp, f.sticky, g.r9, 8)!
	r.place('bas_fin')
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.st(g.rbp, f.total, g.rax, 8)!
	r.ld(g.rbp, f.t1, g.rax, 8)!
	r.st(g.rbp, f.rlen, g.rax, 8)!
}

// dec_arith_nwin stores min(total in t0, p+1) in t1.
fn (e Emitter) dec_arith_nwin(mut r DecimalRoutine, f DecArithFrame, format decimal.Format, prefix string) !void {
	g := r.reg
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.li(g.rcx, u64(format.digits() + 1))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, prefix + 'nwt')
	r.st(g.rbp, f.t1, g.rcx, 8)!
	r.jump(prefix + 'nwd')
	r.place(prefix + 'nwt')
	r.st(g.rbp, f.t1, g.rax, 8)!
	r.place(prefix + 'nwd')
}

// dec_arith_pathb_sub subtracts the smaller operand's digits from the larger's.
// Since d >= p the larger is H, so the answer is H-1 above a gap of nines with
// 10^Llen - L below it. The window is stripped of leading zeros, which happens
// only when H was one and the gap was empty.
fn (e Emitter) dec_arith_pathb_sub(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	// Hm1 = H - 1 into ba, with its leading zeros counted in t4 and its length
	// in t3.
	r.ld(g.rbp, f.hptr, g.r11, 8)!
	r.adr(g.rbp, f.ba, g.rdi)!
	r.li(g.r8, 0)!
	r.ld(g.rbp, f.hlen, g.r10, 8)!
	r.place('hmcopy')
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'hmcopyd')
	r.mv(g.rcx, g.r11)!
	r.addw(g.rcx, g.r8)!
	r.byl(g.rcx, g.rdx)!
	r.mv(g.rcx, g.rdi)!
	r.addw(g.rcx, g.r8)!
	r.bys(g.rcx, g.rdx)!
	r.ai(g.r8, 1)!
	r.jump('hmcopy')
	r.place('hmcopyd')
	r.ld(g.rbp, f.hlen, g.r8, 8)!
	r.ai(g.r8, -1)!
	r.li(g.r9, 1)!
	r.place('hmsub')
	r.testw(g.r8)!
	r.branch(.less, 'hmsubd')
	r.adr(g.rbp, f.ba, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.subw(g.rcx, g.r9)!
	r.branch(.less, 'hmneg')
	r.adr(g.rbp, f.ba, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.jump('hmsubd')
	r.place('hmneg')
	r.ai(g.rcx, 10)!
	r.adr(g.rbp, f.ba, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r8, -1)!
	r.jump('hmsub')
	r.place('hmsubd')
	// strip Hm1's leading zeros
	r.li(g.r8, 0)!
	r.place('hmstrip')
	r.ld(g.rbp, f.hlen, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'hmstripd')
	r.adr(g.rbp, f.ba, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.testw(g.rcx)!
	r.branch(.not_equal, 'hmstripd')
	r.ai(g.r8, 1)!
	r.jump('hmstrip')
	r.place('hmstripd')
	r.st(g.rbp, f.t4, g.r8, 8)!
	r.ld(g.rbp, f.hlen, g.rax, 8)!
	r.subw(g.rax, g.r8)!
	r.st(g.rbp, f.t3, g.rax, 8)!
	// comp = 10^Llen - L into bb, LSD first and then reversed.
	r.li(g.r8, 0)!
	r.li(g.r9, 0)!
	r.place('cpl')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'cpld')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.ai(g.r10, -1)!
	r.subw(g.r10, g.r8)!
	r.ld(g.rbp, f.lptr, g.r11, 8)!
	r.addw(g.r11, g.r10)!
	r.byl(g.r11, g.rcx)!
	r.xorw(g.rdx, g.rdx)!
	r.subw(g.rdx, g.rcx)!
	r.subw(g.rdx, g.r9)!
	r.branch(.less, 'cplneg')
	r.xorw(g.r9, g.r9)!
	r.jump('cplst')
	r.place('cplneg')
	r.ai(g.rdx, 10)!
	r.li(g.r9, 1)!
	r.place('cplst')
	r.adr(g.rbp, f.bb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rdx)!
	r.ai(g.r8, 1)!
	r.jump('cpl')
	r.place('cpld')
	r.adr(g.rbp, f.bb, g.rdi)!
	r.li(g.r8, 0)!
	r.ld(g.rbp, f.llen, g.r9, 8)!
	r.ai(g.r9, -1)!
	r.place('cpr')
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r9)!
	r.branch(.greater_or_equal, 'cprd')
	r.mv(g.rcx, g.rdi)!
	r.addw(g.rcx, g.r8)!
	r.byl(g.rcx, g.rdx)!
	r.mv(g.r10, g.rdi)!
	r.addw(g.r10, g.r9)!
	r.byl(g.r10, g.r11)!
	r.bys(g.rcx, g.r11)!
	r.bys(g.r10, g.rdx)!
	r.ai(g.r8, 1)!
	r.ai(g.r9, -1)!
	r.jump('cpr')
	r.place('cprd')
	// total = hlen + d; compstart = total - Llen; nwin.
	r.ld(g.rbp, f.t3, g.rax, 8)!
	r.ld(g.rbp, f.d, g.rcx, 8)!
	r.addw(g.rax, g.rcx)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	r.ld(g.rbp, f.llen, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.st(g.rbp, f.t2, g.r10, 8)!
	e.dec_arith_nwin(mut r, f, format, 'bsn')!
	// fill the window: Hm1 above, nines in the gap, comp below.
	r.li(g.r8, 0)!
	r.place('bsf')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bsfd')
	r.ld(g.rbp, f.t3, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.less, 'bsf_h')
	r.ld(g.rbp, f.t2, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bsf_c')
	r.li(g.rcx, 9)!
	r.jump('bsf_s')
	r.place('bsf_h')
	r.ld(g.rbp, f.t4, g.r10, 8)!
	r.addw(g.r10, g.r8)!
	r.adr(g.rbp, f.ba, g.rdx)!
	r.addw(g.rdx, g.r10)!
	r.byl(g.rdx, g.rcx)!
	r.jump('bsf_s')
	r.place('bsf_c')
	r.ld(g.rbp, f.t2, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.adr(g.rbp, f.bb, g.rdx)!
	r.addw(g.rdx, g.rax)!
	r.byl(g.rdx, g.rcx)!
	r.place('bsf_s')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r8, 1)!
	r.jump('bsf')
	r.place('bsfd')
	// sticky: the gap below the window is nines, which are nonzero, and the comp
	// below it may be too.
	r.ld(g.rbp, f.t2, g.rcx, 8)!
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.mv(g.rax, g.rcx)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater, 'bss1')
	r.ld(g.rbp, f.t1, g.rax, 8)!
	r.ld(g.rbp, f.t2, g.rcx, 8)!
	r.subw(g.rax, g.rcx)!
	r.mv(g.r8, g.rax)!
	r.li(g.r9, 0)!
	r.place('bss_l')
	r.ld(g.rbp, f.llen, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bss_ld')
	r.adr(g.rbp, f.bb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.orw(g.r9, g.rcx)!
	r.ai(g.r8, 1)!
	r.jump('bss_l')
	r.place('bss_ld')
	r.st(g.rbp, f.sticky, g.r9, 8)!
	r.jump('bss_fin')
	r.place('bss1')
	r.li(g.r9, 1)!
	r.st(g.rbp, f.sticky, g.r9, 8)!
	r.place('bss_fin')
	// strip the window's leading zeros, which only the H == 1 case produces.
	r.li(g.r8, 0)!
	r.place('bsz')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.mv(g.rax, g.r8)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bszd')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.testw(g.rcx)!
	r.branch(.not_equal, 'bszd')
	r.ai(g.r8, 1)!
	r.jump('bsz')
	r.place('bszd')
	r.testw(g.r8)!
	r.branch(.equal, 'bsz_done')
	r.ld(g.rbp, f.t1, g.r10, 8)!
	r.subw(g.r10, g.r8)!
	r.li(g.r9, 0)!
	r.place('bss_l2')
	r.mv(g.rax, g.r9)!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'bss_l2d')
	r.mv(g.rdx, g.r9)!
	r.addw(g.rdx, g.r8)!
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.rdx)!
	r.byl(g.rax, g.rcx)!
	r.adr(g.rbp, f.rb, g.rdx)!
	r.addw(g.rdx, g.r9)!
	r.bys(g.rdx, g.rcx)!
	r.ai(g.r9, 1)!
	r.jump('bss_l2')
	r.place('bss_l2d')
	r.place('bsz_done')
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.st(g.rbp, f.total, g.rax, 8)!
	r.ld(g.rbp, f.t1, g.rax, 8)!
	r.subw(g.rax, g.r8)!
	r.st(g.rbp, f.rlen, g.rax, 8)!
}

// dec_arith_round rounds the magnitude to the format's digit count, ties to
// even, working on the p+1 digit window and the sticky bit the paths left.
fn (e Emitter) dec_arith_round(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	p := format.digits()
	// The rounding decision and the exponent shift are the total digit count's;
	// the window only carries the top p+1 of them.
	r.ld(g.rbp, f.total, g.r8, 8)!
	r.li(g.rcx, u64(p))!
	r.mv(g.r10, g.r8)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, 'rnd_ret')
	r.subw(g.r8, g.rcx)!
	r.st(g.rbp, f.t0, g.r8, 8)!
	// guard = window[p]
	r.adr(g.rbp, f.rb, g.rax)!
	r.ai(g.rax, p)!
	r.byl(g.rax, g.rcx)!
	r.mv(g.r10, g.rcx)!
	r.li(g.r11, 5)!
	r.subw(g.r10, g.r11)!
	r.branch(.greater, 'rnd_up')
	r.branch(.less, 'ru_done')
	r.ld(g.rbp, f.sticky, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.not_equal, 'rnd_up')
	r.adr(g.rbp, f.rb, g.rax)!
	r.ai(g.rax, p - 1)!
	r.byl(g.rax, g.rcx)!
	r.li(g.r10, 1)!
	r.andw(g.rcx, g.r10)!
	r.testw(g.rcx)!
	r.branch(.not_equal, 'rnd_up')
	r.jump('ru_done')
	r.place('rnd_up')
	r.li(g.r8, u64(p))!
	r.ai(g.r8, -1)!
	r.place('ru_l')
	r.testw(g.r8)!
	r.branch(.less, 'ru_carry')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.byl(g.rax, g.rcx)!
	r.ai(g.rcx, 1)!
	r.mv(g.r10, g.rcx)!
	r.li(g.r11, 10)!
	r.subw(g.r10, g.r11)!
	r.branch(.less, 'ru_inc')
	r.li(g.rcx, 0)!
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r8, -1)!
	r.jump('ru_l')
	r.place('ru_inc')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r8)!
	r.bys(g.rax, g.rcx)!
	r.jump('ru_done')
	r.place('ru_carry')
	r.adr(g.rbp, f.rb, g.rax)!
	r.li(g.rcx, 1)!
	r.bys(g.rax, g.rcx)!
	r.li(g.r9, 1)!
	r.place('ru_z')
	r.mv(g.rax, g.r9)!
	r.li(g.r10, u64(p))!
	r.subw(g.rax, g.r10)!
	r.branch(.greater_or_equal, 'ru_zd')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r9)!
	r.li(g.rcx, 0)!
	r.bys(g.rax, g.rcx)!
	r.ai(g.r9, 1)!
	r.jump('ru_z')
	r.place('ru_zd')
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.ai(g.rax, 1)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	r.place('ru_done')
	r.li(g.rax, u64(p))!
	r.st(g.rbp, f.rlen, g.rax, 8)!
	r.ld(g.rbp, f.rexp, g.rax, 8)!
	r.ld(g.rbp, f.t0, g.rcx, 8)!
	r.addw(g.rax, g.rcx)!
	r.st(g.rbp, f.rexp, g.rax, 8)!
	r.place('rnd_ret')
	_ = format
}

// dec_arith_encode writes the result from rsign, rexp, rlen and rb into the
// destination object, in the BID encoding the module's encode produces.
fn (e Emitter) dec_arith_encode(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	p := format.digits()
	cbits := format.coefficient_bits()
	bias := format.bias()
	maxb := format.largest_biased_exponent()
	r.ld(g.rbp, f.dest, g.rdi, 8)!
	r.ld(g.rbp, f.rlen, g.r8, 8)!
	r.testw(g.r8)!
	r.branch(.equal, 'enc_zero')
	// c = the digits as an integer, in chi:clo.
	r.li(g.rax, 0)!
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.li(g.r9, 0)!
	r.place('enc_dl')
	r.mv(g.r10, g.r9)!
	r.subw(g.r10, g.r8)!
	r.branch(.greater_or_equal, 'enc_dd')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r9)!
	r.byl(g.rax, g.rcx)!
	r.ld(g.rbp, f.clo, g.rax, 8)!
	r.li(g.r10, 10)!
	r.op(r.t.multiply_pair(g.r10)!)
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.mv(g.r11, g.rdx)!
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.op(r.t.multiply_pair(g.r10)!)
	r.addw(g.rax, g.r11)!
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.ld(g.rbp, f.clo, g.rax, 8)!
	r.addw(g.rax, g.rcx)!
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.op(r.t.add_with_carry_immediate(g.rax, 0)!)
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.ai(g.r9, 1)!
	r.jump('enc_dl')
	r.place('enc_dd')
	// used = rlen, biased = rexp + bias
	r.ld(g.rbp, f.rlen, g.r9, 8)!
	r.ld(g.rbp, f.rexp, g.rax, 8)!
	r.ai(g.rax, bias)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	// while biased > maxb and used < p: c *= 10; used++; biased--
	r.place('enc_g1')
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.li(g.rcx, u64(maxb))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, 'enc_g1d')
	r.mv(g.r10, g.r9)!
	r.li(g.rcx, u64(p))!
	r.subw(g.r10, g.rcx)!
	r.branch(.greater_or_equal, 'enc_g1d')
	r.ld(g.rbp, f.clo, g.rax, 8)!
	r.li(g.r10, 10)!
	r.op(r.t.multiply_pair(g.r10)!)
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.mv(g.r11, g.rdx)!
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.op(r.t.multiply_pair(g.r10)!)
	r.addw(g.rax, g.r11)!
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.ai(g.r9, 1)!
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.ai(g.rax, -1)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	r.jump('enc_g1')
	r.place('enc_g1d')
	// removable = the trailing zeros of the result digits
	r.li(g.r11, 0)!
	r.ld(g.rbp, f.rlen, g.r10, 8)!
	r.ai(g.r10, -1)!
	r.place('enc_tz')
	r.testw(g.r10)!
	r.branch(.less, 'enc_tzd')
	r.adr(g.rbp, f.rb, g.rax)!
	r.addw(g.rax, g.r10)!
	r.byl(g.rax, g.rcx)!
	r.testw(g.rcx)!
	r.branch(.not_equal, 'enc_tzd')
	r.ai(g.r11, 1)!
	r.ai(g.r10, -1)!
	r.jump('enc_tz')
	r.place('enc_tzd')
	// while biased < 0 and removable > 0: c /= 10; used--; removable--; biased++
	r.place('enc_g2')
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.greater_or_equal, 'enc_g2d')
	r.testw(g.r11)!
	r.branch(.equal, 'enc_g2d')
	r.xorw(g.rdx, g.rdx)!
	r.ld(g.rbp, f.chi, g.rax, 8)!
	r.li(g.rcx, 10)!
	r.op(r.t.divide_pair(g.rcx)!)
	r.st(g.rbp, f.cqh, g.rax, 8)!
	r.ld(g.rbp, f.clo, g.rax, 8)!
	r.op(r.t.divide_pair(g.rcx)!)
	r.st(g.rbp, f.clo, g.rax, 8)!
	r.ld(g.rbp, f.cqh, g.rax, 8)!
	r.st(g.rbp, f.chi, g.rax, 8)!
	r.ai(g.r9, -1)!
	r.ai(g.r11, -1)!
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.ai(g.rax, 1)!
	r.st(g.rbp, f.t0, g.rax, 8)!
	r.jump('enc_g2')
	r.place('enc_g2d')
	// an exponent below the field is an underflow to zero; above it, an infinity.
	r.ld(g.rbp, f.t0, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.less, 'enc_zero')
	r.li(g.rcx, u64(maxb))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.greater, 'enc_over')
	match format {
		.decimal32 {
			r.ld(g.rbp, f.clo, g.rax, 8)!
			r.li(g.rcx, u64(1 << cbits))!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.below, 'enc_n32')
			r.li(g.rcx, u64((1 << cbits) + (1 << (cbits - 2))))!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.above_or_equal, 'enc_over')
			r.ld(g.rbp, f.t0, g.rcx, 8)!
			r.shl(g.rcx, u8(cbits - 2))!
			r.li(g.r10, u64(3 << (total_bits(format) - 3)))!
			r.orw(g.rcx, g.r10)!
			r.li(g.r10, u64((1 << (cbits - 2)) - 1))!
			r.andw(g.rax, g.r10)!
			r.orw(g.rcx, g.rax)!
			r.jump('enc_stw')
			r.place('enc_n32')
			r.ld(g.rbp, f.t0, g.rcx, 8)!
			r.shl(g.rcx, u8(cbits))!
			r.orw(g.rcx, g.rax)!
			r.jump('enc_stw')
		}
		.decimal64 {
			r.ld(g.rbp, f.clo, g.rax, 8)!
			r.li(g.rcx, u64(1 << cbits))!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.below, 'enc_n64')
			r.li(g.rcx, u64((1 << cbits) + (1 << (cbits - 2))))!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.above_or_equal, 'enc_over')
			r.ld(g.rbp, f.t0, g.rcx, 8)!
			r.shl(g.rcx, u8(cbits - 2))!
			r.li(g.r10, u64(3 << (total_bits(format) - 3)))!
			r.orw(g.rcx, g.r10)!
			r.li(g.r10, u64((1 << (cbits - 2)) - 1))!
			r.andw(g.rax, g.r10)!
			r.orw(g.rcx, g.rax)!
			r.jump('enc_stw')
			r.place('enc_n64')
			r.ld(g.rbp, f.t0, g.rcx, 8)!
			r.shl(g.rcx, u8(cbits))!
			r.orw(g.rcx, g.rax)!
			r.jump('enc_stw')
		}
		.decimal128 {
			r.ld(g.rbp, f.chi, g.rax, 8)!
			r.li(g.rcx, u64(1) << 49)!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.below, 'enc_n128')
			r.li(g.rcx, u64(5) << 47)!
			r.mv(g.r10, g.rax)!
			r.subw(g.r10, g.rcx)!
			r.branch(.above_or_equal, 'enc_over')
			r.ld(g.rbp, f.t0, g.r11, 8)!
			r.shl(g.r11, 47)!
			r.li(g.r10, u64(3) << 62)!
			r.orw(g.r11, g.r10)!
			r.li(g.r10, (u64(1) << 47) - 1)!
			r.andw(g.rax, g.r10)!
			r.orw(g.r11, g.rax)!
			r.ld(g.rbp, f.clo, g.rcx, 8)!
			r.jump('enc_stw')
			r.place('enc_n128')
			r.ld(g.rbp, f.t0, g.r11, 8)!
			r.shl(g.r11, 49)!
			r.ld(g.rbp, f.chi, g.rax, 8)!
			r.orw(g.r11, g.rax)!
			r.ld(g.rbp, f.clo, g.rcx, 8)!
			r.jump('enc_stw')
		}
	}
	r.place('enc_stw')
	e.dec_arith_store_word(mut r, f, format, g.rcx, g.r11)!
	r.jump('ret')
	r.place('enc_over')
	match format {
		.decimal32 {
			r.li(g.rcx, 0x78000000)!
		}
		.decimal64 {
			r.li(g.rcx, 0x7800000000000000)!
		}
		.decimal128 {
			r.li(g.rcx, 0)!
			r.li(g.r11, 0x7800000000000000)!
		}
	}
	e.dec_arith_store_word(mut r, f, format, g.rcx, g.r11)!
	r.jump('ret')
	r.place('enc_zero')
	r.ld(g.rbp, f.rexp, g.rax, 8)!
	r.ai(g.rax, bias)!
	r.testw(g.rax)!
	r.branch(.greater_or_equal, 'ez1')
	r.li(g.rax, 0)!
	r.place('ez1')
	r.li(g.rcx, u64(maxb))!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.less_or_equal, 'ez2')
	r.mv(g.rax, g.rcx)!
	r.place('ez2')
	match format {
		.decimal32 {
			r.mv(g.rcx, g.rax)!
			r.shl(g.rcx, 23)!
		}
		.decimal64 {
			r.mv(g.rcx, g.rax)!
			r.shl(g.rcx, 53)!
		}
		.decimal128 {
			r.mv(g.r11, g.rax)!
			r.shl(g.r11, 49)!
			r.li(g.rcx, 0)!
		}
	}
	e.dec_arith_store_word(mut r, f, format, g.rcx, g.r11)!
	r.jump('ret')
}

// total_bits is the width of a format in bits.
fn total_bits(format decimal.Format) int {
	return format.bytes() * 8
}

// dec_arith_store_word puts the sign bit on the word and writes it into the
// destination, which dec_arith_encode has left in rdi. The high word is
// meaningful only for the 128-bit format.
fn (e Emitter) dec_arith_store_word(mut r DecimalRoutine, f DecArithFrame, format decimal.Format, wlo backend.Register, whi backend.Register) !void {
	g := r.reg
	match format {
		.decimal32 {
			r.ld(g.rbp, f.rsign, g.rax, 8)!
			r.shl(g.rax, 31)!
			r.orw(wlo, g.rax)!
			r.sti(g.rdi, wlo, 4)!
		}
		.decimal64 {
			r.ld(g.rbp, f.rsign, g.rax, 8)!
			r.shl(g.rax, 63)!
			r.orw(wlo, g.rax)!
			r.sti(g.rdi, wlo, 8)!
		}
		.decimal128 {
			r.ld(g.rbp, f.rsign, g.rax, 8)!
			r.shl(g.rax, 63)!
			r.orw(whi, g.rax)!
			r.sti(g.rdi, wlo, 8)!
			r.ai(g.rdi, 8)!
			r.sti(g.rdi, whi, 8)!
		}
	}
}

// dec_arith_specials writes the result when either operand is an infinity or a
// NaN, matching decimal/decimal.v's special_sum on the operands after a
// subtraction has taken the sign off the right one: a NaN on either side is the
// quiet NaN, an infinity beside a finite value is that infinity, and two
// infinities of opposite sign are the quiet NaN.
fn (e Emitter) dec_arith_specials(mut r DecimalRoutine, f DecArithFrame, format decimal.Format) !void {
	g := r.reg
	r.ld(g.rbp, f.speca, g.rax, 8)!
	r.li(g.rcx, 2)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.equal, 'spec_nan')
	r.ld(g.rbp, f.specb, g.rax, 8)!
	r.mv(g.r10, g.rax)!
	r.subw(g.r10, g.rcx)!
	r.branch(.equal, 'spec_nan')
	r.ld(g.rbp, f.speca, g.rax, 8)!
	r.testw(g.rax)!
	r.branch(.not_equal, 'spec_a_inf')
	r.ld(g.rbp, f.signb, g.rax, 8)!
	r.jump('spec_inf')
	r.place('spec_a_inf')
	r.ld(g.rbp, f.specb, g.rcx, 8)!
	r.testw(g.rcx)!
	r.branch(.equal, 'spec_a_only')
	r.ld(g.rbp, f.signa, g.rax, 8)!
	r.ld(g.rbp, f.signb, g.rcx, 8)!
	r.mv(g.r10, g.rax)!
	r.xorw(g.r10, g.rcx)!
	r.testw(g.r10)!
	r.branch(.not_equal, 'spec_nan')
	r.place('spec_a_only')
	r.ld(g.rbp, f.signa, g.rax, 8)!
	r.place('spec_inf')
	r.st(g.rbp, f.rsign, g.rax, 8)!
	r.ld(g.rbp, f.dest, g.rdi, 8)!
	match format {
		.decimal32 {
			r.li(g.rcx, 0x78000000)!
		}
		.decimal64 {
			r.li(g.rcx, 0x7800000000000000)!
		}
		.decimal128 {
			r.li(g.rcx, 0)!
			r.li(g.r11, 0x7800000000000000)!
		}
	}
	e.dec_arith_store_word(mut r, f, format, g.rcx, g.r11)!
	r.jump('spec_ret')
	r.place('spec_nan')
	r.li(g.rax, 0)!
	r.st(g.rbp, f.rsign, g.rax, 8)!
	r.ld(g.rbp, f.dest, g.rdi, 8)!
	match format {
		.decimal32 {
			r.li(g.rcx, 0x7e000000)!
		}
		.decimal64 {
			r.li(g.rcx, 0x7e00000000000000)!
		}
		.decimal128 {
			r.li(g.rcx, 0)!
			r.li(g.r11, 0x7e00000000000000)!
		}
	}
	e.dec_arith_store_word(mut r, f, format, g.rcx, g.r11)!
	r.place('spec_ret')
}
