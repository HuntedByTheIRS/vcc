module decimal

// The three decimal floating formats of GNU C: `_Decimal32`, `_Decimal64` and
// `_Decimal128`. A value of one of them is stored in the BID encoding (binary
// integer decimal), which is what gcc uses on x86-64 and what
// `__DECIMAL_BID_FORMAT__` says it uses; the layout below was read off the bytes
// gcc 16.2.1 wrote for a table of literals rather than recalled, and every row
// of that table encodes and decodes exactly.
//
// The fields, for all three formats: one sign bit, then the exponent, then the
// coefficient, with the two highest exponent bits doubling as the top of the
// coefficient for the canonical form, and a marker for a coefficient that needs
// the whole field. A coefficient below two to the coefficient-bits power is
// canonical: its bits sit directly under the exponent. A coefficient at or above
// that is the large form: the two bits below the sign are 11, the exponent moves
// down two bits and the coefficient is the implied power of two plus the bits
// under the exponent. The five bits below the sign equal 11110 for an infinity
// and 11111 for a NaN in either form's place.
//
//   format      bits  coefficient bits  exponent bits  bias
//   decimal32   32    23                8              101
//   decimal64   64    53                10             398
//   decimal128  128   113               14             6176
pub enum Format {
	decimal32
	decimal64
	decimal128
}

// digits is the number of significant decimal digits the format keeps: a
// literal with more digits than this is rounded to it, ties to even.
pub fn (f Format) digits() int {
	return match f {
		.decimal32 { 7 }
		.decimal64 { 16 }
		.decimal128 { 34 }
	}
}

// exponent_max is the largest power of ten a value of the format carries, the
// Emax of the format's specification.
pub fn (f Format) exponent_max() int {
	return match f {
		.decimal32 { 96 }
		.decimal64 { 384 }
		.decimal128 { 6144 }
	}
}

// coefficient_bits is the width of the coefficient field in the canonical form:
// the number of bits a coefficient must fit in before the large form is used.
pub fn (f Format) coefficient_bits() int {
	return match f {
		.decimal32 { 23 }
		.decimal64 { 53 }
		.decimal128 { 113 }
	}
}

// exponent_bits is the width of the biased exponent field.
pub fn (f Format) exponent_bits() int {
	return match f {
		.decimal32 { 8 }
		.decimal64 { 10 }
		.decimal128 { 14 }
	}
}

// largest_biased_exponent is the largest biased exponent the canonical form can
// hold. The two highest bits of the exponent field are the marker for the large
// form when both are set, so the exponent stops one short of the field's own
// maximum: 191 for decimal32, 767 for decimal64, 12287 for decimal128. gcc stops
// there too, which is why `1e96df` is stored as a coefficient of 1000000 with a
// power of 90 rather than a coefficient of one with a power of 96.
pub fn (f Format) largest_biased_exponent() int {
	return (0b11 << (f.exponent_bits() - 2)) - 1
}

// bias is the constant added to the power of ten to make the biased exponent the
// encoding stores.
pub fn (f Format) bias() int {
	return match f {
		.decimal32 { 101 }
		.decimal64 { 398 }
		.decimal128 { 6176 }
	}
}

// bytes is how wide a value of the format is in memory.
pub fn (f Format) bytes() int {
	return match f {
		.decimal32 { 4 }
		.decimal64 { 8 }
		.decimal128 { 16 }
	}
}

// from_kind names the format a `_Decimal32`, `_Decimal64` or `_Decimal128` type
// is. The reader has already chosen which one the spelling names, so an unknown
// name cannot reach here; decimal64 is the answer that keeps a caller honest if
// one ever does.
pub fn from_kind(kind string) Format {
	return match kind {
		'_Decimal32' { .decimal32 }
		'_Decimal128' { .decimal128 }
		else { .decimal64 }
	}
}

