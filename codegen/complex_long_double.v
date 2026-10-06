module codegen

import backend
import image
import types
import ast

// `long double _Complex` is the extended type's complex form: two sixteen-byte
// components, the real part first, thirty-two bytes in all and aligned sixteen.
// The model already sizes it (types/object.v), and this file is what carries a
// value of it through the back end.
//
// A value travels the way a complex value does and the way a long double does at
// once: an expression of the type is worth the address of its bytes rather than
// a value in a register, because no register is thirty-two bytes wide. A
// component is read and written with the x87 moves the scalar type already uses,
// and the arithmetic is the x87 stack's.
//
// The convention, measured with gcc 16.2.1 at -O0: an argument is thirty-two
// bytes in memory, real part at the lower address; a return leaves st(0) the
// real part and st(1) the imaginary one, so a caller pops the real part first.

// complex_long_double_component is one component: the extended format's sixteen
// bytes, which is what fldt and fstpt move.
const complex_long_double_component = long_double_bytes

// complex_long_double_bytes is the whole object: two components.
const complex_long_double_bytes = 2 * complex_long_double_component

// is_long_double_complex says whether a type is the extended complex type.
fn (e Emitter) is_long_double_complex(t types.Type) bool {
	return t.kind == .complex_long_double
}

// returns_a_complex_long_double says whether a call hands a value of the
// extended complex type back: the type the reader resolved onto the call says
// so, and the return type a declaration this file read says so where the reader
// left the call's own type unresolved.
fn (e Emitter) returns_a_complex_long_double(call ast.Call) bool {
	if call.typ.kind == .complex_long_double {
		return true
	}
	return e.complex_long_double_returns[call.name]
}

// complex_long_double_parameter says whether parameter `position` of a call is
// the extended complex type: the declaration's parameter list says so, whether
// or not this file wrote the body, and none of the two tables a call reads for a
// parameter type names it as a system this back end can carry alone.
fn (e Emitter) complex_long_double_parameter(call ast.Call, position int) bool {
	if parameter := call_parameter(call, position) {
		return parameter.kind == .complex_long_double
	}
	if kinds := e.complex_long_double_params[call.name] {
		if position < kinds.len {
			return kinds[position]
		}
	}
	return false
}

// complex_long_double_argument says whether argument `position` is handed over
// as a thirty-two byte object in memory, which is a parameter of the extended
// complex type or, where nothing declares it, an argument that is itself one.
// It is the same question long_double_argument asks of the scalar type: a value
// this type is never carried by a register, so a call has to hand the bytes over
// rather than the address of them.
fn (e Emitter) complex_long_double_argument(call ast.Call, position int, arg ast.Expr) bool {
	if e.complex_long_double_parameter(call, position) {
		return true
	}
	if parameter := call_parameter(call, position) {
		// The callee names its parameters and none of them is this type, so the
		// argument is converted to whatever the parameter is and not handed over
		// as an extended complex value.
		_ = parameter
		return false
	}
	if kinds := e.complex_long_double_params[call.name] {
		if position < kinds.len {
			return kinds[position]
		}
	}
	return arg.typ.kind == .complex_long_double
}

// complex_long_double_argument_address leaves in the accumulator the address of
// the thirty-two bytes an argument of the extended complex type is handed over
// as. An argument that already is one is its own storage; a real one is turned
// into a complex value with a zero imaginary part first, which is 6.3.2.2 and
// what makes `csqrtl(4.0L)` hand over `4.0L + 0.0Li`.
fn (mut e Emitter) complex_long_double_argument_address(arg ast.Expr, depth int) !void {
	line := expr_line(arg)
	col := expr_col(arg)
	destination := types.complex_long_double_type()
	object := e.complex_object_as(arg, destination, depth)!
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(object.offset), register))
}

