module parser

import ast
import tokenize
import types

// This file reads a compound literal, C99 6.5.2.5: a type name in parentheses
// followed by a brace list, `(int[]){10, 20, 30}`. The construct names an
// unnamed object whose lifetime is the enclosing block, so it is an lvalue, and
// an array one decays to a pointer to its first element wherever an array does.
//
// The object is not a shape the back end has a node for, and it does not need
// one: the tree already places a brace initializer against a named object in a
// body, one store per scalar subobject, and an object of an aggregate type has
// an address, a member and an element wherever those are wanted. So the literal
// is read as what it is - a declaration of an object with no name, followed by
// the stores that initialize it - and the expression the literal is worth is a
// use of that name. Everything after that is the code that was already there:
// `arr[1] = 21` writes through the name, `&(P){3, 4}` takes its address, and
// passing one to a function reads it the way passing a named object does.
//
// The statements are put in front of the statement the literal was written in,
// which is where the object has to be created before the expression that reads
// it runs. `parse_statement` opens one list per statement for this to be
// appended to.
fn (mut p Parser) parse_compound_literal(spec DeclSpec, d Declarator, at tokenize.Token) !ast.Expr {
	list := p.parse_brace_initializer(true) or {
		return error('compound literal initializer')
	}
	if p.compound_pending.len == 0 {
		// A compound literal outside a statement is one whose object would live
		// in the image rather than in a frame, and that object is not built
		// here.
		p.error_at(at, 'unsupported: a compound literal at file scope is not implemented')
		return error('compound literal at file scope')
	}
	name := p.compound_name()
	target, stmts := p.compound_literal_object(name, spec, d, at, list)
	p.compound_pending[p.compound_pending.len - 1] << stmts
	return ast.Expr(ast.Ident{
		name: name
		typ:  target
		line: at.line
		col:  at.col
	})
}

// compound_name is the name of the unnamed object a compound literal declares.
// It is in the namespace the implementation reserves for itself, so no source
// text can write it, and the serial makes each literal's object its own.
fn (mut p Parser) compound_name() string {
	name := '__vcc_compound_${p.compound_serial}'
	p.compound_serial++
	return name
}

// compound_literal_object builds the declaration of the compound literal's
// object and the stores that initialize it, and answers the object's type and
// the statements. The type is the type name with a size an unsized array's
// brackets take from the list, which is the size a later `sizeof` or subscript
// reads: `(int[]){1, 2, 3}` is an int[3].
//
// The initialization is the same walk a body's brace initializer makes: every
// scalar subobject is stored zero first, because the frame slot starts as
// whatever was there and 6.7.8p21 makes the subobjects the list did not reach
// hold zero, and then each value the list wrote is stored over it. That is what
// makes a flat list, a nested list, a designator and an element that is any
// expression all one path here.
fn (mut p Parser) compound_literal_object(name string, spec DeclSpec, d Declarator, at tokenize.Token, list BraceList) (types.Type, []ast.Stmt) {
	declared := p.declared_type(spec.clause, d)
	mut target := declared
	mut count := d.array_count()
	if declared.is_array() && count <= 0 {
		// An array whose brackets named no size takes it from the list, the way
		// a declaration's does: the objects the list reaches are how many the
		// array turned out to be.
		named := brace_array_count(list.elements)
		if named > 0 {
			count = named
			target = types.array_of(declared.element() or { declared }, named)
		}
	}
	p.declare_name(name, target, at, false)
	stride := declaration_stride(target, p.representation)
	bytes := p.aggregate_bytes(declared)
	mut stmts := []ast.Stmt{}
	stmts << ast.Stmt{
		kind:        .var_decl
		decl_name:   name
		decl_type:   p.spelling_of(spec, d.pointer_count())
		decl_count:  count
		decl_stride: stride
		bytes:       bytes
		line:        at.line
		col:         at.col
	}
	array := target.kind == .array
	element := if array { target.element() or { target } } else { target }
	element_width := p.representation.size_of(element) or { 0 }
	mut writes := []BraceWrite{}
	p.fill_brace(target, list.elements, 0, 0, mut writes)
	mut leaves := []BraceWrite{}
	p.collect_leaves(target, 0, mut leaves)
	for leaf in leaves {
		stmts << p.store_a_leaf(name, at, leaf, zero_initializer(at), array, bytes, element_width,
			target)
	}
	for write in writes {
		value := if expression := write.element.expr {
			expression
		} else if number := write.element.number {
			p.constant_expr(number)
		} else {
			zero_initializer(at)
		}
		stmts << p.store_a_leaf(name, at, write, value, array, bytes, element_width, target)
	}
	return target, stmts
}
