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
	// names that. The type here is one the compiler still has no form for, so the
	// diagnostic is still a refusal and the subject is still the file it names.
	result := parsed_from('long double f() { return 1; }', '/usr/include/stdlib.h')
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
	// A type the emitter has no width for is named by the word the compiler has
	// always named it by: `_Imaginary` is still not one of them.
	result := parsed('_Imaginary f() { return 1; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('_Imaginary')
	assert result.diagnostics[0].line == 1
}

// The narrow integer types are types this reader knows and names. A declaration of
// one is read with the type its spelling names rather than refused by that
// spelling, because the back end moves a value of each width: `_Bool` and the
// three character types live in one byte, and a `short` in two. Measured on gcc
// 16.2.1 with `sizeof` and `_Alignof`: each of the first four is 1 with an
// alignment of 1, and `short` and `unsigned short` are 2 with an alignment of 2. A
// lone `signed` is an int and a lone `unsigned` an unsigned int, which is what
// 6.7.2 makes of a specifier list with no type word in it.
fn test_the_narrow_integer_spellings_are_read_as_the_types_they_name() {
	result := parsed('_Bool b;\nsigned char sc;\nunsigned char uc;\nshort s;\nunsigned short us;\nsigned si;\nunsigned ui;\n')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 7
	assert result.unit.globals[0].resolved.same(types.bool_type())
	assert result.unit.globals[1].resolved.same(types.signed_char_type())
	assert result.unit.globals[2].resolved.same(types.unsigned_char_type())
	assert result.unit.globals[3].resolved.same(types.short_type())
	assert result.unit.globals[4].resolved.same(types.unsigned_short_type())
	assert result.unit.globals[5].resolved.same(types.int_type())
	assert result.unit.globals[6].resolved.same(types.unsigned_int_type())
}

// `sizeof` is an operator and not a call, and what it answers is a constant the
// emitter writes: the size of a type is a fact about the target and the standard
// makes it an integer constant expression, so the operand is never evaluated.
// Measured against gcc 16.2.1 on this machine, `sizeof(char)`, `sizeof(int)`,
// `sizeof(double)` and `sizeof(char *) * 4` are 1, 4, 8 and 32, and `sizeof "vcc"`
// is 4: the literal is an array of four chars and `sizeof` does not decay it.
//
// The constant has the type the target gives size_t, which is unsigned long, so
// `sizeof(char) * 4` is an unsigned long and not an int. Measured, `sizeof(int)
// - 5 > 0` is 1 on gcc 16.2.1 and was 0 while this was an int.
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
	assert binary.typ.describe() == 'unsigned long'
	left := binary.left as ast.IntLit
	right := binary.right as ast.IntLit
	assert left.value == 1
	assert left.typ.describe() == 'unsigned long'
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

