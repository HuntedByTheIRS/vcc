module parser

import ast
import tokenize
import types

// This file is the declaration grammar of a preprocessed stream. A real header
// is mostly declarations the back end cannot turn into code: typedefs, tags,
// struct members, and function declarations whose parameters are pointers,
// varargs and GNU attributes. They still have to be read, because the only way
// to find where one declaration ends and the next begins is to parse it.
//
// Reading and keeping are different answers here. A typedef and a tag add no
// code, so neither is kept in the tree: what a type name means is a question for
// the symbol table, which is where the declaration records it, and a later stage
// asks the table rather than walking the tree for it. A function declaration is
// kept, with an empty body when it is a prototype, because the declaration is
// what names the function whether or not the file defines it. A function
// definition the back end cannot emit is reported: a definition is code, and code
// quietly left out is the failure this compiler is not allowed.

// storage_classes are the words that say what kind of declaration this is.
// The double-underscore spellings are the GNU ones: a system header reaches
// this parser with either, depending on what the preprocessor expanded, and
// neither changes what the reader has to do.
const storage_classes = ['typedef', 'extern', 'static', 'auto', 'register', 'inline', '_Thread_local',
	'__inline', '__inline__', '__thread', '__extension__']

// type_qualifiers say something about the type or the pointer they sit next to
// and nothing about the shape of the declaration. The GNU spellings are here
// for the same reason: `char *__restrict p` is how the headers write
// `char *restrict p`.
const type_qualifiers = ['const', 'volatile', 'restrict', '_Atomic', '__const', '__const__',
	'__volatile', '__volatile__', '__restrict', '__restrict__', '__signed', '__signed__']

// builtin_types are the type words of the language. A type can also be a name
// this file has typedef'd, which is why the parser carries that list.
const builtin_types = ['void', 'char', 'short', 'int', 'long', 'signed', 'unsigned', 'float', 'double',
	'_Bool', '_Complex', '_Imaginary']

// tag_keywords open the specifier that names a struct, a union or an enum.
const tag_keywords = ['struct', 'union', 'enum']

// gnu_postfix are the words that can follow a declarator and have to be read
// past: an attribute list and an assembler name. Both arrive in system
// headers, and a parser that stops at one stops in the middle of the
// declaration it belongs to.
const gnu_postfix = ['__attribute__', '__asm__', '__asm']

// max_declaration_depth bounds how deep a declarator or a tag body may nest.
// The nesting is counted rather than followed, because a file that nests a
// thousand structs is a file attacking the parser, and the answer to that is
// a diagnostic rather than a stack overflow.
const max_declaration_depth = 200

// starts_declaration says whether a token can open a declaration: one of the
// specifier words, or a name this file has already declared as a type.
fn (p Parser) starts_declaration(t tokenize.Token) bool {
	return t.kind == .identifier && (is_specifier_word(t.text) || p.is_type_name(t.text))
}

fn is_specifier_word(text string) bool {
	return text in storage_classes || text in type_qualifiers || text in builtin_types
		|| text in tag_keywords
}

// storage_of is the storage class a word names. `inline` and `__extension__` say
// something about a function and nothing about a storage class, so they leave the
// declaration with the one it would have had anyway.
fn storage_of(word string) types.Storage {
	return match word {
		'typedef' { types.Storage.typedef_ }
		'extern' { types.Storage.extern_ }
		'static' { types.Storage.static_ }
		'register' { types.Storage.register_ }
		'_Thread_local', '__thread' { types.Storage.thread_ }
		else { types.Storage.automatic }
	}
}

// add_qualifier adds the qualifier a word names to the ones already read. The
// GNU spellings are the same qualifiers under another name: `__const` is `const`,
// and a declaration that writes either means the same thing.
fn add_qualifier(quals types.Qualifiers, word string) types.Qualifiers {
	return types.Qualifiers{
		const_:    quals.const_ || word in ['const', '__const', '__const__']
		volatile_: quals.volatile_ || word in ['volatile', '__volatile', '__volatile__']
		restrict_: quals.restrict_ || word in ['restrict', '__restrict', '__restrict__']
	}
}

// DeclSpec is what the specifiers of a declaration add up to: the words in the
// order they were written, and the properties a later stage asks about. words
// holds the storage classes and the qualifiers too, because the diagnostic for
// a definition this compiler cannot emit names the first word that stopped it.
struct DeclSpec {
mut:
	words      []string
	type_words []string
	start      tokenize.Token
	is_typedef bool
	is_extern  bool
	has_type   bool
	tag_decl   bool
	// clause is the type the specifiers name, resolved as they are read: the
	// builtin words added up, a name followed to what it was declared as, or a
	// tag. The declarator that follows is built from it, and it is unresolved
	// when the model has no answer for the words - which is not the same as
	// saying the declaration has no type, only that this compiler has not
	// worked out which one it is.
	clause     types.Type
	qualifiers types.Qualifiers
	storage    types.Storage
}

fn (mut s DeclSpec) note(t tokenize.Token) {
	if s.words.len == 0 {
		s.start = t
	}
	s.words << t.text
}

