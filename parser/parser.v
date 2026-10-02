module parser

import ast
import backend
import tokenize
import types

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
	// scopes is every name this file has declared, in the scope it was declared
	// in. The declaration grammar needs it: `size_t n` and `puts(x)` are the
	// same token shape, and only the names seen so far say which one a statement
	// holds. It is also what gives every node its type clause, because a name is
	// typed where it is read and a name the reader has not met yet has nothing
	// to find. It is a table of scopes rather than one map because an inner
	// declaration hides an outer one and gives it back when its block ends.
	scopes types.Table
	// representation is what the target description answered about the object
	// representation of the C types: the width of a pointer, and the width of
	// the integer kinds the back end writes a constant at. A question that
	// needs a width the description does not carry is refused and the node it
	// belongs to is left unresolved rather than guessed at.
	representation types.Representation
	// pending_base is the type the specifiers just read name, for the declarator
	// that follows them. A declarator is read in three places - a declaration, a
	// parameter and a member - and it is the same grammar in all three, so what
	// the specifiers resolved to is held here for the declarator to use.
	pending_base    ?types.Type
	pending_storage types.Storage
	// depth counts open parentheses. The grammar recurses only through them, so
	// this is the one number that keeps a hostile file from running the stack out.
	depth int
	// globals is every object this file defined at the top level, in the order
	// the definitions were read. A declaration returns functions, because only
	// functions are code; the objects are collected here and travel with the
	// tree, since a body reads them by name.
	globals []ast.Global
	// declared is every name this file declares anywhere, wherever it was
	// declared: an object, a function, a typedef, a parameter. It is what the
	// check at the end of the unit asks a name the tree carries against, and it
	// is a set of names rather than the scope table because that check is about
	// the unit and not about which block a name was visible in.
	declared map[string]bool
	// file is the source the tokens being read came from, which the preprocessor
	// fills in for every file it reads. A diagnostic raised inside an included
	// file names that file: reporting a header's line number against the name of
	// the program that included it is a message about the wrong file.
	file string
}

// supported_types are the ones the back end can emit today. The 8-byte integer
// spellings are here because the emitter moves eight bytes for a pointer already
// and computes at that width for the 128-bit pair, so a value of one of them is
// the width it already has. `unsigned` and `unsigned int` are one type, and so are
// the three ways of writing each of the long types, which is why the spellings are
// listed and not the kinds: the check is against what the file wrote.
const supported_types = ['int', 'char', 'void', 'double', 'long', 'long long', 'unsigned',
	'unsigned int', 'unsigned long', 'unsigned long long']

// emitted_kinds are the kinds those spellings name, which is the question a
// spelling cannot answer on its own: `unsigned`, `unsigned int` and `unsigned
// long` are three spellings and two kinds, `long int` and `signed long` are two
// more spellings of a kind already listed, and a typedef resolves to a spelling
// that may be any of them. A type is one the emitter has a form for when the words
// name one of these.
const emitted_kinds = [types.Kind.void_, .int_, .unsigned_int, .char_, .double, .long, .unsigned_long,
	.long_long, .unsigned_long_long]

// max_expression_depth bounds how deep one expression nests: the parenthesised
// kind, the prefix kind and the cast kind all write one expression inside
// another. The C standard asks a compiler for 63 levels; past this the parser
// reports instead of following the recursion until the stack runs out.
const max_expression_depth = 200

// parse reads a token stream into a translation unit, for the machine this binary
// was built to run on. A caller that has chosen a target uses parse_for, because
// the two are not the same machine once a second target exists.
pub fn parse(tokens []tokenize.Token) Result {
	return parse_for(tokens, backend.host())
}

// parse_for reads a token stream into a translation unit for a chosen target.
//
// The target is a parameter rather than something this file looks up, because
// nearly every width it resolves is the target's: the width of a pointer and of an
// int, the offset a member sits at, the type a constant is given, and the class an
// object of aggregate type is handed over in. A parse is a parse for one machine,
// so the caller that selected the machine has to say which one. An absent target
// leaves every width unanswered, which turns a question about one into a refusal
// that names what could not be answered instead of a number this file invented.
pub fn parse_for(tokens []tokenize.Token, target ?backend.Target) Result {
	mut p := Parser{
		tokens:         tokens
		scopes:         types.new_table()
		representation: representation_of(target)
		declared:       map[string]bool{}
	}
	unit := p.parse_unit()
	// Every name the tree carries has to be a name this file declares. A name
	// that is not is refused here, once the whole unit has been read, because
	// whether a name is declared is a question only the end of the file can
	// answer: a definition may follow the function that calls it.
	p.report_undeclared(unit)
	return Result{
		unit:        unit
		diagnostics: p.diagnostics
	}
}

// representation_of is what the description says about the C types: the width of a
// pointer, and the width of an int and of an unsigned int, which is the width the
// back end writes a constant at. A question the description cannot answer is
// refused by name, which is the difference between a compiler that does not know
// something and one that guesses. A description of nothing answers nothing, so a
// missing target reaches the same refusal as an unknown width.
fn representation_of(target ?backend.Target) types.Representation {
	chosen := target or { return types.Representation{} }
	return types.from_target(chosen).representation
}

// is_type_name says whether a name is one this file has declared as a type
// rather than as an object.
fn (p Parser) is_type_name(name string) bool {
	symbol := p.scopes.lookup(name) or { return false }
	return symbol.is_typedef()
}

// resolve is the one lookup the expression reader does, and it is the reason a
// name declared later is not a name: this answers with what has been declared so
// far, and the zero type for a name the reader has not met.
fn (p Parser) resolve(name string) types.Type {
	symbol := p.scopes.lookup(name) or { return types.Type{} }
	return symbol.typ
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
		// not there. What the specifiers of the last declaration resolved to is
		// per declaration for the same reason.
		p.depth = 0
		p.pending_base = none
		p.pending_storage = .automatic
		decls << p.parse_declaration()
	}
	return ast.TranslationUnit{
		decls:   decls
		globals: p.globals
	}
}

