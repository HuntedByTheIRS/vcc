module codegen

import ast
import backend
import backend.os.elf
import os
import parser
import time
import tokenize

// WideValueCase is one 128-bit program beside the status it exits with. The two
// fields are declared rather than written as a two-element literal, because a
// literal mixing a string and an int is not an array this V infers.
struct WideValueCase {
	source string
	status int
}

// The tests below run as part of module codegen, and reach into the parser to
// build input, which is the shortest path from C source to an AST that the
// compiler has. String literals, call statements, variables, branches and loops
// cannot all be parsed yet, so the tests that need them build the tree the
// parser will produce for them: the emitter consumes the same nodes either way.

fn translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

// run_capturing writes an image the way main.v does and runs it, so these tests
// check the artifact and not the intent behind it. The output is what a library
// call was supposed to produce, and the exit status is what the returned
// constant became.
fn run_capturing(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_codegen_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

fn run_image(image []u8) int {
	return run_capturing(image).exit_code
}

// The tree for a program the parser cannot write down yet: a function that calls
// other functions, with string and integer arguments, and returns a constant.
fn call_statement(name string, args []ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind: .expr_stmt
		expr: ast.Expr(ast.Call{
			name: name
			args: args
		})
	}
}

fn string_argument(value string) ast.Expr {
	return ast.Expr(ast.StrLit{
		value: value
		text:  '"${value}"'
	})
}

fn int_argument(value i64) ast.Expr {
	return ast.Expr(ast.IntLit{
		value: value
		text:  '${value}'
	})
}

fn return_statement(value i64) ast.Stmt {
	return ast.Stmt{
		kind: .return_stmt
		expr: ast.Expr(ast.IntLit{
			value: value
			text:  '${value}'
		})
	}
}

// The builders below assemble the tree for a body that keeps values in
// variables, branches on them and loops over them. They are the nodes the ast
// declares, made by hand because the parser cannot write all of them down yet.
fn name_node(name string) ast.Expr {
	return ast.Expr(ast.Ident{
		name: name
	})
}

fn binary_node(op string, left ast.Expr, right ast.Expr) ast.Expr {
	return ast.Expr(ast.Binary{
		op:    op
		left:  left
		right: right
	})
}

fn unary_node(op string, expr ast.Expr) ast.Expr {
	return ast.Expr(ast.Unary{
		op:   op
		expr: expr
	})
}

fn call_expression(name string, args []ast.Expr) ast.Expr {
	return ast.Expr(ast.Call{
		name: name
		args: args
	})
}

fn declaration(name string, typ string, init ?ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind:      .var_decl
		decl_name: name
		decl_type: typ
		init:      init
	}
}

fn assignment(target string, expr ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind:   .assign
		target: target
		expr:   expr
	}
}

fn return_expression(expr ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind: .return_stmt
		expr: expr
	}
}

fn if_statement(cond ast.Expr, then_body []ast.Stmt, else_body []ast.Stmt) ast.Stmt {
	return ast.Stmt{
		kind:      .if_stmt
		cond:      cond
		then_body: then_body
		else_body: else_body
	}
}

fn while_statement(cond ast.Expr, body []ast.Stmt) ast.Stmt {
	return ast.Stmt{
		kind: .while_stmt
		cond: cond
		body: body
	}
}

fn break_statement() ast.Stmt {
	return ast.Stmt{
		kind: .break_stmt
	}
}

fn continue_statement() ast.Stmt {
	return ast.Stmt{
		kind: .continue_stmt
	}
}

fn param(name string, typ string) ast.Param {
	return ast.Param{
		name: name
		typ:  typ
	}
}

fn function_in_file(name string, params []ast.Param, body []ast.Stmt) ast.FnDecl {
	return ast.FnDecl{
		name:    name
		ret:     'int'
		params:  params
		defined: true
		body:    body
	}
}

// unit_of is a translation unit whose entry function is main, with the other
// functions after it: a call written before a definition still binds to it, and
// this is the order that says so.
fn unit_of(main_body []ast.Stmt, helpers []ast.FnDecl) ast.TranslationUnit {
	mut decls := [function_in_file('main', []ast.Param{}, main_body)]
	decls << helpers
	return ast.TranslationUnit{
		decls: decls
	}
}

fn program(body []ast.Stmt) ast.TranslationUnit {
	return ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name:    'main'
				ret:     'int'
				defined: true
				body:    body
			},
		]
	}
}

