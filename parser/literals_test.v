module parser

import math
import tokenize
import types
import decimal
import ast

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
	// which this compiler reads and stores now, so the reader takes it. The
	// value 0x1.8p3 is 12.0, and the significand and power of two are the ones
	// gcc 16.2.1 produces for the same spelling, read as extended bits rather
	// than as a decimal that would round and hide a value one bit off.
	wide := parse_long_double_literal('0x1.8p3L') or {
		assert false
		return
	}
	assert wide.mantissa == 0xc000000000000000
	assert wide.exponent() == 3
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

// An escape gcc does not know is the character itself and not a refusal. Measured
// on gcc 16.2.1 with -std=gnu11, which compiles and runs a program printing each
// of these values: `\q` is 113 and `\8` is 56 under a warning, and `\e` is 27 with
// no warning at all, so GNU's escape character is a spelling gcc knows rather than
// one it tolerates. V's own generated C writes `'\`'` where `'`'` would do, and
// every one of the 47 lines of it this compiler refused named the backtick.
fn test_an_escape_gcc_does_not_know_is_the_character_itself() {
	assert (parse_escape('`') or { i64(-1) }) == 96
	assert (parse_escape('q') or { i64(-1) }) == 113
	assert (parse_escape('8') or { i64(-1) }) == 56
	assert (parse_escape('e') or { i64(-1) }) == 27
	// What stays refused is what gcc refuses too: an escape with nothing behind the
	// backslash, and a hex escape with no digit.
	assert (parse_escape('') or { i64(-1) }) == -1
	assert (parse_escape('x') or { i64(-1) }) == -1
	assert (parse_escape('xg') or { i64(-1) }) == -1
}

// The three decimal suffixes name the format a floating constant is stored in:
// `df`/`DF` is `_Decimal32`, `dd`/`DD` is `_Decimal64` and `dl`/`DL` is
// `_Decimal128`. Each pair is two spellings of one suffix and the reader takes
// both cases, which is what gcc 16.2.1 does.
//
// A suffix names a decimal only on a floating constant, and a floating constant is
// one that has a point or an exponent: measured, gcc calls `1df` an `invalid suffix
// "df" on integer constant` because it has neither, while `0.0df`, `1e6df` and
// `1.0df` are decimal constants. So a bare integer with a decimal suffix is not a
// decimal constant here either: it reaches the integer reader, which refuses the
// `d` as a digit that is not one, and that is the same answer gcc gives.
fn test_the_decimal_suffixes_name_their_format() {
	for text in ['1.5df', '1.5DF', '1e0df', '.5df', '5.df', '1.0df'] {
		assert is_decimal_constant(text), '${text} is a decimal constant'
	}
	for text in ['1.5dd', '1.5DD', '1e0dd', '.5dd', '5.dd'] {
		assert is_decimal_constant(text), '${text} is a decimal constant'
	}
	for text in ['1.5dl', '1.5DL', '1e0dl', '.5dl', '5.dl'] {
		assert is_decimal_constant(text), '${text} is a decimal constant'
	}
	// A bare integer with a decimal suffix is not one, and neither is a floating
	// constant with any other suffix.
	for text in ['1df', '1dd', '1dl', '1.5f', '1.5F', '1.5l', '1.5L', '1.5d', '1.5', '1e3', '1.5dfx',
		'0x1p3df'] {
		assert !is_decimal_constant(text), '${text} is not a decimal constant'
	}
	// The suffix picks the format and the format picks the type.
	assert decimal_kind_of('1.5df') == .decimal32
	assert decimal_kind_of('1.5DF') == .decimal32
	assert decimal_kind_of('1.5dd') == .decimal64
	assert decimal_kind_of('1.5DD') == .decimal64
	assert decimal_kind_of('1.5dl') == .decimal128
	assert decimal_kind_of('1.5DL') == .decimal128
}

// read_decimal is the value the reader made for a decimal constant, and
// decimal_word is that value encoded, most significant byte first, which is how
// the probes of gcc's own bytes print them. The encoding is the `decimal` module's;
// what is being checked here is that the digits, the power of ten and the sign the
// reader produced are the ones the encoding is written from.
fn read_decimal(text string) types.Decimal {
	return parse_decimal_literal(text) or {
		assert false, '${text} was refused: ${err.msg()}'
		return types.Decimal{}
	}
}

