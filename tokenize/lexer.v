module tokenize

// Longest-match-first tables. C's punctuation is not a prefix code, so `<<=`
// has to be tried before `<<` before `<`. `#` and `##` are here because a
// fragment — the text of a directive line — has no line-start rule attached to
// it: in `#define STR(x) #x` the first hash opens the directive and the second
// is a punctuator, and both are read by the same table.
const punct3 = ['<<=', '>>=', '...']

const punct2 = ['->', '++', '--', '<<', '>>', '<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=',
	'/=', '%=', '&=', '|=', '^=', '##']

const punct1 = '+-*/%&|^~!<>=()[]{};,.?:#'

// The first three translation phases, which turn the bytes of a file into the
// text a token is read from. They run in the order C99 gives them, and the
// order is what the reader below is for:
//
//   1. Trigraph replacement. Three characters stand for one, everywhere: in a
//      directive, in a string literal, in a character constant and inside a
//      comment. Running first is what makes `??/` at the end of a line a
//      backslash, which is what phase 2 then reads as a line join.
//   2. Line splicing. A backslash immediately before a line ending is deleted
//      with it, so the two lines are one line before anything else looks. This
//      one is why a backslash at the end of a `//` comment carries the comment
//      onto the next line, and why `foo\<newline>bar` is one identifier.
//   3. Comment removal. Every comment is one space, which is what comments in
//      a directive line become and what makes a comment that runs over the end
//      of a line keep the directive line open. It is done in `run()` and
//      `lex_directive()` as the text is walked rather than as a pass over the
//      bytes, because a comment is only a comment where a token is not.
//
// Measured on gcc 16.2.1, which is the oracle for the orderings:
//
//   printf 'int a; // c ??/\nint b;\n' > t1.c; gcc -std=c99 -Wtrigraphs -E t1.c
//   t1.c:1:19: warning: trigraph '??/' converted to '\' [-Wtrigraphs]
//   ... int a;      <- `int b;` is inside the comment: phase 1 before phase 3
//   printf 'int a; // c \\\nint b;\n' > t2.c; gcc -std=c99 -E t2.c
//   ... int a;      <- phase 2 before phase 3
//   printf 'int fo\\\nobar;\n' > t3.c; gcc -std=c99 -E t3.c
//   ... int foobar; <- phase 2 deletes both bytes
//
// The trigraph table. Whether phase 1 runs is the selected mode's answer and not
// a property of this file. gcc 16.2.1, measured one mode at a time over
// `int main(void) { return 0 ??!??! 0; }`:
//
//   -std=c89, -std=c99, -std=c11, -std=c17   rc 0, and the line is `0 || 0`
//   -std=gnu89 … -std=gnu23, -std=c23, and   rc 1, with `trigraph '??!' ignored,
//   no -std at all                           use '-trigraphs' to enable`: the
//                                            bytes are the program's
//
// So it is a dialect answer, and it is written down once, in
// `standard.replaces_trigraphs` — which this module cannot import, because
// `standard` imports this one — and it arrives here through `Options`.
const trigraphs = [
	['??=', '#'],
	['??/', '\\'],
	["??'", '^'],
	['??(', '['],
	['??)', ']'],
	['??!', '|'],
	['??<', '{'],
	['??>', '}'],
	['??-', '~'],
]

// character_at is the byte at the raw position `at` with phase 1 applied, and
// how many raw bytes it was written with: three for a trigraph, one for
// anything else. `replace` is the selected mode's answer and the only thing
// that decides whether `??x` is the character it names: with it false the three
// bytes are the three bytes.
fn character_at(src string, at int, replace bool) (u8, int) {
	if replace && src[at] == `?` && at + 2 < src.len && src[at + 1] == `?` {
		three := src[at..at + 3]
		for pair in trigraphs {
			if three == pair[0] {
				return pair[1][0], 3
			}
		}
	}
	return src[at], 1
}

