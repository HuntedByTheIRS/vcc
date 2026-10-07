// Comparison of two decimal floating values through the emitter.
//
// The reader carries _Decimal32, _Decimal64 and _Decimal128 as objects in memory,
// each holding the BID encoding gcc stores. A comparison of two of them is the one
// operation on the types that is a routine rather than a sequence of the
// accumulator: the operands travel by address, because they are objects and not
// values of a register this back end computes in, and the answer is an int.
//
// The routine is emitted once per width a unit compares, the way the conversion
// routine is, and for the same reason: a program that never compares a decimal
// carries none of it. It decodes both operands, orders them the way
// decimal/decimal.v's cmp_values orders two decoded values, and leaves one of
// four codes in the result register. The call site turns that code into the
// operator's own answer, so the operator is not an argument to the routine and
// the routine is written once.
//
// The four codes are the whole of a comparison: 0 when the two are equal, 1 when
// the left is greater, 2 when it is less, and 3 when the pair is unordered, which
// is what a NaN operand makes of every operator but !=. The order itself is
// decided the way cmp_values decides it: a NaN first, then an infinity against a
// finite value, then the sign, then the magnitude. The magnitude is compared by
// giving each coefficient the format's full digit count, which makes the
// exponents directly comparable and, when they agree, makes the coefficients
// directly comparable: scaling the smaller-exponent coefficient up rather than the
// larger one down keeps every digit, and the number of digits a format keeps
// bounds the exponent difference.
module codegen

import ast
import backend
import decimal

// decimal_compare_name is the label a comparison of one format enters. The width
// names it, so the three widths do not collide.
fn decimal_compare_name(format decimal.Format) string {
	return 'vcc_decimal_compare_${format.bytes()}'
}

// decimal_compare_codes names the four things a comparison can be. A NaN on
// either side makes the pair unordered, which is neither of the three orders.
const decimal_compare_equal = u64(0)
const decimal_compare_greater = u64(1)
const decimal_compare_less = u64(2)
const decimal_compare_unordered = u64(3)

// The frame the comparison routine keeps its decoded operands in. Each decode
// writes five words: the special, the sign, the exponent and the two words of the
// coefficient. The two blocks are laid one after the other and the whole frame is
// rounded up past them.
const decimal_compare_frame = 96

// decimal_compare_threshold is the smallest coefficient with the format's full
// digit count, which is the coefficient the normalizing multiply stops at: a
// coefficient below it is multiplied by ten and its exponent lowered by one until
// it is not. It is ten to one less than the number of digits the format keeps, so
// it is at most 10^33 and fits two words.
fn decimal_compare_threshold(format decimal.Format) (u64, u64) {
	return match format {
		.decimal32 {
			(u64(0)), u64(0xf4240)
		}
		.decimal64 {
			(u64(0)), u64(0x38d7ea4c68000)
		}
		.decimal128 {
			(u64(0x314dc6448d93)), u64(0x38c15b0a00000000)
		}
	}
}

// load_local and store_local read and write one word of the routine's own frame,
// which is based in rbx. They are the only memory the routine touches apart from
// the two operands.
fn (mut r DecimalRoutine) load_local(slot int, register backend.Register) !void {
	r.op(r.t.load_slot(r.reg.rbx, i32(slot), register, 8)!)
}

fn (mut r DecimalRoutine) store_local(slot int, register backend.Register) !void {
	r.op(r.t.store_slot(r.reg.rbx, i32(slot), register, 8)!)
}

fn (mut r DecimalRoutine) move_imm(register backend.Register, value u64) !void {
	r.op(r.t.move_immediate64(register, value)!)
}

fn (mut r DecimalRoutine) move_reg(dst backend.Register, src backend.Register) !void {
	r.op(r.t.move_register64(dst, src)!)
}

// decimal_operand_format is the format of an expression that is one of the
// decimal types, or none for anything else. It is asked of both operands of a
// comparison, and the two answers have to be the same format for the routine that
// compares them to exist.
fn (e Emitter) decimal_operand_format(expr ast.Expr) ?decimal.Format {
	if !expr.typ.kind.is_decimal() {
		return none
	}
	return expr.typ.kind.decimal_format()
}