// parse_block reads `{ ... }`. Every statement a body is made of is read by the
// statement reader; what is left here is the block's own business: where it
// ends, what a declaration inside it is scoped to, and what happens when the file
// ends before it does.
//
// The block is a scope, which is where 6.2.1 puts the names declared in it: a
// declaration inside a block hides one outside it and gives it back when the
// block ends. Names are declared where the statement reader meets them, so this
// opens the scope before the first statement and closes it when the closing brace
// is read, errors included.
//
// A declaration statement gets its type clause here, from the symbol the
// declaration recorded. The statement reader builds a declaration out of the
// spelling it reads - that is its job - and the clause is filled from the one
// place that answered the type, so the node and the scope cannot disagree.
fn (mut p Parser) parse_block() ![]ast.Stmt {
	open := p.peek()
	if !p.at_punct('{') {
		p.error_at(open, 'unsupported: expected { to open a block, found ${describe(open)}')
		return error('expected a block')
	}
	p.next()
	p.scopes.enter()
	defer {
		p.scopes.leave()
	}
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
		stmts << p.with_declared_types(fresh)
	}
	return stmts
}

// with_declared_types gives every declaration among the statements of a block the
// type its declaration resolved to, taken from the symbol table the declaration
// was recorded in.
fn (p Parser) with_declared_types(stmts []ast.Stmt) []ast.Stmt {
	mut out := []ast.Stmt{cap: stmts.len}
	for stmt in stmts {
		if stmt.kind == .var_decl {
			if symbol := p.scopes.lookup(stmt.decl_name) {
				out << ast.Stmt{
					...stmt
					resolved: symbol.typ
				}
				continue
			}
		}
		out << stmt
	}
	return out
}

// report_undeclared refuses every name the tree carries that nothing in the unit
// declares.
//
// The emitter resolves a name at layout, and a call to a name no declaration
// describes is written as a call to a symbol the image does not hold: measured,
// `int main(void) { return missing(1); }` compiled into a binary that died at
// load with `undefined symbol: missing`. The question is asked here, over the
// whole unit, rather than where the name is read, because a definition may
// follow the function that calls it: `int main(void) { return f(); } int f(void)
// { return 0; }` is a file this compiler reads, and a use it had not met a
// declaration for by then is not by itself a name nothing declares. A name no
// declaration in the unit provides is the class C99 refuses as an implicit
// declaration, and refusing it is what keeps a name the back end cannot place
// out of an image.
//
// One diagnostic per name, at the first use the walk reaches, because three uses
// of a name nothing declares are one missing declaration and not three.
fn (mut p Parser) report_undeclared(unit ast.TranslationUnit) {
	mut reported := map[string]bool{}
	for decl in unit.decls {
		p.check_undeclared_statements(decl.body, mut reported)
	}
}

fn (mut p Parser) check_undeclared_statements(stmts []ast.Stmt, mut reported map[string]bool) {
	for stmt in stmts {
		if stmt.kind == .assign {
			// The name an assignment writes to is a use of it: `missing = 1;`
			// names a missing declaration just as reading the name does.
			p.check_undeclared_name(stmt.target, stmt.line, stmt.col, mut reported)
		}
		if expr := stmt.expr {
			p.check_undeclared_expression(expr, mut reported)
		}
		if init := stmt.init {
			p.check_undeclared_expression(init, mut reported)
		}
		if index := stmt.index {
			p.check_undeclared_expression(index, mut reported)
		}
		if cond := stmt.cond {
			p.check_undeclared_expression(cond, mut reported)
		}
		p.check_undeclared_statements(stmt.body, mut reported)
		p.check_undeclared_statements(stmt.then_body, mut reported)
		p.check_undeclared_statements(stmt.else_body, mut reported)
		p.check_undeclared_statements(stmt.step, mut reported)
	}
}

// check_undeclared_expression walks one expression for the names it carries: the
// name of a value, the name a call reaches, and the name of an array being
// subscripted or assigned element by element.
fn (mut p Parser) check_undeclared_expression(expr ast.Expr, mut reported map[string]bool) {
	match expr {
		ast.Ident {
			p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
		}
		ast.Call {
			p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
			for argument in expr.args {
				p.check_undeclared_expression(argument, mut reported)
			}
		}
		ast.Index {
			p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
			p.check_undeclared_expression(expr.index, mut reported)
		}
		ast.Field {
			p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
		}
		ast.Unary {
			p.check_undeclared_expression(expr.expr, mut reported)
		}
		ast.Cast {
			p.check_undeclared_expression(expr.expr, mut reported)
		}
		ast.Binary {
			p.check_undeclared_expression(expr.left, mut reported)
			p.check_undeclared_expression(expr.right, mut reported)
		}
		ast.IncDec {
			// The name the operator steps is a use of it: `++missing;` names
			// a missing declaration just as reading the name does.
			p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
		}
		ast.Conditional {
			// All three operands are read, because all three can name
			// something: the condition as much as either arm.
			p.check_undeclared_expression(expr.cond, mut reported)
			p.check_undeclared_expression(expr.then_expr, mut reported)
			p.check_undeclared_expression(expr.else_expr, mut reported)
		}
		ast.IntLit, ast.StrLit, ast.FloatLit {}
	}
}

fn (mut p Parser) check_undeclared_name(name string, line int, col int, mut reported map[string]bool) {
	// A reserved word is not a name, and the constructs that put one in the tree
	// as if it were - a cast, which this reader does not implement - carry their
	// own diagnostic. Reporting the word here as well would be a second message
	// about a construct that was already refused.
	if name.len == 0 || is_keyword(name) || name in p.declared || name in reported {
		return
	}
	reported[name] = true
	p.error_span(line, col, 'unsupported: ${name} is used here and nothing in this file declares it')
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
	condition := p.parse_binary(0)!
	if !p.at_punct('?') {
		return condition
	}
	return p.parse_conditional(condition)
}