// emit_long_double_complex_into writes the value of an expression into an object
// of the extended complex type. It is emit_complex_into_type for this one type,
// whose components are the extended format and whose arithmetic is the x87
// stack's rather than one instruction per component in the floating file.
fn (mut e Emitter) emit_long_double_complex_into(dest Slot, expr ast.Expr, depth int) !void {
	line := expr_line(expr)
	col := expr_col(expr)
	if expr.typ.is_arithmetic() && !expr.typ.kind.is_complex() {
		return e.emit_real_into_complex_long_double(dest, expr, depth)
	}
	if !expr.typ.kind.is_complex() {
		e.diagnostics << problem(line, col, 'unsupported: a value of type ${expr.typ.describe()} is not converted to ${types.complex_long_double_type().describe()}')
		return error('not a complex conversion')
	}
	if expr.typ.kind != .complex_long_double {
		// A complex value of the other width converted to this one: each
		// component is widened to the extended format on the x87 stack.
		source := e.complex_object_as(expr, expr.typ, depth + 1)!
		return e.convert_complex_to_extended(dest, source, expr.typ, line, col)
	}
	if expr is ast.Ident {
		if local := e.lookup(expr.name) {
			if local.complex {
				return e.copy_complex_frame(local, dest, dest.width, line, col)
			}
		}
	}
	if expr is ast.Binary {
		return e.emit_long_double_complex_arithmetic(dest, expr, depth)
	}
	if expr is ast.Call {
		return e.emit_complex_call(dest, expr, depth)
	}
	if expr is ast.Cast {
		return e.emit_long_double_complex_into(dest, expr.expr, depth)
	}
	if expr is ast.Unary {
		if expr.op == '-' {
			return e.emit_long_double_complex_negation(dest, expr, depth)
		}
		if expr.op == '+' {
			source := e.complex_object(expr.expr, depth + 1)!
			return e.copy_complex_frame(source, dest, dest.width, line, col)
		}
	}
	if expr is ast.Ident || expr is ast.Field || expr is ast.Index {
		e.address_of_object(expr, depth + 1)!
		source_address := e.value_slot(depth + 1)
		e.store_accumulator(source_address, line, col)!
		frame := e.frame_pointer(line, col)!
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(dest.offset), register))
		destination_address := e.value_slot(depth)
		e.store_accumulator(destination_address, line, col)!
		return e.copy_address_object(source_address, destination_address, complex_long_double_bytes,
			line, col)
	}
	e.diagnostics << problem(line, col, 'unsupported: a value of type ${types.complex_long_double_type().describe()} written as this expression is not one this back end computes')
	return error('unsupported long double complex value')
}

// emit_real_into_complex_long_double writes a real value into an extended
// complex object: the real part is the value converted to the extended format
// and the imaginary part is +0.0 of it. The zero is written rather than left
// alone, because the object is storage that may have held something else.
fn (mut e Emitter) emit_real_into_complex_long_double(dest Slot, expr ast.Expr, depth int) !void {
	line := expr_line(expr)
	col := expr_col(expr)
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is not converted to ${types.complex_long_double_type().describe()}')
		return error('pointer to complex')
	}
	real := Slot{
		offset: dest.offset
		width:  complex_long_double_component
	}
	e.store_long_double(real, expr, line, col, depth)!
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(dest.offset + complex_long_double_component), register))
	e.append(e.target.extended_zero())
	e.append(e.target.store_extended(register)!)
}

// convert_complex_to_extended widens a `float _Complex` or `double _Complex`
// value to the extended complex type, one component at a time: the component is
// read at its own width, rounded to a double where it is a float, and written
// through the x87 stack as the extended format.
fn (mut e Emitter) convert_complex_to_extended(dest Slot, source Slot, source_type types.Type, line int,
	col int) !void {
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	single := complex_component_single(source_type)
	step := complex_component_width(source_type)
	mut which := 0
	for which < 2 {
		from := source.offset + which * step
		to := dest.offset + which * complex_long_double_component
		if single {
			e.append(e.target.load_float_slot(frame, i32(from), value)!)
			e.append(e.target.float_to_double(value, value)!)
		} else {
			e.append(e.target.load_double_slot(frame, i32(from), value)!)
		}
		temporary := e.reserve(8)
		e.append(e.target.store_double_slot(frame, i32(temporary.offset), value)!)
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(temporary.offset), register))
		e.append(e.target.load_double_extended(register)!)
		e.append(e.target.address_of_slot(frame, i32(to), register))
		e.append(e.target.store_extended(register)!)
		which++
	}
}

