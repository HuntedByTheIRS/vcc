module preprocess

import backend
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
			name:   definition.name
			params: definition.params
			body:   tokenize.lex_fragment(definition.body)
			file:   '<built-in>'
			line:   1
			col:    1
		}
	}
}

// dynamic_builtin answers the macros whose value depends on where they are
// used rather than on what the compiler knows: __LINE__ is the line it was
// written on, and __FILE__ is the file it was written in. A name that a
// program defined itself is not one of these — the macro table is asked first
// — because a program that defines them is on its own either way.
fn (p Processor) dynamic_builtin(tok tokenize.Token) ?[]tokenize.Token {
	where := if p.frames.len > 0 { p.frames.last().path } else { tok.file }
	match tok.text {
		'__LINE__' {
			return [
				tokenize.Token{
					kind: .number
					text: '${tok.line}'
					line: tok.line
					col:  tok.col
					file: tok.file
				},
			]
		}
		'__FILE__' {
			return [
				tokenize.Token{
					kind: .string
					text: '"${where}"'
					line: tok.line
					col:  tok.col
					file: tok.file
				},
			]
		}
		'__BASE_FILE__' {
			return [
				tokenize.Token{
					kind: .string
					text: '"${p.main_path}"'
					line: tok.line
					col:  tok.col
					file: tok.file
				},
			]
		}
		else {
			return none
		}
	}
}
