module codegen

import ast
import os
import parser
import time
import tokenize

// The bytes a run-time decimal product or quotient comes out as, measured from
// gcc 16.2.1: the format, the two literals, the operator, and the result's bytes
// as hex. Each row's program stores both literals in volatile objects, so the
// operation is one the compiler cannot fold and the routine the emitter writes is
// what runs. The rows cover all three widths, both operators, and the shapes the
// routine has to get right: a coefficient the format cannot keep, a value whose
// exponent sits at the top of the field, an overflow to infinity, and an
// underflow to zero. The wide rows are the ones a frame's layout has to survive:
// a decimal128 coefficient runs to 34 digits, more than a decimal64's 16.
const decimal_muldiv_rows = [
	'_Decimal32 1.5df * -2.5df 770180b1',
	'_Decimal32 0.1df * 0.1df 01008031',
	'_Decimal32 1e96df * 1e96df 00000078',
	'_Decimal32 1e-101df * 1e-7df 00000000',
	'_Decimal32 9999999.0df * 2.0df 80841e33',
	'_Decimal32 1.5df / -2.5df 060000b2',
	'_Decimal32 1e96df / 1e-101df 00000078',
	'_Decimal32 1e-101df / 1e96df 00000000',
	'_Decimal32 1234567.8df / 1e-7df 88d61236',
	'_Decimal32 0.1df / 1000000.0df 0100002f',
	'_Decimal64 123456789012345.6dd * -2.5dd e0d25a1715f7aab1',
	'_Decimal64 9999999999999999.0dd * 1.0dd ffffc06ff286736c',
	'_Decimal64 1e384dd * 1e384dd 0000000000000078',
	'_Decimal64 1e-398dd * 1e-320dd 0000000000000000',
	'_Decimal64 1e384dd / 1.5dd abaa804a4cafd75f',
	'_Decimal64 1e-398dd / 1000000.0dd 0000000000000000',
	'_Decimal64 9007199254740993.0dd / 1.5dd 565555555555d531',
	'_Decimal64 1e384dd / 1e-398dd 0000000000000078',
	'_Decimal128 1e6144dl * 1.0dl 000000000a5bc138938d44c64d31fe5f',
	'_Decimal128 1e6144dl * 1e6144dl 00000000000000000000000000000078',
	'_Decimal128 123456789012345678901234567890.1dl * 1.0dl 123aa09016dd4359643c0ad39b003c30',
	'_Decimal128 1e6144dl * 1e-6176dl 000000000a5bc138938d44c64d31be2f',
	'_Decimal128 1e6144dl / 1.0dl 000000000a5bc138938d44c64d31fe5f',
	'_Decimal128 1e6144dl / 1e6144dl 01000000000000000000000000004030',
	'_Decimal128 123456789012345678901234567890.1dl / 1.0dl 356c760e4fc986a2a39f1a950f003e30',
	'_Decimal128 123456789012345678901234567890.1dl / 1e6144dl 356c760e4fc986a2a39f1a950f003e00',
	'_Decimal128 1e6144dl / 0.1dl 00000000000000000000000000000078',
	'_Decimal128 1e6144dl / 1e30dl 000000000a5bc138938d44c64d31c25f',
]

// decimal_muldiv_width is the width in bytes of a decimal type's name, which is
// also the number of bytes a result is copied out with.
fn decimal_muldiv_width(typ string) int {
	return match typ {
		'_Decimal32' { 4 }
		'_Decimal64' { 8 }
		else { 16 }
	}
}

// decimal_muldiv_program is a C program that stores one product or quotient in a
// volatile pair of objects and prints the result's bytes as hex. Both operands
// are volatile so the operation cannot be folded, and neither literal is a
// constant the reader would rather compute.
fn decimal_muldiv_program(typ string, op string, left string, right string) string {
	width := decimal_muldiv_width(typ)
	return 'int printf(const char *, ...);\n' +
		'int memcpy(void *, const void *, unsigned long);\n' +
		'static void hex(const void *p, int n) {\n' +
		'\tint i;\n' +
		'\tconst unsigned char *b = (const unsigned char *) p;\n' +
		'\tfor (i = 0; i < n; i++) {\n' +
		'\t\tprintf("%02x", (unsigned) b[i]);\n' +
		'\t}\n' +
		'\tprintf("\\n");\n' +
		'}\n' +
		'int main(void) {\n' +
		'\tvolatile ${typ} a = ${left};\n' +
		'\tvolatile ${typ} b = ${right};\n' +
		'\t${typ} r = a ${op} b;\n' +
		'\tunsigned char out[${width}];\n' +
		'\tmemcpy(out, &r, ${width});\n' +
		'\thex(out, ${width});\n' +
		'\treturn 0;\n' +
		'}\n'
}

// decimal_muldiv_translation_unit reads a program the way the front end does.
// The helpers are this file's own: `v test` builds each _test.v as a program of
// its own, so a helper next to the codegen module's other test file is not in
// scope here.
fn decimal_muldiv_translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_muldiv_run writes the image and runs it, so the test checks the
// artifact and not the intent behind it.
fn decimal_muldiv_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_muldiv_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

// A product or a quotient a program computes at run time has to be the bytes
// gcc's own __bid_ routines make, for every width and both operators. The
// operands are objects rather than constants, so what is tested is the routine
// the emitter writes, and the bytes are the whole answer: a result that carries
// the right value with the wrong coefficient or exponent fails here.
fn test_a_run_time_muldiv_makes_the_bytes_gcc_makes() {
	for row in decimal_muldiv_rows {
		parts := row.split(' ')
		typ := parts[0]
		left := parts[1]
		op := parts[2]
		right := parts[3]
		want := parts[4]
		emitted := emit(decimal_muldiv_translation_unit(decimal_muldiv_program(typ, op, left, right)), Options{})
		assert tokenize.errors(emitted.diagnostics).len == 0, '${row}: ${emitted.diagnostics[0].msg}'
		result := decimal_muldiv_run(emitted.bytes)
		assert result.exit_code == 0, '${row}: the program exited ${result.exit_code}'
		got := result.output.trim_space()
		assert got == want, '${row}: the routine made ${got}, gcc made ${want}'
	}
}

// A product or a quotient of one decimal format into an object of another is a
// conversion this back end does not have, and the routine writes the width of
// the format it was built for, so a narrower object would take bytes it does not
// have. It has to be refused by name, the way the same value written as a
// constant is, and not written past the end of the object. decimal_step answers
// the step .object whatever the destination's width, so the store's own width
// check is the refusal that fires here.
fn test_a_muldiv_of_another_width_is_refused_by_name() {
	source := 'int main(void) {\n' +
		'	volatile _Decimal128 a = 1.5dl;\n' +
		'	volatile _Decimal128 b = 2.0dl;\n' +
		'	_Decimal64 c = a * b;\n' +
		'	return 0;\n' +
		'}\n'
	emitted := emit(decimal_muldiv_translation_unit(source), Options{})
	mut refused := false
	for diagnostic in emitted.diagnostics {
		if diagnostic.msg.contains('different decimal width') {
			refused = true
		}
	}
	assert refused, 'a _Decimal128 product into a _Decimal64 was not refused by name'
}
