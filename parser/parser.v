module parser

import ast
import tokenize

// Result is a parse of one file: the declarations that parsed, plus every
// diagnostic produced on the way. A construct the compiler cannot handle stops
// its own declaration and no more, so a file with three separate unsupported
// constructs reports three times instead of once.
pub struct Result {
pub:
	unit        ast.TranslationUnit
	diagnostics []tokenize.Diagnostic
}

struct Parser {
mut:
	tokens      []tokenize.Token
	pos         int
	diagnostics []tokenize.Diagnostic
	// typedefs is every name this file has declared as a type. The declaration
	// grammar needs it: `size_t n` and `puts(x)` are the same token shape, and
	// only the names seen so far say which one a statement holds. It is a map
	// because every declaration start asks it a question, and a list would
	// turn parsing a file with twenty thousand typedefs quadratic.
	typedefs map[string]bool
	// depth counts open parentheses. The grammar recurses only through them, so
	// this is the one number that keeps a hostile file from running the stack out.
	depth int
}

// supported_types are the ones the back end can emit today.
const supported_types = ['int', 'char', 'void']

// max_expression_depth bounds parenthesised nesting. The C standard asks a
// compiler for 63 levels; past this the parser reports instead of following the
// recursion until the stack runs out.
const max_expression_depth = 200

// parse reads a token stream into a translation unit.
pub fn parse(tokens []tokenize.Token) Result {
	mut p := Parser{
		tokens: tokens
	}
	unit := p.parse_unit()
	return Result{
		unit:        unit
		diagnostics: p.diagnostics
	}
}

fn (mut p Parser) parse_unit() ast.TranslationUnit {
	mut decls := []ast.FnDecl{}
	for !p.at_eof() {
		if p.peek().kind == .directive {
			// The preprocessor is a later milestone. Directives are recorded by
			// the lexer and nothing is made of them here.
			p.next()
			continue
		}
		if p.at_punct(';') {
			// An empty declaration is legal in this spot, and a header that
			// holds one should not cost a diagnostic.
			p.next()
			continue
		}
		if p.peek().kind != .identifier || !p.starts_declaration(p.peek()) {
			p.error_at(p.peek(), 'unsupported: expected a declaration, found ${describe(p.peek())}')
			p.skip_declaration()
			continue
		}
		// Depth is per declaration: an error in one declaration leaves a count
		// behind, and carrying it into the next one would report nesting that is
		// not there.
		p.depth = 0
		decls << p.parse_declaration()
	}
	return ast.TranslationUnit{
		decls: decls
	}
}

// parse_block reads `{ ... }`. Every statement a body is made of is read by the
// statement reader; what is left here is the block's own business: where it
// ends, and what happens when the file ends before it does.
fn (mut p Parser) parse_block() ![]ast.Stmt {
	open := p.peek()
	if !p.at_punct('{') {
		p.error_at(open, 'unsupported: expected { to open a block, found ${describe(open)}')
		return error('expected a block')
	}
	p.next()
	mut stmts := []ast.Stmt{}
	for {
		t := p.peek()
		if t.kind == .eof {
			p.error_at(open, 'unterminated block, opened at ${open.line}:${open.col}')
			return error('unterminated block')
		}
		if t.kind == .directive {
			p.next()
			continue
		}
		if t.kind == .punct && t.text == '}' {
			p.next()
			break
		}
		if t.kind == .punct && t.text == ';' {
			// An empty statement is legal wherever a statement is, and a block
			// that holds one should not cost a diagnostic. Nothing is put in
			// the tree for it: a statement that does nothing is not code.
			p.next()
			continue
		}
		// A statement that stopped on a region which never closed has already
		// been reported where the region opened, and the closing brace this
		// loop is waiting for is gone with it.
		fresh := p.parse_statement() or { break }
		stmts << fresh
	}
	return stmts
}

// skip_statement moves past a statement that failed, so the rest of the block
// still gets parsed and one unsupported construct produces one diagnostic
// instead of a cascade. It stops at the semicolon that ends the statement, or
// leaves the closing brace of the enclosing block for the block reader.
fn (mut p Parser) skip_statement() {
	mut depth := 0
	for !p.at_eof() {
		t := p.next()
		if t.kind != .punct {
			continue
		}
		if t.text == '{' {
			depth++
			continue
		}
		if t.text == '}' {
			if depth == 0 {
				p.pos-- // the block reader wants this brace
				return
			}
			depth--
			continue
		}
		if t.text == ';' && depth == 0 {
			return
		}
	}
}

fn (mut p Parser) parse_expression() !ast.Expr {
	return p.parse_binary(0)
}

// parse_binary is precedence climbing: read a unary expression, then keep taking
// operators that bind at least as tightly as the caller's minimum.
fn (mut p Parser) parse_binary(min_precedence int) !ast.Expr {
	mut left := p.parse_unary()!
	for {
		t := p.peek()
		if t.kind != .punct {
			break
		}
		precedence := binary_precedence(t.text)
		if precedence == 0 || precedence < min_precedence {
			break
		}
		p.next()
		right := p.parse_binary(precedence + 1)!
		left = ast.Expr(ast.Binary{
			op:    t.text
			left:  left
			right: right
			line:  t.line
			col:   t.col
		})
	}
	return left
}

