module parser

import math
import math.big
import strconv
import types
import decimal

// Literal conversion. Both of these report instead of guessing: a constant that
// does not fit, or a digit that is not valid for the base it was written in, is
// exactly the kind of thing a compiler must not quietly turn into a number.

// parse_integer_literal reads an integer constant in any of the bases C allows.
// Suffixes are accepted and dropped here, since which type the suffix names is
// the type model's question and not this reader's.
//
// The value is accumulated as an unsigned 64-bit number so that the whole range
// of an `unsigned long long` is reachable: 18446744073709551615 is 2^64 - 1, and
// a program that writes it with a `ULL` suffix is a program this reader has to
// hand on rather than refuse. The result is returned as the 64-bit pattern, so a
// value whose top bit is set comes back as a negative i64 and the type model
// reads it as the unsigned value it was written as. Measured on gcc 16.2.1:
// `18446744073709551615ULL` is accepted and is `unsigned long long`.
fn parse_integer_literal(text string) !i64 {
	mut body := text
	for body.len > 0 && body[body.len - 1] in [`u`, `U`, `l`, `L`] {
		body = body[..body.len - 1]
	}
	if body == '' {
		return error('${text}: not an integer constant')
	}
	mut base := 10
	mut digits := body
	if body.len > 1 && body[0] == `0` && (body[1] == `x` || body[1] == `X`) {
		base = 16
		digits = body[2..]
		// A point or a `p` exponent makes the token a hexadecimal floating
		// constant, and the floating reader takes it. The main path never sends
		// one here, because is_floating_constant routes it, but `_BitInt` and
		// bitfield widths read their number directly, and a width written as a
		// float is not a width. Saying that is better than reporting the `p` as
		// a digit base 16 is missing.
		if digits.contains('.') || digits.contains('p') || digits.contains('P') {
			return error('${text}: not an integer constant')
		}
	} else if body.len > 1 && body[0] == `0` && (body[1] == `b` || body[1] == `B`) {
		base = 2
		digits = body[2..]
	} else if body.contains('.') || body.contains('e') || body.contains('E')
		|| body.ends_with('f') || body.ends_with('F') {
		return error('${text}: floating point literals are not implemented')
	} else if body.len > 1 && body[0] == `0` {
		base = 8
		digits = body[1..]
	}
	if digits == '' {
		// `0x` with nothing after it, which is a base marker and no number.
		return error('${text}: not an integer constant')
	}
	mut value := u64(0)
	for ch in digits {
		digit := digit_value(ch, base) or {
			return error('${text}: ${ch.ascii_str()} is not a digit in base ${base}')
		}
		step := u64(digit)
		if value > (max_u64 - step) / u64(base) {
			return error('${text}: integer constant does not fit in 64 bits')
		}
		value = value * u64(base) + step
	}
	return i64(value)
}

// max_u64 is the largest number 64 bits hold, which is the largest an integer
// constant may be. Past it the constant is not one this compiler can carry, and
// that is said rather than wrapped around to a smaller value.
const max_u64 = u64(18446744073709551615)

// is_floating_constant says whether a numeric token names a floating constant
// rather than an integer one. 6.4.4.2 makes that a question about the spelling
// and not about the value: a decimal constant is floating when it has a point or
// an exponent, so `1.0` and `1e3` are floating and `1` is not. A hexadecimal
// constant is floating when it is spelled as a hexadecimal floating constant, a
// point or a `p` exponent: `0x1.8p3` and `0x1p3` are, and `0x1E` is the integer
// 30. The `p` is what tells `0x1p3` from a hexadecimal integer, because `e` is a
// digit of base 16 and `p` is not, so neither can be read as the other's marker.
fn is_floating_constant(text string) bool {
	if text.len > 1 && text[0] == `0` && (text[1] == `x` || text[1] == `X`) {
		return text.contains('.') || text.contains('p') || text.contains('P')
	}
	return text.contains('.') || text.contains('e') || text.contains('E')
}

// is_long_double_constant says whether a floating constant is written with the
// `l` suffix, which names a long double. 6.4.4.2 makes the suffix the whole
// question of the constant's type, and this is asked only of a token the
// floating reader would take: `10L` is a long integer, not a floating constant.
fn is_long_double_constant(text string) bool {
	if text.len == 0 {
		return false
	}
	last := text[text.len - 1]
	return last == `l` || last == `L`
}

// is_float128_constant says whether a floating constant is written with the
// `f128` suffix, which C's Annex G and gcc give the `_Float128` type. The check
// is asked only of a token the floating reader would take, so `1f128` - which is
// not a floating constant, having no point and no exponent - is not one.
fn is_float128_constant(text string) bool {
	return text.len > 4 && (text.ends_with('f128') || text.ends_with('F128'))
}

// is_decimal_constant says whether a token is one of GNU C's decimal floating
// constants, which is a floating constant whose suffix is `df`, `dd` or `dl` in
// either case: the first names `_Decimal32`, the second `_Decimal64` and the third
// `_Decimal128`. 6.4.4.2 makes the suffix the whole question of the constant's type.
// A floating constant is one with a point or an exponent, so this asks
// `is_floating_constant` itself rather than trusting its callers to have asked.
//
// Measured on gcc 16.2.1, which is what the two guards are for: `1df` and `5df` are
// `invalid suffix 'df' on integer constant`, because they have neither a point nor
// an exponent and are integer constants, and `0x1p3df` is `invalid suffix 'df' with
// hexadecimal floating constant`, because a hexadecimal constant has no decimal
// suffix either. `0.0df`, `.5df` and `1e6df` are decimal constants, and `1.5d` is
// not one of these three: gcc reads the `d` alone as its own spelling of double.
//
// A caller must ask this before is_long_double_constant, because `dl` and `DL` end
// in the letter `l`: that check would send `1.5dl` to the long double reader, which
// takes one character off and refuses the `d` as a character no floating constant
// holds.
fn is_decimal_constant(text string) bool {
	if !is_floating_constant(text) {
		return false
	}
	if text.len > 1 && text[0] == `0` && (text[1] == `x` || text[1] == `X`) {
		return false
	}
	if text.len < 3 {
		return false
	}
	tail := text[text.len - 2..]
	return tail == 'df' || tail == 'DF' || tail == 'dd' || tail == 'DD' || tail == 'dl'
		|| tail == 'DL'
}

// decimal_kind_of is the kind the suffix of a decimal constant names. It is asked
// only of a token is_decimal_constant accepted, so the last two characters are one
// of the six spellings.
fn decimal_kind_of(text string) types.Kind {
	tail := text[text.len - 2..]
	if tail == 'df' || tail == 'DF' {
		return types.Kind.decimal32
	}
	if tail == 'dd' || tail == 'DD' {
		return types.Kind.decimal64
	}
	return types.Kind.decimal128
}

