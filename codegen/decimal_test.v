module codegen

import ast
import os
import parser
import time
import tokenize

// The double each literal converts to, measured from gcc 16.2.1 with a union of
// a double and its bits. The rows are decimal/convert_test.v's table, which is
// the module's own record of what gcc makes; decimal-vectors.json in the agent's
// scratch directory holds the same rows with the bytes beside them.
//
// Each literal is stored in a volatile object before it is converted, so the
// conversion is one the compiler cannot fold: what is tested is the routine a
// program carries and runs, and its answer has to be the folded one's bit for
// bit. The rows are the places a conversion goes wrong: a tenth, which is not a
// binary number; a tie at two to the fifty-third; a value below the smallest
// normal, which lands on a subnormal; a value past what a double holds; and a
// thirty-four digit decimal128, which has to round.
const decimal_folded_conversions = [
	'_Decimal32 1.5df 3ff8000000000000',
	'_Decimal32 -1.5df bff8000000000000',
	'_Decimal32 +1.5df 3ff8000000000000',
	'_Decimal32 0.0df 0000000000000000',
	'_Decimal32 0.1df 3fb999999999999a',
	'_Decimal32 1e-300df 0000000000000000',
	'_Decimal64 1.5dd 3ff8000000000000',
	'_Decimal64 0.1dd 3fb999999999999a',
	'_Decimal64 1234567890123456.0dd 43118b54f22aeb00',
	'_Decimal64 9007199254740993.0dd 4340000000000000',
	'_Decimal64 1e16dd 4341c37937e08000',
	'_Decimal64 1e-16dd 3c9cd2b297d889bc',
	'_Decimal64 1e-320dd 00000000000007e8',
	'_Decimal128 3.5dl 400c000000000000',
	'_Decimal128 1e50dl 4a511b0ec57e649a',
	'_Decimal128 1234567890123456789012345678901234.0dl 46ce6f37ffcb996f',
]

// decimal_translation_unit reads a program the way the front end does. Only
// errors are asserted away: one row is a decimal32 below its range, which the
// reader warns about and stores as a zero, and the warning is not what this test
// is checking.
fn decimal_translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_run writes the image and runs it, so the test checks the artifact and
// not the intent behind it.
fn decimal_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

// decimal_conversion_program is a C program that stores one decimal literal in a
// volatile object, converts it with the routine the emitter writes, and prints the
// double's bits as sixteen hex digits. The object is volatile so no part of the
// conversion can be folded at compile time.
fn decimal_conversion_program(typ string, literal string) string {
	return 'int printf(const char *, ...);\n' +
		'int memcpy(void *, const void *, unsigned long);\n' +
		'int main(void) {\n' +
		'\tvolatile ${typ} v = ${literal};\n' +
		'\tdouble d = (double) v;\n' +
		'\tunsigned long long b = 0;\n' +
		'\tmemcpy(&b, &d, sizeof b);\n' +
		'\tprintf("%016llx\\n", b);\n' +
		'\treturn 0;\n' +
		'}\n'
}

fn test_a_conversion_a_program_cannot_fold_makes_the_double_gcc_makes() {
	for row in decimal_folded_conversions {
		parts := row.split(' ')
		typ := parts[0]
		literal := parts[1]
		want := parts[2]
		emitted := emit(decimal_translation_unit(decimal_conversion_program(typ, literal)), Options{})
		assert tokenize.errors(emitted.diagnostics).len == 0, '${literal}: ${emitted.diagnostics[0].msg}'
		result := decimal_run(emitted.bytes)
		assert result.exit_code == 0, '${literal}: the program exited ${result.exit_code}'
		got := result.output.trim_space()
		assert got == want, '${literal}: the routine made ${got}, gcc made ${want}'
	}
}