// parse_conditional reads a `? then : else` after the condition it selects on.
//
// The conditional operator binds looser than every binary operator and tighter
// than an assignment, so it is read after the precedence climbing has taken
// every operator that binds tighter: `a || b ? c : d` selects on `a || b`. It
// is right-associative, and the third operand is read as an expression again,
// which is what makes `a ? b : c ? d : e` read as `a ? b : (c ? d : e)`. The
// middle operand is the whole expression before the `:`, so it is read the same
// way.
//
// The GNU spelling with the middle operand left out, `a ?: b`, is not C99, and
// the standard reading of those tokens is not the same as the extension's: the
// extension repeats the condition, and this compiler refuses it by name rather
// than reading the condition as the middle operand.
fn (mut p Parser) parse_conditional(condition ast.Expr) !ast.Expr {
	question := p.next() // ?
	if p.at_punct(':') {
		p.error_at(question, 'unsupported: `?:` with the middle operand left out is a GNU extension and not C99, and this compiler reads the middle operand')
		return error('omitted middle operand')
	}
	// A chain of conditionals nests through its operands: the third of
	// `a ? b : c ? d : e` is another conditional and the second of
	// `a ? b ? c : d : e` is one too, so the reader recurses once per link.
	// The count that bounds parenthesised nesting bounds this one, so a chain
	// thousands of links long is refused rather than run out of stack.
	p.depth++
	if p.depth > max_expression_depth {
		p.depth--
		p.error_at(question, 'expression is nested more than ${max_expression_depth} levels deep')
		return error('expression nested too deeply')
	}
	then_expr := p.parse_expression() or {
		p.depth--
		return error('a conditional expression')
	}
	if !p.expect_punct(':') {
		p.depth--
		return error('a conditional expression without its colon')
	}
	else_expr := p.parse_expression() or {
		p.depth--
		return error('a conditional expression')
	}
	p.depth--
	return ast.Expr(ast.Conditional{
		cond:      condition
		then_expr: then_expr
		else_expr: else_expr
		typ:       p.conditional_type(question, then_expr, else_expr)
		line:      question.line
		col:       question.col
	})
}

// conditional_type is the type a conditional expression has, which 6.5.15
// decides from its two arms and never from its condition. Two arithmetic arms
// give the type the usual arithmetic conversions put them both in, two void
// arms give void, and two pointers give the pointer both arms convert to: a
// pointer to void takes over from a pointer to an object type, and a pointer
// beside an integer constant of value zero is that pointer's type, which is the
// null pointer constant rule.
//
// The answer is a question about the arms and not about which one runs, so it
// is asked while the expression is read and not where the branch is emitted.
// `sizeof(1 ? 1 : 1.0)` is the shape that needs it: the size is eight because
// the arm that is not an int makes the conditional a double.
//
// A pair the clause has no answer for is a constraint violation and is reported
// at the `?`. An arm whose type the reader did not resolve was refused where it
// was written, and the conditional is left unresolved rather than reported a
// second time.
fn (mut p Parser) conditional_type(op tokenize.Token, then_expr ast.Expr, else_expr ast.Expr) types.Type {
	a := p.value_type(then_expr)
	b := p.value_type(else_expr)
	if a.kind == .unknown || b.kind == .unknown {
		return types.Type{}
	}
	if a.is_arithmetic() && b.is_arithmetic() {
		return types.usual_arithmetic_conversions(a, b, p.representation) or {
			p.error_at(op, err.msg())
			return types.Type{}
		}
	}
	if a.is_void() && b.is_void() {
		return types.void_type()
	}
	if a.is_pointer() && b.is_pointer() {
		if a.same(b) {
			return a
		}
		left := a.pointee() or { types.Type{} }
		right := b.pointee() or { types.Type{} }
		// 6.5.15: a pointer to void beside a pointer to an object type gives
		// a pointer to void, whichever side it was written on.
		if left.kind == .void_ {
			return a
		}
		if right.kind == .void_ {
			return b
		}
		// 6.5.15: two pointers to compatibly qualified versions of one type
		// give a pointer to the composite type, which keeps both qualifiers.
		// `current != NULL ? current : "C"` for a `const char *current` is the
		// shape: the string literal is `char *`, and the result is const.
		if types.unqualified(left).compatible(types.unqualified(right)) {
			return types.pointer_to(types.qualified(left, right.quals))
		}
		p.error_at(op, 'a constraint violation: the two arms of a conditional are ${a.describe()} and ${b.describe()}, and they do not point to compatible types')
		return types.Type{}
	}
	// 6.5.15: a pointer beside an integer constant of value zero is that
	// pointer, the same pairing an initializer and an assignment allow.
	if a.is_pointer() && is_null_constant(else_expr) {
		return a
	}
	if b.is_pointer() && is_null_constant(then_expr) {
		return b
	}
	p.error_at(op, 'a constraint violation: the two arms of a conditional are ${a.describe()} and ${b.describe()}, and 6.5.15 pairs two arithmetic types, two void types, or two pointers')
	return types.Type{}
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
			typ:   p.binary_type(t, left, right)
			line:  t.line
			col:   t.col
		})
	}
	return left
}