// parse_float128_literal reads a `_Float128` constant into the value it names.
// The digits are read by the same exact reader a long double constant uses, so
// the value is rounded once to sixty-four bits of significand; see the comment
// on the `float128` kind for what this back end does and does not compute with
// a value of the type. The suffix is four characters, so the body the readers
// take is the spelling with `f128` removed.
fn parse_float128_literal(text string) !types.LongDouble {
	if !is_float128_constant(text) {
		return error('${text}: not a _Float128 constant')
	}
	body := text[..text.len - 4]
	if body.len > 1 && body[0] == `0` && (body[1] == `x` || body[1] == `X`) {
		return parse_hex_long_double(text, body)
	}
	return parse_decimal_long_double(text, body)
}

// parse_long_double_literal reads a long double constant into the value it
// names, in the extended format the target gives `long double`.
//
// The value is computed here rather than handed to the host's double reader
// because a long double holds more precision than a double does, and a value
// rounded through a double first would be a different number: measured on gcc
// 16.2.1, `0.6L` is 0x3ffe9999999999999a and the double 0.6 rounded up to a
// long double is 0x3ffe99999999999a00. Both decimal and hexadecimal constants
// are read exactly and rounded once, to nearest with ties to even, which is the
// rule the hardware uses and the rule gcc's own reader uses.
fn parse_long_double_literal(text string) !types.LongDouble {
	if text.len < 2 {
		return error('${text}: not a floating constant')
	}
	body := text[..text.len - 1]
	if body.len > 1 && body[0] == `0` && (body[1] == `x` || body[1] == `X`) {
		return parse_hex_long_double(text, body)
	}
	return parse_decimal_long_double(text, body)
}

// DecimalParts is the digits and the power of ten the body of a decimal floating
// constant names: the value is digits * 10^exp, where digits is every digit the
// file wrote with the point taken out, leading zeros included.
struct DecimalParts {
	digits []u8
	exp    int
}

// read_decimal_parts walks the body of a decimal floating constant, which is the
// spelling with its suffix taken off: an integer part, a point and a fraction, and
// an `e` exponent. The digits are one unsigned integer D with the point removed
// and the exponent is the written one less the digits that followed the point, so
// the value is D * 10^exp. Both the long double reader and the decimal reader take
// their digits here rather than each walking the text again, so the two accept and
// refuse the same spellings.
fn read_decimal_parts(text string, body string) !DecimalParts {
	mut int_digits := []u8{}
	mut frac_digits := []u8{}
	mut exp_sign := 1
	mut exp_value := 0
	mut seen_point := false
	mut seen_exp := false
	mut seen_exp_digit := false
	mut i := 0
	for i < body.len {
		c := body[i]
		if c >= `0` && c <= `9` {
			if seen_exp {
				if exp_value < 1000000 {
					exp_value = exp_value * 10 + int(c - `0`)
				}
				seen_exp_digit = true
			} else if seen_point {
				frac_digits << c
			} else {
				int_digits << c
			}
			i++
			continue
		}
		if c == `.` {
			if seen_point || seen_exp {
				return error('${text}: not a floating constant')
			}
			seen_point = true
			i++
			continue
		}
		if c == `e` || c == `E` {
			if seen_exp {
				return error('${text}: not a floating constant')
			}
			seen_exp = true
			i++
			if i < body.len && (body[i] == `+` || body[i] == `-`) {
				if body[i] == `-` {
					exp_sign = -1
				}
				i++
			}
			continue
		}
		return error('${text}: ${c.ascii_str()} is not part of a floating constant')
	}
	if int_digits.len + frac_digits.len == 0 {
		return error('${text}: not a floating constant')
	}
	if seen_exp && !seen_exp_digit {
		return error('${text}: an exponent with no digits')
	}
	// D is the digits with the point removed, and the value is
	// D * 10^(written exponent - how many digits followed the point).
	mut all := int_digits
	all << frac_digits
	return DecimalParts{
		digits: all
		exp:    exp_sign * exp_value - frac_digits.len
	}
}

// parse_decimal_long_double reads the decimal form of a long double constant.
// The digits are an integer D, the constant is D * 10^exp, and the value is
// rounded to sixty-four bits of significand once.
fn parse_decimal_long_double(text string, body string) !types.LongDouble {
	parts := read_decimal_parts(text, body)!
	mut start := 0
	for start < parts.digits.len && parts.digits[start] == `0` {
		start++
	}
	if start == parts.digits.len {
		return types.LongDouble{}
	}
	significant := parts.digits[start..].clone()
	value := decimal_to_long_double(significant.bytestr(), parts.exp) or {
		return error('${text}: the constant is outside the range this reader converts')
	}
	return value
}

// decimal_range_warning is the warning gcc gives for a decimal constant the format
// cannot hold, and an empty string when the constant fitted. Measured on gcc 16.2.1
// on this machine, `double x = 1e400dd;` is `warning: floating constant exceeds range
// of '_Decimal64' [-Woverflow]` and `double x = 1e-400dd;` is `warning: floating
// constant truncated to zero [-Woverflow]`, and in neither case does gcc refuse the
// program: it stores an infinity for the first and a zero for the second - measured
// in `_Decimal32`, whose range ends at `1e96` and `1e-101`, `1e300df` is 0x78000000,
// an infinity, and `1e-300df` is 0x00000000, a zero. This reader reads the same way
// and puts the warning here, because a warning is not something a value can carry.
//
// Which of the two happened is read off the value and the source: a value past the
// format comes back an infinity, and a value the format truncated to zero comes back
// a zero from a source whose coefficient held a digit that is not zero. A source
// that wrote a zero of its own is not warned about, which is why the digits the
// warning looks at stop at the exponent - `0e5df` is a zero the file wrote.
fn decimal_range_warning(text string, value types.Decimal) string {
	if value.special == .infinity {
		return "floating constant exceeds range of '${types.decimal_type(value.kind).describe()}'"
	}
	if value.is_zero() && decimal_written_nonzero(text) {
		return 'floating constant truncated to zero'
	}
	return ''
}

// decimal_written_nonzero says whether the coefficient the source wrote held a digit
// other than zero. The exponent is not part of the answer: `0e5df` is a zero the
// file wrote, and only the digits in front of the `e` or `E` are the coefficient.
fn decimal_written_nonzero(text string) bool {
	for ch in text {
		if ch == `e` || ch == `E` {
			break
		}
		if ch >= `1` && ch <= `9` {
			return true
		}
	}
	return false
}

