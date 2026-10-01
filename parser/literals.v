module parser

import strconv

// Literal conversion. Both of these report instead of guessing: a constant that
// does not fit, or a digit that is not valid for the base it was written in, is
// exactly the kind of thing a compiler must not quietly turn into a number.

// parse_integer_literal reads an integer constant in any of the bases C allows.
// Suffixes are accepted and dropped here, since which type the suffix names is
// the type model's question and not this reader's.
//
// The value is accumulated as an unsigned 64-bit number so that the whole range
// of an `unsigned long long` is reachable: 18446744073709551615 is 2^64 - 1, and
// a program that writes it with a `ULL` suffix is a program this reader has to
// hand on rather than refuse. The result is returned as the 64-bit pattern, so a
// value whose top bit is set comes back as a negative i64 and the type model
// reads it as the unsigned value it was written as. Measured on gcc 16.2.1:
// `18446744073709551615ULL` is accepted and is `unsigned long long`.
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
		// A hexadecimal floating constant is a construct, and not a digit that
		// the base does not have. gcc refuses `0x1.8` as `hexadecimal floating
		// constants require an exponent` and compiles `0x1p3`, so reporting the
		// `p` as a digit base 16 is missing says the wrong thing about what the
		// program wrote. Its value needs a float type, which is the C2 lane's
		// work and the emitter's, so what is owed here is the honest half: the
		// refusal names the construct, and the caller reports the token this
		// text was read from, so it is named at its location too.
		if digits.contains('p') || digits.contains('P') {
			return error('${text}: hexadecimal floating constants are not implemented')
		}
		// `0x1.8` is the same construct short of its exponent, which gcc also
		// refuses, in these words: `hexadecimal floating constants require an
		// exponent`. Naming it is the same answer as above, and better than
		// reporting the point as a digit base 16 is missing.
		if digits.contains('.') {
			return error('${text}: hexadecimal floating constants require an exponent')
		}
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
	mut value := u64(0)
	for ch in digits {
		digit := digit_value(ch, base) or {
			return error('${text}: ${ch.ascii_str()} is not a digit in base ${base}')
		}
		step := u64(digit)
		if value > (max_u64 - step) / u64(base) {
			return error('${text}: integer constant does not fit in 64 bits')
		}
		value = value * u64(base) + step
	}
	return i64(value)
}

// max_u64 is the largest number 64 bits hold, which is the largest an integer
// constant may be. Past it the constant is not one this compiler can carry, and
// that is said rather than wrapped around to a smaller value.
const max_u64 = u64(18446744073709551615)

// is_floating_constant says whether a numeric token names a floating constant
// rather than an integer one. 6.4.4.2 makes that a question about the spelling
// and not about the value: a decimal constant is floating when it has a point or
// an exponent, so `1.0` and `1e3` are floating and `1` is not. A hexadecimal
// constant is decided by its `p` exponent instead, and those are refused by name
// in the integer reader, so this reads past them rather than calling `0x1E` a
// decimal constant with an exponent.
fn is_floating_constant(text string) bool {
	if text.len > 1 && text[0] == `0` && (text[1] == `x` || text[1] == `X`) {
		return false
	}
	return text.contains('.') || text.contains('e') || text.contains('E')
}

