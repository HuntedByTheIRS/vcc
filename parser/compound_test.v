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

// A nonconstant literal in a place the statement may evaluate more than once is
// initialized where the literal is evaluated, not in front of the statement. The
// object is still declared in front of the statement, so there is one object for
// the scope; the stores that initialize it are wrapped in a statement expression
// the comma puts at the literal's own position, and the comma is worth the
// object they wrote.
fn test_a_nonconstant_literal_in_a_reevaluated_place_is_initialized_at_the_literal() {
	decl := compound_first('int main(void) { int i = 0; while ((int[]){i}[0]) { i++; } return i; }')
	body := decl.body
	mut object := ''
	mut loop := ast.Stmt{}
	for stmt in body {
		if stmt.kind == .var_decl && stmt.decl_name.starts_with('__vcc_compound_') {
			object = stmt.decl_name
		}
		if stmt.kind == .while_stmt {
			loop = stmt
		}
	}
	assert object.len > 0
	cond := loop.cond or {
		assert false
		return
	}
	assert cond is ast.Index
	base := (cond as ast.Index).base
	assert base is ast.Comma
	comma := base as ast.Comma
	assert comma.right is ast.Ident
	assert (comma.right as ast.Ident).name == object
	assert comma.left is ast.StmtExpr
	stores := comma.left as ast.StmtExpr
	assert stores.typ.same(types.void_type())
	assert stores.body.len > 0
	// Every statement the wrapper runs is a store into the object, so the
	// declaration is not among them.
	for stmt in stores.body {
		assert stmt.kind == .assign
		assert stmt.target == object
	}
}

fn test_a_constant_literal_in_a_reevaluated_place_is_read() {
	result := compound_parsed('int main(void) { int i = 0; while ((int[]){1}[0]) { i++; } return i; }')
	assert result.diagnostics.len == 0
}

// A literal in a for header's condition is read by the same path. The header's
// clauses and the literal's brace list share the parentheses that hold them,
// which the reader used to misread as the header's end and report as
// `unsupported: expected ;, found ')'` at the closing parenthesis.
fn test_a_nonconstant_literal_in_a_for_header_is_read() {
	result := compound_parsed('int main(void) { int i = 0, n = 0; for (; (int[]){i}[0] < 3; i++) n += 1; return n; }')
	assert result.diagnostics.len == 0
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

// A designated member whose own type is an aggregate takes the element as a
// value of that member: the designator is resolved against the literal's own
// type and the member's own byte receives the value. The reader used to descend
// into the aggregate member and read the same element again one level down,
// which looked the designator up against the member's type and reported
// `struct T has no member named t`.
fn test_a_designated_aggregate_member_takes_the_element_as_its_value() {
	result := compound_parsed('struct T { int x; int y; };\nstruct S { struct T t; int n; };\nint main(void) { struct T v = {1, 2}; struct S s = (struct S){.n = 3, .t = v}; return 0; }')
	assert result.diagnostics.len == 0
	mut body := []ast.Stmt{}
	for decl in result.unit.decls {
		if decl.name == 'main' {
			body = decl.body
		}
	}
	assert body.len > 0
	mut object := ''
	for stmt in body {
		if stmt.kind == .var_decl && stmt.decl_name.starts_with('__vcc_compound_') {
			object = stmt.decl_name
		}
	}
	assert object.len > 0
	mut stores := 0
	for stmt in body {
		if stmt.kind != .assign || stmt.target != object {
			continue
		}
		field := stmt.field or { continue }
		if field.typ.kind != .struct_ {
			continue
		}
		stores++
		// The member sits at the start of the object, and the value is the name
		// the element wrote rather than a walk into T's own members (x and y),
		// which are the only stores of the scalar type beside it.
		assert field.offset == 0
		value := stmt.expr or {
			assert false
			return
		}
		assert value is ast.Ident
		assert (value as ast.Ident).name == 'v'
	}
	assert stores == 1
}

// The positional form is the one that still elides: `(struct S){v, 3}` walks
// into the aggregate member and writes v into T's first member, so no store
// names `t` as a subobject of the literal. Each of this pair fails if the reader
// treats its shape as the other.
fn test_a_positional_flat_list_still_elides_into_an_aggregate_member() {
	result := compound_parsed('struct T { int x; int y; };\nstruct S { struct T t; int n; };\nint main(void) { struct T v = {1, 2}; struct S s = (struct S){v, 3}; return 0; }')
	assert result.diagnostics.len == 0
	mut body := []ast.Stmt{}
	for decl in result.unit.decls {
		if decl.name == 'main' {
			body = decl.body
		}
	}
	assert body.len > 0
	mut object := ''
	for stmt in body {
		if stmt.kind == .var_decl && stmt.decl_name.starts_with('__vcc_compound_') {
			object = stmt.decl_name
		}
	}
	assert object.len > 0
	for stmt in body {
		if stmt.kind != .assign || stmt.target != object {
			continue
		}
		field := stmt.field or { continue }
		assert field.typ.kind != .struct_
	}
}

// A designator may name a member an anonymous struct contributes, because
// 6.7.2.1p13 makes that member a member of the aggregate the initializer is for.
// `err` and `value` are the members of the anonymous struct that sits after `ok`,
// so `.err = 7` is a designator the enclosing struct's member table has to answer
// and the write lands at the offset the promotion gives the member. Before the
// member was recorded the reader refused `.err` by name.
fn test_a_designator_names_a_member_an_anonymous_struct_contributes() {
	result := compound_parsed('struct Q { int ok; struct { int err; int value; }; };\nint main(void) { struct Q q = { .ok = 1, .err = 7, .value = 9 }; return q.err; }')
	assert result.diagnostics.len == 0
}

// The same designator read at file scope, where the initializer is not a
// statement and the member is named among the parts of the object the image
// holds. A promoted member is named the same way.
fn test_a_file_scope_designator_names_a_promoted_member() {
	result := compound_parsed('struct G { int x; union { int y; }; };\nstruct G g = { .x = 3, .y = 4 };\nint main(void) { return g.y; }')
	assert result.diagnostics.len == 0
}

// A compound literal is an element a brace list may hold, because 6.7.8p1 makes
// an element an assignment-expression and 6.5.2.5 makes a compound literal one.
// In a body the element is the subobject's own bytes rather than a second
// object: the walk against the element's type stores each scalar where it
// belongs, so `{(struct S){1, 2}, (struct S){3, 4}}` writes 1, 2, 3 and 4. This
// was refused as `__vcc_compound_0 is an object of an aggregate type, and using
// it as a value is not implemented`.
fn test_a_body_brace_element_may_be_a_compound_literal() {
	result := compound_parsed('struct S { int a; int b; };\nint main(void) { struct S arr[2] = {(struct S){1, 2}, (struct S){3, 4}}; return arr[0].a + arr[1].b; }')
	assert result.diagnostics.len == 0
	mut main := result.unit.decls[0]
	for decl in result.unit.decls {
		if decl.name == 'main' {
			main = decl
		}
	}
	mut values := []i64{}
	for stmt in main.body {
		if stmt.kind != .assign {
			continue
		}
		if value := stmt.expr {
			if value is ast.IntLit && (value as ast.IntLit).value != 0 {
				values << (value as ast.IntLit).value
			}
		}
	}
	assert values == [1, 2, 3, 4]
}
