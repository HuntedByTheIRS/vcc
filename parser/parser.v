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
	// depth counts open parentheses. The grammar recurses only through them, so
	// this is the one number that keeps a hostile file from running the stack out.
	depth int
}

// type_keywords is every word that can start a type in C, so the parser can say
// "unsupported type unsigned" instead of failing on an unexpected token.
const type_keywords = ['int', 'char', 'void', 'short', 'long', 'signed', 'unsigned', 'float', 'double',
	'struct', 'union', 'enum', 'typedef', 'static', 'const', 'extern', 'inline', 'register', 'volatile',
	'auto', '_Bool', '_Complex', '_Imaginary']

// supported_types are the ones the back end can emit today.
const supported_types = ['int', 'char', 'void']

// max_expression_depth bounds parenthesised nesting. The C standard asks a
// compiler for 63 levels; past this the parser reports instead of following the
// recursion until the stack runs out.
const max_expression_depth = 200

// statement_keywords are the statements this compiler does not implement. They
// are named so that `if (x) return;` is reported as an unsupported statement
// rather than as an expression that went wrong at its first parenthesis.
const statement_keywords = ['if', 'else', 'while', 'do', 'for', 'switch', 'case', 'default', 'goto',
	'break', 'continue']

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
		if p.peek().kind != .identifier || p.peek().text !in type_keywords {
			p.error_at(p.peek(), 'unsupported: expected a declaration, found ${describe(p.peek())}')
			p.skip_declaration()
			continue
		}
		// Depth is per declaration: an error in one declaration leaves a count
		// behind, and carrying it into the next one would report nesting that is
		// not there.
		p.depth = 0
		decl := p.parse_declaration() or {
			p.skip_declaration()
			continue
		}
		decls << decl
	}
	return ast.TranslationUnit{
		decls: decls
	}
}

// parse_declaration reads one function definition. A declaration that has no
// body (a prototype) is kept with an empty body so a program that announces its
// functions before defining them still parses.
fn (mut p Parser) parse_declaration() !ast.FnDecl {
	ret := p.parse_type_specifier()!
	mut stars := 0
	for p.peek().kind == .punct && p.peek().text == '*' {
		p.next()
		stars++
	}
	name := p.peek()
	if name.kind != .identifier {
		p.error_at(name, 'unsupported: expected a function name, found ${describe(name)}')
		return error('expected a name')
	}
	p.next()
	if stars > 0 {
		p.error_at(name, 'unsupported: pointer return types are not implemented')
		return error('pointer return type')
	}
	if !p.at_punct('(') {
		p.error_at(name, 'unsupported: only function definitions are implemented, so a declaration of ${name.text} has nowhere to go')
		return error('variable declaration')
	}
	p.next()
	p.parse_parameters()!
	if !p.at_punct('{') {
		if !p.expect_punct(';') {
			return error('expected a prototype')
		}
		return ast.FnDecl{
			name: name.text
			ret:  ret
			line: name.line
			col:  name.col
		}
	}
	body := p.parse_block()!
	return ast.FnDecl{
		name: name.text
		ret:  ret
		body: body
		line: name.line
		col:  name.col
	}
}

// parse_type_specifier reads a type as it is written and returns it when the
// back end can emit it. The spelling that was found goes into the diagnostic, so
// nobody has to guess which part of `unsigned long long` is missing.
fn (mut p Parser) parse_type_specifier() !string {
	start := p.peek()
	mut typ := ''
	for p.peek().kind == .identifier && p.peek().text in type_keywords {
		specifier := p.next()
		if typ != '' || specifier.text !in supported_types {
			p.error_at(start, 'unsupported type ${specifier.text}')
			return error('unsupported type')
		}
		typ = specifier.text
	}
	if typ == '' {
		p.error_at(start, 'unsupported: expected a type, found ${describe(p.peek())}')
		return error('expected a type')
	}
	return typ
}

fn (mut p Parser) parse_parameters() ! {
	if p.at_punct(')') {
		p.next()
		return
	}
	// `void` alone is an empty parameter list, not a parameter.
	if p.peek().kind == .identifier && p.peek().text == 'void' && p.at_punct_ahead(')', 1) {
		p.next()
		p.next()
		return
	}
	for {
		p.parse_type_specifier()!
		if p.peek().kind == .identifier {
			p.next() // the parameter name, which the stub has no use for
		}
		if p.peek().kind == .punct && p.peek().text == '*' {
			p.error_at(p.peek(), 'unsupported: pointer parameters are not implemented')
			return error('pointer parameter')
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct(')') {
			p.next()
			return
		}
		p.error_at(p.peek(), 'unsupported: expected , or ) in the parameter list, found ${describe(p.peek())}')
		return error('parameter list')
	}
}

// parse_block reads `{ ... }`. Only return statements and expressions have a
// form in the back end; a statement it cannot read is reported where it starts
// and skipped, so the statements after it still parse.
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
			p.next()
			continue
		}
		if t.kind == .punct && t.text == '{' {
			inner := p.parse_block()!
			stmts << ast.Stmt{
				kind: .block
				body: inner
				line: t.line
				col:  t.col
			}
			continue
		}
		if t.kind == .identifier && t.text == 'return' {
			p.next()
			if p.at_punct(';') {
				p.next()
				stmts << ast.Stmt{
					kind: .return_stmt
					line: t.line
					col:  t.col
				}
				continue
			}
			// A return whose expression does not parse is reported by the
			// expression reader; the statement is skipped so the rest of the
			// function still parses and the file reports once.
			expr := p.parse_expression() or {
				p.skip_statement()
				continue
			}
			if !p.expect_punct(';') {
				p.skip_statement()
				continue
			}
			stmts << ast.Stmt{
				kind: .return_stmt
				expr: expr
				line: t.line
				col:  t.col
			}
			continue
		}
		// A statement that starts with a type name declares an object or a
		// type. Neither has anywhere to go until there are frames and a type
		// table, and reading it as an expression would turn `size_t n;` into a
		// call to size_t, so it is reported here instead.
		if t.kind == .identifier && t.text in type_keywords {
			p.error_at(t, 'unsupported statement starting at ${describe(t)}: a declaration inside a function has nowhere to go yet')
			p.skip_statement()
			continue
		}
		if t.kind == .identifier && t.text in statement_keywords {
			p.error_at(t, 'unsupported statement starting at ${describe(t)}: only return statements and expressions are implemented')
			p.skip_statement()
			continue
		}
		// Anything else is an expression evaluated for what it does, which is
		// what a call written as a statement is. An expression that does not
		// parse is reported by the expression reader and the statement is
		// skipped, so one unsupported construct produces one diagnostic.
		expr := p.parse_expression() or {
			p.skip_statement()
			continue
		}
		if !p.expect_punct(';') {
			p.skip_statement()
			continue
		}
		stmts << ast.Stmt{
			kind: .expr_stmt
			expr: expr
			line: t.line
			col:  t.col
		}
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

// binary_precedence is the binding strength of an operator the stub folds. An
// operator that is not in the table stops the expression, and the caller
// diagnoses whatever it stopped on.
fn binary_precedence(op string) int {
	return match op {
		'*', '/', '%' { 5 }
		'+', '-' { 4 }
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

fn (p Parser) at_punct_ahead(text string, ahead int) bool {
	t := p.peek_at(ahead)
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