// clamp brings a value into the format's range the way gcc does with a literal
// that is outside it: a value above the largest the format holds becomes an
// infinity and one below the smallest becomes a zero, both keeping the sign.
// Measured on gcc 16.2.1, which warns (`floating constant exceeds range of
// '_Decimal32'`, or `floating constant truncated to zero`) and stores that
// value. The caller reports; this only says what the value becomes.
pub fn (v Value) clamp(f Format) Value {
	if v.special != .finite || v.digits.len == 0 {
		return v
	}
	// The power of ten of the leading digit is what the range is about: the
	// format holds anything from the smallest power it can name up to its
	// exponent maximum with all the digits it keeps.
	leading := v.exponent + v.digits.len - 1
	if leading > f.exponent_max() {
		return Value{
			sign:    v.sign
			special: .infinity
		}
	}
	if leading < -f.bias() {
		return Value{
			sign: v.sign
		}
	}
	return v
}

// from_suffix names the format a decimal constant's suffix writes: `df` is a
// `_Decimal32`, `dd` a `_Decimal64` and `dl` a `_Decimal128`, either case. An
// empty answer means the suffix is not one of them, and the reader is the one
// that says so.
pub fn from_suffix(text string) ?Format {
	if text.ends_with('df') || text.ends_with('DF') {
		return .decimal32
	}
	if text.ends_with('dd') || text.ends_with('DD') {
		return .decimal64
	}
	if text.ends_with('dl') || text.ends_with('DL') {
		return .decimal128
	}
	return none
}

// Special is what a value is when it is not a number: the encodings carry an
// infinity and two NaN forms in the place a coefficient would be.
pub enum Special {
	finite
	infinity
	signaling_nan
	quiet_nan
}

// Value is a decimal number: the sign, the significant digits with no leading
// zero, and the power of ten they are scaled by, so the value is
// (-1)^sign * digits * 10^exponent. `digits` holds ASCII '0' to '9' and is empty
// for a zero, which is how the reader hands a literal over and how a rounded
// result is written back out.
pub struct Value {
pub mut:
	sign     bool
	digits   []u8
	exponent int
	special  Special = .finite
}

// zero is the value zero of either sign with the exponent a plain zero carries.
pub fn zero(sign bool) Value {
	return Value{
		sign: sign
	}
}

// zero_at is a zero carrying the exponent the result of an operation has, which
// is not always the exponent a plain zero carries. An addition and a subtraction
// give their result the preferred exponent, the smaller of the two operands'
// exponents, and gcc does the same: `1e7df - 1e7df` is a zero at a power of
// seven and `1e-101df - 1e-101df` a zero at minus one hundred and one, while
// `0.0df - 0.0df` is a zero at minus one because both operands were.
pub fn zero_at(sign bool, exponent int) Value {
	return Value{
		sign:     sign
		exponent: exponent
	}
}

// is_zero says whether the value is a zero of either sign.
pub fn (v Value) is_zero() bool {
	return v.special == .finite && v.digits.len == 0
}

// from_text reads a decimal constant's body into a value: the digits, the point
// and the exponent, with the suffix already taken off. The digits are
// taken as written with the point removed and the exponent adjusted for it, then
// rounded to the format's precision: that is what gcc stores, which is why
// `1.0dd` is a coefficient of ten with a power of minus one rather than a
// coefficient of one, and why `1234567.0df` loses its last zero (decimal32 keeps
// seven digits and the value has eight).
pub fn from_text(body string, f Format) Value {
	mut text := body
	mut sign := false
	if text.starts_with('-') {
		sign = true
		text = text[1..]
	} else if text.starts_with('+') {
		text = text[1..]
	}
	mut exponent := 0
	mut epos := -1
	for i, c in text {
		if c == `e` || c == `E` {
			epos = i
			break
		}
	}
	if epos >= 0 {
		exponent = text[epos + 1..].int()
		text = text[..epos]
	}
	mut digits := []u8{}
	mut point := -1
	for i, c in text {
		if c == `.` {
			point = i
			break
		}
	}
	if point >= 0 {
		digits = text[..point].bytes()
		frac := text[point + 1..].bytes()
		digits << frac
		exponent -= frac.len
	} else {
		digits = text.bytes()
	}
	return from_digits(digits, exponent, sign).round(f)
}

