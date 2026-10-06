module decimal

// The double each of these converts to was measured from gcc 16.2.1 with a union
// of a double and its bits (the vector table the measurement for this work
// recorded, decimal-vectors.json in the agent's scratch directory). The rows
// were chosen for the places a conversion goes wrong: a tenth, which is not a
// binary number at all; the tie at two to the fifty-third; a value above what a
// double holds; one below the smallest normal, which lands on a subnormal; and a
// thirty-four digit decimal128, which has to round.

// Each row is the literal and the bits of the double gcc produces for it.
const conversions = [
	'1.5df 3ff8000000000000',
	'-1.5df bff8000000000000',
	'0.0df 0000000000000000',
	'0.1df 3fb999999999999a',
	'1e300df 7ff0000000000000',
	'1e-300df 0000000000000000',
	'1.5dd 3ff8000000000000',
	'0.1dd 3fb999999999999a',
	'1234567890123456.0dd 43118b54f22aeb00',
	'9007199254740993.0dd 4340000000000000',
	'1e16dd 4341c37937e08000',
	'1e-16dd 3c9cd2b297d889bc',
	'1e384dd 7ff0000000000000',
	'1e-320dd 00000000000007e8',
	'3.5dl 400c000000000000',
	'1e50dl 4a511b0ec57e649a',
	'1234567890123456789012345678901234.0dl 46ce6f37ffcb996f',
]

fn test_the_conversion_makes_the_double_gcc_makes() {
	for row in conversions {
		text := row.all_before(' ')
		want := row.all_after(' ')
		format := from_suffix(text) or { panic('${text} has no decimal suffix') }
		value := from_text(text[..text.len - 2], format).clamp(format)
		got := '${value.to_f64_bits():016x}'
		assert got == want, '${text}: got ${got}, gcc made ${want}'
	}
}

fn test_the_conversion_of_a_few_values_worth_naming() {
	// Two to the fifty-third plus one is exactly halfway between two doubles, and
	// the rule rounds it to the even one.
	odd := from_text('9007199254740993.0', .decimal64)
	assert odd.to_f64() == 9007199254740992.0
	// A sixteenth of a tenth is not ten to the minus seventeen, and the double it
	// does make is the nearest one: the decimal value is exact and only the final
	// rounding decides.
	tenth := from_text('0.1', .decimal64)
	assert tenth.to_f64() == 0.1
	// A value whose exponent is past what a double holds is an infinity, and one
	// far below it is a zero, with the sign kept.
	huge := from_text('1e400', .decimal128)
	assert huge.to_f64() == f64_from_bits(0x7ff0000000000000)
	tiny := from_text('-1e-400', .decimal128)
	assert tiny.to_f64() == f64_from_bits(0x8000000000000000)
}