// emit_decimal_comparison writes a comparison of two decimal values. Each operand
// is addressed where it lives and the address is left in the register the routine
// reads its two arguments from; the routine is called and its order code is turned
// into the operator's answer. An operand that is a constant is written into a slot
// of its own first, because the routine reads an object and a constant is one the
// encoder can already produce the bytes of.
//
// The step reaching here is one decimal_step answered .value for, so its two
// operands are decimals. Two decimals of different widths, or an operand that is
// neither an object nor a constant, are refused by name rather than compared at
// the wrong width.
fn (mut e Emitter) emit_decimal_comparison(step ast.Binary, depth int) !void {
	left := e.decimal_operand_format(step.left) or {
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} compares ${step.left.typ.describe()} with ${step.right.typ.describe()} here, and this back end compares two decimals of the same width')
		return error('decimal comparison operand')
	}
	right := e.decimal_operand_format(step.right) or {
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} compares ${step.left.typ.describe()} with ${step.right.typ.describe()} here, and this back end compares two decimals of the same width')
		return error('decimal comparison operand')
	}
	if left != right {
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} compares ${step.left.typ.describe()} with ${step.right.typ.describe()} here, and this back end compares two decimals of the same width')
		return error('decimal comparison operand')
	}
	e.decimal_compare_call(left, step.left, step.right, step.line, step.col, depth)!
	e.decimal_comparison_result(step.op, step.line, step.col)!
}

// emit_decimal_logical_not writes `!a` for a decimal operand. The operator asks
// whether the value is zero, which is the equality comparison against a zero of
// the same width: a NaN is not equal to zero and a zero of either sign is, which
// is what gcc's `!a` is measured to do. The zero is written into a slot of its own
// first, so the routine reads the same kind of operand twice.
fn (mut e Emitter) emit_decimal_logical_not(unary ast.Unary, depth int) !void {
	format := e.decimal_operand_format(unary.expr) or {
		e.diagnostics << problem(unary.line, unary.col, 'unsupported: ! takes a value this back end has no form for, and ${describe_target(unary.expr)} is a ${unary.expr.typ.describe()}')
		return error('decimal logical not')
	}
	zero := decimal.encode(decimal.zero(false), format)
	zero_slot := e.reserve(zero.len)
	e.put_decimal_bytes(zero_slot, zero, unary.line, unary.col)!
	first := e.reserve(e.target.word_size)
	e.decimal_operand_address(unary.expr, depth + 1, unary.line, unary.col)!
	e.store_accumulator(first, unary.line, unary.col)!
	base := e.frame_pointer(unary.line, unary.col)!
	e.append(e.target.address_of_slot(base, zero_slot.offset, e.accumulator(unary.line, unary.col)!))
	e.decimal_compare_arguments(first, unary.line, unary.col)!
	e.decimal_compare_emit_call(format)
	e.decimal_comparison_result('==', unary.line, unary.col)!
}

// decimal_compare_call emits the two operand addresses, the call into the width's
// comparison routine, and leaves its order code in the accumulator.
fn (mut e Emitter) decimal_compare_call(format decimal.Format, left ast.Expr, right ast.Expr, line int, col int, depth int) !void {
	// The first address waits in a slot while the second is computed, because the
	// expression that produces the second may use the register the first is in.
	first := e.reserve(e.target.word_size)
	e.decimal_operand_address(left, depth + 1, line, col)!
	e.store_accumulator(first, line, col)!
	e.decimal_operand_address(right, depth + 1, line, col)!
	e.decimal_compare_arguments(first, line, col)!
	e.decimal_compare_emit_call(format)
}