// line_ending_at is the position after the line ending that starts at `at`, and
// 0 when none does. A `\r\n` is one line ending.
fn line_ending_at(src string, at int) int {
	if at >= src.len {
		return 0
	}
	if src[at] == `\n` {
		return at + 1
	}
	if src[at] == `\r` && at + 1 < src.len && src[at + 1] == `\n` {
		return at + 2
	}
	return 0
}

// translated is the character the lexer reads at the raw position `at`, the raw
// position the character itself starts at, and the raw position after it. The
// two positions, and not one, because a backslash and a line ending deleted by
// phase 2 belong to no character at all: the character after a splice starts
// further along, and the line the person wrote after it is where it is reported.
fn translated(src string, at int, replace bool) (u8, int, int) {
	mut i := at
	for i < src.len {
		byte, width := character_at(src, i, replace)
		if byte == `\\` {
			after := line_ending_at(src, i + width)
			if after > 0 {
				i = after
				continue
			}
		}
		return byte, i, i + width
	}
	// Nothing is left: a backslash at the very end of the file joins nothing.
	return 0, src.len, src.len
}

// Lexer walks the text the phases produced once, left to right. It holds the
// line and column of the byte it is about to read rather than of the byte it
// just read, so a token records where it starts, and those are the positions of
// the file rather than of the text the phases produced: a trigraph counts as
// the three characters it was written with.
pub struct Lexer {
pub mut:
	src         string
	pos         int
	line        int
	col         int
	diagnostics []Diagnostic
	// directives turns on the rule that a `#` which is the first token on a line
	// opens a directive. It is off for a fragment, where `#` is a punctuator.
	directives bool
	// at_line_start is true when the next token would be the first one on its
	// line, which is the condition C puts on a directive's `#`.
	at_line_start bool
	// replace_trigraphs is the selected mode's answer to the phase 1 question,
	// handed in through `Options` rather than decided here: in effect in the
	// strict ISO modes up to C17, and left alone in a GNU dialect, in C23 and in
	// a `-std=` spelling this compiler does not implement.
	// `standard.replaces_trigraphs` is where that answer is written down.
	replace_trigraphs bool
}

// Options are the answers the translation phases need from the language the
// command line chose. Phase 1 runs before a token exists, so its answer is not
// in the token stream and not in the feature table: it is asked of the mode and
// handed in here.
pub struct Options {
pub:
	// trigraphs says whether phase 1 replaces a `??x` with the one character it
	// names. It is the selected mode's answer, and `standard.replaces_trigraphs`
	// is where that answer is written down: in effect in the strict ISO modes up
	// to C17, left alone in a GNU dialect, in C23 and in a `-std=` spelling this
	// compiler does not implement. The field's zero value, false, is the answer
	// no mode gets: a caller that does not say leaves the bytes alone.
	trigraphs bool
}

// lex reads a whole source file into tokens. Directives are recorded as single
// tokens and nothing else happens to them: macro expansion is the
// preprocessor's job, and `#define` reaches it as one token holding the line.
//
// No dialect is named here, so phase 1 leaves a trigraph alone. That is the
// answer the compiler's own default mode gets — `.none` is no standard, and gcc
// with no `-std` leaves the bytes alone too (rc 1, measured) — and a caller that
// knows the selected mode asks `lex_with`.
pub fn lex(src string) Result {
	return lex_with(src, Options{})
}

// lex_with reads a whole source file with the phases' dialect answers given.
pub fn lex_with(src string, opts Options) Result {
	mut l := Lexer{
		src:               src
		line:              1
		col:               1
		directives:        true
		at_line_start:     true
		replace_trigraphs: opts.trigraphs
	}
	tokens := l.run()
	return Result{
		tokens:      tokens
		diagnostics: l.diagnostics
	}
}

