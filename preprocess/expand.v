module preprocess

import standard
import tokenize

// Expanding a macro with arguments is the part of the preprocessor that is
// rules rather than code: which tokens are the arguments, which of them are
// replaced before the substitution and which are not, what a # does to one and
// what a ## does to two, and what stops an expansion that would otherwise go on
// forever. There is one function here per rule, in roughly the order the
// standard states them.

// Arguments is one macro use after the name: the argument lists, and where the
// tokens after the call begin.
struct Arguments {
	// called is false when the name was not a call at all — a function-like
	// macro's name with no ( after it is just a name in the text.
	called bool
	lists  [][]tokenize.Token
	// next is the index of the first token after the call's closing ), or
	// where the reader already was when there was no call.
	next int
}

// collect_arguments reads the argument list of a macro use starting at the
// token after the name. Commas inside parentheses are part of an argument and
// commas at the top level separate them, which is the only kind of nesting C
// protects.
fn (mut p Processor) collect_arguments(tokens []tokenize.Token, from int, tok tokenize.Token) Arguments {
	if from >= tokens.len {
		return Arguments{
			next: from
		}
	}
	open := tokens[from]
	if open.kind != .punct || open.text != '(' {
		return Arguments{
			next: from
		}
	}
	mut lists := [][]tokenize.Token{}
	mut current := []tokenize.Token{}
	mut depth := 1
	mut i := from + 1
	for i < tokens.len {
		t := tokens[i]
		if t.kind == .punct {
			if t.text == '(' {
				depth++
			} else if t.text == ')' {
				depth--
				if depth == 0 {
					lists << current
					return Arguments{
						called: true
						lists:  lists
						next:   i + 1
					}
				}
			} else if t.text == ',' && depth == 1 {
				lists << current
				current = []tokenize.Token{}
				i++
				continue
			}
		}
		current << t
		i++
	}
	p.problem(tok, 'the arguments of ${tok.text} have no closing )')
	return Arguments{
		next: tokens.len
	}
}

// expand_all returns the tokens with every macro use in them expanded. A name
// that takes arguments is a call only when a ( follows it, and the arguments
// are read from the tokens after it in the same list — which is what a call in
// a file looks like, what a call inside a replacement looks like, and what a
// call in the controlling expression of an #if looks like.
fn (mut p Processor) expand_all(tokens []tokenize.Token) []tokenize.Token {
	// Expansion is recursive, and the guard that stops a macro naming itself
	// stops the shapes a person writes. This limit is for the shapes nobody
	// writes: without it, one that slipped past the guard would be a crash
	// instead of a diagnostic.
	if p.expansion_depth >= max_expansion_depth {
		if !p.expansion_reported && tokens.len > 0 {
			p.expansion_reported = true
			p.problem(tokens[0], 'the expansion here is ${max_expansion_depth} levels deep and still going')
		}
		return tokens
	}
	p.expansion_depth++
	defer {
		p.expansion_depth--
	}
	mut out := []tokenize.Token{}
	mut i := 0
	for i < tokens.len {
		tok := tokens[i]
		if tok.kind != .identifier {
			out << tok
			i++
			continue
		}
		if tok.text == '_Pragma' {
			// `_Pragma("...")` is how a macro says a pragma, which is why it is
			// an operator and not a directive: the tokens are already past the
			// line start by the time they exist. A pragma this compiler has
			// nothing to say about is nothing, so the shape is read and the
			// text is left out.
			if after := pragma_operator(tokens, i) {
				i = after
				continue
			}
		}
		if tok.text !in p.macros {
			// __LINE__ and __FILE__ are the macros whose value is where they
			// were written, and a program that defined one of them itself has
			// the macro table answering for it instead.
			if builtin := p.dynamic_builtin(tok) {
				for t in builtin {
					out << t
				}
				i++
				continue
			}
			out << tok
			i++
			continue
		}
		macro := p.macros[tok.text]
		if macro.takes_arguments() {
			if tok.text in p.expanding {
				// The name is being expanded right now, so this occurrence is
				// the text it stands for: this is the same rule as for an
				// object-like macro, and it is what stops a replacement that
				// calls the macro it came from.
				out << tok
				i++
				continue
			}
			use_args := p.collect_arguments(tokens, i + 1, tok)
			if !use_args.called {
				// The name of a function-like macro with no ( after it is not
				// a use of it, and C says it stays where it is.
				out << tok
				i++
				continue
			}
			out << p.expand_call(tok, macro, use_args)
			i = use_args.next
			continue
		}
		if tok.text in p.expanding {
			// The name is being expanded right now, so this occurrence is the
			// text it stands for and not another expansion. This is the rule
			// that makes `#define A B` beside `#define B A` terminate.
			out << tok
			i++
			continue
		}
		p.expanding << tok.text
		mut replacement := []tokenize.Token{}
		for body_token in macro.body {
			replacement << at_use_site(body_token, tok)
		}
		out << p.expand_all(replacement)
		p.expanding.delete(p.expanding.len - 1)
		i++
	}
	return out
}

