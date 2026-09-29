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

fn test_one_unsupported_statement_does_not_cascade() {
	// The statement is skipped to its semicolon, so the return after it parses
	// and the file produces exactly one diagnostic.
	result := parsed('int main() { printf("hi"); return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unsupported statement')
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].body.len == 1
}

fn test_a_string_literal_is_reported_rather_than_parsed() {
	result := parsed('int main() { return "x"; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('string literals')
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
