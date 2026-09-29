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

fn test_a_variable_declaration_says_function_definitions_are_what_exists() {
	result := parsed('int x;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('only function definitions')
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
	result := parsed('int main() { printf("hi"); return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
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
	result := parsed('int main() { puts("a\\x41\\102\\n\\\\"); return 0; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	args := (expr as ast.Call).args
	assert (args[0] as ast.StrLit).value == 'aAB\n\\'
}

fn test_an_escape_that_names_more_than_a_byte_is_reported() {
	result := parsed('int main() { puts("\\x1ff"); return 0; }')
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

// An array is a shape the tree has no node for, and the bound is a constant
// expression this parser does not read. The declaration is reported and dropped
// rather than half-kept.
fn test_a_local_declaration_of_an_array_is_reported() {
	result := parsed('int main() { char buf[10]; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('array declarations')
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
	result := parsed('int main() { if (x) return 1; return 2; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].kind == .if_stmt
	assert body[0].then_body.len == 1
	assert body[0].else_body.len == 0
	assert body[1].kind == .return_stmt
}

fn test_an_else_if_is_an_if_in_the_else() {
	result := parsed('int main() { if (a) return 1; else if (b) return 2; else return 3; }')
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
	result := parsed('int main() { if (x) { return 1; } return 0; }')
	assert result.diagnostics.len == 0
	body := result.unit.decls[0].body
	assert body[0].then_body.len == 1
	assert body[0].then_body[0].kind == .block
	assert body[0].then_body[0].body.len == 1
	assert body[0].then_body[0].body[0].kind == .return_stmt
}

fn test_a_condition_may_be_a_call() {
	result := parsed('int main() { if (is_even(x)) return 1; return 0; }')
	assert result.diagnostics.len == 0
	cond := result.unit.decls[0].body[0].cond or {
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
	result := parsed('int main() { while (1) { if (x) break; continue; } return 0; }')
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

// A for is a block holding its initializer and a while, and the while's body is
// the loop body with the step after it. The tree has no for node, so this is
// the shape a reader of the tree sees.
fn test_a_for_is_a_block_holding_a_while() {
	result := parsed('int main() { int i = 0; for (i = 0; i < 3; i = i + 1) x = i; return 0; }')
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
	assert spelled.body.len == 2
	assert spelled.body[0].kind == .assign
	assert spelled.body[0].target == 'x'
	step := spelled.body[1]
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
	// The body was the empty statement, so all the loop runs is the step.
	assert spelled.body.len == 1
	assert spelled.body[0].kind == .assign
	assert spelled.body[0].target == 'i'
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
	result := parsed('int main() { for (i = 0; i < 2; i = i + 1) for (j = 0; j < 2; j = j + 1) x = i; return 0; }')
	assert result.diagnostics.len == 0
	outer := result.unit.decls[0].body[0]
	assert outer.kind == .block
	assert outer.body.len == 2
	assert outer.body[1].kind == .while_stmt
	spelled := outer.body[1]
	assert spelled.body.len == 2
	inner := spelled.body[0]
	assert inner.kind == .block
	assert inner.body.len == 2
	assert inner.body[0].kind == .assign
	assert inner.body[1].kind == .while_stmt
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
