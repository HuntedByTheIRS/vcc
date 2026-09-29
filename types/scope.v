module types

// The names a translation unit declares, the scopes they are declared in, and the
// linkage and storage duration each one has.
//
// The symbol table lives here rather than in the parser because the parser needs
// it while it reads: a type resolves in one pass, so a declaration is complete
// when its reader finishes it, and a name a use cannot find is a diagnostic
// rather than an entry in a list some later walk is supposed to fix up.
//
// There are two namespaces, because C has two: an ordinary identifier (an object,
// a function, or a type name) and a tag (`struct S`, `union S`, `enum S`). A tag
// never hides an object and an object never hides a tag.

// Storage is the storage class a declaration wrote, and `.automatic` is a
// declaration that wrote none.
pub enum Storage {
	automatic
	typedef_
	extern_
	static_
	register_
}

// Linkage is what 6.2.2 gives a name: how it is known to the rest of the program,
// to the rest of the file, or nowhere outside its own scope.
pub enum Linkage {
	// none: the name is known inside its block and nowhere else.
	none
	// internal: one name for the whole file, and no name outside it.
	internal
	// external: one name for the whole program.
	external
}

// Symbol is one name as it was declared: what it is called, what type it has,
// where it was declared, and whether that declaration defined it.
pub struct Symbol {
pub:
	name    string
	typ     Type
	storage Storage
	linkage Linkage
	line    int
	col     int
	// defined says the declaration is the one that makes the object or the
	// function exist, rather than a declaration that promises it does.
	defined bool
}

// is_typedef says whether the name is a type name rather than an object.
pub fn (s Symbol) is_typedef() bool {
	return s.storage == .typedef_
}

// Scope is one run of declarations: a block, a function's parameter list, or the
// whole file. Tags have their own table because a tag and an ordinary identifier
// of the same spelling are two different names.
pub struct Scope {
pub mut:
	symbols map[string]Symbol
	tags    map[string]Type
}

// Table is the scopes a file is inside of, outermost first, so the file scope is
// the first entry and the block being read is the last. A new block is an entry,
// and a name is found in the innermost scope that has it, which is what makes an
// inner declaration shadow an outer one.
pub struct Table {
pub mut:
	scopes []Scope
}

// new_table is a table holding the file scope and nothing else.
pub fn new_table() Table {
	return Table{
		scopes: [Scope{
			symbols: map[string]Symbol{}
			tags:    map[string]Type{}
		}]
	}
}

// enter opens a scope, and leave closes the innermost one. The file scope is
// never closed.
pub fn (mut t Table) enter() {
	t.scopes << Scope{
		symbols: map[string]Symbol{}
		tags:    map[string]Type{}
	}
}

pub fn (mut t Table) leave() {
	if t.scopes.len > 1 {
		t.scopes = t.scopes[..t.scopes.len - 1]
	}
}

// depth is how many scopes are open, which is what tells a declaration at file
// scope from one inside a body.
pub fn (t Table) depth() int {
	return t.scopes.len
}

pub fn (t Table) at_file_scope() bool {
	return t.scopes.len <= 1
}

// lookup finds a name, innermost scope first, and answers none when no scope has
// it. It is the whole of the one-pass rule: a name that is not declared yet is
// not there to find.
pub fn (t Table) lookup(name string) ?Symbol {
	for index := t.scopes.len - 1; index >= 0; index-- {
		if symbol := t.scopes[index].symbols[name] {
			return symbol
		}
	}
	return none
}

// lookup_here finds a name in the innermost scope only, which is the question a
// redeclaration asks.
pub fn (t Table) lookup_here(name string) ?Symbol {
	return t.scopes[t.scopes.len - 1].symbols[name] or { return none }
}

// declare records a declaration in the innermost scope and answers with the
// declaration it replaces, which is none for a new name and the earlier one for a
// redeclaration. Two declarations of one name in one scope are one name, and
// whether they are compatible is the question their reader asks.
pub fn (mut t Table) declare(symbol Symbol) ?Symbol {
	mut previous := ?Symbol(none)
	if earlier := t.scopes[t.scopes.len - 1].symbols[symbol.name] {
		previous = earlier
	}
	// A second declaration of a name does not un-define it: a declaration that
	// promises and a definition that follows are one object.
	defined := if earlier := previous { earlier.defined || symbol.defined } else { symbol.defined }
	t.scopes[t.scopes.len - 1].symbols[symbol.name] = Symbol{
		...symbol
		defined: defined
	}
	return previous
}

// declare_tag records a tag in the innermost scope and answers with the
// declaration it replaces, which is how a tag written twice in one scope is
// noticed. A tag written with no body declares it and does not define it, so the
// type it leaves behind is not complete.
pub fn (mut t Table) declare_tag(name string, typ Type) ?Type {
	previous := t.scopes[t.scopes.len - 1].tags[name] or {
		t.scopes[t.scopes.len - 1].tags[name] = typ
		return none
	}
	if typ.complete {
		t.scopes[t.scopes.len - 1].tags[name] = typ
	}
	return previous
}

// lookup_tag finds a tag, innermost scope first.
pub fn (t Table) lookup_tag(name string) ?Type {
	for index := t.scopes.len - 1; index >= 0; index-- {
		if tag := t.scopes[index].tags[name] {
			return tag
		}
	}
	return none
}

// linkage_for is 6.2.2: what linkage a declaration with this storage class has,
// where it was written, and what the name already means.
//
// A file scope declaration has external linkage unless `static` makes it internal,
// and a name declared `extern` inside a body has the linkage of the declaration
// outside it. Everything else declared in a body is known inside that body only.
// A typedef names a type rather than an object and has no linkage at all.
pub fn linkage_for(storage Storage, file_scope bool, previous ?Symbol) Linkage {
	if storage == .typedef_ {
		return .none
	}
	if file_scope {
		if storage == .static_ {
			return .internal
		}
		return .external
	}
	if storage == .extern_ {
		if earlier := previous {
			if earlier.linkage != .none {
				return earlier.linkage
			}
		}
		return .external
	}
	return .none
}
