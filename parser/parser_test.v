module parser

import ast
import tokenize
import types

fn parsed(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// The tokens of a source as if a header had been read: the file a token came from
// is filled in by the preprocessor for every file it reads, and this is that
// answer without a preprocessor.
fn parsed_from(source string, file string) Result {
	mut tokens := tokenize.lex(source).tokens
	for i in 0 .. tokens.len {
		tokens[i] = tokenize.Token{
			...tokens[i]
			file: file
		}
	}
	return parse(tokens)
}

fn test_a_diagnostic_names_the_file_its_token_came_from() {
	// Measured: `#include <stdlib.h>` over a two-line program reported
	// `prog.c:33:1: unsupported type unsigned`, a line the program does not have,
	// because the parser reported a header's position under the name of the file
	// it was handed. The preprocessor fills a token's file in, and the message
	// names that.
	result := parsed_from('unsigned int f() { return 1; }', '/usr/include/stdlib.h')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].file == '/usr/include/stdlib.h'
}

// The 128-bit type is gcc's, and the tree reads it by name wherever a type can
// be written: its size is a question the model answers, and a declaration of an
// object of one is refused with the spelling that was written, because the back
// end has no value of that width. Measured on gcc 16.2.1, `sizeof(__int128)` and
// `sizeof(unsigned __int128)` are both 16.
fn test_the_128_bit_type_is_read_by_name() {
	// `sizeof` of it is 16, and so is the unsigned spelling and the one with
	// `signed` in front of it. Measured on gcc 16.2.1.
	result := parsed('int main(void) { return sizeof(__int128) + sizeof(unsigned __int128) + sizeof(signed __int128); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	sum := expr as ast.Binary
	within := sum.left as ast.Binary
	assert (within.left as ast.IntLit).value == 16
	assert (within.right as ast.IntLit).value == 16
	assert (sum.right as ast.IntLit).value == 16
	// A qualifier written in front of it does not change the type, which is what
	// makes `const __int128` the same width.
	qualified := parsed('int main(void) { return sizeof(const __int128); }')
	assert qualified.diagnostics.len == 0
	alone := qualified.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (alone as ast.IntLit).value == 16
}

// An object of the 128-bit type is storage: a declaration of one is read, and the
// questions about a value of that width are the emitter's rather than the reader's.
// Reading one as a value is refused there by name, which is where the emitter
// tests check it.
fn test_an_object_of_the_128_bit_type_is_read_as_storage() {
	signed_up := parsed('int main(void) { __int128 v = 5; return 0; }')
	assert signed_up.diagnostics.len == 0
	body := signed_up.unit.decls[0].body
	assert body[0].decl_type == '__int128'
	unsigned_one := parsed('int main(void) { unsigned __int128 w = 5; return 0; }')
	assert unsigned_one.diagnostics.len == 0
	assert unsigned_one.unit.decls[0].body[0].decl_type == 'unsigned __int128'
}

// The four shapes a function can write the type in: a prototype, a definition
// whose parameter is one, a definition that returns one, and a call to it. The
// reader takes all four, because a type whose width the model knows is a type it
// can name wherever a type is written. Measured on gcc 16.2.1, which accepts all
// four under `-std=c99`. Whether a value of sixteen bytes can be handed over is
// the emitter's question, and it answers it by name rather than silently.
fn test_the_128_bit_type_is_read_in_a_parameter_list_and_as_a_return() {
	// A prototype naming the type, which is a promise and no code.
	prototype := parsed('int f(__int128 v);')
	assert prototype.diagnostics.len == 0
	assert prototype.unit.decls.len == 1
	assert prototype.unit.decls[0].body.len == 0
	// A definition whose parameter is one.
	defined := parsed('int f(__int128 v) { return 0; }')
	assert defined.diagnostics.len == 0
	assert defined.unit.decls.len == 1
	// A definition that returns one, and the unsigned spelling in both
	// positions, which is the other type the model has.
	returning := parsed('__int128 f(void) { return 0; }')
	assert returning.diagnostics.len == 0
	unsigned_one := parsed('unsigned __int128 f(unsigned __int128 v);')
	assert unsigned_one.diagnostics.len == 0
	// A call to a function whose prototype names the type. The argument has the
	// type the parameter was declared with, so the call is the call it looks
	// like rather than a conversion.
	call := parsed('int f(__int128 v);\nint main(void) { __int128 x = 3; return f(x); }')
	assert call.diagnostics.len == 0
	assert call.unit.decls.len == 2
}

fn test_a_function_that_returns_a_constant() {
	result := parsed('int main() { return 42; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 1
	decl := result.unit.decls[0]
	assert decl.name == 'main'
	assert decl.ret == 'int'
	assert decl.body.len == 1
	assert decl.body[0].kind == .return_stmt
	expr := decl.body[0].expr or {
		assert false
		return
	}
	assert expr is ast.IntLit
	assert (expr as ast.IntLit).value == 42
}

// The parser recurses through parentheses, so a file with thousands of them used
// to run the stack out. It is reported now, which is what a compiler owes a file
// it cannot compile.
fn test_deeply_nested_parentheses_are_reported() {
	depth := max_expression_depth + 100
	result := parsed('int main() { return ${'('.repeat(depth)}1${')'.repeat(depth)}; }')
	mut reported := false
	for diagnostic in result.diagnostics {
		if diagnostic.msg.contains('nested more than') {
			reported = true
		}
	}
	assert reported
}

fn test_operators_bind_by_precedence() {
	result := parsed('int main() { return 2 + 3 * 4; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '+'
	assert binary.right is ast.Binary
	assert (binary.right as ast.Binary).op == '*'
}

fn test_parentheses_override_precedence() {
	result := parsed('int main() { return (2 + 3) * 4; }')
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	binary := expr as ast.Binary
	assert binary.op == '*'
	assert binary.left is ast.Binary
}

fn test_unary_minus_is_kept() {
	result := parsed('int main() { return -7; }')
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Unary
	assert (expr as ast.Unary).op == '-'
}

fn test_a_prototype_and_a_definition_both_parse() {
	result := parsed('int main(void); int main(void) { return 1; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 2
	assert result.unit.decls[0].body.len == 0
	assert result.unit.decls[1].body.len == 1
}

fn test_an_empty_statement_is_dropped_and_a_block_is_unwrapped() {
	result := parsed('int main() { ; { return 1; } }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 1
	assert body[0].kind == .block
	assert body[0].body.len == 1
}

fn test_an_unsupported_type_names_the_type() {
	result := parsed('unsigned int f() { return 1; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('unsigned')
	assert result.diagnostics[0].line == 1
}

// `sizeof` is an operator and not a call, and what it answers is a constant the
// emitter writes: the size of a type is a fact about the target and the standard
// makes it an integer constant expression, so the operand is never evaluated.
// Measured against gcc 16.2.1 on this machine, `sizeof(char)`, `sizeof(int)`,
// `sizeof(double)` and `sizeof(char *) * 4` are 1, 4, 8 and 32, and `sizeof "vcc"`
// is 4: the literal is an array of four chars and `sizeof` does not decay it.
fn test_sizeof_answers_the_size_of_a_type() {
	result := parsed('int main(void) { return sizeof(char) * 4; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '*'
	assert binary.typ.describe() == 'int'
	left := binary.left as ast.IntLit
	right := binary.right as ast.IntLit
	assert left.value == 1
	assert right.value == 4
}

// An operand that is an expression is sized from the type it has, and a string
// literal keeps its array type: what was written is four bytes, not the address
// an array's name is worth in every other expression.
fn test_sizeof_of_an_expression_is_the_size_of_its_type() {
	result := parsed('int main(void) { double d = 0; return sizeof d + sizeof "vcc"; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	binary := expr as ast.Binary
	assert (binary.left as ast.IntLit).value == 8
	assert (binary.right as ast.IntLit).value == 4
}

// A size this compiler cannot answer is refused where the operator is written,
// and the refusal names what it was looking at.
fn test_sizeof_of_a_type_with_no_size_is_refused() {
	result := parsed('int main(void) { return sizeof(void); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('sizeof asks how many bytes void takes')
	assert result.diagnostics[0].line == 1
}

// The operand of `sizeof` is a type name or an expression, and `x` is a name
// here rather than a type: `sizeof (x)` sizes the variable.
fn test_sizeof_of_a_parenthesised_name_is_the_size_of_the_variable() {
	result := parsed('int main(void) { char x = 0; return sizeof(x); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 1
}

// typeof is a specifier whose operand is a type name or an expression, and what
// it names is the type of that operand: a declaration written through it is a
// declaration of the type behind the name, which is why the reading is checked
// by the type the declaration carries and not by the spelling it wrote. Measured
// on gcc 16.2.1, `typeof(x) y = 4;` for `int x` is an int object and
// `sizeof(typeof(x))` is 4.
fn test_typeof_names_the_type_of_a_value_and_of_a_type() {
	result := parsed('int main(void) { int x = 3; typeof(x) y = 4; __typeof__(int) z = 5; return x + y + z; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].decl_type == 'int'
	assert body[1].resolved.same(types.int_type())
	assert body[2].decl_type == 'int'
	assert body[2].resolved.same(types.int_type())
}

// typeof of an expression is the type of the value the expression has, and the
// value itself is not read: `typeof(-x)` is an int, and `typeof(*p)` is the type
// p points at, which is the difference between asking for the type of a name and
// asking for the type of what it points at.
fn test_typeof_of_a_derived_expression_is_the_type_of_that_expression() {
	result := parsed('struct S { int a; char b; }; int main(void) { struct S s; int *p = &s.a; typeof(*p) v = 1; typeof(s.b) c = 2; return v + c; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[2].decl_type == 'int'
	assert body[3].decl_type == 'char'
}

// A pointer written through typeof carries its stars in the type and not in the
// declarator, and the type the declaration has is a pointer either way.
fn test_typeof_carries_the_pointer_the_operand_had() {
	result := parsed('int main(void) { int x = 3; typeof(&x) p = &x; return *p; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].decl_type == 'int *'
	assert body[1].resolved.kind == .pointer
}

// The operand is a type name when a type name is written there, and a typedef is
// a type name: `typeof(m)` written where `Money` is one is the type behind it.
fn test_typeof_over_a_type_name_resolves_through_a_typedef() {
	result := parsed('typedef int Money; int main(void) { __typeof__(Money) w = 2; return w; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].decl_type == 'int'
	assert body[0].resolved.same(types.int_type())
}

// typeof_unqual is the same specifier with the qualifiers taken off the type it
// names, which is what C23 added it for. Measured on gcc 16.2.1: `typeof(x)`
// written where x is a `const int` is a const int and `typeof_unqual(x)` is an
// int, so an assignment to the second is an assignment to an object that is not
// const.
fn test_typeof_unqual_drops_the_qualifiers_the_operand_had() {
	result := parsed('int main(void) { const int x = 3; typeof_unqual(x) y = x; y = 4; return y; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].decl_type == 'int'
	assert !body[1].resolved.is_const()
}

// An operand whose type this compiler never resolved has no type to give a
// declaration, and the refusal names the operand and where typeof was written.
fn test_typeof_of_an_unresolved_operand_is_refused() {
	result := parsed('int main(void) { typeof(nothing) y = 1; return y; }')
	assert result.diagnostics.len >= 1
	first := result.diagnostics[0]
	assert first.msg.contains('typeof asks for the type of nothing')
	assert first.line == 1
}

// An array type written through typeof would make the declaration an array the
// declarator never wrote, and the reader refuses that rather than reading it as
// one element of the array.
fn test_typeof_of_an_array_type_is_refused() {
	result := parsed('int main(void) { int a[4]; typeof(a) b; return 0; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('typeof of an array type is not implemented')
}

// A word the language reserves for itself cannot name a declaration, and typeof
// is one: measured on gcc 16.2.1, `int typeof = 1;` is refused under -std=gnu99
// with "expected identifier or '(' before 'typeof'" and under -std=c23 with the
// same message, because typeof is a keyword in both.
fn test_an_object_may_not_be_named_typeof() {
	result := parsed('int main(void) { int typeof = 1; return typeof; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('typeof is a keyword')
}

// A definition of an object at the top level is storage the image holds: the
// type, how many elements and the constant it starts at are what the back end
// lays out from, and a body reads the name like any other.
fn test_a_definition_of_an_object_carries_its_type_and_constant() {
	result := parsed('int counter = -3; char buf[16]; int total;')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 3
	assert result.unit.globals[0].name == 'counter'
	assert result.unit.globals[0].typ == 'int'
	assert result.unit.globals[0].init or { 0 } == -3
	assert result.unit.globals[1].name == 'buf'
	assert result.unit.globals[1].count == 16
	assert result.unit.globals[1].init == ?i64(none)
	assert result.unit.globals[2].init == ?i64(none)
}

// The statement is skipped to its semicolon, so the return after it parses and
// the file produces exactly one diagnostic. A statement this compiler has no
// form for is what that path is for.
fn test_one_unsupported_statement_does_not_cascade() {
	result := parsed('int main() { do { return 1; } while (0); return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported statement')
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].body.len == 1
	assert result.unit.decls[0].body[0].kind == .return_stmt
}

// The statement is an expression evaluated for what it does, which is what a
// call written as a statement is. It parses now, and the return after it is the
// second statement rather than the first.
fn test_an_expression_statement_parses() {
	result := parsed('int printf(char *s);\nint main() { printf("hi"); return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[1].body
	assert body.len == 2
	assert body[0].kind == .expr_stmt
	expr := body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Call
	assert (expr as ast.Call).name == 'printf'
	assert body[1].kind == .return_stmt
}

fn test_a_string_literal_keeps_its_bytes_and_its_spelling() {
	result := parsed('int main() { return "x\\ty"; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.StrLit
	literal := expr as ast.StrLit
	assert literal.value == 'x	y'
	assert literal.text == '"x\\ty"'
}

fn test_a_string_literal_carries_every_escape_a_character_constant_takes() {
	result := parsed('int puts(char *s);\nint main() { puts("a\\x41\\102\\n\\\\"); return 0; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[1].body[0].expr or {
		assert false
		return
	}
	args := (expr as ast.Call).args
	assert (args[0] as ast.StrLit).value == 'aAB\n\\'
}

fn test_an_escape_that_names_more_than_a_byte_is_reported() {
	result := parsed('int puts(char *s);\nint main() { puts("\\x1ff"); return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('not a byte')
}

fn test_a_bad_integer_literal_is_reported() {
	result := parsed('int main() { return 0x; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('not an integer constant')
}

fn test_an_integer_that_does_not_fit_is_reported() {
	result := parsed('int main() { return 99999999999999999999999; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('does not fit')
}

fn test_character_constants_are_values() {
	result := parsed("int main() { return 'A'; }")
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 65
}

fn test_a_declaration_inside_a_body_is_storage_in_the_frame() {
	result := parsed('int main() { int x; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 2
	assert body[0].kind == .var_decl
	assert body[0].decl_name == 'x'
	assert body[0].decl_type == 'int'
	mut initialized := false
	if _ := body[0].init {
		initialized = true
	}
	assert !initialized
	assert body[1].kind == .return_stmt
}

fn test_a_declaration_keeps_its_initializer() {
	result := parsed('int main() { int x = 5; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	init := body[0].init or {
		assert false
		return
	}
	assert init is ast.IntLit
	assert (init as ast.IntLit).value == 5
	returned := body[1].expr or {
		assert false
		return
	}
	assert returned is ast.Ident
	assert (returned as ast.Ident).name == 'x'
}

fn test_a_pointer_declaration_keeps_the_stars_and_the_literal() {
	result := parsed('int main() { char *s = "text"; return 0; }')
	assert result.diagnostics.len == 0
	decl := result.unit.decls[0].body[0]
	assert decl.kind == .var_decl
	assert decl.decl_name == 's'
	assert decl.decl_type == 'char *'
	init := decl.init or {
		assert false
		return
	}
	assert init is ast.StrLit
	assert (init as ast.StrLit).value == 'text'
}

// A statement names one object, so a declaration of two is two statements in
// the tree and still one line of source.
fn test_a_declaration_may_name_several_objects() {
	result := parsed('int main() { int a = 1, b = 2; return a + b; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 3
	assert body[0].kind == .var_decl
	assert body[0].decl_name == 'a'
	assert body[1].kind == .var_decl
	assert body[1].decl_name == 'b'
	assert body[2].kind == .return_stmt
}

// The type is the one a definition's return type may be, so a word the emitter
// has no form for is reported where the declaration is written, and what comes
// after the declaration still parses.
fn test_a_local_declaration_with_an_unsupported_type_is_reported() {
	result := parsed('int main() { unsigned int n = 0; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type unsigned')
	assert result.unit.decls[0].body.len == 1
	assert result.unit.decls[0].body[0].kind == .return_stmt
}

// A body's array declaration keeps the size it was given, so what is left to
// report is a size this reader cannot read as one: a name, a computation, or an
// empty pair of brackets. The declaration is dropped rather than half-kept.
fn test_a_local_array_whose_size_is_not_a_number_is_reported() {
	result := parsed('int main() { int a[n]; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('needs a size')
	assert result.unit.decls[0].body.len == 1
}

fn test_an_assignment_writes_to_a_name() {
	result := parsed('int main() { int x; x = 5; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .assign
	assert body[1].target == 'x'
	value := body[1].expr or {
		assert false
		return
	}
	assert value is ast.IntLit
	assert (value as ast.IntLit).value == 5
}

fn test_an_assignment_takes_a_variable_on_each_side() {
	result := parsed('int main() { int x = 1; int y = 2; x = y + 1; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	value := body[2].expr or {
		assert false
		return
	}
	assert value is ast.Binary
	binary := value as ast.Binary
	assert binary.op == '+'
	assert binary.left is ast.Ident
	assert (binary.left as ast.Ident).name == 'y'
}

// `x += 1` reads and writes the same name, so it is the assignment it means,
// written the way the tree writes an assignment of a sum.
fn test_a_compound_assignment_is_the_assignment_it_means() {
	result := parsed('int main() { int x = 1; x += 2; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .assign
	assert body[1].target == 'x'
	value := body[1].expr or {
		assert false
		return
	}
	assert value is ast.Binary
	binary := value as ast.Binary
	assert binary.op == '+'
	assert binary.left is ast.Ident
	assert (binary.left as ast.Ident).name == 'x'
	assert binary.right is ast.IntLit
}

// A compound spelling this reader does not expand, here `*=`, is reported
// rather than turned into `x = x * 2`: only `+=` and `-=` are expanded, and the
// rest are the emitter's decision.
fn test_a_compound_assignment_with_no_form_is_reported() {
	result := parsed('int main() { int x = 1; x *= 2; return x; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('compound assignment')
	assert result.unit.decls[0].body.len == 2
	assert result.unit.decls[0].body[1].kind == .return_stmt
}

// A condition is written with the operators C compares with, and they bind the
// way C binds them: the arithmetic first, then the comparisons, then the two
// that join conditions.
fn test_a_comparison_binds_looser_than_arithmetic() {
	result := parsed('int main() { return 1 + 2 < 3 * 4; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '<'
	assert binary.left is ast.Binary
	assert (binary.left as ast.Binary).op == '+'
	assert binary.right is ast.Binary
	assert (binary.right as ast.Binary).op == '*'
}

fn test_an_equality_binds_looser_than_a_comparison() {
	result := parsed('int main() { return a == b < c; }')
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '=='
	assert binary.right is ast.Binary
	assert (binary.right as ast.Binary).op == '<'
}

fn test_the_operators_that_join_conditions_bind_loosest() {
	result := parsed('int main() { return a && b || c != d; }')
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '||'
	assert binary.left is ast.Binary
	assert (binary.left as ast.Binary).op == '&&'
	assert binary.right is ast.Binary
	assert (binary.right as ast.Binary).op == '!='
}

// A shift is an operator between two values, and the tree holds it as one with
// the spelling it was written with. C's 6.5.7 gives it the promoted type of its
// left operand, which for two ints is an int.
fn test_a_shift_is_a_binary_operator() {
	left := parsed('int main(void) { return 1 << 2; }')
	assert left.diagnostics.len == 0
	expr := left.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	shift := expr as ast.Binary
	assert shift.op == '<<'
	assert (shift.left as ast.IntLit).value == 1
	assert (shift.right as ast.IntLit).value == 2
	assert shift.typ.describe() == 'int'
	right := parsed('int main(void) { return 4 >> 1; }')
	assert right.diagnostics.len == 0
	other := right.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert other is ast.Binary
	shifted := other as ast.Binary
	assert shifted.op == '>>'
	assert (shifted.left as ast.IntLit).value == 4
	assert (shifted.right as ast.IntLit).value == 1
}

// The three bitwise operators are binary operators with the same shape, and each
// one keeps its own spelling: the emitter matches on that string, so `|`, `^`
// and `&` have to come back as themselves rather than as one another.
fn test_the_bitwise_operators_keep_their_own_spellings() {
	for pair in [['|', '1 | 2'], ['^', '1 ^ 2'], ['&', '1 & 2']] {
		result := parsed('int main(void) { return ${pair[1]}; }')
		assert result.diagnostics.len == 0
		expr := result.unit.decls[0].body[0].expr or {
			assert false
			return
		}
		assert expr is ast.Binary
		binary := expr as ast.Binary
		assert binary.op == pair[0]
		assert (binary.left as ast.IntLit).value == 1
		assert (binary.right as ast.IntLit).value == 2
	}
}

// A shift binds tighter than a comparison and looser than `+`, which is where C
// puts it: `1 + 2 << 3` is `(1 + 2) << 3` and `1 << 2 < 3` is `(1 << 2) < 3`.
fn test_a_shift_binds_between_addition_and_a_comparison() {
	added := parsed('int main(void) { return 1 + 2 << 3; }')
	assert added.diagnostics.len == 0
	expr := added.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	shift := expr as ast.Binary
	assert shift.op == '<<'
	assert shift.left is ast.Binary
	assert (shift.left as ast.Binary).op == '+'
	assert (shift.right as ast.IntLit).value == 3
	compared := parsed('int main(void) { return 1 << 2 < 3; }')
	assert compared.diagnostics.len == 0
	other := compared.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert other is ast.Binary
	less := other as ast.Binary
	assert less.op == '<'
	assert less.left is ast.Binary
	assert (less.left as ast.Binary).op == '<<'
}

// `&` binds looser than `==`, so `1 & 2 == 3` is `1 & (2 == 3)`: the and is the
// node at the top and the comparison is its right operand.
fn test_a_bitwise_and_binds_looser_than_equality() {
	result := parsed('int main(void) { return 1 & 2 == 3; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	binary := expr as ast.Binary
	assert binary.op == '&'
	assert (binary.left as ast.IntLit).value == 1
	assert binary.right is ast.Binary
	assert (binary.right as ast.Binary).op == '=='
}

// The three bitwise operators bind in C's order, `&` tightest of them and `|`
// loosest: `1 | 2 ^ 3 & 4` is `1 | (2 ^ (3 & 4))`.
fn test_the_bitwise_operators_bind_in_c_order() {
	result := parsed('int main(void) { return 1 | 2 ^ 3 & 4; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	pipe := expr as ast.Binary
	assert pipe.op == '|'
	assert (pipe.left as ast.IntLit).value == 1
	assert pipe.right is ast.Binary
	xor := pipe.right as ast.Binary
	assert xor.op == '^'
	assert (xor.left as ast.IntLit).value == 2
	assert xor.right is ast.Binary
	amp := xor.right as ast.Binary
	assert amp.op == '&'
	assert (amp.left as ast.IntLit).value == 3
	assert (amp.right as ast.IntLit).value == 4
}

// `~` is a prefix operator and not a binary one, and the reader already has the
// prefix mechanism for it: the operand is promoted and the node keeps the
// spelling, which is what the emitter matches on.
fn test_a_complement_is_a_unary_operator() {
	result := parsed('int main(void) { return ~1; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Unary
	complement := expr as ast.Unary
	assert complement.op == '~'
	assert complement.typ.describe() == 'int'
	// Where `~` is a prefix operator, `&` is both: the position decides. The
	// initializer of a declarator goes through the same expression reader, so
	// `int *p = &x;` still reads as the address of x with the type of a
	// pointer, and `x & 1` reads as the bitwise and.
	address := parsed('int main(void) { int x = 1; int *p = &x; return p != 0; }')
	assert address.diagnostics.len == 0
	init := address.unit.decls[0].body[1].init or {
		assert false
		return
	}
	assert init is ast.Unary
	unary := init as ast.Unary
	assert unary.op == '&'
	assert unary.expr is ast.Ident
	assert (unary.expr as ast.Ident).name == 'x'
	assert unary.typ.describe() == 'int *'
	bitwise := parsed('int main(void) { int x = 1; x = x & 1; return x; }')
	assert bitwise.diagnostics.len == 0
	assignment := bitwise.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	assert assignment is ast.Binary
	assert (assignment as ast.Binary).op == '&'
}

fn test_a_negation_is_a_unary_node() {
	result := parsed('int main() { return !x; }')
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert expr is ast.Unary
	assert (expr as ast.Unary).op == '!'
}

// The second token is what tells an assignment from a comparison, so `==` is
// read as the operator it is and the statement stays an expression.
fn test_an_expression_that_compares_is_not_an_assignment() {
	result := parsed('int main() { int x = 1; x == 1; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .expr_stmt
	expr := body[1].expr or {
		assert false
		return
	}
	assert expr is ast.Binary
	assert (expr as ast.Binary).op == '=='
}

fn test_an_if_keeps_its_condition_and_both_branches() {
	result := parsed('int main() { int x = 0; if (x < 1) return 1; else return 2; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .if_stmt
	cond := body[1].cond or {
		assert false
		return
	}
	assert cond is ast.Binary
	assert (cond as ast.Binary).op == '<'
	assert body[1].then_body.len == 1
	assert body[1].then_body[0].kind == .return_stmt
	assert body[1].else_body.len == 1
	assert body[1].else_body[0].kind == .return_stmt
}

fn test_an_if_without_an_else_leaves_the_else_empty() {
	result := parsed('int x;\nint main() { if (x) return 1; return 2; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .if_stmt
	assert body[0].then_body.len == 1
	assert body[0].else_body.len == 0
	assert body[1].kind == .return_stmt
}

fn test_an_else_if_is_an_if_in_the_else() {
	result := parsed('int a;\nint b;\nint main() { if (a) return 1; else if (b) return 2; else return 3; }')
	assert result.diagnostics.len == 0
	first := result.unit.decls[0].body[0]
	assert first.kind == .if_stmt
	assert first.else_body.len == 1
	assert first.else_body[0].kind == .if_stmt
	assert first.else_body[0].else_body.len == 1
	assert first.else_body[0].else_body[0].kind == .return_stmt
}

// A branch written as a block is a block statement, which is the shape a block
// already had inside a body.
fn test_a_branch_that_is_a_block_is_a_block_statement() {
	result := parsed('int x;\nint main() { if (x) { return 1; } return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].then_body.len == 1
	assert body[0].then_body[0].kind == .block
	assert body[0].then_body[0].body.len == 1
	assert body[0].then_body[0].body[0].kind == .return_stmt
}

fn test_a_condition_may_be_a_call() {
	result := parsed('int x;\nint is_even(int n);\nint main() { if (is_even(x)) return 1; return 0; }')
	assert result.diagnostics.len == 0
	cond := result.unit.decls[1].body[0].cond or {
		assert false
		return
	}
	assert cond is ast.Call
	assert (cond as ast.Call).name == 'is_even'
}

fn test_a_while_keeps_its_condition_and_its_body() {
	result := parsed('int main() { int x = 0; while (x < 3) x = x + 1; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .while_stmt
	cond := body[1].cond or {
		assert false
		return
	}
	assert cond is ast.Binary
	assert (cond as ast.Binary).op == '<'
	assert body[1].body.len == 1
	assert body[1].body[0].kind == .assign
	assert body[1].body[0].target == 'x'
}

fn test_a_while_body_may_be_empty() {
	result := parsed('int main() { while (1) ; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .while_stmt
	assert body[0].body.len == 0
	assert body[1].kind == .return_stmt
}

fn test_break_and_continue_are_statements() {
	result := parsed('int x;\nint main() { while (1) { if (x) break; continue; } return 0; }')
	assert result.diagnostics.len == 0
	loop := result.unit.decls[0].body[0]
	assert loop.kind == .while_stmt
	assert loop.body.len == 1
	inner := loop.body[0]
	assert inner.kind == .block
	assert inner.body[0].kind == .if_stmt
	assert inner.body[0].then_body[0].kind == .break_stmt
	assert inner.body[1].kind == .continue_stmt
}

// A condition that does not parse is reported by the expression reader, and the
// statement is skipped so the one after it still parses.
fn test_a_condition_that_does_not_parse_costs_one_diagnostic() {
	result := parsed('int main() { if (x > ) return 1; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('expected an expression')
	body := result.unit.decls[0].body
	assert body.len == 1
	assert body[0].kind == .return_stmt
}

fn test_an_else_with_no_if_is_reported() {
	result := parsed('int main() { else return 1; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('else with no if')
}

// A for is a block holding its initializer and a while, and the while's step is
// the third part of the for. The tree has no for node, so this is the shape a
// reader of the tree sees.
fn test_a_for_is_a_block_holding_a_while() {
	result := parsed('int x;\nint main() { int i = 0; for (i = 0; i < 3; i = i + 1) x = i; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	loop := body[1]
	assert loop.kind == .block
	assert loop.body.len == 2
	assert loop.body[0].kind == .assign
	assert loop.body[0].target == 'i'
	spelled := loop.body[1]
	assert spelled.kind == .while_stmt
	cond := spelled.cond or {
		assert false
		return
	}
	assert cond is ast.Binary
	assert (cond as ast.Binary).op == '<'
	assert spelled.body.len == 1
	assert spelled.body[0].kind == .assign
	assert spelled.body[0].target == 'x'
	step := spelled.step[0]
	assert step.kind == .assign
	assert step.target == 'i'
	value := step.expr or {
		assert false
		return
	}
	assert value is ast.Binary
	assert (value as ast.Binary).op == '+'
}

fn test_a_for_may_declare_its_counter() {
	result := parsed('int main() { for (int i = 0; i < 3; i = i + 1) ; return 0; }')
	assert result.diagnostics.len == 0
	loop := result.unit.decls[0].body[0]
	assert loop.kind == .block
	assert loop.body.len == 2
	assert loop.body[0].kind == .var_decl
	assert loop.body[0].decl_name == 'i'
	spelled := loop.body[1]
	assert spelled.kind == .while_stmt
	// The body was the empty statement, which is not kept, so all the loop runs
	// is the step.
	assert spelled.body.len == 0
	assert spelled.step.len == 1
	assert spelled.step[0].kind == .assign
	assert spelled.step[0].target == 'i'
}

// A loop with no condition runs until a break. The language says a missing
// condition is a nonzero constant, so the condition the tree spells is 1, which
// is the same loop in the shape this tree has.
fn test_a_for_with_no_condition_spells_the_constant() {
	result := parsed('int main() { for (;;) { break; } return 0; }')
	assert result.diagnostics.len == 0
	loop := result.unit.decls[0].body[0]
	assert loop.kind == .block
	assert loop.body.len == 1
	spelled := loop.body[0]
	assert spelled.kind == .while_stmt
	cond := spelled.cond or {
		assert false
		return
	}
	assert cond is ast.IntLit
	assert (cond as ast.IntLit).value == 1
	assert spelled.body.len == 1
	assert spelled.body[0].kind == .block
	assert spelled.body[0].body[0].kind == .break_stmt
}

fn test_a_for_may_be_the_body_of_another_for() {
	result := parsed('int i;\nint j;\nint x;\nint main() { for (i = 0; i < 2; i = i + 1) for (j = 0; j < 2; j = j + 1) x = i; return 0; }')
	assert result.diagnostics.len == 0
	outer := result.unit.decls[0].body[0]
	assert outer.kind == .block
	assert outer.body.len == 2
	assert outer.body[1].kind == .while_stmt
	spelled := outer.body[1]
	assert spelled.body.len == 1
	inner := spelled.body[0]
	assert inner.kind == .block
	assert inner.body.len == 2
	assert inner.body[0].kind == .assign
	assert inner.body[1].kind == .while_stmt
	// Each loop keeps its own step: the inner one advances j and the outer one
	// advances i.
	assert inner.body[1].step.len == 1
	assert inner.body[1].step[0].target == 'j'
	assert spelled.step.len == 1
	assert spelled.step[0].target == 'i'
}

fn test_an_unterminated_block_is_reported_once() {
	result := parsed('int main() { return 1;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unterminated block')
}

fn test_an_empty_file_parses_to_nothing() {
	result := parsed('')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 0
}

fn test_a_for_keeps_its_step_out_of_its_body() {
	// The third part of a for is a part of the loop, not a statement at the end
	// of the body: a continue has to reach it, and a continue above a statement
	// inside the body would jump over it.
	result := parsed('int main() { int j = 0; for (j = 0; j < 3; j = j + 1) { j = j; } }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	// The declaration, then the block the loop was written in with its
	// initializer and the loop itself.
	loop := body[1].body[1]
	assert loop.kind == .while_stmt
	// The braces are a block of their own, so the body is one block and the
	// step is the increment that used to sit inside it.
	assert loop.body.len == 1
	assert loop.body[0].kind == .block
	assert loop.body[0].body[0].kind == .assign
	assert loop.step.len == 1
	assert loop.step[0].kind == .assign
}

// An array in a body is storage with a size, and the size is a number by the
// time this reader sees it: the preprocessor has already replaced the names that
// stand for one.
fn test_an_array_declaration_keeps_its_size() {
	result := parsed('int main() { char buf[16]; int a[4]; return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 3
	assert body[0].kind == .var_decl
	assert body[0].decl_type == 'char'
	assert body[0].decl_name == 'buf'
	assert body[0].decl_count == 16
	assert body[1].decl_type == 'int'
	assert body[1].decl_count == 4
	assert body[2].decl_count == 0
}

fn test_an_element_of_an_array_is_read_and_written() {
	result := parsed('int main() { int a[4]; a[0] = 5; int x = a[2] + a[0]; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .assign
	assert body[1].target == 'a'
	index := body[1].index or {
		assert false
		return
	}
	assert index is ast.IntLit
	assert (index as ast.IntLit).value == 0
	init := body[2].init or {
		assert false
		return
	}
	assert init is ast.Binary
	binary := init as ast.Binary
	assert binary.left is ast.Index
	element := binary.left as ast.Index
	assert element.name == 'a'
	assert (element.index as ast.IntLit).value == 2
}

fn test_a_compound_assignment_to_an_element_reads_the_element() {
	result := parsed('int main() { int a[4]; a[2] += 3; return a[2]; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[1].kind == .assign
	assert body[1].index != none
	value := body[1].expr or {
		assert false
		return
	}
	assert value is ast.Binary
	assert (value as ast.Binary).left is ast.Index
}

fn test_an_array_declaration_without_a_size_is_reported() {
	result := parsed('int main() { char buf[]; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('needs a size')
}

fn test_two_sizes_of_an_array_are_reported() {
	result := parsed('int main() { int a[2][3]; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('only one size')
}

// A name the tree carries that nothing in the file declares is refused once the
// whole unit has been read. The emitter resolves a name at layout and writes a
// call to one as a symbol the image does not hold: measured, `int main(void) {
// return missing(1); }` compiled into an image that died at load with `undefined
// symbol: missing`, and `int main(void) { puts("hi"); return 0; }` compiled and
// ran. Both are refused now, naming the name and the line it is written on.
fn test_a_name_nothing_declares_is_refused_with_the_name_and_its_location() {
	for source in [
		'int main(void) { return missing(1); }',
		'int main(void) { puts("hi"); return 0; }',
		'int main(void) { return missing; }',
	] {
		result := parsed(source)
		assert result.diagnostics.len == 1
		assert result.diagnostics[0].msg.contains('is used here and nothing in this file declares it')
		assert result.diagnostics[0].line == 1
	}
	// The location is the use itself rather than the end of the file the check
	// runs at.
	spread := parsed('int main(void) {\n  return missing(1);\n}')
	assert spread.diagnostics.len == 1
	assert spread.diagnostics[0].line == 2
	assert spread.diagnostics[0].col == 10
}

// A name a refused declaration declares is still a name this file declares: the
// refusal is about the type, and reporting the name again as one nothing declares
// would say something untrue about the source. Measured, `int main(void) {
// unsigned int u = 0; u = 1; return 0; }` was `unsupported type unsigned` and then
// `u is used here and nothing in this file declares it`; it is one message now.
fn test_a_name_a_refused_declaration_declares_is_not_reported_again() {
	result := parsed('int main(void) { unsigned int u = 0; u = 1; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type unsigned')
	// The same at the top level, where the declarator was read before the type was
	// refused and the name was recorded as a matter of course.
	global := parsed('unsigned int g = 1;\nint main(void) { return g; }')
	assert global.diagnostics.len == 1
	assert global.diagnostics[0].msg.contains('unsupported type unsigned')
}

// One diagnostic per name, however many times it is read: three uses of a name
// nothing declares are one missing declaration.
fn test_an_undeclared_name_costs_one_diagnostic() {
	result := parsed('int main(void) { return missing(1) + missing(2); }')
	assert result.diagnostics.len == 1
}

// A name declared anywhere in the unit satisfies the check, which is why it is
// asked over the whole unit rather than where the name is read: a definition may
// follow the function that calls it, and the call the reader had not met a
// declaration for is typed as unresolved rather than refused.
fn test_a_name_declared_later_in_the_file_is_not_refused() {
	result := parsed('int main(void) { return f(); }\nint f(void) { return 0; }')
	assert result.diagnostics.len == 0
	call := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert call is ast.Call
	assert (call as ast.Call).typ.kind == .unknown
}
