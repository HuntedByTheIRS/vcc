module parser

import ast
import tokenize

// A function defined inside a body is GNU's nested function. The reader reads it
// where it is written, gives the name it was written with to the rest of the
// body, and emits it under a symbol built from the function it is written in, so
// a nested function and a top-level name cannot land on one symbol.

fn parse_nested(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// nested_decls is every function the body of the first declaration defines.
fn nested_decls(result Result) []ast.FnDecl {
	mut out := []ast.FnDecl{}
	for decl in result.unit.decls {
		for stmt in decl.body {
			if nested := stmt.nested_fn() {
				out << nested
			}
		}
	}
	return out
}

// call_named says whether an expression tree writes a call to a symbol, which is
// how a call to a nested function is recognised: the call carries the symbol and
// not the name that was written.
fn call_named(expr ast.Expr, name string) bool {
	if expr is ast.Call {
		if expr.name == name {
			return true
		}
		for arg in expr.args {
			if call_named(arg, name) {
				return true
			}
		}
	}
	return false
}

fn test_a_function_defined_in_a_body_is_a_nested_function_of_its_enclosing_one() {
	result := parse_nested('int main(void) { int n = 5; int add(int v) { return v + n; } return add(1); }')
	assert result.diagnostics.len == 0
	nested := nested_decls(result)
	assert nested.len == 1
	assert nested[0].nested
	assert nested[0].owner == 'main'
	// The symbol is the enclosing function's name and the written name joined by
	// a dot, which no C identifier can spell: a top-level function named `add`
	// and this one are two symbols.
	assert nested[0].name == 'main.add'
	// The name the file wrote is what the body calls, and the call is written
	// against the symbol.
	mut call_found := false
	for stmt in result.unit.decls[0].body {
		if expr := stmt.expr {
			if call_named(expr, 'main.add') {
				call_found = true
			}
		}
	}
	assert call_found
}

fn test_two_nested_functions_in_one_body_get_two_symbols() {
	result := parse_nested('int main(void) { int f(void) { return 1; } int g(void) { return 2; } return f() + g(); }')
	assert result.diagnostics.len == 0
	nested := nested_decls(result)
	assert nested.len == 2
	assert nested[0].name == 'main.f'
	assert nested[1].name == 'main.g'
}

fn test_a_nested_function_of_another_function_does_not_share_the_symbol() {
	result := parse_nested('int main(void) { int f(void) { return 1; } return f(); } int other(void) { int f(void) { return 2; } return f(); }')
	assert result.diagnostics.len == 0
	assert nested_decls(result).len == 2
	// Both are written `f`, and each is emitted under the symbol of the function
	// that writes it, so the two do not collide.
	first := result.unit.decls[0].body[0].nested_fn() or { ast.FnDecl{} }
	second := result.unit.decls[1].body[0].nested_fn() or { ast.FnDecl{} }
	assert first.name == 'main.f'
	assert second.name == 'other.f'
}

fn test_a_nested_function_carries_its_parameters_and_body() {
	result := parse_nested('int main(void) { int square(int z) { return z * z; } return square(4); }')
	assert result.diagnostics.len == 0
	nested := nested_decls(result)
	assert nested.len == 1
	assert nested[0].params.len == 1
	assert nested[0].params[0].name == 'z'
	assert nested[0].ret == 'int'
	assert nested[0].defined
	assert nested[0].body.len == 1
}

fn test_a_nested_function_declared_without_a_body_is_read() {
	// gcc reads a nested function declared inside a body and gives it no code:
	// the name is in scope for the rest of the block and nothing is emitted for
	// it. Measured on gcc 16.2.1: `int main(void) { int f(void); return 0; }`
	// compiles and exits 0.
	result := parse_nested('int main(void) { int f(void); return 0; }')
	assert result.diagnostics.len == 0
}

fn test_a_nested_function_declared_and_then_defined_is_reported() {
	// The definition of a nested function is static and a declaration of one that
	// says nothing about linkage is not, so gcc refuses the pair, and this reader
	// reports it where the definition is written.
	result := parse_nested('int main(void) { int f(void); int f(void) { return 1; } return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('is declared and then defined')
}

fn test_the_name_of_a_nested_function_written_as_a_value_is_read() {
	// A function designator written where a value is wanted is the address of
	// the function, and a nested function is emitted under the symbol its
	// enclosing function gives it, so the name is read as that symbol rather
	// than refused. The emitter writes the trampoline the value needs, which is
	// what is not the reader's business.
	result := parse_nested('int main(void) { int f(void) { return 1; } int (*p)(void) = f; return 0; }')
	assert result.diagnostics.len == 0
	assert nested_decls(result).len == 1
}

fn test_two_blocks_each_define_a_nested_function_of_one_name() {
	// A nested function's name is visible to the end of the block it is written
	// in, so two blocks are two scopes and the two functions are two functions:
	// the symbols they are emitted under are numbered apart, which is what the
	// written names being equal does not say.
	result := parse_nested('int main(void) { { int f(void) { return 1; } } { int f(void) { return 2; } } return 0; }')
	assert result.diagnostics.len == 0
}

fn test_two_definitions_of_one_nested_name_in_one_block_are_reported() {
	result := parse_nested('int main(void) { int f(void) { return 1; } int f(void) { return 2; } return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('already has a body')
}
