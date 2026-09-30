module standard

import tokenize

// Status says what this compiler does with a construct today.
pub enum Status {
	// implemented: the tree reads the construct, and the dialect check is what
	// says whether the selected mode allows it.
	implemented
	// unimplemented: the tree does not read the construct yet. A program that
	// writes one is refused by the stage that meets it, with a diagnostic that
	// names the construct and its location, and that refusal is the whole
	// answer until the construct lands: a pedantic message about something the
	// compiler will not compile anyway would be noise on top of it.
	unimplemented
}

// Feature is one row of the dialect table: a construct, the standard it is part
// of, and what this compiler does with it.
//
// A row is data and not a branch. The dialect check reads the rows, so a
// construct the compiler gains is a row that changes status and not a new clause
// somewhere in the check, and a construct a -fvcc-exts= extension brings down to
// an earlier mode is a name in the extension column.
pub struct Feature {
pub:
	// spellings are the token texts that mark the construct in a token stream.
	// A construct no single token marks has none, and the lane that implements
	// it brings the detection with it.
	spellings []string
	// since is the mode the construct first became standard in. `.none` says
	// no ISO mode has it: the spelling is a GNU extension, which a GNU dialect
	// takes and a strict one does not.
	since Mode
	// gnu says the spelling is a GNU extension, which is what keeps it out of
	// a strict mode even where the standard's row includes it.
	gnu bool
	// extension is the name of the -fvcc-exts= extension that brings the
	// construct down to a mode before `since`, when there is one. Nothing is
	// brought down yet: the flag parses the names and honors none of them, so
	// every row here is empty.
	extension string
	// pedantic is the phrase a pedantic message is built from: the name of the
	// standard the selected mode asks about, the word `forbids`, and this.
	pedantic string
	// status is what the tree does with the construct today.
	status Status
}