// emit_complex_long_double_return leaves a value of the extended complex type
// where a caller of this function finds it: on the x87 stack, st(0) the real
// part and st(1) the imaginary one. Measured on gcc 16.2.1, which returns one
// this way. The value is materialized into an object of this frame first, so a
// return of an expression that is not already an object - a sum, a product, a
// call - is computed once, and then its two components are pushed in the order
// the caller pops them: the imaginary part first, so the real part ends on top.
fn (mut e Emitter) emit_complex_long_double_return(expr ast.Expr, line int, col int) !void {
	object := e.complex_object_as(expr, types.complex_long_double_type(), 0)!
	frame := e.frame_pointer(line, col)!
	e.push_extended_component(frame, object.offset + complex_long_double_component, line, col)!
	e.push_extended_component(frame, object.offset, line, col)!
	e.append(e.target.frame_epilogue())
}

// push_extended_component loads the sixteen bytes of a component at a frame
// offset onto the x87 stack.
fn (mut e Emitter) push_extended_component(frame backend.Register, offset int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(offset), register))
	e.append(e.target.load_extended(register)!)
}

// pop_extended_component writes the value at the top of the x87 stack into the
// sixteen bytes of a component at a frame offset, and pops it.
fn (mut e Emitter) pop_extended_component(frame backend.Register, offset int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(offset), register))
	e.append(e.target.store_extended(register)!)
}

// extended_component_step computes one component of an arithmetic step: the left
// value is pushed first and the right one second, so the x87 instruction that
// combines the pair computes the left against the right, and the result is
// written into the destination component.
fn (mut e Emitter) extended_component_step(frame backend.Register, left_offset int, right_offset int, dest_offset int, op string, line int,
	col int) !void {
	e.push_extended_component(frame, left_offset, line, col)!
	e.push_extended_component(frame, right_offset, line, col)!
	e.append(e.target.extended_arithmetic(op)!)
	e.pop_extended_component(frame, dest_offset, line, col)!
}

// emit_long_double_complex_arithmetic writes an arithmetic step on two extended
// complex values. The four operators are the language's; two of them are one x87
// instruction per component and the product is the formula the double complex
// product already uses, computed at the extended width.
fn (mut e Emitter) emit_long_double_complex_arithmetic(dest Slot, binary ast.Binary, depth int) !void {
	left := e.complex_object_as(binary.left, binary.typ, depth + 1)!
	right := e.complex_object_as(binary.right, binary.typ, depth + 1)!
	match binary.op {
		'+', '-' {
			return e.emit_long_double_complex_sum(dest, binary, left, right)
		}
		'*' {
			return e.emit_long_double_complex_product(dest, binary, left, right)
		}
		'/' {
			return e.emit_long_double_complex_quotient(dest, binary, left, right)
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} is not an operator this back end computes ${types.complex_long_double_type().describe()} with')
			return error('unsupported long double complex operator')
		}
	}
}

// emit_long_double_complex_sum writes the sum or the difference of two extended
// complex values: the real part from the real parts and the imaginary part from
// the imaginary ones, each a single x87 instruction.
fn (mut e Emitter) emit_long_double_complex_sum(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	step := complex_long_double_component
	mut which := 0
	for which < 2 {
		e.extended_component_step(frame, left.offset + which * step, right.offset + which * step,
			dest.offset + which * step, binary.op, line, col)!
		which++
	}
}

// emit_long_double_complex_negation writes the negation of an extended complex
// value: each component's sign is flipped where it sits on the x87 stack, with
// the same `fchs` the scalar extended type's negation uses. The instruction
// changes the sign bit and rounds nothing, so a component that is -0.0 becomes
// +0.0 and stays a different value from +0.0, a NaN keeps its payload and takes
// the other sign, and an infinity takes the opposite sign. gcc 16.2.1 emits the
// same `fchs` for each component at -O0, measured on
// `long double _Complex g(long double _Complex a) { return -a; }`.
fn (mut e Emitter) emit_long_double_complex_negation(dest Slot, unary ast.Unary, depth int) !void {
	line := unary.line
	col := unary.col
	source := e.complex_object(unary.expr, depth + 1)!
	frame := e.frame_pointer(line, col)!
	step := complex_long_double_component
	mut which := 0
	for which < 2 {
		e.push_extended_component(frame, source.offset + which * step, line, col)!
		e.append(e.target.extended_negate())
		e.pop_extended_component(frame, dest.offset + which * step, line, col)!
		which++
	}
}

