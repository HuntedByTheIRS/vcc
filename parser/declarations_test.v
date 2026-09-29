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
// and a definition is storage this compiler cannot emit yet.
fn test_an_extern_object_with_an_initializer_is_a_definition() {
	result := declarations_of('extern int table[4] = { 1, 2, 3, 4 };')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('only function definitions')
}

fn test_a_definition_of_an_object_is_still_reported() {
	result := declarations_of('int counter;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('only function definitions')
}

fn test_a_definition_with_pointer_parameters_is_reported() {
	result := declarations_of('int main(int argc, char **argv) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('pointer parameters')
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