// binary_type is the type an expression with two operands has: int for a
// comparison or a logical operator, and for the arithmetic and bitwise ones the
// type the two operands convert to, which is what 6.3.2.1 calls the usual
// arithmetic conversions. A shift is the one operator that is not symmetric in
// its operands, and 6.5.7 gives it the promoted type of its left one. An operand
// that is an array is read as a pointer to its first element first.
//
// Where the model refuses - two arithmetic operands whose conversion needs a
// width the target description does not carry - the refusal is reported at the
// operator, where the construct is written, and the clause is left unresolved
// rather than filled in. The emitter refuses a node whose clause is unresolved,
// so a construct nothing could type does not reach a binary. A node that already
// carries the zero type was refused where it was written, and a second message
// about the operator would only repeat the first.
//
// Pointer arithmetic is a case this model has no answer for: the type of `p + 1`
// this model answers, and the scale factor and the emitted bytes are the back end
// milestone's, but the type of the difference of two pointers is `ptrdiff_t`,
// which is a type a header names and not one this compiler has, so it stays
// unresolved and the back end refuses it.
fn (mut p Parser) binary_type(op tokenize.Token, left ast.Expr, right ast.Expr) types.Type {
	a := p.value_type(left)
	b := p.value_type(right)
	if op.text in ['&&', '||', '==', '!=', '<', '>', '<=', '>='] {
		// The answer is a truth value whatever the operands were.
		return types.int_type()
	}
	if op.text in ['<<', '>>'] {
		// 6.5.7: a shift answers with the type of its left operand after the
		// integer promotions. The count on the right is a value of its own
		// type and is not converted to the left operand's, which is why this
		// is not the conversion the two arithmetic operators go through.
		if p.is_unresolved(left) || p.is_unresolved(right) {
			return types.Type{}
		}
		if !a.is_integer() {
			p.error_at(op, 'unsupported: the type of ${describe_operand(left)} ${op.text} ${describe_operand(right)} is not one this compiler resolves')
			return types.Type{}
		}
		return types.integer_promotion(a, p.representation) or {
			p.error_at(op, err.msg())
			return types.Type{}
		}
	}
	if a.is_arithmetic() && b.is_arithmetic() {
		return types.usual_arithmetic_conversions(a, b, p.representation) or {
			p.error_at(op, err.msg())
			return types.Type{}
		}
	}
	if op.text == '+' || op.text == '-' {
		if a.is_pointer() && b.is_integer() {
			return a
		}
		if op.text == '+' && b.is_pointer() && a.is_integer() {
			return b
		}
	}
	if a.kind != .unknown && b.kind != .unknown {
		// Both operands were resolved and the model still has no answer for the
		// operator, which is a construct this reader does not type rather than
		// a construct it refused.
		p.error_at(op, 'unsupported: the type of ${describe_operand(left)} ${op.text} ${describe_operand(right)} is not one this compiler resolves')
	}
	return types.Type{}
}

// parse_member_path reads `.name` and the dots that follow it as one object read
// further in. The object's name is looked up once, and each dot after the first is
// read from the type the one before it answered, so the offsets add up as the path
// goes in and `b.a.x` comes back as one Field naming `b` at the byte `x` sits at.
// It is what both a value read and an assignment to a member go through, because
// the two ask the same question of the same path.
fn (mut p Parser) parse_member_path(base string, base_at tokenize.Token, through_pointer bool, index ?ast.Expr) !ast.Field {
	mut aggregate := p.scopes.lookup(base) or {
		p.error_at(base_at, 'unsupported: ${base} is read as an object with a member, and no declaration of that name is in scope')
		return error('unknown object')
	}.typ
	if index != none {
		// `s[i].a` reads the member of the element the index names, so the type
		// the member is looked up in is the element's type, not the array's. The
		// stride between elements is the size of that type, which the field's
		// declaration carried and the back end scales an index by.
		aggregate = aggregate.element() or {
			p.error_at(base_at, 'unsupported: ${base} is read as an array, and its declaration is not one')
			return error('not an array')
		}
	}
	if through_pointer {
		// `p->a` is the member of the object `p` points at, so the type the first
		// member is looked up in is the one the pointer's base names. A name that
		// is not a pointer has no object to be read through, and saying so here
		// keeps the pointer's value from being read as an address that means
		// something else.
		pointed_at := aggregate.pointee() or {
			p.error_at(base_at, 'unsupported: ${base} is read through ->, and it is declared ${aggregate.describe()} rather than a pointer')
			return error('not a pointer')
		}
		aggregate = pointed_at
	}
	mut member := p.parse_member(base, aggregate, 0, '', through_pointer, index)!
	for p.at_punct('.') {
		member = p.parse_member(base, member.typ, member.offset, member.member, false, index)!
	}
	return member
}

// parse_member reads one `.name` of an object and answers what the member is: how
// many bytes into the object it starts, what type the value at that offset has,
// and what to call both of those in a diagnostic.
//
// None of those is a fact about the source. The offset is where the model's
// layout of the object's type puts the member, and the type is the one the tag was
// declared with, so this is one of the places a declaration's type is asked rather
// than worked out from the words of the declaration.
//
// `aggregate` is the type of the object this `.` is read from, which for the `.x`
// of `b.a.x` is the type of `b.a` and not the type of `b`; `into` and `path` carry
// what the members before this one already answered, so the offsets add up and the
// diagnostic names the whole path. A member of a member is one object read further
// in, because a member of an object is inside the object, and a name written at the
// end of a path is one Field and not a chain of reads.
fn (mut p Parser) parse_member(base string, aggregate types.Type, into int, path string, through_pointer bool, index ?ast.Expr) !ast.Field {
	dot := p.next() // .
	if p.peek().kind != .identifier {
		p.error_at(p.peek(), 'unsupported: expected a member name after ., found ${describe(p.peek())}')
		return error('member name')
	}
	name := p.next()
	written := if path == '' { name.text } else { '${path}.${name.text}' }
	if aggregate.kind !in [types.Kind.struct_, .union_] {
		p.error_at(dot, 'unsupported: ${base}${if path == '' { '' } else { '.' + path }} is declared ${aggregate.describe()}, and a member is read from an object whose type has members')
		return error('not an aggregate')
	}
	mut at := -1
	for i, member in aggregate.members {
		if member.name == name.text {
			at = i
			break
		}
	}
	if at < 0 {
		p.error_at(name, 'unsupported: ${aggregate.describe()} has no member called ${name.text}')
		return error('unknown member')
	}
	layout := p.representation.layout(aggregate) or {
		p.error_at(name, 'unsupported: the members of ${aggregate.describe()} are not a layout this compiler knows, so the member ${name.text} cannot be read')
		return error('no layout')
	}
	member := aggregate.members[at]
	return ast.Field{
		name:            base
		index:           index
		member:          written
		offset:          into + layout.offsets[at]
		spelling:        member.typ.describe()
		typ:             member.typ
		through_pointer: through_pointer
		line:            dot.line
		col:             dot.col
	}
}

