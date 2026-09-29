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
	// A statement that starts with a type name declares an object. Storage in
	// the frame is what the tree calls a var_decl, and one statement names one
	// object, so a declaration of several declarators is several statements.
	if p.starts_declaration(t) {
		return p.parse_local_declaration()
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

// parse_local_declaration reads a declaration inside a body: storage in the
// frame, and a statement that runs where it is written. One declaration of
// several declarators becomes one statement per declared name, because a
// statement is what names one object and the tree gives each of them its own
// name, type and initializer.
//
// The type is the type a definition's return type may be, asked with the same
// function, because both are storage the emitter has to find a form for. A
// shape the tree has no node for — an array, a function, a brace full of
// initializers — is reported rather than half-read, and the rest of the
// declaration is skipped so the statements after it still parse.
fn (mut p Parser) parse_local_declaration() []ast.Stmt {
	mut stmts := []ast.Stmt{}
	spec := p.parse_decl_specifiers(0) or {
		p.skip_declaration()
		return stmts
	}
	if p.at_punct(';') {
		p.error_at(p.peek(), 'unsupported: expected a declarator, found ${describe(p.peek())}')
		p.next()
		return stmts
	}
	if offender := unsupported_type_word(spec) {
		p.error_at(spec.start, 'unsupported type ${offender}')
		p.skip_declaration()
		return stmts
	}
	for {
		d := p.parse_declarator(0) or {
			p.skip_declaration()
			return stmts
		}
		if d.name.len == 0 {
			p.error_at(p.peek(), 'unsupported: expected a name in a declaration, found ${describe(p.peek())}')
			p.skip_declaration()
			return stmts
		}
		if d.is_function {
			p.error_at(d.name_at, 'unsupported: a function declaration inside a body is not implemented')
			p.skip_declaration()
			return stmts
		}
		if d.array_at.line > 0 {
			p.error_at(d.array_at, 'unsupported: array declarations are not implemented')
			p.skip_declaration()
			return stmts
		}
		mut init := ?ast.Expr(none)
		if p.at_punct('=') {
			p.next()
			if p.at_punct('{') {
				p.error_at(p.peek(), 'unsupported: a brace initializer is not implemented')
				p.skip_declaration()
				return stmts
			}
			init = p.parse_expression() or {
				p.skip_declaration()
				return stmts
			}
		}
		stmts << ast.Stmt{
			kind:      .var_decl
			init:      init
			decl_name: d.name
			decl_type: spec.type_spelling(d.stars)
			line:      d.name_at.line
			col:       d.name_at.col
		}
		if p.at_punct(',') {
			p.next()
			continue
		}
		if p.at_punct(';') {
			p.next()
			break
		}
		p.error_at(p.peek(), 'unsupported: expected , or ; after a declarator, found ${describe(p.peek())}')
		p.skip_declaration()
		return stmts
	}
	return stmts
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
