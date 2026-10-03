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
	'_Bool', '_Complex', '_Imaginary', '__int128']

// bitint_words are the spellings that open a _BitInt specifier. C23 added the
// type, and its width is written in parentheses after the word: `_BitInt(128)`
// is a type of 128 bits. The width belongs to the specifier rather than to the
// declarator, which is what the parentheses are for, so the reader below reads
// the word and the width together and the words of the declaration carry them
// as one. Measured on gcc 16.2.1: the width may be any integer constant
// expression - `_BitInt(64 * 2)` is the same type as `_BitInt(128)` - and a
// width that is not a multiple of the byte, as in `_BitInt(65)`, occupies the
// bytes the next multiple needs.
const bitint_words = ['_BitInt']

// tag_keywords open the specifier that names a struct, a union or an enum.
const tag_keywords = ['struct', 'union', 'enum']

// typeof_words are the spellings that open a typeof specifier. `typeof` is the
// spelling C23 added and a GNU one besides: measured on gcc 16.2.1, `typeof` is
// read in every GNU dialect and in C23, and is not a word at all in a strict
// mode, where `typeof(x) y;` is read as a call to a function named typeof. The
// two spellings with the underscores around them are in the namespace every
// implementation reserves for itself, so gcc 16.2.1 reads them in every mode
// including c89 and draws no pedantic message from any of them.
const typeof_words = ['typeof', '__typeof', '__typeof__']

// typeof_unqual_words are the same specifier with the qualifiers taken off the
// type it names, which is the one difference between the two: `typeof` keeps
// them and `typeof_unqual` does not. C23 spells it `typeof_unqual`, and the
// underscored form is GNU's, the same way it is for typeof.
const typeof_unqual_words = ['typeof_unqual', '__typeof_unqual__']

// keywords are the words the language reserves for itself. A keyword can never
// name a declarator and can never be a use of a name either, and the lexer does
// not tell one from an identifier: that table lives in `tokenize/`, which is
// another lane's file. So a keyword read as an identifier here is a construct
// this reader has not implemented - a cast is where it happens, `(int)d` reads
// its `int` as a name - and it is refused by the diagnostic for that construct
// rather than reported a second time as a missing declaration.
const keywords = ['_Atomic', '_BitInt', '_Bool', '_Complex', '_Imaginary', '_Thread_local', 'auto',
	'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extern',
	'float', 'for', 'goto', 'if', 'inline', 'int', 'long', 'register', 'restrict', 'return', 'short',
	'signed', 'sizeof', 'static', 'struct', 'switch', 'typedef', 'typeof', 'typeof_unqual', 'union',
	'unsigned', 'void', 'volatile', 'while', '__asm', '__asm__', '__attribute__', '__const', '__const__',
	'__extension__', '__inline', '__inline__', '__int128', '__restrict', '__restrict__', '__signed',
	'__signed__', '__thread', '__typeof', '__typeof__', '__typeof_unqual__', '__volatile',
	'__volatile__']

// is_keyword says whether a spelling is one of the reserved words. Nothing in the
// language may use one as an identifier, so the question is asked by the declarator
// reader and by the check that refuses a name nothing declares.
fn is_keyword(text string) bool {
	return text in keywords
}

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

// starts_type_name says whether a token can open a type name written as a cast.
// A cast is a type name and not a declaration, so a storage class never opens
// one: `extern`, `static` and `__extension__` say what kind of declaration
// follows and have no place in a conversion. Reading `(__extension__ ...)` as a
// cast is what made glibc's tgmath.h macros stop at a `sizeof` read as a
// declarator name, so a type name and a declaration share the type words but
// not the storage classes.
fn (p Parser) starts_type_name(t tokenize.Token) bool {
	return t.kind == .identifier && ((is_specifier_word(t.text) && t.text !in storage_classes)
		|| p.is_type_name(t.text))
}

