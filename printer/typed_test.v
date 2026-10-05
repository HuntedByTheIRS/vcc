module printer

import ast
import parser
import tokenize
import types

// `-print-ast` is the surface this milestone is read from: one line per node, and
// after the location it came from, the type the model resolved it to. These tests
// read that text, one construct per type, so that a change which loses a clause or
// resolves it to the wrong type fails here rather than in a reader's head.
//
// The fixture names every type in a *declaration* rather than in an object, where
// it can: the back end has forms for three types, and a definition of anything
// else is refused before it reaches the printer. A prototype promises and is kept,
// so `struct point origin(void);` renders the type a later milestone will emit
// from, and the refusal it will replace is named in the feature table.

// every_type is a file with no diagnostics whose tree carries one clause per type
// the model has.
const every_type = 'typedef unsigned long ulong;
struct point { int x; int y; };
union value { int i; char c; };
enum colour { red, green };
struct later;
_Bool flag(void);
char letter(void);
short small(void);
int count(void);
unsigned int counted(void);
long wide(void);
long long wider(void);
float ratio(void);
double precise(void);
long double widest(void);
double _Complex pair(void);
struct point origin(void);
union value pick(void);
enum colour next(void);
int *pointer_to_int(char *s, int n);
int apply(int (*f)(int, int), int x);
int counter;
char name[8];
int table[4];
int add(int a, int b) { return a + b; }'

fn parsed(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed_result := parser.parse(lexed.tokens)
	assert parsed_result.diagnostics.len == 0
	return parsed_result.unit
}

// printed_lines is render split into the lines a reader compares. It is defined
// here rather than shared with the other test file because each `_test.v` file is
// compiled on its own.
fn printed_lines(unit ast.TranslationUnit) []string {
	return render(unit).split_into_lines()
}

// clause_after is the part of a line after its location and its type clause: what
// the model answered for it.
fn clause_after(line string) string {
	parts := line.split(' : ')
	if parts.len < 2 {
		return ''
	}
	return parts[1]
}

// clause_of_declaration is the clause of the declaration line that names a thing:
// a function, a global, or a declaration inside a body.
fn clause_of_declaration(printed []string, head string) string {
	for line in printed {
		if line.starts_with(head) || line.trim_space().starts_with(head) {
			return clause_after(line)
		}
	}
	return ''
}

fn test_one_clause_per_type_in_a_file_the_emitter_can_read() {
	printed := printed_lines(parsed(every_type))
	// The scalars, written as the return type of a function that promises one.
	assert clause_of_declaration(printed, 'fn flag() _Bool') == '_Bool (void)'
	assert clause_of_declaration(printed, 'fn letter() char') == 'char (void)'
	assert clause_of_declaration(printed, 'fn small() short') == 'short (void)'
	assert clause_of_declaration(printed, 'fn count() int') == 'int (void)'
	assert clause_of_declaration(printed, 'fn counted() unsigned int') == 'unsigned int (void)'
	assert clause_of_declaration(printed, 'fn wide() long') == 'long (void)'
	assert clause_of_declaration(printed, 'fn wider() long long') == 'long long (void)'
	assert clause_of_declaration(printed, 'fn ratio() float') == 'float (void)'
	assert clause_of_declaration(printed, 'fn precise() double') == 'double (void)'
	assert clause_of_declaration(printed, 'fn widest() long double') == 'long double (void)'
	assert clause_of_declaration(printed, 'fn pair() double _Complex') == 'double _Complex (void)'
	// The derived types.
	assert clause_of_declaration(printed, 'fn pointer_to_int() int *') == 'int * (char *, int)'
	assert clause_of_declaration(printed, 'fn apply() int') == 'int (int (int, int) *, int)'
	assert clause_of_declaration(printed, 'global table int[4]') == 'int[4]'
	assert clause_of_declaration(printed, 'global name char[8]') == 'char[8]'
	assert clause_of_declaration(printed, 'global counter int') == 'int'
	// The aggregates.
	assert clause_of_declaration(printed, 'fn origin() struct point') == 'struct point (void)'
	assert clause_of_declaration(printed, 'fn pick() union value') == 'union value (void)'
	// An enumerator list settles the integer type the enum has, so the head is
	// the type gcc gives the enum and the emitter reads, and the clause after
	// the colon is the tag the model kept. This is the same reading a typedef
	// name gets: `typedef int T; T f(void);` prints `fn f() int`, not `T`.
	assert clause_of_declaration(printed, 'fn next() unsigned int') == 'enum colour (void)'
	// A definition, which the emitter does have a form for.
	assert clause_of_declaration(printed, 'fn add() int') == 'int (int, int)'
}

