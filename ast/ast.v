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
	// defined says the file wrote a body for this function. It is separate
	// from body because a definition may have an empty body: `void f(void) {}`
	// is a definition this translation unit supplies, and body.len is zero for
	// it just as it is for a prototype. A prototype (defined false) names a
	// function the link has to find elsewhere; a definition is emitted here and
	// a call to it is a call into this image.
	defined bool
	// body is the statements the definition wrote. It is empty both for a
	// prototype and for a definition written as `{}`, so defined is what tells
	// the two apart.
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
	name     string
	typ      string
	resolved types.Type
	count    int
	// bytes is how much storage an object of an aggregate type takes, and zero
	// for every other kind, which is sized from its type the way it always was.
	// An aggregate has no width a spelling answers, so the declaration asks the
	// model's layout once, here, and every later stage reads the number.
	bytes      int
	init       ?i64
	init_float ?f64
	// inits and init_floats are a brace initializer for an array: one constant
	// per element in the order written, the first list for an object whose
	// elements are integers and the second for one whose elements are doubles,
	// the same split a scalar initializer has. The elements the list did not
	// write are the zeros the storage starts as, which is what C says the rest
	// of a partly initialized array holds.
	inits       []i64
	init_floats []f64
	// member_inits is a struct's brace initializer: one entry per member the
	// list wrote, in the order written. A struct's members sit at successive
	// offsets, so each constant carries the member it goes to and the members
	// the list did not reach are the zeros the storage starts as (6.7.8p21).
	member_inits []MemberInit
	line         int
	col          int
}

// MemberInit is one member a brace initializer wrote into an object at file
// scope: where the member sits in the object, how wide it is, and the constant
// written into it. The width and the spelling are the member's own type, because
// a value written into a member is converted the way a store into a member
// converts it, and at most one of init and init_float is set.
pub struct MemberInit {
pub:
	offset   int
	width    int
	spelling string
	init     ?i64
	// init_float is the same constant when the member holds a floating value,
	// the split a scalar and an array initializer already make.
	init_float ?f64
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
	// do_while_stmt is a loop whose test runs after its body, so the body runs at
	// least once whatever the condition says. It holds what a while holds and has
	// no step, because where the test sits is the whole difference between the two
	// and that is what the kind says.
	do_while_stmt
	break_stmt
	continue_stmt
	// switch_stmt is `switch (expr) stmt`. The controlling expression selects
	// which of the case labels written in the body the program jumps to, and
	// control then runs on through the statements in the order they are
	// written, so a case with no break before the next one runs into it.
	switch_stmt
	// case_stmt is a `case constant:` label. It is a statement of its own so
	// that a switch's body is the statements written in it and a label is one
	// of them: the label names the place the statement after it is written at,
	// and case_value is the integer the switch matches it against.
	case_stmt
	// default_stmt is the `default:` label, which is where a switch goes when
	// no case matches. A switch has at most one.
	default_stmt
	// label_stmt is a named label, `name:`, which a goto jumps to. It is a
	// statement of its own and governs nothing: the statement written after it
	// is the next statement of the block.
	label_stmt
	// goto_stmt is `goto name;`, a jump to the label of that name anywhere in
	// the same function, forward or backward.
	goto_stmt
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
	// deref is the dereference an assignment writes through when the target
	// is not a name: `*p = v` writes the value at the address the pointer
	// holds, so what the store needs is that address and the tree keeps the
	// expression that gives it, a Unary whose operand is the pointer. It is
	// none for an assignment to a name, and target is empty for one written
	// through a dereference.
	deref ?Expr
	// subscript is the element an assignment writes to when its base is not a
	// name the target fields can address, which is what `3[p] = 9` and
	// `p[3] = 9` for a pointer p are. The element node is carried whole because
	// the address it is stored through is computed from the base's value.
	subscript ?Expr
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
	// label is the name a goto jumps to and the name a label statement
	// declares. Labels are a namespace of their own: a label named `x` and an
	// object named `x` in the same function are two different names, and only
	// the label one is a place to jump to.
	label string
	// case_value is the integer constant a case label names, as written. C
	// converts it to the type of the controlling expression, and that
	// conversion is made where the label is placed.
	case_value i64
	line       int
	col        int
}

