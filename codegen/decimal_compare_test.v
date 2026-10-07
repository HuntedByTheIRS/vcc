module codegen

import ast
import os
import parser
import time
import tokenize

// The answers to the six comparison operators and the logical not, measured from
// gcc 16.2.1 with the same two volatile operands a program carries. Each row is
// the width, the two spellings of the operands, the operator and the answer gcc
// printed; the operand is volatile so the comparison is the routine a program runs
// and not a constant the front end could fold.
//
// The rows are the places the order is not the obvious one: two equal values
// written with a different exponent or a different number of digits, a zero that
// carries a power of ten and so has other bytes than the plain zero, an infinity
// against a finite value, and the boundary of each format's precision.
const decimal_compare_rows = [
	'_Decimal32 1.5df 15e-1df == 1',
	'_Decimal32 1.5df 15e-1df != 0',
	'_Decimal32 1.5df 15e-1df < 0',
	'_Decimal32 1.5df 15e-1df <= 1',
	'_Decimal32 1.5df 15e-1df > 0',
	'_Decimal32 1.5df 15e-1df >= 1',
	'_Decimal32 1.5df 1.50df == 1',
	'_Decimal32 1.5df 1.50df != 0',
	'_Decimal32 1.5df 1.50df < 0',
	'_Decimal32 1.5df 1.50df <= 1',
	'_Decimal32 1.5df 1.50df > 0',
	'_Decimal32 1.5df 1.50df >= 1',
	'_Decimal32 0.0df 0e30df == 1',
	'_Decimal32 0.0df 0e30df != 0',
	'_Decimal32 0.0df 0e30df < 0',
	'_Decimal32 0.0df 0e30df <= 1',
	'_Decimal32 0.0df 0e30df > 0',
	'_Decimal32 0.0df 0e30df >= 1',
	'_Decimal32 1.0df 2.0df == 0',
	'_Decimal32 1.0df 2.0df != 1',
	'_Decimal32 1.0df 2.0df < 1',
	'_Decimal32 1.0df 2.0df <= 1',
	'_Decimal32 1.0df 2.0df > 0',
	'_Decimal32 1.0df 2.0df >= 0',
	'_Decimal32 -1.0df 1.0df == 0',
	'_Decimal32 -1.0df 1.0df != 1',
	'_Decimal32 -1.0df 1.0df < 1',
	'_Decimal32 -1.0df 1.0df <= 1',
	'_Decimal32 -1.0df 1.0df > 0',
	'_Decimal32 -1.0df 1.0df >= 0',
	'_Decimal32 1e7df 9999999.0df == 0',
	'_Decimal32 1e7df 9999999.0df != 1',
	'_Decimal32 1e7df 9999999.0df < 0',
	'_Decimal32 1e7df 9999999.0df <= 0',
	'_Decimal32 1e7df 9999999.0df > 1',
	'_Decimal32 1e7df 9999999.0df >= 1',
	'_Decimal32 1e100df 1.5df == 0',
	'_Decimal32 1e100df 1.5df != 1',
	'_Decimal32 1e100df 1.5df < 0',
	'_Decimal32 1e100df 1.5df <= 0',
	'_Decimal32 1e100df 1.5df > 1',
	'_Decimal32 1e100df 1.5df >= 1',
	'_Decimal32 -1e100df 1.5df == 0',
	'_Decimal32 -1e100df 1.5df != 1',
	'_Decimal32 -1e100df 1.5df < 1',
	'_Decimal32 -1e100df 1.5df <= 1',
	'_Decimal32 -1e100df 1.5df > 0',
	'_Decimal32 -1e100df 1.5df >= 0',
	'_Decimal32 0.0df -0.0df == 1',
	'_Decimal32 0.0df -0.0df != 0',
	'_Decimal32 0.0df -0.0df < 0',
	'_Decimal32 0.0df -0.0df <= 1',
	'_Decimal32 0.0df -0.0df > 0',
	'_Decimal32 0.0df -0.0df >= 1',
	'_Decimal64 1.5dd 15e-1dd == 1',
	'_Decimal64 1.5dd 15e-1dd != 0',
	'_Decimal64 1.5dd 15e-1dd < 0',
	'_Decimal64 1.5dd 15e-1dd <= 1',
	'_Decimal64 1.5dd 15e-1dd > 0',
	'_Decimal64 1.5dd 15e-1dd >= 1',
	'_Decimal64 1.5dd 1.50dd == 1',
	'_Decimal64 1.5dd 1.50dd != 0',
	'_Decimal64 1.5dd 1.50dd < 0',
	'_Decimal64 1.5dd 1.50dd <= 1',
	'_Decimal64 1.5dd 1.50dd > 0',
	'_Decimal64 1.5dd 1.50dd >= 1',
	'_Decimal64 0.0dd 0e300dd == 1',
	'_Decimal64 0.0dd 0e300dd != 0',
	'_Decimal64 0.0dd 0e300dd < 0',
	'_Decimal64 0.0dd 0e300dd <= 1',
	'_Decimal64 0.0dd 0e300dd > 0',
	'_Decimal64 0.0dd 0e300dd >= 1',
	'_Decimal64 1.0dd 2.0dd == 0',
	'_Decimal64 1.0dd 2.0dd != 1',
	'_Decimal64 1.0dd 2.0dd < 1',
	'_Decimal64 1.0dd 2.0dd <= 1',
	'_Decimal64 1.0dd 2.0dd > 0',
	'_Decimal64 1.0dd 2.0dd >= 0',
	'_Decimal64 -1.0dd 1.0dd == 0',
	'_Decimal64 -1.0dd 1.0dd != 1',
	'_Decimal64 -1.0dd 1.0dd < 1',
	'_Decimal64 -1.0dd 1.0dd <= 1',
	'_Decimal64 -1.0dd 1.0dd > 0',
	'_Decimal64 -1.0dd 1.0dd >= 0',
	'_Decimal64 1e19dd 9007199254740993.0dd == 0',
	'_Decimal64 1e19dd 9007199254740993.0dd != 1',
	'_Decimal64 1e19dd 9007199254740993.0dd < 0',
	'_Decimal64 1e19dd 9007199254740993.0dd <= 0',
	'_Decimal64 1e19dd 9007199254740993.0dd > 1',
	'_Decimal64 1e19dd 9007199254740993.0dd >= 1',
	'_Decimal64 1e400dd 1.5dd == 0',
	'_Decimal64 1e400dd 1.5dd != 1',
	'_Decimal64 1e400dd 1.5dd < 0',
	'_Decimal64 1e400dd 1.5dd <= 0',
	'_Decimal64 1e400dd 1.5dd > 1',
	'_Decimal64 1e400dd 1.5dd >= 1',
	'_Decimal64 -1e400dd 1.5dd == 0',
	'_Decimal64 -1e400dd 1.5dd != 1',
	'_Decimal64 -1e400dd 1.5dd < 1',
	'_Decimal64 -1e400dd 1.5dd <= 1',
	'_Decimal64 -1e400dd 1.5dd > 0',
	'_Decimal64 -1e400dd 1.5dd >= 0',
	'_Decimal64 0.0dd -0.0dd == 1',
	'_Decimal64 0.0dd -0.0dd != 0',
	'_Decimal64 0.0dd -0.0dd < 0',
	'_Decimal64 0.0dd -0.0dd <= 1',
	'_Decimal64 0.0dd -0.0dd > 0',
	'_Decimal64 0.0dd -0.0dd >= 1',
	'_Decimal64 0.1dd 0.1dd == 1',
	'_Decimal64 0.1dd 0.1dd != 0',
	'_Decimal64 0.1dd 0.1dd < 0',
	'_Decimal64 0.1dd 0.1dd <= 1',
	'_Decimal64 0.1dd 0.1dd > 0',
	'_Decimal64 0.1dd 0.1dd >= 1',
	'_Decimal128 1.5dl 15e-1dl == 1',
	'_Decimal128 1.5dl 15e-1dl != 0',
	'_Decimal128 1.5dl 15e-1dl < 0',
	'_Decimal128 1.5dl 15e-1dl <= 1',
	'_Decimal128 1.5dl 15e-1dl > 0',
	'_Decimal128 1.5dl 15e-1dl >= 1',
	'_Decimal128 1.5dl 1.50dl == 1',
	'_Decimal128 1.5dl 1.50dl != 0',
	'_Decimal128 1.5dl 1.50dl < 0',
	'_Decimal128 1.5dl 1.50dl <= 1',
	'_Decimal128 1.5dl 1.50dl > 0',
	'_Decimal128 1.5dl 1.50dl >= 1',
	'_Decimal128 0.0dl 0e300dl == 1',
	'_Decimal128 0.0dl 0e300dl != 0',
	'_Decimal128 0.0dl 0e300dl < 0',
	'_Decimal128 0.0dl 0e300dl <= 1',
	'_Decimal128 0.0dl 0e300dl > 0',
	'_Decimal128 0.0dl 0e300dl >= 1',
	'_Decimal128 1.0dl 2.0dl == 0',
	'_Decimal128 1.0dl 2.0dl != 1',
	'_Decimal128 1.0dl 2.0dl < 1',
	'_Decimal128 1.0dl 2.0dl <= 1',
	'_Decimal128 1.0dl 2.0dl > 0',
	'_Decimal128 1.0dl 2.0dl >= 0',
	'_Decimal128 -1.0dl 1.0dl == 0',
	'_Decimal128 -1.0dl 1.0dl != 1',
	'_Decimal128 -1.0dl 1.0dl < 1',
	'_Decimal128 -1.0dl 1.0dl <= 1',
	'_Decimal128 -1.0dl 1.0dl > 0',
	'_Decimal128 -1.0dl 1.0dl >= 0',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl == 0',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl != 1',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl < 0',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl <= 0',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl > 1',
	'_Decimal128 1e30dl 123456789012345678901234567890.1dl >= 1',
	'_Decimal128 1e6200dl 1.5dl == 0',
	'_Decimal128 1e6200dl 1.5dl != 1',
	'_Decimal128 1e6200dl 1.5dl < 0',
	'_Decimal128 1e6200dl 1.5dl <= 0',
	'_Decimal128 1e6200dl 1.5dl > 1',
	'_Decimal128 1e6200dl 1.5dl >= 1',
	'_Decimal128 -1e6200dl 1.5dl == 0',
	'_Decimal128 -1e6200dl 1.5dl != 1',
	'_Decimal128 -1e6200dl 1.5dl < 1',
	'_Decimal128 -1e6200dl 1.5dl <= 1',
	'_Decimal128 -1e6200dl 1.5dl > 0',
	'_Decimal128 -1e6200dl 1.5dl >= 0',
	'_Decimal128 0.0dl -0.0dl == 1',
	'_Decimal128 0.0dl -0.0dl != 0',
	'_Decimal128 0.0dl -0.0dl < 0',
	'_Decimal128 0.0dl -0.0dl <= 1',
	'_Decimal128 0.0dl -0.0dl > 0',
	'_Decimal128 0.0dl -0.0dl >= 1',
]

