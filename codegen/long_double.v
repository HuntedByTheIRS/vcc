module codegen

import abi

// Long double is the target's extended-precision type: eighty significant bits
// held in sixteen bytes of memory, which is the format this machine's x87 stack
// carries. This file is the whole of the type's support in the back end - the
// value of a literal, the storage of an object of the type, and the conversions
// between it and a double - and it is deliberately not the whole of the type.
//
// What is absent is arithmetic, and it is absent on purpose. This back end
// computes in the SSE register file, whose widest format is the double, so an
// operation on two long doubles would have to be computed in a double and stored
// back as though nothing had been lost: a value narrower than the type says it
// is, with no diagnostic, which is the one outcome this compiler treats as a
// bug. Every operation of that kind is refused by name, at the place it is
// written, rather than answered with a wrong value.
//
// A long double value has the shape an aggregate and an array have here: an
// expression of the type is worth the address of its sixteen bytes and not a
// value in a register, because there is no register of that width. So a copy of
// one is a sixteen-byte copy, a read of one is a read through its address, and a
// conversion is a load from the address of the source and a store.
//
// Measured on gcc 16.2.1 on this target: sizeof(long double) and
// _Alignof(long double) are both 16, the ten significant bytes of the value are
// stored least significant first with the sign and exponent word above them, and
// a long double passed to or returned from a function travels by the x87
// convention. The size and the alignment are the model's; the calling convention
// is what the refusals below name.
import ast
import types

const long_double_bytes = 16

// writes_a_long_double says whether a written type spelling is the extended
// type. A pointer to it is a pointer, which type_width already answers for, so
// only the type itself is asked about.
fn (e Emitter) writes_a_long_double(written string) bool {
	return written == 'long double'
}

// long_double_of says whether a value is one of the extended type. It is the
// question every path that would otherwise compute in a double asks, and the
// type the reader resolved onto the expression is the answer.
fn (e Emitter) long_double_of(expr ast.Expr) bool {
	return expr.typ.kind == .long_double
}

// global_is_long_double is the same question about a top-level object. An array
// of them answers no: its name is the address of its first element, and an
// element is read one at a time through that address.
fn (e Emitter) global_is_long_double(name string) bool {
	for global in e.unit.globals {
		if global.name == name {
			return global.count == 0 && e.writes_a_long_double(global.typ)
		}
	}
	return false
}

// global_array_is_long_double is the same question about an array of them at top
// level. Its name is the address of its first element, and an element of it is
// sixteen bytes written through that address, so the size of one element is what
// makes the write the extended type's.
fn (e Emitter) global_array_is_long_double(name string) bool {
	for global in e.unit.globals {
		if global.name == name {
			return global.count > 0 && e.writes_a_long_double(global.typ)
		}
	}
	return false
}

// returns_a_long_double says whether a call hands back a value of the extended
// type: the signature the reader resolved says so, and the spelling a function
// this file declares returns says so where the reader had no signature.
fn (e Emitter) returns_a_long_double(call ast.Call) bool {
	if call.typ.kind == .long_double {
		return true
	}
	return e.returns[call.name] == 'long double'
}

// extended_parameter says whether a call's parameter at `position` is the
// extended type, or none when no declaration answers for that position: a call
// nothing prototypes, or an argument past the parameters a prototype names. The
// argument's own type answers in that case, which is the same fallback
// argument_is_double makes.
fn (e Emitter) extended_parameter(call ast.Call, position int) ?bool {
	if parameter := call_parameter(call, position) {
		return abi.travels_on_the_x87_stack(parameter)
	}
	if extendeds := e.extended_params[call.name] {
		if position < extendeds.len {
			return extendeds[position]
		}
	}
	return none
}

// extended_argument says whether the convention hands argument `position` over
// in memory, which is a parameter of the extended type or, where nothing
// declares it, an argument that is itself a long double. A long double travels
// by the x87 convention and not in the argument register file, so the address
// of its value is not what the callee expects to read and a call has to hand
// over the sixteen bytes themselves.
fn (e Emitter) extended_argument(call ast.Call, position int, arg ast.Expr) bool {
	if known := e.extended_parameter(call, position) {
		return known
	}
	return e.is_extended(arg)
}

// long_double_argument is argument `position` of a call when the convention
// hands it over in memory, or none when it is a value the argument registers
// carry. It is the seam the call's placement reads, so the address of a long
// double's value is never handed over as though it were the value itself.
fn (e Emitter) long_double_argument(call ast.Call, position int, arg ast.Expr) ?ast.Expr {
	if e.extended_argument(call, position, arg) {
		return arg
	}
	return none
}

