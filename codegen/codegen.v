module codegen

import ast
import backend
import math
import tokenize

// Options is what the caller asks for. An empty target means the machine this
// binary runs on, and an empty entry means `main`.
pub struct Options {
pub:
	target string
	entry  string
	// libraries are the -l names the command line gave, in the order they were
	// written: a program that calls a function out of a shared library other
	// than the C library has to name that library for the loader to map it.
	libraries []string
	// library_dirs are the -L directories, which are searched for a -l name
	// before the directories the system keeps its libraries in.
	library_dirs []string
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
	global_address // the address of an object defined at the top level
	float_constant // a double the instruction reads out of the read-only data
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
	// libraries are the shared libraries the image names as needed, in the
	// order the -l flags named them: the loader maps these before the first
	// instruction runs, and one that is not named is one whose symbols are not
	// there. The C library is not in this list; the container adds it to every
	// image it writes.
	libraries []string
	// string_blob is the read-only data: every distinct string literal with the
	// terminator a library function reads to, and strings is where each one
	// starts in it.
	string_blob []u8
	strings     map[string]int
	// doubles is the same storage again for the eight bytes of a floating
	// constant, keyed by the bit pattern rather than by the bytes, so that two
	// constants that are the same double are one entry the way two identical
	// strings are. A double is read out of the image and never written, which
	// is what lets it live beside the strings.
	doubles map[string]int
	// globals_blob is the storage of the objects defined at the top level, and
	// globals is where each one starts in it. It is a second blob rather than a
	// part of the strings because a global is written as well as read, and
	// because a string is interned for the bytes it holds while a global is
	// interned for the name it was defined with.
	globals_blob []u8
	globals      map[string]GlobalSlot
}

// GlobalSlot is where a top-level object lives in the image and how wide it is:
// the offset of its first element in globals_blob, the width of one element, and
// the count of elements it was defined with. floating says the object holds
// doubles, which is a different instruction for every read and write of it.
struct GlobalSlot {
	offset int
	width  int
	count  int
	// object says the storage is an object of an aggregate type rather than a
	// value: one object is as many bytes as the layout said and an array of them
	// is that many per element, and nothing reads one as a value.
	object   bool
	floating bool
}

