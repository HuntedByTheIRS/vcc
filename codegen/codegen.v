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
// a function in the same file, a call to a function that lives in a library, the
// address of a string, or a jump to a place in the function being emitted. The
// instruction is in the text with four zero bytes where its displacement goes,
// and the layout fills them in. length is kept so that filling the reference in
// cannot quietly change the size of the code it sits in, and register is the
// register the instruction reads its answer into, for the references that have
// one.
struct Fixup {
	start    int
	length   int
	kind     FixupKind
	name     string
	register string
}

enum FixupKind {
	call_local     // a call to a function this translation unit defines
	call_import    // a call to a symbol the loader resolves out of a library
	take_address   // the address of a string in the image
	jump_local     // a jump to a label inside the function being emitted
	branch_zero    // the same jump, taken when the value last tested was zero
	branch_nonzero // and when it was not
}

// Program is what one translation unit became: machine code, the strings it
// reads, and the references between them.
struct Program {
mut:
	text []u8
	// fixups are the references the layout has to fill in.
	fixups []Fixup
	// labels is where each function's code begins in text, and where every jump
	// label inside one landed.
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

// Slot is where a local or a parameter lives: a displacement from the frame
// pointer, and the width of the value in it. The width is what keeps an int and
// a pointer apart, since a value read or written at the other width is a value
// from a neighbouring slot rather than a wrong answer.
struct Slot {
	offset int
	width  int
}

// LoopLabels are the two places a loop's body can leave by: where the loop ends,
// for a break, and where it goes round again, for a continue.
struct LoopLabels {
	break_to    string
	continue_to string
}

// Emitter writes one translation unit into a Program. It owns statement and
// expression emission and the constant walk, and it records what it cannot know:
// where the text will land, and what the loader will do once the program starts.
struct Emitter {
	target backend.Target
	entry  string
	unit   ast.TranslationUnit
mut:
	program     Program
	diagnostics []tokenize.Diagnostic
	// signatures is the width of each parameter of every function the file
	// defines, so that a call in the file hands each argument over at the width
	// the definition expects.
	signatures map[string][]int
	// scopes is the blocks being emitted, innermost last. A name is visible in
	// the block it was declared in and the ones inside it, which is where a
	// declaration gets its slot and its width from.
	scopes []map[string]Slot
	// frame_used is how many bytes of frame the function being emitted has
	// claimed: its parameters, its locals and the slots an expression needs.
	frame_used int
	// values is the scratch area, one slot per level of expression nesting,
	// where a half-finished value waits while the other half is computed.
	values []Slot
	// loops is the loops being emitted, innermost last, for break and continue.
	loops []LoopLabels
	// next_label numbers the jump labels. It runs across the whole file rather
	// than restarting at each function, because every label of every function
	// lives in the same table.
	next_label int
}

// A frame is a multiple of sixteen so that every call made from the body starts
// on the boundary the machine's convention wants: the prologue's push and this
// subtraction are what put the stack pointer there, and both are needed for a
// called function to find the stack as it expects.
const frame_alignment = 16

// max_emit_depth is the nesting an expression may have before it is reported.
// Parentheses are the only way to get deeper in the grammar, and a tree past
// this is a tree that would take the stack out rather than one a program writes.
const max_emit_depth = 200

// emit turns a parsed translation unit into an executable image. Every function
// with a body is emitted and the entry function is the one the image starts in.
//
// A function body is a frame with storage in it: its parameters and its locals
// live at fixed displacements from the frame pointer, expressions compute values
// in registers and keep half-finished ones in the frame, and branches and loops
// are jumps between labels. The functions are linked dynamically, so a call to a
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
	// A diagnostic anywhere means the translation unit was not emitted, so the
	// image goes away with it. A stage that reports something and returns an
	// image anyway would otherwise hand the caller a program with a hole in it
	// and nothing that says so.
	if emitter.diagnostics.len > 0 {
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
	// The names and the parameter widths come first so that a call binds to a
	// definition wherever in the file it is written. The width is the one the
	// definition gives the parameter, which is what a call in the same file has
	// to hand over; a definition with a parameter this back end cannot size is
	// left out of the table, because its own emission is where that is reported.
	for decl in e.unit.decls {
		if decl.body.len > 0 {
			e.program.defined[decl.name] = true
			mut widths := []int{}
			mut sized := true
			for param in decl.params {
				if width := e.type_width(param.typ) {
					widths << width
				} else {
					sized = false
				}
			}
			if sized {
				e.signatures[decl.name] = widths
			}
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
	// The stack is put on the boundary a call wants before anything is called.
	// A process starts on whatever stack the kernel left, and every frame below
	// this point assumes the convention holds, so the one instruction is what
	// makes that true rather than lucky.
	e.append(e.target.align_stack())
	status := e.target.arg_reg(0) or {
		e.diagnostics << problem(1, 1, '${e.target.name}: no register carries the first argument, so a process status has nowhere to go')
		return error('no status register')
	}
	result := e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(1, 1, '${e.target.name}: no register named ${e.target.return_reg} to hold a function result')
		return error('no result register')
	}
	e.reference(e.target.call_near(0), .call_local, e.entry, '')
	e.append(e.target.move_register32(status, result)!)
	e.import_symbol('exit')
	e.reference(e.target.call_slot(0), .call_import, 'exit', '')
	// The library's exit does not return. If it ever did, it would be a bug
	// somewhere else, and stopping here is better than running into the bytes
	// that follow.
	e.append(e.target.halt())
}

// emit_function writes one function: its frame, its parameters into their slots,
// its statements, and a return of zero when the body can fall off the end
// without a return of its own. C says the entry function does that, and every
// function here needs it, because falling through would otherwise hand the
// caller whatever the last call left in the result register.
fn (mut e Emitter) emit_function(decl ast.FnDecl) !void {
	if decl.ret != 'int' {
		e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, and only int is implemented')
		return error('unsupported return type')
	}
	// The prologue is what a call to this function jumps to, so the label goes
	// in front of it.
	e.program.labels[decl.name] = e.program.text.len
	e.append(e.target.frame_prologue())
	// The frame is opened with a size of zero and filled in once the body has
	// been walked: the size is the sum of what the body asked for, and the body
	// is exactly what is about to be emitted. The immediate is four bytes wide
	// whatever the size turns out to be, so filling it in cannot move anything
	// that was written after it.
	frame_at := e.program.text.len + e.target.frame_immediate_offset()
	e.append(e.target.frame_reserve(0))
	e.push_scope()
	// The parameters arrive in the machine's argument registers. They are stored
	// into the frame on the way in, so a parameter is read exactly the way a
	// local is, and the register is free for the expression that follows.
	for i, param in decl.params {
		slot := e.declare(param.name, param.typ, param.line, param.col)!
		register := e.target.arg_reg(i) or {
			e.diagnostics << problem(param.line, param.col, 'unsupported: ${decl.name} takes more than ${i} parameters, and the machine passes only ${i} of them in registers')
			return error('too many parameters')
		}
		e.store_register(slot, register, param.line, param.col)!
	}
	returned := e.emit_statements(decl.body)!
	if !returned {
		result := e.accumulator(decl.line, decl.col)!
		e.append(e.target.move_immediate32(result, 0)!)
		e.append(e.target.frame_epilogue())
	}
	e.pop_scope()
	// The frame the body asked for is rounded up to the alignment a call needs.
	// The prologue's push leaves the stack a multiple of sixteen at the entry,
	// and this subtraction has to keep it that way or a call inside the body
	// reaches a function whose own frame is off by the remainder.
	e.fill_frame(frame_at, align(e.frame_used, frame_alignment))
	// The next function starts with a frame and a scratch area of its own. The
	// labels are the one thing that carries over: they are numbered across the
	// whole file, because jumps of every function share one table.
	e.frame_used = 0
	e.values = []Slot{}
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
				// A block is a scope: what it declares is visible inside it and
				// gone after it, so two blocks can each declare a name.
				e.push_scope()
				block_returned := e.emit_statements(stmt.body)!
				e.pop_scope()
				if block_returned {
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
			.var_decl {
				e.emit_var_decl(stmt)!
			}
			.assign {
				e.emit_assign(stmt)!
			}
			.if_stmt {
				if e.emit_if(stmt)! {
					returned = true
				}
			}
			.while_stmt {
				e.emit_while(stmt)!
			}
			.break_stmt {
				e.emit_jump_out(stmt, true)!
			}
			.continue_stmt {
				e.emit_jump_out(stmt, false)!
			}
		}
	}
	return returned
}

// emit_return writes the value into the register a function's results arrive in
// and closes the frame. Every return leaves the same way, whatever the function
// did before it.
fn (mut e Emitter) emit_return(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: return without a value in a function that returns int')
		return error('return without a value')
	}
	e.emit_expr(expr)!
	e.append(e.target.frame_epilogue())
}