// from_digits reads a value from the digits the source wrote: leading zeros are
// dropped, an empty digit string is zero, and the exponent is the power of ten
// the digits are scaled by. The digits are not rounded and not normalised,
// because a literal keeps the digits as written.
pub fn from_digits(digits []u8, exponent int, sign bool) Value {
	mut d := digits.clone()
	mut i := 0
	for i < d.len && (d[i] == `0` || d[i] == `_`) {
		i++
	}
	d = d[i..]
	return Value{
		sign:     sign && d.len > 0
		digits:   d
		exponent: exponent
	}
}

// string writes the value the way the source would: a minus sign, the digits
// with a point after the first of them when the power of ten is negative, and
// the exponent when the value is not written out in full.
pub fn (v Value) string() string {
	if v.special != .finite {
		return match v.special {
			.infinity {
				if v.sign { '-Infinity' } else { 'Infinity' }
			}
			.signaling_nan { 'sNaN' }
			.quiet_nan { 'NaN' }
			.finite { '' }
		}
	}
	if v.digits.len == 0 {
		return '0'
	}
	mut out := if v.sign { '-' } else { '' }
	digits := v.digits.bytestr()
	if v.exponent >= 0 {
		out += digits + strings_repeat('0', v.exponent)
	} else {
		point := digits.len + v.exponent
		if point > 0 {
			out += digits[..point] + '.' + digits[point..]
		} else {
			out += '0.' + strings_repeat('0', -point) + digits
		}
	}
	return out
}

// strings_repeat is `strings.repeat` without pulling the module in for one call:
// the places that need padding are all short and all known.
fn strings_repeat(s string, n int) string {
	if n <= 0 {
		return ''
	}
	mut b := []u8{len: s.len * n}
	for i in 0 .. n {
		for j in 0 .. s.len {
			b[i * s.len + j] = s[j]
		}
	}
	return b.bytestr()
}

// -- digits ------------------------------------------------------------------
//
// The coefficient of a value is a decimal integer held as its ASCII digits with
// the most significant first, so the arithmetic below is the schoolbook
// arithmetic a person would do on paper. It is slow next to machine words and
// that is the right trade here: it runs once per constant, in the compiler, and
// its exactness is what the compiler is being asked for.

// strip drops leading zeros, leaving an empty digit list for zero.
fn strip(digits []u8) []u8 {
	mut i := 0
	for i < digits.len && digits[i] == `0` {
		i++
	}
	return digits[i..]
}

// reversed turns a list built least significant first into the reading order the
// rest of the module uses. It is written out rather than called on the array
// because a reverse that the caller has to remember to keep is a trap, and this
// one had already been fallen into once.
fn reversed(digits []u8) []u8 {
	mut out := []u8{len: digits.len}
	for i in 0 .. digits.len {
		out[i] = digits[digits.len - 1 - i]
	}
	return out
}

// cmp_digits compares two digit lists: -1 when a is smaller, 0 when equal, 1
// when greater. Both are expected stripped.
fn cmp_digits(a []u8, b []u8) int {
	if a.len != b.len {
		return if a.len < b.len { -1 } else { 1 }
	}
	for i in 0 .. a.len {
		if a[i] != b[i] {
			return if a[i] < b[i] { -1 } else { 1 }
		}
	}
	return 0
}

// add_digits adds two digit lists and returns the sum as digits.
fn add_digits(a []u8, b []u8) []u8 {
	mut out := []u8{}
	mut carry := 0
	mut i := a.len - 1
	mut j := b.len - 1
	for i >= 0 || j >= 0 || carry > 0 {
		mut sum := carry
		if i >= 0 {
			sum += int(a[i] - `0`)
			i--
		}
		if j >= 0 {
			sum += int(b[j] - `0`)
			j--
		}
		out << u8(`0` + sum % 10)
		carry = sum / 10
	}
	return strip(reversed(out))
}

// sub_digits subtracts b from a, where a is not smaller than b, and returns the
// difference as digits.
fn sub_digits(a []u8, b []u8) []u8 {
	mut out := []u8{}
	mut borrow := 0
	mut i := a.len - 1
	mut j := b.len - 1
	for i >= 0 {
		mut diff := int(a[i] - `0`) - borrow
		if j >= 0 {
			diff -= int(b[j] - `0`)
			j--
		}
		if diff < 0 {
			diff += 10
			borrow = 1
		} else {
			borrow = 0
		}
		out << u8(`0` + diff)
		i--
	}
	return strip(reversed(out))
}

