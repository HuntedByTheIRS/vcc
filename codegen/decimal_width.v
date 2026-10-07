module codegen

// This file holds the conversions that have a decimal on both sides: a value of
// one decimal width converted to one of the others, and a decimal written into
// an object at all. They follow codegen/decimal.v's decimal-to-double routine:
// the value is read where it lives and the result is written where it is going,
// and the routine a cast needs is emitted once per (source, destination) pair.
//
// The value a routine works on is the one codegen/decimal_convert.v's decode
// leaves behind: the coefficient as an integer in rax and rdx, the power of ten
// in rcx and the sign in r8. The rounding is the one gcc does and the one
// decimal/decimal.v's round writes: to the format's significant digits, ties to
// even, at the format's smallest exponent when the value is subnormal, and past
// it to an infinity.
import ast
import decimal
import types

// DecimalTarget gathers one format's constants so a routine that rounds or
// encodes for it reads them in one place.
struct DecimalTarget {
	format     decimal.Format
	digits     int
	bias       int
	emax       int
	max_biased int
	cbits      int
	bytes      int
	total      int
}

fn decimal_target(format decimal.Format) DecimalTarget {
	return DecimalTarget{
		format:     format
		digits:     format.digits()
		bias:       format.bias()
		emax:       format.exponent_max()
		max_biased: format.largest_biased_exponent()
		cbits:      format.coefficient_bits()
		bytes:      format.bytes()
		total:      format.bytes() * 8
	}
}

fn decimal_quantize_name(format decimal.Format) string {
	return 'vcc_decimal_quantize_${format.bytes()}'
}

fn decimal_encode_name(format decimal.Format) string {
	return 'vcc_decimal_encode_${format.bytes()}'
}

fn decimal_pair_name(src decimal.Format, dst decimal.Format) string {
	return 'vcc_decimal_${src.bytes()}_to_${dst.bytes()}'
}

// decimal_power10 is ten to a non-negative power, as the pair of words a routine
// compares or loads against.
fn decimal_power10(n int) (u64, u64) {
	mut v := u128(1)
	for _ in 0 .. n {
		v *= 10
	}
	return u64(v & 0xffffffffffffffff), u64((v >> 64) & 0xffffffffffffffff)
}

// decimal_store_words writes the encoded value, its low word in rax and its high
// word in rdx, to the address the destination left in rdi. A four-byte or an
// eight-byte format is one store; the sixteen-byte format is two.
fn (e Emitter) decimal_store_words(mut r DecimalRoutine, dst DecimalTarget) !void {
	g := r.reg
	if dst.bytes == 16 {
		r.op(r.t.store_slot(g.rdi, 0, g.rax, 8)!)
		r.op(r.t.store_slot(g.rdi, 8, g.rdx, 8)!)
	} else {
		r.op(r.t.store_slot(g.rdi, 0, g.rax, dst.bytes)!)
	}
}

// decimal_write_special writes the encoding of an infinity or a quiet NaN with
// the sign the caller left in r8.
fn (e Emitter) decimal_write_special(mut r DecimalRoutine, dst DecimalTarget, nan bool) !void {
	g := r.reg
	mut w := u128(if nan { 0b11111 } else { 0b11110 }) << (dst.total - 6)
	if nan {
		w |= u128(1) << (dst.total - 7)
	}
	r.op(r.t.move_immediate64(g.rax, u64(w & 0xffffffffffffffff))!)
	r.op(r.t.move_immediate64(g.rdx, u64((w >> 64) & 0xffffffffffffffff))!)
	if dst.total == 128 {
		r.op(r.t.move_register64(g.r10, g.r8)!)
		r.op(r.t.shift_left_word(g.r10, 63)!)
		r.op(r.t.or_word(g.rdx, g.r10)!)
	} else {
		r.op(r.t.move_register64(g.r10, g.r8)!)
		r.op(r.t.shift_left_word(g.r10, u8(dst.total - 1))!)
		r.op(r.t.or_word(g.rax, g.r10)!)
	}
	e.decimal_store_words(mut r, dst)!
}