fn decimal_word(text string) string {
	value := read_decimal(text)
	bytes := decimal.encode(value.value(), value.decimal_format())
	mut out := ''
	for i := bytes.len - 1; i >= 0; i-- {
		out += '${bytes[i]:02x}'
	}
	return out
}

// Rows of the literal and the bytes gcc 16.2.1 stores for it, most significant byte
// first. The same rows are the `decimal` module's, whose encoder was verified
// against the union probes in the measuring lane's scratch directory; the reader's
// own round trip through that encoder is what these check, so a reader that keeps
// the wrong digits or the wrong power of ten fails here rather than at the back end.
//
// The rows cover the canonical form, the large form (a coefficient at or above two
// to the coefficient bits), a coefficient padded by powers of ten to reach the
// exponent field, the zero, the smallest normal and the widest values, at all three
// widths.
const reader_rows = [
	'0.0df 32000000',
	'1.0df 3200000a',
	'1.5df 3200000f',
	'12.5df 3200007d',
	'1e6df 35800001',
	'1e-6df 2f800001',
	'1e96df 5f8f4240',
	'1234567.0df 3292d687',
	'123456.7df 3212d687',
	'8388607.0df 32ffffff',
	'8388608.0df 6ca00000',
	'9999999.0df 6cb8967f',
	'0.0dd 31a0000000000000',
	'1.0dd 31a000000000000a',
	'1.5dd 31a000000000000f',
	'2.5dd 31a0000000000019',
	'1e10dd 3300000000000001',
	'1e-10dd 3080000000000001',
	'1e384dd 5fe38d7ea4c68000',
	'1e-398dd 0000000000000001',
	'1234567890123456.0dd 31c462d53c8abac0',
	'9007199254740991.0dd 31dfffffffffffff',
	'9007199254740992.0dd 6c70000000000000',
	'9999999999999999.0dd 6c7386f26fc0ffff',
	'0.0dl 303e0000000000000000000000000000',
	'1.0dl 303e000000000000000000000000000a',
	'3.5dl 303e0000000000000000000000000023',
	'1e6144dl 5ffe314dc6448d9338c15b0a00000000',
]

fn test_a_decimal_constant_reads_to_the_bytes_gcc_stores() {
	for row in reader_rows {
		text := row.all_before(' ')
		want := row.all_after(' ')
		assert decimal_word(text) == want, '${text} read as ${decimal_word(text)}, gcc stores ${want}'
	}
}

// A decimal constant's spelling, the digits the reader keeps for it and the power of
// ten they are scaled by. The rows below are the reader's own answers, so the digits
// and the power are what a second reader would have to produce to agree with gcc's
// bytes, which the round trip above checks.
struct ReadDecimal {
	text   string
	digits string
	power  int
}

// A decimal constant keeps the digits the source wrote, at the precision the format
// keeps, and is not normalised. That is what the measured bytes say: `1.0dd` is a
// coefficient of ten at the power minus one and not a coefficient of one at the
// power zero, and `1.500000df` is 1500000 at the power minus six.
const written_digits = [
	ReadDecimal{'1.0dd', '10', -1},
	ReadDecimal{'1.5df', '15', -1},
	ReadDecimal{'1.500df', '1500', -3},
	ReadDecimal{'1.500000df', '1500000', -6},
	ReadDecimal{'25.0dd', '250', -1},
	ReadDecimal{'1e6df', '1', 6},
	ReadDecimal{'1e-95df', '1', -95},
]

fn test_a_decimal_constant_keeps_the_digits_the_source_wrote() {
	for row in written_digits {
		value := read_decimal(row.text)
		assert value.digits_text() == row.digits, '${row.text} read the digits ${value.digits_text()}'
		assert value.exponent == row.power, '${row.text} read the power ${value.exponent}'
		assert value.kind == decimal_kind_of(row.text)
		assert value.special == .finite
	}
}