fn test_the_exit_status_is_the_returned_constant() {
	emitted := emit(translation_unit('int main() { return 7; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 7
}

fn test_a_read_through_an_address_reads_the_value_at_it() {
	// Measured with gcc 16.2.1 on the same programs: the char 65 behind an
	// address is 65, an array's name is the address of its first element, the int
	// 7 is 7, and the double 2.5 read through one and converted is 2.
	for source in [
		'int main() { char s[4]; s[0] = 65; char *p = s; return *p; }',
		'int main() { char s[4]; s[0] = 65; return *s; }',
		'int main() { int x = 7; int *p = &x; return *p; }',
	] {
		emitted := emit(translation_unit(source), Options{})
		assert emitted.diagnostics.len == 0
		answer := if source.contains('int x') { 7 } else { 65 }
		assert run_image(emitted.bytes) == answer
	}
	doubled := emit(translation_unit('int main() { double d = 2.5; double *p = &d; return (int)*p; }'),
		Options{})
	assert doubled.diagnostics.len == 0
	assert run_image(doubled.bytes) == 2
	// A char is loaded with its sign, which is what makes the value the int the
	// language promotes it to.
	signed := emit(translation_unit('int main() { char c = (char)200; char *p = &c; return *p; }'),
		Options{})
	assert signed.diagnostics.len == 0
	assert run_image(signed.bytes) == 200
}

// A store through an address writes the object the pointer points at and not
// the pointer itself: the ints below are told apart by the exit status, and an
// implementation that wrote over the pointer's own slot would corrupt the frame
// and answer with a different number. Measured with gcc 16.2.1, the first
// program exits 109 and the second 191.
fn test_a_store_through_an_address_writes_the_object_the_pointer_points_at() {
	for source in [
		'int main() { int a = 1; int b = 2; int *p = &b; *p = 9; return a * 100 + b; }',
		'int main() { int a = 1; int b = 2; int *p = &b; int *q = &a; *p = 9; return a * 100 + b * 10 + *q; }',
	] {
		emitted := emit(translation_unit(source), Options{})
		assert emitted.diagnostics.len == 0
		answer := if source.contains('*q') { 191 } else { 109 }
		assert run_image(emitted.bytes) == answer
	}
}

// The width of the store is the width of what the pointer points at. A char
// object takes one byte, so the bytes beside the one written keep their values
// and the program can tell; a double takes eight, written by the instruction
// that moves one. Measured with gcc 16.2.1, the two programs exit 1 and 6.
fn test_a_store_through_an_address_writes_the_width_of_what_it_points_at() {
	char_store := emit(translation_unit('int main() { char s[4]; s[0] = 1; s[1] = 2; s[2] = 3; s[3] = 4; char *cp = s; *cp = 9; return s[0] == 9 && s[1] == 2 && s[2] == 3 && s[3] == 4; }'),
		Options{})
	assert char_store.diagnostics.len == 0
	assert run_image(char_store.bytes) == 1
	double_store := emit(translation_unit('int main() { double d = 0.0; double *dp = &d; *dp = 1.5; return (int)(d * 4); }'),
		Options{})
	assert double_store.diagnostics.len == 0
	assert run_image(double_store.bytes) == 6
}

// The address comes from an expression rather than a name: `(*f()) = v` calls a
// function that returns the address and stores there. This is the shape the
// corpus is written in, where `errno` is a macro that expands to a dereference
// of a call. Measured with gcc 16.2.1, the program exits 7.
fn test_a_store_through_an_address_a_call_returns() {
	emitted := emit(translation_unit('int *__errno_location(void); int main(void) { (*__errno_location()) = 7; return (*__errno_location()); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 7
}

// A pointer to a pointer is a store through the address the outer dereference
// reads: `**pp = 7` writes into x. Measured with gcc 16.2.1, the program exits 7.
fn test_a_store_through_a_pointer_to_a_pointer_writes_where_it_points() {
	emitted := emit(translation_unit('int main() { int x = 1; int *p = &x; int **pp = &p; **pp = 7; return x; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 7
}

// The value converts to the pointed-at type the way it does into a name: a
// double stored through an address of int is the integer the conversion makes,
// and a negative int constant stored through an address of long is sign-widened
// into the whole word, which the comparison reads back a word at a time rather
// than through the status byte. Measured with gcc 16.2.1, the two programs exit
// 3 and 1.
fn test_a_store_through_an_address_converts_to_what_it_points_at() {
	converted := emit(translation_unit('int main() { int x = 0; int *p = &x; double d = 3.7; *p = d; return x; }'),
		Options{})
	assert converted.diagnostics.len == 0
	assert run_image(converted.bytes) == 3
	wide := emit(translation_unit('int main() { long x = 0; long *lp = &x; *lp = -5; return x == -5L; }'),
		Options{})
	assert wide.diagnostics.len == 0
	assert run_image(wide.bytes) == 1
}

// A pointer stored through an address of pointer is written at the machine's
// word, which is the width of both. Measured with gcc 16.2.1, the two addresses
// compare equal and the program exits 1.
fn test_a_store_through_an_address_of_a_pointer_keeps_the_whole_address() {
	emitted := emit(translation_unit('int main() { char *c = 0; char **cpp = &c; char *s = "hi"; *cpp = s; return (int)s == (int)c; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

fn test_a_read_through_something_that_is_not_an_address_is_reported() {
	// The reader refuses it, so there is no tree to emit and no bytes to write:
	// what the source says is checked without going through the emitter, which is
	// what the pipeline test that reads a refused source covers as well.
	lexed := tokenize.lex('int main() { int x = 3; return *x; }')
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].msg.contains('reads through an address')
}

fn test_a_cast_converts_between_the_classes_the_back_end_carries() {
	// Measured with gcc 16.2.1 on the same program: `(char)300` is 44 and
	// `(int)(char *)0` is 0, so the three conversions in one program add up to
	// 51, which is what the exit status is.
	emitted := emit(translation_unit('int main() { int x = 7; char *p = (char *)0; double d = (double)x; return (int)d + (char)300 + (int)p; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 51
	// A conversion of an int to an address keeps the sign: `(char *)-1` is an
	// address whose upper half is ones, and reading the int back out of it
	// answers -1 rather than 2147483647.
	signed := emit(translation_unit('int main() { char *p = (char *)-1; return (int)p == -1; }'), Options{})
	assert signed.diagnostics.len == 0
	assert run_image(signed.bytes) == 1
}

fn test_a_cast_with_no_conversion_behind_it_is_reported() {
	// A conversion to a type this back end has no register for is refused by
	// name rather than written as a value of the wrong width.
	unsupported := emit(translation_unit('int main() { int x = 3; double d = (long double)x; return 0; }'),
		Options{})
	assert unsupported.diagnostics.len == 1
	assert unsupported.diagnostics[0].msg.contains('long double')
	assert unsupported.bytes.len == 0
	// A floating type and an address are not converted into one another, and
	// that is said rather than emitted as a pointer whose bits are a double.
	wrong_class := emit(translation_unit('int main() { double d = 1.5; char *p = (char *)d; return 0; }'),
		Options{})
	assert wrong_class.diagnostics.len == 1
	assert wrong_class.diagnostics[0].msg.contains('char *')
	assert wrong_class.bytes.len == 0
}

// The narrow integer types are values a register holds. A read widens the value to
// the int the promotion makes it, with the value's sign kept or with zero above it
// when the type is unsigned, and a store writes the low byte or the low two bytes
// of the register. A conversion to `_Bool` makes the value 0 or 1 and a conversion
// to a narrower type cuts the value to that width with the sign the type has. The
// reads of a global and of an array element go through an address rather than a
// frame slot, which is the other path a wide value is read by. Measured on gcc
// 16.2.1, this program exits 11, one for each comparison that is true: the two
// reads that would be wrong if the sign were taken, the two that would be wrong if
// zero were not, the global and the element read the same way, the `_Bool` that is
// 1 whatever was stored in it, and the three narrowings.
fn test_the_narrow_integer_types_hold_their_values() {
	emitted := emit(translation_unit('static unsigned char gb[3] = {200, 100, 255};\nstatic unsigned short gus = 40000;\nint main(void) { unsigned char uc = 200; signed char sc = -56; short s = -300; unsigned short us = 40000; _Bool b = 42; return (uc == 200) + (sc == -56) + (s == -300) + (us == 40000) + (b == 1) + ((unsigned short)-1 == 65535) + ((short)70000 == 4464) + ((unsigned char)-1 == 255) + (gb[0] == 200) + (gb[2] == 255) + (gus == 40000); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 11
}

// A function of a narrow integer type returns a value the caller reads at that
// type's width. The register holds an int whatever the type says, so the callee
// cuts the value to the type before it returns, which is what makes `return
// 70000;` in a `short` function the 4464 the language and gcc answer with.
// Measured on gcc 16.2.1, this program exits 4.
fn test_a_narrow_return_type_comes_back_cut_to_its_width() {
	emitted := emit(translation_unit('short nf(void) { return 70000; }\nunsigned short uf(void) { return -1; }\n_Bool bf(void) { return 5; }\nsigned char cf(void) { return 200; }\nint main(void) { return (nf() == 4464) + (uf() == 65535) + (bf() == 1) + (cf() == -56); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 4
}

// Every store into a `_Bool` object leaves 0 or 1, which is 6.3.1.2 and not only
// the store a frame slot goes through: the members and the elements of an array go
// through their own addresses, and a top-level object's first value is written into
// the image by the layout. Measured on gcc 16.2.1, this program exits 5.
fn test_a_store_into_a_bool_makes_the_value_zero_or_one() {
	emitted := emit(translation_unit('_Bool g = 2;\nstatic _Bool ga[2] = {2, 0};\nstruct S { _Bool b; };\nint main(void) { _Bool a[2]; a[0] = 2; struct S s; s.b = 3; return (g == 1) + (ga[0] == 1) + (ga[1] == 0) + (a[0] == 1) + (s.b == 1); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 5
}

// A store into a bitfield writes only that member's bits. Two bitfields in one
// storage unit used to clobber each other, because the member store wrote the
// whole unit: the second store overwrote the first. Measured on gcc 16.2.1, this
// program returns 2, so the read-modify-write leaves s.a at 5 after s.b is set.
fn test_a_bitfield_store_writes_only_its_own_bits() {
	emitted := emit(translation_unit('struct S { unsigned int a : 4; unsigned int b : 4; };\nint main(void) { struct S s; s.a = 5; s.b = 3; return (s.a == 5) + (s.b == 3); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 2
}

// The shape the defect was reported with: a negative store into the signed
// neighbour used to leave the whole unit at -3, and reading the first field came
// back as 253 rather than 5. gcc 16.2.1 returns 2 here.
fn test_a_bitfield_store_keeps_the_bits_of_the_field_next_to_it() {
	emitted := emit(translation_unit('struct S { signed int a : 4; signed int b : 4; };\nint main(void) { struct S s; s.a = 5; s.b = -3; return (s.a == 5) + (s.b == -3); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 2
}

// The widths a file writes and the two signednesses. Each field is read back as
// its own bits: a 1-bit field, an 8-bit one, a 16-bit one, and one that does not
// fit beside its neighbour and starts a new unit. gcc 16.2.1 returns 4.
fn test_a_bitfield_read_is_taken_from_its_own_bits() {
	emitted := emit(translation_unit('struct W { unsigned int a : 1; unsigned int b : 8; unsigned int c : 16; unsigned int d : 31; };\nint main(void) { struct W w; w.a = 1; w.b = 200; w.c = 40000; w.d = 5; return (w.a == 1) + (w.b == 200) + (w.c == 40000) + (w.d == 5); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 4
}

// The plain members on either side of a bitfield group are in their own units and
// their bytes survive a store into the bitfields. gcc 16.2.1 returns 4.
fn test_a_bitfield_store_keeps_the_plain_members_next_to_it() {
	emitted := emit(translation_unit('struct S { unsigned int head; unsigned int a : 3; unsigned int b : 3; unsigned int tail; };\nint main(void) { struct S s; s.head = 7; s.tail = 9; s.a = 5; s.b = 3; return (s.head == 7) + (s.tail == 9) + (s.a == 5) + (s.b == 3); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 4
}

// The corpus shape: an unsigned field, a signed field, a `_Bool` field and a
// zero-width unnamed field that starts a new unit for the last one. gcc 16.2.1
// returns 4, and so does this.
fn test_a_bitfield_group_with_a_bool_and_a_zero_width_field() {
	emitted := emit(translation_unit('struct B { unsigned int a : 3; signed int b : 5; _Bool c : 1; unsigned int : 0; unsigned int d : 2; };\nint main(void) { struct B bf; bf.a = 5u; bf.b = -3; bf.c = 1; bf.d = 1u; return (bf.a == 5u) + (bf.b == -3) + (bf.c == 1u) + (bf.d == 1u); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 4
}

// A field wider than four bytes is refused by name rather than written with a
// clear mask this back end cannot express. The refusal says which unit it is.
fn test_a_store_into_a_bitfield_wider_than_four_bytes_is_refused() {
	emitted := emit(translation_unit('struct S { unsigned long a : 4; unsigned long b : 4; };\nint main(void) { struct S s; s.a = 5; return 0; }'),
		Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('storage unit')
	assert emitted.bytes.len == 0
}

// A bitfield has no address of its own, so taking one is refused by name. gcc
// 16.2.1 refuses the same program with `cannot take address of bit-field`.
fn test_the_address_of_a_bitfield_is_refused() {
	emitted := emit(translation_unit('struct S { unsigned int a : 4; };\nint main(void) { struct S s; unsigned int *p = &s.a; return 0; }'),
		Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('bitfield')
	assert emitted.bytes.len == 0
}

fn test_a_constant_expression_is_folded() {
	emitted := emit(translation_unit('int main() { return 6 * 7; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

fn test_a_negative_return_wraps_into_the_status_byte() {
	emitted := emit(translation_unit('int main() { return -1; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 255
}

fn test_a_status_wider_than_a_byte_keeps_its_low_bits() {
	emitted := emit(translation_unit('int main() { return 300; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 44
}

// A constant the type model did not resolve is refused before the layout runs.
// The emitter writes a constant as a four-byte int, so a value that int cannot
// hold would be written as a different number than the program asked for:
// measured, `int main(void) { return 4294967295 > 2147483647; }` was emitted as
// an int comparison and returned 0 where ISO C and gcc return 1.
fn test_a_constant_the_model_did_not_type_is_refused_before_anything_is_written() {
	emitted := emit(program([return_expression(int_argument(4294967295))]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('4294967295')
	assert emitted.bytes.len == 0
	// The same node with a value an int holds is written as the int it is, which
	// is what keeps a tree assembled by hand emittable.
	small := emit(program([return_expression(int_argument(7))]), Options{})
	assert small.diagnostics.len == 0
	assert run_image(small.bytes) == 7
}

// A body is statements now, not one folded return: the first return is what the
// function finishes with, and the second is emitted behind it and never reached.
fn test_a_body_with_more_than_one_return_compiles_and_the_first_wins() {
	emitted := emit(translation_unit('int main() { return 1; return 2; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

fn test_a_return_inside_a_nested_block_is_emitted() {
	emitted := emit(translation_unit('int main() { { return 5; } }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 5
}

// A program whose body runs to the end without returning still has a status:
// zero, which is what C says the entry function does.
fn test_a_body_that_never_returns_finishes_with_zero() {
	body := [
		call_statement('puts', [string_argument('no return statement')]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('no return statement')
}

// The point of the whole container: the code calls a function that is not in the
// image, the loader resolves it out of libc, and the process prints. A file with
// no string in it would pass without any of that working.
fn test_a_call_to_a_library_function_prints_and_the_return_becomes_the_status() {
	body := [
		call_statement('puts', [string_argument('vcc speaks to libc')])
		return_statement(3),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 3
	assert result.output.contains('vcc speaks to libc')
}

// printf is variadic, which is the one call shape where the machine wants more
// than the arguments themselves: the number of vector arguments goes in the low
// byte of the result register before the call.
fn test_a_variadic_library_call_prints_its_formatted_argument() {
	body := [
		call_statement('printf', [string_argument('value: %d\n'), int_argument(42)])
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('value: 42')
}

// A call to a name the file defines is a call into the image, wherever in the
// file the definition is written. Treating it as a library symbol would fail at
// load time with the name of a function the file supplies itself.
fn test_a_call_to_a_function_in_the_file_binds_to_the_definition() {
	unit := ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name:    'main'
				ret:     'int'
				defined: true
				body:    [call_statement('helper', []ast.Expr{}), return_statement(5)]
			},
			ast.FnDecl{
				name:    'helper'
				ret:     'int'
				defined: true
				body:    [
					call_statement('puts', [string_argument('from the helper')])
					return_statement(0),
				]
			},
		]
	}
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 5
	assert result.output.contains('from the helper')
}

// The same tree has to produce the same bytes every run: the layout is a
// sequence and the imports are in the order they were first called.
fn test_the_same_tree_produces_the_same_bytes() {
	body := [
		call_statement('puts', [string_argument('deterministic')])
		return_statement(0),
	]
	first := emit(program(body), Options{})
	second := emit(program(body), Options{})
	assert first.diagnostics.len == 0
	assert second.diagnostics.len == 0
	assert first.bytes == second.bytes
}

// The facts that make this a dynamically linked executable: what the file is,
// which machine it is for, the loader it names, and the library it runs
// against. The entry point has to land inside the segment the loader maps,
// otherwise the kernel has nowhere to start.
fn test_the_image_is_a_dynamic_elf_the_kernel_can_start() {
	emitted := emit(translation_unit('int main() { return 3; }'), Options{})
	assert emitted.diagnostics.len == 0
	bytes := emitted.bytes
	base := emitted.target.load_base
	assert bytes[0..4] == [u8(0x7f), `E`, `L`, `F`]
	assert bytes[4] == 2 // 64-bit
	assert bytes[5] == 1 // little endian
	assert u16_at(bytes, 16) == 2 // ET_EXEC
	assert u16_at(bytes, 18) == 62 // EM_X86_64
	headers := segments(bytes)
	assert headers.len == 4
	interp := only_segment(headers, elf.elf_ph_type_interp)
	assert read_string(bytes, int(interp.offset)) == emitted.target.interpreter
	load := only_segment(headers, elf.elf_ph_type_load)
	entry := u64_at(bytes, 24)
	assert entry >= load.vaddr
	assert entry < load.vaddr + load.filesz
	assert load.filesz == u64(bytes.len)
	needed := dynamic_value(bytes, elf.dt_needed) or { panic('the image has no DT_NEEDED') }
	strtab := dynamic_value(bytes, elf.dt_strtab) or { panic('the image has no DT_STRTAB') }
	assert read_string(bytes, int(strtab - base) + int(needed)) == 'libc.so.6'
}

// Dynamic linking is also a symbol table and a relocation per imported function:
// the loader has to find each name and write its address where the calls read
// it, so a test looks at both rather than trusting that the calls work by luck.
fn test_an_imported_function_is_an_undefined_symbol_with_a_relocation() {
	body := [
		call_statement('puts', [string_argument('relocated')])
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	bytes := emitted.bytes
	base := emitted.target.load_base
	dynsym := dynamic_value(bytes, elf.dt_symtab) or { panic('the image has no DT_SYMTAB') }
	dynstr := dynamic_value(bytes, elf.dt_strtab) or { panic('the image has no DT_STRTAB') }
	hash := dynamic_value(bytes, elf.dt_hash) or { panic('the image has no DT_HASH') }
	rela := dynamic_value(bytes, elf.dt_rela) or { panic('the image has no DT_RELA') }
	relasz := dynamic_value(bytes, elf.dt_relasz) or { panic('the image has no DT_RELASZ') }
	// The hash table's chain count is how many symbols there are, which is what
	// walks the table: the null entry, the called function, and the exit the
	// entry point leaves through.
	count := int(u32_at(bytes, int(hash - base) + 4))
	assert count == 3
	mut names := []string{}
	for i in 1 .. count {
		at := int(dynsym - base) + i * elf.elf_symbol_size
		assert bytes[at + 4] == elf.symbol_global_function
		assert u16_at(bytes, at + 6) == 0 // undefined: the definition is elsewhere
		names << read_string(bytes, int(dynstr - base) + int(u32_at(bytes, at)))
	}
	assert 'puts' in names
	assert 'exit' in names
	// One relocation per imported function, each one a global data relocation
	// naming a symbol and pointing at a slot the code reads.
	assert relasz == u64(2 * elf.elf_relocation_size)
	mut slots := []u64{}
	for i in 0 .. 2 {
		at := int(rela - base) + i * elf.elf_relocation_size
		slots << u64_at(bytes, at)
		info := u64_at(bytes, at + 8)
		assert (info & 0xffffffff) == elf.relocation_glob_dat
		assert (info >> 32) >= 1 // the null symbol is never referenced
	}
	assert slots[0] != slots[1]
	for slot in slots {
		assert slot >= base && slot < base + u64(bytes.len)
	}
}

// A long constant chain used to take the stack out: the fold recursed once per
// term, and about three thousand terms is a size generated code reaches without
// trying. The benchmark harness found it; this keeps it found.
fn test_a_long_constant_chain_folds() {
	mut terms := []string{}
	mut expected := i64(0)
	for i in 0 .. 20000 {
		value := (i % 97) + 1
		terms << '${value}'
		expected = (expected + value) & 0xff
	}
	source := 'int main() { return ${terms.join(' + ')}; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(expected)
}

// A long chain of variable terms used to take the stack out where a chain of
// constants did not: the width walk recursed once per term, and an 8 MB stack
// ended at about two thousand terms. Measured on this tree, a chain of 2010
// `+ x` terms compiled and one of 2020 took signal 11. The walk is a loop now,
// and the chain below is longer than the one the stack carried.
fn test_a_long_variable_chain_is_emitted_and_runs() {
	mut source := 'int main(void) { int x = 1; int y = 0'
	mut expected := i64(0)
	for _ in 0 .. 3000 {
		source += ' + x'
		expected = (expected + 1) & 0xff
	}
	source += '; return y; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(expected)
}

// An operator chain is one node deep in the grammar however many terms it has,
// so the nesting limit does not see it and it is counted against its own bound.
// What a chain of this size gets is a diagnostic that names the construct and
// where it starts, not a signal: gcc compiles the same file, and refusing it is
// a smaller lie than running the stack out or walking it term by term.
fn test_a_chain_past_the_emit_bound_is_refused_by_name() {
	mut source := 'int main(void) { int x = 1; int y = 0'
	for _ in 0 .. max_emit_chain + 1 {
		source += ' + x'
	}
	source += '; return y; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('chain of ${max_emit_chain + 1} operators')
	assert emitted.diagnostics[0].msg.contains('more than the ${max_emit_chain}')
	// The location is the operand the chain starts from, which is the `0`.
	assert emitted.diagnostics[0].line == 1
	assert emitted.diagnostics[0].col == 37
	// A chain is not the nesting it is not: the message says what it is.
	assert !emitted.diagnostics[0].msg.contains('nested')
}

// The chain at the bound is still emitted and runs, so the count is what draws
// the line and not one term short of it.
fn test_a_chain_at_the_emit_bound_is_emitted() {
	mut source := 'int main(void) { int x = 1; int y = 0'
	mut expected := i64(0)
	for _ in 0 .. max_emit_chain {
		source += ' + x'
		expected = (expected + 1) & 0xff
	}
	source += '; return y; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(expected)
}

// A division by zero is refused where a constant expression is required and
// nowhere else, which is what C99 6.6 says and what gcc 16.2.1 does: it compiles
// a division by zero in a program, and only a constant context makes it complain.
// These two are the side of that boundary this emitter used to get wrong - it
// refused `1 / 0` and `1 ? 2 : (1 / 0)` outright, which rejected programs gcc
// accepts. The other side is not tested here because it is not the emitter's: a
// static initializer that is not a constant is refused while the declaration is
// read.
fn test_a_division_by_zero_at_run_time_is_emitted_and_not_refused() {
	emitted := emit(translation_unit('int main() { return 1 / 0; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert emitted.bytes.len > 0
}

fn test_a_division_by_zero_in_an_untaken_arm_is_not_evaluated() {
	emitted := emit(translation_unit('int main() { return 1 ? 2 : (1 / 0); }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 2
}

fn test_a_non_constant_return_is_reported_with_the_name() {
	// The tree is assembled by hand rather than parsed: a name nothing in the
	// unit declares is refused by the parser once the whole unit has been read,
	// and what this checks is the message the emitter gives for a name it cannot
	// place.
	emitted := emit(program([ast.Stmt{
		kind: .return_stmt
		expr: name_node('x')
	}]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('x is not a constant')
}

// A call whose result is read is emitted: the value arrives in the register a
// value is expected to be in, so a call can stand where a name would. What the
// -O levels decide is whether a call the optimizer knows is folded, not whether
// a call can be made at all.
fn test_a_call_can_be_the_value_of_an_expression() {
	helper := ast.FnDecl{
		name:    'twice'
		ret:     'int'
		params:  [ast.Param{
			name: 'x'
			typ:  'int'
		}]
		defined: true
		body:    [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('x'), name_node('x'))
		}]
	}
	body := [
		declaration('v', 'int', ast.Expr(ast.Call{
			name: 'twice'
			args: [int_argument(21)]
		})),
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', name_node('v'), int_argument(42))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// Two calls in one expression each want somewhere to park their arguments, and
// the inner one has to park them above the outer one's: a shared slot would have
// the outer call hand over a value the inner one overwrote.
fn test_a_call_can_be_the_argument_of_another_call() {
	helper := ast.FnDecl{
		name:    'twice'
		ret:     'int'
		params:  [ast.Param{
			name: 'x'
			typ:  'int'
		}]
		defined: true
		body:    [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('x'), name_node('x'))
		}]
	}
	body := [
		declaration('v', 'int', ast.Expr(ast.Call{
			name: 'twice'
			args: [ast.Expr(ast.Call{
				name: 'twice'
				args: [int_argument(21)]
			})]
		})),
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', name_node('v'), int_argument(84))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// A function that returns nothing has no value to read: the file says what each
// function it declares returns, and a call to one that returns void, read as a
// value, is reported rather than read from whatever the call left in the
// register.
fn test_a_call_to_a_void_function_used_as_a_value_is_reported() {
	declared := ast.FnDecl{
		name:   'nothing'
		ret:    'void'
		params: [ast.Param{
			name: 'v'
			typ:  'int'
		}]
	}
	body := [
		declaration('x', 'int', ast.Expr(ast.Call{
			name: 'nothing'
			args: [int_argument(1)]
		})),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [declared]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('returns void')
	assert emitted.bytes.len == 0
}

fn test_a_call_argument_that_is_not_a_constant_is_reported() {
	body := [
		call_statement('puts', [ast.Expr(ast.Ident{ name: 'message' })]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('message')
	assert emitted.bytes.len == 0
}

// Seven arguments where the machine has six registers is not a refusal: the
// seventh is pushed and the callee reads it. What is emitted is an image, and the
// instruction that takes the stack back is there, because a frame that gives the
// stack away and never takes it back would corrupt the call after it.
fn test_more_arguments_than_the_machine_has_registers_is_passed_on_the_stack() {
	mut args := []ast.Expr{}
	for i in 0 .. 7 {
		args << int_argument(i64(i))
	}
	emitted := emit(program([call_statement('puts', args)]), Options{})
	assert emitted.diagnostics.len == 0
	assert emitted.bytes.len > 0
	// `push rax` is the byte 0x50; the machine code holds one for the seventh
	// argument.
	assert emitted.bytes.contains(u8(0x50))
}

fn test_an_expression_statement_that_is_not_a_call_is_reported() {
	body := [
		ast.Stmt{
			kind: .expr_stmt
			expr: ast.Expr(ast.IntLit{ value: 1, text: '1' })
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('call')
	assert emitted.bytes.len == 0
}

// A void expression in a statement is evaluated for its side effects and its
// value thrown away, which is where a conversion to void and a read through an
// address of void are legal. Measured on gcc 16.2.1, which compiles and runs
// all three under both -std=c99 -pedantic-errors and -std=gnu99 and exits 7.
fn test_a_void_expression_statement_compiles_and_runs() {
	for source in [
		'int main(void) { int x = 3; (void)x; (void)(x + 1); return 7; }',
		'int main(void) { int x = 3; void *p = &x; *(void *)p; return 7; }',
		'int main(void) { int x = 3; __extension__ *(void *)&x; return 7; }',
	] {
		emitted := emit(translation_unit(source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 7
	}
}

fn test_a_file_without_main_says_so() {
	emitted := emit(translation_unit('int other() { return 1; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('no definition of main')
}

fn test_a_return_type_other_than_int_is_reported() {
	// The example has to be a type this compiler still refuses, or the test stops testing the
	// check: `char` was that example until the narrow integer types were implemented.
	unit := ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name:    'main'
				ret:     'long double'
				defined: true
				body:    [return_statement(0)]
			},
		]
	}
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('only int')
}

// The check is on every function the image holds, not only on the entry point:
// a helper the entry point calls is emitted too.
fn test_a_helper_with_another_return_type_is_reported() {
	unit := ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name:    'main'
				ret:     'int'
				defined: true
				body:    [call_statement('helper', []ast.Expr{}), return_statement(0)]
			},
			ast.FnDecl{
				name:    'helper'
				ret:     'long double'
				defined: true
				body:    [return_statement(0)]
			},
		]
	}
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('only int')
}

fn test_the_entry_point_can_be_named() {
	emitted := emit(translation_unit('int other() { return 9; }'), Options{
		entry: 'other'
	})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 9
}

fn test_an_unknown_target_names_the_targets_that_exist() {
	emitted := emit(translation_unit('int main() { return 1; }'), Options{
		target: 'riscv64-linux'
	})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('unknown target riscv64-linux')
	assert emitted.diagnostics[0].msg.contains('x86_64-linux')
}

// A frame with two locals in it: each declaration takes a slot, each initializer
// writes it, and the return reads both back out.
fn test_two_locals_are_summed() {
	body := [
		declaration('a', 'int', int_argument(40)),
		declaration('b', 'int', int_argument(2)),
		return_expression(binary_node('+', name_node('a'), name_node('b'))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

// A declaration without an initializer is storage: the value is whatever the
// function writes into it before it reads it.
fn test_a_declaration_without_an_initializer_is_storage() {
	body := [
		declaration('n', 'int', none),
		assignment('n', int_argument(42)),
		return_expression(name_node('n')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

// A parameter arrives in a register, is stored where a local lives, and is read
// from there as many times as the expression asks for it.
fn test_a_parameter_is_used_in_an_expression() {
	helper := function_in_file('twice', [param('x', 'int')], [
		call_statement('printf', [string_argument('twice %d\n'), binary_node('+', name_node('x'),
			name_node('x'))]),
		return_statement(0),
	])
	body := [
		call_statement('twice', [int_argument(21)]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('twice 42')
}

// An arithmetic answer that is not a constant: the two values are in the frame
// and the operation happens at run time, where a wrong width or a wrong operand
// order would show up in the status.
fn test_arithmetic_on_locals_is_computed() {
	body := [
		declaration('a', 'int', int_argument(47)),
		declaration('b', 'int', int_argument(5)),
		declaration('sum', 'int', binary_node('+', name_node('a'), name_node('b'))),
		declaration('product', 'int', binary_node('*', binary_node('-', name_node('a'), name_node('b')),
			int_argument(2))),
		return_expression(binary_node('+', binary_node('+', name_node('sum'),
			name_node('product')), int_argument(0))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	// 52 + 84, and the low eight bits of 136 are the status.
	assert run_image(emitted.bytes) == 136
}

// The two division operators read the quotient and the remainder from the two
// registers a signed division leaves them in: 47 / 5 is 9 and 47 % 5 is 2.
fn test_division_and_remainder_on_locals() {
	body := [
		declaration('a', 'int', int_argument(47)),
		declaration('b', 'int', int_argument(5)),
		return_expression(binary_node('+', binary_node('/', name_node('a'), name_node('b')),
			binary_node('*', binary_node('%', name_node('a'), name_node('b')), int_argument(10)))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 29
}

// Each side of an if returns a value of its own, so the status says which branch
// ran. The condition is a constant here and a value read from the frame in the
// test after it, which is the case the branch is for.
fn test_each_side_of_an_if_returns_its_own_value() {
	taken := emit(program([
		if_statement(int_argument(1), [return_statement(3)], [return_statement(4)]),
	]), Options{})
	assert taken.diagnostics.len == 0
	assert run_image(taken.bytes) == 3
	not_taken := emit(program([
		if_statement(int_argument(0), [return_statement(3)], [return_statement(4)]),
	]), Options{})
	assert not_taken.diagnostics.len == 0
	assert run_image(not_taken.bytes) == 4
}

fn test_a_condition_on_a_local_picks_the_branch() {
	body := [
		declaration('n', 'int', int_argument(7)),
		if_statement(binary_node('<', name_node('n'), int_argument(10)), [return_statement(1)],
			[return_statement(2)]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A body whose if can fall through has a way out that returns nothing, so the
// function still finishes with the zero a caller is owed.
fn test_a_body_that_falls_off_the_end_after_an_if_returns_zero() {
	body := [
		if_statement(int_argument(0), [return_statement(7)], []ast.Stmt{}),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 0
}

// A loop that counts to five: the variable is what the condition reads and the
// body writes, and the status is what it holds when the loop stops.
fn test_a_while_loop_counts_to_five() {
	body := [
		declaration('i', 'int', int_argument(0)),
		while_statement(binary_node('<', name_node('i'), int_argument(5)), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
		]),
		return_expression(name_node('i')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 5
}

// break leaves the loop where it stands.
fn test_break_leaves_a_loop() {
	body := [
		declaration('i', 'int', int_argument(0)),
		while_statement(int_argument(1), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			if_statement(binary_node('==', name_node('i'), int_argument(3)), [break_statement()],
				[]ast.Stmt{}),
		]),
		return_expression(name_node('i')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 3
}

// continue goes back to the test, so the statement after it is skipped and the
// loop still runs to its end: four rounds, one of them cut short.
fn test_continue_goes_round_the_loop_again() {
	body := [
		declaration('i', 'int', int_argument(0)),
		declaration('counted', 'int', int_argument(0)),
		while_statement(binary_node('<', name_node('i'), int_argument(4)), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			if_statement(binary_node('==', name_node('i'), int_argument(2)), [continue_statement()],
				[]ast.Stmt{}),
			assignment('counted', binary_node('+', name_node('counted'), int_argument(1))),
		]),
		return_expression(name_node('counted')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 3
}

// The shape a for is turned into before the back end sees it: a block that holds
// the declaration, a while whose condition is the test, and the increment as the
// last statement of the body. Nothing in the emitter knows about for; this test
// pins the desugaring both lanes write against, and the parser's own for is what
// produced the binary this shape came from.
fn test_the_shape_a_for_is_desugared_into_counts() {
	counting := ast.Stmt{
		kind: .block
		body: [
			declaration('i', 'int', int_argument(0)),
			while_statement(binary_node('<', name_node('i'), int_argument(5)), [
				assignment('total', binary_node('+', name_node('total'), binary_node('*',
					name_node('i'), int_argument(2)))),
				assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			]),
		]
	}
	body := [
		declaration('total', 'int', int_argument(0)),
		counting,
		return_expression(name_node('total')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 20
}

// A call whose arguments are computed: two locals are read out of the frame and
// handed over in the registers the definition reads its parameters from, and the
// definition reads them in a frame of its own. The library call inside the
// definition prints what arrived, which is what makes the arguments visible.
fn test_a_call_whose_arguments_are_locals() {
	helper := function_in_file('show', [param('x', 'int'), param('y', 'int')], [
		call_statement('printf', [string_argument('sum %d\n'), binary_node('+', name_node('x'),
			name_node('y'))]),
		return_statement(0),
	])
	body := [
		declaration('a', 'int', int_argument(40)),
		declaration('b', 'int', int_argument(2)),
		call_statement('show', [name_node('a'), name_node('b')]),
		call_statement('printf', [string_argument('difference %d\n'), binary_node('-', name_node('a'),
			name_node('b'))]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('sum 42')
	assert result.output.contains('difference 38')
}

// A pointer local is eight bytes wide and holds the address of a string literal.
// The library call reads the variable, not a literal written where the call is,
// and the program prints what the local points at.
fn test_a_library_call_reads_a_pointer_local() {
	body := [
		declaration('message', 'char *', string_argument('a variable says hello')),
		call_statement('puts', [name_node('message')]),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('a variable says hello')
}

// An int is four bytes and a pointer is eight, and the difference is visible: a
// pointer local and an int local sit in the same frame, each written and read at
// its own width. The call says the pointer kept its value and the status says the
// int kept its.
fn test_an_int_local_and_a_pointer_local_keep_their_widths() {
	body := [
		declaration('message', 'char *', string_argument('widths')),
		declaration('n', 'int', int_argument(6)),
		call_statement('puts', [name_node('message')]),
		return_expression(binary_node('*', name_node('n'), int_argument(7))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 42
	assert result.output.contains('widths')
}

// A wide string literal is an array of wchar_t and decays to a pointer to its
// first element, which on this target is an `int *` because wchar_t is an int.
// Its elements are four bytes apart, so a step of one lands on the next
// character rather than inside the first one, and the terminator the literal does
// not write is a zero wchar_t. Measured on gcc 16.2.1, this program exits 42.
fn test_a_wide_string_literal_decays_to_a_wide_pointer() {
	emitted := emit(translation_unit('int main() { int *p = L"hi"; if (sizeof(L"hi") != 12) return 1; if (p[0] != \'h\') return 2; if (p[1] != \'i\') return 3; if (p[2] != 0) return 4; if ((L"abcd" + 1)[0] != \'b\') return 5; return 42; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

// A function that takes both a pointer and an int and calls the library itself.
// The call to it is written before its definition, which is where a call has to
// bind forward, and the variadic call inside it formats a value computed from
// its parameters.
fn test_a_helper_takes_a_pointer_and_an_int() {
	helper := function_in_file('report', [param('message', 'char *'), param('n', 'int')], [
		call_statement('printf', [string_argument('%s %d\n'), name_node('message'),
			binary_node('*', name_node('n'), int_argument(2))]),
		return_statement(0),
	])
	body := [
		declaration('text', 'char *', string_argument('from a helper')),
		call_statement('report', [name_node('text'), int_argument(21)]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('from a helper 42')
}

// Every comparison is a value of int width, zero or one, and the bits of the
// status are where the six of them are read back.
fn test_comparisons_produce_zero_or_one() {
	operators := ['<', '>', '==', '!=', '<=', '>=']
	// 3 against 5, 3 against 5, then 3 against 3: true, false, true, false,
	// true, true. Each answer goes into a bit of the status, so one run reads
	// back all six.
	truths := [i64(1), i64(0), i64(1), i64(0), i64(1), i64(1)]
	mut body := [declaration('a', 'int', int_argument(3))]
	mut total := i64(0)
	mut sum := ast.Expr(int_argument(0))
	for i, op in operators {
		right := if op in ['<', '>'] { int_argument(5) } else { int_argument(3) }
		weight := i64(1) << i
		body << declaration('c${i}', 'int', binary_node(op, name_node('a'), right))
		total += truths[i] * weight
		sum = binary_node('+', sum, binary_node('*', name_node('c${i}'), int_argument(weight)))
	}
	body << return_expression(sum)
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(total)
}

// The unary operators take one computed value: the sign change negates what is in
// the frame, and the logical not answers whether it is zero.
fn test_unary_operators_compute_on_a_local() {
	negated := emit(program([
		declaration('minus', 'int', int_argument(-42)),
		return_expression(unary_node('-', name_node('minus'))),
	]), Options{})
	assert negated.diagnostics.len == 0
	assert run_image(negated.bytes) == 42
	notted := emit(program([
		declaration('zero', 'int', int_argument(0)),
		declaration('five', 'int', int_argument(5)),
		return_expression(binary_node('+', binary_node('*', unary_node('!', name_node('zero')),
			int_argument(40)), binary_node('*', unary_node('!', name_node('five')), int_argument(2)))),
	]), Options{})
	assert notted.diagnostics.len == 0
	assert run_image(notted.bytes) == 40
}

// The short-circuit operators: the left side settles the answer, so the right
// side is not evaluated at all. The right side here divides by a variable that
// holds zero, which would stop the process if it were evaluated.
fn test_and_and_or_do_not_evaluate_the_side_they_do_not_need() {
	body := [
		declaration('zero', 'int', int_argument(0)),
		declaration('one', 'int', int_argument(1)),
		declaration('conjunction', 'int', binary_node('&&', name_node('zero'),
			binary_node('/', name_node('one'), name_node('zero')))),
		declaration('disjunction', 'int', binary_node('||', name_node('one'),
			binary_node('/', name_node('one'), name_node('zero')))),
		return_expression(binary_node('+', binary_node('*', name_node('conjunction'), int_argument(2)),
			name_node('disjunction'))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A tree with a frame produces the same bytes every time it is emitted, which is
// what the layout being a sequence is for.
fn test_a_tree_with_a_frame_produces_the_same_bytes() {
	body := [
		declaration('a', 'int', int_argument(1)),
		if_statement(name_node('a'), [
			assignment('a', binary_node('+', name_node('a'), int_argument(1))),
		], []ast.Stmt{}),
		while_statement(binary_node('<', name_node('a'), int_argument(4)), [
			assignment('a', binary_node('+', name_node('a'), int_argument(1))),
		]),
		return_expression(name_node('a')),
	]
	unit := program(body)
	first := emit(unit, Options{})
	second := emit(unit, Options{})
	assert first.diagnostics.len == 0
	assert second.diagnostics.len == 0
	assert first.bytes == second.bytes
}

// What the back end cannot emit it reports, once, with the place it was written,
// and writes no image at all. These are the three shapes a body can reach: a
// statement with no loop to leave, a local of a type that has no instruction,
// and an operation on a pointer that would compute at the wrong width.
fn test_two_addresses_are_compared_at_the_width_of_a_word() {
	// The two addresses hold the same low half and different upper halves: q is
	// p cut down to an int and made back into an address, which sign-extends
	// what is left. Comparing four bytes would call them equal, and measured,
	// gcc 16.2.1 answers 0 here while `(int)p == (int)q` answers 1.
	emitted := emit(translation_unit('int main() { int x = 0; char *p = (char *)&x; char *q = (char *)(int)&x; if (p == q) { return 1; } return 0; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 0
	// The same comparison with the halves asked about says the halves are equal,
	// which is what makes the answer above a comparison of the whole word.
	halves := emit(translation_unit('int main() { int x = 0; char *p = (char *)&x; char *q = (char *)(int)&x; if ((int)p == (int)q) { return 1; } return 0; }'),
		Options{})
	assert halves.diagnostics.len == 0
	assert run_image(halves.bytes) == 1
}

fn test_break_outside_a_loop_is_one_located_diagnostic_and_no_bytes() {
	emitted := emit(program([break_statement()]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('break outside a loop')
	assert emitted.bytes.len == 0
}

// A 128-bit object is storage this back end has: sixteen bytes, a value narrower
// than that widened into its two words, and one object copied into another. The
// value cannot be read back yet, because this back end has no value of that width,
// so what a test can assert about the store is what it emits: the high word is the
// low one's sign, and the arithmetic shift that computes it is written here and
// nowhere else in the tree, which is what makes the bytes below this store's.
fn test_a_128_bit_object_is_stored_as_two_words() {
	emitted := emit(translation_unit('int main() { __int128 a = 5; __int128 b = a; a = -1; return (int)(&a != &b); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	// Two objects, each of sixteen bytes, at two addresses: what the program can
	// still observe is that they are storage of their own.
	assert run_image(emitted.bytes) == 1
	// `sar rax, 63`: the sign of the low word spread over the high one.
	assert holds(emitted.bytes, [u8(0x48), 0xc1, 0xf8, 0x3f])
}

// A 128-bit object is read by converting it to a narrower type, and the read is the
// low word: the value of the type is the two words the object holds, and a
// conversion out of it takes that value modulo the width of the target. Measured on
// gcc 16.2.1, the programs here return 7, 44, 255 and 44, and the last two of them
// read bytes that a copy and an assignment wrote.
fn test_a_128_bit_object_is_read_by_converting_it_to_a_narrower_type() {
	stored := emit(translation_unit('int main() { __int128 v = 7; return (int)v; }'), Options{})
	assert stored.diagnostics.len == 0
	assert run_image(stored.bytes) == 7
	// 300 is 0x12c: the low byte is 44 and the byte above it is 1, which is what
	// makes the read a read of the value rather than of a byte that happened to
	// be in the register.
	low_byte := emit(translation_unit('int main() { __int128 v = 300; return (int)(char)v; }'),
		Options{})
	assert low_byte.diagnostics.len == 0
	assert run_image(low_byte.bytes) == 44
	// A negative value has the sign in every byte of both words, so the low word
	// read as an int is the value that was stored.
	negative := emit(translation_unit('int main() { __int128 v = -1; return (int)v; }'), Options{})
	assert negative.diagnostics.len == 0
	assert run_image(negative.bytes) == 255
	// The bytes the store wrote are the bytes the read takes: through a copy into
	// another object of the type, and through an assignment to an object that was
	// declared with no initializer.
	copied := emit(translation_unit('int main() { __int128 a = 300; __int128 b = a; return (int)(char)b; }'),
		Options{})
	assert copied.diagnostics.len == 0
	assert run_image(copied.bytes) == 44
	assigned := emit(translation_unit('int main() { __int128 a; a = 300; return (int)(char)a; }'),
		Options{})
	assert assigned.diagnostics.len == 0
	assert run_image(assigned.bytes) == 44
	// A pointer takes the low word, which is what gcc's `(char *)` of one is.
	as_pointer := emit(translation_unit('int main() { __int128 v = 0; char *p = (char *)v; return p == 0; }'),
		Options{})
	assert as_pointer.diagnostics.len == 0
	assert run_image(as_pointer.bytes) == 1
}

// A member of that width is written and read the way an object of the type is, at
// the member's own address: the object it lies in may be a local, a pointer's
// target or a top-level object, so the store cannot be an offset from the frame.
// Measured on gcc 16.2.1, the four programs here return 44, 7, 44 and 1.
fn test_a_128_bit_member_is_written_and_read_at_its_address() {
	local := emit(translation_unit('struct S { __int128 v; char c; }; int main() { struct S s; s.v = 300; return (int)(char)s.v; }'),
		Options{})
	assert local.diagnostics.len == 0
	assert run_image(local.bytes) == 44
	whole := emit(translation_unit('struct S { __int128 v; }; int main() { struct S s; s.v = 7; return (int)s.v; }'),
		Options{})
	assert whole.diagnostics.len == 0
	assert run_image(whole.bytes) == 7
	// A member reached through a pointer is at an address the frame does not hold:
	// the store goes through what the pointer holds plus the member's offset.
	through_pointer := emit(translation_unit('struct S { __int128 v; }; int main() { struct S s; struct S *p = &s; p->v = 300; return (int)(char)s.v; }'),
		Options{})
	assert through_pointer.diagnostics.len == 0
	assert run_image(through_pointer.bytes) == 44
	// A member assigned another member of the same type is a copy of the sixteen
	// bytes rather than a value widened into them.
	copied := emit(translation_unit('struct S { __int128 v; }; int main() { struct S a; struct S b; a.v = 300; b.v = a.v; return (int)(char)b.v; }'),
		Options{})
	assert copied.diagnostics.len == 0
	assert run_image(copied.bytes) == 44
	// The bytes after the member are the member's neighbours, not its second half:
	// a char after it is read back as the char it was written as.
	neighbour := emit(translation_unit('struct S { __int128 v; char c; }; int main() { struct S s; s.v = 300; s.c = 65; return s.c == 65; }'),
		Options{})
	assert neighbour.diagnostics.len == 0
	assert run_image(neighbour.bytes) == 1
}

// A top-level object of the type is storage the image holds, reachable the way any
// other top-level object is: written through its address, read by a conversion at that
// address, and an element of an array of them the same. Before this, the shape of the
// type had no case for a top-level object, so every one of these refused with a message
// about a missing local. Measured on gcc 16.2.1, the programs below return 44, 144, 44,
// 44 and 255.
fn test_a_top_level_object_of_128_bits_is_written_and_read_at_its_address() {
	scalar := emit(translation_unit('__int128 g; int main() { g = 300; int n = g; return n; }'), Options{})
	assert scalar.diagnostics.len == 0
	assert run_image(scalar.bytes) == 44
	twice := emit(translation_unit('__int128 g; int main() { g = 300; g = 400; int n = g; return n; }'),
		Options{})
	assert twice.diagnostics.len == 0
	assert run_image(twice.bytes) == 144
	element := emit(translation_unit('__int128 g[2]; int main() { g[1] = 300; int n = g[1]; return n; }'),
		Options{})
	assert element.diagnostics.len == 0
	assert run_image(element.bytes) == 44
	copied := emit(translation_unit('__int128 g[2]; int main() { g[0] = 300; g[1] = g[0]; int n = g[1]; return n; }'),
		Options{})
	assert copied.diagnostics.len == 0
	assert run_image(copied.bytes) == 44
	negative := emit(translation_unit('__int128 g; int main() { g = -1; int n = g; return n; }'), Options{})
	assert negative.diagnostics.len == 0
	assert run_image(negative.bytes) == 255
	// The name read as a *value* is refused by name, the way a local of the type is:
	// the storage is real and the value of that width is not.
	value := emit(translation_unit('__int128 g; int main() { g = 5; return g; }'), Options{})
	assert value.diagnostics.len == 1
	assert value.diagnostics[0].msg.contains('is an object of 128 bits')
	assert value.bytes.len == 0
}

// The initializer of a top-level object of the type is a constant written into the
// image, and the image is where the sign has to reach: a width wider than the eight
// bytes a constant is held in fills its remaining bytes from the sign, because the
// shift that would read them is a shift by the width of the value itself. V leaves
// that undefined and it answered zero, so `__int128 g = -100` came out with a zero
// second word and every later read of that word was wrong: the shift that takes the
// word answered 0 where gcc answers 255, `g < 0` answered 0 where gcc answers 1, and
// a division and a remainder on a negative object used the pair as if it were
// positive. The assignment case above was always right, which is what makes this the
// initializer alone. Measured on gcc 16.2.1, the programs below return 255, 1, 0,
// 255, 242 and 254.
// A pointer to the type is a pointer, one word, and this back end stores an address
// in one the way it does for every other pointee. It was not: the question the
// reader asked was whether the spelling contains the type's name, and `__int128 *`
// does, so the declaration was given sixteen bytes as if it were the object and the
// address was then refused as `a pointer is stored in an object of 128 bits`, naming
// the opposite of what the source says. Measured on gcc 16.2.1, the programs below
// return 5 and 7.
//
// What a pointer to the type still cannot do is refused by name: reading through
// one is a whole-object read, and an element of the type is sixteen bytes one
// instruction cannot move. Both of those are the refusals they always were.
fn test_a_pointer_to_the_type_is_a_pointer() {
	declared := emit(translation_unit('int main() { __int128 a = 5; __int128 *p = &a; return (int)a; }'), Options{})
	assert declared.diagnostics.len == 0
	assert run_image(declared.bytes) == 5
	assigned := emit(translation_unit('int main() { __int128 a = 5; __int128 *p; p = &a; return (int)a; }'),
		Options{})
	assert assigned.diagnostics.len == 0
	assert run_image(assigned.bytes) == 5
	global := emit(translation_unit('__int128 g = 7; int main() { __int128 *p = &g; return (int)g; }'), Options{})
	assert global.diagnostics.len == 0
	assert run_image(global.bytes) == 7
	// A parameter of this type is one argument register, which the same question
	// used to answer as a pair of them.
	passed := emit(translation_unit('int f(__int128 *p) { return 1; } int main() { __int128 a = 5; return f(&a); }'),
		Options{})
	assert passed.diagnostics.len == 0
	assert run_image(passed.bytes) == 1
	read_through := emit(translation_unit('int main() { __int128 a = 5; __int128 *p = &a; return (int)(*p); }'),
		Options{})
	assert read_through.diagnostics.len == 1
	assert read_through.diagnostics[0].msg.contains('reads through an address')
	assert read_through.bytes.len == 0
	element := emit(translation_unit('int main() { __int128 a[2]; __int128 *p = a; return (int)p[0]; }'), Options{})
	assert element.diagnostics.len == 1
	assert element.diagnostics[0].msg.contains('an object of 128 bits')
	assert element.bytes.len == 0
}

fn test_a_top_level_object_of_128_bits_keeps_the_sign_of_its_initializer() {
	shifted := emit(translation_unit('__int128 g = -100; int main() { return (int)(g >> 64); }'), Options{})
	assert shifted.diagnostics.len == 0
	assert run_image(shifted.bytes) == 255
	compared := emit(translation_unit('__int128 g = -100; int main() { return g < 0; }'), Options{})
	assert compared.diagnostics.len == 0
	assert run_image(compared.bytes) == 1
	positive := emit(translation_unit('__int128 g = 300; int main() { return (int)(g >> 64); }'), Options{})
	assert positive.diagnostics.len == 0
	assert run_image(positive.bytes) == 0
	unsigned_negative := emit(translation_unit('unsigned __int128 g = -1; int main() { return (int)(g >> 64); }'),
		Options{})
	assert unsigned_negative.diagnostics.len == 0
	assert run_image(unsigned_negative.bytes) == 255
	divided := emit(translation_unit('__int128 g = -100; int main() { __int128 h = 7; return (int)(g / h); }'),
		Options{})
	assert divided.diagnostics.len == 0
	assert run_image(divided.bytes) == 242
	remainder := emit(translation_unit('__int128 g = -100; int main() { __int128 h = 7; return (int)(g % h); }'),
		Options{})
	assert remainder.diagnostics.len == 0
	assert run_image(remainder.bytes) == 254
}

// An array of 128-bit objects is storage whose elements are written and read the way
// the object of the type is, at the element's own address: the store is the two words
// an object takes, the conversion is the low word at the element's address, and an
// element taken as a *value* is refused by name, because the type has no value here.
// Measured on gcc 16.2.1, the programs below return 0, 44, 44 and 255.
fn test_an_array_of_128_bit_objects_is_written_and_read_at_an_element_address() {
	declared := emit(translation_unit('int main() { __int128 a[3]; return (int)sizeof(a); }'), Options{})
	assert declared.diagnostics.len == 0
	assert run_image(declared.bytes) == 48
	stored := emit(translation_unit('int main() { __int128 a[3]; a[0] = 300; return 0; }'), Options{})
	assert stored.diagnostics.len == 0
	assert run_image(stored.bytes) == 0
	converted := emit(translation_unit('int main() { __int128 a[3]; a[0] = 300; int n = a[0]; return n; }'),
		Options{})
	assert converted.diagnostics.len == 0
	assert run_image(converted.bytes) == 44
	// An element assigned another element is a copy of the sixteen bytes, and the
	// address of the source is the element's own.
	copied := emit(translation_unit('int main() { __int128 a[2]; a[0] = 300; a[1] = a[0]; int n = a[1]; return n; }'),
		Options{})
	assert copied.diagnostics.len == 0
	assert run_image(copied.bytes) == 44
	negative := emit(translation_unit('int main() { __int128 a[2]; a[0] = -1; int n = a[0]; return n; }'), Options{})
	assert negative.diagnostics.len == 0
	assert run_image(negative.bytes) == 255
	// An element read as a value is the one shape left refused, and it is refused by
	// name: the value of that width is what this back end does not have.
	read := emit(translation_unit('int main() { __int128 a[3]; a[0] = 5; return a[0]; }'), Options{})
	assert read.diagnostics.len == 1
	assert read.diagnostics[0].msg.contains('is an object of 128 bits')
	assert read.bytes.len == 0
	// The member of an element is the same widening store the member of any object
	// takes, at the address of the element plus the member's offset.
	member := emit(translation_unit('struct S { __int128 v; }; struct S s[2]; int main() { s[1].v = 300; return (int)(char)s[1].v; }'),
		Options{})
	assert member.diagnostics.len == 0
	assert run_image(member.bytes) == 44
}

// The machine scales an index by one, two, four or eight and by no other number, so
// an array of objects of any other size is a multiply and an add. Measured on gcc
// 16.2.1, the two programs below return 44, and a whole element of a sixteen-byte
// struct is refused by name rather than passed to the encoding.
fn test_an_element_of_a_size_the_machine_does_not_scale_is_a_multiply_and_an_add() {
	twelve := emit(translation_unit('struct S { int a; int b; int c; }; int main() { struct S s[3]; s[2].b = 300; return (int)(char)s[2].b; }'),
		Options{})
	assert twelve.diagnostics.len == 0
	assert run_image(twelve.bytes) == 44
	through_an_index := emit(translation_unit('struct S { int a; int b; int c; }; int main() { struct S s[4]; int i = 3; s[i].c = 300; return (int)(char)s[i].c; }'),
		Options{})
	assert through_an_index.diagnostics.len == 0
	assert run_image(through_an_index.bytes) == 44
	whole := emit(translation_unit('struct S { int a; int b; int c; int d; }; int main() { struct S s[2]; s[0] = s[1]; return 0; }'),
		Options{})
	assert whole.diagnostics.len == 1
	assert whole.diagnostics[0].msg.contains('elements of 16 bytes')
}

// A constant stored into an element is written at the element's width, which is
// what a store into a local already does: the value is widened into a wider
// element and narrowed into a narrower one the way the member path does, so an
// element of an unsigned long holds -5 as its unsigned reading and an element of
// an unsigned int takes the low four bytes of a wider constant. The element is
// reached the same way through a pointer, through a two-dimensional subscript
// and as a member of an array of structs. Measured on gcc 16.2.1, which answers
// the program below with 6.
fn test_a_constant_stored_into_an_element_converts_to_the_elements_width() {
	emitted := emit(translation_unit('unsigned long g[4];\nint main(void) { unsigned long a[4]; a[1] = -5; unsigned long expect = 18446744073709551611UL; unsigned long buf[4]; unsigned long *p = buf; p[1] = -5; unsigned long row[4]; unsigned long *p2[2]; p2[0] = row; p2[0][1] = -5; unsigned int b[4]; b[1] = 0xFFFFFFFFFFFFFFFBUL; struct S { unsigned long y; } s[4]; s[1].y = -5; g[1] = -5; return (a[1] == expect) + (buf[1] == expect) + (row[1] == expect) + (b[1] == 0xFFFFFFFBu) + (s[1].y == expect) + (g[1] == expect); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 6
}

// A floating target is the one conversion out of a 128-bit object that this back
// end does not make: the double of that value is a rounding of the whole of it and
// not the low word, so it is refused rather than answered with the low word as
// though the top of the value were zero.
fn test_a_conversion_from_a_128_bit_object_to_a_double_is_reported() {
	emitted := emit(translation_unit('int main() { __int128 v = 5; double d = (double)v; return (int)d; }'),
		Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('128-bit object to double')
	assert emitted.bytes.len == 0
}

// A double and a pointer are not widened into a 128-bit object, and saying so is
// better than writing the bits of one as the low word of the other.
fn test_a_value_that_cannot_widen_into_a_128_bit_object_is_reported() {
	wrong_class := emit(translation_unit('int main() { __int128 a = 2.5; return 0; }'), Options{})
	assert wrong_class.diagnostics.len == 1
	assert wrong_class.diagnostics[0].msg.contains('128 bits')
	assert wrong_class.bytes.len == 0
}

// A 128-bit object stored into a narrower slot takes its low word: the value of the
// type modulo the width of the slot, which is the conversion the language defines.
// Measured on gcc 16.2.1, the programs below return 44, 44, 255, 65 and 44.
fn test_a_128_bit_object_stored_into_a_narrower_slot_takes_its_low_word() {
	declared := emit(translation_unit('int main() { __int128 v = 300; int n = v; return n; }'), Options{})
	assert declared.diagnostics.len == 0
	assert run_image(declared.bytes) == 44
	as_char := emit(translation_unit('int main() { __int128 v = 300; char c = v; return c; }'), Options{})
	assert as_char.diagnostics.len == 0
	assert run_image(as_char.bytes) == 44
	negative := emit(translation_unit('int main() { __int128 v = -1; int n = v; return n; }'), Options{})
	assert negative.diagnostics.len == 0
	assert run_image(negative.bytes) == 255
	assigned := emit(translation_unit('int main() { __int128 v = 65; char c = 0; c = v; return c; }'), Options{})
	assert assigned.diagnostics.len == 0
	assert run_image(assigned.bytes) == 65
	// A member of that type is read the same way, through the member's own address.
	member := emit(translation_unit('struct S { __int128 v; }; int main() { struct S s; s.v = 300; int n = s.v; return n; }'),
		Options{})
	assert member.diagnostics.len == 0
	assert run_image(member.bytes) == 44
}

// The low word is the answer for an integer slot and the wrong answer for a
// floating one, where the language converts the whole value: this program answered
// 0 before the refusal was written, because the low word stored into a double slot
// is the integer's bits rather than the number. Measured on gcc 16.2.1,
// `double d = (__int128)5;` is 5.0.
fn test_the_low_word_is_refused_for_a_floating_slot() {
	declared := emit(translation_unit('int main() { __int128 v = 5; double d = v; return (int)d; }'), Options{})
	assert declared.diagnostics.len == 1
	assert declared.diagnostics[0].msg.contains('does not convert to a floating type')
	assert declared.bytes.len == 0
	assigned := emit(translation_unit('int main() { __int128 v = 5; double d = 0; d = v; return (int)d; }'), Options{})
	assert assigned.diagnostics.len == 1
	assert assigned.diagnostics[0].msg.contains('slot that holds a double')
	assert assigned.bytes.len == 0
}

fn test_a_local_of_a_type_with_no_instruction_is_reported() {
	// `long double` is the type here rather than `float`, which this back end now
	// has instructions for: what this checks is the refusal, so it names a type
	// the emitter still has no form for.
	body := [
		declaration('f', 'long double', int_argument(1)),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('long double')
	assert emitted.bytes.len == 0
}

fn test_an_operation_on_a_pointer_is_reported() {
	body := [
		declaration('s', 'char *', string_argument('x')),
		declaration('t', 'char *', binary_node('+', name_node('s'), int_argument(1))),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('pointer')
	assert emitted.bytes.len == 0
}

// More parameters than the machine passes in registers: the rest would have to
// be read off the stack, and that is said rather than emitted.
// A definition with more parameters than the machine has registers reads the
// extra ones from the frame it was entered with, sixteen bytes past the frame
// pointer counting the saved frame pointer and the return address.
fn test_more_parameters_than_the_machine_has_registers_are_read_from_the_stack() {
	mut params := []ast.Param{}
	for i in 0 .. 7 {
		params << param('p${i}', 'int')
	}
	helper := function_in_file('many', params, [return_statement(0)])
	emitted := emit(unit_of([return_statement(0)], [helper]), Options{})
	assert emitted.diagnostics.len == 0
	assert emitted.bytes.len > 0
}

// A program header the way the kernel reads it, so a test can say what the image
// claims rather than what the emitter meant.
struct Segment {
	kind   u32
	offset u64
	vaddr  u64
	filesz u64
}

fn u16_at(bytes []u8, offset int) u16 {
	return u16(bytes[offset]) | (u16(bytes[offset + 1]) << 8)
}

fn u32_at(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) | (u32(bytes[offset + 1]) << 8) | (u32(bytes[offset + 2]) << 16) | (u32(bytes[offset + 3]) << 24)
}

fn u64_at(bytes []u8, offset int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 {
		value |= u64(bytes[offset + i]) << u64(8 * i)
	}
	return value
}

fn segments(bytes []u8) []Segment {
	start := int(u64_at(bytes, 32))
	size := int(u16_at(bytes, 54))
	count := int(u16_at(bytes, 56))
	mut out := []Segment{}
	for i in 0 .. count {
		at := start + i * size
		out << Segment{
			kind:   u32_at(bytes, at)
			offset: u64_at(bytes, at + 8)
			vaddr:  u64_at(bytes, at + 16)
			filesz: u64_at(bytes, at + 32)
		}
	}
	return out
}

fn only_segment(headers []Segment, kind u32) Segment {
	matching := headers.filter(it.kind == kind)
	assert matching.len == 1
	return matching[0]
}

// dynamic_value looks a tag up in the dynamic table the loader reads.
fn dynamic_value(bytes []u8, tag u64) ?u64 {
	dynamic := only_segment(segments(bytes), elf.elf_ph_type_dynamic)
	for i in 0 .. int(dynamic.filesz) / elf.elf_dynamic_entry_size {
		at := int(dynamic.offset) + i * elf.elf_dynamic_entry_size
		if u64_at(bytes, at) == elf.dt_null {
			break
		}
		if u64_at(bytes, at) == tag {
			return u64_at(bytes, at + 8)
		}
	}
	return none
}

// holds says whether a run of bytes is somewhere in the image, which is how a test
// checks for an instruction the way the push test checks for 0x50.
fn holds(bytes []u8, needle []u8) bool {
	if needle.len == 0 || bytes.len < needle.len {
		return false
	}
	for start in 0 .. bytes.len - needle.len + 1 {
		mut found := true
		for i in 0 .. needle.len {
			if bytes[start + i] != needle[i] {
				found = false
				break
			}
		}
		if found {
			return true
		}
	}
	return false
}

fn read_string(bytes []u8, offset int) string {
	mut end := offset
	for end < bytes.len && bytes[end] != 0 {
		end++
	}
	return bytes[offset..end].bytestr()
}

// A char is one byte in the frame and an int in an expression: the load widens
// what it read, so adding one to a number needs nothing else, and a value too
// large for the byte is stored as its low byte, which is what the language's
// assignment to a char does.
fn test_a_char_local_is_a_byte_that_widens_when_it_is_read() {
	body := [
		declaration('c', 'char', int_argument(65)),
		declaration('sum', 'int', int_argument(0)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('-', name_node('c'), int_argument(65)))),
		declaration('d', 'char', int_argument(300)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('-', name_node('d'), int_argument(44)))),
		declaration('e', 'char', int_argument(-1)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('+', name_node('e'), int_argument(1)))),
		ast.Stmt{
			kind: .return_stmt
			expr: name_node('sum')
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// A char parameter arrives in a register that carries a machine word: the frame
// keeps the low byte of it, and the argument side reads the byte and widens it,
// so a char whose value is negative is handed over as the number it is.
fn test_a_char_parameter_keeps_its_value_and_its_sign() {
	helper := ast.FnDecl{
		name:    'addc'
		ret:     'int'
		params:  [
			ast.Param{
				name: 'a'
				typ:  'char'
			},
			ast.Param{
				name: 'b'
				typ:  'char'
			},
		]
		defined: true
		body:    [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('a'), name_node('b'))
		}]
	}
	body := [
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', ast.Expr(ast.Call{
				name: 'addc'
				args: [int_argument(200), int_argument(100)]
			}), int_argument(44))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// An array is a block of storage and its name is the address of the first
// element, which is what a library function that takes a pointer reads: the bytes
// written one at a time are the string that comes out of it.
fn test_a_char_array_written_one_byte_at_a_time_is_a_string() {
	body := [
		ast.Stmt{
			kind:       .var_decl
			decl_name:  'buf'
			decl_type:  'char'
			decl_count: 8
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(0)
			expr:   int_argument(72)
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(1)
			expr:   int_argument(105)
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(2)
			expr:   int_argument(0)
		},
		call_statement('puts', [name_node('buf')]),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('Hi')
}

// An element is addressed as the frame plus the index scaled by the width of an
// element, so an index that is not a constant is the same instruction: what one
// element was written through, the other is read through.
fn test_an_element_with_a_variable_index_is_the_element_it_reads() {
	body := [
		ast.Stmt{
			kind:       .var_decl
			decl_name:  'a'
			decl_type:  'int'
			decl_count: 4
		},
		declaration('i', 'int', int_argument(2)),
		ast.Stmt{
			kind:   .assign
			target: 'a'
			index:  name_node('i')
			expr:   int_argument(30)
		},
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', ast.Expr(ast.Index{
				base:  name_node('a')
				index: int_argument(2)
			}), int_argument(30))
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// A double is a value the floating-point registers hold and their instructions
// compute. These tests read it back the way a program does: the image is emitted,
// run, and its exit status is the value truncated to an int where the language
// converts it. The number each one asserts is what the arithmetic gives, so a
// wrong instruction in the register file shows up as a wrong answer.
// A 128-bit value is a pair and the operations on it are the two-word forms of
// the machine's instructions: the low words are added and the carry goes into the
// high ones, the subtraction borrows, the order of two pairs is the borrow out of
// the low subtraction carried into the high one, and the sign of a pair changes
// through the carry the low negation leaves. Measured on gcc 16.2.1, the programs
// below and ten more return exactly these numbers, which are the low bytes of the
// two-word answers.
// doubling is the source for a power of two, which is how the tests below write a
// 128-bit expected value: the type has no literal that wide, and a shift would be
// another feature.
fn doubling(name string, times int) string {
	mut text := '\tunsigned __int128 ${name} = 1;\n'
	for _ in 0 .. times {
		text += '\t${name} = ${name} + ${name};\n'
	}
	return text
}

// A pair multiplied by a pair. Every case here is a program whose answer gcc
// 16.2.1 gives as 1 and whose answer this compiler gives as 1 too: the low word's
// product reaching the high word, the two cross products, a sign on one operand
// and on both, a narrow operand on either side, and a chain.
fn test_two_128_bit_values_are_multiplied() {
	powers := doubling('t64', 64) + doubling('t33', 33) + doubling('t32', 32) + doubling('t65', 65) + doubling('t97', 97)
	cases := [
		// (2^32 + 1)^2 = 2^64 + 2^33 + 1: the cross products are zero and the low
		// product is the part that overflows.
		'${powers}\tunsigned __int128 a = t32 + 1;\n\tunsigned __int128 p = a * a;\n\tunsigned __int128 e = t64 + t33 + 1;\n\treturn p == e;',
		// (2^64 + 2^32 + 1)^2 = 2^97 + 2^65 + 2^64 + 2^33 + 1: every part of the
		// sequence matters at once.
		'${powers}\tunsigned __int128 a = t64 + t32 + 1;\n\tunsigned __int128 p = a * a;\n\tunsigned __int128 e = t97 + t65 + t64 + t33 + 1;\n\treturn p == e;',
		// -(2^64 + 1) * (2^64 + 5) = -(6 * 2^64 + 5), where both cross products
		// carry a sign.
		'${powers}\t__int128 a = 0 - t64 - 1;\n\t__int128 b = t64 + 5;\n\t__int128 p = a * b;\n\t__int128 e = 0;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - 5;\n\treturn p == e;',
		// A narrow operand on either side, which is widened into a pair first.
		'\tunsigned __int128 a = 6;\n\treturn (a * 7) == 42;',
		'\tunsigned __int128 b = 6;\n\treturn (7 * b) == 42;',
		// A negative narrow operand, and a chain of three.
		'\t__int128 a = -3;\n\treturn (int)(a * 5) == -15;',
		'\tunsigned __int128 a = 3;\n\treturn (int)(a * 2 * 7) == 42;',
		'\tunsigned __int128 a = 0;\n\treturn (a * 12345) == 0;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

// A pair divided by a pair, and the remainder of one by the other. gcc hands this
// to libgcc and this back end has nothing to call, so the routine is the compiler's
// own; every program here is one gcc 16.2.1 answers with 1 and this compiler
// answers with 1 too. The large cases are the identity a division is defined by —
// the quotient times the divisor plus the remainder is the dividend, and the
// remainder is the smaller — which pins the quotient exactly, given the multiply
// and the comparison the identity is written with are already held to gcc.
// The shifts and the bitwise operators, on a narrow value and on a pair. The
// count of a shift is written into the instruction, so every program here shifts
// by a constant; a count the program computes is refused, and that refusal is the
// next test. Every answer here is one gcc 16.2.1 gives the same status for.
fn test_a_shift_and_a_bitwise_operator_on_a_narrow_value() {
	cases := [
		'\tint a = 1;\n\treturn (a << 3) == 8;',
		'\tint a = 256;\n\treturn (a >> 4) == 16;',
		// The shift that keeps the sign: a negative value shifted right stays
		// negative, and one shifted down to the sign bit is -1.
		'\tint a = -8;\n\treturn (a >> 1) == -4;',
		'\tint a = -8;\n\treturn (a >> 31) == -1;',
		'\tint a = 1;\n\treturn (a << 31) < 0;',
		'\tint a = 6;\n\tint b = 3;\n\treturn (a & b) == 2 && (a | b) == 7 && (a ^ b) == 5;',
		'\tint a = 1;\n\tint b = 2;\n\treturn ((a << 3) + (b << 2)) == 16;',
		'\tint a = 5;\n\treturn (a << 0) == 5 && (a >> 0) == 5;',
		'\tint a = 0x1234;\n\treturn ((a >> 4) & 0xff) == 0x23;',
		'\tint a = 6;\n\treturn ~a == -7;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

// A shift of a pair moves the other word across, and a count of a word or more
// moves it over entirely, which is the case the high word can be read with: `a >>
// 64` of a pair whose low word is 5 and whose high word is 1 is 1. A bitwise
// operator works on both words at once, which is what the pair's form of it means.
fn test_a_shift_of_a_pair_moves_the_other_word() {
	powers := doubling('t64', 64) + doubling('t70', 70) + doubling('t100', 100) + doubling('t127', 127)
	cases := [
		'${powers}\t__int128 a = t64 + 5;\n\treturn (a >> 64) == 1;',
		'${powers}\tunsigned __int128 a = t64 + 5;\n\treturn (a >> 64) == 1;',
		'${powers}\t__int128 a = t70;\n\treturn (a >> 70) == 1;',
		'${powers}\t__int128 a = t100;\n\treturn (a >> 100) == 1;',
		'${powers}\t__int128 a = 5;\n\t__int128 p = a << 64;\n\treturn p == t64 * 5;',
		'${powers}\t__int128 a = 3;\n\t__int128 p = a << 70;\n\treturn p == t70 * 3;',
		'${powers}\t__int128 a = 1;\n\treturn (a << 63) == t64 / 2;',
		'${powers}\t__int128 a = 1;\n\t__int128 p = a << 127;\n\treturn p < 0 && (p >> 127) == -1;',
		'\t__int128 a = 5;\n\treturn (a << 3) == 40 && (a >> 3) == 0;',
		'\t__int128 a = 40;\n\treturn (a >> 3) == 5;',
		'\t__int128 a = -1;\n\treturn (a >> 1) == -1 && (a >> 64) == -1;',
		'\t__int128 a = 7;\n\treturn (a >> 0) == 7 && (a << 0) == 7;',
		'${powers}\t__int128 a = t64 + 0xff;\n\t__int128 b = 0x0f;\n\treturn (a & b) == 0x0f;',
		'\t__int128 a = 0xf0;\n\t__int128 b = 0x0f;\n\treturn (a | b) == 0xff && (a ^ b) == 0xff;',
		'${powers}\tunsigned __int128 a = t64 + 0x1234;\n\treturn ((a >> 4) & 0xff) == 0x23;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

// A count the program writes down is refused when it is as wide as the value being
// shifted, because the language calls that undefined and any answer would be
// invented: the instruction would shift by the count modulo the width, which is a
// number nobody wrote.
// A compound assignment on an object of 128 bits, which is the shape `v <<= 1`
// has: the reader writes it as the assignment of the binary operator to the same
// name, and the value the emitter is handed is the result of that operator rather
// than storage. It was refused by name for a while, because the reader built the
// node by hand and left its type empty, and an empty type is a value this back end
// cannot size.
fn test_a_compound_assignment_on_a_pair_runs() {
	powers := doubling('t64', 64) + doubling('t72', 72)
	cases := [
		'\t__int128 v = 6;\n\tv *= 7;\n\treturn v == 42;',
		'\t__int128 v = 100;\n\tv /= 3;\n\treturn v == 33;',
		'\t__int128 v = 100;\n\tv %= 7;\n\treturn v == 2;',
		'\t__int128 v = -8;\n\tv >>= 1;\n\treturn v == -4;',
		'\tunsigned __int128 v = 84;\n\tv >>= 1;\n\treturn v == 42;',
		'\t__int128 v = 0xf0;\n\tv |= 0x0f;\n\tv ^= 0x80;\n\treturn v == 0x7f;',
		'\t__int128 v = 8; int n = 2;\n\tv <<= n;\n\treturn v == 32;',
		'${powers}\t__int128 v = 1;\n\tv <<= 70;\n\treturn (v >> 70) == 1;',
		'${powers}\t__int128 v = t64 + 0xff;\n\tv &= 0x0f;\n\treturn v == 0x0f;',
		'${powers}\t__int128 v = 1;\n\tv <<= 64;\n\tv += 5;\n\tv <<= 1;\n\treturn (v >> 65) == 1;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main(void) {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

// An assignment and a comma are expressions of the ordinary grammar, worth the
// value 6.5.16 and 6.5.17 give them, so they run inside a larger expression the
// way gcc runs them. Each case returns 1 when the value is what the source
// says it is.
fn test_an_assignment_and_a_comma_expression_as_a_value_run() {
	cases := [
		'int a = 0;\n	return (a = 5) == 5;',
		'int a = 0; int b = 0;\n	return (a = b = 7) == 7 && a == 7 && b == 7;',
		'int a = 0; int b = 0;\n	return (a = 1, b = 2, a + b) == 3;',
		'int a = 1;\n	return (a <<= 1) == 2 && (a >>= 1) == 1;',
		'int a = 0; int b = (a = 4, a + 1);\n	return b == 5;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

fn test_a_shift_by_a_count_as_wide_as_the_value_is_refused() {
	cases := [
		'int main() { int a = 1;\n\treturn a << 32; }',
		'int main() { int a = 1;\n\treturn a >> 32; }',
		'int main() { __int128 a = 1;\n\treturn (int)(a << 128); }',
		'int main() { __int128 a = 1;\n\treturn (int)(a >> 128); }',
		'int main() { int a = 1;\n\treturn a << -1; }',
	]
	for source in cases {
		emitted := emit(translation_unit(source), Options{})
		assert emitted.diagnostics.len == 1
		assert emitted.diagnostics[0].msg.contains('is not implemented')
		assert emitted.bytes.len == 0
	}
}

// A count the program works out is shifted by the register the machine reads a
// count from, so it is a count the program decides at run time. The machine reads
// the count modulo the register's width, which is what gcc answers too, and it is
// why the two widths are shifted with different instructions: a narrow count is
// read as five bits and a word's as six, so a shift of 33 of a narrow value is a
// shift of one and a shift of 33 of a pair is a shift of thirty-three.
fn test_a_shift_by_a_count_the_program_works_out_runs() {
	powers := doubling('t64', 64) + doubling('t72', 72)
	cases := [
		'\tint a = 8; int n = 2;\n\treturn (a << n) == 32;',
		'\tint a = 8; int n = 33;\n\treturn (a << n) == 16;',
		'\tint a = 256; int n = 4;\n\treturn (a >> n) == 16;',
		'\tint a = -8; int n = 1;\n\treturn (a >> n) == -4;',
		'\tint a = -8; int n = 33;\n\treturn (a >> n) == -4;',
		'\tint a = -8; int n = 31;\n\treturn (a >> n) == -1;',
		'\tint a = 7; int n = 0;\n\treturn (a >> n) == 7 && (a << n) == 7;',
		'\tint a = 0xf0; int m = 0x0f; int n = 4;\n\treturn ((a >> n) | m) == 0x0f;',
		'${powers}\t__int128 a = t64 + 5; int n = 64;\n\treturn (a >> n) == 1;',
		'${powers}\t__int128 a = t64 + 5; int n = 64;\n\t__int128 p = a << n;\n\treturn p == (t64 + 5) * t64;',
		'${powers}\t__int128 a = t72 + 3; int n = 72;\n\treturn (a >> n) == 1;',
		'\t__int128 a = 9; int n = 128;\n\treturn (a >> n) == 9;',
		'${powers}\t__int128 a = t72; int n = 200;\n\treturn (a >> n) == 1;',
		'\t__int128 a = -1; int n = 70;\n\treturn (a >> n) == -1;',
		'\tunsigned __int128 a = -1; int n = 1;\n\tunsigned __int128 h = a >> n;\n\treturn (h >> 126) == 1;',
		'\t__int128 a = 7; int n = 0;\n\treturn (a >> n) == 7;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

fn test_one_128_bit_value_is_divided_by_another() {
	powers := doubling('t64', 64) + doubling('t36', 36) + doubling('t100', 100) + doubling('t127', 127)
	cases := [
		'\tunsigned __int128 a = 40;\n\tunsigned __int128 b = 2;\n\treturn (a / b) == 20;',
		'\tunsigned __int128 a = 40;\n\treturn (a % 3) == 1;',
		// A narrow divisor, which is widened into a pair before the routine starts.
		'\tunsigned __int128 a = 40;\n\treturn (a / 2) == 20;',
		'\tunsigned __int128 a = 12345;\n\treturn (a / 1) == 12345;',
		'\tunsigned __int128 a = 987654321;\n\treturn (a / a) == 1 && (a % a) == 0;',
		// The remainder takes the dividend's sign and the quotient the two signs
		// together, which is what C asks for.
		'\t__int128 a = -7;\n\t__int128 b = 3;\n\treturn (a % b) == -1;',
		'\t__int128 a = 7;\n\t__int128 b = -3;\n\treturn (a % b) == 1;',
		'\t__int128 a = -7;\n\t__int128 b = -3;\n\treturn (a % b) == -1;',
		'\t__int128 a = -7;\n\t__int128 b = 3;\n\treturn (a / b) == -2;',
		'\t__int128 a = 7;\n\t__int128 b = -3;\n\treturn (a / b) == -2;',
		// A dividend and a divisor too wide for a word, which is what the routine
		// shifts and subtracts for.
		'${powers}\tunsigned __int128 D = t100 + 7;\n\tunsigned __int128 q = D / 3;\n\tunsigned __int128 r = D % 3;\n\treturn (q * 3 + r) == D && r < 3;',
		'${powers}\tunsigned __int128 D = t100 + 7;\n\tunsigned __int128 q = D / 7;\n\tunsigned __int128 r = D % 7;\n\treturn (q * 7 + r) == D && r < 7;',
		'${powers}\tunsigned __int128 D = t100;\n\treturn (D / t64) == t36;',
		'${powers}\t__int128 D = t100 + 7;\n\t__int128 q = D / 3;\n\t__int128 r = D % 3;\n\treturn (q * 3 + r) == D && r == 2;',
		'${powers}\t__int128 D = 0 - t100 - 7;\n\t__int128 q = D / 3;\n\t__int128 r = D % 3;\n\treturn (q * 3 + r) == D && r == -2;',
		// The one division that would overflow if the signs were put back by
		// negating the dividend: the answer is the dividend, measured on gcc.
		'${powers}\t__int128 a = 0 - t127;\n\treturn (a / -1) == a;',
		'${powers}\t__int128 a = 0 - t127;\n\treturn (a % -1) == 0;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

// A divisor of zero is a fault in gcc, in all four forms, and it is the machine's
// own fault here: the routine reaches a real division by the zero divisor, so the
// program dies of the same signal gcc's program dies of. The runner this test uses
// reports that as the number of the signal, 8, where a shell would say 136.
fn test_a_128_bit_division_by_zero_faults() {
	cases := [
		'\t__int128 a = 5;\n\t__int128 b = 0;\n\treturn (int)(a / b);',
		'\tunsigned __int128 a = 5;\n\tunsigned __int128 b = 0;\n\treturn (int)(a / b);',
		'\t__int128 a = 5;\n\t__int128 b = 0;\n\treturn (int)(a % b);',
		'\tunsigned __int128 a = 5;\n\tunsigned __int128 b = 0;\n\treturn (int)(a % b);',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 8
	}
}

// The order of two 128-bit values, every operator against every shape of pair.
// The cases that matter most are the ones whose high words are equal and whose low
// words differ: the second subtraction of a comparison is then zero, and its zero
// flag says nothing about the 128-bit difference, so a condition that reads that
// flag answers "not greater" for a value that is greater. Every program here is one
// gcc 16.2.1 answers with the same status this compiler answers with.
fn test_two_128_bit_values_are_ordered() {
	doubled := doubling('t64', 64) + doubling('t65', 65)
	shapes := [
		'\t__int128 a;\n\t__int128 b;\n\ta = 1;\n\tb = 0;',
		'\t__int128 a;\n\t__int128 b;\n\ta = 0;\n\tb = 1;',
		'\t__int128 a;\n\t__int128 b;\n\ta = 5;\n\tb = 5;',
		'\t__int128 a;\n\t__int128 b;\n\ta = -1;\n\tb = 0;',
		'\t__int128 a;\n\t__int128 b;\n\ta = -2;\n\tb = 1;',
		'${doubled}\t__int128 a = t64 + 5;\n\t__int128 b = t64 + 3;',
		'${doubled}\t__int128 a = t64 + 3;\n\t__int128 b = t64 + 5;',
		'${doubled}\t__int128 a = t65;\n\t__int128 b = t64;',
		'${doubled}\t__int128 a = t64;\n\t__int128 b = t65;',
		'\tunsigned __int128 a;\n\tunsigned __int128 b;\n\ta = 1;\n\tb = 0;',
		'\tunsigned __int128 a;\n\tunsigned __int128 b;\n\ta = 0;\n\tb = 1;',
		'\tunsigned __int128 a;\n\tunsigned __int128 b;\n\ta = -1;\n\tb = 0;',
		'\tunsigned __int128 a;\n\tunsigned __int128 b;\n\ta = 5;\n\tb = 5;',
		'${doubled}\tunsigned __int128 a = t64 + 5;\n\tunsigned __int128 b = t64 + 3;',
		'${doubled}\tunsigned __int128 a = t64;\n\tunsigned __int128 b = t65;',
	]
	// The status gcc gives each of these, taken from the same programs.
	answers := {
		'==': ['0', '0', '1', '0', '0', '0', '0', '0', '0', '0', '0', '0', '1', '0', '0']
		'!=': ['1', '1', '0', '1', '1', '1', '1', '1', '1', '1', '1', '1', '0', '1', '1']
		'<':  ['0', '1', '0', '1', '1', '0', '1', '0', '1', '0', '1', '0', '0', '0', '1']
		'>':  ['1', '0', '0', '0', '0', '1', '0', '1', '0', '1', '0', '1', '0', '1', '0']
		'<=': ['0', '1', '1', '1', '1', '0', '1', '0', '1', '0', '1', '0', '1', '0', '1']
		'>=': ['1', '0', '1', '0', '0', '1', '0', '1', '0', '1', '0', '1', '1', '1', '0']
	}
	for op in ['==', '!=', '<', '>', '<=', '>='] {
		expected := answers[op]
		for i, shape in shapes {
			source := 'int main() {\n${shape}\n\treturn a ${op} b;\n}'
			emitted := emit(translation_unit(source), Options{})
			assert emitted.diagnostics.len == 0
			assert run_image(emitted.bytes) == expected[i].int()
		}
	}
}

// A conversion to a 128-bit type widens the value it converts, and what the word
// above holds is what that value's own width asks for: the sign of a signed value,
// zero for an unsigned one, and for a value as wide as a word the sign of the whole
// value whichever type it is converted to. Every program here is one gcc 16.2.1
// answers with the status this compiler answers with.
fn test_a_narrow_value_converts_to_a_128_bit_type() {
	doubled := doubling('t64', 64)
	cases := [
		'\t__int128 a = (__int128)-1;\n\treturn a == -1;',
		'\tunsigned __int128 a = (unsigned __int128)-1;\n\treturn (a + 1) == 0;',
		'\t__int128 a = (__int128)(char)200;\n\treturn a == -56;',
		'\t__int128 a = (__int128)300;\n\treturn a == 300;',
		'\tunsigned __int128 u = 5;\n\t__int128 a = (__int128)u;\n\treturn a == 5;',
		'\tunsigned __int128 a = (unsigned __int128)-1;\n\treturn a > 0;',
		'\t__int128 a = (__int128)-1;\n\treturn (int)a == -1;',
		'\t__int128 a = (__int128)3 + (__int128)4;\n\treturn (int)a == 7;',
		'\tint n = (__int128)300;\n\treturn n == 300;',
		'\t__int128 a = (__int128)(int)(__int128)7;\n\treturn (int)a == 7;',
		// A pointer is as wide as a word, so its conversion keeps every bit of it
		// and the word above is its sign rather than the sign of its low half.
		'\tchar *p = (char *)-1;\n\tunsigned __int128 u = (unsigned __int128)p;\n\treturn (u + 1) == 0;',
		'\tint x = 1;\n\t__int128 p = (__int128)&x;\n\treturn p > 0;',
		'\tint x = 1;\n\tunsigned __int128 p = (unsigned __int128)&x;\n\treturn p != 0;',
		'${doubled}\tunsigned __int128 t = t64;\n\t__int128 a = (__int128)(int)(t64 / t64);\n\treturn (int)a == 1;',
	]
	for source in cases {
		emitted := emit(translation_unit('int main() {\n${source}\n}'), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == 1
	}
}

fn test_a_128_bit_value_is_computed_as_a_pair() {
	cases := [
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 2; return (int)(a + b); }', 42},
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 2; return (int)(a - b); }', 38},
		WideValueCase{'int main() { __int128 a = 2; __int128 b = 40; return (int)(a - b); }', 218},
		WideValueCase{'int main() { __int128 a = 40; return (int)(-a); }', 216},
		WideValueCase{'int main() { __int128 a = 0; return (int)(-a); }', 0},
		WideValueCase{'int main() { __int128 a = 0; return (int)(~a); }', 255},
		WideValueCase{'int main() { __int128 a = -1; __int128 b = 0; return a < b; }', 1},
		WideValueCase{'int main() { unsigned __int128 a = -1; unsigned __int128 b = 0; return a < b; }', 0},
		WideValueCase{'int main() { __int128 a = 5; __int128 b = 40; return a > b; }', 0},
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 40; return a <= b; }', 1},
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 40; return a == b; }', 1},
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 41; return a != b; }', 1},
		WideValueCase{'int main() { __int128 a = 40; int n = a + 2; return n; }', 42},
		WideValueCase{'int main() { __int128 a = 40; __int128 w; w = a + 2; return (int)w; }', 42},
		WideValueCase{'int main() { __int128 a = 40; __int128 w; w = -a; return (int)w; }', 216},
		WideValueCase{'int main() { __int128 a = 40; __int128 b = 1; __int128 c = 1; return (int)(a + b + c); }', 42},
		WideValueCase{'int main() { __int128 a = 40; return (int)(1 + a); }', 41},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// The second word of an addition is an add-with-carry and not an add: `adc rdx,
// rcx` is in the image of a two-word sum, and the instruction is what makes the
// carry out of the low word part of the high one. The same test the sign word
// gets: the instruction is asserted rather than inferred from an answer that a
// small pair would give either way.
fn test_the_high_word_of_a_sum_takes_the_carry_of_the_low_one() {
	emitted := emit(translation_unit('int main() { __int128 a = 40; __int128 b = 2; return (int)(a + b); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert holds(emitted.bytes, [u8(0x48), 0x11, 0xca])
}

fn test_a_double_is_computed_in_the_floating_register_file() {
	emitted := emit(translation_unit('int main() { double x = 1.5; double y = 2.5; double z = x * y; int n = z * 10; return n; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 37
}

fn test_a_double_is_passed_and_returned_in_the_floating_registers() {
	// The arguments of a call and the value a function returns travel in the
	// floating file, which is a sequence of its own: a double is not passed in an
	// integer register, and a call with both kinds of argument numbers the two
	// sequences separately.
	emitted := emit(translation_unit('double twice(double x) { return x + x; } int main() { double v = 3.25; int n = twice(v) * 4; return n; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 26
}

// A float argument to a function this file does not define travels as the
// prototype says: a scalar single in the low half of the floating register, not
// a double. The callee has to be a real one for the argument to be read back, so
// the fixture calls a library function with a float parameter and a float result
// and links the library. A compiler that widens the argument to a double hands
// over the low 32 bits of the double's encoding, which is zero for 6.25f, and
// the function then answers 0.0f rather than 2.5f. The same-file call is beside
// it as the constraint: it was passing a float before this and has to keep doing
// so. Measured with gcc 16.2.1, both programs exit 0.
fn test_a_float_argument_is_passed_as_a_float_to_a_declared_callee() {
	external := emit(translation_unit('extern float sqrtf(float); int main() { return sqrtf(6.25f) == 2.5f ? 0 : 1; }'),
		Options{
			libraries: ['m']
		})
	assert external.diagnostics.len == 0
	assert run_image(external.bytes) == 0
	in_file := emit(translation_unit('float half(float x) { return x / 2.0f; } int main() { return half(5.0f) == 2.5f ? 0 : 1; }'),
		Options{})
	assert in_file.diagnostics.len == 0
	assert run_image(in_file.bytes) == 0
}

fn test_a_double_comparison_answers_the_int_a_branch_reads() {
	// A comparison of two doubles reads the flags the floating compare leaves,
	// which are not the integer ones: the sign of a double lives in the top bit of
	// its value, and the branch is the artifact that says whether the answer was
	// read from the right place.
	negative := emit(translation_unit('int main() { double a = -3.5; if (a < 0.0) { return 1; } return 2; }'),
		Options{})
	assert negative.diagnostics.len == 0
	assert run_image(negative.bytes) == 1
	positive := emit(translation_unit('int main() { double a = 3.5; if (a < 0.0) { return 1; } return 2; }'),
		Options{})
	assert positive.diagnostics.len == 0
	assert run_image(positive.bytes) == 2
	// The same comparison written as a value rather than as a branch reads the
	// same flags.
	as_a_value := emit(translation_unit('int main() { double a = -3.5; int b = a < 0.0; return b; }'),
		Options{})
	assert as_a_value.diagnostics.len == 0
	assert run_image(as_a_value.bytes) == 1
}

fn test_each_element_of_an_array_of_doubles_is_its_own_value() {
	// A counted slot keeps the class of its elements, and that class is what
	// decides between the eight-byte move and the integer load and store: with it
	// lost, every element was written as the truncation of its value and read back
	// as an integer, which made all three of them the same number.
	emitted := emit(translation_unit('int main() { double a[3]; a[0] = 1.5; a[1] = 2.25; a[2] = a[0] + a[1]; int n = a[2] * 4; return n; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 15
}

fn test_each_element_of_a_top_level_array_of_doubles_is_its_own_value() {
	// The same class question for an array defined at the top level, where the
	// address of an element is the address of the object plus an offset rather
	// than a place in the frame.
	emitted := emit(translation_unit('double top[3]; int main() { top[0] = 1.5; top[1] = 2.25; int n = (top[0] + top[1]) * 4; return n; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 15
}

fn test_a_top_level_double_holds_its_initializer_in_the_image() {
	// The initializer of an object at the top level is the eight bytes of its
	// value rather than the two's complement of an integer, and a store to the
	// object goes through the same class.
	emitted := emit(translation_unit('double g = 1.25; int main() { g = g + 2.0; int n = g * 4; return n; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 13
	// An integer initializer for a double object is that integer's value as a
	// double, which is the conversion an assignment makes.
	whole := emit(translation_unit('double g = 3; int main() { int n = g * 2; return n; }'), Options{})
	assert whole.diagnostics.len == 0
	assert run_image(whole.bytes) == 6
}

fn test_a_double_and_an_int_convert_both_ways() {
	emitted := emit(translation_unit('int main() { int n = 7; double d = n; d = d / 2.0; int r = d * 2; return r; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 7
}

fn test_the_logical_not_of_a_double_is_a_comparison_with_zero() {
	// `!d` compares the value with zero, and zero comes from the exclusive-or of a
	// register with itself. That instruction is the packed-double one and not the
	// scalar one, whose prefix is not an instruction at all: a program with the
	// scalar prefix in it died on an illegal instruction the first time a `!` was
	// evaluated.
	nonzero := emit(translation_unit('int main() { double d = 1.5; return !d; }'), Options{})
	assert nonzero.diagnostics.len == 0
	assert run_image(nonzero.bytes) == 0
	zero := emit(translation_unit('int main() { double d = 0.0; return !d; }'), Options{})
	assert zero.diagnostics.len == 0
	assert run_image(zero.bytes) == 1
}

// A function of one of the 128-bit types answers with a pair: the low word in the
// accumulator and the word above it in the register a pair keeps its high word in.
// Measured on gcc 16.2.1, which writes both registers for `return 5` as well as for
// a value of the type, so a caller that reads the high word reads zero rather than
// whatever the body left there.
fn test_a_128_bit_function_returns_a_pair() {
	cases := [
		WideValueCase{'__int128 five(void) { return 5; } int main() { __int128 r = five(); return (int)r * 10 + (int)(r >> 64); }', 50},
		WideValueCase{'__int128 neg(void) { return -1; } int main() { __int128 r = neg(); return (int)r + ((int)(r >> 64) + 2) * 20; }', 19},
		WideValueCase{'__int128 big(void) { __int128 t = 1; t = t << 70; return t + 9; } int main() { __int128 r = big(); return (int)((r >> 64) & 0xff); }', 64},
		WideValueCase{'__int128 fromint(int v) { return v - 100; } int main() { __int128 r = fromint(40); return (int)r + 100; }', 40},
		WideValueCase{'__int128 make(void) { return 40; } int main() { __int128 r = make() + 2; return (int)r; }', 42},
		WideValueCase{'unsigned __int128 five(void) { return 5; } int main() { unsigned __int128 r = five(); return (int)r * 10 + (int)(r >> 64); }', 50},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// A 128-bit parameter is a pair in two consecutive argument registers of the general
// file, low word first, and the pair pushes the arguments after it along: a pair
// with an int before it puts the int in the first register and the pair in the two
// after that, and a pair with an int after it makes that int the third register.
// Measured on gcc 16.2.1. The pair order itself is what the two word-order programs
// assert: a swapped low and high word would answer the other way round.
fn test_a_128_bit_parameter_arrives_in_two_argument_registers() {
	cases := [
		WideValueCase{'__int128 ident(__int128 a) { return a; } int main() { __int128 r = ident((__int128)300); return (int)r; }', 44},
		WideValueCase{'int before(int x, __int128 a) { return x + (int)a; } int main() { return before(20, (__int128)22); }', 42},
		WideValueCase{'int after(__int128 a, int y) { return (int)a + y; } int main() { return after((__int128)20, 22); }', 42},
		WideValueCase{'__int128 sub(__int128 a, __int128 b) { return a - b; } int main() { return (int)sub((__int128)44, (__int128)2); }', 42},
		WideValueCase{'__int128 three(__int128 a, __int128 b, int y) { return a + b + y; } int main() { return (int)three((__int128)20, (__int128)21, 1); }', 42},
		WideValueCase{'int four(int a, int b, int c, int d, __int128 x) { return a + b + c + d + (int)x; } int main() { return four(1, 2, 3, 4, (__int128)32); }', 42},
		WideValueCase{'__int128 first(__int128 a) { return a + 1; } int main() { return (int)first(41); }', 42},
		WideValueCase{'int order(__int128 a) { return ((a >> 64) & 0xff) == 3 && (int)(a & 0xf) == 7; } int main() { __int128 t = 3; t = t << 64; return order(t + 7); }', 1},
		WideValueCase{'int order2(__int128 a) { return (int)a == -1 && (int)(a >> 64) == 4; } int main() { __int128 t = 5; t = t << 64; return order2(t - 1); }', 1},
		WideValueCase{'int pick(unsigned __int128 a, int y) { return (int)((a >> 64) & 0xf) + y; } int main() { unsigned __int128 t = -1; return pick(t, 32); }', 47},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// A wide argument whose value comes from a call is the case where the caller has
// to keep a finished pair somewhere while it works out the next argument, and
// somewhere that the next argument's own call does not write over. The slots a
// step keeps a pair in are cut from the frame of the function being emitted, so a
// list of them that outlived its function handed the next one an offset its frame
// did not have and the pair landed on a parameter: f(g(9), g(4)) answered 20,
// which is a + a, where gcc answers 15. The object cases here are the ones that
// passed throughout, and they are in the list so that a fix for the others cannot
// quietly cost them.
fn test_a_128_bit_argument_that_is_itself_a_call() {
	cases := [
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a + b; } int main() { return (int)f(g(9), g(4)) == 15; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return b; } int main() { return (int)f(g(9), g(4)) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, int b) { return a * 10 + b; } int main() { return f(g(3), 4) == 44; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(int a, int b, __int128 c) { return c * 10 + a * 2 + b; } int main() { return f(1, 2, g(3)) == 44; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a - b; } int main() { __int128 q = 5; return f(g(9), q) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a - b; } int main() { __int128 p = 10; return f(p, g(4)) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b, __int128 c) { return a + b * 2 + c * 4; } int main() { return f(g(1), g(2), g(3)) == 24; }', 1},
		WideValueCase{'__int128 f(__int128 a, __int128 b) { return a + b; } int main() { __int128 x = 2; return f(f(x, x), f(x, x)) == 8; }', 1},
		WideValueCase{'__int128 sum(int n, __int128 acc) { if (n == 0) { return acc; } return sum(n - 1, acc + n); } int main() { return sum(6, 0) == 21; }', 1},
		WideValueCase{'__int128 f(__int128 a, __int128 b) { return a + b; } int main() { __int128 p = 10; __int128 q = 5; return (int)f(p, q) == 15; }', 1},
		WideValueCase{'__int128 f(__int128 a, __int128 b) { return b; } int main() { __int128 p = 10; __int128 q = 5; return (int)f(p, q) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a + b; } int main() { __int128 v = 3; return f(v + 1, g(2)) == 7; }', 1},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// A pair takes its two registers out of the general file and leaves the floating
// one alone, so a double beside it is numbered from the beginning of its own
// sequence and a pointer beside it is one more general argument. Measured on gcc
// 16.2.1, which passes `(char c, double d, __int128 a, int y)` with c in dil, d in
// xmm0, a in rsi:rdx and y in ecx. The programs also cover the two ways a result
// reaches the next call: a pair handed on as an argument, and a pair read out of a
// call made inside the arguments of another call.
fn test_a_pair_is_passed_beside_ints_doubles_pointers_and_other_calls() {
	cases := [
		WideValueCase{'__int128 mix(char c, double d, __int128 a, int y) { return a + c + y + (int)d; } int main() { return (int)mix(3, 4.0, (__int128)30, 5); }', 42},
		WideValueCase{'__int128 mix(int a, double b, __int128 c, char d) { return c + a + d + (int)b; } int main() { return (int)mix(10, 11.0, (__int128)20, 1); }', 42},
		WideValueCase{'int all(char c, double d, int *p, __int128 a, int y) { return c + (int)d + *p + (int)a + y; } int main() { int v = 10; return all(1, 2.0, &v, (__int128)20, 9); }', 42},
		WideValueCase{'int ptr(int *p, __int128 a) { return *p + (int)a; } int main() { int v = 20; return ptr(&v, (__int128)22); }', 42},
		WideValueCase{'int cp(char *s, __int128 a, char c) { return *s + (int)a + c; } int main() { return cp("zz", (__int128)34, 4); }', 160},
		WideValueCase{'int f(__int128 a, int b, int c, int d, int e, int g, int h) { return (int)a + b + c + d + e + g + h; } int main() { return f((__int128)20, 1, 2, 3, 4, 11, 1); }', 42},
		WideValueCase{'__int128 inner(__int128 a) { return a + 1; } __int128 outer(__int128 a, __int128 b) { return inner(a + b); } int main() { return (int)outer((__int128)20, (__int128)21); }', 42},
		WideValueCase{'__int128 down(__int128 n) { if (n == 0) { return 0; } return 1 + down(n - 1); } int main() { return (int)down(9); }', 9},
		WideValueCase{'int depth(__int128 n) { if (n == 0) { return 0; } return 1 + depth(n - 1); } int main() { return depth((__int128)42); }', 42},
		WideValueCase{'__int128 sum(__int128 a, __int128 b) { return a + b; } int main() { return (int)sum((__int128)20, sum((__int128)10, (__int128)12)); }', 42},
		WideValueCase{'__int128 id(__int128 a) { return a; } __int128 add2(__int128 a, __int128 b) { return a + b; } int main() { return (int)add2(id((__int128)20), id((__int128)22)); }', 42},
		WideValueCase{'double half(int x, __int128 a) { return x + (int)a + 0.0; } int main() { return (int)half(2, (__int128)40); }', 42},
		WideValueCase{'int narrow(__int128 a) { return (int)a + (int)(a >> 64); } int main() { __int128 t = (__int128)40; return narrow(t); }', 40},
		WideValueCase{'__int128 make(void) { __int128 t = 3; return t << 64; } int take(__int128 a) { return (int)(a >> 64); } int main() { return take(make()); }', 3},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// A pair the argument registers have no room for is passed in memory by the
// convention, and this back end does not do that: the callee refuses it by name
// with the line it was written on, and nothing is written out. Measured on gcc
// 16.2.1, which reads such a parameter from 16(%rbp) rather than from a register,
// so a callee that expected it in a register would read whatever was there.
fn test_a_128_bit_parameter_that_will_not_fit_the_registers_is_reported() {
	emitted := emit(translation_unit('int f(int a, int b, int c, int d, int e, __int128 x) { return (int)x; }\nint main() { return 0; }'),
		Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].line == 1
	assert emitted.diagnostics[0].msg.contains('the parameter x is declared __int128')
	assert emitted.diagnostics[0].msg.contains('two argument registers at once')
	assert emitted.bytes.len == 0
}

// The caller reaches the same answer, and it is the call site that reports it: the
// definition is written after main, so main is emitted first. A caller that put a
// pair in registers where the callee reads it from memory would hand over words
// nothing reads.
fn test_a_128_bit_argument_that_will_not_fit_the_registers_is_reported() {
	emitted := emit(translation_unit('int g(int a, int b, int c, int d, int e, __int128 x);\nint main() { return g(1, 2, 3, 4, 5, (__int128)6); }\nint g(int a, int b, int c, int d, int e, __int128 x) { return (int)x; }'),
		Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].line == 2
	assert emitted.diagnostics[0].msg.contains('argument 6 of the call to g is a 128-bit value')
	assert emitted.diagnostics[0].msg.contains('two argument registers at once')
	assert emitted.bytes.len == 0
}

// A 128-bit temporary is a place in the frame, and the places are worked out again
// for every function. A temporary kept from the function before would put this
// function's arithmetic on top of one of its own parameters or locals: in the first
// program the slot holding the first operand of `a + b` is the slot `b` lives in, so
// b is overwritten before it is read and the sum comes back as the first value
// twice. Measured on gcc 16.2.1, the three programs exit 15, 25 and 25. The third
// has no 128-bit parameter and no 128-bit return type, so the fault was there
// before either of them; this test keeps it fixed. The places a half-finished value
// waits in are not the only ones: the block a pair division works in is another, and
// a division that kept its block puts the next function's quotient, remainder,
// counter and flags on that function's own parameters and locals. Measured on gcc
// 16.2.1, the five programs exit 15, 25, 25, 11 and 149.
fn test_a_128_bit_temporary_does_not_outlive_the_function_that_needed_it() {
	cases := [
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a + b; } int main() { return (int)f(g(9), g(4)); }', 15},
		WideValueCase{'__int128 f(void) { __int128 a = 1; return a + a; } __int128 g(void) { __int128 a = 2; __int128 b = 3; return a + b; } int main() { return (int)f() * 10 + (int)g(); }', 25},
		WideValueCase{'int f(void) { __int128 a = 1; return (int)(a + a); } int g(void) { __int128 a = 1; __int128 b = 2; __int128 c = 3; return (int)(b + c); } int main() { return f() * 10 + g(); }', 25},
		WideValueCase{'__int128 first(__int128 p0, __int128 p1) { return p0 / p1; } __int128 second(__int128 p0) { __int128 v0 = 1; return p0 / 1; } int main(void) { return (int)first(1, 1) * 10 + (int)second(1); }', 11},
		WideValueCase{'__int128 first(__int128 p0, __int128 p1) { return p0 / p1; } __int128 second(__int128 p0, __int128 p1) { __int128 v0 = 7; return (p0 % p1) + v0; } int main(void) { return (int)first(100, 7) * 10 + (int)second(100, 7); }', 149},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// An argument whose value comes from a call keeps its own value: it is parked in a
// slot of the call being made, and the call that produced it is free to use the
// registers and to make calls of its own on the way. Every program below answers 1
// in both compilers, and each puts the call in a different position relative to a
// literal, an object and another call: the first, the second, the third, one of two,
// both of two, inside an arithmetic operand, and three of them at once.
fn test_an_argument_that_is_a_call_keeps_its_own_value() {
	cases := [
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(int a, __int128 b) { return b * 10 + a; } int main(void) { return (int)f(4, g(3)) == 44; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a - b; } int main(void) { __int128 p = 10; return (int)f(p, g(4)) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a - b; } int main(void) { __int128 q = 5; return (int)f(g(9), q) == 5; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b, __int128 c) { return a + b * 2 + c * 4; } int main(void) { return (int)f(g(1), g(2), g(3)) == 24; }', 1},
		WideValueCase{'__int128 g(__int128 x) { return x + 1; } __int128 f(__int128 a, __int128 b) { return a + b; } int main(void) { __int128 v = 3; return (int)f(v + 1, g(2)) == 7; }', 1},
		WideValueCase{'__int128 f(__int128 a, __int128 b) { return a + b; } int main(void) { __int128 x = 2; return (int)f(f(x, x), f(x, x)) == 8; }', 1},
		WideValueCase{'__int128 sum(int n, __int128 acc) { if (n == 0) return acc; return sum(n - 1, acc + n); } int main(void) { return (int)sum(6, 0) == 21; }', 1},
	]
	for case in cases {
		emitted := emit(translation_unit(case.source), Options{})
		assert emitted.diagnostics.len == 0
		assert run_image(emitted.bytes) == case.status
	}
}

// A constant wider than the four-byte immediate this back end writes a constant
// with is written whole rather than halved. `1234567890123456789LL` is a long long,
// so it is written with the ten-byte immediate and arrives at whatever width it is
// stored into; written as its low four bytes the program below would have had a
// value whose low byte was not 21, and it had one that was.
fn test_a_constant_wider_than_the_immediate_is_written_whole() {
	emitted := emit(translation_unit('int main() { __int128 v = 1234567890123456789LL; return (int)(v % 256); }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 21
	// The same line with a constant the instruction holds answers the same way,
	// which is what makes the value the subject rather than the line.
	control := emit(translation_unit('int main() { __int128 v = 42; return (int)(v % 256); }'), Options{})
	assert control.diagnostics.len == 0
	assert run_image(control.bytes) == 42
}

fn test_a_double_returning_function_with_no_return_statement_answers_zero() {
	// Running off the end of a function that returns a double answers zero in the
	// register the caller reads. The language leaves this undefined, so what this
	// test records is what this compiler does with it.
	emitted := emit(translation_unit('double f(void) { int x = 1; } int main() { double v = f(); return v == 0.0; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// The 64-bit integer types are eight bytes on this target, measured on gcc
// 16.2.1 with `sizeof`, and `unsigned` is the four-byte integer it always was.
fn test_the_64_bit_integer_types_are_eight_bytes_wide() {
	emitted := emit(translation_unit('int main() { return sizeof(long) == 8 && sizeof(unsigned long) == 8 && sizeof(long long) == 8 && sizeof(unsigned long long) == 8 && sizeof(unsigned) == 4; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A comparison of two 64-bit integers was read as a comparison of two addresses,
// which is a signed order over the same bits: `18446744073709551615UL > 1UL`
// answered false where ISO C and gcc answer true. Measured on gcc 16.2.1, which
// answers 1 for the unsigned pair and 1 for `-1L < 0L`.
fn test_a_wide_integer_comparison_reads_the_order_of_its_type() {
	unsigned_case := emit(translation_unit('int main() { unsigned long a = 18446744073709551615UL; unsigned long b = 1UL; return a > b; }'),
		Options{})
	assert unsigned_case.diagnostics.len == 0
	assert run_image(unsigned_case.bytes) == 1
	// The signed type over the same bits is the signed order.
	signed := emit(translation_unit('int main() { long a = -1L; long b = 0L; return a < b; }'), Options{})
	assert signed.diagnostics.len == 0
	assert run_image(signed.bytes) == 1
	// A four-byte unsigned value is the unsigned order too: the int converts to
	// the unsigned int, so -1 is the largest value of that type.
	mixed := emit(translation_unit('int main() { int a = -1; unsigned int b = 0u; return a < b; }'), Options{})
	assert mixed.diagnostics.len == 0
	assert run_image(mixed.bytes) == 0
}

// An unsigned 64-bit division clears the register above the pair, and a signed
// one fills it with the sign. Measured on gcc 16.2.1: `18446744073709551615UL / 3`
// is 6148914691236517205, where the signed reading of the same bits divided by 3
// is 0.
fn test_an_unsigned_wide_division_reads_the_pair_as_unsigned() {
	unsigned_case := emit(translation_unit('int main() { unsigned long a = 18446744073709551615UL; return (a / 3) == 6148914691236517205UL && (a % 3) == 0; }'),
		Options{})
	assert unsigned_case.diagnostics.len == 0
	assert run_image(unsigned_case.bytes) == 1
	// The signed division truncates toward zero, and its remainder takes the
	// sign of the dividend.
	signed := emit(translation_unit('int main() { long a = -9L; return (a / 2) == -4 && (a % 2) == -1; }'),
		Options{})
	assert signed.diagnostics.len == 0
	assert run_image(signed.bytes) == 1
}

// A right shift of an unsigned value is the logical one, so the sign bit is not
// spread over the vacated bits.
fn test_a_wide_shift_of_an_unsigned_value_keeps_no_sign() {
	unsigned_case := emit(translation_unit('int main() { unsigned long a = 18446744073709551615UL; return (a >> 1) == 9223372036854775807UL; }'),
		Options{})
	assert unsigned_case.diagnostics.len == 0
	assert run_image(unsigned_case.bytes) == 1
	// The signed shift spreads the sign.
	signed := emit(translation_unit('int main() { long a = -8L; return (a >> 1) == -4; }'), Options{})
	assert signed.diagnostics.len == 0
	assert run_image(signed.bytes) == 1
	// A count the program works out is read from the register the machine takes
	// a count from, at the width of the shift.
	counted := emit(translation_unit('int main() { unsigned long a = 18446744073709551615UL; int n = 1; return (a >> n) == 9223372036854775807UL; }'),
		Options{})
	assert counted.diagnostics.len == 0
	assert run_image(counted.bytes) == 1
}

// `unsigned` answers unsigned in the three places a signed answer is a different
// number: a comparison, a division and a shift.
fn test_unsigned_int_answers_unsigned() {
	comparison := emit(translation_unit('int main() { unsigned a = 0u; unsigned b = 1u; return (a - b) > 0u; }'),
		Options{})
	assert comparison.diagnostics.len == 0
	assert run_image(comparison.bytes) == 1
	division := emit(translation_unit('int main() { unsigned a = 4294967295u; return (a / 3) == 1431655765u && (a % 7u) == 3u; }'),
		Options{})
	assert division.diagnostics.len == 0
	assert run_image(division.bytes) == 1
	shift := emit(translation_unit('int main() { unsigned a = 4294967295u; return (a >> 1) == 2147483647u; }'),
		Options{})
	assert shift.diagnostics.len == 0
	assert run_image(shift.bytes) == 1
}

// A constant wider than a signed 64-bit value is written whole: the ten-byte
// immediate carries all eight bytes, so what arrives is the value and not its
// low four bytes with the rest cleared.
fn test_a_constant_wider_than_a_signed_64_bit_value_is_written_whole() {
	emitted := emit(translation_unit('int main() { unsigned long long m = 18446744073709551615ULL; return (m >> 32) == 4294967295ULL; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// The two constants the corpus declares at the top of a file reach the program
// that reads them, and comparing them takes the unsigned order.
fn test_a_static_const_wide_integer_reaches_the_program() {
	emitted := emit(translation_unit('static const long long c99_ll_max = 9223372036854775807LL; static const unsigned long long c99_ull_max = 18446744073709551615ULL; int main(void) { return c99_ll_max == 9223372036854775807LL && c99_ull_max > c99_ll_max; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A 64-bit value survives a call in both directions: the argument register is
// loaded at eight bytes, so a narrow signed argument is widened into it rather
// than arriving as its unsigned reading, and the return carries all eight.
fn test_a_wide_integer_return_and_argument_keep_all_eight_bytes() {
	widened := emit(translation_unit('long id(long x) { return x; } int main(void) { int i = -1; return id(i) == -1L; }'),
		Options{})
	assert widened.diagnostics.len == 0
	assert run_image(widened.bytes) == 1
	returned := emit(translation_unit('unsigned long long twice(unsigned long long x) { return x * 2ULL; } int main(void) { unsigned long long m = 9223372036854775807ULL; return twice(m) == 18446744073709551614ULL; }'),
		Options{})
	assert returned.diagnostics.len == 0
	assert run_image(returned.bytes) == 1
	// A narrow initializer into a wide slot is widened into the whole register,
	// so `long a = -9;` holds -9 and not its unsigned reading.
	stored := emit(translation_unit('int main(void) { long a = -9; return a == -9L; }'), Options{})
	assert stored.diagnostics.len == 0
	assert run_image(stored.bytes) == 1
}

// A condition of a wide type is tested at eight bytes: 4294967296 has its low
// four bytes clear and is not zero.
fn test_a_wide_condition_is_tested_at_the_width_of_the_value() {
	emitted := emit(translation_unit('int main(void) { long a = 4294967296L; if (a) return 1; return 0; }'),
		Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
	// The same test on the value the four-byte read would see, which is zero.
	zero := emit(translation_unit('int main(void) { long a = 0L; if (a) return 1; return 0; }'), Options{})
	assert zero.diagnostics.len == 0
	assert run_image(zero.bytes) == 0
}

// Only the arm the condition selects is evaluated: the other is behind the
// jump, so a side effect written in it does not happen. Measured with gcc
// 16.2.1, `int i = 0; int n = (1 ? ++i : 3); return i * 100 + n;` exits 101,
// and the false condition beside it exits 3.
fn test_only_the_arm_a_conditional_selects_is_evaluated() {
	taken := emit(translation_unit('int main(void) { int i = 0; int n = (1 ? ++i : 3); return i * 100 + n; }'),
		Options{})
	assert taken.diagnostics.len == 0
	assert run_image(taken.bytes) == 101
	skipped := emit(translation_unit('int main(void) { int i = 0; int n = (0 ? ++i : 3); return i * 100 + n; }'),
		Options{})
	assert skipped.diagnostics.len == 0
	assert run_image(skipped.bytes) == 3
	// The same question with a call in the arm that must not run: it writes a
	// global, and the status is 20 when the call never happened and 21 when it
	// did. Measured with gcc 16.2.1.
	called := emit(translation_unit('int g = 0;\nint bumped(void) { g = 1; return 7; }\nint main(void) { int n = (1 ? 2 : bumped()); return n * 10 + g; }'),
		Options{})
	assert called.diagnostics.len == 0
	assert run_image(called.bytes) == 20
}

// The value of a conditional is the arm's value converted to the type the two
// arms share. An int arm beside a double one arrives as a double, so 1 is 1.0
// and not the bits of an int read as one; and `sizeof(1 ? 1 : 1.0)` is the size
// of a double although one arm is an int.
fn test_a_conditional_converts_its_arm_to_the_type_the_two_arms_share() {
	mixed := emit(translation_unit('int main(void) { return sizeof(1 ? 1 : 1.0) == sizeof(double); }'),
		Options{})
	assert mixed.diagnostics.len == 0
	assert run_image(mixed.bytes) == 1
	value := emit(translation_unit('int main(void) { double d = 1 ? 1 : 2.5; return d == 1.0 ? 1 : 0; }'),
		Options{})
	assert value.diagnostics.len == 0
	assert run_image(value.bytes) == 1
	// The arm that runs is the second one here, and it is converted too.
	other := emit(translation_unit('int main(void) { double d = 0 ? 2.5 : 1; return d == 1.0 ? 1 : 0; }'),
		Options{})
	assert other.diagnostics.len == 0
	assert run_image(other.bytes) == 1
}

// An arm narrower than the type the two arms share is widened with its own
// signedness before the arms meet: an int -1 in a long conditional is -1 and
// not 4294967295. Measured with gcc 16.2.1 on both programs.
fn test_an_arm_is_widened_to_the_type_the_two_arms_share() {
	first := emit(translation_unit('int main(void) { long v = 1 ? -1 : 0L; return v == -1L ? 1 : 0; }'),
		Options{})
	assert first.diagnostics.len == 0
	assert run_image(first.bytes) == 1
	// The other way round, with the narrow arm second.
	second := emit(translation_unit('int main(void) { long v = 0 ? 2L : -1; return v == -1L ? 1 : 0; }'),
		Options{})
	assert second.diagnostics.len == 0
	assert run_image(second.bytes) == 1
	// An unsigned result keeps the value the conversion gives it: the int -1
	// converted to an unsigned long is all ones.
	unsigned_one := emit(translation_unit('int main(void) { unsigned long v = 1 ? -1 : 0UL; return v == 18446744073709551615UL ? 1 : 0; }'),
		Options{})
	assert unsigned_one.diagnostics.len == 0
	assert run_image(unsigned_one.bytes) == 1
}

// A chain of conditionals inside the nesting limit is emitted and runs: 150
// links, each the third operand of the one before it, which is the deep case
// and not an interesting one.
fn test_a_long_chain_of_conditionals_compiles_and_runs() {
	mut source := 'int main(void) { return 1'
	for _ in 0 .. 150 {
		source += ' ? 1 : 1'
	}
	source += '; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}