// parse_decimal_literal reads a decimal floating constant into the value it names,
// in the format its suffix chose. The reading is the `decimal` module's `from_text`,
// which takes the body, keeps the digits as written with the point removed and the
// exponent adjusted for it, and rounds once to the precision the format keeps - 7
// digits for `_Decimal32`, 16 for `_Decimal64`, 34 for `_Decimal128` - with ties to
// even. That module is the compiler's only rounding: the reader does not round a
// second time, because two roundings of one literal that disagree would be a bug with
// no owner. The format's own `from_suffix` names it from the suffix, `decimal_digits`
// answers the same precision out of the same module, and `clamp` is where the range
// rule lives.
//
// A zero keeps no digits and the exponent the source wrote, because the encoding of
// a zero carries its exponent: `0.0df` is the exponent -1, and gcc stores the field
// 100 for it.
//
// A constant outside the format's range is read, not refused: gcc warns and stores a
// value, so the module's `clamp` answers an infinity above the range and a zero below
// it, and `decimal_range_warning` is what says which of the two the source asked for.
// See it for the measurements.
fn parse_decimal_literal(text string) !types.Decimal {
	format := decimal.from_suffix(text) or {
		return error('${text}: not a decimal floating constant')
	}
	body := decimal.from_text(text[..text.len - 2], format)
	value := body.clamp(format)
	// A value the format truncated to zero keeps the power of ten the source wrote,
	// which is the same rule a zero the source wrote follows, and the encoding is
	// what brings it to the field. Measured on gcc 16.2.1, `1e-300df` and `1e-400dd`
	// are the bytes 00000000 and 0000000000000000 - the exponent field 0 - where
	// `0e30df` is 41800000 and `0e400dd` is 5fe0000000000000, the written power and
	// then the field's own largest.
	return types.Decimal{
		kind:     decimal_kind_of(text)
		sign:     value.sign
		digits:   value.digits
		exponent: if value.is_zero() && !body.is_zero() { body.exponent } else { value.exponent }
		special:  value.special
	}
}

// parse_hex_long_double reads the hexadecimal form, `0x` significand `p`
// exponent, into a long double. The significand D is a power-of-two multiple of
// an integer, D * 2^bin_exp, and it is rounded to sixty-four bits of significand
// once.
fn parse_hex_long_double(text string, body string) !types.LongDouble {
	after := body[2..]
	mut exponent_at := -1
	for i, ch in after {
		if ch == `p` || ch == `P` {
			exponent_at = i
			break
		}
	}
	if exponent_at < 0 {
		return error('${text}: hexadecimal floating constants require an exponent')
	}
	mantissa := after[..exponent_at]
	exponent := after[exponent_at + 1..]
	mut digits := []u8{}
	mut fractional := 0
	mut point_seen := false
	for ch in mantissa {
		if ch == `.` {
			if point_seen {
				return error('${text}: not a floating constant')
			}
			point_seen = true
			continue
		}
		if digit_value(ch, 16) == none {
			return error('${text}: ${ch.ascii_str()} is not part of a hexadecimal floating constant')
		}
		digits << ch
		if point_seen {
			fractional++
		}
	}
	if digits.len == 0 {
		return error('${text}: a hexadecimal floating constant has no digits')
	}
	mut i := 0
	mut negative := false
	if i < exponent.len && (exponent[i] == `+` || exponent[i] == `-`) {
		negative = exponent[i] == `-`
		i++
	}
	mut magnitude := 0
	mut exponent_digits := 0
	for i < exponent.len {
		ch := exponent[i]
		if ch < `0` || ch > `9` {
			break
		}
		if magnitude < 1000000 {
			magnitude = magnitude * 10 + int(ch - `0`)
		}
		exponent_digits++
		i++
	}
	if exponent_digits == 0 {
		return error('${text}: an exponent with no digits')
	}
	if negative {
		magnitude = -magnitude
	}
	// The digits name the integer D and the value is D * 2^(exp - 4*fractional).
	mut start := 0
	for start < digits.len && digits[start] == `0` {
		start++
	}
	if start == digits.len {
		return types.LongDouble{}
	}
	significant := digits[start..].clone()
	if significant.len > 32 {
		return error('${text}: the constant has more significant digits than this reader carries')
	}
	mut d := u128(0)
	for ch in significant {
		got := digit_value(ch, 16) or { return error('${text}: not a floating constant') }
		d = d * 16 + u128(got)
	}
	value := long_double_from_scaled(d, magnitude - 4 * fractional, false) or {
		return error('${text}: the constant is outside the range this reader converts')
	}
	return value
}

// decimal_to_long_double rounds D * 10^exp to the extended format. Positive
// exponents multiply out exactly into an integer; a negative exponent is a
// division, and the quotient is scaled by a power of two so that at least
// sixty-five bits of it survive, which is what holds the rounding bit and the
// sticky bit the nearest-even rule needs. It answers none when the arithmetic
// would need more bits than a 128-bit integer holds, which is a constant this
// reader does not carry rather than one it rounds wrongly.
fn decimal_to_long_double(significant string, exp int) ?types.LongDouble {
	// A power of ten this far from the digits cannot leave a value the extended
	// exponent field holds, whatever the digits are, so the arithmetic below is
	// kept to a size a string can carry. Ten to the five thousandth is past
	// every value the format reaches, and a decimal constant that far out is an
	// overflow rather than a constant this reader cannot carry: gcc 16.2.1
	// answers one with an infinity, measured on `1e10000L`, which is where
	// glibc's HUGE_VALL resolves outside a GNU dialect. A constant this far the
	// other way cannot reach the smallest value the reader computes exactly, so
	// it stays a refusal rather than an answer of zero.
	if exp > 5000 {
		return types.LongDouble{
			mantissa: u64(0x8000000000000000)
			sign_exp: u16(0x7fff)
		}
	}
	if exp < -5000 {
		return none
	}
	// The arithmetic is arbitrary precision because a constant may name more
	// digits, and a smaller power of ten, than any fixed-width integer holds:
	// `1.08420217248550443400745280086994171e-19L` is thirty-six digits over a
	// fifty-fourth power of ten, and rounding it through a fixed width first
	// would answer with a different number.
	mut numerator := big.integer_from_string(significant) or { return none }
	mut denominator := big.integer_from_string('1') or { return none }
	if exp >= 0 {
		power := big.integer_from_string(power_of_ten(exp)) or { return none }
		numerator = numerator * power
	} else {
		denominator = big.integer_from_string(power_of_ten(-exp)) or { return none }
	}
	if numerator.bit_len() == 0 {
		return types.LongDouble{}
	}
	// The value's leading bit sits at the difference of the two bit lengths, one
	// place lower when the numerator is the smaller of the two at that width.
	// Aligning to that place is what makes one division enough: the quotient of
	// the numerator scaled to the sixty-fourth place by the denominator is
	// sixty-four bits wide with its leading bit on top, and the remainder is
	// what the rounding reads.
	mut exponent := numerator.bit_len() - denominator.bit_len()
	if exponent >= 0 {
		if numerator < denominator.left_shift(u32(exponent)) {
			exponent--
		}
	} else {
		if numerator.left_shift(u32(-exponent)) < denominator {
			exponent--
		}
	}
	mut scaled := numerator
	mut divisor := denominator
	if exponent <= 63 {
		scaled = numerator.left_shift(u32(63 - exponent))
	} else {
		divisor = denominator.left_shift(u32(exponent - 63))
	}
	quotient, remainder := scaled.div_mod(divisor)
	mantissa := strconv.parse_uint(quotient.str(), 10, 64) or { return none }
	mut result := mantissa
	// Rounding to nearest with ties to even is twice the remainder against the
	// divisor, which is the same question as the first dropped bit and whether
	// anything followed it.
	if remainder.bit_len() > 0 {
		twice := remainder * big.integer_from_int(2)
		if twice > divisor || (twice == divisor && (mantissa & 1) == 1) {
			result++
			if result == 0 {
				// The significand rounded up out of sixty-four bits, so the
				// leading bit moved one place.
				return long_double_from_parts(u64(0x8000000000000000), exponent + 1)
			}
		}
	}
	return long_double_from_parts(result, exponent)
}

