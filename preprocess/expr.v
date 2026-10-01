module preprocess

import tokenize

// The controlling expression of an #if is read before anything else on the
// line matters, so it has its own reader and its own arithmetic. Macros in it
// are expanded, `defined` is answered from the macro table before that
// expansion, every name that is left over is zero, and the operators are C's
// with C's precedence, because what these expressions come from is headers
// written for a C compiler.
//
// Everything is read as a signed 64-bit integer, which is what C calls
// intmax_t, and the arithmetic wraps instead of trapping. The unsigned half of
// C's type rules — whether `-1 < 1u` is true — is not modeled; no header in the
// tree's way needs it yet.

// Condition is one #if expression: the tokens to read, where the reader is, and
// what it has to report.
struct Condition {
mut:
	tokens      []tokenize.Token
	pos         int
	diagnostics []tokenize.Diagnostic
	file        string
	line        int
	col         int
}

// parse reads the whole expression and refuses anything left over, so a token
// the evaluator did not understand is a diagnostic instead of a value that
// silently ignored it.
fn (mut c Condition) parse() ?i64 {
	value := c.ternary(true) or { return none }
	if c.pos < c.tokens.len {
		c.problem('the #if expression has something this evaluator cannot read: ${c.tokens[c.pos].text}')
		return none
	}
	return value
}

fn (mut c Condition) ternary(evaluate bool) ?i64 {
	condition := c.binary(1, evaluate)?
	if !c.at('?') {
		return condition
	}
	c.pos++
	taken := condition != 0
	then_value := c.ternary(evaluate && taken)?
	if !c.at(':') {
		c.problem('the #if expression has a ? with no :')
		return none
	}
	c.pos++
	else_value := c.ternary(evaluate && !taken)?
	if !evaluate {
		return 0
	}
	return if taken { then_value } else { else_value }
}

// binary reads an expression by precedence, the way every C expression reader
// does. evaluate is false on the side of a && or || or ?: that is not taken:
// the tokens are still read, and nothing is computed from them — which is what
// keeps `#if 0 && 1 / 0` from being a division by zero.
fn (mut c Condition) binary(min int, evaluate bool) ?i64 {
	mut left := c.unary(evaluate)?
	for c.pos < c.tokens.len {
		t := c.tokens[c.pos]
		if t.kind != .punct {
			break
		}
		precedence := binary_precedence(t.text)
		if precedence == 0 || precedence < min {
			break
		}
		c.pos++
		if t.text == '&&' {
			right := c.binary(precedence + 1, evaluate && left != 0)?
			left = if left != 0 && right != 0 { i64(1) } else { i64(0) }
			continue
		}
		if t.text == '||' {
			right := c.binary(precedence + 1, evaluate && left == 0)?
			left = if left != 0 || right != 0 { i64(1) } else { i64(0) }
			continue
		}
		right := c.binary(precedence + 1, evaluate)?
		left = c.apply(t, left, right, evaluate)?
	}
	return left
}

fn (mut c Condition) unary(evaluate bool) ?i64 {
	if c.pos >= c.tokens.len {
		c.problem('the #if expression ends where a value was expected')
		return none
	}
	t := c.tokens[c.pos]
	if t.kind == .punct && t.text in ['-', '+', '!', '~'] {
		c.pos++
		operand := c.unary(evaluate)?
		if !evaluate {
			return 0
		}
		return match t.text {
			'-' { wrap_sub(i64(0), operand) }
			'+' { operand }
			'!' {
				if operand == 0 {
					i64(1)
				} else {
					i64(0)
				}
			}
			else { ~operand }
		}
	}
	return c.primary(evaluate)
}

fn (mut c Condition) primary(evaluate bool) ?i64 {
	if c.pos >= c.tokens.len {
		c.problem('the #if expression ends where a value was expected')
		return none
	}
	t := c.tokens[c.pos]
	if t.kind == .punct && t.text == '(' {
		c.pos++
		value := c.ternary(evaluate)?
		if !c.at(')') {
			c.problem('the #if expression has a ( with no )')
			return none
		}
		c.pos++
		return value
	}
	if t.kind == .number {
		c.pos++
		return integer_literal_value(t.text) or {
			c.problem('${t.text} is not an integer constant the #if evaluator can read')
			return none
		}
	}
	if t.kind == .character {
		c.pos++
		return character_value(t.text) or {
			c.problem('${t.text} is not a character constant the #if evaluator can read')
			return none
		}
	}
	if t.kind == .identifier {
		// A name that is still here after expansion is not defined, and C says
		// an undefined name in an #if is zero. `defined` was answered before
		// expansion, so it never reaches this arm as an operator.
		c.pos++
		return 0
	}
	c.problem('the #if expression has a value where none can be read: ${t.text}')
	return none
}

