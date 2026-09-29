module preprocess

import backend
import os
import time
import tokenize

// A C compiler defines a set of macros before it reads a single line of the
// program, because the headers it is about to read ask about the machine they
// are being read on: which type size_t is, how wide a pointer is, which
// standard the language is, which endianness the bytes are in.
//
// They are defined by the command line before the file and can be taken away
// by it, which is the order C puts every macro in: a -D of one of these names
// wins over the built-in value, and an #undef takes one away.
//
// The values are the ones the compiler being replaced predefines for this
// target, which is also what the headers expect to be told. A compiler that
// predefines nothing still gets a working set of headers — gcc's own headers
// carry fallbacks for every name here — but it gets the fallbacks, spelled the
// way the fallbacks spell them, and a libc header that branches on a macro
// nobody defined takes a path nobody tested.

// Definition is one predefined macro: a name, the parameters it takes if it is
// function-like, and what it stands for.
struct Definition {
	name   string
	params []string
	body   string
}

// builtins are the macros that describe the target.
fn builtins(target backend.Target) []Definition {
	mut definitions := []Definition{}
	if target.arch == 'x86_64' {
		definitions << Definition{'__x86_64__', [], '1'}
		definitions << Definition{'__x86_64', [], '1'}
		definitions << Definition{'__amd64__', [], '1'}
		definitions << Definition{'__LP64__', [], '1'}
		definitions << Definition{'__SIZEOF_POINTER__', [], '8'}
		definitions << Definition{'__SIZEOF_LONG__', [], '8'}
		definitions << Definition{'__SIZEOF_LONG_LONG__', [], '8'}
		definitions << Definition{'__SIZEOF_INT__', [], '4'}
		definitions << Definition{'__CHAR_BIT__', [], '8'}
		definitions << Definition{'__SIZE_TYPE__', [], 'unsigned long'}
		definitions << Definition{'__PTRDIFF_TYPE__', [], 'long'}
		definitions << Definition{'__INTPTR_TYPE__', [], '__PTRDIFF_TYPE__'}
		definitions << Definition{'__UINTPTR_TYPE__', [], 'unsigned __PTRDIFF_TYPE__'}
		definitions << Definition{'__INT32_TYPE__', [], 'int'}
		definitions << Definition{'__INT64_TYPE__', [], 'long'}
		definitions << Definition{'__WCHAR_TYPE__', [], 'int'}
		definitions << Definition{'__WINT_TYPE__', [], 'unsigned int'}
		definitions << Definition{'__INT_MAX__', [], '0x7fffffff'}
		definitions << Definition{'__LONG_MAX__', [], '0x7fffffffffffffffL'}
		definitions << Definition{'__LONG_LONG_MAX__', [], '0x7fffffffffffffffLL'}
	}
	if target.os == 'linux' {
		definitions << Definition{'__linux__', [], '1'}
		definitions << Definition{'__linux', [], '1'}
		definitions << Definition{'__gnu_linux__', [], '1'}
		definitions << Definition{'__unix__', [], '1'}
		definitions << Definition{'__unix', [], '1'}
		definitions << Definition{'__ELF__', [], '1'}
	}
	definitions << Definition{'__ORDER_LITTLE_ENDIAN__', [], '1234'}
	definitions << Definition{'__ORDER_BIG_ENDIAN__', [], '4321'}
	definitions << Definition{'__BYTE_ORDER__', [], '__ORDER_LITTLE_ENDIAN__'}
	definitions << Definition{'__STDC__', [], '1'}
	definitions << Definition{'__STDC_HOSTED__', [], '1'}
	definitions << Definition{'__STDC_VERSION__', [], '199901L'}
	// The __has_ macros are how a header asks whether a construct exists.
	// Answering 0 is a compiler saying it knows none of the things they ask
	// about, which is true, and is what keeps a header on the paths that use
	// the C the compiler does know.
	definitions << Definition{'__has_attribute', ['x'], '0'}
	definitions << Definition{'__has_builtin', ['x'], '0'}
	definitions << Definition{'__has_feature', ['x'], '0'}
	return definitions
}

// define_builtins puts them in the macro table, before anything else is read.
fn (mut p Processor) define_builtins() {
	target := backend.host() or { return }
	for definition in builtins(target) {
		p.macros[definition.name] = Macro{
			name:          definition.name
			function_like: definition.params.len > 0
			params:        definition.params
			body:          tokenize.lex_fragment(definition.body)
			file:          '<built-in>'
			line:          1
			col:           1
		}
	}
}

// dynamic_builtin answers the macros whose value depends on where they are used
// rather than on what the compiler knows: __LINE__ is the line it was written
// on, __FILE__ is the file it was written in, and __COUNTER__ is how many times
// it has been asked. A name that a program defined itself is not one of these —
// the macro table is asked first — because a program that defines them is on its
// own either way.
fn (mut p Processor) dynamic_builtin(tok tokenize.Token) ?[]tokenize.Token {
	match tok.text {
		'__LINE__' {
			return [number_token('${tok.line}', tok)]
		}
		'__FILE__' {
			return [string_token('"${p.file_name(tok)}"', tok)]
		}
		'__BASE_FILE__' {
			return [string_token('"${p.main_path}"', tok)]
		}
		'__COUNTER__' {
			// The first use is 0 and every use after it is one more. That is
			// what makes it a way to build a name that is different each time
			// the same header is read, which is the whole of what it is for.
			value := p.counter
			p.counter++
			return [number_token('${value}', tok)]
		}
		'__INCLUDE_LEVEL__' {
			// How deep in the includes this use is: 0 in the file the compiler
			// was handed, 1 in a file it includes, and so on.
			return [number_token('${p.frames.len - 1}', tok)]
		}
		'__DATE__' {
			return [string_token(date_text(time.now()), tok)]
		}
		'__TIME__' {
			return [string_token(time_text(time.now()), tok)]
		}
		'__TIMESTAMP__' {
			return [string_token(timestamp_text(written_at(p.file_name(tok))), tok)]
		}
		else {
			return none
		}
	}
}

