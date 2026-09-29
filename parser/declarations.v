module parser

import ast
import tokenize

// This file is the declaration grammar of a preprocessed stream. A real header
// is mostly declarations the back end cannot turn into code: typedefs, tags,
// struct members, and function declarations whose parameters are pointers,
// varargs and GNU attributes. They still have to be read, because the only way
// to find where one declaration ends and the next begins is to parse it.
//
// Reading and keeping are different answers here. A declaration of a type or an
// object adds no code, so it is read and dropped; dropping a typedef costs
// nothing while this compiler has no type to attach a name to. A function
// declaration is kept, with an empty body when it is a prototype, because the
// declaration is what names the function whether or not the file defines it.
// A function definition the back end cannot emit is reported: a definition is
// code, and code quietly left out is the failure this compiler is not allowed.

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
// specifier words, or a name this file has already typedef'd.
fn (p Parser) starts_declaration(t tokenize.Token) bool {
	return t.kind == .identifier && (is_specifier_word(t.text) || t.text in p.typedefs)
}

fn is_specifier_word(text string) bool {
	return text in storage_classes || text in type_qualifiers || text in builtin_types
		|| text in tag_keywords
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
	name        string
	name_at     tokenize.Token
	stars       int
	star_at     tokenize.Token
	array_at    tokenize.Token
	is_function bool
	// params are the parameters this declarator names, in the order they were
	// written. Every function declarator is read for them and the ones that
	// declare a function by name keep them: a pointer to a function is not
	// something a call reaches by name, and this compiler emits no such call.
	params []ast.Param
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
				body := p.parse_block() or { return decls }
				// A definition with no name has been reported and has no
				// identity to record; one whose signature was reported is kept
				// anyway, because the tree is what the file said and the
				// diagnostic is what stops it being compiled.
				if d.name.len > 0 {
					decls << ast.FnDecl{
						name:   d.name
						ret:    spec.type_spelling(d.stars)
						params: d.params
						body:   body
						line:   d.name_at.line
						col:    d.name_at.col
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
					name:   d.name
					ret:    spec.type_spelling(d.stars)
					params: d.params
					body:   []ast.Stmt{}
					line:   d.name_at.line
					col:    d.name_at.col
				}
			}
		} else {
			if !data_seen {
				data_seen = true
				data_name = d.name
				data_at = if d.name.len > 0 { d.name_at } else { spec.start }
			}
			if p.at_punct('=') {
				// An initializer makes it a definition even when the
				// declaration says extern: the object has to live somewhere.
				data_defined = true
				p.next()
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
		p.error_at(data_at, 'unsupported: only function definitions are implemented, so a declaration of ${data_name} has nowhere to go')
	}
	return decls
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
fn unsupported_type_word(spec DeclSpec) ?string {
	if spec.words.len == 0 {
		return none
	}
	if spec.words.len == 1 && spec.words[0] in supported_types {
		return none
	}
	if spec.words.len > 1 && spec.words[0] in supported_types {
		return spec.words[1]
	}
	return spec.words[0]
}

// parse_decl_specifiers reads the words in front of a declarator. It accepts
// what the language allows rather than what this compiler implements, because
// a header declares things this compiler has no opinion about and the
// declaration still has to be measured to its end.
fn (mut p Parser) parse_decl_specifiers(depth int) !DeclSpec {
	mut spec := DeclSpec{}
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
			continue
		}
		if t.text in type_qualifiers {
			p.next()
			spec.note(t)
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
			spec.type_words << tag
			spec.has_type = true
			spec.tag_decl = true
			continue
		}
		if t.text in p.typedefs && !spec.has_type {
			// A name this file has typedef'd. Only one can sit among the
			// specifiers, so once a type has been read the name is the
			// declarator's: `typedef __ssize_t ssize_t;` redeclares ssize_t and
			// does not name two types.
			p.next()
			spec.note_type(t)
			continue
		}
		// An identifier in specifier position that is not a name this file has
		// typedef'd is still a type name. A compiler declares spellings of its
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
	return spec
}

// parse_tag_specifier reads a struct, union or enum specifier and returns the
// type as it was written. The tag lives in its own namespace and is not
// recorded: every later use of it carries its keyword, so `struct _IO_FILE`
// reads the same wherever it appears.
fn (mut p Parser) parse_tag_specifier(keyword tokenize.Token, depth int) !string {
	if depth > max_declaration_depth {
		p.error_at(keyword, 'declaration is nested more than ${max_declaration_depth} levels deep')
		return error('declaration nested too deeply')
	}
	mut text := keyword.text
	if p.peek().kind == .identifier {
		text += ' ' + p.next().text
	}
	if !p.at_punct('{') {
		return text
	}
	open := p.next()
	if keyword.text == 'enum' {
		// An enumerator list is names and constant expressions, and nothing in
		// it is a declaration, so it is scanned as one bracketed region.
		p.skip_balanced(open)!
		return text
	}
	p.parse_member_list(keyword, open, depth)!
	return text
}

// parse_member_list reads the body of a struct or a union. Members are not
// kept: without a type system there is nowhere to put them. The body is read
// to its closing brace, which is what keeps the declaration after it starting
// in the right place.
fn (mut p Parser) parse_member_list(keyword tokenize.Token, open tokenize.Token, depth int) ! {
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
			return
		}
		if t.kind == .punct && t.text == ';' {
			p.next()
			continue
		}
		_ := p.parse_decl_specifiers(depth + 1)!
		// An unnamed bitfield, `int : 3;`, has a width and no declarator.
		if p.at_punct(':') {
			p.next()
			p.skip_to_separator()!
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
			p.parse_declarator(depth + 1)!
			p.skip_gnu_postfix()!
			if p.at_punct(':') {
				p.next()
				p.skip_to_separator()!
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
		// Qualifiers may sit between the star and the name: `char *restrict p`.
		for p.peek().kind == .identifier && p.peek().text in type_qualifiers {
			p.next()
		}
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
			p.parse_array_suffix()!
			continue
		}
		if p.at_punct('(') {
			params := p.parse_parameter_list(depth + 1)!
			if !pointer_to_function {
				d.is_function = true
				d.params = params.params
			}
			if params.problem.len > 0 && d.param_problem.len == 0 {
				d.param_problem = params.problem
				d.param_at = params.at
			}
			continue
		}
		break
	}
	return d
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
		// not checked against an empty list, so there is nothing to keep.
		p.next()
		return params
	}
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
					typ:  spec.type_spelling(0)
					line: spec.start.line
					col:  spec.start.col
				}
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			}
		} else {
			d := p.parse_declarator(depth + 1)!
			params.params << ast.Param{
				name: d.name
				typ:  spec.type_spelling(d.stars)
				line: if d.name.len > 0 { d.name_at.line } else { spec.start.line }
				col:  if d.name.len > 0 { d.name_at.col } else { spec.start.col }
			}
			// The order of the questions is the order a reader asks them: what
			// keeps this parameter from being named at all, then the shapes the
			// tree has no form for, then the types the emitter does.
			if d.name.len == 0 {
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			} else if d.array_at.line > 0 {
				params.note_problem('unsupported: array parameters are not implemented', d.array_at)
			} else if !(spec.words.len == 1 && spec.words[0] in supported_types) {
				params.note_problem('unsupported type ${spec.words[0]}', spec.start)
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
fn (mut p Parser) parse_array_suffix() ! {
	open := p.next() // [
	return p.skip_balanced(open)
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
fn (mut p Parser) register_typedef(name string) {
	if name.len > 0 {
		p.typedefs[name] = true
	}
}
