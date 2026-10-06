module decimal

// The bytes in these tests are gcc 16.2.1's own output, read with a union of a
// decimal value and its bytes (the probes live beside this work in the agent's
// scratch directory: dec-bytes-hermes.c and dec-large-hermes.c). Nothing here is
// computed from a remembered layout: if the encoder and gcc disagree on one of
// these rows, the encoder is what is wrong.

// literal reads a decimal constant the way the reader does: the digits as
// written with the point taken out, the exponent adjusted for it, and the value
// then rounded to the format's precision. That is what gcc stores, so a literal
// round trip is a fair test of the encoder.
fn literal(text string, f Format) Value {
	// The suffix names the format and is not part of the number.
	body := text[..text.len - 2]
	return from_text(body, f)
}

fn hex_of(bytes []u8) string {
	mut out := ''
	for i := bytes.len - 1; i >= 0; i-- {
		out += '${bytes[i]:02x}'
	}
	return out
}

// Each row is the literal and the bytes gcc stores for it, most significant
// byte first the way the probe printed them; the suffix names the format.
const measured = [
	'0.0df 32000000',
	'1.0df 3200000a',
	'-1.0df b200000a',
	'1.5df 3200000f',
	'12.5df 3200007d',
	'1e6df 35800001',
	'1234567.0df 3292d687',
	'123456.7df 3212d687',
	'1e-6df 2f800001',
	'1e96df 5f8f4240',
	'1e-95df 03000001',
	'8388607.0df 32ffffff',
	'8388608.0df 6ca00000',
	'8388609.0df 6ca00001',
	'9000000.0df 6ca95440',
	'8999999.0df 6ca9543f',
	'9999999.0df 6cb8967f',
	'9999999e10df 6df8967f',
	'9999999e-10df 6b78967f',
	'9999999e90df 77f8967f',
	'9999999e-95df 60d8967f',
	'8388.608df 6c400000',
	'83886.08df 6c600000',
	'0.0dd 31a0000000000000',
	'1.0dd 31a000000000000a',
	'-1.0dd b1a000000000000a',
	'1.5dd 31a000000000000f',
	'2.5dd 31a0000000000019',
	'1e10dd 3300000000000001',
	'1e-10dd 3080000000000001',
	'1e384dd 5fe38d7ea4c68000',
	'1e-398dd 0000000000000001',
	'1234567890123456.0dd 31c462d53c8abac0',
	'9007199254740991.0dd 31dfffffffffffff',
	'9007199254740992.0dd 6c70000000000000',
	'9007199254740993.0dd 6c70000000000001',
	'9000000000000000.0dd 31dff973cafa8000',
	'999999999999999.0dd 6c6b86f26fc0fff6',
	'9999999999999999.0dd 6c7386f26fc0ffff',
	'9999999999999999e100dd 6f9386f26fc0ffff',
	'9999999999999999e-100dd 695386f26fc0ffff',
	'0.0dl 303e0000000000000000000000000000',
	'1.0dl 303e000000000000000000000000000a',
	'3.5dl 303e0000000000000000000000000023',
	'1e50dl 30a40000000000000000000000000001',
	'1e6144dl 5ffe314dc6448d9338c15b0a00000000',
	'1234567890123456789012345678901234.0dl 30403cde6fff9732de825cd07e96aff2',
]

// format_of names the format a literal's suffix writes.
fn format_of(text string) Format {
	if text.ends_with('df') {
		return .decimal32
	}
	if text.ends_with('dl') {
		return .decimal128
	}
	return .decimal64
}

fn test_the_encoder_writes_the_bytes_gcc_writes() {
	for row in measured {
		text := row.all_before(' ')
		want := row.all_after(' ')
		format := format_of(text)
		value := literal(text, format)
		got := hex_of(encode(value, format))
		assert got == want, '${text}: got ${got}, gcc wrote ${want}'
	}
}

fn test_a_value_decodes_to_what_was_encoded() {
	for row in measured {
		text := row.all_before(' ')
		format := format_of(text)
		value := literal(text, format)
		back := decode(encode(value, format), format)
		assert back.sign == value.sign, '${text}: sign'
		assert back.special == value.special, '${text}: special'
		assert cmp_values(back, value) == 0, '${text}: ${back} is not ${value}'
	}
}

