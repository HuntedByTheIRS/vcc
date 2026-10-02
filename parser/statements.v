module parser

import ast
import tokenize
import types

// This file reads the statements a function body is made of. A statement is
// where the tree keeps code: a return leaves the function, an expression is
// evaluated for what it does, and a statement this compiler has no form for is
// reported where it was written. Which of them a run of tokens is, is a question
// about the first token and the one after it, and it is asked here.

// parse_statement reads one statement. A statement that opens with a word the
// language reserves is read by the reader that word names, and the dispatch
// below is the whole table: C's statements begin with a keyword or with an
// identifier and nothing else, so a word that is not there is a name, and a name
// nothing declares is reported by the check over the whole unit. A statement
// that cannot be read is reported where it starts and skipped by the reader that
// failed on it, so the statements after it still parse and one unsupported
// construct costs one diagnostic. The error is returned for a region that never
// closed and nothing else: the closing brace the caller is waiting for is gone
// with it.
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
		if t.text == 'do' {
			return p.parse_do_while_statement()
		}
		if t.text == 'for' {
			return p.parse_for_statement()
		}
		if t.text == 'switch' {
			return p.parse_switch_statement()
		}
		if t.text == 'case' {
			return p.parse_case_label()
		}
		if t.text == 'default' {
			return p.parse_default_label()
		}
		if t.text == 'goto' {
			return p.parse_goto_statement()
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
		// A name followed by `:` names a place in the function and not an
		// object. The two namespaces are separate in C, which is why a label
		// and a variable of the same name are two names and why this check is
		// the shape of the tokens and not a lookup.
		if p.peek_at(1).kind == .punct && p.peek_at(1).text == ':' {
			return p.parse_label_statement(t)
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
	// A statement that parsed as an expression and is followed by the operator
	// that writes is a write to an element whose base is not a name, which is
	// what `3[p] = 9` is, or to one whose base is a member, which is what
	// `s.a[1] = 7` is. The target fields of a statement name an object, so the
	// element node itself is carried instead. This is read before the
	// dereference below, because an element is one of the shapes that reader
	// refuses.
	if p.peek().kind == .punct && p.peek().text in assignment_operators && expr is ast.Index {
		return p.parse_subscript_assignment(expr as ast.Index)!
	}
	// An assignment whose target is not a name. The expression reader reads
	// `*p` as the value at an address and stops at the operator, because an
	// assignment is not one of the binary operators; the operator that follows
	// is what says the value that was read is the object the assignment writes
	// to. A `=` after a name or an element never reaches here, because
	// starts_assignment read that statement already.
	if op := p.assignment_operator() {
		p.next()
		return p.parse_deref_assignment(t, expr, op)!
	}
	return ast.Stmt{
		kind: .expr_stmt
		expr: expr
		line: t.line
		col:  t.col
	}
}

// assignment_operator is the assignment token at the cursor, or none where the
// statement is not one. A compound spelling is one too, so the reader below is
// the one that says which targets a compound assignment writes and which it
// does not.
fn (p Parser) assignment_operator() ?tokenize.Token {
	t := p.peek()
	if t.kind == .punct && t.text in assignment_operators {
		return t
	}
	return none
}

// parse_deref_assignment reads the assignment whose target is a dereference:
// `*p = v` writes the value at the address the pointer holds, and the address
// is the one expression the store needs. `(*f()) = v` is the same shape, with
// the address coming from a call, and `**pp = v` is a dereference of a
// dereference: the operand of the outer one is itself a read through an
// address, which is the address that store writes to.
//
// A compound spelling through a dereference is refused by name rather than read
// as the compound assignment it names. `*p += 1` means `*p = *p + 1`, and
// writing it that way evaluates the pointer expression twice where C evaluates
// the lvalue once, which is a different program whenever the pointer has a side
// effect. This tree has no shape that reads an lvalue once and uses it twice,
// so the spelling stays unimplemented rather than half-working.
//
// Anything else the expression reader left in front of an assignment operator
// is not a place a value can be written, and is refused by name.
fn (mut p Parser) parse_deref_assignment(start tokenize.Token, target ast.Expr, op tokenize.Token) !ast.Stmt {
	match target {
		ast.Unary {
			if target.op != '*' {
				p.error_at(op, 'unsupported: the target of an assignment is ${describe_operand(target)}, and this compiler writes to a name, an element, a member or a dereference')
				return error('assignment target is not a dereference')
			}
			if op.text != '=' {
				p.error_at(op, 'unsupported: the compound assignment ${op.text} through a dereference is not implemented')
				return error('compound assignment through a dereference')
			}
			value := p.parse_expression()!
			// The object written to is the one the pointer points at, so the
			// value converts to the pointed-at type the same way it does into
			// a name.
			p.check_assignment(target.typ, value, op)
			return ast.Stmt{
				kind:  .assign
				deref: ast.Expr(target)
				expr:  value
				line:  start.line
				col:   start.col
			}
		}
		else {
			p.error_at(op, 'unsupported: the target of an assignment is ${describe_operand(target)}, and this compiler writes to a name, an element, a member or a dereference')
			return error('assignment target is not an lvalue')
		}
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
	if next.kind == .punct && next.text in assignment_operators {
		return true
	}
	// `a[i] = v` starts with a name and a subscript, and the subscript can hold
	// anything, so the tokens are scanned to the bracket that closes it: the
	// operator after that is what says whether this is an assignment. Nothing is
	// consumed here — it is a lookahead, and the reading happens once.
	// `x.a = v` starts with a name, a dot and a member. A member is one name, so
	// three tokens say whether this is an assignment to a member: the operator
	// after the member is the one that writes.
	if next.kind == .punct && (next.text == '.' || next.text == '->') {
		// One member is one name, and a path of members is one name per dot or
		// arrow, so the pairs are walked to the token after the last of them: that
		// token says whether this writes a member.
		return p.assignment_after(1)
	}
	if next.kind == .punct && next.text == '[' {
		mut depth := 0
		mut ahead := 1
		for {
			t := p.peek_at(ahead)
			if t.kind == .eof {
				return false
			}
			if t.kind == .punct {
				if t.text == '[' {
					depth++
				} else if t.text == ']' {
					depth--
					if depth == 0 {
						// What follows the element is either the operator or a
						// member path that leads to one: `a[i] = v` and
						// `a[i].m = v` are both writes to an element's worth of
						// storage.
						return p.assignment_after(ahead + 1)
					}
				}
			}
			ahead++
		}
	}
	return false
}

// assignment_after says whether the tokens from `at` on are any number of
// `.<name>` or `-><name>` pairs followed by an assignment operator. It is a
// lookahead and not a reading: a member path is one name per step, and the
// operator after the last step is what says the statement writes through it.
fn (p Parser) assignment_after(at int) bool {
	mut ahead := at
	for {
		head := p.peek_at(ahead)
		if head.kind == .punct && (head.text == '.' || head.text == '->') {
			if p.peek_at(ahead + 1).kind != .identifier {
				return false
			}
			ahead += 2
			continue
		}
		return head.kind == .punct && head.text in assignment_operators
	}
}

// parse_assignment reads `name = expr`. C makes an assignment an expression;
// this tree makes it a statement, because a statement is where it is written in
// almost every line of C there is. The target is the name alone: an lvalue with
// a subscript or a dereference is not a name the tree can hold, and the
// expression reader reports it where it stopped.
fn (mut p Parser) parse_assignment() !ast.Stmt {
	t := p.next() // the name
	mut index := ?ast.Expr(none)
	mut field := ?ast.Field(none)
	mut arrow := false
	if p.at_punct('[') {
		p.next()
		index = p.parse_expression() or { return error('bad subscript') }
		if !p.at_punct(']') {
			p.error_at(p.peek(), 'unsupported: expected ] after the index of an element, found ${describe(p.peek())}')
			return error('expected ]')
		}
		p.next()
		// A member of an element of an array is the same object read further in:
		// the index names which element, and the member is read from that
		// element, so the field carries the index and the index is no longer a
		// target of its own.
		if p.at_punct('.') || p.at_punct('->') {
			arrow = p.at_punct('->')
			field = p.parse_member_path(t.text, t, arrow, index)!
			index = ?ast.Expr(none)
		}
	} else if p.at_punct('.') || p.at_punct('->') {
		arrow = p.at_punct('->')
		field = p.parse_member_path(t.text, t, arrow, ?ast.Expr(none))!
	}
	op := p.next() // = or a compound spelling
	if op.text == '=' {
		expr := p.parse_expression()!
		// An element of a pointer is the same subscript an element of an array
		// is, but the object it is addressed from is a value rather than a place
		// in the frame, so the target is carried as the element node with the
		// name as its base. An element of an array keeps the name-and-index
		// shape it has always had.
		if subscript := index {
			declared := p.resolve(t.text)
			if declared.is_pointer() {
				element := declared.pointee() or { types.Type{} }
				base := ast.Expr(ast.Ident{
					name: t.text
					typ:  declared
					line: t.line
					col:  t.col
				})
				p.check_assignment(element, expr, op)
				return ast.Stmt{
					kind:      .assign
					subscript: ast.Expr(ast.Index{
						base:  base
						index: subscript
						typ:   element
						line:  t.line
						col:   t.col
					})
					expr:      expr
					line:      t.line
					col:       t.col
				}
			}
		}
		p.check_assignment(p.assignment_target_type(t.text, index, field), expr, op)
		return ast.Stmt{
			kind:   .assign
			target: t.text
			index:  index
			field:  field
			expr:   expr
			line:   t.line
			col:    t.col
		}
	}
	if member := field {
		p.error_at(op, 'unsupported: a compound assignment to the member ${member.name}.${member.member} is not implemented')
		return error('compound assignment to a member')
	}
	return p.parse_compound_assignment(t, op, index)
}

// parse_subscript_assignment reads `E1[E2] = value` where the target's base is
// not a name the assignment reader can address, which is what `3[p] = 9` is. The
// element node is carried whole so the back end can compute the address the value
// is stored through. A compound spelling is refused by name: `E1[E2] += v` reads
// the element twice and this tree has no shape for that target yet.
fn (mut p Parser) parse_subscript_assignment(index ast.Index) !ast.Stmt {
	op := p.next()
	if op.text != '=' {
		p.error_at(op, 'unsupported: the compound assignment ${op.text} to an element is not implemented')
		return error('compound assignment to an element')
	}
	value := p.parse_expression()!
	p.check_assignment(index.typ, value, op)
	return ast.Stmt{
		kind:      .assign
		subscript: ast.Expr(index)
		expr:      value
		line:      index.line
		col:       index.col
	}
}

// assignment_target_type is the type an assignment writes through: the type the
// name was declared with, or the type of one element of it where the target is
// written with a subscript. A name no declaration describes answers with the zero
// type, and the constraint below takes no position on that: the name is what the
// check at the end of the unit is for.
fn (p Parser) assignment_target_type(name string, index ?ast.Expr, field ?ast.Field) types.Type {
	// A member is written at an offset into an object, and what the value written
	// there converts to is the type of the member, which the reader worked out
	// when it read the member.
	if member := field {
		return member.typ
	}
	declared := p.resolve(name)
	if index == none {
		return declared
	}
	if declared.is_array() {
		return declared.element() or { types.Type{} }
	}
	if declared.is_pointer() {
		return declared.pointee() or { types.Type{} }
	}
	return types.Type{}
}

// check_assignment asks the constraint 6.5.16.1 for a value written into an
// object, which is what an assignment is and what an initialization is: an
// argument is checked the same way because 6.5.2.2 says it converts as if by
// assignment, and `types.assignment_problem` is the one place those rules live.
// The refusal is reported at the operator that writes, which is where a reader of
// the source looks for it.
//
// The compound spellings are not asked here. `x += e` is read as `x = x + e` in
// this tree, and the sum is a node built while the compound spelling is read,
// which carries no clause at all: the question would have no operand to ask about.
// A source whose target and value disagree that way is refused at the operators
// it is written with, which is the next milestone's arithmetic.
fn (mut p Parser) check_assignment(to types.Type, value ast.Expr, at tokenize.Token) {
	problem := types.assignment_problem(to, p.value_type(value), is_null_constant(value)) or {
		return
	}
	p.error_at(at, problem)
}

// check_initializer is the same question for the initializer of a declaration,
// reported at the initializer as it was written, which is where gcc points at it:
// measured, `int main(void) { int *p = 7; return 0; }` is `initialization of 'int
// *' from 'int' makes pointer from integer without a cast` under `gcc -std=c99
// -pedantic-errors`, where this compiler used to accept it.
fn (mut p Parser) check_initializer(to types.Type, init ast.Expr) {
	problem := types.assignment_problem(to, p.value_type(init), is_null_constant(init)) or {
		return
	}
	p.error_span(init.line, init.col, problem)
}

// parse_compound_assignment reads `name += expr` and every other compound
// spelling, because they are all the same thing with the other operator: `x += 1`
// reads and writes the same name, so with a name for its target it means exactly
// `x = x + 1`, and that is the shape the tree is written in.
//
// Every spelling the lexer carries is expanded here now that the emitter writes
// every operator they name, so the list below is every one of them and the guard
// after it is left for a spelling a later change might add. The narrower list this
// replaced expanded only `+=` and `-=`, which was a decision about the arithmetic
// the emitter had: expanding `x &= 1` while nothing could emit a `&` would have
// moved the refusal from the first stage that can describe the construct to one
// that can only complain about it.
fn (mut p Parser) parse_compound_assignment(target tokenize.Token, op tokenize.Token, index ?ast.Expr) !ast.Stmt {
	arithmetic := op.text[..op.text.len - 1]
	if arithmetic !in ['+', '-', '*', '/', '%', '<<', '>>', '&', '|', '^'] {
		p.error_at(op, 'unsupported: the compound assignment ${op.text} is not implemented')
		return error('compound assignment')
	}
	right := p.parse_expression()!
	// What the assignment reads is the target itself, and for an element that is
	// the element rather than the array: the subscript is written into the tree
	// again, so that `a[i] += 1` means `a[i] = a[i] + 1`.
	//
	// The nodes built here carry the types the expression reader would have given
	// them, because everything after the reader reads those types rather than the
	// spelling: a binary whose type is the zero type is a value the emitter cannot
	// size, and `v *= 7` on an object of 128 bits was refused by name for being a
	// value this back end could not widen, which was true of the empty type and was
	// not true of the value. The operator the type is worked out from is the one the
	// spelling names, not the spelling itself, and it is the same token with that
	// text.
	operator := tokenize.Token{
		...op
		text: arithmetic
	}
	target_type := p.assignment_target_type(target.text, index, none)
	mut left := ast.Expr(ast.Ident{
		name: target.text
		typ:  target_type
		line: target.line
		col:  target.col
	})
	if subscript := index {
		left = ast.Expr(ast.Index{
			base:  ast.Expr(left)
			index: subscript
			typ:   target_type
			line:  target.line
			col:   target.col
		})
	}
	value := ast.Expr(ast.Binary{
		op:    arithmetic
		left:  left
		right: right
		typ:   p.binary_type(operator, left, right)
		line:  op.line
		col:   op.col
	})
	return ast.Stmt{
		kind:   .assign
		target: target.text
		index:  index
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

// parse_do_while_statement reads `do stmt while (cond);`. The `while` at the end is
// this loop's test and not a second statement, which is why it is read here: left for
// the statement reader it would be a loop with no body and then a stray parenthesis
// where the source has one loop.
fn (mut p Parser) parse_do_while_statement() ![]ast.Stmt {
	t := p.next() // do
	body := p.parse_control_body()!
	if p.peek().kind != .identifier || p.peek().text != 'while' {
		p.error_at(p.peek(), 'unsupported: expected while, found ${describe(p.peek())}')
		p.skip_statement()
		return []ast.Stmt{}
	}
	p.next() // while
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
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	return [ast.Stmt{
		kind: .do_while_stmt
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

// parse_label_statement reads `name: stmt`. The label is a place in the
// function and not an object, so nothing is declared here and the name is
// looked up nowhere: a label is a name for the position of the statement that
// follows it, and whether a goto ever reaches it is a question about the
// function.
fn (mut p Parser) parse_label_statement(name tokenize.Token) ![]ast.Stmt {
	p.next() // the name
	p.next() // :
	mut out := [ast.Stmt{
		kind:  .label_stmt
		label: name.text
		line:  name.line
		col:   name.col
	}]
	out << p.statement_under_label()!
	return out
}

// statement_under_label reads the statement a label governs. An empty statement
// is legal wherever a statement is, and it is nothing in the tree, which is the
// rule the block reader already applies to a `;` written between two statements.
// A label whose statement is empty is a label at the end of a block, which is a
// place a goto still reaches.
fn (mut p Parser) statement_under_label() ![]ast.Stmt {
	if p.at_punct(';') {
		p.next()
		return []ast.Stmt{}
	}
	return p.parse_statement()
}

// parse_goto_statement reads `goto name;`. The name is a label and never an
// object, so it is not resolved here: what a label is a place in is a function,
// and only the whole of one says whether the name was defined, which is where
// the jump is emitted.
fn (mut p Parser) parse_goto_statement() ![]ast.Stmt {
	t := p.next() // goto
	if p.peek().kind != .identifier {
		p.error_at(p.peek(), 'unsupported: expected a label name after goto, found ${describe(p.peek())}')
		p.skip_statement()
		return []ast.Stmt{}
	}
	name := p.next()
	if is_keyword(name.text) {
		p.error_at(name, 'unsupported: ${name.text} is a keyword and cannot name a label')
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	return [ast.Stmt{
		kind:  .goto_stmt
		label: name.text
		line:  t.line
		col:   t.col
	}]
}

// parse_switch_statement reads `switch (expr) stmt`. The controlling expression
// is what the case labels are matched against, and the body is read as a
// statement like any other: the case labels inside it are statements too, and
// the reader of a case label is what knows it is inside a switch.
//
// The values the labels have written are collected while the body is read, so
// that a value written twice in one switch is refused where it is written the
// second time. The set is pushed around the body rather than kept in the reader,
// because the cases of a nested switch belong to it and not to the one outside.
fn (mut p Parser) parse_switch_statement() ![]ast.Stmt {
	t := p.next() // switch
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
	p.check_switch_operand(cond, t)
	p.case_values << map[i64]bool{}
	p.case_defaults << false
	body := p.parse_control_body()!
	p.case_values.pop()
	p.case_defaults.pop()
	return [ast.Stmt{
		kind: .switch_stmt
		cond: cond
		body: body
		line: t.line
		col:  t.col
	}]
}

// check_switch_operand refuses a controlling expression that is not an integer,
// which is what 6.8.4.2 asks for: measured on gcc 16.2.1, `switch (1.5)` is
// `switch quantity not an integer` and `switch (p)` on a `char *` is the same
// message about the address. An operand whose type the reader did not resolve
// was refused where it was written, and it is left alone here so that one
// construct is one diagnostic.
fn (mut p Parser) check_switch_operand(expr ast.Expr, at tokenize.Token) {
	typ := p.value_type(expr)
	if typ.kind == .unknown {
		return
	}
	if !typ.kind.is_integer() {
		p.error_at(at, 'unsupported: the switch quantity is not an integer')
	}
}

// parse_case_label reads `case constant: stmt`. The value is converted to the
// type of the controlling expression where the label is placed, so what is kept
// here is the constant as written; what this reader refuses is a value it cannot
// reduce to one, which is a constant expression that is not a written constant.
//
// The label is worth a statement of its own rather than a field on the statement
// after it: a run of labels over one statement, `case 0: case 1: x += 1;`, is a
// run of statements in C's grammar, and a label with no statement under it is a
// case that falls into the next one.
fn (mut p Parser) parse_case_label() ![]ast.Stmt {
	t := p.next() // case
	if p.case_values.len == 0 {
		p.error_at(t, 'unsupported: a case label is not in a switch statement')
		p.skip_statement()
		return []ast.Stmt{}
	}
	expr := p.parse_expression() or {
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(':') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	value := p.case_constant(expr) or {
		// The label is refused for its value, and the statement under it is
		// still read: the arm is not a place the switch can jump to, and
		// skipping it would report the statements after it a second time.
		p.error_at(t, 'unsupported: this case value is not one this reader reduces to an integer constant, and only a written integer constant or one of those negated is read')
		return p.statement_under_label()
	}
	if p.case_values[p.case_values.len - 1][value] {
		p.error_at(t, 'duplicate case value ${value} in one switch')
		return p.statement_under_label()
	}
	p.case_values[p.case_values.len - 1][value] = true
	mut out := [ast.Stmt{
		kind:       .case_stmt
		case_value: value
		line:       t.line
		col:        t.col
	}]
	out << p.statement_under_label()!
	return out
}

// parse_default_label reads `default: stmt`. Which of the labels is the default
// one is not a position in the body: measured on gcc 16.2.1, a default written
// first, in the middle or last selects the same arm, because the labels are a
// set and the order they are written in is the order control falls through them.
// A second default in one switch is refused.
fn (mut p Parser) parse_default_label() ![]ast.Stmt {
	t := p.next() // default
	if p.case_defaults.len == 0 {
		p.error_at(t, 'unsupported: a default label is not in a switch statement')
		p.skip_statement()
		return []ast.Stmt{}
	}
	if !p.expect_punct(':') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	// The colon is read before the label is judged, so that a refused default
	// leaves the reader at the statement under it rather than at its colon.
	// Reading it as an expression would report the label twice.
	if p.case_defaults[p.case_defaults.len - 1] {
		p.error_at(t, 'duplicate default label in one switch')
		return p.statement_under_label()
	}
	p.case_defaults[p.case_defaults.len - 1] = true
	mut out := [ast.Stmt{
		kind: .default_stmt
		line: t.line
		col:  t.col
	}]
	out << p.statement_under_label()!
	return out
}

// case_constant is the integer a case label names. 6.8.4.2 asks for an integer
// constant expression, and what this reader reduces is a written integer
// constant, a character constant, or a chain of `-`, `+` and `~` over one of
// those: an expression worked out from several terms is refused by name rather
// than guessed at, and the chain is walked with a loop because how many
// operators one has is what the source says and not something a compiler
// chooses.
fn (mut p Parser) case_constant(expr ast.Expr) ?i64 {
	mut operators := []string{}
	mut node := expr
	for node is ast.Unary {
		unary := node as ast.Unary
		operators << unary.op
		node = unary.expr
	}
	if node !is ast.IntLit {
		return none
	}
	written := node as ast.IntLit
	mut value := written.value
	for i := operators.len - 1; i >= 0; i-- {
		match operators[i] {
			'-' {
				value = -value
			}
			'~' {
				value = ~value
			}
			'+' {}
			else {
				return none
			}
		}
	}
	return value
}

// parse_for_statement reads `for (A; B; C) D` and writes the loop it means: a
// block holding A, then a while whose condition is B and whose body is D with C
// after it. The tree has a while and no for, so a reader that never saw the
// source is reading a loop that runs the step at the end of every round, which
// is what a for does. The condition and the step are the ones that were written,
// in the order they were written.
//
// A missing A or C is nothing, and nothing is written for it. A missing B is a
// loop only a break ends: the language says the condition is a nonzero constant
// there, so the tree spells it 1, which is the same loop in the shape this tree
// has.
fn (mut p Parser) parse_for_statement() ![]ast.Stmt {
	t := p.next() // for
	if !p.expect_punct('(') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	mut head := []ast.Stmt{}
	if p.at_punct(';') {
		p.next()
	} else if p.starts_declaration(p.peek()) {
		// `for (int i = 0; ...)`: the declaration reader stops after the `;`
		// that every header has, which is where the condition starts.
		head = p.parse_local_declaration()
	} else {
		stmt := p.parse_expression_statement() or {
			p.skip_statement()
			return []ast.Stmt{}
		}
		if !p.expect_punct(';') {
			p.skip_statement()
			return []ast.Stmt{}
		}
		head << stmt
	}
	mut cond := ast.Expr(ast.IntLit{
		value: 1
		text:  '1'
		line:  t.line
		col:   t.col
	})
	if !p.at_punct(';') {
		cond = p.parse_expression() or {
			p.skip_statement()
			return []ast.Stmt{}
		}
	}
	if !p.expect_punct(';') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	mut step := []ast.Stmt{}
	if !p.at_punct(')') {
		stmt := p.parse_expression_statement() or {
			p.skip_statement()
			return []ast.Stmt{}
		}
		step << stmt
	}
	if !p.expect_punct(')') {
		p.skip_statement()
		return []ast.Stmt{}
	}
	body := p.parse_control_body()!
	// The step is the loop's own third part rather than the body's last
	// statement: a continue has to reach it, and a continue at the end of the
	// body would jump over a statement written inside the body.
	loop := ast.Stmt{
		kind: .while_stmt
		cond: cond
		body: body
		step: step
		line: t.line
		col:  t.col
	}
	mut block := head.clone()
	block << loop
	return [ast.Stmt{
		kind: .block
		body: block
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
	if offender := p.unsupported_type_word(spec) {
		p.error_at(spec.start, 'unsupported type ${offender}')
		// The declaration is refused for its type, and the name it declares is
		// still a name this file declares: recording it here is what keeps a later
		// use of it from being reported a second time as a name nothing declares,
		// which would say something untrue about the source. A statement that
		// reads it is still refused where it is written, by the type this
		// declaration never gave it.
		if p.peek().kind == .identifier {
			p.declared[p.peek().text] = true
		}
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
		if d.array_dims > 1 {
			p.error_at(d.array_at, 'unsupported: only one size of an array is implemented, and this declarator writes ${d.array_dims}')
			p.skip_declaration()
			return stmts
		}
		declared := p.declared_type(spec.clause, d)
		mut init := ?ast.Expr(none)
		// brace says the initializer was written as a list, elements are its
		// values as expressions, and list_ok says the list was read. A list that
		// was refused has already been reported and is not reported again as an
		// array with no size.
		mut brace := false
		mut list_ok := false
		mut elements := []ast.Expr{}
		if p.at_punct('=') {
			p.next()
			if p.at_punct('{') {
				brace = true
				if d.stars == 0 && spec.clause.kind in [types.Kind.struct_, .union_] {
					// A list for an object of an aggregate type is a list of
					// lists: a member may itself be an aggregate, and the
					// designators and the nesting are not shapes this reader
					// has. Measured, gcc 16.2.1 refuses `struct S s = {5, 6};`
					// with `invalid initializer`, and this compiler used to
					// report the same declaration twice.
					p.error_at(p.peek(), 'unsupported: ${d.name} is an object of the type ${spec.clause.describe()}, and a brace initializer for one is not implemented')
					p.skip_declaration()
					return stmts
				}
				if list := p.parse_brace_initializer() {
					list_ok = true
					if d.array_at.line == 0 {
						// One scalar in braces. A list of more values has no
						// room in one object (6.7.8p2, measured on gcc
						// 16.2.1: `int x = {1, 2};` is `excess elements in
						// scalar initializer`).
						if list.values.len > 1 {
							p.error_at(list.at, 'a constraint violation: ${d.name} holds one value and its initializer writes ${list.values.len}')
						}
						init = p.constant_expr(list.values[0])
					} else {
						// A written size smaller than the list is the same
						// violation (measured, `int a[2] = {1, 2, 3};` is
						// `excess elements in array initializer`).
						if d.array_count > 0 && list.values.len > d.array_count {
							p.error_at(list.at, 'a constraint violation: ${d.name} holds ${d.array_count} elements and its initializer writes ${list.values.len}')
						}
						for value in list.values {
							elements << p.constant_expr(value)
						}
					}
				}
			} else {
				init = p.parse_expression() or {
					p.skip_declaration()
					return stmts
				}
			}
			if initializer := init {
				// 6.7.8 lets an array of characters be initialized by a string
				// literal, which is not an assignment and not this constraint's
				// business: it is the one initializer that is not a value written
				// into an object.
				if !(declared.is_array() && initializer is ast.StrLit) {
					p.check_initializer(declared, initializer)
				}
			}
		}
		// An array declaration needs a size, and a brace list is one for an
		// array whose brackets were empty: `int a[] = {1, 2, 3};` declares a of
		// three. A list the reader refused has already been named and the size
		// is not reported a second time.
		if d.array_at.line > 0 && d.array_count <= 0 && !brace {
			p.error_at(d.array_at, 'unsupported: an array declaration in a body needs a size that is a number and more than zero')
			p.skip_declaration()
			return stmts
		}
		count := if d.array_count > 0 { d.array_count } else { elements.len }
		stmts << ast.Stmt{
			kind:       .var_decl
			init:       init
			decl_name:  d.name
			decl_type:  p.spelling_of(spec, d.stars)
			decl_count: count
			// The declarator decides whether the object is the aggregate or
			// something derived from it: `struct S x;` is the object, and
			// `struct S *p;` is one word holding an address, which the back end
			// sizes from the spelling.
			// An array of aggregates carries the size of one element here, and
			// the count it was declared with travels beside it: the frame reserves
			// the product, and an index scales by the size of one element.
			bytes:      p.aggregate_bytes(declared)
			line:       d.name_at.line
			col:        d.name_at.col
		}
		// A list for an array is the stores the initialization makes at the
		// point of the declaration: one per value the list wrote, and a zero for
		// each the list did not, because the rest of a partly initialized array
		// is the zeros C says it holds. The frame slot starts as whatever was
		// there, so the unwritten elements have to be written.
		if brace && list_ok && d.array_at.line > 0 {
			for i in 0 .. count {
				value := if i < elements.len {
					elements[i]
				} else {
					ast.Expr(ast.IntLit{
						value: 0
						text:  '0'
						typ:   types.int_type()
						line:  d.name_at.line
						col:   d.name_at.col
					})
				}
				stmts << ast.Stmt{
					kind:   .assign
					target: d.name
					index:  ast.Expr(ast.IntLit{
						value: i64(i)
						text:  '${i}'
						typ:   types.int_type()
						line:  d.name_at.line
						col:   d.name_at.col
					})
					expr:   value
					line:   d.name_at.line
					col:    d.name_at.col
				}
			}
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