// power_of_ten is the decimal text of ten raised to a non-negative power, which
// is what the arbitrary-precision reader reads its power of ten from.
fn power_of_ten(k int) string {
	return '1' + '0'.repeat(k)
}

// long_double_from_parts builds the value from a sixty-four-bit significand,
// whose leading bit is the top bit of the word, and an unbiased power of two. A
// value whose exponent is outside the field is refused rather than answered
// with a wrong exponent.
fn long_double_from_parts(mantissa u64, exponent int) ?types.LongDouble {
	if mantissa == 0 {
		return types.LongDouble{}
	}
	field := exponent + 16383
	if field >= 0x7fff {
		// The value is past every value the extended format reaches, so it is
		// an infinity, which is what gcc 16.2.1 answers a constant that
		// overflows the type with: measured, `1e4933L` is above LDBL_MAX and
		// gcc and this reader both make it +inf. `long_double_from_scaled`
		// below answers the same way for the hexadecimal form.
		return types.LongDouble{
			mantissa: u64(0x8000000000000000)
			sign_exp: u16(0x7fff)
		}
	}
	if field <= 0 {
		// A subnormal or underflowing constant is outside what this reader
		// computes exactly, so it is refused rather than answered wrongly.
		return none
	}
	return types.LongDouble{
		mantissa: mantissa
		sign_exp: u16(field)
	}
}

// long_double_from_scaled rounds q * 2^bin_exp, where q is a non-negative
// integer and `sticky` says bits below q were dropped, to the extended format.
// The significand is the top sixty-four bits of q, rounded to nearest with ties
// to even, and the exponent is the position of q's leading bit plus bin_exp.
fn long_double_from_scaled(q u128, bin_exp int, sticky bool) ?types.LongDouble {
	if q == 0 {
		return types.LongDouble{}
	}
	bits := bit_len_u128(q)
	mut mantissa := u64(0)
	mut round_sticky := sticky
	if bits <= 64 {
		mantissa = u64(q) << (64 - bits)
	} else {
		shift := bits - 64
		mantissa = u64(q >> shift)
		guard := (q >> (shift - 1)) & 1 == 1
		if shift >= 2 && (q & ((u128(1) << (shift - 1)) - 1)) != 0 {
			round_sticky = true
		}
		if guard && (round_sticky || (mantissa & 1) == 1) {
			mantissa++
		}
	}
	mut exponent := (bits - 1) + bin_exp
	if mantissa == 0 {
		// The significand rounded up out of sixty-four bits: the leading bit
		// moved one place, and the mantissa is that bit alone.
		mantissa = u64(0x8000000000000000)
		exponent++
	}
	field := exponent + 16383
	if field >= 0x7fff {
		return types.LongDouble{
			mantissa: u64(0x8000000000000000)
			sign_exp: u16(0x7fff)
		}
	}
	if field <= 0 {
		// A subnormal or underflowing constant is outside what this reader
		// computes exactly, so it is refused rather than answered wrongly.
		return none
	}
	return types.LongDouble{
		mantissa: mantissa
		sign_exp: u16(field)
	}
}

// pow10_u128 is ten to the k as a 128-bit integer, and none past the largest
// power that fits, which is 10^38.
fn pow10_u128(k int) ?u128 {
	if k < 0 || k > 38 {
		return none
	}
	mut value := u128(1)
	for _ in 0 .. k {
		value *= 10
	}
	return value
}

// bit_len_u128 is how many bits the value needs, and zero for a zero.
fn bit_len_u128(x u128) int {
	mut count := 0
	mut value := x
	for value != 0 {
		count++
		value >>= 1
	}
	return count
}

// parse_floating_literal reads a floating constant into the value it names. A
// hexadecimal constant is a different shape answering the same question, what
// value the spelling names, so it is handed to its own reader; everything below
// is the decimal form.
//
// The suffix decides the type, and this answers with the value that type holds:
// a constant written with an `f` is a float, so the digits are rounded to single
// precision here and the answer is the double that float is. That is the whole
// point of the suffix: `0.1f` and `0.1` are different values, and reading the
// first as a double would give the program a number it did not write.
//
// The `l` suffix names a long double, which this compiler has no value for, so
// it is refused by name. Any other suffix is refused by the character scan
// below, because a constant this reader does not take is reported rather than
// read as the part it recognises.
fn parse_floating_literal(text string) !f64 {
	if text.len > 1 && text[0] == `0` && (text[1] == `x` || text[1] == `X`) {
		return parse_hex_floating_literal(text)
	}
	mut body := text
	mut single := false
	if body.len > 0 {
		last := body[body.len - 1]
		if last == `f` || last == `F` {
			single = true
			body = body[..body.len - 1]
		} else if last == `l` || last == `L` {
			return error('${text}: a long double literal names a type this compiler does not implement')
		}
	}
	if body == '' {
		return error('${text}: not a floating constant')
	}
	// The point may be the first or the last character, and 6.4.4.2 allows
	// both: `.5` and `5.` are floating constants, and `5.` is not the integer
	// 5 followed by nothing.
	mut digits := 0
	mut points := 0
	mut exponents := 0
	for i, ch in body {
		if ch == `.` {
			points++
			continue
		}
		if ch == `e` || ch == `E` {
			exponents++
			continue
		}
		if ch == `+` || ch == `-` {
			// A sign is part of the constant only when it follows the
			// exponent marker; anywhere else it is a token of its own and the
			// lexer would not have put it in this one.
			if i == 0 || (body[i - 1] != `e` && body[i - 1] != `E`) {
				return error('${text}: not a floating constant')
			}
			continue
		}
		if ch < `0` || ch > `9` {
			return error('${text}: ${ch.ascii_str()} is not part of a floating constant')
		}
		digits++
	}
	if digits == 0 {
		return error('${text}: not a floating constant')
	}
	if points > 1 || exponents > 1 {
		return error('${text}: not a floating constant')
	}
	if exponents == 1 {
		// The exponent needs digits after it, and an exponent part is what
		// makes `1e` a mistake rather than the integer 1.
		for i, ch in body {
			if ch == `e` || ch == `E` {
				rest := body[i + 1..]
				mut start := 0
				if rest.len > 0 && (rest[0] == `+` || rest[0] == `-`) {
					start = 1
				}
				if rest.len <= start {
					return error('${text}: an exponent with no digits')
				}
				break
			}
		}
	}
	value := strconv.atof64(body) or { return error('${text}: not a floating constant') }
	if single {
		// Rounded once, here, so that the value the tree carries is the value a
		// float holds. Every later use of it - a store, a conversion, the
		// bytes written into the image - is then exactly that value, and no
		// two of them can round it differently.
		return f64(f32(value))
	}
	return value
}

