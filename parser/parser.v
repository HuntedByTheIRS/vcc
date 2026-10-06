module parser

import ast
import backend
import backend.abi
import diagnostics
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

// PendingBound is a file-scope array bound that named something this reader did
// not resolve, with where the bound and the name were written. The report waits
// until the whole file has been read, because whether a name is declared anywhere
// is a question only the end of the file can answer.
struct PendingBound {
	object    string
	name      string
	name_line int
	name_col  int
	at_line   int
	at_col    int
}

// IdentSpan is the first and the last place an identifier text appears in the
// token stream. Both are token indices, and a name that appears once has the
// same number for each.
struct IdentSpan {
	first int
	last  int
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
	// vla_bounds is the bound expression of every variable-length array type
	// this unit has built, in the order they were built, and a type refers to
	// one by its number in this list. The model holds no expression - types
	// does not know the tree - so the bound lives here and the type carries the
	// handle to it. A number is one more than the position, so the zero value of
	// a type's handle means `not a variable-length array`.
	vla_bounds []VlaBound
	// pending_base is the type the specifiers just read name, for the declarator
	// that follows them. A declarator is read in three places - a declaration, a
	// parameter and a member - and it is the same grammar in all three, so what
	// the specifiers resolved to is held here for the declarator to use.
	pending_base    ?types.Type
	pending_storage types.Storage
	// depth counts how deep the expression being read is nested. The expression
	// grammar comes back on itself through more than one spelling - a
	// parenthesis, a prefix operator, a cast, a `?:`, a `[` index, a call's
	// argument list and a `sizeof` operand - and every one of them raises this
	// count, so it is the one number that keeps a hostile file from running the
	// stack out.
	depth int
	// globals is every object this file defined at the top level, in the order
	// the definitions were read. A declaration returns functions, because only
	// functions are code; the objects are collected here and travel with the
	// tree, since a body reads them by name.
	globals []ast.Global
	// extern_objects is every object this file declared at the top level with
	// no storage here: an `extern` declaration names an object another object
	// defines, so the name travels with the tree as a reachable name and not
	// as storage. It is kept apart from globals so nothing lays out storage for
	// a declaration.
	extern_objects []ast.Global
	// declared is every name this file declares anywhere, wherever it was
	// declared: an object, a function, a typedef, a parameter. It is what the
	// check at the end of the unit asks a name the tree carries against, and it
	// is a set of names rather than the scope table because that check is about
	// the unit and not about which block a name was visible in.
	declared map[string]bool
	// ident_span says, for every identifier text in the stream, where its first
	// and its last occurrence sit. `skip_uncalled_static` asks whether a
	// function's name is written anywhere outside its own definition, and the
	// name is an identifier in the stream itself, so both occurrences are in
	// these two numbers: everything the question needs is a comparison, where
	// walking the stream for each `static` a file has was one walk per
	// declaration on V's own generated C. A name that is not here is not an
	// identifier anywhere in the stream.
	ident_span map[string]IdentSpan
	// current_function is the name of the function whose body is being read, and
	// empty outside one. The function-name spellings read it: 6.4.2.2 makes
	// `__func__` a static array holding the name of the enclosing function, and
	// gcc's `__FUNCTION__` and `__PRETTY_FUNCTION__` are the same name. glibc's
	// assert hands `__PRETTY_FUNCTION__` to __assert_fail under a GNU dialect,
	// so the C this compiler has to compile reads one.
	current_function string
	// pending_bounds is a file-scope array bound whose expression names something
	// this reader did not resolve. Its report waits until the whole file has been
	// read, because whether a name is declared anywhere is a question only the end
	// of the file can answer: `int x[n]; int n = 4;` names a variable declared
	// later, and the bound is not an integer constant expression, while
	// `enum { N = 4 }; int x[N];` names nothing at all because this reader does
	// not declare enumeration constants. Reporting the second as a bound that is
	// not constant would name a cause the compiler cannot show.
	pending_bounds []PendingBound
	// bound_name is the first name a bound written in brackets carried that the
	// scope at that point did not have, with where it was written. The suffix
	// reader fills it for the declaration reader to keep on its step.
	bound_name      string
	bound_name_line int
	bound_name_col  int
	// file is the source the tokens being read came from, which the preprocessor
	// fills in for every file it reads. A diagnostic raised inside an included
	// file names that file: reporting a header's line number against the name of
	// the program that included it is a message about the wrong file.
	file string
	// case_values is one set of case values per switch statement being read,
	// innermost last. Two case labels in one switch with the same value are
	// refused where the second is written, which is the constraint 6.8.4.2
	// states; a switch's own set is pushed and popped around its body, so the
	// cases of a nested switch do not collide with the ones outside it.
	case_values []map[i64]bool
	// case_defaults says, one entry per switch being read, whether a default
	// label has been read in it: a second default in one switch is refused.
	case_defaults []bool
	// compound_serial numbers the unnamed objects a compound literal declares,
	// so each one gets a name of its own that no source text can write.
	compound_serial int
	// compound_pending is one list of statements per statement being read,
	// innermost last. A compound literal (C99 6.5.2.5) is an unnamed object,
	// so reading one declares a local and the stores that initialize it; those
	// statements belong in front of the statement the literal was written in,
	// and this is where they wait until that statement is finished and its list
	// is put together.
	compound_pending [][]ast.Stmt
	// compound_unstable counts the places being read whose expression may be
	// evaluated a number of times the enclosing statement does not describe: a
	// condition, a loop's third part, the right operand of `&&` or `||`, and an
	// arm of `?:`. A compound literal is built where its statement begins, which
	// is one evaluation; where this is not zero and the literal's list is not
	// constant, 6.5.2.5p7 re-initializes the object at the literal's own
	// position instead, so the value a later read sees is the one that
	// evaluation wrote.
	compound_unstable int
	// generic_controls is the controlling expression of every generic selection
	// read, kept because 6.5.17 says it is not evaluated: no code is emitted for
	// one, but the names it carries are still uses that have to be declared, and
	// the check at the end of the unit walks this list so a selection over a name
	// nothing declares is still reported.
	generic_controls []ast.Expr
}

// supported_types are the ones the back end can emit today. The 8-byte integer
// spellings are here because the emitter moves eight bytes for a pointer already
// and computes at that width for the 128-bit pair, so a value of one of them is
// the width it already has. `float` is here because the emitter has the
// four-byte instructions for one, which are the eight-byte ones with the other
// prefix. `short` and `_Bool` are here because the emitter loads and stores the
// one- and two-byte values they name. `unsigned` and `unsigned int` are one type,
// and so are the three ways of writing each of the long types, which is why the
// spellings are listed and not the kinds: the check is against what the file
// wrote. A spelling of more than one word is not here, because the words name a
// kind that emitted_kinds answers.
const supported_types = ['int', 'char', 'void', 'double', 'float', 'long', 'long long', 'signed',
	'unsigned', 'unsigned int', 'unsigned long', 'unsigned long long', 'short', '_Bool', '__float128']

// emitted_kinds are the kinds those spellings name, which is the question a
// spelling cannot answer on its own: `unsigned`, `unsigned int` and `unsigned
// long` are three spellings and two kinds, `long int` and `signed long` are two
// more spellings of a kind already listed, and a typedef resolves to a spelling
// that may be any of them. A type is one the emitter has a form for when the words
// name one of these.
const emitted_kinds = [types.Kind.void_, .int_, .unsigned_int, .bool_, .char_, .signed_char,
	.unsigned_char, .short, .unsigned_short, .double, .float, .long, .unsigned_long, .long_long,
	.unsigned_long_long, .long_double, .float128, .complex_float, .complex_double,
	.complex_long_double]

// max_expression_depth bounds how deep one expression nests: a parenthesis, a
// prefix operator, a cast, a `?:`, a `[` index, a call's argument list and a
// `sizeof` operand each write one expression inside another. The C standard
// asks a compiler for 63 levels; past this the parser reports instead of
// following the recursion until the stack runs out.
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
		ident_span:     map[string]IdentSpan{}
	}
	p.declare_argument_list()
	p.index_identifiers()
	unit := p.parse_unit()
	// A file-scope bound that named something the scope did not have is answered
	// now, because the whole file has been read and whether the name is declared
	// anywhere is a question only this point can answer.
	p.report_pending_bounds()
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

// declare_argument_list puts the type a header's `__builtin_va_list` names into
// the file scope before anything is read.
//
// `<stdarg.h>` declares it as a typedef of a compiler's own spelling, and the
// two typedefs a program sees - `__gnuc_va_list` and `va_list` - resolve
// through it, so a `va_list` in a program is this type written out. The type is
// the argument list the calling convention walks, which is a fact about the
// target, so it comes from `backend/abi` and is not spelled here.
fn (mut p Parser) declare_argument_list() {
	p.declared['__builtin_va_list'] = true
	p.scopes.declare_at_file_scope(types.Symbol{
		name:    '__builtin_va_list'
		typ:     abi.argument_list_type()
		storage: types.Storage.typedef_
		line:    1
		col:     1
	})
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

// index_identifiers records where the first and the last occurrence of every
// identifier text in the stream sit. It is one walk of the stream, and it buys
// the `static` step-over the two numbers it needs to answer, for every `static`
// definition in the file, without walking the stream again each time. Only the
// names a definition declares are ever asked about, and the stream holds far
// more tokens than it holds distinct names, so this is smaller than the stream
// it is built from.
fn (mut p Parser) index_identifiers() {
	for i, tok in p.tokens {
		if tok.kind != .identifier {
			continue
		}
		if existing := p.ident_span[tok.text] {
			p.ident_span[tok.text] = IdentSpan{
				first: existing.first
				last:  i
			}
			continue
		}
		p.ident_span[tok.text] = IdentSpan{
			first: i
			last:  i
		}
	}
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
		decls:          decls
		globals:        p.globals
		extern_objects: p.extern_objects
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
				// What the declaration resolved to is the symbol's type. A
				// statement that already carried an extra part keeps it, the
				// stride and the width a compound declaration worked out among
				// the rest, because this pass is about the type and nothing
				// else.
				mut extra := &ast.StmtExtra{
					resolved: symbol.typ
				}
				if source := stmt.extra {
					extra = &ast.StmtExtra{
						...*source
						resolved: symbol.typ
					}
				}
				out << ast.Stmt{
					...stmt
					extra: extra
				}
				continue
			}
		}
		out << stmt
	}
	return out
}

// report_pending_bounds answers each file-scope bound that named something the
// scope did not have, now that the whole file has been read. A name the file
// declares somewhere leaves the object without an integer constant expression,
// which is the constraint 6.6 makes for an object at file scope; a name the file
// declares nowhere is that name's own failure and is reported as one, at the name.
// The distinction matters because the two are different constructs: this reader
// does not declare enumeration constants, so `enum { N = 4 }; int x[N];` fails
// because N has no declaration, not because a declared N turned out not to be
// constant.
fn (mut p Parser) report_pending_bounds() {
	for bound in p.pending_bounds {
		if bound.name in p.declared {
			p.error_span(bound.at_line, bound.at_col, 'a constraint violation: the bound of ${bound.object} is not an integer constant expression, and an object at file scope needs a size that is one')
			continue
		}
		p.error_span(bound.name_line, bound.name_col, 'a constraint violation: ${bound.name} is used here and nothing in this file declares it')
	}
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
	// A generic selection's controlling expression is not in the tree, because
	// 6.5.17 does not evaluate it, so the names it carries are walked here. A
	// selection over a name nothing declares is still a use of that name.
	for control in p.generic_controls {
		p.check_undeclared_expression(control, mut reported)
	}
}