fn (mut s DeclSpec) note_type(t tokenize.Token) {
	s.note(t)
	s.type_words << t.text
	s.has_type = true
}

// specifier_clause is the type the specifiers name. The words are the language's
// type words, a name this file declared as a type, or a compiler's own spelling
// of one that arrives from a header - `typedef __builtin_va_list va_list;` has
// no other reading. A tag is resolved where it is read, because only the tag's
// own namespace knows it, and it is passed in as the answer for that case.
//
// A name this compiler has no definition for becomes an opaque type carrying the
// name: the type exists, nothing may be laid out in it, and a diagnostic can say
// which name it was.
fn (p Parser) specifier_clause(spec DeclSpec, tag_clause types.Type) types.Type {
	mut clause := tag_clause
	if clause.kind == .unknown {
		if word_type := types.from_words(spec.type_words) {
			clause = word_type
		} else if spec.type_words.len == 1 {
			clause = p.name_clause(spec.type_words[0])
		} else {
			clause = types.opaque_type(spec.type_words.join(' '))
		}
	}
	return types.qualified(clause, spec.qualifiers)
}

// name_clause is the type a name written among the specifiers stands for: what a
// typedef declared it as, or an opaque type carrying the name when there is no
// declaration of it this reader has met.
fn (p Parser) name_clause(name string) types.Type {
	if symbol := p.scopes.lookup(name) {
		if symbol.is_typedef() {
			return symbol.typ
		}
	}
	return types.opaque_type(name)
}

// type_spelling is the type as it was written, with the pointer stars the
// declarator put in front of the name. The stars go down as one run, which is
// how a type is written: `char **argv` is a pointer to a pointer, and `char * *`
// is not what the file says.
fn (s DeclSpec) type_spelling(stars int) string {
	mut text := if s.type_words.len > 0 { s.type_words.join(' ') } else { s.words.join(' ') }
	if stars > 0 {
		text += ' ' + '*'.repeat(stars)
	}
	return text
}

// Declarator is what one declarator says: the name it gives, the pointer stars
// in front of that name, and whether it declares a function. An abstract
// declarator has no name, which is what a bare type and a parameter may have.
struct Declarator {
mut:
	name    string
	name_at tokenize.Token
	stars   int
	star_at tokenize.Token
	// star_quals are the qualifiers written after each star, one entry per star.
	// That is where `char * const p` puts its const: on the pointer and not on
	// the character it points at, which is the difference between two types an
	// assignment may not drop either way.
	star_quals []types.Qualifiers
	array_at   tokenize.Token
	// array_count is how many elements the first `[...]` suffix asked for, and
	// zero when the suffix did not write a size this reader could read — an
	// empty pair of brackets, or something that was not a number. array_dims
	// counts the suffixes: a declarator may write more than one, and only the
	// first is a shape this tree has.
	array_count int
	array_dims  int
	is_function bool
	// params are the parameters this declarator names, in the order they were
	// written. Every function declarator is read for them and the ones that
	// declare a function by name keep them: a pointer to a function is not
	// something a call reaches by name, and this compiler emits no such call.
	params []ast.Param
	// variadic says the list ended in an ellipsis and prototyped says it was a
	// prototype at all: `int f()` names no parameters and says nothing about a
	// call, while `int f(void)` names the empty list.
	variadic   bool
	prototyped bool
	// inner_function says the suffix named the function a pointer points at.
	// `int (*f)(int)` declares a pointer, and what it points at is a function
	// type: a type this model has, even though a call through the pointer is not
	// a shape this tree carries. The parameters in that case are the ones the
	// function being pointed at takes, and they are read from the same list.
	inner_function bool
	// param_problem says what makes the parameter list one the back end cannot
	// emit, and stays empty when there is nothing wrong with it. It is recorded
	// rather than reported because whether it matters is only known when a body
	// turns up after it: a prototype promises, and a definition is code.
	param_problem string
	param_at      tokenize.Token
}

// Params is what a parameter list turned out to be: the parameters it named, in
// the order they were written, and the reason it is one a definition cannot use,
// when there is one. The reason is recorded rather than reported because whether
// it matters is only known when a body turns up after it: a prototype promises,
// and a definition is code.
struct Params {
mut:
	params  []ast.Param
	problem string
	at      tokenize.Token
	// variadic says the list ended in an ellipsis, so there are arguments it
	// does not name. prototyped says the list was a prototype at all: `()` names
	// no parameters and says nothing about a call, which is a different thing
	// from naming the empty list.
	variadic   bool
	prototyped bool
}