// Expr is one of the expression shapes the stub understands. A call is parsed
// so that the diagnostic can say calls are not implemented yet, rather than the
// parser failing on a token it did not expect.
//
// Every one of them carries `typ`, the type the expression has: a literal the
// type of the constant, a name the type it was declared with, an operator the
// type its operands convert to. Where the model has no answer the clause is
// unresolved, and the printer says nothing about it.
pub type Expr = Binary
	| Unary
	| Cast
	| IntLit
	| FloatLit
	| Ident
	| Call
	| StrLit
	| Index
	| Field
	| IncDec
	| Conditional
	| Assign
	| Comma
	| StmtExpr

// StmtExpr is a GNU statement expression, `({ ... })`: a brace-enclosed
// compound statement written where a value is wanted, whose value is the value
// of its last statement when that statement is an expression statement. The
// construct is gcc's and glibc's own headers write it, so it is read here for
// the same reason `__extension__` is: the C this compiler has to compile uses
// it, and gcc's own `assert` expands to one whenever `__GNUC__` is defined.
//
// body holds the statements that run for what they do, in the order they were
// written, and value holds the last statement's expression when there is one:
// the two are one statement list in the source, split here so the back end
// emits each half once. A construct whose last statement is not an expression
// statement has no value and its type is void, which is what `({ int x = 4; })`
// and `({ if (c) ; })` are; gcc refuses such one where a value is required and
// accepts it where the value is thrown away, and this tree's emitter does the
// same by name.
pub struct StmtExpr {
pub:
	body  []Stmt
	value ?Expr
	typ   types.Type
	line  int
	col   int
}

// Assign is an assignment used where a value is wanted rather than as a
// statement: `(x = 1) + 2`, `(a <<= 1)`, and the right operand of the second
// `=` in `(a = b = 3)`. 6.5.16 makes an assignment an expression of the
// ordinary grammar, so it stands wherever any other expression does; this tree
// reads the statement form as `Stmt` of kind `assign`, because that is where it
// is written in almost every line of C, and this node for the places the value
// is used.
//
// op is the operator as written (`=` or one of the compound spellings) and is
// kept so a reader of the tree sees what was written; the value written is
// already the one the operator means, because a compound spelling is expanded
// where it is read. target is the lvalue the value is written into and value is
// what is written. typ is the type of the object written, which is what the
// expression is worth after the conversion the store makes.
pub struct Assign {
pub:
	op     string
	target Expr
	value  Expr
	typ    types.Type
	line   int
	col    int
}

// Comma is the comma operator, `E1 , E2`. 6.5.17 makes it worth the value of
// its right operand and sequences the left before the right: the left is
// evaluated for what it does and thrown away. It is not the comma that
// separates: the commas in an argument list, a parameter list and a brace
// initializer are separators and are read where they are written, so this node
// is built only where a comma stands inside an expression.
pub struct Comma {
pub:
	left  Expr
	right Expr
	typ   types.Type
	line  int
	col   int
}

// Conditional is the conditional operator, `cond ? then_expr : else_expr`. It is
// worth a value rather than an effect: the value of whichever arm the condition
// selects, converted to the type the two arms have in common, so `int x = a ? b
// : c;` and `sizeof(1 ? 1 : 1.0)` are shapes it is read in. Only the arm the
// condition selects is evaluated, which is the part of 6.5.15 a reader cannot
// see from the types.
//
// `typ` is the type 6.5.15 gives the two arms together and not either arm's own.
// The condition's type is not part of that answer: a pointer, a double and an
// int condition all select between the same two arms.
pub struct Conditional {
pub:
	cond      Expr
	then_expr Expr
	else_expr Expr
	typ       types.Type
	line      int
	col       int
}

