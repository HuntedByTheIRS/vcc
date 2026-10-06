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

// A block-scope `extern` declaration of a file-scope object gives the name no
// storage in the frame: the object lives at file scope and the name reaches it
// there. Before this the declaration was emitted as a local like any other and
// a read of the name read that uninitialized slot. Measured on gcc 16.2.1 and
// this compiler, `static int obj = 100;` with `{ extern int obj; got = obj; }`
// in main exits 100, and this compiler read address-shaped garbage. The name is
// still declared, so a use of it is not refused, but no local statement is
// built for it.
fn test_a_block_scope_extern_object_emits_no_local() {
	result := declarations_of('static int obj = 100;\nint main(void) { int got = 0; { extern int obj; got = obj; } return got; }')
	assert result.diagnostics.len == 0
	main_fn := result.unit.decls[0]
	assert main_fn.name == 'main'
	// The body is the local `got`, the nested block, and the return.
	assert main_fn.body.len == 3
	assert main_fn.body[0].kind == .var_decl
	assert main_fn.body[0].decl_name == 'got'
	assert main_fn.body[1].kind == .block
	// The block holds the assignment alone: the extern declaration left no
	// statement of its own.
	assert main_fn.body[1].body.len == 1
	assert main_fn.body[1].body[0].kind == .assign
	assert main_fn.body[2].kind == .return_stmt
}

