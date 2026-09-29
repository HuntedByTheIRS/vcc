module codegen

import ast
import backend
import tokenize

// Options is what the caller asks for. An empty target means the machine this
// binary runs on, and an empty entry means `main`.
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

// Fixup is a reference the code could not finish when it was written: a call to
// a function in the same file, a call to a function that lives in a library, or
// the address of a string. The instruction is in the text with four zero bytes
// where its displacement goes, and the layout fills them in. length is kept so
// that filling the reference in cannot quietly change the size of the code it
// sits in.
struct Fixup {
	start        int
	length       int
	kind         FixupKind
	name         string
	arg_position int
}

enum FixupKind {
	call_local   // a call to a function this translation unit defines
	call_import  // a call to a symbol the loader resolves out of a library
	take_address // the address of a string in the image
}

// Program is what one translation unit became: machine code, the strings it
// reads, and the references between them.
struct Program {
mut:
	text []u8
	// fixups are the references the layout has to fill in.
	fixups []Fixup
	// labels is where each function's code begins in text.
	labels map[string]int
	// defined is every function the file defines. A call is checked against it
	// before the library, so a call to a function whose body comes later in the
	// file binds to that function and not to a symbol of the same name.
	defined map[string]bool
	// imports are the library symbols the image needs, in the order they were
	// first called, so that the same input produces the same bytes every run.
	imports []string
	// string_blob is the read-only data: every distinct string literal with the
	// terminator a library function reads to, and strings is where each one
	// starts in it.
	string_blob []u8
	strings     map[string]int
}

// Emitter writes one translation unit into a Program. It owns statement
// emission and the constant folder, and it records what it cannot know: where
// the text will land, and what the loader will do once the program starts.
struct Emitter {
	target backend.Target
	entry  string
	unit   ast.TranslationUnit
mut:
	program     Program
	diagnostics []tokenize.Diagnostic
}

// emit turns a parsed translation unit into an executable image. Every function
// with a body is emitted and the entry function is the one the image starts in.
//
// A body is no longer required to be a single constant return: statements are
// emitted in order, so a function that calls a library function and then returns
// a constant is a program. The functions are linked dynamically, so a call to a
// name the file does not define is resolved out of the library the loader maps
// before the first instruction runs.
pub fn emit(unit ast.TranslationUnit, opts Options) Result {
	target := resolve_target(opts.target) or {
		return Result{
			diagnostics: [problem(1, 1, err.msg())]
		}
	}
	entry := if opts.entry == '' { 'main' } else { opts.entry }
	if entry_definition(unit, entry) == none {
		return Result{
			target:      target
			diagnostics: [problem(1, 1, 'no definition of ${entry} in this translation unit')]
		}
	}
	mut emitter := Emitter{
		target: target
		entry:  entry
		unit:   unit
	}
	image := emitter.build() or {
		return Result{
			target:      target
			diagnostics: emitter.diagnostics
		}
	}
	return Result{
		bytes:  image
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

// entry_definition finds the function the image starts in. The last definition
// of the name is the one a link would have taken, so it is the one that wins
// here too.
fn entry_definition(unit ast.TranslationUnit, entry string) ?ast.FnDecl {
	mut found := ?ast.FnDecl(none)
	for candidate in unit.decls {
		if candidate.name == entry && candidate.body.len > 0 {
			found = candidate
		}
	}
	return found
}

// build lays the whole program out: the entry point the kernel jumps to, then
// every function with a body, then the container that holds them.
fn (mut e Emitter) build() ![]u8 {
	// The names come first so that a call to a function defined further down the
	// file binds to it: where each one begins is settled as its body is emitted.
	for decl in e.unit.decls {
		if decl.body.len > 0 {
			e.program.defined[decl.name] = true
		}
	}
	e.emit_start()!
	for decl in e.unit.decls {
		if decl.body.len == 0 {
			continue
		}
		e.emit_function(decl)!
	}
	image := executable(e.program, e.target) or {
		e.diagnostics << problem(1, 1, 'internal: the image could not be laid out: ${err.msg()}')
		return error('cannot lay out the image')
	}
	return image
}

// emit_start writes the entry point the kernel jumps to. It is not the program's
// main: it calls it, keeps what it returned as the process status, and leaves
// through the library's exit, which is what flushes a buffered stream. A program
// that stopped through the exit syscall instead would print nothing whenever its
// output is a pipe or a file.
fn (mut e Emitter) emit_start() !void {
	status := e.target.arg_reg(0) or {
		e.diagnostics << problem(1, 1, '${e.target.name}: no register carries the first argument, so a process status has nowhere to go')
		return error('no status register')
	}
	result := e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(1, 1, '${e.target.name}: no register named ${e.target.return_reg} to hold a function result')
		return error('no result register')
	}
	e.reference(e.target.call_near(0), .call_local, e.entry, 0)
	e.append(e.target.move_register32(status, result)!)
	e.import_symbol('exit')
	e.reference(e.target.call_slot(0), .call_import, 'exit', 0)
	// The library's exit does not return. If it ever did, it would be a bug
	// somewhere else, and stopping here is better than running into the bytes
	// that follow.
	e.append(e.target.halt())
}

// emit_function writes one function: its frame, its statements, and a return of
// zero when the body can fall off the end without a return of its own. C says
// the entry function does that, and every function here needs it, because
// falling through would otherwise hand the caller whatever the last call left in
// the result register.
fn (mut e Emitter) emit_function(decl ast.FnDecl) !void {
	if decl.ret != 'int' {
		e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, and only int is implemented')
		return error('unsupported return type')
	}
	// The prologue is what a call to this function jumps to, so the label goes
	// in front of it.
	e.program.labels[decl.name] = e.program.text.len
	e.append(e.target.frame_prologue())
	returned := e.emit_statements(decl.body)!
	if returned {
		return
	}
	result := e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(decl.line, decl.col, '${e.target.name}: no register named ${e.target.return_reg} to hold a function result')
		return error('no result register')
	}
	e.append(e.target.move_immediate32(result, 0)!)
	e.append(e.target.frame_epilogue())
}