fn (mut p Parser) parse_unary() !ast.Expr {
	t := p.peek()
	if t.kind == .punct && t.text in ['-', '+', '!', '~'] {
		p.next()
		operand := p.parse_unary()!
		return ast.Expr(ast.Unary{
			op:   t.text
			expr: operand
			line: t.line
			col:  t.col
		})
	}
	return p.parse_primary()
}

fn (mut p Parser) parse_primary() !ast.Expr {
	t := p.peek()
	if t.kind == .number {
		p.next()
		value := parse_integer_literal(t.text) or {
			p.error_at(t, err.msg())
			return error('bad integer literal')
		}
		return ast.Expr(ast.IntLit{
			value: value
			text:  t.text
			line:  t.line
			col:   t.col
		})
	}
	if t.kind == .character {
		p.next()
		value := parse_character_literal(t.text) or {
			p.error_at(t, err.msg())
			return error('bad character literal')
		}
		return ast.Expr(ast.IntLit{
			value: value
			text:  t.text
			line:  t.line
			col:   t.col
		})
	}
	if t.kind == .identifier {
		p.next()
		if p.at_punct('(') {
			args := p.parse_arguments()!
			return ast.Expr(ast.Call{
				name: t.text
				args: args
				line: t.line
				col:  t.col
			})
		}
		return ast.Expr(ast.Ident{
			name: t.text
			line: t.line
			col:  t.col
		})
	}
	if t.kind == .string {
		p.next()
		value := parse_string_literal(t.text) or {
			p.error_at(t, err.msg())
			return error('bad string literal')
		}
		return ast.Expr(ast.StrLit{
			value: value
			text:  t.text
			line:  t.line
			col:   t.col
		})
	}
	if t.kind == .punct && t.text == '(' {
		p.next()
		p.depth++
		if p.depth > max_expression_depth {
			p.error_at(t, 'expression is nested more than ${max_expression_depth} levels deep')
			p.depth--
			return error('expression nested too deeply')
		}
		inner := p.parse_expression() or {
			p.depth--
			return error('expression')
		}
		p.depth--
		if !p.expect_punct(')') {
			return error('unclosed parenthesis')
		}
		return inner
	}
	p.error_at(t, 'unsupported: expected an expression, found ${describe(t)}')
	return error('expected an expression')
}

fn (mut p Parser) parse_arguments() ![]ast.Expr {
	p.next() // (
	mut args := []ast.Expr{}
	if p.at_punct(')') {
		p.next()
		return args
	}
	for {
		args << p.parse_expression()!
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct(')') {
			p.next()
			return args
		}
		p.error_at(p.peek(), 'unsupported: expected , or ) in the argument list, found ${describe(p.peek())}')
		return error('argument list')
	}
}

// binary_precedence is the binding strength of an operator the tree has a node
// for. The order is C's: `*` binds tighter than `+`, `+` tighter than the four
// comparisons, those tighter than `==`, and `&&` tighter than `||`. An
// operator that is not in the table stops the expression, and the caller
// diagnoses whatever it stopped on.
fn binary_precedence(op string) int {
	return match op {
		'||' { 3 }
		'&&' { 4 }
		'==', '!=' { 5 }
		'<', '>', '<=', '>=' { 6 }
		'+', '-' { 7 }
		'*', '/', '%' { 8 }
		else { 0 }
	}
}

// skip_declaration resynchronises on the token after a declaration that failed,
// so one unsupported construct does not turn into a diagnostic per token for the
// rest of the file.
fn (mut p Parser) skip_declaration() {
	mut depth := 0
	for !p.at_eof() {
		t := p.next()
		if t.kind != .punct {
			continue
		}
		if t.text == '{' {
			depth++
			continue
		}
		if t.text == '}' {
			if depth <= 1 {
				return
			}
			depth--
			continue
		}
		if t.text == ';' && depth == 0 {
			return
		}
	}
}

fn (p Parser) peek() tokenize.Token {
	return p.peek_at(0)
}

fn (p Parser) peek_at(ahead int) tokenize.Token {
	if p.pos + ahead < p.tokens.len {
		return p.tokens[p.pos + ahead]
	}
	return tokenize.Token{
		kind: .eof
	}
}

fn (mut p Parser) next() tokenize.Token {
	t := p.peek()
	if p.pos < p.tokens.len {
		p.pos++
	}
	return t
}

fn (p Parser) at_eof() bool {
	return p.peek().kind == .eof
}

fn (p Parser) at_punct(text string) bool {
	t := p.peek()
	return t.kind == .punct && t.text == text
}

fn (mut p Parser) expect_punct(text string) bool {
	if p.at_punct(text) {
		p.next()
		return true
	}
	p.error_at(p.peek(), 'unsupported: expected ${text}, found ${describe(p.peek())}')
	return false
}

fn (mut p Parser) error_at(t tokenize.Token, msg string) {
	p.diagnostics << tokenize.Diagnostic{
		line: t.line
		col:  t.col
		msg:  msg
	}
}

fn describe(t tokenize.Token) string {
	if t.kind == .eof {
		return 'end of file'
	}
	return "'${t.text}'"
}