// Slot is where a local or a parameter lives: a displacement from the frame
// pointer, and the width of the value in it. The width is what keeps an int and
// a pointer apart, since a value read or written at the other width is a value
// from a neighbouring slot rather than a wrong answer. A double is eight bytes
// like a pointer, so the width alone cannot tell those two apart either, and
// `floating` is what does: it says which of the machine's two value files the
// slot is read and written through.
struct Slot {
	offset int
	width  int
	// count is how many elements an array slot holds, and zero for a slot that
	// holds one value. An array's slot is the address of its first element, and
	// width is the width of one element of it.
	count int
	// floating is set for a slot holding a double, which is a value the machine
	// moves with a different instruction than an integer of the same width.
	floating bool
	// bytes is the size of a slot that holds an object of an aggregate type, and
	// zero for a slot that holds a scalar or an array: an object of a struct
	// type has no spelling this back end can size, so the size the model laid
	// out travels with the declaration and the frame reserves that many bytes.
	// The name of such a slot is the address of the object, which is what a
	// member is read and written through.
	bytes int
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
	// libraries are the -l names the command line gave, and library_dirs the
	// -L directories they are looked for in. Both are resolved into the names
	// the image carries before anything is emitted.
	libraries    []string
	library_dirs []string
mut:
	program     Program
	diagnostics []tokenize.Diagnostic
	// signatures is the width of each parameter of every function the file
	// defines, so that a call in the file hands each argument over at the width
	// the definition expects.
	signatures map[string][]int
	// float_params says, for the same functions, which parameters are doubles.
	// The width cannot answer that on its own: a double is eight bytes and so is
	// a pointer, and the two travel through different registers.
	float_params map[string][]bool
	// aggregate_params says, for the same functions, which parameters are
	// objects of an aggregate type and how many bytes of one they are. An object
	// of one eightbyte is handed over as its bytes in one register rather than
	// as a value, so a call has to know which parameters those are, and zero
	// bytes means the parameter is a value.
	aggregate_params map[string][]ast.Class
	// return_classes says, for the same functions, which of them hand an object
	// of an aggregate type back, and how many bytes of one. The value comes back
	// in the register its class names rather than converted.
	return_classes map[string]ast.Class
	// returning is the return type of the function being emitted, as it was
	// written, which is what a return statement's value is converted to.
	returning string
	// return_class is how the function being emitted hands its value back, and
	// zero for a function that returns a value of its own width or nothing.
	return_class ast.Class
	// returns is the return type of every function the file defines, which is
	// what a call whose value is read has to be checked against: a void
	// function's result is nothing, and a value read from a call to one would
	// be whatever the call left in the register.
	returns map[string]string
	// scopes is the blocks being emitted, innermost last. A name is visible in
	// the block it was declared in and the ones inside it, which is where a
	// declaration gets its slot and its width from.
	scopes []map[string]Slot
	// frame_used is how many bytes of frame the function being emitted has
	// claimed: its parameters, its locals and the slots an expression needs.
	frame_used int
	// stack_pushed is how many bytes the call being emitted has pushed for the
	// arguments its registers ran out for, and zero when it pushed none. The
	// caller gives those bytes back once the call returns, so the frame is where
	// it was and the slots keep their offsets.
	stack_pushed int
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
		target:       target
		entry:        entry
		unit:         unit
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
	}
	// Nothing is written from a tree the model did not type. The check runs
	// before the layout, so a tree it refuses produces no image at all.
	emitter.refuse_unresolved() or {
		if emitter.diagnostics.len == 0 {
			emitter.diagnostics << problem(1, 1, 'internal: the tree could not be checked: ${err.msg()}')
		}
		return Result{
			target:      target
			diagnostics: emitter.diagnostics
		}
	}
	image := emitter.build() or {
		// A stage that failed without reporting why still owes a message: an
		// empty output file that says nothing is the worst outcome available,
		// and it is what an error raised past a diagnostic produces.
		if emitter.diagnostics.len == 0 {
			emitter.diagnostics << problem(1, 1, 'internal: the image could not be produced: ${err.msg()}')
		}
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
	// The libraries the image will name are settled before a byte is written.
	// A -l name with no file behind it is an error a link makes, and the
	// alternative is worse than an error: a program that compiles and then
	// dies at load with an undefined symbol says nothing about the flag that
	// asked for the library.
	for name in e.libraries {
		soname := resolve_library(name, search_dirs(e.library_dirs, e.target.library_dirs)) or {
			e.diagnostics << problem(1, 1, err.msg())
			return error('cannot resolve -l${name}')
		}
		if soname !in e.program.libraries {
			e.program.libraries << soname
		}
	}
	// The names and the parameter widths come first so that a call binds to a
	// definition wherever in the file it is written. The width is the one the
	// definition gives the parameter, which is what a call in the same file has
	// to hand over; a definition with a parameter this back end cannot size is
	// left out of the table, because its own emission is where that is reported.
	for decl in e.unit.decls {
		e.returns[decl.name] = decl.ret
		if decl.ret_class.bytes > 0 {
			e.return_classes[decl.name] = decl.ret_class
		}
		if decl.body.len > 0 {
			e.program.defined[decl.name] = true
			mut widths := []int{}
			mut classes := []bool{}
			mut aggregates := []ast.Class{}
			mut sized := true
			for param in decl.params {
				// A parameter that is an object of an aggregate type is handed
				// over as its bytes in one register: how many bytes it is and
				// which file the register belongs to are the two facts the call
				// needs, and both come from the declaration.
				if param.class.bytes > 0 {
					widths << param.class.bytes
					classes << param.class.first_floating
					aggregates << param.class
					continue
				}
				aggregates << ast.Class{}
				if width := e.type_width(param.typ) {
					widths << width
					classes << e.writes_a_double(param.typ)
				} else {
					sized = false
				}
			}
			if sized {
				e.signatures[decl.name] = widths
				e.float_params[decl.name] = classes
				e.aggregate_params[decl.name] = aggregates
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

// refuse_unresolved refuses a tree that carries a value the model did not type.
//
// The emitter takes the width of a value and the instruction an operator uses
// from the shape of the node, not from its clause, so a constant whose clause is
// unresolved is a value it would write an answer for that nothing decided.
// Measured, `int main(void) { return 4294967295 > 2147483647; }` was read as an
// int comparison and returned 0 where ISO C and gcc return 1.
//
// The constant is the node this reads. The emitter writes every constant as a
// four-byte int, so a constant the model left unresolved and whose value that int
// cannot hold would be written as a different number than the program asked for.
// It is refused before a byte is written, so no image comes out of it. Every
// other clause the model did not resolve is refused in parser/, which names the
// construct and its location: a construct the parser refused where it was read, or
// a name nothing in the unit declares, which is refused once the whole unit has
// been read because a definition may follow the function that calls it. A call is
// the one node both of those can leave standing: a call to a name the unit declares
// as something that is not a function is refused where the call is written, and a
// call through a name the unit declares as a function is written although nothing
// in the unit defines it, so the image dies at load with an undefined symbol. That
// last shape is a linker's business and not this emitter's.
// A node reached here with the zero type and a value an int holds is one the
// emitter writes correctly, which is what keeps a tree the tests assemble by hand
// emittable.
fn (mut e Emitter) refuse_unresolved() !void {
	for decl in e.unit.decls {
		e.check_statements(decl.body, 0)!
	}
}

// check_statements walks the statements of a body looking for such a constant.
fn (mut e Emitter) check_statements(stmts []ast.Stmt, depth int) !void {
	for stmt in stmts {
		if expr := stmt.expr {
			e.check_expression(expr, depth)!
		}
		if init := stmt.init {
			e.check_expression(init, depth)!
		}
		if index := stmt.index {
			e.check_expression(index, depth)!
		}
		if cond := stmt.cond {
			e.check_expression(cond, depth)!
		}
		e.check_statements(stmt.body, depth)!
		e.check_statements(stmt.then_body, depth)!
		e.check_statements(stmt.else_body, depth)!
		e.check_statements(stmt.step, depth)!
	}
}

// check_expression walks one expression. A tree deeper than the emitter's own
// walk would go is left to the emitter's depth report, which is the same number.
fn (mut e Emitter) check_expression(expr ast.Expr, depth int) !void {
	if depth > max_emit_depth {
		return
	}
	if expr is ast.IntLit {
		if expr.typ.kind == .unknown && !is_an_int_value(expr.value) {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: the integer constant ${expr.text} has no type this compiler resolved, and it is not a value the int this back end writes a constant as can hold')
			return error('unresolved constant')
		}
		return
	}
	match expr {
		ast.Binary {
			e.check_expression(expr.left, depth + 1)!
			e.check_expression(expr.right, depth + 1)!
		}
		ast.Unary {
			e.check_expression(expr.expr, depth + 1)!
		}
		ast.Call {
			for arg in expr.args {
				e.check_expression(arg, depth + 1)!
			}
		}
		ast.Index {
			e.check_expression(expr.index, depth + 1)!
		}
		else {}
	}
}

// is_an_int_value says whether a value is one the four-byte signed int this back
// end writes a constant as holds, which is the range a constant written at that
// width keeps its value in.
fn is_an_int_value(value i64) bool {
	return value >= -2147483648 && value <= 2147483647
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
	// A definition returns a value the caller reads or nothing at all. There is
	// no third answer the machine has a place for: the result register holds
	// what a call leaves there, and a void function leaves nothing to read.
	if decl.ret_class.bytes > 0 {
		// A function may hand an object of an aggregate type back, and the value
		// comes back in the register the class names rather than converted. An
		// object larger than one eightbyte is two registers or a copy in memory,
		// which is the half of this that this compiler does not hand over.
		if decl.ret_class.count > 2 {
			e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, which is an object of ${decl.ret_class.bytes} bytes or ${decl.ret_class.count} eightbytes, and this compiler hands back an aggregate of at most two')
			return error('aggregate return too large')
		}
		if decl.ret_class.first_floating && decl.ret_class.bytes < e.target.word_size {
			e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, which is an object of ${decl.ret_class.bytes} bytes whose class is the floating-point one, and this compiler moves such an object as eight bytes')
			return error('aggregate floating class width')
		}
	} else if decl.ret != 'int' && decl.ret != 'void' && decl.ret != 'double' {
		e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, and only int, double and void are implemented')
		return error('unsupported return type')
	}
	e.returning = decl.ret
	e.return_class = decl.ret_class
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
	//
	// There are two sequences of them and a parameter belongs to one: an int
	// arrives in the general file and a double in the floating one, each numbered
	// from its own beginning, which is how `f(int a, double b)` finds a in the
	// first general register and b in the first floating one.
	mut integers := 0
	mut doubles := 0
	mut stacked := 0
	for _, param in decl.params {
		// An object of an aggregate type arrives as its bytes in one register of
		// the class its members make, and the parameter is storage of exactly
		// that many bytes: the value is copied into the slot rather than
		// converted into it.
		if param.class.bytes > 0 {
			if param.class.count > 2 {
				e.diagnostics << problem(param.line, param.col, 'unsupported: ${decl.name} takes ${param.typ} by value, which is ${param.class.bytes} bytes or ${param.class.count} eightbytes, and this compiler hands over an aggregate of at most two')
				return error('aggregate parameter too large')
			}
			object := e.declare(param.name, param.typ, 0, param.class.bytes, param.line, param.col)!
			stacked_at := 2 * e.target.word_size + stacked * e.target.word_size
			if param.class.count == 2 {
				// Two eightbytes: each arrives in a register of its own class,
				// or both arrive as two words of the stack when either sequence
				// had none left for the object, which is the same answer the
				// caller reached.
				placed := pair_places(e.target, param.class.first_floating, param.class.second_floating,
					integers, doubles)
				if placed.registers {
					integers = placed.integers
					doubles = placed.doubles
					e.store_argument_eightbyte(object, 0, e.target.word_size,
						param.class.first_floating, placed.first, param.line, param.col)!
					e.store_argument_eightbyte(object, e.target.word_size,
						param.class.bytes - e.target.word_size, param.class.second_floating,
						placed.second, param.line, param.col)!
					continue
				}
				e.load_stacked_eightbyte(object, 0, e.target.word_size, stacked_at, param.line,
					param.col)!
				e.load_stacked_eightbyte(object, e.target.word_size,
					param.class.bytes - e.target.word_size, stacked_at + e.target.word_size,
					param.line, param.col)!
				stacked += 2
				continue
			}
			if param.class.first_floating {
				if register := e.target.float_arg_reg(doubles) {
					e.store_double_register(object, register, param.line, param.col)!
					doubles++
					continue
				}
				double_register := e.float_accumulator(param.line, param.col)!
				base := e.frame_pointer(param.line, param.col)!
				e.append(e.target.load_double_slot(base, stacked_at, double_register)!)
				e.store_double_register(object, double_register, param.line, param.col)!
				stacked++
				continue
			}
			if register := e.target.arg_reg(integers) {
				e.store_register(object, register, param.line, param.col)!
				integers++
				continue
			}
			register := e.accumulator(param.line, param.col)!
			base := e.frame_pointer(param.line, param.col)!
			e.append(e.target.load_slot(base, stacked_at, register, e.target.word_size)!)
			e.store_register(object, register, param.line, param.col)!
			stacked++
			continue
		}
		// A parameter is one value in a register or one on the stack, and an
		// object of an aggregate type passed by value is neither: its spelling
		// reaches `type_width` and is refused there by name.
		slot := e.declare(param.name, param.typ, 0, 0, param.line, param.col)!
		// The arguments a sequence ran out for arrive on the stack, and where
		// they are is the caller's side of the same rule: the first one the
		// caller pushed is at the return address, so sixteen bytes past the
		// frame pointer counting the frame pointer and the return address, and
		// the ones after it follow one machine word apart.
		at := 2 * e.target.word_size + stacked * e.target.word_size
		if slot.floating {
			if register := e.target.float_arg_reg(doubles) {
				e.store_double_register(slot, register, param.line, param.col)!
				doubles++
				continue
			}
			double_register := e.float_accumulator(param.line, param.col)!
			base := e.frame_pointer(param.line, param.col)!
			e.append(e.target.load_double_slot(base, at, double_register)!)
			e.store_double_register(slot, double_register, param.line, param.col)!
			stacked++
			continue
		}
		if register := e.target.arg_reg(integers) {
			e.store_register(slot, register, param.line, param.col)!
			integers++
			continue
		}
		register := e.accumulator(param.line, param.col)!
		base := e.frame_pointer(param.line, param.col)!
		e.append(e.target.load_slot(base, at, register, slot.width)!)
		e.store_register(slot, register, param.line, param.col)!
		stacked++
	}
	returned := e.emit_statements(decl.body)!
	if !returned {
		if decl.ret == 'double' {
			// A function that falls off its end returns zero, and zero as a
			// double is the floating-point register file's own zero rather than
			// the integer one: the caller reads the value out of the other
			// register, and an int zero there would be whatever the body left.
			register := e.float_accumulator(decl.line, decl.col)!
			e.append(e.target.zero_double(register)!)
		} else {
			result := e.accumulator(decl.line, decl.col)!
			e.append(e.target.move_immediate32(result, 0)!)
		}
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
// did before it. The value is converted to the function's return type where the
// two are different classes, which is the same conversion a call makes for an
// argument: `return 1;` in a function returning a double returns 1.0, and
// `return 1.5;` in one returning an int returns 1.
fn (mut e Emitter) emit_return(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: return without a value in a function that returns ${e.returning}')
		return error('return without a value')
	}
	if e.returning == 'void' {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: return with a value in a function that returns void')
		return error('return with a value')
	}
	if e.return_class.bytes > 0 {
		// The value is an object, and the machine hands it back as its bytes in
		// the registers the classes name: the address of the object is taken and
		// each eightbyte is read from it, which is the same bytes a caller reads
		// out of those registers. The first eightbyte of a pair goes into the
		// register a value of its class comes back in and the second into the one
		// after it, so the two files are numbered apart and both are read here.
		if e.return_class.count == 2 {
			// The second eightbyte is read first and eight bytes further in, and the
			// object's address is taken again for the first one, because the address
			// travels in the register the first general eightbyte goes back in.
			e.address_of_object(expr, 0)!
			base := e.accumulator(stmt.line, stmt.col)!
			e.append(e.target.add_immediate(base, e.target.word_size))
			e.load_return_eightbyte(base, 1, e.return_class.bytes - e.target.word_size,
				e.return_class.second_floating, stmt.line, stmt.col)!
		}
		e.address_of_object(expr, 0)!
		base := e.accumulator(stmt.line, stmt.col)!
		e.load_return_eightbyte(base, 0, e.target.word_size, e.return_class.first_floating,
			stmt.line, stmt.col)!
		e.append(e.target.frame_epilogue())
		return
	}
	e.emit_expr(expr)!
	e.convert_to_return(expr, stmt.line, stmt.col)!
	e.append(e.target.frame_epilogue())
}

// convert_to_return makes the value being returned the class the function
// returns. Both directions are conversions the language defines, and the one that
// is refused is a pointer: a function returning an int or a double has no
// conversion to make from an address, and the answer would be half of it or an
// address that is no longer one.
fn (mut e Emitter) convert_to_return(expr ast.Expr, line int, col int) !void {
	if e.returning == 'double' {
		return e.convert_to_double(expr, line, col)
	}
	if e.floating_of(expr) {
		return e.convert_to_int(expr, line, col)
	}
	return
}

// emit_var_decl gives a declaration its slot in the frame and, when it has one,
// writes the initializer into it. A declaration without an initializer is
// storage and nothing else, which is what C says it is: the slot is there for
// whatever the function writes into it next.
fn (mut e Emitter) emit_var_decl(stmt ast.Stmt) !void {
	slot := e.declare(stmt.decl_name, stmt.decl_type, stmt.decl_count, stmt.bytes, stmt.line, stmt.col)!
	init := stmt.init or { return }
	if slot.bytes > 0 {
		// An object of an aggregate type declared with an initializer takes the
		// value of another object of its type, or the value a call hands back:
		// the same copy the assignment makes, into the storage the declaration
		// just claimed.
		declared := ast.Stmt{
			kind:   .assign
			target: stmt.decl_name
			expr:   init
			line:   stmt.line
			col:    stmt.col
		}
		return e.assign_object_local(declared, slot)
	}
	if stmt.decl_count > 0 {
		// An array is storage, and the elements of it are whatever the frame
		// held: an initializer for one is a shape this back end does not copy
		// yet, and writing one element of it would be a wrong program.
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.decl_name} is an array declared with an initializer, and an array of elements is not initialized here')
		return error('array initializer')
	}
	e.emit_expr(init)!
	e.store_value(slot, init, stmt.line, stmt.col)!
}

// emit_assign evaluates the value and writes it into the slot the name lives in.
// The name has to be in scope: an assignment to a name that was never declared
// has nowhere to go, and a guessed slot would be someone else's variable.
fn (mut e Emitter) emit_assign(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned without a value')
		return error('assignment without a value')
	}
	if member := stmt.field {
		return e.assign_member(stmt, member, expr)
	}
	if subscript := stmt.index {
		return e.assign_element(stmt, subscript, expr)
	}
	target := e.lookup(stmt.target) or {
		// A top-level object is written through its address in the image, the
		// same way a local is written through its place in the frame.
		if object := e.global_of(stmt.target) {
			if object.object && object.count == 0 {
				return e.assign_object_global(stmt, object)
			}
			return e.assign_global(stmt, object, expr)
		}
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned to, and no local of that name is in scope')
		return error('unknown assignment target')
	}
	if target.bytes > 0 {
		return e.assign_object_local(stmt, target)
	}
	e.emit_expr(expr)!
	e.store_value(target, expr, stmt.line, stmt.col)!
}

// assign_object_local writes an object into a local object: the destination's
// address is the frame's address plus the slot's offset, parked in a value slot
// while the value is read.
fn (mut e Emitter) assign_object_local(stmt ast.Stmt, target Slot) !void {
	expr_value := stmt.expr or { return error('assignment without a value') }
	register := e.accumulator(stmt.line, stmt.col)!
	frame := e.frame_pointer(stmt.line, stmt.col)!
	e.append(e.target.address_of_slot(frame, target.offset, register))
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	return e.assign_object(address, target.width, expr_value, stmt.line, stmt.col)
}

// assign_object_global writes an object into a top-level object: the destination's
// address is in the image, so it is a reference the layout fills in rather than an
// offset from the frame.
fn (mut e Emitter) assign_object_global(stmt ast.Stmt, object GlobalSlot) !void {
	expr_value := stmt.expr or { return error('assignment without a value') }
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference(e.target.address_of(register, 0), .global_address, stmt.target, register.name)
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	return e.assign_object(address, object.width, expr_value, stmt.line, stmt.col)
}

// assign_object writes one object of an aggregate type into the storage at an
// address the caller has already parked in a slot.
//
// The value is one of two things. A call to a function that hands an object back
// leaves its bytes in the register the class names, so the call is emitted here and
// the register is stored. Anything else is an object of the same type, which is a
// copy of its bytes: the source's address is taken and the bytes are read from it.
// The destination's address is loaded into a scratch register last, because that is
// the register the store goes through and reading the value must not disturb it.
fn (mut e Emitter) assign_object(address Slot, width int, expr ast.Expr, line int, col int) !void {
	if expr is ast.Call {
		if class := e.return_classes[expr.name] {
			// The value arrives in the registers the classes name: one eightbyte,
			// or two when the object is two of them, each in the register a value
			// of its class comes back in.
			if class.bytes != width {
				e.diagnostics << problem(line, col, 'unsupported: the call to ${expr.name} hands back an object of ${class.bytes} bytes and ${width} bytes are written into this object')
				return error('aggregate too small')
			}
			e.emit_expr_at(expr, 1)!
			base := e.scratch(line, col)!
			e.load_argument(address, base, e.target.word_size, line, col)!
			e.store_return_eightbyte(base, 0, e.target.word_size, class.first_floating, expr.line,
				expr.col)!
			if class.count == 2 {
				e.append(e.target.add_immediate(base, e.target.word_size))
				e.store_return_eightbyte(base, 1, class.bytes - e.target.word_size,
					class.second_floating, expr.line, expr.col)!
			}
			return
		}
	}
	// An object of the same type: a copy of its bytes, which is what the language
	// asks for and what the machine does in chunks it can move in one instruction.
	// Neither object is read as a value, so an object of any size is copied.
	e.address_of_object(expr, 1)!
	source := e.value_slot(1)
	e.store_accumulator(source, line, col)!
	mut done := 0
	for done < width {
		remaining := width - done
		chunk := if remaining >= 8 {
			8
		} else if remaining >= 4 {
			4
		} else if remaining >= 2 {
			2
		} else {
			1
		}
		source_register := e.scratch(line, col)!
		e.load_argument(source, source_register, e.target.word_size, line, col)!
		if done > 0 {
			e.append(e.target.add_immediate(source_register, done))
		}
		value := e.remainder(line, col)!
		e.append(e.target.load_indirect(source_register, value, chunk)!)
		destination := e.accumulator(line, col)!
		e.load_argument(address, destination, e.target.word_size, line, col)!
		if done > 0 {
			e.append(e.target.add_immediate(destination, done))
		}
		e.append(e.target.store_indirect(destination, value, chunk)!)
		done += chunk
	}
}

// assign_member writes a value into one member of an object. The address of the
// member is the address of the object plus the offset the layout put it at, parked
// in a scratch slot while the value is computed, and the value is written through
// it: the shape an element of an array is written with, because a member is an
// element of the object at a fixed offset rather than at a computed one.
// aggregate_argument is how argument `position` of a call is handed over when it
// is an object of an aggregate type, and none when it is a value. It answers from
// the signature the declaration gave, so a call to a function this file defines
// knows; a call to a name nothing declares has no signature, and an object is
// refused there rather than handed to a function whose convention is unknown.
fn (e Emitter) aggregate_argument(call ast.Call, position int) ?ast.Class {
	if classes := e.aggregate_params[call.name] {
		if position < classes.len && classes[position].bytes > 0 {
			return classes[position]
		}
	}
	return none
}

// address_of_object leaves the address of the object an expression names in the
// accumulator. An object handed over by value is read from its bytes, so what the
// caller needs is where those bytes are: a local's place in the frame, a top-level
// object's place in the image, or a member's place inside the object that holds it.
fn (mut e Emitter) address_of_object(expr ast.Expr, depth int) !void {
	if expr is ast.Ident {
		e.address_of_member(expr.name, ?ast.Expr(none), 0, false, depth, expr.line, expr.col)!
		return
	}
	if expr is ast.Field {
		e.address_of_member(expr.name, expr.index, expr.offset, expr.through_pointer, depth, expr.line,
			expr.col)!
		return
	}
	if expr is ast.Index {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of an array is not handed over by value in this compiler, so ${expr.name}[...] cannot be an argument')
		return error('element by value')
	}
	e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: an object handed over by value has to be a name, an element or a member, and this expression is not one')
	return error('not an object')
}

// address_of_member leaves the address of a member in the accumulator. An object
// named by a name is at the frame's address plus the byte the layout gave the
// member. An object named by a pointer, which is what `->` writes, is at the
// address the pointer holds plus that byte, so the pointer's value is read and the
// byte is added to it. The address is left in the accumulator rather than stored,
// because the reader loads through it and the writer stores it where the value will
// need it.
fn (mut e Emitter) address_of_member(name string, index ?ast.Expr, offset int, through_pointer bool, depth int, line int, col int) !void {
	if element := index {
		// One element of an array of objects: the address of the element is the
		// address of the array plus the index scaled by the size of one element,
		// and for an aggregate that size is the layout's, which is why the
		// element's width travels in the slot. The member is read at that
		// address plus its own offset into the element.
		//
		// The index is computed before the array's address is taken, so the index
		// expression cannot overwrite the address on the way, which is the same
		// order the element read uses. The array's address goes into a scratch
		// register and not the frame pointer, because a stride the scaled address
		// cannot write is a multiply followed by an add, and the add must not
		// move the frame pointer out from under the rest of the function.
		e.emit_expr_at(element, depth + 1)!
		register := e.accumulator(line, col)!
		base := e.scratch(line, col)!
		mut stride := 0
		if slot := e.lookup(name) {
			if slot.count == 0 {
				e.diagnostics << problem(line, col, 'unsupported: ${name} is read as an array, and it is not one')
				return error('not an array')
			}
			stride = slot.width
			frame := e.frame_pointer(line, col)!
			e.append(e.target.address_of_slot(frame, slot.offset, base))
		} else if object := e.global_of(name) {
			if object.count == 0 {
				e.diagnostics << problem(line, col, 'unsupported: ${name} is read as an array, and it is not one')
				return error('not an array')
			}
			stride = object.width
			e.reference(e.target.address_of(base, 0), .global_address, name, base.name)
		} else {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is read as an array, and no declaration of that name is in scope')
			return error('unknown name')
		}
		if stride == 1 || stride == 2 || stride == 4 || stride == 8 {
			e.append(e.target.address_of_element(base, register, stride, 0, register)!)
		} else {
			// A stride the scaled address cannot write is a multiply and an add:
			// an object of an aggregate type is rarely a power of two bytes, and
			// the machine scales an index only by those.
			e.append(e.target.imul_immediate(register, stride))
			e.append(e.target.add_reg64(register, base))
		}
		if offset != 0 {
			e.append(e.target.add_immediate(register, offset))
		}
		return
	}

	slot := e.lookup(name) or {
		// A top-level object: it has no slot in the frame, so the address of the
		// member is the address of the object in the image plus the byte the
		// layout gave the member. A pointer at the top level is storage the tree
		// does not lay out, so an arrow on one cannot be reached from here.
		// `global_of` also lays the storage out the first time the name is
		// used, which is what an address of it needs: a reference the layout
		// fills in is meaningless until there is an object to point at.
		if _ := e.global_of(name) {
			register := e.accumulator(line, col)!
			e.reference(e.target.address_of(register, 0), .global_address, name, register.name)
			if offset != 0 && !through_pointer {
				e.append(e.target.add_immediate(register, offset))
			}
			return
		}
		e.diagnostics << problem(line, col, 'unsupported: ${name} is read as an object with a member, and no declaration of that name is in scope')
		return error('unknown object')
	}
	if !through_pointer && slot.bytes == 0 {
		e.diagnostics << problem(line, col, 'unsupported: ${name} is not an object whose type has members')
		return error('not an aggregate')
	}
	register := e.accumulator(line, col)!
	if through_pointer {
		e.load_argument(slot, register, e.target.word_size, line, col)!
		if offset != 0 {
			e.append(e.target.add_immediate(register, offset))
		}
		return
	}
	base := e.frame_pointer(line, col)!
	e.append(e.target.address_of_slot(base, slot.offset + offset, register))
}

fn (mut e Emitter) assign_member(stmt ast.Stmt, member ast.Field, expr ast.Expr) !void {
	width := e.type_width(member.spelling) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the member ${member.name}.${member.member} is declared ${member.spelling}, and this back end stores ints, chars, doubles and pointers only')
		return error('unsupported member type')
	}
	e.address_of_member(member.name, member.index, member.offset, member.through_pointer, 1, stmt.line, stmt.col)!
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	e.emit_expr_at(expr, 1)!
	address_register := e.scratch(stmt.line, stmt.col)!
	member_name := '${member.name}.${member.member}'
	if e.writes_a_double(member.spelling) {
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in the member ${member_name}, which holds a double, and there is no conversion between them')
			return error('pointer into a double')
		}
		e.convert_to_double(expr, stmt.line, stmt.col)!
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_double_indirect(address_register, value)!)
		return
	}
	if e.floating_of(expr) {
		e.convert_to_int(expr, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, width)!)
		return
	}
	value_width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	if value_width != width && !(width == 1 && value_width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored into the member ${member_name}, which holds ${width}')
		return error('width mismatch')
	}
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, width)!)
}