// emit_var_decl gives a declaration its slot in the frame and, when it has one,
// writes the initializer into it. A declaration without an initializer is
// storage and nothing else, which is what C says it is: the slot is there for
// whatever the function writes into it next.
fn (mut e Emitter) emit_var_decl(stmt ast.Stmt) !void {
	slot := e.declare(stmt.decl_name, stmt.decl_type, stmt.line, stmt.col)!
	init := stmt.init or { return }
	e.emit_expr(init)!
	e.store_value(slot, init, stmt.line, stmt.col)!
}

// emit_assign evaluates the value and writes it into the slot the name lives in.
// The name has to be in scope: an assignment to a name that was never declared
// has nowhere to go, and a guessed slot would be someone else's variable.
fn (mut e Emitter) emit_assign(stmt ast.Stmt) !void {
	target := e.lookup(stmt.target) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned to, and no local of that name is in scope')
		return error('unknown assignment target')
	}
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned without a value')
		return error('assignment without a value')
	}
	e.emit_expr(expr)!
	e.store_value(target, expr, stmt.line, stmt.col)!
}

fn (mut e Emitter) emit_expression_statement(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an expression statement with no expression')
		return error('empty expression statement')
	}
	if expr is ast.Call {
		e.emit_call(expr, 0)!
		return
	}
	e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an expression statement is emitted when it is a call, and this one is not a call')
	return error('not a call')
}