// is_extended says whether an expression is worth a long double value, which is
// the address of its sixteen bytes. A call whose signature returns one is one
// even where the reader left the call expression's own type unresolved, so the
// question is asked the way returns_a_long_double asks it.
fn (e Emitter) is_extended(expr ast.Expr) bool {
	if expr is ast.Call {
		return e.returns_a_long_double(expr)
	}
	return e.long_double_of(expr)
}

// store_extended_result hands a call that returns a long double to the
// expression around it. The convention leaves the value on the x87 stack and a
// long double value in this back end is the address of its sixteen bytes, so
// the value is written into a frame temporary and that address is what the call
// expression is worth. A call that does not return one leaves the accumulator
// as it found it.
fn (mut e Emitter) store_extended_result(call ast.Call, line int, col int) !void {
	if !e.returns_a_long_double(call) {
		return
	}
	temporary := e.reserve(long_double_bytes)
	base := e.frame_pointer(line, col)!
	register := e.scratch(line, col)!
	e.append(e.target.address_of_slot(base, i32(temporary.offset), register))
	e.append(e.target.store_extended(register)!)
	return e.leave_address(temporary, line, col)
}

// emit_extended_return leaves the value a function returns on the x87 stack,
// which is where the convention hands a long double back. An expression of the
// type is already the address of sixteen bytes, so it is loaded from there; any
// other value is converted into a frame temporary first and loaded from that,
// which is the conversion a return makes when the two classes differ.
fn (mut e Emitter) emit_extended_return(expr ast.Expr, line int, col int) !void {
	if e.is_extended(expr) {
		e.emit_expr(expr)!
		register := e.accumulator(line, col)!
		e.append(e.target.load_extended(register)!)
		e.append(e.target.frame_epilogue())
		return
	}
	temporary := e.reserve(long_double_bytes)
	base := e.frame_pointer(line, col)!
	address := e.value_slot(0)
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(base, i32(temporary.offset), register))
	e.store_accumulator(address, line, col)!
	e.emit_expr(expr)!
	e.convert_value_to_extended(address, expr, line, col)!
	destination := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(base, i32(temporary.offset), destination))
	e.append(e.target.load_extended(destination)!)
	e.append(e.target.frame_epilogue())
}

// word_from_bytes reads eight bytes of an object representation as the machine
// word they are, least significant byte first, which is how this target stores
// a value.
fn word_from_bytes(bytes [16]u8, at int) u64 {
	mut value := u64(0)
	for i := 0; i < 8; i++ {
		value |= u64(bytes[at + i]) << u64(8 * i)
	}
	return value
}

// put_extended_value writes the sixteen bytes of an extended constant into the
// image's writable data, where a top-level object of the type starts out. The
// ten significant bytes are the value and the six above them are the padding
// this target leaves zero.
fn put_extended_value(mut blob []u8, at int, value types.LongDouble) {
	bytes := value.bytes()
	for i := 0; i < long_double_bytes; i++ {
		blob[at + i] = bytes[i]
	}
}

// leave_address leaves the address of a frame slot in the accumulator, which is
// what a value of the extended type is worth.
fn (mut e Emitter) leave_address(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	base := e.frame_pointer(line, col)!
	e.append(e.target.address_of_slot(base, slot.offset, register))
}

// put_extended_bytes writes the sixteen bytes of an extended value into a slot
// of the frame. The machine has no form of a move that takes a floating value in
// the instruction, so the two words go in as immediates.
fn (mut e Emitter) put_extended_bytes(slot Slot, bytes [16]u8, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.move_immediate64(register, word_from_bytes(bytes, 0))!)
	e.append(e.target.store_slot(base, i32(slot.offset), register, 8)!)
	e.append(e.target.move_immediate64(register, word_from_bytes(bytes, 8))!)
	e.append(e.target.store_slot(base, i32(slot.offset + 8), register, 8)!)
}

fn (mut e Emitter) put_extended(slot Slot, value types.LongDouble, line int, col int) !void {
	return e.put_extended_bytes(slot, value.bytes(), line, col)
}

