// Decimal values through the emitter.
//
// A decimal object is bytes in memory, and the two things a program does with
// one that this file is about are read those bytes as a value and hand that
// value somewhere. gcc 16.2.1's convention, measured, is that a decimal value
// travels in the floating-point register file: a _Decimal32 or a _Decimal64 in
// the low half of one xmm register and a _Decimal128 across the xmm0:xmm1 pair,
// with nothing on the stack for the arguments a register file has room for. A
// struct containing one follows the ordinary aggregate rules, and the eightbyte
// that covers a decimal is a floating-point one, the same class an eightbyte of
// doubles has.
//
// The value the emitter keeps in flight is therefore the bytes read into the
// floating accumulator, xmm0 for the two narrow formats and xmm0:xmm1 for the
// wide one. Every operation here is a load of those bytes from an address or a
// store of them to one; nothing computes with a decimal, which is the work of
// the conversion routine beside this file and of the arithmetic that is still
// refused by name.
module codegen

import ast
import backend
import image
import types

// decimal_width_of is the size of the format a decimal type names, which is the
// width a value of it travels at and the width the object's bytes are.
fn decimal_width_of(typ types.Type) int {
	return typ.kind.decimal_format().bytes()
}

// returning_decimal says the function being emitted hands a decimal value back,
// which is the question a return statement asks of the declaration rather than
// reading the value's own type: a return converts its expression to the
// function's return type.
fn (e Emitter) returning_decimal() bool {
	return e.decimal_format_of(e.returning) != none
}

// type_contains_decimal says whether an object of a type has a decimal member
// anywhere inside it. It is what tells a small floating-class struct apart from
// one that is not this back end's to hand back: the class of an eightbyte does
// not remember which floating type covered it, and a struct of one _Decimal32 is
// four bytes in the floating class exactly as a struct of one float is. Measured
// on gcc 16.2.1, which returns both in the low half of xmm0.
fn (e Emitter) type_contains_decimal(typ types.Type) bool {
	if typ.kind.is_decimal() {
		return true
	}
	if typ.kind in [types.Kind.struct_, .union_] {
		for member in typ.members {
			if e.type_contains_decimal(member.typ) {
				return true
			}
		}
		return false
	}
	if typ.kind == .array {
		if element := typ.element() {
			return e.type_contains_decimal(element)
		}
	}
	return false
}

// decimal_word_key is the name one eight-byte word of a decimal constant is
// interned under in the image's read-only data. The bytes are part of the key so
// that two words with the same content are one entry and two with different
// content are not, and the `dec` prefix keeps the key apart from the one a real
// double is interned under.
fn decimal_word_key(bytes []u8) string {
	mut text := 'dec'
	for byte in bytes {
		text += ':${byte}'
	}
	return text
}

// intern_decimal_word puts eight bytes of a decimal constant into the image's
// read-only data once and answers nothing. It is intern_double for bytes that
// are not a double: the encoding's own bytes go in, and the instruction that
// reads them reads them the way gcc's own image holds them.
fn (mut e Emitter) intern_decimal_word(key string, bytes []u8) {
	if key in e.program.doubles {
		return
	}
	e.program.doubles[key] = e.program.string_blob.len
	for byte in bytes {
		e.program.string_blob << byte
	}
}

// load_decimal_at reads a decimal value of `width` bytes through an address
// register and a displacement into the decimal accumulator. Eight bytes move
// with the instruction that moves a double, four with the one that moves a
// float, and sixteen is two words read into xmm0 and xmm1, the pair gcc hands a
// _Decimal128 over in.
fn (mut e Emitter) load_decimal_at(address backend.Register, disp int, width int, line int, col int) !void {
	low := e.float_accumulator(line, col)!
	match width {
		4 {
			e.append(e.target.load_float_slot(address, i32(disp), low)!)
		}
		8 {
			e.append(e.target.load_double_slot(address, i32(disp), low)!)
		}
		else {
			high := e.float_scratch(line, col)!
			e.append(e.target.load_double_slot(address, i32(disp), low)!)
			e.append(e.target.load_double_slot(address, i32(disp) + 8, high)!)
		}
	}
}

