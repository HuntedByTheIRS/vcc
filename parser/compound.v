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

// brace_list_is_constant says whether a brace list initializes its object
// without running anything: every element is a written constant - a number, a
// character or an address - rather than an expression the program evaluates,
// and a nested list is constant the same way. An object built from such a list
// holds the same bytes wherever it is built, so building it at the start of the
// statement is the object the literal would have built in place.
fn brace_list_is_constant(elements []BraceElement) bool {
	for element in elements {
		if element.expr != none {
			return false
		}
		if list := element.list {
			if !brace_list_is_constant(list.elements) {
				return false
			}
		}
	}
	return true
}

fn (mut p Parser) parse_compound_literal(spec DeclSpec, d Declarator, at tokenize.Token) !ast.Expr {
	list := p.parse_brace_initializer(true) or {
		return error('compound literal initializer')
	}
	if p.compound_unstable > 0 && !brace_list_is_constant(list.elements) {
		p.error_at(at, 'unsupported: a compound literal whose initializer is not constant is built where its statement begins, and this one is written inside a condition, a loop step or a short-circuited operand, where the standard may evaluate it a number of times the statement does not describe')
		return error('compound literal in a re-evaluated place')
	}
	if p.compound_pending.len == 0 {
		// A compound literal outside a statement is one whose object lives in
		// the image rather than in a frame. The one shape this reader builds
		// there is a pointer initialized by an array literal, which the
		// file-scope reader recognizes before it gets here.
		p.error_at(at, 'unsupported: a compound literal here is not one this compiler builds')
		return error('compound literal outside a statement')
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

// compound_literal_size answers the size of the object a compound literal names
// without building it, which is what `sizeof (int[]){1, 2, 3}` asks: 6.5.3.4
// makes a `sizeof` operand's value a constant and its operand unevaluated, so
// the brace list is read only for the size an unsized array's brackets take
// from it, and nothing is stored.
fn (mut p Parser) compound_literal_size(spec DeclSpec, d Declarator, list BraceList) ?int {
	declared := p.declared_type(spec.clause, d)
	mut target := declared
	if declared.is_array() && d.array_count() <= 0 {
		named := brace_array_count(list.elements)
		if named > 0 {
			target = types.array_of(declared.element() or { declared }, named)
		}
	}
	return p.representation.size_of(target)
}

// looks_like_compound_literal says whether the tokens at the cursor are a
// compound literal written where only a brace list after the closing
// parenthesis can tell it from a conversion. The parenthesis are matched
// without reading anything, because the answer decides which reader runs and a
// reader that guessed would have to be undone.
fn (p Parser) looks_like_compound_literal() bool {
	if !p.at_punct('(') || !p.starts_type_name(p.peek_at(1)) {
		return false
	}
	mut depth := 0
	mut i := p.pos
	for i < p.tokens.len {
		t := p.tokens[i]
		if t.kind == .punct {
			if t.text == '(' {
				depth++
			} else if t.text == ')' {
				depth--
				if depth == 0 {
					next := i + 1
					return next < p.tokens.len && p.tokens[next].kind == .punct
						&& p.tokens[next].text == '{'
				}
			}
		}
		i++
	}
	return false
}

// file_scope_compound_literal reads a compound literal written as the
// initializer of an object at file scope, where the unnamed object it names has
// static storage duration rather than the enclosing block's. The object is a
// definition in the image like any other top-level object, with a name of the
// reader's own, and the value the literal is worth is that object's address:
// `int *p = (int[]){1, 2, 3};` defines an int[3] holding 1, 2 and 3 and
// initializes p with the address of its first element, which is what decays an
// array to a pointer.
//
// The shape is read for an array whose element is a scalar, which is what an
// image writes as a run of constants. An array of aggregates and a struct
// literal would need the member walk the file-scope reader already does for a
// named object, and neither is a shape the tests here settle, so each is
// refused by name rather than written wrong.
fn (mut p Parser) file_scope_compound_literal() ?ast.AddressInit {
	at := p.peek()
	name := p.compound_name()
	p.next() // (
	spec, d, _ := p.parse_type_name_parts(1) or { return none }
	if !p.expect_punct(')') {
		return none
	}
	list := p.parse_brace_initializer(false) or { return none }
	declared := p.declared_type(spec.clause, d)
	if !declared.is_array() {
		p.error_at(at, 'unsupported: a compound literal at file scope is implemented for an array of a scalar type, and this one is of the type ${declared.describe()}')
		return none
	}
	element := declared.element() or { return none }
	if element.kind in [types.Kind.struct_, .union_, .array, .unknown] {
		p.error_at(at, 'unsupported: a compound literal at file scope is implemented for an array of a scalar type, and its element is ${element.describe()}')
		return none
	}
	mut count := d.array_count()
	if count <= 0 {
		count = list.elements.len
	}
	written := p.spelling_of(spec, 0)
	inits, init_floats := p.initializer_list_for(written, list.elements, name, at)
	p.declared[name] = true
	p.globals << ast.Global{
		name:        name
		typ:         written
		resolved:    types.array_of(element, count)
		count:       count
		inits:       inits
		init_floats: init_floats
		line:        at.line
		col:         at.col
	}
	return ast.AddressInit{
		name: name
		line: at.line
		col:  at.col
	}
}