// apply does the arithmetic of one operator. evaluate is false inside a branch
// that was not taken, where the answer is not used and the checks are not run.
fn (mut c Condition) apply(op tokenize.Token, left i64, right i64, evaluate bool) ?i64 {
	if !evaluate {
		return 0
	}
	return match op.text {
		'+' { wrap_add(left, right) }
		'-' { wrap_sub(left, right) }
		'*' { wrap_mul(left, right) }
		'/' {
			if right == 0 {
				c.problem('division by zero in a #if expression')
				return none
			}
			left / right
		}
		'%' {
			if right == 0 {
				c.problem('division by zero in a #if expression')
				return none
			}
			left % right
		}
		'<' {
			i64(bool_to_int(left < right))
		}
		'>' {
			i64(bool_to_int(left > right))
		}
		'<=' {
			i64(bool_to_int(left <= right))
		}
		'>=' {
			i64(bool_to_int(left >= right))
		}
		'==' {
			i64(bool_to_int(left == right))
		}
		'!=' {
			i64(bool_to_int(left != right))
		}
		'&' { left & right }
		'|' { left | right }
		'^' { left ^ right }
		'<<' {
			if right < 0 || right >= 64 {
				c.problem('the #if expression shifts by ${right}, which is outside the 64 bits it is evaluated in')
				return none
			}
			i64(u64(left) << u64(right))
		}
		'>>' {
			if right < 0 || right >= 64 {
				c.problem('the #if expression shifts by ${right}, which is outside the 64 bits it is evaluated in')
				return none
			}
			left >> u64(right)
		}
		else {
			c.problem('the #if expression has an operator this evaluator cannot read: ${op.text}')
			return none
		}
	}
}

fn binary_precedence(op string) int {
	return match op {
		'||' { 1 }
		'&&' { 2 }
		'|' { 3 }
		'^' { 4 }
		'&' { 5 }
		'==', '!=' { 6 }
		'<', '>', '<=', '>=' { 7 }
		'<<', '>>' { 8 }
		'+', '-' { 9 }
		'*', '/', '%' { 10 }
		else { 0 }
	}
}

fn (mut c Condition) at(text string) bool {
	if c.pos >= c.tokens.len {
		return false
	}
	t := c.tokens[c.pos]
	return t.kind == .punct && t.text == text
}

fn (mut c Condition) problem(msg string) {
	t := if c.pos < c.tokens.len {
		c.tokens[c.pos]
	} else {
		tokenize.Token{
			line: c.line
			col:  c.col
		}
	}
	c.diagnostics << tokenize.Diagnostic{
		line: t.line
		col:  t.col
		msg:  msg
		file: c.file
	}
}

fn bool_to_int(value bool) int {
	return if value { 1 } else { 0 }
}

// integer_literal_value reads a number the way an #if has to: decimal, octal,
// hexadecimal and the 0b form, with the suffixes a literal may wear. Anything
// else — a float, a stray character — is refused so the caller can say so.
fn integer_literal_value(text string) ?i64 {
	mut body := text
	mut base := 10
	if body.starts_with('0x') || body.starts_with('0X') {
		base = 16
		body = body[2..]
	} else if body.starts_with('0b') || body.starts_with('0B') {
		base = 2
		body = body[2..]
	} else if body.len > 1 && body[0] == `0` {
		base = 8
		body = body[1..]
	}
	mut digits := ''
	for i in 0 .. body.len {
		c := body[i]
		if c == `u` || c == `U` || c == `l` || c == `L` {
			break
		}
		digits += c.ascii_str()
	}
	if digits == '' {
		if text == '0' {
			return 0
		}
		return none
	}
	mut value := u64(0)
	for i in 0 .. digits.len {
		c := digits[i]
		digit := digit_value(c) or { return none }
		if digit >= base {
			return none
		}
		value = value * u64(base) + u64(digit)
	}
	return i64(value)
}

fn digit_value(c u8) ?int {
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

// character_value reads a character constant to the value it stands for. The
// escapes are the ones a C compiler has to know; a multi-character constant is
// C's implementation-defined case and is refused rather than guessed at.
fn character_value(text string) ?i64 {
	// C99 6.4.4.4 lets a character constant name the encoding of what it holds: `L` for
	// wchar_t, `u` for char16_t, `U` for char32_t. The #if evaluator wants the value, and
	// the prefix does not change it, so the prefix is dropped and the constant read the
	// same way either side of it. This is not a corner: glibc's <bits/wchar.h> asks
	// `#elif L'\0' - 1 > 0`, so a prefix refused here refuses every translation unit that
	// includes <wchar.h>.
	mut quoted := text
	for prefix in ['u8', 'L', 'u', 'U'] {
		if quoted.starts_with(prefix) {
			quoted = quoted[prefix.len..]
			break
		}
	}
	if quoted.len < 3 || quoted[0] != `'` || quoted[quoted.len - 1] != `'` {
		return none
	}
	body := quoted[1..quoted.len - 1]
	if body.len == 0 {
		return none
	}
	if body[0] == `\\` {
		if body.len < 2 {
			return none
		}
		escaped := body[1]
		return match escaped {
			`n` { i64(10) }
			`t` { i64(9) }
			`r` { i64(13) }
			`0` { i64(0) }
			`a` { i64(7) }
			`b` { i64(8) }
			`f` { i64(12) }
			`v` { i64(11) }
			`\\`, `'`, `"`, `?` { i64(escaped) }
			else { none }
		}
	}
	if body.len != 1 {
		return none
	}
	return i64(body[0])
}

// The wrapping arithmetic is the same three helpers the emitter uses, written
// once more here because the two stages do not depend on each other yet. When
// they do, this file and the emitter should share one copy.
fn wrap_add(a i64, b i64) i64 {
	return i64(u64(a) + u64(b))
}

fn wrap_sub(a i64, b i64) i64 {
	return i64(u64(a) - u64(b))
}

fn wrap_mul(a i64, b i64) i64 {
	return i64(u64(a) * u64(b))
}