fn test_a_local_declaration_and_its_initializer_carry_their_clauses() {
	printed := printed_lines(parsed('int main(void) { int x = 1; char c = 97; while (x < 2) { x = x + 1; } return x; }'))
	assert clause_of_declaration(printed, 'declaration of int x') == 'int'
	assert clause_of_declaration(printed, 'declaration of char c') == 'char'
	assert clause_of_declaration(printed, 'int 1 at') == 'int'
	assert clause_of_declaration(printed, 'int 97 at') == 'int'
	assert clause_of_declaration(printed, 'ident x at') == 'int'
	// A comparison answers with an int whatever its operands were.
	assert clause_of_declaration(printed, 'binary < at') == 'int'
	assert clause_of_declaration(printed, 'binary + at') == 'int'
}

fn test_a_parameter_resolves_to_the_type_it_was_declared_with() {
	printed := printed_lines(parsed('int add(int a, char b) { return a + b; }'))
	// The return is the conversion of the two operands, and b is a char because
	// that is what it was declared as.
	for line in printed {
		if line.contains('ident b') {
			assert clause_after(line) == 'char'
		}
		if line.contains('binary +') {
			assert clause_after(line) == 'int'
		}
	}
}

fn test_a_node_the_model_has_no_answer_for_is_refused_rather_than_written() {
	// A name nothing in the unit declares has no type, so the node for it is
	// refused and the printer names what the model did not answer rather than
	// inventing a type for it. The dump says `unresolved` for that node and for
	// the sum that reads it. A decimal constant that fits no signed type used to
	// be the other half of this file; it is accepted as `unsigned long long` now
	// (the extension gcc performs with the warning `integer constant is so large
	// that it is unsigned`), so the dump prints it with the clause the model gave
	// it rather than `unresolved`.
	lexed := tokenize.lex('int main(void) { return missing + 18446744073709551615; }')
	refused := parser.parse(lexed.tokens)
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('missing')
	assert refused.diagnostics[0].line == 1
	assert refused.diagnostics[0].col == 25
	printed := printed_lines(refused.unit)
	assert clause_of_declaration(printed, 'ident missing') == 'unresolved'
	// The dump prints the constant's value rather than its spelling, and
	// 18446744073709551615 is the 64-bit pattern -1 read as a signed value.
	assert clause_of_declaration(printed, 'int -1') == 'unsigned long long'
	assert clause_of_declaration(printed, 'binary +') == 'unresolved'
	// The other side of the same boundary: the two constants the description
	// carries a width for are answered, and the printer shows the clause the
	// model gave each of them rather than the one the spelling suggests.
	carried := printed_lines(parsed('int main(void) { return 100000 + 0xffffffff; }'))
	assert clause_of_declaration(carried, 'int 100000') == 'int'
	assert clause_of_declaration(carried, 'int 4294967295') == 'unsigned int'
	// The return type of the definition was resolved, so the function line keeps
	// its clause and is not written off with the rest.
	assert clause_of_declaration(printed, 'fn main() int') == 'int (void)'
	// A call to a name the unit declares is checked against that declaration,
	// and its clause is what the declaration returns: the model has an answer
	// for the node because it has a declaration to take it from. A call to a
	// name nothing in the unit declares is refused once the whole unit has been
	// read, so no such call reaches the printer as an unresolved node.
	library := printed_lines(parsed('int abs(int n);\nint main(void) { return abs(-7) - 6; }'))
	assert clause_of_declaration(library, 'call abs') == 'int'
}

