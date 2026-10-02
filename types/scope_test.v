module types

// The symbol table is the one-pass rule written down: a name is found only where
// it has already been declared, and the innermost scope answers first.

fn symbol(name string, typ Type) Symbol {
	return Symbol{
		name: name
		typ:  typ
	}
}

fn test_a_name_declared_in_a_scope_is_found_there() {
	mut table := new_table()
	assert table.at_file_scope()
	assert table.depth() == 1
	assert table.lookup('x') == none
	table.declare(symbol('x', int_type()))
	found := table.lookup('x') or {
		assert false
		return
	}
	assert found.typ.same(int_type())
	assert table.lookup('y') == none
}

fn test_an_inner_declaration_shadows_an_outer_one_and_does_not_outlive_it() {
	mut table := new_table()
	table.declare(symbol('x', int_type()))
	table.enter()
	assert table.depth() == 2
	assert !table.at_file_scope()
	table.declare(symbol('x', char_type()))
	inner := table.lookup('x') or {
		assert false
		return
	}
	assert inner.typ.same(char_type())
	table.leave()
	assert table.depth() == 1
	outer := table.lookup('x') or {
		assert false
		return
	}
	assert outer.typ.same(int_type())
	// The file scope is never left, so a leave with one scope open does nothing.
	table.leave()
	assert table.depth() == 1
	assert table.lookup('x') != none
}

fn test_a_redeclaration_in_one_scope_answers_with_the_earlier_declaration() {
	mut table := new_table()
	assert table.declare(symbol('f', function_type(int_type(), [], false, true))) == none
	earlier := table.declare(symbol('f', function_type(int_type(), [], false, true))) or {
		assert false
		return
	}
	assert earlier.name == 'f'
	// The name is declared once: a redeclaration replaces the entry rather than
	// adding a second one.
	here := table.lookup_here('f') or {
		assert false
		return
	}
	assert here.name == 'f'
	// A typedef promises a type and does not define an object.
	mut names := new_table()
	names.declare(Symbol{
		name:    'size_t'
		typ:     opaque_type('size_t')
		storage: .typedef_
	})
	typedef := names.lookup('size_t') or {
		assert false
		return
	}
	assert typedef.is_typedef()
	assert typedef.storage == .typedef_
	assert !typedef.defined
}

// The type a declarator could not finish is completed by what follows it: an
// array's size comes from a string literal initializer written after the
// brackets, and the name has to answer with that size wherever it is used.
fn test_a_declared_type_can_be_completed_after_its_declarator() {
	mut table := new_table()
	table.declare(symbol('s', array_of(char_type(), -1)))
	incomplete := table.lookup('s') or {
		assert false
		return
	}
	assert !incomplete.typ.is_complete()
	table.complete_type('s', array_of(char_type(), 4))
	completed := table.lookup('s') or {
		assert false
		return
	}
	assert completed.typ.is_complete()
	assert completed.typ.count == 4
	// A name no scope holds is left alone rather than declared by the call.
	table.complete_type('missing', int_type())
	assert table.lookup('missing') == none
}

fn test_a_definition_keeps_the_name_defined_across_a_later_declaration() {
	mut table := new_table()
	table.declare(Symbol{
		name:    'f'
		typ:     function_type(void_type(), [], false, true)
		defined: true
	})
	table.declare(Symbol{
		name: 'f'
		typ:  function_type(void_type(), [], false, true)
	})
	held := table.lookup('f') or {
		assert false
		return
	}
	assert held.defined
}

// A tag has its own namespace: `struct S` and an object called S are two names.
fn test_a_tag_does_not_hide_an_object_and_an_object_does_not_hide_a_tag() {
	mut table := new_table()
	table.declare(symbol('S', int_type()))
	assert table.declare_tag('S', struct_type('S', [])) == none
	tag := table.lookup_tag('S') or {
		assert false
		return
	}
	assert tag.kind == .struct_
	object := table.lookup('S') or {
		assert false
		return
	}
	assert object.typ.kind == .int_
	// A tag written twice in one scope answers with the earlier declaration,
	// which is what a redefinition is reported from.
	table.enter()
	assert table.declare_tag('S', struct_type('S', [])) == none
	second := table.declare_tag('S', struct_type('S', [])) or {
		assert false
		return
	}
	assert second.kind == .struct_
	table.leave()
	assert table.lookup_tag('S') != none
	// A tag declared with no body is declared and not complete, so nothing may
	// be laid out in it.
	table.declare_tag('T', Type{
		kind: .opaque
		tag:  'T'
	})
	incomplete := table.lookup_tag('T') or {
		assert false
		return
	}
	assert !incomplete.is_complete()
	assert table.lookup_tag('U') == none
}

// 6.2.2: the linkage a declaration has, from its storage class and where it was
// written.
fn test_linkage_comes_from_the_storage_class_and_the_scope() {
	// At file scope external unless static makes it internal.
	assert linkage_for(.automatic, true, none) == .external
	assert linkage_for(.extern_, true, none) == .external
	assert linkage_for(.static_, true, none) == .internal
	// A typedef names a type and has no linkage at all.
	assert linkage_for(.typedef_, true, none) == .none
	assert linkage_for(.typedef_, false, none) == .none
	// Inside a body, nothing has linkage except extern, which takes the linkage
	// of the declaration outside it when there is one.
	assert linkage_for(.automatic, false, none) == .none
	assert linkage_for(.static_, false, none) == .none
	assert linkage_for(.register_, false, none) == .none
	assert linkage_for(.extern_, false, none) == .external
	outside := Symbol{
		name:    'x'
		linkage: .internal
	}
	assert linkage_for(.extern_, false, outside) == .internal
	assert linkage_for(.extern_, true, outside) == .external
}

fn test_an_enumeration_constant_is_found_with_its_value() {
	mut table := new_table()
	assert table.lookup_constant('N') == none
	table.declare_constant('N', 4)
	value := table.lookup_constant('N') or {
		assert false
		return
	}
	assert value == 4
	assert table.lookup_constant('M') == none
}

// A constant whose value is zero is a constant like any other: the name being
// present is the question, not whether the number is true.
fn test_a_constant_of_zero_is_still_found() {
	mut table := new_table()
	table.declare_constant('ZERO', 0)
	value := table.lookup_constant('ZERO') or {
		assert false
		return
	}
	assert value == 0
}

// An inner enum hides an outer constant and gives it back when its block ends,
// which is the same rule the symbols follow.
fn test_an_inner_constant_shadows_an_outer_one_and_does_not_outlive_it() {
	mut table := new_table()
	table.declare_constant('N', 1)
	table.enter()
	table.declare_constant('N', 2)
	inner := table.lookup_constant('N') or {
		assert false
		return
	}
	assert inner == 2
	table.leave()
	outer := table.lookup_constant('N') or {
		assert false
		return
	}
	assert outer == 1
}
