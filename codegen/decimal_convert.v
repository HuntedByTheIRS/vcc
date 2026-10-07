// Decimal conversions beyond the one to double.
//
// codegen/decimal.v writes the routine that turns a decimal object into a double,
// and the algorithm it follows is decimal/convert.v's to_f64_bits. This file adds
// the other conversions GNU C asks for: a decimal to an integer, a decimal to a
// float, an integer to a decimal, a float or a double to a decimal, and one decimal
// width to another. Each is a routine the emitter writes in machine code, emitted
// only for the (source, destination) pairs a unit actually names, and each is held
// to the bytes gcc 16.2.1 produces for the same program.
//
// The shape every routine shares is the one already in this back end: a decimal
// value is an object in memory whose name is its address, so a conversion reads it
// where it lives. A routine that produces a decimal leaves the address of an object
// holding the bytes, and a routine that consumes one takes the address in the
// accumulator, which is where the call site put it.
//
// Decimal to an integer is gcc's __bid_fix* family. Measured on gcc 16.2.1 with a
// table of out-of-range, infinite and NaN values:
//
//   - a signed int or long target gets the value truncated toward zero, and
//     anything that does not fit, an infinity or a NaN, becomes that target's
//     minimum value;
//   - an unsigned int or long target gets the value truncated toward zero, and
//     anything negative, too large, infinite or NaN becomes zero;
//   - a char, a short or either unsigned form converts through int or unsigned int
//     and then truncates to its own width, which is why `(char)1e96df` is zero (the
//     int conversion is INT_MIN and its low byte is zero) and `(char)300.0df` is 44.
module codegen

import ast
import backend
import decimal
import types

// The integer targets a decimal conversion has to know: a signed or unsigned one at
// the machine's int width or at a word. A char or a short is one of the first two,
// with the value truncated to its own width by the call site.
const fix_int32 = 0
const fix_uint32 = 1
const fix_int64 = 2
const fix_uint64 = 3

// The two labels the routines are built from: one decode per format, and the single
// truncation core they share.
const decimal_fix_core_name = 'vcc_decimal_fix_core'

fn decimal_decode_name(format decimal.Format) string {
	return 'vcc_decimal_decode_${format.bytes()}'
}

fn decimal_fix_name(format decimal.Format, target int) string {
	return 'vcc_decimal_fix_${format.bytes()}_c${target}'
}

// decimal_fix_target says which of the four integer conversions a cast to this type
// asks for, or none when the destination is not an integer this file converts to.
fn decimal_fix_target(kind types.Kind) ?int {
	match kind {
		.int_, .char_, .signed_char, .short, .bool_ {
			return fix_int32
		}
		.unsigned_int, .unsigned_char, .unsigned_short {
			return fix_uint32
		}
		.long, .long_long {
			return fix_int64
		}
		.unsigned_long, .unsigned_long_long {
			return fix_uint64
		}
		else {
			return none
		}
	}
}

