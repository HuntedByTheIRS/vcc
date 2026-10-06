module parser

import tokenize

// This file is the GNU attribute grammar. An attribute is written
// `__attribute__((name))` or `__attribute__((name(argument)))`, and a
// declaration may carry several of them, in one list or in several specifiers.
//
// Reading and keeping are different answers here, the same as everywhere else in
// this file's neighbours. Three of the attributes this compiler reads say
// something about the object the compiler emits, and only two of those change
// it: `weak` changes a symbol's binding, `aligned(N)` asks for a stricter
// alignment than the object's type would give it, and `noreturn`, `noinline` and
// `dllimport` change nothing on this target, which is what gcc on Linux emits for
// them too. Every other attribute is a claim about the object this compiler
// cannot keep, so it is refused by name at the place it was written rather than
// read past.

// AttributeSet is what the attributes on one declaration say about the object it
// declares. Zero is no attributes.
struct AttributeSet {
mut:
	// weak says the declaration asked for the weak binding, which is what
	// `__attribute__((weak))` on a definition means: a definition a link may
	// take another of, rather than one that collides with a second.
	weak bool
	// alignment is the strictest alignment the declaration asked for with
	// `aligned(N)`, and zero when it asked for none.
	alignment int
	// cleanup is the name of the function a declaration asked for with
	// `cleanup(name)`, which the declaration runs on the object when the block
	// it was declared in ends. It is empty when none was asked for.
	cleanup string
}

// merge_attributes folds the attributes of a second list into the first. A
// declaration may carry more than one `__attribute__` specifier and 6.7 makes
// all of them say something about the same object, so a strict alignment asked
// for twice is the stricter of the two and a weak binding asked for once is
// enough. A cleanup asked for twice is a constraint violation in gcc, and the
// later name is the one kept here: the reader that places the attribute reports
// the second, so this folding never has to.
fn merge_attributes(a AttributeSet, b AttributeSet) AttributeSet {
	return AttributeSet{
		weak:      a.weak || b.weak
		alignment: if b.alignment > a.alignment { b.alignment } else { a.alignment }
		cleanup:   if b.cleanup != '' { b.cleanup } else { a.cleanup }
	}
}

// parse_attribute_specifiers reads a run of `__attribute__((...))` specifiers
// and answers what they say about the declaration they sit on. It reads nothing
// when the cursor is not at one, so a caller may ask at every place an attribute
// can stand without first checking the token.
//
// `report` says whether an attribute this compiler does not implement is refused
// here. It is true in the position a declaration opens with, which is where V's
// generated C writes one and where the attribute belongs to a declaration this
// compiler is about to emit; there a name it cannot keep is refused by name. It
// is false where a system header writes an attribute in a place this reader has
// always stepped over, because refusing there would refuse the headers the
// compiler reads today. What the two attributes that change the object say is
// read in both cases, so `weak` and `aligned(N)` are honoured wherever a
// declaration carries them.
fn (mut p Parser) parse_attribute_specifiers(report bool) AttributeSet {
	mut set := AttributeSet{}
	for {
		t := p.peek()
		if t.kind != .identifier || t.text != '__attribute__' {
			return set
		}
		p.next()
		if !p.at_punct('(') {
			p.error_at(p.peek(), 'unsupported: expected ( after __attribute__, found ${describe(p.peek())}')
			return set
		}
		open := p.next()
		// GNU writes the attribute list inside a second pair of parentheses,
		// `__attribute__((name, name))`, and gcc 16.2.1 also accepts one pair,
		// `__attribute__((name))`. Which was written is the token after the
		// opening bracket.
		double := p.at_punct('(')
		if double {
			p.next()
		}
		set = merge_attributes(set, p.parse_attribute_list(open, report))
		if double && !p.expect_punct(')') {
			return set
		}
		if !p.expect_punct(')') {
			return set
		}
	}
	return set
}

// parse_attribute_list reads the comma-separated attributes inside one
// `__attribute__` list and answers what they say. The cursor is left at the
// closing parenthesis of the list, which is the one the caller consumed the
// opening of.
fn (mut p Parser) parse_attribute_list(open tokenize.Token, report bool) AttributeSet {
	mut set := AttributeSet{}
	for {
		t := p.peek()
		if t.kind == .punct && t.text == ')' {
			// An empty list, `__attribute__(())`, which gcc accepts and which
			// says nothing.
			return set
		}
		if t.kind != .identifier {
			p.error_at(t, 'unsupported: expected an attribute name, found ${describe(t)}')
			return set
		}
		p.next()
		mut args := []tokenize.Token{}
		if p.at_punct('(') {
			args = p.parse_attribute_arguments(open)
		}
		set = merge_attributes(set, p.read_attribute(t, args, report))
		if p.at_punct(',') {
			p.next()
			continue
		}
		return set
	}
	return set
}