// A zero keeps no digits and the exponent the source wrote, because the encoding of
// a zero carries its exponent: measured, `0.0df` is the bytes 32000000, the power
// minus one in the exponent field, and `0e0dd` is the power zero.
fn test_a_decimal_zero_keeps_the_exponent_the_source_wrote() {
	zero := read_decimal('0.0df')
	assert zero.is_zero() && zero.digits_text() == '0'
	assert zero.exponent == -1
	assert decimal_word('0.0df') == '32000000'
	plain := read_decimal('0.0dd')
	assert plain.is_zero() && plain.exponent == -1
	assert decimal_word('0.0dd') == '31a0000000000000'
	assert read_decimal('0e0dd').exponent == 0
	assert read_decimal('0.000000df').exponent == -6
}

// Reading rounds once to the precision the format keeps, ties to even, and the
// digits are the ones the source wrote up to that point: measured on gcc 16.2.1 in
// `_Decimal32`, whose precision is seven digits, `1.0000015df` keeps 1000002 at the
// power minus six, because the tie rounds onto the odd 1, while `1.0000005df` keeps
// 1000000, because the tie rounds onto the even 0.
//
// When the rounding carries out of the most significant digit the answer is one
// followed by as many zeros as the precision allows, at one power of ten higher,
// which is the widest value at that precision: measured, `9999999.5df` is the
// digits 1000000 at the power one, written 1.000000e7, and gcc stores the same
// coefficient and exponent.
const rounded_digits = [
	ReadDecimal{'1.0000015df', '1000002', -6},
	ReadDecimal{'1.0000005df', '1000000', -6},
	ReadDecimal{'1.0000025df', '1000002', -6},
	ReadDecimal{'9999999.5df', '1000000', 1},
	ReadDecimal{'9999999.4df', '9999999', 0},
	ReadDecimal{'9007199254740991.0dd', '9007199254740991', 0},
	ReadDecimal{'9007199254740992.0dd', '9007199254740992', 0},
	ReadDecimal{'1234567890123456789012345678901234.0dl', '1234567890123456789012345678901234', 0},
]

fn test_a_decimal_constant_is_rounded_once_to_the_precisions_digits() {
	for row in rounded_digits {
		value := read_decimal(row.text)
		assert value.digits_text() == row.digits, '${row.text} read ${value.digits_text()}'
		assert value.exponent == row.power, '${row.text} read the power ${value.exponent}'
	}
	// The digits that fit are the digits that stay, however few of them there are.
	assert read_decimal('.5df').digits_text() == '5'
	assert read_decimal('0.1dd').digits_text() == '1'
	assert read_decimal('0.1dd').exponent == -1
	assert read_decimal('1e6df').digits_text() == '1'
}

// A constant outside the format's range is read, not refused. Measured on gcc
// 16.2.1, `1e400dd` is `warning: floating constant exceeds range of '_Decimal64'`
// and the value it stores is an infinity, while `1e-400dd` is `warning: floating
// constant truncated to zero` and the value it stores is a zero. In `_Decimal32`,
// whose range ends at `1e96` and `1e-101`, `1e300df` is 0x78000000 - an infinity -
// and `1e-300df` is 0x00000000.
fn test_a_decimal_constant_outside_its_range_reads_as_an_infinity_or_a_zero() {
	beyond := read_decimal('1e400dd')
	assert beyond.special == .infinity
	assert beyond.is_zero()
	assert decimal_range_warning('1e400dd', beyond) == "floating constant exceeds range of '_Decimal64'"
	below := read_decimal('1e-400dd')
	assert below.special == .finite && below.is_zero()
	assert decimal_range_warning('1e-400dd', below) == 'floating constant truncated to zero'
	narrow := read_decimal('1e300df')
	assert narrow.special == .infinity && narrow.kind == .decimal32
	assert decimal_range_warning('1e300df', narrow) == "floating constant exceeds range of '_Decimal32'"
	tiny := read_decimal('1e-300df')
	assert tiny.special == .finite && tiny.is_zero()
	assert decimal_range_warning('1e-300df', tiny) == 'floating constant truncated to zero'
	wide := read_decimal('1e6145dl')
	assert wide.special == .infinity && wide.kind == .decimal128
	// The largest exponents each format holds are read, not moved: the encoding
	// pads the coefficient into the exponent field where it has to.
	assert read_decimal('1e96df').special == .finite
	assert read_decimal('1e-95df').special == .finite
	assert read_decimal('1e6144dl').special == .finite
	// A zero the source wrote is not a truncation, however small the exponent is:
	// the coefficient is what says so, and it is all zeros.
	assert decimal_range_warning('0.0df', read_decimal('0.0df')) == ''
	assert decimal_range_warning('0e-400dd', read_decimal('0e-400dd')) == ''
	// The bytes of the value say which of the two it is, and gcc 16.2.1's are
	// these: measured with a union of the value and its bytes, `0.0df` is
	// 32000000, `0e30df` is 41800000, `1e300df` is 78000000 - an infinity of the
	// sign the source wrote - `0e-400dd` is 0000000000000000 (a written power
	// below the field brought up to its bottom) and both truncated zeros,
	// `1e-300df` and `1e-400dd`, are all zeros.
	assert decimal_word('0.0df') == '32000000'
	assert decimal_word('0e30df') == '41800000'
	assert decimal_word('1e300df') == '78000000'
	assert decimal_word('0e-400dd') == '0000000000000000'
	assert decimal_word('1e-300df') == '00000000'
	assert decimal_word('1e-400dd') == '0000000000000000'
}