// imaginary_suffix_removed answers what is left of a numeric token once its
// imaginary suffix is taken off, and whether there was one. 6.4.4.2 makes `i`
// and `j` the marker of an imaginary constant, and gcc 16.2.1 accepts the marker
// on either side of the floating suffix: measured, `1.0if`, `1.0iF` and `1.0Fi`
// are an eight-byte `float _Complex` and `1.0i` is a sixteen-byte
// `double _Complex`. `_Complex_I` in <complex.h> is the first of those, written
// `1.0iF`, so the marker is taken wherever it sits rather than in one order
// only.
//
// Only the marker comes off. What is left keeps its own floating suffix so that
// it reaches the reader that rounds a constant once, at the width the suffix
// names: `0.1if` rounded here and then converted would be a value a float never
// holds, and a float the program did not write.
fn imaginary_suffix_removed(text string) (string, bool) {
	if text.len == 0 {
		return text, false
	}
	last := text[text.len - 1]
	if last == `i` || last == `j` || last == `I` || last == `J` {
		return text[..text.len - 1], true
	}
	if text.len > 1 && (last == `f` || last == `F` || last == `l` || last == `L`) {
		before := text[text.len - 2]
		if before == `i` || before == `j` || before == `I` || before == `J` {
			return text[..text.len - 2] + text[text.len - 1..], true
		}
	}
	return text, false
}

// is_imaginary_constant says whether a numeric token names an imaginary constant
// rather than an integer or a real one.
fn is_imaginary_constant(text string) bool {
	_, imaginary := imaginary_suffix_removed(text)
	return imaginary
}

// parse_imaginary_literal reads an imaginary constant into the value of its
// imaginary part and says whether the component type is float rather than
// double. 6.4.4.2 leaves the real part zero, so `1.0i` is the value 1.0 in the
// imaginary position and nothing in the real one, and the value is the one the
// floating reader gives the coefficient.
//
// The suffix attaches to a floating constant, and the two refusals here are the
// spellings that are not one. A `long double _Complex` is named and refused here
// because this constant reader carries the extended value of a real constant and
// has no form for the imaginary one: the type is carried now, so the refusal is
// the reader's, at the constant, and not the compiler's. An
// integer coefficient is refused as well, because gcc 16.2.1 reads `1i` as a
// `float _Complex` and answering a `double _Complex` for it would be a type the
// program did not write.
fn parse_imaginary_literal(text string) !(f64, bool) {
	body, imaginary := imaginary_suffix_removed(text)
	if !imaginary || body == '' {
		return error('${text}: not an imaginary constant')
	}
	if body.ends_with('l') || body.ends_with('L') {
		return error('${text}: a long double imaginary constant names a long double complex, which this constant reader does not carry; write the value as a real long double constant times `I` instead')
	}
	if !is_floating_constant(body) {
		return error('${text}: an imaginary constant is written on a floating constant, and ${body} is not one')
	}
	value := parse_floating_literal(body) or { return error(err.msg()) }
	// The floating suffix, which the reader above has already rounded for, is
	// what names the component type: `1.0if` is a float complex and `1.0i` is a
	// double one.
	single := body.ends_with('f') || body.ends_with('F')
	return value, single
}

// parse_hex_floating_literal reads a hexadecimal floating constant, which C99
// 6.4.4.2 spells as `0x`, hexadecimal digits with an optional point, and a
// binary exponent introduced by `p` or `P`. The exponent is required. Without
// one, `0x1E` is a hexadecimal integer and `0x1.8` is neither an integer nor a
// constant, which is why gcc 16.2.1 refuses `0x1.8` with `hexadecimal floating
// constants require an exponent`.
//
// The value of a hexadecimal floating constant is a scaled power of two, so it
// is a dyadic rational and can be held exactly. The reader rounds it to the
// width the suffix names with the rule the hardware uses, to nearest with ties
// to even, so the bits it produces are the bits gcc's reader produces from the
// same spelling. A value past the range of its type becomes an infinity, which
// is what gcc 16.2.1 warns about and then compiles.
fn parse_hex_floating_literal(text string) !f64 {
	if text.len < 2 || text[0] != `0` || (text[1] != `x` && text[1] != `X`) {
		return error('${text}: not a hexadecimal floating constant')
	}
	body := text[2..]
	mut exponent_at := -1
	for i, ch in body {
		if ch == `p` || ch == `P` {
			exponent_at = i
			break
		}
	}
	if exponent_at < 0 {
		return error('${text}: hexadecimal floating constants require an exponent')
	}
	mantissa := body[..exponent_at]
	exponent := body[exponent_at + 1..]
	// The significand: hexadecimal digits with at most one point, and at least
	// one digit of either kind. `0x.8` has none before the point and `0x.p1`
	// none after it, and both are short of a significand.
	mut digits := []u8{}
	mut fractional := 0
	mut point_seen := false
	for ch in mantissa {
		if ch == `.` {
			if point_seen {
				return error('${text}: not a floating constant')
			}
			point_seen = true
			continue
		}
		if digit_value(ch, 16) == none {
			return error('${text}: ${ch.ascii_str()} is not part of a hexadecimal floating constant')
		}
		digits << ch
		if point_seen {
			fractional++
		}
	}
	if digits.len == 0 {
		return error('${text}: a hexadecimal floating constant has no digits')
	}
	// The binary exponent: a sign and decimal digits, the digits required,
	// which is what makes `0x1p` and `0x1p+` mistakes rather than numbers.
	mut i := 0
	mut negative := false
	if i < exponent.len && (exponent[i] == `+` || exponent[i] == `-`) {
		negative = exponent[i] == `-`
		i++
	}
	mut magnitude := 0
	mut exponent_digits := 0
	for i < exponent.len {
		ch := exponent[i]
		if ch < `0` || ch > `9` {
			break
		}
		// The exponent is only compared against the range of the type, so once
		// it is past any range the accumulator stops growing. A long run of
		// digits then cannot overflow it, and the sign still travels.
		if magnitude < 1000000 {
			magnitude = magnitude * 10 + int(ch - `0`)
		}
		exponent_digits++
		i++
	}
	if exponent_digits == 0 {
		return error('${text}: an exponent with no digits')
	}
	suffix := exponent[i..]
	mut single := false
	if suffix.len == 1 && (suffix[0] == `f` || suffix[0] == `F`) {
		single = true
	} else if suffix.len == 1 && (suffix[0] == `l` || suffix[0] == `L`) {
		return error('${text}: a long double literal names a type this compiler does not implement')
	} else if suffix.len > 0 {
		return error('${text}: ${suffix[0].ascii_str()} is not part of a floating constant')
	}
	if negative {
		magnitude = -magnitude
	}
	// The digits name the integer D and the value is D * 16^-fractional * 2^exp,
	// which is D * 2^(exp - 4*fractional).
	return hex_scaled_to_float(digits, magnitude - 4 * fractional, single)
}