// assign_element writes a value into one element of an array. The address of the
// element is computed from the index and the array's place in the frame, parked
// in a scratch slot while the value is computed, and the value is written
// through it. The parking is what makes `a[i] = a[i] + 1` work: the value reads
// the array again, and computing it would otherwise write over the register the
// address was in.
fn (mut e Emitter) assign_element(stmt ast.Stmt, subscript ast.Expr, expr ast.Expr) !void {
	slot := e.lookup(stmt.target) or {
		// A top-level array is addressed from its storage in the image instead
		// of from the frame: the address of the object is what the element is an
		// offset from.
		if object := e.global_of(stmt.target) {
			if object.count == 0 {
				e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned an element of it, and it is not an array')
				return error('not an array')
			}
			e.emit_expr_at(subscript, 0)!
			register := e.accumulator(stmt.line, stmt.col)!
			base := e.scratch(stmt.line, stmt.col)!
			e.reference(e.target.address_of(base, 0), .global_address, stmt.target, base.name)
			e.append(e.target.address_of_element(base, register, object.width, 0, register)!)
			address := e.value_slot(0)
			e.store_accumulator(address, stmt.line, stmt.col)!
			e.emit_expr_at(expr, 1)!
			address_register := e.scratch(stmt.line, stmt.col)!
			if object.floating {
				if !e.floating_of(expr) && e.is_a_pointer(expr) {
					e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in an element that holds a double, and there is no conversion between them')
					return error('pointer into a double')
				}
				e.convert_to_double(expr, stmt.line, stmt.col)!
				value := e.float_accumulator(stmt.line, stmt.col)!
				e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
				e.append(e.target.store_double_indirect(address_register, value)!)
				return
			}
			if e.floating_of(expr) {
				e.convert_to_int(expr, stmt.line, stmt.col)!
				value := e.accumulator(stmt.line, stmt.col)!
				e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
				e.append(e.target.store_indirect(address_register, value, object.width)!)
				return
			}
			if width := e.width_of(expr) {
				if width != object.width && !(object.width == 1 && width == 4) {
					e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${width} bytes is stored into an element of ${stmt.target}, which holds ${object.width}')
					return error('width mismatch')
				}
			} else {
				e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
				return error('unknown width')
			}
			value := e.accumulator(stmt.line, stmt.col)!
			e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
			e.append(e.target.store_indirect(address_register, value, object.width)!)
			return
		}
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned to, and no local of that name is in scope')
		return error('unknown assignment target')
	}
	if slot.count == 0 {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an element of ${stmt.target} is written, and ${stmt.target} is not an array')
		return error('not an array')
	}
	e.emit_expr_at(subscript, 0)!
	base := e.frame_pointer(stmt.line, stmt.col)!
	register := e.accumulator(stmt.line, stmt.col)!
	e.append(e.target.address_of_element(base, register, slot.width, slot.offset, register)!)
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	e.emit_expr_at(expr, 1)!
	address_register := e.scratch(stmt.line, stmt.col)!
	if slot.floating {
		// An element of an array of doubles: the value is converted to a double
		// if it is not one, and written with the instruction that moves eight
		// bytes of a double rather than with the integer store, which would
		// write half of it.
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in an element that holds a double, and there is no conversion between them')
			return error('pointer into a double')
		}
		e.convert_to_double(expr, stmt.line, stmt.col)!
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_double_indirect(address_register, value)!)
		return
	}
	if e.floating_of(expr) {
		e.convert_to_int(expr, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, slot.width)!)
		return
	}
	width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	if width != slot.width && !(slot.width == 1 && width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${width} bytes is stored into an element of ${slot.width}')
		return error('width mismatch')
	}
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, slot.width)!)
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
	e.emit_test(e.floating_of(cond), stmt.line, stmt.col)!
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
	e.emit_test(e.floating_of(cond), stmt.line, stmt.col)!
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
// The width is the width of the type as it was written: an int is four bytes, a
// pointer is the machine's word and a double is eight. A type that is none of
// those is reported where it was written, because storing it at a width that
// happens to fit would make every value it touches silently wrong.
//
// A declaration with a count is an array: it takes a block of storage, one
// element after another, and what the name is worth in an expression is the
// address of the first of them. The block is rounded up to the machine's word
// like every other slot, so no element straddles the end of it.
fn (mut e Emitter) declare(name string, written string, count int, bytes int, line int, col int) !Slot {
	if e.scopes.len > 0 {
		if name in e.scopes[e.scopes.len - 1] {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is declared twice in the same block')
			return error('redeclared')
		}
	}
	// An object of an aggregate type is sized by the layout the reader worked
	// out rather than by its spelling: `struct S` is a name the back end has no
	// width for, and the members are what say how many bytes the object is.
	width := if bytes > 0 {
		bytes
	} else {
		e.type_width(written) or {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is declared ${written}, and this back end stores ints, chars, doubles and pointers only')
			return error('unsupported type')
		}
	}
	slot := if count > 0 { e.reserve(count * width) } else { e.reserve(width) }
	block := Slot{
		offset:   slot.offset
		width:    width
		count:    count
		floating: bytes == 0 && e.writes_a_double(written)
		bytes:    bytes
	}
	e.scopes[e.scopes.len - 1][name] = block
	return block
}