// lex_fragment reads the text of one directive line — everything after the `#`
// — or of a macro body. `#` and `##` are punctuators here, and the result has no
// end-of-file token: a fragment ends where the caller's text ends.
//
// A fragment is text phase 1 has already had — the directive line a file's lexer
// copied, a macro body, the name a paste built — so the fragment reader does not
// replace a trigraph: `??!` is the three punctuators the text is made of. That
// is gcc's answer for text that never was a file's bytes: measured,
// `gcc -std=c99 -E -DX='??!'` prints `??!` and not `|`.
pub fn lex_fragment(text string) []Token {
	mut l := Lexer{
		src:  text
		line: 1
		col:  1
	}
	tokens := l.run()
	if tokens.len > 0 && tokens[tokens.len - 1].kind == .eof {
		return tokens[..tokens.len - 1]
	}
	return tokens
}

fn (mut l Lexer) run() []Token {
	// A file that opens with a spliced line ending opens on its second line,
	// and settling the position here is what makes its first token report that.
	l.settle()
	mut tokens := []Token{}
	for l.pos < l.src.len {
		c := l.at()
		if c == ` ` || c == `\t` || c == `\r` || c == `\n` || c == `\v` || c == `\f` {
			l.advance()
			continue
		}
		// A line ending inside a `//` comment that the phases spliced away is
		// not there to end the comment, which is what carries the comment onto
		// the next line.
		if c == `/` && l.peek(1) == `/` {
			for l.pos < l.src.len && l.at() != `\n` {
				l.advance()
			}
			continue
		}
		if c == `/` && l.peek(1) == `*` {
			if !l.skip_block_comment() {
				break
			}
			continue
		}
		// `#` opens a directive when it is the first token on its line and this
		// text is source rather than a fragment. Anywhere else the same byte is
		// a punctuator, which is what a macro body uses to paste and stringize.
		if c == `#` && l.directives && l.at_line_start {
			tokens << l.lex_directive()
			l.at_line_start = false
			continue
		}
		tok := l.lex_token() or { break }
		tokens << tok
		l.at_line_start = false
	}
	tokens << Token{
		kind: .eof
		line: l.line
		col:  l.col
	}
	return tokens
}

fn (mut l Lexer) skip_block_comment() bool {
	line := l.line
	col := l.col
	l.advance()
	l.advance()
	for l.pos < l.src.len {
		if l.at() == `*` && l.peek(1) == `/` {
			l.advance()
			l.advance()
			return true
		}
		l.advance()
	}
	l.diagnostics << Diagnostic{
		line: line
		col:  col
		msg:  'unterminated block comment'
	}
	return false
}

fn (mut l Lexer) lex_directive() Token {
	line := l.line
	col := l.col
	mut text := ''
	for l.pos < l.src.len && l.at() != `\n` {
		c := l.at()
		// A comment is one space as far as a directive is concerned, and a
		// comment that runs over the end of a line takes the directive with
		// it: C replaces every comment with a space before it looks for
		// directives, so the newline inside one does not end the line.
		if c == `/` && l.peek(1) == `*` {
			text += ' '
			if !l.skip_block_comment() {
				break
			}
			continue
		}
		// A line comment hides the rest of the line, so the directive ends
		// where the comment starts.
		if c == `/` && l.peek(1) == `/` {
			break
		}
		// A string or a character constant is text: nothing inside one of them
		// is a comment. A backslash before a line ending inside one of them is
		// a line join like any other, and the phases have already taken it
		// away, so what is copied here is the line the person continued.
		if c == `"` || c == `'` {
			quote := c
			text += c.ascii_str()
			l.advance()
			for l.pos < l.src.len && l.at() != `\n` {
				inner := l.at()
				text += inner.ascii_str()
				l.advance()
				if inner == `\\` && l.pos < l.src.len {
					text += l.at().ascii_str()
					l.advance()
					continue
				}
				if inner == quote {
					break
				}
			}
			continue
		}
		text += c.ascii_str()
		l.advance()
	}
	return Token{
		kind: .directive
		text: text.trim_space()
		line: line
		col:  col
	}
}

