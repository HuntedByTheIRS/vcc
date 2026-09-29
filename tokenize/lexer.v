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

// Lexer walks the source once, left to right. It holds the line and column of
// the byte it is about to read rather than of the byte it just read, so a token
// records where it starts.
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
	mut tokens := []Token{}
	for l.pos < l.src.len {
		c := l.src[l.pos]
		if c == ` ` || c == `\t` || c == `\r` || c == `\n` || c == `\v` || c == `\f` {
			l.advance()
			continue
		}
		// A backslash before a newline joins the two lines before lexing them.
		if c == `\\` && l.peek(1) == `\n` {
			l.advance()
			l.advance()
			continue
		}
		if c == `/` && l.peek(1) == `/` {
			for l.pos < l.src.len && l.src[l.pos] != `\n` {
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
		if l.src[l.pos] == `*` && l.peek(1) == `/` {
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
	for l.pos < l.src.len && l.src[l.pos] != `\n` {
		if l.src[l.pos] == `\\` && l.peek(1) == `\n` {
			l.advance()
			l.advance()
			continue
		}
		text += l.src[l.pos].ascii_str()
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
	c := l.src[l.pos]
	if is_ident_start(c) {
		mut text := ''
		for l.pos < l.src.len && is_ident_char(l.src[l.pos]) {
			text += l.src[l.pos].ascii_str()
			l.advance()
		}
		// L"x", u'x' and u8"x" are one literal, not an identifier and a string.
		if l.pos < l.src.len && (l.src[l.pos] == `"` || l.src[l.pos] == `'`)
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
	for n in [3, 2, 1] {
		if l.pos + n > l.src.len {
			continue
		}
		text := l.src[l.pos..l.pos + n]
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
		ch := l.src[l.pos]
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
		if (ch == `+` || ch == `-`) && text.len > 0 && l.src[l.pos - 1] in [`e`, `E`, `p`, `P`] {
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
	quote := l.src[l.pos]
	kind := if quote == `"` { Kind.string } else { Kind.character }
	mut text := prefix + quote.ascii_str()
	l.advance()
	mut closed := false
	for l.pos < l.src.len {
		ch := l.src[l.pos]
		if ch == `\n` {
			break
		}
		if ch == `\\` {
			text += ch.ascii_str()
			l.advance()
			if l.pos < l.src.len {
				text += l.src[l.pos].ascii_str()
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

fn (mut l Lexer) advance() {
	if l.pos >= l.src.len {
		return
	}
	if l.src[l.pos] == `\n` {
		l.line++
		l.col = 1
		// The next token starts a line, and a `#` there opens a directive.
		l.at_line_start = true
	} else {
		l.col++
	}
	l.pos++
}

fn (l Lexer) peek(n int) u8 {
	if l.pos + n < l.src.len {
		return l.src[l.pos + n]
	}
	return 0
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