// mul_digits multiplies two digit lists and returns the product as digits.
fn mul_digits(a []u8, b []u8) []u8 {
	if a.len == 0 || b.len == 0 {
		return []u8{}
	}
	// The array is exactly as wide as the product can be. One more column would
	// leave the least significant digit one place to the left, which is a product
	// ten times too large.
	mut acc := []int{len: a.len + b.len}
	for i := a.len - 1; i >= 0; i-- {
		for j := b.len - 1; j >= 0; j-- {
			acc[i + j + 1] += int(a[i] - `0`) * int(b[j] - `0`)
		}
	}
	for k := acc.len - 1; k > 0; k-- {
		acc[k - 1] += acc[k] / 10
		acc[k] %= 10
	}
	mut out := []u8{len: acc.len}
	for k in 0 .. acc.len {
		out[k] = u8(`0` + acc[k] % 10)
	}
	return strip(out)
}

// div_digits divides a by b and returns the quotient and the remainder, both as
// digits. The quotient is truncated: `div_round` is the one that rounds.
fn div_digits(a []u8, b []u8) ([]u8, []u8) {
	divisor := strip(b)
	if divisor.len == 0 {
		return []u8{}, []u8{}
	}
	mut quotient := []u8{}
	mut remainder := []u8{}
	for i in 0 .. a.len {
		mut next := remainder.clone()
		next << a[i]
		next = strip(next)
		mut digit := 0
		for digit < 9 && cmp_digits(next, divisor) >= 0 {
			next = sub_digits(next, divisor)
			digit++
		}
		quotient << u8(`0` + digit)
		remainder = next.clone()
	}
	return strip(quotient), strip(remainder)
}

// shift_digits multiplies the digits by ten to the n, which is appending zeros,
// or divides by ten to the -n, which is dropping digits and reporting whether
// anything was dropped.
fn shift_digits(digits []u8, n int) ([]u8, bool) {
	if digits.len == 0 {
		return []u8{}, false
	}
	if n >= 0 {
		mut out := digits.clone()
		for _ in 0 .. n {
			out << `0`
		}
		return strip(out), false
	}
	drop := -n
	if drop >= digits.len {
		return []u8{}, true
	}
	return strip(digits[..digits.len - drop]), true
}

// -- values ------------------------------------------------------------------

// align puts two values on one power of ten, the smaller of the two, by scaling
// the other's digits up. It reports whether anything was dropped, which is what
// a rounding decision needs to know about a digit that fell off the end of a
// value scaled down by ten.
fn align(a Value, b Value) (Value, Value, bool) {
	mut lo := a
	mut hi := b
	if a.exponent > b.exponent {
		lo = b
		hi = a
	}
	scale := hi.exponent - lo.exponent
	scaled, dropped := shift_digits(hi.digits, scale)
	return lo, Value{
		sign:     hi.sign
		digits:   scaled
		exponent: lo.exponent
		special:  hi.special
	}, dropped
}

// cmp_values compares two values: -1 when a is smaller, 0 when equal, 1 when
// greater. Exponents are compared first through the digits' length, so no
// scaling is needed and nothing is lost. It is the order a folded comparison of
// two decimal constants asks for. A zero is ordered against the other value's
// sign, not its own: zero sits between the negative values and the positive
// ones, so `0.0 < -1.0` is false and `-1.0 < 0.0` is true, whichever sign the
// zero itself carries.
pub fn cmp_values(a Value, b Value) int {
	if a.is_zero() && b.is_zero() {
		return 0
	}
	if a.is_zero() {
		return if b.sign { 1 } else { -1 }
	}
	if b.is_zero() {
		return if a.sign { -1 } else { 1 }
	}
	if a.sign != b.sign {
		return if a.sign { -1 } else { 1 }
	}
	// The exponent of the first significant digit decides the order: a value with
	// more digits in front of the point is larger.
	ea := a.exponent + a.digits.len
	eb := b.exponent + b.digits.len
	mut order := 0
	if ea != eb {
		order = if ea < eb { -1 } else { 1 }
	} else {
		l, r, _ := align(a, b)
		order = cmp_digits(l.digits, r.digits)
	}
	if a.sign {
		return -order
	}
	return order
}