// hex_scaled_to_float converts D * 2^e, where D is the hexadecimal integer whose
// digits are `digits`, to the floating type named, rounding to nearest with ties
// to even. It handles the subnormal range and overflows to an infinity, which is
// the value the hardware and gcc produce for the same spelling.
fn hex_scaled_to_float(digits []u8, e int, single bool) f64 {
	mut start := 0
	for start < digits.len && digits[start] == `0` {
		start++
	}
	if start == digits.len {
		return 0.0
	}
	d := digits[start..]
	nbits := 4 * (d.len - 1) + nibble_bits(d[0])
	// The unbiased exponent of D's most significant bit.
	u0 := nbits - 1 + e
	p := if single { 24 } else { 53 }
	emin := if single { -126 } else { -1022 }
	emax := if single { 127 } else { 1023 }
	bias := if single { 127 } else { 1023 }
	frac_bits := p - 1
	sub := emin - frac_bits
	// The unit the answer rounds to: a normal value to the last bit its own
	// leading exponent allows, a subnormal to the last bit the format holds,
	// which is a fixed position rather than one that moves with the value.
	step := if u0 >= emin { u0 - frac_bits } else { sub }
	mut m := round_bits(d, nbits, e, step)
	mut pattern := u64(0)
	if u0 >= emin {
		mut field := u0 + bias
		// A carry out of the significand raises the exponent by one, and m
		// becomes the leading bit alone.
		if m == (u64(1) << p) {
			m >>= 1
			field++
		}
		if field > (emax + bias) {
			return hex_infinity(single)
		}
		pattern = (u64(field) << frac_bits) | (m & ((u64(1) << frac_bits) - 1))
	} else {
		if m >= (u64(1) << frac_bits) {
			// A carry out of the subnormal range has reached the smallest
			// normal, whose exponent field is one and whose fraction is zero.
			pattern = u64(1) << frac_bits
		} else {
			pattern = m
		}
	}
	if single {
		return f64(math.f32_from_bits(u32(pattern)))
	}
	return math.f64_from_bits(pattern)
}

// round_bits is the number of units of 2^step that D * 2^e is nearest, rounding
// to nearest with ties to even against the bits below the unit. D's hexadecimal
// digits are read most significant first; the unit sits `step - e` bits above
// D's last bit, so that many bits are dropped, and a negative count means D is
// narrower than the unit and the value is exact.
fn round_bits(d []u8, nbits int, e int, step int) u64 {
	shift := step - e
	mut m := u64(0)
	if shift <= 0 {
		for k in 0 .. nbits {
			bit := if hex_bit(d, nbits - 1 - k) { u64(1) } else { u64(0) }
			m = (m << 1) | bit
		}
		return m << (-shift)
	}
	for k in 0 .. (nbits - shift) {
		bit := if hex_bit(d, nbits - 1 - k) { u64(1) } else { u64(0) }
		m = (m << 1) | bit
	}
	guard := hex_bit(d, shift - 1)
	mut sticky := false
	for k in 0 .. (shift - 1) {
		if hex_bit(d, k) {
			sticky = true
			break
		}
	}
	// Round up when the dropped part is past half, or is exactly half with an
	// odd unit, which is the tie going to the even neighbour.
	if guard && (sticky || ((m & 1) == 1)) {
		m++
	}
	return m
}

// hex_bit is bit `i` of D, counting from the least significant bit, where D's
// hexadecimal digits are held most significant first. A position the digits do
// not reach is a zero bit.
fn hex_bit(digits []u8, i int) bool {
	if i < 0 {
		return false
	}
	at := digits.len - 1 - i / 4
	if at < 0 || at >= digits.len {
		return false
	}
	value := digit_value(digits[at], 16) or { return false }
	return (value & (1 << (i % 4))) != 0
}

// nibble_bits is how many bits a hexadecimal digit has, four when the top bit is
// set and fewer otherwise. The first digit of a significand is never zero.
fn nibble_bits(v u8) int {
	mut bits := 4
	mut mask := u8(8)
	for (v & mask) == 0 {
		bits--
		mask >>= 1
	}
	return bits
}

// hex_infinity is the infinity a hexadecimal floating constant past the range of
// its type becomes. gcc 16.2.1 warns `floating constant exceeds range` and
// compiles the infinity, so the value is the one it produced.
fn hex_infinity(single bool) f64 {
	if single {
		return f64(math.f32_from_bits(u32(0x7f800000)))
	}
	return math.f64_from_bits(u64(0x7ff0000000000000))
}

// parse_character_literal reads a character constant into its value. The result
// is an int in C, so that is what it becomes here.
fn parse_character_literal(text string) !i64 {
	mut body := text
	mut narrow := true
	if body.len > 0 && (body[0] == `L` || body[0] == `u` || body[0] == `U`) {
		body = body[1..]
		narrow = false
	}
	if body.len < 2 || body[0] != `'` || body[body.len - 1] != `'` {
		return error('${text}: not a character constant')
	}
	inner := body[1..body.len - 1]
	if inner == '' {
		return error('${text}: empty character constant')
	}
	if inner[0] != `\\` {
		if inner.len > 1 {
			return error('${text}: multi-character constants are not implemented')
		}
		return i64(inner[0])
	}
	if inner.len >= 2 && (inner[1] == `u` || inner[1] == `U`) {
		// A universal character name in a character constant names one
		// character. A narrow constant takes its execution-set encoding, which
		// is UTF-8, packed into the int the way gcc packs a multi-character
		// constant: measured on gcc 16.2.1, '\u00E9' is 0xC3A9, '\U0001F600'
		// is 0xF09F9880 and '\U00020000' is 0xF0A08080. A wide one takes the
		// code point itself: L'\u00E9' is 233 and L'\U0001F600' is 128512.
		name, _ := parse_ucn(inner, 1) or { return error('${text}: ${err.msg()}') }
		if narrow {
			return ucn_value(name)
		}
		return i64(name)
	}
	return parse_escape(inner[1..]) or { error('${text}: ${err.msg()}') }
}

