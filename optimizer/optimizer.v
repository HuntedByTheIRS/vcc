module optimizer

import ast

// The optimizer sits between the parser and the emitter: `ast` in, `ast` out.
// It owns two things a compiler is expected to have: the `-O` levels, and the
// set of library functions whose value it may compute itself (`-fno-builtin`
// takes that back).
//
// Both are tables rather than branches. A pass names the level that turns it on
// and the function that applies it, so adding an optimization is a row in
// `passes` and a function beside it. A builtin names its arity and the function
// that computes its value, so adding `strlen` later is a row in `builtins`.
//
// The emitter never asks this module anything. It runs before codegen and hands
// over a tree, which keeps `codegen/` about one target's bytes and nothing else.

pub enum Level {
	o0
	o1
	o2
	o3
	os
}

// rank orders the levels by how much work they turn on. `-Os` sits with `-O2`,
// which is what it is: `-O2` without the passes that make code larger.
fn (l Level) rank() int {
	return match l {
		.o0 { 0 }
		.o1 { 1 }
		.o2 { 2 }
		.o3 { 3 }
		.os { 2 }
	}
}

pub fn (l Level) spelling() string {
	return match l {
		.o0 { '-O0' }
		.o1 { '-O1' }
		.o2 { '-O2' }
		.o3 { '-O3' }
		.os { '-Os' }
	}
}

// Options is the optimization state of one compile.
pub struct Options {
pub mut:
	level Level
	// builtins is on by default, as it is in gcc and clang: a call to a known
	// library function with constant arguments is computed at compile time.
	builtins bool
	// disabled holds the names `-fno-builtin-NAME` turned off.
	disabled []string
	// recorded keeps the flags as they were written, so a verbose mode can show
	// what the command line asked for rather than only what was honored.
	recorded []string
}

pub fn default_options() Options {
	return Options{
		builtins: true
	}
}

// accept_flag reads one command-line argument and reports whether the optimizer
// owns it. The command line parser calls this for every flag it does not know,
// so the list of optimization flags lives here and not in `cli/`.
//
// A level or a `-f...` spelling this stub does not implement is accepted and
// recorded rather than refused. V hands a compiler flags for work it expects to
// be done, and refusing one fails a build that was supposed to succeed.
pub fn (mut o Options) accept_flag(arg string) bool {
	if arg == '-O' {
		return o.record_level(arg, .o1)
	}
	if arg.starts_with('-O') && arg.len > 2 {
		rest := arg[2..]
		return match rest {
			'0' { o.record_level(arg, .o0) }
			'1' { o.record_level(arg, .o1) }
			'2' { o.record_level(arg, .o2) }
			'3' { o.record_level(arg, .o3) }
			// -Os is -O2 for size; -Og is -O1 without the optimizations that
			// make debugging harder; -Ofast is -O3 plus semantic loosenings this
			// stub does not implement, so it is the level and not the loosenings.
			's' { o.record_level(arg, .os) }
			'g' { o.record_level(arg, .o1) }
			'fast' { o.record_level(arg, .o3) }
			// Anything else is recorded and changes nothing.
			else {
				o.recorded << arg
				true
			}
		}
	}
	if arg == '-fno-builtin' {
		o.builtins = false
		o.recorded << arg
		return true
	}
	if arg == '-fbuiltin' {
		o.builtins = true
		o.recorded << arg
		return true
	}
	if arg.starts_with('-fno-builtin-') {
		o.disabled << arg[13..]
		o.recorded << arg
		return true
	}
	if arg.starts_with('-fbuiltin-') {
		o.enable_builtin(arg[10..])
		o.recorded << arg
		return true
	}
	return false
}

fn (mut o Options) record_level(arg string, level Level) bool {
	o.level = level
	o.recorded << arg
	return true
}

fn (mut o Options) enable_builtin(name string) {
	mut kept := []string{}
	for disabled in o.disabled {
		if disabled != name {
			kept << disabled
		}
	}
	o.disabled = kept
}

// folds_builtin says whether a call to this name may be replaced by its value.
//
// The reserved `__builtin_` spelling is an explicit request and survives
// -fno-builtin, which is how gcc treats it: -fno-builtin says "do not assume
// what a library function named abs does", and `__builtin_abs` is not a library
// function anyone else can redefine.
pub fn (o Options) folds_builtin(name string) bool {
	if name.starts_with('__builtin_') {
		return true
	}
	if !o.builtins {
		return false
	}
	return name !in o.disabled
}

// Pass is one rewrite with the level that turns it on.
struct Pass {
	name  string
	min   Level
	apply fn (unit ast.TranslationUnit, opts Options) ast.TranslationUnit @[required]
}