// parse_declaration reads one declaration and returns the functions it
// declares or defines. A typedef, a tag and an object are read and dropped,
// since none of them adds code. A declaration that cannot be read is skipped
// to its end here, so the caller never sees a half-read declaration and the
// next one starts in the right place.
fn (mut p Parser) parse_declaration() []ast.FnDecl {
	mut decls := []ast.FnDecl{}
	spec := p.parse_decl_specifiers(0) or {
		p.skip_declaration()
		return decls
	}
	if p.at_punct(';') {
		// A tag with no declarator, as in `struct _IO_FILE;`. It says the name
		// exists and nothing else.
		if !spec.tag_decl {
			p.error_at(p.peek(), 'unsupported: expected a declarator, found ${describe(p.peek())}')
		}
		p.next()
		return decls
	}
	mut names := []string{}
	mut data_seen := false
	mut data_defined := false
	mut data_name := ''
	mut data_at := spec.start
	// What a definition of an object at the top level needs to be laid out: the
	// type and the count as written, and the constant it starts at. They are
	// kept aside from the declarator because the declarator is gone by the time
	// the declaration is known to be a definition - it is the `=` or the `;`
	// that decides that.
	mut data_type := ''
	mut data_stars := 0
	mut data_count := 0
	mut data_clause := types.Type{}
	mut data_init := ?i64(none)
	for {
		d := p.parse_declarator(0) or {
			p.skip_declaration()
			return decls
		}
		p.skip_gnu_postfix() or {
			p.skip_declaration()
			return decls
		}
		if d.name.len > 0 {
			names << d.name
		}
		if d.is_function {
			if p.at_punct('{') {
				if spec.is_typedef {
					p.error_at(d.name_at, 'unsupported: a typedef names a type, so it cannot have a function body')
					p.skip_declaration()
					return decls
				}
				p.check_definition(spec, d)
				p.declare_name(d.name, p.declared_type(spec.clause, d), d.name_at, true)
				// A parameter's scope is the body, so the parameters are
				// declared in a scope around it: their declarators were read
				// before the body existed, and a name is typed where it is
				// read.
				p.scopes.enter()
				p.declare_parameters(d.params)
				body := p.parse_block()
				p.scopes.leave()
				statements := body or { return decls }
				// A definition with no name has been reported and has no
				// identity to record; one whose signature was reported is kept
				// anyway, because the tree is what the file said and the
				// diagnostic is what stops it being compiled.
				if d.name.len > 0 {
					decls << ast.FnDecl{
						name:     d.name
						ret:      spec.type_spelling(d.stars)
						ret_type: p.pointer_type(spec.clause, d)
						resolved: p.declared_type(spec.clause, d)
						params:   d.params
						body:     statements
						line:     d.name_at.line
						col:      d.name_at.col
					}
				}
				return decls
			}
			// A prototype. It is kept with an empty body: the declaration is
			// what names the function whether or not this file defines it, and
			// the types in it are only a promise, since nothing is emitted for
			// a declaration. The parameters are kept anyway — a name and a type
			// as written are what the declaration said, and a later stage that
			// wants to check a call against it would find them here. A typedef
			// of a function type is not a function declaration, so it is not
			// kept as one.
			if !spec.is_typedef {
				decls << ast.FnDecl{
					name:     d.name
					ret:      spec.type_spelling(d.stars)
					ret_type: p.pointer_type(spec.clause, d)
					resolved: p.declared_type(spec.clause, d)
					params:   d.params
					body:     []ast.Stmt{}
					line:     d.name_at.line
					col:      d.name_at.col
				}
			}
		} else {
			if !data_seen {
				data_seen = true
				data_name = d.name
				data_at = if d.name.len > 0 { d.name_at } else { spec.start }
				data_type = spec.type_spelling(d.stars)
				data_stars = d.stars
				data_count = d.array_count
				data_clause = p.declared_type(spec.clause, d)
			}
			if p.at_punct('=') {
				// An initializer makes it a definition even when the
				// declaration says extern: the object has to live somewhere.
				data_defined = true
				p.next()
				data_init = p.file_scope_constant()
				p.skip_to_separator() or {
					p.skip_declaration()
					return decls
				}
			}
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct(';') {
			p.next()
			break
		}
		p.error_at(p.peek(), 'unsupported: expected , or ; after a declarator, found ${describe(p.peek())}')
		p.skip_declaration()
		return decls
	}
	if spec.is_typedef {
		for name in names {
			p.register_typedef(name)
		}
		return decls
	}
	if data_seen {
		if spec.is_extern && !data_defined {
			// An extern declaration adds no code: it says the object exists
			// somewhere else, and this compiler has no storage to give it.
			return decls
		}
		if data_stars > 0 {
			p.error_at(data_at, 'unsupported: ${data_name} is a pointer, and a pointer defined at the top level is storage this compiler does not lay out yet')
			return decls
		}
		// The type of an object defined at the top level is the same question a
		// definition's return type is: storage the program has to find room for,
		// so the answer is the same helper. A prototype can promise anything; a
		// definition cannot promise a type this back end has no width for.
		if offender := unsupported_type_word(spec) {
			p.error_at(data_at, 'unsupported type ${offender}')
			return decls
		}
		if data_defined && data_init == none {
			p.error_at(data_at, 'unsupported: ${data_name} is initialized with something that is not a number, and only a number can be written into the image so far')
			return decls
		}
		if data_name.len == 0 {
			p.error_at(data_at, 'unsupported: a definition of an object at the top level needs a name')
			return decls
		}
		// A definition of an object: storage the image holds, which every
		// function reads and writes by name. Everything the back end needs to
		// lay the bytes out is known here - the type, how many elements, and the
		// constant the storage starts at - so no later stage has to ask.
		p.declare_name(data_name, data_clause, data_at, true)
		p.globals << ast.Global{
			name:     data_name
			typ:      data_type
			resolved: data_clause
			count:    data_count
			init:     data_init
			line:     data_at.line
			col:      data_at.col
		}
	}
	return decls
}

// file_scope_constant reads the initializer a file-scope definition may have: a
// number, signed, which is the only shape the language allows there anyway.
// Anything else - a string, a brace list, an expression - reads as none, and the
// caller reports it: what is written into the image is a constant, and a
// constant is what can be written.
fn (mut p Parser) file_scope_constant() ?i64 {
	sign := if p.at_punct('-') {
		p.next()
		-1
	} else if p.at_punct('+') {
		p.next()
		1
	} else {
		1
	}
	if p.peek().kind != .number {
		return none
	}
	t := p.peek()
	p.next()
	value := parse_integer_literal(t.text) or { return none }
	return sign * value
}

// check_definition reports what keeps a definition from being emitted. A
// prototype can promise anything, because nothing is emitted for it; a
// definition is code, and this back end takes three return types and parameters
// it can name.
fn (mut p Parser) check_definition(spec DeclSpec, d Declarator) {
	if d.name.len == 0 {
		p.error_at(spec.start, 'unsupported: a function definition needs a name')
		return
	}
	if spec.clause.is_complex() || spec.clause.kind == .long_double {
		// A type the model knows and the emitter has no form for is a different
		// answer from a type whose first word is not one the emitter reads:
		// `long double` and `double _Complex` are each one type, and the refusal
		// names it rather than naming half of it.
		p.error_at(spec.start, 'unsupported: ${spec.clause.describe()} is a type this compiler does not emit yet, so a function cannot return it')
		return
	}
	if offender := unsupported_type_word(spec) {
		p.error_at(spec.start, 'unsupported type ${offender}')
		return
	}
	if d.stars > 0 {
		p.error_at(d.star_at, 'unsupported: pointer return types are not implemented')
		return
	}
	if d.param_problem.len > 0 {
		p.error_at(d.param_at, d.param_problem)
	}
}

// unsupported_type_word is the word among a declaration's specifiers that keeps
// the back end from giving an object the type it names, or none when every word
// is one the emitter has a form for. A definition's return type and a
// declaration inside a body are the same question, because both are storage the
// program has to find room for; a prototype is a promise, and a promise is not
// asked.
//
// It answers with the first word and not with the type as it was written, which
// is what the emitter stopped at: the diagnostic for `long long x` reads
// `unsupported type long`, and that wording is the compiler's published
// behavior, so it is not this lane's to move. A type written as two words is
// named in full where the answer is about the construct rather than about the
// word: the parameter list names what a parameter was declared with, and a
// complex type is refused by name below.
fn unsupported_type_word(spec DeclSpec) ?string {
	// The words a type is made of, not the storage class in front of them: an
	// `extern` or a `static` is not a type, and reporting one as an unsupported
	// type would be reporting the wrong word for the right reason.
	if spec.type_words.len == 0 {
		return none
	}
	if spec.type_words.len == 1 && spec.type_words[0] in supported_types {
		return none
	}
	if spec.type_words.len > 1 && spec.type_words[0] in supported_types {
		return spec.type_words[1]
	}
	return spec.type_words[0]
}

// parse_decl_specifiers reads the words in front of a declarator. It accepts
// what the language allows rather than what this compiler implements, because
// a header declares things this compiler has no opinion about and the
// declaration still has to be measured to its end.
fn (mut p Parser) parse_decl_specifiers(depth int) !DeclSpec {
	mut spec := DeclSpec{}
	mut tag_clause := types.Type{}
	for {
		t := p.peek()
		if t.kind == .directive {
			p.next()
			continue
		}
		if t.kind != .identifier {
			break
		}
		if t.text in storage_classes {
			p.next()
			spec.note(t)
			if t.text == 'typedef' {
				spec.is_typedef = true
			}
			if t.text == 'extern' {
				spec.is_extern = true
			}
			// The first storage class written is the one the declaration has:
			// `inline static` is a static function, and a word that says
			// nothing about storage leaves the answer alone.
			if spec.storage == .automatic {
				spec.storage = storage_of(t.text)
			}
			continue
		}
		if t.text in type_qualifiers {
			p.next()
			spec.note(t)
			spec.qualifiers = add_qualifier(spec.qualifiers, t.text)
			continue
		}
		if t.text in builtin_types {
			p.next()
			spec.note_type(t)
			continue
		}
		if t.text in tag_keywords {
			p.next()
			spec.note(t)
			tag := p.parse_tag_specifier(t, depth)!
			spec.type_words << tag.spelling
			spec.has_type = true
			spec.tag_decl = true
			tag_clause = tag.clause
			continue
		}
		if p.is_type_name(t.text) && !spec.has_type {
			// A name this file has declared as a type. Only one can sit among
			// the specifiers, so once a type has been read the name is the
			// declarator's: `typedef __ssize_t ssize_t;` redeclares ssize_t and
			// does not name two types.
			p.next()
			spec.note_type(t)
			continue
		}
		// An identifier in specifier position that is not a name this file has
		// declared is still a type name. A compiler declares spellings of its
		// own, which is how __builtin_va_list arrives here, and there is no
		// other reading of `typedef __builtin_va_list va_list;`.
		if !spec.has_type {
			p.next()
			spec.note_type(t)
			p.register_typedef(t.text)
			continue
		}
		break
	}
	if spec.words.len == 0 {
		p.error_at(p.peek(), 'unsupported: expected a type, found ${describe(p.peek())}')
		return error('expected a type')
	}
	spec.clause = p.specifier_clause(spec, tag_clause)
	// What the declarator that follows is built from is held here, because a
	// declarator is read in three places - a declaration, a parameter and a
	// member - and this is the one place that resolves the specifiers.
	p.pending_base = spec.clause
	p.pending_storage = spec.storage
	return spec
}

// TagType is a tag specifier: the keyword and the tag as written, which is how a
// tag is spelled wherever it is used, and the type it named, which is complete
// when the specifier wrote a body and a tag that is only a name when it did not.
struct TagType {
	spelling string
	clause   types.Type
}

// parse_tag_specifier reads a struct, union or enum specifier. Its tag lives in
// its own namespace, where the keyword is part of the name: `struct S` and
// `union S` are two tags, and neither hides an object called S. A tag with a body
// defines it and is complete; a tag written without one is declared here if
// nothing declared it before, so that `struct S *p;` read before
// `struct S { ... };` is a pointer to the type the later declaration defines.
fn (mut p Parser) parse_tag_specifier(keyword tokenize.Token, depth int) !TagType {
	if depth > max_declaration_depth {
		p.error_at(keyword, 'declaration is nested more than ${max_declaration_depth} levels deep')
		return error('declaration nested too deeply')
	}
	kind := tag_kind(keyword.text)
	mut spelling := keyword.text
	mut tag := ''
	if p.peek().kind == .identifier {
		tag = p.next().text
		spelling += ' ' + tag
	}
	if !p.at_punct('{') {
		// No body: the type is whatever the tag namespace has for it, or a tag
		// this reader declares now so that the definition after it completes
		// the same type.
		clause := p.scopes.lookup_tag(spelling) or {
			fresh := types.incomplete_tag(kind, tag)
			p.scopes.declare_tag(spelling, fresh)
			fresh
		}
		return TagType{
			spelling: spelling
			clause:   clause
		}
	}
	open := p.next()
	if keyword.text == 'enum' {
		// An enumerator list is names and constant expressions, and nothing in
		// it is a declaration, so it is scanned as one bracketed region.
		p.skip_balanced(open)!
		clause := types.enum_type(tag)
		p.scopes.declare_tag(spelling, clause)
		return TagType{
			spelling: spelling
			clause:   clause
		}
	}
	members := p.parse_member_list(keyword, open, depth)!
	clause := if keyword.text == 'union' {
		types.union_type(tag, members)
	} else {
		types.struct_type(tag, members)
	}
	p.scopes.declare_tag(spelling, clause)
	return TagType{
		spelling: spelling
		clause:   clause
	}
}

// tag_kind is the kind a tag keyword names.
fn tag_kind(keyword string) types.Kind {
	return match keyword {
		'union' { types.Kind.union_ }
		'enum' { types.Kind.enum_ }
		else { types.Kind.struct_ }
	}
}

// parse_member_list reads the body of a struct or a union and returns its members
// in the order they were written. A member is a name, the type it resolved to, and
// the width when it was written as a bitfield; the members are what make the
// aggregate a complete type, since how much room it takes is the question the
// object representation answers from them.
//
// An unnamed bitfield carries no name and its width, which is what asks the next
// unit of its type to start where it is: the object representation reads a width
// of zero that way.
fn (mut p Parser) parse_member_list(keyword tokenize.Token, open tokenize.Token, depth int) ![]types.Member {
	mut members := []types.Member{}
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated ${keyword.text} body, opened at ${open.line}:${open.col}')
			return error('unterminated tag body')
		}
		if t.kind == .directive {
			p.next()
			continue
		}
		if t.kind == .punct && t.text == '}' {
			p.next()
			return members
		}
		if t.kind == .punct && t.text == ';' {
			p.next()
			continue
		}
		spec := p.parse_decl_specifiers(depth + 1)!
		// An unnamed bitfield, `int : 3;`, has a width and no declarator.
		if p.at_punct(':') {
			bits := p.parse_bitfield_width()!
			members << types.Member{
				typ:      spec.clause
				bitfield: true
				bits:     bits
				line:     spec.start.line
				col:      spec.start.col
			}
			continue
		}
		for {
			if p.at_punct(';') {
				p.next()
				break
			}
			if p.at_punct('}') {
				// A member whose semicolon is missing, which the closing brace
				// ends anyway.
				break
			}
			d := p.parse_declarator(depth + 1)!
			p.skip_gnu_postfix()!
			bits := if p.at_punct(':') { p.parse_bitfield_width()! } else { 0 }
			members << types.Member{
				name:     d.name
				typ:      p.declared_type(spec.clause, d)
				bitfield: bits > 0
				bits:     bits
				line:     if d.name.len > 0 { d.name_at.line } else { spec.start.line }
				col:      if d.name.len > 0 { d.name_at.col } else { spec.start.col }
			}
			if p.at_punct(',') {
				p.next()
				continue
			}
			if p.at_punct(';') {
				p.next()
				break
			}
			if p.at_punct('}') {
				break
			}
			p.error_at(p.peek(), 'unsupported: expected , or ; in a ${keyword.text} member, found ${describe(p.peek())}')
			return error('member list')
		}
	}
	return members
}