// expand_call expands one use of a macro that takes arguments: the arguments go
// where the parameters are, and the result is read again for macro uses of its
// own.
//
// The name goes on the expansion stack for that second read and not before it,
// because the arguments are expanded as if they stood on their own — `F(F(1))`
// is the inner F being replaced — while a replacement that names the macro it
// came from is exactly the case the stack is there to stop.
fn (mut p Processor) expand_call(tok tokenize.Token, macro Macro, use_args Arguments) []tokenize.Token {
	replacement := p.substitute(macro, use_args, tok)
	p.expanding << tok.text
	expanded := p.expand_all(replacement)
	p.expanding.delete(p.expanding.len - 1)
	return expanded
}

// substitute is the replacement itself: every parameter is replaced by its
// argument, # stringizes the argument it is in front of, ## joins the tokens
// around it into one, and __VA_ARGS__ stands for the arguments after the named
// parameters.
fn (mut p Processor) substitute(macro Macro, arguments Arguments, tok tokenize.Token) []tokenize.Token {
	mut lists := arguments.lists.clone()
	// `F()` is one empty argument to a macro that takes one, and no arguments
	// at all to a macro that takes none: the count is what tells the two
	// apart, and the count is what the standard says to read it by.
	if lists.len == 1 && lists[0].len == 0 && macro.params.len == 0 {
		lists.clear()
	}
	if macro.variadic {
		if lists.len < macro.params.len {
			p.problem(tok, '${tok.text} takes at least ${macro.params.len} ${argument_word(macro.params.len)} and ${lists.len} ${were_word(lists.len)} given')
			for lists.len < macro.params.len {
				lists << []tokenize.Token{}
			}
		}
	} else if lists.len != macro.params.len {
		p.problem(tok, '${tok.text} takes ${macro.params.len} ${argument_word(macro.params.len)} and ${lists.len} ${were_word(lists.len)} given')
		for lists.len < macro.params.len {
			lists << []tokenize.Token{}
		}
		lists = lists[..macro.params.len]
	}
	mut args := map[string][]tokenize.Token{}
	for index, param in macro.params {
		args[param] = if index < lists.len { lists[index] } else { []tokenize.Token{} }
	}
	if macro.variadic {
		// __VA_ARGS__ is every argument from the variadic one on, with the
		// commas between them, because that is what the caller wrote and that
		// is what the replacement has to say.
		mut rest := []tokenize.Token{}
		for index in macro.params.len .. lists.len {
			if index > macro.params.len {
				rest << tokenize.Token{
					kind: .punct
					text: ','
					line: tok.line
					col:  tok.col
					file: tok.file
				}
			}
			rest << lists[index]
		}
		args['__VA_ARGS__'] = rest
	}
	mut out := []tokenize.Token{}
	mut i := 0
	for i < macro.body.len {
		t := macro.body[i]
		if t.kind == .punct && t.text == '#' {
			// # puts the argument in a string literal without expanding it,
			// which is what makes a macro turn a name into a message.
			if i + 1 < macro.body.len && macro.body[i + 1].kind == .identifier && macro.body[i + 1].text in args {
				out << stringized(args[macro.body[i + 1].text], tok)
				i += 2
				continue
			}
			p.problem(tok, 'the # in the replacement of ${tok.text} is not in front of one of its parameters')
			i++
			continue
		}
		if t.kind == .punct && t.text == '##' {
			if i + 1 >= macro.body.len {
				p.problem(tok, 'the ## at the end of the replacement of ${tok.text} has nothing to join')
				i++
				continue
			}
			next := macro.body[i + 1]
			right := if next.kind == .identifier && next.text in args {
				args[next.text]
			} else {
				[at_use_site(next, tok)]
			}
			if right.len == 0 {
				// An empty argument on the right of a ##: nothing is joined,
				// and the token on the left stands alone. `, ## __VA_ARGS__`
				// with no arguments after it is the reason the rule exists:
				// it is how a macro writes a comma that is only there when
				// something follows it.
				if macro.variadic && out.len > 0 && out.last().kind == .punct && out.last().text == ',' {
					out.delete(out.len - 1)
				}
				i += 2
				continue
			}
			if macro.variadic && next.text == '__VA_ARGS__' && out.len > 0 && out.last().kind == .punct && out.last().text == ',' {
				// With arguments, the same spelling writes the comma and the
				// tokens out as they are: a comma joined to the token after it
				// is not a paste anybody means.
				for u in right {
					out << u
				}
				i += 2
				continue
			}
			if out.len == 0 {
				for u in right {
					out << u
				}
				i += 2
				continue
			}
			left := out.last()
			out.delete(out.len - 1)
			for u in p.paste(left, right[0], tok) {
				out << u
			}
			for u in right[1..] {
				out << u
			}
			i += 2
			continue
		}
		if t.kind == .identifier && t.text in args {
			raw := args[t.text]
			// An argument is expanded before it is put in place — unless it
			// stands beside a # or a ##, where the tokens themselves are the
			// point and the expansion would lose them.
			beside_paste := (i + 1 < macro.body.len && is_paste(macro.body[i + 1])) || (i > 0 && is_paste(macro.body[i - 1]))
			mut text := []tokenize.Token{}
			for argument_token in raw {
				text << at_use_site(argument_token, tok)
			}
			if !beside_paste {
				text = p.expand_all(text)
			}
			for u in text {
				out << u
			}
			i++
			continue
		}
		out << at_use_site(t, tok)
		i++
	}
	return out
}

