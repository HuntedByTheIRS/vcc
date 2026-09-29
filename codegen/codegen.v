module codegen

import ast
import backend
import tokenize

// Options is what the caller asks for. An empty target means the machine this
// binary runs on, which is the only kind of build the stub can do.
pub struct Options {
pub:
	target string
	entry  string
}

// Result carries the image to write, or the reasons it could not be produced.
pub struct Result {
pub:
	bytes       []u8
	target      backend.Target
	diagnostics []tokenize.Diagnostic
}

// emit turns a parsed translation unit into an executable image. There is no
// instruction selection yet: the body of the entry function has to fold to a
// constant, and the image exits with it.
pub fn emit(unit ast.TranslationUnit, opts Options) Result {
	target := resolve_target(opts.target) or {
		return Result{
			diagnostics: [problem(1, 1, err.msg())]
		}
	}
	entry := if opts.entry == '' { 'main' } else { opts.entry }
	mut definition := ?ast.FnDecl(none)
	for candidate in unit.decls {
		if candidate.name == entry && candidate.body.len > 0 {
			definition = candidate
		}
	}
	decl := definition or {
		return Result{
			target:      target
			diagnostics: [problem(1, 1, 'no definition of ${entry} in this translation unit')]
		}
	}
	mut diagnostics := []tokenize.Diagnostic{}
	status := exit_status(decl, mut diagnostics) or {
		return Result{
			target:      target
			diagnostics: diagnostics
		}
	}
	code := target.exit_sequence(status) or {
		return Result{
			target:      target
			diagnostics: [problem(decl.line, decl.col, err.msg())]
		}
	}
	return Result{
		bytes:  executable(code, target)
		target: target
	}
}

fn resolve_target(name string) !backend.Target {
	if name == '' {
		return backend.host() or { error('this platform has no backend: vcc emits ${target_names()}') }
	}
	return backend.lookup(name) or { error('unknown target ${name}: vcc emits ${target_names()}') }
}

fn target_names() string {
	mut names := []string{}
	for target in backend.targets() {
		names << target.name
	}
	return names.join(', ')
}

// exit_status folds the entry function's body down to the status the process
// exits with. Reporting into the caller's list rather than returning a message
// keeps one diagnostic per problem: the caller already knows where the function
// was written.
fn exit_status(decl ast.FnDecl, mut diagnostics []tokenize.Diagnostic) !u8 {
	if decl.ret != 'int' {
		diagnostics << problem(decl.line, decl.col,
			'unsupported: ${decl.name} returns ${decl.ret}, and only int is implemented')
		return error('unsupported return type')
	}
	stmts := reachable_statements(decl.body)
	if stmts.len != 1 || stmts[0].kind != .return_stmt {
		diagnostics << problem(decl.line, decl.col,
			'unsupported: the stub emits a body that is a single return of a constant, and ${decl.name} is not one')
		return error('unsupported body')
	}
	stmt := stmts[0]
	expr := stmt.expr or {
		diagnostics << problem(stmt.line, stmt.col,
			'unsupported: return without a value in a function that returns int')
		return error('return without a value')
	}
	value := fold(expr, mut diagnostics) or { return error('not a constant expression') }
	// A process status is the low eight bits of the value, which is what the
	// kernel keeps of it anyway.
	return u8(value & 0xff)
}

// reachable_statements drops the empty statements and unwraps a body that is a
// single block, so `int main() { { return 1; } }` has the same shape as
// `int main() { return 1; }`.
fn reachable_statements(body []ast.Stmt) []ast.Stmt {
	if body.len == 1 && body[0].kind == .block {
		return reachable_statements(body[0].body)
	}
	mut out := []ast.Stmt{}
	for stmt in body {
		if stmt.kind != .empty {
			out << stmt
		}
	}
	return out
}