// Cast is a conversion written as a type name in parentheses, `(char *)p`. The
// type is what the operand is converted to and what the node is worth; spelling
// is the type as the file wrote it, which is what a diagnostic about the
// conversion names.
pub struct Cast {
pub:
	spelling string
	expr     Expr
	typ      types.Type
	line     int
	col      int
}

// Index is one element of an array or of the object a pointer addresses, written
// `E1[E2]`. 6.5.2.1 defines it as `*((E1) + (E2))`, so the base is an expression
// and not a name: a name, a member that is an array, another element, or a
// pointer value such as `*pp` or a call.
//
// Which of the two operands holds the address is settled while they are read.
// Addition commutes, so `3[p]` is `p[3]`, and the base here is always the operand
// whose type is the array or the pointer. `typ` is the type of the element that
// base names.
pub struct Index {
pub:
	base  Expr
	index Expr
	typ   types.Type
	line  int
	col   int
}

// Field is one member of an aggregate object, written `x.a`. The object is named
// rather than held as a nested expression: a member is read from an object with a
// place in the frame, and the name is that place.
//
// offset is where the member sits in the object, which is a fact about the
// target's layout that the model answered when the member was read. spelling is
// the member's type as this compiler writes a type, because what is read at that
// offset is a value of the member's type and the back end sizes a load from that.
//
// A path of members is one Field and not a chain of them, because a member of a
// member is inside the same object: `b.a.x` names `b` at the byte `x` sits at, with
// the offsets added up on the way in.
pub struct Field {
pub:
	name string
	// index is set when the object is one element of an array, which is what
	// `s[i].a` writes: the member is read from the element the index names, so
	// the address of the object is the address of that element and the stride
	// between elements is the size of one element's type.
	index    ?Expr
	member   string
	offset   int
	spelling string
	typ      types.Type
	// bitfield says the member is a bitfield: the value it holds is the bit_width
	// bits starting at bit_offset inside the storage unit at offset, and a store
	// into it has to leave the unit's other bits alone. unit_width is the size in
	// bytes of that storage unit, which is the width of the member's declared
	// type. A member that is not a bitfield leaves these false and zero, which is
	// what every read and write that does not ask about bits gets.
	bitfield   bool
	bit_offset int
	bit_width  int
	unit_width int
	// through_pointer says the name holds a pointer and not the object itself,
	// which is what `->` writes: `p->a` reads the member from the object `p`
	// points at, so the address comes from the pointer's value rather than from
	// the frame.
	through_pointer bool
	line            int
	col             int
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
	// callee is what a call calls when that is not a bare name: `(*fp)(1, 2)`,
	// `table[0](3, 4)`, and a name that holds a function pointer are all one
	// expression whose value is the address being called. It is none for a call
	// written to a name, which is what a function definition or an undeclared
	// library function is called by, and some(expression) otherwise. A call with
	// a callee is an indirect call: the expression's value is the address.
	callee ?Expr
	args   []Expr
	typ    types.Type
	line   int
	col    int
}

// IncDec is `++x`, `--x`, `x++` or `x--` written where a value is expected. The
// operand is a name and not a nested expression: the object this reads, steps
// and writes is a plain scalar, and a subscript, a member and a literal are
// refused where the operator is read rather than desugared into a shape the tree
// has no node for.
//
// C makes an assignment a statement here and gives the increment no statement of
// its own, so this is an expression node: it is worth a value, unlike `x = 1`.
//
// `op` is the operator as written, `++` or `--`. `postfix` says which value the
// node is worth: `x++` is what x held before the step and `++x` what it holds
// after, and that is the only difference between the two spellings.
pub struct IncDec {
pub:
	op      string
	name    string
	postfix bool
	typ     types.Type
	line    int
	col     int
}