// aggregate_bytes is how many bytes of storage an object of this type takes when
// the type is one the back end cannot size from a spelling. A struct whose layout
// the model gave is that many bytes; everything else answers zero, which is what
// a declaration of a scalar asks for and never looks at.
fn (p Parser) aggregate_bytes(declared types.Type) int {
	if declared.is_array() {
		// An array of aggregates is a stride and a count: one element is as many
		// bytes as the layout says, and the count is what the declarator wrote, so
		// the stride is the size of the element's type and the frame scales an
		// index by it.
		element := declared.element() or { return 0 }
		return p.aggregate_bytes(element)
	}
	if declared.kind !in [types.Kind.struct_, .union_] || !declared.is_complete() {
		return 0
	}
	layout := p.representation.layout(declared) or { return 0 }
	return layout.size
}

// describe_operand names an operand of an operator for a diagnostic, so the
// refusal says which expression the operator was written between.
fn describe_operand(expr ast.Expr) string {
	return match expr {
		ast.Ident { expr.name }
		ast.Index { '${expr.name}[...]' }
		ast.Field { '${expr.name}.${expr.member}' }
		ast.IntLit { expr.text }
		ast.FloatLit { expr.text }
		ast.StrLit { 'a string literal' }
		ast.Call { 'a call to ${expr.name}' }
		ast.Unary { 'a value with ${expr.op} applied to it' }
		ast.Cast { 'a value converted to ${expr.spelling}' }
		ast.Binary { 'a value of ${expr.op}' }
		ast.IncDec { 'a value with ${expr.op} applied to ${expr.name}' }
		ast.Conditional { 'a conditional value' }
	}
}

// value_type is the type an operand contributes where a value is expected: the
// type it has, with an array decayed to a pointer to its first element and a
// function to a pointer to itself. 6.3.2.1 lists where that happens, and the
// places it does not are read from the operand's own clause instead - `&a` is the
// address of the array, and a string literal that initializes an array of
// characters stays an array.
fn (p Parser) value_type(expr ast.Expr) types.Type {
	return types.decay(expr.typ)
}

// unary_type is the type a prefix operator gives its expression. `!` answers with
// an int whatever it was given and `&` with a pointer to the operand's own type,
// undecayed; the arithmetic operators promote their operand.
//
// The promotion is a call the model can refuse, and where it does the refusal is
// reported at the operator instead of being discarded. An operand that already
// carries the zero type was refused where it was written, so it is left alone
// rather than reported twice.
fn (mut p Parser) unary_type(op tokenize.Token, operand ast.Expr) types.Type {
	if op.text == '!' {
		return types.int_type()
	}
	if op.text == '*' {
		return p.deref_type(op, operand)
	}
	if op.text == '&' {
		if p.is_unresolved(operand) {
			return types.Type{}
		}
		return types.pointer_to(operand.typ)
	}
	if p.is_unresolved(operand) {
		return types.Type{}
	}
	return types.integer_promotion(p.value_type(operand), p.representation) or {
		p.error_at(op, err.msg())
		return types.Type{}
	}
}

// deref_type is the type of the value at an address: 6.5.3.2 makes `*p` a value
// of the type p points at, and an array's name is the address of its first
// element, so `*a` for `char a[4]` is a char. A value that is not an address has
// no value at it, and one that points at void has none either: both are refused
// here by name rather than read at the width of something else.
fn (mut p Parser) deref_type(op tokenize.Token, operand ast.Expr) types.Type {
	if p.is_unresolved(operand) {
		return types.Type{}
	}
	if operand.typ.is_array() {
		return operand.typ.element() or { types.Type{} }
	}
	if !operand.typ.is_pointer() {
		p.error_at(op, 'unsupported: * reads through an address, and this operand is ${operand.typ.describe()}')
		return types.Type{}
	}
	pointed_at := operand.typ.pointee() or { types.Type{} }
	if pointed_at.kind == .void_ {
		p.error_at(op, 'unsupported: * reads through an address of void, which has no value at it')
		return types.Type{}
	}
	return pointed_at
}

// is_unresolved says whether an expression's clause is the one the model could
// not answer for, which no operator may take an address of or promote.
fn (p Parser) is_unresolved(expr ast.Expr) bool {
	if expr.typ.kind == .unknown {
		return true
	}
	return false
}

fn (mut p Parser) parse_unary() !ast.Expr {
	t := p.peek()
	// `sizeof` binds as tightly as the prefix operators and not as tightly as a
	// call, so it is read here and not where a name is: `sizeof(char) * 4` is
	// four times the size of a char, and `sizeof x + 1` adds one to the size of
	// x, which is the grammar the standard writes for an operator.
	if t.kind == .identifier && t.text == 'sizeof' {
		return p.parse_sizeof(t)
	}
	// A conversion is written as a type name in parentheses, and it is read here
	// because that is where it binds: `(char *)p + 1` adds one to the address and
	// not to the char, and `*(int *)p` reads through the pointer rather than
	// multiplying. Which of the two a `(` opens - a type name or an expression -
	// is the token after it: a specifier word or a name this file declared as a
	// type is a conversion, and a name that is not is a value in parentheses.
	if t.kind == .punct && t.text == '(' && p.starts_declaration(p.peek_at(1)) {
		return p.parse_cast(t)
	}
	// `++` and `--` are prefix operators here: what follows is the operand they
	// step, and the value they are worth is the operand after the step. They
	// are read with the other prefix operators because that is where they bind
	// - `++*p` steps the value p points at - and because the operand is read by
	// the same function that reads the operand of a cast.
	if t.kind == .punct && (t.text == '++' || t.text == '--') {
		p.next()
		operand := p.parse_prefix_operand(t)!
		return p.inc_dec(t, operand, false)
	}
	// `&` and `*` are here with the other prefix operators: the address of a
	// value and the value at an address both bind as tightly as they do -
	// `&x + 1` is the address of x plus one, and `*p + 1` adds one to the char p
	// points at. Whether what follows is something with an address, and where the
	// storage of a name is, are questions for the back end and for this reader's
	// type lookup.
	if t.kind == .punct && t.text in ['-', '+', '!', '~', '&', '*'] {
		p.next()
		operand := p.parse_prefix_operand(t)!
		return ast.Expr(ast.Unary{
			op:   t.text
			expr: operand
			typ:  p.unary_type(t, operand)
			line: t.line
			col:  t.col
		})
	}
	return p.parse_postfix()
}