// type_width is the width of a value of a type as the source wrote it. An int is
// four bytes; a char is one, which is the width of its slot and of the byte the
// machine stores into it, while every read of it widens to an int (see
// width_of); a pointer is the machine's word, which is what makes `char *` and
// `char **` read and write the same way; and a double is eight bytes, which is
// what the machine moves with one instruction. Everything else is a type this
// back end has no instruction for.
fn (e Emitter) type_width(written string) ?int {
	if written == 'int' {
		return 4
	}
	if written == 'char' {
		return 1
	}
	if written == 'double' {
		return 8
	}
	if written.contains('*') {
		return e.target.word_size
	}
	return none
}

// writes_a_double says whether a type as it was written names a double, which is
// the one type this back end moves through the floating-point register file. The
// spelling is what a declaration carries, so this is where a declaration decides
// which file its storage is read and written through.
fn (e Emitter) writes_a_double(written string) bool {
	return written == 'double'
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
//
// A double is tested the same way through the other file, but the comparison
// that produces the flag is a different one and the flags it leaves mean
// something else: a NaN is not equal to zero, so it is true as a condition, and
// only the pair of flags `not equal or unordered` reads that. The register is
// cleared by exclusive-or with itself rather than read from memory, so this costs
// no constant.
fn (mut e Emitter) emit_test(floating bool, line int, col int) !void {
	register := e.accumulator(line, col)!
	if floating {
		zero := e.float_scratch(line, col)!
		value := e.float_accumulator(line, col)!
		other := e.scratch(line, col)!
		e.append(e.target.zero_double(zero)!)
		e.append(e.target.double_comparison('!=', value, zero, register, other)!)
	}
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

// remainder is the third register an operation needs when the accumulator and the
// scratch one are each holding something else: a copy of an object moves its bytes
// through a register of its own while the two addresses are loaded again.
fn (mut e Emitter) remainder(line int, col int) !backend.Register {
	return e.target.remainder() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no third register for a copy that holds two addresses")
		return error('no remainder register')
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
// position, at the width the argument is passed at. A char argument is read at
// its own width whatever width the call asks for, because the read is what
// widens it: four bytes from a one-byte slot would take the padding with them.
fn (mut e Emitter) load_argument(slot Slot, register backend.Register, width int, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	if slot.width == 1 {
		e.append(e.target.load_slot(base, slot.offset, register, 1)!)
		return
	}
	e.append(e.target.load_slot(base, slot.offset, register, width)!)
}

// float_accumulator is the register a double is computed in, and float_scratch is
// where the right-hand value of an operation on two of them waits. They are the
// same two roles the general register file has, in the machine's other file: a
// value in flight is in one of the two accumulators depending on its type, which
// is what the `floating` flag on a slot and the clause on an expression say.
fn (mut e Emitter) float_accumulator(line int, col int) !backend.Register {
	return e.target.float_return() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no floating-point result register, and a double has nowhere to be computed")
		return error('no floating result register')
	}
}

fn (mut e Emitter) float_scratch(line int, col int) !backend.Register {
	return e.target.float_scratch() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no floating-point scratch register for the second half of an operation")
		return error('no floating scratch register')
	}
}

// store_double_register writes one floating-point register into a slot.
fn (mut e Emitter) store_double_register(slot Slot, register backend.Register, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.store_double_slot(base, slot.offset, register)!)
}

// store_double_accumulator writes the floating-point accumulator into a slot,
// and load_double_accumulator reads one back. They are store_accumulator and
// load_accumulator one file over: the slot holds a double, so the eight bytes
// move with the instruction that moves a double.
fn (mut e Emitter) store_double_accumulator(slot Slot, line int, col int) !void {
	register := e.float_accumulator(line, col)!
	e.store_double_register(slot, register, line, col)!
}

fn (mut e Emitter) load_double_accumulator(slot Slot, line int, col int) !void {
	register := e.float_accumulator(line, col)!
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_double_slot(base, slot.offset, register)!)
}

// load_double_argument reads an argument slot into the floating-point register
// that carries its position. It mirrors load_argument, and a double is always
// eight bytes wide, so there is no promotion to take into account here.
fn (mut e Emitter) load_double_argument(slot Slot, register backend.Register, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_double_slot(base, slot.offset, register)!)
}

// floating_of says whether an expression is a double, which is what decides
// which register file its value travels in and which instruction computes it: a
// constant written as one, a name whose storage holds one, a call that returns
// one, and an operation on one, while a comparison answers an int however its
// operands are spelled.
//
// The clause the parser resolved is the answer where there is one. An operation
// is asked its own type rather than its operands, which is the difference between
// one lookup and a descent per term: measured, the chain `1 + 1 + ... + 1` of
// twenty thousand terms is folded into one constant by the emitter, and asking its
// operands term by term instead took the stack out in this function before the
// fold could run.
//
// A tree assembled by hand carries no clause, so the shape is asked instead, down
// to the depth the emitter's own walk stops at: a floating constant is a double, a
// name is a double if its slot is, and a call is a double if the function returns
// one. A tree this reader cannot type is then not a tree that can take the stack
// out either.
fn (e Emitter) floating_of(expr ast.Expr) bool {
	return e.floating_at(expr, 0)
}

fn (e Emitter) floating_at(expr ast.Expr, depth int) bool {
	if depth > max_emit_depth {
		return false
	}
	return match expr {
		ast.FloatLit {
			true
		}
		ast.Ident {
			if slot := e.lookup(expr.name) {
				// The name of an array is the address of its first element,
				// which is a pointer and not a double, however its elements
				// are read.
				slot.count == 0 && slot.floating
			} else {
				e.global_is_double(expr.name)
			}
		}
		ast.Unary {
			// The sign change and the unary plus preserve the type; the
			// logical not and the complement produce an int, and the type the
			// parser resolved says which one this is.
			if expr.typ.kind != .unknown {
				return expr.typ.is_floating()
			}
			(expr.op == '-' || expr.op == '+') && e.floating_at(expr.expr, depth + 1)
		}
		ast.Binary {
			if expr.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
				false
			} else if expr.typ.kind != .unknown {
				// Both operands of an arithmetic operator have one class after
				// the usual conversions, so the node's own type answers for the
				// whole chain.
				expr.typ.is_floating()
			} else {
				e.floating_at(expr.left, depth + 1) || e.floating_at(expr.right, depth + 1)
			}
		}
		ast.Index {
			// An element of an array of doubles is a double, and the array it
			// belongs to is what says so: a counted slot or a top-level object
			// with a double element type. An element of a char array is the int
			// the load widens it to, so it is not.
			if slot := e.lookup(expr.name) {
				slot.count > 0 && slot.floating
			} else {
				e.global_element_is_double(expr.name)
			}
		}
		ast.Field {
			// A member whose declared type is a double is a double, and the
			// reader kept that type as the spelling of the member.
			e.writes_a_double(expr.spelling)
		}
		ast.Call {
			// A call that hands an object back hands its bytes over in the
			// register its class names, so the floating class is the same answer
			// as a function that returns a double.
			e.returns[expr.name] == 'double' || e.return_classes[expr.name].first_floating
		}
		else {
			false
		}
	}
}

// convert_to_double makes sure the value just computed is a double, widening the
// int in the accumulator when it is not. It is the C conversion between an
// integer type and a floating one, applied where the language asks for it: an
// operand of an operation the other side made floating, a value stored into a
// slot that holds a double, an argument a parameter is a double for, and the
// value a function returning a double returns.
fn (mut e Emitter) convert_to_double(expr ast.Expr, line int, col int) !void {
	if e.floating_of(expr) {
		return
	}
	if e.is_a_pointer(expr) {
		// A pointer is not an arithmetic type, so there is no conversion to
		// make and a value that quietly became a double would be an address the
		// program can no longer follow.
		e.diagnostics << problem(line, col, 'unsupported: a pointer is not converted to a double')
		return error('pointer to double')
	}
	integer := e.accumulator(line, col)!
	double_register := e.float_accumulator(line, col)!
	e.append(e.target.int_to_double(double_register, integer)!)
}