// round_to rounds the digits to at most n of them, ties to even, and reports the
// exponent the rounding moved to. A value that already fits is returned as it
// is. The rounding is done on the digits themselves so a tie is a real tie: the
// source's digits decide, not a binary approximation of them.
pub fn round_to(digits []u8, exponent int, n int) ([]u8, int) {
	return round_with_sticky(digits, exponent, n, false)
}

// round_with_sticky is round_to for a digit list that is itself the front of a
// longer number: `sticky` says that what was cut off before this list was built
// was not zero, which turns a last digit of five from a tie into a value above
// the halfway point.
fn round_with_sticky(digits []u8, exponent int, n int, sticky bool) ([]u8, int) {
	d := strip(digits)
	if d.len <= n {
		return d, exponent
	}
	drop := d.len - n
	mut kept := d[..n].clone()
	first_dropped := d[n]
	mut rest := sticky
	for i in n + 1 .. d.len {
		if d[i] != `0` {
			rest = true
			break
		}
	}
	mut up := first_dropped > `5`
	if first_dropped == `5` {
		// Ties to even: an exact five rounds up only when the kept digit is odd.
		up = rest || (kept[kept.len - 1] - `0`) % 2 == 1
	}
	mut exp := exponent + drop
	if up {
		kept = add_digits(kept, [`1`])
		if kept.len > n {
			// 999 rounds to 1000: one digit too many, so the power of ten moves.
			kept = strip(kept)
			exp++
			if kept.len > n {
				kept = kept[..n]
			}
		}
	}
	return strip(kept), exp
}

// round rounds a value to the format's precision, ties to even.
pub fn (v Value) round(f Format) Value {
	if v.special != .finite {
		return v
	}
	digits, exponent := round_to(v.digits, v.exponent, f.digits())
	return Value{
		sign:     v.sign && digits.len > 0
		digits:   digits
		exponent: exponent
		special:  .finite
	}
}

// add returns a + b in the format, rounded to its precision.
pub fn add(a Value, b Value, f Format) Value {
	if a.special != .finite || b.special != .finite {
		return special_sum(a, b)
	}
	if a.is_zero() && b.is_zero() {
		exponent := if a.exponent < b.exponent { a.exponent } else { b.exponent }
		return zero_at(a.sign && b.sign, exponent)
	}
	l, r, _ := align(a, b)
	mut digits := []u8{}
	mut sign := false
	if l.sign == r.sign {
		digits = add_digits(l.digits, r.digits)
		sign = l.sign
	} else {
		order := cmp_digits(l.digits, r.digits)
		if order == 0 {
			// The operands cancel exactly. The zero that comes out carries the
			// preferred exponent, which is the aligned exponent both operands
			// now share, and a positive sign: an exact zero of two opposite
			// values is plus zero in the rounding mode this compiler emits.
			return zero_at(false, l.exponent)
		} else if order > 0 {
			digits = sub_digits(l.digits, r.digits)
			sign = l.sign
		} else {
			digits = sub_digits(r.digits, l.digits)
			sign = r.sign
		}
	}
	return Value{
		sign:     sign && digits.len > 0
		digits:   digits
		exponent: l.exponent
		special:  .finite
	}.round(f)
}

// sub returns a - b in the format.
pub fn sub(a Value, b Value, f Format) Value {
	mut negated := b
	if !b.is_zero() || b.sign {
		negated.sign = !b.sign
	}
	return add(a, negated, f)
}

// mul returns a * b in the format. The product's digits are exact before the
// rounding, which is what makes a decimal multiplication round once.
pub fn mul(a Value, b Value, f Format) Value {
	if a.special != .finite || b.special != .finite {
		return special_product(a, b)
	}
	digits := mul_digits(a.digits, b.digits)
	return Value{
		sign:     (a.sign != b.sign) && digits.len > 0
		digits:   digits
		exponent: a.exponent + b.exponent
		special:  .finite
	}.round(f)
}

