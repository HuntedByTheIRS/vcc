module preprocess

import standard
import tokenize

// Expanding a macro with arguments is the part of the preprocessor that is
// rules rather than code: which tokens are the arguments, which of them are
// replaced before the substitution and which are not, what a # does to one and
// what a ## does to two, and what stops an expansion that would otherwise go on
// forever. There is one function here per rule, in roughly the order the
// standard states them.
//
// The rule that stops an expansion is kept on the tokens rather than in a stack
// of the names being expanded. The standard says a macro name that arrived
// while that macro's own replacement was being built is not replaced again, and
// that is a property of the token: it stays true however many times the token is
// read afterwards. A stack answers a different question — which macros are being
// expanded right now — and the two answers part company when an argument is
// expanded before it is put in place. By the time the whole replacement is read
// again the argument's own macro has left the stack, so a name the argument was
// meant to keep quiet becomes live a second time; and a name that second read
// produces while the outer macro is still on the stack is left standing as
// ordinary text. glibc's <tgmath.h> nests macros deeply enough to reach both.

// Piece is one preprocessing token together with the names it is hidden from:
// the macro whose replacement produced it, and the macros that hid the place it
// was produced. A name in that set is not a use of that macro, however often the
// token is read again.
struct Piece {
	tok  tokenize.Token
	hide []string
}

// produced_from turns a token of a replacement into the text of the expansion
// that happened at `site`: moved there for a diagnostic, and hidden from the
// macro being expanded and from everything that hid the use itself. The second
// part is what carries hiding around a corner: `#define A B` beside
// `#define B A` terminates because the B that A produced is hidden from A, and
// the A that B produces is hidden from both.
fn produced_from(piece Piece, site Piece) Piece {
	mut hide := piece.hide.clone()
	for name in site.hide {
		if name !in hide {
			hide << name
		}
	}
	if site.tok.text !in hide {
		hide << site.tok.text
	}
	return Piece{
		tok:  at_use_site(piece.tok, site.tok)
		hide: hide
	}
}

// shared_hide is the names the two tokens around a ## have in common. The token
// they make is hidden from those and from no other: a name that hid only one of
// the two suppressed a token that is no longer there on its own, and holding it
// against the joined token would keep a name-built-out-of-two-pieces from ever
// being read as the name it spells.
fn shared_hide(left Piece, right Piece) []string {
	mut shared := []string{}
	for name in left.hide {
		if name in right.hide {
			shared << name
		}
	}
	return shared
}

// Arguments is one macro use after the name: the argument lists, and where the
// tokens after the call begin.
struct Arguments {
	// called is false when the name was not a call at all — a function-like
	// macro's name with no ( after it is just a name in the text.
	called bool
	lists  [][]Piece
	// seps[i] says a run of whitespace stood in front of the comma that
	// separates lists[i] from lists[i + 1]. The comma itself is not part of
	// either argument, so its spelling is kept here: stringizing __VA_ARGS__
	// writes those commas back between the arguments, and whether a space
	// stood before one is the source's answer and not this compiler's.
	seps []bool
	// next is the index of the first token after the call's closing ), or
	// where the reader already was when there was no call.
	next int
}

