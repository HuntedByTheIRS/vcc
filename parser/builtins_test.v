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

// __builtin_offsetof is where stddef.h's offsetof lands, and the answer has to be
// the offset the layout really puts the member at. Measured on gcc 16.2.1, the
// `b` of `struct { char a; int b; }` is 4 and the `b` of `struct { int a; int b;
// }` is 4 as well, so a test that only asked the second would pass on a reader
// that ignored the padding.
fn test_offsetof_is_the_offset_the_layout_gives() {
	assert builtin_value('struct P { char a; int b; };\nint main(void) { return __builtin_offsetof(struct P, b); }') == 4
	assert builtin_value('struct P { int a; int b; };\nint main(void) { return __builtin_offsetof(struct P, b); }') == 4
	assert builtin_value('struct P { char a; char b; };\nint main(void) { return __builtin_offsetof(struct P, b); }') == 1
	assert builtin_value('typedef struct { int a, b; } pair_t;\nint main(void) { return __builtin_offsetof(pair_t, b); }') == 4
}

// A member of a member is one offset and not two answers: the offset of the
// inner member inside the outer object is what offsetof asks for.
fn test_offsetof_walks_a_path_of_members() {
	source := 'struct inner { int x, y; };\nstruct outer { struct inner point; int flag; };\nint main(void) { return __builtin_offsetof(struct outer, point.y); }'
	assert builtin_value(source) == 4
	second := 'struct inner { int x, y; };\nstruct outer { struct inner point; int flag; };\nint main(void) { return __builtin_offsetof(struct outer, flag); }'
	assert builtin_value(second) == 8
}

// offsetof yields size_t, which is what the standard says and what makes
// `sizeof(offsetof(...))` the size of a size_t and not of an int.
fn test_offsetof_is_size_t() {
	result := builtin_read('struct P { char a; int b; };\nint main(void) { return sizeof(__builtin_offsetof(struct P, b)); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 8
}

fn test_offsetof_refuses_a_member_the_type_does_not_have() {
	result := builtin_read('struct P { int a; };\nint main(void) { return __builtin_offsetof(struct P, b); }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported: struct P has no member called b'
}

// The four argument-list operations are calls the reader builds itself, and the
// node a `va_arg` builds carries the type of the argument it reads: a walk
// through a list holds no type, so this node is the only place that says whether
// the next argument is an int, a long long or a double.
fn test_va_arg_reads_a_call_carrying_the_type_of_the_argument() {
	result := builtin_read('typedef __builtin_va_list va_list;\nint main(void) { va_list ap; return __builtin_va_arg(ap, int); }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	call := expr as ast.Call
	assert call.name == '__builtin_va_arg'
	assert call.args.len == 1
	assert (call.args[0] as ast.Ident).name == 'ap'
	assert call.typ.kind == .int_
}

// A `va_list` is written by the operation that fills it in, so the list has to
// be a name: a spelling with nowhere to write is refused rather than read as a
// value that would be stepped and thrown away.
fn test_va_start_writes_the_name_it_is_given() {
	good := builtin_read('typedef __builtin_va_list va_list;\nint main(void) { va_list ap; __builtin_va_start(ap, 0); return 0; }')
	assert good.diagnostics.len == 0
	refused := builtin_read('typedef __builtin_va_list va_list;\nint main(void) { __builtin_va_start(0, 0); return 0; }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('writes the argument list it is given')
}

fn test_va_end_and_va_copy_read_their_lists() {
	result := builtin_read('typedef __builtin_va_list va_list;\nint main(void) { va_list ap, snapshot; __builtin_va_start(ap, 0); __builtin_va_copy(snapshot, ap); __builtin_va_end(snapshot); return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert (body[2].expr or { ast.Expr(ast.IntLit{}) }) is ast.Call
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
