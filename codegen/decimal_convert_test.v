module codegen

import ast
import os
import parser
import time
import tokenize

// Every decimal conversion, with the bytes gcc 16.2.1 makes, measured through
// this file's own programs: each row's source was compiled with gcc -std=gnu99
// -O0 and the bytes it printed are the row's last field, least significant byte
// first. The rows are the places a conversion goes wrong.
//
// A decimal to an integer discards the fraction toward zero, and a value past
// what the integer holds saturates. A decimal to a float or a double rounds into
// the binary format, which is not the decimal that was written for a tenth and is
// an infinity past what the binary format holds. An integer to a decimal rounds
// to the destination's precision, ties to even. A width conversion rounds to the
// destination's precision and answers zero or an infinity past what it holds, and
// it keeps the exponent of a zero. Negating one flips the sign bit, and one is
// not zero unless its coefficient is, whatever its sign and its exponent.
//
// The operand is stored in a volatile object where the conversion is the one a
// program runs at run time, and in a plain object where it is one the compiler
// can fold: the two spellings have to answer the same bytes.
//
// A row is `declaration|result type|bytes|cast|bytes gcc made`, all hex.
const decimal_cast_rows = [
	'_Decimal32 a = 1234567.8df|int|4|(int) a|88d61200',
	'_Decimal32 a = -1234567.8df|int|4|(int) a|7829edff',
	'_Decimal64 b = 123456789012345.6dd|long|8|(long) b|79df0d8648700000',
	'_Decimal64 b = -123456789012345.6dd|long|8|(long) b|8720f279b78fffff',
	'_Decimal128 c = 123456789012345678901234567890.1dl|unsigned long|8|(unsigned long) c|0000000000000000',
	'_Decimal128 c = -123456789012345678901234567890.1dl|unsigned long|8|(unsigned long) c|0000000000000000',
	'volatile _Decimal32 a = 9999999.0df|int|4|(int) a|7f969800',
	'volatile _Decimal64 b = 1e-320dd|unsigned long|8|(unsigned long) b|0000000000000000',
	'_Decimal32 a = 1.5df|double|8|(double) a|000000000000f83f',
	'_Decimal64 b = 0.1dd|double|8|(double) b|9a9999999999b93f',
	'_Decimal128 c = 123456789012345678901234567890.1dl|double|8|(double) c|3e376cff90eef845',
	'_Decimal32 a = 1.5df|float|4|(float) a|0000c03f',
	'_Decimal64 b = 0.1dd|float|4|(float) b|cdcccc3d',
	'volatile _Decimal64 b = 1e384dd|float|4|(float) b|0000807f',
	'int i = -1234567|_Decimal32|4|(_Decimal32) i|87d692b2',
	'int i = 2147483647|_Decimal32|4|(_Decimal32) i|9cc42034',
	'long l = 123456789012345L|_Decimal64|8|(_Decimal64) l|79df0d864870c031',
	'long l = 9223372036854775807L|_Decimal64|8|(_Decimal64) l|f853e3a59bc4886c',
	'unsigned long u = 18446744073709551615UL|_Decimal128|16|(_Decimal128) u|ffffffffffffffff0000000000004030',
	'volatile unsigned long u = 18446744073709551615UL|_Decimal128|16|(_Decimal128) u|ffffffffffffffff0000000000004030',
	'_Decimal32 a = 1.5df|_Decimal64|8|(_Decimal64) a|0f0000000000a031',
	'_Decimal32 a = 0.0df|_Decimal64|8|(_Decimal64) a|000000000000a031',
	'_Decimal32 a = 1e96df|_Decimal64|8|(_Decimal64) a|40420f000000003d',
	'_Decimal32 a = 1e-101df|_Decimal128|16|(_Decimal128) a|0100000000000000000000000000762f',
	'_Decimal64 b = 1234567.8dd|_Decimal32|4|(_Decimal32) b|88d69232',
	'_Decimal64 b = 1e-398dd|_Decimal32|4|(_Decimal32) b|00000000',
	'_Decimal64 b = 1.5dd|_Decimal128|16|(_Decimal128) b|0f000000000000000000000000003e30',
	'_Decimal128 c = 1234567.8dl|_Decimal32|4|(_Decimal32) c|88d69232',
	'_Decimal128 c = 1234567.8dl|_Decimal64|8|(_Decimal64) c|4e61bc000000a031',
	'_Decimal128 c = 1e-6176dl|_Decimal64|8|(_Decimal64) c|0000000000000000',
	'_Decimal32 a = 1234567.8df|_Decimal32|4|-a|88d692b2',
	'_Decimal64 b = 1e-398dd|_Decimal64|8|-b|0100000000000080',
	'_Decimal128 c = 1.5dl|_Decimal128|16|-c|0f000000000000000000000000003eb0',
	'_Decimal32 a = 0.0df|int|4|!a|01000000',
	'_Decimal64 b = -0.0dd|int|4|!b|01000000',
	'_Decimal128 c = 1.5dl|int|4|!c|00000000',
]

// decimal_cast_unit reads a program the way the front end does.
fn decimal_cast_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_cast_run writes the image and runs it, so the test checks the artifact
// and not the intent behind it.
fn decimal_cast_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_cast_test_${os.getpid()}_${time.now().unix()}_${image.len}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

// decimal_cast_program is a C program that declares the row's operand, applies
// the row's conversion to it, and prints the result's bytes as hex. The loop
// counter is `k` because a row's operand may be named `i`.
fn decimal_cast_program(decl string, rtype string, bytes int, cast string) string {
	return 'int printf(const char *, ...);\n' +
		'int memcpy(void *, const void *, unsigned long);\n' +
		'int main(void) {\n' +
		'\t${decl};\n' +
		'\t${rtype} r = ${cast};\n' +
		'\tunsigned char o[${bytes}];\n' +
		'\tint k;\n' +
		'\tmemcpy(o, &r, ${bytes});\n' +
		'\tfor (k = 0; k < ${bytes}; k++) printf("%02x", (unsigned) o[k]);\n' +
		'\tprintf("\\n");\n' +
		'\treturn 0;\n' +
		'}\n'
}

fn test_every_decimal_cast_makes_the_bytes_gcc_makes() {
	for row in decimal_cast_rows {
		parts := row.split('|')
		assert parts.len == 5, row
		decl := parts[0]
		rtype := parts[1]
		bytes := parts[2].int()
		cast := parts[3]
		want := parts[4]
		source := decimal_cast_program(decl, rtype, bytes, cast)
		emitted := emit(decimal_cast_unit(source), Options{})
		assert tokenize.errors(emitted.diagnostics).len == 0, '${row}: ${emitted.diagnostics[0].msg}'
		result := decimal_cast_run(emitted.bytes)
		assert result.exit_code == 0, '${row}: the program exited ${result.exit_code}'
		got := result.output.trim_space()
		assert got == want, '${row}: the conversion made ${got}, gcc made ${want}'
	}
}