// A tag that was declared and never defined has no members, and no members is
// not a size of zero: there is nothing to lay out and nothing to answer. The
// refusal names the tag as it was written, and it is an incomplete type gcc
// refuses too: measured, gcc 16.2.1 rejects `struct S; sizeof(struct S);` with
// `invalid application of 'sizeof' to an incomplete type`.
fn test_sizeof_of_a_tag_that_is_never_completed_is_refused_by_name() {
	result := parsed('struct S;\nint main(void) { return sizeof(struct S); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported: sizeof asks how many bytes struct S takes, and this compiler has no size for it'
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
// form for is what that path is for, and `else` with nothing to attach to is
// one of them: this test used to write `goto end;`, which has a reader now and
// is a jump the emitter has to find a label for, so the construct that still
// takes this path is the one that is still refused.
fn test_one_unsupported_statement_does_not_cascade() {
	result := parsed('int main() { else; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('else with no if')
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

fn test_a_universal_character_name_in_a_string_literal_is_utf8() {
	// C99 6.4.3: a universal character name is one character, and a narrow
	// literal writes it in the execution character set, which is UTF-8.
	// Measured on gcc 16.2.1: "\u00E9" is c3 a9, "\U0001F600" is
	// f0 9f 98 80, and a literal can mix them with ordinary characters.
	result := parsed('int main() { return "\\u00E9\\U0001F600"; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	literal := expr as ast.StrLit
	assert literal.value == '\xc3\xa9\xf0\x9f\x98\x80'
	assert literal.value.len == 6
}

fn test_an_incomplete_universal_character_name_is_reported() {
	// Measured on gcc 16.2.1: a name with fewer than the four hex digits \u
	// takes, or eight that \U takes, is `incomplete universal character name
	// \u00E`. The refusal names it where it is written.
	result := parsed('int main() { return "\\u00E"; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('incomplete universal character name \\u00E')
}

fn test_a_universal_character_name_that_names_no_character_is_reported() {
	// The surrogate range and values past the largest character name no
	// character. Measured on gcc 16.2.1: `\uD800` and `\U80000000` are
	// reported as `<spelling> is not a valid universal character`.
	surrogate := parsed('int main() { return "\\uD800"; }')
	assert surrogate.diagnostics.len == 1
	assert surrogate.diagnostics[0].msg.contains('\\uD800 is not a valid universal character')
	big := parsed('int main() { return "\\U80000000"; }')
	assert big.diagnostics.len == 1
	assert big.diagnostics[0].msg.contains('\\U80000000 is not a valid universal character')
}

fn test_a_universal_character_name_in_a_wide_literal_is_its_code_point() {
	// A wide literal writes the character as the wchar_t this target gives,
	// four bytes little-endian, rather than as its UTF-8 bytes. Measured on
	// gcc 16.2.1: L"\u00E9\U0001F600" is two wchar_t, 0xE9 and 0x1F600.
	result := parsed('int take(int *p);\nint main() { take(L"\\u00E9\\U0001F600"); return 0; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[1].body[0].expr or {
		assert false
		return
	}
	literal := (expr as ast.Call).args[0] as ast.StrLit
	assert literal.unit == 4
	assert literal.value == '\xe9\x00\x00\x00\x00\xf6\x01\x00'
}

fn test_a_universal_character_name_in_a_character_constant_is_packed() {
	// Measured on gcc 16.2.1: a narrow character constant takes the bytes of
	// the character's UTF-8 packed into the int, so '\u00E9' is 0xC3A9 and
	// '\U0001F600' is 0xF09F9880 as a signed int; a wide one takes the code
	// point, so L'\u00E9' is 233.
	narrow := parsed("int main() { return '\\u00E9'; }")
	assert narrow.diagnostics.len == 0
	narrow_expr := narrow.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (narrow_expr as ast.IntLit).value == 50089
	emoji := parsed("int main() { return '\\U0001F600'; }")
	assert emoji.diagnostics.len == 0
	emoji_expr := emoji.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (emoji_expr as ast.IntLit).value == -257976192
	wide := parsed("int main() { return L'\\u00E9'; }")
	assert wide.diagnostics.len == 0
	wide_expr := wide.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (wide_expr as ast.IntLit).value == 233
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
	result := parsed('int main() { double _Complex n = 0; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type _Complex')
	assert result.unit.decls[0].body.len == 1
	assert result.unit.decls[0].body[0].kind == .return_stmt
}

// A pointer to a tag with no body is a complete object: it is one address wide
// whatever the tag turns out to be, which is what lets `FILE *f;` be declared
// where FILE is `typedef struct _IO_FILE FILE;` and the struct's body is written
// after the typedef. Measured, gcc 16.2.1 compiles such a program and it exits 0.
fn test_a_local_pointer_to_a_tag_with_no_body_is_accepted() {
	direct := parsed('struct S; int main() { struct S *p = 0; return p == 0; }')
	assert direct.diagnostics.len == 0
	decl := direct.unit.decls[0].body[0]
	assert decl.kind == .var_decl
	assert decl.decl_type == 'struct S *'

	// The typedef spelling resolves to the tag, and a pointer written through it
	// is accepted for the same reason. A union tag with no body is the same
	// shape.
	aliased := parsed('struct S; typedef struct S T; int main() { T *p = 0; return p == 0; }')
	assert aliased.diagnostics.len == 0
	assert aliased.unit.decls[0].body[0].decl_type == 'struct S *'
	tagged := parsed('union U; int main() { union U *p = 0; return p == 0; }')
	assert tagged.diagnostics.len == 0
	assert tagged.unit.decls[0].body[0].decl_type == 'union U *'
}

// The pointer is what makes the object complete, so an object of the tag is
// still refused with the tag named. gcc 16.2.1 refuses it too ("storage size of
// 'x' isn't known"), which is what keeps the acceptance above from being a
// weakening of the refusal.
fn test_an_object_of_a_tag_with_no_body_is_still_reported() {
	result := parsed('struct S; int main() { struct S x; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported type struct S'
	assert result.unit.decls[0].body.len == 1
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

// A parenthesised expression is a primary-expression, and 6.5.16 and 6.5.17 put
// the assignment and the comma at the top of the expression grammar, so
// `(a = 1)` is a well-formed expression worth 1. The reader for it reads an
// assignment expression, which is the shape this test reads back.
fn test_a_parenthesised_assignment_expression_is_read_as_an_assignment() {
	result := parsed('int main() { int a = 0; return (a = 1) == 1; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	cmp := expr as ast.Binary
	assert cmp.op == '=='
	assign := cmp.left as ast.Assign
	assert assign.op == '='
	assert (assign.target as ast.Ident).name == 'a'
	assert (assign.value as ast.IntLit).value == 1
}

// 6.5.17 makes the comma left associative and worth the value of its right
// operand, so `(a = 1, b = 2, a + b)` writes 1, writes 2, and is worth 3. The
// tree reads a chain of commas as a nest with the sum on the right.
fn test_a_comma_expression_is_left_associative_and_worth_its_right_operand() {
	result := parsed('int main() { int a = 0; int b = 0; return (a = 1, b = 2, a + b) == 3; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[2].expr or {
		assert false
		return
	}
	cmp := expr as ast.Binary
	assert cmp.op == '=='
	comma := cmp.left as ast.Comma
	assert comma.typ.kind == .int_
	sum := comma.right as ast.Binary
	assert sum.op == '+'
	outer := comma.left as ast.Comma
	assert (outer.left as ast.Assign).op == '='
	assert (outer.right as ast.Assign).op == '='
}

// A comma in a for's init or update is 6.5.17's comma operator written where
// the value is thrown away: the clauses run in the order they were written, so
// the desugared block holds each of them as its own statement. `for (i = 0, j =
// 10; i < j; i++, j--) ;` is the corpus's own line, and it was refused before
// this reader existed because the init and update were read by a reader that
// stops at the comma.
fn test_a_for_init_and_update_read_a_comma() {
	result := parsed('int main() { int i; int j; for (i = 0, j = 10; i < j; i++, j--) ; return 0; }')
	assert result.diagnostics.len == 0
	block := result.unit.decls[0].body[2]
	assert block.kind == .block
	head := block.body
	// The two init clauses, then the loop the desugaring writes.
	assert head.len == 3
	assert head[0].kind == .assign
	assert head[1].kind == .assign
	loop := head[2]
	assert loop.kind == .while_stmt
	assert loop.step.len == 2
	assert loop.step[0].kind == .expr_stmt
	assert loop.step[1].kind == .expr_stmt
}

// A for's condition is an expression, so a comma there is the comma operator:
// gcc 16.2.1 runs `for (i = 0; i < 5, i < 3; i++) ;` three times, because the
// condition is worth its right operand. The reader keeps the comma as one
// condition rather than stopping at it, which is what the corpus's line needs
// for the init and update and what a bare comma condition needs of its own.
fn test_a_for_condition_reads_a_comma_expression() {
	result := parsed('int main() { int i; for (i = 0; i < 5, i < 3; i++) ; return i; }')
	assert result.diagnostics.len == 0
	loop := result.unit.decls[0].body[1].body[1]
	assert loop.kind == .while_stmt
	cond := loop.cond or {
		assert false
		return
	}
	assert cond is ast.Comma
	assert (cond as ast.Comma).typ.kind == .int_
}

// A GNU statement expression is `({ ... })`: a brace-enclosed compound statement
// in parentheses, read as a primary expression. Its value is the value of its
// last statement when that statement is an expression, and the statements before
// it are the body. gcc refuses a construct whose last statement is not an
// expression wherever a value is required and accepts it where the value is
// thrown away, so the reader keeps the two apart rather than guessing at the
// point of use.
fn test_a_statement_expression_keeps_its_body_and_its_value_apart() {
	result := parsed('int main() { int x = ({ int a = 4; a * 2; }); return x; }')
	assert result.diagnostics.len == 0
	init := result.unit.decls[0].body[0].init or {
		assert false
		return
	}
	construct := init as ast.StmtExpr
	assert construct.body.len == 1
	assert construct.body[0].kind == .var_decl
	value := construct.value or {
		assert false
		return
	}
	assert (value as ast.Binary).op == '*'
	assert construct.typ.kind == .int_
}

// An assignment is an expression in C (6.5.16) even though this tree keeps a
// bare assignment as a statement of its own, so a body whose last statement is
// an assignment is worth the assignment's value: measured on gcc 16.2.1,
// `({ a = 5; })` is 5. The reader puts the assignment back together as the
// expression it is, and the statement stays out of the body so the store happens
// once.
fn test_a_statement_expression_ending_in_an_assignment_is_worth_its_value() {
	result := parsed('int main() { int a = 0; int x = ({ a = 5; }); return x; }')
	assert result.diagnostics.len == 0
	init := result.unit.decls[0].body[1].init or {
		assert false
		return
	}
	construct := init as ast.StmtExpr
	assert construct.body.len == 0
	value := construct.value or {
		assert false
		return
	}
	assign := value as ast.Assign
	assert assign.op == '='
	assert (assign.target as ast.Ident).name == 'a'
	assert (assign.value as ast.IntLit).value == 5
	assert construct.typ.kind == .int_
}

// A body whose last statement is not an expression - a declaration, a loop, an
// if, a block - leaves the construct with no value and the void type. The
// statements before the last one are still the body and still run.
fn test_a_statement_expression_whose_last_statement_is_not_an_expression_is_void() {
	result := parsed('int main() { int x = 0; ({ x = 3; if (x) { x = 4; } }); return x; }')
	assert result.diagnostics.len == 0
	raw := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	construct := raw as ast.StmtExpr
	assert construct.value == none
	assert construct.typ.kind == .void_
	assert construct.body.len == 2
	assert construct.body[0].kind == .assign
	assert construct.body[1].kind == .if_stmt
}

// 6.4.2.2 makes `__func__` a static array of char holding the name of the
// enclosing function, and gcc's `__FUNCTION__` and `__PRETTY_FUNCTION__` are the
// same name. glibc's assert hands `__PRETTY_FUNCTION__` to __assert_fail under a
// GNU dialect, so the reader reads the three spellings as the string literal
// they name.
fn test_the_function_name_spellings_read_the_enclosing_function_name() {
	for spelling in ['__func__', '__FUNCTION__', '__PRETTY_FUNCTION__'] {
		result := parsed('int main() { return ${spelling}[0]; }')
		assert result.diagnostics.len == 0
		expr := result.unit.decls[0].body[0].expr or {
			assert false
			return
		}
		index := expr as ast.Index
		name := index.base as ast.StrLit
		assert name.value == 'main'
		assert name.typ.kind == .array
	}
}

// 6.5.16 gives the assignment the value of its left operand after the store, and
// the operator is right associative, so `(a = b = 3)` writes 3 into b and then b
// into a and is worth 3. The tree nests the second assignment inside the first.
fn test_an_assignment_expression_is_right_associative() {
	result := parsed('int main() { int a = 0; int b = 0; return (a = b = 3) == 3; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[2].expr or {
		assert false
		return
	}
	assign := (expr as ast.Binary).left as ast.Assign
	assert (assign.target as ast.Ident).name == 'a'
	inner := assign.value as ast.Assign
	assert (inner.target as ast.Ident).name == 'b'
	assert (inner.value as ast.IntLit).value == 3
}

// A compound spelling is read as the assignment it means, the way the statement
// reader reads it: `(a <<= 1)` is `a = a << 1`, so the value the node carries is
// the sum and the spelling is kept beside it.
fn test_a_compound_assignment_expression_is_the_assignment_it_means() {
	result := parsed('int main() { int a = 1; return (a <<= 1) == 2; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	assign := (expr as ast.Binary).left as ast.Assign
	assert assign.op == '<<='
	assert (assign.target as ast.Ident).name == 'a'
	sum := assign.value as ast.Binary
	assert sum.op == '<<'
	assert (sum.left as ast.Ident).name == 'a'
	assert (sum.right as ast.IntLit).value == 1
}

// An assignment writes to a place, so a value that is not one is refused at the
// operator, the same way gcc refuses it with `lvalue required as left operand of
// assignment`.
fn test_an_assignment_expression_refuses_a_target_that_is_not_a_place() {
	result := parsed('int main() { return (1 = 2); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('left operand of =')
}

// `*p = 5` writes through the address p holds, so the tree keeps the
// dereference as the target and has no name for it: the address is what the
// store needs, and the expression the dereference reads through is where it
// comes from.
fn test_an_assignment_through_a_dereference_writes_what_the_pointer_points_at() {
	result := parsed('int main() { int x = 1; int *p = &x; *p = 5; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[2].kind == .assign
	assert body[2].target == ''
	target := body[2].deref or {
		assert false
		return
	}
	assert target is ast.Unary
	assert (target as ast.Unary).op == '*'
	operand := (target as ast.Unary).expr
	assert operand is ast.Ident
	assert (operand as ast.Ident).name == 'p'
}

// The operand of the outer dereference is another dereference: `**pp = 7` is a
// write through the address `*pp` reads.
fn test_an_assignment_through_a_pointer_to_a_pointer_keeps_both_dereferences() {
	result := parsed('int main() { int x = 1; int *p = &x; int **pp = &p; **pp = 7; return x; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	target := body[3].deref or {
		assert false
		return
	}
	assert target is ast.Unary
	inner := (target as ast.Unary).expr
	assert inner is ast.Unary
	assert (inner as ast.Unary).op == '*'
}

// The pointer an assignment writes through is a use of the name, so a name
// nothing declares is reported there the way it is anywhere else.
fn test_an_assignment_through_an_undeclared_pointer_is_reported() {
	result := parsed('int main() { *missing = 1; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('missing')
}

// A compound assignment through a dereference is refused by name: writing
// `*p += 1` as `*p = *p + 1` would read the pointer twice, where C reads the
// lvalue once, and this tree has no shape that reads it once.
fn test_a_compound_assignment_through_a_dereference_is_refused_by_name() {
	result := parsed('int main() { int x = 1; int *p = &x; *p += 1; return x; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('through a dereference')
	assert result.diagnostics[0].msg.contains('not implemented')
}

// An assignment after an expression that is not a place is refused by name
// rather than read as a store.
fn test_an_assignment_to_something_that_is_not_a_place_is_refused() {
	result := parsed('int main() { int x = 1; -x = 2; return x; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('writes to a name, an element, a member or a dereference')
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
// Every compound spelling is read as the assignment to the same name, whose value
// is the binary operator the spelling names: `x <<= 3` means `x = x << 3`, and the
// operator in the tree is the one the emitter has an arm for rather than the one
// the source wrote. The operator's own precedence never applies here: what the
// compound spelling governs is the whole expression on its right, so `x &= 1 | 2`
// groups the `|` under the `&`.
fn test_a_compound_assignment_is_the_binary_operator_it_names() {
	spellings := [
		'+',
		'-',
		'*',
		'/',
		'%',
		'<<',
		'>>',
		'&',
		'|',
		'^',
	]
	for spelling in spellings {
		source := 'int main(void) { int x = 6;\n\tx ${spelling}= 3;\n\treturn x;\n}\n'
		result := parsed(source)
		assert result.diagnostics.len == 0
		body := result.unit.decls[0].body
		assert body.len == 3
		statement := body[1]
		assert statement.kind == .assign
		assert statement.target == 'x'
		expr := statement.expr or {
			assert false
			return
		}
		assert expr is ast.Binary
		binary := expr as ast.Binary
		assert binary.op == spelling
		assert binary.left is ast.Ident
		assert (binary.left as ast.Ident).name == 'x'
		assert binary.right is ast.IntLit
		assert (binary.right as ast.IntLit).value == 3
		// The node carries the type of the operator, which is the type the rest of
		// the compiler reads rather than the spelling. A node of the zero type is
		// what made `v *= 7` on an object of 128 bits refuse a store the object was
		// wide enough for.
		assert binary.typ.describe() == 'int'
	}
	// The same spelling on a target of 128 bits answers with the pair.
	wide := parsed('int main(void) { __int128 v = 1;\n\tv *= 7;\n\treturn 0; }')
	assert wide.diagnostics.len == 0
	compound := wide.unit.decls[0].body[1]
	value := (compound.expr or {
		assert false
		return
	}) as ast.Binary
	assert value.op == '*'
	assert value.typ.kind == .int128
	// The compound spelling governs the whole expression on its right.
	grouped := parsed('int main(void) { int x = 6;\n\tx &= 1 | 2;\n\treturn x;\n}\n')
	assert grouped.diagnostics.len == 0
	statement := grouped.unit.decls[0].body[1]
	outer := (statement.expr or {
		assert false
		return
	}) as ast.Binary
	assert outer.op == '&'
	assert (outer.right as ast.Binary).op == '|'
}

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

fn test_do_while_is_a_statement_of_its_own() {
	result := parsed('int x;\nint main() { do { x = 1; } while (x < 3); return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .do_while_stmt
	assert body[0].body.len == 1
	assert body[0].body[0].kind == .block
	// The `while` belongs to the loop, so the statement after this one is the return
	// and not a second loop with no body.
	assert body[1].kind == .return_stmt
	assert body.len == 2
}

fn test_a_do_while_body_does_not_need_braces() {
	result := parsed('int x;\nint main() { do x = 1; while (x < 3); return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .do_while_stmt
	assert body[0].body.len == 1
	assert body[0].body[0].kind == .assign
	assert body[1].kind == .return_stmt
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
	base := element.base as ast.Ident
	assert base.name == 'a'
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

// Two sizes on one declarator are a two-dimensional object rather than a
// refusal: `int a[2][3]` is two rows of three ints, an array whose element is an
// array. Measured on gcc 16.2.1, gcc sizes it at 24 with `sizeof a[0]` at 12.
fn test_two_sizes_of_an_array_declare_a_two_dimensional_object() {
	result := parsed('int main() { int a[2][3]; return 0; }')
	assert result.diagnostics.len == 0
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
// unsigned short u = 0; u = 1; return 0; }` was `unsupported type unsigned` and
// then `u is used here and nothing in this file declares it`; it is one message
// now, and the type the case is measured with is one this compiler still has no
// form for.
fn test_a_name_a_refused_declaration_declares_is_not_reported_again() {
	result := parsed('int main(void) { double _Complex u = 0; u = 1; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported type _Complex')
	// The same at the top level, where the declarator was read before the type was
	// refused and the name was recorded as a matter of course.
	global := parsed('double _Complex g = 1;\nint main(void) { return g; }')
	assert global.diagnostics.len == 1
	assert global.diagnostics[0].msg.contains('unsupported type _Complex')
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

// `++` and `--` are operators and not statements, so each is read as an
// expression that is worth a value. The prefix form is worth the operand after
// the step and the postfix form what it held before, and the node says which by
// the `postfix` flag; a reader that swapped them would leave a program whose
// answer is wrong, which is why the flag is checked on its own here. Whether the
// value is the right one is the emitter's test.
fn test_the_increment_and_decrement_are_read_as_prefix_and_postfix_values() {
	result := parsed('int main(void) { int i = 0; i++; ++i; i--; --i; return i; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 6
	post_increment := body[1].expr or {
		assert false
		return
	}
	assert post_increment is ast.IncDec
	assert (post_increment as ast.IncDec).name == 'i'
	assert (post_increment as ast.IncDec).op == '++'
	assert (post_increment as ast.IncDec).postfix
	pre_increment := body[2].expr or {
		assert false
		return
	}
	assert (pre_increment as ast.IncDec).op == '++'
	assert !(pre_increment as ast.IncDec).postfix
	post_decrement := body[3].expr or {
		assert false
		return
	}
	assert (post_decrement as ast.IncDec).op == '--'
	assert (post_decrement as ast.IncDec).postfix
	pre_decrement := body[4].expr or {
		assert false
		return
	}
	assert (pre_decrement as ast.IncDec).op == '--'
	assert !(pre_decrement as ast.IncDec).postfix
	// The value the node is worth is the type of the name, which is what makes
	// `i++` an int the expression around it can use.
	assert (post_increment as ast.IncDec).typ.kind == .int_
}

// The step of a for is the third part of the header, and `i++` there is a
// statement use of the operator like `i++` anywhere else: the reader turns the
// for into a block holding the head and a while whose step is the operator.
fn test_an_increment_is_read_as_the_step_of_a_for() {
	result := parsed('int main(void) { int i; for (i = 0; i < 3; i++) { } return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 3
	for_block := body[1]
	assert for_block.kind == .block
	assert for_block.body.len == 2
	loop := for_block.body[1]
	assert loop.kind == .while_stmt
	assert loop.step.len == 1
	step := loop.step[0]
	assert step.kind == .expr_stmt
	expr := step.expr or {
		assert false
		return
	}
	assert expr is ast.IncDec
	assert (expr as ast.IncDec).postfix
}

// Every operand that is not a name is refused where the operator is written,
// and the message names the construct it refused: a silently wrong value from an
// element or a member read as the name beside it is the worst outcome here.
fn test_an_increment_refuses_every_operand_that_is_not_a_name() {
	element := parsed('int main(void) { int a[3]; a[0]++; return 0; }')
	assert element.diagnostics.len == 1
	assert element.diagnostics[0].msg.contains('on a[...]')
	assert element.diagnostics[0].msg.contains('implements ++ and -- on a plain name only')
	literal := parsed('int main(void) { ++5; return 0; }')
	assert literal.diagnostics.len == 1
	assert literal.diagnostics[0].msg.contains('on 5')
	member := parsed('struct S { int a; };\nint main(void) { struct S s; --s.a; return 0; }')
	assert member.diagnostics.len == 1
	assert member.diagnostics[0].msg.contains('on s.a')
}

// The step is one, which is the increment of an integer of any width the back
// end stores: a long, an unsigned long and a short are each stepped by one, and
// the value wraps at the object's own width the way the language says.
fn test_an_increment_steps_an_integer_of_any_width() {
	long := parsed('int main(void) { long i = 0; i++; ++i; i--; return 0; }')
	assert long.diagnostics.len == 0
	unsigned_long := parsed('int main(void) { unsigned long i = 0; i++; return 0; }')
	assert unsigned_long.diagnostics.len == 0
	unsigned_int := parsed('int main(void) { unsigned i = 0; ++i; return 0; }')
	assert unsigned_int.diagnostics.len == 0
	short := parsed('int main(void) { short s = 0; s++; return 0; }')
	assert short.diagnostics.len == 0
	// A char is an integer the back end steps at its own byte, so it is read
	// and not refused.
	character := parsed('int main(void) { char c = 0; c++; return c; }')
	assert character.diagnostics.len == 0
}

// A pointer name is a step of the size of what it points at, and the reader
// accepts one whatever it points at: the stride is the emitter's question,
// because the size is a fact about the target and not about the spelling. A
// pointer to a type with no size is refused there, by name.
fn test_an_increment_of_a_pointer_name_is_read_as_a_step() {
	int_pointer := parsed('int main(void) { int *p; p++; ++p; p--; return 0; }')
	assert int_pointer.diagnostics.len == 0
	char_pointer := parsed('int main(void) { const char *scan; scan++; return 0; }')
	assert char_pointer.diagnostics.len == 0
	array_pointer := parsed('int main(void) { int (*p)[3]; p++; return 0; }')
	assert array_pointer.diagnostics.len == 0
}

// A type this compiler does not step is refused by the type it is: a double is
// a floating value this back end does not step, and a 128-bit integer is an
// integer with no value to step.
fn test_an_increment_refuses_a_name_this_compiler_does_not_step() {
	floating := parsed('int main(void) { double d = 0.0; d--; return 0; }')
	assert floating.diagnostics.len == 1
	assert floating.diagnostics[0].msg.contains('which is double')
	assert floating.diagnostics[0].msg.contains('steps an integer or a pointer name only')
	wide := parsed('int main(void) { __int128 x = 5; x++; return 0; }')
	assert wide.diagnostics.len == 1
	assert wide.diagnostics[0].msg.contains('which is __int128')
	assert wide.diagnostics[0].msg.contains('has no __int128 value to step')
}

// A name nothing declares gets the message about a missing declaration and not
// one about the operator: the walk over the unit is what answers for names, and
// a second message about the operator would say something untrue about the
// source.
fn test_an_increment_of_an_undeclared_name_is_reported_as_a_missing_declaration() {
	result := parsed('int main(void) { ++missing; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('missing is used here and nothing in this file declares it')
}

// A conditional carries the type its two arms share and not either arm's own.
// Two int arms are an int, and an int arm beside a double one is a double,
// which is the answer `sizeof` reads and what makes `sizeof(1 ? 1 : 1.0)` eight.
fn test_a_conditional_carries_the_type_its_two_arms_share() {
	ints := parsed('int main(void) { int x = 1 ? 2 : 3; return 0; }')
	assert ints.diagnostics.len == 0
	init := ints.unit.decls[0].body[0].init or {
		assert false
		return
	}
	conditional := init as ast.Conditional
	assert conditional.typ.kind == types.Kind.int_
	mixed := parsed('int main(void) { return sizeof(1 ? 1 : 1.0); }')
	assert mixed.diagnostics.len == 0
	size := mixed.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (size as ast.IntLit).value == 8
}

// The middle operand is the whole expression before the `:` and the third is a
// conditional expression, which is what makes the operator right-associative:
// `a ? b : c ? d : e` is `a ? b : (c ? d : e)` and not `(a ? b : c) ? d : e`.
fn test_a_conditional_is_right_associative() {
	result := parsed('int f(int a, int b, int c, int d, int e) { return a ? b : c ? d : e; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	outer := expr as ast.Conditional
	assert outer.then_expr is ast.Ident
	assert outer.else_expr is ast.Conditional
	inner := outer.else_expr as ast.Conditional
	assert (inner.cond as ast.Ident).name == 'c'
}

// The conditional binds looser than every binary operator, so it is read after
// the precedence climbing has taken them: `a || b ? c : d` selects on `a || b`.
fn test_a_conditional_binds_looser_than_the_binary_operators() {
	result := parsed('int f(int a, int b, int c, int d) { return a || b ? c : d; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	conditional := expr as ast.Conditional
	assert conditional.cond is ast.Binary
	assert (conditional.cond as ast.Binary).op == '||'
	assert (conditional.then_expr as ast.Ident).name == 'c'
	assert (conditional.else_expr as ast.Ident).name == 'd'
}

// The GNU spelling with the middle operand left out is refused by name: the
// extension repeats the condition, and reading the tokens that way would be a
// value the standard does not give them.
fn test_the_omitted_middle_operand_is_refused_by_name() {
	result := parsed('int main(void) { int a = 1; return a ?: 2; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('GNU extension')
	assert result.diagnostics[0].msg.contains('not C99')
}

// Two pointers to compatibly qualified versions of one type give a pointer to
// the composite type: a `const char *` arm beside a `char *` one is a
// `const char *`, which is the shape `p != NULL ? p : "text"` has.
fn test_a_conditional_between_two_qualified_pointers_keeps_the_qualifier() {
	result := parsed('int main(void) { const char *c = "x"; const char *p = c ? c : "y"; return 0; }')
	assert result.diagnostics.len == 0
}

// A chain of conditionals nests through its operands, so a long one is counted
// against the same limit as parenthesised nesting and refused with a
// diagnostic. Before the count was added, a chain of ten thousand `?:` - each
// third operand another conditional - segfaulted the reader on a stack it had
// run out of, which is a crash and not a refusal.
fn test_a_long_chain_of_conditionals_is_refused_rather_than_run_out_of_stack() {
	mut source := 'int main(void) { return 1'
	for _ in 0 .. 10000 {
		source += ' ? 1 : 1'
	}
	source += '; }'
	result := parsed(source)
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('nested more than')
}

// The other three spellings the expression grammar recurses through. A call's
// argument list and a subscript's index are expressions written inside another,
// and a sizeof operand is a unary one, and none of the three raised the count
// that bounds parenthesised nesting. Each chain was followed until the stack ran
// out - measured on an 8 MB stack, a chain of twenty thousand of any of them
// took signal 11 - so each is read through a counted reader now and is refused
// with a diagnostic instead of a crash.
fn test_a_long_chain_of_calls_is_refused_rather_than_run_out_of_stack() {
	result := parsed('int main(void) { return ${'f('.repeat(10000)}1${')'.repeat(10000)}; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('nested more than')
}

fn test_a_long_chain_of_subscripts_is_refused_rather_than_run_out_of_stack() {
	result := parsed('int a[1]; int main(void) { return ${'a['.repeat(10000)}0${']'.repeat(10000)}; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('nested more than')
}

fn test_a_long_chain_of_sizeof_is_refused_rather_than_run_out_of_stack() {
	result := parsed('int x; int main(void) { return ${'sizeof '.repeat(10000)}x; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('nested more than')
}

// A switch is a statement whose controlling expression the case labels inside
// its body are matched against. The labels are statements of their own, so a run
// of them over one statement is a run of statements: `case 0: case 1: x = 1;`
// is two labels and an assignment, and the two labels are two places the switch
// can jump to.
fn test_a_switch_holds_its_case_labels_as_statements() {
	result := parsed('int main(void) { int i = 2; int n = 0; switch (i) { case 0: case 1: n = 1; break; case 2: n = 2; default: n = 3; } return n; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[2].kind == .switch_stmt
	inner := body[2].body
	assert inner.len == 1
	assert inner[0].kind == .block
	arms := inner[0].body
	assert arms[0].kind == .case_stmt
	assert arms[0].case_value == 0
	assert arms[1].kind == .case_stmt
	assert arms[1].case_value == 1
	assert arms[2].kind == .assign
	assert arms[3].kind == .break_stmt
	assert arms[4].kind == .case_stmt
	assert arms[4].case_value == 2
	assert arms[6].kind == .default_stmt
}

// A case value this reader cannot reduce to an integer is refused by name at the
// label, and the statement under it is still read: measured on gcc 16.2.1,
// `switch (v) { case n: }` for an object n is `case label does not reduce to an
// integer constant`, and the statements after it are read once.
fn test_a_case_value_that_is_not_a_constant_is_refused_by_name() {
	result := parsed('int main(void) { int n = 1; int v = 0; switch (v) { case n: v = 1; break; } return v; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('integer constant')
	assert result.diagnostics[0].line == 1
}

// Two case labels of one switch with the same value are refused where the second
// is written, which is the constraint 6.8.4.2 states: measured on gcc 16.2.1,
// `duplicate case value`.
fn test_a_duplicate_case_value_is_refused_by_name() {
	result := parsed('int main(void) { int n = 0; switch (n) { case 1: n = 1; break; case 1: n = 2; break; } return n; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('duplicate case value 1')
}

// The same value in two different switches is not a collision: each switch has
// its own set of labels, and the sets nest.
fn test_the_same_case_value_in_a_nested_switch_is_not_a_duplicate() {
	result := parsed('int main(void) { int n = 0; switch (n) { case 1: switch (n) { case 1: n = 1; break; default: n = 2; } break; default: n = 3; } return n; }')
	assert result.diagnostics.len == 0
}

// One switch has one default, and a second is refused by name: measured on gcc
// 16.2.1, `multiple default labels in one switch`.
fn test_a_second_default_in_one_switch_is_refused_by_name() {
	result := parsed('int main(void) { int n = 0; switch (n) { default: n = 1; break; default: n = 2; break; } return n; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('duplicate default label')
}

// A case or default label is a label of a switch and nothing else: measured on
// gcc 16.2.1, `case 1:` outside one is `case label not within a switch
// statement` and `default:` is the same for the other word.
fn test_a_label_of_a_switch_outside_one_is_refused_by_name() {
	offered := parsed('int main(void) { case 1: return 0; }')
	assert offered.diagnostics.len == 1
	assert offered.diagnostics[0].msg.contains('not in a switch statement')
	fallback := parsed('int main(void) { default: return 0; }')
	assert fallback.diagnostics.len == 1
	assert fallback.diagnostics[0].msg.contains('not in a switch statement')
}

// The controlling expression has to be an integer: measured on gcc 16.2.1,
// `switch (1.5)` is `switch quantity not an integer`, and a pointer is refused
// with the same words.
fn test_a_switch_operand_that_is_not_an_integer_is_refused_by_name() {
	floating := parsed('int main(void) { double d = 1.5; switch (d) { case 1: return 1; } return 0; }')
	assert floating.diagnostics.len == 1
	assert floating.diagnostics[0].msg.contains('switch quantity is not an integer')
	pointer := parsed('int main(void) { int x = 0; int *p = &x; switch (p) { case 1: return 1; } return 0; }')
	assert pointer.diagnostics.len == 1
	assert pointer.diagnostics[0].msg.contains('switch quantity is not an integer')
}

// A goto is a jump to a label of the same function and a label is a place in it,
// so the two are one jump each way: the label statement is in the body where it
// was written and the jump names it.
fn test_a_goto_and_a_label_are_a_jump_and_a_place() {
	result := parsed('int main(void) { goto done; done: return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body.len == 3
	assert body[0].kind == .goto_stmt
	assert body[0].label == 'done'
	assert body[1].kind == .label_stmt
	assert body[1].label == 'done'
	assert body[2].kind == .return_stmt
}

// A label lives in a namespace of its own, so a label and an object of the same
// name are two names and neither hides the other. Measured on gcc 16.2.1: this
// program compiles with no diagnostic and exits 7, and reading the object at the
// label is reading the object.
fn test_a_label_and_an_object_of_the_same_name_are_two_names() {
	result := parsed('int main(void) { int label = 5; goto past; past: label = label + 2; return label; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	returned := body[body.len - 1]
	operand := returned.expr or {
		assert false
		return
	}
	assert (operand as ast.Ident).name == 'label'
	assert (operand as ast.Ident).typ.kind == .int_
}

// A cast of an integer constant to an integer type is an integer constant
// expression (6.6), so the folder evaluates one and a pointer is initialized with
// the zero it names. Measured on gcc 16.2.1 under `-std=c99`, `f((int)0)` for a
// parameter of type `int (*)(void)` compiles and runs, and this compiler refused
// both spellings at the cast because the folder had no arm for the node. The
// header bound that needs the arm is glibc's `sys/select.h`, which asks for
// `1024 / (8 * (int) sizeof (__fd_mask))`.
fn test_a_cast_of_a_constant_is_an_integer_constant_expression() {
	zero := parsed('int f(int (*g)(void));\nint main(void) { return f((int)0); }')
	assert zero.diagnostics.len == 0
	// The cast is folded and not merely accepted: `(int)1` is the value one, and
	// one is not the integer that initializes a pointer.
	one := parsed('int f(int (*g)(void));\nint main(void) { return f((int)1); }')
	assert one.diagnostics.len == 1
	assert one.diagnostics[0].msg.contains('integer constant of value zero')
}