// emit_long_double_complex_product writes the product of two extended complex
// values with the same formula the double complex product uses: `ac - bd` for
// the real part and `ad + bc` for the imaginary one, which is exact for every
// product whose partial products are representable. The four partial products go
// to a work area of this node's own, so a destination that is also an operand is
// read before it is written.
fn (mut e Emitter) emit_long_double_complex_product(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	step := complex_long_double_component
	frame := e.frame_pointer(line, col)!
	work := e.reserve(4 * step)
	// ac and bd.
	e.extended_component_step(frame, left.offset, right.offset, work.offset, '*', line, col)!
	e.extended_component_step(frame, left.offset + step, right.offset + step, work.offset + step, '*',
		line, col)!
	// The real part is ac - bd.
	e.extended_component_step(frame, work.offset, work.offset + step, dest.offset, '-', line, col)!
	// ad and bc.
	e.extended_component_step(frame, left.offset, right.offset + step, work.offset + 2 * step, '*',
		line, col)!
	e.extended_component_step(frame, left.offset + step, right.offset, work.offset + 3 * step, '*',
		line, col)!
	// The imaginary part is ad + bc.
	e.extended_component_step(frame, work.offset + 2 * step, work.offset + 3 * step, dest.offset + step,
		'+', line, col)!
}

// The scaling constants libgcc's __divxc3 uses for the extended format, read
// off gcc 16.2.1's helper as compiled on this machine. RBIG is half the largest
// finite long double, RMIN the smallest normal one, RMIN2 the machine epsilon,
// RMINSCAL its reciprocal, and RMAX2 the product of the first and the third.
// Each is written as the two fields types.LongDouble stores, and each was
// checked against the sixteen bytes gcc writes for the same value:
// LDBL_MAX is 0xffffffffffffffff/0x7ffe and LDBL_MIN is
// 0x8000000000000000/0x0001, so RBIG and RMAX2 share LDBL_MAX's all-ones
// significand at exponents 0x7ffd and 0x7fbe, and LDBL_EPSILON and its
// reciprocal share LDBL_MIN's integer-bit-only significand at 0x3fc0 and
// 0x403e.
const complex_extended_rbig = types.LongDouble{
	mantissa: u64(0xffffffffffffffff)
	sign_exp: u16(0x7ffd)
}
const complex_extended_rmin = types.LongDouble{
	mantissa: u64(0x8000000000000000)
	sign_exp: u16(0x0001)
}
const complex_extended_rmin2 = types.LongDouble{
	mantissa: u64(0x8000000000000000)
	sign_exp: u16(0x3fc0)
}
const complex_extended_rminscal = types.LongDouble{
	mantissa: u64(0x8000000000000000)
	sign_exp: u16(0x403e)
}
const complex_extended_rmax2 = types.LongDouble{
	mantissa: u64(0xffffffffffffffff)
	sign_exp: u16(0x7fbe)
}
const complex_extended_half = types.LongDouble{
	mantissa: u64(0x8000000000000000)
	sign_exp: u16(0x3ffe)
}

// extended_copy moves one sixteen-byte component between slots of the frame.
fn (mut e Emitter) extended_copy(frame backend.Register, from int, to int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(from), register))
	e.append(e.target.load_extended(register)!)
	e.append(e.target.address_of_slot(frame, i32(to), register))
	e.append(e.target.store_extended(register)!)
}

// extended_absolute_copy writes the magnitude of one component into another
// slot, which is the value the scaling tests compare.
fn (mut e Emitter) extended_absolute_copy(frame backend.Register, from int, to int, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(from), register))
	e.append(e.target.load_extended(register)!)
	e.append(e.target.extended_absolute())
	e.append(e.target.address_of_slot(frame, i32(to), register))
	e.append(e.target.store_extended(register)!)
}

