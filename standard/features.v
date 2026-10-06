module standard

import tokenize
import diagnostics

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
	// reserved says the spelling is in the reserved namespace: a name with two
	// underscores around it, which no mode has to grant and none may refuse.
	// Measured on gcc 16.2.1, the reserved spellings of the typeof specifier
	// are accepted under every -std tried, `-std=c99 -pedantic-errors`
	// included, with empty stderr. So a row with this set is taken by every
	// mode and is never reported, and it carries no phrase to report: no mode
	// forbids the construct. Rows that are not reserved leave it out.
	reserved bool
	// invalid says a mode without the construct does not merely need warning
	// about it: the mode does not have the construct at all, and gcc refuses
	// the spelling under it whatever is written on the command line. Measured
	// on gcc 16.2.1, plain `typeof` under `-std=c99` and `typeof_unqual` under
	// `-std=gnu99` exit 1 with and without -pedantic, `-w` does not silence
	// either, and no `-std` spelling makes gcc take them. A row with this set
	// is reported as a diagnostic the compiler raises on its own account,
	// which no flag silences; a row without it is a pedantic message, which
	// is silent until something asks for it.
	invalid bool
	// extension is the name of the -fvcc-exts= extension that brings the
	// construct down to a mode before `since`, when there is one. The names
	// these rows carry are the whole list of extensions this compiler offers:
	// extension_names() below reads them off the rows, and extensions/ builds
	// the flag's interface on that rather than on a list of its own.
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
	// The seven atomic operations and the four zero-bit counts are the GNU
	// compiler's own and no standard has them: V's code generator writes them
	// into an inline shim, and the tree reads each one here and emits the
	// machine's instruction for it. The row is a GNU row with a phrase, the way
	// the attribute and asm rows above are, and for the same measured reason:
	// gcc 16.2.1 accepts `__atomic_load_n(p, 5)` and `__builtin_ctz(x)` under
	// `-std=c99 -pedantic-errors` with empty stderr, because the double
	// underscore is in the reserved namespace. So no ISO mode is made to refuse
	// them and a strict mode reports the construct only when asked: -Wpedantic
	// shows the message and -pedantic-errors makes it an error.
	Feature{
		spellings: ['__atomic_load_n', '__atomic_store_n', '__atomic_exchange_n',
			'__atomic_compare_exchange_n', '__atomic_fetch_add', '__atomic_fetch_sub',
			'__atomic_thread_fence', '__builtin_ctz', '__builtin_ctzll', '__builtin_clz',
			'__builtin_clzll']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'the atomic builtins and the count-trailing and count-leading builtins'
		status:    .implemented
	},
	// The rest of the GNU compiler's own builtins this tree reads, the same kind
	// of reserved-namespace spelling as the row above and by the same measured
	// reasoning: gcc 16.2.1 accepts each of them under `-std=c99 -pedantic-errors`
	// with empty stderr, because the double underscore is the compiler's own
	// namespace and no program can write a declaration for it. So no ISO mode is
	// made to refuse them, and a strict mode reports a construct from this row
	// only when asked, under -Wpedantic or -pedantic-errors. `__builtin_constant_p`
	// and `__builtin_object_size` are folded where they are written,
	// `__builtin_return_address`, `__builtin_bswap16/32`, `__builtin_popcount`,
	// `__builtin_parity`, the two overflow-checking builtins, `__builtin_alloca`
	// and the two no-return builtins are emitted as instructions, and every one of
	// them is read in `parser/builtins.v`.
	Feature{
		spellings: ['__builtin_constant_p', '__builtin_object_size', '__builtin_return_address',
			'__builtin_unreachable', '__builtin_trap', '__builtin_bswap16', '__builtin_bswap32',
			'__builtin_popcount', '__builtin_parity', '__builtin_add_overflow', '__builtin_mul_overflow',
			'__builtin_alloca']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'the constant-fold, object-size, return-address, unreachable, trap, byte-swap, bit-count, overflow-check and stack-allocation builtins'
		status:    .implemented
	},
	// A GNU statement expression, `({ ... })`, is marked by two tokens with nothing
	// between them and not by a word, so its spelling here is the pair and the
	// check joins two tokens to find it. The tree reads the construct, so the row
	// is implemented: `parser/parser.v` reads the group, `ast.StmtExpr` carries it
	// and `codegen/codegen.v` writes it, and a group used as a value whose last
	// statement is not an expression statement is refused by name where it is
	// written. Measured on gcc 16.2.1, it is a GNU extension: c89, c99, c11 and
	// c23 exit 0 silently and report it only under -pedantic (`ISO C forbids
	// braced-groups within expressions`, an error under -pedantic-errors), and a
	// GNU dialect takes it as its own. `gnu: true` is what says that and is the
	// whole of the row's answer. The one place the answer is coarser than gcc is
	// `-std=gnu99 -pedantic`, where gcc reports the construct anyway because
	// -pedantic asks for the ISO standard's answer while this row is allowed in a
	// GNU mode and the check produces nothing there; the `__int128` row is coarse
	// the same way, measured the same way, so that is the `gnu` field's limit and
	// not this row's.
	Feature{
		spellings: ['({']
		since:     .none
		gnu:       true
		extension: ''
		pedantic:  'braced-groups within expressions'
		status:    .implemented
	},
	// typeof is C23's specifier, and the bare spelling is a keyword only where
	// that standard or a GNU dialect is in effect. Measured on gcc 16.2.1,
	// `typeof(x) y = 2;` is accepted under `-std=c23`, under `-std=gnu99` and
	// with no `-std` at all, and the strict modes fail on it without
	// -pedantic: `-std=c99`, `-std=c99 -pedantic` and
	// `-std=c99 -pedantic-errors` all exit 1, reporting
	// `implicit declaration of function 'typeof'` inside a function body and
	// `return type defaults to 'int'` at file scope. The mode does not have
	// the construct at all: no flag makes gcc take it. The table reports it
	// in the modes that lack it, because reporting is what this check does
	// with a construct a mode does not allow. Refusing it outright means
	// asking the mode where the spelling is read, which is the parser's job
	// and not this table's.
	Feature{
		spellings: ['typeof']
		since:     .c23
		gnu:       true
		extension: 'typeof'
		invalid:   true
		pedantic:  'the typeof specifier'
		status:    .implemented
	},
	// The two underscore-wrapped spellings of the specifier have a row of their
	// own, because a row is found by token text and the answer differs from the
	// bare spelling's: measured on gcc 16.2.1, `__typeof__(x) y = 2;` and
	// `__typeof(x) y = 2;` are accepted under every `-std` tried,
	// `-std=c99 -pedantic-errors` included, with empty stderr. A name with two
	// underscores around it is in the reserved namespace, so no mode has to
	// grant it and none refuses it.
	Feature{
		spellings: ['__typeof__', '__typeof']
		since:     .none
		gnu:       false
		reserved:  true
		extension: ''
		pedantic:  ''
		status:    .implemented
	},
	// typeof_unqual is C23's other spelling of the specifier: the same type
	// with the qualifiers taken off it. Measured on gcc 16.2.1 it is narrower
	// than typeof, and the difference is that no GNU dialect has it as an
	// extension of its own: `typeof_unqual(x) y = 2;` is accepted under
	// `-std=c23` and with no `-std` at all, and refused under `-std=gnu99` as
	// well as under `-std=c99`, `-std=c99 -pedantic` and
	// `-std=c99 -pedantic-errors`, where the line reads as a call to a
	// function of that name. So `since: .c23` with `gnu: false`: gnu23 takes it
	// because gnu23 includes C23, and gnu99 does not.
	Feature{
		spellings: ['typeof_unqual']
		since:     .c23
		gnu:       false
		extension: ''
		invalid:   true
		pedantic:  'the typeof_unqual specifier'
		status:    .implemented
	},
	// The reserved spelling of typeof_unqual, on the same footing as the two
	// above it: gcc 16.2.1 measured accepts `__typeof_unqual__(x) y = 2;` in
	// every mode, and tcc knows neither spelling, so nothing here depends on
	// tcc's answer.
	Feature{
		spellings: ['__typeof_unqual__']
		since:     .none
		gnu:       false
		reserved:  true
		extension: ''
		pedantic:  ''
		status:    .implemented
	},
	// The C23 auto type specifier takes a type from its initializer: `auto x = 1;`
	// is an int. It is read by `parse_local_declaration` in `parser/statements.v`,
	// which completes the declaration with the initializer's type after the lvalue
	// conversion once the initializer has been read, and refuses a declaration
	// with no initializer by name because C23 requires one. The word is also the
	// C89 storage class, so the spelling alone does not mark the construct and
	// this row brings its own detection: only `auto x` (which the token after the
	// name ends) is the type specifier, while `auto int x` and `auto T x` have a
	// type between the word and the name and are the storage class; see
	// `auto_is_a_type_specifier` below. Measured on gcc 16.2.1, the flags are the
	// C23 ones and the refusal is one the command line does not take back:
	// `auto x = 1;` is refused under -std=c99 and -std=gnu99 even with -w written
	// on the command line (`type defaults to 'int' ... [-Wimplicit-int]`), and
	// taken under -std=c23, under -std=gnu23 because gnu23 includes C23, and with
	// no -std at all. `-Wno-implicit-int` is the one flag that takes the refusal
	// back, and it is a flag this compiler does not have, so within its surface
	// the row refuses like the typeof row above it and is `invalid` rather than a
	// pedantic message. The qualified form `auto const x = 1;` is not read: the
	// reader meets the qualifier between the word and the name and reads the
	// storage class, so the declaration is refused rather than deduced.
	Feature{
		spellings: ['auto']
		since:     .c23
		gnu:       false
		extension: 'auto'
		invalid:   true
		pedantic:  'the auto type specifier'
		status:    .implemented
	},
	// _Generic is read by `parse_generic_selection` in `parser/parser.v`: the
	// controlling expression's type, after the lvalue conversion 6.5.17 asks for,
	// is matched against the associations and the selection is worth the selected
	// arm's expression and type. The controlling expression is not evaluated, so
	// no code is emitted for it. Measured on gcc 16.2.1, the flags are the C11
	// ones: c99 and gnu99 take the construct and warn only under -pedantic
	// (`ISO C99 does not support '_Generic'`), c11 and c23 take it silently, and
	// a GNU dialect before C11 does not add it. The row is a pedantic message and
	// not `invalid`, the same shape as _Static_assert's.
	Feature{
		spellings: ['_Generic']
		since:     .c11
		gnu:       false
		extension: 'generic'
		pedantic:  'the _Generic selection'
		status:    .implemented
	},
	// _Static_assert is read in both positions it can be written in, file scope
	// and a body, by one reader in `parser/declarations.v`: the condition is
	// folded there and a false one is a diagnostic carrying the message. Measured
	// before the reader, the two positions answered wrong and differently: at file
	// scope the words were refused as `unsupported: expected a declaration, found
	// '_Static_assert'`, and in a body the statement reader took them for an
	// expression, so a static assertion read as a statement became a call to a
	// symbol nothing defined, which is the parser defect this reader removes. The
	// flags are measured on gcc 16.2.1: c99 and gnu99 take the construct and warn
	// only under -pedantic, c11 and c23 take it silently, and a GNU dialect does
	// not add it to a mode before C11, so the phrase below is a pedantic message
	// and the row is not `invalid`.
	Feature{
		spellings: ['_Static_assert']
		since:     .c11
		gnu:       false
		extension: 'static-assert'
		pedantic:  'the _Static_assert declaration'
		status:    .implemented
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
	// as a member of an object and as an element of an array of them, whose element
	// access is refused by name (an element of sixteen bytes is not a value one
	// instruction moves). Reading one is written as a conversion to a
	// narrower type, which is its low word: measured on gcc 16.2.1, `(int)` of a
	// stored 300 is 300, `(char)` of one is 44, and `(int)` of a stored -1 is -1.
	// What is missing is a *value* of that width, so a parameter of the type and
	// an implicit narrowing store are refused by name: `int f(__int128 v) { return
	// 0; }` reports `unsupported type __int128`, and `__int128 v = 5; int n = v;`
	// reports that the object has no value of that width to read. A conversion of
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
	// The 128-bit type C23 added, written `_BitInt(128)`: the word and the width
	// in parentheses are one specifier, and the check finds the row by the word.
	// C23 has the type and no earlier standard does, and a GNU mode does not
	// grant it the way it grants a GNU extension. Measured on gcc 16.2.1:
	// `-std=c99 -pedantic` warns `ISO C does not support '_BitInt(128)' before
	// C23`, c11 and gnu99 say it too, `-pedantic-errors` makes it an error, and
	// c23 and gnu23 say nothing. What the tree reads is the one width it has a
	// value of that size for: `_BitInt(128)` is the 128-bit pair under C23's
	// spelling, and every other width is refused by name with its location.
	Feature{
		spellings: ['_BitInt']
		since:     .c23
		gnu:       false
		extension: ''
		pedantic:  'the _BitInt type'
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
	// sizeof is C89's operator and the tree reads it: `parser/parser.v` answers it
	// where it is written, its operand is not evaluated, and `pipeline_test.v`
	// asserts both (`sizeof(double) + sizeof(char)` is 9, and `sizeof(bump())`
	// calls bump no times). Measured on gcc 16.2.1, the operator is C89's, so every
	// mode has it and none reports it. The comment on this row used to say the
	// tree did not read the spelling and refused it by name, which was true before
	// the reader landed and stopped being true after; the reader is what the row
	// now records. A sizeof whose operand is an array with no size this compiler
	// knows, which is a variable-length array, is refused by name at its own
	// location, and that is the shape's answer rather than this operator's.
	Feature{
		spellings: ['sizeof']
		since:     .c89
		gnu:       false
		extension: ''
		pedantic:  'the sizeof operator'
		status:    .implemented
	},
]

// extension_names is the set of -fvcc-exts= names this table carries: the
// extension strings of the feature rows, no name written twice and the list in
// alphabetical order, so that what a caller prints does not move when a row is
// added elsewhere in the table. It is the whole list of extensions the compiler
// offers, and extensions/ reads it here rather than keeping a second list that
// can drift from the rows.
pub fn extension_names() []string {
	mut out := []string{}
	for feature in features {
		if feature.extension == '' {
			continue
		}
		if out.contains(feature.extension) {
			continue
		}
		out << feature.extension
	}
	out.sort()
	return out
}

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
//   -std=c2y, -std=gnu2y                     rc 1, the same as C23: the next
//                                            standard does not bring them back.
//                                            gcc 16.2.1 takes the working
//                                            spelling and refuses -std=c29, so
//                                            that is the spelling measured
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
		.none, .c23, .c29, .gnu89, .gnu99, .gnu11, .gnu17, .gnu23, .gnu29, .other { false }
	}
}