// A file-scope `static` gives a name internal linkage (6.2.2p3), and the
// declaration has to carry it: the object writer writes such a definition with
// the local binding, so two translation units may each define one of the same
// name without the link reading them as two definitions of one program-wide
// name. A declaration without `static` keeps external linkage. The static
// function here is one something calls, because an uncalled one is stepped over
// before it reaches the tree.
fn test_a_file_scope_static_name_carries_internal_linkage() {
	result := declarations_of('static int helper(int n) { return n * 2; }\nint call(int n) { return helper(n); }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 2
	assert result.unit.decls[0].name == 'helper'
	assert result.unit.decls[0].defined
	assert result.unit.decls[0].static_
	assert result.unit.decls[1].name == 'call'
	assert !result.unit.decls[1].static_

	objects := declarations_of('static int table[4] = { 1, 2, 3, 4 };\nint open[4] = { 1, 2, 3, 4 };')
	assert objects.diagnostics.len == 0
	assert objects.unit.globals.len == 2
	assert objects.unit.globals[0].name == 'table'
	assert objects.unit.globals[0].static_
	assert objects.unit.globals[1].name == 'open'
	assert !objects.unit.globals[1].static_
}

// A file-scope declaration with several declarators defines one object per
// declarator, each with the type and the initializer written for it. Only the
// first used to reach the tree and the last initializer overwrote the first's,
// so `static int a = 5, b = 7;` defined `a` as 7 and left `b` with no object:
// measured, the program returned 7 where gcc 16.2.1 returns 5. The declarators
// here are a scalar with its own value, a pointer to one of them, and an array,
// so the group covers three derived types in one declaration. The pointers and
// the arrays are written without addresses of names read later, because a
// file-scope address initializer is a separate path and not what this checks.
fn test_a_file_scope_declaration_registers_every_declarator() {
	mixed := declarations_of('static int a = 5, *b = 0, c[3] = { 1, 2, 3 }, d = 9;')
	assert mixed.diagnostics.len == 0
	assert mixed.unit.globals.len == 4
	assert mixed.unit.globals[0].name == 'a'
	assert mixed.unit.globals[0].init or { -1 } == 5
	assert mixed.unit.globals[1].name == 'b'
	assert mixed.unit.globals[1].typ == 'int *'
	assert mixed.unit.globals[2].name == 'c'
	assert mixed.unit.globals[2].count == 3
	assert mixed.unit.globals[2].inits[0] == 1 && mixed.unit.globals[2].inits[2] == 3
	assert mixed.unit.globals[3].name == 'd'
	assert mixed.unit.globals[3].init or { -1 } == 9
	// A function-pointer declarator beside a scalar is the same question: each
	// name is an object of the type its own declarator built.
	pointers := declarations_of('int (*fp)(int) = 0, g = 9;')
	assert pointers.diagnostics.len == 0
	assert pointers.unit.globals.len == 2
	assert pointers.unit.globals[0].name == 'fp'
	assert pointers.unit.globals[0].resolved.describe() == 'int (int) *'
	assert pointers.unit.globals[1].name == 'g'
	assert pointers.unit.globals[1].init or { -1 } == 9
	// No initializer is still one object per name, each zeroed.
	plain := declarations_of('int a, b;')
	assert plain.diagnostics.len == 0
	assert plain.unit.globals.len == 2
	assert plain.unit.globals[0].name == 'a'
	assert plain.unit.globals[1].name == 'b'
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

// 6.7.8p14 lets an array of character type be initialized by a string literal,
// and an array whose brackets wrote no size is the literal including its
// terminating zero. Measured on gcc 16.2.1 under `-std=gnu99`, a program whose
// `char s[] = "abc";` is at file scope and that returns `sizeof s` exits 4 and
// reads `abc`, and one whose `char s[8] = "abc";` returns `sizeof s` exits 8.
fn test_a_file_scope_char_array_takes_a_string_literal() {
	deduced := declarations_of('char s[] = "abc";')
	assert deduced.diagnostics.len == 0
	global := deduced.unit.globals[0]
	assert global.count == 4
	assert global.inits.len == 4
	assert global.inits[0] == 97 && global.inits[1] == 98 && global.inits[2] == 99
	assert global.inits[3] == 0
	// A written size is used, and the elements after the terminator stay the
	// zeros the storage starts as.
	sized := declarations_of('char s[8] = "abc";')
	assert sized.diagnostics.len == 0
	assert sized.unit.globals[0].count == 8
	assert sized.unit.globals[0].inits.len == 4
	// A bound exactly the characters keeps no terminating zero, which gcc
	// accepts: `char s[3] = "abc";` exits zero.
	exact := declarations_of('char s[3] = "abc";')
	assert exact.diagnostics.len == 0
	assert exact.unit.globals[0].count == 3
	assert exact.unit.globals[0].inits.len == 3
	// Adjacent literals are one literal (6.4.5p5).
	joined := declarations_of('char s[] = "ab" "cd";')
	assert joined.diagnostics.len == 0
	assert joined.unit.globals[0].count == 5
	assert joined.unit.globals[0].inits[2] == 99
}

// A wide literal initializes an array of this target's wchar_t, an int: four
// elements of four bytes, which is what gcc 16.2.1 lays out for
// `wchar_t w[] = L"abc";`.
fn test_a_file_scope_wide_array_takes_a_wide_literal() {
	result := declarations_of('typedef int wchar_t;\nwchar_t w[] = L"abc";')
	assert result.diagnostics.len == 0
	global := result.unit.globals[0]
	assert global.count == 4
	assert global.inits.len == 4
	assert global.inits[0] == 97 && global.inits[3] == 0
	// The wide literal's characters are four little-endian bytes each.
	escaped := declarations_of('typedef int wchar_t;\nwchar_t w[] = L"\\xe9";')
	assert escaped.diagnostics.len == 0
	assert escaped.unit.globals[0].inits[0] == 233
}

// A bound that was written is used and never filled in from the literal:
// `char s[0] = "abc";` holds none and writes four, which gcc 16.2.1 reports as
// `initializer-string for array of 'char' is too long (4 chars into 0
// available)`, and `char s[2] = "abc";` is the same violation into two. A bound
// that is not an integer constant expression stays the file-scope refusal it
// already was, because a literal does not settle the size of an object whose
// storage the image has to hold.
fn test_a_written_bound_is_not_filled_in_from_a_string_literal() {
	zero := declarations_of('char s[0] = "abc";')
	assert zero.diagnostics.len == 1
	assert zero.diagnostics[0].msg.contains('holds 0 elements and its initializer writes 4')
	assert zero.unit.globals.len == 0
	too_long := declarations_of('char s[2] = "abc";')
	assert too_long.diagnostics.len == 1
	assert too_long.diagnostics[0].msg.contains('holds 2 elements and its initializer writes 4')
	assert too_long.unit.globals.len == 0
	variable := declarations_of('int n = 3;\nchar s[n] = "abc";')
	assert variable.diagnostics.len == 1
	assert variable.diagnostics[0].msg.contains('is not an integer constant expression')
}

// A narrow literal whose element type is not the array's is not this initializer:
// measured on gcc 16.2.1, `int a[] = "xy";` is `cannot initialize array of 'int'
// from a string literal with type array of 'char'`. This compiler reports the
// declaration as one whose initializer is not a number, which is the refusal it
// already had for the shape.
fn test_a_narrow_literal_does_not_initialize_an_int_array() {
	result := declarations_of('int a[] = "xy";')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('is initialized with something this compiler cannot write')
}

// A written bound that is negative is a constraint violation (6.7.5.2p1).
// Measured on gcc 16.2.1, `int x[2 - 5];`, `int x[-1];` and `int x[~0];` are
// `size of array 'x' is negative` and rejected under `-std=gnu99` and under
// `-std=c99 -pedantic-errors`, as a file-scope object, a struct member or a
// parameter. Zero is not that case: `int x[0];` is a zero-size array gcc accepts
// under `-std=gnu99`, and empty brackets are a size an initializer may give.
fn test_a_negative_written_bound_is_a_constraint_violation() {
	difference := declarations_of('int x[2 - 5];')
	assert difference.diagnostics.len == 1
	assert difference.diagnostics[0].msg.contains('the bound of x is -3')
	assert difference.diagnostics[0].msg.contains('6.7.5.2p1')
	negative := declarations_of('int x[-1];')
	assert negative.diagnostics.len == 1
	assert negative.diagnostics[0].msg.contains('the bound of x is -1')
	// The same bound as a struct member and as a parameter is the same
	// violation, which gcc rejects in both places too.
	member := declarations_of('struct S { int a[-1]; };')
	assert member.diagnostics.len == 1
	assert member.diagnostics[0].msg.contains('the bound of a is -1')
	parameter := declarations_of('void f(int a[-1]);')
	assert parameter.diagnostics.len == 1
	assert parameter.diagnostics[0].msg.contains('the bound of a is -1')
	// Zero was written and is not negative: it reads as no size, which is what
	// `int x[0];` was before this check.
	zero := declarations_of('int x[0];')
	assert zero.diagnostics.len == 0
}

// A written zero is zero for a string initializer too, so the literal is checked
// against it rather than the object resized from the literal. Measured on gcc
// 16.2.1, `char s[0] = "abc";` is `initializer-string for array of 'char' is too
// long (4 chars into 0 available)`, and `char s[0] = "";` holds no element and
// is accepted.
fn test_a_written_zero_bound_is_zero_for_a_string_initializer() {
	too_long := declarations_of('char s[0] = "abc";')
	assert too_long.diagnostics.len == 1
	assert too_long.diagnostics[0].msg.contains('holds 0 elements and its initializer writes 4')
	empty := declarations_of('char s[0] = "";')
	assert empty.diagnostics.len == 0
	// The same in a body, where the written zero sizes the object as zero.
	body := declarations_of('int main(void) { char s[0] = ""; return 0; }')
	assert body.diagnostics.len == 0
	assert body.unit.decls[0].body[0].decl_count == 0
}

// A shape the reader does not implement is refused by name: an element that
// begins with neither a written number nor an address. An array whose brackets
// wrote no size takes its size from the list, and an empty list writes no
// element to give it one: measured on gcc 16.2.1, `int a[] = {};` is `ISO C
// forbids empty initializer braces before C23` under `-std=gnu99` and then
// `zero or negative size array`, so the empty-list refusal that used to live in
// the reader is now the size this declaration has no answer for.
fn test_a_file_scope_list_shape_that_is_not_implemented_is_named() {
	// A name is read as an address, which is what a pointer's initializer is, so
	// on an object that holds no address the element is named for that: gcc
	// 16.2.1 rejects `int a[2] = {name};` as an undeclared name, and this reader
	// refuses the address the name stands for.
	addressed := declarations_of('int a[2] = {name};')
	assert addressed.diagnostics.len == 1
	assert addressed.diagnostics[0].msg.contains('does not hold addresses')
	// A parenthesized expression that is not a constant is still refused by
	// name. A constant one is read now, which is the sibling test's subject:
	// 6.7.8p1 makes an element an assignment-expression and 6.6p4 lets a
	// file-scope one be a constant expression.
	element := declarations_of('int y = 1; int a[2] = {(1 + y)};')
	assert element.diagnostics.len == 1
	assert element.diagnostics[0].msg.contains('written constant')
	// An empty list writes no value, so it gives an array with empty brackets
	// no size to be.
	empty := declarations_of('int a[] = {};')
	assert empty.diagnostics.len == 1
	assert empty.diagnostics[0].msg.contains('empty brace initializer does not write')
}

// A brace list whose element read fails leaves the cursor where it was, so the
// statements after the list are still the statements of the body that holds it.
// The element below is refused by name - a designator with no `=` is not a
// value this reader writes - and the point of this test is what the refusal does
// to the rest of the body. Before the recovery the failed read left the cursor
// in front of the list's own closing brace, the block reader took that brace for
// the end of the function, and every statement after it was reported as
// `expected a declaration` at file scope: the shape at hello.c 3437 did that to
// eight statements of `_vinit`. The empty list in that shape is read now, so the
// failing element is a designator missing its value.
fn test_a_failed_brace_element_leaves_the_reader_in_the_function() {
	result := declarations_of('struct T { int a; }; struct S { int typ; struct T *obj; int boxed; }; struct S g; void *memdup(const void *p, unsigned long n); int main(void) { g = (struct S){.typ = 1, .obj = (struct T *)memdup(&(struct T){.a 1}, sizeof(struct T)), .boxed = 1}; g.typ = 6; return g.typ; }')
	// One diagnostic, the element refused by name. The cascade that used to
	// report every statement after the assignment is gone.
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('expected =')
	mut main := result.unit.decls[0]
	for decl in result.unit.decls {
		if decl.name == 'main' {
			main = decl
		}
	}
	assert main.name == 'main'
	assert main.body.len > 0
	last := main.body[main.body.len - 1]
	assert last.kind == .return_stmt
}

// The same recovery in an enum body. An enumerator whose value the folder cannot
// compute is refused by name, and before the recovery the cursor was left inside
// the braces: the typedef of the enum then reported its own name, `E`, as
// `expected a declaration` at file scope - measured, `typedef enum { A =
// NOTDEFINED, B } E;` gave that message at E's column, and glibc's
// `<stdatomic.h>` reaches it through `__ATOMIC_RELAXED`, which nothing here
// defines.
fn test_a_failed_enumerator_leaves_the_reader_in_the_enum() {
	result := declarations_of('typedef enum { A = NOTDEFINED, B } E; int x; int main(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('integer constant expression')
	// The typedef read to its closing brace, so the program after it is the
	// program: one global and one function, and no statement read as a
	// declaration.
	assert result.unit.globals.len == 1
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].name == 'main'
}

// V writes every constant it emits as `(type)(value)`, so the C it generates has
// file-scope const arrays whose first element is a cast of a written constant:
// `{((u8)(0x08)), 0x00, ...}`. A cast of a written constant is itself a written
// constant, and the value is the one the conversion makes - measured on gcc
// 16.2.1, `((u8)(0x08))` is 8, `((unsigned long)(1e1))` is 10, `((double)(0.5))`
// is 0.5, and `((unsigned long)(0x3ff0000000000000))` is 4607182418800017408, so
// the wide value reaches the image whole rather than halved. A written constant
// in parentheses, with a sign in front of them, is the same constant: `(7)` is 7
// and `-(32)` is -32.
fn test_a_file_scope_cast_or_parenthesized_constant_is_a_written_constant() {
	casted := declarations_of('typedef unsigned char u8;
static const u8 t[4] = {((u8)(0x08)), 0x01, 0x02, 0x03};')
	assert casted.diagnostics.len == 0
	assert casted.unit.globals.len == 1
	assert casted.unit.globals[0].count == 4
	assert casted.unit.globals[0].inits[0] == 8
	assert casted.unit.globals[0].inits[1] == 1
	// A floating constant cast to an integer type is truncated towards zero.
	truncated := declarations_of('static const unsigned long p[] = {((unsigned long)(1e1))};')
	assert truncated.diagnostics.len == 0
	assert truncated.unit.globals[0].inits[0] == 10
	// A cast to a floating type keeps the value in the class the object holds.
	fraction := declarations_of('static const double d[] = {((double)(0.5))};')
	assert fraction.diagnostics.len == 0
	assert fraction.unit.globals[0].init_floats[0] == 0.5
	// A value wider than the four bytes an instruction holds reaches the image
	// whole: 0x3ff0000000000000 is the double 1.0 as its bits, and a table of
	// these decides a float formatter's behaviour.
	wide := declarations_of('static const unsigned long pos[] = {((unsigned long)(0x3ff0000000000000))};')
	assert wide.diagnostics.len == 0
	assert wide.unit.globals[0].inits[0] == 4607182418800017408
	// Width and sign are the target type's: a narrowing conversion keeps the low
	// bytes, and a signed one sign-extends them.
	narrowed := declarations_of('static const unsigned char n[] = {((unsigned char)(300))};')
	assert narrowed.diagnostics.len == 0
	assert narrowed.unit.globals[0].inits[0] == 44
	signed := declarations_of('static const signed char s[] = {((signed char)(0xFF))};')
	assert signed.diagnostics.len == 0
	assert signed.unit.globals[0].inits[0] == -1
	// A written constant in parentheses, and a sign in front of the parentheses.
	parenthesized := declarations_of('static const int q[] = {(7), -(32)};')
	assert parenthesized.diagnostics.len == 0
	assert parenthesized.unit.globals[0].inits[0] == 7
	assert parenthesized.unit.globals[0].inits[1] == -32
	// A cast of an expression the folder evaluates is a written constant too:
	// 6.7.8p1 makes an element an assignment-expression and 6.6p4 lets a
	// file-scope one be a constant expression, so `((int)(1 + 2))` is 3 and
	// `((int)(sizeof(int)))` is 4. Measured on gcc 16.2.1, both are accepted
	// and answer those values, where this reader refused both.
	expression := declarations_of('static const int r[] = {((int)(1 + 2))};')
	assert expression.diagnostics.len == 0
	assert expression.unit.globals[0].inits[0] == 3
	sized := declarations_of('static const int u[] = {((int)(sizeof(int)))};')
	assert sized.diagnostics.len == 0
	assert sized.unit.globals[0].inits[0] == 4
	// A cast of a call is not a constant: the value is one the program computes
	// at run time and the image holds constants, so the element is refused by
	// name rather than written.
	call := declarations_of('int f(void); static const int c[] = {((int)(f()))};')
	assert call.diagnostics.len == 1
	assert call.diagnostics[0].msg.contains('written constant')
}

// A file-scope list with a nested list or a designator initializes the
// subobject it names, and each entry carries the byte that subobject starts at.
// Measured on gcc 16.2.1, `static int a[2][2] = {{1, 2}, {3, 4}};` reads 1, 2, 3
// and 4 at the four ints of the object, and `{[2] = 3, [0] = 1}` writes an int[4]
// whose elements 0 and 2 are 1 and 3 and whose others are zero.
fn test_a_file_scope_nested_or_designated_list_writes_the_subobject_it_names() {
	nested := declarations_of('static int a[2][2] = {{1, 2}, {3, 4}};')
	assert nested.diagnostics.len == 0
	assert nested.unit.globals.len == 1
	nested_entries := nested.unit.globals[0].member_inits
	assert nested_entries.len == 4
	mut offsets := []int{}
	mut values := []i64{}
	for entry in nested_entries {
		offsets << entry.offset
		values << (entry.init or { -1 })
	}
	assert offsets == [0, 4, 8, 12]
	assert values == [1, 2, 3, 4]
	designated := declarations_of('static int a[4] = {[2] = 3, [0] = 1};')
	assert designated.diagnostics.len == 0
	entries := designated.unit.globals[0].member_inits
	assert entries.len == 2
	assert entries[0].offset == 8
	assert (entries[0].init or { -1 }) == 3
	assert entries[1].offset == 0
	assert (entries[1].init or { -1 }) == 1
}

// A GNU range designator `[first ... last] = value` writes the one value into
// every element of the range, and an array with empty brackets takes its size
// from the last element the range names. Measured on gcc 16.2.1,
// `{ [0 ... 1] = 5, [3 ... 3] = 9 }` on an int[4] is {5, 5, 0, 9}, and an unsized
// `{ [0 ... 9] = 1, [10] = 2 }` is eleven elements. A range that ends before it
// begins and one that reaches past the array are refused by name at the
// designator rather than read as a shorter list.
fn test_a_range_designator_fills_every_element_it_names() {
	filled := declarations_of('static int a[4] = {[0 ... 1] = 5, [3 ... 3] = 9};')
	assert filled.diagnostics.len == 0
	entries := filled.unit.globals[0].member_inits
	assert entries.len == 3
	mut offsets := []int{}
	mut values := []i64{}
	for entry in entries {
		offsets << entry.offset
		values << (entry.init or { -1 })
	}
	assert offsets == [0, 4, 12]
	assert values == [5, 5, 9]
	sized := declarations_of('static int b[] = {[0 ... 9] = 1, [10] = 2};')
	assert sized.diagnostics.len == 0
	assert sized.unit.globals[0].count == 11
	empty := declarations_of('static int c[4] = {[3 ... 1] = 1};')
	assert empty.diagnostics.len == 1
	assert empty.diagnostics[0].msg.contains('names no element')
	beyond := declarations_of('static int d[4] = {[0 ... 9] = 1};')
	assert beyond.diagnostics.len == 1
	assert beyond.diagnostics[0].msg.contains('is outside')
}

// 6.7.8p1 makes each element of an aggregate initializer an
// assignment-expression and 6.6p4 lets a file-scope one be a constant
// expression, so an element may be arithmetic over constants rather than a
// single written number. Measured on gcc 16.2.1, `int a[] = {1 + 2, (3 * 4),
// 5, 2 * sizeof(int)};` writes 3, 12, 5 and 8, and an enumeration constant is
// an integer constant expression whether it stands alone or begins a longer
// element.
fn test_a_file_scope_constant_expression_element_is_folded() {
	folded := declarations_of('static const int a[] = {1 + 2, (3 * 4), 5, 2 * sizeof(int)};')
	assert folded.diagnostics.len == 0
	assert folded.unit.globals[0].count == 4
	assert folded.unit.globals[0].inits[0] == 3
	assert folded.unit.globals[0].inits[1] == 12
	assert folded.unit.globals[0].inits[2] == 5
	assert folded.unit.globals[0].inits[3] == 8
	enumerated := declarations_of('enum { E = 7, F = 8 };\nstatic const int b[] = {E, E + F};')
	assert enumerated.diagnostics.len == 0
	assert enumerated.unit.globals[0].inits[0] == 7
	assert enumerated.unit.globals[0].inits[1] == 15
	// A parenthesized expression that is not constant is refused by name: the
	// element is an expression the image cannot hold.
	refused := declarations_of('int y = 1; static const int c[] = {(1 + y)};')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('written constant')
}

// A floating constant expression is a value a file-scope initializer may hold
// (6.6p4), and the bytes the image writes are the value it folds to. Measured on
// gcc 16.2.1, the first program below holds 0.083333333333333329 in b[0] and
// prints 83 for `(int)(b[0] * 1000.0)`. The parenthesized element in V's
// generated C is the shape this reads, and `{1.0 / 12.0, 2.0}` is the same value
// written without the parentheses: it used to be accepted with the object left
// out of the unit entirely, so a later read of b[0] failed with a message about
// the name rather than about the initializer.
fn test_a_file_scope_floating_constant_expression_element_is_folded() {
	parenthesized := declarations_of('const double b[2] = {(1.0) / ((((6.0) * (2.0)) * (1.0))), 2.0};')
	assert parenthesized.diagnostics.len == 0
	assert parenthesized.unit.globals.len == 1
	object := parenthesized.unit.globals[0]
	assert object.count == 2
	assert object.inits.len == 0
	assert object.init_floats.len == 2
	assert object.init_floats[0] == 1.0 / 12.0
	assert object.init_floats[1] == 2.0
	// The same element with no parentheses around the first term is the same
	// value in the image, and not a declaration that writes no object.
	bare := declarations_of('const double b[2] = {1.0 / 12.0, 2.0};')
	assert bare.diagnostics.len == 0
	assert bare.unit.globals.len == 1
	assert bare.unit.globals[0].init_floats.len == 2
	assert bare.unit.globals[0].init_floats[0] == 1.0 / 12.0
	assert bare.unit.globals[0].init_floats[1] == 2.0
	// A scalar floating object folds an expression rather than only a literal.
	scalar := declarations_of('double g = 1.5 + 1.5;')
	assert scalar.diagnostics.len == 0
	assert (scalar.unit.globals[0].init_float or { 0.0 }) == 3.0
	// An expression over a name is not a constant: the element is refused by
	// name rather than written as a value the fold did not make.
	refused := declarations_of('int y = 1; static const double c[2] = {(1.0 + y), 2.0};')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('written constant')
}

// A file-scope object of the extended type starts at the value its initializer
// names, whatever the spelling. A long double literal keeps that value in the
// extended field of the tree (ast.FloatLit.long_value) and leaves its double
// field zero, and a reader that folded the literal as a double wrote the double
// 0.0 into every such object: measured with this compiler, `static long double
// g = 12.0L;` read 0 where gcc 16.2.1 reads 12. 12.0L is 1.5 * 2^3, whose
// extended form is the significand 0xc000000000000000 and the exponent 0x4002,
// and 0x1.8p+3L is the same value the corpus writes at monolithic.c:266.
fn test_a_file_scope_long_double_keeps_the_value_of_its_initializer() {
	decimal := declarations_of('static long double g = 12.0L;')
	assert decimal.diagnostics.len == 0
	assert decimal.unit.globals.len == 1
	twelve := decimal.unit.globals[0].init_long or {
		assert false
		return
	}
	assert twelve.mantissa == u64(0xc000000000000000)
	assert twelve.sign_exp == 0x4002
	// The hexadecimal spelling of the same value is the same bytes.
	hexadecimal := declarations_of('static const long double h = 0x1.8p+3L;')
	assert hexadecimal.diagnostics.len == 0
	same := hexadecimal.unit.globals[0].init_long or {
		assert false
		return
	}
	assert same.mantissa == twelve.mantissa
	assert same.sign_exp == twelve.sign_exp
	// A different value is a different exponent: 0.5L is 1.0 * 2^-1.
	half := declarations_of('static const long double h = 0.5L;')
	assert half.diagnostics.len == 0
	value := half.unit.globals[0].init_long or {
		assert false
		return
	}
	assert value.mantissa == u64(0x8000000000000000)
	assert value.sign_exp == 0x3ffe
	// The sign written in front of a constant is part of its value, which the
	// extended form carries in the top bit of the sign and exponent word.
	negative := declarations_of('static const long double n = -12.0L;')
	assert negative.diagnostics.len == 0
	signed := negative.unit.globals[0].init_long or {
		assert false
		return
	}
	assert signed.mantissa == u64(0xc000000000000000)
	assert signed.sign_exp == 0xc002
}

// A const-qualified element of a floating type belongs to the floating class,
// and the elements of a const brace initializer are floating constants:
// `const double b[2][2] = {{2.0, 3.0}, {4.0, 5.0}}` writes 2.0 and 3.0 into the
// first row and not the integers 2 and 3. Measured on gcc 16.2.1, the eight
// bytes at b start `00 00 00 00 00 00 00 40` (2.0), and a program reading b[0][0]
// through a `double` is the same bytes.
fn test_a_const_floating_aggregate_takes_floating_elements() {
	result := declarations_of('static const double b[2][2] = {{2.0, 3.0}, {4.0, 5.0}};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	entries := object.member_inits
	assert entries.len == 4
	assert entries[0].offset == 0
	assert entries[1].offset == 8
	assert entries[2].offset == 16
	assert entries[3].offset == 24
	assert entries[0].spelling == 'double'
	assert (entries[0].init_float or { -1.0 }) == 2.0
	assert (entries[1].init_float or { -1.0 }) == 3.0
	assert (entries[2].init_float or { -1.0 }) == 4.0
	assert (entries[3].init_float or { -1.0 }) == 5.0
	assert entries[0].init == none
	// The single class is the element's own, and a const float element is the
	// four-byte one: the two classes are told apart by the spelling.
	single := declarations_of('static const float f[2][2] = {{2.0f, 3.0f}, {4.0f, 5.0f}};')
	assert single.diagnostics.len == 0
	sentries := single.unit.globals[0].member_inits
	assert sentries.len == 4
	assert sentries[0].spelling == 'float'
	assert (sentries[0].init_float or { -1.0 }) == 2.0
}

// A compound literal is an element an aggregate list may hold, because 6.7.8p1
// makes an element an assignment-expression and 6.5.2.5 makes a compound
// literal one. At file scope the literal's object has static storage duration
// and its elements are constant expressions (6.7.8p4), so the bytes its list
// writes are the bytes the element takes. Measured on gcc 16.2.1,
// `string a[2] = {(string){"a", 1, 1}, (string){"bb", 2, 1}};` prints `a 1 bb
// 2`, and the two strings' own addresses are the two literals.
fn test_a_file_scope_compound_literal_element_initializes_an_aggregate() {
	source := 'typedef struct { char *str; int len; int is_lit; } string;\nstatic string a[2] = {(string){"a", 1, 1}, (string){"bb", 2, 1}};'
	result := declarations_of(source)
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.count == 2
	assert object.bytes == 16
	entries := object.member_inits
	assert entries.len == 6
	// The first member of each string is an address the layout resolves, and
	// the two beside it are the numbers the list wrote.
	assert entries[0].offset == 0
	assert entries[0].address != none
	assert entries[1].offset == 8
	assert (entries[1].init or { -1 }) == 1
	assert entries[2].offset == 12
	assert (entries[2].init or { -1 }) == 1
	assert entries[3].offset == 16
	assert entries[3].address != none
	assert entries[4].offset == 24
	assert (entries[4].init or { -1 }) == 2
	// A compound literal initializing a whole aggregate object is the same
	// object's brace list, and its values reach the members the same way.
	direct := declarations_of('struct S { int a; int b; };\nstatic struct S s = (struct S){5, 6};')
	assert direct.diagnostics.len == 0
	assert direct.unit.globals.len == 1
	assert direct.unit.globals[0].member_inits.len == 2
	assert (direct.unit.globals[0].member_inits[0].init or { -1 }) == 5
	assert (direct.unit.globals[0].member_inits[1].init or { -1 }) == 6
}

// A struct's brace initializer at file scope gives each value to a member in the
// order the members were written, and each constant carries the byte the layout
// gave that member. Measured on gcc 16.2.1, `struct S s = {5, 6};` returns 56 for
// `s.a * 10 + s.b`, which is why each value has to reach its own member.
fn test_a_file_scope_struct_brace_initializer_writes_each_member() {
	result := declarations_of('struct S { int a; int b; };\nstruct S s = {5, 6};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.member_inits.len == 2
	assert object.member_inits[0].offset == 0
	assert object.member_inits[1].offset == 4
	first := object.member_inits[0].init or {
		assert false
		return
	}
	second := object.member_inits[1].init or {
		assert false
		return
	}
	assert first == 5
	assert second == 6
}

// `typedef struct S S;` takes the tag before `struct S { int a; int b; };`
// completes it, and 6.7.2.3 makes the two declarations one type. Measured, gcc
// 16.2.1 compiles the program and `s.a + s.b` is 3. Reading the definition is
// what gives the initializer two members to place: a type that never saw the
// body has none, and the declaration was refused as `s has 0 members and its
// initializer writes 2`.
fn test_a_typedef_before_the_struct_body_sees_the_definition() {
	result := declarations_of('typedef struct S S;\nstruct S { int a; int b; };\nS s = {1, 2};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.resolved.is_complete()
	assert object.bytes == 8
	assert object.member_inits.len == 2
	assert object.member_inits[0].offset == 0
	assert object.member_inits[1].offset == 4
	// Two names for one tag are one type, and the definition each was written
	// before is the same definition.
	two := declarations_of('typedef struct S S;\ntypedef struct S T;\nstruct S { int a; int b; };\nS s = {1, 2};\nT t = {3, 4};')
	assert two.diagnostics.len == 0
	assert two.unit.globals.len == 2
	assert two.unit.globals[0].bytes == 8
	assert two.unit.globals[1].bytes == 8
}

// A typedef of a pointer to the tag is a complete object before the body is
// read, which is what `FILE *f;` needs: 6.2.5 sizes a pointer from its star and
// never asks what is under it. The tag's members are still the definition's
// once it is read.
fn test_a_typedef_of_a_pointer_to_the_tag_stays_complete() {
	result := declarations_of('typedef struct S *SP;\nstruct S { int a; int b; };\nSP p;')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.resolved.is_complete()
	assert object.resolved.kind == .pointer
}

// A GNU attribute may follow a struct's closing brace, and 6.7 makes the
// declaration valid with it: `struct T { int a; } __attribute__((aligned(16)));`.
// This compiler has no attribute model, so the attribute is read past and not
// recorded, the same as one written after a declarator. Refusing it would refuse
// a declaration gcc 16.2.1 accepts, and V's prelude writes exactly this shape.
fn test_an_attribute_after_a_struct_body_is_read_past() {
	result := declarations_of('struct T { int a; } __attribute__((aligned(16)));\nstruct T t = {5};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].name == 't'
	// The same attribute between the body and the declarator name, which is how
	// V's prelude writes `} __attribute__((aligned(16))) v_int128_t;`.
	named := declarations_of('struct T { int a; } __attribute__((aligned(16))) named;\nstruct T other = {6};')
	assert named.diagnostics.len == 0
	assert named.unit.globals.len == 2
	assert named.unit.globals[0].name == 'named'
	assert named.unit.globals[1].name == 'other'
}

// A list for a struct whose member is itself an aggregate is walked against the
// object's type: a positional value elides into the scalar subobject it reaches
// (6.7.8p20) and a subobject the list does not reach holds the zero 6.7.8p21
// gives it. Measured on gcc 16.2.1, `struct S s = {1, 2, 3};` reads t.x 1, t.y
// 2 and n 3, and `struct A a = {0};` on a struct whose member is an array reads
// the whole object as zero. This shape used to be refused by name.
fn test_a_file_scope_list_for_a_struct_with_an_aggregate_member_is_refused() {
	result := declarations_of('struct T { int x; int y; };\nstruct S { struct T t; int n; };\nstruct S s = {1, 2, 3};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.bytes == 12
	assert object.member_inits.len == 3
	assert object.member_inits[0].offset == 0
	assert object.member_inits[1].offset == 4
	assert object.member_inits[2].offset == 8
	first := object.member_inits[0].init or {
		assert false
		return
	}
	second := object.member_inits[1].init or {
		assert false
		return
	}
	third := object.member_inits[2].init or {
		assert false
		return
	}
	assert first == 1
	assert second == 2
	assert third == 3
	// `{0}` on a struct whose only member is an array elides the zero into the
	// first element and leaves the rest to the implicit zero.
	zeroed := declarations_of('struct A { int a[3]; };\nstruct A x = {0};')
	assert zeroed.diagnostics.len == 0
	assert zeroed.unit.globals.len == 1
	assert zeroed.unit.globals[0].bytes == 12
	assert zeroed.unit.globals[0].member_inits.len == 1
	assert zeroed.unit.globals[0].member_inits[0].offset == 0
	only := zeroed.unit.globals[0].member_inits[0].init or {
		assert false
		return
	}
	assert only == 0
	// `{}` writes no value at all: every subobject is the implicit zero.
	empty := declarations_of('struct A { int a[3]; int n; };\nstruct A x = {};')
	assert empty.diagnostics.len == 0
	assert empty.unit.globals.len == 1
	assert empty.unit.globals[0].bytes == 16
	assert empty.unit.globals[0].member_inits.len == 0
	// A written value that is not the aggregate's has no place at the subobject:
	// an address written into an int element is refused by name rather than laid
	// down where a read would take it.
	address := declarations_of('int n;\nstruct A { int a[2]; };\nstruct A x = {&n};')
	assert address.diagnostics.len == 1
	assert address.diagnostics[0].msg.contains('an address initializes an object of the type int')
}

// A bitfield member takes its value into the field's own bits inside the storage
// unit it shares with the members beside it, so a value for one is placed rather
// than refused. Measured on gcc 16.2.1, `struct B { unsigned int a : 3; int n; };
// struct B b = {5, 1};` reads a as 5 and n as 1.
fn test_a_file_scope_list_for_a_struct_with_a_bitfield_member_places_the_value() {
	result := declarations_of('struct B { unsigned int a : 3; int n; };\nstruct B b = {5, 1};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	entries := result.unit.globals[0].member_inits
	assert entries.len == 2
	assert entries[0].bitfield
	assert entries[0].offset == 0
	assert entries[0].bit_offset == 0
	assert entries[0].bit_width == 3
	assert entries[0].unit_width == 4
	assert (entries[0].init or { -1 }) == 5
	assert !entries[1].bitfield
	assert entries[1].offset == 4
	assert (entries[1].init or { -1 }) == 1
}

// An unnamed bitfield is not a member a positional list writes: 6.7.2.1p12 skips
// it, and a zero-width one only moves the next member to a unit boundary. The
// value after the skipped field goes to the member after it. Measured on gcc
// 16.2.1, `struct T { unsigned int a : 3; unsigned int : 0; unsigned int d : 2; };
// struct T t = {5, 3};` reads a as 5, d as 3 and is eight bytes.
fn test_an_unnamed_bitfield_is_skipped_by_a_positional_list() {
	result := declarations_of('struct T { unsigned int a : 3; unsigned int : 0; unsigned int d : 2; };\nstruct T t = {5, 3};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.bytes == 8
	entries := object.member_inits
	assert entries.len == 2
	assert entries[0].bitfield && entries[0].offset == 0 && entries[0].bit_offset == 0
	assert (entries[0].init or { -1 }) == 5
	assert entries[1].bitfield && entries[1].offset == 4 && entries[1].bit_offset == 0
	assert (entries[1].init or { -1 }) == 3
}

// In a body a bitfield member's value becomes a store that carries the field's
// bits, so the emitter masks and shifts instead of writing the whole unit. A
// negative constant written into a signed field is read as the type of its
// operand, which is what gcc does: measured, `struct B b = {-3};` returns -3.
fn test_a_body_list_writes_a_bitfield_member_into_its_own_bits() {
	result := declarations_of('int main(void) { struct B { signed int b : 5; }; struct B x = {-3}; return x.b; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .var_decl
	assert body[1].kind == .assign
	field := body[1].field or {
		assert false
		return
	}
	assert field.bitfield
	assert field.bit_offset == 0
	assert field.bit_width == 5
	assert field.unit_width == 4
}

// A designated list carries the same bit position a positional one does: the
// value goes into the field's own bits inside the storage unit it shares, so
// `{.b = 9}` must not write a whole unit of its own over the field beside it.
// Measured on gcc 16.2.1, `struct S { unsigned int a : 3; unsigned int b : 5; };
// struct S s = {.b = 9, .a = 5};` reads a as 5 and b as 9.
fn test_a_file_scope_designated_list_writes_a_bitfield_member_into_its_own_bits() {
	result := declarations_of('struct S { unsigned int a : 3; unsigned int b : 5; };\nstruct S s = {.b = 9, .a = 5};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	entries := result.unit.globals[0].member_inits
	assert entries.len == 2
	assert entries[0].bitfield
	assert entries[0].offset == 0
	assert entries[0].bit_offset == 3
	assert entries[0].bit_width == 5
	assert entries[0].unit_width == 4
	assert (entries[0].init or { -1 }) == 9
	assert entries[1].bitfield
	assert entries[1].bit_offset == 0
	assert (entries[1].init or { -1 }) == 5
}

// The same in a body: the store the designated list makes carries the field's
// bits, so the emitter masks and shifts instead of writing the whole unit, and
// the value beside it stays. Measured on gcc 16.2.1, `struct S s = {.b = 9};`
// reads a as 0 and b as 9.
fn test_a_body_designated_list_writes_a_bitfield_member_into_its_own_bits() {
	result := declarations_of('int main(void) { struct S { unsigned int a : 3; unsigned int b : 5; }; struct S s = {.b = 9}; return s.b; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	mut found := false
	for stmt in body {
		if stmt.kind != .assign {
			continue
		}
		if field := stmt.field {
			if field.bitfield {
				found = true
				assert field.offset == 0
				assert field.bit_offset == 3
				assert field.bit_width == 5
				assert field.unit_width == 4
			}
		}
	}
	assert found
}

// 6.7.2.1 makes a bitfield's width an integer constant expression, so a width
// written as an enum name or a sum is the number it folds to. A width that is
// not positive, one wider than its type, and one the folder cannot compute are
// each refused by name, because a width read as the wrong number lays the object
// out at the wrong size. Measured on gcc 16.2.1: `unsigned int a : 0;` is `zero
// width for bit-field 'a'`, `a : -1` is `negative width in bit-field 'a'`, and
// `unsigned int a : 33;` is `width of 'a' exceeds its type`.
fn test_a_bitfield_width_is_folded_and_a_bad_one_is_refused() {
	folded := declarations_of('enum { W = 2 }; struct S { unsigned int a : W + 1; }; struct S s = {3};')
	assert folded.diagnostics.len == 0
	zero := declarations_of('struct S { unsigned int a : 0; };')
	assert zero.diagnostics.len >= 1
	assert zero.diagnostics.any(it.msg.contains('width of 0'))
	negative := declarations_of('struct S { unsigned int a : -1; };')
	assert negative.diagnostics.len >= 1
	assert negative.diagnostics.any(it.msg.contains('width of -1'))
	wide := declarations_of('struct S { unsigned int a : 33; };')
	assert wide.diagnostics.len >= 1
	assert wide.diagnostics.any(it.msg.contains('exceeds its type'))
	anonymous := declarations_of('struct S { unsigned int : -1; };')
	assert anonymous.diagnostics.len >= 1
	assert anonymous.diagnostics.any(it.msg.contains('unnamed'))
}

// A character constant is a written constant too: 6.4.4.4 gives it the value of
// the character it names and the type int, so `{ 'A' }` is the element `{ 65 }`
// is. Measured on gcc 16.2.1, a program reading the first element of
// `int a[1] = { 'A' };` returns 65.
fn test_a_character_constant_is_a_written_constant_in_a_brace_initializer() {
	result := declarations_of("int a[1] = { 'A' };")
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].inits.len == 1
	assert result.unit.globals[0].inits[0] == 65
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

// The same initializer in a body is the stores the declaration makes where it is
// written, and the name is completed from the literal so a later `sizeof`
// answers with the size the literal fixed. Measured on gcc 16.2.1, a program
// whose `char s[] = "abc";` is a local and that returns `sizeof s` exits 4.
fn test_a_body_char_array_takes_a_string_literal() {
	result := declarations_of('int main(void) { char s[] = "abc"; return sizeof s; }')
	assert result.diagnostics.len == 0
	decl := result.unit.decls[0].body[0]
	assert decl.kind == .var_decl
	assert decl.decl_count == 4
	// One store per element the literal writes, the terminator last.
	mut assigns := 0
	for stmt in result.unit.decls[0].body {
		if stmt.kind == .assign {
			assigns++
		}
	}
	assert assigns == 4
	last := result.unit.decls[0].body[4]
	value := last.expr or {
		assert false
		return
	}
	assert value is ast.IntLit
	if value is ast.IntLit {
		assert value.value == 0
	}
	// A written size is used, and the elements after the terminator stay zero.
	sized := declarations_of('int main(void) { char s[8] = "abc"; return 0; }')
	assert sized.diagnostics.len == 0
	assert sized.unit.decls[0].body[0].decl_count == 8
}

// A wide literal in a body owns four-byte elements the same way it does at file
// scope: `wchar_t w[] = L"abc";` is four of them.
fn test_a_body_wide_array_takes_a_wide_literal() {
	result := declarations_of('typedef int wchar_t;\nint main(void) { wchar_t w[] = L"abc"; return sizeof w; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].body[0].decl_count == 4
}

// A written bound in a body is used and not filled in from the literal:
// `char s[0] = "abc";` and `char s[2] = "abc";` are the constraint violation gcc
// 16.2.1 reports as `initializer-string for array of 'char' is too long`.
fn test_a_body_written_bound_is_not_filled_in_from_a_string_literal() {
	zero := declarations_of('int main(void) { char s[0] = "abc"; return 0; }')
	assert zero.diagnostics.len == 1
	assert zero.diagnostics[0].msg.contains('holds 0 elements and its initializer writes 4')
	too_long := declarations_of('int main(void) { char s[2] = "abc"; return 0; }')
	assert too_long.diagnostics.len == 1
	assert too_long.diagnostics[0].msg.contains('holds 2 elements and its initializer writes 4')
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

// The shapes a body's list takes now: a nested brace, a designator and an
// element that is an expression are all walked against the object's type, and
// each write becomes the store the declaration makes at the subobject it
// reached. The subobjects the list did not reach are stored zero first, because
// the frame slot is whatever was there and the rest of the object is the zeros C
// says it holds (6.7.8p21). A list too long for the array is still one
// diagnostic that names the constraint and the declaration after it is read.
// Measured on gcc 16.2.1, `struct P p = {.b = 2, .a = 1};` reads 1 and 2 for p.a
// and p.b, and `int a[6] = {[4] = 40, [0] = 1, [2] = 20};` reads
// 1, 0, 20, 0, 40, 0.
fn test_a_body_nested_or_designated_list_stores_the_subobject_it_names() {
	result := declarations_of('struct P { int a; int b; };\nint main(void) { struct P p = {.b = 2, .a = 1}; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	mut offsets := []int{}
	mut values := []i64{}
	for stmt in body {
		if stmt.kind != .assign {
			continue
		}
		field := stmt.field or { continue }
		expr := stmt.expr or { continue }
		if expr is ast.IntLit {
			offsets << field.offset
			values << (expr as ast.IntLit).value
		}
	}
	// A zero for each of the two members, then the two values the list wrote, at
	// the offsets the designators named.
	assert offsets == [0, 4, 4, 0]
	assert values == [0, 0, 2, 1]
	designated := declarations_of('int main(void) { int a[6] = {[4] = 40, [0] = 1, [2] = 20}; return 0; }')
	assert designated.diagnostics.len == 0
	assert designated.unit.decls[0].body[0].decl_count == 6
	excess := declarations_of('int main(void) { int a[2] = {1, 2, 3}; return 0; }')
	assert excess.diagnostics.len == 1
	assert excess.diagnostics[0].msg.contains('holds 2 elements')
}

// A pointer array in a body takes the same list as any other: an element is an
// expression the declaration stores, so `&v` and a string literal reach a member
// of pointer type the way any other expression does. Measured on gcc 16.2.1,
// `int v = 1; int *p[2] = {&v, 0};` reads 1 for `*p[0]` and 0 for p[1].
fn test_a_body_list_of_addresses_becomes_the_stores_of_the_elements() {
	result := declarations_of('int main(void) { int v = 1; int *p[2] = {&v, 0}; return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].body[1].decl_count == 2
	mut assigns := 0
	for stmt in result.unit.decls[0].body {
		if stmt.kind == .assign {
			assigns++
		}
	}
	// Two zero stores for the two pointer elements, then the two values.
	assert assigns == 4
}

// An address of a part of an object is a value a body's brace list stores like
// any other. gcc 16.2.1 accepts `int a[2]; int *p[2] = {&a[0], &a[1]};`, and the
// store an element of an array takes evaluates the address where the declaration
// runs, so the byte the part starts at is placed: the two address expressions
// reach the back end as the stores of `p`, one per element.
fn test_a_body_list_that_addresses_a_part_of_an_object_is_stored() {
	result := declarations_of('int main(void) { int a[2] = {1, 2}; int *p[2] = {&a[0], &a[1]}; return 0; }')
	assert result.diagnostics.len == 0
	mut addresses := 0
	for stmt in result.unit.decls[0].body {
		if stmt.kind != .assign {
			continue
		}
		if expr := stmt.expr {
			if expr is ast.Unary {
				if expr.op == '&' && expr.expr is ast.Index {
					addresses++
				}
			}
		}
	}
	assert addresses == 2
}

// An element that begins with a written constant and is longer than one is the
// expression the store takes rather than the constant: `{1 + 1}` is one element
// whose value is two, which gcc 16.2.1 accepts. What ends an element is the comma
// or the closing brace, so anything else after the constant makes the element an
// expression.
fn test_a_body_list_element_that_is_a_constant_expression_is_read() {
	result := declarations_of('int main(void) { int a[2] = {1 + 1, 3}; return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].body[0].decl_count == 2
	mut assigns := 0
	for stmt in result.unit.decls[0].body {
		if stmt.kind == .assign {
			assigns++
		}
	}
	// The two elements are stores, and the zero each element starts as is stored
	// first.
	assert assigns == 4
}

// A struct's brace initializer in a body is the stores the members make at the
// point of the declaration, one per member the list wrote, at the member's own
// offset. Measured on gcc 16.2.1, `struct S s = {5, 6};` returns 56 for
// `s.a * 10 + s.b`.
fn test_a_body_struct_brace_initializer_becomes_the_stores_of_the_members() {
	result := declarations_of('struct S { int a; int b; };\nint main(void) { struct S s = {5, 6}; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 4
	assert body[0].kind == .var_decl
	assert body[1].kind == .assign
	assert (body[1].field or {
		assert false
		return
	}).member == 'a'
	assert (body[2].field or {
		assert false
		return
	}).member == 'b'
	assert body[3].kind == .return_stmt
}

// A list shorter than the members leaves the rest zero (6.7.8p21), and the frame
// slot is whatever was there, so the members the list did not write are stored
// as zero. Measured on gcc 16.2.1, `struct S s = {5};` returns 5 for s.a and 0
// for s.b.
fn test_a_body_struct_brace_initializer_zeroes_the_members_it_did_not_write() {
	result := declarations_of('struct S { int a; int b; };\nint main(void) { struct S s = {5}; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 4
	assert body[1].kind == .assign
	assert (body[1].field or {
		assert false
		return
	}).member == 'a'
	assert body[2].kind == .assign
	assert (body[2].field or {
		assert false
		return
	}).member == 'b'
	zero := body[2].expr or {
		assert false
		return
	}
	assert zero is ast.IntLit
	assert (zero as ast.IntLit).value == 0
}

// An object of a struct type in a body whose member is itself an aggregate is
// initialized leaf by leaf: every scalar subobject is stored zero first, because
// a frame slot starts as whatever was there and 6.7.8p21 makes the subobjects
// the list did not reach hold zero, and then each value the list wrote is stored
// over it. Measured on gcc 16.2.1, `struct S s = {1, 2, 3};` reads t.x 1, t.y 2
// and n 3, and `struct A x = {};` reads every member as zero.
fn test_a_body_list_for_a_struct_with_an_aggregate_member_is_refused() {
	result := declarations_of('struct T { int x; int y; };\nstruct S { struct T t; int n; };\nint main(void) { struct S s = {1, 2, 3}; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	// The declaration, one zero store per scalar leaf, the three written values,
	// and the return.
	assert body.len == 8
	assert body[0].kind == .var_decl
	expected := [i64(0), 0, 0, 1, 2, 3]
	for i in 0 .. expected.len {
		assert body[i + 1].kind == .assign
		value := body[i + 1].expr or {
			assert false
			return
		}
		assert value is ast.IntLit
		assert (value as ast.IntLit).value == expected[i]
	}
	assert body[7].kind == .return_stmt
	// `{}` writes no value, so the leaves it does not write get the zero store
	// and nothing is written over them: the empty list is the limit case.
	empty := declarations_of('struct A { int a[3]; int n; };\nint main(void) { struct A x = {}; return 0; }')
	assert empty.diagnostics.len == 0
	empty_body := empty.unit.decls[0].body
	assert empty_body.len == 6
	for i in 0 .. 4 {
		assert empty_body[i + 1].kind == .assign
		zero := empty_body[i + 1].expr or {
			assert false
			return
		}
		assert zero is ast.IntLit
		assert (zero as ast.IntLit).value == 0
	}
}

// An empty brace list is a list of no written values: 6.7.8p21 leaves every
// subobject of the object zero, at file scope because the storage starts zeroed
// and in a body because every leaf is stored zero. Measured on gcc 16.2.1, a
// struct of scalars and an int both read zero for `= {}`. A value that has no
// conversion to the subobject it would go into is still refused by name: the null
// pointer constant is the one integer a pointer member takes, and a number
// written for one that is not zero is named.
fn test_an_empty_brace_list_writes_no_value() {
	scalar := declarations_of('struct S { int a; int b; };\nstruct S s = {};')
	assert scalar.diagnostics.len == 0
	assert scalar.unit.globals.len == 1
	assert scalar.unit.globals[0].bytes == 8
	assert scalar.unit.globals[0].member_inits.len == 0
	number := declarations_of('int x = {};')
	assert number.diagnostics.len == 0
	assert number.unit.globals.len == 1
	assert number.unit.globals[0].init == none
	array := declarations_of('int a[3] = {};')
	assert array.diagnostics.len == 0
	assert array.unit.globals.len == 1
	assert array.unit.globals[0].count == 3
	assert array.unit.globals[0].inits.len == 0
	// A struct whose aggregate member is left to the walk: a nonzero number has
	// no place in a pointer element, so each one is refused rather than written
	// where a read would take it as an address.
	pin := declarations_of('struct A { int *p[2]; int n; };\nstruct A x = {5, 6, 7};')
	assert pin.diagnostics.len == 2
	assert pin.diagnostics[0].msg.contains('which is a pointer')
	assert pin.diagnostics[1].msg.contains('which is a pointer')
	// In a body the object is stored zero leaf by leaf, because a frame slot is
	// not zeroed the way storage in the image is.
	body := declarations_of('struct S { int a; int b; };\nint main(void) { struct S s = {}; return 0; }')
	assert body.diagnostics.len == 0
	body_stmts := body.unit.decls[0].body
	assert body_stmts.len == 4
	assert body_stmts[0].kind == .var_decl
	assert body_stmts[1].kind == .assign
	assert body_stmts[2].kind == .assign
	assert body_stmts[3].kind == .return_stmt
}

// A file-scope initializer that is a number the literal reader refuses gets the
// refusal the expression path gives it, at the literal as it was written, rather
// than the report for an initializer that is not a number at all. Measured,
// `int x = 0x1.8;` used to exit with a message that the object was initialized
// with something that is not a number, which names neither the construct nor
// where it is.
fn test_a_file_scope_initializer_the_literal_reader_refuses_is_named() {
	result := declarations_of('int x = 0x1.8;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('0x1.8')
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 9
	assert result.unit.globals.len == 0
}

// A file-scope initializer written as one parenthesized number is that number.
// It is the shape a macro that wraps its argument in parentheses writes: the
// corpus reaches `int c99_slot_7 = (7);` through `C99_DECLARE(7)`. Measured on
// gcc 16.2.1, `int c99_slot_7 = (7); int g = (-3);` returns 4 for
// `c99_slot_7 + g`, which is 7 + (-3). An operator after the pair makes the
// initializer an expression, and an expression that is an integer constant
// expression is folded like any other: `int g = (7) + 1;` is 8 to gcc. A comma is
// not an operator a constant expression may have (6.6p3), so `(7, 8)` stays
// refused.
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
	summed := declarations_of('int g = (7) + 1;')
	assert summed.diagnostics.len == 0
	summed_value := summed.unit.globals[0].init or {
		assert false
		return
	}
	assert summed_value == 8
	// A comma is not an operator an integer constant expression may have, so the
	// pair with one after it stays refused by name.
	refused := declarations_of('int g = (7, 8);')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('is initialized with something this compiler cannot write')
}

// A file-scope scalar may be initialized by an integer constant expression, and
// the folder that evaluates a bound evaluates one here too. Measured on gcc
// 16.2.1 under `-std=c99`, `int g = 2 + 3;` is 5, `int g = 1 << 3;` is 8,
// `char g = 2 + 3;` is 5 and `int y = 12 * sizeof(int) - 5 * sizeof(void *);` is
// 8. Reading the first number and stopping defined those as 2 and 1 with no
// diagnostic; refusing them was the same gap as a bound the folder could not
// fold, which is why the file-scope reader now asks the folder before it asks for
// a number.
//
// A shape that is not an integer constant expression is still refused by name: a
// floating constant expression, a name and a call are not constants this reader
// writes into the image, and the whole expression reads as nothing rather than as
// its first term.
fn test_a_file_scope_initializer_that_is_an_integer_constant_expression_is_folded() {
	values := {
		'int g = 2 + 3;':                                 5
		'int g = 1 << 3;':                                8
		'char g = 2 + 3;':                                5
		'int y = 12 * sizeof(int) - 5 * sizeof(void *);': 8
		'int g = 1 ? 5 : 6;':                             5
		'__int128 g = 0 - 100;':                          -100
		'__int128 g = -100 + 0;':                         -100
	}
	for source, expected in values {
		result := declarations_of(source)
		assert result.diagnostics.len == 0
		assert result.unit.globals.len == 1
		value := result.unit.globals[0].init or {
			assert false
			return
		}
		assert value == expected
	}
	// The expressions that are not integer constant expressions stay refused.
	// A floating operand is the one entry that left this list: a floating
	// constant expression is a file-scope constant (6.6p4) and is folded now,
	// so the refusal that covers it is a floating expression over a name.
	refused := [
		'int y = 1;\ndouble g = y + 1.5;',
		'int n = 4;\nint g = n;',
		'int f(void);\nint g = f();',
		'int g = (1, 2);',
	]
	for source in refused {
		result := declarations_of(source)
		assert result.diagnostics.len == 1
		assert result.diagnostics[0].msg.contains('is initialized with something this compiler cannot write')
	}
	// A single number is still read, and its sign with it, which is the shape the
	// language puts in the image.
	kept := declarations_of('int g = -7;')
	assert kept.diagnostics.len == 0
	assert kept.unit.globals.len == 1
	zero := declarations_of('__int128 g = 0;')
	assert zero.diagnostics.len == 0
}

// A pointer object at the top level is one word of storage whatever it points
// at, so a declaration of one is laid out rather than refused, and a null
// pointer constant is the number written into it.
fn test_a_pointer_defined_at_the_top_level_is_storage() {
	result := declarations_of('char *message = 0;')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	object := result.unit.globals[0]
	assert object.name == 'message'
	assert object.count == 0
	assert (object.init or { i64(-1) }) == 0
}

// 6.6p9 makes a cast of an address constant to a pointer or an integer type an
// address constant, and a cast of an integer constant expression to a pointer
// type the same: `((void *)0)` is the null pointer constant `g_main_argv` is
// initialized with in V's generated C (vcc-self.c:5749), `(char *)&x` is the
// address of x, and `(long)&x` is that address in an eight-byte integer object.
// Measured on gcc 16.2.1, all of them are accepted.
fn test_a_cast_in_a_file_scope_initializer_is_an_address_constant() {
	null := declarations_of('void *g = ((void *)0);')
	assert null.diagnostics.len == 0
	assert null.unit.globals.len == 1
	assert (null.unit.globals[0].init or { i64(1) }) == 0
	assert null.unit.globals[0].address == none
	// A cast of an address is the address, dropped to the type it was cast to:
	// the layout writes the reference and not a number.
	pointer := declarations_of('int x = 5;\nchar *p = (char *)&x;')
	assert pointer.diagnostics.len == 0
	address := pointer.unit.globals[1].address or {
		assert false
		return
	}
	assert address.name == 'x'
	integer := declarations_of('int x = 5;\nlong l = (long)&x;')
	assert integer.diagnostics.len == 0
	cast := integer.unit.globals[1].address or {
		assert false
		return
	}
	assert cast.name == 'x'
	// An object narrower than an address cannot hold one, which is what gcc
	// refuses as `initializer element is not computable at load time`; a bare
	// address with no cast is refused for an integer object too.
	narrow := declarations_of('int x = 5;\nint i = (long)&x;')
	assert narrow.diagnostics.len >= 1
	assert narrow.diagnostics[0].msg.contains('narrower than an address')
	bare := declarations_of('int x = 5;\nlong l = &x;')
	assert bare.diagnostics.len == 1
}

// gcc 6.12.24 makes `__PRETTY_FUNCTION__` the string "top level" at file scope,
// where it names no function: measured on gcc 16.2.1, `static const char *const
// top = __PRETTY_FUNCTION__;` compiles to a pointer to "top level". The other two
// spellings name the function they are written in and there is none at file
// scope, so each is refused by name at its own location rather than read as a
// symbol nothing defines.
fn test_pretty_function_at_file_scope_is_the_string_top_level() {
	pretty := declarations_of('static const char *const top = __PRETTY_FUNCTION__;')
	assert pretty.diagnostics.len == 0
	assert pretty.unit.globals.len == 1
	address := pretty.unit.globals[0].address or {
		assert false
		return
	}
	assert address.string
	assert address.name == 'top level'
	for spelling in ['__FUNCTION__', '__func__'] {
		refused := declarations_of('static const char *const top = ${spelling};')
		assert refused.diagnostics.len == 1
		assert refused.diagnostics[0].msg.contains(spelling)
		assert refused.diagnostics[0].msg.contains('file scope')
		assert refused.diagnostics[0].line == 1
	}
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

// A definition whose parameter list ends in an ellipsis is a definition like any
// other: which arguments arrived in registers and which on the stack is what the
// save area records, and the reader carries the ellipsis on the declaration so
// that the back end can lay one out. Nothing here refuses it.
fn test_a_variadic_definition_is_read() {
	result := declarations_of('int f(int a, ...) { return a; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].resolved.variadic
	assert result.unit.decls[0].params.len == 1
}

// `<stdarg.h>` declares the compiler's own spelling of the argument list and
// typedefs the name a program writes from it, so a `va_list` in a program is
// the calling convention's argument list written out. It resolves to a pointer,
// which is what makes a declaration of one a single word of storage and what
// lets a `va_list` be handed to a library function as the address of the tag.
fn test_the_argument_list_resolves_from_the_compiler_spelling() {
	result := declarations_of('typedef __builtin_va_list va_list; int f(int a) { va_list ap; return a; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 2
	assert body[0].kind == .var_decl
	assert body[0].decl_type.contains('*')
	assert body[0].decl_type.contains('__va_list_tag')
}

// C99 6.7.5.3p7: a parameter written with an array type is adjusted to a
// pointer to its element. The tree keeps the adjustment, so a `sizeof` in the
// body and an element read both go through a pointer, and the written type
// gains the star the adjustment adds.
fn test_an_array_parameter_is_adjusted_to_a_pointer() {
	result := declarations_of('int f(char s[10]) { return 0; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params.len == 1
	assert params[0].name == 's'
	assert params[0].typ == 'char *'
	assert params[0].resolved.is_pointer()
	assert params[0].resolved.describe() == 'char *'
}

fn test_an_array_parameter_of_no_written_size_is_adjusted_the_same_way() {
	result := declarations_of('int f(int a[]) { return a[0]; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params[0].typ == 'int *'
	assert params[0].resolved.describe() == 'int *'
}

// A qualifier on the element is part of the pointee and not of the written
// spelling, the same way `const char *__s` keeps only the star.
fn test_a_const_array_parameter_adjusts_to_a_pointer_to_const() {
	result := declarations_of('int f(const char s[]) { return s[0]; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params[0].typ == 'char *'
	assert params[0].resolved.is_pointer()
	assert params[0].resolved.describe() == 'const char *'
}

// An array of pointers adjusts to a pointer to a pointer.
fn test_an_array_parameter_of_pointers_adjusts_to_a_pointer_to_a_pointer() {
	result := declarations_of('int f(char *argv[]) { return 0; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params[0].typ == 'char **'
	assert params[0].resolved.describe() == 'char **'
}

// A multidimensional array parameter adjusts to a pointer to its row type, so
// the body subscripts it twice.
fn test_a_multidimensional_array_parameter_adjusts_to_a_pointer_to_an_array() {
	result := declarations_of('int f(int a[3][4]) { return a[0][0]; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params[0].typ == 'int *'
	assert params[0].resolved.is_pointer()
	row := params[0].resolved.pointee() or {
		assert false
		return
	}
	assert row.kind == .array
	assert row.count == 4
}

// A `static` bound is a promise about the caller and not part of the type: the
// parameter is still one pointer.
fn test_a_static_bound_on_an_array_parameter_does_not_change_the_type() {
	result := declarations_of('int f(int a[static 10]) { return a[0]; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params[0].typ == 'int *'
	assert params[0].resolved.describe() == 'int *'
}

// The adjustment happens at the declaration, so a prototype written `[]` and a
// definition written `*` are one function (6.7.5.3p15).
fn test_an_array_parameter_and_a_pointer_parameter_are_one_type() {
	result := declarations_of('int f(int a[]); int f(int *a) { return 0; }')
	assert result.diagnostics.len == 0
}

// 6.7.5.2p1 makes the element type of an array an object type, so a parameter
// that is an array of void is refused where a `void *` parameter is not.
fn test_an_array_parameter_of_void_is_refused() {
	result := declarations_of('int f(void a[]) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('array of void')
}

// An array parameter's element has to be complete too, which a pointer to the
// same tag does not: `struct S *a` is a parameter this reader can name.
fn test_an_array_parameter_of_an_incomplete_tag_is_refused() {
	result := declarations_of('struct S; int f(struct S a[]) { return a == 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type struct S')
}

fn test_a_parameter_of_a_definition_needs_a_name() {
	result := declarations_of('int f(int) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('needs a name')
}

// A parameter that is a pointer to a tag with no body is a parameter this reader
// can name: the parameter is one address, and the callee needs no size for what
// it points at. Measured, gcc 16.2.1 compiles a definition of `int f(struct S
// *p)` where S has no body anywhere in the file, and refuses `int f(struct S p)`
// ("parameter has incomplete type"), which is the same split a declaration of an
// object gets.
fn test_a_pointer_parameter_to_a_tag_with_no_body_is_accepted() {
	result := declarations_of('struct S; int f(struct S *p) { return p == 0; }')
	assert result.diagnostics.len == 0
	params := result.unit.decls[0].params
	assert params.len == 1
	assert params[0].name == 'p'
	assert params[0].typ == 'struct S *'
}

fn test_an_object_parameter_of_a_tag_with_no_body_is_reported() {
	result := declarations_of('struct S; int f(struct S p) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type struct S')
}

// An alias that names an array is a type the model settled when it read the alias,
// so a pointer to it is a parameter this reader can name. The question is about
// that type and not about the words the file wrote, because `typedef int Arr[4]`
// spells `Arr *` as the array's type and no word of the language is `int[4]`.
// Measured on gcc 16.2.1, which compiles a definition taking `Arr *` and answers
// the same value the direct spelling `int (*p)[4]` answers.
fn test_a_pointer_parameter_to_an_array_alias_is_accepted() {
	direct := declarations_of('int f(int (*p)[4]) { return (*p)[0]; }')
	assert direct.diagnostics.len == 0

	aliased := declarations_of('typedef int Arr[4]; int f(Arr *p) { return (*p)[0]; }')
	assert aliased.diagnostics.len == 0
	last := aliased.unit.decls[aliased.unit.decls.len - 1]
	assert last.params.len == 1
	assert last.params[0].name == 'p'
	assert last.params[0].resolved.describe().contains('[4]')
}

// An alias with no star is an array parameter, which 6.7.5.3p7 adjusts to a
// pointer to its element. This path does not make that adjustment, so it stays
// refused rather than being laid out as an array object and passed as one.
fn test_an_array_alias_parameter_with_no_star_is_still_refused() {
	result := declarations_of('typedef int Arr[4]; int f(Arr p) { return p[0]; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type int[4]')
}

// A definition whose return type is a pointer is a definition like any other.
// The value goes back in the register an int comes back in, and what the pointer
// points at is not laid out at the return, so the reader keeps the type instead
// of refusing it. Measured on gcc 16.2.1, which compiles and runs every program
// below.
fn test_a_definition_may_return_a_pointer() {
	scalar := declarations_of('char *f(void) { return 0; }')
	assert scalar.diagnostics.len == 0
	assert scalar.unit.decls[0].ret == 'char *'
	assert scalar.unit.decls[0].ret_type.describe() == 'char *'

	// The qualifier the type was written with is in the resolved type; the
	// spelling the return conversion reads is the type words with the stars, so
	// the qualifier is not in `ret`.
	qualified := declarations_of('const char *f(void) { return 0; }')
	assert qualified.diagnostics.len == 0
	assert qualified.unit.decls[0].ret == 'char *'
	assert qualified.unit.decls[0].ret_type.describe() == 'const char *'

	voidp := declarations_of('void *f(void) { return 0; }')
	assert voidp.diagnostics.len == 0
	assert voidp.unit.decls[0].ret_type.describe() == 'void *'

	// The 12-level declarator the corpus writes: a function returning a pointer
	// to an array of three ints. The stars the spelling carries are the name's
	// own, and the array is what the pointer points at.
	array := declarations_of('int (*f(void))[3] { return 0; }')
	assert array.diagnostics.len == 0
	assert array.unit.decls[0].ret == 'int *'
	assert array.unit.decls[0].ret_type.describe() == 'int[3]*'
}

// The pointer return rule does not reach inside the star. A pointer to a type
// the emitter has no form for is still one address wide, so it is refused the
// same way a pointer object's declaration is: by naming the word. A bare long
// double is the other side of that: the type holds and the calling convention a
// value of it travels by is written, so both a pointer to one and a value of one
// are accepted. `_Imaginary` is the type that still has no form, because C99
// leaves it optional and this compiler models no value for it; `long double
// _Complex` used to make the point and is now carried.
fn test_a_pointer_to_a_type_the_emitter_has_no_form_for_is_refused_by_name() {
	pointer := declarations_of('long double _Imaginary *f(void) { return 0; }')
	assert pointer.diagnostics.len == 1
	assert pointer.diagnostics[0].msg.contains('unsupported type long')

	value := declarations_of('long double _Imaginary f(void) { return 0; }')
	assert value.diagnostics.len == 1
	assert value.diagnostics[0].msg.contains('unsupported type long')

	long_pointer := declarations_of('long double *f(void) { return 0; }')
	assert long_pointer.diagnostics.len == 0
	assert long_pointer.unit.decls[0].ret_type.describe() == 'long double *'

	long_value := declarations_of('long double f(void) { return 0; }')
	assert long_value.diagnostics.len == 0
	assert long_value.unit.decls[0].ret_type.describe() == 'long double'

	// The extended complex type is a value now, and a definition returning it is
	// a declaration this compiler reads rather than a refusal.
	complex_value := declarations_of('long double _Complex f(void) { return 0; }')
	assert complex_value.diagnostics.len == 0
	assert complex_value.unit.decls[0].ret_type.describe() == 'long double _Complex'
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

// 6.7.6.3p15: a parameter declared with a qualified type is taken as having the
// unqualified version of its declared type, so a qualifier on the parameter's
// own type does not make a second declaration of the name a different type.
// Measured, gcc 16.2.1 under `-std=c99` accepts the two declarations of memcpy
// below; glibc's string.h declares memcpy with `__restrict` on both pointers,
// where the declaration this tree already holds for memcpy spells neither, so
// the pair is a stop on the path to including <string.h>. The qualifier of what
// the parameter points at is not the parameter's own and stays: measured,
// gcc 16.2.1 refuses `void f(void *); void f(const void *);` with
// `conflicting types for f`, and that pair is still refused here.
fn test_a_parameter_qualified_only_on_its_own_type_is_not_a_redeclaration() {
	accepted := declarations_of('void *memcpy(void *d, const void *s, unsigned long n);\nvoid *memcpy(void *restrict d, const void *restrict s, unsigned long n);\nint main(void) { return 0; }')
	assert accepted.diagnostics.len == 0
	// `const` and `volatile` on the parameter's own pointer type are dropped the
	// same way `restrict` is.
	assert declarations_of('void f(int *p);\nvoid f(int *const p);\nint main(void) { return 0; }').diagnostics.len == 0
	assert declarations_of('void f(int *p);\nvoid f(int *volatile p);\nint main(void) { return 0; }').diagnostics.len == 0
	// The qualifier of what the parameter points at is kept, so the two
	// declarations describe two types and the second is the constraint
	// violation gcc reports as `conflicting types for f`.
	pointed_at := declarations_of('void f(void *d);\nvoid f(const void *d);\nint main(void) { return 0; }')
	assert pointed_at.diagnostics.len == 1
	assert pointed_at.diagnostics[0].msg.contains('f is declared as void (void *)')
	assert pointed_at.diagnostics[0].line == 2
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

// A bound that is not an integer constant expression leaves an object at the top
// level without a size the image can carry, which 6.6 makes a constraint
// violation. Measured on gcc 16.2.1 under `-std=c99`, `int a[1/0];` and
// `int n = 3; int a[n];` are both `variably modified 'a' at file scope` and exit
// 1. A body's bound that is not constant declares a variable-length array: the
// object's size is a value the program computes where the declaration runs, so
// the declaration is kept and carries the expression that sizes it.
fn test_a_non_constant_bound_at_file_scope_is_a_constraint_violation() {
	divided := declarations_of('int a[1/0];')
	assert divided.diagnostics.len == 1
	assert divided.diagnostics[0].msg.contains('a constraint violation')
	assert divided.diagnostics[0].msg.contains('is not an integer constant expression')
	assert divided.unit.globals.len == 0
	named := declarations_of('int n = 3;\nint a[n];')
	assert named.diagnostics.len == 1
	assert named.diagnostics[0].msg.contains('a constraint violation')
	assert named.unit.globals.len == 1
	// A dimension inside a written one is the same object and the same refusal.
	inner := declarations_of('int n = 3;\nint a[3][n];')
	assert inner.diagnostics.len == 1
	assert inner.diagnostics[0].msg.contains('a constraint violation')
	// A body's copy of the named bound is the variable-length array itself: the
	// declaration carries the expression that sizes it, which is the bound times
	// the width of an element, and the element width beside it.
	body := declarations_of('int main(void) { int n = 3; int a[n]; return 0; }')
	assert body.diagnostics.len == 0
	decl := body.unit.decls[0].body[1]
	assert decl.decl_vla_size() != none
	assert decl.decl_stride() == 4
}

// The conditional operator is an operator 6.6p3 leaves in a constant expression,
// so a bound written with one is an integer constant expression and the object is
// the size the arm the condition selects names. Measured on gcc 16.2.1 under
// `-std=c99`, `int x[1 ? 2 : 3];` is two ints, `int x[0 ? 2 : 7];` is seven, and
// `int x[1 ? 2 : n]` is two with n a variable because 6.5.15 does not evaluate
// the arm it does not take. The whole expression still has to have an integer
// type: `int x[1 ? 2 : 3.5];` is refused by gcc as `size of array has non-integer
// type`, and the fold answers none for it here as well.
fn test_a_conditional_bound_is_an_integer_constant_expression() {
	taken := declarations_of('int x[1 ? 2 : 3];')
	assert taken.diagnostics.len == 0
	assert taken.unit.globals.len == 1
	assert taken.unit.globals[0].count == 2
	perhaps := declarations_of('int x[0 ? 2 : 7];')
	assert perhaps.diagnostics.len == 0
	assert perhaps.unit.globals[0].count == 7
	// The arm that does not run does not have to be a constant: this is the
	// short-circuit 6.5.15 makes and gcc confirms, so the count is the then arm.
	short := declarations_of('int n = 4;\nint x[1 ? 5 : n];')
	assert short.diagnostics.len == 0
	assert short.unit.globals[1].count == 5
	// An arm of a floating type makes the conditional a double, which no array
	// size is: the fold answers none and the file-scope check refuses the bound.
	floating := declarations_of('int x[1 ? 2 : 3.5];')
	assert floating.diagnostics.len == 1
	assert floating.diagnostics[0].msg.contains('is not an integer constant expression')
}

// 6.6p3 excludes assignment, increment, decrement, function call and comma from a
// constant expression and leaves everything else in, so the shifts, the four
// comparisons, the two equalities, the three bitwise operators, the two logical
// operators and the prefix `~` and `!` all fold. Measured one at a time against
// gcc 16.2.1 under `-std=c99`, each bound here is the size of the value it names:
// `4 && 1` and `4 > 1` and `4 == 4` and `!0` are one, `16 >> 2` and `1 << 2` are
// four, `2 | 1` is three, `6 ^ 3` is five and `6 & 3` is two.
fn test_a_bitwise_relational_or_logical_bound_is_an_integer_constant_expression() {
	controls := [
		'int x[4 && 1];',
		'int x[4 > 1];',
		'int x[4 == 4];',
		'int x[!0];',
		'int x[16 >> 2];',
		'int x[1 << 2];',
		'int x[2 | 1];',
		'int x[6 ^ 3];',
		'int x[6 & 3];',
	]
	expected := [1, 1, 1, 1, 4, 4, 3, 5, 2]
	for index, source in controls {
		result := declarations_of(source)
		assert result.diagnostics.len == 0
		assert result.unit.globals[0].count == expected[index]
	}
	// `~` and `!` are prefix operators over a constant: `(~0 & 3) + 1` is four
	// and `!7 + 3` is three, and both are positive so the count is the value.
	prefix := declarations_of('int x[(~0 & 3) + 1];\nint y[!7 + 3];')
	assert prefix.diagnostics.len == 0
	assert prefix.unit.globals[0].count == 4
	assert prefix.unit.globals[1].count == 3
	// A logical operator does not evaluate the operand its result does not need,
	// which gcc confirms: `1 || f()` and `0 && n` are accepted at file scope with
	// f a function and n a variable, while `2 && f()` has to read f() and is
	// refused.
	short := declarations_of('int f(void);\nint n = 4;\nint x[1 || f()];\nint y[0 && n];')
	assert short.diagnostics.len == 0
	// globals holds the objects in order: n, then x, then y. `1 || f()` is one and
	// `0 && n` is zero, and neither read the operand the result does not need.
	assert short.unit.globals.len == 3
	assert short.unit.globals[1].count == 1
	assert short.unit.globals[2].count == 0
	needed := declarations_of('int f(void);\nint x[2 && f()];')
	assert needed.diagnostics.len == 1
	assert needed.diagnostics[0].msg.contains('is not an integer constant expression')
	// Division by zero is still not a value this reader answers, so a bound
	// written with one leaves the object without a size and is refused.
	divided := declarations_of('int x[4 / 0];')
	assert divided.diagnostics.len == 1
	assert divided.diagnostics[0].msg.contains('is not an integer constant expression')
}

// 6.6p6 admits a floating constant to an integer constant expression as the
// immediate operand of a cast to an integer type, which is the one floating shape
// an array size may be built from. Measured on gcc 16.2.1 under `-std=c99`, `int
// x[(int) 3.5];` is three elements and `int x[(char) 300.9];` is 44, because the
// conversion truncates toward zero and then narrows. A floating constant that is
// not the operand of a cast is not an operand at all - `int x[1.5];` is `size of
// array has non-integer type` to gcc - and a cast whose target is not an integer
// type is refused the same way, so the fold answers none for both.
fn test_a_floating_constant_as_the_immediate_operand_of_a_cast_is_a_bound() {
	whole := declarations_of('int x[(int) 3.5];')
	assert whole.diagnostics.len == 0
	assert whole.unit.globals[0].count == 3
	narrowed := declarations_of('int x[(char) 300.9];')
	assert narrowed.diagnostics.len == 0
	assert narrowed.unit.globals[0].count == 44
	// A sign in front of the floating constant is the same operand: `(int) -0.5`
	// is zero, which gcc gives `int x[(int) -0.5];` too.
	signed := declarations_of('int x[(int) -0.5 + 4];')
	assert signed.diagnostics.len == 0
	assert signed.unit.globals[0].count == 4
	// Not under a cast: no.
	loose := declarations_of('int x[1.5];')
	assert loose.diagnostics.len == 1
	assert loose.diagnostics[0].msg.contains('is not an integer constant expression')
	// A cast to a floating type is one 6.6p6 does not allow.
	target := declarations_of('int x[(double) 3];')
	assert target.diagnostics.len == 1
	assert target.diagnostics[0].msg.contains('is not an integer constant expression')
}

// A file-scope bound that names something the file declares nowhere is that
// name's failure and not the object's. An enumeration constant is not such a
// name - it is a value the enum gives it, so `enum { N = 4 }; int x[N];` is a
// bound of four and says nothing at all - and the undeclared name has to be one
// the file never gives a value to. Reporting the bound as not an integer constant
// expression would name a cause the compiler cannot show, and a wrong cause is
// worse than a narrower message. Whether the name is declared is asked once the
// whole file has been read, so a name declared after the bound still gets the
// object's own report.
fn test_a_bound_that_names_an_undeclared_name_is_reported_as_that_name() {
	missing := declarations_of('int y;\nint x[nowhere];')
	assert missing.diagnostics.len == 1
	assert missing.diagnostics[0].msg.contains('nowhere is used here and nothing in this file declares it')
	assert !missing.diagnostics[0].msg.contains('is not an integer constant expression')
	assert missing.diagnostics[0].line == 2
	// An enumeration constant is a constant, so a bound that names one is the
	// object's to answer for and there is nothing to report.
	constant := declarations_of('enum { N = 4 };\nint x[N];')
	assert constant.diagnostics.len == 0
	// A name the file declares later is a bound that is not constant, and the
	// report says that, because the question is asked with the whole file read.
	later := declarations_of('int x[n];\nint n = 4;')
	assert later.diagnostics.len == 1
	assert later.diagnostics[0].msg.contains('is not an integer constant expression')
	// A name the file already declares is the same report, and it is not held.
	earlier := declarations_of('int n = 4;\nint x[n];')
	assert earlier.diagnostics.len == 1
	assert earlier.diagnostics[0].msg.contains('is not an integer constant expression')
}

// A declaration inside a body may write a type and no object, which is what
// `struct point { int x; };` and `enum { A = 5, B = 6 };` do: 6.7 makes the
// declarator list optional, and the declaration is still the one that declares
// the tag and, for an enum, the names with their values. The body that follows
// uses the names, so a name the declaration failed to make is reported as a name
// nothing declares.
fn test_a_declaration_in_a_body_may_write_a_tag_and_no_object() {
	aggregate := declarations_of('int main(void) { struct point { int x; }; return 0; }')
	assert aggregate.diagnostics.len == 0
	enumeration := declarations_of('int main(void) { enum { A = 5, B = 6, C = 7 }; return A + B + C; }')
	assert enumeration.diagnostics.len == 0
	tagged := declarations_of('int main(void) { enum colour { RED = 1, GREEN }; return GREEN; }')
	assert tagged.diagnostics.len == 0
}

// A static assertion declares no object and produces no code: the check runs
// where the declaration is read. Measured on gcc 16.2.1, the two positions it
// may be written in answer the same way, so both are tested here. Before this
// reader the two positions answered wrong and differently: at file scope the
// words were refused as `expected a declaration`, and in a body the statement
// reader took them for an expression.
fn test_a_passing_static_assertion_is_read_in_both_positions() {
	file_scope := declarations_of('_Static_assert(1, "ok");\nint main(void) { return 0; }')
	assert file_scope.diagnostics.len == 0
	assert file_scope.unit.decls.len == 1
	in_body := declarations_of('int main(void) { _Static_assert(1, "ok"); return 0; }')
	assert in_body.diagnostics.len == 0
	assert in_body.unit.decls[0].body.len == 1
}

// A false condition is a diagnostic carrying the message the source wrote, the
// way gcc 16.2.1 writes it: `static assertion failed: "must fail"`.
fn test_a_failing_static_assertion_names_its_message() {
	file_scope := declarations_of('_Static_assert(0, "must fail");\nint main(void) { return 0; }')
	assert file_scope.diagnostics.len == 1
	assert file_scope.diagnostics[0].msg == 'static assertion failed: "must fail"'
	assert file_scope.diagnostics[0].line == 1
	assert file_scope.diagnostics[0].col == 1
	in_body := declarations_of('int main(void) { _Static_assert(0, "body fail"); return 0; }')
	assert in_body.diagnostics.len == 1
	assert in_body.diagnostics[0].msg == 'static assertion failed: "body fail"'
	assert in_body.diagnostics[0].col == 18
}

// C23 made the message optional, and the condition is tested either way. The
// shape under test folds through `sizeof`, which its own reader turns into an
// integer constant before this reader sees it.
fn test_a_static_assertion_without_a_message_still_tests_its_condition() {
	ok := declarations_of('_Static_assert(sizeof(int) == 4);\nint main(void) { return 0; }')
	assert ok.diagnostics.len == 0
	failed := declarations_of('_Static_assert(sizeof(int) == 8);\nint main(void) { return 0; }')
	assert failed.diagnostics.len == 1
	assert failed.diagnostics[0].msg == 'static assertion failed: ""'
}

// A condition this reader cannot reduce to an integer constant is refused by
// name rather than assumed true.
fn test_a_condition_that_is_not_an_integer_constant_is_refused() {
	result := declarations_of('int n = 1;\n_Static_assert(n, "not constant");\nint main(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('is not an integer constant expression')
}

// The message has to be a string literal, and a shape that is not one is named
// where it was written.
fn test_a_static_assertion_message_that_is_not_a_string_is_refused() {
	result := declarations_of('_Static_assert(1, 2);\nint main(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('expected the message of a static assertion')
}

// C23's auto takes the type of its initializer, after the lvalue conversion an
// assignment makes. Measured on gcc 16.2.1, `auto x = 1;` is an int, `auto d =
// 2.5;` a double, `auto u = 1u;` an unsigned int and `auto s = "hi";` a char *,
// and the declaration's own spelling is the deduced type because there is no
// other answer to write down.
fn test_a_local_auto_takes_the_type_of_its_initializer() {
	result := declarations_of('int main(void) { auto x = 1; auto d = 2.5; auto u = 1u; auto s = "hi"; auto l = 2L; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 6
	assert body[0].decl_type == 'int'
	assert body[1].decl_type == 'double'
	assert body[2].decl_type == 'unsigned int'
	assert body[3].decl_type == 'char *'
	assert body[4].decl_type == 'long'
}

// C23 requires the initializer: there is nothing to take the type from, and the
// error names that rather than leaving the object with the word auto for a type.
fn test_an_auto_declaration_without_an_initializer_is_refused_by_name() {
	result := declarations_of('int main(void) { auto x; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('auto needs an initializer')
}

// C23 asks for one declarator and a plain identifier, and neither is assumed:
// each is refused by name at the declaration that wrote it.
fn test_auto_needs_a_plain_identifier_and_one_declarator() {
	pointer := declarations_of('int main(void) { auto *p = 0; return 0; }')
	assert pointer.diagnostics.len == 1
	assert pointer.diagnostics[0].msg.contains('needs a plain identifier')
	two := declarations_of('int main(void) { auto x = 1, y = 2; return 0; }')
	assert two.diagnostics.len == 1
	assert two.diagnostics[0].msg.contains('only one declarator')
}

// The word is also the C89 storage class, and a declaration with a type between
// the word and the name is still that storage class: `auto int x;` declares an
// int, and the name after it is deduced only from what it is given.
fn test_auto_with_a_type_after_it_is_still_the_storage_class() {
	result := declarations_of('int main(void) { auto int x = 1; auto y = x; return y; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].body[0].decl_type == 'int'
	assert result.unit.decls[0].body[1].decl_type == 'int'
}

// Measured on gcc 16.2.1, C23's auto is taken at file scope too and the object is
// a definition: `auto x = 2.5;` defines a double, and `auto u = 1u;` an unsigned
// int, which is why the type cannot be read off the folded number alone.
fn test_a_file_scope_auto_defines_an_object_of_the_initializer_type() {
	result := declarations_of('auto x = 2.5;\nauto u = 1u;\nint main(void) { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 2
	assert result.unit.globals[0].typ == 'double'
	assert result.unit.globals[1].typ == 'unsigned int'
}

// A file-scope auto is storage the image lays out, so the same constraint holds:
// there is no object without an initializer.
fn test_a_file_scope_auto_without_an_initializer_is_refused_by_name() {
	result := declarations_of('auto x;\nint main(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('auto needs an initializer')
}

// The decimal floating types are types the language has and this compiler does
// not write. Each is refused by name where the declaration asks for it, rather
// than left to be read as a name the file never declared: a program that writes
// one is a program about that construct, and the diagnostic has to say so. The
// words are reserved here for the same reason, so one of them cannot quietly
// become an object's name either.
fn test_a_decimal_floating_type_is_refused_by_name_at_its_declaration() {
	result := declarations_of('_Decimal32 a = 1;\n_Decimal64 b = 2;\n_Decimal128 c = 3;\n')
	assert result.diagnostics.len == 3
	assert result.diagnostics[0].msg.contains('unsupported type _Decimal32')
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[1].msg.contains('unsupported type _Decimal64')
	assert result.diagnostics[2].msg.contains('unsupported type _Decimal128')
}

// A decimal type resolves to no size, so a `sizeof` of one is refused by name
// too, which is the other half of the same construct: the test that measures the
// three types asks for it there as well.
fn test_a_sizeof_of_a_decimal_floating_type_is_refused_by_name() {
	result := declarations_of('int f(void) {\n	int n = sizeof(_Decimal32);\n	return n;\n}\n')
	assert result.diagnostics.len > 0
	assert result.diagnostics.any(it.msg.contains('_Decimal32'))
}