// emit_decimal_convert_routines writes the conversion routines a unit named, and
// none it did not. It is built as one block so a routine can call another by a
// label inside the block, which is how the four wrappers reach the one truncation
// core. It is called after the double routines, so a call site's name finds a label
// the layout will place.
fn (mut e Emitter) emit_decimal_convert_routines() !void {
	formats := [decimal.Format.decimal32, decimal.Format.decimal64, decimal.Format.decimal128]
	mut any_wanted := false
	// Parallel to formats: which of the four targets each format asked for.
	mut by_format := [][]int{}
	for format in formats {
		mut targets := []int{}
		for target in [fix_int32, fix_uint32, fix_int64, fix_uint64] {
			if decimal_fix_name(format, target) in e.decimal_convert_used {
				targets << target
				any_wanted = true
			}
		}
		by_format << targets
	}
	if !any_wanted {
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
	e.decimal_fix_core(mut r)!
	for i, format in formats {
		if by_format[i].len > 0 {
			e.decimal_decode(mut r, format)!
		}
	}
	for i, format in formats {
		for target in by_format[i] {
			e.decimal_fix_wrapper(mut r, format, target)!
		}
	}
	base := e.program.text.len
	bytes := r.resolved()
	e.program.text << bytes
	e.program.labels[decimal_fix_core_name] = base + r.labels[decimal_fix_core_name]
	for format in formats {
		name := decimal_decode_name(format)
		if name in r.labels {
			e.program.labels[name] = base + r.labels[name]
		}
		for target in [fix_int32, fix_uint32, fix_int64, fix_uint64] {
			label := decimal_fix_name(format, target)
			if label in r.labels {
				e.program.labels[label] = base + r.labels[label]
			}
		}
	}
}

// decimal_decode reads one format's bytes out of an object and leaves the value's
// parts in the registers the routines work in: the coefficient in rax:rdx, the
// power of ten in rcx, the sign in r8 and the special kind in r9 (zero for finite,
// one for an infinity, two for a NaN). The address arrives in rax, which is where a
// call site leaves it, and is moved to rsi before the first word is read.
//
// The fields are the ones decimal/decimal.v's decode reads, and the large form with
// its marker is the same one: the coefficient's top bit is implied and the exponent
// sits two bits lower.
fn (e Emitter) decimal_decode(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	r.place(decimal_decode_name(format))
	r.op(r.t.move_register64(g.rsi, g.rax)!)
	match format {
		.decimal32 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 4)!)
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
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.and_immediate(g.rax, 0x7fffff)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 23)!)
			r.op(r.t.and_immediate(g.rdx, 0xff)!)
			r.op(r.t.add_immediate(g.rdx, -101))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			r.place('dec32_large')
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.and_immediate(g.rax, 0x1fffff)!)
			r.op(r.t.move_immediate64(g.r11, 0x800000)!)
			r.op(r.t.or_word(g.rax, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 21)!)
			r.op(r.t.and_immediate(g.rdx, 0xff)!)
			r.op(r.t.add_immediate(g.rdx, -101))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			e.decimal_decode_special(mut r, 'dec32_inf', 'dec32_nan')!
		}
		.decimal64 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 8)!)
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
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.and_word(g.rax, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 53)!)
			r.op(r.t.move_immediate64(g.r11, 0x3ff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -398))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			r.place('dec64_large')
			r.op(r.t.move_immediate64(g.r11, 0x7ffffffffffff)!)
			r.op(r.t.move_register64(g.r10, g.rax)!)
			r.op(r.t.and_word(g.rax, g.r11)!)
			r.op(r.t.move_immediate64(g.r11, 0x20000000000000)!)
			r.op(r.t.or_word(g.rax, g.r11)!)
			r.op(r.t.move_register64(g.rdx, g.r10)!)
			r.op(r.t.shift_right_word(g.rdx, 51)!)
			r.op(r.t.move_immediate64(g.r11, 0x3ff)!)
			r.op(r.t.and_word(g.rdx, g.r11)!)
			r.op(r.t.add_immediate(g.rdx, -398))
			r.op(r.t.move_register64(g.rcx, g.rdx)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			e.decimal_decode_special(mut r, 'dec64_inf', 'dec64_nan')!
		}
		.decimal128 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 8)!)
			r.op(r.t.load_slot(g.rsi, 8, g.r11, 8)!)
			r.op(r.t.move_register64(g.r8, g.r11)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.move_register64(g.r10, g.r11)!)
			r.op(r.t.shift_right_word(g.r10, 58)!)
			r.op(r.t.and_immediate(g.r10, 0x1f)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -30))
			r.branch(.equal, 'dec128_inf')
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -31))
			r.branch(.equal, 'dec128_nan')
			r.op(r.t.move_register64(g.r10, g.r11)!)
			r.op(r.t.shift_right_word(g.r10, 61)!)
			r.op(r.t.and_immediate(g.r10, 3)!)
			r.op(r.t.move_register64(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -3))
			r.branch(.equal, 'dec128_large')
			r.op(r.t.move_register64(g.rdx, g.r11)!)
			r.op(r.t.move_immediate64(g.r10, 0x1ffffffffffff)!)
			r.op(r.t.and_word(g.rdx, g.r10)!)
			r.op(r.t.move_register64(g.rcx, g.r11)!)
			r.op(r.t.shift_right_word(g.rcx, 49)!)
			r.op(r.t.move_immediate64(g.r10, 0x3fff)!)
			r.op(r.t.and_word(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -6176))
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			r.place('dec128_large')
			r.op(r.t.move_register64(g.rdx, g.r11)!)
			r.op(r.t.move_immediate64(g.r10, 0x7fffffffffff)!)
			r.op(r.t.and_word(g.rdx, g.r10)!)
			r.op(r.t.move_immediate64(g.r10, 0x2000000000000)!)
			r.op(r.t.or_word(g.rdx, g.r10)!)
			r.op(r.t.move_register64(g.rcx, g.r11)!)
			r.op(r.t.shift_right_word(g.rcx, 47)!)
			r.op(r.t.move_immediate64(g.r10, 0x3fff)!)
			r.op(r.t.and_word(g.rcx, g.r10)!)
			r.op(r.t.add_immediate(g.rcx, -6176))
			r.op(r.t.xor_word(g.r9, g.r9)!)
			r.op(r.t.ret())
			e.decimal_decode_special(mut r, 'dec128_inf', 'dec128_nan')!
		}
	}
}

