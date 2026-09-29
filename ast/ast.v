module ast

// The tree the parser produces and the back end consumes. It covers what the
// stub compiles and nothing else: function definitions returning one of the
// supported types, statements that are a return, a block or an empty statement,
// and integer constant expressions. Every node carries the location it came
// from, because a diagnostic without one is a diagnostic nobody can act on.

// TranslationUnit is one source file: its declarations, in the order they were
// written.
pub struct TranslationUnit {
pub:
	decls []FnDecl
}

pub struct FnDecl {
pub:
	name string
	// ret is the return type as written, `int` or `void`.
	ret string
	// body is empty for a declaration without a definition.
	body []Stmt
	line int
	col  int
}

pub enum StmtKind {
	return_stmt
	block
	empty
	// expr_stmt is an expression evaluated for what it does and thrown away,
	// which is what a call written as a statement is.
	expr_stmt
}

pub struct Stmt {
pub:
	kind StmtKind
	// expr is the returned expression of a return statement, and none for a
	// bare `return;` or for a statement that returns nothing.
	expr ?Expr
	// body is the contents of a block.
	body []Stmt
	line int
	col  int
}

// Expr is one of the expression shapes the stub understands. A call is parsed
// so that the diagnostic can say calls are not implemented yet, rather than the
// parser failing on a token it did not expect.
pub type Expr = Binary | Unary | IntLit | Ident | Call | StrLit

pub struct IntLit {
pub:
	value i64
	// text is the literal as written, kept for diagnostics.
	text string
	line int
	col  int
}

// StrLit is one string literal. value is the bytes it names with the escapes
// resolved — what the program will actually read — and text is the literal as
// written, quotes included, for diagnostics and for printing a tree.
pub struct StrLit {
pub:
	value string
	text  string
	line  int
	col   int
}

pub struct Ident {
pub:
	name string
	line int
	col  int
}

pub struct Unary {
pub:
	op   string
	expr Expr
	line int
	col  int
}

pub struct Binary {
pub:
	op    string
	left  Expr
	right Expr
	line  int
	col   int
}

pub struct Call {
pub:
	name string
	args []Expr
	line int
	col  int
}
