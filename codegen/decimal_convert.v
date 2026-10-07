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
	// The binary-to-decimal conversions this unit named, one per source width,
	// which reach the same rounding and encoding routines as a width conversion to
	// the same destination.
	mut from_binary := [][]int{}
	for _ in formats {
		from_binary << []int{}
	}
	for j, dst in formats {
		for src_bytes in [4, 8] {
			if decimal_from_binary_name(src_bytes, dst) in e.decimal_convert_used {
				from_binary[j] << src_bytes
				width_format[j] = true
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
	for i, dst in formats {
		if from_binary[i].len > 0 {
			e.decimal_binary_core(mut r, dst)!
		}
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
		for src_bytes in from_binary[i] {
			e.decimal_binary_wrapper(mut r, src_bytes, format)!
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
			decimal_from_binary_core_name(format),
		] {
			if name in r.labels {
				e.program.labels[name] = base + r.labels[name]
			}
		}
		for src_bytes in [4, 8] {
			label := decimal_from_binary_name(src_bytes, format)
			if label in r.labels {
				e.program.labels[label] = base + r.labels[label]
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

// A binary floating value is m times two to the e, and a decimal is a
// coefficient times a power of ten. The two meet at ten: two to the minus one is
// five tenths, so m times two to the e is m times five to the minus e times ten
// to the e. The coefficient that conversion produces is an arbitrarily large
// integer, five to the one thousand and seventy-fourth for the smallest double,
// which is why the routines below build it in a fixed block of words on the
// stack rather than in the pair of registers every other conversion works in.
// They then round it to the destination's precision exactly as a decimal of
// another width is rounded, and the quantizer and encoder already here finish
// the object.
//
// The coefficient is built in the form gcc stores rather than the first one the
// arithmetic produces. A power of two that pairs with a power of five is a ten
// the coefficient would carry as a trailing zero; taking the significand's own
// trailing zero bits out first removes exactly those, which is why `1.0` is a
// coefficient of one under a power of zero and not a million under minus six.
// Five to the minus e is never even, so nothing below that first step can leave
// a trailing zero behind.

// The words a coefficient is built in. Five to the one thousand and seventy-fourth
// has two thousand four hundred and ninety-five bits, and the significand puts
// fifty-three more above it, so forty words hold the widest double and every float
// with room to spare.
const decimal_binary_limbs = 40
const decimal_binary_bytes = decimal_binary_limbs * 8

// decimal_from_binary_name is the entry a call site names for a conversion from a
// binary float of one width into one of the decimal formats.
fn decimal_from_binary_name(src_bytes int, dst decimal.Format) string {
	return 'vcc_decimal_from_f${src_bytes}_to_${dst.bytes()}'
}

// decimal_from_binary_core_name is the per-destination routine that turns a
// significand and a binary exponent into the destination's decimal object. It is
// one routine per format because the precision, the bias and the infinity it
// rounds at are the format's own.
fn decimal_from_binary_core_name(dst decimal.Format) string {
	return 'vcc_decimal_from_binary_${dst.bytes()}'
}

// emit_decimal_from_binary converts an object of a binary floating type to a
// decimal one at run time. The object has to be a name, a member or an element,
// because the routine reads it where it lives; anything else is refused by name.
// The source's address is left in rax and the object the value is going into is
// addressed into rdi, which is where the integer conversions of a decimal leave
// them too.
fn (mut e Emitter) emit_decimal_from_binary(slot Slot, expr ast.Cast, depth int) !void {
	g := decimal_registers(e.target) or {
		e.diagnostics << problem(expr.line, expr.col, 'internal: the target has no register a decimal conversion needs')
		return error('decimal registers')
	}
	source_bytes := match expr.expr.typ.kind {
		.double { 8 }
		.float { 4 }
		else {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.expr.typ.describe()} is converted to ${expr.typ.describe()}, and only a float or a double is a binary source this back end converts')
			return error('decimal binary source')
		}
	}
	if !e.names_an_object(expr.expr) {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: a ${expr.expr.typ.describe()} is converted to ${expr.typ.describe()} here, and only an object of one can be, because the conversion reads it where it lives')
		return error('decimal value')
	}
	e.emit_address(ast.Unary{
		op:   '&'
		expr: expr.expr
		typ:  expr.expr.typ
		line: expr.line
		col:  expr.col
	}, depth + 1)!
	e.append(e.target.move_register64(g.rsi, e.accumulator(expr.line, expr.col)!)!)
	e.leave_address(slot, expr.line, expr.col)!
	e.append(e.target.move_register64(g.rdi, e.accumulator(expr.line, expr.col)!)!)
	e.append(e.target.move_register64(g.rax, g.rsi)!)
	name := decimal_from_binary_name(source_bytes, expr.typ.kind.decimal_format())
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// decimal_binary_wrapper reads the fields of one binary float out of the object
// the caller addressed and hands the core a significand and a binary exponent.
// The address arrives in rax and the destination object in rdi. Sign, exponent
// field and fraction are taken off the one word a float or a double is; the
// implied leading bit is added for a normal value and left out for a subnormal
// one, whose exponent is the format's smallest, and an infinity or a NaN never
// reaches the core at all.
fn (e Emitter) decimal_binary_wrapper(mut r DecimalRoutine, src_bytes int, dst decimal.Format) !void {
	g := r.reg
	name := decimal_from_binary_name(src_bytes, dst)
	target := decimal_target(dst)
	r.place(name)
	r.op(r.t.push_register(g.rbx))
	match src_bytes {
		8 {
			r.op(r.t.load_indirect(g.rax, g.rax, 8)!)
			r.op(r.t.move_register64(g.r8, g.rax)!)
			r.op(r.t.shift_right_word(g.r8, 63)!)
			r.op(r.t.move_register64(g.r9, g.rax)!)
			r.op(r.t.shift_right_word(g.r9, 52)!)
			r.op(r.t.and_immediate(g.r9, 0x7ff)!)
			r.op(r.t.move_immediate64(g.rcx, 0xfffffffffffff)!)
			r.op(r.t.move_register64(g.r11, g.rax)!)
			r.op(r.t.and_word(g.r11, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.r9)!)
			r.op(r.t.add_immediate(g.rcx, -0x7ff))
			r.branch(.equal, '${name}_special')
			r.op(r.t.test_word(g.r9)!)
			r.branch(.equal, '${name}_subnormal')
			r.op(r.t.move_immediate64(g.rcx, 0x10000000000000)!)
			r.op(r.t.or_word(g.r11, g.rcx)!)
			r.op(r.t.move_register64(g.rdx, g.r9)!)
			r.op(r.t.add_immediate(g.rdx, -1075))
			r.op(r.t.move_register64(g.rax, g.r11)!)
			r.jump('${name}_call')
			r.place('${name}_subnormal')
			r.op(r.t.move_register64(g.rax, g.r11)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.add_immediate(g.rdx, -1074))
			r.place('${name}_call')
			r.call(decimal_from_binary_core_name(dst))
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
			r.place('${name}_special')
			r.op(r.t.test_word(g.r11)!)
			r.branch(.equal, '${name}_inf')
			e.decimal_write_binary_nan(mut r, target, g.r11, 52, '${name}_nan')!
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
			r.place('${name}_inf')
			e.decimal_write_special(mut r, target, false)!
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
		}
		4 {
			r.op(r.t.load_indirect(g.rax, g.rax, 4)!)
			r.op(r.t.move_register64(g.r8, g.rax)!)
			r.op(r.t.shift_right_word(g.r8, 31)!)
			r.op(r.t.move_register64(g.r9, g.rax)!)
			r.op(r.t.shift_right_word(g.r9, 23)!)
			r.op(r.t.and_immediate(g.r9, 0xff)!)
			r.op(r.t.move_immediate64(g.rcx, 0x7fffff)!)
			r.op(r.t.move_register64(g.r11, g.rax)!)
			r.op(r.t.and_word(g.r11, g.rcx)!)
			r.op(r.t.move_register64(g.rcx, g.r9)!)
			r.op(r.t.add_immediate(g.rcx, -0xff))
			r.branch(.equal, '${name}_special')
			r.op(r.t.test_word(g.r9)!)
			r.branch(.equal, '${name}_subnormal')
			r.op(r.t.move_immediate64(g.rcx, 0x800000)!)
			r.op(r.t.or_word(g.r11, g.rcx)!)
			r.op(r.t.move_register64(g.rdx, g.r9)!)
			r.op(r.t.add_immediate(g.rdx, -150))
			r.op(r.t.move_register64(g.rax, g.r11)!)
			r.jump('${name}_call')
			r.place('${name}_subnormal')
			r.op(r.t.move_register64(g.rax, g.r11)!)
			r.op(r.t.xor_word(g.rdx, g.rdx)!)
			r.op(r.t.add_immediate(g.rdx, -149))
			r.place('${name}_call')
			r.call(decimal_from_binary_core_name(dst))
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
			r.place('${name}_special')
			r.op(r.t.test_word(g.r11)!)
			r.branch(.equal, '${name}_inf')
			e.decimal_write_binary_nan(mut r, target, g.r11, 23, '${name}_nan')!
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
			r.place('${name}_inf')
			e.decimal_write_special(mut r, target, false)!
			r.op(r.t.pop_register(g.rbx))
			r.op(r.t.ret())
		}
		else {
			return error('decimal binary source')
		}
	}
}

// decimal_write_binary_nan writes the NaN a binary source becomes: the five marker
// bits under the source's sign, and below them the payload the source's fraction
// carries, scaled the way gcc scales one - the fraction's own most significant bit
// is its quiet bit and does not count, and what is under it lands two places below
// the top of the coefficient field, with the low bits that fall off the field gone
// rather than rounded. gcc keeps that payload only while it is smaller than the
// destination's own count of digits, so a fraction whose payload reaches that
// count, or is nothing under its quiet bit, leaves the bare marker that is the
// quiet NaN every format shares. A decimal NaN carries its payload word as a
// payload word and is not scaled this way, which is why decimal_write_special is
// still the routine its decode leaves by.
fn (e Emitter) decimal_write_binary_nan(mut r DecimalRoutine, target DecimalTarget, frac backend.Register, frac_bits int, base string) !void {
	g := r.reg
	shift := target.cbits - 2 - frac_bits
	threshold_lo, threshold_hi := decimal_power10(target.digits - 1)
	marker := u128(0b11111) << (target.total - 6)
	r.op(r.t.move_register64(g.rax, frac)!)
	// The quiet bit is the fraction's own most significant one and does not count
	// as payload. A shift up past the top of the register and back down drops it
	// and nothing else, because the bits above the fraction's field are zero.
	r.op(r.t.shift_left_word(g.rax, u8(64 - frac_bits + 1))!)
	r.op(r.t.shift_right_word(g.rax, u8(64 - frac_bits + 1))!)
	if shift < 0 {
		r.op(r.t.move_immediate64(g.rcx, u64(-shift))!)
		r.op(r.t.shift_right_word_register(g.rax)!)
		r.op(r.t.xor_word(g.rdx, g.rdx)!)
	} else if shift < 64 {
		r.op(r.t.move_register64(g.rdx, g.rax)!)
		r.op(r.t.move_immediate64(g.rcx, u64(64 - shift))!)
		r.op(r.t.shift_right_word_register(g.rdx)!)
		r.op(r.t.move_immediate64(g.rcx, u64(shift))!)
		r.op(r.t.shift_left_word_register(g.rax)!)
	} else {
		r.op(r.t.move_register64(g.rdx, g.rax)!)
		r.op(r.t.move_immediate64(g.rcx, u64(shift - 64))!)
		r.op(r.t.shift_left_word_register(g.rdx)!)
		r.op(r.t.xor_word(g.rax, g.rax)!)
	}
	// Below the destination's own count of digits the payload stands; at that count
	// and above, gcc leaves it out. The comparison runs in a scratch register so
	// subtracting the threshold does not eat the payload it is judging.
	if threshold_hi != 0 {
		r.op(r.t.move_immediate64(g.rcx, threshold_hi)!)
		r.op(r.t.move_register64(g.r9, g.rdx)!)
		r.op(r.t.subtract_word(g.r9, g.rcx)!)
		r.branch(.above, '${base}_empty')
		r.branch(.below, '${base}_write')
	}
	r.op(r.t.move_immediate64(g.rcx, threshold_lo)!)
	r.op(r.t.move_register64(g.r9, g.rax)!)
	r.op(r.t.subtract_word(g.r9, g.rcx)!)
	r.branch(.below, '${base}_write')
	r.place('${base}_empty')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.place('${base}_write')
	r.op(r.t.move_immediate64(g.rcx, u64(marker & 0xffffffffffffffff))!)
	r.op(r.t.or_word(g.rax, g.rcx)!)
	r.op(r.t.move_immediate64(g.rcx, u64((marker >> 64) & 0xffffffffffffffff))!)
	r.op(r.t.or_word(g.rdx, g.rcx)!)
	if target.total == 128 {
		r.op(r.t.move_register64(g.rcx, g.r8)!)
		r.op(r.t.shift_left_word(g.rcx, 63)!)
		r.op(r.t.or_word(g.rdx, g.rcx)!)
	} else {
		r.op(r.t.move_register64(g.rcx, g.r8)!)
		r.op(r.t.shift_left_word(g.rcx, u8(target.total - 1))!)
		r.op(r.t.or_word(g.rax, g.rcx)!)
	}
	e.decimal_store_words(mut r, target)!
}

// decimal_binary_core is the routine a wrapper calls: it takes a significand in
// rax, a binary exponent in rdx, a sign in r8 and the destination object's
// address in rdi, and writes the destination format's encoding there.
//
// The coefficient is built in a block of words below the frame, one decimal digit
// at a time is dropped from its low end until it fits the destination's precision
// and until its power of ten is in the format's range, and the digit dropped last
// decides the rounding, with a five rounded to the even coefficient. That is one
// rounding at one place, which is what the quantizer does with a coefficient it is
// handed; a coefficient rounded twice would not be the same decimal.
fn (e Emitter) decimal_binary_core(mut r DecimalRoutine, dst decimal.Format) !void {
	g := r.reg
	n := decimal_from_binary_core_name(dst)
	target := decimal_target(dst)
	pow_lo, pow_hi := decimal_power10(target.digits)
	prev_lo, prev_hi := decimal_power10(target.digits - 1)
	top_slot := i32((decimal_binary_limbs - 1) * 8)
	r.place(n)
	for saved in [g.rbx, g.r12, g.r13, g.r14, g.r15] {
		r.op(r.t.push_register(saved))
	}
	r.op(r.t.frame_reserve(decimal_binary_bytes))
	r.op(r.t.move_register64(g.r11, g.rsp)!) // the block of words
	r.op(r.t.move_register64(g.r12, g.rdi)!) // the object being written
	r.op(r.t.move_register64(g.r13, g.rax)!) // the significand
	r.op(r.t.move_register64(g.r14, g.rdx)!) // the binary exponent
	r.op(r.t.move_register64(g.r15, g.r8)!) // the sign
	// A zero significand is a zero of this sign, under a power of zero, which is
	// the encoding every format calls its flat zero.
	r.op(r.t.test_word(g.r13)!)
	r.branch(.equal, '${n}_zero')
	// Two to a power that meets a five is a ten, and a ten the coefficient carries
	// as a trailing zero is a power of ten the exponent should hold instead. The
	// significand's trailing zero bits are the twos that pair off: taking them out
	// leaves the coefficient gcc keeps, with none of its own.
	r.op(r.t.bit_scan_forward(g.r9, g.r13, true)!)
	r.op(r.t.move_register64(g.rcx, g.r9)!)
	r.op(r.t.shift_right_word_register(g.r13)!)
	r.op(r.t.add_reg64(g.r14, g.r9))
	// The block starts at zero, and the significand is the lowest word of it.
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.move_register64(g.r9, g.r11)!)
	r.op(r.t.move_immediate64(g.r10, decimal_binary_limbs)!)
	r.place('${n}_fill')
	r.op(r.t.store_slot(g.r9, 0, g.rax, 8)!)
	r.op(r.t.add_immediate(g.r9, 8))
	r.op(r.t.add_immediate(g.r10, -1))
	r.branch(.not_equal, '${n}_fill')
	r.op(r.t.store_slot(g.r11, 0, g.r13, 8)!)
	r.op(r.t.test_word(g.r14)!)
	r.branch(.greater_or_equal, '${n}_shift')
	// A negative binary exponent is five to its size: the coefficient is the
	// significand times that power, and the exponent of ten is its negative. The
	// power is taken in twenty-seven digit steps, because five to the twenty-seven
	// is the largest that still fits a word and the product of a word with it
	// needs both words of the pair.
	r.op(r.t.negate_word(g.r14)!)
	r.op(r.t.move_register64(g.rbx, g.r14)!)
	r.op(r.t.negate_word(g.rbx)!)
	r.op(r.t.move_register64(g.rsi, g.r14)!)
	r.place('${n}_mul')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, '${n}_built')
	r.op(r.t.move_register64(g.r8, g.rsi)!)
	r.op(r.t.add_immediate(g.r8, -27))
	r.branch(.greater_or_equal, '${n}_mul27')
	r.op(r.t.move_immediate64(g.r14, 5)!)
	r.op(r.t.move_immediate64(g.r8, 1)!)
	r.jump('${n}_mulpick')
	r.place('${n}_mul27')
	r.op(r.t.move_immediate64(g.r14, 7450580596923828125)!)
	r.op(r.t.move_immediate64(g.r8, 27)!)
	r.place('${n}_mulpick')
	r.op(r.t.xor_word(g.rcx, g.rcx)!)
	r.op(r.t.move_register64(g.r9, g.r11)!)
	r.op(r.t.move_immediate64(g.r10, decimal_binary_limbs)!)
	r.place('${n}_mulbody')
	r.op(r.t.load_slot(g.r9, 0, g.rax, 8)!)
	r.op(r.t.multiply_pair(g.r14)!)
	r.op(r.t.add_reg64(g.rax, g.rcx))
	r.op(r.t.add_with_carry_immediate(g.rdx, 0)!)
	r.op(r.t.store_slot(g.r9, 0, g.rax, 8)!)
	r.op(r.t.move_register64(g.rcx, g.rdx)!)
	r.op(r.t.add_immediate(g.r9, 8))
	r.op(r.t.add_immediate(g.r10, -1))
	r.branch(.not_equal, '${n}_mulbody')
	r.op(r.t.subtract_word(g.rsi, g.r8)!)
	r.jump('${n}_mul')
	// A binary exponent that is not negative leaves an integer: the significand
	// shifted up by it is the coefficient and its power of ten is zero.
	r.place('${n}_shift')
	r.op(r.t.xor_word(g.rbx, g.rbx)!)
	r.op(r.t.move_register64(g.rsi, g.r14)!)
	r.place('${n}_shiftloop')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, '${n}_built')
	r.op(r.t.address_of_slot(g.r11, top_slot, g.r9))
	r.op(r.t.move_immediate64(g.r10, decimal_binary_limbs - 1)!)
	r.place('${n}_shiftbody')
	r.op(r.t.load_slot(g.r9, 0, g.rax, 8)!)
	r.op(r.t.load_slot(g.r9, -8, g.rcx, 8)!)
	r.op(r.t.shift_wide_left(g.rax, g.rcx, 1)!)
	r.op(r.t.store_slot(g.r9, 0, g.rax, 8)!)
	r.op(r.t.add_immediate(g.r9, -8))
	r.op(r.t.add_immediate(g.r10, -1))
	r.branch(.not_equal, '${n}_shiftbody')
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.shift_left_word(g.rax, 1)!)
	r.op(r.t.store_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rsi, -1))
	r.jump('${n}_shiftloop')
	// The highest word that is not zero carries the coefficient's own power of ten,
	// and nothing above it is asked.
	r.place('${n}_built')
	r.op(r.t.move_immediate64(g.rdi, decimal_binary_limbs - 1)!)
	r.place('${n}_findtop')
	r.op(r.t.test_word(g.rdi)!)
	r.branch(.equal, '${n}_top')
	r.op(r.t.address_of_element(g.r11, g.rdi, 8, 0, g.r9)!)
	r.op(r.t.load_indirect(g.r9, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_top')
	r.op(r.t.add_immediate(g.rdi, -1))
	r.jump('${n}_findtop')
	r.place('${n}_top')
	// rsi is the digit dropped last, r8 whether any digit below it was not zero.
	r.op(r.t.xor_word(g.rsi, g.rsi)!)
	r.op(r.t.xor_word(g.r8, g.r8)!)
	r.place('${n}_drop')
	// Drop while the power of ten is below the format's smallest, which is where a
	// subnormal loses its low digits whatever its count.
	r.op(r.t.move_register64(g.rax, g.rbx)!)
	r.op(r.t.add_immediate(g.rax, i32(target.bias)))
	r.branch(.less, '${n}_dstep')
	// And drop while the coefficient still has more than the format's digits.
	r.op(r.t.move_register64(g.rax, g.rdi)!)
	r.op(r.t.add_immediate(g.rax, -2))
	r.branch(.greater_or_equal, '${n}_dstep')
	r.op(r.t.move_register64(g.rax, g.rdi)!)
	r.op(r.t.add_immediate(g.rax, -1))
	r.branch(.not_equal, '${n}_zero_top')
	r.op(r.t.load_slot(g.r11, 8, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rcx, pow_hi)!)
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.above, '${n}_dstep')
	r.branch(.below, '${n}_round')
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rcx, pow_lo)!)
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.above_or_equal, '${n}_dstep')
	r.jump('${n}_round')
	r.place('${n}_zero_top')
	if pow_hi != 0 {
		// Ten to the digits needs two words, so a coefficient that fits one is
		// below it whatever that word says.
		r.jump('${n}_round')
	} else {
		r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
		r.op(r.t.move_immediate64(g.rcx, pow_lo)!)
		r.op(r.t.subtract_word(g.rax, g.rcx)!)
		r.branch(.above_or_equal, '${n}_dstep')
		r.jump('${n}_round')
	}
	r.place('${n}_dstep')
	// One digit off the low end: the words are divided from the top down so each
	// quotient fits a word, and the remainder of the lowest word is the digit.
	r.op(r.t.address_of_element(g.r11, g.rdi, 8, 0, g.r9)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_register64(g.r14, g.rdi)!)
	r.op(r.t.add_immediate(g.r14, 1))
	r.op(r.t.move_immediate64(g.rcx, 10)!)
	r.place('${n}_dbody')
	r.op(r.t.load_indirect(g.r9, g.rax, 8)!)
	r.op(r.t.divide_pair(g.rcx)!)
	r.op(r.t.store_indirect(g.r9, g.rax, 8)!)
	r.op(r.t.add_immediate(g.r9, -8))
	r.op(r.t.add_immediate(g.r14, -1))
	r.branch(.not_equal, '${n}_dbody')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, '${n}_nofive')
	r.op(r.t.move_immediate64(g.r8, 1)!)
	r.place('${n}_nofive')
	r.op(r.t.move_register64(g.rsi, g.rdx)!)
	r.op(r.t.add_immediate(g.rbx, 1))
	// The top word can only lose a place one at a time: dividing by ten takes at
	// most four bits off the number.
	r.op(r.t.address_of_element(g.r11, g.rdi, 8, 0, g.r9)!)
	r.op(r.t.load_indirect(g.r9, g.rax, 8)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_dropped')
	r.op(r.t.test_word(g.rdi)!)
	r.branch(.equal, '${n}_dropped')
	r.op(r.t.add_immediate(g.rdi, -1))
	r.place('${n}_dropped')
	r.jump('${n}_drop')
	// Round once, to nearest with ties to even, from the digit dropped last and
	// whether anything below it was not zero.
	r.place('${n}_round')
	r.op(r.t.test_word(g.rsi)!)
	r.branch(.equal, '${n}_after')
	r.op(r.t.move_register64(g.rax, g.rsi)!)
	r.op(r.t.add_immediate(g.rax, -5))
	r.branch(.greater, '${n}_up')
	r.branch(.less, '${n}_after')
	r.op(r.t.test_word(g.r8)!)
	r.branch(.not_equal, '${n}_up')
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.and_immediate(g.rax, 1)!)
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_up')
	r.jump('${n}_after')
	r.place('${n}_up')
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, 1))
	r.op(r.t.store_slot(g.r11, 0, g.rax, 8)!)
	r.branch(.above_or_equal, '${n}_after')
	r.op(r.t.load_slot(g.r11, 8, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rax, 1))
	r.op(r.t.store_slot(g.r11, 8, g.rax, 8)!)
	r.place('${n}_after')
	// A coefficient that reached ten to the digits is one digit too many: it is ten
	// to the digits minus one under a power one higher.
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rcx, pow_lo)!)
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.not_equal, '${n}_load')
	r.op(r.t.load_slot(g.r11, 8, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rcx, pow_hi)!)
	r.op(r.t.subtract_word(g.rax, g.rcx)!)
	r.branch(.not_equal, '${n}_load')
	r.op(r.t.move_immediate64(g.rax, prev_lo)!)
	r.op(r.t.store_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.move_immediate64(g.rax, prev_hi)!)
	r.op(r.t.store_slot(g.r11, 8, g.rax, 8)!)
	r.op(r.t.add_immediate(g.rbx, 1))
	r.place('${n}_load')
	r.op(r.t.load_slot(g.r11, 0, g.rax, 8)!)
	r.op(r.t.load_slot(g.r11, 8, g.rdx, 8)!)
	r.op(r.t.move_register64(g.rcx, g.rbx)!)
	r.jump('${n}_finish')
	r.place('${n}_zero')
	r.op(r.t.xor_word(g.rax, g.rax)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.xor_word(g.rcx, g.rcx)!)
	r.place('${n}_finish')
	r.op(r.t.move_register64(g.r8, g.r15)!)
	r.op(r.t.move_register64(g.rdi, g.r12)!)
	r.call(decimal_quantize_name(dst))
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${n}_infinity')
	r.call(decimal_encode_name(dst))
	r.jump('${n}_done')
	r.place('${n}_infinity')
	e.decimal_write_special(mut r, target, false)!
	r.place('${n}_done')
	r.op(r.t.stack_release(decimal_binary_bytes))
	for saved in [g.r15, g.r14, g.r13, g.r12, g.rbx] {
		r.op(r.t.pop_register(saved))
	}
	r.op(r.t.ret())
}