fn (mut p Parser) check_undeclared_statements(stmts []ast.Stmt, mut reported map[string]bool) {
	for stmt in stmts {
		if stmt.kind == .assign && stmt.target != '' {
			// The name an assignment writes to is a use of it: `missing = 1;`
			// names a missing declaration just as reading the name does. An
			// assignment through a dereference has no name of its own, and the
			// pointer it writes through is the expression below.
			p.check_undeclared_name(stmt.target, stmt.line, stmt.col, mut reported)
		}
		if deref := stmt.deref() {
			p.check_undeclared_expression(deref, mut reported)
		}
		if expr := stmt.expr {
			p.check_undeclared_expression(expr, mut reported)
		}
		if init := stmt.init {
			p.check_undeclared_expression(init, mut reported)
		}
		// A variable-length array's size expression carries the names its
		// bounds were written with, at the point the declaration runs.
		if size := stmt.decl_vla_size() {
			p.check_undeclared_expression(size, mut reported)
		}
		if index := stmt.index {
			p.check_undeclared_expression(index, mut reported)
		}
		if subscript := stmt.subscript() {
			p.check_undeclared_expression(subscript, mut reported)
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
			if callee := expr.callee {
				// A call through an expression names nothing itself; the names
				// are inside the expression the call is written to.
				p.check_undeclared_expression(callee, mut reported)
			} else {
				// A call to one of the argument-list operations, or to one of the
				// machine builtins the back end answers with an instruction, is not
				// a name the unit has to declare: the reader built the call itself,
				// from a spelling in the compiler's own namespace, and there is no
				// declaration any program could write for it. The builtin list in
				// `builtins.v` is the one place those spellings are named.
				if expr.name !in builtin_expression_names {
					p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
				}
			}
			for argument in expr.args {
				p.check_undeclared_expression(argument, mut reported)
			}
		}
		ast.Index {
			p.check_undeclared_expression(expr.base, mut reported)
			p.check_undeclared_expression(expr.index, mut reported)
			// The stride of an element of an array whose bound is a value is an
			// expression and carries the bound's names: `int m[r][c]` reaches
			// `c` through the subscript and not through any other node.
			if stride := expr.vla_stride {
				p.check_undeclared_expression(stride, mut reported)
			}
		}
		ast.Field {
			// A member of an expression carries the object's own names inside
			// the base; a member of a name is a use of that name.
			if base := expr.base {
				p.check_undeclared_expression(base, mut reported)
			} else {
				p.check_undeclared_name(expr.name, expr.line, expr.col, mut reported)
			}
		}
		ast.Unary {
			p.check_undeclared_expression(expr.expr, mut reported)
		}
		ast.Cast {
			p.check_undeclared_expression(expr.expr, mut reported)
		}
		ast.Binary {
			// An operator chain is one node deep in the grammar however many
			// terms it has, so the left spine is walked with a loop and only
			// genuinely nested expressions recurse: a chain of a few thousand
			// terms is a size generated code reaches, and a call per term would
			// take the stack out on it.
			mut spine := []ast.Binary{}
			mut node := ast.Expr(expr)
			for node is ast.Binary {
				step := node as ast.Binary
				spine << step
				node = step.left
			}
			p.check_undeclared_expression(node, mut reported)
			for i := spine.len - 1; i >= 0; i-- {
				p.check_undeclared_expression(spine[i].right, mut reported)
			}
		}
		ast.IncDec {
			// The object the operator steps is a use of it: `++missing;`
			// names a missing declaration just as reading the name does.
			p.check_undeclared_expression(expr.operand, mut reported)
		}
		ast.Conditional {
			// All three operands are read, because all three can name
			// something: the condition as much as either arm.
			p.check_undeclared_expression(expr.cond, mut reported)
			p.check_undeclared_expression(expr.then_expr, mut reported)
			p.check_undeclared_expression(expr.else_expr, mut reported)
		}
		ast.IntLit, ast.StrLit, ast.FloatLit, ast.ComplexLit {}
		ast.Assign {
			// The target is a use of what it names, and the value is an
			// expression of its own: both sides are walked.
			p.check_undeclared_expression(expr.target, mut reported)
			p.check_undeclared_expression(expr.value, mut reported)
		}
		ast.Comma {
			p.check_undeclared_expression(expr.left, mut reported)
			p.check_undeclared_expression(expr.right, mut reported)
		}
		ast.StmtExpr {
			// The body is statements and the value is an expression of its
			// own: both halves can name something, so each is walked the way
			// it would be at the place it stands.
			p.check_undeclared_statements(expr.body, mut reported)
			if value := expr.value {
				p.check_undeclared_expression(value, mut reported)
			}
		}
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
	// The class is the program's, not this compiler's: a name nothing declares is
	// the constraint C99 states as an implicit declaration. gcc 16.2.1 reports it
	// as an error in every mode measured (`-std=gnu11`, `-std=c99`, `-std=c23`,
	// `-std=c2y`: `error: implicit declaration of function 'helper'
	// [-Wimplicit-function-declaration]`, exit 1), and nothing here is a construct
	// this compiler lacks: the name has no place in the image and that is the
	// program's doing. It stays an error rather than the warning gcc's own flag
	// would make of it, because an image with an unresolved call is not one this
	// back end can write.
	p.error_span(line, col, 'a constraint violation: ${name} is used here and nothing in this file declares it')
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

// parse_parenthesized_expression reads the expression one level inside
// parentheses. 6.5.16 and 6.5.17 put the assignment and the comma at the top of
// the expression grammar, above every operator the precedence climb carries, so
// the tokens inside `( ... )` are a full expression: `(a = 1, b = 2, a + b)` is
// one expression worth 3, and that is what this reader answers with.
//
// The two readers below are reached from here and from the three other places an
// assignment is an expression: the condition of an if, a while, a do-while and a
// switch, the condition of a for header, and the value of another assignment,
// which is what makes `a = b = 3` right associative. A comma still separates in
// an argument list and a brace initializer, because those readers never descend
// through the parenthesized-expression reader.
fn (mut p Parser) parse_parenthesized_expression() !ast.Expr {
	return p.parse_comma_expression()
}

// parse_comma_expression reads an assignment expression and, while a comma
// follows, another one. 6.5.17 makes the comma left associative and worth the
// value of its right operand, so the operands on its left are evaluated for what
// they do: `(a = 1, b = 2, a + b)` writes 1, writes 2 and is worth 3.
fn (mut p Parser) parse_comma_expression() !ast.Expr {
	mut left := p.parse_assignment_expression()!
	for p.at_punct(',') {
		t := p.next()
		right := p.parse_assignment_expression()!
		left = ast.Expr(ast.Comma{
			left:  left
			right: right
			typ:   p.value_type(right)
			line:  t.line
			col:   t.col
		})
	}
	return left
}

// parse_assignment_expression reads an expression and, where an assignment
// operator follows it, the assignment that operator writes. 6.5.16 makes an
// assignment an expression, and the expression is worth the value written after
// the conversion the store makes, which is the type of the object written. The
// operator is right associative, which is why the value is read by this same
// reader: `(a = b = 3)` writes 3 into b and then b into a.
//
// The left operand has to be a place. The places this tree writes are the ones
// the statement reader addresses - a name, an element, a member and a
// dereference - and anything else is refused by name at the operator.
//
// A compound spelling is read as the assignment it means, the way the statement
// reader reads it: `a <<= 1` is `a = a << 1`, and the sum is built here so the
// value the node carries is the one written. The spelling is not asked about in
// the assignment check, because the sum is the node the check would have to ask
// about and it carries the type the operands gave it.
fn (mut p Parser) parse_assignment_expression() !ast.Expr {
	left := p.parse_expression()!
	op := p.assignment_operator() or { return left }
	p.next()
	if !is_a_place(left) {
		p.error_at(op, 'unsupported: the left operand of ${op.text} is ${describe_operand(left)}, and an assignment writes to a name, an element, a member or a dereference')
		return error('assignment target')
	}
	target_type := p.value_type(left)
	if op.text == '=' {
		value := p.parse_assignment_expression()!
		p.check_assignment(target_type, value, op)
		return ast.Expr(ast.Assign{
			op:     op.text
			target: left
			value:  value
			typ:    target_type
			line:   op.line
			col:    op.col
		})
	}
	arithmetic := op.text[..op.text.len - 1]
	if arithmetic !in ['+', '-', '*', '/', '%', '<<', '>>', '&', '|', '^'] {
		p.error_at(op, 'unsupported: the compound assignment ${op.text} is not implemented')
		return error('compound assignment')
	}
	if !is_a_compound_target(left) {
		p.error_at(op, 'unsupported: the compound assignment ${op.text} to ${describe_operand(left)} is not implemented')
		return error('compound assignment target')
	}
	right := p.parse_assignment_expression()!
	operator := tokenize.Token{
		...op
		text: arithmetic
	}
	value := ast.Expr(ast.Binary{
		op:    arithmetic
		left:  left
		right: right
		typ:   p.binary_type(operator, left, right)
		line:  left.line
		col:   left.col
	})
	p.check_assignment(target_type, value, op)
	return ast.Expr(ast.Assign{
		op:     op.text
		target: left
		value:  value
		typ:    target_type
		line:   op.line
		col:    op.col
	})
}

// is_a_place says whether an expression is one an assignment can write: a name,
// an element, a member or a dereference. They are the shapes the back end has a
// store for, and the same list the statement reader addresses.
fn is_a_place(expr ast.Expr) bool {
	return match expr {
		ast.Ident, ast.Index, ast.Field { true }
		ast.Unary { expr.op == '*' }
		else { false }
	}
}

// is_a_compound_target says whether an expression is a place a compound
// assignment can read twice. A compound spelling means `x = x op value`, and the
// operand written twice has to be a place the statement reader can also address:
// a name, or an element whose base is a name. A member and a dereference would
// be read twice, which is a different program whenever the pointer or the object
// has a side effect, so those are refused by name rather than read as something
// the source did not write.
fn is_a_compound_target(expr ast.Expr) bool {
	if expr is ast.Ident {
		return true
	}
	if expr is ast.Index {
		return (expr as ast.Index).base is ast.Ident
	}
	return false
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
	p.compound_unstable++
	then_expr := p.parse_expression() or {
		p.compound_unstable--
		p.depth--
		return error('a conditional expression')
	}
	p.compound_unstable--
	if !p.expect_punct(':') {
		p.depth--
		return error('a conditional expression without its colon')
	}
	p.compound_unstable++
	else_expr := p.parse_expression() or {
		p.compound_unstable--
		p.depth--
		return error('a conditional expression')
	}
	p.compound_unstable--
	p.depth--
	return ast.Expr(ast.Conditional{
		cond:      p.constant_condition(question, condition)
		then_expr: then_expr
		else_expr: else_expr
		typ:       p.conditional_type(question, then_expr, else_expr)
		line:      question.line
		col:       question.col
	})
}

// constant_condition folds the condition of a conditional expression to an
// integer literal when it is an integer constant expression this reader can
// evaluate, and leaves it alone otherwise.
//
// 6.5.15 evaluates only the arm the condition selects, so a condition with a
// value is the same answer on every run and the arm it does not select is never
// evaluated. Folding the condition here is what tells the emitter that: it can
// read a literal and cannot evaluate an arbitrary constant expression, so the
// value in the tree is how only one arm comes to be written. The arm that is not
// selected stays in the tree, is still read and still checked, which 6.6 and
// 6.5.15 ask of it; only the emitter stops writing it. The shape this fixes is
// glibc's `isinf`, whose type dispatch selects a call for a type the machine
// does not carry and never runs it.
fn (p Parser) constant_condition(at tokenize.Token, condition ast.Expr) ast.Expr {
	value := p.constant_value(condition) or { return condition }
	return ast.Expr(ast.IntLit{
		value: value
		text:  '${value}'
		typ:   types.int_type()
		line:  at.line
		col:   at.col
	})
}

// conditional_type is the type a conditional expression has, which 6.5.15
// decides from its two arms and never from its condition. Two arithmetic arms
// give the type the usual arithmetic conversions put them both in, two void
// arms give void, and two pointers give the pointer both arms convert to: a
// pointer to void takes over from a pointer to an object type, and a pointer
// beside a null pointer constant is that pointer's type.
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
	// 6.5.15p3: two arms of the same structure or union type give that type,
	// and the result is a value of it. The arm that is not chosen is copied
	// into wherever the conditional is used rather than addressed there, so
	// `(c ? x : y).a` reads the member of the copy and writing through the
	// copy leaves `x` and `y` alone. The two arms have to be that one type:
	// two different aggregates are still a constraint violation, and the
	// message names both.
	if a.kind in [.struct_, .union_] && b.kind in [.struct_, .union_] {
		if types.unqualified(a).same(types.unqualified(b)) {
			return types.unqualified(a)
		}
		p.error_at(op, 'a constraint violation: the two arms of a conditional are ${a.describe()} and ${b.describe()}, and 6.5.15 pairs two arms of the same structure or union type')
		return types.Type{}
	}
	if a.is_void() && b.is_void() {
		return types.void_type()
	}
	// 6.5.15p6: a pointer beside a null pointer constant is that pointer, the
	// same pairing an initializer and an assignment allow. It is asked before
	// the two-pointer cases below, because a null pointer constant is not a
	// pointer with a type of its own even when 6.3.2.3p3 spells it as one.
	// `1 ? (void *)0 : p` is `p`'s type, and so is `1 ? (void *)0 : (T *)0`,
	// which is the shape `__tgmath_real_type` is built on: without this the
	// constant's void pointer takes over and the conditional is a void pointer,
	// dereferencing to void.
	if a.is_pointer() && p.is_null_pointer_constant(else_expr) {
		return a
	}
	if b.is_pointer() && p.is_null_pointer_constant(then_expr) {
		return b
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
		short_circuit := t.text in ['&&', '||']
		if short_circuit {
			p.compound_unstable++
		}
		right := p.parse_binary(precedence + 1) or {
			if short_circuit {
				p.compound_unstable--
			}
			return error('binary operand')
		}
		if short_circuit {
			p.compound_unstable--
		}
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
// Pointer arithmetic is a case this model answers in part: the type of `p + 1`
// is the pointer's own, and 6.5.6p9 makes the difference of two pointers a
// `ptrdiff_t`, which is a signed integer type rather than a pointer. The type
// this target gives it is written out by `pointer_difference_type` below. A
// sum of two pointers has no answer and stays unresolved.
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
	if a.is_vector() || b.is_vector() {
		// A GNU vector operator is defined on its elements, so `a + b` adds
		// lane by lane and the two operands have to be the same vector type.
		// The arithmetic is element-wise and not the usual arithmetic
		// conversions: a vector and a scalar do not mix, and two different
		// vector types do not either.
		//
		// Only `+` is typed here, which is the operator the corpus checks and
		// the one this compiler lowers. The other element-wise operators are
		// refused by name rather than typed and then computed with a scalar
		// meaning, which would answer one lane or the wrong width.
		if !(a.is_vector() && b.is_vector()) || !a.same(b) {
			p.error_at(op, 'unsupported: the type of ${describe_operand(left)} ${op.text} ${describe_operand(right)} is not one this compiler resolves, and a vector operator takes two operands of one vector type')
			return types.Type{}
		}
		if op.text != '+' {
			p.error_at(op, 'unsupported: the element-wise operator ${op.text} on ${a.describe()} is not implemented, and this compiler implements + on two vectors of one type')
			return types.Type{}
		}
		return a
	}
	if op.text == '+' || op.text == '-' {
		if a.is_pointer() && b.is_integer() {
			return a
		}
		if op.text == '+' && b.is_pointer() && a.is_integer() {
			return b
		}
		if op.text == '-' && a.is_pointer() && b.is_pointer() {
			return p.pointer_difference_type(op, left, right, a, b)
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

// pointer_difference_type is the type `p - q` has when both operands are
// pointers: 6.5.6p9 makes the difference of two pointers a `ptrdiff_t`, the
// signed integer type of a count of elements.
//
// The standard lets an implementation choose any signed integer type wide enough
// to hold the difference, and this target's choice is written out here.
// Measured with `_Generic` on gcc 16.2.1, `(q - p)` for two `int *` selects
// `long` and selects neither `long long` nor `int`, and `sizeof(q - p)` is 8, so
// the type is `long`. It is not derived from the width of a pointer: `long` and
// `long long` occupy the same eight bytes and are still two types, and a
// `_Generic` over the difference can tell which one it is.
//
// The two operands have to point at compatible object types, and 6.5.6p8 reads
// a qualified and an unqualified version of one type as compatible, so the
// qualifiers are dropped before they are compared. Two `void *` are compatible
// the same way and the GNU dialects accept their difference, so that pair is not
// refused here; the back end scales it by a byte. Any other pair shares no
// element type, and its difference is refused rather than counted in an element
// neither pointer names.
fn (mut p Parser) pointer_difference_type(op tokenize.Token, left ast.Expr, right ast.Expr, a types.Type, b types.Type) types.Type {
	left_element := a.pointee() or {
		p.error_at(op, 'unsupported: the type of ${describe_operand(left)} ${op.text} ${describe_operand(right)} is not one this compiler resolves')
		return types.Type{}
	}
	right_element := b.pointee() or {
		p.error_at(op, 'unsupported: the type of ${describe_operand(left)} ${op.text} ${describe_operand(right)} is not one this compiler resolves')
		return types.Type{}
	}
	if !types.unqualified(left_element).compatible(types.unqualified(right_element)) {
		p.error_at(op, 'unsupported: ${describe_operand(left)} and ${describe_operand(right)} are ${a.describe()} and ${b.describe()}, which point at incompatible types, so their difference is not a count of an element')
		return types.Type{}
	}
	return types.long_type()
}

// parse_member_path reads `.name` and the dots that follow it as one object read
// further in. The object's name is looked up once, and each dot after the first is
// read from the type the one before it answered, so the offsets add up as the path
// goes in and `b.a.x` comes back as one Field naming `b` at the byte `x` sits at.
// It is what both a value read and an assignment to a member go through, because
// the two ask the same question of the same path.
fn (mut p Parser) parse_member_path(base string, base_at tokenize.Token, through_pointer bool, index ?ast.Expr) !&ast.Field {
	mut aggregate := p.scopes.lookup(base) or {
		p.error_at(base_at, 'unsupported: ${base} is read as an object with a member, and no declaration of that name is in scope')
		return error('unknown object')
	}.typ
	if index != none {
		// `s[i].a` reads the member of the element the index names, so the type
		// the member is looked up in is the element's type, not the array's. The
		// stride between elements is the size of that type, which the field's
		// declaration carried and the back end scales an index by.
		//
		// `e[i].a` where `e` is a pointer is the same member of an element, but
		// the element is `*(e + i)`: an object addressed from the pointer's
		// value rather than a place in the frame. Reading that subscript
		// resolves it this way, through the general reader, which holds the
		// element in the Field's base and looks the member up in what the
		// pointer points at, so the assignment target asks the same reader
		// instead of being read as an element of the pointer's declaration.
		if aggregate.is_pointer() {
			element_base := ast.Expr(ast.Ident{
				name: base
				typ:  aggregate
				line: base_at.line
				col:  base_at.col
			})
			element := p.element(element_base, index, base_at)!
			return p.parse_general_member_path(element, through_pointer, base_at)
		}
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
	mut member := p.parse_member(base, ?ast.Expr(none), aggregate, 0, '', through_pointer, index)!
	for p.at_punct('.') {
		// Every dot after the first reads further into the same object, and
		// that object is still the one the first access named: a path that
		// began with `->` keeps reading from the pointer's value the whole
		// way in, so the flag the first access set travels with each step.
		member = p.parse_member(base, ?ast.Expr(none), member.typ, member.offset, member.member,
			through_pointer, index)!
	}
	return member
}

// parse_general_member_path reads a member access whose object is an expression
// rather than a name: `f()->m`, `(p)->m`, `a->b->c`, `arr[i].m`. The object's own
// type decides which member can be read and where the layout put it, exactly as
// it does for a name, and the object is kept in the Field's base so the back end
// can compute its address. The dots that follow the first access add up into the
// same Field the way they do for a name, because a member of a member is inside
// the same object.
fn (mut p Parser) parse_general_member_path(object ast.Expr, through_pointer bool, at tokenize.Token) !&ast.Field {
	object_desc := describe_operand(object)
	mut aggregate := object.typ
	if through_pointer {
		// The object is a pointer and the member belongs to what it points at.
		// A value that is not a pointer has no object to be read through, and
		// saying so here keeps the value from being read as an address that
		// means something else.
		aggregate = aggregate.pointee() or {
			p.error_at(at, 'unsupported: ${object_desc} is read through ->, and it is declared ${aggregate.describe()} rather than a pointer')
			return error('not a pointer')
		}
	}
	mut member := p.parse_member(object_desc, object, aggregate, 0, '', through_pointer, ?ast.Expr(none))!
	for p.at_punct('.') {
		// The dots after the first read further into the same object, which is
		// still the one the first access named, so a path that began with `->`
		// keeps reading from the pointer's value the whole way in.
		member = p.parse_member(object_desc, object, member.typ, member.offset, member.member,
			through_pointer, ?ast.Expr(none))!
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
fn (mut p Parser) parse_member(base string, object ?ast.Expr, aggregate types.Type, into int, path string, through_pointer bool, index ?ast.Expr) !&ast.Field {
	dot := p.next() // .
	if p.peek().kind != .identifier {
		p.error_at(p.peek(), 'unsupported: expected a member name after ., found ${describe(p.peek())}')
		return error('member name')
	}
	name := p.next()
	written := if path == '' { name.text } else { '${path}.${name.text}' }
	// The members belong to the tag, so an aggregate read before its body was
	// completed is asked for the tag's current type before its members are
	// searched. The pointee in `struct S *p;` read before `struct S { int a; };`
	// holds the tag and no members, and the members are read from the tag.
	tagged := p.tagged_type(aggregate)
	if tagged.kind !in [types.Kind.struct_, .union_] {
		p.error_at(dot, 'unsupported: ${base}${if path == '' { '' } else { '.' + path }} is declared ${tagged.describe()}, and a member is read from an object whose type has members')
		return error('not an aggregate')
	}
	mut at := -1
	for i, member in tagged.members {
		if member.name == name.text {
			at = i
			break
		}
	}
	if at < 0 {
		p.error_at(name, 'unsupported: ${tagged.describe()} has no member called ${name.text}')
		return error('unknown member')
	}
	layout := p.representation.layout(tagged) or {
		p.error_at(name, 'unsupported: the members of ${tagged.describe()} are not a layout this compiler knows, so the member ${name.text} cannot be read')
		return error('no layout')
	}
	member := tagged.members[at]
	return &ast.Field{
		name:            base
		base:            object
		index:           index
		member:          written
		offset:          into + layout.offsets[at]
		spelling:        member.typ.storage_spelling()
		typ:             member.typ
		bitfield:        member.bitfield
		bit_offset:      if member.bitfield { layout.bits[at] } else { 0 }
		bit_width:       member.bits
		unit_width:      if member.bitfield {
			p.representation.size_of(member.typ) or { 0 }
		} else {
			0
		}
		through_pointer: through_pointer
		line:            dot.line
		col:             dot.col
	}
}

// tagged_type is the aggregate a type names as the tag namespace holds it now,
// and the type itself when it names no tag or the tag is not in scope.
//
// A struct or a union is identified by its tag, and its members belong to the tag
// rather than to the reading of it a declaration took. A type read before the body
// that completed its tag carries no members of its own: the pointee of
// `struct S *p;` read before `struct S { int a; };` is one, and so is the `next`
// member of a self-referential struct, whose body names the tag while the body is
// being read. Asking the tag namespace for the tag answers the completed type,
// which is where those members are. A type that is already complete is answered as
// it is: its members are the tag's, and a lookup could only find the tag of some
// other scope wearing the same name.
fn (p Parser) tagged_type(aggregate types.Type) types.Type {
	if aggregate.kind !in [types.Kind.struct_, .union_] || aggregate.tag == ''
		|| aggregate.is_complete() {
		return aggregate
	}
	// A tag is declared under the keyword and the tag as they were written, which
	// is an unqualified aggregate's description; the qualifiers a type carries are
	// not part of the name, so `const struct S` asks the same tag as `struct S`.
	// The tag's members are the type's, but the qualifiers on the reading that
	// asked are kept, because `const S x;` written through a typedef of `struct S`
	// is a const object of the completed type.
	found := p.scopes.lookup_tag(types.unqualified(aggregate).describe()) or { return aggregate }
	return types.qualified(found, aggregate.quals)
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
	if declared.kind in [types.Kind.complex_float, .complex_double] {
		// A complex object is two components stored one after the other, and the
		// model measured the size: sixteen bytes for a `double _Complex` and
		// eight for a `float _Complex`. The declaration carries it so that the
		// frame reserves the whole object rather than one value of it.
		return p.representation.size_of(declared) or { 0 }
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
		ast.Index { '${describe_operand(expr.base)}[...]' }
		ast.Field { '${expr.name}.${expr.member}' }
		ast.IntLit { expr.text }
		ast.FloatLit { expr.text }
		ast.ComplexLit { expr.text }
		ast.StrLit { 'a string literal' }
		ast.Call {
			if _ := expr.callee {
				'a call through an expression'
			} else {
				'a call to ${expr.name}'
			}
		}
		ast.Unary { 'a value with ${expr.op} applied to it' }
		ast.Cast { 'a value converted to ${expr.spelling}' }
		ast.Binary { 'a value of ${expr.op}' }
		ast.IncDec { 'a value with ${expr.op} applied to ${describe_operand(expr.operand)}' }
		ast.Conditional { 'a conditional value' }
		ast.Assign { 'a value assigned to ${describe_operand(expr.target)} with ${expr.op}' }
		ast.Comma { 'a value of ,' }
		ast.StmtExpr { 'a statement expression' }
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
// no value at it, so the operand is refused by name rather than read at the width
// of something else. A pointer to void is the one pointer whose read is a void
// expression rather than a refusal: 6.3.2.2 says that expression has no value,
// and the places it may appear are the places a value is thrown away.
//
// An operand of function type is the designator 6.3.2.1p4 converts to a pointer
// to itself, so `*f` where f names a function is that designator again: the
// conversion and the indirection cancel and the result is the function type, not
// a value read out of memory. This is the shape V's generated C writes to fill a
// table of function pointers - `.g = *f` - where f is a function returning the
// table's element type.
fn (mut p Parser) deref_type(op tokenize.Token, operand ast.Expr) types.Type {
	if p.is_unresolved(operand) {
		return types.Type{}
	}
	if operand.typ.is_array() {
		return operand.typ.element() or { types.Type{} }
	}
	if operand.typ.is_function() {
		return operand.typ
	}
	if !operand.typ.is_pointer() {
		p.error_at(op, 'unsupported: * reads through an address, and this operand is ${operand.typ.describe()}')
		return types.Type{}
	}
	return operand.typ.pointee() or { types.Type{} }
}

// is_unresolved says whether an expression's clause is the one the model could
// not answer for, which no operator may take an address of or promote.
fn (p Parser) is_unresolved(expr ast.Expr) bool {
	if expr.typ.kind == .unknown {
		return true
	}
	return false
}

// unresolved_name is the first name an expression carries that the scope at this
// point does not have, or none. It is asked of a bound that did not fold: a name
// the file declares nowhere is a different failure from an expression that is not
// an integer constant expression, and a report that names the wrong one is a
// message about a construct the compiler never saw.
//
// Which names the scope has is what is asked here, not which names the file has:
// `int x[n]; int n = 4;` has no n at this point, and the caller that wants the
// file's answer waits until the end of the file to ask it.
fn (p Parser) unresolved_name(expr ast.Expr) ?ast.Ident {
	match expr {
		ast.Ident {
			if is_keyword(expr.name) {
				return none
			}
			if _ := p.scopes.lookup(expr.name) {
				return none
			}
			return expr
		}
		ast.Unary {
			return p.unresolved_name(expr.expr)
		}
		ast.Cast {
			return p.unresolved_name(expr.expr)
		}
		ast.Binary {
			// An operator chain is one node deep in the grammar however many
			// terms it has, so the left spine is walked with a loop and only
			// genuinely nested expressions recurse.
			mut spine := []ast.Binary{}
			mut node := ast.Expr(expr)
			for node is ast.Binary {
				step := node as ast.Binary
				spine << step
				node = step.left
			}
			if found := p.unresolved_name(node) {
				return found
			}
			for i := spine.len - 1; i >= 0; i-- {
				if found := p.unresolved_name(spine[i].right) {
					return found
				}
			}
			return none
		}
		ast.Conditional {
			if found := p.unresolved_name(expr.cond) {
				return found
			}
			if found := p.unresolved_name(expr.then_expr) {
				return found
			}
			return p.unresolved_name(expr.else_expr)
		}
		ast.Index {
			if found := p.unresolved_name(expr.base) {
				return found
			}
			return p.unresolved_name(expr.index)
		}
		else {
			return none
		}
	}
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
	// `__extension__` marks the expression after it as an extension and is worth
	// nothing itself. glibc writes it inside tgmath.h to keep a strict mode quiet
	// about the statement expressions the macros use. The name is in the reserved
	// namespace, so no dialect may refuse it: the tree reads it here the way it
	// already reads it in front of a declaration, and no features.v row gates it
	// because a reserved spelling carries nothing for the dialect check to report.
	if t.kind == .identifier && t.text == '__extension__' {
		p.next()
		return p.parse_prefix_operand(t)!
	}
	// `__real__` and `__imag__` name the two parts of a value. glibc's <tgmath.h>
	// writes them around the argument it is asking a type question about - it
	// asks `sizeof (+__real__ (Val))` and `__builtin_classify_type (__real__
	// (Val))` - and the names are in the reserved namespace the same way
	// `__extension__` is, so no dialect refuses them and no features.v row gates
	// them. Read as a call they name a function nothing declares, the operand's
	// type stays unresolved, and the `sizeof` or `__builtin_classify_type`
	// around them is refused, which is the whole of the tgmath unary macro.
	if t.kind == .identifier && (t.text == '__real__' || t.text == '__imag__') {
		p.next()
		operand := p.parse_prefix_operand(t)!
		return p.real_or_imaginary(t, operand)
	}
	// A conversion is written as a type name in parentheses, and it is read here
	// because that is where it binds: `(char *)p + 1` adds one to the address and
	// not to the char, and `*(int *)p` reads through the pointer rather than
	// multiplying. Which of the two a `(` opens - a type name or an expression -
	// is the token after it: a specifier word or a name this file declared as a
	// type is a conversion, and a name that is not is a value in parentheses.
	if t.kind == .punct && t.text == '(' && p.starts_type_name(p.peek_at(1)) {
		// A compound literal is a postfix expression and not a conversion,
		// but it is written the same way: a type name in parentheses. What
		// follows the closing parenthesis decides which of the two it is - a
		// brace list is the literal, anything else is the conversion - so the
		// two are read together and only one of them is built.
		return p.parse_cast_or_compound(t)
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

// real_or_imaginary reads the value `__real__ x` or `__imag__ x` is worth. The
// two names are gcc extensions rather than anything the C standard defines, and
// gcc 16.2.1 is the oracle for all of it, measured with programs that run:
//
//	double x = 3.0;  __real__ x     is 3.0      and its type is double
//	                 __imag__ x     is 0        and its type is double
//	                 __real__(x + 1.0)          is 4.0
//
// `__real__ x` is x's own object: `&__real__ x == &x`, and `__real__ x = 4.0`
// writes x. The type of `__imag__` is the operand's own and not a promoted one:
// char for a char operand, short for a short, long long for a long long.
// `__imag__ x` is a value and not an object, so it cannot be assigned to.
//
// So `__real__` of an operand of a real arithmetic type is the operand, and
// returning it as written gives the same object, the same address, the same
// type, and the operand evaluated once. `__imag__` is a zero of the operand's
// type, which is a written constant of that type.
//
// An operand of a complex type is a pair of components, and the part is the one
// the operator names: `__real__ z` is the first component of the pair and
// `__imag__ z` the second, at the component's own type. The node carries the
// operand and the operator so the back end can read the component out of the
// pair; the value is real and lives in one register, so the node's own type is
// the component's. A `long double _Complex` component is a width this compiler
// does not carry, so that operand is refused by name rather than read at the
// width of a double. An operand that is real but not arithmetic has no real
// part, which is a constraint violation.
//
// One measured difference is not modelled: gcc still evaluates the operand of
// `__imag__` - `__imag__ f()` calls f and answers 0 - and a written zero does
// not carry that call. Preserving it would need the operand emitted for its
// effect and the result register cleared afterwards, and the back end has no
// instruction that clears the floating-point result register.
fn (mut p Parser) real_or_imaginary(op tokenize.Token, operand ast.Expr) ast.Expr {
	// An operand the reader did not resolve was refused where it was written,
	// and a second message about the operator would only repeat the first.
	if p.is_unresolved(operand) {
		return p.zero_value(op, types.Type{})
	}
	value := p.value_type(operand)
	if value.is_complex() {
		return p.complex_part(op, operand, value)
	}
	if !value.is_arithmetic() {
		p.error_at(op, 'a constraint violation: ${op.text} takes a value of an arithmetic type, and this one is ${value.describe()}')
		return p.zero_value(op, types.Type{})
	}
	if op.text == '__real__' {
		return operand
	}
	return p.zero_value(op, value)
}

// complex_part is the value `__real__ z` or `__imag__ z` is worth when z has a
// complex type: one component of the pair, at the component's own type. The node
// carries the operand so the back end can read the component the operator names
// out of storage; its own type is the component's, since a part of a complex
// value is a real value.
//
// A `long double _Complex` component is the extended type, sixteen bytes, and the
// back end reads it at that width rather than at the width of a double; the
// component's own kind is what the node's type is, so the two cases are the same
// answer here.
fn (mut p Parser) complex_part(op tokenize.Token, operand ast.Expr, value types.Type) ast.Expr {
	kind := value.kind.complex_component() or {
		p.error_at(op, 'unsupported: ${op.text} takes a value of a complex type, and ${value.describe()} has no component this compiler can read')
		return p.zero_value(op, types.Type{})
	}
	component := types.scalar(kind) or { types.Type{} }
	return ast.Expr(ast.Unary{
		op:   op.text
		expr: operand
		typ:  component
		line: op.line
		col:  op.col
	})
}

// zero_value is the constant zero of a type, which is what `__imag__` of a real
// operand is worth: an int literal for an integer type and a double literal for
// a floating one, the same two nodes a written constant of that type already is.
fn (mut p Parser) zero_value(op tokenize.Token, value types.Type) ast.Expr {
	if value.is_floating() {
		return ast.Expr(ast.FloatLit{
			value: 0.0
			text:  '0.0'
			typ:   value
			line:  op.line
			col:   op.col
		})
	}
	return ast.Expr(ast.IntLit{
		value: 0
		text:  '0'
		typ:   value
		line:  op.line
		col:   op.col
	})
}

// and charges that level to the nesting count.
//
// A `[` index and a call's argument list are each an expression written inside
// another, and neither is read through parse_primary or parse_prefix_operand,
// so without this count they follow the chain until the stack runs out: measured
// on an 8 MB stack, `a[a[...]]` and `f(f(...))` nested twenty thousand deep each
// take signal 11. The count is left where it was found on every return, a failed
// one included, so a diagnostic about nesting does not push the next expression
// over the limit as well.
//
// Both positions take a full expression, so the assignment-expression reader is
// what reads one: `f(a = b = 1)` and `x[i = 0]` write where they stand.
fn (mut p Parser) parse_nested(at tokenize.Token) !ast.Expr {
	p.depth++
	defer {
		p.depth--
	}
	if p.depth > max_expression_depth {
		p.error_at(at, 'expression is nested more than ${max_expression_depth} levels deep')
		return error('expression nested too deeply')
	}
	return p.parse_assignment_expression()
}

// parse_postfix reads a primary expression and then the postfix operators that
// follow it, left to right: `x++`, `x--`, and the subscript `x[i]` of 6.5.2.1.
// A postfix operator binds to what comes before it, so it is read here, after
// parse_primary has built the operand, and before parse_binary is given a chance
// to read a binary operator at the same position.
//
// The subscript is here rather than in parse_primary because its left operand is
// an expression and not a name: `3[p]`, `(*row)[2]` and `arr[0][1]` are all the
// same shape, and a postfix loop is what lets one routine read every base.
//
// The loop takes every operator that follows, because `x++++` is two steps in
// the grammar; the second operand is an expression that is not a name and is
// refused by inc_dec, which is where the refusal belongs.
fn (mut p Parser) parse_postfix() !ast.Expr {
	return p.postfix_on(p.parse_primary()!)
}

// postfix_on reads the postfix operators that follow an operand already read,
// left to right: `x++`, `x--`, the subscript `x[i]` of 6.5.2.1, the call
// `x(...)`, and the member `x.a`. parse_postfix builds the operand with
// parse_primary first; a compound literal builds its own operand and comes here
// with it, because 6.5.2.5 makes the literal a postfix expression too.
fn (mut p Parser) postfix_on(base ast.Expr) !ast.Expr {
	mut expr := base
	for {
		t := p.peek()
		if t.kind == .punct && (t.text == '++' || t.text == '--') {
			op := p.next()
			expr = p.inc_dec(op, expr, true)!
			continue
		}
		if t.kind == .punct && t.text == '(' {
			// A call binds to whatever comes before it the way a subscript
			// does, so it is read here and after any base: a name, an element,
			// a dereferenced pointer, or a parenthesised expression. The base
			// is the callee, and what it has to be is checked where the call
			// is built.
			args := p.parse_arguments()!
			expr = p.call(expr, args)!
			continue
		}
		if t.kind == .punct && t.text == '[' {
			expr = p.parse_subscript(expr)!
			continue
		}
		// A member access binds to whatever comes before it the way a call and
		// a subscript do, so it is read here and after any base: a name, a
		// call's result, a chained arrow, a parenthesised pointer, or an
		// element of an array. An object named by a name keeps the
		// name-and-offset shape the reader has always built, and every other
		// object is held in the Field's base so the back end can compute its
		// address.
		if t.kind == .punct && (t.text == '.' || t.text == '->') {
			expr = p.parse_member_on(expr, t.text == '->', t)!
			continue
		}
		break
	}
	return expr
}

// parse_member_on reads one member access, `.name` or `->name`, on whatever the
// object is. An object named by a name is read by the name-and-offset reader,
// which also takes the whole chain of dots that follows; an element whose base
// is a name keeps the name-and-index shape `s[i].a` has always had; and every
// other object goes through the general reader, which holds the object in the
// Field's base.
fn (mut p Parser) parse_member_on(object ast.Expr, through_pointer bool, at tokenize.Token) !ast.Expr {
	if object is ast.Ident {
		named := object as ast.Ident
		named_at := tokenize.Token{
			kind: .identifier
			text: named.name
			line: named.line
			col:  named.col
		}
		member := p.parse_member_path(named.name, named_at, through_pointer, ?ast.Expr(none))!
		return ast.Expr(*member)
	}
	if object is ast.Index {
		// A member of an element: `s[i].a` reads the member from the element
		// the index names. The name-and-index shape belongs to an array, whose
		// place in the frame or the image the reader knows and whose stride the
		// declaration carries. An element of a pointer is an object addressed
		// from the pointer's value and scaled by the size of what it points at,
		// which is what the general reader computes; `p[i].a` goes there with
		// the element node as its base, exactly as `p[i]` alone does.
		element := object as ast.Index
		if element.base is ast.Ident {
			base := element.base as ast.Ident
			if base.typ.is_array() || base.typ.kind == .unknown {
				base_at := tokenize.Token{
					kind: .identifier
					text: base.name
					line: base.line
					col:  base.col
				}
				return ast.Expr(*p.parse_member_path(base.name, base_at, through_pointer, element.index)!)
			}
		}
	}
	member := p.parse_general_member_path(object, through_pointer, at)!
	return ast.Expr(*member)
}

// parse_member_chain reads the member accesses that follow an object, left to
// right, until the token no longer opens one. It is what continues a path the
// name-and-offset reader stopped in the middle of, because a step through a
// pointer member is an object of its own rather than a byte inside the name.
fn (mut p Parser) parse_member_chain(object ast.Expr) !ast.Expr {
	mut expr := object
	for {
		t := p.peek()
		if t.kind == .punct && (t.text == '.' || t.text == '->') {
			expr = p.parse_member_on(expr, t.text == '->', t)!
			continue
		}
		break
	}
	return expr
}

// parse_subscript reads `[E2]` after a primary expression and builds the element
// 6.5.2.1 defines as `*((E1) + (E2))`. The index is an expression of its own, so
// `a[i + 1]` and `a[b[0]]` are both the shape this reads.
fn (mut p Parser) parse_subscript(base ast.Expr) !ast.Expr {
	at := p.next() // [
	index := p.parse_nested(at)!
	if !p.at_punct(']') {
		p.error_at(p.peek(), 'unsupported: expected ] after the index of an element, found ${describe(p.peek())}')
		return error('expected ]')
	}
	p.next()
	return p.element(base, index, at)
}

// element builds the node for one subscript. Which of the two operands holds the
// address is a question about their types: an array or a pointer is the one the
// index is added to, and 6.5.2.1 makes the other one the index. Addition
// commutes, so `3[p]` is read as `p[3]` and the base of the node is always the
// operand that is the array or the pointer.
//
// A base that is a member and of an array type is addressable storage rather than
// a value - the member's own read would hand the index the bytes of the first
// element - so its address is taken here, which is the `&` an array's name stands
// for everywhere else.
fn (mut p Parser) element(base ast.Expr, index ast.Expr, at tokenize.Token) !ast.Expr {
	mut address := base
	mut count := index
	mut element := types.Type{}
	if base.typ.is_array() || base.typ.is_pointer() {
		element = p.element_type(base.typ, base, at) or { return error('no element type') }
	} else if index.typ.is_array() || index.typ.is_pointer() {
		address = index
		count = base
		element = p.element_type(index.typ, index, at) or { return error('no element type') }
	} else {
		p.error_at(at, 'unsupported: neither ${describe_operand(base)} nor ${describe_operand(index)} is an array or a pointer, so this is not an element of one')
		return error('no array or pointer operand')
	}
	if address is ast.Field && address.typ.is_array() {
		address = ast.Expr(ast.Unary{
			op:   '&'
			expr: address
			typ:  address.typ
			line: address.line
			col:  address.col
		})
	}
	// A row of an array whose bound is a value is that many bytes wide, and how
	// many is a question for the running program: `int m[r][c]`'s stride is
	// `c * sizeof(int)`. It is left none where the element type has a size this
	// reader can fold, which is every ordinary array, and the emitter then
	// scales the index by that size as it always did.
	mut stride := ?ast.Expr(none)
	if element.has_vla() {
		stride = p.vla_size_expr(element, at)
	}
	return ast.Expr(ast.Index{
		base:       address
		index:      count
		typ:        element
		vla_stride: stride
		line:       at.line
		col:        at.col
	})
}

// element_type is the type of one element of an array or of one pointed-to value:
// `a[i]` has the element type of what a was declared as, and `p[i]` the type p
// points at. A name that is neither an array nor a pointer has no element to be
// one of, which is refused where the operator that asked for one was written.
fn (mut p Parser) element_type(t types.Type, operand ast.Expr, at tokenize.Token) ?types.Type {
	if t.is_array() {
		return t.element() or { types.Type{} }
	}
	if t.is_pointer() {
		return t.pointee() or { types.Type{} }
	}
	p.error_at(at, 'unsupported: ${describe_operand(operand)} is neither an array nor a pointer, so it has no element to subscript')
	return none
}

// inc_dec builds the node for `++` or `--` on an object, and refuses every other
// operand where the operator is written: the lvalue this compiler steps is an
// object - a name, an element, a member or what a pointer points at - so a
// literal, a call's result and an arithmetic value are named in a diagnostic
// rather than read as something else.
//
// The type has to be a scalar the back end moves as a value: an integer, whose
// step is one, a pointer, whose step is the size of what it points at, or a
// floating value, whose step is one of its own width. The reader accepts all
// three and leaves the pointer's stride to the emitter, which has the target's
// sizes; a pointer to a type with no size is refused there by name. A name whose
// type the reader never resolved is left for the walk that reports names nothing
// declares, so an undeclared name gets that message and not this one.
fn (mut p Parser) inc_dec(op tokenize.Token, operand ast.Expr, postfix bool) !ast.Expr {
	if !steps_an_object(operand) {
		p.error_at(op, 'unsupported: ${op.text} on ${describe_operand(operand)}, and this compiler steps an object - a name, an element, a member or what a pointer points at - only')
		return error('operand is not an object')
	}
	kind := operand.typ.kind
	if kind != .unknown && !steps_a_value(kind) {
		reason := if kind in [.int128, .unsigned_int128] {
			'and this back end has no ${operand.typ.describe()} value to step'
		} else {
			'and this compiler steps an object of an integer, a pointer or a floating type only'
		}
		p.error_at(op, 'unsupported: ${op.text} on ${describe_operand(operand)}, which is ${operand.typ.describe()}, ${reason}')
		return error('operand is not a value this compiler steps')
	}
	return ast.Expr(ast.IncDec{
		op:      op.text
		operand: operand
		postfix: postfix
		typ:     operand.typ
		line:    op.line
		col:     op.col
	})
}

// steps_an_object says whether an expression names an object the operator can
// step in place: a name, an element, a member, or what a pointer points at. A
// literal and a computed value are not objects, so they are refused by name
// rather than read as a place to store.
fn steps_an_object(operand ast.Expr) bool {
	return match operand {
		ast.Ident, ast.Index, ast.Field { true }
		ast.Unary { operand.op == '*' }
		else { false }
	}
}

// steps_a_value says whether the back end steps an object of this kind as a
// value of its own width. A pointer is stepped by the size of what it points
// at, a floating value by one of its own width, and every integer kind it stores
// is a candidate; the two 128-bit kinds are not, because the back end has no
// value that wide and refuses an object of one by name.
fn steps_a_value(kind types.Kind) bool {
	if kind == .pointer || kind == .float || kind == .double {
		return true
	}
	return kind.is_integer() && kind !in [.int128, .unsigned_int128]
}

// parse_cast reads a conversion: the type name in parentheses, and the operand it
// converts. The operand is a unary expression, which is what the grammar says and
// why `(char)-x` and `(char)*p` are conversions of a value rather than of a sum.
//
// A conversion to `void` is a void expression, not an error: 6.5.4 lets a cast
// name void, and 6.3.2.2 says the value of such an expression is discarded. The
// node carries the void type the way a value conversion carries its type, and a
// later stage decides from the type whether the expression is in a place that
// may throw a value away.
// parse_cast_or_compound reads the type name a `(` opens, the `)` that closes
// it, and then what decides which construct this is: a brace list makes it a
// compound literal, 6.5.2.5's unnamed object, which is a postfix expression and
// is handed to the postfix reader so a subscript, a call or a member may follow
// it; anything else makes it the conversion the type name was written for.
fn (mut p Parser) parse_cast_or_compound(at tokenize.Token) !ast.Expr {
	p.next() // (
	spec, d, _ := p.parse_type_name_parts(1)!
	if !p.expect_punct(')') {
		return error('unclosed cast')
	}
	if p.at_punct('{') {
		literal := p.parse_compound_literal(spec, d, at)!
		return p.postfix_on(literal)
	}
	operand := p.parse_prefix_operand(at)!
	destination := p.declared_type(spec.clause, d)
	return ast.Expr(ast.Cast{
		spelling: p.conversion_spelling(spec, d, destination)
		expr:     decayed_operand(operand)
		typ:      destination
		line:     at.line
		col:      at.col
	})
}

// conversion_spelling is the type a conversion names, as the diagnostic about a
// conversion quotes it. `spelling_of` writes the specifiers and appends the
// pointer stars, which is the whole of a declarator that is a run of pointers;
// a declarator that also wrote a function or an array step wrote a part the
// stars do not carry, so `(int (*)(int))` came out as `int *` and the message
// named a destination the program never wrote. The resolved type's own spelling
// keeps that part, and it is the same type the conversion is about.
fn (p Parser) conversion_spelling(spec DeclSpec, d Declarator, resolved types.Type) string {
	if d.steps.len > d.pointer_count() {
		return resolved.describe()
	}
	return p.spelling_of(spec, d.pointer_count())
}

// decayed_operand applies 6.3.2.1p4 to the operand of a conversion: a function
// designator written where a value is wanted is the pointer to that function.
// The operand of a cast is such a place, and the back end classifies the source
// of a conversion by its type, so an operand that is still the function type
// itself has no width for the conversion to widen and `(int (*)(int))inc` was
// refused as though the destination were an object pointer. `&f` is that
// conversion written out - the same value the emitter already writes for a bare
// function name - and it is what makes the conversion the pointer-to-pointer
// conversion 6.3.2.3p8 allows, to a different function type and back.
fn decayed_operand(operand ast.Expr) ast.Expr {
	if !operand.typ.is_function() {
		return operand
	}
	return ast.Expr(ast.Unary{
		op:   '&'
		expr: operand
		typ:  types.decay(operand.typ)
		line: operand.line
		col:  operand.col
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
		// nothing about a value. A brace list after the closing parenthesis
		// makes it a compound literal, and its size is the size of the object
		// it names: `sizeof (int[]){1, 2, 3}` is the size of an int[3], and the
		// list is read for the size an unsized array takes from it and not
		// evaluated.
		p.next() // (
		spec, d, _ := p.parse_type_name_parts(0)!
		if !p.expect_punct(')') {
			return error('unclosed sizeof')
		}
		if p.at_punct('{') {
			list := p.parse_brace_initializer(true) or {
				return error('sizeof compound literal')
			}
			spelling = p.spelling_of(spec, d.pointer_count())
			size = p.compound_literal_size(spec, d, list) or {
				p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler has no size for it')
				return error('no size for the type')
			}
		} else {
			declared := p.declared_type(spec.clause, d)
			spelling = p.spelling_of(spec, d.pointer_count())
			if vla := p.vla_size_expr(declared, at) {
				return vla
			}
			size = p.representation.size_of(declared) or {
				p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler has no size for it')
				return error('no size for the type')
			}
		}
	} else {
		// The operand is a unary expression and not a full one: `sizeof x + 1`
		// is one plus the size of x, so it binds where a prefix operator does.
		// It is read through parse_prefix_operand, the same reader the prefix
		// operators use, so a chain of `sizeof` raises the nesting count once
		// per link: measured on an 8 MB stack, `sizeof sizeof ... x` nested
		// twenty thousand deep took signal 11 before this.
		//
		// Nothing the operand writes is run unless its size is not a constant, so
		// where the statements it wrote are dropped is below. The list is one per
		// statement being read, and a sizeof outside any statement has none.
		pending := if p.compound_pending.len > 0 {
			p.compound_pending[p.compound_pending.len - 1].len
		} else {
			0
		}
		operand := p.parse_prefix_operand(at)!
		spelling = describe_operand(operand)
		if p.is_unresolved(operand) {
			// The operand was refused where it was written, and its type is
			// the one the reader never resolved. Naming the operand is what
			// says which size could not be answered.
			p.error_at(at, 'unsupported: sizeof asks how many bytes ${spelling} takes, and this compiler did not resolve its type')
			return error('no type for the operand')
		}
		// A variable-length array's size is not a constant, so it is not a
		// constant expression and the answer is the product of its bounds,
		// evaluated where the sizeof is asked.
		if vla := p.vla_size_expr(operand.typ, at) {
			return vla
		}
		// The size is a constant, so 6.5.3.4p2 has the operand not evaluated and
		// nothing it wrote may run: measured against gcc 16.2.1,
		// `sizeof((S){count(), count()})` calls count no times, where this
		// compiler called it twice. Dropping what the operand appended is the
		// whole of it, and the declaration a compound literal writes goes with
		// them, so the object is not created either.
		if p.compound_pending.len > 0 {
			p.compound_pending[p.compound_pending.len - 1] = p.compound_pending[p.compound_pending.len - 1][..pending]
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

// GenericAssociation is one arm of a generic selection: the type name it matches,
// or the `default` keyword when it is the fallback, and the expression the arm is
// worth. The spelling is kept for a diagnostic that has to name the type the way
// the source wrote it.
struct GenericAssociation {
	is_default bool
	typ        types.Type
	spelling   string
	expr       ast.Expr
	at         tokenize.Token
}

// parse_generic_selection reads a C11 generic selection: `_Generic` over a
// controlling expression and a list of `type-name : expression` associations,
// at most one of which may be `default`. The controlling expression's type,
// after the lvalue conversion 6.5.17 asks for, is matched against the
// associations, and the result is the selected association's expression, whose
// type is therefore the type of the selection.
//
// Two things the standard says and this reader keeps: the controlling expression
// is not evaluated, so it is parsed for its type but no code is emitted for it
// and its names are checked by the walk at the end of the unit instead; and the
// association types have to be distinct, which is asked with the model's
// compatibility relation, while a selection that matches nothing and has no
// default is a constraint violation.
fn (mut p Parser) parse_generic_selection(at tokenize.Token) !ast.Expr {
	p.next() // (
	p.depth++
	defer {
		p.depth--
	}
	if p.depth > max_expression_depth {
		p.error_at(at, 'expression is nested more than ${max_expression_depth} levels deep')
		return error('expression nested too deeply')
	}
	controlling := p.parse_assignment_expression()!
	// The type the associations are matched against is the controlling
	// expression's after the lvalue conversion: an array decays to a pointer to
	// its first element, a function to a pointer to itself, and the qualifiers
	// come off. Measured on gcc 16.2.1, `const int x; _Generic(x, int: 11,
	// default: 99)` is 11, so a qualified operand matches the unqualified type.
	selector := types.unqualified(types.decay(controlling.typ))
	p.generic_controls << controlling
	if !p.expect_punct(',') {
		return error('expected , after the controlling expression of a generic selection')
	}
	mut arms := []GenericAssociation{}
	for !p.at_punct(')') && !p.at_eof() {
		arms << p.parse_generic_association()!
		if p.at_punct(',') {
			p.next()
			continue
		}
		break
	}
	if !p.expect_punct(')') {
		return error('unclosed generic selection')
	}
	mut seen := []types.Type{}
	mut default_arm := ?GenericAssociation(none)
	for arm in arms {
		if arm.is_default {
			if default_arm != none {
				p.error_at(arm.at, 'a constraint violation: a generic selection has one default association, and this is the second')
			} else {
				default_arm = arm
			}
			continue
		}
		for earlier in seen {
			if earlier.compatible(arm.typ) {
				p.error_at(arm.at, 'a constraint violation: a generic selection names ${earlier.describe()} twice, and the two associations are compatible')
			}
		}
		seen << arm.typ
	}
	if selector.kind == .unknown {
		p.error_at(at, 'unsupported: a generic selection asks for the type of ${describe_operand(controlling)}, and this compiler did not resolve it')
		return error('no type for the controlling expression')
	}
	for arm in arms {
		if !arm.is_default && selector.compatible(arm.typ) {
			return arm.expr
		}
	}
	if arm := default_arm {
		return arm.expr
	}
	p.error_at(at, 'a constraint violation: a generic selection over ${selector.describe()} has no association compatible with it and no default')
	return error('no matching association')
}

// parse_generic_association reads one arm: `default : expression`, or a type name
// and an expression. The type name is read by the same reader a cast uses, so
// `struct S` and a typedef name are types here the way they are anywhere else.
fn (mut p Parser) parse_generic_association() !GenericAssociation {
	at := p.peek()
	if at.kind == .identifier && at.text == 'default' {
		p.next()
		if !p.expect_punct(':') {
			return error('expected : after default')
		}
		expr := p.parse_assignment_expression()!
		return GenericAssociation{
			is_default: true
			expr:       expr
			at:         at
		}
	}
	if at.kind != .identifier || !p.starts_declaration(at) {
		p.error_at(at, 'unsupported: expected a type name or default in a generic selection, found ${describe(at)}')
		return error('expected a type name')
	}
	name := p.parse_type_name(0)!
	if name.typ.kind == .unknown {
		p.error_at(name.at, 'unsupported: a generic selection names the type ${name.spelling}, and this compiler did not resolve it')
		return error('no type for an association')
	}
	if !p.expect_punct(':') {
		return error('expected : after an association type')
	}
	expr := p.parse_assignment_expression()!
	return GenericAssociation{
		typ:      types.unqualified(name.typ)
		spelling: name.spelling
		expr:     expr
		at:       at
	}
}

fn (mut p Parser) parse_primary() !ast.Expr {
	t := p.peek()
	if t.kind == .number {
		p.next()
		// The spelling decides whether this is an imaginary constant, a
		// floating constant or an integer one, so the readers are reached
		// from here rather than one of them guessing at another's input.
		// The imaginary one is asked first because its spelling also has a
		// point, which would otherwise send it to the floating reader and
		// refuse the `i` as a character no floating constant holds.
		if is_imaginary_constant(t.text) {
			value, single := parse_imaginary_literal(t.text) or {
				p.error_at(t, err.msg())
				return error('bad imaginary literal')
			}
			return ast.Expr(ast.ComplexLit{
				value: value
				text:  t.text
				typ:   if single { types.complex_float_type() } else { types.complex_double_type() }
				line:  t.line
				col:   t.col
			})
		}
		if is_floating_constant(t.text) {
			if is_long_double_constant(t.text) {
				value := parse_long_double_literal(t.text) or {
					p.error_at(t, err.msg())
					return error('bad long double literal')
				}
				return ast.Expr(ast.FloatLit{
					long_value: value
					text:       t.text
					typ:        p.floating_type(t, 0.0)
					line:       t.line
					col:        t.col
				})
			}
			if is_float128_constant(t.text) {
				value := parse_float128_literal(t.text) or {
					p.error_at(t, err.msg())
					return error('bad _Float128 literal')
				}
				return ast.Expr(ast.FloatLit{
					long_value: value
					text:       t.text
					typ:        p.floating_type(t, 0.0)
					line:       t.line
					col:        t.col
				})
			}
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
		// A generic selection is a primary expression written with the word
		// `_Generic` and the parenthesis that follows it, so it is read here
		// rather than resolved as a name, which is what it would otherwise be.
		if t.text == '_Generic' && p.at_punct('(') {
			return p.parse_generic_selection(t)!
		}
		// An enumeration constant stands for a number and not for an object: a
		// use of it is the value the enum gave it, which is what makes it an
		// integer constant expression an array bound or a case label can be
		// built from. It is asked before the name is resolved, because there is
		// no storage behind the name to read.
		if constant := p.scopes.lookup_constant(t.text) {
			return integer_constant(constant.value, t.text, t, constant.kind)
		}
		// The function-name spellings name the function the expression is
		// written in: `__func__` is C99's (6.4.2.2), and `__FUNCTION__` and
		// `__PRETTY_FUNCTION__` are gcc's spellings of the same name. What
		// they are worth is a string holding it, so they are read as the
		// string literal they describe rather than as a name nothing
		// declares. glibc's assert passes `__PRETTY_FUNCTION__` to
		// __assert_fail, which is why the tree reads one.
		if t.text in ['__func__', '__FUNCTION__', '__PRETTY_FUNCTION__'] {
			return p.function_name_expression(t)!
		}
		// The reserved `__builtin_` spellings are reads of their own and not
		// calls: their arguments are types as often as expressions, and the
		// value is settled while the tokens are read. The list is in
		// builtins.v, where each one's reader is.
		if t.text in builtin_expression_names && p.at_punct('(') {
			return p.parse_builtin_expression(t)!
		}

		if p.at_punct('.') || p.at_punct('->') {
			member := p.parse_member_path(t.text, t, p.at_punct('->'), ?ast.Expr(none))!
			return ast.Expr(*member)
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
		literal := parse_string_literal(t.text) or {
			p.error_at(t, err.msg())
			return error('bad string literal')
		}
		return ast.Expr(ast.StrLit{
			value: literal.value
			text:  t.text
			unit:  literal.unit
			typ:   string_literal_type(t.text, literal)
			line:  t.line
			col:   t.col
		})
	}
	if t.kind == .punct && t.text == '(' {
		// The token after the parenthesis decides what kind of thing this is:
		// a specifier word or a declared type names a conversion, a `{` opens
		// a GNU statement expression, and anything else is a value in
		// parentheses. A statement expression is not read by the cast reader
		// even though `{` cannot start a type name, because reading the block
		// is a different job from reading one expression.
		if p.peek_at(1).kind == .punct && p.peek_at(1).text == '{' {
			return p.parse_statement_expression(t)!
		}
		p.next()
		p.depth++
		if p.depth > max_expression_depth {
			p.error_at(t, 'expression is nested more than ${max_expression_depth} levels deep')
			p.depth--
			return error('expression nested too deeply')
		}
		inner := p.parse_parenthesized_expression() or {
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

// parse_statement_expression reads `({ ... })`, a GNU statement expression: a
// brace-enclosed compound statement in parentheses whose value is the value of
// its last statement when that statement is an expression statement. glibc's
// `assert` expands to one under the GNU dialects this compiler reads, so the
// form is here for the reason the tree reads `__extension__`: the C it has to
// compile writes it.
//
// The block is read by the reader a function body uses, so a declaration, a
// loop, an if and every other statement inside the braces are read as the
// statements they are. The last expression statement becomes the node's value
// and the statements before it become its body; a last statement that is not an
// expression statement - a declaration, a block, a loop - leaves the construct
// with no value and the void type, which is what gcc answers and what this
// compiler refuses where a value is required.
//
// The parenthesis is consumed here rather than by the caller, so the nesting
// count covers the whole construct: a chain of statement expressions inside one
// another is a chain of nested expressions and is bounded like one.
fn (mut p Parser) parse_statement_expression(open tokenize.Token) !ast.Expr {
	p.next() // (
	p.depth++
	if p.depth > max_expression_depth {
		p.error_at(open, 'expression is nested more than ${max_expression_depth} levels deep')
		p.depth--
		return error('statement expression nested too deeply')
	}
	stmts := p.parse_block() or {
		p.depth--
		return error('statement expression body')
	}
	p.depth--
	if !p.expect_punct(')') {
		return error('unclosed statement expression')
	}
	// The last statement is the value when it is an expression: C makes an
	// assignment an expression too, and this tree keeps a bare assignment as a
	// statement of its own, so `trailing_value` is what tells the two apart.
	// Every other kind leaves the construct worth nothing. The two halves are
	// split here so the back end emits each one once: the value is the last
	// expression and the body is everything before it.
	mut value := ?ast.Expr(none)
	if stmts.len > 0 {
		value = p.trailing_value(stmts[stmts.len - 1])
	}
	body := if value != none { stmts[..stmts.len - 1].clone() } else { stmts.clone() }
	typ := if present := value { p.value_type(present) } else { types.void_type() }
	return ast.Expr(ast.StmtExpr{
		body:  body
		value: value
		typ:   typ
		line:  open.line
		col:   open.col
	})
}

// trailing_value is the expression a statement is worth, for the statement kinds
// that are expressions. An expression statement is one by construction. An
// assignment is an expression in C (6.5.16) even though this tree keeps a bare
// assignment as a statement of its own, so the assignment is put back together
// as the expression it is: `({ a = 5; })` is worth 5, and `({ a += 1; })` is worth
// the sum, because the compound spelling was already read as `a = a + 1`. Every
// other statement kind is worth nothing, which is what a declaration, a loop, an
// if and a block are.
fn (p Parser) trailing_value(stmt ast.Stmt) ?ast.Expr {
	match stmt.kind {
		.expr_stmt {
			return stmt.expr
		}
		.assign {
			value := stmt.expr or { return none }
			target := p.assignment_target(stmt) or { return none }
			return ast.Expr(ast.Assign{
				target: target
				value:  value
				op:     '='
				typ:    p.value_type(target)
				line:   stmt.line
				col:    stmt.col
			})
		}
		else {
			return none
		}
	}
}

// assignment_target puts back the object an assignment statement writes to, as
// the expression C says the assignment's left side is. The statement carries the
// pieces apart - an element node, a dereference, a member, a name with a
// subscript - and each piece is the expression it stands for, so the whole
// target is put back the way the expression reader read it when the same
// assignment is written where a value is wanted.
fn (p Parser) assignment_target(stmt ast.Stmt) ?ast.Expr {
	if subscript := stmt.subscript() {
		return subscript
	}
	if deref := stmt.deref() {
		return deref
	}
	if member := stmt.field {
		return ast.Expr(*member)
	}
	if index := stmt.index {
		base := p.resolve(stmt.target)
		return ast.Expr(ast.Index{
			base:  ast.Expr(ast.Ident{
				name: stmt.target
				typ:  base
				line: stmt.line
				col:  stmt.col
			})
			index: index
			typ:   p.assignment_target_type(stmt.target, stmt.index, none)
			line:  stmt.line
			col:   stmt.col
		})
	}
	if stmt.target.len == 0 {
		return none
	}
	return ast.Expr(ast.Ident{
		name: stmt.target
		typ:  p.resolve(stmt.target)
		line: stmt.line
		col:  stmt.col
	})
}

// function_name_expression reads one of the function-name spellings,
// `__func__`, `__FUNCTION__` or `__PRETTY_FUNCTION__`, as the string it names:
// the name of the function whose body is being read. 6.4.2.2 makes `__func__` a
// static array of char holding that name and its terminator, and the two GNU
// spellings are the same name. A use outside a function body has no function to
// name, so it is refused by name rather than given an empty string.
fn (mut p Parser) function_name_expression(at tokenize.Token) !ast.Expr {
	name := p.current_function
	if name.len == 0 {
		p.error_at(at, 'unsupported: ${at.text} is read outside a function body, and it names the function it is written in')
		return error('function name outside a function')
	}
	return ast.Expr(ast.StrLit{
		value: name
		text:  '"${name}"'
		typ:   types.array_of(types.char_type(), name.len + 1)
		line:  at.line
		col:   at.col
	})
}

fn (mut p Parser) parse_arguments() ![]ast.Expr {
	p.next() // (
	mut args := []ast.Expr{}
	if p.at_punct(')') {
		p.next()
		return args
	}
	for {
		args << p.parse_nested(p.peek())!
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
	// A constant written with a leading minus reaches here with the sign folded
	// into the value while the token holds the unsigned literal: the brace-list
	// reader reads `-3` as the value -3 and keeps the token `3`. 6.5.3.3 gives
	// `-3` the type of its promoted operand, so the type is the type of the
	// token's own value, not of the signed one. Asking the type of -3 directly
	// reads the minus as the top bit of a 64-bit pattern and refuses the
	// constant as too large, which is what happened to every struct brace list
	// with a negative member.
	operand := if value < 0 { parse_integer_literal(at.text) or { value } } else { value }
	return types.integer_constant_type(at.text, operand, p.representation) or {
		p.error_at(at, err.msg())
		return types.Type{}
	}
}

// floating_type is the type a floating constant has. 6.4.4.2 makes that a
// question about the suffix: a constant with no suffix is a double, one written
// with an `f` is a float, and one written with an `l` is a long double.
//
// The value arrives already rounded to the width the suffix named, so nothing
// here changes it; this only says which of the three floating types the
// constant is. The host double is not consulted for a long double constant
// because it cannot hold one; the suffix is the whole answer.
fn (mut p Parser) floating_type(at tokenize.Token, value f64) types.Type {
	if value != value {
		// A NaN is what a conversion that ran out of range produces, and the
		// constant it came from was a number the program wrote. Saying so at
		// the constant is better than emitting a NaN where a number was.
		p.error_at(at, '${at.text}: the constant is out of range for a double')
		return types.Type{}
	}
	if is_long_double_constant(at.text) && is_floating_constant(at.text) {
		return types.long_double_type()
	}
	if is_float128_constant(at.text) {
		return types.float128_type()
	}
	if at.text.len > 0 && (at.text[at.text.len - 1] == `f` || at.text[at.text.len - 1] == `F`) {
		return types.float_type()
	}
	return types.double_type()
}

// string_literal_type is the type of a string literal: an array of char holding
// the bytes and the terminator the literal does not write. An L-prefixed literal
// names an array of wchar_t instead, which this target gives as an int, holding
// one per character and the terminator. A literal with any other prefix names a
// type laid out in a header this compiler has not read, so its clause is left
// unresolved.
fn string_literal_type(text string, literal StringLiteral) types.Type {
	if literal.unit == 4 {
		return types.array_of(types.int_type(), literal.count + 1)
	}
	if text.len > 0 && text[0] != `"` {
		return types.Type{}
	}
	return types.array_of(types.char_type(), literal.value.len + 1)
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
	return p.checked_arguments(signature, args, name, name.text)
}

// checked_arguments checks one call's arguments against the function type its
// callee is worth and answers with what the function returns. It is the half of
// call_type that does not depend on the callee being a name, so a call through an
// expression is checked by the same rule: 6.5.2.2 makes an argument an assignment
// to its parameter, and one function decides that for both call shapes.
//
// A function type that named no parameters - `int f()` - says nothing about the
// call, so nothing is checked against nothing.
fn (mut p Parser) checked_arguments(signature types.Type, args []ast.Expr, at tokenize.Token, what string) types.Type {
	if !signature.prototyped {
		return signature.returns() or { types.Type{} }
	}
	parameters := signature.params
	if !signature.variadic && parameters.len != args.len {
		p.error_at(at, 'the call to ${what} passes ${args.len} argument(s), and the declaration of ${what} names ${parameters.len} argument(s)')
	}
	for index, argument in args {
		if index >= parameters.len {
			break
		}
		problem := types.assignment_problem(parameters[index].typ, p.value_type(argument), p.is_null_constant(argument)) or {
			continue
		}
		p.problem_span(argument.line, argument.col, problem)
	}
	return signature.returns() or { types.Type{} }
}

// call builds the node for a call whose callee was read as an expression. A name
// is the one case a call is written to a function rather than through a value: a
// name that holds a function pointer is an object, and calling one is an indirect
// call like any other, while a name that is a function is called directly by the
// name the back end resolves. Every other callee - an element, a dereference, a
// parenthesised expression - has to be worth a function or a pointer to one, and
// anything else is refused by name here, where the call is written.
fn (mut p Parser) call(callee ast.Expr, args []ast.Expr) !ast.Expr {
	if callee is ast.Ident {
		name := (callee as ast.Ident).name
		at := tokenize.Token{
			kind: .identifier
			text: name
			line: callee.line
			col:  callee.col
		}
		typ := p.call_type(at, args)
		if p.object_holds_a_function_pointer(name) {
			return ast.Expr(ast.Call{
				callee: callee
				args:   args
				typ:    typ
				line:   callee.line
				col:    callee.col
			})
		}
		return ast.Expr(ast.Call{
			name: name
			args: args
			typ:  typ
			line: callee.line
			col:  callee.col
		})
	}
	what := describe_operand(callee)
	signature := callable_signature(callee) or {
		p.error_span(callee.line, callee.col, 'a constraint violation: what a call calls has to be a function or a pointer to a function, and this is ${callee.typ.describe()}')
		return error('the callee is not callable')
	}
	at := tokenize.Token{
		kind: .identifier
		text: what
		line: callee.line
		col:  callee.col
	}
	return ast.Expr(ast.Call{
		callee: callee
		args:   args
		typ:    p.checked_arguments(signature, args, at, what)
		line:   callee.line
		col:    callee.col
	})
}

// object_holds_a_function_pointer says whether a name is an object whose type is a
// pointer to a function, which is a call through a value rather than a call to the
// function the name is. A typedef that names the pointer type resolves to the
// pointer here, so `binop fp` and `int (*fp)(int, int)` answer the same.
fn (p Parser) object_holds_a_function_pointer(name string) bool {
	declared := p.resolve(name)
	if !declared.is_pointer() {
		return false
	}
	inner := declared.pointee() or { return false }
	return inner.is_function()
}

// callable_signature is the function type an expression is worth calling: the
// function it is, or the function a pointer to it points at, and nothing for
// anything else. It is the question 6.5.2.2 asks of the callee, asked of an
// expression rather than of a name.
fn callable_signature(callee ast.Expr) ?types.Type {
	if callee.typ.is_function() {
		return callee.typ
	}
	if callee.typ.is_pointer() {
		inner := callee.typ.pointee() or { return none }
		if inner.is_function() {
			return inner
		}
	}
	return none
}

// is_null_constant says whether an expression is the integer constant expression
// with the value 0 that 6.3.2.3 calls a null pointer constant, which is the one
// integer a pointer may be initialized with. The clause asks for the value of the
// expression and not for the way it is spelled, so `0`, `-0`, `2 - 2` and `3 / 4`
// are the same answer to the question here. Measured, gcc 16.2.1 under `-std=c99`
// accepts `h(1 - 1)` for a parameter of type `int (*)(void)`, which this compiler
// refused while the question was asked of the literal alone.
fn (p Parser) is_null_constant(expr ast.Expr) bool {
	value := p.constant_value(expr) or { return false }
	return value == 0
}

// is_null_pointer_constant says whether an expression is a null pointer
// constant, which 6.3.2.3p3 defines as the integer constant expression with the
// value 0, or such an expression cast to void *. The second spelling is not a
// second kind of value, it is the first one wearing a pointer's clothes, and it
// is the spelling the tgmath macros use: `(void *) 0` and `(void *) (E)` for an
// E that is an integer constant expression both convert to any object pointer
// without a cast, and 6.5.15p6 gives a conditional whose arm is one of them the
// other arm's pointer type.
//
// A cast to an object pointer is not a null pointer constant, however constant
// the zero under it is. Measured, gcc 16.2.1 refuses `1 ? (double *)0 : (char
// *)0` with `pointer type mismatch`, and accepts `1 ? (void *)0 : (char *)0`
// with the type `char *`: the clause names void * and no other pointer.
//
// An assignment and a call argument ask the same question through
// `types.assignment_problem`, which already lets a void pointer convert to any
// object pointer, so the cast spelling needs no change there.
fn (p Parser) is_null_pointer_constant(expr ast.Expr) bool {
	if p.is_null_constant(expr) {
		return true
	}
	if expr is ast.Cast && expr.typ.is_pointer() {
		pointee := expr.typ.pointee() or { return false }
		return pointee.kind == .void_ && p.is_null_constant(expr.expr)
	}
	return false
}

// constant_value is the value of an integer constant expression this reader
// evaluates while it reads: a literal, a literal with a sign in front of it, a
// cast of one to an integer type, the arithmetic of two values, the shifts, the
// comparisons, the bitwise and logical operators, the prefix operators, and the
// conditional. The set is 6.6's rather than the shapes a header happens to
// write: 6.6p3 excludes assignment, increment, decrement, a function call and a
// comma from a constant expression and leaves everything else in, so `1 ? 2 : 3`
// and `4 > 1` and `1 << 2` are integer constant expressions and gcc 16.2.1
// accepts them at file scope under `-std=c99` where this folder answered none.
// The
// arithmetic is what the bounds a real header writes reach for: measured with
// `vcc -E`, glibc's `stdio.h` declares `char _unused2[12 * sizeof (int) - 5 *
// sizeof (void *)]` and `sys/select.h` declares `char data[1024 / (8 * (int)
// sizeof (__fd_mask))]`. `sizeof` is an operator the expression reader turns into
// its value, so the arithmetic arrives here as integer constants.
//
// An expression that is not one of those answers none, which says that this is not
// a constant expression the compiler can evaluate - not that it has no value. A
// name, a call and a cast to a floating or pointer type all answer none, so a
// pointer is still never initialized with something that only has a value at run
// time.
fn (p Parser) constant_value(expr ast.Expr) ?i64 {
	if expr is ast.IntLit {
		return expr.value
	}
	if expr is ast.Unary {
		operand := p.constant_value(expr.expr) or { return none }
		if expr.op == '-' {
			return -operand
		}
		if expr.op == '+' {
			return operand
		}
		if expr.op == '~' {
			return ~operand
		}
		if expr.op == '!' {
			return if operand == 0 { i64(1) } else { i64(0) }
		}
		return none
	}
	if expr is ast.Cast {
		// 6.6 makes a cast of an integer constant to an integer type an integer
		// constant expression, and 6.6p6 allows only that: a cast whose target is
		// not an integer type answers none, so `(double) 3` is not an operand an
		// array size may be built from.
		if !expr.typ.kind.is_integer() {
			return none
		}
		// The value is the one the conversion makes: `(char) 300` is 44 here as it
		// is at run time, because a value that narrows keeps what the target type
		// can hold.
		if operand := p.constant_value(expr.expr) {
			return p.converted_constant(expr.typ, operand)
		}
		// 6.6p6 names the other operand an integer constant expression may have
		// from a floating constant: one that is the immediate operand of a cast.
		// `(int) 3.5` is an integer constant expression whose value is three, and
		// gcc 16.2.1 under `-std=c99` accepts `int x[(int) 3.5];` as three
		// elements where this folder answered none and the bound was refused.
		if value := floating_operand(expr.expr) {
			return p.converted_float_constant(expr.typ, value)
		}
		return none
	}
	if expr is ast.Binary {
		// `&&` and `||` are operators 6.6p3 leaves in a constant expression, and
		// the operand the result does not need is not evaluated. Measured on gcc
		// 16.2.1 under `-std=c99`, `int x[1 || f()]` and `int x[0 && n]` are
		// accepted at file scope while `int x[2 && f()]` is `variably modified`,
		// so the right operand is read only when the left one leaves the answer
		// open. They keep their recursion for the same reason: which side is
		// evaluated depends on the other one, so the two operands are not folded
		// in a fixed order.
		if expr.op == '&&' {
			left := p.constant_value(expr.left) or { return none }
			if left == 0 {
				return i64(0)
			}
			right := p.constant_value(expr.right) or { return none }
			return if right != 0 { i64(1) } else { i64(0) }
		}
		if expr.op == '||' {
			left := p.constant_value(expr.left) or { return none }
			if left != 0 {
				return i64(1)
			}
			right := p.constant_value(expr.right) or { return none }
			return if right != 0 { i64(1) } else { i64(0) }
		}
		// An operator chain is one node deep in the grammar however many terms it
		// has, so the left spine is walked with a loop and only genuinely nested
		// expressions recurse: a chain of a few thousand terms is a size generated
		// code reaches, and a call per term would take the stack out on it.
		mut spine := []ast.Binary{}
		mut node := ast.Expr(expr)
		for node is ast.Binary {
			step := node as ast.Binary
			if step.op == '&&' || step.op == '||' {
				break
			}
			spine << step
			node = step.left
		}
		mut value := p.constant_value(node) or { return none }
		for i := spine.len - 1; i >= 0; i-- {
			step := spine[i]
			right := p.constant_value(step.right) or { return none }
			value = apply_constant_step(step.op, value, right) or { return none }
		}
		return value
	}
	if expr is ast.Conditional {
		// 6.6p3 leaves the conditional operator in a constant expression and
		// 6.5.15 evaluates one arm, so only the arm the condition selects has to
		// be constant. Measured on gcc 16.2.1 under `-std=c99`, `int x[1 ? 2 :
		// n]` and `int x[1 ? 2 : f()]` are accepted at file scope with n a
		// variable and f a function, while `int x[1 ? 2 : 3.5]` is refused as
		// `size of array has non-integer type`: the expression's own type has to
		// be an integer type, and the arm that does not run does not have to be
		// constant.
		if !expr.typ.kind.is_integer() {
			return none
		}
		condition := p.constant_value(expr.cond) or { return none }
		if condition != 0 {
			return p.constant_value(expr.then_expr) or { return none }
		}
		return p.constant_value(expr.else_expr) or { return none }
	}
	return none
}

// floating_constant_value is the value of a floating constant expression this
// reader evaluates while it reads: a floating literal, a sign in front of one, a
// cast of an integer or a floating constant to a floating type, the arithmetic
// of two such values, and the conditional. It is what a file-scope object of a
// floating type, or an element of a brace initializer for one, holds: the image
// is written before the program runs, so the value is what goes into it and not
// the expression that computes it.
//
// A step is evaluated in the class its own operands give it, which is what the
// usual arithmetic conversions do: an operand of an integer type is folded by
// the integer folder and widened here, and `1 / 2` stays the zero it is rather
// than becoming the half of a floating division. A shape that is not one of
// these answers none, so an element this reader cannot evaluate is refused by
// name rather than written as a value the fold did not make.
fn (p Parser) floating_constant_value(expr ast.Expr) ?f64 {
	if expr is ast.FloatLit {
		if expr.long_value != none {
			// A long double constant keeps its value in the extended field and
			// its double field is zero (ast.FloatLit), so folding one here
			// answered 0.0 for every spelling. This folder produces a double
			// and cannot hold the extended value, so it answers none and the
			// file-scope constant reader takes the literal through the reader
			// of the extended type instead, which is where its bytes come from.
			return none
		}
		return expr.value
	}
	if expr is ast.Unary {
		if expr.op != '-' && expr.op != '+' {
			return none
		}
		operand := p.floating_constant_value(expr.expr) or { return none }
		return if expr.op == '-' { -operand } else { operand }
	}
	if expr is ast.Cast {
		if !expr.typ.kind.is_floating() {
			return none
		}
		if value := p.floating_constant_value(expr.expr) {
			return value
		}
		if value := p.constant_value(expr.expr) {
			return f64(value)
		}
		return none
	}
	if expr is ast.Binary {
		if !expr.typ.kind.is_floating() {
			return none
		}
		left := p.floating_operand_value(expr.left) or { return none }
		right := p.floating_operand_value(expr.right) or { return none }
		return match expr.op {
			'+' { left + right }
			'-' { left - right }
			'*' { left * right }
			'/' {
				if right == 0.0 {
					return none
				}
				left / right
			}
			else { none }
		}
	}
	if expr is ast.Conditional {
		if !expr.typ.kind.is_floating() {
			return none
		}
		condition := p.constant_value(expr.cond) or { return none }
		if condition != 0 {
			return p.floating_constant_value(expr.then_expr) or { return none }
		}
		return p.floating_constant_value(expr.else_expr) or { return none }
	}
	return none
}

// floating_operand_value is one operand of a floating step: its floating value
// when it is a floating expression, and the integer folder's value widened when
// it is a constant of an integer type. The two classes are read apart rather
// than both through the double folder, so a step whose own operands are integers
// keeps the integer arithmetic the language gives it.
fn (p Parser) floating_operand_value(expr ast.Expr) ?f64 {
	if value := p.floating_constant_value(expr) {
		return value
	}
	if value := p.constant_value(expr) {
		return f64(value)
	}
	return none
}

// apply_constant_step is the arithmetic constant_value folds one binary step
// with. It is the match the binary arm used to hold inline, moved out so the
// left-spine loop and the callers answer the same value for an operator.
fn apply_constant_step(op string, left i64, right i64) ?i64 {
	return match op {
		'+' { left + right }
		'-' { left - right }
		'*' { left * right }
		'/' {
			if right == 0 {
				return none
			}
			left / right
		}
		'%' {
			if right == 0 {
				return none
			}
			left % right
		}
		'<<' {
			if right < 0 || right >= 64 {
				return none
			}
			left << right
		}
		'>>' {
			if right < 0 || right >= 64 {
				return none
			}
			left >> right
		}
		'<' {
			if left < right { i64(1) } else { i64(0) }
		}
		'>' {
			if left > right { i64(1) } else { i64(0) }
		}
		'<=' {
			if left <= right { i64(1) } else { i64(0) }
		}
		'>=' {
			if left >= right { i64(1) } else { i64(0) }
		}
		'==' {
			if left == right { i64(1) } else { i64(0) }
		}
		'!=' {
			if left != right { i64(1) } else { i64(0) }
		}
		'&' { left & right }
		'^' { left ^ right }
		'|' { left | right }
		else { none }
	}
}

// floating_operand is the value of a floating constant written as the operand of
// a cast, with a sign in front of it allowed: 6.6p6 admits a floating constant to
// an integer constant expression only as the immediate operand of a cast, and
// `-3.5` is one constant with a sign on it. It is asked only from the cast arm, so
// a floating constant anywhere else still has no value this folder will use.
fn floating_operand(expr ast.Expr) ?f64 {
	if expr is ast.FloatLit {
		return expr.value
	}
	if expr is ast.Unary {
		if operand := floating_operand(expr.expr) {
			if expr.op == '-' {
				return -operand
			}
			if expr.op == '+' {
				return operand
			}
		}
	}
	return none
}

// converted_constant is one integer constant converted to an integer type: a
// `_Bool` is one for any value that is not zero, a narrowing conversion keeps the
// low bytes, and a type the target has no size for answers none.
fn (p Parser) converted_constant(typ types.Type, operand i64) ?i64 {
	if typ.kind == .bool_ {
		return if operand != 0 { i64(1) } else { i64(0) }
	}
	size := p.representation.size_of(typ) or { return none }
	return truncate_integer(operand, size, typ.is_unsigned_type())
}

// converted_float_constant is a floating constant converted to an integer type,
// the one floating operand 6.6p6 allows in an integer constant expression. The
// conversion truncates toward zero, which is what the run-time one does and what
// gcc 16.2.1 gives under `-std=c99`: `int x[(int) 3.5];` is three elements and
// `int x[(int) -0.5];` is zero. A value no i64 holds, or a NaN, is not a
// conversion this reader makes and answers none rather than wrapping to a number
// that is not the one written.
fn (p Parser) converted_float_constant(typ types.Type, value f64) ?i64 {
	if value != value || value >= 9223372036854775808.0 || value < -9223372036854775808.0 {
		return none
	}
	return p.converted_constant(typ, i64(value))
}

// truncate_integer is a constant converted to an integer type of size bytes: a
// narrowing conversion keeps the low bytes, and a signed one sign-extends them.
// A width of eight bytes or more changes nothing, because every constant this
// reader holds is an i64 already.
fn truncate_integer(value i64, size int, unsigned bool) i64 {
	if size <= 0 || size >= 8 {
		return value
	}
	bits := size * 8
	mask := (i64(1) << bits) - 1
	kept := value & mask
	if !unsigned && (kept & (i64(1) << (bits - 1))) != 0 {
		return kept | ~mask
	}
	return kept
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
	p.report_at(t.line, t.col, if t.file != '' { t.file } else { p.file }, msg, false, .cpp)
}

// error_span reports a diagnostic at a position that came from a node rather than
// from a token: the argument of a call is where its own expression started, which
// is the line and column a reader of the source will look at. A node carries no
// file, so the one the reader is in is the file the message names.
fn (mut p Parser) error_span(line int, col int, msg string) {
	p.report_at(line, col, p.file, msg, false, .cpp)
}

// problem_at reports a conversion reason at a token, which is where the
// diagnostic's class comes from: `types.Problem` carries whether the flags
// decide the reason and which class names it, so a reason gcc warns about is a
// warning here and a reason the program is wrong for stays an error.
fn (mut p Parser) problem_at(t tokenize.Token, problem types.Problem) {
	p.report_at(t.line, t.col, if t.file != '' { t.file } else { p.file }, problem.msg, problem.warning, problem.class)
}

// problem_span is the same for a reason reported where a node started, which is
// where gcc points a discarded qualifier: at the initializer it was written.
fn (mut p Parser) problem_span(line int, col int, problem types.Problem) {
	p.report_at(line, col, p.file, problem.msg, problem.warning, problem.class)
}

// report_at is the parser's one diagnostic sink. `warning` says whether the
// command line decides the diagnostic's fate or it stops the compile on its own,
// and `class` is what a -W flag names; a diagnostic the parser raises on its own
// account is an error and carries the default class, which is why `warning` is
// false on every path but a conversion reason.
fn (mut p Parser) report_at(line int, col int, file string, msg string, warning bool, class diagnostics.Class) {
	p.diagnostics << tokenize.Diagnostic{
		line:    line
		col:     col
		msg:     msg
		file:    file
		warning: warning
		class:   class
	}
}

fn describe(t tokenize.Token) string {
	if t.kind == .eof {
		return 'end of file'
	}
	return "'${t.text}'"
}
