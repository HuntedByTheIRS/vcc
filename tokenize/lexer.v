module tokenize

// Longest-match-first tables. C's punctuation is not a prefix code, so `<<=`
// has to be tried before `<<` before `<`. `#` and `##` are here because a
// fragment — the text of a directive line — has no line-start rule attached to
// it: in `#define STR(x) #x` the first hash opens the directive and the second
// is a punctuator, and both are read by the same table.
const punct3 = ['<<=', '>>=', '...']

const punct2 = ['->', '++', '--', '<<', '>>', '<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=',
	'%=', '&=', '|=', '^=', '##']

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
// The trigraph table. Phase 1 is unconditional here and not a branch in the
// lexer: a mode that leaves `??` alone (gcc's `-std=gnu99` and `-std=c23` do,
// `-std=c99` does not) is a dialect answer, and the dialect table lives in
// `standard/`, which this file may read and not write.
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
// anything else.
fn character_at(src string, at int) (u8, int) {
	if src[at] == `?` && at + 2 < src.len && src[at + 1] == `?` {
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
fn translated(src string, at int) (u8, int, int) {
	mut i := at
	for i < src.len {
		byte, width := character_at(src, i)
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
}

// lex reads a whole source file into tokens. Directives are recorded as single
// tokens and nothing else happens to them: macro expansion is the
// preprocessor's job, and `#define` reaches it as one token holding the line.
pub fn lex(src string) Result {
	mut l := Lexer{
		src:           src
		line:          1
		col:           1
		directives:    true
		at_line_start: true
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
	if is_ident_start(c) {
		mut text := ''
		for l.pos < l.src.len && is_ident_char(l.at()) {
			text += l.at().ascii_str()
			l.advance()
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

// at is the byte the lexer is about to read, after the phases have had it.
fn (l Lexer) at() u8 {
	byte, _, _ := translated(l.src, l.pos)
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
	_, _, next := translated(l.src, l.pos)
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
		_, start, _ := translated(l.src, l.pos)
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
		got, _, next := translated(l.src, at)
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
		byte, _, next := translated(l.src, at)
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

fn is_ident_start(c u8) bool {
	return c == `_` || (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c >= 0x80
}

fn is_ident_char(c u8) bool {
	return is_ident_start(c) || is_digit(c)
}