// emit_statements writes a list of statements in order and answers whether any
// of them returned. Statements after a return are still emitted and never run,
// which is what a compiler does with unreachable code it does not diagnose; the
// answer is what tells a function whether it can fall off the end.
fn (mut e Emitter) emit_statements(stmts []ast.Stmt) !bool {
	mut returned := false
	for stmt in stmts {
		match stmt.kind {
			.empty {}
			.block {
				if e.emit_statements(stmt.body)! {
					returned = true
				}
			}
			.return_stmt {
				e.emit_return(stmt)!
				returned = true
			}
			.expr_stmt {
				e.emit_expression_statement(stmt)!
			}
		}
	}
	return returned
}

// emit_return writes a return of a folded constant. A return expression that is
// not a constant is reported by the folder, which knows which part of it is not
// one.
fn (mut e Emitter) emit_return(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: return without a value in a function that returns int')
		return error('return without a value')
	}
	result := e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(stmt.line, stmt.col, '${e.target.name}: no register named ${e.target.return_reg} to hold a function result')
		return error('no result register')
	}
	value := e.fold(expr) or { return error('not a constant expression') }
	// The value is loaded at the machine's word for an int; what a process exits
	// with is the low eight bits of it, which the library's exit takes care of
	// when the entry function's value becomes the status.
	e.append(e.target.move_immediate32(result, u32(value))!)
	e.append(e.target.frame_epilogue())
}

fn (mut e Emitter) emit_expression_statement(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an expression statement with no expression')
		return error('empty expression statement')
	}
	if expr is ast.Call {
		e.emit_call(expr)!
		return
	}
	e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an expression statement is emitted when it is a call, and this one is not a call')
	return error('not a call')
}

// emit_call writes one call: each argument into the register the machine takes
// that position in, then the call itself. A name the file defines is called by
// its distance in the code, so a call to a function in the same translation unit
// binds to that definition; every other name is a symbol the loader resolves
// before the program starts.
fn (mut e Emitter) emit_call(call ast.Call) !void {
	for i, arg in call.args {
		register := e.target.arg_reg(i) or {
			e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} has more than ${i} arguments, and the machine has no register for another one')
			return error('too many arguments')
		}
		if arg is ast.StrLit {
			e.intern(arg.value)
			e.reference(e.target.address_of(register, 0), .take_address, arg.value, i)
			continue
		}
		if arg is ast.Call {
			e.diagnostics << problem(arg.line, arg.col, 'unsupported: the call to ${arg.name} is an argument of another call, which is not implemented yet')
			return error('nested call')
		}
		value := e.fold(arg) or { return error('argument is not a constant') }
		e.append(e.target.move_immediate32(register, u32(value))!)
	}
	if call.name in e.program.defined {
		e.reference(e.target.call_near(0), .call_local, call.name, 0)
		return
	}
	e.import_symbol(call.name)
	// A library function this compiler has no prototype for may be variadic, and
	// the machine's convention wants the number of vector arguments in the low
	// byte of the result register before a call like that. Zero is what a call
	// with no vector arguments says, and printf reads it.
	result := e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(call.line, call.col, '${e.target.name}: no register named ${e.target.return_reg} for a call to count its vector arguments in')
		return error('no result register')
	}
	e.append(e.target.move_immediate32(result, 0)!)
	e.reference(e.target.call_slot(0), .call_import, call.name, 0)
}

