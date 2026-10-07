module parser

import ast
import decimal
import types

// Constant folding of decimal arithmetic, which is what gcc's front end does to
// a constant expression of one of the `_Decimal32`, `_Decimal64` and
// `_Decimal128` types: `1.0dd + 2.0dd` is the value 3.0 before the program runs,
// and the value's bytes are the ones gcc writes into the object.
//
// The arithmetic is the `decimal` module's, which is the same arithmetic the
// types were built from: a value is a sign, a coefficient and a power of ten,
// and add, sub, mul and div are the schoolbook operations on it. What this file
// adds is the two things gcc's front end does around an operation and the module
// does not: an operand is the value as it is *stored*, which for a coefficient
// that needs the large form is not the digits the source wrote (gcc folds
// `1e96df * 1e-7df` into the coefficient 1000000 at a power of 83, not into 1 at
// a power of 89, because `1e96df` is stored as that padded coefficient), and a
// result is brought back inside the format's exponent field the way gcc brings
// it: a value past the largest exponent is an infinity, one below the smallest
// rounds to the format's last digit or to zero, and a zero keeps the exponent
// the operation prefers.

// decimal_constant_value is the value of a decimal constant expression this
// reader can evaluate: a decimal constant, or one with a sign in front of it.
// The reader keeps `-1.5df` as the negation of the constant rather than a
// constant with a negative sign, so the sign is taken off here.
fn decimal_constant_value(expr ast.Expr) ?types.Decimal {
	match expr {
		ast.FloatLit {
			if expr.decimal_value.kind.is_decimal() && expr.typ.kind.is_decimal() {
				return expr.decimal_value
			}
			return none
		}
		ast.Unary {
			if expr.op != '-' && expr.op != '+' {
				return none
			}
			inner := decimal_constant_value(expr.expr) or { return none }
			if expr.op == '+' {
				return inner
			}
			mut negated := inner
			// The sign bit flips for a zero too, which is the one difference
			// between a zero and the value it negates at a value's level.
			negated.sign = !negated.sign
			return negated
		}
		else {
			return none
		}
	}
}

// decimal_stored is a value as the program stores it: the encoded bytes read
// back, so a coefficient gcc pads to fit the exponent field (`1e96df` is stored
// as 1000000 at a power of 90) is the coefficient the arithmetic uses. A value
// the format cannot encode answers none, and the fold leaves the expression
// alone rather than computing with a value the program cannot hold.
fn decimal_stored(v decimal.Value, f decimal.Format) ?decimal.Value {
	bytes := decimal.encode(v, f)
	if bytes.len == 0 {
		return none
	}
	return decimal.decode(bytes, f)
}

// decimal_ideal is the exponent an operation's result prefers: the smaller of
// the two operands' for an addition or a subtraction, the sum for a
// multiplication, the difference for a division. gcc gives a zero result this
// exponent, and a result below the format's range keeps it too.
fn decimal_ideal(op string, a decimal.Value, b decimal.Value) int {
	return match op {
		'+' {
			if a.exponent < b.exponent { a.exponent } else { b.exponent }
		}
		'-' {
			if a.exponent < b.exponent { a.exponent } else { b.exponent }
		}
		'*' { a.exponent + b.exponent }
		'/' { a.exponent - b.exponent }
		else { 0 }
	}
}

// fold_decimal_binary is a decimal operation over two decimal constants,
// evaluated here with the arithmetic in `decimal/`. It answers nothing for an
// expression that is not one, so the operation stays in the tree and the back
// end refuses it by name, which is what it does with every decimal value it has
// no form for.
fn (p Parser) fold_decimal_binary(binary ast.Binary) ?ast.Expr {
	a := decimal_constant_value(binary.left) or { return none }
	b := decimal_constant_value(binary.right) or { return none }
	if !a.kind.is_decimal() || a.kind != b.kind {
		return none
	}
	f := a.kind.decimal_format()
	va := decimal_stored(a.value(), f) or { return none }
	vb := decimal_stored(b.value(), f) or { return none }
	if binary.op in ['==', '!=', '<', '<=', '>', '>='] {
		answer := decimal_compare(va, vb, binary.op)
		return ast.Expr(ast.IntLit{
			value: answer
			text:  '${answer}'
			typ:   types.int_type()
			line:  binary.line
			col:   binary.col
		})
	}
	if binary.op !in ['+', '-', '*', '/'] {
		return none
	}
	result := decimal_fold_arithmetic(binary.op, va, vb, f)
	value := types.Decimal{
		kind:     a.kind
		sign:     result.sign
		digits:   result.digits
		exponent: result.exponent
		special:  result.special
	}
	return ast.Expr(ast.FloatLit{
		decimal_value: value
		text:          value.text()
		typ:           binary.typ
		line:          binary.line
		col:           binary.col
	})
}