// parse_bitfield_width reads `: N`, the width of a bitfield. A width this reader
// can read is a number, which is what a source file writes; anything else - an
// expression a header computed - is scanned to its separator and the member is
// recorded without a width, which is what the reader that asked decides about.
fn (mut p Parser) parse_bitfield_width() !int {
	p.next() // :
	if p.peek().kind == .number {
		t := p.next()
		value := parse_integer_literal(t.text) or { return 0 }
		return int(value)
	}
	p.skip_to_separator()!
	return 0
}

// parse_declarator reads one declarator: pointer stars, a name, and the array
// and function suffixes that bind to it.
fn (mut p Parser) parse_declarator(depth int) !Declarator {
	if depth > max_declaration_depth {
		p.error_at(p.peek(), 'declaration is nested more than ${max_declaration_depth} levels deep')
		return error('declaration nested too deeply')
	}
	mut d := Declarator{}
	for p.at_punct('*') {
		if d.stars == 0 {
			d.star_at = p.peek()
		}
		p.next()
		d.stars++
		mut quals := types.Qualifiers{}
		// Qualifiers may sit between the star and the name: `char *restrict p`.
		for p.peek().kind == .identifier && p.peek().text in type_qualifiers {
			quals = add_qualifier(quals, p.peek().text)
			p.next()
		}
		d.star_quals << quals
	}
	mut wrapped := false
	if p.at_punct('(') {
		// A declarator in parentheses, as in `(*handler)(int)`. The suffixes
		// after the closing parenthesis bind to the declarator around them, not
		// to the name inside, which is the difference between a function and a
		// pointer to one.
		p.next()
		inner := p.parse_declarator(depth + 1)!
		if !p.expect_punct(')') {
			return error('unclosed declarator')
		}
		d = inner
		wrapped = true
	} else if p.peek().kind == .identifier {
		d.name_at = p.peek()
		d.name = p.next().text
	}
	pointer_to_function := wrapped && d.stars > 0
	for {
		if p.at_punct('[') {
			if d.array_at.line == 0 {
				d.array_at = p.peek()
			}
			d.array_dims++
			count := p.parse_array_suffix()!
			if d.array_dims == 1 {
				d.array_count = int(count)
			}
			continue
		}
		if p.at_punct('(') {
			params := p.parse_parameter_list(depth + 1)!
			if !pointer_to_function {
				d.is_function = true
			} else {
				d.inner_function = true
			}
			d.params = params.params
			d.variadic = params.variadic
			d.prototyped = params.prototyped
			if params.problem.len > 0 && d.param_problem.len == 0 {
				d.param_problem = params.problem
				d.param_at = params.at
			}
			continue
		}
		break
	}
	// The name is recorded where the declarator ends, which is where 6.2.1 says
	// its scope begins: a declaration is complete when its reader finishes it.
	p.note_declaration(d, depth)
	return d
}