// The logical not of one decimal of each width, measured the same way. It asks
// whether the value is zero, so a zero of either sign is one, an infinity and a
// value that is not zero is zero, and a zero written with another exponent is
// still a zero.
const decimal_not_rows = [
	'_Decimal32 0.0df 1',
	'_Decimal32 0e30df 1',
	'_Decimal32 1.5df 0',
	'_Decimal32 -1.0df 0',
	'_Decimal32 1e100df 0',
	'_Decimal64 0.0dd 1',
	'_Decimal64 0e300dd 1',
	'_Decimal64 1.5dd 0',
	'_Decimal64 -1.0dd 0',
	'_Decimal64 1e400dd 0',
	'_Decimal64 0.1dd 0',
	'_Decimal128 0.0dl 1',
	'_Decimal128 0e300dl 1',
	'_Decimal128 1.5dl 0',
	'_Decimal128 -1.0dl 0',
	'_Decimal128 1e6200dl 0',
]

// decimal_compare_translation_unit reads a program the way the front end does.
fn decimal_compare_translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_compare_run writes the image and runs it, so the test checks the
// artifact and not the intent behind it.
fn decimal_compare_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_compare_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

// decimal_compare_program writes every comparison row into one program: a volatile
// object of each operand's width and a printf of the comparison, in the order the
// rows are written, so the run's output lines up with them.
fn decimal_compare_program() string {
	mut source := 'int printf(const char *, ...);\nint main(void) {\n'
	for row in decimal_compare_rows {
		parts := row.split(' ')
		source += '\t{\n'
		source += '\t\tvolatile ${parts[0]} a = ${parts[1]};\n'
		source += '\t\tvolatile ${parts[0]} b = ${parts[2]};\n'
		source += '\t\tprintf("%d\\n", a ${parts[3]} b);\n'
		source += '\t}\n'
	}
	source += '\treturn 0;\n}\n'
	return source
}

