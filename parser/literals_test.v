module parser

import math
import tokenize

// A hexadecimal floating constant reads to the value its spelling names, and
// that value is exact. The bits below were measured on gcc 16.2.1 by printing
// the object's bytes for each spelling, not the decimal gcc prints, because a
// decimal print rounds and would hide a value one bit off.

struct HexDouble {
	text string
	bits u64
}

struct HexSingle {
	text string
	bits u32
}

fn test_a_hexadecimal_float_reads_to_the_bits_gcc_produces() {
	doubles := [
		HexDouble{'0x1.8p+3', u64(0x4028000000000000)}, // 12
		HexDouble{'0x.8p1', u64(0x3ff0000000000000)}, // 1
		HexDouble{'0x0.1p4', u64(0x3ff0000000000000)}, // 1
		HexDouble{'0x1p-1', u64(0x3fe0000000000000)}, // 0.5
		HexDouble{'0X1.8P+3', u64(0x4028000000000000)}, // uppercase spellings
		HexDouble{'0x1.00000000000008p0', u64(0x3ff0000000000000)}, // just below 1, rounds down
		HexDouble{'0x1.00000000000018p0', u64(0x3ff0000000000002)}, // rounds up
		HexDouble{'0x1.0000000000000ffffp0', u64(0x3ff0000000000001)}, // past half, rounds up
		HexDouble{'0x1p-1074', u64(0x0000000000000001)}, // smallest subnormal
		HexDouble{'0x1.8p-1074', u64(0x0000000000000002)}, // a tie, to even
		HexDouble{'0x1p-1075', u64(0x0000000000000000)}, // half the smallest, to even zero
		HexDouble{'0x1.fffffffffffffp+1023', u64(0x7fefffffffffffff)}, // largest finite
		HexDouble{'0x1.fffffffffffff8p+1023', u64(0x7ff0000000000000)}, // rounds to infinity
		HexDouble{'0x1p-1022', u64(0x0010000000000000)}, // smallest normal
		HexDouble{'0x1.fffffffffffffp-1023', u64(0x0010000000000000)}, // rounds up to it
		HexDouble{'0x1p+1024', u64(0x7ff0000000000000)}, // past the range
		HexDouble{'0x.0000000000001p0', u64(0x3cb0000000000000)}, // 2^-52
	]
	for c in doubles {
		value := parse_floating_literal(c.text) or { panic(err) }
		assert math.f64_bits(value) == c.bits
	}
	singles := [
		HexSingle{'0x1.fffffep+127f', u32(0x7f7fffff)}, // largest finite float
		HexSingle{'0x1.8p3f', u32(0x41400000)},
		HexSingle{'0x1p-1f', u32(0x3f000000)},
		HexSingle{'0x1p-149f', u32(0x00000001)}, // smallest subnormal float
		HexSingle{'0x1.8p-149f', u32(0x00000002)},
		HexSingle{'0x1p-126f', u32(0x00800000)}, // smallest normal float
		HexSingle{'0x1p-150f', u32(0x00000000)},
		HexSingle{'0x1p+128f', u32(0x7f800000)}, // past the range
	]
	for c in singles {
		value := parse_floating_literal(c.text) or { panic(err) }
		assert math.f32_bits(f32(value)) == c.bits
	}
}

// A malformed constant is refused by name at the reader, and the name says what
// is wrong rather than what digit is missing.
fn test_a_malformed_hexadecimal_float_is_refused_by_name() {
	assert reject_message('0x1.8').contains('hexadecimal floating constants require an exponent')
	assert reject_message('0x.8').contains('hexadecimal floating constants require an exponent')
	assert reject_message('0x1p').contains('an exponent with no digits')
	assert reject_message('0x1p+').contains('an exponent with no digits')
	assert reject_message('0x.p1').contains('a hexadecimal floating constant has no digits')
	assert reject_message('0x1p3g').contains('is not part of a floating constant')
	assert reject_message('0x1.8p1u').contains('is not part of a floating constant')
	// The `l` suffix is not a mistake in the constant: it names a long double,
	// which is a type this compiler has no value for, so that is what is said.
	assert reject_message('0x1.8p3L').contains('a long double literal')
}