// decimal_fold_arithmetic runs one operation and brings the result inside the
// format: a quotient that comes out exact is expressed with the preferred
// exponent, a result past the format's range is an infinity or a rounded
// subnormal, and a zero keeps the exponent the operation prefers.
fn decimal_fold_arithmetic(op string, a decimal.Value, b decimal.Value, f decimal.Format) decimal.Value {
	match op {
		'+' {
			return decimal_settle(decimal.add(a, b, f), op, a, b, f)
		}
		'-' {
			return decimal_settle(decimal.sub(a, b, f), op, a, b, f)
		}
		'*' {
			return decimal_settle(decimal.mul(a, b, f), op, a, b, f)
		}
		'/' {
			return decimal_settle(decimal_quotient(a, b, f), op, a, b, f)
		}
		else {
			return a
		}
	}
}

// decimal_quotient divides, which is the one operation whose result exponent
// the module's division does not already give the way gcc does. A division by
// zero is the infinity gcc's front end writes, and the zero divided by zero is
// the NaN it writes; an exact quotient is then reduced toward the preferred
// exponent, which is what makes `1.0dd / 2.0dd` the coefficient 5 at minus one
// rather than the coefficient 5000000000000000 the scaling leaves.
fn decimal_quotient(a decimal.Value, b decimal.Value, f decimal.Format) decimal.Value {
	if a.special != .finite || b.special != .finite {
		return decimal.div(a, b, f)
	}
	if b.is_zero() {
		if a.is_zero() {
			// Measured on gcc 16.2.1: `0.0dd / 0.0dd` is 000000000000007c, the
			// NaN whose quiet bit is clear, at all three widths.
			return decimal.Value{
				special: .signaling_nan
			}
		}
		return decimal.Value{
			sign:    a.sign != b.sign
			special: .infinity
		}
	}
	if a.is_zero() {
		return decimal.zero_at(a.sign != b.sign, a.exponent - b.exponent)
	}
	result := decimal.div(a, b, f)
	// An exact quotient is expressed the way gcc expresses it: the coefficient of
	// the terminating decimal at the exponent the division prefers, reduced only
	// as far as an integer coefficient needs. The module's own division scales
	// the dividend and leaves fifteen trailing zeros in `1.0dd / 2.0dd`, which is
	// a different encoding of the same value. When the quotient does not
	// terminate, or needs more digits than the format keeps, gcc rounds it and
	// the module's division already rounds that case.
	ideal := a.exponent - b.exponent
	ca := decimal_coefficient(a)
	cb := decimal_coefficient(b)
	exact, coefficient, exponent := decimal_exact_quotient(ca, cb, ideal, f.digits())
	if exact {
		mut digits := decimal_digits_of(coefficient)
		mut at := exponent
		for at < ideal && digits.len > 0 && digits[digits.len - 1] == `0` {
			digits = digits[..digits.len - 1]
			at++
		}
		return decimal.Value{
			sign:     result.sign
			digits:   digits
			exponent: at
			special:  .finite
		}
	}
	return result
}

// decimal_exact_quotient is the exact quotient of two coefficients, written the
// way gcc's division writes it: the coefficient of the terminating decimal and
// the exponent it sits at, or a report that the quotient is not one the format
// holds. A quotient whose lowest terms keep a prime other than two or five does
// not terminate, and one whose exact coefficient needs more digits than the
// format keeps is a quotient gcc rounds; both answer false so the caller keeps
// the module's rounded result.
fn decimal_exact_quotient(ca u128, cb u128, ideal int, precision int) (bool, u128, int) {
	if ca == 0 || cb == 0 {
		return false, 0, 0
	}
	g := decimal_gcd(ca, cb)
	p := ca / g
	mut q := cb / g
	mut twos := 0
	for q % 2 == 0 {
		q /= 2
		twos++
	}
	mut fives := 0
	for q % 5 == 0 {
		q /= 5
		fives++
	}
	if q != 1 {
		return false, 0, 0
	}
	k := if twos > fives { twos } else { fives }
	limit := decimal_power_of_ten(precision)
	mut c := p
	for _ in 0 .. (k - twos) {
		if c > limit / 2 {
			return false, 0, 0
		}
		c *= 2
	}
	for _ in 0 .. (k - fives) {
		if c > limit / 5 {
			return false, 0, 0
		}
		c *= 5
	}
	if c >= limit {
		return false, 0, 0
	}
	return true, c, ideal - k
}

// decimal_coefficient is a value's digits as an integer, which the exact
// quotient is computed from. A value of one of the three formats keeps at most
// thirty-four digits, so its coefficient is a u128.
fn decimal_coefficient(v decimal.Value) u128 {
	mut c := u128(0)
	for d in v.digits {
		c = c * 10 + u128(d - `0`)
	}
	return c
}

// decimal_gcd is the greatest common divisor of two coefficients, by the
// Euclidean algorithm.
fn decimal_gcd(a u128, b u128) u128 {
	mut x := a
	mut y := b
	for y != 0 {
		x, y = y, x % y
	}
	return x
}

// decimal_power_of_ten is ten to the n, which bounds the coefficient an exact
// quotient may keep: a coefficient with more digits than the format holds is one
// gcc rounds.
fn decimal_power_of_ten(n int) u128 {
	mut c := u128(1)
	for _ in 0 .. n {
		c *= 10
	}
	return c
}