// convert_to_int is the other direction: the double in the floating-point
// accumulator is truncated towards zero into the int in the general one, which is
// what the language defines an integer conversion from a floating type to do. A
// value out of range is not reported, because the conversion's result is
// undefined for one and the instruction's answer is what every compiler on this
// machine gives.
fn (mut e Emitter) convert_to_int(expr ast.Expr, line int, col int) !void {
	if !e.floating_of(expr) {
		return
	}
	double_register := e.float_accumulator(line, col)!
	integer := e.accumulator(line, col)!
	e.append(e.target.double_to_int(integer, double_register)!)
}

// is_a_pointer says whether an expression is a pointer: the width of a word that
// is not a double is one, and a string is the address of its bytes.
fn (e Emitter) is_a_pointer(expr ast.Expr) bool {
	if expr.typ.kind == .pointer || expr.typ.is_array() {
		return true
	}
	if expr is ast.StrLit {
		return true
	}
	if e.floating_of(expr) {
		return false
	}
	if expr is ast.Ident {
		if slot := e.lookup(expr.name) {
			return slot.count > 0
		}
		if object := e.global_shape(expr.name) {
			return object.count > 0
		}
	}
	return false
}

// store_value writes the accumulator into a slot, after checking that the value
// is one the slot can hold. A constant is written at the width of the slot,
// because a constant is the one value that says nothing about its own width
// (`char *p = 0` is a zero of pointer width). Any other value has to have the
// slot's width already: storing a pointer in four bytes or an int in eight is a
// wrong value rather than a narrow one.
//
// A slot holding a double is the exception to that, and the reason the check is
// written around the conversion: the language converts an integer to a double
// and a double to an integer where one is stored in the other, which is a
// different value of a different width rather than a wrong one, so the value is
// converted first and the width it had no longer describes it. A pointer is one
// of the two conversions that does not exist, and it is refused by name.
fn (mut e Emitter) store_value(slot Slot, expr ast.Expr, line int, col int) !void {
	floating := e.floating_of(expr)
	if slot.floating {
		if !floating && e.is_a_pointer(expr) {
			e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a slot that holds a double, and there is no conversion between them')
			return error('pointer into a double')
		}
		e.convert_to_double(expr, line, col)!
		e.store_double_accumulator(slot, line, col)!
		return
	}
	if floating {
		e.convert_to_int(expr, line, col)!
		e.store_accumulator(slot, line, col)!
		return
	}
	if e.constant(expr) == none {
		width := e.width_of(expr) or {
			e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
			return error('unknown width')
		}
		if width != slot.width && !(slot.width == 1 && width == 4) {
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
		ast.FloatLit {
			// A floating constant is eight bytes of read-only data and an
			// instruction that says where they are. The machine has no form of
			// a floating move that takes the value in the instruction, so the
			// bytes go in the image and are read from it, which is also what
			// makes two constants with the same value one entry.
			e.intern_double(expr.value)
			register := e.float_accumulator(expr.line, expr.col)!
			e.reference(e.target.load_double_constant(register, 0)!, .float_constant, float_key(expr.value), register.name)
		}
		ast.Ident {
			slot := e.lookup(expr.name) or {
				// Not a local: a top-level object is storage the image holds,
				// and its name is the address of that storage. What is read is
				// the value at the width the object was defined with, which is
				// the same load an element of an array takes.
				if object := e.global_of(expr.name) {
					register := e.accumulator(expr.line, expr.col)!
					e.reference(e.target.address_of(register, 0), .global_address, expr.name, register.name)
					if object.count > 0 {
						// The name of an array is the address of its first
						// element.
						return
					}
					if object.floating {
						// A double is read through its address with the
						// instruction that moves one, and the address is in
						// the general file, so nothing is disturbed by reading
						// into the floating one.
						double_register := e.float_accumulator(expr.line, expr.col)!
						e.append(e.target.load_double_indirect(register, double_register)!)
						return
					}
					e.append(e.target.load_indirect(register, register, object.width)!)
					return
				}
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is not a constant and is not a local of this function')
				return error('unknown name')
			}
			if slot.bytes > 0 {
				// The name of an object of an aggregate type is the object, and
				// a value of a struct type is not a value this back end moves:
				// a member of it and its address are, so the refusal names the
				// shape that is not implemented instead of reading the object's
				// first bytes as an int.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of an aggregate type, and using it as a value is not implemented; a member of it, or its address, is')
				return error('aggregate value')
			}
			if slot.count > 0 {
				// An array's name is worth the address of its first element: in
				// an expression it is what a pointer is, which is what makes
				// `puts(buf)` and `strlen(buf)` work with an array.
				register := e.accumulator(expr.line, expr.col)!
				base := e.frame_pointer(expr.line, expr.col)!
				e.append(e.target.address_of_slot(base, slot.offset, register))
				return
			}
			if slot.floating {
				e.load_double_accumulator(slot, expr.line, expr.col)!
				return
			}
			e.load_accumulator(slot, expr.line, expr.col)!
		}
		ast.Field {
			// A member is the value at an offset into an object: the address of
			// the object plus the offset the model's layout put the member at,
			// read at the width of the member's type. A double member is read
			// with the instruction that moves one rather than with the integer
			// load of the same width.
			width := e.type_width(expr.spelling) or {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the member ${expr.name}.${expr.member} is declared ${expr.spelling}, and this back end stores ints, chars, doubles and pointers only')
				return error('unsupported member type')
			}
			e.address_of_member(expr.name, expr.index, expr.offset, expr.through_pointer, depth, expr.line, expr.col)!
			register := e.accumulator(expr.line, expr.col)!
			if e.writes_a_double(expr.spelling) {
				double_register := e.float_accumulator(expr.line, expr.col)!
				e.append(e.target.load_double_indirect(register, double_register)!)
				return
			}
			e.append(e.target.load_indirect(register, register, width)!)
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
			// A call's value arrives in the register the machine returns
			// results in, which is the register a value is expected to be in,
			// so a call in an expression is emitted where a name would be. Its
			// arguments are parked one level up, so that a call inside a larger
			// expression does not hand them to the slots the expression around
			// it is using.
			//
			// A function the file defines says what it returns, and a void one
			// returns nothing: reading that as a value is reported rather than
			// read from a register the call happened to leave something in.
			if e.returns[expr.name] == 'void' {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the call to ${expr.name} is used as a value, and ${expr.name} returns void')
				return error('void value')
			}
			e.emit_call(expr, depth + 1)!
		}
		ast.Index {
			// One element of an array: the address of the element, computed from
			// the index scaled by the width of an element, and then the value
			// read through it. The load is the same one a frame slot uses, so an
			// element of a char array arrives as the int the language promotes
			// it to.
			slot := e.lookup(expr.name) or {
				// A top-level array: its storage is in the image, so the
				// address of an element is an offset from the address of the
				// object rather than from the frame.
				if object := e.global_of(expr.name) {
					if object.count == 0 {
						e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is read as an array, and it is not one')
						return error('not an array')
					}
					e.emit_expr_at(expr.index, depth + 1)!
					register := e.accumulator(expr.line, expr.col)!
					// The address of the object goes into the scratch register
					// after the index is computed, so that the index expression
					// cannot overwrite it on the way.
					base := e.scratch(expr.line, expr.col)!
					e.reference(e.target.address_of(base, 0), .global_address, expr.name, base.name)
					e.append(e.target.address_of_element(base, register, object.width, 0, register)!)
					if object.floating {
						double_register := e.float_accumulator(expr.line, expr.col)!
						e.append(e.target.load_double_indirect(register, double_register)!)
						return
					}
					e.append(e.target.load_indirect(register, register, object.width)!)
					return
				}
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is not a local of this function')
				return error('unknown name')
			}
			if slot.count == 0 {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${expr.name} is read, and ${expr.name} is not an array')
				return error('not an array')
			}
			e.emit_expr_at(expr.index, depth + 1)!
			base := e.frame_pointer(expr.line, expr.col)!
			register := e.accumulator(expr.line, expr.col)!
			e.append(e.target.address_of_element(base, register, slot.width, slot.offset, register)!)
			if slot.floating {
				// An element of an array of doubles: the address is in a general
				// register and the value is read into a floating-point one, which
				// is the same split the load of a double global makes.
				double_register := e.float_accumulator(expr.line, expr.col)!
				e.append(e.target.load_double_indirect(register, double_register)!)
				return
			}
			e.append(e.target.load_indirect(register, register, slot.width)!)
		}
	}
}

// emit_unary writes the operators that take one value: the sign change, the
// bitwise complement, and the logical not, which is a comparison with zero. The
// unary plus is the one that computes nothing, since the value is already where
// it belongs.
//
// emit_address takes the address of a name. A local lives in the frame, so its
// address is its place in the frame; an object defined at the top level lives in
// the image, so its address is the one the layout fills in. An array's name is
// already the address of its first element, which is why `&a` and `a` are worth
// the same address here: the language tells those two types apart, and this back
// end has no types to tell them apart with.
fn (mut e Emitter) emit_address(unary ast.Unary) !void {
	register := e.accumulator(unary.line, unary.col)!
	if unary.expr is ast.Ident {
		name := unary.expr.name
		if slot := e.lookup(name) {
			base := e.frame_pointer(unary.line, unary.col)!
			e.append(e.target.address_of_slot(base, slot.offset, register))
			return
		}
		if _ := e.global_of(name) {
			e.reference(e.target.address_of(register, 0), .global_address, name, register.name)
			return
		}
	}
	e.diagnostics << problem(unary.line, unary.col, 'unsupported: the address of ${describe_target(unary.expr)} is not implemented, and only a local or a top-level object has one this back end can take')
	return error('no address')
}

// describe_target names what an address was taken of, so the diagnostic says
// which expression it was looking at.
fn describe_target(expr ast.Expr) string {
	return match expr {
		ast.Ident {
			expr.name
		}
		ast.Index {
			'${expr.name}[...]'
		}
		ast.StrLit {
			'a string literal'
		}
		ast.Call {
			'the value of a call'
		}
		else {
			'an expression'
		}
	}
}

fn (mut e Emitter) emit_unary(unary ast.Unary, depth int) !void {
	if unary.op == '&' {
		// Taking an address is not a computation on a value: the operand is not
		// read at all, and what is taken is where it lives.
		return e.emit_address(unary)
	}
	floating := e.floating_of(unary.expr)
	if floating {
		// Three operators have a meaning for a double: the sign change, the
		// unary plus that computes nothing, and the logical not, which asks
		// whether the value is zero. The complement is a bit operation on an
		// integer, and ISO C refuses it on a floating operand rather than
		// defining one.
		if unary.op != '+' && unary.op != '-' && unary.op != '!' {
			e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} takes an integer operand, and this one is a double')
			return error('operator on a double')
		}
	} else if width := e.width_of(unary.expr) {
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
			if floating {
				// The machine negates an integer and has no instruction that
				// negates a double, so the sign bit is flipped through a
				// general register. Subtracting from zero would round a
				// signalling NaN into a quiet one and turn -0.0 into 0.0,
				// neither of which is the value the operator asks for.
				e.append(e.target.negate_double(e.float_accumulator(unary.line, unary.col)!, register)!)
			} else {
				e.append(e.target.negate(register)!)
			}
		}
		'~' {
			e.append(e.target.complement(register)!)
		}
		'!' {
			if floating {
				// `!d` is one exactly when d compares equal to zero, and the
				// comparison against zero is the one that answers it: a NaN is
				// not equal to zero, so the answer there is zero, which is what
				// the language says it is.
				zero := e.float_scratch(unary.line, unary.col)!
				value := e.float_accumulator(unary.line, unary.col)!
				other := e.scratch(unary.line, unary.col)!
				e.append(e.target.zero_double(zero)!)
				e.append(e.target.double_comparison('==', value, zero, register, other)!)
			} else {
				e.append(e.target.logical_not(register)!)
			}
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
//
// Each step of the chain is computed in the file its result belongs to: an
// arithmetic step with a double on either side is a double and lands in the
// floating-point file, a comparison lands in the general one as an int, and a
// step of two integers is unchanged. Which file the value being carried up the
// spine is in is tracked as the chain is folded, because a step that converts
// changes it: `1 + 2.5` widens the int on the way, and `d + 1 + 2` has a double
// under it rather than an int.
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
		//
		// What is in the accumulator at this point is the step's left operand,
		// because the spine was built by walking left: the last step of the
		// chain has the innermost expression under it, and every step before
		// that one has the step after it. That is what the conversion asks
		// about, and it is why the class of the value being carried does not
		// have to be tracked here.
		slot := e.value_slot(depth)
		if e.computed_in_doubles(step) {
			e.convert_to_double(step.left, step.line, step.col)!
			e.store_double_accumulator(slot, step.line, step.col)!
			e.emit_expr_at(step.right, depth + 1)!
			e.convert_to_double(step.right, step.line, step.col)!
			e.move_double_to_scratch(step.line, step.col)!
			e.load_double_accumulator(slot, step.line, step.col)!
			e.apply_double(step)!
			continue
		}
		e.store_accumulator(slot, step.line, step.col)!
		e.emit_expr_at(step.right, depth + 1)!
		e.move_to_scratch(step.line, step.col)!
		e.load_accumulator(slot, step.line, step.col)!
		e.apply_binary(step)!
	}
}