// The reader reports through the parser, which puts the token's location on the
// message, so a refusal is named where the constant was written.
fn test_a_refused_hexadecimal_float_names_its_location() {
	lexed := tokenize.lex('double x = 0x1.8;\n')
	result := parse(lexed.tokens)
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('hexadecimal floating constants require an exponent')
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 12
}

fn reject_message(text string) string {
	parse_floating_literal(text) or { return err.msg() }
	return ''
}

// An imaginary constant reads to the value of its imaginary part and the width
// its suffix names. The bits below were measured on gcc 16.2.1 by printing the
// bytes of the constant, not the decimal gcc prints, because a decimal print
// rounds and would hide a value one bit off. `0.1iF`, `0.1if` and `0.1Fi` are
// the same four bytes in the same place, which is the point: the marker is
// taken wherever it sits, and what is left is rounded once by the floating
// reader rather than rounded here and converted again.
struct ImagSingle {
	text string
	bits u32
}

struct ImagDouble {
	text string
	bits u64
}

fn test_an_imaginary_constant_reads_to_the_value_gcc_produces() {
	singles := [
		ImagSingle{'0.1iF', u32(0x3dcccccd)},
		ImagSingle{'0.1if', u32(0x3dcccccd)},
		ImagSingle{'0.1Fi', u32(0x3dcccccd)},
		ImagSingle{'0.1IF', u32(0x3dcccccd)},
		ImagSingle{'1.0iF', u32(0x3f800000)},
		ImagSingle{'0x1p-1fI', u32(0x3f000000)},
	]
	for c in singles {
		value, single := parse_imaginary_literal(c.text) or { panic(err) }
		assert single, '${c.text} is a float _Complex and this reader did not say so'
		assert math.f32_bits(f32(value)) == c.bits, '${c.text} read to the wrong bits'
	}
	doubles := [
		ImagDouble{'0.1i', u64(0x3fb999999999999a)},
		ImagDouble{'0.1I', u64(0x3fb999999999999a)},
		ImagDouble{'0.1j', u64(0x3fb999999999999a)},
		ImagDouble{'0.1J', u64(0x3fb999999999999a)},
		ImagDouble{'1.0i', u64(0x3ff0000000000000)},
		ImagDouble{'0x1p3i', u64(0x4020000000000000)},
	]
	for c in doubles {
		value, single := parse_imaginary_literal(c.text) or { panic(err) }
		assert !single, '${c.text} is a double _Complex and this reader did not say so'
		assert math.f64_bits(value) == c.bits, '${c.text} read to the wrong bits'
	}
	// The real part is zero, which is what 6.4.4.2 leaves it as and what the
	// node carries: neither reader above answers with a real part at all.
	assert !is_imaginary_constant('1.0')
	assert is_imaginary_constant('1.0if')
	assert is_imaginary_constant('1.0Fi')
	assert is_imaginary_constant('0x1p3i')
	assert !is_imaginary_constant('0x1p3')
}

// An imaginary constant this compiler has no value for is refused by name, and
// the name says which spelling asked for it. gcc 16.2.1 reads `1i` as a
// `float _Complex`, which is what an integer coefficient is refused for: the
// answer this compiler would give is a double one, and a type the program did
// not write is worse than a refusal.
fn test_a_refused_imaginary_constant_is_named() {
	assert imaginary_reject('1.0il').contains('a long double complex')
	assert imaginary_reject('1.0li').contains('a long double complex')
	assert imaginary_reject('1i').contains('written on a floating constant')
	assert imaginary_reject('1iF').contains('written on a floating constant')
	// Two markers are not one marker: the last one comes off and what is left
	// still carries one, so it is not a floating constant at all.
	assert imaginary_reject('0.1ij').contains('is not part of a floating constant')
	// `1iF` is shaped like an imaginary constant, which is why the reader is
	// reached at all; what it is refused for is the coefficient, which is `1F`
	// and is not a floating constant. Reading it as the double this compiler
	// would answer would be a type the program did not write, and gcc 16.2.1
	// refuses the same spelling.
	assert is_imaginary_constant('1iF')
}

fn imaginary_reject(text string) string {
	parse_imaginary_literal(text) or { return err.msg() }
	return ''
}