fn parse_escape(rest string) !i64 {
	if rest == '' {
		return error('the escape is not finished')
	}
	c := rest[0]
	if c == `x` || c == `X` {
		mut value := i64(0)
		mut seen := 0
		for i in 1 .. rest.len {
			digit := digit_value(rest[i], 16) or { break }
			value = value * 16 + i64(digit)
			seen++
		}
		if seen == 0 {
			return error('hex escape without digits')
		}
		return value
	}
	if c >= `0` && c <= `7` {
		mut value := i64(0)
		mut seen := 0
		for i in 0 .. rest.len {
			if seen == 3 {
				break
			}
			digit := digit_value(rest[i], 8) or { break }
			value = value * 8 + i64(digit)
			seen++
		}
		return value
	}
	return match c {
		`a` { i64(7) }
		`b` { i64(8) }
		`f` { i64(12) }
		`n` { i64(10) }
		`r` { i64(13) }
		`t` { i64(9) }
		`v` { i64(11) }
		`\\` { i64(92) }
		`'` { i64(39) }
		`"` { i64(34) }
		`?` { i64(63) }
		// GNU's `\e` is the escape character, and gcc 16.2.1 knows it: measured, a
		// program printing `'\e'` prints 27 and gcc says nothing about it, in every
		// mode it has.
		`e` { i64(27) }
		// An escape gcc does not know is the character itself: measured on gcc
		// 16.2.1, `\q` is 113 and `\8` is 56 and `\`` is 96, each with a `warning:
		// unknown escape sequence`, silent under -w and an error only under
		// -pedantic-errors. Refusing them stops a program gcc compiles, and V's own
		// generated C is one: it writes `'\`'` where `'`'` would do, and every one
		// of the 47 lines of it this compiler refused named the backtick. The warning
		// is owed rather than dropped: it is a diagnostic the standard requires,
		// which is the class -pedantic-errors promotes, and the parser's diagnostic
		// sink carries no class yet.
		else { i64(c) }
	}
}

// parse_ucn reads the universal character name `\uXXXX` or `\UXXXXXXXX` whose
// `u` or `U` sits at `at` in the literal's inner text, and answers the code
// point it names and where the text after it starts. C99 6.4.3 makes the two
// spellings four and eight hexadecimal digits; a name with fewer is not a name
// and is reported in gcc 16.2.1's own words, `incomplete universal character
// name \u00E`. A name that stands for no character, which is the surrogate
// range and everything past the largest the conversion holds, is reported the
// same way gcc reports it in a literal: `\uD800 is not a valid universal
// character`. Both messages are measured against gcc 16.2.1 one input at a time.
fn parse_ucn(inner string, at int) !(u32, int) {
	width := if inner[at] == `u` { 4 } else { 8 }
	mut spelling := '\\' + inner[at].ascii_str()
	mut value := u32(0)
	mut i := at + 1
	mut seen := 0
	for seen < width && i < inner.len {
		c := inner[i]
		if c == `\n` {
			break
		}
		digit := digit_value(c, 16) or { break }
		value = value * 16 + u32(digit)
		spelling += c.ascii_str()
		seen++
		i++
	}
	if seen < width {
		return error('incomplete universal character name ${spelling}')
	}
	if (value >= 0xD800 && value <= 0xDFFF) || value > 0x7FFFFFFF {
		return error('${spelling} is not a valid universal character')
	}
	return value, i
}

// encode_utf8 writes a code point in UTF-8, the execution character set every
// mainstream toolchain uses for a narrow literal. The carries run to six bytes
// rather than four because gcc accepts a UCN up to \U7FFFFFFF and encodes it
// anyway; measured, `"\U7FFFFFFF"` is `fd bf bf bf bf bf`.
fn encode_utf8(cp u32) []u8 {
	if cp < 0x80 {
		return [u8(cp)]
	}
	mut len := 2
	if cp >= 0x4000000 {
		len = 6
	} else if cp >= 0x200000 {
		len = 5
	} else if cp >= 0x10000 {
		len = 4
	} else if cp >= 0x800 {
		len = 3
	}
	mut out := []u8{len: len}
	lead := match len {
		2 { u8(0xC0) }
		3 { u8(0xE0) }
		4 { u8(0xF0) }
		5 { u8(0xF8) }
		else { u8(0xFC) }
	}
	mut shift := (len - 1) * 6
	out[0] = lead | u8((cp >> shift) & u32(0x3F))
	for k in 1 .. len {
		shift = (len - 1 - k) * 6
		out[k] = u8(0x80) | u8((cp >> shift) & u32(0x3F))
	}
	return out
}

// ucn_value is the value a universal character name gives an integer character
// constant. gcc writes the character's encoding into the int, most significant
// byte first, and keeps the last four bytes when the encoding is longer than
// the int. Measured on gcc 16.2.1: '\u00E9' is 0xC3A9, '\U0001F600' is
// 0xF09F9880, and '\U7FFFFFFF' is 0xBFBFBFBF, the tail of the six-byte encoding.
fn ucn_value(cp u32) i64 {
	bytes := encode_utf8(cp)
	start := if bytes.len > 4 { bytes.len - 4 } else { 0 }
	mut packed := u32(0)
	for b in bytes[start..] {
		packed = (packed << 8) | u32(b)
	}
	return i64(i32(packed))
}

// StringLiteral is the object a string literal names: the bytes of its
// characters with the escapes resolved, how wide one character is in those
// bytes, and how many characters the literal holds before the terminator it does
// not write. A narrow literal's characters are bytes one wide; a wide one's are
// the wchar_t this target gives, four bytes each, held little-endian.
struct StringLiteral {
	value string
	unit  int
	count int
}

