module parser

import ast
import tokenize
import types

// The GCC builtins a C library's headers reach for, checked on the answers they
// give rather than on the diagnostics they raise. Every value here is the one
// gcc 16.2.1 gives the same program, because a wrong constant is a silently
// wrong program and the two directions of a comparison are not each other's
// evidence.

fn builtin_read(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// builtin_value is the value of the one expression in the body of `main`, which
// is what a test of a folded constant wants: the node the reader built.
fn builtin_value(source string) i64 {
	result := builtin_read(source)
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return 0
	}
	return (expr as ast.IntLit).value
}

// __builtin_types_compatible_p answers 1 for one type written twice and 0 for
// two different types, and both directions are checked: a reader that answered
// the same number to every question would pass a test that only asked one.
// Measured on gcc 16.2.1, `(double, float)` is 0 and `(double, double)` is 1.
fn test_types_compatible_p_answers_both_directions() {
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(double, float); }') == 0
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(double, double); }') == 1
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(char, signed char); }') == 0
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(int, long); }') == 0
}

// The answer has the type int, which is what gcc gives the builtin and what
// makes it an integer constant expression a case label or an array bound can use.
fn test_types_compatible_p_is_an_int_constant() {
	result := builtin_read('int main(void) { return __builtin_types_compatible_p(double, double); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	lit := expr as ast.IntLit
	assert lit.typ.same(types.int_type())
	assert lit.value == 1
}

// gcc ignores top-level qualifiers and nothing else. Measured on gcc 16.2.1:
// `(const int, int)` and `(int const, int volatile)` are 1, while `(const int *,
// int *)` is 0 because there the qualifier is on the pointee and not on the type
// itself, and `(int *, int * const)` is 1 because there it is on the type.
fn test_types_compatible_p_ignores_the_qualifiers_on_the_type_itself() {
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(const int, int); }') == 1
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(int const, int volatile); }') == 1
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(const int *, int *); }') == 0
	assert builtin_value('int main(void) { return __builtin_types_compatible_p(int *, int * const); }') == 1
}

// A typedef names the type behind it, and a tag-less struct written twice is two
// types: measured on gcc 16.2.1, `(pair, struct { int a; })` for a typedef of a
// three-member pair is 0.
fn test_types_compatible_p_asks_the_type_a_name_stands_for() {
	source := 'typedef int myint;\nint main(void) { return __builtin_types_compatible_p(myint, int); }'
	assert builtin_value(source) == 1
	tagged := 'struct S { int a; };\nint main(void) { return __builtin_types_compatible_p(struct S, struct S); }'
	assert builtin_value(tagged) == 1
}

// __builtin_types_compatible_p is half of how glibc makes isnan type-generic;
// the other half is __builtin_choose_expr, which picks the arm its constant
// names. The expression is worth the arm chosen, so its type is that arm's own:
// measured on gcc 16.2.1, `sizeof(__builtin_choose_expr(1, (char)0, (long)0))`
// is 1.
fn test_choose_expr_returns_the_arm_the_constant_names() {
	assert builtin_value('int main(void) { return __builtin_choose_expr(1, 7, 9); }') == 7
	assert builtin_value('int main(void) { return __builtin_choose_expr(0, 7, 9); }') == 9
	assert builtin_value('int main(void) { return __builtin_choose_expr(2 - 2, 7, 9); }') == 9
}

fn test_choose_expr_is_worth_the_type_of_the_chosen_arm() {
	result := builtin_read('int main(void) { return sizeof(__builtin_choose_expr(1, (char)0, (long)0)); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 1
	other := builtin_read('int main(void) { return sizeof(__builtin_choose_expr(0, (char)0, (long)0)); }')
	assert other.diagnostics.len == 0
	chosen := other.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (chosen as ast.IntLit).value == 8
}

// The chain glibc builds, written out: three queries and a choose_expr between
// each pair, which is what `isnan(double)` becomes once the macros are expanded.
fn test_the_type_generic_dispatch_reads_the_type_of_its_argument() {
	source := 'int f(double x) { return __builtin_choose_expr(__builtin_types_compatible_p(__typeof(x), float), 1, __builtin_choose_expr(__builtin_types_compatible_p(__typeof(x), double), 2, 3)); }'
	result := builtin_read(source)
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 2
	same := builtin_read('int f(float x) { return __builtin_choose_expr(__builtin_types_compatible_p(__typeof(x), float), 1, __builtin_choose_expr(__builtin_types_compatible_p(__typeof(x), double), 2, 3)); }')
	assert same.diagnostics.len == 0
	first := same.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (first as ast.IntLit).value == 1
}

// A condition this reader cannot evaluate is refused by name rather than guessed
// at: gcc requires an integer constant expression in that place.
fn test_choose_expr_refuses_a_condition_that_is_not_a_constant() {
	result := builtin_read('int main(void) { int x = 1; return __builtin_choose_expr(x, 7, 9); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported: __builtin_choose_expr selects on a constant, and the first argument is not one this compiler can read'
}

// A type this compiler did not resolve is not answered 0: the comparison would
// be a value nothing computed.
fn test_types_compatible_p_refuses_a_type_it_cannot_resolve() {
	result := builtin_read('int main(void) { return __builtin_types_compatible_p(int, _Float128); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == "unsupported: __builtin_types_compatible_p asks for a type name, and '_Float128' is not a type this compiler knows"
}

// A deep chain of one builtin inside another is a file attacking the reader, and
// the answer is a diagnostic rather than a stack overflow.
fn test_a_deep_chain_of_choose_expr_is_refused_rather_than_followed() {
	mut chain := '1'
	for _ in 0 .. 300 {
		chain = '__builtin_choose_expr(1, ${chain}, 0)'
	}
	result := builtin_read('int main(void) { return ' + chain + '; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('nested more than')
}