// decimal_not_program writes every logical-not row into one program the same way.
fn decimal_not_program() string {
	mut source := 'int printf(const char *, ...);\nint main(void) {\n'
	for row in decimal_not_rows {
		parts := row.split(' ')
		source += '\t{\n'
		source += '\t\tvolatile ${parts[0]} a = ${parts[1]};\n'
		source += '\t\tprintf("%d\\n", !a);\n'
		source += '\t}\n'
	}
	source += '\treturn 0;\n}\n'
	return source
}

fn test_a_comparison_a_program_makes_is_the_one_gcc_makes() {
	emitted := emit(decimal_compare_translation_unit(decimal_compare_program()), Options{})
	assert tokenize.errors(emitted.diagnostics).len == 0, 'a comparison was refused: ${emitted.diagnostics[0].msg}'
	result := decimal_compare_run(emitted.bytes)
	assert result.exit_code == 0, 'the program exited ${result.exit_code}'
	got := result.output.trim_space().split('\n')
	assert got.len == decimal_compare_rows.len, 'the program printed ${got.len} lines, not ${decimal_compare_rows.len}'
	for i, row in decimal_compare_rows {
		want := row.split(' ')[4]
		assert got[i] == want, '${row}: the routine made ${got[i]}'
	}
}

fn test_the_logical_not_of_a_decimal_is_the_one_gcc_makes() {
	emitted := emit(decimal_compare_translation_unit(decimal_not_program()), Options{})
	assert tokenize.errors(emitted.diagnostics).len == 0, 'the logical not was refused: ${emitted.diagnostics[0].msg}'
	result := decimal_compare_run(emitted.bytes)
	assert result.exit_code == 0, 'the program exited ${result.exit_code}'
	got := result.output.trim_space().split('\n')
	assert got.len == decimal_not_rows.len, 'the program printed ${got.len} lines, not ${decimal_not_rows.len}'
	for i, row in decimal_not_rows {
		want := row.split(' ')[2]
		assert got[i] == want, '${row}: the routine made ${got[i]}'
	}
}

fn test_a_nan_compares_unordered() {
	// A NaN has no spelling, so its bytes are written into the object through its
	// address. Every operator is false but !=, which is true.
	source := 'int printf(const char *, ...);\n' +
		'int memcpy(void *, const void *, unsigned long);\n' +
		'int main(void) {\n' +
		'\tvolatile _Decimal64 a = 1.5dd;\n' +
		'\tvolatile _Decimal64 n;\n' +
		'\tunsigned char bytes[8] = { 0, 0, 0, 0, 0, 0, 0, 0x7c };\n' +
		'\tmemcpy(&n, bytes, sizeof bytes);\n' +
		'\tprintf("%d %d %d %d %d %d\\n", n == n, n != n, n < a, n <= a, n > a, n >= a);\n' +
		'\treturn 0;\n}\n'
	emitted := emit(decimal_compare_translation_unit(source), Options{})
	assert tokenize.errors(emitted.diagnostics).len == 0, 'the NaN comparison was refused: ${emitted.diagnostics[0].msg}'
	result := decimal_compare_run(emitted.bytes)
	assert result.exit_code == 0, 'the program exited ${result.exit_code}'
	assert result.output.trim_space() == '0 1 0 0 0 0', 'the routine made ${result.output.trim_space()}'
}