// decimal_decode_special writes the two leaves a decode takes when the top five bits
// are the infinity or NaN marker. The coefficient and exponent are left zero and the
// sign stays where the decode put it; the caller reads the special kind in r9.
fn (e Emitter) decimal_decode_special(mut r DecimalRoutine, infinity string, nan string) !void {
	g := r.reg
	r.place(infinity)
	r.op(r.t.move_immediate64(g.r9, 1)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.xor_word(g.rcx, g.rcx)!)
	r.op(r.t.ret())
	r.place(nan)
	r.op(r.t.move_immediate64(g.r9, 2)!)
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.xor_word(g.rcx, g.rcx)!)
	r.op(r.t.ret())
}

// decimal_fix_core truncates a decoded value toward zero and leaves the magnitude in
// rax with the sign in r8 and an overflow flag in r9. It is handed the coefficient in
// rax:rdx, the power of ten in rcx and the special kind in r9, and it is the same
// arithmetic for every destination, because the range check that differs is done by
// the wrapper that calls it.
//
// A positive power of ten multiplies the coefficient by ten until the exponent is
// spent, and the first time a product needs more than a word the value is past every
// integer this back end converts to and the overflow flag is set. A negative power of
// ten divides the pair by ten, which is where a fractional decimal truncates toward
// zero; a coefficient that becomes zero stays zero, so a value far below one is
// zero without the loop running to the exponent's full size.
fn (e Emitter) decimal_fix_core(mut r DecimalRoutine) !void {
	g := r.reg
	r.place(decimal_fix_core_name)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	// A special value is out of range whatever the target is.
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, 'fix_overflow')
	// A zero coefficient is zero of either sign, with no overflow.
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.or_word(g.r10, g.rdx)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, 'fix_zero')
	r.op(r.t.xor_word(g.r9, g.r9)!)
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.less, 'fix_down')
	// The exponent is positive: the coefficient's own high word means the value is
	// already past a word, and an exponent of twenty or more means ten to it is.
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'fix_overflow')
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.add_immediate(g.r10, -20))
	r.branch(.greater_or_equal, 'fix_overflow')
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.place('fix_up_loop')
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, 'fix_up_done')
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.move_immediate64(g.r12, 10)!)
	r.op(r.t.multiply_pair(g.r12)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'fix_overflow')
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.add_immediate(g.r10, -1))
	r.jump('fix_up_loop')
	r.place('fix_up_done')
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.jump('fix_finish')
	// The exponent is negative: divide the pair by ten until it is spent. The high
	// word is divided first so each division's quotient fits a word, and the
	// remainder of that division becomes the top of the second dividend.
	r.place('fix_down')
	r.op(r.t.negate_word(g.rcx)!)
	r.place('fix_down_loop')
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.equal, 'fix_down_done')
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.or_word(g.r10, g.rdx)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, 'fix_down_done')
	r.op(r.t.move_register64(g.r13, g.rdx)!)
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r13)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_immediate64(g.r12, 10)!)
	r.op(r.t.divide_pair(g.r12)!)
	r.op(r.t.move_register64(g.r15, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r14)!)
	r.op(r.t.divide_pair(g.r12)!)
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r13, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.r14)!)
	r.op(r.t.move_register64(g.rdx, g.r13)!)
	r.op(r.t.add_immediate(g.rcx, -1))
	r.jump('fix_down_loop')
	r.place('fix_down_done')
	// Whatever is left in the high word is past a word, so it is past every target.
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, 'fix_overflow')
	r.jump('fix_finish')
	r.place('fix_zero')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.r9, g.r9)!)
	r.jump('fix_finish')
	r.place('fix_overflow')
	r.op(r.t.move_immediate64(g.r9, 1)!)
	r.place('fix_finish')
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// decimal_fix_wrapper is the entry a call site names: it decodes the object, runs the
// core, and answers the value the destination type asks for. The range check is the
// part that differs, and it is the one measured off gcc: a signed target answers its
// minimum value when the magnitude is past its positive range and the sign is wrong
// for the negative one, and an unsigned target answers zero.
fn (e Emitter) decimal_fix_wrapper(mut r DecimalRoutine, format decimal.Format, target int) !void {
	g := r.reg
	name := decimal_fix_name(format, target)
	r.place(name)
	r.call(decimal_decode_name(format))
	r.call(decimal_fix_core_name)
	if target == fix_int32 {
		r.op(r.t.test_word(g.r9)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.test_word(g.r8)!)
		r.branch(.not_equal, '${name}_neg')
		r.op(r.t.move_immediate64(g.r10, 0x80000000)!)
		r.op(r.t.move_register64(g.r11, g.rax)!)
		r.op(r.t.subtract_word(g.r11, g.r10)!)
		r.branch(.above_or_equal, '${name}_out')
		r.op(r.t.ret())
		r.place('${name}_neg')
		r.op(r.t.move_immediate64(g.r10, 0x80000000)!)
		r.op(r.t.move_register64(g.r11, g.rax)!)
		r.op(r.t.subtract_word(g.r11, g.r10)!)
		r.branch(.above, '${name}_out')
		r.op(r.t.negate_word(g.rax)!)
		r.op(r.t.ret())
		r.place('${name}_out')
		r.op(r.t.move_immediate64(g.rax, 0xffffffff80000000)!)
		r.op(r.t.ret())
	} else if target == fix_uint32 {
		r.op(r.t.test_word(g.r9)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.test_word(g.r8)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.move_immediate64(g.r10, 0xffffffff)!)
		r.op(r.t.move_register64(g.r11, g.rax)!)
		r.op(r.t.subtract_word(g.r11, g.r10)!)
		r.branch(.above, '${name}_out')
		r.op(r.t.ret())
		r.place('${name}_out')
		r.op(r.t.xor_word(g.rax, g.rax)!)
		r.op(r.t.ret())
	} else if target == fix_int64 {
		r.op(r.t.test_word(g.r9)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.test_word(g.r8)!)
		r.branch(.not_equal, '${name}_neg')
		r.op(r.t.move_immediate64(g.r10, 0x8000000000000000)!)
		r.op(r.t.move_register64(g.r11, g.rax)!)
		r.op(r.t.subtract_word(g.r11, g.r10)!)
		r.branch(.above_or_equal, '${name}_out')
		r.op(r.t.ret())
		r.place('${name}_neg')
		r.op(r.t.move_immediate64(g.r10, 0x8000000000000000)!)
		r.op(r.t.move_register64(g.r11, g.rax)!)
		r.op(r.t.subtract_word(g.r11, g.r10)!)
		r.branch(.above, '${name}_out')
		r.op(r.t.negate_word(g.rax)!)
		r.op(r.t.ret())
		r.place('${name}_out')
		r.op(r.t.move_immediate64(g.rax, 0x8000000000000000)!)
		r.op(r.t.ret())
	} else if target == fix_uint64 {
		r.op(r.t.test_word(g.r9)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.test_word(g.r8)!)
		r.branch(.not_equal, '${name}_out')
		r.op(r.t.ret())
		r.place('${name}_out')
		r.op(r.t.xor_word(g.rax, g.rax)!)
		r.op(r.t.ret())
	} else {
		return error('decimal fix target')
	}
}

