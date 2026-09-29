module parser

import ast
import tokenize

fn parsed(source string) Result {
	return parse(tokenize.lex(source).tokens)
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

// A compound operator the expression grammar has no binary spelling for is
// reported rather than expanded into something the file did not say.
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