// fold evaluates a constant expression. Signed arithmetic wraps, because that is
// what V's generated C is compiled with and what the C standard calls undefined
// but every C compiler on the machines this targets does anyway.
//
// The left spine of an operator chain is walked with a loop, and only genuinely
// nested expressions recurse. `1 + 1 + 1 ...` is one node deep in the grammar and
// thousands deep in the tree, so a recursive fold turns a long constant
// expression into a stack overflow: the benchmark harness found that at about
// three thousand terms, which is a size a generated program reaches without trying.
fn fold(expr ast.Expr, mut diagnostics []tokenize.Diagnostic) !i64 {
	return fold_at(expr, 0, mut diagnostics)
}

// max_fold_depth is the nesting the fold will follow. Parentheses are the only
// way to get deeper, and no real expression comes close to this, so anything past
// it is reported rather than allowed to run the stack out.
const max_fold_depth = 200

fn fold_at(expr ast.Expr, depth int, mut diagnostics []tokenize.Diagnostic) !i64 {
	if depth > max_fold_depth {
		diagnostics << problem(1, 1,
			'expression is nested more than ${max_fold_depth} levels deep, which the stub does not fold')
		return error('expression nested too deeply')
	}
	mut spine := []ast.Binary{}
	mut node := expr
	for node is ast.Binary {
		binary := node as ast.Binary
		spine << binary
		node = binary.left
	}
	mut value := fold_leaf(node, depth + 1, mut diagnostics)!
	for i := spine.len - 1; i >= 0; i-- {
		binary := spine[i]
		right := fold_at(binary.right, depth + 1, mut diagnostics)!
		value = apply_binary(binary, value, right, mut diagnostics)!
	}
	return value
}

fn fold_leaf(expr ast.Expr, depth int, mut diagnostics []tokenize.Diagnostic) !i64 {
	match expr {
		ast.IntLit {
			return expr.value
		}
		ast.Unary {
			operand := fold_at(expr.expr, depth + 1, mut diagnostics)!
			return match expr.op {
				'-' { wrap_sub(i64(0), operand) }
				'+' { operand }
				'!' {
					if operand == 0 {
						i64(1)
					} else {
						i64(0)
					}
				}
				'~' { (~operand) }
				else {
					diagnostics << problem(expr.line, expr.col,
						'unsupported unary operator ${expr.op}')
					return error('unsupported unary operator')
				}
			}
		}
		ast.Binary {
			return fold_at(expr, depth + 1, mut diagnostics)
		}
		ast.Ident {
			diagnostics << problem(expr.line, expr.col,
				'unsupported: ${expr.name} is not a constant, and the stub folds constant expressions only')
			return error('not a constant')
		}
		ast.Call {
			diagnostics << problem(expr.line, expr.col,
				'unsupported: the call to ${expr.name} cannot be folded; calls are not implemented')
			return error('call in a constant expression')
		}
	}
}

// apply_binary does the arithmetic for one operator, with the checks that keep a
// constant expression from silently holding a wrong value.
fn apply_binary(binary ast.Binary, left i64, right i64, mut diagnostics []tokenize.Diagnostic) !i64 {
	return match binary.op {
		'+' { wrap_add(left, right) }
		'-' { wrap_sub(left, right) }
		'*' { wrap_mul(left, right) }
		'/' {
			if right == 0 {
				diagnostics << problem(binary.line, binary.col,
					'division by zero in a constant expression')
				return error('division by zero')
			}
			left / right
		}
		'%' {
			if right == 0 {
				diagnostics << problem(binary.line, binary.col,
					'remainder by zero in a constant expression')
				return error('remainder by zero')
			}
			left % right
		}
		else {
			diagnostics << problem(binary.line, binary.col,
				'unsupported binary operator ${binary.op}')
			return error('unsupported binary operator')
		}
	}
}

fn problem(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
	}
}

// Wrapping arithmetic, spelled out rather than assumed. V 0.5.2 has no `+%`
// operators, and whether `+` traps on overflow depends on how the compiler that
// built this binary was invoked, so the fold goes through u64 where the wrap is
// what the machine does by definition.
fn wrap_add(a i64, b i64) i64 {
	return i64(u64(a) + u64(b))
}

fn wrap_sub(a i64, b i64) i64 {
	return i64(u64(a) - u64(b))
}

fn wrap_mul(a i64, b i64) i64 {
	return i64(u64(a) * u64(b))
}