// import_symbol records a library symbol the image needs, once. The order the
// symbols are first called in is the order they appear in the image, so the same
// source produces the same bytes.
fn (mut e Emitter) import_symbol(name string) {
	if name !in e.program.imports {
		e.program.imports << name
	}
}

// intern puts a string literal into the image's read-only data once. Two
// literals with the same bytes are one entry, which is what C says they are.
fn (mut e Emitter) intern(text string) {
	if text in e.program.strings {
		return
	}
	e.program.strings[text] = e.program.string_blob.len
	e.program.string_blob << text.bytes()
	e.program.string_blob << u8(0) // the terminator a library function reads to
}

// append puts finished instruction bytes into the text.
fn (mut e Emitter) append(bytes []u8) {
	e.program.text << bytes
}

// reference appends an instruction whose displacement is not known yet and
// records what it points at and how long it is.
fn (mut e Emitter) reference(bytes []u8, kind FixupKind, name string, arg_position int) {
	start := e.program.text.len
	e.program.text << bytes
	e.program.fixups << Fixup{
		start:        start
		length:       bytes.len
		kind:         kind
		name:         name
		arg_position: arg_position
	}
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
fn (mut e Emitter) fold(expr ast.Expr) !i64 {
	return e.fold_at(expr, 0)
}

// max_fold_depth is the nesting the fold will follow. Parentheses are the only
// way to get deeper, and no real expression comes close to this, so anything past
// it is reported rather than allowed to run the stack out.
const max_fold_depth = 200

fn (mut e Emitter) fold_at(expr ast.Expr, depth int) !i64 {
	if depth > max_fold_depth {
		e.diagnostics << problem(1, 1, 'expression is nested more than ${max_fold_depth} levels deep, which the stub does not fold')
		return error('expression nested too deeply')
	}
	mut spine := []ast.Binary{}
	mut node := expr
	for node is ast.Binary {
		binary := node as ast.Binary
		spine << binary
		node = binary.left
	}
	mut value := e.fold_leaf(node, depth + 1)!
	for i := spine.len - 1; i >= 0; i-- {
		binary := spine[i]
		right := e.fold_at(binary.right, depth + 1)!
		value = e.apply_binary(binary, value, right)!
	}
	return value
}

fn (mut e Emitter) fold_leaf(expr ast.Expr, depth int) !i64 {
	match expr {
		ast.IntLit {
			return expr.value
		}
		ast.Unary {
			operand := e.fold_at(expr.expr, depth + 1)!
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
					e.diagnostics << problem(expr.line, expr.col, 'unsupported unary operator ${expr.op}')
					return error('unsupported unary operator')
				}
			}
		}
		ast.Binary {
			return e.fold_at(expr, depth + 1)
		}
		ast.Ident {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is not a constant, and the stub folds constant expressions only')
			return error('not a constant')
		}
		ast.StrLit {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: a string literal is not a constant, and the stub folds constant expressions only')
			return error('not a constant')
		}
		ast.Call {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: the call to ${expr.name} cannot be folded, because a call is not a constant expression')
			return error('call in a constant expression')
		}
	}
}

// apply_binary does the arithmetic for one operator, with the checks that keep a
// constant expression from silently holding a wrong value.
fn (mut e Emitter) apply_binary(binary ast.Binary, left i64, right i64) !i64 {
	return match binary.op {
		'+' { wrap_add(left, right) }
		'-' { wrap_sub(left, right) }
		'*' { wrap_mul(left, right) }
		'/' {
			if right == 0 {
				e.diagnostics << problem(binary.line, binary.col, 'division by zero in a constant expression')
				return error('division by zero')
			}
			left / right
		}
		'%' {
			if right == 0 {
				e.diagnostics << problem(binary.line, binary.col, 'remainder by zero in a constant expression')
				return error('remainder by zero')
			}
			left % right
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported binary operator ${binary.op}')
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
