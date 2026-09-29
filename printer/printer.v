module printer

import ast
import types

// The printer turns a translation unit into text. It is what `-print-ast` runs,
// and it exists as its own module because `ast/` is node types only: the shape
// of a node and the way it reads are different jobs, and a tree that can print
// itself grows a print method on every node.
//
// The output is deterministic — same tree, same text — because it is read by
// people comparing two runs, and a dump that reorders its own lines is a dump
// nobody can diff.
//
// Every node the parser gave a type to carries it, written after the location it
// came from: `int 42 at 1:17 : int`. The clause is the model's answer and not the
// spelling, which is the point of printing it — a reader comparing the two sees
// where a declaration was read and where it was resolved. A node the model could
// not answer for says `: unresolved`, so that a missing clause means the printer
// had none to print and never that the reader has no answer.

// max_indent is where indentation stops growing. A chain of twenty thousand terms
// is twenty thousand levels deep, and growing the indent all the way down would
// print two spaces for every level of every line: hundreds of megabytes of
// whitespace for a file with one expression in it. Past this depth the levels
// are simply level with each other, and the order still reads.
const max_indent = 32

// render turns a unit into an indented tree, one node per line, with the
// location each node came from.
//
// Not named `dump`: V has a `dump()` builtin that wins over a function of the
// same name inside its own module, so the call would compile into the builtin's
// behavior with no diagnostic at the call site.
pub fn render(unit ast.TranslationUnit) string {
	mut out := []string{}
	for global in unit.globals {
		mut line := 'global ${global.name} ${global.typ}'
		if global.count > 0 {
			line += '[${global.count}]'
		}
		if init := global.init {
			line += ' = ${init}'
		} else {
			line += ' (zeroed)'
		}
		out << '${line} at ${global.line}:${global.col}${typed(global.resolved)}'
	}
	if unit.decls.len == 0 {
		out << '(no declarations)'
	}
	for decl in unit.decls {
		out << 'fn ${decl.name}() ${decl.ret} at ${decl.line}:${decl.col}${typed(decl.resolved)}'
		if decl.body.len == 0 {
			out << '  (declaration without a definition)'
			continue
		}
		dump_statements(decl.body, 1, mut out)
	}
	return out.join('\n')
}

// typed is the type clause of a node, written after the location it came from. A
// node with no answer carries the zero type, whose kind is unknown, and says so:
// the alternative - printing nothing - would read the same as a node this printer
// has no clause for.
fn typed(typ types.Type) string {
	if typ.kind == .unknown {
		return ' : unresolved'
	}
	return ' : ${typ.describe()}'
}

fn indent_of(depth int) string {
	level := if depth > max_indent { max_indent } else { depth }
	return '  '.repeat(level)
}

fn dump_statements(body []ast.Stmt, depth int, mut out []string) {
	for stmt in body {
		indent := indent_of(depth)
		match stmt.kind {
			.return_stmt {
				out << '${indent}return at ${stmt.line}:${stmt.col}'
			}
			.block {
				out << '${indent}block at ${stmt.line}:${stmt.col}'
			}
			.empty {
				out << '${indent}empty statement at ${stmt.line}:${stmt.col}'
			}
			.expr_stmt {
				out << '${indent}expression statement at ${stmt.line}:${stmt.col}'
			}
			.var_decl {
				elements := if stmt.decl_count > 0 { '[${stmt.decl_count}]' } else { '' }
				out << '${indent}declaration of ${stmt.decl_type} ${stmt.decl_name}${elements} at ${stmt.line}:${stmt.col}${typed(stmt.resolved)}'
			}
			.assign {
				out << '${indent}assignment to ${stmt.target} at ${stmt.line}:${stmt.col}'
			}
			.if_stmt {
				out << '${indent}if at ${stmt.line}:${stmt.col}'
			}
			.while_stmt {
				out << '${indent}while at ${stmt.line}:${stmt.col}'
			}
			.break_stmt {
				out << '${indent}break at ${stmt.line}:${stmt.col}'
			}
			.continue_stmt {
				out << '${indent}continue at ${stmt.line}:${stmt.col}'
			}
		}
		if expr := stmt.expr {
			dump_expression(expr, depth + 1, mut out)
		}
		if index := stmt.index {
			out << '${indent}subscript'
			dump_expression(index, depth + 1, mut out)
		}
		if init := stmt.init {
			out << '${indent}initializer'
			dump_expression(init, depth + 1, mut out)
		}
		if cond := stmt.cond {
			out << '${indent}condition'
			dump_expression(cond, depth + 1, mut out)
		}
		dump_statements(stmt.body, depth + 1, mut out)
		dump_statements(stmt.then_body, depth + 1, mut out)
		dump_statements(stmt.else_body, depth + 1, mut out)
		if stmt.step.len > 0 {
			// The step of a loop is written under its own heading, because it
			// is a part of the loop and not a part of the body.
			out << '${indent}step'
			dump_statements(stmt.step, depth + 1, mut out)
		}
	}
}