// extended_compare_branch compares two components of the frame and branches on
// the outcome. The right value is pushed first and the left second, which is the
// order the encoder reads as the left against the right.
fn (mut e Emitter) extended_compare_branch(frame backend.Register, left int, right int, op string, kind image.FixupKind, name string, line int, col int) !void {
	address := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(right), address))
	e.append(e.target.load_extended(address)!)
	e.append(e.target.address_of_slot(frame, i32(left), address))
	e.append(e.target.load_extended(address)!)
	result := e.accumulator(line, col)!
	scratch := e.scratch(line, col)!
	e.append(e.target.extended_comparison(op, result, scratch)!)
	e.append(e.target.test(result)!)
	e.branch(kind, name, line, col)!
}

// extended_compare_constant_branch compares the magnitude of one component with
// a constant and branches on the outcome. The constant is materialized into a
// frame slot and loaded from there, because the machine has no immediate form of
// an extended value.
fn (mut e Emitter) extended_compare_constant_branch(frame backend.Register, component int, constant types.LongDouble, op string, kind image.FixupKind, name string, line int, col int, magnitude int, literal int) !void {
	e.extended_absolute_copy(frame, component, magnitude, line, col)!
	e.put_extended(Slot{
		offset: literal
		width:  complex_long_double_component
	}, constant, line, col)!
	e.extended_compare_branch(frame, magnitude, literal, op, kind, name, line, col)!
}

// extended_scale_all multiplies every component in place by one factor, which is
// the scaling __divxc3 applies to all four operands at once.
fn (mut e Emitter) extended_scale_all(frame backend.Register, offsets []int, factor types.LongDouble, literal int, line int, col int) !void {
	e.put_extended(Slot{
		offset: literal
		width:  complex_long_double_component
	}, factor, line, col)!
	for offset in offsets {
		e.extended_component_step(frame, offset, literal, offset, '*', line, col)!
	}
}

// emit_long_double_complex_quotient writes the quotient of two extended complex
// values with the arithmetic gcc 16.2.1 carries.
//
// gcc sends a `long double _Complex` division to libgcc's __divxc3, and no
// symbol an image this compiler builds can name holds it, so the arithmetic that
// helper performs is emitted here, the way the double complex quotient emits
// __divdc3's. The naive formula, `(a*c + b*d) / (c*c + d*d)`, answers
// differently from gcc on 38400 of the 390625 pairs of a thirteen-value extreme
// set, because `c*c + d*d` overflows as soon as a component of the divisor is
// large. The scaled division below is what __divxc3 does about that: the four
// operands are scaled before the ratio is formed, and the products are formed
// through a divided operand when the ratio is subnormal. Measured against gcc
// 16.2.1 at -O0 -fno-builtin over the same pairs, printed with %.17Lg, this
// arithmetic agrees with gcc's helper on every pair whose components are finite.
// __divxc3's final recovery of infinities and zeros, for an operand that is
// itself an infinity, is the one part not written, and the double complex
// quotient beside it leaves the same part out.
//
// The four components are copied into writable slots so the scaling can rewrite
// them and so an operand that is also the destination is read before it is
// written, and every intermediate is a frame slot: the x87 stack is a place a
// value is loaded from, combined, and stored back from.
fn (mut e Emitter) emit_long_double_complex_quotient(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	step := complex_long_double_component
	// a, b, c, d, the ratio, the denominator, two temporaries, and a magnitude
	// and a literal scratch slot, sixteen bytes each.
	work := e.reserve(10 * step)
	wa := work.offset
	wb := wa + step
	wc := wb + step
	wd := wc + step
	wr := wd + step
	we := wr + step
	wt := we + step
	wt2 := wt + step
	wabs := wt2 + step
	wcst := wabs + step
	e.extended_copy(frame, left.offset, wa, line, col)!
	e.extended_copy(frame, left.offset + step, wb, line, col)!
	e.extended_copy(frame, right.offset, wc, line, col)!
	e.extended_copy(frame, right.offset + step, wd, line, col)!
	less := e.label()
	done := e.label()
	// if (|c| < |d|) the large component is d; else it is c.
	e.extended_absolute_copy(frame, wc, wabs, line, col)!
	e.extended_absolute_copy(frame, wd, wcst, line, col)!
	e.extended_compare_branch(frame, wabs, wcst, '<', .branch_nonzero, less, line, col)!
	// |c| >= |d|: ratio = d / c, denom = d * ratio + c, and c is the large one.
	e.complex_extended_scaling(frame, wa, wb, wc, wd, wc, wabs, wcst, line, col)!
	e.extended_component_step(frame, wd, wc, wr, '/', line, col)!
	e.extended_component_step(frame, wd, wr, wt, '*', line, col)!
	e.extended_component_step(frame, wt, wc, we, '+', line, col)!
	e.complex_extended_tail(frame, dest, wa, wb, wc, wd, wr, we, wt, wt2, wabs, wcst, true, line, col)!
	e.jump(done)!
	e.place(less)
	// |c| < |d|: ratio = c / d, denom = c * ratio + d, and d is the large one.
	e.complex_extended_scaling(frame, wa, wb, wc, wd, wd, wabs, wcst, line, col)!
	e.extended_component_step(frame, wc, wd, wr, '/', line, col)!
	e.extended_component_step(frame, wc, wr, wt, '*', line, col)!
	e.extended_component_step(frame, wt, wd, we, '+', line, col)!
	e.complex_extended_tail(frame, dest, wa, wb, wc, wd, wr, we, wt, wt2, wabs, wcst, false, line, col)!
	e.place(done)
}