// declared_type is the type a specifier and a declarator together name. The
// declarator grammar applies its pieces in the order it read them: the stars bind
// first and each binds to what is left, an array suffix makes an array of that,
// and a function suffix makes a function returning it.
//
// A declarator that wrote more than one array suffix is a shape this tree has no
// form for, so only the first becomes an array and the reader that asked for it
// reports the rest; the type is the one array it describes.
fn (p Parser) declared_type(base types.Type, d Declarator) types.Type {
	target := if d.inner_function {
		// The pointer points at the function its suffix named.
		types.function_type(base, type_params(d.params), d.variadic, d.prototyped)
	} else {
		base
	}
	mut typ := p.pointer_type(target, d)
	if d.array_at.line > 0 {
		typ = types.array_of(typ, if d.array_count > 0 { d.array_count } else { -1 })
	}
	if d.is_function {
		typ = types.function_type(typ, type_params(d.params), d.variadic, d.prototyped)
	}
	return typ
}

// type_params is the parameters of a declarator as the type model wants them. The
// tree keeps a parameter with the type as it was written, because that is what a
// definition's frame is laid out from; the type keeps the one the model resolved.
// parameter_spelling is the type a parameter was declared with, written the way
// it was written: the type words joined, and the storage class and qualifiers in
// front of them left out, since those are not the type.
fn parameter_spelling(spec DeclSpec) string {
	if spec.type_words.len == 0 {
		return spec.words.join(' ')
	}
	return spec.type_words.join(' ')
}