// has_digraphs answers the other spelling question for the selected mode, and it
// is a separate question because C asks it separately: the six C99 digraphs
// (`%:` for `#`, `%:%:` for `##`, `<:` and `:>` for the brackets and `<%` and
// `%>` for the braces) are token spellings, not a replacement phase 1 makes in
// the bytes. `replaces_trigraphs` above is the other one, and the two answers
// are not the same: a trigraph is replaced only up to C17, and a digraph is read
// everywhere.
//
// Measured on gcc 16.2.1, one mode at a time over `%:define A 41` and a program
// that returns `A + 1`:
//
//	-std=c89            rc 1: `error: expected identifier or '('`, at 1:1
//	-std=gnu89, -std=c99, -std=c11, -std=c17,
//	-std=c23, -std=gnu23, -std=c2y, -std=gnu2y,
//	and no -std at all                         rc 0
//
// The one mode without them is the strict ISO mode they arrived after, and the
// GNU dialect of that same standard has them, which is what gcc does with a
// feature its own strict mode lacks. A `-std=` spelling this compiler does not
// implement is recorded and refused nothing, and it takes the default dialect's
// answer, which is gnu-like: it has them.
pub fn has_digraphs(mode Mode) bool {
	return match mode {
		.c89 { false }
		.none, .c99, .c11, .c17, .c23, .c29, .gnu89, .gnu99, .gnu11, .gnu17, .gnu23, .gnu29,
		.other {
			true
		}
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

// auto_is_a_type_specifier says whether the `auto` token at `at` is C23's type
// specifier rather than the C89 storage class of the same spelling, which is
// what decides whether the auto row's construct is written. The declaration says
// which and the tokens after the word are what say it: the deduced form is
// written with the name right after the word, so the token after the name ends
// the declaration (`=`, `;` or `,`), while the storage-class form has a type
// between the word and the name (`auto int x`, `auto T x`). The question is
// asked of two following tokens rather than of a table of type words because a
// name the file typedef'd is a type and this check knows no scopes. The reader
// in `parser/declarations.v` asks the same question of the same two tokens.
fn auto_is_a_type_specifier(tokens []tokenize.Token, at int) bool {
	if at + 1 >= tokens.len {
		return false
	}
	after := tokens[at + 1]
	if after.kind == .punct {
		// The storage class cannot stand without a type in front of the
		// declarator, so a declarator starting right after the word is the
		// deduced form written with a declarator the standard does not allow.
		return after.text in ['*', '(', '[']
	}
	if after.kind != .identifier || at + 2 >= tokens.len {
		return false
	}
	ended := tokens[at + 2]
	return ended.kind == .punct && ended.text in ['=', ';', ',', '[']
}

// spelling_is_the_pair says whether `spelling` is the two tokens `first` and
// `second` written with nothing between them. It compares the bytes rather than
// joining the two texts first: the join was a heap string per row per token, and
// the answer does not need the string. A two-token spelling is how a construct
// whose spelling is more than one token is found, `({` for a braced group.
fn spelling_is_the_pair(spelling string, first string, second string) bool {
	if spelling.len != first.len + second.len {
		return false
	}
	for k in 0 .. first.len {
		if spelling[k] != first[k] {
			return false
		}
	}
	for k in 0 .. second.len {
		if spelling[first.len + k] != second[k] {
			return false
		}
	}
	return true
}

// spelling_matches says whether one of a row's spellings is the token `text` or
// the two tokens `text` and `after` written with nothing between them. `has_after`
// is false at the end of the stream, where there is no second token and so no
// pair to match.
fn spelling_matches(spellings []string, text string, after string, has_after bool) bool {
	for spelling in spellings {
		if spelling == text {
			return true
		}
		if has_after && spelling_is_the_pair(spelling, text, after) {
			return true
		}
	}
	return false
}

// uses is the walk itself, over a table the caller hands in rather than over the
// table above, which is how the rule an extension follows is checked before
// there is an extension to check it with: the tests bring a table of their own.
fn uses(tokens []tokenize.Token, table []Feature, question Question) []tokenize.Diagnostic {
	mut out := []tokenize.Diagnostic{}
	// A construct no single spelling marks brings its own detection, because the
	// spelling is shared with something else: `auto` is C23's type specifier and
	// the C89 storage class, and only the tokens after the word say which. See
	// auto_is_a_type_specifier.
	for i, token in tokens {
		// The two-token spelling is looked for by comparing a row's spelling
		// against the two texts rather than by joining them. The join was a
		// heap string per (token, row) pair, and on V's own generated C this
		// walk is 5.1M tokens times 18 rows, every one of them a string that
		// found nothing.
		has_after := i + 1 < tokens.len
		after := if has_after { tokens[i + 1].text } else { '' }
		for feature in table {
			if feature.status == .unimplemented {
				continue
			}
			if !spelling_matches(feature.spellings, token.text, after, has_after) {
				continue
			}
			if feature.extension == 'auto' && !auto_is_a_type_specifier(tokens, i) {
				continue
			}
			if allowed(feature, question) {
				continue
			}
			if question.system_files[token.file] {
				continue
			}
			// A construct the mode does not have is reported as a diagnostic the
			// compiler raises on its own account, which no flag silences, and one
			// the mode merely does not allow is a pedantic message the flags
			// decide the fate of. Both name the mode and the construct.
			out << tokenize.Diagnostic{
				line:    token.line
				col:     token.col
				msg:     '${question.mode.standard_name()} forbids ${feature.pedantic}'
				file:    token.file
				warning: !feature.invalid
				class:   if feature.invalid {
					diagnostics.Class.cpp
				} else {
					diagnostics.Class.pedantic
				}
			}
		}
	}
	return out
}

// allowed says whether the selected mode takes the construct in: it is part of
// the standard the mode names, or the mode is a GNU dialect and the construct is
// one of GNU's own extensions, or an extension the command line turned on brings
// it down to this mode.
//
// A reserved spelling is the first thing answered, and every mode takes it: the
// name is in the implementation's namespace, so the mode is not a question
// anybody asked about it and there is nothing to report.
fn allowed(feature Feature, question Question) bool {
	if feature.reserved {
		return true
	}
	if feature.since != .none && question.mode.includes(feature.since) {
		return true
	}
	if feature.gnu && question.mode.is_gnu() {
		return true
	}
	return brought_down(feature, question.extensions)
}

// brought_down answers the question the extension column is for: whether an
// extension the command line named brings this row's construct down to the
// selected mode. Every row is answered, and the answer is a fact about the row
// rather than the outcome of a lookup that can come back empty: a row that
// names no extension is brought down by no name, and a name the table does not
// carry is not a name any row can have written.
fn brought_down(feature Feature, named []string) bool {
	if feature.extension == '' {
		return false
	}
	return named.contains(feature.extension)
}