// parse_floating_literal reads a decimal floating constant into the double it
// names. A suffix is refused by name rather than dropped, because the two
// suffixes that exist name types this compiler does not have yet, and reading
// `1.5f` as a double would give the program a type it did not ask for. The
// value itself is converted exactly: the digits between the point and the
// exponent are the sign of a decimal fraction, and the conversion is the one
// that rounds to nearest.
fn parse_floating_literal(text string) !f64 {
	mut body := text
	if body.len > 0 {
		last := body[body.len - 1]
		if last == `f` || last == `F` {
			return error('${text}: a float literal names a type this compiler does not implement, and reading it as a double would change its value')
		}
		if last == `l` || last == `L` {
			return error('${text}: a long double literal names a type this compiler does not implement')
		}
	}
	if body == '' {
		return error('${text}: not a floating constant')
	}
	// The point may be the first or the last character, and 6.4.4.2 allows
	// both: `.5` and `5.` are floating constants, and `5.` is not the integer
	// 5 followed by nothing.
	mut digits := 0
	mut points := 0
	mut exponents := 0
	for i, ch in body {
		if ch == `.` {
			points++
			continue
		}
		if ch == `e` || ch == `E` {
			exponents++
			continue
		}
		if ch == `+` || ch == `-` {
			// A sign is part of the constant only when it follows the
			// exponent marker; anywhere else it is a token of its own and the
			// lexer would not have put it in this one.
			if i == 0 || (body[i - 1] != `e` && body[i - 1] != `E`) {
				return error('${text}: not a floating constant')
			}
			continue
		}
		if ch < `0` || ch > `9` {
			return error('${text}: ${ch.ascii_str()} is not part of a floating constant')
		}
		digits++
	}
	if digits == 0 {
		return error('${text}: not a floating constant')
	}
	if points > 1 || exponents > 1 {
		return error('${text}: not a floating constant')
	}
	if exponents == 1 {
		// The exponent needs digits after it, and an exponent part is what
		// makes `1e` a mistake rather than the integer 1.
		for i, ch in body {
			if ch == `e` || ch == `E` {
				rest := body[i + 1..]
				mut start := 0
				if rest.len > 0 && (rest[0] == `+` || rest[0] == `-`) {
					start = 1
				}
				if rest.len <= start {
					return error('${text}: an exponent with no digits')
				}
				break
			}
		}
	}
	value := strconv.atof64(body) or { return error('${text}: not a floating constant') }
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
	if c == `u` || c == `U` {
		// A universal character name in a literal is an escape whose value is
		// the character it names, written in the execution character set. That
		// encoding is the literal reader's next piece of work, so the refusal
		// names the construct rather than calling a name an unknown escape,
		// which is what the base's message did.
		return error('universal character names in a literal are not implemented')
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

// parse_string_literal reads a string literal into the bytes it names, with the
// escapes resolved. The spelling stays with the caller; what comes back is what
// the program would read.
fn parse_string_literal(text string) !string {
	mut body := text
	if body.len > 0 && body[0] != `"` {
		// A prefixed literal: u8"x", L"x", u"x", U"x". The narrow prefix names
		// the same bytes; the wide ones name an array of something this
		// compiler does not have, and guessing at it is worse than saying so.
		mut quote := 0
		for quote < body.len && body[quote] != `"` {
			quote++
		}
		if body[..quote] != 'u8' {
			return error('${text}: wide string literals are not implemented')
		}
		body = body[quote..]
	}
	if body.len < 2 || body[0] != `"` || body[body.len - 1] != `"` {
		return error('${text}: not a string constant')
	}
	inner := body[1..body.len - 1]
	mut bytes := []u8{}
	mut i := 0
	for i < inner.len {
		c := inner[i]
		if c != `\\` {
			bytes << c
			i++
			continue
		}
		if i + 1 < inner.len && inner[i + 1] == `\n` {
			// A backslash before the newline joins the two lines, and the pair
			// produces no byte at all.
			i += 2
			continue
		}
		value, next := parse_string_escape(inner, i + 1) or {
			return error('${text}: ${err.msg()}')
		}
		if value > 255 {
			return error('${text}: the escape names ${value}, which is not a byte')
		}
		bytes << u8(value)
		i = next
	}
	return bytes.bytestr()
}

// parse_string_escape reads the escape that starts at `at`, the byte after the
// backslash, and returns its value and the index after it. The escapes are the
// ones a character constant takes; a string needs the end of each escape as
// well, because the byte after a hex escape belongs to the string.
fn parse_string_escape(inner string, at int) !(i64, int) {
	if at >= inner.len {
		return error('the escape is not finished')
	}
	c := inner[at]
	if c == `x` || c == `X` {
		mut value := i64(0)
		mut seen := 0
		mut i := at + 1
		for i < inner.len {
			digit := digit_value(inner[i], 16) or { break }
			value = value * 16 + i64(digit)
			seen++
			i++
		}
		if seen == 0 {
			return error('hex escape without digits')
		}
		return value, i
	}
	if c >= `0` && c <= `7` {
		mut value := i64(0)
		mut seen := 0
		mut i := at
		for i < inner.len && seen < 3 {
			digit := digit_value(inner[i], 8) or { break }
			value = value * 8 + i64(digit)
			seen++
			i++
		}
		return value, i
	}
	value := parse_escape(c.ascii_str()) or { return error(err.msg()) }
	return value, at + 1
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