// div returns a / b in the format, rounded to its precision. The quotient is
// taken further than the format keeps so the rounding decision has the digit
// that decides it, and the remainder says whether that digit was a tie or
// something above one.
pub fn div(a Value, b Value, f Format) Value {
	if b.special != .finite || a.special != .finite {
		return special_quotient(a, b)
	}
	if b.is_zero() {
		return Value{
			sign:    a.sign != b.sign
			special: .infinity
		}
	}
	if a.is_zero() {
		return zero(a.sign != b.sign)
	}
	// Scale the dividend up until the quotient has more digits than the format
	// keeps: each zero added to the dividend adds a digit to the quotient without
	// changing its value, and the power of ten is taken back below.
	want := b.digits.len + f.digits() + 2
	mut scaled := a.digits.clone()
	mut extra := 0
	for scaled.len < want {
		scaled << `0`
		extra++
	}
	q, rem := div_digits(scaled, b.digits)
	if q.len == 0 {
		return zero(a.sign != b.sign)
	}
	digits, exponent := round_with_sticky(q, a.exponent - b.exponent - extra, f.digits(), rem.len > 0)
	return Value{
		sign:     (a.sign != b.sign) && digits.len > 0
		digits:   digits
		exponent: exponent
		special:  .finite
	}
}

// special_quotient divides when either side is not a finite number.
fn special_quotient(a Value, b Value) Value {
	if a.special == .signaling_nan || b.special == .signaling_nan || a.special == .quiet_nan
		|| b.special == .quiet_nan {
		return Value{
			special: .quiet_nan
		}
	}
	if a.special == .infinity && b.special == .infinity {
		return Value{
			special: .quiet_nan
		}
	}
	return Value{
		sign:    a.sign != b.sign
		special: .infinity
	}
}

// special_sum adds when either side is not a finite number. An infinity plus
// anything finite is that infinity; anything else that involves a NaN is the
// quiet NaN, which is what the format's specification asks for.
fn special_sum(a Value, b Value) Value {
	if a.special == .signaling_nan || b.special == .signaling_nan {
		return Value{
			special: .quiet_nan
		}
	}
	if a.special == .quiet_nan || b.special == .quiet_nan {
		return Value{
			special: .quiet_nan
		}
	}
	if a.special == .infinity && b.special == .infinity {
		if a.sign != b.sign {
			return Value{
				special: .quiet_nan
			}
		}
		return a
	}
	if a.special == .infinity {
		return a
	}
	return b
}

// special_product multiplies when either side is not a finite number.
fn special_product(a Value, b Value) Value {
	if a.special == .signaling_nan || b.special == .signaling_nan {
		return Value{
			special: .quiet_nan
		}
	}
	if a.special == .quiet_nan || b.special == .quiet_nan {
		return Value{
			special: .quiet_nan
		}
	}
	return Value{
		sign:    a.sign != b.sign
		special: .infinity
	}
}

// coefficient is the value's digits as an integer, which the encoder needs.
fn (v Value) coefficient() u128 {
	mut c := u128(0)
	for d in v.digits {
		c = c * 10 + u128(d - `0`)
	}
	return c
}