// emit_if writes a condition and its two branches. The condition is evaluated
// and tested, the false case jumps past the true body, and when there is an else
// the true body jumps past it at the end. Each body is a block of its own, so
// what one of them declares is not visible in the other.
//
// The answer is whether every way out of the statement returns, which a function
// needs to know before it puts a return of zero behind it: an if whose two
// bodies both return has no way through.
fn (mut e Emitter) emit_if(stmt ast.Stmt) !bool {
	cond := stmt.cond or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an if without a condition')
		return error('if without a condition')
	}
	e.emit_expr(cond)!
	e.emit_test(stmt.line, stmt.col)!
	else_label := e.label()
	e.branch(.branch_zero, else_label, stmt.line, stmt.col)!
	then_returned := e.emit_branch_body(stmt.then_body)!
	if stmt.else_body.len > 0 {
		end_label := e.label()
		e.jump(end_label)!
		e.place(else_label)
		else_returned := e.emit_branch_body(stmt.else_body)!
		e.place(end_label)
		return then_returned && else_returned
	}
	e.place(else_label)
	return false
}

// emit_while writes a loop: the condition at the top, the body, and a jump back
// to the condition. A for loop arrives as this shape, with its step as the last
// statement of the body, so there is nothing here that knows about one.
//
// A continue goes back to the condition, which is where a while goes round; a for
// loop whose step is at the end of the body is the desugaring's business, and
// this is the shape it desugared into.
fn (mut e Emitter) emit_while(stmt ast.Stmt) !void {
	cond := stmt.cond or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a while without a condition')
		return error('while without a condition')
	}
	top := e.label()
	end := e.label()
	// A continue goes to the step, which is the third part of a for and nothing
	// at all in a while: with no step written it lands on the test, which is
	// what going round again means there. Emitting the step at the end of the
	// body instead would read the same and be wrong — every continue above it
	// would jump past the statement that advances the loop.
	step := e.label()
	continue_to := if stmt.step.len > 0 { step } else { top }
	e.place(top)
	e.emit_expr(cond)!
	e.emit_test(stmt.line, stmt.col)!
	e.branch(.branch_zero, end, stmt.line, stmt.col)!
	// The body can leave by jumping to either end of the loop, so both labels
	// are known while it is emitted.
	e.loops << LoopLabels{
		break_to:    end
		continue_to: continue_to
	}
	e.emit_branch_body(stmt.body)!
	e.loops.pop()
	if stmt.step.len > 0 {
		// The step runs in the loop's own scope, which is where C puts it: the
		// names a for declares in its head are the names its step writes to.
		e.place(step)
		_ := e.emit_statements(stmt.step)!
	}
	e.jump(top)!
	e.place(end)
}

// emit_branch_body writes the body of a branch or a loop as a block of its own,
// which is what its braces were: the names it declares stay inside it.
fn (mut e Emitter) emit_branch_body(body []ast.Stmt) !bool {
	e.push_scope()
	returned := e.emit_statements(body)!
	e.pop_scope()
	return returned
}

// emit_jump_out writes a break or a continue, which are the same jump to two
// different labels of the innermost loop. A loop is what either is about, so one
// outside a loop is reported rather than emitted as a jump to nowhere.
fn (mut e Emitter) emit_jump_out(stmt ast.Stmt, is_break bool) !void {
	if e.loops.len == 0 {
		word := if is_break { 'break' } else { 'continue' }
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${word} outside a loop')
		return error('${word} outside a loop')
	}
	loop := e.loops[e.loops.len - 1]
	name := if is_break { loop.break_to } else { loop.continue_to }
	e.jump(name)!
}