// emit_extended_literal materializes a long double constant into a frame
// temporary and leaves the address of it in the accumulator, which is what a
// value of the type is worth. The bytes are the machine's representation of the
// constant the reader computed, so the value is the reader's and nothing here
// rounds it a second time.
fn (mut e Emitter) emit_extended_literal(expr ast.FloatLit, line int, col int) !void {
	value := expr.long_value or {
		e.diagnostics << problem(line, col, 'internal: a long double literal reached the emitter with no value of the extended type')
		return error('long double literal without a value')
	}
	temporary := e.reserve(long_double_bytes)
	e.put_extended(temporary, value, line, col)!
	return e.leave_address(temporary, line, col)
}

// store_long_double writes a value into the sixteen bytes of an object of the
// extended type. The destination's address is worked out first and parked in a
// value slot, so computing the value cannot lose it, and the value is then
// written by the path that matches what it is: sixteen bytes copied from
// wherever a long double value's address is, or a double, float or integer
// converted by the machine's x87 moves.
fn (mut e Emitter) store_long_double(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	base := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(base, slot.offset, register))
	address := e.value_slot(depth)
	e.store_accumulator(address, line, col)!
	return e.store_long_double_at(address, expr, line, col, depth)
}

fn (mut e Emitter) store_long_double_at(address Slot, expr ast.Expr, line int, col int, depth int) !void {
	if e.is_extended(expr) {
		// A value of the same type is a copy of sixteen bytes, from wherever its
		// address is: a literal materialized into a temporary, or an object the
		// program named, or a call whose sixteen bytes came back on the x87
		// stack and were put in a temporary of their own.
		e.emit_expr_at(expr, depth + 1)!
		source := e.value_slot(depth + 1)
		e.store_accumulator(source, line, col)!
		return e.copy_address_object(source, address, long_double_bytes, line, col)
	}
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a long double, and there is no conversion between them')
		return error('pointer into a long double')
	}
	e.emit_expr_at(expr, depth + 1)!
	return e.convert_value_to_extended(address, expr, line, col)
}

// convert_value_to_extended writes the value just computed for a double, a float
// or an integer into the extended object at the parked address. The machine does
// the conversion on its x87 stack: the value is put back in memory at its own
// width, loaded from there with the instruction for that width, and stored as
// the extended format. A float widens to a double exactly first, so there is one
// path for the two floating types.
//
// An eight-byte unsigned source is refused by name: its values at and above
// 2^63 are the ones the signed load of a word reads as negative, and making the
// conversion right would need a subtraction in the extended format, which is
// the arithmetic this back end does not compute.
fn (mut e Emitter) convert_value_to_extended(address Slot, expr ast.Expr, line int, col int) !void {
	destination := e.scratch(line, col)!
	e.load_argument(address, destination, e.target.word_size, line, col)!
	base := e.frame_pointer(line, col)!
	if e.single_of(expr) || e.double_of(expr) {
		value := e.float_accumulator(line, col)!
		if e.single_of(expr) {
			e.append(e.target.float_to_double(value, value)!)
		}
		temporary := e.reserve(8)
		e.append(e.target.store_double_slot(base, i32(temporary.offset), value)!)
		source := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(base, temporary.offset, source))
		e.append(e.target.load_double_extended(source)!)
		e.append(e.target.store_extended(destination)!)
		return
	}
	width := e.width_of(expr) or {
		e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot size, so it cannot be converted to a long double')
		return error('unknown width')
	}
	if expr.typ.kind.is_unsigned() && width == 8 {
		e.diagnostics << problem(line, col, 'unsupported: an unsigned eight-byte integer holds values at and above 2^63, and converting one to a long double needs a subtraction this back end does not compute')
		return error('unsigned word to a long double')
	}
	// An unsigned value narrower than a word is zero-extended into the whole of
	// the register already, so it is stored and loaded as an eight-byte integer
	// and the sign bit the four-byte load would read is above it.
	eight := width == 8 || expr.typ.kind.is_unsigned()
	integer := e.accumulator(line, col)!
	temporary := e.reserve(8)
	e.append(e.target.store_slot(base, i32(temporary.offset), integer, if eight { 8 } else { 4 })!)
	source := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(base, temporary.offset, source))
	if eight {
		e.append(e.target.load_word_extended(source)!)
	} else {
		e.append(e.target.load_int_extended(source)!)
	}
	e.append(e.target.store_extended(destination)!)
}