fn is_specifier_word(text string) bool {
	return text in storage_classes || text in type_qualifiers || text in builtin_types
		|| text in tag_keywords || text in typeof_words || text in typeof_unqual_words
		|| text in bitint_words
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

// alias_spelling is the type a name this file declared as a type stands for,
// written the way this compiler writes a type: with `typedef int T;`, a
// declaration of `T x` declares an int, and with `typedef char *String;`, a
// declaration of `String *p` declares a pointer to a char pointer.
//
// Everything after the declaration reads a type as the words the source wrote, so
// an alias is spelled out where the declaration is read rather than carried as a
// name every later stage would have to look up. A name that is not a typedef
// answers none and stands as written.
fn (p Parser) alias_spelling(name string) ?string {
	if symbol := p.scopes.lookup(name) {
		if symbol.is_typedef() && symbol.typ.kind != .unknown {
			return symbol.typ.describe()
		}
	}
	return none
}

// spelling_of is the type a declaration was written with, with a name this file
// declared as a type spelled out as the type it names.
fn (p Parser) spelling_of(spec DeclSpec, stars int) string {
	if spec.type_words.len == 1 {
		if spelling := p.alias_spelling(spec.type_words[0]) {
			return with_stars(spelling, stars)
		}
	}
	return spec.type_spelling(stars)
}

// with_stars is a type written with the pointer stars the declarator put in front
// of the name.
fn with_stars(text string, stars int) string {
	if stars > 0 {
		return text + ' ' + '*'.repeat(stars)
	}
	return text
}

// type_spelling is the type as it was written, with the pointer stars the
// declarator put in front of the name. The stars go down as one run, which is
// how a type is written: `char **argv` is a pointer to a pointer, and `char * *`
// is not what the file says.
fn (s DeclSpec) type_spelling(stars int) string {
	mut text := if s.type_words.len > 0 { s.type_words.join(' ') } else { s.words.join(' ') }
	return with_stars(text, stars)
}

// DeclStepKind is which constructor a declarator step is: a pointer star, an
// array suffix, or a function suffix.
enum DeclStepKind {
	pointer_step
	array_step
	function_step
}

// DeclStep is one constructor a declarator puts around the type its specifiers
// named, kept in the order the type is built from that base outward. The order
// is the type and not a detail of it: `int *p[5]` is a pointer step and then an
// array step, an array of five pointers, and `int (*p)[5]` is the same two
// steps the other way round, one pointer to an array of five. The star sits on
// the other side of the parentheses and that is the whole difference.
struct DeclStep {
	kind  DeclStepKind
	quals types.Qualifiers
	// count is how many elements an array step asked for, and zero when the
	// brackets named no size this reader could read. unreadable_bound is a
	// bound that was written and could not be evaluated, which is not zero.
	count int
	// sized says the brackets wrote something: a number, or an expression
	// this reader read. Empty brackets wrote nothing, and that is the only
	// pair a later reader may take a size for from an initializer.
	sized bool
	// at is where the step was written.
	at tokenize.Token
	// bound_name, with its line and column, is the first name a written bound
	// carried that the scope at that point did not have, when there was one. It is
	// what tells a bound that is not a constant expression from a bound whose
	// operand is a name nothing declares, which the file-scope report needs to
	// name the right failure.
	bound_name      string
	bound_name_line int
	bound_name_col  int
	// params, variadic and prototyped are a function step's parameter list.
	params     []ast.Param
	variadic   bool
	prototyped bool
}

// Declarator is what one declarator says: the name it gives and the
// constructors it puts around the type its specifiers named. An abstract
// declarator has no name, which is what a bare type and a parameter may have.
struct Declarator {
mut:
	name    string
	name_at tokenize.Token
	// steps are the constructors this declarator puts around the base type, in
	// the order the type is built: the first is applied to the type the
	// specifiers named and the last is the type the name has.
	steps []DeclStep
	// param_problem says what makes the parameter list one the back end cannot
	// emit, and stays empty when there is nothing wrong with it. It is recorded
	// rather than reported because whether it matters is only known when a body
	// turns up after it: a prototype promises, and a definition is code.
	param_problem string
	param_at      tokenize.Token
}

// pointer_count is how many pointer steps the declarator wrote.
fn (d Declarator) pointer_count() int {
	mut count := 0
	for step in d.steps {
		if step.kind == .pointer_step {
			count++
		}
	}
	return count
}

// is_function says the declared name has a function type, which is a function
// step as the last one: `int f(void)` is a function, and `int (*f)(void)` is a
// pointer whose last step is the star.
fn (d Declarator) is_function() bool {
	return d.steps.len > 0 && d.steps.last().kind == .function_step
}

// is_array says the declared name has an array type rather than a pointer to
// one: `int *p[5]` is an array and `int (*p)[5]` is a pointer whose last step
// is the star.
fn (d Declarator) is_array() bool {
	return d.steps.len > 0 && d.steps.last().kind == .array_step
}

// array_count is how many elements the array the name has asked for, and zero
// when the name is not an array or its brackets named no size.
fn (d Declarator) array_count() int {
	if !d.is_array() {
		return 0
	}
	count := d.steps.last().count
	return if count > 0 { count } else { 0 }
}

// array_sized says the array's brackets wrote something, which tells a pair of
// empty brackets from a size that was written and could not be read. Only empty
// brackets may take a size from an initializer, so a reader that has an
// initializer asks.
fn (d Declarator) array_sized() bool {
	if !d.is_array() {
		return false
	}
	return d.steps.last().sized
}

// array_at is where the array the name has was written, and the zero token when
// the name is not an array.
fn (d Declarator) array_at() tokenize.Token {
	if !d.is_array() {
		return tokenize.Token{}
	}
	return d.steps.last().at
}

// array_bound_is_unreadable says a bound the declarator wrote in its brackets is
// not an integer constant expression this reader evaluated. It is the question a
// reader asks where storage has to be sized while the file is read, which is the
// top level: a file-scope object's size is a fact the image carries, and a bound
// that is not constant is a constraint violation there (6.6). A struct member and
// a parameter ask it of no one here, because this reader does not size their
// storage: the same suffix is read for all three.
fn (d Declarator) array_bound_is_unreadable() bool {
	for step in d.steps {
		if step.kind == .array_step && step.count == unreadable_bound {
			return true
		}
	}
	return false
}

// array_bound_ident is the name a written bound carried that the scope at that
// point did not have, when there was one. It is what distinguishes a bound that is
// not an integer constant expression from a bound whose operand is declared
// nowhere: the first is the object's problem, the second is the name's, and the
// report says which.
fn (d Declarator) array_bound_ident() ?ast.Ident {
	for step in d.steps {
		if step.kind == .array_step && step.count == unreadable_bound && step.bound_name.len > 0 {
			return ast.Ident{
				name: step.bound_name
				line: step.bound_name_line
				col:  step.bound_name_col
			}
		}
	}
	return none
}

// array_dims counts the array steps, which is how many sizes the declarator
// wrote for one name.
fn (d Declarator) array_dims() int {
	mut count := 0
	for step in d.steps {
		if step.kind == .array_step {
			count++
		}
	}
	return count
}

// star_at is where the first pointer step was written, and the zero token when
// the declarator wrote no star.
fn (d Declarator) star_at() tokenize.Token {
	for step in d.steps {
		if step.kind == .pointer_step {
			return step.at
		}
	}
	return tokenize.Token{}
}

// function_params, function_variadic and function_prototyped are what the
// declarator's function step said about its list.
fn (d Declarator) function_params() []ast.Param {
	for step in d.steps {
		if step.kind == .function_step {
			return step.params
		}
	}
	return []ast.Param{}
}

fn (d Declarator) function_variadic() bool {
	for step in d.steps {
		if step.kind == .function_step {
			return step.variadic
		}
	}
	return false
}

fn (d Declarator) function_prototyped() bool {
	for step in d.steps {
		if step.kind == .function_step {
			return step.prototyped
		}
	}
	return false
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

// skip_uncalled_static skips the definition of a `static` function that nothing
// else in the file names, and says whether it did.
//
// A header carries helpers a program may never call, and what they are written in
// is not what this reader has: the byte-swap and endianness helpers in
// <bits/byteswap.h> and <bits/uintn-identity.h> take and return __uint16_t,
// __uint32_t and __uint64_t, whose specifiers are unsigned types, and their
// bodies shift and mask. Reading a definition nothing calls refuses the program
// over a construct it never reaches, so such a definition is stepped over by
// tokens - braces counted, nothing recorded - before its specifiers are read,
// which is the only place the refusal can be avoided: `__uint16_t __bsx` is
// refused at the parameter.
//
// What says a definition is one: the first `{` before the declaration's `;` is a
// body, so a `(` comes before it at the top level, and the identifier in front of
// that `(` is the name. The name then has to appear nowhere outside the
// definition, which is the question a call would answer: a function that calls
// itself is still named by nothing else, and one a later declaration or call names
// is read as it always was.
fn (mut p Parser) skip_uncalled_static() bool {
	if !p.starts_a_static_declaration() {
		return false
	}
	start := p.pos
	mut open := -1
	mut brace := -1
	mut depth := 0
	mut i := start
	for i < p.tokens.len {
		t := p.tokens[i]
		if t.kind == .eof {
			return false
		}
		if t.kind == .punct {
			match t.text {
				'(' {
					if depth == 0 && open < 0 {
						open = i
					}
					depth++
				}
				')' {
					if depth > 0 {
						depth--
					}
				}
				'{' {
					if depth == 0 {
						brace = i
						break
					}
					depth++
				}
				'}' {
					if depth > 0 {
						depth--
					}
				}
				';' {
					// A declaration of an object, or a prototype: nothing to
					// skip, and the words in front of it are read as they are.
					if depth == 0 {
						return false
					}
				}
				else {}
			}
		}
		i++
	}
	if brace < 0 || open < 0 || open > brace {
		return false
	}
	if open == 0 || p.tokens[open - 1].kind != .identifier {
		return false
	}
	name := p.tokens[open - 1].text
	end := p.end_of_block(brace)
	if end < 0 {
		return false
	}
	for j, t in p.tokens {
		if j >= start && j <= end {
			continue
		}
		if t.kind == .identifier && t.text == name {
			return false
		}
	}
	p.pos = end + 1
	return true
}

// starts_a_static_declaration says whether the declaration at the reader's
// position begins with the words in front of the type and one of them is
// `static`. The helper definitions a header writes put `__extension__` or
// `__inline` in front of it, and any of them may come first.
fn (p Parser) starts_a_static_declaration() bool {
	mut is_static := false
	mut i := p.pos
	for i < p.tokens.len {
		t := p.tokens[i]
		if t.kind != .identifier {
			return false
		}
		if t.text == 'static' {
			is_static = true
			i++
			continue
		}
		if t.text in ['__extension__', 'inline', '__inline', '__inline__'] {
			i++
			continue
		}
		return is_static
	}
	return false
}

// end_of_block is the index of the `}` that closes the brace at `open`, or -1
// when the tokens run out first.
fn (p Parser) end_of_block(open int) int {
	mut depth := 0
	mut i := open
	for i < p.tokens.len {
		t := p.tokens[i]
		if t.kind == .punct {
			if t.text == '{' {
				depth++
			}
			if t.text == '}' {
				depth--
				if depth == 0 {
					return i
				}
			}
		}
		i++
	}
	return -1
}

// parse_declaration reads one declaration and returns the functions it
// declares or defines. A typedef, a tag and an object are read and dropped,
// since none of them adds code. A declaration that cannot be read is skipped
// to its end here, so the caller never sees a half-read declaration and the
// next one starts in the right place.
fn (mut p Parser) parse_declaration() []ast.FnDecl {
	mut decls := []ast.FnDecl{}
	if p.skip_uncalled_static() {
		return decls
	}
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
	// data_complete is the type of an array whose size its initializer gave it,
	// which the declarator could not: the brackets wrote none, and the string
	// literal after them is what says how many. It is set once the initializer
	// has been read, and the name is completed with it after it is declared.
	mut data_complete := ?types.Type(none)
	mut data_init := ?i64(none)
	// data_init_float is the same initializer when it was written as a floating
	// constant. The two are kept apart while the declaration is read because the
	// object's type is not known until the declarator has been read, and which
	// one is written into the image is a question about that type.
	mut data_init_float := ?f64(none)
	// data_init_long is the same initializer when it was written as a long
	// double constant, which a host double cannot hold: the object's type and the
	// constant's type are both needed before the bytes can be written.
	mut data_init_long := ?types.LongDouble(none)
	// data_inits and data_init_floats are the brace initializer of an array, the
	// same split as the scalar pair: which list is filled is a question about the
	// element type, which is not known until the declarator has been read.
	mut data_inits := []i64{}
	mut data_init_floats := []f64{}
	// data_array says the declarator wrote brackets, which is what makes the
	// list an array's elements rather than one scalar in braces, and data_brace
	// says the initializer was written as a list. The two are kept because the
	// size of an array with empty brackets comes from the list.
	mut data_array := false
	mut data_brace := false
	// data_union_first says the brace initializer is a union's, which
	// initializes the union's first member rather than writing the whole object:
	// the constant is written at the beginning of the storage, and the rest
	// stays the zeros the object starts as.
	mut data_union_first := false
	// data_struct_brace says the brace initializer is a struct's, and
	// data_member_inits is the constant for each member the list wrote, at the
	// offset and width the layout gave that member. The members the list did
	// not reach are the zeros the storage starts as.
	mut data_struct_brace := false
	mut data_member_inits := []ast.MemberInit{}
	// data_resolved is the type a nested or designated list was walked against,
	// which is the object's own type with the array sizes applied: `spec.clause`
	// is the base the declarator was written from, and the walk needs the array
	// a write's offset is inside.
	mut data_resolved := ?types.Type(none)
	// data_bytes is the number of bytes one element of the object takes when a
	// nested or designated list was walked against its type, and zero when the
	// object's width is the one its spelling answers. An array whose elements
	// are aggregates has no width a spelling answers, so the walk is what says
	// how far an index reaches.
	mut data_bytes := 0
	// data_string says the initializer was a string literal that was read, which
	// is a declaration with storage even when the array it initializes holds no
	// element: `char s[0] = "";` writes none, and the report for an initializer
	// that is not a number is not about it.
	mut data_string := false
	// data_address is the initializer of an object whose value is an address
	// rather than a number, which is what a pointer at the top level has: a
	// function designator, the address of an object, or a string literal.
	mut data_address := ?ast.AddressInit(none)
	// data_address_inits is a brace list of addresses, one per element of an
	// array whose elements are pointers: `int (*t[2])(int) = {inc, dec};`. It is
	// separate from data_inits because an element that is an address is a
	// reference the layout resolves rather than a constant written here.
	mut data_address_inits := []ast.AddressInit{}
	// data_problem says a brace initializer was read and refused for its size,
	// which is a declaration the image does not lay out: the program is already
	// refused, and storage for an object whose initializer is wrong is storage
	// nothing should read.
	mut data_problem := false
	// literal_refused says the initializer was a shape the reader reported, which
	// is a different answer from an initializer that is not a number at all: the
	// first has its own diagnostic at its own location, and the second is what
	// the report below is for.
	mut literal_refused := false
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
		if d.is_function() {
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
				p.declare_parameters(d.function_params())
				// The function-name spellings inside the body name this
				// function, so its name is carried while the body is read and
				// the one before it is given back after.
				previous_function := p.current_function
				p.current_function = d.name
				body := p.parse_block()
				p.current_function = previous_function
				p.scopes.leave()
				statements := body or { return decls }
				// A definition with no name has been reported and has no
				// identity to record; one whose signature was reported is kept
				// anyway, because the tree is what the file said and the
				// diagnostic is what stops it being compiled.
				if d.name.len > 0 {
					decls << ast.FnDecl{
						name:     d.name
						ret:      p.spelling_of(spec, d.pointer_count())
						ret_type: p.return_type(spec.clause, d)
						resolved: p.declared_type(spec.clause, d)
						params:   d.function_params()
						defined:  true
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
					ret:      p.spelling_of(spec, d.pointer_count())
					ret_type: p.return_type(spec.clause, d)
					resolved: p.declared_type(spec.clause, d)
					params:   d.function_params()
					body:     []ast.Stmt{}
					line:     d.name_at.line
					col:      d.name_at.col
				}
			}
		} else {
			// An object at the top level is storage the image lays out, so its
			// size has to be a fact by the time this file is read. A bound that
			// is not an integer constant expression leaves the object without
			// one, which 6.6 makes a constraint violation. Measured on gcc 16.2.1
			// under `-std=c99`, `int a[1/0];` and `int n = 3;\nint a[n];` are both
			// `variably modified 'a' at file scope` and exit 1. The check is here
			// and not in the suffix reader because the same suffix is read for a
			// struct member, whose bound may be one this compiler cannot fold.
			if !spec.is_typedef && d.is_array() && d.array_bound_is_unreadable() {
				if ident := d.array_bound_ident() {
					// The bound named something the scope did not have. Whether
					// the file declares that name anywhere is a question only the
					// end of the file answers, so the report waits: `int x[n];
					// int n = 4;` names a variable declared later and its bound is
					// not a constant expression, while `enum { N = 4 }; int x[N];`
					// names nothing at all, and calling the second non-constant
					// would name a cause the compiler cannot show.
					p.pending_bounds << PendingBound{
						object:    d.name
						name:      ident.name
						name_line: ident.line
						name_col:  ident.col
						at_line:   d.array_at().line
						at_col:    d.array_at().col
					}
				} else {
					p.error_at(d.array_at(), 'a constraint violation: the bound of ${d.name} is not an integer constant expression, and an object at file scope needs a size that is one')
				}
				p.skip_declaration()
				return decls
			}
			if !data_seen {
				data_seen = true
				data_name = d.name
				data_at = if d.name.len > 0 { d.name_at } else { spec.start }
				data_type = p.spelling_of(spec, d.pointer_count())
				data_stars = d.pointer_count()
				data_count = d.array_count()
				data_array = d.is_array()
				data_clause = p.declared_type(spec.clause, d)
			}
			if p.at_punct('=') {
				// An initializer makes it a definition even when the
				// declaration says extern: the object has to live somewhere.
				data_defined = true
				p.next()
				before := p.diagnostics.len
				if p.at_punct('{') && d.pointer_count() == 0 {
					// A brace initializer, read here because a list is
					// what gives an array with empty brackets its size.
					// A pointer's list is read by the arm below, which
					// knows the elements are addresses.
					data_brace = true
					if list := p.parse_brace_initializer(false) {
						if !list.is_a_flat_list() {
							// A nested list or a designator: the list is
							// walked against the object's type and each write
							// lands at the byte its subobject starts at.
							if general := p.file_scope_general_initializer(spec, d, list, data_name) {
								data_member_inits = general.members
								data_bytes = general.bytes
								data_count = general.count
								data_resolved = general.resolved
								data_struct_brace = true
							} else {
								data_problem = true
							}
						} else if !data_array {
							// A union takes one value for its first member
							// and a struct one value per member; a scalar
							// takes the one value in the braces.
							if spec.clause.kind == .union_ {
								// 6.7.8: a union's initializer initializes its
								// first member, which sits at the beginning of
								// the object. A first member that is itself an
								// aggregate takes a list of its own, and a list of
								// more than one value has no room in one object.
								if list.elements.len > 1 {
									p.error_at(list.at, 'a constraint violation: ${data_name} holds one value and its initializer writes ${list.elements.len}')
									data_problem = true
								} else if spec.clause.members.len == 0 {
									p.error_at(list.at, 'unsupported: ${spec.clause.describe()} has no first member to initialize')
									data_problem = true
								} else {
									first := spec.clause.members[0]
									if first.typ.kind in [types.Kind.struct_, .union_, .array] {
										p.error_at(list.at, 'unsupported: the first member of ${spec.clause.describe()} is an object of the type ${first.typ.describe()}, and a brace initializer for one is not implemented')
										data_problem = true
									} else {
										element := list.elements[0]
										if address := element.address {
											if first.typ.kind != .pointer {
												// The first member does not hold an
												// address, and an address is not
												// converted to another scalar: gcc
												// 16.2.1 warns and the program reads
												// a different value, so the shape is
												// refused rather than written.
												p.error_at(list.at, 'unsupported: the first member of ${spec.clause.describe()} is of the type ${first.typ.describe()}, and its initializer writes an address')
												data_problem = true
											} else {
												// A union's first member sits at the
												// beginning of the object, so an
												// address initializing a pointer
												// member is written at the union's
												// own offset.
												data_address = address
												data_union_first = true
											}
										} else if number := element.number {
											data_init, data_init_float = initializer_for(first.typ.describe(), number.number.integer,
												number.number.floating)
											data_init_long = number.number.long_floating
											data_union_first = true
										}
									}
								}
							} else if spec.clause.kind == .struct_ {
								// A struct's brace initializer gives each
								// value to a member in the order the members
								// were written. A member that is itself an
								// aggregate or a bitfield is refused by name
								// in the helper, and the declaration is not
								// laid out: there is nothing to write.
								if layout := p.struct_brace_members(spec.clause, list, data_name) {
									data_member_inits = p.struct_member_inits(spec.clause, list, layout)
									data_struct_brace = true
								} else {
									data_problem = true
								}
							} else {
								// One scalar in braces; a list of more
								// values has no room in one object
								// (6.7.8p2, measured on gcc 16.2.1:
								// `int x = {1, 2};` is `excess elements
								// in scalar initializer`).
								if list.elements.len > 1 {
									p.error_at(list.at, 'a constraint violation: ${data_name} holds one value and its initializer writes ${list.elements.len}')
									data_problem = true
								}
								element := list.elements[0]
								if element.address != none {
									// The object's type is not a pointer: a
									// pointer's braces are read as a table
									// before this arm, and an address has no
									// conversion to another scalar.
									p.error_at(list.at, 'unsupported: ${data_name} is not of pointer type, and its initializer writes an address')
									data_problem = true
								} else if number := element.number {
									data_init, data_init_float = initializer_for(data_type, number.number.integer,
										number.number.floating)
									data_init_long = number.number.long_floating
								}
							}
						} else {
							// A written size smaller than the list is
							// the same violation (measured,
							// `int a[2] = {1, 2, 3};` is `excess
							// elements in array initializer`), and a
							// list for an array with empty brackets
							// is what its size is.
							if data_count > 0 && list.elements.len > data_count {
								p.error_at(list.at, 'a constraint violation: ${data_name} holds ${data_count} elements and its initializer writes ${list.elements.len}')
								data_problem = true
							}
							if data_count == 0 {
								data_count = list.elements.len
							}
							data_inits, data_init_floats = p.initializer_list_for(data_type, list.elements,
								data_name, list.at)
						}
					}
					literal_refused = true
				} else if d.pointer_count() > 0 {
					// An object of pointer type takes an address: a
					// function designator, the address of an object, or a
					// string literal. A written number is a null pointer
					// constant, which is the one value of an integer type
					// a pointer takes, and it is written as the number it
					// is. A brace list is a table of them, one per element,
					// and it is read on its own path because an element
					// that is an address is a reference the layout resolves
					// rather than bytes written here.
					if p.at_punct('{') {
						if elements := p.parse_address_initializer() {
							data_address_inits = elements.clone()
							if data_count == 0 {
								// Empty brackets are what the list sizes, the
								// same as a list of numbers sizes an array.
								data_count = elements.len
							} else if elements.len > data_count {
								p.error_at(data_at, 'a constraint violation: ${data_name} holds ${data_count} elements and its initializer writes ${elements.len}')
								data_problem = true
							}
						} else {
							// The list was refused at its own element; there is
							// nothing to lay out.
							data_problem = true
							literal_refused = true
						}
					} else if p.looks_like_compound_literal() {
						// An unnamed object with static storage duration, defined
						// in the image like any other top-level object, whose
						// address initializes this pointer.
						if address := p.file_scope_compound_literal() {
							data_address = address
						} else {
							data_problem = true
							literal_refused = true
						}
					} else if address := p.file_scope_address() {
						data_address = address
					} else {
						// What is left is a constant: a written number is a null
						// pointer constant, which is the one value of an integer
						// type a pointer takes. A shape the constant reader does
						// not read is reported at the literal itself.
						constant := p.file_scope_constant()
						data_init = constant.integer
						data_init_float = constant.floating
						data_init_long = constant.long_floating
						literal_refused = p.diagnostics.len > before
					}
				} else if p.peek().kind == .string && d.is_array() {
					// 6.7.8p14: an array of character type may be
					// initialized by a string literal. The elements become
					// the same constants a brace list writes, so the image
					// lays them out along the path a brace-initialized
					// array already takes. A literal whose element type is
					// not the array's is not this initializer, and the
					// report below names the declaration.
					if literal := p.read_array_string_literal() {
						declared := p.declared_type(spec.clause, d)
						if array_takes_string(d, declared, literal) {
							written := p.file_scope_string_initializer(d, declared, data_name,
								literal)
							if written.ok {
								data_inits = written.inits
								data_count = written.count
								data_complete = written.complete
								data_string = true
							} else {
								// The literal was too long for the size that
								// was written; it has been named at its own
								// location and nothing is laid out.
								data_problem = true
								literal_refused = true
							}
						}
					} else {
						literal_refused = true
					}
				} else {
					constant := p.file_scope_constant()
					data_init = constant.integer
					data_init_float = constant.floating
					data_init_long = constant.long_floating
					literal_refused = p.diagnostics.len > before
				}
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
		// A pointer object at the top level is one word of storage, and what it
		// points at does not decide how wide it is: 6.2.5 lets a pointer name an
		// incomplete type, and the back end sizes a pointer from its star rather
		// than from the type under it. It takes the value path below rather than
		// the aggregate one, whatever the type under the star is.
		//
		// The type of an object defined at the top level is the same question a
		// definition's return type is: storage the program has to find room for,
		// so the answer is the same helper. A prototype can promise anything; a
		// definition cannot promise a type this back end has no width for.
		if offender := p.unsupported_type_word(spec, data_stars) {
			p.error_at(data_at, 'unsupported type ${offender}')
			return decls
		}
		if data_stars == 0 && (spec.clause.kind in [types.Kind.struct_, .union_] || data_bytes > 0) {
			if data_problem {
				// The list was refused for its size and has already been
				// named: there is nothing to lay out.
				return decls
			}
			if data_brace && !data_union_first && !data_struct_brace {
				// A brace initializer for an object of an aggregate type that
				// the reader refused: a union's one value initializes its
				// first member and a struct's values initialize its members,
				// both written into the image below. Measured before the
				// members were written, a file-scope `struct S s = {5, 6};`
				// laid the object out as zeros and the program read 0 where
				// gcc 16.2.1 reads 56.
				p.error_at(data_at, 'unsupported: ${data_name} is an object of the type ${spec.clause.describe()}, and a brace initializer for one is not implemented')
				return decls
			}
			// An object of an aggregate type at the top level is storage in the
			// image, and how much of it is a fact about the layout: the model
			// answers the size once, here, and the image writer reserves that
			// many zeroed bytes. A union's first member is the one thing a
			// definition writes into that storage; with no initializer it is
			// the zeros the storage starts as.
			//
			// A list with a nested brace or a designator decided that size
			// itself, because the type it was walked against may be an array
			// whose element is an aggregate and has no width a spelling
			// answers. `data_bytes` is that answer and is zero for a plain
			// struct, which asks the layout the way it always did.
			bytes := if data_bytes > 0 { data_bytes } else { p.aggregate_bytes(spec.clause) }
			if bytes == 0 {
				p.error_at(data_at, 'unsupported: ${data_name} is defined with the type ${spec.clause.describe()}, and its layout is not one this compiler knows')
				return decls
			}
			// An array of aggregates is that many bytes per element and as many
			// elements as the declarator wrote: the size travels here and the count
			// travels beside it, which is what the image reserves and what an index
			// scales by. A union's one value is the constant its first member
			// holds, written at the beginning of the storage.
			p.declare_name(data_name, data_clause, data_at, true)
			p.globals << ast.Global{
				name:         data_name
				typ:          data_type
				resolved:     data_resolved or { spec.clause }
				count:        data_count
				bytes:        bytes
				init:         data_init
				init_float:   data_init_float
				address:      data_address
				member_inits: data_member_inits
				line:         data_at.line
				col:          data_at.col
			}
			return decls
		}
		if data_defined && data_init == none && data_init_float == none && data_inits.len == 0
			&& data_init_floats.len == 0 && data_init_long == none && !data_string && data_address == none
			&& data_address_inits.len == 0 {
			// Either way the definition is refused. When the initializer was a
			// shape the reader reported, it has already been named at its own
			// location and this report would be a second message about the
			// same construct.
			if !literal_refused {
				p.error_at(data_at, 'unsupported: ${data_name} is initialized with something this compiler cannot write into the image, and it is not a shape it reads')
			}
			return decls
		}
		if data_problem {
			// The list was refused for its size and has already been named:
			// there is nothing to lay out, and the program does not compile.
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
		//
		// The initializer is made the class the object was declared with while
		// the tree is built, because the two are one value of one type: an
		// integer initializing a double object is that integer's value as a
		// double, and a floating constant initializing an int or a char is
		// truncated towards zero, which is the conversion an assignment makes
		// and the reason neither of these needs a diagnostic of its own.
		init, init_float := initializer_for(data_type, data_init, data_init_float)
		if data_init_long != none && data_type != 'long double' {
			p.error_at(data_at, 'unsupported: ${data_name} is defined with the type ${data_type}, and its initializer is a long double constant')
			return decls
		}
		mut starts_at_zero := true
		if value := data_init {
			if value != 0 {
				starts_at_zero = false
			}
		}
		if value := data_init_float {
			if value != 0.0 {
				starts_at_zero = false
			}
		}
		if data_type == 'long double' && data_init_long == none && !starts_at_zero {
			// An object of the extended type at the top level starts at the
			// constant its initializer names when that constant is one of the
			// type, and at zero when there is nothing to start it at, which is
			// what the unsized storage in the image already holds. A constant of
			// another type is a conversion at load time, which this reader does
			// not write into the image.
			p.error_at(data_at, 'unsupported: ${data_name} is a long double, and its initializer is not a long double constant: converting a constant of another type to the extended format at load time is not written into the image')
			return decls
		}
		p.declare_name(data_name, data_clause, data_at, true)
		if completed := data_complete {
			// The name was declared with the size-less array its declarator
			// wrote, and the string literal that followed is what gives it a
			// size: the symbol is completed here so a later `sizeof` answers
			// with the size the initializer fixed rather than with the brackets
			// that wrote none.
			p.scopes.complete_type(data_name, completed)
		}
		p.globals << ast.Global{
			name:          data_name
			typ:           data_type
			resolved:      if completed := data_complete { completed } else { data_clause }
			count:         data_count
			init:          init
			init_float:    init_float
			init_long:     data_init_long
			address:       data_address
			inits:         data_inits
			init_floats:   data_init_floats
			address_inits: data_address_inits
			line:          data_at.line
			col:           data_at.col
		}
	}
	return decls
}

// FileConstant is the number a file-scope definition was initialized with. One of
// the two fields is set: `integer` for an integer constant, `floating` for a
// floating one, and neither for a shape this reader does not take. Keeping them
// apart here is what lets the caller check the class against the object's type
// rather than converting one into the other and losing what was written.
struct FileConstant {
	integer       ?i64
	floating      ?f64
	long_floating ?types.LongDouble
}

// NumberConstant is a written number with the sign that may stand in front of it,
// and the token the number itself was written at. The token is kept because the
// type of a constant is decided from its spelling - `1` and `1L` are not the
// same type - and a list of them is read into nodes that need one.
struct NumberConstant {
	number FileConstant
	at     tokenize.Token
}

// number_constant reads a written number with the sign in front of it. It is the
// shape a constant initializer has wherever the compiler can write one: a scalar
// or a list element. It answers none when what is written is not a number at all,
// and reports a literal it cannot read at the literal itself, which is the same
// refusal the expression path gives the same spelling.
fn (mut p Parser) number_constant() ?NumberConstant {
	sign := if p.at_punct('-') {
		p.next()
		-1
	} else if p.at_punct('+') {
		p.next()
		1
	} else {
		1
	}
	// A character constant is a written constant too, and 6.4.4.4 gives it the
	// value of the character it names and the type int. `{ 'A' }` is the same
	// element `{ 65 }` is, and the corpus reaches one, so the reader takes both.
	if p.peek().kind == .character {
		t := p.next()
		value := parse_character_literal(t.text) or {
			p.error_at(t, err.msg())
			return none
		}
		return NumberConstant{
			number: FileConstant{
				integer: sign * value
			}
			at:     t
		}
	}
	if p.peek().kind != .number {
		return none
	}
	t := p.next()
	if is_floating_constant(t.text) {
		if is_long_double_constant(t.text) {
			value := parse_long_double_literal(t.text) or {
				p.error_at(t, err.msg())
				return none
			}
			return NumberConstant{
				number: FileConstant{
					long_floating: value
				}
				at:     t
			}
		}
		value := parse_floating_literal(t.text) or {
			p.error_at(t, err.msg())
			return none
		}
		return NumberConstant{
			number: FileConstant{
				floating: if sign < 0 { -value } else { value }
			}
			at:     t
		}
	}
	value := parse_integer_literal(t.text) or {
		p.error_at(t, err.msg())
		return none
	}
	return NumberConstant{
		number: FileConstant{
			integer: sign * value
		}
		at:     t
	}
}

// file_scope_constant reads the initializer a file-scope definition may have: an
// integer constant expression, or a written number with a sign. The expression is
// read first, because the folder takes the operators 6.6 gives a constant
// expression and the reader that names a number takes only the shapes the folder
// does not: a floating constant, and a literal it refuses.
//
// Anything else - a string, a name, a call - reads as none, and the caller
// reports it: what is written into the image is a constant, and a constant is
// what can be written. A brace list is read by `parse_brace_initializer` before
// this is reached, so it never arrives here.
//
// A number the literal reader refuses is reported by `number_constant`, at the
// literal as it was written, which is where the expression path reports the same
// refusal. The caller is told that it happened so that it does not follow it with
// the report for an initializer that is not a number at all: measured,
// `int x = 0x1p3;` used to exit with `x is initialized with something that is not
// a number` instead of naming the construct.
fn (mut p Parser) file_scope_constant() FileConstant {
	// A parenthesized constant, `(7)`, is the number the one pair of parentheses
	// holds, which is the shape a macro that wraps its argument in them writes:
	// the corpus reaches `int c99_slot_7 = (7);` through `C99_DECLARE(7)`.
	if p.is_parenthesized_constant() {
		p.next()
		constant := p.number_constant() or { return FileConstant{} }
		p.next()
		return constant.number
	}
	// An integer constant expression is the other shape an integer initializer
	// has, and the folder reads one here rather than the reader that names a
	// number: measured on gcc 16.2.1 under `-std=c99`, `int y = 12 * sizeof(int)
	// - 5 * sizeof(void *);` is 8 and `int y = 2 + 3;` is 5, and this reader
	// refused both while the same expression in a body was folded.
	if constant := p.folded_file_initializer() {
		return constant
	}
	// The number is the initializer or the initializer is not one this reads. An
	// expression this folder does not evaluate and reading its first term and
	// stopping was silent: `int g = 2 + 3;` defined g as 2, `int g = 1 << 3;` as
	// 1, `char g = 2 + 3;` as 2, `double g = 1.5 + 1.5;` as 1, and
	// `__int128 g = 0 - 100;` as 0, each with no diagnostic and an image written.
	// Answering none here is what the comment above promises: the caller reports
	// what it cannot write, so an expression refuses by name at the definition.
	constant := p.number_constant() or { return FileConstant{} }
	if !p.at_punct(',') && !p.at_punct(';') {
		return FileConstant{}
	}
	return constant.number
}

// file_scope_address reads the initializer of an object whose value is an address
// rather than a number: a function designator, the address of an object, or a
// string literal. It answers none for anything else without consuming a token, so
// a caller that finds no address can read the same place as a number instead, and
// a null pointer constant is still a number.
//
// The name is kept rather than resolved. This reader knows the scope, and whether
// a name is a function or an object is a question about the whole file's
// definitions, which the back end asks where it lays the storage out.
fn (mut p Parser) file_scope_address() ?ast.AddressInit {
	if p.peek().kind == .string {
		token := p.next()
		literal := parse_string_literal(token.text) or {
			p.error_at(token, err.msg())
			return none
		}
		if literal.unit == 4 {
			// A wide literal is a run of ints, and a pointer at the top level
			// takes the literal of its own element's type: this reader has no
			// wchar_t to compare the pointee against here, so it names the
			// shape rather than writing the wrong address.
			p.error_at(token, 'unsupported: a wide string literal does not initialize a pointer here')
			return none
		}
		return ast.AddressInit{
			name:   literal.value
			string: true
			line:   token.line
			col:    token.col
		}
	}
	if p.at_punct('&') {
		amp := p.next()
		if p.peek().kind != .identifier {
			p.error_at(amp, 'unsupported: the operand of & in a file-scope initializer has to be a name')
			return none
		}
		name := p.next()
		if p.at_punct('[') || p.at_punct('.') || p.at_punct('->') {
			// `&name[0]`, `&name.m` and `&name->m` are the address of a part of
			// an object, which is the object's address plus an offset: the
			// reference carries no offset yet, so the shape is refused by name
			// rather than written as the address of the whole object, which is
			// not what it names.
			p.error_at(name, 'unsupported: the address of a part of ${name.text} is not implemented, and the address of the whole object is not what it names')
			return none
		}
		return ast.AddressInit{
			name:     name.text
			explicit: true
			line:     name.line
			col:      name.col
		}
	}
	if p.peek().kind == .identifier {
		name := p.next()
		if p.at_punct('[') || p.at_punct('.') || p.at_punct('->') {
			p.error_at(name, 'unsupported: ${name.text} is named where an address is wanted and a part of it is read, and an address of a part of an object is not implemented')
			return none
		}
		return ast.AddressInit{
			name: name.text
			line: name.line
			col:  name.col
		}
	}
	return none
}

// folded_file_initializer reads the initializer as an expression and answers the
// integer constant expression it is worth. Its operand and operator set is the
// folder's, which is 6.6's, so the same expressions are constants here as in a
// bound: measured on gcc 16.2.1 under `-std=c99`, `int y = 12 * sizeof(int) - 5 *
// sizeof(void *);` is 8, `int y = 2 + 3;` is 5 and `int y = 1 << 3;` is 8, and
// this reader refused all three while a body's copy of the first was folded by
// the same folder.
//
// Nothing is kept of a read that does not fold: the cursor, the diagnostics, the
// depth and the specifier state go back, and the reader that names a number
// answers for the shapes this one does not take - a floating constant, a bad
// literal, a name and a call among them.
fn (mut p Parser) folded_file_initializer() ?FileConstant {
	saved_pos := p.pos
	saved_diagnostics := p.diagnostics.len
	saved_depth := p.depth
	saved_base := p.pending_base
	saved_storage := p.pending_storage
	expr := p.parse_expression() or {
		p.pos = saved_pos
		p.diagnostics = p.diagnostics[..saved_diagnostics]
		p.depth = saved_depth
		p.pending_base = saved_base
		p.pending_storage = saved_storage
		return none
	}
	p.depth = saved_depth
	p.pending_base = saved_base
	p.pending_storage = saved_storage
	if !p.at_punct(',') && !p.at_punct(';') {
		p.pos = saved_pos
		p.diagnostics = p.diagnostics[..saved_diagnostics]
		return none
	}
	value := p.constant_value(expr) or {
		p.pos = saved_pos
		p.diagnostics = p.diagnostics[..saved_diagnostics]
		return none
	}
	return FileConstant{
		integer: value
	}
}

// is_parenthesized_constant answers whether the next tokens are one pair of
// parentheses around one number, signed or not, with nothing but the end of the
// declaration after the pair. It reads no token, so a false answer leaves the
// parser where it was and the initializer is refused by the path that already
// names what it cannot write.
fn (p Parser) is_parenthesized_constant() bool {
	if !p.at_punct('(') {
		return false
	}
	mut index := 1
	sign := p.peek_at(index)
	if sign.kind == .punct && (sign.text == '-' || sign.text == '+') {
		index++
	}
	if p.peek_at(index).kind != .number {
		return false
	}
	index++
	close := p.peek_at(index)
	if close.kind != .punct || close.text != ')' {
		return false
	}
	index++
	after := p.peek_at(index)
	return after.kind == .punct && (after.text == ',' || after.text == ';')
}

// BraceDesignator is one designator in front of an element of a brace
// initializer: `.name` picks a member of a struct, `[n]` an element of an array,
// and a run of them descends through subobjects, `.chain[1]` picking member
// `chain` and then element 1 of it. Exactly one of `member` and `index` is set.
struct BraceDesignator {
	member ?string
	index  ?int
	at     tokenize.Token
}

// BraceElement is one element of a brace initializer. At most one of number,
// address and expr is set: a file-scope list writes a written number with its
// sign or an address, which is what the image holds, and a body's list writes an
// expression, which is what a store takes. `list` is the element's own brace
// list when it is one, `{{1, 2}}` for a member that is itself an aggregate, and
// `designators` are the designators written in front of it, empty for an element
// that names its subobject by position.
struct BraceElement {
	number      ?NumberConstant
	address     ?ast.AddressInit
	expr        ?ast.Expr
	list        ?BraceList
	designators []BraceDesignator
}

// BraceList is a brace initializer as the reader read it: the elements in the
// order written, and the opening brace, which is what a diagnostic about the
// list points at.
struct BraceList {
	elements []BraceElement
	at       tokenize.Token
}

// parse_brace_initializer reads `{ v, v, ... }`, the list of values that
// initializes an object. One element is a written number with its sign or a
// character constant, which 6.4.4.4 gives the value of the character and the
// type int; an address, which is what an element of a pointer's type is: a
// function designator, `&name`, or a string literal; or a brace list of its own,
// which is what an element that is itself an aggregate is. An element may be
// preceded by designators, `.name` or `[n]`, which name the subobject it
// initializes instead of leaving it to the position.
//
// `body` says the list initializes storage in a frame rather than an object in
// the image, which decides how a leaf is read. A frame is written by stores, so
// an element there is any expression a store can take, and a parenthesized
// constant or `(void *)0` is an element a body has and a file-scope list does
// not: the image holds constants and addresses, and those are what that reader
// accepts.
//
// A shape this reader does not read is refused by name and at its own location
// rather than read as a shorter list, because a list that wrote three values and
// was read as one would write a wrong table, and a wrong value in a table is
// worse than a refusal. Refused here: a file-scope element that is neither a
// written constant nor an address, and an empty pair of braces, which gives an
// array no size to be.
fn (mut p Parser) parse_brace_initializer(body bool) !BraceList {
	open := p.next() // {
	if p.at_punct('}') {
		p.next()
		p.error_at(open, 'unsupported: an empty brace initializer is not implemented')
		return error('empty brace initializer')
	}
	// A shape that stops the reader is reported and the rest of the list is
	// read past to its closing brace, so that the token after the list is where
	// the declaration reader expects it: a failed read that left the cursor
	// inside the braces would report the same declaration a second time at a
	// token of the next one.
	mut elements := []BraceElement{}
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated { opened at ${open.line}:${open.col}')
			return error('unterminated brace initializer')
		}
		designators := p.brace_designators() or {
			p.skip_balanced(open) or {}
			return error('brace designator')
		}
		if designators.len > 0 && !p.expect_punct('=') {
			p.skip_balanced(open) or {}
			return error('brace designator')
		}
		if p.at_punct('{') {
			list := p.parse_brace_initializer(body) or {
				p.skip_balanced(open) or {}
				return error('nested brace initializer')
			}
			elements << BraceElement{
				list:        list
				designators: designators
			}
		} else if p.starts_a_written_constant() {
			before := p.pos
			constant := p.number_constant() or {
				p.skip_balanced(open) or {}
				return error('brace element')
			}
			if body && !p.at_punct(',') && !p.at_punct('}') {
				// The constant is the first operand of an expression rather than
				// the whole element: `{1 + 1}` is one element whose value is two,
				// which gcc 16.2.1 accepts. What ends an element is the comma or
				// the closing brace, so any other token after the constant means
				// the element is longer than it and is read as an expression.
				p.pos = before
				expr := p.parse_expression() or {
					p.skip_balanced(open) or {}
					return error('brace element')
				}
				elements << BraceElement{
					expr:        expr
					designators: designators
				}
			} else {
				elements << BraceElement{
					number:      constant
					designators: designators
				}
			}
		} else if !body && (t.kind == .identifier || t.kind == .string || (t.kind == .punct && t.text == '&')) {
			// Only a token that can start an address takes the address path: a
			// name, a string literal, or the ampersand in front of one.
			if address := p.file_scope_address() {
				elements << BraceElement{
					address:     address
					designators: designators
				}
			} else {
				p.skip_balanced(open) or {}
				return error('brace element')
			}
		} else if body {
			// The element a store takes: a name, a call, `&x`, a string
			// literal, or a parenthesized constant this reader has no arm for.
			expr := p.parse_expression() or {
				p.skip_balanced(open) or {}
				return error('brace element')
			}
			// The address of a *part* of an object is refused by name. gcc 16.2.1
			// accepts `int a[2]; int *p[2] = {&a[0], &a[1]};`, and the store this
			// reader makes for one element of an array does not yet place the
			// byte the part starts at: measured on the binary built from this
			// tree's base commit, `int *p[1]; p[0] = &a[1];` reads back the
			// address of `a` rather than of `a[1]`. A wrong address is worse than
			// a refusal, so the shape is named here. The address of the whole
			// object, `&x`, is one the store places.
			if part := address_of_a_part(expr) {
				p.error_span(part.line, part.col, 'unsupported: the address of a part of ${part.name} is not implemented, and the address of the whole object is not what it names')
				p.skip_balanced(open) or {}
				return error('brace element')
			}
			elements << BraceElement{
				expr:        expr
				designators: designators
			}
		} else {
			p.error_at(t, 'unsupported: an element of a brace initializer is a written number or an address, found ${describe(t)}')
			p.skip_balanced(open) or {}
			return error('brace element')
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct('}') {
			p.next()
			return BraceList{
				elements: elements
				at:       open
			}
		}
		p.error_at(p.peek(), 'unsupported: expected , or } in a brace initializer, found ${describe(p.peek())}')
		p.skip_balanced(open) or {}
		return error('brace list')
	}
}

// AddressOfAPart is the name an address of a part of an object names together
// with the place the name is written. A diagnostic about the shape points at the
// name rather than at the ampersand in front of it, which is the token that looks
// like an ordinary address and not like the part being addressed.
struct AddressOfAPart {
	name string
	line int
	col  int
}

// address_of_a_part is what an address of a part of an object names, and none
// when the expression is not one: `&name[i]` and `&name.a` address a part of an
// object, and `&name` addresses the whole thing, which is a value an element
// store places. The name is empty for a part reached through something other than
// a name, which has no name to point at.
fn address_of_a_part(expr ast.Expr) ?AddressOfAPart {
	if expr is ast.Unary {
		if expr.op == '&' {
			inner := expr.expr
			if inner is ast.Index {
				if inner.base is ast.Ident {
					return AddressOfAPart{
						name: inner.base.name
						line: inner.base.line
						col:  inner.base.col
					}
				}
				return AddressOfAPart{
					line: inner.line
					col:  inner.col
				}
			}
			if inner is ast.Field {
				return AddressOfAPart{
					name: inner.name
					line: inner.line
					col:  inner.col
				}
			}
		}
	}
	return none
}

// starts_a_written_constant answers whether the next token begins a written
// number or character constant, sign included. It reads no token, so a false
// answer leaves the parser where it was and the element is read by another path.
fn (p Parser) starts_a_written_constant() bool {
	t := p.peek()
	if t.kind == .number || t.kind == .character {
		return true
	}
	if t.kind == .punct && (t.text == '-' || t.text == '+') {
		after := p.peek_at(1)
		return after.kind == .number || after.kind == .character
	}
	return false
}

// brace_designators reads the run of designators in front of an element and
// answers with an empty list when the element has none. A designator is `.name`
// or `[constant]`, and a run of them is one list because they all name the one
// subobject the element initializes.
fn (mut p Parser) brace_designators() ?[]BraceDesignator {
	mut designators := []BraceDesignator{}
	for p.at_punct('.') || p.at_punct('[') {
		at := p.next()
		if at.text == '.' {
			name := p.peek()
			if name.kind != .identifier {
				p.error_at(at, 'unsupported: a designator names a member with an identifier, found ${describe(name)}')
				return none
			}
			p.next()
			designators << BraceDesignator{
				member: name.text
				at:     at
			}
			continue
		}
		index := p.brace_designator_index() or { return none }
		if !p.expect_punct(']') {
			return none
		}
		designators << BraceDesignator{
			index: index
			at:    at
		}
	}
	return designators
}

// brace_designator_index reads the element an array designator names, which is
// an integer constant expression: a written constant is read as one, and
// anything else is read as an expression and folded the way a bound is. A shape
// the folder cannot evaluate is refused by name rather than read as an index of
// a guessed value.
fn (mut p Parser) brace_designator_index() ?int {
	at := p.peek()
	saved := p.pos
	saved_diagnostics := p.diagnostics.len
	if p.starts_a_written_constant() {
		if constant := p.number_constant() {
			if value := constant.number.integer {
				return int(value)
			}
		}
		p.pos = saved
		p.diagnostics = p.diagnostics[..saved_diagnostics]
	}
	expr := p.parse_expression() or {
		p.pos = saved
		p.diagnostics = p.diagnostics[..saved_diagnostics]
		p.error_at(at, 'unsupported: an array designator names an element with an integer constant, found ${describe(at)}')
		return none
	}
	value := p.constant_value(expr) or {
		p.error_at(at, 'unsupported: an array designator names an element with an integer constant, found ${describe(at)}')
		return none
	}
	return int(value)
}

// parse_address_initializer reads `{ a, a, ... }` where every element initializes
// an object of pointer type: an address - a function designator, `&name`, or a
// string literal - or a written integer, which is a null pointer constant. It
// mirrors parse_brace_initializer, including refusing a nested list, a designator,
// and an element that is neither an address nor a number by name and at its own
// location: a list read as shorter than it was written would write a wrong table,
// and a wrong address is worse than a refusal.
fn (mut p Parser) parse_address_initializer() ![]ast.AddressInit {
	open := p.next() // {
	if p.at_punct('}') {
		p.next()
		p.error_at(open, 'unsupported: an empty brace initializer is not implemented')
		return error('empty brace initializer')
	}
	mut elements := []ast.AddressInit{}
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated { opened at ${open.line}:${open.col}')
			return error('unterminated brace initializer')
		}
		if t.kind == .punct && t.text == '{' {
			p.error_at(t, 'unsupported: a nested brace initializer is not implemented')
			p.skip_balanced(open) or {}
			return error('nested brace initializer')
		}
		if t.kind == .punct && (t.text == '.' || t.text == '[') {
			p.error_at(t, 'unsupported: a designator in a brace initializer is not implemented')
			p.skip_balanced(open) or {}
			return error('brace designator')
		}
		before := p.diagnostics.len
		// Only a token that can start an address takes the address path: a name,
		// a string literal, or the ampersand in front of one. Everything else is
		// read the way a constant was always read, so a character constant and a
		// number keep the one path they had.
		if t.kind == .identifier || t.kind == .string || (t.kind == .punct && t.text == '&') {
			if address := p.file_scope_address() {
				elements << address
			} else {
				p.skip_balanced(open) or {}
				return error('address element')
			}
		} else {
			constant := p.number_constant() or {
				if p.diagnostics.len == before {
					p.error_at(t, 'unsupported: an element of a pointer initializer is an address or a written number, found ${describe(t)}')
				}
				p.skip_balanced(open) or {}
				return error('address element')
			}
			value := constant.number.integer or {
				p.error_at(t, 'unsupported: an element of a pointer initializer is an address or an integer constant')
				p.skip_balanced(open) or {}
				return error('address element')
			}
			elements << ast.AddressInit{
				number: value
				line:   t.line
				col:    t.col
			}
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct('}') {
			p.next()
			return elements
		}
		p.error_at(p.peek(), 'unsupported: expected , or } in a pointer initializer, found ${describe(p.peek())}')
		p.skip_balanced(open) or {}
		return error('pointer list')
	}
}

// BraceWrite is one scalar subobject a brace initializer wrote: the byte it
// starts at inside the object, the width of its type, the type's spelling, and
// the element that wrote it. A designator and a nested list both arrive here:
// where a value goes is decided while the list is walked, and what is left is
// one write per scalar subobject.
struct BraceWrite {
	offset   int
	width    int
	spelling string
	typ      types.Type
	element  BraceElement
}

// is_a_flat_list says the list is one level of elements with no designator and
// no nested list, which is the shape the readers that predate designators place.
// Every other list is walked by `fill_brace`.
fn (list BraceList) is_a_flat_list() bool {
	for element in list.elements {
		if element.list != none || element.designators.len > 0 {
			return false
		}
	}
	return true
}

// is_a_flat_number_list says every element is a written number, which is what a
// body's list has to be for the stores the flat path emits. A body list whose
// element is an expression is walked by `fill_brace` even when it is flat.
fn (list BraceList) is_a_flat_number_list() bool {
	for element in list.elements {
		if element.list != none || element.designators.len > 0 || element.number == none {
			return false
		}
	}
	return true
}

// brace_array_count is how many elements a list gives an array declared with
// empty brackets: the highest subobject it reaches, one past the last index a
// designator names and one past each element written by position.
fn brace_array_count(items []BraceElement) int {
	mut index := 0
	mut count := 0
	for item in items {
		if item.designators.len > 0 {
			if named := item.designators[0].index {
				index = named
			}
		}
		if index + 1 > count {
			count = index + 1
		}
		index++
	}
	return count
}

// member_index is the position of the named member in an aggregate, and none
// when the aggregate has no member of that name.
fn member_index(typ types.Type, name string) ?int {
	for i, member in typ.members {
		if member.name == name {
			return i
		}
	}
	return none
}

// fill_brace walks a brace list against the type it initializes and appends the
// writes it makes, one per scalar subobject, in the order it reaches them. It is
// 6.7.8 read as a walk: an element initializes the next subobject of the current
// level unless a designator names one, a nested list initializes the subobject
// as a whole, and an element that reaches an aggregate initializes it without
// its own braces. `start` is the first element to read and the answer is the
// first one left, so a caller can tell a list that wrote more than the object
// holds.
fn (mut p Parser) fill_brace(typ types.Type, items []BraceElement, start int, base int, mut writes []BraceWrite) int {
	match typ.kind {
		.array {
			element := typ.element() or { return start }
			stride := p.representation.size_of(element) or { return start }
			count := typ.count
			mut index := 0
			mut i := start
			for i < items.len {
				item := items[i]
				if item.designators.len > 0 {
					named := item.designators[0].index or {
						p.error_at(item.designators[0].at, 'unsupported: an array is initialized by position or by an index, and a member designator names no element')
						return items.len
					}
					index = named
					if index < 0 || (count > 0 && index >= count) {
						p.error_at(item.designators[0].at, 'a constraint violation: the designator [${index}] is outside ${typ.describe()}')
						return items.len
					}
					i = p.fill_designated(element, item.designators[1..], items, i, base + index * stride, mut writes)
					index++
					continue
				}
				if count > 0 && index >= count {
					return i
				}
				i = p.fill_one(element, items, i, base + index * stride, mut writes)
				index++
			}
			return i
		}
		.struct_ {
			layout := p.representation.layout(typ) or { return start }
			mut member := 0
			mut i := start
			for i < items.len {
				item := items[i]
				if item.designators.len > 0 {
					named := item.designators[0].member or {
						p.error_at(item.designators[0].at, 'unsupported: a struct is initialized by position or by a member name, and an index designates no member')
						return items.len
					}
					found := member_index(typ, named) or {
						p.error_at(item.designators[0].at, 'a constraint violation: ${typ.describe()} has no member named ${named}')
						return items.len
					}
					member = found
					i = p.fill_designated(typ.members[member].typ, item.designators[1..], items, i, base + layout.offsets[member], mut writes)
					member++
					continue
				}
				if member >= typ.members.len {
					return i
				}
				i = p.fill_one(typ.members[member].typ, items, i, base + layout.offsets[member], mut writes)
				member++
			}
			return i
		}
		.union_ {
			if typ.members.len == 0 || start >= items.len {
				return start
			}
			layout := p.representation.layout(typ) or { return start }
			item := items[start]
			mut member := 0
			mut rest := []BraceDesignator{}
			if item.designators.len > 0 {
				named := item.designators[0].member or {
					p.error_at(item.designators[0].at, 'unsupported: a union is initialized by position or by a member name, and an index designates no member')
					return items.len
				}
				member = member_index(typ, named) or {
					p.error_at(item.designators[0].at, 'a constraint violation: ${typ.describe()} has no member named ${named}')
					return items.len
				}
				rest = item.designators[1..]
			}
			return p.fill_designated(typ.members[member].typ, rest, items, start, base + layout.offsets[member], mut writes)
		}
		else {
			if start >= items.len {
				return start
			}
			p.write_brace_leaf(typ, base, items[start], mut writes)
			return start + 1
		}
	}
}

// fill_one initializes one subobject from the element at `start`: the element's
// own list when it has one, an aggregate walked element by element when the
// element is a value that reaches one, and a leaf otherwise. It answers the
// first element left.
fn (mut p Parser) fill_one(typ types.Type, items []BraceElement, start int, base int, mut writes []BraceWrite) int {
	item := items[start]
	if list := item.list {
		p.fill_brace(typ, list.elements, 0, base, mut writes)
		return start + 1
	}
	if typ.kind in [types.Kind.array, .struct_, .union_] {
		// Brace elision: the elements that follow initialize the aggregate's own
		// subobjects, which is the shape `struct S s = {1, 2, 3};` has for a
		// struct whose first member is a struct.
		return p.fill_brace(typ, items, start, base, mut writes)
	}
	p.write_brace_leaf(typ, base, item, mut writes)
	return start + 1
}

// fill_designated applies the designators that follow the one a caller already
// read at its own level, and then initializes the subobject they name. It is the
// `[1]` of a `.chain[1]`, or empty for a designator that named the subobject
// itself.
fn (mut p Parser) fill_designated(typ types.Type, designators []BraceDesignator, items []BraceElement, start int, base int, mut writes []BraceWrite) int {
	if designators.len == 0 {
		return p.fill_one(typ, items, start, base, mut writes)
	}
	designator := designators[0]
	rest := designators[1..]
	match typ.kind {
		.array {
			element := typ.element() or { return start }
			stride := p.representation.size_of(element) or { return start }
			index := designator.index or {
				p.error_at(designator.at, 'unsupported: an array is initialized by position or by an index, and a member designator names no element')
				return items.len
			}
			if index < 0 || (typ.count > 0 && index >= typ.count) {
				p.error_at(designator.at, 'a constraint violation: the designator [${index}] is outside ${typ.describe()}')
				return items.len
			}
			return p.fill_designated(element, rest, items, start, base + index * stride, mut writes)
		}
		.struct_ {
			layout := p.representation.layout(typ) or { return start }
			named := designator.member or {
				p.error_at(designator.at, 'unsupported: a struct is initialized by position or by a member name, and an index designates no member')
				return items.len
			}
			member := member_index(typ, named) or {
				p.error_at(designator.at, 'a constraint violation: ${typ.describe()} has no member named ${named}')
				return items.len
			}
			return p.fill_designated(typ.members[member].typ, rest, items, start, base + layout.offsets[member], mut writes)
		}
		.union_ {
			layout := p.representation.layout(typ) or { return start }
			named := designator.member or {
				p.error_at(designator.at, 'unsupported: a union is initialized by position or by a member name, and an index designates no member')
				return items.len
			}
			member := member_index(typ, named) or {
				p.error_at(designator.at, 'a constraint violation: ${typ.describe()} has no member named ${named}')
				return items.len
			}
			return p.fill_designated(typ.members[member].typ, rest, items, start, base + layout.offsets[member], mut writes)
		}
		else {
			p.error_at(designator.at, 'unsupported: a designator names a subobject of an object with members, and ${typ.describe()} has none')
			return items.len
		}
	}
}

// write_brace_leaf appends the one write an element makes for a scalar subobject
// of the given type at the given byte.
fn (mut p Parser) write_brace_leaf(typ types.Type, base int, element BraceElement, mut writes []BraceWrite) {
	writes << BraceWrite{
		offset:   base
		width:    p.representation.size_of(typ) or { 0 }
		spelling: typ.describe()
		typ:      typ
		element:  element
	}
}

// collect_leaves is every scalar subobject of an object type, in the order a
// walk reaches them, which is what a body's initializer stores zero into before
// it writes the values: the frame slot starts as whatever was there, and the
// subobjects a list did not reach are the zeros C says the rest of the object
// holds (6.7.8p21). A union contributes every member, because a member starts at
// the beginning of the union and zeroing each of them covers the bytes whichever
// one a later read looks at.
fn (mut p Parser) collect_leaves(typ types.Type, base int, mut leaves []BraceWrite) {
	match typ.kind {
		.array {
			element := typ.element() or { return }
			stride := p.representation.size_of(element) or { return }
			for index in 0 .. typ.count {
				p.collect_leaves(element, base + index * stride, mut leaves)
			}
		}
		.struct_ {
			layout := p.representation.layout(typ) or { return }
			for i, member in typ.members {
				p.collect_leaves(member.typ, base + layout.offsets[i], mut leaves)
			}
		}
		.union_ {
			layout := p.representation.layout(typ) or { return }
			for i, member in typ.members {
				p.collect_leaves(member.typ, base + layout.offsets[i], mut leaves)
			}
		}
		else {
			leaves << BraceWrite{
				offset:   base
				width:    p.representation.size_of(typ) or { 0 }
				spelling: typ.describe()
				typ:      typ
			}
		}
	}
}

// BraceGeneral is a nested or designated list at file scope as the object it
// initializes: the writes the list made, the bytes one element of the object
// takes, how many elements an array has, and the type the walk ran against. The
// count and the type are the two facts the walk answers that the declarator did
// not: an array with empty brackets takes its size from the list.
struct BraceGeneral {
	members  []ast.MemberInit
	bytes    int
	count    int
	resolved types.Type
}

// file_scope_general_initializer walks a nested or designated list against the
// type of the object it initializes and answers with the writes the image holds.
// A shape the walk cannot place - an object that is a scalar, a type without a
// layout, a list that reaches past the object - is refused by name and none is
// answered, so the declaration is not laid out with a table it cannot trust.
fn (mut p Parser) file_scope_general_initializer(spec DeclSpec, d Declarator, list BraceList, name string) ?BraceGeneral {
	declared := p.declared_type(spec.clause, d)
	array := d.is_array()
	if !array && spec.clause.kind !in [types.Kind.struct_, .union_] {
		p.error_at(list.at, 'unsupported: ${name} is a scalar, and a nested or designated list initializes an object with subobjects')
		return none
	}
	mut target := declared
	mut count := d.array_count()
	if array && count == 0 {
		// Empty brackets: the size is the highest subobject the list reaches.
		count = brace_array_count(list.elements)
		if count > 0 {
			element := declared.element() or { return none }
			target = types.array_of(element, count)
		}
	}
	element := if array { target.element() or { return none } } else { target }
	bytes := p.representation.size_of(element) or {
		p.error_at(list.at, 'unsupported: the layout of ${target.describe()} is not one this compiler knows')
		return none
	}
	mut writes := []BraceWrite{}
	end := p.fill_brace(target, list.elements, 0, 0, mut writes)
	if end < list.elements.len {
		p.error_at(list.at, 'a constraint violation: ${name} is initialized with more elements than its type holds')
		return none
	}
	return BraceGeneral{
		members:  p.brace_writes_to_members(writes)
		bytes:    bytes
		count:    count
		resolved: target
	}
}

// brace_writes_to_members turns the writes a list made into the entries a
// file-scope initializer carries: the byte the subobject starts at inside the
// object, its width and its spelling, and the constant or the address written
// into it. The class is the subobject's own type, because a value written into a
// member is converted the way a store into the member converts it.
fn (mut p Parser) brace_writes_to_members(writes []BraceWrite) []ast.MemberInit {
	mut members := []ast.MemberInit{cap: writes.len}
	for write in writes {
		element := write.element
		if address := element.address {
			members << ast.MemberInit{
				offset:   write.offset
				width:    write.width
				spelling: write.spelling
				address:  address
			}
			continue
		}
		number := element.number or { continue }
		init, init_float := initializer_for(write.spelling, number.number.integer,
			number.number.floating)
		members << ast.MemberInit{
			offset:     write.offset
			width:      write.width
			spelling:   write.spelling
			init:       init
			init_float: init_float
		}
	}
	return members
}

// constant_expr is one constant of a brace list as the expression the tree
// carries: an integer constant becomes an int literal and a floating one a
// double literal, which are the two nodes a written constant already is. The
// type is the one the literal has from its spelling, not the type of the object
// it initializes, so that the assignment the list becomes checks the constant
// against the object the same way a written assignment does.
fn (mut p Parser) constant_expr(constant NumberConstant) ast.Expr {
	if value := constant.number.integer {
		// A character constant has the type int whatever it was written as,
		// and its spelling is not the spelling of a number, so the type is
		// asked of the token rather than read off the text.
		if constant.at.kind == .character {
			return ast.Expr(ast.IntLit{
				value: value
				text:  constant.at.text
				typ:   types.int_type()
				line:  constant.at.line
				col:   constant.at.col
			})
		}
		return ast.Expr(ast.IntLit{
			value: value
			text:  constant.at.text
			typ:   p.constant_type(constant.at, value)
			line:  constant.at.line
			col:   constant.at.col
		})
	}
	if long_value := constant.number.long_floating {
		return ast.Expr(ast.FloatLit{
			long_value: long_value
			text:       constant.at.text
			typ:        types.long_double_type()
			line:       constant.at.line
			col:        constant.at.col
		})
	}
	value := constant.number.floating or { f64(0) }
	return ast.Expr(ast.FloatLit{
		value: value
		text:  constant.at.text
		typ:   p.floating_type(constant.at, value)
		line:  constant.at.line
		col:   constant.at.col
	})
}

// initializer_for makes a file-scope initializer the class the object was
// declared with, and answers with the pair the tree carries: at most one of them
// is set, and it is the one the object's type asks for. An object with no
// initializer answers with neither, which is the storage a definition starts
// zeroed. A floating initializer for an integer object and an integer one for a
// double are both conversions the language makes, so neither is reported, and a
// float object takes a floating initializer the same way a double does.
fn initializer_for(written string, integer ?i64, floating ?f64) (?i64, ?f64) {
	if written == 'long double' {
		// A long double object holds a value a host double cannot represent, so
		// the conversion of a double or an integer constant into one is not made
		// here: the constant's own extended-format value travels in its own
		// field, and a constant without one is refused where the bytes would be
		// written.
		return none, none
	}
	mut value := integer
	mut fraction := floating
	if written == 'double' || written == 'float' {
		if number := integer {
			return none, f64(number)
		}
		return none, fraction
	}
	if fraction_value := fraction {
		// The truncation is towards zero, which is what the conversion from a
		// floating type to an integer one is defined to do.
		if fraction_value != fraction_value {
			return none, none
		}
		return i64(fraction_value), none
	}
	return value, none
}

// initializer_list_for makes each element of an array's brace list the class the
// object's element type holds, which is the conversion an initialization makes:
// an integer constant initializing a double is that integer as a double, and a
// floating constant initializing an integer is truncated towards zero. At most one
// of the two answers is non-empty, for the same reason the scalar pair is split:
// how the element's bytes are written is a question about the class.
//
// An element that is an address does not belong here: the type is not a pointer,
// or the list would have been read as a table of addresses before this path, and
// an address has no conversion to another scalar. It is refused by name rather
// than read as a zero, because a zero in the storage is a value the declaration
// did not write.
fn (mut p Parser) initializer_list_for(written string, elements []BraceElement, name string, at tokenize.Token) ([]i64, []f64) {
	if written == 'long double' {
		// An array of long doubles would be a table of sixteen-byte extended
		// constants, and the two lists this returns carry an integer or a
		// double; a long double value fits in neither. The elements are refused
		// by name rather than dropped, because the storage they would have gone
		// into starts zeroed and a program reading the table would get zeros
		// with no diagnostic.
		p.error_at(at, 'unsupported: ${name} is an array of long doubles with a brace initializer, and the extended constants of one have no field to be written into at file scope here')
		return []i64{}, []f64{}
	}
	if written == 'double' || written == 'float' {
		mut floats := []f64{cap: elements.len}
		for element in elements {
			if element.address != none {
				p.error_at(at, 'unsupported: ${name} does not hold addresses, and its initializer writes one')
				return []i64{}, []f64{}
			}
			number := element.number or { continue }
			_, fraction := initializer_for(written, number.number.integer, number.number.floating)
			floats << (fraction or { f64(0) })
		}
		return []i64{}, floats
	}
	mut integers := []i64{cap: elements.len}
	for element in elements {
		if element.address != none {
			p.error_at(at, 'unsupported: ${name} does not hold addresses, and its initializer writes one')
			return []i64{}, []f64{}
		}
		number := element.number or { continue }
		integer, _ := initializer_for(written, number.number.integer, number.number.floating)
		integers << (integer or { i64(0) })
	}
	return integers, []f64{}
}

// struct_brace_members checks a struct's brace initializer and answers the
// object's layout when the list is one this reader places. 6.7.8p17 gives the
// values to the members in the order the members were written, and the members
// after the last value are zero (6.7.8p21).
//
// A struct is read here only when every member is a complete scalar. A bitfield
// member takes a value written into a field of a storage unit and a member that
// is itself an aggregate takes a value written into a sub-object, neither of
// which is a store this tree places; each is refused by name rather than written
// at a guessed offset, because a wrong value is worse than a refusal. A list
// longer than the members is the constraint gcc 16.2.1 reports as `excess
// elements in struct initializer`.
fn (mut p Parser) struct_brace_members(aggregate types.Type, list BraceList, name string) ?types.Layout {
	for member in aggregate.members {
		if member.bitfield {
			p.error_at(list.at, 'unsupported: ${name} has a bitfield member ${member.name}, and a value is not written into a bitfield here')
			return none
		}
		if member.typ.kind in [types.Kind.struct_, .union_, .array] || member.typ.kind == .unknown {
			p.error_at(list.at, 'unsupported: ${name} has a member ${member.name} of the type ${member.typ.describe()}, and a value is not written into an object of that type here')
			return none
		}
	}
	if list.elements.len > aggregate.members.len {
		p.error_at(list.at, 'a constraint violation: ${name} has ${aggregate.members.len} members and its initializer writes ${list.elements.len}')
		return none
	}
	// An element has to be the class its member holds: an address for a member of
	// pointer type, a number for any other scalar, and a written zero, which is
	// the null pointer constant, for either. The two are told apart here rather
	// than converted, because an address written into a member that does not hold
	// one is a wrong value, not a conversion.
	for i in 0 .. list.elements.len {
		element := list.elements[i]
		pointer := aggregate.members[i].typ.kind == .pointer
		if element.address != none && !pointer {
			p.error_at(list.at, 'unsupported: ${name} has a member ${aggregate.members[i].name} of the type ${aggregate.members[i].typ.describe()}, and its initializer writes an address')
			return none
		}
		if number := element.number {
			if pointer && (number.number.integer or { i64(0) }) != 0 {
				p.error_at(list.at, 'unsupported: ${name} has a member ${aggregate.members[i].name} of the type ${aggregate.members[i].typ.describe()}, and its initializer writes the number ${number.number.integer or { i64(0) }}')
				return none
			}
		}
	}
	layout := p.representation.layout(aggregate) or {
		p.error_at(list.at, 'unsupported: the layout of ${aggregate.describe()} is not one this compiler knows')
		return none
	}
	return layout
}

// struct_member_inits makes each element a struct's brace initializer wrote the
// value the image holds for that member: the conversion the member's own type
// makes, at the offset and width the layout gave the member, or an address the
// layout resolves when the member is a pointer.
fn (mut p Parser) struct_member_inits(aggregate types.Type, list BraceList, layout types.Layout) []ast.MemberInit {
	mut members := []ast.MemberInit{cap: list.elements.len}
	for i in 0 .. list.elements.len {
		element := list.elements[i]
		member := aggregate.members[i]
		if address := element.address {
			members << ast.MemberInit{
				offset:   layout.offsets[i]
				width:    p.representation.size_of(member.typ) or { 0 }
				spelling: member.typ.describe()
				address:  address
			}
			continue
		}
		number := element.number or { continue }
		init, init_float := initializer_for(member.typ.describe(), number.number.integer,
			number.number.floating)
		members << ast.MemberInit{
			offset:     layout.offsets[i]
			width:      p.representation.size_of(member.typ) or { 0 }
			spelling:   member.typ.describe()
			init:       init
			init_float: init_float
		}
	}
	return members
}

// check_definition reports what keeps a definition from being emitted. A
// prototype can promise anything, because nothing is emitted for it; a
// definition is code, and this back end takes the return types and parameters
// it can name.
fn (mut p Parser) check_definition(spec DeclSpec, d Declarator) {
	if d.name.len == 0 {
		p.error_at(spec.start, 'unsupported: a function definition needs a name')
		return
	}
	// A return type with a star is one address wide whatever it points at, so
	// the base type is asked the same question a local of pointer type is: the
	// emitter sizes the value from the star and never lays out what is under it.
	// The complex and long double clause below is about a value the emitter has
	// to give a form to, so it is asked only of a return type that is not a
	// pointer, and a pointer to one of those types takes the same answer a
	// pointer object takes.
	if d.pointer_count() == 0 && spec.clause.kind == .long_double {
		// The type itself holds now - it has a size, a form and constants - but a
		// value of it is carried in the x87 stack, whose calling convention this
		// compiler does not emit yet, so a value passed back would be read from
		// the wrong place. The refusal names the stack rather than claiming the
		// type does not exist.
		p.error_at(spec.start, 'unsupported: long double is a type the x87 stack carries and this compiler has no calling convention for it yet, so a function cannot return it')
		return
	}
	if d.pointer_count() == 0 && spec.clause.is_complex() {
		// A type the model knows and the emitter has no form for is a different
		// answer from a type whose first word is not one the emitter reads:
		// `double _Complex` is one type, and the refusal names it rather than
		// naming half of it.
		p.error_at(spec.start, 'unsupported: ${spec.clause.describe()} is a type this compiler does not emit yet, so a function cannot return it')
		return
	}
	if offender := p.unsupported_type_word(spec, d.pointer_count()) {
		p.error_at(spec.start, 'unsupported type ${offender}')
		return
	}
	if d.param_problem.len > 0 {
		p.error_at(d.param_at, d.param_problem)
	}
}

// word_problem is the word of a type this compiler does not read, or none when
// the word names a type it does.
//
// A name this file declared as a type is asked about the type it names rather
// than about itself: `typedef long Big; Big x;` is a `long x`, and the answer is
// that the back end has a form for a long. Answering none for the name would move
// the question to the back end, which only asks it for an object something uses,
// and an unused object of a type with no form would then be dropped without a
// word.
fn (p Parser) word_problem(word string) ?string {
	if word in supported_types {
		return none
	}
	if word.contains('*') {
		// A spelling that carries its own stars is a pointer, and a pointer is
		// one word on this machine whatever it points at: the back end sizes it
		// from the star and never asks what is under it. A declaration written
		// with a star keeps the star in its declarator and the word here is the
		// base, so a word with a star in it is a type the reader resolved rather
		// than one the file wrote, which is what `typeof(&x) p` is.
		return none
	}
	if spelling := p.alias_spelling(word) {
		// A type the alias names with a star is a pointer, and a pointer is one
		// word on this machine whatever it points at: the back end sizes it from
		// the star and never asks what is under it. `typedef char *String` is the
		// case that reaches here, and the answer is that the emitter has a form
		// for it.
		if spelling.contains('*') {
			return none
		}
		words := spelling.split(' ')
		if words.len > 0 {
			// The type the words name, not the first word of them: `unsigned`,
			// `unsigned int` and `unsigned long` are three spellings and two
			// kinds, and asking about the kind is what keeps the third from
			// being read as the answer to the first.
			kind := types.from_specifiers(words) or { return words[0] }
			if kind in emitted_kinds {
				return none
			}
			return words[0]
		}
	}
	// A spelling of more than one word that is not a name this file declared: the
	// words the file wrote, joined by the caller, and the type they name decides.
	// `unsigned long int` and `long unsigned` are spellings of a type the emitter
	// has a form for, and neither is a name a lookup would find.
	words := word.split(' ')
	if words.len > 1 {
		if kind := types.from_specifiers(words) {
			return if kind in emitted_kinds { none } else { words[0] }
		}
	}
	return word
}

// incomplete_aggregate says a declaration's clause is a tag with no body, or one
// whose members this model could not lay out, so the model has no size for an
// object of it. A pointer to such a type is still a complete object: 6.2.5 lets
// a pointer name an incomplete type, and the back end sizes a pointer from its
// star rather than from what it points at.
fn (p Parser) incomplete_aggregate(spec DeclSpec) bool {
	if spec.clause.kind !in [types.Kind.struct_, .union_] {
		return false
	}
	return !spec.clause.is_complete() || p.representation.layout(spec.clause) == none
}

// unsupported_type_word is the word among a declaration's specifiers that keeps
// the back end from giving an object the type it names, or none when every word
// is one the emitter has a form for. A definition's return type and a
// declaration inside a body are the same question, because both are storage the
// program has to find room for; a prototype is a promise, and a promise is not
// asked.
//
// It answers with the first word and not with the type as it was written, which
// is what the emitter stopped at: a type written as two words that the emitter has
// no form for is named by its first word, so `long double x` reads `unsupported
// type long`, which is the wording this compiler published. The 64-bit integer
// spellings are not that case any more: they name kinds in emitted_kinds and are
// answered none. The question is about the kind the words name rather than about
// the words, because `long int`, `signed long` and `long` are one type and three
// spellings. A type written as two words is named in full where the answer is
// about the construct rather than about the word: the parameter list names what a
// parameter was declared with, and a complex type is refused by name below.
fn (p Parser) unsupported_type_word(spec DeclSpec, stars int) ?string {
	// The words a type is made of, not the storage class in front of them: an
	// `extern` or a `static` is not a type, and reporting one as an unsupported
	// type would be reporting the wrong word for the right reason.
	// An object of an aggregate type is storage of the size the model lays out,
	// and the words of the declaration say nothing about that size: `struct S`
	// is a tag, and its members are what decide how many bytes the object is. A
	// tag written with no body leaves the size unknown, so the refusal is the
	// tag as it was written.
	//
	// `stars` is how many pointer steps the declarator wrote, because a pointer
	// to a type the model cannot size is still one address wide: 6.2.5 lets a
	// pointer name an incomplete type, and the back end sizes a pointer from the
	// star and never asks what is under it.
	if spec.clause.kind in [types.Kind.struct_, .union_] {
		// A tag that was declared and never defined is not complete, so there is
		// no size to give an object of it: the refusal names the tag as it was
		// written, and it happens here rather than where the object is used. A
		// pointer to it is a complete object and there is nothing to refuse:
		// `FILE *f;` reaches here when FILE is `typedef struct _IO_FILE FILE;`
		// and the struct's body is written after the typedef, and measured, gcc
		// 16.2.1 compiles that program and it exits 0. An object of the tag with
		// no star stays refused, which is what gcc does too ("storage size of 'x'
		// isn't known").
		if p.incomplete_aggregate(spec) {
			if stars > 0 {
				return none
			}
			return spec.type_words.join(' ')
		}
		return none
	}
	// A 128-bit integer is storage this back end has: an object of one is the
	// sixteen bytes it writes at two words, so a declaration of one is a
	// declaration and not a refusal. The questions about a value of that width
	// are the emitter's, and it answers them by name.
	if spec.clause.kind in [types.Kind.int128, .unsigned_int128] {
		return none
	}
	if spec.type_words.len == 0 {
		return none
	}
	if spec.type_words.len == 1 {
		return p.word_problem(spec.type_words[0])
	}
	// More than one word: the type they name decides, and the answer is the first
	// word when that type is not one the emitter has a form for. A run of words
	// the table does not have at all names no type, and its first word is named
	// the same way.
	kind := types.from_specifiers(spec.type_words) or { return spec.type_words[0] }
	if kind in emitted_kinds {
		return none
	}
	// A complex type written with its floating word in front is named by the
	// word that makes it complex: `double _Complex` is refused for the
	// `_Complex`, which is what the message said before the 64-bit spellings
	// were read, and `double` on its own is a type this compiler reads.
	for word in spec.type_words {
		if word in ['_Complex', '_Imaginary'] {
			return word
		}
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
		if t.text in bitint_words && !spec.has_type {
			// `_BitInt (N)` is one specifier: the width in the parentheses
			// is read with the word, and the words of the declaration carry
			// the two as one, because a later stage has no parentheses left
			// to look at. The width is the type, so it is read here rather
			// than counted later.
			//
			// Only before the declaration has a type, the same as a typeof
			// specifier: a type word cannot follow one, and `int _BitInt(8)
			// x;` is two types written where there is room for one.
			p.next()
			spec.note(t)
			width := p.parse_bitint_width(t)!
			word := '_BitInt(${width})'
			// The words a declaration carries from here on are the resolved
			// type's own spelling, which is what a typeof specifier writes
			// there too, because later stages ask the words what the type is:
			// `_BitInt(128)` and `__int128` are one type written twice, and a
			// declaration is not the place to keep both spellings alive. A
			// width this compiler has no value for stays as the program wrote
			// it, so that the refusal names the width that was asked for.
			if resolved := types.from_words([word]) {
				spec.type_words << resolved.describe()
			} else {
				spec.type_words << word
			}
			spec.has_type = true
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
		if (t.text in typeof_words || t.text in typeof_unqual_words) && !spec.has_type {
			// `typeof (...)` is a type specifier: the operand between the
			// parentheses is a type name or an expression, and the specifier
			// names the type of that operand. The type this compiler resolved
			// is written into the words of the declaration, because the words
			// are what a declaration carries from here on and no later stage
			// has an operand left to look at.
			//
			// Only before the declaration has a type: a specifier cannot
			// follow one, so `int typeof = 1;` is a declaration whose
			// declarator is named by a keyword, which is refused there and
			// where gcc 16.2.1 refuses it too.
			p.next()
			spec.note(t)
			named := p.parse_typeof_specifier(t, depth, t.text in typeof_unqual_words)!
			tag_clause = named
			spec.type_words << types.unqualified(named).describe()
			spec.has_type = true
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

// parse_typeof_specifier reads the operand of a typeof specifier and answers the
// type it names. The operand is a type name if a type name is written there and
// an expression otherwise, which is the shape a cast and the operand of sizeof
// share: `typeof(int)` and `typeof(x)` are one construct asked of two different
// things.
//
// The operand's value is neither read nor evaluated, which is what makes
// `typeof(f())` a type rather than a call, and what is taken is the type the
// model resolved: `typeof(x)` written where x is a typedef is the type behind
// the name, and the declaration that follows is built from that type.
//
// `typeof_unqual` is the same specifier with the qualifiers taken off the type
// it names, which is the whole of the difference between the two spellings.
//
// Two operands are refused here rather than left to a later stage: one whose
// type the model did not resolve, because a declaration built from a type
// nothing answered for is a declaration nothing can size, and one of an array
// type, which would make the declaration an array the declarator never wrote.
fn (mut p Parser) parse_typeof_specifier(at tokenize.Token, depth int, unqual bool) !types.Type {
	if !p.at_punct('(') {
		p.error_at(p.peek(), 'unsupported: expected ( after ${at.text}, found ${describe(p.peek())}')
		return error('expected ( after ${at.text}')
	}
	p.next()
	mut answered := types.Type{}
	mut written := ''
	if p.starts_declaration(p.peek()) {
		name := p.parse_type_name(depth)!
		answered = name.typ
		written = name.spelling
	} else {
		operand := p.parse_expression()!
		written = describe_operand(operand)
		if p.is_unresolved(operand) {
			p.error_at(at, 'unsupported: ${at.text} asks for the type of ${written}, and this compiler did not resolve its type')
			return error('no type for the operand')
		}
		answered = operand.typ
	}
	if !p.expect_punct(')') {
		return error('unclosed ${at.text}')
	}
	if answered.kind == .unknown {
		p.error_at(at, 'unsupported: ${at.text} asks for the type of ${written}, and this compiler did not resolve it')
		return error('no type for the operand')
	}
	if answered.is_array() {
		p.error_at(at, 'unsupported: ${at.text} of an array type is not implemented; write the element type and how many elements')
		return error('typeof of an array')
	}
	if unqual {
		return types.unqualified(answered)
	}
	return answered
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
		// An enumerator list declares names and gives them values: each name is
		// an integer constant, so reading it is what lets a use of it be the
		// number the enum gave it rather than a name nothing declares.
		p.parse_enumerator_list(open)!
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

// parse_enumerator_list reads the body of an enum: names, each optionally given a
// value by a constant expression, separated by commas, with the closing brace
// ending the list. The trailing comma C99 allows is read like any other.
//
// Every enumerator is declared where it is read, and its value is recorded with
// it: 6.7.2.2 makes an enumeration constant an int, and a use of one is the number
// the enum gave it rather than a read of storage that does not exist. An
// enumerator written with no `=` is the one before it plus one, and the first is
// zero, which is what `enum { A, B, C };` means and how a header counts a list it
// cannot count itself.
//
// The value is folded with the reader's own integer constant expression
// evaluator, the one an array bound goes through. An expression it cannot compute
// is refused by name rather than guessed at: values like glibc's `_ISalpha` are
// computed from `>>>` and `?:` in the enumerator list, and an enum is how a header
// builds the masks a program compares against, so a number that is wrong is a
// program that is wrong in silence.
fn (mut p Parser) parse_enumerator_list(open tokenize.Token) ! {
	mut next := i64(0)
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated enum body, opened at ${open.line}:${open.col}')
			return error('unterminated enum body')
		}
		if t.kind == .directive {
			p.next()
			continue
		}
		if t.kind == .punct && t.text == '}' {
			p.next()
			return
		}
		if t.kind != .identifier {
			p.error_at(t, 'unsupported: an enumerator is a name, found ${describe(t)}')
			return error('an enumerator name')
		}
		name := p.next()
		mut value := next
		if p.at_punct('=') {
			p.next()
			expression := p.parse_expression()!
			value = p.constant_value(expression) or {
				p.error_at(name, 'unsupported: the value of ${name.text} is not an integer constant expression this compiler can compute')
				return error('an enumerator value')
			}
		}
		// An enumeration constant is not an object, so nothing is declared that
		// could be written to: only the number is recorded, and the name is
		// marked declared for the check at the end of the unit.
		p.scopes.declare_constant(name.text, value)
		p.declared[name.text] = true
		next = value + 1
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct('}') {
			p.next()
			return
		}
		p.error_at(p.peek(), 'unsupported: expected , or } in an enumerator list, found ${describe(p.peek())}')
		return error('an enumerator separator')
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

// parse_bitint_width reads the width of a _BitInt specifier, which is written in
// parentheses after the word: the `(128)` of `_BitInt(128)`.
//
// The width is one written number. C23 reads any integer constant expression
// there, and `_BitInt(64 * 2)` is a type of 128 bits; this reader reads a number
// and refuses an expression by name, because a width read as its first term
// would be a type of the wrong size. A type is not a thing to guess at, and the
// width a program wrote is the whole of what it asked for.
fn (mut p Parser) parse_bitint_width(at tokenize.Token) !int {
	if !p.at_punct('(') {
		p.error_at(p.peek(), 'unsupported: ${at.text} is written with its width in parentheses, as in ${at.text}(128), found ${describe(p.peek())}')
		return error('expected the width of ${at.text}')
	}
	p.next()
	if p.peek().kind != .number {
		p.error_at(p.peek(), 'unsupported: the width of ${at.text} is a written number, found ${describe(p.peek())}')
		return error('expected the width of ${at.text}')
	}
	t := p.next()
	value := parse_integer_literal(t.text) or {
		p.error_at(t, 'unsupported: the width of ${at.text} is a written number, and ${t.text} is not one this compiler reads')
		return error('expected the width of ${at.text}')
	}
	if !p.expect_punct(')') {
		return error('unclosed ${at.text}')
	}
	return int(value)
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
// and function suffixes that bind to it. What it answers with is the steps that
// build the type, in the order the type is built rather than in the order they
// were written, because a parenthesised pointer swaps the two: the suffixes
// outside the parentheses apply to the base before the star does.
fn (mut p Parser) parse_declarator(depth int) !Declarator {
	if depth > max_declaration_depth {
		p.error_at(p.peek(), 'declaration is nested more than ${max_declaration_depth} levels deep')
		return error('declaration nested too deeply')
	}
	mut d := Declarator{}
	// The stars in front of the direct-declarator, as they were written.
	mut stars := []DeclStep{}
	for p.at_punct('*') {
		at := p.peek()
		p.next()
		mut quals := types.Qualifiers{}
		// Qualifiers may sit between the star and the name: `char *restrict p`.
		for p.peek().kind == .identifier && p.peek().text in type_qualifiers {
			quals = add_qualifier(quals, p.peek().text)
			p.next()
		}
		stars << DeclStep{
			kind:  .pointer_step
			quals: quals
			at:    at
		}
	}
	// The direct-declarator is a name or another declarator in parentheses, and
	// its own steps sit between this level's stars and the base.
	mut inner := []DeclStep{}
	if p.at_punct('(') {
		// A declarator in parentheses, as in `(*handler)(int)`. The suffixes
		// after the closing parenthesis bind to the declarator around them, not
		// to the name inside, which is the difference between a function and a
		// pointer to one.
		p.next()
		inner_declarator := p.parse_declarator(depth + 1)!
		if !p.expect_punct(')') {
			return error('unclosed declarator')
		}
		d.name = inner_declarator.name
		d.name_at = inner_declarator.name_at
		d.param_problem = inner_declarator.param_problem
		d.param_at = inner_declarator.param_at
		inner = inner_declarator.steps
	} else if p.peek().kind == .identifier {
		d.name_at = p.peek()
		d.name = p.next().text
		// A word the language reserves for itself cannot be the name of a
		// declaration (6.4.1). The lexer does not tell a keyword from an identifier
		// - that table is `tokenize/`, another lane's file - so the reader that would
		// make one a name is where the question is asked. Measured, `int if = 1;` and
		// `int main(void) { int sizeof = 1; return 0; }` compiled where gcc 16.2.1
		// refuses both with `expected identifier or '(' before 'if'`.
		if is_keyword(d.name) {
			p.error_at(d.name_at, 'unsupported: ${d.name} is a keyword, and a keyword cannot be the name of a declaration')
			return error('keyword as a name')
		}
	}
	// A suffix is applied to the base ahead of what has been read so far: the
	// brackets bind to the name before the stars do, so each one goes in front
	// of the steps already there.
	mut steps := inner.clone()
	for {
		if p.at_punct('[') {
			at := p.peek()
			suffix := p.parse_array_suffix(d.name)!
			steps.prepend(DeclStep{
				kind:            .array_step
				count:           suffix.count_as_step()
				sized:           suffix.bound != .empty
				at:              at
				bound_name:      p.bound_name
				bound_name_line: p.bound_name_line
				bound_name_col:  p.bound_name_col
			})
			continue
		}
		if p.at_punct('(') {
			// The parameters are read with the reader a declaration uses, and
			// each of them names its own specifiers, so what the list resolved
			// to last is not this declarator's base or storage class: the base
			// is what the declaration's own specifiers gave, and so is the
			// storage, which decides whether the name is a type. Measured
			// before each was held, `int f(void); int main(void) { return f() +
			// 1; }` was refused because the `(void)` left the base at void and
			// the prototype was declared `void (void)`, and `typedef int
			// (*cmp)(const void *, const void *);` was recorded as a name of no
			// type because the parameter list left the storage automatic.
			at := p.peek()
			base := p.pending_base
			storage := p.pending_storage
			params := p.parse_parameter_list(depth + 1)!
			p.pending_base = base
			p.pending_storage = storage
			if params.problem.len > 0 && d.param_problem.len == 0 {
				d.param_problem = params.problem
				d.param_at = params.at
			}
			steps.prepend(DeclStep{
				kind:       .function_step
				params:     params.params
				variadic:   params.variadic
				prototyped: params.prototyped
				at:         at
			})
			continue
		}
		break
	}
	// The stars read at this level apply after everything inside the parentheses
	// and after every suffix, so they go in front of the steps from the last
	// written to the first: the star nearest the name is the pointer the name is.
	for i in 0 .. stars.len {
		steps.prepend(stars[i])
	}
	d.steps = steps
	// The name is recorded where the declarator ends, which is where 6.2.1 says
	// its scope begins: a declaration is complete when its reader finishes it.
	p.note_declaration(d, depth)
	return d
}

// TypeName is a type name as it was written: what it resolved to, how it is
// spelled in a diagnostic, and where it started. It is what a cast and the
// operand of `sizeof` read, and neither of them declares anything, so the
// spelling is kept beside the type rather than looked up again.
struct TypeName {
	typ      types.Type
	spelling string
	at       tokenize.Token
}

// parse_type_name reads a type name: the specifiers of a declaration and a
// declarator with no name in it. It is the shape `(char *)` and `sizeof(int)`
// share, which is why it is here beside the declarator rather than in the
// expression reader: it is the declaration grammar with the name left out.
fn (mut p Parser) parse_type_name(depth int) !TypeName {
	spec, d, start := p.parse_type_name_parts(depth)!
	return TypeName{
		typ:      p.declared_type(spec.clause, d)
		spelling: p.spelling_of(spec, d.pointer_count())
		at:       start
	}
}

// parse_type_name_parts reads a type name and answers the three pieces it was
// built from: the specifiers, the abstract declarator, and the token the name
// started at. A compound literal is read from the declarator as well as the
// type - its array count and its pointer stars are the shapes the object and
// the stores are built from - so the parts are kept here rather than folded
// into the one TypeName a cast or a sizeof needs.
fn (mut p Parser) parse_type_name_parts(depth int) !(DeclSpec, Declarator, tokenize.Token) {
	start := p.peek()
	spec := p.parse_decl_specifiers(depth)!
	d := p.parse_declarator(depth)!
	if d.name.len > 0 {
		// A type name has no declarator that names anything: `(int x)` is not a
		// cast, and reading it as one would silently drop the name.
		p.error_at(d.name_at, 'unsupported: a type name is read here, and ${d.name} names an object')
		return error('a name in a type name')
	}
	return spec, d, start
}

// apply_step is one constructor of a declarator applied to a type: a pointer to
// it, an array of it, or a function returning it.
fn apply_step(base types.Type, step DeclStep) types.Type {
	return match step.kind {
		.pointer_step { types.qualified(types.pointer_to(base), step.quals) }
		.array_step { types.array_of(base, if step.count > 0 { step.count } else { -1 }) }
		.function_step {
			types.function_type(base, type_params(step.params), step.variadic, step.prototyped)
		}
	}
}

// declared_type is the type a specifier and a declarator together name. The
// declarator's steps are applied in the order it wrote them: a pointer step is a
// pointer to what is under it, an array step is an array of it, and a function
// step is a function returning it. A pointer inside parentheses reverses the
// order of the two around it, which is the whole difference between `int *p[5]`
// and `int (*p)[5]`.
fn (p Parser) declared_type(base types.Type, d Declarator) types.Type {
	mut typ := base
	for step in d.steps {
		typ = apply_step(typ, step)
	}
	return typ
}

// parameter_spelling is the type a parameter was declared with, written the way
// it was written: the type words joined, and the storage class and qualifiers in
// front of them left out, since those are not the type. A name this file declared
// as a type is spelled as the type it names, so the message says which type has
// no form rather than which name the parameter used for it, which is the same
// answer a definition of an object gets.
fn (p Parser) parameter_spelling(spec DeclSpec) string {
	if spec.type_words.len == 1 {
		if spelling := p.alias_spelling(spec.type_words[0]) {
			return spelling
		}
	}
	if spec.type_words.len == 0 {
		return spec.words.join(' ')
	}
	return spec.type_words.join(' ')
}

// type_params is the parameters of a declarator as the type model wants them. The
// tree keeps a parameter with the type as it was written, because that is what a
// definition's frame is laid out from; the type keeps the one the model resolved.
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

// return_type is the type a function declarator returns: the base with every
// step but the name's own function suffix applied to it, since a function step
// says the name is a function rather than making another type. `int *f(void)`
// returns an int *.
fn (p Parser) return_type(base types.Type, d Declarator) types.Type {
	mut typ := base
	for i, step in d.steps {
		if i == d.steps.len - 1 && step.kind == .function_step {
			break
		}
		typ = apply_step(typ, step)
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
// its storage class and its scope give it. The name is recorded in the unit's
// own set of declared names as well, which is what the check at the end of the
// unit asks a name the tree carries against.
fn (mut p Parser) declare_name(name string, typ types.Type, at tokenize.Token, defined bool) {
	p.declared[name] = true
	previous := p.scopes.lookup(name)
	linkage := types.linkage_for(p.pending_storage, p.scopes.at_file_scope(), previous)
	// One name declared twice in one scope is one name (6.2.2), and the two
	// declarations have to describe compatible types (6.2.7): asked here of what
	// this declaration spells against what the scope already holds. Measured,
	// `void f1(int *p); void f1(char *p);` was accepted where gcc 16.2.1 refuses
	// `conflicting types for f1`; a declaration that repeats a type is one name and
	// not a conflict, `int f(int); int f(int) { return 0; }` included.
	if earlier := p.scopes.lookup_here(name) {
		if redeclaration_conflicts(earlier.typ, typ) {
			p.error_at(at, 'a constraint violation: ${name} is declared as ${earlier.typ.describe()} in this scope and this declaration gives it ${typ.describe()}, and two declarations of one name in one scope have to describe one type')
		}
	}
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

// redeclaration_conflicts says whether two declarations of one name in one scope
// describe two different things, which 6.2.7 refuses. Two types that are the same
// type are one thing and not a conflict, and two declarations of an object are one
// object. The one case the model's `same` cannot answer is 6.2.7p15: a function
// type written with an empty parameter list says nothing about its parameters
// rather than saying that there are none, so two function types one of which is
// written that way are compared by what they return.
//
// Measured, gcc 16.2.1 accepts `int f(void); int f();` and `int f(int a); int f();`
// under `-std=c99`, and refuses `int f(void); char f();`, which returns something
// else, and `int f(int a); int f(char b);`, whose parameter lists are both written
// and disagree.
fn redeclaration_conflicts(earlier types.Type, later types.Type) bool {
	if earlier.compatible(later) {
		return false
	}
	if earlier.is_function() && later.is_function() && !(earlier.prototyped && later.prototyped) {
		earlier_returns := earlier.returns() or { return true }
		later_returns := later.returns() or { return true }
		return !earlier_returns.compatible(later_returns)
	}
	return true
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
			// An ellipsis says there are arguments the list does not name, and
			// the tree records it: a definition with one is emitted with a save
			// area and an argument list the body can walk, and a prototype that
			// has one is a promise about the call rather than about the
			// definition.
			p.next()
			params.variadic = true
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
					typ:      p.spelling_of(spec, 0)
					resolved: spec.clause
					line:     spec.start.line
					col:      spec.start.col
				}
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			}
		} else {
			d := p.parse_declarator(depth + 1)!
			// A parameter declared with an array type has the array type
			// adjusted to a pointer to its element (C99 6.7.5.3p7): `int a[]`
			// and `int a[10]` are `int *`, `char *argv[]` is `char **`, and
			// `int a[3][4]` is a pointer to an array of four ints. The written
			// type gains the star the adjustment adds, which is the spelling a
			// parameter of the same pointer type written directly would carry;
			// the adjusted type the tree keeps is what the elements are read
			// through. The bound does not travel with the parameter: a size
			// or a variable length is not part of the pointer's type, so
			// `int f(int a[3])`, `int f(int a[n])` and `int f(int *a)` are
			// one function (6.7.5.3p15).
			stars := if d.is_array() { d.pointer_count() + 1 } else { d.pointer_count() }
			params.params << ast.Param{
				name:     d.name
				typ:      p.spelling_of(spec, stars)
				resolved: types.adjust_parameter(p.declared_type(spec.clause, d))
				line:     if d.name.len > 0 { d.name_at.line } else { spec.start.line }
				col:      if d.name.len > 0 { d.name_at.col } else { spec.start.col }
			}
			// The order of the questions is the order a reader asks them: what
			// keeps this parameter from being named at all, then the types the
			// emitter does. An array parameter is asked about its element, not
			// about the pointer it adjusts to. 6.7.5.2p1 makes a void element
			// and an incomplete element each a constraint violation, so
			// `void a[]` and `struct S a[]` with no body for S are refused
			// where `void *a` and `struct S *a` are not.
			if d.name.len == 0 {
				params.note_problem('unsupported: a parameter of a definition needs a name', spec.start)
			} else if d.is_array() && d.pointer_count() == 0 && spec.clause.kind == .void_ {
				params.note_problem('a constraint violation: ${d.name} is declared as an array of void, and 6.7.5.2p1 makes the element type of an array an object type', spec.start)
			} else if d.pointer_count() == 0 && spec.clause.kind == .long_double {
				// The type holds now, but a value of it is carried in the x87
				// stack, whose calling convention this compiler does not emit
				// yet, so an argument would be handed over in the wrong place.
				// An array of them adjusts to a pointer and is not asked this:
				// an address is what the call passes.
				params.note_problem('unsupported: long double is a type the x87 stack carries and this compiler has no calling convention for it yet, so a function cannot take one as a parameter', spec.start)
			} else if !p.parameter_type_is_known(spec, d.pointer_count()) {
				// The type as the parameter wrote it, so that `double _Complex`
				// and `long long` are named rather than a word of them.
				params.note_problem('unsupported type ${p.parameter_spelling(spec)}', spec.start)
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

// parameter_type_is_known says whether a parameter's type is one this reader can
// name: a word of the language, or a single name this file declared as a type,
// which answers as the type it names.
//
// The question is asked of the spelling, which for a declaration written through
// `typeof` is the type the reader resolved rather than the words the file wrote:
// `int f(typeof(x) v)` is a parameter of the type x has, and asking about the
// word `typeof` would refuse a parameter whose type this compiler knows.
//
// A parameter of the 128-bit type is asked about the type the model resolved
// rather than about the word, because that type has a width and the model is
// where the width is: the spelling joins two words, and `unsigned __int128` is
// not a word this reader has.
fn (p Parser) parameter_type_is_known(spec DeclSpec, stars int) bool {
	// An object of an aggregate type is one a definition can be handed by value:
	// the layout says how many bytes it is and what class its first eightbyte
	// has, which is what the caller and the callee each have to agree on. A tag
	// with no body has neither, so it is not one. A pointer to such a tag is
	// still a parameter this reader can name: the parameter is one address
	// whatever the tag turns out to be, which is the same answer a declaration
	// of a pointer to the tag gets.
	if spec.clause.kind in [types.Kind.struct_, .union_] {
		if stars > 0 {
			return true
		}
		return spec.clause.is_complete() && p.representation.layout(spec.clause) != none
	}
	// A 128-bit integer is a type the model knows the width of, sixteen bytes,
	// so a parameter declared with one is a parameter whose type this reader can
	// name. The questions about handing a value of that width over are the
	// emitter's, and it answers them by name, which is the same split a
	// declaration of an object of the type already has.
	if spec.clause.kind in [types.Kind.int128, .unsigned_int128] {
		return true
	}
	return p.word_problem(p.parameter_spelling(spec)) == none
}

fn (mut params Params) note_problem(problem string, at tokenize.Token) {
	if params.problem.len == 0 {
		params.problem = problem
		params.at = at
	}
}

// unreadable_bound is what a declarator step carries for a bound that was
// written in the brackets and is not an integer constant expression this reader
// evaluated. It is negative, so a step whose bound was a size stays positive and
// a pair of empty brackets stays zero; array_sized says which of those a zero
// was. The value says which of the two kinds of unread step happened, because
// the question differs by context: a body's bound that is not constant is a
// variable-length array this compiler does not implement, and a file-scope
// object's is a constraint violation, while a struct member's is a member that
// still compiles.
const unreadable_bound = -1

// ArrayBound is what one pair of brackets said about an array's size. The four
// answers are kept apart because a caller has to tell them apart: an initializer
// may give a size to empty brackets and to nothing else, and a bound that was
// written and read as no positive size is a different thing from one this
// reader could not evaluate at all.
enum ArrayBound {
	// empty is a pair of brackets with nothing between them: `int a[]`. An
	// initializer may be what gives the array its size.
	empty
	// held is a bound this reader evaluated to a positive size.
	held
	// unheld is a bound that was written and evaluated to something that is
	// not a size: `int a[0]`, `int a[2 - 5]`. A negative one is reported where
	// it is read and reaches the caller as this same case.
	unheld
	// unreadable is a bound that was written and this reader could not
	// evaluate, as in `int a[n]` where n is a name.
	unreadable
}

// ArraySuffix is what one pair of brackets answered: which of the four shapes it
// was, and the size when it read one. The kind beside the size is what keeps the
// two distinctions a caller needs in one answer: empty brackets may take a size
// from an initializer, and any bound that was written may not, whether it read
// as a size or not.
struct ArraySuffix {
	bound ArrayBound
	count i64
}

// count_as_step is the size a declarator step carries for this suffix: the size
// when one was read, zero when the brackets wrote no size or one that did not
// read as a size, and unreadable_bound when a bound was written and could not be
// evaluated at all.
fn (s ArraySuffix) count_as_step() int {
	if s.bound == .unreadable {
		return unreadable_bound
	}
	return int(s.count)
}

// array_takes_string says whether a string literal initializes the array a
// declarator declared: an array of character type by an ordinary literal and an
// array of this target's wchar_t, an int, by a wide one. Measured on gcc 16.2.1,
// `signed char a[] = "x"` and `unsigned char a[] = "x"` are accepted while
// `int a[] = "x"` and `unsigned int a[] = L"x"` are not, so the element type has
// to be the literal's own.
fn array_takes_string(d Declarator, declared types.Type, literal ast.StrLit) bool {
	if !d.is_array() {
		return false
	}
	element := declared.element() or { return false }
	return element_takes_literal(element, literal.unit)
}

// element_takes_literal is the element type a string literal of this width
// initializes: an ordinary literal an array of character type - char, signed
// char or unsigned char - and a wide one an array of wchar_t, which this target
// gives as an int.
fn element_takes_literal(element types.Type, unit int) bool {
	if unit == 4 {
		return element.kind == .int_
	}
	return element.kind in [.char_, .signed_char, .unsigned_char]
}

// read_array_string_literal reads the string literal at the cursor as one object:
// a run of adjacent literals is one literal (6.4.5p5), which is what
// `char s[] = "one" "two";` relies on. Every piece has to be of the literal's own
// width, and a piece that cannot be read is named where it is written and answers
// none.
fn (mut p Parser) read_array_string_literal() ?ast.StrLit {
	token := p.next()
	first := parse_string_literal(token.text) or {
		p.error_at(token, err.msg())
		return none
	}
	mut value := first.value
	mut characters := first.count
	for p.peek().kind == .string {
		next := p.next()
		piece := parse_string_literal(next.text) or {
			p.error_at(next, err.msg())
			return none
		}
		if piece.unit != first.unit {
			p.error_at(next, 'unsupported: adjacent string literals of different widths, ${token.text} and ${next.text}')
			return none
		}
		value += piece.value
		characters += piece.count
	}
	return ast.StrLit{
		value: value
		text:  token.text
		unit:  first.unit
		typ:   string_literal_type(token.text, StringLiteral{
			value: value
			unit:  first.unit
			count: characters
		})
		line:  token.line
		col:   token.col
	}
}

// string_elements is the elements a string literal writes into an array: one per
// character, and the terminator the literal does not write as the last of them. A
// wide literal's value holds four little-endian bytes a character and a narrow
// one's holds one byte a character, so how a character is read off the literal is
// what its unit says.
fn string_elements(literal ast.StrLit) []i64 {
	mut values := []i64{}
	if literal.unit == 4 {
		mut i := 0
		for i + 3 < literal.value.len {
			mut value := u64(0)
			for k in 0 .. 4 {
				value |= u64(literal.value[i + k]) << (8 * k)
			}
			values << i64(value)
			i += 4
		}
	} else {
		for byte in literal.value.bytes() {
			values << i64(byte)
		}
	}
	values << 0
	return values
}

// string_elements_at is the elements string_elements answers, written as the
// integer constants a brace list writes, at the position of the declaration that
// holds them. A literal and a list then reach the back end as one thing.
fn string_elements_at(literal ast.StrLit, at tokenize.Token) []ast.Expr {
	mut elements := []ast.Expr{}
	for value in string_elements(literal) {
		elements << ast.Expr(ast.IntLit{
			value: value
			text:  '${value}'
			typ:   types.int_type()
			line:  at.line
			col:   at.col
		})
	}
	return elements
}

// ArrayString is what a string literal that initializes a file-scope array
// writes: the element constants, how many elements the array turned out to have,
// and the type the name is completed with. ok is false when the literal or its
// size was refused, and the declaration is then not laid out.
struct ArrayString {
	inits    []i64
	count    int
	complete types.Type
	ok       bool
}

// file_scope_string_initializer reads the string literal that initializes a
// file-scope array and answers the elements it writes. 6.7.8p14 lets an array of
// character type be initialized by a string literal: each character initializes
// one element, and the terminating zero the literal does not write is an element
// when the array has room for it.
//
// An array whose brackets wrote no size is exactly the literal including its
// terminator. A written bound is used instead, and a literal too long for it is
// the constraint violation gcc 16.2.1 refuses as `initializer-string for array of
// 'char' is too long`: `char s[2] = "abc";` holds two and writes four, and
// `char s[0] = "abc";` is the same refusal into none, because a bound was written
// and the size is not taken from the literal. A bound exactly the characters
// keeps no terminating zero, which gcc accepts and this accepts too.
fn (mut p Parser) file_scope_string_initializer(d Declarator, declared types.Type,
	name string, literal ast.StrLit) ArrayString {
	values := string_elements(literal)
	characters := values.len - 1
	element := declared.element() or { declared }
	if d.array_sized() {
		written := d.array_count()
		if written < characters {
			p.error_span(literal.line, literal.col, 'a constraint violation: ${name} holds ${written} elements and its initializer writes ${values.len} characters')
			return ArrayString{}
		}
		limit := if written < values.len { written } else { values.len }
		return ArrayString{
			inits:    values[..limit]
			count:    written
			complete: types.array_of(element, written)
			ok:       true
		}
	}
	return ArrayString{
		inits:    values
		count:    values.len
		complete: types.array_of(element, values.len)
		ok:       true
	}
}

// parse_array_suffix reads `[ ... ]`. A bound written in the brackets is an
// integer constant expression and its value is what the array's type is built
// from, so it is evaluated here rather than scanned past. `sizeof` is an
// operator the expression reader already turns into the number it names, so a
// real header's bound reaches this reader as arithmetic over constants:
// `char _unused2[12 * sizeof (int) - 5 * sizeof (void *)]` is worth 8.
//
// A pair of empty brackets answers `.empty` without parsing anything, which is
// what tells it from a bound that was written; a bound that evaluated to
// something that is not a positive size answers `.unheld`, and one this reader
// could not evaluate answers `.unreadable`. A region that does not evaluate is
// skipped to its bracket as it always was, so the suffix still ends where it
// says it ends.
//
// A written bound that is negative is a constraint violation (6.7.5.2p1) and is
// reported here, where the value is known, rather than left to a reader that
// would only see that no positive size was read. Measured on gcc 16.2.1,
// `int x[2 - 5];`, `int x[-1];` and `int x[~0];` are all `size of array 'x' is
// negative` and rejected under `-std=gnu99` and under `-std=c99
// -pedantic-errors`, as a file-scope object, a struct member or a parameter.
// Zero is not that case: `int x[0];` is a zero-size array, which gcc accepts
// under `-std=gnu99`, and empty brackets are a size the initializer may give.
fn (mut p Parser) parse_array_suffix(name string) !ArraySuffix {
	open := p.next() // [
	p.bound_name = ''
	p.bound_name_line = 0
	p.bound_name_col = 0
	if p.at_punct(']') {
		p.next()
		return ArraySuffix{
			bound: .empty
		}
	}
	bound_at := p.peek()
	// The bound is read as an expression so that it can be evaluated. Nothing the
	// trial read is kept if it does not end at the bracket: the cursor, the
	// diagnostics it produced, the depth it counted and the type the declarator
	// is being built from are all restored, and the region is skipped instead.
	saved_pos := p.pos
	saved_diagnostics := p.diagnostics.len
	saved_depth := p.depth
	saved_base := p.pending_base
	saved_storage := p.pending_storage
	mut read := ?ast.Expr(none)
	if expr := p.parse_expression() {
		read = expr
	}
	p.depth = saved_depth
	p.pending_base = saved_base
	p.pending_storage = saved_storage
	if expr := read {
		if p.at_punct(']') {
			p.next()
			value := p.constant_value(expr) or {
				// A bound that did not fold may name something this scope does not
				// have. That name is kept so the file-scope report can tell a
				// bound that is not a constant expression from one whose operand
				// is declared nowhere, which is a different failure and a
				// different message. Whether the name is declared anywhere is a
				// question only the end of the file can answer, so the report
				// waits; see `pending_bounds`.
				if ident := p.unresolved_name(expr) {
					p.bound_name = ident.name
					p.bound_name_line = ident.line
					p.bound_name_col = ident.col
				}
				return ArraySuffix{
					bound: .unreadable
				}
			}
			if value > 0 {
				return ArraySuffix{
					bound: .held
					count: value
				}
			}
			if value < 0 {
				who := if name.len > 0 { name } else { 'an array' }
				p.error_span(bound_at.line, bound_at.col, 'a constraint violation: the bound of ${who} is ${value}, and 6.7.5.2p1 makes a size that was written one that is not negative')
			}
			// A size written and not held — `int a[0]`, `int a[2 - 5]` —
			// reads as no size at all, and the reader that asked for one says
			// so. It was written, though, so it is not a pair a size may be
			// taken for from an initializer.
			return ArraySuffix{
				bound: .unheld
			}
		}
	}
	p.pos = saved_pos
	p.diagnostics = p.diagnostics[..saved_diagnostics]
	p.skip_balanced(open)!
	return ArraySuffix{
		bound: .unreadable
	}
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
	p.declared[name] = true
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