fn test_a_clause_is_the_models_answer_and_not_the_spelling() {
	// `struct point` as written and `struct point` as resolved read the same
	// here, which is the point of printing both: a reader comparing the two sees
	// where a declaration was read and where it was resolved. The typedef case is
	// where they differ, and a typedef has no declarator of its own to print.
	printed := printed_lines(parsed('struct point { int x; int y; };\nint f(struct point p);'))
	assert clause_of_declaration(printed, 'fn f() int') == 'int (struct point)'
}

// The clause of a node the model could not answer for is the word unresolved
// and not an empty string. Printing nothing would read the same as a node this
// printer has no clause for, which is the difference the clause exists to draw.
fn test_the_clause_of_an_unresolved_type_says_so() {
	assert typed(types.Type{}) == ' : unresolved'
	assert types.Type{}.describe() == 'unresolved'
}

// A resolved basic type is spelled the way a declaration writes it, so the
// clause after the location is the model's answer and not the source spelling.
fn test_the_clause_of_a_resolved_basic_type() {
	assert typed(types.int_type()) == ' : int'
	assert typed(types.bool_type()) == ' : _Bool'
	assert typed(types.double_type()) == ' : double'
	assert typed(types.long_double_type()) == ' : long double'
}

// Qualifiers are part of the type and are written in the clause. A qualified
// scalar puts them before the type; a qualified pointer puts them after, since
// the const on a pointer is the pointer's own and the const on its base is
// already in the base's description.
fn test_the_clause_carries_the_qualifiers() {
	const_int := types.Type{
		kind:  .int_
		quals: types.Qualifiers{
			const_: true
		}
	}
	assert typed(const_int) == ' : const int'
	mut pointer := types.pointer_to(types.int_type())
	pointer.quals = types.Qualifiers{
		const_: true
	}
	assert typed(pointer) == ' : int * const'
	volatile_char := types.Type{
		kind:  .char_
		quals: types.Qualifiers{
			volatile_: true
		}
	}
	assert typed(types.pointer_to(volatile_char)) == ' : volatile char *'
}

// A pointer type in the clause is the base description and a star, with a space
// before the star for a scalar base and no space for one that is itself a
// pointer or an array.
fn test_the_clause_of_a_pointer_type() {
	assert typed(types.pointer_to(types.int_type())) == ' : int *'
	assert typed(types.pointer_to(types.pointer_to(types.char_type()))) == ' : char **'
}

// An array and a function in the clause spell their element or return type and
// then their own shape: the count in brackets, or the parameter list. A
// prototype with no parameters is (void); one written without a prototype is
// ().
fn test_the_clause_of_an_array_and_a_function_type() {
	assert typed(types.array_of(types.int_type(), 4)) == ' : int[4]'
	assert typed(types.array_of(types.char_type(), 8)) == ' : char[8]'
	two_params := [
		types.Param{
			typ: types.int_type()
		},
		types.Param{
			typ: types.int_type()
		},
	]
	assert typed(types.function_type(types.int_type(), two_params, false, true)) == ' : int (int, int)'
	assert typed(types.function_type(types.int_type(), []types.Param{}, false, true)) == ' : int (void)'
	assert typed(types.function_type(types.int_type(), []types.Param{}, false, false)) == ' : int ()'
}

// The printer writes one of two clauses: the word unresolved for a node the
// model had no answer for, and the description of the type for one it did. Both
// carry the same leading space and colon, so a reader splits a line on it the
// same way whichever it is.
fn test_the_two_clauses_the_printer_can_write() {
	unresolved := typed(types.Type{})
	resolved := typed(types.int_type())
	assert unresolved == ' : unresolved'
	assert resolved == ' : int'
	assert unresolved.starts_with(' : ')
	assert resolved.starts_with(' : ')
	assert unresolved[3..] == 'unresolved'
}