fn type_params(params []ast.Param) []types.Param {
	mut out := []types.Param{cap: params.len}
	for param in params {
		out << types.Param{
			name: param.name
			typ:  param.resolved
			line: param.line
			col:  param.col
		}
	}
	return out
}

// pointer_type is the base with the pointer stars of a declarator, and nothing
// else: what a function returns is its specifiers and its stars, without the
// function suffix and without an array the same declarator might have written for
// something else.
fn (p Parser) pointer_type(base types.Type, d Declarator) types.Type {
	mut typ := base
	for index in 0 .. d.stars {
		quals := if index < d.star_quals.len { d.star_quals[index] } else { types.Qualifiers{} }
		typ = types.qualified(types.pointer_to(typ), quals)
	}
	return typ
}

// note_declaration records the name a declarator gives. It is called for every
// declarator and answers for the top level only: a member and a parameter are
// declarators too, and neither declares a name a later use finds by itself - a
// member is reached through the object, and a parameter is declared in the body's
// own scope, where the definition puts it.
fn (mut p Parser) note_declaration(d Declarator, depth int) {
	if depth != 0 || d.name.len == 0 {
		return
	}
	base := p.pending_base or { return }
	p.declare_name(d.name, p.declared_type(base, d), d.name_at, false)
}

// declare_name writes a declaration into the scope being read, with the linkage
// its storage class and its scope give it.
fn (mut p Parser) declare_name(name string, typ types.Type, at tokenize.Token, defined bool) {
	previous := p.scopes.lookup(name)
	linkage := types.linkage_for(p.pending_storage, p.scopes.at_file_scope(), previous)
	p.scopes.declare(types.Symbol{
		name:    name
		typ:     typ
		storage: p.pending_storage
		linkage: linkage
		line:    at.line
		col:     at.col
		defined: defined
	})
}