// features is the table, one row per construct: what the standards say about it
// and what this compiler does with it.
//
// It carries the constructs this milestone can act on and the ones the C99 work
// is aimed at, so that the table describes the language rather than only the
// part of it that happened to be built first. The rows that are not implemented
// yet are read by nothing; the day one lands, its row changes status, gains its
// spellings and starts being checked.
pub const features = [
	// An attribute can be written before the declaration
	// (`__attribute__((unused)) int f(void);`), between the specifiers and the
	// declarator, and after the declarator
	// (`int f(void) __attribute__((unused));`). The check finds the spelling by
	// token text and cannot tell the positions apart, so the phrase is the one
	// true of all of them and names no position at all. The tree reads the
	// postfix position only (`parser/declarations.v`), and the prefix one is
	// refused by the parser on its own account. gcc 16.2.1 says nothing about
	// any of the positions under `-std=c99 -pedantic-errors`, measured.
	Feature{
		spellings: ['__attribute__']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'an attribute'
		status:    .implemented
	},
	// The asm row's phrase has to be true of both constructs the spelling
	// marks, because the check finds a row by token text and cannot tell them
	// apart: a statement-level `__asm__ volatile ("" : "+r"(x));` is an asm
	// statement, and `int g(void) __asm__("g_alias");` is an assembler name on
	// a declarator. gcc 16.2.1 has no wording to borrow for either shape: it
	// exits 0 with empty stderr on both of them under `-std=c99 -pedantic` and
	// under `-std=c99 -pedantic-errors`, and its C front end carries no such
	// message at all, because the double-underscore spelling is in the
	// reserved namespace and needs no extension. So the phrase names the two
	// shapes instead of borrowing the name of one of them.
	Feature{
		spellings: ['__asm__', '__asm']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'an asm statement or an assembler name on a declarator'
		status:    .implemented
	},
	Feature{
		spellings: []
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'braced-groups within expressions'
		status:    .unimplemented
	},
	Feature{
		spellings: ['typeof', '__typeof__', '__typeof']
		since:     .c23
		gnu:       true
		extension: ''
		pedantic:  'the typeof specifier'
		status:    .implemented
	},
	Feature{
		spellings: []
		since:     .c23
		gnu:       false
		extension: ''
		pedantic:  'the auto type specifier'
		status:    .unimplemented
	},
	Feature{
		spellings: ['_Generic']
		since:     .c11
		gnu:       false
		extension: ''
		pedantic:  'the _Generic selection'
		status:    .unimplemented
	},
	// _Static_assert stays unimplemented because the tree does not read a
	// static assertion, and measured, the two positions it can be written in
	// are not one answer. At file scope the parser refuses it and names it
	// (`unsupported: expected a declaration, found '_Static_assert'`), which is
	// the unimplemented rule. Inside a function body the statement path reads
	// the token as the start of an expression, so `_Static_assert(1, "x");`
	// compiles and becomes a call to a symbol that was never defined, which is
	// the parser's defect — recorded for the milestone that owns statement
	// parsing — and is not a reading this row may claim. The day the parser
	// reads a static assertion, this row changes status and starts being
	// checked; the phrase below is already what that message needs.
	Feature{
		spellings: ['_Static_assert']
		since:     .c11
		gnu:       false
		extension: ''
		pedantic:  'the _Static_assert declaration'
		status:    .unimplemented
	},
	// The C99 types the type model resolves and the back end has no form for.
	// The tree reads each of them, so a prototype naming one is read and kept;
	// a definition is storage, and a definition of one is refused by location.
	// The two complex types stay `.unimplemented` because C6's last tier is
	// where their arithmetic lands, and the floats and `_Bool` say
	// `.implemented` because the tree does read them and the refusal is the back
	// end's rather than the reader's.
	//
	// Which name that refusal uses depends on the path, and the difference is
	// recorded rather than smoothed over. A function return type is the one path
	// that names the type in full, because the answer is about the construct and
	// not about a word of it: measured, `long double f(void) { return 0; }` and
	// `double _Complex f(void) { return 0; }` report `unsupported: <type> is a
	// type this compiler does not emit yet, so a function cannot return it`.
	// Everywhere else the answer is the first word of the type as written, which
	// is the word the emitter stopped at: measured, `long long x;` reports
	// `unsupported type long`, `unsigned long long x;` reports `unsupported type
	// unsigned`, and `double _Complex z = 0;` in a body reports `unsupported type
	// double`. A definition's parameter list names what the parameter was
	// declared with, so `int h(double _Complex z) { return 0; }` reports
	// `unsupported type double _Complex`; the same list in a prototype is a
	// promise and is kept.
	//
	// `long long` and `long double` have no row, and cannot have one: a row is
	// found by the text of a single token, and both are written as two tokens
	// whose first is `long`.
	Feature{
		spellings: ['_Bool']
		since:     .c99
		gnu:       false
		extension: ''
		pedantic:  'the _Bool type'
		status:    .implemented
	},
	Feature{
		spellings: ['float']
		since:     .c89
		gnu:       false
		extension: ''
		pedantic:  'the float type'
		status:    .implemented
	},
	Feature{
		spellings: ['double']
		since:     .c89
		gnu:       false
		extension: ''
		pedantic:  'the double type'
		status:    .implemented
	},
	// The 128-bit integer is gcc's and no standard has it: `__int128` and the
	// unsigned type `unsigned __int128` names, written with one token the check
	// can find the row by. A GNU dialect takes it, and a strict mode reports it.
	// Measured on gcc 16.2.1: `-std=c99 -pedantic` warns `ISO C does not support
	// '__int128' types`, `-std=c99 -pedantic-errors` makes that warning an
	// error, `-std=c23 -pedantic-errors` says the same thing because C23 does
	// not have the type either, and `-std=gnu99` says nothing at all. The tree
	// reads the type wherever a type can be written, the model sizes it and lays
	// it out, which is what makes `sizeof(__int128)` 16, and an object of one is
	// storage this back end has: sixteen bytes that are declared, given a value
	// narrower than them, copied and addressed, at the top level, as a local and
	// as a top-level object, as a member of an object and as an element of an array of
	// them, where the element
	// is written as the two words an object takes and read by a conversion at its own
	// address, and an element taken as a *value* is refused by name. Reading one is written as a conversion to a
	// narrower type or into a narrower slot, which is its low word: measured on gcc
	// 16.2.1, `(int)` of a stored 300 is 300, `(char)` of one is 44, `(int)` of a
	// stored -1 is -1, and an int declared from a stored 300 is 300.
	// What is missing is a *value* of that width, so a parameter of the type and
	// an implicit narrowing store are refused by name: `int f(__int128 v) { return
	// 0; }` reports `unsupported type __int128`, and `__int128 v = 5; int n = v;`
	// reports that the object has no value of that width to read (`int n = a;` is
	// that same read, and takes the low word). A conversion of
	// an object to a double is refused too, since a double of that value is a
	// rounding of the whole of it and not its low word, while a prototype naming
	// the type is a promise and is kept.
	Feature{
		spellings: ['__int128']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'the __int128 type'
		status:    .implemented
	},
	Feature{
		spellings: ['_Complex']
		since:     .c99
		gnu:       false
		extension: ''
		pedantic:  'the _Complex type'
		status:    .unimplemented
	},
	Feature{
		spellings: ['_Imaginary']
		since:     .c99
		gnu:       false
		extension: ''
		pedantic:  'the _Imaginary type'
		status:    .unimplemented
	},
	// sizeof is an operator, and the tree does not read it: the spelling in a
	// program was read as a call to a function of that name, so
	// `int main(void) { int a[4]; return sizeof(a); }` compiled into a binary
	// that died at load with `undefined symbol: sizeof`. The parser refuses the
	// spelling by name and location now, which is the refusal the unimplemented
	// rule asks for, and the row records that the operator is C89 and is not
	// read yet. Implementing it is the milestone that owns the operator.
	Feature{
		spellings: ['sizeof']
		since:     .c89
		gnu:       false
		extension: ''
		pedantic:  'the sizeof operator'
		status:    .unimplemented
	},
]