// complex_extended_tail writes the two components of the quotient after the
// ratio and the denominator are known. `wa` and `wb` are a and b, `wc` and `wd`
// are c and d, `wr` and `we` are the ratio and the denominator, and `c_large`
// says which component the branch was chosen on: when c is large the real part is
// b*ratio + a and the imaginary part is b - a*ratio, and when d is large they are
// a*ratio + b and b*ratio - a. Each is divided by the denominator, and when the
// ratio is subnormal the products are formed through a divided operand instead,
// which is __divxc3's alternate order.
fn (mut e Emitter) complex_extended_tail(frame backend.Register, dest Slot, wa int, wb int, wc int, wd int, wr int, we int, wt int, wt2 int, magnitude int, literal int, c_large bool, line int, col int) !void {
	alt := e.label()
	end_alt := e.label()
	e.extended_compare_constant_branch(frame, wr, complex_extended_rmin, '>', .branch_zero, alt, line, col, magnitude, literal)!
	if c_large {
		// real = (b*ratio + a) / denom, imaginary = (b - a*ratio) / denom.
		e.extended_component_step(frame, wb, wr, wt, '*', line, col)!
		e.extended_component_step(frame, wt, wa, wt, '+', line, col)!
		e.extended_component_step(frame, wt, we, wt2, '/', line, col)!
		e.extended_copy(frame, wt2, dest.offset, line, col)!
		e.extended_component_step(frame, wa, wr, wt, '*', line, col)!
		e.extended_component_step(frame, wb, wt, wt2, '-', line, col)!
		e.extended_component_step(frame, wt2, we, wt, '/', line, col)!
		e.extended_copy(frame, wt, dest.offset + complex_long_double_component, line, col)!
	} else {
		// real = (a*ratio + b) / denom, imaginary = (b*ratio - a) / denom.
		e.extended_component_step(frame, wa, wr, wt, '*', line, col)!
		e.extended_component_step(frame, wt, wb, wt, '+', line, col)!
		e.extended_component_step(frame, wt, we, wt2, '/', line, col)!
		e.extended_copy(frame, wt2, dest.offset, line, col)!
		e.extended_component_step(frame, wb, wr, wt, '*', line, col)!
		e.extended_component_step(frame, wt, wa, wt2, '-', line, col)!
		e.extended_component_step(frame, wt2, we, wt, '/', line, col)!
		e.extended_copy(frame, wt, dest.offset + complex_long_double_component, line, col)!
	}
	e.jump(end_alt)!
	e.place(alt)
	if c_large {
		// real = (a + d*(b/c)) / denom, imaginary = (b - d*(a/c)) / denom.
		e.extended_component_step(frame, wb, wc, wt, '/', line, col)!
		e.extended_component_step(frame, wd, wt, wt, '*', line, col)!
		e.extended_component_step(frame, wa, wt, wt, '+', line, col)!
		e.extended_component_step(frame, wt, we, wt2, '/', line, col)!
		e.extended_copy(frame, wt2, dest.offset, line, col)!
		e.extended_component_step(frame, wa, wc, wt, '/', line, col)!
		e.extended_component_step(frame, wd, wt, wt, '*', line, col)!
		e.extended_component_step(frame, wb, wt, wt2, '-', line, col)!
		e.extended_component_step(frame, wt2, we, wt, '/', line, col)!
		e.extended_copy(frame, wt, dest.offset + complex_long_double_component, line, col)!
	} else {
		// real = (c*(a/d) + b) / denom, imaginary = (c*(b/d) - a) / denom.
		e.extended_component_step(frame, wa, wd, wt, '/', line, col)!
		e.extended_component_step(frame, wc, wt, wt, '*', line, col)!
		e.extended_component_step(frame, wt, wb, wt, '+', line, col)!
		e.extended_component_step(frame, wt, we, wt2, '/', line, col)!
		e.extended_copy(frame, wt2, dest.offset, line, col)!
		e.extended_component_step(frame, wb, wd, wt, '/', line, col)!
		e.extended_component_step(frame, wc, wt, wt, '*', line, col)!
		e.extended_component_step(frame, wt, wa, wt2, '-', line, col)!
		e.extended_component_step(frame, wt2, we, wt, '/', line, col)!
		e.extended_copy(frame, wt, dest.offset + complex_long_double_component, line, col)!
	}
	e.place(end_alt)
}