// decimal_digits_of writes a coefficient as its decimal digits, most
// significant first, and an empty list for zero.
fn decimal_digits_of(c u128) []u8 {
	if c == 0 {
		return []u8{}
	}
	mut reversed := []u8{}
	mut n := c
	for n > 0 {
		reversed << u8(`0` + u8(n % 10))
		n /= 10
	}
	mut out := []u8{len: reversed.len}
	for i in 0 .. reversed.len {
		out[i] = reversed[reversed.len - 1 - i]
	}
	return out
}

// decimal_settle brings a result inside the format's exponent field. A finite
// value whose leading digit is past the format's largest power of ten is the
// infinity gcc writes; one whose power of ten is below the smallest is rounded
// at the smallest, to the last digit or to zero; a result whose power of ten is
// past the field but whose coefficient can be padded is padded, which is how
// `1e96df` is stored. A zero result keeps the operation's preferred exponent,
// which the encoder brings into the field for a zero however far out it is.
fn decimal_settle(result decimal.Value, op string, a decimal.Value, b decimal.Value, f decimal.Format) decimal.Value {
	if result.special != .finite {
		return result
	}
	ideal := decimal_ideal(op, a, b)
	mut sign := result.sign
	if op == '*' || op == '/' {
		// Multiplication and division keep the sign of a zero result, which is
		// the exclusive or of the operands' signs; the module forces a zero
		// product positive.
		sign = a.sign != b.sign
	}
	if result.digits.len == 0 {
		return decimal.zero_at(sign, ideal)
	}
	mut digits := result.digits.clone()
	mut exponent := result.exponent
	if exponent + digits.len - 1 > f.exponent_max() {
		return decimal.Value{
			sign:    sign
			special: .infinity
		}
	}
	max_exponent := f.largest_biased_exponent() - f.bias()
	if exponent > max_exponent {
		extra := exponent - max_exponent
		if digits.len + extra > f.digits() {
			return decimal.Value{
				sign:    sign
				special: .infinity
			}
		}
		digits = digits.clone()
		for _ in 0 .. extra {
			digits << `0`
		}
		exponent = max_exponent
	}
	min_exponent := -f.bias()
	if exponent < min_exponent {
		digits, exponent = decimal_round_into_range(digits, exponent, min_exponent)
		if digits.len == 0 {
			return decimal.zero_at(sign, min_exponent)
		}
	}
	return decimal.Value{
		sign:     sign
		digits:   digits
		exponent: exponent
		special:  .finite
	}
}

// decimal_round_into_range rounds a coefficient whose power of ten is below the
// format's smallest so that it sits at the smallest, ties to even. A value whose
// digits all fall below the smallest rounds to a zero, which is the empty list.
fn decimal_round_into_range(digits []u8, exponent int, min_exponent int) ([]u8, int) {
	shift := min_exponent - exponent
	if shift > digits.len {
		// Every digit is below the last place the format has, so the value is
		// under one unit there and rounds to zero.
		return []u8{}, min_exponent
	}
	if shift == digits.len {
		// The first digit is the unit's place and the rest are its fraction:
		// the value rounds up only above a half, and an exact half is even.
		mut rest := false
		for i in 1 .. digits.len {
			if digits[i] != `0` {
				rest = true
				break
			}
		}
		if digits[0] > `5` || (digits[0] == `5` && rest) {
			return [`1`], min_exponent
		}
		return []u8{}, min_exponent
	}
	rounded, at := decimal.round_to(digits, exponent, digits.len - shift)
	return rounded, at
}

// decimal_compare folds one comparison of two decimal constants to the int C
// gives it: one or zero. A NaN makes every comparison false except `!=`, and an
// infinity orders past every finite value.
fn decimal_compare(a decimal.Value, b decimal.Value, op string) int {
	if a.special == .quiet_nan || a.special == .signaling_nan || b.special == .quiet_nan
		|| b.special == .signaling_nan {
		return if op == '!=' { 1 } else { 0 }
	}
	order := decimal_order(a, b)
	return match op {
		'==' {
			if order == 0 { 1 } else { 0 }
		}
		'!=' {
			if order != 0 { 1 } else { 0 }
		}
		'<' {
			if order < 0 { 1 } else { 0 }
		}
		'<=' {
			if order <= 0 { 1 } else { 0 }
		}
		'>' {
			if order > 0 { 1 } else { 0 }
		}
		'>=' {
			if order >= 0 { 1 } else { 0 }
		}
		else { 0 }
	}
}

// decimal_order compares two values: -1, 0 or 1, with an infinity ordered past
// every finite value of either sign.
fn decimal_order(a decimal.Value, b decimal.Value) int {
	a_infinite := a.special == .infinity
	b_infinite := b.special == .infinity
	if a_infinite || b_infinite {
		if a_infinite && b_infinite {
			if a.sign == b.sign {
				return 0
			}
			return if a.sign { -1 } else { 1 }
		}
		if a_infinite {
			return if a.sign { -1 } else { 1 }
		}
		return if b.sign { 1 } else { -1 }
	}
	return decimal.cmp_values(a, b)
}