// parse_string_literal reads a string literal into the bytes it names, with the
// escapes resolved. The spelling stays with the caller; what comes back is what
// the program would read.
fn parse_string_literal(text string) !StringLiteral {
	mut body := text
	mut unit := 1
	if body.len > 0 && body[0] != `"` {
		// A prefixed literal: u8"x", L"x", u"x", U"x". The narrow prefix names
		// the same bytes, `L` names a wide literal whose characters are the
		// wchar_t this target gives, and `u` and `U` name char16_t and char32_t,
		// which are header types this compiler does not have and are refused by
		// name rather than guessed at.
		mut quote := 0
		for quote < body.len && body[quote] != `"` {
			quote++
		}
		prefix := body[..quote]
		if prefix == 'L' {
			unit = 4
		} else if prefix != 'u8' {
			return error('${text}: a ${prefix}-prefixed string literal names a type this compiler does not have')
		}
		body = body[quote..]
	}
	if body.len < 2 || body[0] != `"` || body[body.len - 1] != `"` {
		return error('${text}: not a string constant')
	}
	inner := body[1..body.len - 1]
	if unit == 4 {
		return parse_wide_string(text, inner)
	}
	mut bytes := []u8{}
	mut i := 0
	for i < inner.len {
		c := inner[i]
		if c != `\\` {
			bytes << c
			i++
			continue
		}
		if i + 1 < inner.len && inner[i + 1] == `\n` {
			// A backslash before the newline joins the two lines, and the pair
			// produces no byte at all.
			i += 2
			continue
		}
		if i + 1 < inner.len && (inner[i + 1] == `u` || inner[i + 1] == `U`) {
			// A universal character name names one character, and a narrow
			// literal writes it in the execution character set, which is
			// UTF-8, so one name can be several bytes. Measured on gcc
			// 16.2.1: "\u00E9" is c3 a9 and "\U0001F600" is f0 9f 98 80.
			name, next := parse_ucn(inner, i + 1) or {
				return error('${text}: ${err.msg()}')
			}
			bytes << encode_utf8(name)
			i = next
			continue
		}
		value, next := parse_string_escape(inner, i + 1) or {
			return error('${text}: ${err.msg()}')
		}
		if value > 255 {
			return error('${text}: the escape names ${value}, which is not a byte')
		}
		bytes << u8(value)
		i = next
	}
	return StringLiteral{
		value: bytes.bytestr()
		unit:  1
		count: bytes.len
	}
}

// parse_wide_string reads the characters of a wide literal into the wchar_t
// values they name, each written as the four little-endian bytes the target
// reads. An escape names a character by its value directly, and a source
// character is decoded from UTF-8, which is the encoding gcc reads a wide
// literal's plain characters in: measured on gcc 16.2.1, the two source bytes
// of an e-acute are one wchar_t of 233, and so is the hex escape `\xe9`.
//
// A value that does not fit the signed 32-bit wchar_t this target gives is
// reported here rather than truncated into some other character.
fn parse_wide_string(text string, inner string) !StringLiteral {
	mut bytes := []u8{}
	mut count := 0
	mut i := 0
	for i < inner.len {
		c := inner[i]
		mut value := i64(0)
		if c == `\\` {
			if i + 1 < inner.len && inner[i + 1] == `\n` {
				i += 2
				continue
			}
			if i + 1 < inner.len && (inner[i + 1] == `u` || inner[i + 1] == `U`) {
				// A universal character name in a wide literal is the code
				// point itself, written into one wchar_t, not its UTF-8
				// bytes. Measured on gcc 16.2.1: L"\u00E9\U0001F600" is two
				// wchar_t, 0xE9 and 0x1F600.
				name, after := parse_ucn(inner, i + 1) or {
					return error('${text}: ${err.msg()}')
				}
				value = i64(name)
				i = after
			} else {
				parsed, next := parse_string_escape(inner, i + 1) or {
					return error('${text}: ${err.msg()}')
				}
				value = parsed
				i = next
			}
		} else {
			decoded, next := decode_utf8(inner, i) or {
				return error('${text}: ${err.msg()}')
			}
			value = decoded
			i = next
		}
		if value < 0 || value > max_wchar {
			return error('${text}: the character ${value} does not fit in the wchar_t this target gives, a signed 32-bit int')
		}
		for shift in 0 .. 4 {
			bytes << u8((u64(value) >> (8 * shift)) & 0xff)
		}
		count++
	}
	return StringLiteral{
		value: bytes.bytestr()
		unit:  4
		count: count
	}
}

// max_wchar is the largest value the signed 32-bit wchar_t this target gives
// holds, which is the largest a wide character may be.
const max_wchar = i64(0x7fffffff)

// decode_utf8 reads one character of the source, which is UTF-8, and answers the
// code point it names and where the next character starts. A byte that cannot
// begin a sequence, or a continuation byte that is not one, is reported rather
// than read as a value the source did not write.
fn decode_utf8(text string, at int) !(i64, int) {
	b := text[at]
	if b < 0x80 {
		return i64(b), at + 1
	}
	mut need := 0
	mut value := i64(0)
	if b >= 0xc2 && b <= 0xdf {
		need = 1
		value = i64(b & 0x1f)
	} else if b >= 0xe0 && b <= 0xef {
		need = 2
		value = i64(b & 0x0f)
	} else if b >= 0xf0 && b <= 0xf4 {
		need = 3
		value = i64(b & 0x07)
	} else {
		return error('the byte 0x${b:02x} does not start a UTF-8 character')
	}
	if at + need >= text.len {
		return error('a UTF-8 character in the literal is cut short')
	}
	for k in 1 .. need + 1 {
		cont := text[at + k]
		if cont < 0x80 || cont > 0xbf {
			return error('the byte 0x${cont:02x} does not continue a UTF-8 character')
		}
		value = i64((u64(value) << 6) | u64(cont & 0x3f))
	}
	return value, at + need + 1
}

// parse_string_escape reads the escape that starts at `at`, the byte after the
// backslash, and returns its value and the index after it. The escapes are the
// ones a character constant takes; a string needs the end of each escape as
// well, because the byte after a hex escape belongs to the string.
fn parse_string_escape(inner string, at int) !(i64, int) {
	if at >= inner.len {
		return error('the escape is not finished')
	}
	c := inner[at]
	if c == `x` || c == `X` {
		mut value := i64(0)
		mut seen := 0
		mut i := at + 1
		for i < inner.len {
			digit := digit_value(inner[i], 16) or { break }
			value = value * 16 + i64(digit)
			seen++
			i++
		}
		if seen == 0 {
			return error('hex escape without digits')
		}
		return value, i
	}
	if c >= `0` && c <= `7` {
		mut value := i64(0)
		mut seen := 0
		mut i := at
		for i < inner.len && seen < 3 {
			digit := digit_value(inner[i], 8) or { break }
			value = value * 8 + i64(digit)
			seen++
			i++
		}
		return value, i
	}
	value := parse_escape(c.ascii_str()) or { return error(err.msg()) }
	return value, at + 1
}

fn digit_value(ch u8, base int) ?int {
	digit := if ch >= `0` && ch <= `9` {
		int(ch - `0`)
	} else if ch >= `a` && ch <= `f` {
		int(ch - `a`) + 10
	} else if ch >= `A` && ch <= `F` {
		int(ch - `A`) + 10
	} else {
		return none
	}
	if digit >= base {
		return none
	}
	return digit
}