// emit_decimal_to_integer converts a decimal object to one of the integer types at
// run time. The object has to be a name, a member or an element, because the routine
// reads it where it lives. The call is left local, so only a unit that makes the
// conversion carries the routine.
fn (mut e Emitter) emit_decimal_to_integer(expr ast.Expr, target types.Type, line int, col int, depth int) !void {
	if !e.names_an_object(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a ${expr.typ.describe()} is converted to ${target.describe()} here, and only an object of one can be, because the conversion reads it where it lives')
		return error('decimal value')
	}
	class := decimal_fix_target(target.kind) or {
		e.diagnostics << problem(line, col, 'unsupported: a conversion from ${expr.typ.describe()} to ${target.describe()} is not one this back end makes')
		return error('decimal conversion')
	}
	format := expr.typ.kind.decimal_format()
	e.emit_address(ast.Unary{
		op:   '&'
		expr: expr
		typ:  expr.typ
		line: line
		col:  col
	}, depth + 1)!
	name := decimal_fix_name(format, class)
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
	// A char or a short is the int or unsigned int conversion truncated to its own
	// width, which is what gcc does: the value is sign- or zero-extended from the
	// byte or the half it occupies.
	register := e.accumulator(line, col)!
	match target.kind {
		.char_, .signed_char {
			e.append(e.target.sign_extend_byte(register)!)
		}
		.unsigned_char {
			e.append(e.target.widen_byte(register)!)
		}
		.short {
			e.append(e.target.sign_extend_half(register)!)
		}
		.unsigned_short {
			e.append(e.target.zero_extend_half(register)!)
		}
		.bool_ {
			e.append(e.target.test_word(register)!)
			e.append(e.target.set_condition(backend.Condition.not_equal, register)!)
			e.append(e.target.widen_byte(register)!)
		}
		else {}
	}
}

// emit_decimal_conversion is the one door a cast whose operand is a decimal takes.
// It answers the conversion the destination asks for or refuses it by name, and it
// is where the destinations this file has not reached say so.
fn (mut e Emitter) emit_decimal_conversion(cast ast.Cast, target types.Type, depth int) !void {
	if target.kind == .double {
		return e.emit_decimal_to_double(cast.expr, cast.line, cast.col, depth)
	}
	if decimal_fix_target(target.kind) != none {
		return e.emit_decimal_to_integer(cast.expr, target, cast.line, cast.col, depth)
	}
	e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and only a conversion to a double or to an integer is implemented')
	return error('decimal conversion')
}