// number_token and string_token are the two shapes a macro like this can have:
// they are written where the use was written, so a diagnostic about one of them
// points at the line that asked for it.
fn number_token(text string, tok tokenize.Token) tokenize.Token {
	return tokenize.Token{
		kind: .number
		text: text
		line: tok.line
		col:  tok.col
		file: tok.file
	}
}

fn string_token(text string, tok tokenize.Token) tokenize.Token {
	return tokenize.Token{
		kind: .string
		text: text
		line: tok.line
		col:  tok.col
		file: tok.file
	}
}

// The three macros that are about the clock are written the way C writes them,
// which is the only reason these are functions and not a line each: a program
// that parses `__DATE__` is parsing the shape, and the shape is fixed.
//
// C pads the day to two characters with a space and not with a zero, so the
// zero a formatter would write has to come back out.
fn date_text(t time.Time) string {
	return '"${t.custom_format('MMM DD YYYY').replace(' 0', '  ')}"'
}

fn time_text(t time.Time) string {
	return '"${t.custom_format('HH:mm:ss')}"'
}

fn timestamp_text(t time.Time) string {
	return '"${t.custom_format('ddd MMM DD HH:mm:ss YYYY').replace(' 0', '  ')}"'
}

// written_at is when the file being read was last written — which is what
// __TIMESTAMP__ is for, telling one build's output from another's. A file that
// cannot be looked up has no time of its own, and the clock is the only other
// answer there is.
fn written_at(path string) time.Time {
	stamp := os.file_last_mod_unix(path)
	if stamp <= 0 {
		return time.now()
	}
	return time.unix(stamp)
}

// has_names are the macros that ask a compiler about itself. __has_include asks
// about the machine — whether a header is there to be read — and the rest ask
// what this compiler can be told: it honors no attributes, offers no builtins of
// its own and has no extensions, and 0 is the answer that sends a header down
// the fallback path it wrote for compilers like this one. A 1 would promise a
// block that this compiler cannot compile.
const has_names = ['__has_include', '__has_attribute', '__has_builtin', '__has_feature',
	'__has_extension', '__has_c_attribute', '__has_declspec_attribute']

// parenthesised reads the tokens of a parenthesised argument, starting at the
// opening bracket, and says where the tokens after the closing one begin. A
// bracket that is never closed is -1, which is the caller's to report.
fn parenthesised(tokens []tokenize.Token, start int) ([]tokenize.Token, int) {
	mut depth := 0
	mut inside := []tokenize.Token{}
	mut i := start
	for i < tokens.len {
		t := tokens[i]
		if t.kind == .punct && (t.text == '(' || t.text == ')') {
			if t.text == '(' {
				depth++
				// The bracket the argument opens with is not part of the
				// argument: what the caller wants is what is between them.
				if depth > 1 {
					inside << t
				}
			} else {
				depth--
				if depth == 0 {
					return inside, i + 1
				}
				inside << t
			}
			i++
			continue
		}
		inside << t
		i++
	}
	return []tokenize.Token{}, -1
}

// asks_about_itself answers one of the has_names macros, in the shape the caller
// writes into the stream: '1' or '0'.
fn (mut p Processor) asks_about_itself(tok tokenize.Token, argument []tokenize.Token) string {
	if tok.text != '__has_include' {
		// Nothing here is honored, and the argument is not looked at: asking
		// what a compiler supports is how a header protects itself, and the
		// question has an answer whether or not the name is spelled right.
		return '0'
	}
	if argument.len == 0 {
		p.problem(tok, '__has_include( wants a "file" or a <file>')
		return '0'
	}
	mut name := ''
	mut angled := false
	if argument[0].kind == .string {
		name = unquoted_name(argument[0].text)
	} else if argument[0].kind == .punct && argument[0].text == '<' {
		angled = true
		// The characters between the brackets are the name of the file, and the
		// lexer read them as several tokens: `bits/types.h` is a name, a slash,
		// a name and a dot.
		mut i := 1
		for i < argument.len && !(argument[i].kind == .punct && argument[i].text == '>') {
			name += argument[i].text
			i++
		}
		if i >= argument.len {
			p.problem(tok, '__has_include has a < with no >')
			return '0'
		}
	} else {
		p.problem(tok, '__has_include wants a "file" or a <file>, not ${argument[0].text}')
		return '0'
	}
	if name == '' {
		return '0'
	}
	// The search is the one #include would do, from the file that asked, and the
	// file is not read: the question is whether it is there.
	_ := p.find_include(name, angled, p.frames.last().path, false) or { return '0' }
	return '1'
}