// store_decimal_at writes the decimal accumulator through an address register
// and a displacement. It is the same three widths as load_decimal_at, and the
// sixteen-byte case stores both words of the pair.
fn (mut e Emitter) store_decimal_at(address backend.Register, disp int, width int, line int, col int) !void {
	low := e.float_accumulator(line, col)!
	match width {
		4 {
			e.append(e.target.store_float_slot(address, i32(disp), low)!)
		}
		8 {
			e.append(e.target.store_double_slot(address, i32(disp), low)!)
		}
		else {
			high := e.float_scratch(line, col)!
			e.append(e.target.store_double_slot(address, i32(disp), low)!)
			e.append(e.target.store_double_slot(address, i32(disp) + 8, high)!)
		}
	}
}

// load_decimal_slot reads a decimal object's value out of its own frame slot.
// A captured slot is read from the chain pointer the way every other slot is,
// which slot_base_register answers.
fn (mut e Emitter) load_decimal_slot(slot Slot, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.load_decimal_at(base, slot.offset, slot.width, line, col)!
}

// store_decimal_slot_value writes the decimal accumulator into a frame slot at
// the object's own width.
fn (mut e Emitter) store_decimal_slot_value(slot Slot, width int, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.store_decimal_at(base, slot.offset, width, line, col)!
}

// emit_decimal_constant materializes a decimal constant as a value: the bytes
// the encoding gives it are read out of the image into the decimal accumulator.
// A sixteen-byte constant is two consecutive eight-byte entries, one per word of
// the pair, because each instruction that reads one names a whole entry.
fn (mut e Emitter) emit_decimal_constant(expr ast.FloatLit, line int, col int) !void {
	bytes := decimal_constant_bytes(expr) or {
		e.diagnostics << problem(line, col, 'unsupported: the decimal constant ${expr.text} is a ${expr.typ.describe()} this back end cannot materialize as a value')
		return error('decimal constant')
	}
	low := e.float_accumulator(line, col)!
	match bytes.len {
		4 {
			key := decimal_word_key(bytes)
			e.intern_decimal_word(key, bytes)
			e.reference(e.target.load_float_constant(low, 0)!, image.FixupKind.single_constant,
				key, e.target.name_of(low))
		}
		8 {
			key := decimal_word_key(bytes)
			e.intern_decimal_word(key, bytes)
			e.reference(e.target.load_double_constant(low, 0)!, image.FixupKind.float_constant,
				key, e.target.name_of(low))
		}
		16 {
			low_key := decimal_word_key(bytes[0..8])
			high_key := decimal_word_key(bytes[8..16])
			e.intern_decimal_word(low_key, bytes[0..8])
			e.intern_decimal_word(high_key, bytes[8..16])
			e.reference(e.target.load_double_constant(low, 0)!, image.FixupKind.float_constant,
				low_key, e.target.name_of(low))
			high := e.float_scratch(line, col)!
			e.reference(e.target.load_double_constant(high, 0)!, image.FixupKind.float_constant,
				high_key, e.target.name_of(high))
		}
		else {
			e.diagnostics << problem(line, col, 'internal: a decimal constant of ${bytes.len} bytes')
			return error('decimal constant width')
		}
	}
}

// store_decimal_value writes a decimal value into an object of a decimal type.
// A constant goes in as the bytes the encoding gives it, which is what gcc
// stores; anything else has to be a value of the same decimal type, read into
// the floating accumulator and stored at the object's own width.
fn (mut e Emitter) store_decimal_value(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	if bytes := decimal_constant_bytes(expr) {
		if bytes.len == slot.width {
			return e.put_decimal_bytes(slot, bytes, line, col)
		}
	}
	if !expr.typ.kind.is_decimal() {
		name := expr.typ.describe()
		e.diagnostics << problem(line, col, 'unsupported: an object of a decimal type is initialized here, and only a constant of its own width or a value of the same decimal type belongs in one; this back end has no form for a ${name} initializer')
		return error('decimal initializer')
	}
	if decimal_width_of(expr.typ) != slot.width {
		e.diagnostics << problem(line, col, 'unsupported: a value of ${expr.typ.describe()} is stored in an object of a different decimal width')
		return error('decimal width mismatch')
	}
	e.emit_expr_at(expr, depth + 1)!
	e.store_decimal_slot_value(slot, slot.width, line, col)!
}

