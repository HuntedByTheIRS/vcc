module parser

import ast
import tokenize

// The streams these tests parse are what a preprocessor hands the parser:
// glibc's stdio.h with its directives already handled, then the program the
// header was included from. The declaration shapes below are the ones that
// stream uses, because they are what the first milestone has to consume
// without a diagnostic.

fn declarations_of(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// stdio_shaped is a header in the shape tcc's own preprocessed output has: a
// typedef of each kind, a forward tag, struct bodies whose members the compiler
// cannot keep yet, the prototype spellings a system header uses, and the
// program the header was included from.
const stdio_shaped = '# 1 "stdio.h" 1
typedef unsigned long size_t;
typedef long ssize_t;
typedef struct { int __val[2]; } __fsid_t;
typedef struct
{
  int __count;
  union
  {
    unsigned int __wch;
    char __wchb[4];
  } __value;
} __mbstate_t;
struct _IO_FILE;
struct _IO_FILE
{
  int _flags;
  char *_IO_read_ptr;
  int _flags2:24;
  char _shortbuf[1];
  unsigned short _cur_column;
  signed char _vtable_offset;
  struct _IO_marker *_markers;
  char _unused2[12 * sizeof (int) - 5 * sizeof (void *)];
};
typedef __ssize_t cookie_read_function_t (void *__cookie, char *__buf,
                                          size_t __nbytes);
extern FILE *stdin;
extern int remove (const char *__filename) ;
extern FILE *tmpfile (void)
    ;
extern char *tmpnam (char[20])  ;
extern int fprintf (FILE *restrict __stream,
                    const char *restrict __format, ...) ;
extern char *tmpnam_r (char __s[20])  ;
extern size_t fread (void *__restrict __ptr, size_t __size,
                     size_t __n, FILE *__restrict __stream)
  ;
__extension__ typedef unsigned long long __u_quad_t;
extern int snprintf (char *restrict __s, size_t __maxlen,
                     const char *restrict __format, ...)
      __attribute__ ((__format__ (__printf__, 3, 4)));
extern int fscanf (FILE *restrict __stream, const char *restrict __format, ...) __asm__("__isoc99_fscanf")  ;
extern int __uflow (FILE *);
extern int puts (const char *__s) ;
# 2 "hello.c" 2
int main() {
  puts("Hello, world!");
  return 0;
}
'

fn test_the_stdio_shaped_stream_parses_with_no_diagnostics() {
	result := declarations_of(stdio_shaped)
	assert result.diagnostics.len == 0
	mut definition := ?ast.FnDecl(none)
	mut names := []string{}
	for decl in result.unit.decls {
		names << decl.name
		if decl.name == 'main' {
			definition = decl
		}
	}
	main := definition or {
		assert false
		return
	}
	assert main.ret == 'int'
	assert main.body.len == 2
	// The prototypes are kept, because the declaration is what names the
	// function whether or not this file defines it.
	assert 'remove' in names
	assert 'tmpfile' in names
	// The declaration of puts is kept as well, and the call is read against it:
	// a call to a name nothing in the unit declares is refused once the whole
	// unit has been read, which is what the stream a preprocessor writes for
	// `#include <stdio.h>` carries this prototype for.
	assert 'puts' in names
	// The types and the object are read and dropped: neither adds code.
	assert 'stdin' !in names
	assert 'cookie_read_function_t' !in names
	assert '__mbstate_t' !in names
}

fn test_a_prototype_keeps_its_return_type_as_written() {
	result := declarations_of('extern FILE *tmpfile (void); extern __ssize_t getdelim (char **restrict __lineptr, size_t __n, int __delimiter, FILE *__stream); int main() { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 3
	assert result.unit.decls[0].name == 'tmpfile'
	assert result.unit.decls[0].ret == 'FILE *'
	assert result.unit.decls[0].body.len == 0
	assert result.unit.decls[1].name == 'getdelim'
	assert result.unit.decls[1].ret == '__ssize_t'
}

fn test_a_typedef_name_is_a_type_for_the_rest_of_the_file() {
	result := declarations_of('typedef unsigned long size_t; size_t span (const char *__s); int main() { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 2
	assert result.unit.decls[0].name == 'span'
	// The return type is spelled as the type the name stands for, because the
	// value a function returns is sized from that spelling. A prototype promises
	// rather than defines, so nothing is refused here; what is kept is the type
	// the emitter would be handed if the function were defined.
	assert result.unit.decls[0].ret == 'unsigned long'
}

fn test_an_extern_object_is_read_and_dropped() {
	result := declarations_of('extern FILE *stdout;')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 0
}

// A brace initializer is a definition even when the declaration says extern:
// the object has to live somewhere, and the values written are the ones the
// image holds. Measured with gcc 16.2.1 and this compiler, `int x[2] = {1, 2};`
// returns 3 when the program reads a[0] + a[1].
fn test_a_file_scope_brace_initializer_lays_out_the_values_it_wrote() {
	result := declarations_of('extern int table[4] = { 1, 2, 3, 4 };')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	global := result.unit.globals[0]
	assert global.count == 4
	assert global.inits.len == 4
	assert global.inits[0] == 1 && global.inits[3] == 4
}

// A list is what an array with empty brackets is as long as: measured on gcc
// 16.2.1, `int x[] = {1, 2, 3};` declares x with three elements and the program
// returns 3 when it reads x[2].
fn test_a_file_scope_list_gives_an_empty_bracket_array_its_size() {
	result := declarations_of('int x[] = {1, 2, 3};')
	assert result.diagnostics.len == 0
	global := result.unit.globals[0]
	assert global.count == 3
	assert global.inits.len == 3
	assert global.inits[2] == 3
}

// A scalar wrapped in braces is the same definition as the bare number:
// measured, `int x = {5};` returns 5 when the program reads x.
fn test_a_file_scope_scalar_in_braces_is_the_number_in_them() {
	result := declarations_of('int x = {5};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	value := result.unit.globals[0].init or {
		assert false
		return
	}
	assert value == 5
}

// A list of floating constants for an object whose element type is double is
// the same list in the class the object holds, and an integer constant in it is
// that integer as a double.
fn test_a_file_scope_list_of_doubles_keeps_the_class_of_the_object() {
	result := declarations_of('static const double d[] = {1.5, 2};')
	assert result.diagnostics.len == 0
	global := result.unit.globals[0]
	assert global.count == 2
	assert global.init_floats.len == 2
	assert global.init_floats[0] == 1.5
	assert global.init_floats[1] == 2.0
}

// Fewer values than the array holds leaves the rest at the zeros the storage
// started as. Measured, `int a[4] = {9};` returns 40 for
// `a[0]*1000 + a[1]*100 + a[2]*10 + a[3]`, which is 9000 taken modulo 256, and
// the elements after the first are zero.
fn test_a_file_scope_list_shorter_than_the_array_leaves_the_rest_alone() {
	result := declarations_of('int a[4] = {9};')
	assert result.diagnostics.len == 0
	global := result.unit.globals[0]
	assert global.count == 4
	assert global.inits.len == 1
	assert global.inits[0] == 9
}

// Too many values for the object is a constraint violation (6.7.8p2). Measured
// on gcc 16.2.1, `int a[2] = {1, 2, 3};` is `excess elements in array
// initializer` and `int x = {1, 2};` is `excess elements in scalar
// initializer`, and gcc exits 1 for both.
fn test_a_file_scope_list_too_long_for_the_object_is_refused() {
	arrays := declarations_of('int a[2] = {1, 2, 3};')
	assert arrays.diagnostics.len == 1
	assert arrays.diagnostics[0].msg.contains('holds 2 elements')
	assert arrays.unit.globals.len == 0
	scalars := declarations_of('int x = {1, 2};')
	assert scalars.diagnostics.len == 1
	assert scalars.diagnostics[0].msg.contains('holds one value')
	assert scalars.unit.globals.len == 0
}

// A shape the reader does not implement is refused by name: a nested list, a
// designator, an element that is not a written number, and an empty pair of
// braces. Measured on gcc 16.2.1, `int a[] = {};` under `-std=gnu99` is `ISO C
// forbids empty initializer braces before C23` and `zero or negative size
// array`.
fn test_a_file_scope_list_shape_that_is_not_implemented_is_named() {
	nested := declarations_of('static int a[2][2] = {{1, 2}, {3, 4}};')
	assert nested.diagnostics.len == 1
	assert nested.diagnostics[0].msg.contains('nested brace initializer')
	designated := declarations_of('int a[3] = {[1] = 5};')
	assert designated.diagnostics.len == 1
	assert designated.diagnostics[0].msg.contains('designator')
	element := declarations_of('int a[2] = {name};')
	assert element.diagnostics.len == 1
	assert element.diagnostics[0].msg.contains('written number')
	empty := declarations_of('int a[] = {};')
	assert empty.diagnostics.len == 1
	assert empty.diagnostics[0].msg.contains('empty brace initializer')
}

// An object of an aggregate type has a list of lists, which this reader does
// not implement, so a file-scope brace initializer for one is refused rather
// than laid out as the zeros it would otherwise silently be. Measured before
// this was refused, `struct S s = {5, 6};` compiled and returned 0 where gcc
// 16.2.1 returns 56.
fn test_a_file_scope_brace_initializer_for_an_aggregate_is_refused() {
	result := declarations_of('struct S { int a; int b; };\nstruct S s = {5, 6};')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('brace initializer for one is not implemented')
	assert result.unit.globals.len == 0
}

// In a body a list is the stores the initialization makes at the declaration:
// one assignment per element, and a zero for every element the list did not
// write, because the frame slot is whatever was there and the rest of a partly
// initialized array is zero. Measured, `int a[3] = {7};` returns 188 for
// `a[0]*100 + a[1]*10 + a[2]`.
fn test_a_body_brace_initializer_becomes_the_stores_of_the_values_written() {
	result := declarations_of('int main(void) { int a[3] = {7}; return a[0]; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 5
	assert body[0].kind == .var_decl
	assert body[0].decl_count == 3
	assert body[1].kind == .assign
	assert body[2].kind == .assign
	assert body[3].kind == .assign
	assert body[4].kind == .return_stmt
}

// A list gives an array declared with empty brackets its size in a body too:
// measured on gcc 16.2.1, `int deduced[] = {2, 3, 5, 7, 11};` declares an array
// of five elements.
fn test_a_body_list_gives_an_empty_bracket_array_its_size() {
	result := declarations_of('int main(void) { int a[] = {2, 3, 5}; return a[2]; }')
	assert result.diagnostics.len == 0
	decl := result.unit.decls[0].body[0]
	assert decl.kind == .var_decl
	assert decl.decl_count == 3
}

// A scalar in braces in a body is the number in them: measured, `int x = {5};`
// returns 5 when the program reads x.
fn test_a_body_scalar_in_braces_is_the_number_in_them() {
	result := declarations_of('int main(void) { int x = {5}; return x; }')
	assert result.diagnostics.len == 0
	decl := result.unit.decls[0].body[0]
	assert decl.kind == .var_decl
	value := decl.init or {
		assert false
		return
	}
	assert value is ast.IntLit
	assert (value as ast.IntLit).value == 5
}

// The refusals are the same in a body: a nested list, a designator, an element
// that is not a written number, and a list too long for the array. Each is one
// diagnostic that names the construct, and the declaration after the list is
// still read where it starts.
fn test_a_body_brace_initializer_shape_that_is_not_implemented_is_named() {
	nested := declarations_of('int main(void) { int a[2] = {{1}, {2}}; return 0; }')
	assert nested.diagnostics.len == 1
	assert nested.diagnostics[0].msg.contains('nested brace initializer')
	designated := declarations_of('int main(void) { int a[3] = {[1] = 5}; return 0; }')
	assert designated.diagnostics.len == 1
	assert designated.diagnostics[0].msg.contains('designator')
	element := declarations_of('int main(void) { int a[2] = {name}; return 0; }')
	assert element.diagnostics.len == 1
	assert element.diagnostics[0].msg.contains('written number')
	excess := declarations_of('int main(void) { int a[2] = {1, 2, 3}; return 0; }')
	assert excess.diagnostics.len == 1
	assert excess.diagnostics[0].msg.contains('holds 2 elements')
}

// A pointer array is a list of addresses, which are not the written constants
// this reader takes, so its list is refused rather than written as numbers.
fn test_a_body_list_of_addresses_is_refused() {
	result := declarations_of('int main(void) { int v = 1; int *p[2] = {&v, 0}; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('written number')
}

// An object of an aggregate type in a body has a list of lists, which this
// reader does not read, so the declaration is refused by name once and not
// reported again by the scalar path as a value of the wrong type. Measured, gcc
// 16.2.1 refuses `struct S s = {5, 6};` with `invalid initializer`.
fn test_a_body_brace_initializer_for_an_aggregate_is_refused() {
	result := declarations_of('struct S { int a; int b; };\nint main(void) { struct S s = {5, 6}; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('brace initializer for one is not implemented')
}

// A file-scope initializer that is a number the literal reader refuses gets the
// refusal the expression path gives it, at the literal as it was written, rather
// than the report for an initializer that is not a number at all. Measured,
// `int x = 0x1p3;` used to exit with `x is initialized with something that is
// not a number and only a number can be written into the image so far`, which
// names neither the construct nor where it is.
fn test_a_file_scope_initializer_the_literal_reader_refuses_is_named() {
	result := declarations_of('int x = 0x1p3;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('0x1p3')
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 9
	assert result.unit.globals.len == 0
}

// A file-scope initializer written as one parenthesized number is that number.
// It is the shape a macro that wraps its argument in parentheses writes: the
// corpus reaches `int c99_slot_7 = (7);` through `C99_DECLARE(7)`. Measured on
// gcc 16.2.1, `int c99_slot_7 = (7); int g = (-3);` returns 4 for
// `c99_slot_7 + g`, which is 7 + (-3). A parenthesized expression with anything
// around it is not a shape this folds and is still refused by name: measured,
// gcc accepts `int g = (7) + 1;` and this compiler refuses it.
fn test_a_file_scope_parenthesized_constant_is_the_number_in_them() {
	result := declarations_of('int c99_slot_7 = (7);')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	value := result.unit.globals[0].init or {
		assert false
		return
	}
	assert value == 7
	signed := declarations_of('int g = (-3);')
	assert signed.diagnostics.len == 0
	signed_value := signed.unit.globals[0].init or {
		assert false
		return
	}
	assert signed_value == -3
	// The pair has to end the declaration: an operator or a second operand after
	// it is an expression this does not fold, and it stays refused.
	for refused_source in ['int g = (7) + 1;', 'int g = (7, 8);'] {
		refused := declarations_of(refused_source)
		assert refused.diagnostics.len == 1
		assert refused.diagnostics[0].msg.contains('is initialized with something that is not a number')
	}
}

// A pointer at the top level is a relocation this compiler does not write yet,
// so the definition is reported instead of laid out as a wrong number.
// An initializer that is an expression is a shape this reads no part of. Reading
// its first number and stopping was silent, and the value defined was that first
// number: `int g = 2 + 3;` defined g as 2, `int g = 1 << 3;` as 1, `char g = 2 + 3;`
// as 2, `double g = 1.5 + 1.5;` as 1, and `__int128 g = 0 - 100;` as 0, each with a
// working image behind it and no diagnostic. The whole expression now reads as
// nothing, which is the case the definition reports by name.
fn test_a_file_scope_initializer_that_is_an_expression_is_reported() {
	expressions := [
		'int g = 2 + 3;',
		'int g = 1 << 3;',
		'char g = 2 + 3;',
		'double g = 1.5 + 1.5;',
		'__int128 g = 0 - 100;',
		'__int128 g = -100 + 0;',
	]
	for source in expressions {
		result := declarations_of(source)
		assert result.diagnostics.len == 1
		assert result.diagnostics[0].msg.contains('is initialized with something that is not a number')
		assert result.unit.globals.len == 0
	}
	// A single number is still read, and its sign with it, which is the shape the
	// language puts in the image.
	kept := declarations_of('int g = -7;')
	assert kept.diagnostics.len == 0
	assert kept.unit.globals.len == 1
	zero := declarations_of('__int128 g = 0;')
	assert zero.diagnostics.len == 0
}

fn test_a_pointer_defined_at_the_top_level_is_reported() {
	result := declarations_of('char *message = 0;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('pointer')
	assert result.unit.globals.len == 0
}

fn test_a_definition_keeps_its_parameters() {
	result := declarations_of('int add(int a, int b) { return a + b; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params.len == 2
	assert params[0].name == 'a'
	assert params[0].typ == 'int'
	assert params[0].line == 1
	assert params[1].name == 'b'
	assert params[1].typ == 'int'
}

// A pointer parameter is a type as written, and the stars are part of it.
// Whether the emitter can lay the call out is its question, and this front end
// does not answer it by throwing the type away.
fn test_a_pointer_parameter_keeps_the_stars_it_was_written_with() {
	result := declarations_of('int main(int argc, char **argv) { return 0; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params.len == 2
	assert params[0].typ == 'int'
	assert params[1].name == 'argv'
	assert params[1].typ == 'char **'
}

fn test_void_alone_is_a_list_of_no_parameters() {
	result := declarations_of('int main(void) { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].params.len == 0
}

fn test_an_empty_parameter_list_is_a_list_of_no_parameters() {
	result := declarations_of('int main() { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].params.len == 0
}

// The parameters of a prototype are kept too. Nothing is emitted for a
// declaration, but a name and a type as written are what the declaration says,
// and a later stage that checks a call against it needs them.
fn test_a_prototype_keeps_the_parameters_it_promises() {
	result := declarations_of('int span (const char *__s); int main() { return 0; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params.len == 1
	assert params[0].name == '__s'
	assert params[0].typ == 'char *'
}

fn test_a_variadic_definition_is_reported() {
	result := declarations_of('int f(int a, ...) { return a; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('variadic')
}

fn test_an_array_parameter_of_a_definition_is_reported() {
	result := declarations_of('int f(char s[10]) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('array parameters')
}

fn test_a_parameter_of_a_definition_needs_a_name() {
	result := declarations_of('int f(int) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('needs a name')
}

fn test_a_declaration_with_no_declarator_is_reported() {
	result := declarations_of('typedef;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('expected a declarator')
}

fn test_an_unterminated_array_bound_is_reported() {
	result := declarations_of('extern char name[32;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unterminated [')
}

// The declaration reader recurses through tag bodies the same way the
// expression reader recurses through parentheses, so a deeply nested file is
// reported rather than followed until the stack runs out. The count of
// diagnostics is not the point: a file nested two hundred deep is broken, and
// the first diagnostic is the one that names why.
fn test_a_deeply_nested_tag_body_is_reported() {
	mut source := 'int x;'
	for _ in 0 .. max_declaration_depth + 5 {
		source = 'struct { ${source} } ;'
	}
	result := declarations_of(source)
	mut reported := false
	for diagnostic in result.diagnostics {
		if diagnostic.msg.contains('nested more than') {
			reported = true
		}
	}
	assert reported
}

// A prototype's type is the one its own declaration spelled, not what its parameter
// list last resolved to. Measured before that was held, `int f(void); int main(void)
// { return f() + 1; }` was refused - the `(void)` had left the base at void, so the
// prototype was declared `void (void)` and the call had no value - where gcc
// compiles it.
fn test_a_prototype_has_the_type_its_own_specifiers_gave_it() {
	result := declarations_of('int f(void);\nint main(void) { return f() + 1; }')
	assert result.diagnostics.len == 0
	sum := result.unit.decls[1].body[0].expr or {
		assert false
		return
	}
	assert sum is ast.Binary
	call := (sum as ast.Binary).left
	assert call is ast.Call
	assert (call as ast.Call).typ.kind == .int_
}

// One name declared twice in one scope is one name (6.2.2), and the two
// declarations have to describe one type. Measured, `void f1(int *p); void f1(char
// *p);` was accepted where gcc 16.2.1 refuses `conflicting types for f1`.
fn test_a_redeclaration_with_a_different_type_is_refused() {
	result := declarations_of('void f1(int *p);\nvoid f1(char *p);\nint main(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('f1 is declared as void (int *)')
	assert result.diagnostics[0].line == 2
	assert result.diagnostics[0].col == 6
	// Repeating a type is one declaration and not a conflict.
	repeat := declarations_of('int f(int a);\nint f(int a) { return a; }\nint main(void) { return f(1); }')
	assert repeat.diagnostics.len == 0
	// 6.2.7p15: an empty parameter list says nothing about the parameters, so two
	// function types one of which is written that way are compared by what they
	// return. Measured against gcc 16.2.1 under `-std=c99`: the first two of these
	// are accepted and the second two are refused as `conflicting types for f`.
	assert declarations_of('int f(void);\nint f();\nint main(void) { return 0; }').diagnostics.len == 0
	assert declarations_of('int f(int a);\nint f();\nint main(void) { return 0; }').diagnostics.len == 0
	assert declarations_of('int f(void);\nchar f();\nint main(void) { return 0; }').diagnostics.len == 1
	assert declarations_of('int f(int a);\nint f(char b);\nint main(void) { return 0; }').diagnostics.len == 1
}

// A word the language reserves for itself cannot name a declaration (6.4.1).
// Measured, `int if = 1;` and `int main(void) { int sizeof = 1; return 0; }`
// compiled where gcc 16.2.1 refuses both at the name with `expected identifier or
// '(' before 'if'`. The lexer still does not tell a keyword from an identifier: the
// general reservation is a table in `tokenize/`, which is another lane's file, and
// the reader that would make the word a name is where the question is asked.
fn test_a_keyword_cannot_be_the_name_of_a_declaration() {
	refused := declarations_of('int if = 1;\nint main(void) { return 0; }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('if is a keyword')
	assert refused.diagnostics[0].line == 1
	assert refused.diagnostics[0].col == 5
	// sizeof is the spelling a source is most likely to have written as an object,
	// because the expression reader reads it as an operator wherever it appears.
	operator := declarations_of('int main(void) { int sizeof = 1; return 0; }')
	assert operator.diagnostics.len == 1
	assert operator.diagnostics[0].msg.contains('sizeof is a keyword')
	assert operator.diagnostics[0].col == 22
	// A name that is not reserved is unaffected.
	ordinary := declarations_of('int size = 1;\nint main(void) { return size; }')
	assert ordinary.diagnostics.len == 0
}

// A bound written in the brackets is an integer constant expression, and the
// value is what the array's type is built from. Measured on gcc 16.2.1 under
// `-std=c99`, `char b[12 * sizeof(int) - 5 * sizeof(void *)];` at file scope is
// an array of 8 and `int main(void) { ...; return sizeof b; }` exits 8; this
// compiler scanned the region and read no size, so the object was laid out with
// a count of zero. glibc declares the same bound as a struct member in
// `bits/types/struct_FILE.h`, and the member is the case that must keep
// compiling: only a file-scope object's bound is refused when it is not
// constant, because the suffix is read for a member too.
fn test_a_written_array_bound_is_evaluated_as_a_constant_expression() {
	object := declarations_of('char b[12 * sizeof(int) - 5 * sizeof(void *)];')
	assert object.diagnostics.len == 0
	assert object.unit.globals.len == 1
	assert object.unit.globals[0].count == 8
	// A narrowing cast is one integer constant converted to another, so the value
	// is the one the conversion makes. Measured, gcc 16.2.1 gives `char b[(char)
	// 300];` 44 elements and a program that returns `sizeof b` exits 44.
	narrowed := declarations_of('char b[(char)300];')
	assert narrowed.diagnostics.len == 0
	assert narrowed.unit.globals[0].count == 44
	// The same bound as a struct member still compiles, which is the line the
	// shared suffix reader must not cross.
	member := declarations_of('struct S { char _unused2[12 * sizeof(int) - 5 * sizeof(void *)]; int x; };')
	assert member.diagnostics.len == 0
	// A body's bound is evaluated the same way. Measured on gcc 16.2.1, a program
	// whose `char b[12 * sizeof(int) - 5 * sizeof(void *)]` is a local and that
	// returns `sizeof b` exits 8.
	body := declarations_of('int main(void) { char b[12 * sizeof(int) - 5 * sizeof(void *)]; return 0; }')
	assert body.diagnostics.len == 0
	assert body.unit.decls[0].body[0].decl_count == 8
}