fn test_the_literals_digits_are_the_ones_the_source_wrote() {
	// gcc keeps the digits as written and adjusts the exponent for the point; a
	// literal with more digits than the format keeps is rounded to it, which is
	// where a trailing zero the format has no room for goes.
	assert literal('1.0dd', .decimal64).digits == '10'.bytes()
	assert literal('1.0dd', .decimal64).exponent == -1
	assert literal('1234567.0df', .decimal32).digits == '1234567'.bytes()
	assert literal('1234567.0df', .decimal32).exponent == 0
	assert literal('3.5dl', .decimal128).digits == '35'.bytes()
	assert literal('3.5dl', .decimal128).exponent == -1
}

fn test_a_literal_beyond_the_format_is_rounded_to_even() {
	// 12345678.0 has nine digits and decimal32 keeps seven, so the two digits
	// dropped are an eighty, well above half, and the last digit kept goes up.
	assert literal('12345678.0df', .decimal32).digits == '1234568'.bytes()
	// 12345675.0 drops a five and nothing else, which is a tie, and the digit kept
	// is odd, so the tie rounds up to the even digit.
	assert literal('12345675.0df', .decimal32).digits == '1234568'.bytes()
	// 12345685.0 is the same tie with an even digit kept, so it stays as it is.
	assert literal('12345685.0df', .decimal32).digits == '1234568'.bytes()
}

fn test_the_decimal_arithmetic_is_decimal() {
	// The point of the type: a tenth plus two tenths is three tenths exactly,
	// where the same sum in double is not a tenth more than nothing.
	one := literal('0.1dd', .decimal64)
	two := literal('0.2dd', .decimal64)
	sum := add(one, two, .decimal64)
	assert sum.digits == '3'.bytes(), 'sum was ${sum}'
	assert sum.exponent == -1

	// A product that needs more digits than the format keeps is rounded once, to
	// the format's precision.
	big := literal('9999999999999999.0dd', .decimal64)
	product := mul(big, literal('9999999999999999.0dd', .decimal64), .decimal64)
	assert product.digits.len == 16, 'product was ${product}'
	assert product.exponent == 16, 'product exceeded was ${product}'

	// Sixteen digits plus one has seventeen digits, and the format keeps sixteen:
	// the dropped digit is a one, so the sum rounds back to the sixteen digits it
	// started with. This is the sum that a double cannot do at all.
	sixteen := literal('1e16dd', .decimal64)
	one_more := add(sixteen, literal('1.0dd', .decimal64), .decimal64)
	assert cmp_values(one_more, sixteen) == 0, 'sum was ${one_more}'
	assert one_more.digits == '1000000000000000'.bytes(), 'sum was ${one_more}'
	assert one_more.exponent == 1, 'sum was ${one_more}'

	// One divided by three is a repeating decimal, so it is the format's worth of
	// threes and nothing more.
	third := div(literal('1.0dd', .decimal64), literal('3.0dd', .decimal64), .decimal64)
	assert third.digits == '3333333333333333'.bytes(), 'third was ${third}'
	assert third.exponent == -16

	// Two thirds rounds up: the digit after the sixteenth three is a six.
	two_thirds := div(literal('2.0dd', .decimal64), literal('3.0dd', .decimal64), .decimal64)
	assert two_thirds.digits == '6666666666666667'.bytes(), 'two thirds was ${two_thirds}'
}

fn test_rounding_ties_go_to_the_even_digit() {
	// 15 to one digit is a tie between 1 and 2, and 2 is the even one.
	digits, exponent := round_to('15'.bytes(), -2, 1)
	assert digits == '2'.bytes()
	assert exponent == -1
	// 25 is the same tie and 2 is already even.
	digits2, exponent2 := round_to('25'.bytes(), -2, 1)
	assert digits2 == '2'.bytes()
	assert exponent2 == -1
	// A carry out of the top digit moves the power of ten with it.
	digits3, exponent3 := round_to('999'.bytes(), 0, 2)
	assert digits3 == '10'.bytes()
	assert exponent3 == 2
}

fn test_comparison_orders_decimals_by_their_value() {
	assert cmp_values(literal('1.5dd', .decimal64), literal('15e-1dd', .decimal64)) == 0
	assert cmp_values(literal('0.1dd', .decimal64), literal('0.2dd', .decimal64)) == -1
	assert cmp_values(literal('-1.0dd', .decimal64), literal('1.0dd', .decimal64)) == -1
	assert cmp_values(literal('1e10dd', .decimal64), literal('9999999999.0dd', .decimal64)) == 1
	assert cmp_values(zero(false), zero(true)) == 0
}

fn test_an_exponent_the_format_cannot_hold_is_not_encoded() {
	// The biased exponent has eight bits in decimal32, so a value scaled beyond
	// what they hold has no encoding at all: an empty list says so rather than a
	// number that is not the one asked for.
	assert encode(literal('1e200df', .decimal32), .decimal32).len == 0
}