// replaces_trigraphs answers phase 1's question for the selected mode: whether a
// `??x` is replaced by the one character it names, on the raw bytes and before
// anything reads the text.
//
// Measured on gcc 16.2.1, one mode at a time over
// `int main(void) { return 0 ??!??! 0; }`:
//
//   -std=c89, -std=c99, -std=c11, -std=c17   rc 0: the line is `0 || 0`
//   -std=gnu89 … -std=gnu23, -std=c23        rc 1: `trigraph '??!' ignored, use
//                                            '-trigraphs' to enable`, and the
//                                            bytes are the program's
//   no -std at all                           rc 1, the same: gcc's own default
//                                            is a GNU dialect
//
// A `-std=` spelling this compiler does not implement is recorded and refused
// nothing, and it takes the default dialect's answer, which is gnu-like: a
// trigraph is not replaced there either. So: replaced in the strict ISO modes up
// to C17, left alone everywhere else.
//
// Trigraphs are the one construct the table above cannot carry, and this
// function is why. A row is found by the exact text of one token (see `uses`
// below) and phase 1 runs before a token exists: in a mode that replaces, a
// `??!` is `|` by the time a token is read, and in a mode that leaves the bytes
// alone the three characters reach the stream as three punctuators — `?`, `?`,
// `!` — and no one of them is the construct. So a row for it could never be
// found, and `standard_test.v` asks of every `implemented` row that it carry a
// spelling, which leaves a row here either breaking that test or claiming a
// detection this table does not have. The answer is a function and the record is
// this comment, the same shape as the `$` row the table is still missing.
//
// Two things gcc has are not built here, and are recorded rather than promised:
// `-trigraphs`, which turns replacement back on in a dialect that leaves it off
// (measured: `gcc -std=gnu99 -trigraphs` replaces, rc 0), and the
// `trigraph '??!' ignored, use '-trigraphs' to enable` warning, which is why a
// GNU-mode program that writes `??!` hears nothing about it here. Both are open
// items.
pub fn replaces_trigraphs(mode Mode) bool {
	return match mode {
		.c89, .c99, .c11, .c17 { true }
		.none, .c23, .gnu89, .gnu99, .gnu11, .gnu17, .gnu23, .other { false }
	}
}

// Question is what a dialect check is asked under: the mode the command line
// named, the extensions -fvcc-exts= turned on, and the files the check stays out
// of.
//
// System headers are in that last set because nobody in the build wrote them and
// nobody in the build can fix them: a construct a header uses to describe itself
// is not a statement about the program being compiled. gcc reports nothing
// inside them, and a compiler that did would greet a program including one
// header with messages about the header.
pub struct Question {
pub mut:
	mode         Mode
	extensions   []string
	system_files map[string]bool
}

// pedantic_messages reads a token stream and answers with one diagnostic per use
// of a construct the selected mode does not allow.
//
// It refuses nothing. A pedantic message is a warning, and what the command line
// does with one is the policy's business: reported by -Wpedantic, promoted to an
// error by -pedantic-errors or -Werror=pedantic, silenced by -w or -Wno-pedantic,
// and nothing at all by default.
pub fn pedantic_messages(tokens []tokenize.Token, question Question) []tokenize.Diagnostic {
	if question.mode == .none || question.mode == .other {
		return []
	}
	return uses(tokens, features, question)
}

// uses is the walk itself, over a table the caller hands in rather than over the
// table above, which is how the rule an extension follows is checked before
// there is an extension to check it with: the tests bring a table of their own.
fn uses(tokens []tokenize.Token, table []Feature, question Question) []tokenize.Diagnostic {
	mut out := []tokenize.Diagnostic{}
	for token in tokens {
		for feature in table {
			if feature.status == .unimplemented {
				continue
			}
			if !feature.spellings.contains(token.text) {
				continue
			}
			if allowed(feature, question) {
				continue
			}
			if question.system_files[token.file] {
				continue
			}
			out << tokenize.Diagnostic{
				line:    token.line
				col:     token.col
				msg:     '${question.mode.standard_name()} forbids ${feature.pedantic}'
				file:    token.file
				warning: true
				class:   .pedantic
			}
		}
	}
	return out
}

// allowed says whether the selected mode takes the construct in: it is part of
// the standard the mode names, or the mode is a GNU dialect and the construct is
// one of GNU's own extensions, or an extension the command line turned on brings
// it down to this mode.
fn allowed(feature Feature, question Question) bool {
	if feature.since != .none && question.mode.includes(feature.since) {
		return true
	}
	if feature.gnu && question.mode.is_gnu() {
		return true
	}
	if feature.extension != '' && question.extensions.contains(feature.extension) {
		return true
	}
	return false
}
