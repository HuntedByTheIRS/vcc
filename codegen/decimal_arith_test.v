module codegen

import ast
import os
import parser
import time
import tokenize

// Run-time decimal addition, subtraction and negation, measured from gcc 16.2.1.
//
// A decimal value is an object, so an operation on two of them is a routine the
// emitter writes that reads its operands where they live and stores the result.
// Each row is the type, the operator, the two operands and the bytes gcc stores
// for the result, in the order they sit in memory. The operands are volatile so
// no part of the operation can be folded: what is tested is the routine a program
// carries and runs.
//
// The rows are the places the arithmetic goes wrong. A cancellation, which is a
// zero carrying the operation's preferred exponent rather than a plain zero; an
// operand that is a zero, where the other operand is the whole result; a sum
// whose operands are far apart in magnitude, which rounds to the format's digit
// count; a tie at the last digit, which rounds to even; and a result just past
// what the format carries flat, which takes the large-coefficient form. All three
// widths are here, and the unary minus is a sign flip on the stored word.
const decimal_arith_rows = [
	'_Decimal32 + 1.5df 2.25df 77018031',
	'_Decimal32 - 1.5df 2.25df 4b0080b1',
	'_Decimal32 - 1e7df 1e7df 00000036',
	'_Decimal32 - 0.0df 0.0df 00000032',
	'_Decimal32 + 0.0df 1e-30df 01008023',
	'_Decimal32 + 1e30df 1e-30df 40428f3e',
	'_Decimal32 + 9.999999df 0.000001df 40420f30',
	'_Decimal32 - 8388608.0df 8388607.0df 01008032',
	'_Decimal64 + 1.5dd 2.25dd 7701000000008031',
	'_Decimal64 - 1.5dd 2.25dd 4b000000000080b1',
	'_Decimal64 + 0.0dd 1e-320dd 010000000000c009',
	'_Decimal64 + 1e40dd 1e-40dd 0080c6a47e8de334',
	'_Decimal64 - 1e7dd 1e7dd 000000000000a032',
	'_Decimal64 + 9007199254740993.0dd 0.5dd 020000000000706c',
	'_Decimal64 - 1.0dd 0.0dd 0a0000000000a031',
	'_Decimal128 + 1.5dl 2.25dl 77010000000000000000000000003c30',
	'_Decimal128 - 1.5dl 2.25dl 4b000000000000000000000000003cb0',
	'_Decimal128 + 1e100dl 1.0dl 000000000a5bc138938d44c64d31c630',
	'_Decimal128 + 0.0dl 1e-398dl 0100000000000000000000000000242d',
	'_Decimal128 - 1e7dl 1e7dl 00000000000000000000000000004e30',
	'_Decimal128 + 9.999999999999999999999999999999999e40dl 1e6dl ffffffff638e8d37c087adbe09ed4f30',
]

// The unary minus, one operand and the bytes gcc stores.
const decimal_negate_rows = [
	'_Decimal32 1.5df 0f0000b2',
	'_Decimal64 1.5dd 0f0000000000a0b1',
	'_Decimal128 1.5dl 0f000000000000000000000000003eb0',
]

// decimal_arith_translation_unit reads a program the way the front end does.
fn decimal_arith_translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_arith_run writes the image and runs it, so what is checked is the
// artifact and not the intent behind it.
fn decimal_arith_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_arith_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

// decimal_arith_bytes_program prints a decimal object's stored bytes as hex. The
// two operands are volatile so the operation is one the compiler cannot fold.
fn decimal_arith_bytes_program(typ string, size int, op string, left string, right string) string {
	mut body := '\tvolatile ${typ} a = ${left};\n'
	if op == 'neg' {
		body += '\t${typ} r = -a;\n'
	} else {
		body += '\tvolatile ${typ} b = ${right};\n'
		body += '\t${typ} r = a ${op} b;\n'
	}
	return 'int printf(const char *, ...);\n' +
		'int memcpy(void *, const void *, unsigned long);\n' +
		'int main(void) {\n' + body + '\tunsigned char out[${size}];\n' +
		'\tmemcpy(out, &r, ${size});\n' +
		'\tfor (int i = 0; i < ${size}; i++) printf("%02x", (unsigned) out[i]);\n' +
		'\tprintf("\\n");\n' +
		'\treturn 0;\n' +
		'}\n'
}

// decimal_arith_width is the storage of one of the three decimal types.
fn decimal_arith_width(typ string) int {
	if typ == '_Decimal32' {
		return 4
	}
	if typ == '_Decimal64' {
		return 8
	}
	return 16
}

// The rows are measured from gcc, so the routine the emitter writes has to make
// the same bytes for each: the coefficient, the sign, and the exponent the
// operation's preferred exponent gives the result.
fn test_a_run_time_decimal_sum_and_difference_makes_the_bytes_gcc_makes() {
	for row in decimal_arith_rows {
		parts := row.split(' ')
		typ := parts[0]
		op := parts[1]
		left := parts[2]
		right := parts[3]
		want := parts[4]
		size := decimal_arith_width(typ)
		source := decimal_arith_bytes_program(typ, size, op, left, right)
		emitted := emit(decimal_arith_translation_unit(source), Options{})
		assert tokenize.errors(emitted.diagnostics).len == 0, '${row}: ${emitted.diagnostics[0].msg}'
		result := decimal_arith_run(emitted.bytes)
		assert result.exit_code == 0, '${row}: the program exited ${result.exit_code}'
		got := result.output.trim_space()
		assert got == want, '${row}: the routine made ${got}, gcc made ${want}'
	}
}

// Unary minus is a sign flip on the stored word, at every width.
fn test_a_run_time_decimal_negation_flips_the_sign_bit() {
	for row in decimal_negate_rows {
		parts := row.split(' ')
		typ := parts[0]
		value := parts[1]
		want := parts[2]
		size := decimal_arith_width(typ)
		source := decimal_arith_bytes_program(typ, size, 'neg', value, '')
		emitted := emit(decimal_arith_translation_unit(source), Options{})
		assert tokenize.errors(emitted.diagnostics).len == 0, '${row}: ${emitted.diagnostics[0].msg}'
		result := decimal_arith_run(emitted.bytes)
		assert result.exit_code == 0, '${row}: the program exited ${result.exit_code}'
		got := result.output.trim_space()
		assert got == want, '${row}: the routine made ${got}, gcc made ${want}'
	}
}