// declare gives a name a slot and makes it visible in the block being emitted.
// The width is the width of the type as it was written: an int is four bytes and
// a pointer is the machine's word. A type that is neither is reported where it
// was written, because storing it at a width that happens to fit would make
// every value it touches silently wrong.
fn (mut e Emitter) declare(name string, written string, line int, col int) !Slot {
	if e.scopes.len > 0 {
		if name in e.scopes[e.scopes.len - 1] {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is declared twice in the same block')
			return error('redeclared')
		}
	}
	width := e.type_width(written) or {
		e.diagnostics << problem(line, col, 'unsupported: ${name} is declared ${written}, and this back end stores ints and pointers only')
		return error('unsupported type')
	}
	slot := e.reserve(width)
	e.scopes[e.scopes.len - 1][name] = slot
	return slot
}

// type_width is the width of a value of a type as the source wrote it. An int is
// four bytes; a pointer is the machine's word, which is what makes `char *` and
// `char **` read and write the same way. Everything else is a type this back end
// has no instruction for.
fn (e Emitter) type_width(written string) ?int {
	if written == 'int' {
		return 4
	}
	if written.contains('*') {
		return e.target.word_size
	}
	return none
}

// reserve claims a place in the frame for one value. Offsets count down from the
// frame pointer, and every slot starts on the machine's word so that a four-byte
// and an eight-byte value can sit next to each other without an access that
// straddles them.
fn (mut e Emitter) reserve(width int) Slot {
	e.frame_used = align(e.frame_used + width, e.target.word_size)
	return Slot{
		offset: -e.frame_used
		width:  width
	}
}

// value_slot is the frame slot one level of expression nesting keeps a
// half-finished value in. The levels are what tell the slots apart, so the slots
// are the same for every statement and a function ends up with as many as its
// deepest expression used. The slot is always the machine's word wide: what
// waits in it can be a pointer, and a four-byte slot would drop the half of it
// that matters.
fn (mut e Emitter) value_slot(depth int) Slot {
	for e.values.len <= depth {
		e.values << e.reserve(e.target.word_size)
	}
	return e.values[depth]
}

// push_scope opens a block and pop_scope closes it. Names are found in the
// blocks being emitted, innermost first, so a declaration inside a block
// shadows one outside it and does not outlive it.
fn (mut e Emitter) push_scope() {
	e.scopes << map[string]Slot{}
}

fn (mut e Emitter) pop_scope() {
	e.scopes.pop()
}

fn (e Emitter) lookup(name string) ?Slot {
	for i := e.scopes.len - 1; i >= 0; i-- {
		if slot := e.scopes[i][name] {
			return slot
		}
	}
	return none
}

// label is a name for a jump inside a function. The table that holds them holds
// function names too, and a C identifier cannot have a dot in it, so a label
// written this way cannot collide with a function. The number runs across the
// whole file because every function's labels land in that one table.
fn (mut e Emitter) label() string {
	name := '.L${e.next_label}'
	e.next_label++
	return name
}

// place settles where a label is: everything emitted from here on is behind it.
fn (mut e Emitter) place(name string) {
	e.program.labels[name] = e.program.text.len
}

// jump writes a jump to a label that has not been placed yet; the layout fills
// the distance in once every label of the file is settled.
fn (mut e Emitter) jump(name string) !void {
	e.reference(e.target.jump(0), .jump_local, name, '')
}

// branch is the jump a condition takes when it comes out zero or not zero.
fn (mut e Emitter) branch(kind FixupKind, name string, line int, col int) !void {
	bytes := match kind {
		.branch_zero { e.target.jump_if_zero(0) }
		.branch_nonzero { e.target.jump_if_not_zero(0) }
		else {
			e.diagnostics << problem(line, col, 'internal: ${kind} is not a conditional branch')
			return error('not a conditional branch')
		}
	}
	e.reference(bytes, kind, name, '')
}

// emit_test compares the accumulator with zero, which is all a branch needs told:
// the conditional jumps read the zero flag the comparison leaves.
fn (mut e Emitter) emit_test(line int, col int) !void {
	register := e.accumulator(line, col)!
	e.append(e.target.test(register)!)
}

// frame_pointer is the register the frame is at. Every access to a local goes
// through it, so a machine whose table has none cannot hold a frame at all, and
// that is said rather than worked around.
fn (mut e Emitter) frame_pointer(line int, col int) !backend.Register {
	return e.target.frame_pointer() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no frame register, and a local has nowhere to live without one")
		return error('no frame register')
	}
}

// accumulator is the register an expression leaves its value in, which is the
// register a function leaves its result in as well: one convention and not two,
// so a value computed by a call and a value a function returns arrive in the same
// place and nothing has to be moved between them.
fn (mut e Emitter) accumulator(line int, col int) !backend.Register {
	return e.target.reg(e.target.return_reg) or {
		e.diagnostics << problem(line, col, '${e.target.name}: no register named ${e.target.return_reg} to hold a value')
		return error('no result register')
	}
}

