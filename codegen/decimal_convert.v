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

// decimal_float_core_name is the one shared scaling and rounding core that turns a
// decoded decimal into a float. It follows decimal.v's double core step for step and
// differs only in the rounding at the end, which is to twenty-four bits rather than
// fifty-three and at the float format's exponent range.
const decimal_float_core_name = 'vcc_decimal_to_float_core'

fn decimal_decode_name(format decimal.Format) string {
	return 'vcc_decimal_decode_${format.bytes()}'
}

fn decimal_fix_name(format decimal.Format, target int) string {
	return 'vcc_decimal_fix_${format.bytes()}_c${target}'
}

fn decimal_float_name(format decimal.Format) string {
	return 'vcc_decimal_to_float_${format.bytes()}'
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
	mut any_fix := false
	mut any_float := false
	// Parallel to formats: which of the four integer targets each format asked for,
	// and whether it asked for a float.
	mut by_format := [][]int{}
	mut float_format := []bool{}
	for format in formats {
		mut targets := []int{}
		for target in [fix_int32, fix_uint32, fix_int64, fix_uint64] {
			if decimal_fix_name(format, target) in e.decimal_convert_used {
				targets << target
				any_fix = true
			}
		}
		by_format << targets
		wants_float := decimal_float_name(format) in e.decimal_convert_used
		if wants_float {
			any_float = true
		}
		float_format << wants_float
	}
	// The width conversions this unit named, and the formats whose rounding and
	// encoding routines they reach.
	mut width_format := []bool{}
	for _ in formats {
		width_format << false
	}
	mut pair_src := []int{}
	mut pair_dst := []int{}
	for i, src in formats {
		for j, dst in formats {
			if i == j {
				continue
			}
			if decimal_pair_name(src, dst) in e.decimal_convert_used {
				pair_src << i
				pair_dst << j
				width_format[j] = true
			}
		}
	}
	// The integer conversions this unit named, which reach the same rounding and
	// encoding routines as a width conversion to the same destination.
	mut int_size := []int{}
	mut int_unsigned := []bool{}
	mut int_dst := []int{}
	for size in [1, 2, 4, 8] {
		for unsigned_kind in [false, true] {
			for j, dst in formats {
				if decimal_from_integer_name(size, unsigned_kind, dst) in e.decimal_convert_used {
					int_size << size
					int_unsigned << unsigned_kind
					int_dst << j
					width_format[j] = true
				}
			}
		}
	}
	// Which formats have a zero test, which reads the object through a decode and
	// answers an int.
	mut zero_format := []bool{len: formats.len}
	for j, format in formats {
		if decimal_is_zero_name(format) in e.decimal_convert_used {
			zero_format[j] = true
		}
	}
	// Which formats a decode is read for: its own conversions, and the width
	// conversions that start at it.
	mut any_decode := []bool{}
	for i, _ in formats {
		any_decode << by_format[i].len > 0 || float_format[i] || zero_format[i]
	}
	for i, _ in formats {
		for k, _ in pair_src {
			if pair_src[k] == i {
				any_decode[i] = true
			}
		}
	}
	mut any := any_fix || any_float || int_size.len > 0
	for wants in width_format {
		if wants {
			any = true
		}
	}
	for wants in zero_format {
		if wants {
			any = true
		}
	}
	if !any {
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
	if any_fix {
		e.decimal_fix_core(mut r)!
	}
	if any_float {
		e.decimal_to_float_core(mut r)!
	}
	for i, format in formats {
		if width_format[i] {
			target := decimal_target(format)
			e.emit_decimal_quantize(mut r, target)!
			e.emit_decimal_encode(mut r, target)!
		}
	}
	for i, format in formats {
		if any_decode[i] {
			e.decimal_decode(mut r, format)!
		}
	}
	for i, format in formats {
		for target in by_format[i] {
			e.decimal_fix_wrapper(mut r, format, target)!
		}
		if float_format[i] {
			e.decimal_float_wrapper(mut r, format)!
		}
	}
	for k, _ in pair_src {
		e.emit_decimal_pair(mut r, formats[pair_src[k]], formats[pair_dst[k]])!
	}
	for k, _ in int_size {
		e.emit_decimal_from_integer_routine(mut r, int_size[k], int_unsigned[k], formats[int_dst[k]])!
	}
	for j, wants in zero_format {
		if wants {
			e.emit_decimal_is_zero_routine(mut r, formats[j])!
		}
	}
	base := e.program.text.len
	bytes := r.resolved()
	e.program.text << bytes
	if any_fix {
		e.program.labels[decimal_fix_core_name] = base + r.labels[decimal_fix_core_name]
	}
	if any_float {
		e.program.labels[decimal_float_core_name] = base + r.labels[decimal_float_core_name]
	}
	for format in formats {
		for name in [
			decimal_quantize_name(format),
			decimal_encode_name(format),
			decimal_decode_name(format),
			decimal_float_name(format),
		] {
			if name in r.labels {
				e.program.labels[name] = base + r.labels[name]
			}
		}
		for target in [fix_int32, fix_uint32, fix_int64, fix_uint64] {
			label := decimal_fix_name(format, target)
			if label in r.labels {
				e.program.labels[label] = base + r.labels[label]
			}
		}
		for dst in formats {
			label := decimal_pair_name(format, dst)
			if label in r.labels {
				e.program.labels[label] = base + r.labels[label]
			}
		}
		for size in [1, 2, 4, 8] {
			for unsigned_kind in [false, true] {
				label := decimal_from_integer_name(size, unsigned_kind, format)
				if label in r.labels {
					e.program.labels[label] = base + r.labels[label]
				}
			}
		}
		zero_label := decimal_is_zero_name(format)
		if zero_label in r.labels {
			e.program.labels[zero_label] = base + r.labels[zero_label]
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
	if target.kind == .float {
		return e.emit_decimal_to_float(cast.expr, cast.line, cast.col, depth)
	}
	if decimal_fix_target(target.kind) != none {
		return e.emit_decimal_to_integer(cast.expr, target, cast.line, cast.col, depth)
	}
	e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and only a conversion to a float, a double or an integer is implemented')
	return error('decimal conversion')
}

// emit_decimal_to_float converts a decimal object to a float at run time. As with
// the other conversions the object has to be a name, a member or an element, because
// the routine reads it where it lives, and the result arrives in xmm0.
fn (mut e Emitter) emit_decimal_to_float(expr ast.Expr, line int, col int, depth int) !void {
	if !e.names_an_object(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a ${expr.typ.describe()} is converted to float here, and only an object of one can be, because the conversion reads it where it lives')
		return error('decimal value')
	}
	e.emit_address(ast.Unary{
		op:   '&'
		expr: expr
		typ:  expr.typ
		line: line
		col:  col
	}, depth + 1)!
	name := decimal_float_name(expr.typ.kind.decimal_format())
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// decimal_float_wrapper is the float conversion's entry: it decodes the object and
// hands a finite value to the shared core, and writes the float's own infinity or
// quiet NaN for a special. The sign is the decimal's in every case.
fn (e Emitter) decimal_float_wrapper(mut r DecimalRoutine, format decimal.Format) !void {
	g := r.reg
	name := decimal_float_name(format)
	r.place(name)
	r.call(decimal_decode_name(format))
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${name}_special')
	r.call(decimal_float_core_name)
	r.op(r.t.move_word_to_double(g.xmm0, g.rax)!)
	r.op(r.t.ret())
	r.place('${name}_special')
	r.op(r.t.move_immediate64(g.rax, 0x7f800000)!)
	r.op(r.t.move_register64(g.r10, g.r8)!)
	r.op(r.t.shift_left_word(g.r10, 31)!)
	r.op(r.t.or_word(g.rax, g.r10)!)
	r.op(r.t.move_register64(g.r11, g.r9)!)
	r.op(r.t.add_immediate(g.r11, -2))
	r.branch(.not_equal, '${name}_special_done')
	r.op(r.t.move_immediate64(g.rax, 0x7fc00000)!)
	r.place('${name}_special_done')
	r.op(r.t.move_word_to_double(g.xmm0, g.rax)!)
	r.op(r.t.ret())
}

// decimal_to_float_core scales a decoded decimal to the leading sixty-four bits of
// its coefficient with a sticky bit and rounds once to a float. It is decimal.v's
// double core with the four-byte format's constants: twenty-four bits kept, an
// unbiased exponent that runs to 127 before it overflows, a subnormal that keeps
// fewer bits, and the result left as the float's own bits in rax.
//
// On entry rax:rdx is the coefficient, rcx the exponent, r8 the sign and r9 the
// special kind (zero for finite; the wrapper answers the specials).
fn (e Emitter) decimal_to_float_core(mut r DecimalRoutine) !void {
	g := r.reg
	r.place(decimal_float_core_name)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	r.op(r.t.move_register64(g.r9, g.rax)!) // c_lo
	r.op(r.t.move_register64(g.r10, g.rdx)!) // c_hi
	r.op(r.t.move_register64(g.rsi, g.rcx)!) // exp10
	r.op(r.t.xor_word(g.r13, g.r13)!) // sticky = 0
	// The coefficient is put in the top of a word, its dropped bits in the sticky.
	r.op(r.t.test_word(g.r10)!)
	r.branch(.equal, 'f_low')
	r.op(r.t.count_leading(g.rcx, g.r10, true)!)
	r.op(r.t.move_immediate64(g.r14, 64)!)
	r.op(r.t.subtract_word(g.r14, g.rcx)!)
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r15)!)
	r.op(r.t.add_immediate(g.r15, -1))
	r.op(r.t.move_register64(g.rax, g.r9)!)
	r.op(r.t.and_word(g.rax, g.r15)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'f_hi_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('f_hi_clean')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.move_register64(g.rax, g.r9)!)
	r.op(r.t.shift_right_word_register(g.rax)!)
	r.op(r.t.move_register64(g.r11, g.r10)!)
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r11)!)
	r.op(r.t.or_word(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rbx, g.r11)!)
	r.op(r.t.move_register64(g.r12, g.r14)!)
	r.jump('f_scaled')
	r.place('f_low')
	r.op(r.t.test_word(g.r9)!)
	r.branch(.equal, 'f_zero')
	r.op(r.t.count_leading(g.rcx, g.r9, true)!)
	r.op(r.t.move_register64(g.rbx, g.r9)!)
	r.op(r.t.shift_left_word_register(g.rbx)!)
	r.op(r.t.negate_word(g.rcx)!)
	r.op(r.t.move_register64(g.r12, g.rcx)!)
	r.place('f_scaled')
	// Scale up, nineteen digits at a time, keeping the leading sixty-four bits.
	r.place('f_up')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.less_or_equal, 'f_down')
	r.op(r.t.move_register64(g.rcx, g.rsi)!)
	r.op(r.t.add_immediate(g.rcx, -19))
	r.branch(.less_or_equal, 'f_up_exp')
	r.op(r.t.move_immediate64(g.r9, 19)!)
	r.jump('f_up_chunk')
	r.place('f_up_exp')
	r.op(r.t.move_register64(g.r9, g.rsi)!)
	r.place('f_up_chunk')
	r.op(r.t.move_immediate64(g.r14, 1)!)
	r.op(r.t.move_register64(g.r15, g.r9)!)
	r.place('f_up_power')
	r.op(r.t.test_word(g.r15)!)
	r.branch(.equal, 'f_up_powered')
	r.op(r.t.imul_immediate(g.r14, 10))
	r.op(r.t.add_immediate(g.r15, -1))
	r.jump('f_up_power')
	r.place('f_up_powered')
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.multiply_pair(g.r14)!) // rdx:rax = mant * d
	r.op(r.t.count_leading(g.rcx, g.rdx, true)!)
	r.op(r.t.move_immediate64(g.r14, 64)!)
	r.op(r.t.subtract_word(g.r14, g.rcx)!)
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, -64))
	r.branch(.equal, 'f_up_full')
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.r15)!)
	r.op(r.t.add_immediate(g.r15, -1))
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.and_word(g.r11, g.r15)!)
	r.op(r.t.test_word(g.r11)!)
	r.branch(.equal, 'f_up_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('f_up_clean')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.shift_right_word_register(g.r11)!)
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r14)!)
	r.op(r.t.shift_left_word_register(g.rdx)!)
	r.op(r.t.or_word(g.rdx, g.r11)!)
	r.op(r.t.move_register64(g.rbx, g.rdx)!)
	r.op(r.t.add_reg64(g.r12, g.r14))
	r.op(r.t.subtract_word(g.rsi, g.r9)!)
	r.jump('f_up')
	r.place('f_up_full')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'f_up_full_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('f_up_full_clean')
	r.op(r.t.move_register64(g.rbx, g.rdx)!)
	r.op(r.t.add_immediate(g.r12, 64))
	r.op(r.t.subtract_word(g.rsi, g.r9)!)
	r.jump('f_up')
	// Scale down, dividing a numerator scaled by the top bit of the divisor.
	r.place('f_down')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, 'f_round')
	r.op(r.t.move_register64(g.rcx, g.rsi)!)
	r.op(r.t.negate_word(g.rcx)!)
	r.op(r.t.add_immediate(g.rcx, -19))
	r.branch(.less_or_equal, 'f_down_exp')
	r.op(r.t.move_immediate64(g.r9, 19)!)
	r.jump('f_down_chunk')
	r.place('f_down_exp')
	r.op(r.t.move_register64(g.r9, g.rsi)!)
	r.op(r.t.negate_word(g.r9)!)
	r.place('f_down_chunk')
	r.op(r.t.move_immediate64(g.r14, 1)!)
	r.op(r.t.move_register64(g.r15, g.r9)!)
	r.place('f_down_power')
	r.op(r.t.test_word(g.r15)!)
	r.branch(.equal, 'f_down_powered')
	r.op(r.t.imul_immediate(g.r14, 10))
	r.op(r.t.add_immediate(g.r15, -1))
	r.jump('f_down_power')
	r.place('f_down_powered')
	r.op(r.t.count_leading(g.rcx, g.r14, true)!)
	r.op(r.t.move_immediate64(g.r11, 63)!)
	r.op(r.t.subtract_word(g.r11, g.rcx)!)
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.shift_left_word_register(g.rax)!)
	r.op(r.t.move_register64(g.r15, g.rbx)!)
	r.op(r.t.move_immediate64(g.rcx, 64)!)
	r.op(r.t.subtract_word(g.rcx, g.r11)!)
	r.op(r.t.shift_right_word_register(g.r15)!)
	r.op(r.t.move_register64(g.rdx, g.r15)!)
	r.op(r.t.subtract_word(g.r12, g.r11)!)
	r.op(r.t.divide_pair(g.r14)!)
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, 'f_down_clean')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('f_down_clean')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.equal, 'f_zero')
	r.op(r.t.count_leading(g.rcx, g.rax, true)!)
	r.op(r.t.move_register64(g.r15, g.rcx)!)
	r.op(r.t.shift_left_word_register(g.rax)!)
	r.op(r.t.subtract_word(g.r12, g.r15)!)
	r.op(r.t.move_register64(g.rbx, g.rax)!)
	r.op(r.t.add_reg64(g.rsi, g.r9))
	r.jump('f_down')
	// Round once, to nearest with ties to even, to the twenty-four bits a float keeps.
	r.place('f_round')
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.shift_right_word(g.rax, 40)!)
	r.op(r.t.move_register64(g.rcx, g.rbx)!)
	r.op(r.t.move_immediate64(g.r15, 0xffffffffff)!)
	r.op(r.t.and_word(g.rcx, g.r15)!)
	r.op(r.t.move_immediate64(g.r15, 0x8000000000)!)
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.subtract_word(g.r11, g.r15)!)
	r.branch(.below, 'f_kept')
	r.branch(.above, 'f_carry')
	r.op(r.t.test_word(g.r13)!)
	r.branch(.not_equal, 'f_carry')
	r.op(r.t.move_register64(g.rcx, g.rax)!)
	r.op(r.t.and_immediate(g.rcx, 1)!)
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.not_equal, 'f_carry')
	r.jump('f_kept')
	r.place('f_carry')
	r.op(r.t.add_immediate(g.rax, 1))
	r.place('f_kept')
	r.op(r.t.move_register64(g.r14, g.r12)!)
	r.op(r.t.add_immediate(g.r14, 63))
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_immediate64(g.r9, 24)!)
	r.op(r.t.shift_left_word_register(g.r15)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.subtract_word(g.r11, g.r15)!)
	r.branch(.not_equal, 'f_no_carry')
	r.op(r.t.shift_right_word(g.rax, 1)!)
	r.op(r.t.add_immediate(g.r14, 1))
	r.place('f_no_carry')
	r.op(r.t.move_register64(g.r11, g.r14)!)
	r.op(r.t.add_immediate(g.r11, -128))
	r.branch(.greater_or_equal, 'f_inf')
	r.op(r.t.move_register64(g.r11, g.r14)!)
	r.op(r.t.add_immediate(g.r11, 126))
	r.branch(.greater_or_equal, 'f_normal')
	r.jump('f_subnormal')
	r.place('f_normal')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, 127))
	r.op(r.t.shift_left_word(g.rcx, 23)!)
	r.op(r.t.move_immediate64(g.r15, 0x7fffff)!)
	r.op(r.t.and_word(g.rax, g.r15)!)
	r.op(r.t.or_word(g.rcx, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 31)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.jump('f_finish')
	r.place('f_inf')
	r.op(r.t.move_immediate64(g.rcx, 0x7f800000)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 31)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.jump('f_finish')
	r.place('f_zero')
	r.op(r.t.move_register64(g.rax, g.r8)!)
	r.op(r.t.shift_left_word(g.rax, 31)!)
	r.jump('f_finish')
	r.place('f_subnormal')
	r.op(r.t.move_register64(g.rcx, g.r14)!)
	r.op(r.t.add_immediate(g.rcx, 126))
	r.op(r.t.negate_word(g.rcx)!)
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.add_immediate(g.r11, -64))
	r.branch(.greater_or_equal, 'f_zero')
	r.op(r.t.move_register64(g.rdi, g.rcx)!)
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.op(r.t.shift_left_word_register(g.r10)!)
	r.op(r.t.add_immediate(g.r10, -1))
	r.op(r.t.move_register64(g.r9, g.rax)!)
	r.op(r.t.and_word(g.r9, g.r10)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.shift_right_word_register(g.r11)!)
	r.op(r.t.move_register64(g.rcx, g.rdi)!)
	r.op(r.t.add_immediate(g.rcx, -1))
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.shift_left_word_register(g.r15)!)
	r.op(r.t.move_register64(g.rcx, g.r9)!)
	r.op(r.t.subtract_word(g.rcx, g.r15)!)
	r.branch(.above, 'f_sub_carry')
	r.branch(.below, 'f_sub_kept')
	r.op(r.t.test_word(g.r13)!)
	r.branch(.not_equal, 'f_sub_carry')
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.and_immediate(g.rcx, 1)!)
	r.op(r.t.test_word(g.rcx)!)
	r.branch(.not_equal, 'f_sub_carry')
	r.jump('f_sub_kept')
	r.place('f_sub_carry')
	r.op(r.t.add_immediate(g.r11, 1))
	r.place('f_sub_kept')
	r.op(r.t.move_immediate64(g.r15, 1)!)
	r.op(r.t.move_immediate64(g.rcx, 23)!)
	r.op(r.t.shift_left_word_register(g.r15)!)
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.subtract_word(g.rcx, g.r15)!)
	r.branch(.not_equal, 'f_sub_not_one')
	r.op(r.t.move_register64(g.r11, g.r15)!)
	r.place('f_sub_not_one')
	r.op(r.t.move_register64(g.rcx, g.r11)!)
	r.op(r.t.move_register64(g.r15, g.r8)!)
	r.op(r.t.shift_left_word(g.r15, 31)!)
	r.op(r.t.or_word(g.rcx, g.r15)!)
	r.op(r.t.move_register64(g.rax, g.rcx)!)
	r.place('f_finish')
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}
