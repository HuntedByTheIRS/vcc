module parser

// Literal conversion. Both of these report instead of guessing: a constant that
// does not fit, or a digit that is not valid for the base it was written in, is
// exactly the kind of thing a compiler must not quietly turn into a number.

// parse_integer_literal reads an integer constant in any of the bases C allows.
// Suffixes are accepted and dropped, since the stub has one integer type.
fn parse_integer_literal(text string) !i64 {
	mut body := text
	for body.len > 0 && body[body.len - 1] in [`u`, `U`, `l`, `L`] {
		body = body[..body.len - 1]
	}
	if body == '' {
		return error('${text}: not an integer constant')
	}
	mut base := 10
	mut digits := body
	if body.len > 1 && body[0] == `0` && (body[1] == `x` || body[1] == `X`) {
		base = 16
		digits = body[2..]
	} else if body.len > 1 && body[0] == `0` && (body[1] == `b` || body[1] == `B`) {
		base = 2
		digits = body[2..]
	} else if body.contains('.') || body.contains('e') || body.contains('E')
		|| body.ends_with('f') || body.ends_with('F') {
		return error('${text}: floating point literals are not implemented')
	} else if body.len > 1 && body[0] == `0` {
		base = 8
		digits = body[1..]
	}
	if digits == '' {
		// `0x` with nothing after it, which is a base marker and no number.
		return error('${text}: not an integer constant')
	}
	mut value := i64(0)
	for ch in digits {
		digit := digit_value(ch, base) or {
			return error('${text}: ${ch.ascii_str()} is not a digit in base ${base}')
		}
		if value > (i64(9223372036854775807) - i64(digit)) / i64(base) {
			return error('${text}: integer constant does not fit in 64 bits')
		}
		value = value * i64(base) + i64(digit)
	}
	return value
}

// parse_character_literal reads a character constant into its value. The result
// is an int in C, so that is what it becomes here.
fn parse_character_literal(text string) !i64 {
	mut body := text
	if body.len > 0 && (body[0] == `L` || body[0] == `u` || body[0] == `U`) {
		body = body[1..]
	}
	if body.len < 2 || body[0] != `'` || body[body.len - 1] != `'` {
		return error('${text}: not a character constant')
	}
	inner := body[1..body.len - 1]
	if inner == '' {
		return error('${text}: empty character constant')
	}
	if inner[0] != `\\` {
		if inner.len > 1 {
			return error('${text}: multi-character constants are not implemented')
		}
		return i64(inner[0])
	}
	return parse_escape(inner[1..]) or { error('${text}: ${err.msg()}') }
}

fn parse_escape(rest string) !i64 {
	if rest == '' {
		return error('the escape is not finished')
	}
	c := rest[0]
	if c == `x` || c == `X` {
		mut value := i64(0)
		mut seen := 0
		for i in 1 .. rest.len {
			digit := digit_value(rest[i], 16) or { break }
			value = value * 16 + i64(digit)
			seen++
		}
		if seen == 0 {
			return error('hex escape without digits')
		}
		return value
	}
	if c >= `0` && c <= `7` {
		mut value := i64(0)
		mut seen := 0
		for i in 0 .. rest.len {
			if seen == 3 {
				break
			}
			digit := digit_value(rest[i], 8) or { break }
			value = value * 8 + i64(digit)
			seen++
		}
		return value
	}
	return match c {
		`a` { i64(7) }
		`b` { i64(8) }
		`f` { i64(12) }
		`n` { i64(10) }
		`r` { i64(13) }
		`t` { i64(9) }
		`v` { i64(11) }
		`\\` { i64(92) }
		`'` { i64(39) }
		`"` { i64(34) }
		`?` { i64(63) }
		else { error('unknown escape sequence \\${c.ascii_str()}') }
	}
}

fn digit_value(ch u8, base int) ?int {
	digit := if ch >= `0` && ch <= `9` {
		int(ch - `0`)
	} else if ch >= `a` && ch <= `f` {
		int(ch - `a`) + 10
	} else if ch >= `A` && ch <= `F` {
		int(ch - `A`) + 10
	} else {
		return none
	}
	if digit >= base {
		return none
	}
	return digit
}