// passes is the pipeline, in the order it runs. The only entry today folds a
// call whose value the compiler can compute; it is at -O1 because a call this
// stub cannot emit is a diagnostic at -O0, and turning that into a value is the
// optimization.
const passes = [
	Pass{
		name:  'fold-builtins'
		min:   .o1
		apply: fold_builtin_calls
	},
]

// Builtin is a library function the compiler knows the value of when its
// argument is a constant. arity is checked before `apply` is called.
struct Builtin {
	name  string
	arity int
	apply fn (args []ast.Expr) ?i64 @[required]
}

// builtins is the table `fold-builtins` reads. The three abs spellings are the
// same function with different argument types in C, and the stub has one
// integer type, so they compute the same thing.
//
// `__builtin_constant_p` is deliberately absent: answering it correctly means
// folding a whole constant expression, and this module can only evaluate a
// literal. A wrong answer to that builtin is worse than no answer, so it waits
// for the constant folder to be shared with the emitter.
const builtins = [
	Builtin{
		name:  'abs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  'labs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  'llabs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_abs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_labs'
		arity: 1
		apply: absolute_value
	},
	Builtin{
		name:  '__builtin_llabs'
		arity: 1
		apply: absolute_value
	},
]

// max_rewrite_depth bounds how far into a nested expression the rewrite
// follows. The emitter has the same kind of bound and reports the nesting it
// will not fold, so returning the expression unchanged here leaves the
// diagnostic to the place that already owns it.
const max_rewrite_depth = 200

// pipeline names the passes that run at a level, in order.
pub fn pipeline(opts Options) []string {
	mut names := []string{}
	for pass in passes {
		if pass.min.rank() <= opts.level.rank() {
			names << pass.name
		}
	}
	return names
}

// optimize runs the pipeline over a translation unit and returns the tree the
// emitter gets.
pub fn optimize(unit ast.TranslationUnit, opts Options) ast.TranslationUnit {
	mut current := unit
	for pass in passes {
		if pass.min.rank() <= opts.level.rank() {
			current = pass.apply(current, opts)
		}
	}
	return current
}

// summary is the one line `-vv` prints about the optimizer.
pub fn (o Options) summary() string {
	names := pipeline(o)
	state := if names.len == 0 { 'no passes' } else { names.join(', ') }
	builtins_state := if o.builtins { 'builtins on' } else { 'builtins off' }
	if o.disabled.len > 0 {
		return '${o.level.spelling()}: ${state}; ${builtins_state}; disabled ${o.disabled.join(', ')}'
	}
	return '${o.level.spelling()}: ${state}; ${builtins_state}'
}

fn fold_builtin_calls(unit ast.TranslationUnit, opts Options) ast.TranslationUnit {
	mut decls := []ast.FnDecl{}
	for decl in unit.decls {
		// Every part of the declaration is carried over, and the parameters are
		// the ones that are easy to forget: a declaration rebuilt without them
		// is a function whose parameters the back end cannot find, which is a
		// diagnostic at -O1 and up and nothing at all at -O0.
		decls << ast.FnDecl{
			name:   decl.name
			ret:    decl.ret
			params: decl.params
			body:   rewrite_body(decl.body, opts)
			line:   decl.line
			col:    decl.col
		}
	}
	return ast.TranslationUnit{
		decls: decls
	}
}

fn rewrite_body(body []ast.Stmt, opts Options) []ast.Stmt {
	mut out := []ast.Stmt{}
	for stmt in body {
		// Every expression a statement carries is rewritten, and the
		// statements it carries are rewritten in turn. A statement is passed on
		// whole: a field that is not written here is a field that would be lost
		// on the way to the back end.
		mut expr := ?ast.Expr(none)
		if value := stmt.expr {
			expr = rewrite(value, opts, 0)
		}
		mut init := ?ast.Expr(none)
		if value := stmt.init {
			init = rewrite(value, opts, 0)
		}
		mut cond := ?ast.Expr(none)
		if value := stmt.cond {
			cond = rewrite(value, opts, 0)
		}
		// An element of an array is a place a value is read from as well as
		// written to, so the subscript is rewritten like every other expression.
		mut index := ?ast.Expr(none)
		if value := stmt.index {
			index = rewrite(value, opts, 0)
		}
		out << ast.Stmt{
			kind:       stmt.kind
			expr:       expr
			init:       init
			decl_name:  stmt.decl_name
			decl_type:  stmt.decl_type
			decl_count: stmt.decl_count
			target:     stmt.target
			index:      index
			cond:       cond
			body:       rewrite_body(stmt.body, opts)
			step:       rewrite_body(stmt.step, opts)
			then_body:  rewrite_body(stmt.then_body, opts)
			else_body:  rewrite_body(stmt.else_body, opts)
			line:       stmt.line
			col:        stmt.col
		}
	}
	return out
}