// parse_prefix_operand reads what a prefix operator applies to, and counts the
// nesting while it does.
//
// A chain of prefix operators is one expression written inside another, so it is
// the same count parenthesised nesting uses: `!!!!x` is four levels. Without the
// count, this reader follows the chain until the stack runs out, which is not
// hypothetical - measured on an 8 MB stack, a chain of six thousand `!` takes
// signal 11, and so does a chain of six thousand casts, because both come back
// through parse_unary. The standard asks a compiler for sixty-three levels, so
// refusing past two hundred costs a program nothing it is owed.
fn (mut p Parser) parse_prefix_operand(op tokenize.Token) !ast.Expr {
	p.depth++
	if p.depth > max_expression_depth {
		p.depth--
		p.error_at(op, 'expression is nested more than ${max_expression_depth} levels deep')
		return error('expression nested too deeply')
	}
	operand := p.parse_unary() or {
		p.depth--
		return error('the operand of ${op.text}')
	}
	p.depth--
	return operand
}

// parse_postfix reads a name, a call, an element or a member and then the
// postfix operators that follow it: `x++` and `x--`. A postfix operator binds to
// what comes before it, so it is read here, after parse_primary has built the
// operand, and before parse_binary is given a chance to read a binary operator
// at the same position.
//
// The loop takes every operator that follows, because `x++++` is two steps in
// the grammar; the second operand is an expression that is not a name and is
// refused by inc_dec, which is where the refusal belongs.
fn (mut p Parser) parse_postfix() !ast.Expr {
	mut expr := p.parse_primary()!
	for p.peek().kind == .punct && (p.peek().text == '++' || p.peek().text == '--') {
		op := p.next()
		expr = p.inc_dec(op, expr, true)!
	}
	return expr
}

// inc_dec builds the node for `++` or `--` on a name, and refuses every other
// operand where the operator is written: the lvalue this compiler steps is a
// plain object, so an element, a member and a literal are named in a diagnostic
// rather than read as something else.
//
// The type has to be an integer the back end moves as a value. The step is one,
// which is the increment of an integer and not of a pointer or a double, so a
// name of another type is refused by the type it is. A name whose type the
// reader never resolved is left for the walk that reports names nothing
// declares, so an undeclared name gets that message and not this one.
fn (mut p Parser) inc_dec(op tokenize.Token, operand ast.Expr, postfix bool) !ast.Expr {
	match operand {
		ast.Ident {
			if operand.typ.kind != .unknown
				&& operand.typ.kind !in [.int_, .char_, .signed_char, .unsigned_char] {
				p.error_at(op, 'unsupported: ${op.text} on ${operand.name}, which is ${operand.typ.describe()}, and this compiler steps an int or a char name only')
				return error('operand is not an integer name')
			}
			return ast.Expr(ast.IncDec{
				op:      op.text
				name:    operand.name
				postfix: postfix
				typ:     operand.typ
				line:    op.line
				col:     op.col
			})
		}
		else {
			p.error_at(op, 'unsupported: ${op.text} on ${describe_operand(operand)}, and this compiler implements ++ and -- on a plain name only')
			return error('operand is not a name')
		}
	}
}

// parse_cast reads a conversion: the type name in parentheses, and the operand it
// converts. The operand is a unary expression, which is what the grammar says and
// why `(char)-x` and `(char)*p` are conversions of a value rather than of a sum.
//
// A conversion to `void` is refused here rather than in the back end, because it
// is the one conversion that produces no value: `(void)f()` is a statement that
// throws a result away, and this tree has no node for a value that is not one.
fn (mut p Parser) parse_cast(at tokenize.Token) !ast.Expr {
	p.next() // (
	name := p.parse_type_name(1)!
	if !p.expect_punct(')') {
		return error('unclosed cast')
	}
	if name.typ.kind == .void_ {
		p.error_at(at, 'unsupported: a conversion to void throws its operand away, and this compiler reads a conversion as a value')
		return error('a conversion to void')
	}
	operand := p.parse_prefix_operand(at)!
	return ast.Expr(ast.Cast{
		spelling: name.spelling
		expr:     operand
		typ:      name.typ
		line:     at.line
		col:      at.col
	})
}

// max_size_constant is the largest size this reader answers with. A size is
// computed in an int, so a larger one has already overflowed by the time it
// reaches here, and a program that asks for one is refused rather than handed
// the low half of it.
const max_size_constant = 2147483647

// parse_sizeof reads `sizeof` and its operand, which is a type name or an
// expression, and answers how many bytes the operand's type takes.
//
// The answer is a constant: the size of a type is a fact about the target, and
// the standard makes it an integer constant expression, so a program that writes
// one is emitted as the value it computed to and the operand is never evaluated.
//
// The constant has the type the target gives size_t, which is unsigned long
// here. 6.5.3.4 makes the result size_t rather than an integer big enough to
// hold it, and the difference shows wherever a signedness does. Measured on gcc
// 16.2.1: `sizeof(int) - 5 > 0` is 1, `sizeof(int) - 5 < 0` is 0, and
// `sizeof(int) - 5` is 18446744073709551615, so four minus five here is what it
// is in an unsigned 64-bit type and not the -1 an int would give.
//
// The operand is not decayed: `sizeof buf` for `char buf[16]` is sixteen, which
// is the size of the array and not of the address an array's name is worth
// everywhere else in an expression.
fn (mut p Parser) parse_sizeof(at tokenize.Token) !ast.Expr {
	p.next() // sizeof
	mut spelling := ''
	mut size := 0
	if p.at_punct('(') && p.starts_declaration(p.peek_at(1)) {
		// The operand is written as a type, which is the one operand that says
		// nothing about a value.
		p.next() // (
		name := p.parse_type_name(0)!
		if !p.expect_punct(')') {
			return error('unclosed sizeof')
		}
		spelling = name.spelling
		size = p.representation.size_of(name.typ) or {
			p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler has no size for it')
			return error('no size for the type')
		}
	} else {
		operand := p.parse_unary()!
		spelling = describe_operand(operand)
		if p.is_unresolved(operand) {
			// The operand was refused where it was written, and its type is
			// the one the reader never resolved. Naming the operand is what
			// says which size could not be answered.
			p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler did not resolve its type')
			return error('no type for the operand')
		}
		size = p.representation.size_of(operand.typ) or {
			p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler has no size for ${operand.typ.describe()}')
			return error('no size for the operand')
		}
	}
	if size > max_size_constant {
		p.error_at(at, 'unsupported: ${spelling} is ${size} bytes, and this compiler answers a size in an int')
		return error('size past an int')
	}
	return ast.Expr(ast.IntLit{
		value: i64(size)
		text:  'sizeof(${spelling})'
		typ:   types.unsigned_long_type()
		line:  at.line
		col:   at.col
	})
}