// extended_to_double is the conversion out of the extended type and into a
// double, which the machine makes on its stack: the value is loaded from the
// address the expression left in the accumulator and stored back as a double,
// which rounds once, to nearest even, the way the language's conversion does.
fn (mut e Emitter) extended_to_double(expr ast.Expr, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	source := e.accumulator(line, col)!
	e.append(e.target.load_extended(source)!)
	temporary := e.reserve(8)
	destination := e.scratch(line, col)!
	e.append(e.target.address_of_slot(base, temporary.offset, destination))
	e.append(e.target.store_double_extended(destination)!)
	double_register := e.float_accumulator(line, col)!
	e.append(e.target.load_double_indirect(destination, double_register)!)
}

// emit_extended_cast is a conversion *to* the extended type. A source that is
// already one is the same value, so its address is left as it stands; anything
// else is converted into a frame temporary and the address of that is what the
// conversion is worth.
//
// The temporary's address is parked before the source is evaluated, because
// converting it reads the source out of the accumulator - an integer source is
// there, a floating one is in the floating register beside it - and working out
// the address writes the accumulator too. Parking it first is what keeps an
// integer source from being replaced by the address of the destination before
// the conversion sees it.
fn (mut e Emitter) emit_extended_cast(cast ast.Cast, depth int) !void {
	if e.long_double_of(cast.expr) {
		return e.emit_expr_at(cast.expr, depth)
	}
	if e.is_a_pointer(cast.expr) {
		e.diagnostics << problem(cast.line, cast.col, 'unsupported: a pointer is not converted to a long double, and there is no conversion between an address and a floating type')
		return error('pointer to a long double')
	}
	temporary := e.reserve(long_double_bytes)
	base := e.frame_pointer(cast.line, cast.col)!
	address := e.value_slot(depth)
	register := e.accumulator(cast.line, cast.col)!
	e.append(e.target.address_of_slot(base, temporary.offset, register))
	e.store_accumulator(address, cast.line, cast.col)!
	e.emit_expr_at(cast.expr, depth + 1)!
	e.convert_value_to_extended(address, cast.expr, cast.line, cast.col)!
	return e.leave_address(temporary, cast.line, cast.col)
}

// extended_step says whether a binary step is one the x87 stack computes with:
// an arithmetic operation on two long doubles, or the order of them. The other
// operators the language has are not operations the stack gives the type, and
// each of them is refused at its own site by name.
fn (e Emitter) extended_step(step ast.Binary) bool {
	if step.op !in ['+', '-', '*', '/', '==', '!=', '<', '>', '<=', '>='] {
		return false
	}
	return e.is_extended(step.left) || e.is_extended(step.right)
}

// extended_temp computes an expression of the extended type into a frame
// temporary of its own and returns it. A value of the type is the address of its
// sixteen bytes, so an expression that already is one is copied from that
// address; anything else - an int, a float or a double - is converted into the
// temporary, which is the conversion a mixed operation needs on either side.
fn (mut e Emitter) extended_temp(expr ast.Expr, depth int) !Slot {
	temporary := e.reserve(long_double_bytes)
	line := expr_line(expr)
	col := expr_col(expr)
	base := e.frame_pointer(line, col)!
	if e.is_extended(expr) {
		e.emit_expr_at(expr, depth)!
		source := e.reserve(e.target.word_size)
		e.store_accumulator(source, line, col)!
		destination := e.reserve(e.target.word_size)
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(base, i32(temporary.offset), register))
		e.store_accumulator(destination, line, col)!
		e.copy_address_object(source, destination, long_double_bytes, line, col)!
		return temporary
	}
	destination := e.reserve(e.target.word_size)
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(base, i32(temporary.offset), register))
	e.store_accumulator(destination, line, col)!
	e.emit_expr_at(expr, depth + 1)!
	e.convert_value_to_extended(destination, expr, line, col)!
	return temporary
}