// computed_in_doubles says whether a step's operands are computed as doubles.
// The language's usual arithmetic conversions make a step with a double on
// either side a double step, whether the operator is arithmetic or a comparison:
// `d < 1` compares a double with the int widened to one, and answers with an int.
// A step that is neither a comparison nor one of the four arithmetic operators is
// refused where it is folded, because the operators that need integer operands
// do not have a floating form the language defines.
fn (e Emitter) computed_in_doubles(step ast.Binary) bool {
	floating := e.floating_of(step.left) || e.floating_of(step.right)
	if !floating {
		return false
	}
	return step.op == '+' || step.op == '-' || step.op == '*' || step.op == '/'
		|| step.op in ['==', '!=', '<', '>', '<=', '>=']
}

// apply_double does the operation the tree asked for with both values in the
// floating-point file, the left in the accumulator and the right in the scratch
// register, and leaves a double in the accumulator or an int there when the
// operator was a comparison.
fn (mut e Emitter) apply_double(step ast.Binary) !void {
	value := e.float_accumulator(step.line, step.col)!
	other := e.float_scratch(step.line, step.col)!
	match step.op {
		'+', '-', '*', '/' {
			e.append(e.target.double_arithmetic(step.op, value, other)!)
		}
		'==', '!=', '<', '>', '<=', '>=' {
			// The answer to a comparison is an int, so it is read out of the
			// flags into the general register file: the floating-point one
			// holds values and not truth values.
			integer := e.accumulator(step.line, step.col)!
			byte_scratch := e.scratch(step.line, step.col)!
			e.append(e.target.double_comparison(step.op, value, other, integer, byte_scratch)!)
		}
		else {
			e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} takes integer operands, and one of these is a double')
			return error('operator on a double')
		}
	}
}

// move_double_to_scratch puts the floating-point accumulator into the
// floating-point scratch register, which is where the operation that is about to
// be applied expects the right-hand value.
fn (mut e Emitter) move_double_to_scratch(line int, col int) !void {
	result := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	e.append(e.target.move_double(other, result)!)
}