// assign_decimal_local is the store half of an assignment to a decimal object:
// a constant goes in as its encoded bytes and a value of the same type is read
// into the floating accumulator and stored.
fn (mut e Emitter) assign_decimal_local(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	return e.store_decimal_value(slot, expr, line, col, depth)
}

// decimal_argument_width is the width a decimal argument is passed at, or none
// for an argument that is not one. A prototyped call says so parameter by
// parameter, whether or not this file writes the body; a call whose parameter
// position is past the prototype's named parameters is a variadic one, and there
// the argument's own type is the answer because no default argument promotion
// applies to a decimal (measured on gcc 16.2.1, which passes the raw payload).
fn (e Emitter) decimal_argument_width(call ast.Call, position int, arg ast.Expr) ?int {
	if call.callee != none {
		if parameter := call_parameter(call, position) {
			if parameter.kind.is_decimal() {
				return decimal_width_of(parameter)
			}
			return none
		}
	} else if widths := e.decimal_params[call.name] {
		if position < widths.len {
			if widths[position] > 0 {
				return widths[position]
			}
			return none
		}
	}
	if arg.typ.kind.is_decimal() {
		return decimal_width_of(arg.typ)
	}
	return none
}

// store_decimal_through_address writes a decimal value to an address the caller
// has already parked: the address is read into a register, the value is read
// into the decimal accumulator, and its bytes are stored through the address.
// The value has to be of the object's own decimal width, so a store of some
// other type is refused by name rather than written with the bits of whatever
// the accumulator held.
fn (mut e Emitter) store_decimal_through_address(address Slot, expr ast.Expr, width int, line int, col int, depth int) !void {
	if !expr.typ.kind.is_decimal() {
		e.diagnostics << problem(line, col, 'unsupported: a ${expr.typ.describe()} is stored in a decimal object, and this back end has no conversion from it')
		return error('decimal store')
	}
	if decimal_width_of(expr.typ) != width {
		e.diagnostics << problem(line, col, 'unsupported: a value of ${expr.typ.describe()} is stored in a decimal object of a different width')
		return error('decimal store width')
	}
	e.emit_expr_at(expr, depth + 1)!
	address_register := e.scratch(line, col)!
	e.load_argument(address, address_register, e.target.word_size, line, col)!
	e.store_decimal_at(address_register, 0, width, line, col)!
}

// store_decimal_accumulator_into writes the decimal accumulator into a frame
// slot that a call parked it in. The slot is sixteen bytes in all, so the wide
// case has room for the pair.
fn (mut e Emitter) store_decimal_accumulator_into(slot Slot, width int, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.store_decimal_at(base, slot.offset, width, line, col)!
}

// load_decimal_from_slot_into_registers reads a parked decimal argument out of
// its slot into the floating-point argument registers its position names: one
// register for the two narrow formats and the two-register pair for the wide
// one.
fn (mut e Emitter) load_decimal_from_slot_into_registers(slot Slot, position int, width int, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	low := e.target.float_arg_reg(position) or {
		e.diagnostics << problem(line, col, 'internal: the floating-point argument register a decimal is handed over in is not in the machine table')
		return error('no floating argument register')
	}
	match width {
		4 {
			e.append(e.target.load_float_slot(base, i32(slot.offset), low)!)
		}
		8 {
			e.append(e.target.load_double_slot(base, i32(slot.offset), low)!)
		}
		else {
			high := e.target.float_arg_reg(position + 1) or {
				e.diagnostics << problem(line, col, 'internal: the second floating-point argument register a _Decimal128 is handed over in is not in the machine table')
				return error('no second floating argument register')
			}
			e.append(e.target.load_double_slot(base, i32(slot.offset), low)!)
			e.append(e.target.load_double_slot(base, i32(slot.offset) + 8, high)!)
		}
	}
}

// push_decimal_argument puts a parked decimal argument on the stack, which is
// where it goes when the floating-point argument registers have run out. The
// words are pushed from the last to the first, so the low word ends at the lower
// address the callee reads first.
fn (mut e Emitter) push_decimal_argument(slot Slot, width int, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	word := e.target.word_size
	mut words := 1
	if width == 16 {
		words = 2
	}
	mut k := words - 1
	for k >= 0 {
		register := e.accumulator(line, col)!
		e.append(e.target.load_slot(base, i32(slot.offset + k * word), register, word)!)
		e.append(e.target.push_register(register))
		e.stack_pushed += word
		k--
	}
}
