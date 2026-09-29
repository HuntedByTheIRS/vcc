module ast

import types

// The tree the parser produces and the back end consumes. It covers what the
// stub compiles and nothing else: function definitions returning one of the
// supported types, statements that are a return, a block or an empty statement,
// and integer constant expressions. Every node carries the location it came
// from, because a diagnostic without one is a diagnostic nobody can act on.
//
// Every node also carries the type clause 6 resolves it to, in the field named
// `typ` on an expression and `resolved` on a declaration. It is filled while the
// parser reads, by the type model in `types/`, and a node the model could not
// answer for carries the zero value of `types.Type`, whose kind is `.unknown`:
// the type of a name this compiler never resolved, or of a construct whose
// milestone has not landed. An unresolved clause is not a claim that the type is
// void.
//
// The spelling a declaration was written with is kept beside the clause it
// resolved to, in `ret`, `typ`, `decl_type` and the type a global was declared
// with. The emitter reads the spelling today, since moving it to the clause is
// the back end milestone's work for the C99 types, and a reader comparing the two
// can see where a declaration was read and where it was resolved.

// TranslationUnit is one source file: its declarations, in the order they were
// written.
pub struct TranslationUnit {
pub:
	decls []FnDecl
	// globals are the objects defined at the top level: storage that lives in
	// the image rather than in any function's frame, and that every function
	// reads and writes by name.
	globals []Global
}

pub struct FnDecl {
pub:
	name string
	// ret is the return type as written, `int` or `void`, and ret_type is what
	// the type model resolved that spelling to. resolved is the type the name
	// denotes, which is the function type: the return type and the parameters
	// together, since that is what a call is checked against and what a
	// declaration of the same function has to agree with.
	ret      string
	ret_type types.Type
	resolved types.Type
	// params are the parameters, in the order they were written. They are
	// storage in the frame of the call, so where they are written is where the
	// back end has to put them.
	params []Param
	// body is empty for a declaration without a definition.
	body []Stmt
	line int
	col  int
}

// Param is one parameter of a function: its name, the type as written, and what
// the type model resolved that spelling to. A parameter is stored with the
// adjustment 6.7.5.3 asks for, so one written as an array is a pointer here.
pub struct Param {
pub:
	name     string
	typ      string
	resolved types.Type
	line     int
	col      int
}

// Global is one object defined at the top level. The type is written the way a
// declaration writes it and `resolved` is what it names, which a count above zero
// makes an array of that many elements. The initializer is a constant, which is
// what a file-scope definition may have: none means the storage starts zeroed,
// which is what an object without an initializer is defined to hold.
//
// An object holding a double has its constant in `init_float` and one of any
// other type has it in `init`, because the two are written into the image as
// different bytes: an integer in two's complement at the width of its type, and a
// double as the eight bytes of its value.
pub struct Global {
pub:
	name       string
	typ        string
	resolved   types.Type
	count      int
	init       ?i64
	init_float ?f64
	line       int
	col        int
}

pub enum StmtKind {
	return_stmt
	block
	empty
	// expr_stmt is an expression evaluated for what it does and thrown away,
	// which is what a call written as a statement is.
	expr_stmt
	// var_decl is a declaration inside a function body: storage in the frame,
	// and a statement that runs where it is written.
	var_decl
	// assign is `target = expr;`. C makes an assignment an expression; this
	// tree makes it a statement of its own, because a statement is where it is
	// written in almost every line of C there is.
	assign
	if_stmt
	while_stmt
	break_stmt
	continue_stmt
}

