module codegen

import ast
import os
import parser
import time
import tokenize

// A decimal value travels the way gcc 16.2.1 makes it travel: read out of an
// object for its value, handed to a function and given back, and carried inside
// a struct passed and returned by value. The program below moves one each of the
// four object shapes a value can be read from — a variable, an element of an
// array, a member of a struct and a target of a pointer — through calls that
// carry three decimals at once, and prints the bytes of every answer.
//
// The bytes are what gcc 16.2.1 wrote for the same program: every width travels
// in xmm0, a _Decimal128 across the xmm0:xmm1 pair, and a struct containing one
// follows the ordinary aggregate rules. The variadic shape is exercised by the
// corpus cases beside this one, which record the same bytes over a `va_arg`.
const decimal_value_program = 'int printf(const char *, ...);
int memcpy(void *, const void *, unsigned long);
static void hex(const void *p, int n) {
	int i;
	const unsigned char *b = (const unsigned char *) p;
	for (i = 0; i < n; i++) {
		printf("%02x", (unsigned) b[i]);
	}
	printf("\\n");
}
static _Decimal64 three(_Decimal64 a, _Decimal64 b, _Decimal64 c) { return c; }
static _Decimal32 three32(_Decimal32 a, _Decimal32 b, _Decimal32 c) { return c; }
static _Decimal128 three128(_Decimal128 a, _Decimal128 b, _Decimal128 c) { return c; }
struct hold64 { _Decimal64 x; };
static struct hold64 through(struct hold64 s) { return s; }
int main(void) {
	_Decimal64 a = 1.5dd, b = 2.5dd, c = 3.5dd;
	_Decimal64 arr[4];
	struct hold64 s;
	_Decimal64 *p = &c;
	_Decimal64 r;
	arr[2] = 4.5dd;
	s.x = 5.5dd;
	r = a; hex(&r, 8);
	r = arr[2]; hex(&r, 8);
	r = s.x; hex(&r, 8);
	r = *p; hex(&r, 8);
	r = three(a, b, c); hex(&r, 8);
	_Decimal32 r32 = three32(1.5df, 2.5df, 3.5df); hex(&r32, 4);
	_Decimal128 r128 = three128(1.5dl, 2.5dl, 3.5dl); hex(&r128, 16);
	struct hold64 t = through(s); hex(&t.x, 8);
	return 0;
}'

// The lines gcc 16.2.1 prints for the program above: the bytes of a value read
// from a variable, an array element, a struct member and an address, the answers
// of the three-width calls, and the member of a struct that went by value.
const decimal_value_want = '0f0000000000a031
2d0000000000a031
370000000000a031
230000000000a031
230000000000a031
23000032
23000000000000000000000000003e30
370000000000a031'

// decimal_value_unit reads a program the way the front end does.
fn decimal_value_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert tokenize.errors(lexed.diagnostics).len == 0
	parsed := parser.parse(lexed.tokens)
	assert tokenize.errors(parsed.diagnostics).len == 0
	return parsed.unit
}

// decimal_value_run writes the image and runs it, so the test checks the
// artifact and not the intent behind it.
fn decimal_value_run(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_decimal_value_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

fn test_a_decimal_value_travels_the_way_gcc_makes_it_travel() {
	emitted := emit(decimal_value_unit(decimal_value_program), Options{})
	assert tokenize.errors(emitted.diagnostics).len == 0, '${emitted.diagnostics[0].msg}'
	result := decimal_value_run(emitted.bytes)
	assert result.exit_code == 0, 'the program exited ${result.exit_code}'
	got := result.output.trim_space()
	want := decimal_value_want.trim_space()
	assert got == want, 'the bytes travelled as:\n${got}\nand gcc writes:\n${want}'
}

// A decimal argument whose parameter is not of a decimal type, and a decimal
// parameter whose argument is not one, are both refused by name rather than
// passed with the bits of whatever the accumulator held: this back end has no
// conversion from a decimal except to a double, and the wrong bits would be a
// wrong number. The refusal is what the emitter reports.
const decimal_value_mismatch_program = 'int take(_Decimal64 a) { return (int) a; }
int main(void) {
	_Decimal64 d = 1.5dd;
	int n = 1;
	take(n);
	d = n;
	return 0;
}'

fn test_a_decimal_and_a_non_decimal_do_not_mix_silently() {
	emitted := emit(decimal_value_unit(decimal_value_mismatch_program), Options{})
	assert emitted.diagnostics.len > 0, 'the mismatch was accepted silently'
	found := emitted.diagnostics.any(it.msg.contains('unsupported'))
	assert found, 'the refusal is not named: ${emitted.diagnostics[0].msg}'
}

// A decimal is refused by name wherever nothing of one is handled. A truth test
// and an implicit conversion to a double compute with the value, and the bytes in
// the floating accumulator are not a number to compute with: answering with them
// would be a wrong number nobody could see, so each is refused where it is
// written. A sum, a difference, a product, a quotient and a negation are computed
// now, by the routines the emitter writes for them, and negating a decimal is the
// same sign bit that routine flips. A comparison of two decimals is computed too,
// by the comparison routine. The logical-not row stays because the value it makes
// is an int, and a decimal object is not initialised from an int here.
const decimal_value_unhandled_bodies = [
	'_Decimal64 a = 1.5dd; if (a) { return 1; }',
	'_Decimal64 a = 1.5dd; double x = a;',
	'_Decimal64 a = 1.5dd; _Decimal64 b = !a;',
]

fn test_a_decimal_is_refused_where_no_value_of_one_is_handled() {
	for body in decimal_value_unhandled_bodies {
		source := 'int main(void) {\n	${body}\n	return 0;\n}'
		emitted := emit(decimal_value_unit(source), Options{})
		assert emitted.diagnostics.len > 0, 'the program was accepted: ${body}'
		assert emitted.diagnostics.any(it.msg.contains('unsupported')), 'the refusal is not named: ${body}: ${emitted.diagnostics[0].msg}'
	}
}