fn (mut l Lexer) lex_token() ?Token {
	start_line := l.line
	start_col := l.col
	c := l.at()
	if is_ident_start(c) || (c == `\\` && l.universal_name() != none) {
		mut text := ''
		for l.pos < l.src.len {
			if is_ident_char(l.at()) {
				text += l.at().ascii_str()
				l.advance()
				continue
			}
			// A universal character name is a name for one character, and it
			// is as much a part of an identifier as a letter is: `a\u00e9b` is
			// one name. The token text is the name in the spelling gcc writes
			// in a preprocessed stream, `\U` and eight hexadecimal digits, so
			// the text is itself something C reads back as the same name.
			name := l.universal_name() or { break }
			l.check_universal_name(name, start_line, start_col)
			text += canonical_name(name.value)
			for _ in 0 .. name.width {
				l.advance()
			}
		}
		// L"x", u'x' and u8"x" are one literal, not an identifier and a string.
		if l.pos < l.src.len && (l.at() == `"` || l.at() == `'`)
			&& text in ['L', 'u', 'U', 'u8'] {
			return l.lex_quoted(text, start_line, start_col)
		}
		return Token{
			kind: .identifier
			text: text
			line: start_line
			col:  start_col
		}
	}
	if is_digit(c) || (c == `.` && is_digit(l.peek(1))) {
		return l.lex_number(start_line, start_col)
	}
	if c == `"` || c == `'` {
		return l.lex_quoted('', start_line, start_col)
	}
	// Punctuation is matched longest first against the text the phases produced,
	// so a punctuator written as a trigraph is the punctuator it stands for:
	// `??=??=` is `##` and `??(` is `[`.
	ahead := l.ahead(3)
	for n in [3, 2, 1] {
		if ahead.len < n {
			continue
		}
		text := ahead[..n]
		if n == 1 && !punct1.contains_u8(c) {
			continue
		}
		if (n == 3 && text in punct3) || (n == 2 && text in punct2) || n == 1 {
			for _ in 0 .. n {
				l.advance()
			}
			return Token{
				kind: .punct
				text: text
				line: start_line
				col:  start_col
			}
		}
	}
	l.diagnostics << Diagnostic{
		line: start_line
		col:  start_col
		msg:  'unexpected character ${c.ascii_str()} in the source'
	}
	return none
}

// lex_number reads what the C standard calls a preprocessing number: digits,
// letters, dots and exponent signs, so `1.5e-3f` and `0x1p-4` come out whole.
// Whether the result is a valid number is the parser's problem, as in C.
fn (mut l Lexer) lex_number(start_line int, start_col int) ?Token {
	mut text := ''
	mut seen_dot := false
	for l.pos < l.src.len {
		ch := l.at()
		if is_digit(ch) || is_ident_char(ch) {
			text += ch.ascii_str()
			l.advance()
			continue
		}
		if ch == `.` && !seen_dot && l.peek(1) != `.` {
			seen_dot = true
			text += '.'
			l.advance()
			continue
		}
		if (ch == `+` || ch == `-`) && text.len > 0 && text[text.len - 1] in [`e`, `E`, `p`, `P`] {
			text += ch.ascii_str()
			l.advance()
			continue
		}
		break
	}
	return Token{
		kind: .number
		text: text
		line: start_line
		col:  start_col
	}
}

fn (mut l Lexer) lex_quoted(prefix string, start_line int, start_col int) ?Token {
	quote := l.at()
	kind := if quote == `"` { Kind.string } else { Kind.character }
	mut text := prefix + quote.ascii_str()
	l.advance()
	mut closed := false
	for l.pos < l.src.len {
		ch := l.at()
		if ch == `\n` {
			break
		}
		if ch == `\\` {
			text += ch.ascii_str()
			l.advance()
			if l.pos < l.src.len {
				text += l.at().ascii_str()
				l.advance()
			}
			continue
		}
		text += ch.ascii_str()
		l.advance()
		if ch == quote {
			closed = true
			break
		}
	}
	if !closed {
		l.diagnostics << Diagnostic{
			line: start_line
			col:  start_col
			msg:  'unterminated ${if kind == .string { 'string' } else { 'character' }} literal'
		}
		return none
	}
	return Token{
		kind: kind
		text: text
		line: start_line
		col:  start_col
	}
}