pub struct Stmt {
pub:
	kind StmtKind
	// expr is the returned expression of a return statement, none for a bare
	// `return;` or for a statement that returns nothing.
	expr ?Expr
	// init is the initializer of a declaration, and none for `int x;`.
	init ?Expr
	// decl_name and decl_type are a declaration's name and type as written, and
	// decl_count is how many elements an array declaration has: zero for a
	// declaration of one value. resolved is the type the declaration resolved
	// to, and it is the zero value for a statement that declares nothing.
	decl_name  string
	decl_type  string
	decl_count int
	resolved   types.Type
	// bytes is how many bytes of storage the object is when its type is an
	// aggregate, and zero for an object the back end sizes from its spelling.
	// A struct is not the address of anything and has no spelling the back end
	// can size, so how much room it takes is a fact the reader got from the
	// model's layout and the back end is handed rather than asked for.
	bytes int
	// target is the name an assignment writes to, index is the subscript of
	// an array element: `a[i] = v` writes to an element, and a plain `x = v`
	// has none. field is the member of an aggregate the assignment writes to,
	// `x.a = v`, which is an offset into the object rather than a name of its
	// own.
	target string
	index  ?Expr
	field  ?Field
	// cond is the controlling expression of an if or a while: what has to be
	// true for the branch to be taken, or for the loop to go round again.
	cond ?Expr
	// body is the contents of a block, or the body of a loop.
	body []Stmt
	// step is what a loop runs at the end of every turn before going round
	// again: the third part of a `for`, and empty for a `while`. It belongs to
	// the loop and not to the body, because a continue has to reach it — as the
	// body's last statement it would be jumped over by every continue above it,
	// and a loop whose counter only advances in its last statement would never
	// end.
	step []Stmt
	// then_body and else_body are the two branches of an if. The else is empty
	// when it was not written.
	then_body []Stmt
	else_body []Stmt
	line      int
	col       int
}

// Expr is one of the expression shapes the stub understands. A call is parsed
// so that the diagnostic can say calls are not implemented yet, rather than the
// parser failing on a token it did not expect.
//
// Every one of them carries `typ`, the type the expression has: a literal the
// type of the constant, a name the type it was declared with, an operator the
// type its operands convert to. Where the model has no answer the clause is
// unresolved, and the printer says nothing about it.
pub type Expr = Binary | Unary | IntLit | FloatLit | Ident | Call | StrLit | Index | Field

// Index is one element of an array, written `a[i]`: the name of the array and
// the expression that says which element. An element of a named array is the one
// place a subscript is read and written; a general lvalue — a dereference, a
// subscript of a subscript, or an array that is not a name — is a shape the tree
// does not have, and the expression reader reports it where it stops.
pub struct Index {
pub:
	name  string
	index Expr
	typ   types.Type
	line  int
	col   int
}

// Field is one member of an aggregate object, written `x.a`. The object is named
// rather than held as a nested expression, because a member of a named object is
// the one place this tree reads and writes a field: a member of a member, of a
// call's result, or of a pointer needs a general lvalue the tree does not have.
//
// offset is where the member sits in the object, which is a fact about the
// target's layout that the model answered when the member was read. spelling is
// the member's type as this compiler writes a type, because what is read at that
// offset is a value of the member's type and the back end sizes a load from that.
pub struct Field {
pub:
	name     string
	member   string
	offset   int
	spelling string
	typ      types.Type
	line     int
	col      int
}

pub struct IntLit {
pub:
	value i64
	// text is the literal as written, kept for diagnostics and for the type the
	// constant has, which 6.4.4.1 decides from the spelling as much as from the
	// value.
	text string
	typ  types.Type
	line int
	col  int
}

// FloatLit is one floating constant. value is the double it names, which is what
// a constant with a decimal point or an exponent has unless a suffix says
// otherwise, and text is the spelling it was written with. A constant that is
// too large for a double, or one written with a suffix this compiler does not
// implement, is refused where it is read rather than rounded here.
pub struct FloatLit {
pub:
	value f64
	text  string
	typ   types.Type
	line  int
	col   int
}

// StrLit is one string literal. value is the bytes it names with the escapes
// resolved — what the program will actually read — and text is the literal as
// written, quotes included, for diagnostics and for printing a tree. Its type is
// an array of char, with room for the terminator the literal does not write.
pub struct StrLit {
pub:
	value string
	text  string
	typ   types.Type
	line  int
	col   int
}

pub struct Ident {
pub:
	name string
	typ  types.Type
	line int
	col  int
}

pub struct Unary {
pub:
	op   string
	expr Expr
	typ  types.Type
	line int
	col  int
}

pub struct Binary {
pub:
	op    string
	left  Expr
	right Expr
	typ   types.Type
	line  int
	col   int
}

pub struct Call {
pub:
	name string
	args []Expr
	typ  types.Type
	line int
	col  int
}