// parse_attribute_arguments consumes the parenthesised argument of one
// attribute and answers the tokens inside it, the brackets excluded. A
// parenthesis nested in the argument is counted, so the argument ends at the
// bracket that belongs to it rather than at the first one.
fn (mut p Parser) parse_attribute_arguments(open tokenize.Token) []tokenize.Token {
	p.next()
	mut depth := 1
	mut args := []tokenize.Token{}
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unsupported: unterminated __attribute__ opened at ${open.line}:${open.col}')
			return args
		}
		if t.kind == .punct && t.text == '(' {
			depth++
		} else if t.kind == .punct && t.text == ')' {
			depth--
			if depth == 0 {
				p.next()
				return args
			}
		}
		args << t
		p.next()
	}
	return args
}

// read_attribute is what one attribute says about the declaration it sits on.
// The name is the GNU spelling with the double underscores GNU allows around it
// stripped, so `__weak__` and `weak` are one attribute. An attribute this
// compiler does not implement is reported by name at the place it was written
// when `report` is set, and contributes nothing either way: silently reading past
// one would emit an object the program's author asked to be something else.
fn (mut p Parser) read_attribute(at tokenize.Token, args []tokenize.Token, report bool) AttributeSet {
	name := gnu_attribute_name(at.text)
	match name {
		'weak' {
			return AttributeSet{
				weak: true
			}
		}
		'aligned' {
			value := attribute_alignment(args) or {
				if report {
					p.error_at(at, "unsupported: the attribute 'aligned' asks for the alignment '${attribute_arguments_text(args)}', and this compiler reads one integer that is a power of two")
				}
				return AttributeSet{}
			}
			return AttributeSet{
				alignment: value
			}
		}
		'noreturn', 'noinline', 'dllimport' {
			// None of these changes the object this target emits: noreturn and
			// noinline say what a compiler may assume about a call, not what it
			// writes, and dllimport is a fact about another system. gcc 16.2.1 on
			// Linux accepts all three and emits the same object without them, so
			// this compiler accepts them and records nothing.
			return AttributeSet{}
		}
		'cleanup' {
			// GCC 6.4.1: the attribute names one function, which is called with
			// the address of the object when the block the object was declared
			// in ends. The name is read here and the call is the back end's. An
			// argument that is not a single name is refused by name rather than
			// read as though some other function had been written.
			if args.len != 1 || args[0].kind != .identifier {
				if report {
					p.error_at(at, "unsupported: the attribute 'cleanup' names the one function to run on the object, and '${attribute_arguments_text(args)}' is not a name")
				}
				return AttributeSet{}
			}
			return AttributeSet{
				cleanup: args[0].text
			}
		}
		else {
			if report {
				p.error_at(at, "unsupported: the attribute '${name}' is not implemented")
			}
			return AttributeSet{}
		}
	}
	return AttributeSet{}
}

// gnu_attribute_name is the name of an attribute with the double underscores GNU
// allows around it stripped, which is what makes `__weak__` and `weak` the same
// attribute.
fn gnu_attribute_name(text string) string {
	if text.len > 4 && text.starts_with('__') && text.ends_with('__') {
		return text[2..text.len - 2]
	}
	return text
}

// attribute_arguments_text is the argument of an attribute as it was written, for
// a refusal that names what it could not read rather than only that it could not.
fn attribute_arguments_text(args []tokenize.Token) string {
	mut parts := []string{cap: args.len}
	for t in args {
		parts << t.text
	}
	return parts.join(' ')
}

// attribute_alignment reads the one argument `aligned(N)` takes. The argument is
// an integer that is a power of two, which is what gcc 16.2.1 requires of it:
// measured, `aligned(3)` is `requested alignment is not a power of 2` and a
// non-constant argument is `requested alignment is not an integer constant`. A
// shape this compiler cannot fold is left to the caller's refusal.
fn attribute_alignment(args []tokenize.Token) ?int {
	if args.len != 1 || args[0].kind != .number {
		return none
	}
	value := attribute_number(args[0].text) or { return none }
	if value <= 0 || (value & (value - 1)) != 0 {
		return none
	}
	return value
}

// attribute_number reads the value of an integer token, decimal, hexadecimal or
// octal by its written base. The attributes this compiler honours take a plain
// integer, and one it cannot read is refused rather than guessed at.
fn attribute_number(text string) ?int {
	mut digits := text
	mut base := 10
	if digits.starts_with('0x') || digits.starts_with('0X') {
		digits = digits[2..]
		base = 16
	} else if digits.len > 1 && digits.starts_with('0') {
		digits = digits[1..]
		base = 8
	}
	if digits.len == 0 {
		return none
	}
	mut value := 0
	for c in digits {
		mut digit := 0
		if c >= `0` && c <= `9` {
			digit = int(c - `0`)
		} else if c >= `a` && c <= `f` {
			digit = int(c - `a`) + 10
		} else if c >= `A` && c <= `F` {
			digit = int(c - `A`) + 10
		} else {
			return none
		}
		if digit >= base {
			return none
		}
		value = value * base + digit
	}
	return value
}