// UniversalName is a universal character name as it was written: `\uXXXX` or
// `\UXXXXXXXX`. `value` is the character it names and `width` is how many
// characters the spelling takes, which is what the lexer has to step over.
struct UniversalName {
	spelling string
	value    u32
	width    int
}

// universal_name reads the universal character name at the current position, or
// answers none when what is there is not one. gcc reads a short or a
// non-hexadecimal one as a stray backslash rather than as a name (`int \u00`
// gives `stray '\' in program`), and so does this lexer: the backslash is then
// an unexpected character, which is the same refusal in this compiler's words.
fn (l Lexer) universal_name() ?UniversalName {
	if l.at() != `\\` {
		return none
	}
	kind := l.peek(1)
	digits := match kind {
		`u` { 4 }
		`U` { 8 }
		else { return none }
	}
	mut spelling := '\\' + kind.ascii_str()
	mut value := u32(0)
	for i in 0 .. digits {
		c := l.peek(2 + i)
		digit := hex_value(c) or { return none }
		value = value * 16 + u32(digit)
		spelling += c.ascii_str()
	}
	return UniversalName{
		spelling: spelling
		value:    value
		width:    digits + 2
	}
}

// check_universal_name reports a name that does not stand for something an
// identifier can hold. The two messages are gcc 16.2.1's own, and so is the line
// between them, measured one input at a time:
//
//   int \u0040 = 1;      universal character \u0040 is not valid in an identifier
//   int \u0020 = 1;      the same
//   int \U00110000 = 1;  universal character \U00110000 is not valid in an identifier
//   int \U0010FFFF = 1;  the same
//   int \U0000D800 = 1;  \U0000D800 is not a valid universal character
//   int \U0000DFFF = 1;  the same
//   int \UFFFFFFFE = 1;  \UFFFFFFFE is not a valid universal character
//   int \UFFFFFFFF = 1;  the same
//
// So the first message is for a character an identifier cannot hold: everything
// under A0 except the dollar, and everything past the last character C99
// defines. The second is for a name that is not a character at all, which is
// the surrogate range and the values past what the decimal conversion holds.
// A name over A0 and inside the range is taken as it stands: gcc also refuses
// the ones that are not letters (`\u00a1`, `\u00d7`), which would mean the
// letter ranges of Annex D, and reading a legal name as an illegal one is the
// worse defect of the two while this compiler has no such table.
fn (mut l Lexer) check_universal_name(name UniversalName, line int, col int) {
	if (name.value >= 0xD800 && name.value <= 0xDFFF) || name.value > 0x7FFFFFFF {
		l.diagnostics << Diagnostic{
			line: line
			col:  col
			msg:  '${name.spelling} is not a valid universal character'
		}
		return
	}
	if (name.value < 0xA0 && name.value != 0x24) || name.value > 0x10FFFF {
		l.diagnostics << Diagnostic{
			line: line
			col:  col
			msg:  'universal character ${name.spelling} is not valid in an identifier'
		}
	}
}

// canonical_name is a universal character name in the spelling this compiler
// writes into a token, which is the one gcc writes into a preprocessed stream:
// `\U` and eight lowercase hexadecimal digits. Measured: `gcc -std=c99 -E` over
// `int \u00e9 = 1;` prints `int \U000000e9 = 1;` and over `int \U0001F600 = 1;`
// prints `int \U0001f600 = 1;`. `-E` here prints the same spelling of the same
// name, and the text is itself something C reads back as that name.
fn canonical_name(value u32) string {
	mut out := '\\U'
	for shift in [28, 24, 20, 16, 12, 8, 4, 0] {
		digit := u8((value >> shift) & u32(0xF))
		out += if digit < 10 {
			u8(digit + `0`).ascii_str()
		} else {
			u8(digit - 10 + `a`).ascii_str()
		}
	}
	return out
}