// rewrite returns the expression with every builtin call it can compute
// replaced by the value. The left spine of an operator chain is walked with a
// loop rather than with recursion: a chain of ten thousand terms is one level
// deep in the grammar and ten thousand nodes deep in the tree, and recursing
// over it is a stack overflow rather than an optimization.
fn rewrite(expr ast.Expr, opts Options, depth int) ast.Expr {
	if depth > max_rewrite_depth {
		return expr
	}
	mut spine := []ast.Binary{}
	mut node := expr
	for node is ast.Binary {
		binary := node as ast.Binary
		spine << binary
		node = binary.left
	}
	mut rebuilt := rewrite_leaf(node, opts, depth + 1)
	for i := spine.len - 1; i >= 0; i-- {
		binary := spine[i]
		rebuilt = ast.Expr(ast.Binary{
			op:    binary.op
			left:  rebuilt
			right: rewrite_leaf(binary.right, opts, depth + 1)
			line:  binary.line
			col:   binary.col
		})
	}
	return rebuilt
}

fn rewrite_leaf(expr ast.Expr, opts Options, depth int) ast.Expr {
	match expr {
		ast.IntLit {
			return expr
		}
		ast.Ident {
			return expr
		}
		ast.StrLit {
			return expr
		}
		ast.Index {
			// An element is a place a value is read from, and the expression
			// that says which element is rewritten like any other.
			return ast.Expr(ast.Index{
				name:  expr.name
				index: rewrite(expr.index, opts, depth + 1)
				line:  expr.line
				col:   expr.col
			})
		}
		ast.Binary {
			return rewrite(expr, opts, depth + 1)
		}
		ast.Unary {
			return ast.Expr(ast.Unary{
				op:   expr.op
				expr: rewrite(expr.expr, opts, depth + 1)
				line: expr.line
				col:  expr.col
			})
		}
		ast.Call {
			// The arguments are rewritten first, so `abs(abs(-3))` folds the
			// inner call and then has a constant to work with.
			rewritten := ast.Call{
				name: expr.name
				args: rewrite_arguments(expr.args, opts, depth + 1)
				line: expr.line
				col:  expr.col
			}
			return fold_call(rewritten, opts) or { ast.Expr(rewritten) }
		}
	}
}

fn rewrite_arguments(args []ast.Expr, opts Options, depth int) []ast.Expr {
	mut out := []ast.Expr{}
	for arg in args {
		out << rewrite(arg, opts, depth)
	}
	return out
}

// fold_call computes a call to a builtin, or hands back nothing so the call
// stays in the tree and the emitter reports it. A name that is not in the table,
// an argument count that does not match, an argument that is not a constant, and
// a name the command line turned off all end the same way: leave it alone.
fn fold_call(call ast.Call, opts Options) ?ast.Expr {
	if !opts.folds_builtin(call.name) {
		return none
	}
	for builtin in builtins {
		if builtin.name != call.name {
			continue
		}
		if call.args.len != builtin.arity {
			return none
		}
		value := builtin.apply(call.args) or { return none }
		return ast.Expr(ast.IntLit{
			value: value
			text:  '${value}'
			line:  call.line
			col:   call.col
		})
	}
	return none
}

// constant_of evaluates what the stub calls a constant: a literal, or a literal
// with a sign or a complement in front of it. Folding `abs(1 + 2)` would mean a
// constant expression evaluator here, and the emitter already has one; until the
// two are one function, a builtin's argument has to be written out.
fn constant_of(expr ast.Expr, depth int) ?i64 {
	if depth > 8 {
		return none
	}
	match expr {
		ast.IntLit {
			return expr.value
		}
		ast.Unary {
			operand := constant_of(expr.expr, depth + 1) or { return none }
			return match expr.op {
				'-' { wrap_sub(0, operand) }
				'+' { operand }
				'~' { ~operand }
				else { none }
			}
		}
		else {
			return none
		}
	}
}

fn absolute_value(args []ast.Expr) ?i64 {
	value := constant_of(args[0], 0) or { return none }
	if value < 0 {
		// The one value with no positive counterpart wraps to itself, which is
		// what the emitter's arithmetic does with it too.
		return wrap_sub(0, value)
	}
	return value
}

// Wrapping arithmetic, for the same reason the emitter spells it out: V 0.5.2
// has no `+%`, and whether `-` traps depends on how this binary was built.
fn wrap_sub(a i64, b i64) i64 {
	return i64(u64(a) - u64(b))
}