// The warning is reported where the constant was written, and it is a warning: the
// compile goes on. Measured on gcc 16.2.1, the diagnostic carries the location of
// the constant, the identifier `_Decimal64` for the format and gcc's own wording.
fn test_a_decimal_constant_out_of_range_is_a_warning_at_its_location() {
	source := 'int main(void) { _Decimal64 x = 1e400dd; return 0; }\n'
	lexed := tokenize.lex(source)
	result := parse(lexed.tokens)
	out_of_range := result.diagnostics.filter(it.msg.contains('exceeds range'))
	assert out_of_range.len == 1
	assert out_of_range[0].warning
	assert out_of_range[0].msg == "floating constant exceeds range of '_Decimal64'"
	assert out_of_range[0].line == 1
	found := source.index('1e400dd') or {
		assert false
		return
	}
	assert out_of_range[0].col == found + 1
	truncated := parse(tokenize.lex('int main(void) { _Decimal32 y = 1e-400df; return 0; }\n').tokens)
	to_zero := truncated.diagnostics.filter(it.msg.contains('truncated to zero'))
	assert to_zero.len == 1
	assert to_zero[0].warning
	assert to_zero[0].msg == 'floating constant truncated to zero'
	// A constant that fits says nothing at all.
	quiet := parse(tokenize.lex('int main(void) { _Decimal32 z = 1.5df; return 0; }\n').tokens)
	assert quiet.diagnostics.len == 0
}

// literal_returned_by is the floating literal in the body of the one function the
// source defines, which is how the type and the value a decimal constant carries are
// read out of the tree rather than out of the reader that made them.
fn literal_returned_by(source string) ast.FloatLit {
	result := parse(tokenize.lex(source).tokens)
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 1
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return ast.FloatLit{}
	}
	return expr as ast.FloatLit
}

// A decimal constant's type is the format its suffix named, which is what the
// literal in the tree carries into the back end: `1.5df` is a `_Decimal32`, `2.5dd`
// a `_Decimal64` and `3.5dl` a `_Decimal128`, and the value beside the type is the
// one the reader made rather than a host number that would round it.
fn test_a_decimal_constant_carries_its_type_and_its_value() {
	for text in ['1.5df', '2.5dd', '3.5dl'] {
		result := parse(tokenize.lex('int main(void) { return ${text}; }\n').tokens)
		assert result.diagnostics.len == 0, '${text} was refused'
	}
	literal := literal_returned_by('_Decimal32 half(void) { return 1.5df; }\n')
	assert literal.typ.same(types.decimal_type(.decimal32))
	assert literal.text == '1.5df'
	assert literal.decimal_value.kind == .decimal32
	assert literal.decimal_value.digits_text() == '15'
	assert literal.decimal_value.exponent == -1
	// The double a decimal constant is not: the plain float path is untouched, so a
	// constant with no decimal suffix is still the double it always was, and its
	// decimal field is the unset one.
	ordinary := literal_returned_by('double half(void) { return 1.5; }\n')
	assert ordinary.typ.same(types.double_type())
	assert ordinary.decimal_value.kind == .unknown
}