// declare_parameters declares a definition's parameters in the scope around its
// body. They are declared from the parameters the head was read with, because a
// parameter's declarator is read before the body exists: the body is where its
// scope is, so this opens the scope and the body's own block opens the one inside
// it.
fn (mut p Parser) declare_parameters(params []ast.Param) {
	for param in params {
		if param.name.len == 0 {
			continue
		}
		at := tokenize.Token{
			line: param.line
			col:  param.col
		}
		p.declare_name(param.name, param.resolved, at, true)
	}
}

// parse_parameter_list reads a parameter list into the parameters it names and
// the reason it is one a definition cannot use, when there is one. The
// parameters are kept with their types as written, because the frame of a call
// is storage the back end has to name a type for, and a definition's parameter
// is where that is asked. What a name is spelled is the declarator's business:
// `char **argv` is `char **`, whatever the emitter later makes of it.
fn (mut p Parser) parse_parameter_list(depth int) !Params {
	mut params := Params{}
	open := p.next() // (
	if p.at_punct(')') {
		// `()` names no parameters, which is all the tree records: a call is
		// not checked against an empty list, so there is nothing to keep. It is
		// not a prototype either, so it says nothing about the arguments a call
		// may pass.
		p.next()
		return params
	}
	params.prototyped = true
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated parameter list, opened at ${open.line}:${open.col}')
			return error('unterminated parameter list')
		}
		if t.kind == .punct && t.text == '...' {
			// An ellipsis says there are arguments the list does not name.
			// Nothing in the tree records that, so a definition with one is a
			// function whose arguments this back end cannot lay out. For a
			// prototype it is a promise, and promises are not checked here.
			p.next()
			params.variadic = true
			params.note_problem('unsupported: a variadic definition is not implemented', t)
			if !p.expect_punct(')') {
				return error('parameter list')
			}
			return params
		}
		spec := p.parse_decl_specifiers(depth)!
		if p.at_punct(',') || p.at_punct(')') {
			// A parameter with no declarator: `(void)`, `(int)`, `(size_t)`.
			if spec.words.len == 1 && spec.words[0] == 'void' {
				// `void` alone is the empty list, which is not a parameter at
				// all. Anywhere else it is a parameter with no name.
				if p.at_punct(',') {
					params.note_problem('unsupported: void must be the whole parameter list', spec.start)
				}
			} else {
				params.params << ast.Param{
					typ:      spec.type_spelling(0)
					resolved: spec.clause
					line:     spec.start.line
					col:      spec.start.col
				}
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			}
		} else {
			d := p.parse_declarator(depth + 1)!
			params.params << ast.Param{
				name:     d.name
				typ:      spec.type_spelling(d.stars)
				resolved: p.declared_type(spec.clause, d)
				line:     if d.name.len > 0 { d.name_at.line } else { spec.start.line }
				col:      if d.name.len > 0 { d.name_at.col } else { spec.start.col }
			}
			// The order of the questions is the order a reader asks them: what
			// keeps this parameter from being named at all, then the shapes the
			// tree has no form for, then the types the emitter does.
			if d.name.len == 0 {
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			} else if d.array_at.line > 0 {
				params.note_problem('unsupported: array parameters are not implemented', d.array_at)
			} else if !(spec.words.len == 1 && spec.words[0] in supported_types) {
				// The type as the parameter wrote it, so that `double _Complex`
				// and `long long` are named rather than a word of them.
				params.note_problem('unsupported type ${parameter_spelling(spec)}', spec.start)
			}
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct(')') {
			p.next()
			return params
		}
		p.error_at(p.peek(), 'unsupported: expected , or ) in the parameter list, found ${describe(p.peek())}')
		return error('parameter list')
	}
}