// emit_extended_binary writes an arithmetic step on long doubles. The two
// operands are materialized into frame temporaries, left then right, and loaded
// onto the x87 stack in that order, which leaves the right value on top and the
// left one below it - the order gcc 16.2.1 uses at -O0, measured on
// `long double a, b; a - b` as `fldt a; fldt b; fsubrp %st,%st(1)`. The x87
// instruction replaces the pair with the result, which is stored into a
// temporary of its own and left as the address of that.
fn (mut e Emitter) emit_extended_binary(step ast.Binary, depth int) !void {
	if step.op in ['==', '!=', '<', '>', '<=', '>='] {
		return e.emit_extended_comparison(step, depth)
	}
	left := e.extended_temp(step.left, depth + 1)!
	right := e.extended_temp(step.right, depth + 1)!
	base := e.frame_pointer(step.line, step.col)!
	register := e.accumulator(step.line, step.col)!
	e.append(e.target.address_of_slot(base, i32(left.offset), register))
	e.append(e.target.load_extended(register)!)
	e.append(e.target.address_of_slot(base, i32(right.offset), register))
	e.append(e.target.load_extended(register)!)
	e.append(e.target.extended_arithmetic(step.op)!)
	result := e.reserve(long_double_bytes)
	address := e.accumulator(step.line, step.col)!
	e.append(e.target.address_of_slot(base, i32(result.offset), address))
	e.append(e.target.store_extended(address)!)
	return e.leave_address(result, step.line, step.col)
}

// emit_extended_comparison reads the order of two long doubles off the x87 stack
// into a register as zero or one, which is what a comparison of them is worth.
// The encoder reads the flags as the value on top against the one below it, so
// the right value is pushed first and the left second, leaving the left value on
// top; `fcomip` then compares the left against the right and pops the left, and
// `fstp` drops the right, so both are consumed.
fn (mut e Emitter) emit_extended_comparison(step ast.Binary, depth int) !void {
	left := e.extended_temp(step.left, depth + 1)!
	right := e.extended_temp(step.right, depth + 1)!
	base := e.frame_pointer(step.line, step.col)!
	register := e.accumulator(step.line, step.col)!
	e.append(e.target.address_of_slot(base, i32(right.offset), register))
	e.append(e.target.load_extended(register)!)
	e.append(e.target.address_of_slot(base, i32(left.offset), register))
	e.append(e.target.load_extended(register)!)
	scratch := e.scratch(step.line, step.col)!
	e.append(e.target.extended_comparison(step.op, register, scratch)!)
}

// emit_extended_conditional writes `c ? a : b` where the arms have the extended
// type. Each arm leaves the address of its sixteen bytes in the accumulator, so
// the branch machinery carries an address the same way it carries a value in a
// register: only the arm the condition selects is evaluated, and its address is
// what the conditional is worth.
fn (mut e Emitter) emit_extended_conditional(conditional ast.Conditional, depth int) !void {
	e.emit_condition(conditional.cond, depth + 1, conditional.line, conditional.col)!
	else_label := e.label()
	end_label := e.label()
	e.branch(.branch_zero, else_label, conditional.line, conditional.col)!
	then_temp := e.extended_temp(conditional.then_expr, depth + 1)!
	e.leave_address(then_temp, conditional.line, conditional.col)!
	e.jump(end_label)!
	e.place(else_label)
	else_temp := e.extended_temp(conditional.else_expr, depth + 1)!
	e.leave_address(else_temp, conditional.line, conditional.col)!
	e.place(end_label)
}

// refuse_a_long_double_operation reports an operation on a value of the
// extended type that this back end does not compute, naming the operation and
// what is missing rather than answering with a double.
fn (mut e Emitter) refuse_a_long_double_operation(op string, line int, col int) !void {
	e.diagnostics << problem(line, col, 'unsupported: ${op} on a long double is not one this back end computes; the x87 stack gives two long doubles the arithmetic +, -, *, / and the order comparisons ==, !=, <, >, <=, >= and nothing else, and computing it in a double would round away the precision the type is for')
	return error('long double operation')
}

// refuse_a_long_double_conversion reports a conversion out of the extended type
// that this back end does not make. The machine instruction that takes a value
// out of the extended format rounds to nearest even, which is the right answer
// for a conversion to a double and the wrong one for a conversion that truncates
// toward zero, so only the conversion to double is written and every other
// destination is refused by name rather than answered with the instruction's
// rounding.
fn (mut e Emitter) refuse_a_long_double_conversion(target string, line int, col int) !void {
	e.diagnostics << problem(line, col, 'unsupported: a conversion from long double to ${target} is not one this back end makes, and the machine instruction that takes a value out of the extended format is not the truncation the language asks for; only a conversion to double is implemented')
	return error('long double conversion')
}

// deref_extended is a read through an address of the extended type. The value at
// such an address is the object itself, so what the read is worth is the address
// the pointer already holds: loading sixteen bytes into a register is the one
// thing there is no value of that width for.
fn (mut e Emitter) deref_extended(unary ast.Unary, depth int) !void {
	return e.emit_expr_at(unary.expr, depth)
}