// dump_expression prints an expression. The left spine of an operator chain is
// walked with a loop for the same reason the folder and the optimizer walk it
// that way: a chain of ten thousand terms is one node deep in the grammar and
// ten thousand deep in the tree, and recursion over it runs the stack out on a
// file that is only doing what generated code does.
//
// The spine prints outermost first, its operands after it, so `6 * 7 + 1` reads
// as the tree it is:
//
//	binary + at ...
//	  binary * at ...
//	    int 6 at ...
//	    int 7 at ...
//	  int 1 at ...
fn dump_expression(expr ast.Expr, depth int, mut out []string) {
	mut spine := []ast.Binary{}
	mut node := expr
	for node is ast.Binary {
		binary := node as ast.Binary
		spine << binary
		node = binary.left
	}
	mut current := depth
	for binary in spine {
		out << '${indent_of(current)}binary ${binary.op} at ${binary.line}:${binary.col}${typed(binary.typ)}'
		current++
	}
	dump_leaf(node, current, mut out)
	// The right sides come after the left spine, innermost first, which is the
	// order they were written in.
	for i := spine.len - 1; i >= 0; i-- {
		dump_expression(spine[i].right, depth + i + 1, mut out)
	}
}

fn dump_leaf(expr ast.Expr, depth int, mut out []string) {
	indent := indent_of(depth)
	match expr {
		ast.IntLit {
			out << '${indent}int ${expr.value} at ${expr.line}:${expr.col}${typed(expr.typ)}'
		}
		ast.FloatLit {
			// The value is printed as a double rather than as the spelling it
			// was written with, because what the emitter reads is the value.
			out << '${indent}double ${expr.value} at ${expr.line}:${expr.col}${typed(expr.typ)}'
		}
		ast.Ident {
			out << '${indent}ident ${expr.name} at ${expr.line}:${expr.col}${typed(expr.typ)}'
		}
		ast.Unary {
			out << '${indent}unary ${expr.op} at ${expr.line}:${expr.col}${typed(expr.typ)}'
			dump_expression(expr.expr, depth + 1, mut out)
		}
		ast.Binary {
			// The spine loop leaves no Binary for this function to see; the arm
			// is here because the match covers every node the tree can hold.
			dump_expression(expr, depth, mut out)
		}
		ast.Call {
			out << '${indent}call ${expr.name} with ${expr.args.len} argument(s) at ${expr.line}:${expr.col}${typed(expr.typ)}'
			for arg in expr.args {
				dump_expression(arg, depth + 1, mut out)
			}
		}
		ast.StrLit {
			out << '${indent}string ${expr.text} at ${expr.line}:${expr.col}${typed(expr.typ)}'
		}
		ast.Index {
			out << '${indent}element ${expr.name}[] at ${expr.line}:${expr.col}${typed(expr.typ)}'
			dump_expression(expr.index, depth + 1, mut out)
		}
	}
}