fn (mut params Params) note_problem(problem string, at tokenize.Token) {
	if params.problem.len == 0 {
		params.problem = problem
		params.at = at
	}
}

// parse_array_suffix reads `[ ... ]`. The bound is a constant expression, and
// the first one a system header offers is `sizeof (int)`, which this compiler
// cannot read as an expression yet. So the region is scanned to its bracket and
// nothing in it is evaluated; what matters is that the suffix ends where it
// says it ends.
fn (mut p Parser) parse_array_suffix() !i64 {
	open := p.next() // [
	if p.peek().kind == .number {
		// The size of an array as it is written in a body is a number: the
		// preprocessor has already replaced the names that stand for one, so
		// what arrives here is the number itself.
		size := p.next()
		if p.at_punct(']') {
			p.next()
			value := parse_integer_literal(size.text) or {
				p.error_at(size, err.msg())
				return error('bad array size')
			}
			if value > 0 {
				return value
			}
			// A size that is written and cannot be held — `int a[0]` — reads as
			// no size at all, and the reader that asked for one says so.
			return 0
		}
		// The bound goes on after the number, so it is an expression, and an
		// expression is not a size this reader reads: the region is scanned to
		// its bracket and the size is left unread. A body reports that as an
		// array without one, and a declaration in a header is skipped, which is
		// what makes `char _unused2[12 * sizeof (int) - 5 * sizeof (void *)]`
		// read as the member of a struct that it is.
		p.skip_balanced(open)!
		return 0
	}
	// An empty pair of brackets, or a bound that is not a number at all: the
	// region is read past, and the reader that asked for the size decides
	// whether it needed one.
	p.skip_balanced(open)!
	return 0
}

// skip_to_separator consumes the rest of a declaration that is scanned rather
// than parsed: the width of a bitfield, the initializer of an object. It stops
// at the comma or the semicolon that ends the entry, and leaves a closing brace
// for the reader that opened the region.
fn (mut p Parser) skip_to_separator() ! {
	mut depth := 0
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(t, 'unsupported: unexpected end of file inside a declaration')
			return error('unexpected end of file')
		}
		if t.kind == .punct {
			if t.text in ['(', '[', '{'] {
				depth++
			} else if t.text in [')', ']', '}'] {
				if depth == 0 {
					return
				}
				depth--
			} else if depth == 0 && (t.text == ',' || t.text == ';') {
				return
			}
		}
		p.next()
	}
}

// skip_gnu_postfix consumes the GNU words that may follow a declarator: an
// attribute list and an assembler name, each with its parenthesised argument.
// They are read past rather than recorded, because neither changes the shape of
// the declaration as far as this compiler is concerned.
fn (mut p Parser) skip_gnu_postfix() ! {
	for {
		t := p.peek()
		if t.kind != .identifier || t.text !in gnu_postfix {
			return
		}
		p.next()
		if !p.at_punct('(') {
			p.error_at(p.peek(), 'unsupported: expected ( after ${t.text}, found ${describe(p.peek())}')
			return error('postfix attribute')
		}
		open := p.next()
		p.skip_balanced(open)!
	}
}

// skip_balanced consumes tokens up to and including the bracket that closes the
// opener the caller already consumed. Brackets nested inside are counted, so
// the region ends at the bracket that belongs to this opener. It is how the
// reader gets past the regions it does not parse yet: an attribute, an enum
// body, an array bound.
fn (mut p Parser) skip_balanced(open tokenize.Token) ! {
	closer := closing_of(open.text)
	mut depth := 0
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated ${open.text} opened at ${open.line}:${open.col}')
			return error('unterminated ${open.text}')
		}
		if t.kind == .punct {
			if t.text == closer && depth == 0 {
				p.next()
				return
			}
			if depth == 0 && t.text in [')', ']', '}'] {
				p.error_at(t, 'unsupported: expected ${closer}, found ${describe(t)}')
				return error('unexpected bracket')
			}
			if t.text in ['(', '[', '{'] {
				depth++
			} else if t.text in [')', ']', '}'] {
				depth--
			}
		}
		p.next()
	}
}

fn closing_of(open string) string {
	return match open {
		'(' { ')' }
		'[' { ']' }
		'{' { '}' }
		else { ')' }
	}
}

// register_typedef remembers a name as a type for the rest of the file. The
// declaration grammar needs the list: `size_t n` and `puts(x)` are the same
// token shape, and only the names seen so far say which one this is.
//
// A name already declared as a type is left alone: it is there with the type it
// names, and replacing that with the name itself would throw away the only answer
// this file has. A name this reader could only read as a type becomes an opaque
// type carrying it, recorded at file scope, because a spelling says nothing about
// which block it was written in.
fn (mut p Parser) register_typedef(name string) {
	if name.len == 0 {
		return
	}
	if symbol := p.scopes.lookup(name) {
		if symbol.is_typedef() {
			return
		}
	}
	at := p.peek()
	p.scopes.declare_at_file_scope(types.Symbol{
		name:    name
		typ:     types.opaque_type(name)
		storage: types.Storage.typedef_
		line:    at.line
		col:     at.col
	})
}
