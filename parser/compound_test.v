module parser

import ast
import tokenize
import types

// A compound literal, C99 6.5.2.5: a type name in parentheses followed by a
// brace list. The construct names an unnamed object with the lifetime of the
// enclosing block, so reading one declares an object in a body and the
// expression it is worth is a use of that name. These tests fix the shape the
// reader builds: the declaration, the type it resolved to, the value the
// expression carries, and the lvalue it is.

fn compound_parsed(source string) Result {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	return parse(lexed.tokens)
}

fn compound_first(source string) ast.FnDecl {
	result := compound_parsed(source)
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 1
	return result.unit.decls[0]
}

fn test_a_compound_literal_declares_an_unnamed_object() {
	decl := compound_first('int main(void) { int *arr = (int[]){10, 20, 30}; return arr[0]; }')
	body := decl.body
	// The declaration of the unnamed object and the six stores that zero it and
	// write its three values come before the statement the literal was in.
	assert body.len == 9
	object := body[0]
	assert object.kind == .var_decl
	assert object.decl_name.starts_with('__vcc_compound_')
	assert object.decl_count == 3
	assert object.decl_stride == 4
	assert object.resolved.same(types.array_of(types.int_type(), 3))
	for i in 1 .. 7 {
		assert body[i].kind == .assign
		assert body[i].target == object.decl_name
	}
	arr := body[7]
	assert arr.kind == .var_decl
	init := arr.init or {
		assert false
		return
	}
	assert init is ast.Ident
	assert (init as ast.Ident).name == object.decl_name
	assert (init as ast.Ident).typ.same(types.array_of(types.int_type(), 3))
}

fn test_a_compound_literal_is_an_lvalue() {
	decl := compound_first('int main(void) { (int[]){1, 2}[0] = 5; return 0; }')
	body := decl.body
	assert body.len == 7
	assert body[0].kind == .var_decl
	assert body[0].decl_name.starts_with('__vcc_compound_')
	assert body[5].kind == .assign
	assert body[5].subscript != none
}

fn test_sizeof_a_compound_literal_is_a_constant() {
	decl := compound_first('int main(void) { return sizeof (int[]){1, 2, 3}; }')
	body := decl.body
	assert body.len == 1
	value := body[0].expr or {
		assert false
		return
	}
	assert value is ast.IntLit
	assert (value as ast.IntLit).value == 12
}

fn test_a_file_scope_compound_literal_is_a_static_object() {
	result := compound_parsed('int *p = (int[]){1, 2, 3};')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 2
	object := result.unit.globals[0]
	assert object.name.starts_with('__vcc_compound_')
	assert object.count == 3
	assert object.inits == [i64(1), 2, 3]
	p := result.unit.globals[1]
	assert p.name == 'p'
	address := p.address or {
		assert false
		return
	}
	assert address.name == object.name
	assert !address.string
}
