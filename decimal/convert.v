module decimal

import math

// decimal → double, and the pieces the conversion is built from.
//
// The value is mantissa * 10^exponent. The conversion below keeps sixty-four
// significant bits in a mantissa and remembers in a sticky bit whether anything
// was dropped, scaling by ten nineteen digits at a time, and rounds once at the
// end: to fifty-three bits for a normal result, fewer for a subnormal. The point
// of doing it here, in the compiler, is that a cast of a constant is folded
// exactly, and every constant in a test can be checked against the value gcc
// produces for it.
//
// This is not the routine the emitted code calls: a value in memory has to be
// converted by instructions the program carries, which is the emitter's work.
// This one is the specification that work is held to.

// pow10 is ten to the n for n up to nineteen, which is the largest power of ten
// that fits a 64-bit integer.
fn pow10(n int) u64 {
	mut p := u64(1)
	for _ in 0 .. n {
		p *= 10
	}
	return p
}

// bits_u128 is the number of significant bits in a 128-bit value, which is what
// the division step needs to scale its numerator by.
fn bits_u128(x u128) int {
	mut n := 0
	mut v := x
	for v > 0 {
		n++
		v >>= 1
	}
	return n
}

// keep_bits takes a product or a quotient that may be wider than the sixty-four
// bits the scaling keeps and returns its leading sixty-four bits, folding
// whatever was dropped into the sticky bit and saying how far the point moved.
// Taking p >> 64 instead of the leading bits is the mistake this exists to
// prevent: a product of about two to the hundred and three has only thirty-nine
// leading bits and sixty-four dropped ones, and the low half of the mantissa
// then comes back as zeros.
fn keep_bits(p u128, sticky_in bool) (u64, int, bool) {
	bits := bits_u128(p)
	if bits > 64 {
		drop := bits - 64
		dropped := sticky_in || (p & ((u128(1) << drop) - 1)) != 0
		return u64(p >> drop), drop, dropped
	}
	return u64(p), 0, sticky_in
}

// sign_bit is the double's sign bit for this value.
fn (v Value) sign_bit() u64 {
	return if v.sign { u64(0x8000000000000000) } else { u64(0) }
}

// to_f64_bits returns the value rounded to the nearest double, ties to even, as
// the sixty-four bits of that double.
pub fn (v Value) to_f64_bits() u64 {
	if v.special == .infinity {
		return v.sign_bit() | 0x7ff0000000000000
	}
	if v.special != .finite {
		return 0x7ff8000000000000
	}
	if v.digits.len == 0 {
		return v.sign_bit()
	}
	// The leading digits go into the mantissa exactly: nineteen of them fit a
	// 64-bit integer, and whatever is left over becomes a power of ten.
	lead := if v.digits.len < 19 { v.digits.len } else { 19 }
	mut mant := u64(0)
	for i in 0 .. lead {
		mant = mant * 10 + u64(v.digits[i] - `0`)
	}
	mut exp10 := v.exponent + (v.digits.len - lead)
	mut sticky := false
	mut e2 := 0
	if mant == 0 {
		return v.sign_bit()
	}
	// Keep the mantissa's leading bit at position 63, so every step below has a
	// full sixty-four bits to work with and knows how much of the value it holds.
	for mant & (u64(1) << 63) == 0 {
		mant <<= 1
		e2--
	}
	// Scale up: each step multiplies by a power of ten and drops whatever falls
	// below the mantissa's last bit, remembering that it was not zero.
	for exp10 > 0 {
		chunk := if exp10 > 19 { 19 } else { exp10 }
		p := u128(mant) * u128(pow10(chunk))
		kept, moved, dropped := keep_bits(p, sticky)
		mant = kept
		sticky = dropped
		e2 += moved
		for mant & (u64(1) << 63) == 0 {
			mant <<= 1
			e2--
		}
		exp10 -= chunk
	}
	// Scale down: each step divides by a power of ten, scaled so the quotient
	// keeps a full mantissa, and a non-zero remainder is something dropped.
	for exp10 < 0 {
		chunk := if -exp10 > 19 { 19 } else { -exp10 }
		d := u128(pow10(chunk))
		k := 63 + bits_u128(d) - bits_u128(u128(mant))
		mut numer := u128(mant)
		if k > 0 {
			numer <<= k
			e2 -= k
		}
		kept, moved, dropped := keep_bits(numer / d, sticky || (numer % d) != 0)
		mant = kept
		sticky = dropped
		e2 -= moved
		if mant == 0 {
			// The value is far below the smallest double: nothing is left.
			return v.sign_bit()
		}
		for mant & (u64(1) << 63) == 0 {
			mant <<= 1
			e2--
		}
		exp10 += chunk
	}
	// Round to the fifty-three bits a double keeps, ties to even, with the sticky
	// bit breaking a tie that the bits themselves cannot.
	mut significand := mant >> 11
	rest := mant & ((u64(1) << 11) - 1)
	half := u64(1) << 10
	if rest > half || (rest == half && (sticky || (significand & 1) == 1)) {
		significand++
	}
	// The mantissa sat at bit 63, so the value is significand * 2^(unbiased - 52)
	// and the double's exponent is the unbiased one.
	mut unbiased := 63 + e2
	if significand == (u64(1) << 53) {
		significand >>= 1
		unbiased++
	}
	if unbiased >= 1024 {
		return v.sign_bit() | 0x7ff0000000000000
	}
	if unbiased >= -1022 {
		return v.sign_bit() | (u64(unbiased + 1023) << 52) | (significand & ((u64(1) << 52) - 1))
	}
	// A subnormal keeps fewer bits: the leading one is dropped along with the
	// rest, and what falls below the halfway point decides the rounding.
	shift := -(unbiased + 1022)
	if shift >= 64 {
		return v.sign_bit()
	}
	mut denormal := significand
	rem := denormal & ((u64(1) << shift) - 1)
	denormal >>= shift
	h := u64(1) << (shift - 1)
	if rem > h || (rem == h && (sticky || (denormal & 1) == 1)) {
		denormal++
	}
	if denormal == (u64(1) << 52) {
		// Rounding carried the value up into the smallest normal.
		return v.sign_bit() | (u64(1) << 52)
	}
	return v.sign_bit() | denormal
}

// to_f64 is the value as a double, which is what a cast to `double` asks for.
pub fn (v Value) to_f64() f64 {
	return f64_from_bits(v.to_f64_bits())
}

// f64_from_bits reads the sixty-four bits of a double back as a value of the
// language. `math` has the same pair of conversions, and this module imports it
// for them rather than reaching for a pointer and hoping.
pub fn f64_from_bits(bits u64) f64 {
	return math.f64_from_bits(bits)
}

// f64_bits is the reverse: the sixty-four bits of a double, which the module's
// tests compare against the bits gcc produced.
pub fn f64_bits(x f64) u64 {
	return math.f64_bits(x)
}