fn (mut p Parser) parse_primary() !ast.Expr {
	t := p.peek()
	if t.kind == .number {
		p.next()
		// The spelling decides whether this is a floating constant or an
		// integer one, so the two readers are reached from here rather than
		// one of them guessing at the other's input.
		if is_floating_constant(t.text) {
			value := parse_floating_literal(t.text) or {
				p.error_at(t, err.msg())
				return error('bad floating literal')
			}
			return ast.Expr(ast.FloatLit{
				value: value
				text:  t.text
				typ:   p.floating_type(t, value)
				line:  t.line
				col:   t.col
			})
		}
		value := parse_integer_literal(t.text) or {
			p.error_at(t, err.msg())
			return error('bad integer literal')
		}
		return ast.Expr(ast.IntLit{
			value: value
			text:  t.text
			typ:   p.constant_type(t, value)
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
		// A character constant has the type int, whatever it was written as:
		// 6.4.4.4 says so, and it is why `'a' + 'b'` is an int in C.
		return ast.Expr(ast.IntLit{
			value: value
			text:  t.text
			typ:   types.int_type()
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
				typ:  p.call_type(t, args)
				line: t.line
				col:  t.col
			})
		}
		if p.at_punct('[') {
			// One element of an array, read where a value is expected. The
			// subscript is an expression of its own, so `a[i + 1]` and
			// `a[b[0]]` are both the shape this reads.
			p.next()
			index := p.parse_expression()!
			if !p.at_punct(']') {
				p.error_at(p.peek(), 'unsupported: expected ] after the index of an element, found ${describe(p.peek())}')
				return error('expected ]')
			}
			p.next()
			element := p.index_type(t)
			if p.at_punct('.') || p.at_punct('->') {
				// A member of an element of an array: the object is the element
				// the index names, so the path carries the index and the stride
				// between elements is the size of one element's type.
				return ast.Expr(p.parse_member_path(t.text, t, p.at_punct('->'), index)!)
			}
			return ast.Expr(ast.Index{
				name:  t.text
				index: index
				typ:   element
				line:  t.line
				col:   t.col
			})
		}
		if p.at_punct('.') || p.at_punct('->') {
			return ast.Expr(p.parse_member_path(t.text, t, p.at_punct('->'), ?ast.Expr(none))!)
		}
		typ := p.resolve(t.text)
		return ast.Expr(ast.Ident{
			name: t.text
			typ:  typ
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
			typ:   string_literal_type(t.text, value)
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

// constant_type is the type an integer constant has, which 6.4.4.1 decides from
// the spelling and the value. A constant whose type needs a width the description
// does not carry is refused here, at the constant as it was written: the model has
// no answer, and a node left unresolved is a node a later stage would have to
// guess a width for. Measured, `return 4294967295 > 2147483647;` was compiled
// with the constant read as an int and returned 0 where ISO C and gcc return 1.
fn (mut p Parser) constant_type(at tokenize.Token, value i64) types.Type {
	return types.integer_constant_type(at.text, value, p.representation) or {
		p.error_at(at, err.msg())
		return types.Type{}
	}
}

// floating_type is the type a floating constant has. 6.4.4.2 makes that a
// question about the suffix: a constant with no suffix is a double, and the two
// suffixes name types this compiler does not have, so the reader refuses them
// where the constant is written rather than choosing between three types here.
// A constant with no suffix is therefore a double, which is the type this
// compiler emits.
fn (mut p Parser) floating_type(at tokenize.Token, value f64) types.Type {
	if value != value {
		// A NaN is what a conversion that ran out of range produces, and the
		// constant it came from was a number the program wrote. Saying so at
		// the constant is better than emitting a NaN where a number was.
		p.error_at(at, '${at.text}: the constant is out of range for a double')
		return types.Type{}
	}
	return types.double_type()
}

// string_literal_type is the type of a string literal: an array of char holding
// the bytes and the terminator the literal does not write. A prefixed literal
// names a wide or UTF-8 character type, which is a header's type and not one this
// compiler has yet, so its clause is left unresolved.
fn string_literal_type(text string, value string) types.Type {
	if text.len > 0 && text[0] != `"` {
		return types.Type{}
	}
	return types.array_of(types.char_type(), value.len + 1)
}

// index_type is the type of one element of an array or of one pointed-to value:
// `a[i]` has the element type of what a was declared as, and `p[i]` the type p
// points at. The lookup is the one the name was declared with, which is what
// makes a subscript of a name the shape this reader can type. A name that is
// neither an array nor a pointer has no element to be one of, and that is
// refused here rather than left unresolved.
fn (mut p Parser) index_type(at tokenize.Token) types.Type {
	declared := p.resolve(at.text)
	if declared.is_array() {
		return declared.element() or { types.Type{} }
	}
	if declared.is_pointer() {
		return declared.pointee() or { types.Type{} }
	}
	p.error_at(at, 'unsupported: ${at.text} is neither an array nor a pointer, so it has no element to subscript')
	return types.Type{}
}

// signature is the function type a name declares, following a pointer to a
// function to the function it points at.
fn (p Parser) signature(name string) ?types.Type {
	declared := p.resolve(name)
	if declared.is_function() {
		return declared
	}
	if declared.is_pointer() {
		inner := declared.pointee() or { return none }
		if inner.is_function() {
			return inner
		}
	}
	return none
}

// is_callable says whether a name the unit declares is what 6.5.2.2 requires what a
// call calls to be, which is a function or a pointer to a function.
fn (p Parser) is_callable(name string) bool {
	signature := p.signature(name) or { return false }
	return signature.is_function()
}

// call_type is the type a call has: what the function returns. It also checks the
// arguments against the parameters as they were read, which is the constraint
// 6.5.2.2 names: an argument is converted to its parameter's type as if by
// assignment, so one rule decides both, and the diagnostic names the two types
// and the argument's own location.
//
// A call to a name this file never declared - every call to a library function
// here - has nothing to check against and answers with the zero type. A call
// through a parameter list that named no parameters has nothing to check either,
// because such a declaration says nothing about the call.
fn (mut p Parser) call_type(name tokenize.Token, args []ast.Expr) types.Type {
	// 6.5.2.2: what a call calls has to be a function or a pointer to one. A name
	// the unit declares as something else is refused here rather than written,
	// because the emitter resolves the call to whatever the name is and the image
	// then dies at load. Measured, `int x; int main(void) { return x(1); }`
	// compiled, wrote an image, and the image died at load with `undefined symbol:
	// x`. A name nothing in the unit declares is left to the check at the end of
	// the unit, which reports one message for it.
	if name.text in p.declared && !p.is_callable(name.text) {
		declared := p.resolve(name.text)
		p.error_at(name, 'a constraint violation: ${name.text} is declared as ${declared.describe()}, and what a call calls has to be a function or a pointer to a function')
		return types.Type{}
	}
	signature := p.signature(name.text) or { return types.Type{} }
	if !signature.prototyped {
		return signature.returns() or { types.Type{} }
	}
	parameters := signature.params
	if !signature.variadic && parameters.len != args.len {
		p.error_at(name, 'the call to ${name.text} passes ${args.len} argument(s), and the declaration of ${name.text} names ${parameters.len} argument(s)')
	}
	for index, argument in args {
		if index >= parameters.len {
			break
		}
		problem := types.assignment_problem(parameters[index].typ, p.value_type(argument), is_null_constant(argument)) or {
			continue
		}
		p.error_span(argument.line, argument.col, problem)
	}
	return signature.returns() or { types.Type{} }
}

// is_null_constant says whether an expression is the integer constant expression
// with the value 0 that 6.3.2.3 calls a null pointer constant, which is the one
// integer a pointer may be initialized with. The clause asks for the value of the
// expression and not for the way it is spelled, so `0`, `-0`, `2 - 2` and `3 / 4`
// are the same answer to the question here. Measured, gcc 16.2.1 under `-std=c99`
// accepts `h(1 - 1)` for a parameter of type `int (*)(void)`, which this compiler
// refused while the question was asked of the literal alone.
fn is_null_constant(expr ast.Expr) bool {
	value := constant_value(expr) or { return false }
	return value == 0
}

// constant_value is the value of an integer constant expression this reader
// evaluates while it reads: a literal, a literal with a sign in front of it, and
// the arithmetic of two values. The five arithmetic operators are the ones it
// folds, which is the arithmetic this compiler reads at all.
//
// An expression that is not one of those answers none, which says that this is not
// a constant expression the compiler can evaluate - not that it has no value. A
// name, a call and a cast all answer none, so a pointer is still never initialized
// with something that only has a value at run time.
fn constant_value(expr ast.Expr) ?i64 {
	if expr is ast.IntLit {
		return expr.value
	}
	if expr is ast.Unary {
		operand := constant_value(expr.expr) or { return none }
		if expr.op == '-' {
			return -operand
		}
		if expr.op == '+' {
			return operand
		}
		return none
	}
	if expr is ast.Binary {
		left := constant_value(expr.left) or { return none }
		right := constant_value(expr.right) or { return none }
		match expr.op {
			'+' {
				return left + right
			}
			'-' {
				return left - right
			}
			'*' {
				return left * right
			}
			'/' {
				if right == 0 {
					return none
				}
				return left / right
			}
			'%' {
				if right == 0 {
					return none
				}
				return left % right
			}
			else {
				return none
			}
		}
	}
	return none
}

// binary_precedence is the binding strength of an operator the tree has a node
// for. The order is C's: `*` binds tighter than `+`, `+` tighter than a shift, a
// shift tighter than the four comparisons, those tighter than `==`, `==` tighter
// than `&`, `&` tighter than `^`, `^` tighter than `|`, and `&&` tighter than
// `||`. An operator that is not in the table stops the expression, and the
// caller diagnoses whatever it stopped on.
//
// The numbers are a relative order rather than C's own levels, so inserting an
// operator renumbers the arms it is inserted between: the three bitwise
// operators and the two shifts belong between `==` and `&&`, which a gap of one
// has no room for.
fn binary_precedence(op string) int {
	return match op {
		'||' { 3 }
		'&&' { 4 }
		'|' { 5 }
		'^' { 6 }
		'&' { 7 }
		'==', '!=' { 8 }
		'<', '>', '<=', '>=' { 9 }
		'<<', '>>' { 10 }
		'+', '-' { 11 }
		'*', '/', '%' { 12 }
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
	// The tokens arrive in the order the preprocessor read the files, so the one
	// being read names the file a diagnostic raised before the next one is the
	// file the message is about.
	if t.file != '' {
		p.file = t.file
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
	// A token knows the file it came from, so a diagnostic about one names it
	// even when the token was not read yet - the reader reports what it is
	// looking at as often as what it just read.
	p.report_at(t.line, t.col, if t.file != '' { t.file } else { p.file }, msg)
}

// error_span reports a diagnostic at a position that came from a node rather than
// from a token: the argument of a call is where its own expression started, which
// is the line and column a reader of the source will look at. A node carries no
// file, so the one the reader is in is the file the message names.
fn (mut p Parser) error_span(line int, col int, msg string) {
	p.report_at(line, col, p.file, msg)
}

fn (mut p Parser) report_at(line int, col int, file string, msg string) {
	p.diagnostics << tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
		file: file
	}
}

fn describe(t tokenize.Token) string {
	if t.kind == .eof {
		return 'end of file'
	}
	return "'${t.text}'"
}