// scratch is the register the right-hand value of an operation waits in while
// the left-hand one is in the accumulator.
fn (mut e Emitter) scratch(line int, col int) !backend.Register {
	return e.target.scratch() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no scratch register for the second half of an operation")
		return error('no scratch register')
	}
}

// store_register writes a register into a slot at the slot's width.
fn (mut e Emitter) store_register(slot Slot, register backend.Register, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.store_slot(base, slot.offset, register, slot.width)!)
}

// store_accumulator writes the accumulator into a slot, at the slot's width.
fn (mut e Emitter) store_accumulator(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.store_register(slot, register, line, col)!
}

// load_accumulator reads a slot into the accumulator, at the slot's width.
fn (mut e Emitter) load_accumulator(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_slot(base, slot.offset, register, slot.width)!)
}

// load_argument reads one argument slot into the register that carries that
// position, at the width the argument is passed at.
fn (mut e Emitter) load_argument(slot Slot, register backend.Register, width int, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_slot(base, slot.offset, register, width)!)
}

// store_value writes the accumulator into a slot, after checking that the value
// is one the slot can hold. A constant is written at the width of the slot,
// because a constant is the one value that says nothing about its own width
// (`char *p = 0` is a zero of pointer width). Any other value has to have the
// slot's width already: storing a pointer in four bytes or an int in eight is a
// wrong value rather than a narrow one.
fn (mut e Emitter) store_value(slot Slot, expr ast.Expr, line int, col int) !void {
	if e.constant(expr) == none {
		width := e.width_of(expr) or {
			e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
			return error('unknown width')
		}
		if width != slot.width {
			e.diagnostics << problem(line, col, 'unsupported: a value of ${width} bytes is stored into a slot of ${slot.width}')
			return error('width mismatch')
		}
	}
	e.store_accumulator(slot, line, col)!
}

// fill_frame writes the size the body asked for into the subtraction that opened
// the frame. Both are settled by the time it runs, and the immediate is four
// bytes wide whatever the size is, so the code after it does not move.
fn (mut e Emitter) fill_frame(at int, size int) {
	value := u32(size)
	for i in 0 .. 4 {
		e.program.text[at + i] = u8((value >> (8 * i)) & 0xff)
	}
}

// emit_expr writes an expression and leaves its value in the accumulator.
//
// A constant expression is emitted as the one instruction it always was, which
// is what the constant walk below is for: a program written in constants, like
// `return 6 * 7`, produces the same bytes it did before there was a frame.
fn (mut e Emitter) emit_expr(expr ast.Expr) !void {
	return e.emit_expr_at(expr, 0)
}

fn (mut e Emitter) emit_expr_at(expr ast.Expr, depth int) !void {
	if depth > max_emit_depth {
		e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: the expression is nested more than ${max_emit_depth} levels deep')
		return error('expression nested too deeply')
	}
	if value := e.constant(expr) {
		register := e.accumulator(expr_line(expr), expr_col(expr))!
		e.append(e.target.move_immediate32(register, u32(value))!)
		return
	}
	match expr {
		ast.IntLit {
			// An integer literal is a constant, so the walk above has already
			// answered for it; this is the same answer for a reader who wonders.
			register := e.accumulator(expr.line, expr.col)!
			e.append(e.target.move_immediate32(register, u32(expr.value))!)
		}
		ast.Ident {
			slot := e.lookup(expr.name) or {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is not a constant and is not a local of this function')
				return error('unknown name')
			}
			e.load_accumulator(slot, expr.line, expr.col)!
		}
		ast.StrLit {
			// A string is the address of its bytes: the image holds the bytes
			// and the instruction says where they landed.
			e.intern(expr.value)
			register := e.accumulator(expr.line, expr.col)!
			e.reference(e.target.address_of(register, 0), .take_address, expr.value, register.name)
		}
		ast.Unary {
			e.emit_unary(expr, depth)!
		}
		ast.Binary {
			e.emit_binary(expr, depth)!
		}
		ast.Call {
			// A call is emitted where its result is discarded, which is the
			// statement form. A call whose value is read is the shape the -O
			// levels exist for: the optimizer's builtin table is what turns a
			// call it knows into the value, and one it does not know is reported
			// here rather than handed a value that only looks like the answer.
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: the call to ${expr.name} is used as a value, and a call is emitted only where its result is discarded')
			return error('call used as a value')
		}
	}
}