// collect_arguments reads the argument list of a macro use starting at the
// token after the name. Commas inside parentheses are part of an argument and
// commas at the top level separate them, which is the only kind of nesting C
// protects.
fn (mut p Processor) collect_arguments(tokens []Piece, from int, tok tokenize.Token) Arguments {
	if from >= tokens.len {
		return Arguments{
			next: from
		}
	}
	open := tokens[from]
	if open.tok.kind != .punct || open.tok.text != '(' {
		return Arguments{
			next: from
		}
	}
	mut lists := [][]Piece{}
	mut seps := []bool{}
	mut current := []Piece{}
	mut depth := 1
	mut i := from + 1
	for i < tokens.len {
		t := tokens[i]
		if t.tok.kind == .punct {
			if t.tok.text == '(' {
				depth++
			} else if t.tok.text == ')' {
				depth--
				if depth == 0 {
					lists << current
					return Arguments{
						called: true
						lists:  lists
						seps:   seps
						next:   i + 1
					}
				}
			} else if t.tok.text == ',' && depth == 1 {
				lists << current
				seps << t.tok.space
				current = []Piece{}
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
	// A run with no name that could expand is handed back as it stands. Every
	// token of straight-line code would otherwise be copied into a Piece, read
	// again, and copied into a new token list, none of which can change it: the
	// copies are what a macro use costs, and a run without one should not pay
	// them. A file of ordinary code is almost entirely runs of this kind.
	if !p.may_expand(tokens) {
		return tokens
	}
	mut pieces := []Piece{cap: tokens.len}
	for t in tokens {
		pieces << Piece{
			tok: t
		}
	}
	mut out := []tokenize.Token{cap: pieces.len}
	for piece in p.expand_pieces(pieces) {
		out << piece.tok
	}
	return out
}

// may_expand says whether any token of a run is a name the expander would act
// on: a macro the table knows, one of the names whose value depends on where it
// is used, or the _Pragma operator. A run with none of them expands to itself,
// which is what lets expand_all hand it back without copying it.
//
// The names are exactly the ones expand_pieces looks at. A name the program
// defined itself is in the macro table and so answers here too, which is what
// keeps a program that defines __LINE__ for itself on the slow path.
fn (p Processor) may_expand(tokens []tokenize.Token) bool {
	for t in tokens {
		if t.kind != .identifier {
			continue
		}
		if t.text in p.macros || t.text == '_Pragma' || is_dynamic_builtin_name(t.text) {
			return true
		}
	}
	return false
}

// expand_pieces is expand_all over tokens that carry what they are hidden from,
// which is the form the rules inside an expansion need.
fn (mut p Processor) expand_pieces(tokens []Piece) []Piece {
	// Expansion is recursive, and the guard that stops a macro naming itself
	// stops the shapes a person writes. This limit is for the shapes nobody
	// writes: without it, one that slipped past the guard would be a crash
	// instead of a diagnostic.
	if p.expansion_depth >= max_expansion_depth {
		if !p.expansion_reported && tokens.len > 0 {
			p.expansion_reported = true
			p.problem(tokens[0].tok, 'the expansion here is ${max_expansion_depth} levels deep and still going')
		}
		return tokens
	}
	p.expansion_depth++
	defer {
		p.expansion_depth--
	}
	mut out := []Piece{}
	mut i := 0
	for i < tokens.len {
		piece := tokens[i]
		tok := piece.tok
		if tok.kind != .identifier {
			out << piece
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
					out << Piece{
						tok: t
					}
				}
				i++
				continue
			}
			out << piece
			i++
			continue
		}
		macro := p.macros[tok.text]
		if macro.takes_arguments() {
			if tok.text in piece.hide {
				// The name is hidden from its own replacement here, so this
				// occurrence is the text it stands for and not another
				// expansion. This is the same rule as for an object-like macro,
				// and it is what stops a replacement that calls the macro it
				// came from.
				out << piece
				i++
				continue
			}
			use_args := p.collect_arguments(tokens, i + 1, tok)
			if !use_args.called {
				// The name of a function-like macro with no ( after it is not
				// a use of it, and C says it stays where it is.
				out << piece
				i++
				continue
			}
			out << p.expand_call(macro, use_args, piece)
			i = use_args.next
			continue
		}
		if tok.text in piece.hide {
			// The name is hidden from the expansion it came out of, so this
			// occurrence is the text it stands for and not another expansion.
			// This is the rule that makes `#define A B` beside `#define B A`
			// terminate.
			out << piece
			i++
			continue
		}
		mut replacement := []Piece{cap: macro.body.len}
		for body_token in macro.body {
			replacement << produced_from(Piece{
				tok: body_token
			}, piece)
		}
		out << p.expand_pieces(replacement)
		i++
	}
	return out
}

// expand_call expands one use of a macro that takes arguments: the arguments go
// where the parameters are, and the result is read again for macro uses of its
// own.
//
// The arguments are expanded as if they stood on their own — `F(F(1))` is the
// inner F being replaced — and what each of them is hidden from travels with it
// into the replacement. That is what keeps a name the argument's own expansion
// left standing from becoming live again when the replacement is read, and it is
// also what keeps a name the replacement produces from being handed to the
// outer macro as if it were written here.
fn (mut p Processor) expand_call(macro Macro, use_args Arguments, site Piece) []Piece {
	replacement := p.substitute(macro, use_args, site)
	mut hidden := []Piece{cap: replacement.len}
	for piece in replacement {
		hidden << produced_from(piece, site)
	}
	return p.expand_pieces(hidden)
}

// substitute is the replacement itself: every parameter is replaced by its
// argument, # stringizes the argument it is in front of, ## joins the tokens
// around it into one, and __VA_ARGS__ stands for the arguments after the named
// parameters.
fn (mut p Processor) substitute(macro Macro, arguments Arguments, site Piece) []Piece {
	tok := site.tok
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
				lists << []Piece{}
			}
		}
	} else if lists.len != macro.params.len {
		p.problem(tok, '${tok.text} takes ${macro.params.len} ${argument_word(macro.params.len)} and ${lists.len} ${were_word(lists.len)} given')
		for lists.len < macro.params.len {
			lists << []Piece{}
		}
		lists = lists[..macro.params.len]
	}
	mut args := map[string][]Piece{}
	for index, param in macro.params {
		args[param] = if index < lists.len { lists[index] } else { []Piece{} }
	}
	if macro.variadic {
		// __VA_ARGS__ is every argument from the variadic one on, with the
		// commas between them, because that is what the caller wrote and that
		// is what the replacement has to say.
		mut rest := []Piece{}
		for index in macro.params.len .. lists.len {
			if index > macro.params.len {
				// The comma is put back with the spacing the source gave the
				// one it stands for, which is what stringizing __VA_ARGS__
				// writes out: `S(1, 2, 3)` is "1, 2, 3" and `S(1,2,3)` is
				// "1,2,3", which is gcc's answer and C99 6.10.3.2's.
				rest << Piece{
					tok: tokenize.Token{
						kind:  .punct
						text:  ','
						space: index - 1 < arguments.seps.len && arguments.seps[index - 1]
						line:  tok.line
						col:   tok.col
						file:  tok.file
					}
				}
			}
			rest << lists[index]
		}
		args['__VA_ARGS__'] = rest
	}
	mut out := []Piece{}
	mut i := 0
	for i < macro.body.len {
		t := macro.body[i]
		if t.kind == .punct && t.text == '#' {
			// # puts the argument in a string literal without expanding it,
			// which is what makes a macro turn a name into a message.
			if i + 1 < macro.body.len && macro.body[i + 1].kind == .identifier && macro.body[i + 1].text in args {
				out << Piece{
					tok: stringized(args[macro.body[i + 1].text], tok)
				}
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
				[Piece{
					tok: at_use_site(next, tok)
				}]
			}
			if right.len == 0 {
				// An empty argument on the right of a ##: nothing is joined,
				// and the token on the left stands alone. `, ## __VA_ARGS__`
				// with no arguments after it is the reason the rule exists:
				// it is how a macro writes a comma that is only there when
				// something follows it.
				if macro.variadic && out.len > 0 && out.last().tok.kind == .punct && out.last().tok.text == ',' {
					out.delete(out.len - 1)
				}
				i += 2
				continue
			}
			if macro.variadic && next.text == '__VA_ARGS__' && out.len > 0 && out.last().tok.kind == .punct && out.last().tok.text == ',' {
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
			mut text := []Piece{cap: raw.len}
			for argument in raw {
				text << Piece{
					tok:  at_use_site(argument.tok, tok)
					hide: argument.hide.clone()
				}
			}
			if !beside_paste {
				text = p.expand_pieces(text)
			}
			for u in text {
				out << u
			}
			i++
			continue
		}
		out << Piece{
			tok: at_use_site(t, tok)
		}
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
fn (mut p Processor) paste(left Piece, right Piece, tok tokenize.Token) []Piece {
	joined := left.tok.text + right.tok.text
	lexed := tokenize.lex_fragment(joined, standard.has_digraphs(p.opts.dialect))
	if lexed.len == 1 {
		return [
			Piece{
				tok:  tokenize.Token{
					kind: lexed[0].kind
					text: lexed[0].text
					line: tok.line
					col:  tok.col
					file: tok.file
				}
				hide: shared_hide(left, right)
			},
		]
	}
	p.problem(tok, 'the ## in the replacement of ${tok.text} joins ${left.tok.text} and ${right.tok.text}, which do not make one token')
	return [left, right]
}

fn is_paste(t tokenize.Token) bool {
	return t.kind == .punct && t.text == '##'
}

// stringized writes an argument the way a # writes it: the tokens as they were
// spelled, a run of whitespace between two of them as one space and none at
// either end, quoted, and with the quotes and backslashes of the text escaped
// so the result is the string literal it says it is.
//
// The space goes in front of a token when the source put one there, which is
// C99 6.10.3.2 and not a space between every pair: `a + b` keeps its spaces and
// `a+b` has none, and a comma separating variadic arguments carries the
// argument's own spacing rather than a pair of spaces this compiler added.
fn stringized(tokens []Piece, tok tokenize.Token) tokenize.Token {
	mut spelling := ''
	for index, t in tokens {
		if index > 0 && t.tok.space {
			spelling += ' '
		}
		spelling += t.tok.text
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
// expansion point at something a person wrote. The spelling's own spacing stays
// with it, because it is still the token's: an argument is stringized where it
// was read, and moving it should not lose the space a # has to write back.
fn at_use_site(t tokenize.Token, use tokenize.Token) tokenize.Token {
	return tokenize.Token{
		kind:  t.kind
		text:  t.text
		space: t.space
		line:  use.line
		col:   use.col
		file:  use.file
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
fn pragma_operator(tokens []Piece, at int) ?int {
	if at + 3 >= tokens.len {
		return none
	}
	if tokens[at + 1].tok.text != '(' || tokens[at + 2].tok.kind != .string || tokens[at + 3].tok.text != ')' {
		return none
	}
	return at + 4
}