// decimal_compare_arguments moves the first operand's address out of its slot and
// the second one out of the accumulator into the two registers the routine reads
// them from.
fn (mut e Emitter) decimal_compare_arguments(first Slot, line int, col int) !void {
	rdi := e.target.arg_reg(0) or {
		e.diagnostics << problem(line, col, 'internal: the target has no register a decimal comparison passes its first operand in')
		return error('decimal argument register')
	}
	rsi := e.target.arg_reg(1) or {
		e.diagnostics << problem(line, col, 'internal: the target has no register a decimal comparison passes its second operand in')
		return error('decimal argument register')
	}
	e.append(e.target.move_register64(rsi, e.accumulator(line, col)!)!)
	e.load_accumulator(first, line, col)!
	e.append(e.target.move_register64(rdi, e.accumulator(line, col)!)!)
}

// decimal_compare_emit_call records that the width's comparison routine is used
// and writes the call to it. The call is left local, so the routine is carried only
// by a unit that compares that width.
fn (mut e Emitter) decimal_compare_emit_call(format decimal.Format) {
	name := decimal_compare_name(format)
	e.decimal_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// decimal_operand_address leaves the address of a decimal operand in the
// accumulator. An object already has one; a constant has the bytes the encoder
// gives it written into a slot of the frame, and the address of that slot is the
// address. Anything else is refused by name.
fn (mut e Emitter) decimal_operand_address(operand ast.Expr, depth int, line int, col int) !void {
	if e.names_an_object(operand) {
		return e.emit_address(ast.Unary{
			op:   '&'
			expr: operand
			typ:  operand.typ
			line: line
			col:  col
		}, depth + 1)
	}
	if bytes := decimal_constant_bytes(operand) {
		format := operand.typ.kind.decimal_format()
		if bytes.len == format.bytes() {
			slot := e.reserve(bytes.len)
			e.put_decimal_bytes(slot, bytes, line, col)!
			base := e.frame_pointer(line, col)!
			e.append(e.target.address_of_slot(base, slot.offset, e.accumulator(line, col)!))
			return
		}
	}
	e.diagnostics << problem(line, col, 'unsupported: ${describe_target(operand)} is used in a comparison of decimals, and this back end compares decimal objects or constants')
	return error('decimal comparison operand')
}

// decimal_comparison_result turns the routine's order code into the operator's
// answer, leaving one or zero in the accumulator the way any comparison does. The
// code is small and every operator is one test of it: equality is the code being
// zero; less is the code being exactly two; greater is exactly one; `<=` is the
// low bit clear, which is true of equal and less and false of greater and
// unordered; and `>=` is the second bit clear, which is true of equal and greater
// and false of less and unordered.
fn (mut e Emitter) decimal_comparison_result(op string, line int, col int) !void {
	register := e.accumulator(line, col)!
	match op {
		'==' {
			e.append(e.target.test_word(register)!)
			e.append(e.target.set_condition(.equal, register)!)
		}
		'!=' {
			e.append(e.target.test_word(register)!)
			e.append(e.target.set_condition(.not_equal, register)!)
		}
		'<' {
			e.append(e.target.add_immediate(register, -2))
			e.append(e.target.set_condition(.equal, register)!)
		}
		'>' {
			e.append(e.target.add_immediate(register, -1))
			e.append(e.target.set_condition(.equal, register)!)
		}
		'<=' {
			e.append(e.target.test_byte_immediate(register, 1)!)
			e.append(e.target.set_condition(.equal, register)!)
		}
		'>=' {
			e.append(e.target.test_byte_immediate(register, 2)!)
			e.append(e.target.set_condition(.equal, register)!)
		}
		else {
			e.diagnostics << problem(line, col, 'internal: ${op} is not a comparison a decimal has')
			return error('decimal comparison operator')
		}
	}
	e.append(e.target.widen_byte(register)!)
}

// emit_decimal_compare_routines writes the comparison routines a unit used, and
// no others, behind the functions of the image. It is called once, after the
// functions, so the name a call site wrote finds a label the layout will place.
fn (mut e Emitter) emit_decimal_compare_routines() !void {
	mut wanted := []decimal.Format{}
	for format in [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128] {
		if decimal_compare_name(format) in e.decimal_used {
			wanted << format
		}
	}
	if wanted.len == 0 {
		return
	}
	registers := decimal_registers(e.target) or {
		e.diagnostics << problem(1, 1, 'internal: the target has no register a decimal comparison needs')
		return error('decimal registers')
	}
	mut at := e.program.text.len
	for format in wanted {
		mut r := DecimalRoutine{
			t:      &e.target
			reg:    registers
			labels: map[string]int{}
		}
		e.decimal_compare_routine(mut r, format)!
		bytes := r.resolved()
		e.program.text << bytes
		e.program.labels[decimal_compare_name(format)] = at + r.labels[decimal_compare_name(format)]
		at += bytes.len
	}
}

// decimal_compare_routine writes one width's comparison routine. It saves the
// registers it computes in, opens a frame for the decoded operands, decodes both,
// and orders them. The two operands arrive by address in the first two argument
// registers, and the answer leaves as one of the four order codes in the result
// register.
fn (mut e Emitter) decimal_compare_routine(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	name := decimal_compare_name(format)
	rsp := r.t.reg('rsp') or {
		e.diagnostics << problem(1, 1, 'internal: the target has no stack register a decimal comparison needs')
		return error('no stack register')
	}
	r.place(name)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	r.op(r.t.frame_reserve(u32(decimal_compare_frame)))
	r.move_reg(g.rbx, rsp)!
	r.move_reg(g.r14, g.rdi)!
	r.move_reg(g.r15, g.rsi)!
	e.decimal_compare_decode(mut r, format, g.r14, 0, 'a')!
	e.decimal_compare_decode(mut r, format, g.r15, 40, 'b')!
	e.decimal_compare_order(mut r, format)!
}

// decimal_compare_decode reads one format's operand into the frame block at base.
// The address is in the register named, and the block is the special, the sign,
// the exponent and the two words of the coefficient, in that order. The decode is
// the encoding read off backwards: the five bits below the sign are the special
// markers, the two bits below those say whether the coefficient is in the flat or
// the large form, and the field widths are the format's own.
fn (e Emitter) decimal_compare_decode(mut r DecimalRoutine, format decimal.Format, address backend.Register, base int, tag string) !void {
	g := r.reg
	a_special := 0
	a_sign := 8
	a_exp := 16
	a_lo := 24
	a_hi := 32
	r.move_imm(g.rax, 0)!
	r.store_local(base + a_special, g.rax)!
	match format {
		.decimal32 {
			r.op(r.t.load_indirect(address, g.rax, 4)!)
			r.move_reg(g.r8, g.rax)!
			r.op(r.t.shift_right_word(g.r8, 31)!)
			r.store_local(base + a_sign, g.r8)!
			r.move_reg(g.r9, g.rax)!
			r.op(r.t.shift_right_word(g.r9, 26)!)
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			r.move_reg(g.r10, g.r9)!
			r.op(r.t.add_immediate(g.r10, -30))
			r.branch(.equal, '${tag}_inf')
			r.move_reg(g.r10, g.r9)!
			r.op(r.t.add_immediate(g.r10, -31))
			r.branch(.equal, '${tag}_nan')
			r.move_reg(g.r10, g.rax)!
			r.op(r.t.shift_right_word(g.r10, 29)!)
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.op(r.t.add_immediate(g.r10, -3))
			r.branch(.equal, '${tag}_large')
			r.move_imm(g.r11, 0x7fffff)!
			r.move_reg(g.rdx, g.rax)!
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.store_local(base + a_lo, g.rdx)!
			r.move_imm(g.rdx, 0)!
			r.store_local(base + a_hi, g.rdx)!
			r.move_reg(g.rcx, g.rax)!
			r.op(r.t.shift_right_word(g.rcx, 23)!)
			r.op(r.t.and_immediate(g.rcx, 0xff)!)
			r.op(r.t.add_immediate(g.rcx, -101))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.move_imm(g.r11, 0x1fffff)!
			r.move_reg(g.rdx, g.rax)!
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.move_imm(g.r11, 0x800000)!
			r.op(r.t.or_word(g.rdx, g.r11)!)
			r.store_local(base + a_lo, g.rdx)!
			r.move_imm(g.rdx, 0)!
			r.store_local(base + a_hi, g.rdx)!
			r.move_reg(g.rcx, g.rax)!
			r.op(r.t.shift_right_word(g.rcx, 21)!)
			r.op(r.t.and_immediate(g.rcx, 0xff)!)
			r.op(r.t.add_immediate(g.rcx, -101))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
		}
		.decimal64 {
			r.op(r.t.load_indirect(address, g.rax, 8)!)
			r.move_reg(g.r8, g.rax)!
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.store_local(base + a_sign, g.r8)!
			r.move_reg(g.r9, g.rax)!
			r.op(r.t.shift_right_word(g.r9, 58)!)
			r.op(r.t.and_immediate(g.r9, 0x1f)!)
			r.move_reg(g.r10, g.r9)!
			r.op(r.t.add_immediate(g.r10, -30))
			r.branch(.equal, '${tag}_inf')
			r.move_reg(g.r10, g.r9)!
			r.op(r.t.add_immediate(g.r10, -31))
			r.branch(.equal, '${tag}_nan')
			r.move_reg(g.r10, g.rax)!
			r.op(r.t.shift_right_word(g.r10, 61)!)
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.op(r.t.add_immediate(g.r10, -3))
			r.branch(.equal, '${tag}_large')
			r.move_imm(g.r11, 0x1fffffffffffff)!
			r.move_reg(g.rdx, g.rax)!
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.store_local(base + a_lo, g.rdx)!
			r.move_imm(g.rdx, 0)!
			r.store_local(base + a_hi, g.rdx)!
			r.move_reg(g.rcx, g.rax)!
			r.op(r.t.shift_right_word(g.rcx, 53)!)
			r.op(r.t.and_immediate(g.rcx, 0x3ff)!)
			r.op(r.t.add_immediate(g.rcx, -398))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.move_imm(g.r11, 0x7ffffffffffff)!
			r.move_reg(g.rdx, g.rax)!
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.move_imm(g.r11, 0x20000000000000)!
			r.op(r.t.or_word(g.rdx, g.r11)!)
			r.store_local(base + a_lo, g.rdx)!
			r.move_imm(g.rdx, 0)!
			r.store_local(base + a_hi, g.rdx)!
			r.move_reg(g.rcx, g.rax)!
			r.op(r.t.shift_right_word(g.rcx, 51)!)
			r.op(r.t.and_immediate(g.rcx, 0x3ff)!)
			r.op(r.t.add_immediate(g.rcx, -398))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
		}
		.decimal128 {
			r.op(r.t.load_indirect(address, g.r9, 8)!)
			r.op(r.t.load_slot(address, 8, g.r10, 8)!)
			r.move_reg(g.r8, g.r10)!
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.store_local(base + a_sign, g.r8)!
			r.move_reg(g.r11, g.r10)!
			r.op(r.t.shift_right_word(g.r11, 58)!)
			r.op(r.t.and_immediate(g.r11, 0x1f)!)
			r.move_reg(g.rcx, g.r11)!
			r.op(r.t.add_immediate(g.rcx, -30))
			r.branch(.equal, '${tag}_inf')
			r.move_reg(g.rcx, g.r11)!
			r.op(r.t.add_immediate(g.rcx, -31))
			r.branch(.equal, '${tag}_nan')
			r.move_reg(g.rcx, g.r10)!
			r.op(r.t.shift_right_word(g.rcx, 61)!)
			r.op(r.t.and_immediate(g.rcx, 3)!)
			r.op(r.t.add_immediate(g.rcx, -3))
			r.branch(.equal, '${tag}_large')
			r.move_imm(g.rcx, 0x1ffffffffffff)!
			r.move_reg(g.r11, g.r10)!
			r.op(r.t.and_word(g.r11, g.rcx)!)
			r.store_local(base + a_hi, g.r11)!
			r.store_local(base + a_lo, g.r9)!
			r.move_reg(g.rcx, g.r10)!
			r.op(r.t.shift_right_word(g.rcx, 49)!)
			r.op(r.t.and_immediate(g.rcx, 0x3fff)!)
			r.op(r.t.add_immediate(g.rcx, -6176))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
			r.place('${tag}_large')
			r.move_imm(g.rcx, 0x7fffffffffff)!
			r.move_reg(g.r11, g.r10)!
			r.op(r.t.and_word(g.r11, g.rcx)!)
			r.move_imm(g.rcx, 0x2000000000000)!
			r.op(r.t.or_word(g.r11, g.rcx)!)
			r.store_local(base + a_hi, g.r11)!
			r.store_local(base + a_lo, g.r9)!
			r.move_reg(g.rcx, g.r10)!
			r.op(r.t.shift_right_word(g.rcx, 47)!)
			r.op(r.t.and_immediate(g.rcx, 0x3fff)!)
			r.op(r.t.add_immediate(g.rcx, -6176))
			r.store_local(base + a_exp, g.rcx)!
			r.jump('${tag}_done')
		}
	}
	r.place('${tag}_inf')
	r.move_imm(g.rcx, 1)!
	r.store_local(base + a_special, g.rcx)!
	r.jump('${tag}_done')
	r.place('${tag}_nan')
	r.move_imm(g.rcx, 2)!
	r.store_local(base + a_special, g.rcx)!
	r.place('${tag}_done')
}

// decimal_compare_order writes the part of the routine that turns the two decoded
// operands into an order code.
fn (e Emitter) decimal_compare_order(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	a_special := 0
	a_sign := 8
	a_exp := 16
	a_lo := 24
	a_hi := 32
	b_special := 40
	b_sign := 48
	b_exp := 56
	b_lo := 64
	b_hi := 72
	k_hi, k_lo := decimal_compare_threshold(format)
	// A NaN on either side is unordered, and it is asked first because every other
	// rule would read a coefficient a NaN does not have.
	r.load_local(a_special, g.rax)!
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.equal, 'unordered')
	r.load_local(b_special, g.rax)!
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.equal, 'unordered')
	// An infinity on either side has its own order, and it is asked before the
	// sign because an infinity has no coefficient to compare.
	r.load_local(a_special, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'a_special')
	r.load_local(b_special, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'b_special')
	r.jump('both_finite')
	r.place('a_special')
	r.load_local(b_special, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'both_infinite')
	// The left is infinite and the right is finite, so the sign of the infinity
	// decides.
	r.load_local(a_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'less')
	r.jump('greater')
	r.place('b_special')
	r.load_local(b_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'greater')
	r.jump('less')
	r.place('both_infinite')
	r.load_local(a_sign, g.rax)!
	r.load_local(b_sign, g.rcx)!
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.equal, 'equal')
	r.load_local(a_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'less')
	r.jump('greater')
	r.place('both_finite')
	// A zero is equal to another zero however either is written, so that is asked
	// first: a zero with a power of ten, or with a sign, has other bytes than the
	// plain one and is still the same value.
	r.load_local(a_lo, g.rax)!
	r.load_local(a_hi, g.rcx)!
	r.op(r.t.or_word(g.rax, g.rcx)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'a_nonzero')
	// The left is zero. If the right is too the two are equal; otherwise the zero
	// is greater than a negative right and less than a positive one, which is the
	// right operand's sign and not the zero's own.
	r.load_local(b_lo, g.rax)!
	r.load_local(b_hi, g.rcx)!
	r.op(r.t.or_word(g.rax, g.rcx)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'equal')
	r.load_local(b_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'greater')
	r.jump('less')
	r.place('a_nonzero')
	// The right is zero and the left is not, so the left is greater than zero when
	// it is positive and less than zero when it is negative.
	r.load_local(b_lo, g.rax)!
	r.load_local(b_hi, g.rcx)!
	r.op(r.t.or_word(g.rax, g.rcx)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'both_nonzero')
	r.load_local(a_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'less')
	r.jump('greater')
	r.place('both_nonzero')
	// Neither is zero, so a sign that differs decides.
	r.load_local(a_sign, g.rax)!
	r.load_local(b_sign, g.rcx)!
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.equal, 'same_sign')
	r.load_local(a_sign, g.rax)!
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, 'less')
	r.jump('greater')
	r.place('same_sign')
	// The magnitudes are put on the format's full digit count first, so their
	// exponents order them directly and, when the exponents agree, their
	// coefficients do too.
	e.decimal_compare_normalize(mut r, a_exp, a_lo, a_hi, k_hi, k_lo, 'a')!
	e.decimal_compare_normalize(mut r, b_exp, b_lo, b_hi, k_hi, k_lo, 'b')!
	r.load_local(a_exp, g.rax)!
	r.load_local(b_exp, g.rcx)!
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.greater, 'magnitude_greater')
	r.branch(.less, 'magnitude_less')
	r.load_local(a_hi, g.rax)!
	r.load_local(b_hi, g.rcx)!
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.above, 'magnitude_greater')
	r.branch(.below, 'magnitude_less')
	r.load_local(a_lo, g.rax)!
	r.load_local(b_lo, g.rcx)!
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.above, 'magnitude_greater')
	r.branch(.below, 'magnitude_less')
	r.move_imm(g.rax, decimal_compare_equal)!
	r.jump('sign')
	r.place('magnitude_greater')
	r.move_imm(g.rax, decimal_compare_greater)!
	r.jump('sign')
	r.place('magnitude_less')
	r.move_imm(g.rax, decimal_compare_less)!
	r.jump('sign')
	r.place('sign')
	// A negative makes the greater magnitude the smaller value. The order of the
	// magnitudes is zero, one or two, and swapping one and two is the negation;
	// zero is its own.
	r.load_local(a_sign, g.rcx)!
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.equal, 'finish')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'finish')
	r.move_imm(g.rcx, 3)!
	r.op(r.t.xor_word(g.rax, g.rcx)!)
	r.jump('finish')
	r.place('equal')
	r.move_imm(g.rax, decimal_compare_equal)!
	r.jump('finish')
	r.place('greater')
	r.move_imm(g.rax, decimal_compare_greater)!
	r.jump('finish')
	r.place('less')
	r.move_imm(g.rax, decimal_compare_less)!
	r.jump('finish')
	r.place('unordered')
	r.move_imm(g.rax, decimal_compare_unordered)!
	r.place('finish')
	r.op(r.t.stack_release(u32(decimal_compare_frame)))
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// decimal_compare_normalize scales one operand's coefficient up to the format's
// full digit count, lowering its exponent by however many tens it multiplied in.
// The multiply is repeated until the coefficient reaches the threshold, and the
// two-word form is used for every width so that a decimal128's coefficient fits
// and the narrower widths are the same code with a high word of zero.
fn (e Emitter) decimal_compare_normalize(mut r DecimalRoutine, exponent int, lo int, hi int, k_hi u64, k_lo u64, tag string) !void {
	g := r.reg
	r.place('${tag}_normalize')
	r.load_local(hi, g.rcx)!
	r.load_local(lo, g.rax)!
	r.move_imm(g.r8, k_lo)!
	r.move_imm(g.rdx, k_hi)!
	r.op(r.t.subtract_word(g.rcx, g.rdx)!)
	r.branch(.above, '${tag}_normalized')
	r.branch(.below, '${tag}_multiply')
	r.op(r.t.subtract_word(g.rax, g.r8)!)
	r.branch(.above_or_equal, '${tag}_normalized')
	r.place('${tag}_multiply')
	r.load_local(lo, g.rax)!
	r.move_imm(g.r9, 10)!
	r.op(r.t.multiply_pair(g.r9)!)
	r.load_local(hi, g.rcx)!
	r.op(r.t.imul_immediate(g.rcx, 10))
	r.op(r.t.add_reg64(g.rcx, g.rdx))
	r.store_local(lo, g.rax)!
	r.store_local(hi, g.rcx)!
	r.load_local(exponent, g.rax)!
	r.op(r.t.add_immediate(g.rax, -1))
	r.store_local(exponent, g.rax)!
	r.jump('${tag}_normalize')
	r.place('${tag}_normalized')
}