// paste joins two tokens into one by writing them together and reading the
// result back, which is what a preprocessor does with ##: `__GLIBC_USE_ ## F`
// is how a header builds one name out of two pieces.
//
// Two tokens that do not read back as one are not a paste. The standard leaves
// the answer undefined there, and both tokens are kept, because both of them
// are real and the one that is not real is the joined one.
fn (mut p Processor) paste(left tokenize.Token, right tokenize.Token, tok tokenize.Token) []tokenize.Token {
	joined := left.text + right.text
	lexed := tokenize.lex_fragment(joined, standard.has_digraphs(p.opts.dialect))
	if lexed.len == 1 {
		return [
			tokenize.Token{
				kind: lexed[0].kind
				text: lexed[0].text
				line: tok.line
				col:  tok.col
				file: tok.file
			},
		]
	}
	p.problem(tok, 'the ## in the replacement of ${tok.text} joins ${left.text} and ${right.text}, which do not make one token')
	return [left, right]
}

fn is_paste(t tokenize.Token) bool {
	return t.kind == .punct && t.text == '##'
}

// stringized writes an argument the way a # writes it: the tokens as they were
// spelled with one space between them, quoted, and with the quotes and
// backslashes of the text escaped so the result is the string literal it says
// it is.
fn stringized(tokens []tokenize.Token, tok tokenize.Token) tokenize.Token {
	mut spelling := ''
	for index, t in tokens {
		if index > 0 {
			spelling += ' '
		}
		spelling += t.text
	}
	mut quoted := '"'
	for i in 0 .. spelling.len {
		c := spelling[i]
		if c == `"` || c == `\\` {
			quoted += '\\'
		}
		quoted += c.ascii_str()
	}
	quoted += '"'
	return tokenize.Token{
		kind: .string
		text: quoted
		line: tok.line
		col:  tok.col
		file: tok.file
	}
}

// at_use_site moves a token of a replacement or of an argument to the place the
// macro was used: what the standard asks, and what makes a diagnostic inside an
// expansion point at something a person wrote.
fn at_use_site(t tokenize.Token, use tokenize.Token) tokenize.Token {
	return tokenize.Token{
		kind: t.kind
		text: t.text
		line: use.line
		col:  use.col
		file: use.file
	}
}

fn argument_word(count int) string {
	return if count == 1 { 'argument' } else { 'arguments' }
}

fn were_word(count int) string {
	return if count == 1 { 'was' } else { 'were' }
}

// pragma_operator reads `_Pragma ( "text" )` starting at the name and returns
// where the tokens after it start, or nothing when what follows is not that
// shape — in which case the name is a name and the caller writes it out. The
// operand has to be one string literal and nothing else, which is what makes the
// operator impossible to get wrong in the way a pragma spelled across lines is.
fn pragma_operator(tokens []tokenize.Token, at int) ?int {
	if at + 3 >= tokens.len {
		return none
	}
	if tokens[at + 1].text != '(' || tokens[at + 2].kind != .string || tokens[at + 3].text != ')' {
		return none
	}
	return at + 4
}