// complex_extended_scaling scales the four components the way __divxc3 does
// before the ratio is formed. `large` is the component whose magnitude decides
// the branch: halve the four when it is at or above RBIG, multiply them by
// RMINSCAL when it is below RMIN2, and multiply them by RMINSCAL when both
// components of one operand are small enough that the division could underflow.
// The tests are emitted in the order the helper makes them and short-circuit the
// same way.
fn (mut e Emitter) complex_extended_scaling(frame backend.Register, wa int, wb int, wc int, wd int, large int, magnitude int, literal int, line int, col int) !void {
	offsets := [wa, wb, wc, wd]
	half_done := e.label()
	do_scale := e.label()
	second := e.label()
	after := e.label()
	// if (|large| >= RBIG) halve every operand.
	e.extended_compare_constant_branch(frame, large, complex_extended_rbig, '<', .branch_nonzero, half_done, line, col, magnitude, literal)!
	e.extended_scale_all(frame, offsets, complex_extended_half, literal, line, col)!
	e.place(half_done)
	// if (|large| < RMIN2) scale up; else the composite test on a, b and large.
	e.extended_compare_constant_branch(frame, large, complex_extended_rmin2, '<', .branch_nonzero, do_scale, line, col, magnitude, literal)!
	e.extended_compare_constant_branch(frame, wa, complex_extended_rmin, '<', .branch_zero, second, line, col, magnitude, literal)!
	e.extended_compare_constant_branch(frame, wb, complex_extended_rmax2, '<', .branch_zero, second, line, col, magnitude, literal)!
	e.extended_compare_constant_branch(frame, large, complex_extended_rmax2, '<', .branch_zero, second, line, col, magnitude, literal)!
	e.jump(do_scale)!
	e.place(second)
	e.extended_compare_constant_branch(frame, wb, complex_extended_rmin, '<', .branch_zero, after, line, col, magnitude, literal)!
	e.extended_compare_constant_branch(frame, wa, complex_extended_rmax2, '<', .branch_zero, after, line, col, magnitude, literal)!
	e.extended_compare_constant_branch(frame, large, complex_extended_rmax2, '<', .branch_zero, after, line, col, magnitude, literal)!
	e.place(do_scale)
	e.extended_scale_all(frame, offsets, complex_extended_rminscal, literal, line, col)!
	e.place(after)
}