// emit_unary writes the operators that take one value: the sign change, the
// bitwise complement, and the logical not, which is a comparison with zero. The
// unary plus is the one that computes nothing, since the value is already where
// it belongs.
fn (mut e Emitter) emit_unary(unary ast.Unary, depth int) !void {
	if width := e.width_of(unary.expr) {
		if width != 4 && unary.op != '+' {
			e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} takes an int, and this one is a pointer')
			return error('non-int operand')
		}
	}
	e.emit_expr_at(unary.expr, depth + 1)!
	register := e.accumulator(unary.line, unary.col)!
	match unary.op {
		'+' {}
		'-' {
			e.append(e.target.negate(register)!)
		}
		'~' {
			e.append(e.target.complement(register)!)
		}
		'!' {
			e.append(e.target.logical_not(register)!)
		}
		else {
			e.diagnostics << problem(unary.line, unary.col, 'unsupported unary operator ${unary.op}')
			return error('unsupported unary operator')
		}
	}
}

// emit_binary writes a binary operation. The left spine of an operator chain is
// walked with a loop and only genuinely nested expressions recurse, for the
// reason the constant walk does it: `a + b + c ...` is one node deep in the
// grammar and thousands deep in the tree, and a call per term would take the
// stack out on input a generator writes.
//
// The two short-circuit operators are not that shape: which side is computed
// depends on the other one, so they are written as a branch.
fn (mut e Emitter) emit_binary(binary ast.Binary, depth int) !void {
	if binary.op == '&&' || binary.op == '||' {
		return e.emit_short_circuit(binary, depth)
	}
	mut spine := []ast.Binary{}
	mut node := ast.Expr(binary)
	for node is ast.Binary {
		step := node as ast.Binary
		if step.op == '&&' || step.op == '||' {
			break
		}
		e.check_int_operands(step)!
		spine << step
		node = step.left
	}
	e.emit_expr_at(node, depth + 1)!
	for i := spine.len - 1; i >= 0; i-- {
		step := spine[i]
		if step.op == '/' || step.op == '%' {
			if divisor := e.constant(step.right) {
				if divisor == 0 {
					e.diagnostics << problem(step.line, step.col, 'division by zero')
					return error('division by zero')
				}
			}
		}
		// The left value waits in the frame while the right one is computed: the
		// right side can call a function, and a call is free to use the
		// accumulator and the scratch register both. The slot is at this level of
		// nesting, and everything the right side computes lands above it.
		slot := e.value_slot(depth)
		e.store_accumulator(slot, step.line, step.col)!
		e.emit_expr_at(step.right, depth + 1)!
		e.move_to_scratch(step.line, step.col)!
		e.load_accumulator(slot, step.line, step.col)!
		e.apply_binary(step)!
	}
}

// check_int_operands reports an operand that is not an int. The operators
// emitted here compute with four-byte values; a pointer on either side is a
// different operation, an address plus a distance or two addresses compared, and
// computing it at the width of whatever the other side was would be a wrong
// program rather than a wrong answer.
fn (mut e Emitter) check_int_operands(binary ast.Binary) !void {
	for operand in [binary.left, binary.right] {
		if width := e.width_of(operand) {
			if width != 4 {
				// Eight bytes is the width of a pointer and the only other width
				// this back end has, so the diagnostic can say what it is.
				e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} takes int operands, and this one is a pointer')
				return error('non-int operand')
			}
		}
	}
}

// apply_binary does the operation the tree asked for, with the left value in the
// accumulator and the right one in the scratch register, and leaves the answer in
// the accumulator.
fn (mut e Emitter) apply_binary(binary ast.Binary) !void {
	result := e.accumulator(binary.line, binary.col)!
	other := e.scratch(binary.line, binary.col)!
	match binary.op {
		'+' {
			e.append(e.target.add(result, other)!)
		}
		'-' {
			e.append(e.target.subtract(result, other)!)
		}
		'*' {
			e.append(e.target.multiply(result, other)!)
		}
		'/' {
			// A division leaves the quotient in the accumulator and what it did
			// not divide in the register above, which is where the two operators
			// read their answers from.
			e.append(e.target.divide(other)!)
		}
		'%' {
			remainder := e.target.remainder() or {
				e.diagnostics << problem(binary.line, binary.col, "${e.target.name}: the machine's table has no register for a remainder to land in")
				return error('no remainder register')
			}
			e.append(e.target.divide(other)!)
			e.append(e.target.move_register32(result, remainder)!)
		}
		'==', '!=', '<', '>', '<=', '>=' {
			e.append(e.target.compare(binary.op, result, other)!)
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported binary operator ${binary.op}')
			return error('unsupported binary operator')
		}
	}
}