// check_int_operands reports an operand that is not an int. The operators
// emitted here compute with four-byte values; a pointer on either side is a
// different operation, an address plus a distance or two addresses compared, and
// computing it at the width of whatever the other side was would be a wrong
// program rather than a wrong answer. A double is the one eight-byte value that
// is not a pointer: it is computed by the other path in emit_binary, so it is
// passed over here rather than reported.
fn (mut e Emitter) check_int_operands(binary ast.Binary) !void {
	for operand in [binary.left, binary.right] {
		if e.floating_of(operand) {
			continue
		}
		if width := e.width_of(operand) {
			if width != 4 {
				// Eight bytes that are not a double is the width of a pointer
				// and the only other width this back end has, so the diagnostic
				// can say what it is.
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
	e.emit_test(e.floating_of(binary.left), binary.line, binary.col)!
	if is_and {
		e.branch(.branch_zero, settles, binary.line, binary.col)!
	} else {
		e.branch(.branch_nonzero, settles, binary.line, binary.col)!
	}
	// The left side did not settle it, so the right side is the answer.
	e.emit_expr_at(binary.right, depth + 1)!
	e.emit_test(e.floating_of(binary.right), binary.line, binary.col)!
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
		ast.FloatLit {
			// A floating constant is a double: the eight bytes of one live in
			// the image and the instruction reads them into a floating-point
			// register.
			8
		}
		ast.StrLit {
			// The value of a string is the address of its bytes.
			e.target.word_size
		}
		ast.Field {
			// What is read at the member's offset is a value of the member's
			// type, and the member's type is what the reader worked out from
			// the layout. A char member is an int when it is read, which is the
			// promotion every char gets and the same answer an element of a char
			// array is sized at.
			width := e.type_width(expr.spelling) or { return none }
			return if width == 1 { 4 } else { width }
		}
		ast.Ident {
			slot := e.lookup(expr.name) or {
				// A top-level object: an array's name is the address of its
				// first element, a char is the int it is read as, and anything
				// else is as wide as it was defined.
				if object := e.global_shape(expr.name) {
					if object.count > 0 {
						return e.target.word_size
					}
					return if object.width == 1 { 4 } else { object.width }
				}
				return none
			}
			// An array's name is the address of its first element, which is a
			// pointer. A char in an expression is an int: the language promotes
			// it, and the load that reads it is where that happens, so the width
			// of the value is the width of the read rather than of the slot.
			if slot.count > 0 {
				e.target.word_size
			} else if slot.width == 1 {
				4
			} else {
				slot.width
			}
		}
		ast.Call {
			// A call's value has the width the language returns it with: a
			// double is eight bytes, and everything else this back end emits is
			// four.
			if e.returns[expr.name] == 'double' {
				8
			} else {
				4
			}
		}
		ast.Index {
			// An element is the width of an element of the array it belongs to,
			// with a char promoted to the int the load widens it to.
			slot := e.lookup(expr.name) or { return none }
			if slot.count == 0 {
				return none
			}
			if slot.width == 1 {
				4
			} else {
				slot.width
			}
		}
		ast.Unary {
			if expr.op == '!' {
				4
			} else if expr.op == '&' {
				// The address of a value is a pointer, whatever the width of the
				// value that lives there.
				e.target.word_size
			} else {
				e.width_of(expr.expr) or { return none }
			}
		}
		ast.Binary {
			if expr.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
				4
			} else if e.floating_of(expr) {
				// An arithmetic step with a double on either side is a double,
				// whichever class the other operand was: the two widths are not
				// equal in the tree, and the value the step produces is one
				// double either way.
				8
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
// Where an argument goes is decided before it is evaluated, because the machine
// has two argument sequences and an argument belongs to one of them: an int is
// passed in the general file and a double in the floating-point one, and each
// file numbers its own arguments from the beginning. `printf("%f", x)` is the
// shape that shows it: the format string is the first general argument and the
// double is also the first argument of the floating file.
//
// A name the file defines is called by its distance in the code, so a call to a
// function in the same translation unit binds to that definition; every other
// name is a symbol the loader resolves before the program starts.
fn (mut e Emitter) emit_call(call ast.Call, depth int) !void {
	mut places := []ArgPlace{cap: call.args.len}
	mut integers := 0
	mut doubles := 0
	mut stacked := 0
	for i, arg in call.args {
		// The two sequences run out separately: a call with six ints and nine
		// doubles has three doubles on the stack and every int in a register.
		// The ones a sequence ran out for go on the stack in the order they
		// were written, which is the order the callee reads them in.
		//
		// An object of an aggregate type takes one register like a value, and
		// which file that register belongs to is the class its members make and
		// not a property of the expression: a struct of one double travels where
		// a double does.
		class := e.aggregate_argument(call, i)
		if c := class {
			if c.count > 2 {
				e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${i + 1} of the call to ${call.name} is an object of ${c.bytes} bytes or ${c.count} eightbytes, and this compiler hands over an aggregate of at most two')
				return error('aggregate argument too large')
			}
			if c.count == 2 {
				// Two eightbytes: each takes a register of its own class, and
				// the object goes on the stack whole when either one has none
				// left, which is the answer pair_places gives both sides.
				placed := pair_places(e.target, c.first_floating, c.second_floating,
					integers, doubles)
				if placed.registers {
					places << ArgPlace{
						floating:        c.first_floating
						position:        placed.first
						paired:          true
						second_floating: c.second_floating
						second_position: placed.second
					}
					integers = placed.integers
					doubles = placed.doubles
					continue
				}
				places << ArgPlace{
					stack:    true
					position: stacked
					paired:   true
				}
				stacked += 2
				continue
			}
		}
		mut floating := e.argument_is_double(call, i, arg)
		if c := class {
			floating = c.first_floating
		}
		if floating {
			if e.target.float_arg_reg(doubles) != none {
				places << ArgPlace{
					floating: true
					position: doubles
				}
				doubles++
				continue
			}
			places << ArgPlace{
				floating: true
				position: stacked
				stack:    true
			}
			stacked++
			continue
		}
		if e.target.arg_reg(integers) != none {
			places << ArgPlace{
				floating: false
				position: integers
			}
			integers++
			continue
		}
		places << ArgPlace{
			floating: false
			position: stacked
			stack:    true
		}
		stacked++
	}
	for i, arg in call.args {
		place := places[i]
		line := expr_line(arg)
		col := expr_col(arg)
		if place.paired {
			// An object of two eightbytes is not read into a slot at all: both
			// of its eightbytes are read from the object itself, after the stack
			// this call takes has been made, so that nothing disturbs the
			// registers they went into.
			continue
		}
		if class := e.aggregate_argument(call, i) {
			// An object is handed over as its bytes: the address of the object
			// is taken and the one eightbyte the convention puts in a register
			// is read from it. A struct of one double is bits moved through the
			// floating file, which is the same eight bytes.
			e.address_of_object(arg, depth + i + 1)!
			base := e.accumulator(line, col)!
			if class.first_floating {
				double_register := e.float_accumulator(line, col)!
				e.append(e.target.load_double_indirect(base, double_register)!)
				e.store_double_accumulator(e.value_slot(depth + i), line, col)!
				continue
			}
			e.append(e.target.load_indirect(base, base, class.bytes)!)
			e.store_accumulator(e.value_slot(depth + i), line, col)!
			continue
		}
		if place.floating {
			e.emit_expr_at(arg, depth + i + 1)!
			e.convert_to_double(arg, line, col)!
			e.store_double_accumulator(e.value_slot(depth + i), line, col)!
			continue
		}
		e.emit_expr_at(arg, depth + i + 1)!
		// A double handed to a parameter that is not one is truncated to the
		// integer the parameter holds, which is the conversion the language
		// defines between the two classes.
		e.convert_to_int(arg, line, col)!
		e.store_accumulator(e.value_slot(depth + i), line, col)!
	}
	// The arguments past the registers go on the stack, and the convention puts
	// the first of them where the call's own stack pointer is: they are pushed in
	// reverse, so the one written first is the one the callee finds first, and one
	// word is taken first when an odd number of them is pushed so that the call is
	// made with the stack aligned as the convention requires.
	if stacked > 0 {
		width := e.target.word_size
		if stacked % 2 == 1 {
			e.append(e.target.frame_reserve(u32(width)))
			e.stack_pushed += width
		}
		for i := places.len - 1; i >= 0; i-- {
			place := places[i]
			if !place.stack {
				continue
			}
			arg := call.args[i]
			line := expr_line(arg)
			col := expr_col(arg)
			if place.paired {
				// An object in memory goes on the stack in one piece: the second
				// eightbyte is pushed first, because the stack grows down and the
				// first eightbyte is the one the callee reads at the lower
				// address.
				e.address_of_object(arg, depth + i + 1)!
				base := e.accumulator(line, col)!
				low := e.remainder(line, col)!
				e.append(e.target.load_indirect(base, low, e.target.word_size)!)
				e.append(e.target.add_immediate(base, e.target.word_size))
				high := e.scratch(line, col)!
				e.append(e.target.load_indirect(base, high, e.target.word_size)!)
				e.append(e.target.push_register(high))
				e.append(e.target.push_register(low))
				e.stack_pushed += 2 * width
				continue
			}
			slot := e.value_slot(depth + i)
			// A double in a slot is eight bytes of a value, and handing it over
			// on the stack is moving those eight bytes: the bits are pushed
			// through a general register, because the machine has no push from
			// the floating file.
			pushed_width := if place.floating {
				e.target.word_size
			} else {
				e.passed_width(call, i, arg, false)!
			}
			register := e.accumulator(line, col)!
			e.load_argument(slot, register, pushed_width, line, col)!
			e.append(e.target.push_register(register))
			e.stack_pushed += width
		}
	}
	for i, arg in call.args {
		place := places[i]
		line := expr_line(arg)
		col := expr_col(arg)
		if place.paired && !place.stack {
			// The object's own bytes, read straight into the two argument
			// registers: the second eightbyte is eight bytes further in, and the
			// general file is handed only the bytes the object has left. An
			// object whose two eightbytes did not both fit is on the stack and
			// was pushed already, and reading a register for it would hand the
			// object over twice and clobber the arguments beside it.
			e.address_of_object(arg, depth + i + 1)!
			base := e.accumulator(line, col)!
			class := e.aggregate_argument(call, i) or {
				e.diagnostics << problem(call.line, call.col, 'internal: an object handed over in two registers has no class in the signature of ${call.name}')
				return error('no class')
			}
			e.load_argument_eightbyte(base, 0, e.target.word_size, place.floating,
				place.position, line, col)!
			e.load_argument_eightbyte(base, e.target.word_size, class.bytes - e.target.word_size,
				place.second_floating, place.second_position, line, col)!
			continue
		}
		slot := e.value_slot(depth + i)
		if place.stack {
			continue
		}
		if place.floating {
			register := e.target.float_arg_reg(place.position) or {
				e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} passes more doubles than the machine has registers for')
				return error('too many arguments')
			}
			e.load_double_argument(slot, register, line, col)!
			continue
		}
		register := e.target.arg_reg(place.position) or {
			e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} has more arguments than the machine has registers for')
			return error('too many arguments')
		}
		width := e.passed_width(call, i, arg, place.floating)!
		e.load_argument(slot, register, width, line, col)!
	}
	if call.name in e.program.defined {
		e.reference(e.target.call_near(0), .call_local, call.name, '')
		e.release_call_stack()
		return
	}
	e.import_symbol(call.name)
	// A library function this compiler has no prototype for may be variadic, and
	// the machine's convention wants the number of vector registers the call uses
	// in the low byte of the result register before a call like that. A call with
	// no doubles says zero, and printf reads the count to decide whether it has
	// floating arguments to fetch. The count goes in after the argument registers
	// are loaded, because loading them is the last thing that could disturb it.
	result := e.accumulator(call.line, call.col)!
	e.append(e.target.move_immediate32(result, u32(doubles))!)
	e.reference(e.target.call_slot(0), .call_import, call.name, '')
	e.release_call_stack()
}

// release_call_stack gives back the stack a call took for the arguments its
// registers ran out for. It runs after the call and not before it, because the
// arguments have to still be on the stack when the callee reads them; that is
// the one ordering this has to get right, and the machine code says so when it
// is wrong.
fn (mut e Emitter) release_call_stack() {
	if e.stack_pushed > 0 {
		e.append(e.target.stack_release(u32(e.stack_pushed)))
		e.stack_pushed = 0
	}
}

// ArgPlace is where one argument is passed: which of the machine's two files
// carries it, and its position in that file's own sequence of arguments.
struct ArgPlace {
	floating bool
	// position is the register in the argument's own sequence, or the byte
	// offset from the stack pointer when stack is set.
	position int
	// stack says the argument is handed over on the stack rather than in a
	// register, which is what happens to the ones a sequence ran out for.
	stack bool
	// paired says the argument is an object of two eightbytes: the second one of
	// them travels beside the first, in the register second_floating and
	// second_position name, or as the stack word after it when stack is set.
	paired          bool
	second_floating bool
	second_position int
}

// PairPlaces is where the two eightbytes of an object of two of them go, and it is
// the one answer a caller and a callee both have to reach, because an object the
// caller puts in a register and the callee expects in memory arrives as whatever
// happened to be in the register.
//
// The convention places an object of two eightbytes in registers when both of them
// have a register of their own class left, and in memory when either one does not:
// the object is not split between the two. registers is false in that second case,
// and then the object is two words on the stack, first eightbyte at the lower
// address.
struct PairPlaces {
	first     int
	second    int
	integers  int
	doubles   int
	registers bool
}

fn pair_places(target backend.Target, first_floating bool, second_floating bool, integers int, doubles int) PairPlaces {
	// How far each sequence moves for the first eightbyte, and for the second one
	// on top of that: an object of two eightbytes takes a register per eightbyte
	// from the sequence that eightbyte's class names, so two general eightbytes
	// take two general registers and a mixed pair takes one of each.
	first_integer := if first_floating { 0 } else { 1 }
	first_double := if first_floating { 1 } else { 0 }
	second_integer := first_integer + (if second_floating { 0 } else { 1 })
	second_double := first_double + (if second_floating { 1 } else { 0 })
	mut fits := true
	if first_floating {
		if target.float_arg_reg(doubles) == none {
			fits = false
		}
	} else if target.arg_reg(integers) == none {
		fits = false
	}
	if second_floating {
		if target.float_arg_reg(doubles + first_double) == none {
			fits = false
		}
	} else if target.arg_reg(integers + first_integer) == none {
		fits = false
	}
	return PairPlaces{
		first:     if first_floating { doubles } else { integers }
		second:    if second_floating { doubles + first_double } else { integers + first_integer }
		integers:  integers + second_integer
		doubles:   doubles + second_double
		registers: fits
	}
}

// store_return_eightbyte writes one of the registers a call handed its object back
// in into storage the caller has the address of: the same two files the return read
// from, in the same order.
fn (mut e Emitter) store_return_eightbyte(base backend.Register, offset int, width int, floating bool, line int, col int) !void {
	// base is the address the eightbyte is stored at, which the caller has already
	// advanced for the second one of a pair; offset only says which of the two it
	// is, because that is the register the value came back in.
	if floating {
		value := if offset == 0 {
			e.float_accumulator(line, col)!
		} else {
			e.target.float_scratch() or {
				e.diagnostics << problem(line, col, 'internal: ${e.target.name} has no second floating register a second eightbyte comes back in')
				return error('no second floating register')
			}
		}
		e.append(e.target.store_double_indirect(base, value)!)
		return
	}
	value := if offset == 0 { e.accumulator(line, col)! } else { e.remainder(line, col)! }
	e.append(e.target.store_indirect(base, value, width)!)
}

// load_return_eightbyte loads one eightbyte of an object into the register a value
// of its class is handed back in: a general one, the first of which is the result
// register the machine's calls answer in, and a floating one, which is the machine's
// first floating register or the one beside it. The number of the register is the
// number of eightbytes of that class before this one, which is why the first read
// here is always register zero and the second is register zero or one of the file its
// class names.
fn (mut e Emitter) load_return_eightbyte(base backend.Register, offset int, width int, floating bool, line int, col int) !void {
	// base is the address the eightbyte is read from, which the caller has already
	// advanced for the second one of a pair; offset only says which of the two it is,
	// because that is the register the value goes back in. The general file's result
	// registers are the accumulator and the one beside it, and the floating file's are
	// its first register and the one beside it.
	if floating {
		register := if offset == 0 {
			e.float_accumulator(line, col)!
		} else {
			e.target.float_scratch() or {
				e.diagnostics << problem(line, col, 'internal: ${e.target.name} has no second floating register to hand a second eightbyte back in')
				return error('no second floating register')
			}
		}
		e.append(e.target.load_double_indirect(base, register)!)
		return
	}
	// The first general eightbyte goes into the accumulator last, because the address
	// it is read through is in the accumulator too and reading into the register one
	// has just advanced would read from the value rather than from the object.
	register := if offset == 0 { e.accumulator(line, col)! } else { e.remainder(line, col)! }
	e.append(e.target.load_indirect(base, register, width)!)
}

// load_argument_eightbyte loads one eightbyte of an object into the argument register
// its class names, reading from the object's address. The general file takes the bytes
// themselves and only as many of them as the object has, so an object of twelve bytes
// is not read past its end; the floating-point file takes a double, which is the eight
// bytes an eightbyte of that class is.
fn (mut e Emitter) load_argument_eightbyte(base backend.Register, offset int, width int, floating bool, position int, line int, col int) !void {
	if offset > 0 {
		e.append(e.target.add_immediate(base, offset))
	}
	if floating {
		register := e.target.float_arg_reg(position) or {
			e.diagnostics << problem(line, col, 'internal: the floating-point argument register an eightbyte is handed over in is not in the machine table')
			return error('no floating argument register')
		}
		e.append(e.target.load_double_indirect(base, register)!)
		return
	}
	register := e.target.arg_reg(position) or {
		e.diagnostics << problem(line, col, 'internal: the general argument register an eightbyte is handed over in is not in the machine table')
		return error('no argument register')
	}
	e.append(e.target.load_indirect(base, register, width)!)
}

// store_argument_eightbyte copies the eightbyte an argument register carries into a
// parameter's storage at an offset: a register of the floating-point file carries the
// bits of a double and one of the general file the bytes themselves, and either way
// the slot holds the object's bytes. The store goes through the parameter's address
// because the second eightbyte is stored eight bytes into it.
fn (mut e Emitter) store_argument_eightbyte(object Slot, offset int, width int, floating bool, position int, line int, col int) !void {
	base := e.frame_pointer(line, col)!
	if floating {
		register := e.target.float_arg_reg(position) or {
			e.diagnostics << problem(line, col, 'internal: the floating-point argument register a parameter arrives in is not in the machine table')
			return error('no floating argument register')
		}
		e.append(e.target.store_double_slot(base, i32(object.offset + offset), register)!)
		return
	}
	register := e.target.arg_reg(position) or {
		e.diagnostics << problem(line, col, 'internal: the general argument register a parameter arrives in is not in the machine table')
		return error('no argument register')
	}
	e.append(e.target.store_slot(base, i32(object.offset + offset), register, width)!)
}

// load_stacked_eightbyte copies one eightbyte of an object that is in memory into a
// parameter's storage. Both classes arrive the same way, because what is in memory is
// the object's bytes: the bits of a double are those bytes, and the general file
// carries only as many of them as the object has left.
fn (mut e Emitter) load_stacked_eightbyte(object Slot, offset int, width int, at int, line int, col int) !void {
	register := e.accumulator(line, col)!
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_slot(base, at, register, e.target.word_size)!)
	e.append(e.target.store_slot(base, i32(object.offset + offset), register, width)!)
}

// argument_is_double says whether an argument is handed over as a double. A
// function this file defines says so itself, parameter by parameter; a library
// function has no prototype here, so the argument's own type is the answer.
fn (e Emitter) argument_is_double(call ast.Call, position int, arg ast.Expr) bool {
	if classes := e.float_params[call.name] {
		if position < classes.len {
			return classes[position]
		}
	}
	return e.floating_of(arg)
}

// passed_width is the width one argument is handed over at. A function this file
// defines says what its parameters are; a library function has no prototype
// here, so the width is the one the argument itself has. A value whose width is
// not the parameter's is reported where it is written: a pointer passed where an
// int is expected would hand over one half of itself, and nothing later would
// notice.
//
// The class is the exception again: an argument that is a double and a parameter
// that is not are converted rather than refused, so the width the value had
// before the conversion is not the width it is handed over at. The one case that
// is refused is a double where the parameter holds an address, because there is
// no conversion between a floating type and a pointer and the bits would arrive
// as an address the program can no longer follow.
fn (mut e Emitter) passed_width(call ast.Call, position int, arg ast.Expr, floating bool) !int {
	// An object of an aggregate type is the parameter's own type rather than a
	// value of some width: the two are the same type or the type checker refused
	// the call, and what travels is the object's bytes.
	if class := e.aggregate_argument(call, position) {
		if class.first_floating && class.bytes != e.target.word_size {
			e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${position + 1} of the call to ${call.name} is an object of ${class.bytes} bytes whose class is the floating-point one, and this compiler moves such an object as eight bytes')
			return error('aggregate floating class width')
		}
		return class.bytes
	}
	if floating {
		return e.target.word_size
	}
	actual := e.width_of(arg)
	if e.floating_of(arg) {
		if widths := e.signatures[call.name] {
			if position < widths.len && widths[position] == e.target.word_size {
				e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${position + 1} of the call to ${call.name} is a double and the parameter holds an address, and there is no conversion between them')
				return error('double into a pointer')
			}
		}
		return 4
	}
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

// global_shape is what a top-level object's declaration says about its storage:
// the width of one element and how many there are. It asks the tree rather than
// the image, so an expression can ask it while it is being sized, before anything
// has needed the address of the object and laid the storage out.
fn (e Emitter) global_shape(name string) ?GlobalSlot {
	if slot := e.program.globals[name] {
		return slot
	}
	for global in e.unit.globals {
		if global.name == name {
			if global.bytes > 0 {
				// An object of an aggregate type: its storage is as many bytes
				// as the layout says and it has no element width a load could
				// use, which is why nothing may read the name as a value. An
				// array of them keeps the count, because that is what says the
				// name is an array and how far an index reaches.
				return GlobalSlot{
					offset: 0
					width:  global.bytes
					count:  global.count
					object: true
				}
			}
			element := e.type_width(global.typ) or { return none }
			return GlobalSlot{
				offset:   0
				width:    element
				count:    if global.count > 0 { global.count } else { 0 }
				floating: e.writes_a_double(global.typ)
			}
		}
	}
	return none
}

// global_is_double says whether a top-level object was defined as a double. A
// read of the name has to go through the floating-point file, and the tree says
// so before the storage has been laid out, so this asks the declaration rather
// than the blob.
fn (e Emitter) global_is_double(name string) bool {
	for global in e.unit.globals {
		if global.name == name {
			// An array's name is an address, so only an object that holds one
			// double is read as one.
			return global.count == 0 && e.writes_a_double(global.typ)
		}
	}
	return false
}

// global_element_is_double is the same question about one element of a top-level
// array: `a[0]` is a double when a is an array of doubles, which is the class the
// element is read and written with.
fn (e Emitter) global_element_is_double(name string) bool {
	for global in e.unit.globals {
		if global.name == name {
			return global.count > 0 && e.writes_a_double(global.typ)
		}
	}
	return false
}

// global_of is the storage a top-level object has in the image, laid out the
// first time the name is used: the bytes of its constant initializer, or zeros,
// at the width of one element, with every object starting at a word boundary so
// that a word-sized value is never halfway into the one before it. The address of
// a global is not known while the code is emitted - the image is laid out
// afterwards - so every use of it is a reference the layout fills in, which is
// the same mechanism a string literal is addressed by.
fn (mut e Emitter) global_of(name string) ?GlobalSlot {
	if slot := e.program.globals[name] {
		return slot
	}
	mut definition := ?ast.Global(none)
	for global in e.unit.globals {
		if global.name == name {
			definition = global
			break
		}
	}
	object := definition or { return none }
	shape := e.global_shape(name) or { return none }
	element := shape.width
	// A definition with no written count is one value, and one with a count is
	// that many of them. An object of an aggregate type has neither: its storage
	// is the byte size the declaration asked the layout for, and it starts as
	// zeros because there is nothing in the definition to write into it.
	if object.bytes > 0 {
		// One object of an aggregate type is the layout's size, and an array of
		// them is that many per element: `width` is the size of one element,
		// which is the stride an index scales by, and `count` is how many.
		for e.program.globals_blob.len % e.target.word_size != 0 {
			e.program.globals_blob << u8(0)
		}
		offset := e.program.globals_blob.len
		space := if object.count > 0 { object.count * object.bytes } else { object.bytes }
		e.program.globals_blob << []u8{len: space, init: u8(0)}
		slot := GlobalSlot{
			offset: offset
			width:  object.bytes
			count:  object.count
			object: true
		}
		e.program.globals[name] = slot
		return slot
	}
	count := if shape.count > 0 { shape.count } else { 1 }
	for e.program.globals_blob.len % e.target.word_size != 0 {
		e.program.globals_blob << u8(0)
	}
	offset := e.program.globals_blob.len
	e.program.globals_blob << []u8{len: count * element, init: u8(0)}
	if value := object.init_float {
		// The initializer of a double is the eight bytes of its value, which is
		// the same little-endian image the instruction that reads one expects.
		bits := math.f64_bits(value)
		for i in 0 .. element {
			e.program.globals_blob[offset + i] = u8((bits >> (8 * i)) & 0xff)
		}
	}
	if value := object.init {
		// The initializer is a constant, written the way the machine holds a
		// value of that width: little-endian, two's complement.
		for i in 0 .. element {
			e.program.globals_blob[offset + i] = u8((u64(value) >> (8 * i)) & 0xff)
		}
	}
	slot := GlobalSlot{
		offset:   offset
		width:    element
		count:    shape.count
		floating: shape.floating
	}
	e.program.globals[name] = slot
	return slot
}

// assign_global writes a value into the storage of a top-level object: the
// address of it is loaded out of the image, parked in a scratch slot while the
// value is computed - the value can read the object again - and then the value is
// written through the address.
fn (mut e Emitter) assign_global(stmt ast.Stmt, object GlobalSlot, expr ast.Expr) !void {
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference(e.target.address_of(register, 0), .global_address, stmt.target, register.name)
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	e.emit_expr_at(expr, 1)!
	e.convert_for_global(expr, object, stmt.line, stmt.col)!
	address_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	if object.floating {
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.append(e.target.store_double_indirect(address_register, value)!)
		return
	}
	value := e.accumulator(stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, object.width)!)
}

// convert_for_global makes a value the class of a top-level object's storage and
// checks that the two can be one another at all. It is the same question a store
// into a local asks, with a different shape to the storage.
fn (mut e Emitter) convert_for_global(expr ast.Expr, object GlobalSlot, line int, col int) !void {
	if object.floating {
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a top-level object that holds a double, and there is no conversion between them')
			return error('pointer into a double')
		}
		return e.convert_to_double(expr, line, col)
	}
	if e.floating_of(expr) {
		return e.convert_to_int(expr, line, col)
	}
	if width := e.width_of(expr) {
		if width != object.width && !(object.width == 1 && width == 4) {
			e.diagnostics << problem(line, col, 'unsupported: a value of ${width} bytes is stored into an object that holds ${object.width}')
			return error('width mismatch')
		}
		return
	}
	e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
	return error('unknown width')
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

// float_key is the key one double is interned under: the text of the eight bytes
// it is made of. Two constants with the same bit pattern are one entry, and two
// that are equal as numbers are one entry too, since a double has one bit pattern
// per value. The key is the bits rather than the decimal spelling because the
// decimal spelling of `1.5` and of `1.50` is two strings and the value is one.
fn float_key(value f64) string {
	return '${math.f64_bits(value)}'
}

// intern_double puts the eight bytes of a floating constant into the image's
// read-only data once and answers with the key it landed under. The bytes are
// little-endian, which is how the machine reads the eight bytes of a double out
// of memory, and nothing pads the entry: the instruction that reads one does not
// require an aligned address, so a constant can follow a string literal.
fn (mut e Emitter) intern_double(value f64) string {
	key := float_key(value)
	if key in e.program.doubles {
		return key
	}
	e.program.doubles[key] = e.program.string_blob.len
	bits := math.f64_bits(value)
	for i in 0 .. 8 {
		e.program.string_blob << u8((bits >> (8 * i)) & 0xff)
	}
	return key
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
		ast.FloatLit { expr.line }
		ast.StrLit { expr.line }
		ast.Ident { expr.line }
		ast.Unary { expr.line }
		ast.Binary { expr.line }
		ast.Call { expr.line }
		ast.Index { expr.line }
		ast.Field { expr.line }
	}
}

fn expr_col(expr ast.Expr) int {
	return match expr {
		ast.IntLit { expr.col }
		ast.FloatLit { expr.col }
		ast.StrLit { expr.col }
		ast.Ident { expr.col }
		ast.Unary { expr.col }
		ast.Binary { expr.col }
		ast.Call { expr.col }
		ast.Index { expr.col }
		ast.Field { expr.col }
	}
}

fn problem(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
	}
}