fn hex_value(c u8) ?int {
	if c >= `0` && c <= `9` {
		return int(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return int(c - `a`) + 10
	}
	if c >= `A` && c <= `F` {
		return int(c - `A`) + 10
	}
	return none
}

// at is the byte the lexer is about to read, after the phases have had it.
fn (l Lexer) at() u8 {
	byte, _, _ := translated(l.src, l.pos, l.replace_trigraphs)
	return byte
}

// advance moves past the character the lexer is reading, and counts every raw
// byte behind it: the three a trigraph was written with, and the backslash and
// line ending of a splice, so that the line and column of the next token are the
// ones in the file.
fn (mut l Lexer) advance() {
	if l.pos >= l.src.len {
		return
	}
	_, _, next := translated(l.src, l.pos, l.replace_trigraphs)
	l.count(l.pos, next)
	l.pos = next
	l.settle()
}

// settle counts the bytes the phases spliced away at the current position and
// steps over them, so the character the lexer is about to read is reported where
// the person wrote it. `advance` leaves the position settled, and `run` settles
// it once at the start for a file that opens with a spliced line ending.
fn (mut l Lexer) settle() {
	for l.pos < l.src.len {
		_, start, _ := translated(l.src, l.pos, l.replace_trigraphs)
		if start <= l.pos {
			return
		}
		l.count(l.pos, start)
		l.pos = start
	}
}

// count moves the line and the column over the raw bytes in [from, to). A line
// ending the phases deleted still moves the count to the next line, because the
// token after it was written there.
fn (mut l Lexer) count(from int, to int) {
	for i := from; i < to; i++ {
		if l.src[i] == `\n` {
			l.line++
			l.col = 1
			// The next token starts a line, and a `#` there opens a directive.
			l.at_line_start = true
		} else {
			l.col++
		}
	}
}

// peek answers the byte n positions past the current one in the text the phases
// produced, and 0 past the end of it. n is 0 or 1 everywhere it is used: a lexer
// that needed two bytes of lookahead would need a different shape.
fn (l Lexer) peek(n int) u8 {
	mut at := l.pos
	mut byte := u8(0)
	for _ in 0 .. n + 1 {
		if at >= l.src.len {
			return 0
		}
		got, _, next := translated(l.src, at, l.replace_trigraphs)
		byte = got
		if got == 0 && next >= l.src.len {
			return 0
		}
		at = next
	}
	return byte
}

// ahead is the next n characters of the text the phases produced, for the
// longest-match-first punctuation table.
fn (l Lexer) ahead(n int) string {
	mut out := ''
	mut at := l.pos
	for _ in 0 .. n {
		if at >= l.src.len {
			break
		}
		byte, _, next := translated(l.src, at, l.replace_trigraphs)
		if byte == 0 && next >= l.src.len {
			break
		}
		out += byte.ascii_str()
		at = next
	}
	return out
}

fn is_digit(c u8) bool {
	return c >= `0` && c <= `9`
}

// is_ident_start is what may begin an identifier. `$` is a GNU extension and
// gcc takes it in every mode (measured: `int $x = 0;` compiles under
// `-std=c99 -pedantic-errors`), so it is one here. Every byte at or over 0x80 is
// a name character too, which is what reads an identifier written in UTF-8.
//
// 5.2.4.1 asks an implementation to support 63 significant characters in an
// internal identifier and 31 in an external one. Those are what has to be
// significant, not what may be written: every character of a name is kept and
// none of it is refused, so a name of any length is one token with all of it
// significant, and two names that differ only past the sixty-third character
// are two names here. That settles the decision the standard leaves open for
// short external identifiers, which is whether they collapse across translation
// units: they do not, because nothing in this tree truncates a name. The
// emitter keys its labels by the name the program wrote (`codegen/codegen.v`
// writes `e.program.labels[decl.name]`), and gcc is the same way, measured: two
// functions whose names differ in their thirty-second character are two symbols
// in its object file. Refusing a name this compiler can keep would be the worse
// defect of the two.
fn is_ident_start(c u8) bool {
	return c == `_` || (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c >= 0x80 || c == `$`
}

fn is_ident_char(c u8) bool {
	return is_ident_start(c) || is_digit(c)
}