// emit_short_circuit writes && and ||, where the left side decides whether the
// right side is evaluated at all, which is what the language promises and what
// the machine gets for free: a jump skips over the side that is not needed, and
// the answer as a value of int width is written on both ways out.
fn (mut e Emitter) emit_short_circuit(binary ast.Binary, depth int) !void {
	e.check_int_operands(binary)!
	result := e.accumulator(binary.line, binary.col)!
	settles := e.label()
	end := e.label()
	is_and := binary.op == '&&'
	// The jump the left side takes when it has already settled the answer: out
	// of an and when it is false, out of an or when it is true.
	e.emit_expr_at(binary.left, depth + 1)!
	e.emit_test(binary.line, binary.col)!
	if is_and {
		e.branch(.branch_zero, settles, binary.line, binary.col)!
	} else {
		e.branch(.branch_nonzero, settles, binary.line, binary.col)!
	}
	// The left side did not settle it, so the right side is the answer.
	e.emit_expr_at(binary.right, depth + 1)!
	e.emit_test(binary.line, binary.col)!
	if is_and {
		e.branch(.branch_zero, settles, binary.line, binary.col)!
	} else {
		e.branch(.branch_nonzero, settles, binary.line, binary.col)!
	}
	e.append(e.target.move_immediate32(result, if is_and { u32(1) } else { u32(0) })!)
	e.jump(end)!
	e.place(settles)
	e.append(e.target.move_immediate32(result, if is_and { u32(0) } else { u32(1) })!)
	e.place(end)
}

// move_to_scratch puts the accumulator into the scratch register, which is where
// the operation that is about to be applied expects the right-hand value.
fn (mut e Emitter) move_to_scratch(line int, col int) !void {
	result := e.accumulator(line, col)!
	other := e.scratch(line, col)!
	e.append(e.target.move_register32(other, result)!)
}

// width_of is the width of the value an expression has, four bytes for an int
// and the machine's word for a pointer. It is what keeps an int and a pointer
// apart where the machine would otherwise take one for the other, and none is
// the honest answer for an expression this back end cannot size.
fn (e Emitter) width_of(expr ast.Expr) ?int {
	return match expr {
		ast.IntLit {
			4
		}
		ast.StrLit {
			// The value of a string is the address of its bytes.
			e.target.word_size
		}
		ast.Ident {
			slot := e.lookup(expr.name) or { return none }
			slot.width
		}
		ast.Call {
			// A call is never a value here (the emitter reports one that is),
			// but the table has to answer for every expression shape.
			4
		}
		ast.Unary {
			if expr.op == '!' {
				4
			} else {
				e.width_of(expr.expr) or { return none }
			}
		}
		ast.Binary {
			if expr.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
				4
			} else {
				left := e.width_of(expr.left) or { return none }
				right := e.width_of(expr.right) or { return none }
				if left != right {
					return none
				}
				left
			}
		}
	}
}

// constant evaluates an expression that reads nothing: a program written in
// constants is emitted as the values it computed to, which is what keeps
// `return 6 * 7` the one instruction it always was. An expression with a name in
// it, or one the walk cannot compute, is not a constant and answers none, and
// the emitter writes it as the computation it is.
//
// The left spine is walked with a loop and only genuinely nested expressions
// recurse, for the reason the emitter's own walk does it: a long chain of terms
// is deep in the tree and shallow in the grammar, and recursion per term turns a
// generated constant expression into a stack overflow.
fn (e Emitter) constant(expr ast.Expr) ?i64 {
	return e.constant_at(expr, 0)
}

fn (e Emitter) constant_at(expr ast.Expr, depth int) ?i64 {
	if depth > max_emit_depth {
		return none
	}
	mut spine := []ast.Binary{}
	mut node := expr
	for node is ast.Binary {
		step := node as ast.Binary
		if step.op == '&&' || step.op == '||' {
			// The short-circuit operators are a branch, not a value: what they
			// come to depends on which side was evaluated, so they are not
			// constants even when both sides are.
			return none
		}
		spine << step
		node = step.left
	}
	mut value := e.constant_leaf(node, depth + 1) or { return none }
	for i := spine.len - 1; i >= 0; i-- {
		step := spine[i]
		right := e.constant_at(step.right, depth + 1) or { return none }
		value = apply_constant(step, value, right) or { return none }
	}
	return value
}

fn (e Emitter) constant_leaf(expr ast.Expr, depth int) ?i64 {
	return match expr {
		ast.IntLit {
			expr.value
		}
		ast.Unary {
			operand := e.constant_at(expr.expr, depth + 1) or { return none }
			match expr.op {
				'-' { wrap_sub(i64(0), operand) }
				'+' { operand }
				'!' {
					if operand == 0 { i64(1) } else { i64(0) }
				}
				'~' { ~operand }
				else { return none }
			}
		}
		ast.Binary {
			e.constant_at(expr, depth + 1)
		}
		else {
			return none
		}
	}
}

