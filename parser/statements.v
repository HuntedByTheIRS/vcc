module parser

import ast
import tokenize

// This file reads the statements a function body is made of. A statement is
// where the tree keeps code: a return leaves the function, an expression is
// evaluated for what it does, and a statement this compiler has no form for is
// reported where it was written. Which of them a run of tokens is, is a question
// about the first token and the one after it, and it is asked here.

// statement_keywords are the statements this compiler does not implement. They
// are named so that `switch (x)` is reported as an unsupported statement rather
// than as an expression that went wrong at its first parenthesis.
const statement_keywords = ['do', 'switch', 'case', 'default', 'goto']

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
	if t.kind == .identifier {
		if t.text == 'return' {
			return p.parse_return_statement()
		}
		if t.text == 'if' {
			return p.parse_if_statement()
		}
		if t.text == 'while' {
			return p.parse_while_statement()
		}
		if t.text == 'break' || t.text == 'continue' {
			return p.parse_loop_jump(t)
		}
		if t.text == 'else' {
			// An else belongs to the if in front of it. Getting here means
			// there was no if, and a branch with nothing to branch from is not
			// a statement this file has.
			p.error_at(t, 'unsupported: else with no if')
			p.skip_statement()
			return []ast.Stmt{}
		}
		if t.text in statement_keywords {
			p.error_at(t, 'unsupported statement starting at ${describe(t)}: ${t.text} is not implemented yet')
			p.skip_statement()
			return []ast.Stmt{}
		}
	}
	// A statement that starts with a type name declares an object. Storage in
	// the frame is what the tree calls a var_decl, and one statement names one
	// object, so a declaration of several declarators is several statements.
	if p.starts_declaration(t) {
		return p.parse_local_declaration()
	}
	// Anything else is an assignment or an expression evaluated for what it
	// does, which is what a call written as a statement is. An expression that
	// does not parse is reported by the expression reader and the statement is
	// skipped, so one unsupported construct produces one diagnostic.
	return p.parse_simple_statement()
}

// assignment_operators are the tokens that write to a name. The compound
// spellings are here so that `x *= 2` is read as the compound assignment it is
// rather than as an expression that stopped at `*`.
const assignment_operators = ['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=']

// parse_simple_statement reads the statements that are one expression: an
// assignment, which writes to a name, or an expression evaluated for what it
// does.
fn (mut p Parser) parse_simple_statement() []ast.Stmt {
	stmt := p.parse_expression_statement() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	return [stmt]
}

// parse_expression_statement reads an assignment or an expression and stops
// before the punctuation that ends it: a statement ends with `;`, and the step
// of a for ends with the `)` of its header. A failure reports itself and comes
// back as an error, so the reader that knows what ending it was waiting for is
// the one that resynchronises.
fn (mut p Parser) parse_expression_statement() !ast.Stmt {
	if p.starts_assignment() {
		return p.parse_assignment()!
	}
	t := p.peek()
	expr := p.parse_expression()!
	return ast.Stmt{
		kind: .expr_stmt
		expr: expr
		line: t.line
		col:  t.col
	}
}

// starts_assignment says whether the tokens at the cursor are `name = ...`. It
// is a lookahead and not a reading, because `x = 1;` and `x(1);` start the same
// way and only the second token tells them apart. `==` is a token of its own,
// so an expression like `x == 1;` is not an assignment.
fn (p Parser) starts_assignment() bool {
	if p.peek().kind != .identifier {
		return false
	}
	next := p.peek_at(1)
	return next.kind == .punct && next.text in assignment_operators
}

// parse_assignment reads `name = expr`. C makes an assignment an expression;
// this tree makes it a statement, because a statement is where it is written in
// almost every line of C there is. The target is the name alone: an lvalue with
// a subscript or a dereference is not a name the tree can hold, and the
// expression reader reports it where it stopped.
fn (mut p Parser) parse_assignment() !ast.Stmt {
	t := p.next() // the name
	op := p.next() // = or a compound spelling
	if op.text == '=' {
		expr := p.parse_expression()!
		return ast.Stmt{
			kind:   .assign
			target: t.text
			expr:   expr
			line:   t.line
			col:    t.col
		}
	}
	return p.parse_compound_assignment(t, op)
}

// parse_compound_assignment reads `name += expr`, and `name -= expr` because it
// is the same thing with the other operator. `x += 1` reads and writes the same
// name, so with a name for its target it means exactly `x = x + 1`, and that is
// the shape the tree is written in. The other compound spellings are reported
// instead: a compound operator stands for one the expression grammar does not
// read as a binary operator either, so expanding it would be inventing a form
// nobody has agreed on.
fn (mut p Parser) parse_compound_assignment(target tokenize.Token, op tokenize.Token) !ast.Stmt {
	arithmetic := op.text[..op.text.len - 1]
	if arithmetic !in ['+', '-'] {
		p.error_at(op, 'unsupported: the compound assignment ${op.text} is not implemented')
		return error('compound assignment')
	}
	right := p.parse_expression()!
	value := ast.Expr(ast.Binary{
		op:    arithmetic
		left:  ast.Expr(ast.Ident{
			name: target.text
			line: target.line
			col:  target.col
		})
		right: right
		line:  op.line
		col:   op.col
	})
	return ast.Stmt{
		kind:   .assign
		target: target.text
		expr:   value
		line:   target.line
		col:    target.col
	}
}

// parse_control_body reads the statement a branch or a loop governs: a block, a
// single statement, or the empty statement `;`, which governs nothing. The body
// is a list of statements because a run of statements is what the tree has a
// shape for, and an empty body is the empty list.
fn (mut p Parser) parse_control_body() ![]ast.Stmt {
	if p.at_punct(';') {
		p.next()
		return []ast.Stmt{}
	}
	return p.parse_statement()
}

// parse_if_statement reads `if (cond) stmt else stmt`. An `else if` is an if
// inside the else, which is where the tree puts it: a branch is a list of
// statements, and the one that branch holds is an if.
fn (mut p Parser) parse_if_statement() ![]ast.Stmt {
	t := p.next() // if
	if !p.expect_punct('(') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	cond := p.parse_expression() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(')') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	then_body := p.parse_control_body()!
	mut else_body := []ast.Stmt{}
	if p.peek().kind == .identifier && p.peek().text == 'else' {
		p.next()
		else_body = p.parse_control_body()!
	}
	return [ast.Stmt{
		kind:      .if_stmt
		cond:      cond
		then_body: then_body
		else_body: else_body
		line:      t.line
		col:       t.col
	}]
}

// parse_while_statement reads `while (cond) stmt`. The condition is what has to
// be true for the loop to go round again, and it is read by the expression
// reader, so a comparison or two of them joined need nothing here.
fn (mut p Parser) parse_while_statement() ![]ast.Stmt {
	t := p.next() // while
	if !p.expect_punct('(') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	cond := p.parse_expression() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(')') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	body := p.parse_control_body()!
	return [ast.Stmt{
		kind: .while_stmt
		cond: cond
		body: body
		line: t.line
		col:  t.col
	}]
}

// parse_loop_jump reads `break;` or `continue;`. Which loop it belongs to is a
// question about the loops around it, and it is not asked here: the statement is
// kept where it was written, and a break with no loop around it is the
// emitter's diagnostic to give.
fn (mut p Parser) parse_loop_jump(t tokenize.Token) []ast.Stmt {
	p.next() // break or continue
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if t.text == 'break' {
		return [ast.Stmt{
			kind: .break_stmt
			line: t.line
			col:  t.col
		}]
	}
	return [ast.Stmt{
		kind: .continue_stmt
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