// encode writes the value in the BID encoding the format uses, little endian,
// which is the order it sits in memory. The exponent is the biased one; a value
// whose exponent does not fit the field is reported by returning an empty list,
// because the format has no room for it and the caller must say so rather than
// write a number that is not the one asked for.
pub fn encode(v Value, f Format) []u8 {
	width := f.bytes()
	total := width * 8
	mut w := u128(0)
	if v.special != .finite {
		// The specials are the five bits below the sign: 11110 for an infinity,
		// 11111 for a NaN with the signalling bit above the payload.
		w = u128(0b11110) << (total - 6)
		if v.special == .quiet_nan || v.special == .signaling_nan {
			w = u128(0b11111) << (total - 6)
			if v.special == .quiet_nan {
				w |= u128(1) << (total - 7)
			}
		}
	} else {
		mut biased := v.exponent + f.bias()
		max_biased := f.largest_biased_exponent()
		mut c := v.coefficient()
		mut used := v.digits.len
		if used == 0 {
			// A zero keeps whichever power of ten it was written with, as far as the
			// field can hold it, and a zero is never out of range however it was
			// written. Measured on gcc 16.2.1: `0e30df` is 41800000 (a biased 131),
			// `0e300df` is 5f800000, brought down to 191, the largest biased
			// exponent, and `0e400dd` is 5fe0000000000000, brought down to 767.
			// There are no digits to pad, so this is the whole answer for a zero.
			mut zero_biased := biased
			if zero_biased < 0 {
				zero_biased = 0
			}
			if zero_biased > max_biased {
				zero_biased = max_biased
			}
			w = u128(zero_biased) << f.coefficient_bits()
		} else {
			// A value written with fewer digits than the format keeps can still be
			// written when its power of ten is too large for the exponent field:
			// multiplying the coefficient by ten and lowering the power by one keeps
			// the value and brings the exponent back into the field. gcc does the
			// same, which is why `1e96df` is stored as 1000000 with a power of 90:
			// the largest biased exponent is 191, and a coefficient of one with a
			// power of 96 needs 197.
			for biased > max_biased && used < f.digits() {
				c *= 10
				used++
				biased--
			}
			// The other direction: a coefficient with trailing zeros can be shrunk,
			// which raises the power of ten and brings it back up into the field.
			mut removable := 0
			for removable < v.digits.len && v.digits[v.digits.len - 1 - removable] == `0` {
				removable++
			}
			for biased < 0 && removable > 0 {
				c /= 10
				used--
				removable--
				biased++
			}
			if biased < 0 || biased > max_biased {
				return []u8{}
			}
			cbits := f.coefficient_bits()
			if c < (u128(1) << cbits) {
				w = (u128(biased) << cbits) | c
			} else {
				// The large form: the marker takes the two bits under the sign, the
				// exponent moves down two bits, and the coefficient keeps its implied
				// top bit. A coefficient too large for even this does not fit.
				low := cbits - 2
				if c >= (u128(1) << cbits) + (u128(1) << low) {
					return []u8{}
				}
				w = (u128(0b11) << (total - 3)) | (u128(biased) << low) | (c & ((u128(1) << low) - 1))
			}
		}
	}
	if v.sign {
		w |= u128(1) << (total - 1)
	}
	mut out := []u8{len: width}
	for i in 0 .. width {
		out[i] = u8((w >> (8 * i)) & 0xff)
	}
	return out
}

// decode reads a value back out of the BID encoding, which is what a value in
// memory is.
pub fn decode(bytes []u8, f Format) Value {
	total := f.bytes() * 8
	if bytes.len < f.bytes() {
		return zero(false)
	}
	mut w := u128(0)
	for i := f.bytes() - 1; i >= 0; i-- {
		w = (w << 8) | u128(bytes[i])
	}
	sign := (w >> (total - 1)) & 1 == 1
	top5 := int((w >> (total - 6)) & 0b11111)
	if top5 == 0b11110 {
		return Value{
			sign:    sign
			special: .infinity
		}
	}
	if top5 == 0b11111 {
		return Value{
			sign:    sign
			special: if (w >> (total - 7)) & 1 == 1 { .quiet_nan } else { .signaling_nan }
		}
	}
	cbits := f.coefficient_bits()
	mut c := u128(0)
	mut biased := 0
	if ((w >> (total - 3)) & 0b11) == 0b11 {
		low := cbits - 2
		c = (u128(1) << cbits) | (w & ((u128(1) << low) - 1))
		biased = int((w >> low) & ((u128(1) << f.exponent_bits()) - 1))
	} else {
		c = w & ((u128(1) << cbits) - 1)
		biased = int((w >> cbits) & ((u128(1) << f.exponent_bits()) - 1))
	}
	mut digits := []u8{}
	if c > 0 {
		mut n := c
		for n > 0 {
			digits << u8(`0` + u8(n % 10))
			n /= 10
		}
		digits = reversed(digits)
	}
	return Value{
		sign:     sign && digits.len > 0
		digits:   strip(digits)
		exponent: biased - f.bias()
		special:  .finite
	}
}
