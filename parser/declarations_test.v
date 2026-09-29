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
	assert 'puts' !in names // the call needs no prototype to parse
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
	assert result.unit.decls[0].ret == 'size_t'
}

fn test_an_extern_object_is_read_and_dropped() {
	result := declarations_of('extern FILE *stdout;')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 0
}

// An initializer makes the declaration a definition even when it says extern,
// and a definition is storage the image holds. A brace list is not a number this
// compiler can write into the image, so the definition is reported rather than
// laid out as something it is not.
fn test_an_extern_object_with_a_brace_initializer_is_reported() {
	result := declarations_of('extern int table[4] = { 1, 2, 3, 4 };')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('not a number')
	assert result.unit.globals.len == 0
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

// A pointer at the top level is a relocation this compiler does not write yet,
// so the definition is reported instead of laid out as a wrong number.
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