// emit_decimal_quantize writes the routine that rounds a decoded value to one
// format's precision and range. On entry rax and rdx hold the coefficient, rcx
// the power of ten and r8 the sign; on return they hold the rounded coefficient
// and its power of ten, and r9 says whether the value is finite (zero) or an
// infinity (one).
//
// The coefficient is dropped a digit at a time by dividing by ten, so the
// decision to round up is taken from the digits themselves: the first digit
// dropped decides against five, and a five is a tie only when every digit below
// it is zero, which is rounded to the even coefficient.
fn (e Emitter) emit_decimal_quantize(mut r DecimalRoutine, dst DecimalTarget) !void {
	g := r.reg
	n := decimal_quantize_name(dst.format)
	k10_lo, k10_hi := decimal_power10(dst.digits)
	kprev_lo, kprev_hi := decimal_power10(dst.digits - 1)
	r.place(n)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	r.op(r.t.xor_word(g.r9, g.r9)!)
	// A zero is left for the encoder, which clamps the power it carries.
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_count')
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, '${n}_count')
	r.jump('${n}_return')
	// The coefficient's digits, counted by dividing a copy in r14 and r15.
	r.place('${n}_count')
	r.op(r.t.push_register(g.rax))
	r.op(r.t.push_register(g.rdx))
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.rdx)!)
	r.op(r.t.xor_word(g.r12, g.r12)!)
	r.place('${n}_count_loop')
	r.op(r.t.move_register64(g.r10, g.r14)!)
	r.op(r.t.move_register64(g.r11, g.r15)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.not_equal, '${n}_count_step')
	r.op(r.t.test_word(g.r11)!)
	r.branch(.equal, '${n}_counted')
	r.place('${n}_count_step')
	r.op(r.t.move_immediate64(g.rsi, 10)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.r11)!)
	r.op(r.t.add_immediate(g.r12, 1))
	r.jump('${n}_count_loop')
	r.place('${n}_counted')
	r.op(r.t.pop_register(g.rdx))
	r.op(r.t.pop_register(g.rax))
	// The digits to drop: enough to leave the format's precision, and enough to
	// bring a subnormal value up to the format's smallest exponent.
	r.op(r.t.move_register64(g.r13, g.r12)!)
	r.op(r.t.add_immediate(g.r13, -dst.digits))
	r.op(r.t.test_word(g.r13)!)
	r.branch(.greater_or_equal, '${n}_floor')
	r.op(r.t.xor_word(g.r13, g.r13)!)
	r.place('${n}_floor')
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.negate_word(g.r11)!)
	r.op(r.t.add_immediate(g.r11, -dst.bias))
	r.op(r.t.move_register64(g.r10, g.r13)!)
	r.op(r.t.subtract_word(g.r10, g.r11)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, '${n}_dropping')
	r.op(r.t.move_register64(g.r13, g.r11)!)
	r.place('${n}_dropping')
	r.op(r.t.test_word(g.r13)!)
	r.branch(.less_or_equal, '${n}_range')
	// Drop the digits, keeping the first one dropped in r14 and whether any below
	// it was not zero in r13.
	r.op(r.t.move_register64(g.r15, g.r13)!)
	r.op(r.t.xor_word(g.r13, g.r13)!)
	r.op(r.t.xor_word(g.r14, g.r14)!)
	r.place('${n}_drop_loop')
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.move_register64(g.r11, g.rdx)!)
	r.op(r.t.move_immediate64(g.rsi, 10)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.rbx, g.rdx)!)
	r.op(r.t.move_register64(g.rdx, g.r11)!)
	r.op(r.t.test_word(g.r14)!)
	r.branch(.equal, '${n}_drop_lower')
	r.op(r.t.move_immediate64(g.r13, 1)!)
	r.place('${n}_drop_lower')
	r.op(r.t.move_register64(g.r14, g.rbx)!)
	r.op(r.t.add_immediate(g.rcx, 1))
	r.op(r.t.add_immediate(g.r15, -1))
	r.branch(.not_equal, '${n}_drop_loop')
	r.op(r.t.move_register64(g.r10, g.r14)!)
	r.op(r.t.add_immediate(g.r10, -5))
	r.op(r.t.test_word(g.r10)!)
	r.branch(.less, '${n}_range')
	r.branch(.greater, '${n}_up')
	r.op(r.t.test_word(g.r13)!)
	r.branch(.not_equal, '${n}_up')
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.and_immediate(g.r10, 1)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.not_equal, '${n}_up')
	r.jump('${n}_range')
	r.place('${n}_up')
	r.op(r.t.add_immediate(g.rax, 1))
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_carry')
	r.op(r.t.add_immediate(g.rdx, 1))
	r.place('${n}_carry')
	// A coefficient that reached the precision plus one is one digit of ten too
	// many: the nines rounded to a one and five hundred zeros, which is ten to
	// the power kept one step up.
	r.op(r.t.move_register64(g.r10, g.rax)!)
	r.op(r.t.move_immediate64(g.r11, k10_lo)!)
	r.op(r.t.subtract_word(g.r10, g.r11)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.not_equal, '${n}_range')
	r.op(r.t.move_register64(g.r10, g.rdx)!)
	r.op(r.t.move_immediate64(g.r11, k10_hi)!)
	r.op(r.t.subtract_word(g.r10, g.r11)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.not_equal, '${n}_range')
	r.op(r.t.move_immediate64(g.rax, kprev_lo)!)
	r.op(r.t.move_immediate64(g.rdx, kprev_hi)!)
	r.op(r.t.add_immediate(g.rcx, 1))
	r.place('${n}_range')
	// The rounded coefficient's digits, and the power of its leading digit.
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_range_count')
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.equal, '${n}_normalize')
	r.place('${n}_range_count')
	r.op(r.t.push_register(g.rax))
	r.op(r.t.push_register(g.rdx))
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.rdx)!)
	r.op(r.t.xor_word(g.r12, g.r12)!)
	r.place('${n}_range_count_loop')
	r.op(r.t.move_register64(g.r10, g.r14)!)
	r.op(r.t.move_register64(g.r11, g.r15)!)
	r.op(r.t.test_word(g.r10)!)
	r.branch(.not_equal, '${n}_range_count_step')
	r.op(r.t.test_word(g.r11)!)
	r.branch(.equal, '${n}_range_counted')
	r.place('${n}_range_count_step')
	r.op(r.t.move_immediate64(g.rsi, 10)!)
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.op(r.t.move_register64(g.rax, g.r11)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r11, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.divide_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.r11)!)
	r.op(r.t.add_immediate(g.r12, 1))
	r.jump('${n}_range_count_loop')
	r.place('${n}_range_counted')
	r.op(r.t.pop_register(g.rdx))
	r.op(r.t.pop_register(g.rax))
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.add_reg64(g.r11, g.r12))
	r.op(r.t.add_immediate(g.r11, -1))
	r.op(r.t.move_register64(g.r10, g.r11)!)
	r.op(r.t.add_immediate(g.r10, -dst.emax))
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater, '${n}_infinity')
	r.place('${n}_normalize')
	// A value past the exponent field's largest is written with fewer digits and a
	// smaller power, which is the encoding gcc writes.
	r.op(r.t.move_register64(g.r11, g.rcx)!)
	r.op(r.t.add_immediate(g.r11, dst.bias))
	r.op(r.t.move_register64(g.r10, g.r11)!)
	r.op(r.t.add_immediate(g.r10, -dst.max_biased))
	r.op(r.t.test_word(g.r10)!)
	r.branch(.less_or_equal, '${n}_return')
	r.op(r.t.move_register64(g.r10, g.r12)!)
	r.op(r.t.add_immediate(g.r10, -dst.digits))
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, '${n}_infinity')
	r.op(r.t.move_register64(g.r13, g.rdx)!)
	r.op(r.t.move_immediate64(g.rsi, 10)!)
	r.op(r.t.multiply_pair(g.rsi)!)
	r.op(r.t.move_register64(g.r14, g.rax)!)
	r.op(r.t.move_register64(g.r15, g.rdx)!)
	r.op(r.t.move_register64(g.rax, g.r13)!)
	r.op(r.t.multiply_pair(g.rsi)!)
	r.op(r.t.add_reg64(g.rax, g.r15))
	r.op(r.t.move_register64(g.rdx, g.rax)!)
	r.op(r.t.move_register64(g.rax, g.r14)!)
	r.op(r.t.add_immediate(g.r12, 1))
	r.op(r.t.add_immediate(g.rcx, -1))
	r.jump('${n}_normalize')
	r.place('${n}_infinity')
	r.op(r.t.move_immediate64(g.r9, 1)!)
	r.place('${n}_return')
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// emit_decimal_encode writes the routine that turns a rounded coefficient, its
// power of ten and a sign into the format's encoding and stores it at the
// address the caller left in rdi. It is decimal/decimal.v's encode with the
// constants of one format: the small form when the coefficient fits the field,
// and the large form, whose leading bit is implied and which only the four- and
// eight-byte formats need, when it does not.
fn (e Emitter) emit_decimal_encode(mut r DecimalRoutine, dst DecimalTarget) !void {
	g := r.reg
	n := decimal_encode_name(dst.format)
	r.place(n)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.push_register(g.r12))
	r.op(r.t.push_register(g.r13))
	r.op(r.t.push_register(g.r14))
	r.op(r.t.push_register(g.r15))
	// A zero keeps the power it was written with, as far as the field holds it.
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${n}_biased')
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, '${n}_biased')
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.add_immediate(g.r10, dst.bias))
	r.op(r.t.test_word(g.r10)!)
	r.branch(.greater_or_equal, '${n}_zero_high')
	r.op(r.t.xor_word(g.r10, g.r10)!)
	r.place('${n}_zero_high')
	r.op(r.t.move_register64(g.r11, g.r10)!)
	r.op(r.t.add_immediate(g.r11, -dst.max_biased))
	r.op(r.t.test_word(g.r11)!)
	r.branch(.less_or_equal, '${n}_zero_ready')
	r.op(r.t.move_immediate64(g.r10, u64(dst.max_biased))!)
	r.place('${n}_zero_ready')
	if dst.bytes == 16 {
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(dst.cbits - 64))!)
		r.op(r.t.xor_word(g.rax, g.rax)!)
		r.op(r.t.move_register64(g.rdx, g.r11)!)
	} else {
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(dst.cbits))!)
		r.op(r.t.move_register64(g.rax, g.r11)!)
		r.op(r.t.xor_word(g.rdx, g.rdx)!)
	}
	r.jump('${n}_sign')
	r.place('${n}_biased')
	r.op(r.t.move_register64(g.r10, g.rcx)!)
	r.op(r.t.add_immediate(g.r10, dst.bias))
	// Does the coefficient fit the field's own width?
	if dst.bytes == 16 {
		r.op(r.t.move_immediate64(g.r11, u64(1) << u64(dst.cbits - 64))!)
		r.op(r.t.move_register64(g.r12, g.rdx)!)
		r.op(r.t.subtract_word(g.r12, g.r11)!)
		r.branch(.above_or_equal, '${n}_large')
		r.jump('${n}_small')
	} else {
		r.op(r.t.test_word(g.rdx)!)
		r.branch(.not_equal, '${n}_large')
		r.op(r.t.move_immediate64(g.r11, u64(1) << u64(dst.cbits))!)
		r.op(r.t.move_register64(g.r12, g.rax)!)
		r.op(r.t.subtract_word(g.r12, g.r11)!)
		r.branch(.above_or_equal, '${n}_large')
		r.jump('${n}_small')
	}
	r.place('${n}_small')
	if dst.bytes == 16 {
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(dst.cbits - 64))!)
		r.op(r.t.or_word(g.rdx, g.r11)!)
	} else {
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(dst.cbits))!)
		r.op(r.t.or_word(g.r11, g.rax)!)
		r.op(r.t.move_register64(g.rax, g.r11)!)
	}
	r.jump('${n}_sign')
	r.place('${n}_large')
	low := dst.cbits - 2
	if dst.bytes == 16 {
		r.op(r.t.move_immediate64(g.r11, (u64(1) << u64(low - 64)) - 1)!)
		r.op(r.t.and_word(g.rdx, g.r11)!)
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(low - 64))!)
		r.op(r.t.or_word(g.rdx, g.r11)!)
		r.op(r.t.move_immediate64(g.r11, u64(0b11) << u64(dst.total - 3 - 64))!)
		r.op(r.t.or_word(g.rdx, g.r11)!)
	} else {
		r.op(r.t.move_immediate64(g.r11, (u64(1) << u64(low)) - 1)!)
		r.op(r.t.and_word(g.rax, g.r11)!)
		r.op(r.t.move_register64(g.r11, g.r10)!)
		r.op(r.t.shift_left_word(g.r11, u8(low))!)
		r.op(r.t.or_word(g.rax, g.r11)!)
		r.op(r.t.move_immediate64(g.r11, u64(0b11) << u64(dst.total - 3))!)
		r.op(r.t.or_word(g.rax, g.r11)!)
	}
	r.place('${n}_sign')
	if dst.total == 128 {
		r.op(r.t.move_register64(g.r11, g.r8)!)
		r.op(r.t.shift_left_word(g.r11, 63)!)
		r.op(r.t.or_word(g.rdx, g.r11)!)
	} else {
		r.op(r.t.move_register64(g.r11, g.r8)!)
		r.op(r.t.shift_left_word(g.r11, u8(dst.total - 1))!)
		r.op(r.t.or_word(g.rax, g.r11)!)
	}
	r.place('${n}_place')
	e.decimal_store_words(mut r, dst)!
	r.op(r.t.pop_register(g.r15))
	r.op(r.t.pop_register(g.r14))
	r.op(r.t.pop_register(g.r13))
	r.op(r.t.pop_register(g.r12))
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// emit_decimal_pair writes one width's routine: the source is read where it
// lives, rounded to the destination and written where the destination lives,
// with the source's address in rax and the destination's in rdi. A special keeps
// its kind and its sign.
fn (e Emitter) emit_decimal_pair(mut r DecimalRoutine, src decimal.Format, dst decimal.Format) !void {
	g := r.reg
	name := decimal_pair_name(src, dst)
	target := decimal_target(dst)
	r.place(name)
	r.op(r.t.push_register(g.rbx))
	r.call(decimal_decode_name(src))
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${name}_special')
	r.call(decimal_quantize_name(dst))
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${name}_infinity')
	r.call(decimal_encode_name(dst))
	r.jump('${name}_done')
	r.place('${name}_infinity')
	e.decimal_write_special(mut r, target, false)!
	r.jump('${name}_done')
	r.place('${name}_special')
	r.op(r.t.move_register64(g.r10, g.r9)!)
	r.op(r.t.add_immediate(g.r10, -2))
	r.branch(.not_equal, '${name}_special_inf')
	e.decimal_write_special(mut r, target, true)!
	r.jump('${name}_done')
	r.place('${name}_special_inf')
	e.decimal_write_special(mut r, target, false)!
	r.place('${name}_done')
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// emit_decimal_address leaves the address of a decimal value in the accumulator,
// which is how this back end carries a decimal that is not a constant: the
// object holds the bytes and the routine reads them where they are. Only an
// object of a decimal type works, because anything else would have to be
// computed first, and the computation is itself refused by name.
fn (mut e Emitter) emit_decimal_address(expr ast.Expr, depth int) !void {
	if e.names_an_object(expr) {
		return e.emit_address(ast.Unary{
			op:   '&'
			expr: expr
			typ:  expr.typ
			line: expr_line(expr)
			col:  expr_col(expr)
		}, depth + 1)
	}
	e.diagnostics << problem(expr.line, expr.col, 'unsupported: a ${expr.typ.describe()} value is used where a decimal object is needed, and this back end reads a decimal only where it lives')
	return error('decimal value')
}

// emit_decimal_to_decimal writes a width conversion: the source object's address
// is left in rax, the object the value is going into is addressed into rdi, and
// the pair's routine converts between them where they are.
fn (mut e Emitter) emit_decimal_to_decimal(slot Slot, expr ast.Cast, depth int) !void {
	g := decimal_registers(e.target) or {
		e.diagnostics << problem(expr.line, expr.col, 'internal: the target has no register a decimal conversion needs')
		return error('decimal registers')
	}
	src := expr.expr.typ.kind.decimal_format()
	dst := expr.typ.kind.decimal_format()
	e.emit_decimal_address(expr.expr, depth)!
	e.append(e.target.move_register64(g.rsi, e.accumulator(expr.line, expr.col)!)!)
	e.leave_address(slot, expr.line, expr.col)!
	e.append(e.target.move_register64(g.rdi, e.accumulator(expr.line, expr.col)!)!)
	e.append(e.target.move_register64(g.rax, g.rsi)!)
	name := decimal_pair_name(src, dst)
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// emit_decimal_copy writes one decimal object into another: the bytes are read
// where the value is and written where it is going, a word at a time.
fn (mut e Emitter) emit_decimal_copy(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	g := decimal_registers(e.target) or {
		e.diagnostics << problem(line, col, 'internal: the target has no register a decimal conversion needs')
		return error('decimal registers')
	}
	e.emit_decimal_address(expr, depth)!
	e.append(e.target.move_register64(g.rsi, e.accumulator(line, col)!)!)
	e.leave_address(slot, line, col)!
	e.append(e.target.move_register64(g.rdi, e.accumulator(line, col)!)!)
	chunk := if slot.width >= 8 { 8 } else { 4 }
	mut at := 0
	for at < slot.width {
		e.append(e.target.load_indirect(g.rsi, g.r10, chunk)!)
		e.append(e.target.store_slot(g.rdi, 0, g.r10, chunk)!)
		at += chunk
		if at < slot.width {
			e.append(e.target.add_immediate(g.rsi, i32(chunk)))
			e.append(e.target.add_immediate(g.rdi, i32(chunk)))
		}
	}
}

// store_decimal_value writes a decimal into an object from a value that is not a
// constant: a value of another width converted into this one, an integer
// converted into it, or another object of the same type copied into it. It
// answers whether it wrote, and a value it does not know is left for the caller
// to refuse by name rather than written as something else.
fn (mut e Emitter) store_decimal_value(slot Slot, expr ast.Expr, line int, col int) !bool {
	if expr is ast.Cast {
		if !expr.typ.kind.is_decimal() {
			return false
		}
		if expr.expr.typ.kind.is_decimal() {
			if expr.expr.typ.kind.decimal_format() == expr.typ.kind.decimal_format()
				&& e.names_an_object(expr.expr) {
				// A cast that names the width the value already has changes
				// nothing, so the object is copied.
				e.emit_decimal_copy(slot, expr.expr, line, col, 0)!
				return true
			}
			e.emit_decimal_to_decimal(slot, expr, 0)!
			return true
		}
		if _ := decimal_integer_bytes(expr.expr.typ.kind) {
			e.emit_decimal_from_integer(slot, expr, 0)!
			return true
		}
		if expr.expr.typ.kind in [.double, .float] {
			e.emit_decimal_from_binary(slot, expr, 0)!
			return true
		}
		return false
	}
	if expr is ast.Unary {
		if !expr.typ.kind.is_decimal() {
			return false
		}
		if expr.op == '-' && expr.expr.typ.kind.is_decimal() {
			e.emit_decimal_negate(slot, expr, 0)!
			return true
		}
		if expr.op == '+' && expr.expr.typ.kind.is_decimal() && e.names_an_object(expr.expr) {
			e.emit_decimal_copy(slot, expr.expr, line, col, 0)!
			return true
		}
		return false
	}
	if expr.typ.kind.is_decimal() && e.names_an_object(expr) {
		e.emit_decimal_copy(slot, expr, line, col, 0)!
		return true
	}
	return false
}

// decimal_integer_bytes is how many bytes an integer type occupies, or none for
// a kind that is not an integer this back end converts. The 128-bit integers are
// left out: their value does not fit the coefficient field of any decimal format
// and the conversion is not one this back end makes.
fn decimal_integer_bytes(kind types.Kind) ?int {
	return match kind {
		.char_, .signed_char, .unsigned_char { 1 }
		.short, .unsigned_short { 2 }
		.int_, .unsigned_int { 4 }
		.long, .unsigned_long, .long_long, .unsigned_long_long { 8 }
		else { none }
	}
}

fn decimal_from_integer_name(size int, unsigned bool, dst decimal.Format) string {
	mark := if unsigned { 'u' } else { 's' }
	return 'vcc_decimal_from_${mark}${size}_to_${dst.bytes()}'
}

// emit_decimal_from_integer writes a conversion from an integer to a decimal
// width: the source's address is left in rax, the object the value is going into
// is addressed into rdi, and the routine reads the integer where it lives. The
// integer is exact, so the conversion is the integer's digits rounded to the
// destination's precision and range, which is the same rounding a width
// conversion uses.
fn (mut e Emitter) emit_decimal_from_integer(slot Slot, expr ast.Cast, depth int) !void {
	g := decimal_registers(e.target) or {
		e.diagnostics << problem(expr.line, expr.col, 'internal: the target has no register a decimal conversion needs')
		return error('decimal registers')
	}
	size := decimal_integer_bytes(expr.expr.typ.kind) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.expr.typ.describe()} is converted to ${expr.typ.describe()}, and only a 32- or 64-bit integer is')
		return error('decimal integer')
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
	name := decimal_from_integer_name(size, expr.expr.typ.kind.is_unsigned(), expr.typ.kind.decimal_format())
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// emit_decimal_from_integer_routine writes one integer width's routine: it reads
// the integer where it lives, takes its magnitude's digits, and rounds them into
// the destination format. The sign is the integer's, and an integer too large for
// the format saturates to an infinity.
fn (e Emitter) emit_decimal_from_integer_routine(mut r DecimalRoutine, size int, unsigned_kind bool, dst decimal.Format) !void {
	g := r.reg
	name := decimal_from_integer_name(size, unsigned_kind, dst)
	target := decimal_target(dst)
	r.place(name)
	r.op(r.t.push_register(g.rbx))
	r.op(r.t.move_register64(g.rsi, g.rax)!)
	match size {
		1 {
			if unsigned_kind {
				r.op(r.t.load_indirect_unsigned(g.rsi, g.rax, 1)!)
			} else {
				r.op(r.t.load_indirect(g.rsi, g.rax, 1)!)
			}
		}
		2 {
			if unsigned_kind {
				r.op(r.t.load_indirect_unsigned(g.rsi, g.rax, 2)!)
			} else {
				r.op(r.t.load_indirect(g.rsi, g.rax, 2)!)
			}
		}
		4 {
			r.op(r.t.load_indirect(g.rsi, g.rax, 4)!)
			if !unsigned_kind {
				r.op(r.t.sign_extend_word(g.rax, g.rax)!)
			}
		}
		else {
			r.op(r.t.load_indirect(g.rsi, g.rax, 8)!)
		}
	}
	r.op(r.t.xor_word(g.rcx, g.rcx)!)
	r.op(r.t.xor_word(g.r8, g.r8)!)
	if !unsigned_kind {
		r.op(r.t.test_word(g.rax)!)
		r.branch(.greater_or_equal, '${name}_positive')
		r.op(r.t.move_immediate64(g.r8, 1)!)
		r.op(r.t.negate_word(g.rax)!)
		r.place('${name}_positive')
	}
	r.op(r.t.xor_word(g.rdx, g.rdx)!)
	r.call(decimal_quantize_name(dst))
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${name}_infinity')
	r.call(decimal_encode_name(dst))
	r.jump('${name}_done')
	r.place('${name}_infinity')
	e.decimal_write_special(mut r, target, false)!
	r.place('${name}_done')
	r.op(r.t.pop_register(g.rbx))
	r.op(r.t.ret())
}

// decimal_is_zero_name is the routine that answers whether a decimal of one
// width is zero, which is what `!a` asks. A decimal is zero exactly when its
// coefficient is zero: the sign does not matter, and neither does the exponent,
// so a negative zero answers yes as gcc does.
fn decimal_is_zero_name(src decimal.Format) string {
	return 'vcc_decimal_is_zero_${src.bytes()}'
}

// emit_decimal_is_zero_routine writes that routine: it decodes the object where
// it lies and answers one when the coefficient is zero and the value is not a
// NaN or an infinity.
fn (e Emitter) emit_decimal_is_zero_routine(mut r DecimalRoutine, src decimal.Format) !void {
	g := r.reg
	name := decimal_is_zero_name(src)
	r.place(name)
	r.call(decimal_decode_name(src))
	r.op(r.t.xor_word(g.r10, g.r10)!)
	r.op(r.t.test_word(g.r9)!)
	r.branch(.not_equal, '${name}_done')
	r.op(r.t.test_word(g.rax)!)
	r.branch(.not_equal, '${name}_done')
	r.op(r.t.test_word(g.rdx)!)
	r.branch(.not_equal, '${name}_done')
	r.op(r.t.move_immediate64(g.r10, 1)!)
	r.place('${name}_done')
	r.op(r.t.move_register64(g.rax, g.r10)!)
	r.op(r.t.ret())
}

// emit_decimal_is_zero_test writes a `!a` whose operand is a decimal object. The
// object is read where it lies and the answer is an int, so the operand's value
// is never materialised in a register.
fn (mut e Emitter) emit_decimal_is_zero_test(unary ast.Unary, depth int) !void {
	if !e.names_an_object(unary.expr) {
		e.diagnostics << problem(unary.line, unary.col, 'unsupported: a decimal logical negation reads its operand where it lies, and a ${unary.expr.typ.describe()} result does not lie anywhere')
		return error('decimal object')
	}
	e.emit_address(ast.Unary{
		op:   '&'
		expr: unary.expr
		typ:  unary.expr.typ
		line: unary.line
		col:  unary.col
	}, depth + 1)!
	name := decimal_is_zero_name(unary.expr.typ.kind.decimal_format())
	e.decimal_convert_used[name] = true
	e.reference(e.target.call_near(0), .call_local, name, '')
}

// emit_decimal_negate writes `-a` into a decimal object: the value is the
// operand's bytes with the sign bit flipped, so the object is copied and the top
// byte's highest bit inverted. Nothing is rounded and nothing overflows.
fn (mut e Emitter) emit_decimal_negate(slot Slot, unary ast.Unary, depth int) !void {
	g := decimal_registers(e.target) or {
		e.diagnostics << problem(unary.line, unary.col, 'internal: the target has no register a decimal copy needs')
		return error('decimal registers')
	}
	e.emit_decimal_address(unary.expr, depth)!
	e.append(e.target.move_register64(g.rsi, e.accumulator(unary.line, unary.col)!)!)
	e.leave_address(slot, unary.line, unary.col)!
	e.append(e.target.move_register64(g.rdi, e.accumulator(unary.line, unary.col)!)!)
	chunk := if slot.width >= 8 { 8 } else { 4 }
	mut at := 0
	for at < slot.width {
		e.append(e.target.load_indirect(g.rsi, g.r10, chunk)!)
		e.append(e.target.store_slot(g.rdi, 0, g.r10, chunk)!)
		at += chunk
		if at < slot.width {
			e.append(e.target.add_immediate(g.rsi, i32(chunk)))
			e.append(e.target.add_immediate(g.rdi, i32(chunk)))
		}
	}
	e.append(e.target.add_immediate(g.rsi, i32(chunk - 1)))
	e.append(e.target.add_immediate(g.rdi, i32(chunk - 1)))
	e.append(e.target.load_indirect(g.rsi, g.r10, 1)!)
	e.append(e.target.move_immediate64(g.r11, u64(0x80))!)
	e.append(e.target.xor_word(g.r10, g.r11)!)
	e.append(e.target.store_slot(g.rdi, 0, g.r10, 1)!)
}