// apply_constant computes one operator of a constant expression. The arithmetic
// wraps, because that is what the compiler that built this binary does and what
// every compiler on the machines this targets does; a division or a remainder by
// zero is not a constant, and the emitter reports it where it was written.
fn apply_constant(binary ast.Binary, left i64, right i64) ?i64 {
	return match binary.op {
		'+' { wrap_add(left, right) }
		'-' { wrap_sub(left, right) }
		'*' { wrap_mul(left, right) }
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
		else {
			return none
		}
	}
}

// emit_call writes one call: every argument is evaluated first, each one into a
// slot of its own in the frame, and only then are the machine's argument
// registers loaded with them. An argument can be an expression that calls
// another function, and a call is free to use every register this compiler can;
// storing each finished argument and loading the registers at the end is what
// keeps one argument from landing on another.
//
// A name the file defines is called by its distance in the code, so a call to a
// function in the same translation unit binds to that definition; every other
// name is a symbol the loader resolves before the program starts.
fn (mut e Emitter) emit_call(call ast.Call, depth int) !void {
	for i, arg in call.args {
		if e.target.arg_reg(i) == none {
			e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} has more than ${i} arguments, and the machine has no register for another one')
			return error('too many arguments')
		}
		e.emit_expr_at(arg, depth + i + 1)!
		e.store_accumulator(e.value_slot(depth + i), expr_line(arg), expr_col(arg))!
	}
	for i, arg in call.args {
		register := e.target.arg_reg(i) or {
			e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} has more than ${i} arguments, and the machine has no register for another one')
			return error('too many arguments')
		}
		width := e.passed_width(call, i, arg)!
		e.load_argument(e.value_slot(depth + i), register, width, expr_line(arg), expr_col(arg))!
	}
	if call.name in e.program.defined {
		e.reference(e.target.call_near(0), .call_local, call.name, '')
		return
	}
	e.import_symbol(call.name)
	// A library function this compiler has no prototype for may be variadic, and
	// the machine's convention wants the number of vector arguments in the low
	// byte of the result register before a call like that. Zero is what a call
	// with no vector arguments says, and printf reads it. The count goes in after
	// the argument registers are loaded, because loading them is the last thing
	// that could disturb it.
	result := e.accumulator(call.line, call.col)!
	e.append(e.target.move_immediate32(result, 0)!)
	e.reference(e.target.call_slot(0), .call_import, call.name, '')
}

// passed_width is the width one argument is handed over at. A function this file
// defines says what its parameters are; a library function has no prototype
// here, so the width is the one the argument itself has. A value whose width is
// not the parameter's is reported where it is written: a pointer passed where an
// int is expected would hand over one half of itself, and nothing later would
// notice.
fn (mut e Emitter) passed_width(call ast.Call, position int, arg ast.Expr) !int {
	actual := e.width_of(arg)
	if widths := e.signatures[call.name] {
		if position < widths.len {
			expected := widths[position]
			if actual != none && actual != expected {
				if e.constant(arg) == none {
					e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${position + 1} of the call to ${call.name} is a value of ${actual} bytes and the parameter is ${expected}')
					return error('argument width')
				}
			}
			return expected
		}
	}
	return actual or {
		e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: the width of argument ${position + 1} of the call to ${call.name} is one this back end cannot size')
		return error('unknown argument width')
	}
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
// records what it points at and how long it is. register is the register the
// instruction computes into, for the references that have one: the address of a
// string is loaded where the value is about to be used from.
fn (mut e Emitter) reference(bytes []u8, kind FixupKind, name string, register string) {
	start := e.program.text.len
	e.program.text << bytes
	e.program.fixups << Fixup{
		start:    start
		length:   bytes.len
		kind:     kind
		name:     name
		register: register
	}
}

// Wrapping arithmetic, spelled out rather than assumed. V 0.5.2 has no `+%`
// operators, and whether `+` traps on overflow depends on how the compiler that
// built this binary was invoked, so the walk goes through u64 where the wrap is
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

// expr_line and expr_col are the position an expression was written at. Every
// node carries it, so a diagnostic can say where the construct is no matter
// which node it turned out to be.
fn expr_line(expr ast.Expr) int {
	return match expr {
		ast.IntLit { expr.line }
		ast.StrLit { expr.line }
		ast.Ident { expr.line }
		ast.Unary { expr.line }
		ast.Binary { expr.line }
		ast.Call { expr.line }
	}
}

fn expr_col(expr ast.Expr) int {
	return match expr {
		ast.IntLit { expr.col }
		ast.StrLit { expr.col }
		ast.Ident { expr.col }
		ast.Unary { expr.col }
		ast.Binary { expr.col }
		ast.Call { expr.col }
	}
}

fn problem(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
	}
}
