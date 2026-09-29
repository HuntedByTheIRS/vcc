module parser

import ast

// This file reads the statements a function body is made of. A statement is
// where the tree keeps code: a return leaves the function, an expression is
// evaluated for what it does, and a statement this compiler has no form for is
// reported where it was written. Which of them a run of tokens is, is a question
// about the first token and the one after it, and it is asked here.

// statement_keywords are the statements this compiler does not implement. They
// are named so that `if (x) return;` is reported as an unsupported statement
// rather than as an expression that went wrong at its first parenthesis.
const statement_keywords = ['if', 'else', 'while', 'do', 'for', 'switch', 'case', 'default', 'goto',
	'break', 'continue']

// parse_statement reads one statement. A statement that cannot be read is
// reported where it starts and skipped by the reader that failed on it, so the
// statements after it still parse and one unsupported construct costs one
// diagnostic. The error is returned for a region that never closed and nothing
// else: the closing brace the caller is waiting for is gone with it.
fn (mut p Parser) parse_statement() ![]ast.Stmt {
	t := p.peek()
	if t.kind == .punct && t.text == '{' {
		inner := p.parse_block()!
		return [ast.Stmt{
			kind: .block
			body: inner
			line: t.line
			col:  t.col
		}]
	}
	if t.kind == .identifier && t.text == 'return' {
		return p.parse_return_statement()
	}
	// A statement that starts with a type name declares an object or a type.
	// Neither has anywhere to go until there are frames and a type table, and
	// reading it as an expression would turn `size_t n;` into a call to size_t,
	// so it is reported here instead.
	if p.starts_declaration(t) {
		p.error_at(t, 'unsupported statement starting at ${describe(t)}: a declaration inside a function has nowhere to go yet')
		p.skip_statement()
		return []ast.Stmt{}
	}
	if t.kind == .identifier && t.text in statement_keywords {
		p.error_at(t, 'unsupported statement starting at ${describe(t)}: only return statements and expressions are implemented')
		p.skip_statement()
		return []ast.Stmt{}
	}
	// Anything else is an expression evaluated for what it does, which is what
	// a call written as a statement is. An expression that does not parse is
	// reported by the expression reader and the statement is skipped, so one
	// unsupported construct produces one diagnostic.
	expr := p.parse_expression() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	return [ast.Stmt{
		kind: .expr_stmt
		expr: expr
		line: t.line
		col:  t.col
	}]
}

// parse_return_statement reads `return;` or `return expr;`.
fn (mut p Parser) parse_return_statement() []ast.Stmt {
	t := p.next() // return
	if p.at_punct(';') {
		p.next()
		return [ast.Stmt{
			kind: .return_stmt
			line: t.line
			col:  t.col
		}]
	}
	// A return whose expression does not parse is reported by the expression
	// reader; the statement is skipped so the rest of the function still parses
	// and the file reports once.
	expr := p.parse_expression() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	return [ast.Stmt{
		kind: .return_stmt
		expr: expr
		line: t.line
		col:  t.col
	}]
}
