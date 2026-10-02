module codegen

import ast
import backend
import backend.abi
import backend.os.elf
import backend.os.linux
import image
import math
import tokenize
import types

// Options is what the caller asks for. An empty target means the machine this
// binary runs on, and an empty entry means `main`.
pub struct Options {
pub:
	target string
	entry  string
	// compile_only asks for a relocatable object rather than a program: the same
	// code and data with the addresses left to whoever links it. It changes what
	// the last stage wraps the program in and nothing before it, which is why it
	// is an option here rather than a second entry point.
	compile_only bool
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
	// wide is set for a slot holding a 128-bit integer, which is an object of
	// sixteen bytes rather than a value: it is stored, copied and addressed, and
	// it has no value of that width to be read as. A narrower value is stored in
	// one by widening it into the two words of the object.
	wide bool
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
// WideWorking is the scratch a division of two pairs needs, taken from one
// reservation so the four things it holds sit together: the quotient, which starts
// as the dividend and is shifted a bit at a time, the remainder, the count of bits
// still to shift, and a word per operand saying whether that operand was negative.
struct WideWorking {
	quotient  Slot
	remainder Slot
	counter   Slot
	flags     Slot
}

struct Emitter {
	target backend.Target
	// representation is what the target says about the C types: the width of a
	// pointer, and the width of an int. The calling convention is read from it
	// here rather than from the tree, because which register file carries an
	// object is the target's answer: the same declaration is handed over
	// differently on a machine with a different convention, and an answer
	// carried on a node would be one machine's.
	representation types.Representation
	entry          string
	// compile_only says the container to build is an object and not a program.
	compile_only bool
	unit         ast.TranslationUnit
	// libraries are the -l names the command line gave, and library_dirs the
	// -L directories they are looked for in. Both are resolved into the names
	// the image carries before anything is emitted.
	libraries    []string
	library_dirs []string
mut:
	program     image.Program
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
	aggregate_params map[string][]abi.Class
	// wide_params says, for the same functions, which parameters are one of the
	// 128-bit integers. Such a parameter is passed as a pair of words in two
	// registers at once rather than as one value, so a call has to know which
	// parameters those are, and the width cannot answer it: a pair is sixteen
	// bytes and is not handed over at that width.
	wide_params map[string][]bool
	// return_classes says, for the same functions, which of them hand an object
	// of an aggregate type back, and how many bytes of one. The value comes back
	// in the register its class names rather than converted.
	return_classes map[string]abi.Class
	// returning is the return type of the function being emitted, as it was
	// written, which is what a return statement's value is converted to.
	returning string
	// return_class is how the function being emitted hands its value back, and
	// zero for a function that returns a value of its own width or nothing.
	return_class abi.Class
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
	// hidden_bytes is the storage a call that returns an object of more than two
	// eightbytes lends the function it calls, which is the largest such object this
	// file declares, and zero when no such object is returned anywhere.
	hidden_bytes int
	// hidden is the frame slot that storage is, and the address a call is given for
	// its result travels in the first general register.
	hidden Slot
	// saved_return is the frame slot a function keeps the address its caller named
	// for its own result in, for a function that returns such an object.
	saved_return Slot
	// stack_pushed is how many bytes the call being emitted has pushed for the
	// arguments its registers ran out for, and zero when it pushed none. The
	// caller gives those bytes back once the call returns, so the frame is where
	// it was and the slots keep their offsets.
	stack_pushed int
	// values is the scratch area, one slot per level of expression nesting,
	// where a half-finished value waits while the other half is computed.
	values []Slot
	// wide_left and wide_right are the slots a 128-bit step keeps its two
	// operands in, one slot per level of nesting and one for each side: a pair is
	// two words, and two pairs do not fit in the registers a step has while the
	// right side is still allowed to call a function, so both operands wait in
	// the frame. They are kept the way values are, one per level, so a function
	// ends up with as many as its deepest expression used.
	wide_left    []Slot
	wide_right   []Slot
	wide_scratch []Slot
	// wide_arguments is where a call parks a 128-bit argument whose expression
	// is finished. A pair is two words and the slots the other arguments wait in
	// hold one each, so a pair needs a slot of its own; it is keyed the way the
	// values are, one per level of nesting, because the argument of a call inside
	// the argument of another call has to land somewhere the outer call is not
	// using.
	wide_arguments []Slot
	wide_working   []WideWorking
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

// wide_bytes is the size of a 128-bit integer as an object. It is the number the
// type model carries for both of the 128-bit kinds, and the number the machine's
// sixteen bytes are cut into when one is copied, so it is written once here and
// the emitter asks this name for it.
const wide_bytes = 16

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
	// A program has to start somewhere and a kernel starts it at one place, so a
	// program without the entry function is one this compiler cannot produce. An
	// object is not a program: it starts nowhere, and which function a link makes
	// the entry is not decided here.
	entry := if opts.entry == '' { 'main' } else { opts.entry }
	if !opts.compile_only && entry_definition(unit, entry) == none {
		return Result{
			target:      target
			diagnostics: [problem(1, 1, 'no definition of ${entry} in this translation unit')]
		}
	}
	mut emitter := Emitter{
		target:         target
		representation: types.from_target(target).representation
		entry:          entry
		compile_only:   opts.compile_only
		unit:           unit
		libraries:      opts.libraries
		library_dirs:   opts.library_dirs
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
	image_bytes := emitter.build() or {
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
		bytes:  image_bytes
		target: target
	}
}

fn resolve_target(name string) !backend.Target {
	return backend.resolve(name)
}

// class_of is how an object of this type is handed over on the target being emitted
// for. The emitter asks the declaration's resolved type rather than reading an answer
// off the node, because which register file carries an object is the target's answer
// and not the tree's: a class carried on a node is one machine's answer travelling
// with a file that another machine has to be emitted from.
fn (e &Emitter) class_of(declared types.Type) abi.Class {
	return abi.class_of(e.representation, declared)
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
	// An object names no libraries. What a translation unit runs against is
	// decided when it is linked, so a -l on a -c command line is not this
	// stage's business, and resolving one here would fail a compile over a
	// library the object never mentions.
	if !e.compile_only {
		// The whole list goes over in one call: reading a library file is this
		// system's business, and the emitter has nothing left to say about a name
		// once the reader has answered. The error carries the file that could not
		// be read, which says more than the flag that asked for it.
		sonames := linux.resolve_libraries(e.libraries, linux.search_dirs(e.library_dirs, e.target.library_dirs)) or {
			e.diagnostics << problem(1, 1, err.msg())
			return error('cannot resolve the -l libraries')
		}
		for soname in sonames {
			if soname !in e.program.libraries {
				e.program.libraries << soname
			}
		}
	}
	// The names and the parameter widths come first so that a call binds to a
	// definition wherever in the file it is written. The width is the one the
	// definition gives the parameter, which is what a call in the same file has
	// to hand over; a definition with a parameter this back end cannot size is
	// left out of the table, because its own emission is where that is reported.
	for decl in e.unit.decls {
		e.returns[decl.name] = decl.ret
		ret_class := e.class_of(decl.ret_type)
		if ret_class.bytes > 0 {
			e.return_classes[decl.name] = ret_class
			// An object of more than two eightbytes comes back at an address the
			// caller names, so the caller's storage for it is as large as the
			// largest such object any declaration in this file returns.
			if ret_class.count > 2 && ret_class.bytes > e.hidden_bytes {
				e.hidden_bytes = ret_class.bytes
			}
		}
		if decl.body.len > 0 {
			e.program.defined[decl.name] = true
			mut widths := []int{}
			mut classes := []bool{}
			mut aggregates := []abi.Class{}
			mut wides := []bool{}
			mut sized := true
			for param in decl.params {
				// Which parameters are 128-bit values is read here rather than
				// from the width below, because the width of such a parameter is
				// not the width it is handed over at: it travels as a pair of
				// words in two registers at once.
				wides << e.writes_a_128(param.typ)
				// A parameter that is an object of an aggregate type is handed
				// over as its bytes in one register: how many bytes it is and
				// which file the register belongs to are the two facts the call
				// needs, and both are the target's answer for the type the
				// declaration resolved to.
				class := e.class_of(param.resolved)
				if class.bytes > 0 {
					widths << class.bytes
					classes << class.first_floating
					aggregates << class
					continue
				}
				aggregates << abi.Class{}
				if width := e.type_width(param.typ) {
					widths << width
					classes << e.writes_a_double(param.typ)
				} else if e.writes_a_128(param.typ) {
					// The object is sixteen bytes; the value is a pair. The
					// width goes in the table so that the parameters beside
					// this one keep their own positions and widths.
					widths << wide_bytes
					classes << false
				} else {
					sized = false
				}
			}
			e.wide_params[decl.name] = wides
			if sized {
				e.signatures[decl.name] = widths
				e.float_params[decl.name] = classes
				e.aggregate_params[decl.name] = aggregates
			}
		}
	}
	// The process stub is the place the kernel lands on: it calls the entry
	// function and hands its result to the library's exit. An object has no such
	// place, so it gets none; a link decides what the program starts at.
	if !e.compile_only {
		e.emit_start()!
	}
	for decl in e.unit.decls {
		if decl.body.len == 0 {
			continue
		}
		e.emit_function(decl)!
	}
	// The same program, wrapped as one of two things: an object a linker takes as
	// input, or a program a kernel starts. This is the last decision the emitter
	// makes and the only one that depends on the mode.
	mut bytes := []u8{}
	if e.compile_only {
		bytes = elf.object(e.program, e.target) or {
			e.diagnostics << problem(1, 1, 'internal: the object could not be laid out: ${err.msg()}')
			return error('cannot lay out the object')
		}
	} else {
		bytes = elf.executable(e.program, e.target) or {
			e.diagnostics << problem(1, 1, 'internal: the image could not be laid out: ${err.msg()}')
			return error('cannot lay out the image')
		}
	}
	return bytes
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
	// How the value this function returns is handed back is the target's answer for
	// the type the declaration resolved to. It is asked once here, where the frame
	// is laid out, rather than read off the declaration.
	ret_class := e.class_of(decl.ret_type)
	// A definition returns a value the caller reads or nothing at all. There is
	// no third answer the machine has a place for: the result register holds
	// what a call leaves there, and a void function leaves nothing to read.
	if ret_class.bytes > 0 {
		// A function may hand an object of an aggregate type back, and the value
		// comes back in the register the class names rather than converted. An
		// object larger than one eightbyte is two registers or a copy in memory,
		// which is the half of this that this compiler does not hand over.
		if ret_class.first_floating && ret_class.bytes < e.target.word_size {
			e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, which is an object of ${ret_class.bytes} bytes whose class is the floating-point one, and this compiler moves such an object as eight bytes')
			return error('aggregate floating class width')
		}
	} else if e.writes_a_128(decl.ret) {
		// A 128-bit type is the third shape a value leaves in, and the only one
		// that needs nothing worked out here: the pair goes back in two fixed
		// registers, which are the two a 128-bit operation already leaves its
		// answer in. Measured on gcc 16.2.1, which returns one in rax and the
		// word above it in rdx, and which clears rdx when the returned
		// expression is narrower than the type.
	} else if decl.ret != 'int' && decl.ret != 'void' && decl.ret != 'double'
		&& !e.eight_byte_integer(types.from_words(decl.ret.split(' ')) or { types.Type{} }) {
		e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, and only int, the four 64-bit integers, double and void are implemented')
		return error('unsupported return type')
	}
	e.returning = decl.ret
	e.return_class = ret_class
	if e.hidden_bytes > 0 {
		e.hidden = e.reserve(e.hidden_bytes)
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
	if ret_class.count > 2 {
		// A function that hands an object of more than two eightbytes back is given
		// the address to put it at in the first general register, and keeps it in the
		// frame until the return: the object it returns is written there, and the call
		// answers with that same address. The address is read from the register after
		// the prologue, because the slot it is kept in is a frame slot.
		saved := e.reserve(e.target.word_size)
		e.saved_return = saved
		register := e.target.arg_reg(0) or {
			e.diagnostics << problem(decl.line, decl.col, 'internal: ${e.target.name} has no first general register for the address a returned object goes to')
			return error('no first argument register')
		}
		base := e.frame_pointer(decl.line, decl.col)!
		e.append(e.target.store_slot(base, i32(saved.offset), register, e.target.word_size)!)
	}
	// The parameters arrive in the machine's argument registers. They are stored
	// into the frame on the way in, so a parameter is read exactly the way a
	// local is, and the register is free for the expression that follows.
	//
	// There are two sequences of them and a parameter belongs to one: an int
	// arrives in the general file and a double in the floating one, each numbered
	// from its own beginning, which is how `f(int a, double b)` finds a in the
	// first general register and b in the first floating one.
	mut integers := if ret_class.count > 2 { 1 } else { 0 }
	mut doubles := 0
	mut stacked := 0
	for _, param in decl.params {
		// How this parameter is handed over is the target's answer for the type
		// the declaration resolved to, and it is asked here rather than read off
		// the node.
		class := e.class_of(param.resolved)
		if e.writes_a_128(param.typ) {
			// A 128-bit parameter is a pair: its two words arrive in two
			// consecutive argument registers of the general file, low word
			// first, and the parameter is the object of sixteen bytes they are
			// stored into. Measured on gcc 16.2.1, which passes one such
			// parameter in rdi:rsi and a second in rdx:rcx, and passes
			// `(int x, __int128 a)` with x in edi and the pair in rsi:rdx.
			//
			// The pair takes both registers at once rather than one after the
			// other, so a pair with fewer than two of them left is the case the
			// convention passes in memory. That is not implemented here, and it
			// is refused by name: a caller that reached one answer and a callee
			// that reached the other would read words from somewhere the caller
			// never wrote.
			registers := e.pair_argument_registers(integers) or {
				e.diagnostics << problem(param.line, param.col, 'unsupported: the parameter ${param.name} is declared ${param.typ}, and the pair it is passed in takes two argument registers at once, which this machine has not got at position ${integers}: the convention passes such a pair in memory, which this back end does not do')
				return error('128-bit parameter in memory')
			}
			object := e.declare(param.name, param.typ, 0, 0, param.line, param.col)!
			base := e.frame_pointer(param.line, param.col)!
			word := e.target.word_size
			e.append(e.target.store_slot(base, object.offset, registers[0], word)!)
			e.append(e.target.store_slot(base, object.offset + word, registers[1], word)!)
			integers += 2
			continue
		}
		// An object of an aggregate type arrives as its bytes in one register of
		// the class its members make, and the parameter is storage of exactly
		// that many bytes: the value is copied into the slot rather than
		// converted into it.
		if class.bytes > 0 {
			object := e.declare(param.name, param.typ, 0, class.bytes, param.line, param.col)!
			stacked_at := 2 * e.target.word_size + stacked * e.target.word_size
			if class.count > 2 {
				// An object of more than two eightbytes is passed in memory: the
				// caller put a copy of it on the stack, and the parameter is
				// storage of the layout's bytes that the copy goes into.
				e.copy_stack_object(object, stacked_at, param.line, param.col)!
				stacked += class.count
				continue
			}
			if class.count == 2 {
				// Two eightbytes: each arrives in a register of its own class,
				// or both arrive as two words of the stack when either sequence
				// had none left for the object, which is the same answer the
				// caller reached.
				placed := abi.pair_places(e.target, class.first_floating, class.second_floating,
					integers, doubles)
				if placed.registers {
					integers = placed.integers
					doubles = placed.doubles
					e.store_argument_eightbyte(object, 0, e.target.word_size,
						class.first_floating, placed.first, param.line, param.col)!
					e.store_argument_eightbyte(object, e.target.word_size,
						class.bytes - e.target.word_size, class.second_floating,
						placed.second, param.line, param.col)!
					continue
				}
				e.copy_stack_object(object, stacked_at, param.line, param.col)!
				stacked += 2
				continue
			}
			if class.first_floating {
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
	//
	// The slots an expression keeps half-finished values in go with the frame, and
	// that is every one of these lists rather than the one below alone. A slot is an
	// offset into the frame of the function being emitted, so a list that outlives
	// its function hands the next one an offset that the next frame does not have:
	// a 128-bit temporary landed on a parameter of the function after it, and the
	// parameter was overwritten before the expression that read it ran. The depths
	// are what make these lists reusable within one function, and a function is what
	// they are sized to.
	e.frame_used = 0
	e.values = []Slot{}
	e.wide_left = []Slot{}
	e.wide_right = []Slot{}
	e.wide_scratch = []Slot{}
	e.wide_arguments = []Slot{}
	e.wide_working = []WideWorking{}
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
			.do_while_stmt {
				e.emit_do_while(stmt)!
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
		if e.return_class.count > 2 {
			// The object goes to the address this call was given, which the function
			// kept in the frame, and the call answers with that address in the
			// accumulator: both addresses are parked, because a copy needs two
			// registers and neither of them can hold an address.
			e.address_of_object(expr, 0)!
			source := e.value_slot(0)
			e.store_accumulator(source, stmt.line, stmt.col)!
			register := e.accumulator(stmt.line, stmt.col)!
			base := e.frame_pointer(stmt.line, stmt.col)!
			e.append(e.target.load_slot(base, i32(e.saved_return.offset), register, e.target.word_size)!)
			destination := e.value_slot(1)
			e.store_accumulator(destination, stmt.line, stmt.col)!
			e.copy_address_object(source, destination, e.return_class.bytes, stmt.line, stmt.col)!
			value := e.accumulator(stmt.line, stmt.col)!
			e.load_argument(destination, value, e.target.word_size, stmt.line, stmt.col)!
			e.append(e.target.frame_epilogue())
			return
		}
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
	if e.writes_a_128(e.returning) {
		// A function of a 128-bit type answers with the pair, so the expression
		// is left in the two registers a pair lives in rather than converted to
		// one value. An expression of the type is already the pair; a narrower
		// one is widened into it, which is where the high word of `return 5`
		// comes from rather than whatever the body happened to leave in the
		// register above the low word. Measured on gcc 16.2.1, which answers
		// that program with eax = 5 and edx = 0, and `return -1` with rax = -1
		// and rdx = -1.
		e.emit_value(expr, 0)!
		if !e.wide_value(expr) {
			e.widen_word_pair(expr.typ.kind.is_unsigned(), e.narrow_width(expr.typ), stmt.line,
				stmt.col)!
		}
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
	if e.returns_eight_byte_integer() {
		// A function whose return type is a 64-bit integer leaves the whole
		// register as its value, so a narrower expression is widened into it the
		// same way an operand of a 64-bit step is: `return -1;` in a function
		// returning a long answers -1.
		return e.extend_operand_to_word(expr, line, col)
	}
	return
}

// returns_eight_byte_integer says whether the function being emitted returns one
// of the four 64-bit integer types, which is asked of the type rather than of the
// width because a pointer is eight bytes too and is not widened like one.
fn (e Emitter) returns_eight_byte_integer() bool {
	typ := types.from_words(e.returning.split(' ')) or { return false }
	return e.eight_byte_integer(typ)
}

// emit_var_decl gives a declaration its slot in the frame and, when it has one,
// writes the initializer into it. A declaration without an initializer is
// storage and nothing else, which is what C says it is: the slot is there for
// whatever the function writes into it next.
fn (mut e Emitter) emit_var_decl(stmt ast.Stmt) !void {
	slot := e.declare(stmt.decl_name, stmt.decl_type, stmt.decl_count, stmt.bytes, stmt.line, stmt.col)!
	init := stmt.init or { return }
	if slot.wide {
		// A 128-bit object declared with a value takes one of three things: a copy
		// of another object of the type, the pair a computation left in the
		// registers, or a narrower value widened into the two words. The store asks
		// the value which of the three it is, so a declaration and an assignment
		// share one path.
		return e.store_wide(slot, init, stmt.line, stmt.col)
	}
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
	if e.wide_value(init) {
		// A slot narrower than the object it is given takes the object's low word,
		// which is its value modulo the width of the slot. The wide slot and the
		// wide value are the copy the other branch makes, so what arrives here is
		// an object of one width and a slot of a smaller one.
		if slot.floating {
			// A double of that value is the rounding of the whole of it and not
			// the low word, so the low word is refused rather than stored as
			// though the top of the value were zero. Measured on gcc 16.2.1:
			// `double d = (__int128)5` is 5.0, and the low word read as an integer
			// into a double slot is a different number entirely.
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a conversion from a 128-bit object to ${stmt.decl_type} is not one this back end makes, and a value that wide does not convert to a floating type here')
			return error('128-bit to a double')
		}
		e.low_word_of_object(init, slot.width, stmt.line, stmt.col, 1)!
		return e.store_accumulator(slot, stmt.line, stmt.col)
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
	if subscript := stmt.subscript {
		return e.assign_subscript(stmt, subscript, expr)
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
	if target.wide {
		// A wide target is sixteen bytes of storage, and what is written into it is
		// one of three things: a copy of another object of the type, a pair a
		// computation left in the registers, or a narrower value widened. The store
		// asks the value which of the three it is, so every wide assignment and
		// every wide declaration shares one path.
		return e.store_wide(target, expr, stmt.line, stmt.col)
	}
	if target.bytes > 0 {
		return e.assign_object_local(stmt, target)
	}
	if e.wide_value(expr) {
		// The same read the declaration makes: the low word of the object, at the
		// width of the slot it is written into. The floating slot is refused for
		// the same reason it is there.
		if target.floating {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a conversion from a 128-bit object to a slot that holds a double is not one this back end makes, and a value that wide does not convert to a floating type here')
			return error('128-bit to a double')
		}
		e.low_word_of_object(expr, target.width, stmt.line, stmt.col, 1)!
		return e.store_accumulator(target, stmt.line, stmt.col)
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
fn (mut e Emitter) assign_object_global(stmt ast.Stmt, object image.GlobalSlot) !void {
	expr_value := stmt.expr or { return error('assignment without a value') }
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference(e.target.address_of(register, 0), .global_address, stmt.target, e.target.name_of(register))
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
			if class.count > 2 {
				// The object is in the storage this call lent the function it called,
				// and it is copied from there into the object it is assigned to.
				e.emit_expr_at(expr, 1)!
				return e.copy_frame_object(e.hidden, address, class.bytes, line, col)
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
	return e.copy_address_object(source, address, width, line, col)
}

// copy_address_object copies an object from one address to another, both parked in
// value slots. The bytes move in the chunks the machine moves in one instruction,
// eight then four then two then one, because an object whose size is not a multiple of
// eight has a last chunk narrower than a word; the source's address is reloaded for
// each chunk, so the value can travel through a register of its own and neither address
// is held in one.
fn (mut e Emitter) copy_address_object(source Slot, destination Slot, width int, line int, col int) !void {
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
		destination_register := e.accumulator(line, col)!
		e.load_argument(destination, destination_register, e.target.word_size, line, col)!
		if done > 0 {
			e.append(e.target.add_immediate(destination_register, done))
		}
		e.append(e.target.store_indirect(destination_register, value, chunk)!)
		done += chunk
	}
}

// copy_frame_object copies an object that is storage in the frame to an address parked
// in a value slot, which is what writing an object a call handed back into the object it
// is assigned to is: the caller's storage for the result is a frame slot and the
// destination is an address the assignment already worked out.
fn (mut e Emitter) copy_frame_object(source Slot, destination Slot, width int, line int, col int) !void {
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
		base := e.frame_pointer(line, col)!
		value := e.scratch(line, col)!
		e.append(e.target.load_slot(base, i32(source.offset + done), value, chunk)!)
		destination_register := e.accumulator(line, col)!
		e.load_argument(destination, destination_register, e.target.word_size, line, col)!
		if done > 0 {
			e.append(e.target.add_immediate(destination_register, done))
		}
		e.append(e.target.store_indirect(destination_register, value, chunk)!)
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
fn (e Emitter) aggregate_argument(call ast.Call, position int) ?abi.Class {
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
		// An element is at the base's value plus the index scaled by the size
		// of one element, which is the address emit_element_address computes.
		e.emit_element_address(expr, depth)!
		return
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
			e.reference(e.target.address_of(base, 0), .global_address, name, e.target.name_of(base))
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
			e.reference(e.target.address_of(register, 0), .global_address, name, e.target.name_of(register))
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
	if e.writes_a_128(member.spelling) {
		// A member of that width takes a value narrower than it the way an object
		// of the type does, through the member's own address: the object the
		// member lies in may be a pointer's target or a top-level object, so the
		// store cannot be an offset from the frame.
		e.address_of_member(member.name, member.index, member.offset, member.through_pointer, 1,
			stmt.line, stmt.col)!
		address := e.value_slot(0)
		e.store_accumulator(address, stmt.line, stmt.col)!
		return e.store_wide_at(address, expr, stmt.line, stmt.col)
	}
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

// element_address leaves the address of one element of an array in the index
// register: the index scaled by the size of an element and added to the array's
// base. The machine scales an index by one, two, four or eight and by no other
// number, so any other size is a multiply and an add, which is what an array of
// objects of those sizes needs.
//
// An element of sixteen bytes of an aggregate type is refused here by name rather than
// passed on. An address of one is a multiply and an add, but the load or the store that
// follows it asks the machine for sixteen bytes in one instruction, which it has no
// encoding for: that reached the emitter as an internal diagnostic at the top of the
// file with nothing named. Members of such an object are read and written one value at
// a time and do not come through here, and a whole element of one is a copy this back
// end does not make yet.
//
// An element of a 128-bit type is the case the flag allows instead: the caller reads or
// writes it as the two words an object of the type holds, which is what the declaration
// and the assignment already do, so the address is computed here and the sixteen-byte
// instruction is never asked for.
fn (mut e Emitter) element_address(base backend.Register, index backend.Register, stride int, offset int, wide bool, name string, line int, col int) !void {
	if stride == wide_bytes && !wide {
		e.diagnostics << problem(line, col, 'unsupported: ${name} holds elements of ${stride} bytes, and this back end moves one, four or eight bytes in one instruction, so an element of that size is not a value it reads or writes')
		return error('unsupported element size')
	}
	if stride == 1 || stride == 2 || stride == 4 || stride == 8 {
		e.append(e.target.address_of_element(base, index, stride, 0, index)!)
	} else {
		e.append(e.target.imul_immediate(index, stride))
		e.append(e.target.add_reg64(index, base))
	}
	if offset != 0 {
		e.append(e.target.add_immediate(index, offset))
	}
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
			e.reference(e.target.address_of(base, 0), .global_address, stmt.target, e.target.name_of(base))
			is_wide := !object.object && object.width == wide_bytes
			e.element_address(base, register, object.width, 0, is_wide, stmt.target, stmt.line,
				stmt.col)!
			address := e.value_slot(0)
			e.store_accumulator(address, stmt.line, stmt.col)!
			if is_wide {
				// An element of that width takes the two words an object of the type
				// takes, through the element's own address.
				return e.store_wide_at(address, expr, stmt.line, stmt.col)
			}
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
	e.element_address(base, register, slot.width, slot.offset, slot.wide, stmt.target,
		stmt.line, stmt.col)!
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	if slot.wide {
		// An element of that width takes the two words an object of the type takes,
		// through the element's own address.
		return e.store_wide_at(address, expr, stmt.line, stmt.col)
	}
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

// assign_subscript writes a value into the element a computed address names: the
// address is the one emit_element_address leaves, parked in a slot while the
// value is computed, and the value is written through it at the width of the
// element's type. It is the write half of the general element read, and it is
// what `3[p] = 9` and an element written through a pointer go through.
fn (mut e Emitter) assign_subscript(stmt ast.Stmt, subscript ast.Expr, expr ast.Expr) !void {
	index := subscript as ast.Index
	e.emit_element_address(index, 1)!
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	address_register := e.scratch(stmt.line, stmt.col)!
	e.emit_expr_at(expr, 1)!
	if index.typ.kind == .double {
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
	width := e.storage_width(index.typ) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an element of ${index.typ.describe()} is not one this back end stores')
		return error('unsupported element type')
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
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored into an element of ${width}')
		return error('width mismatch')
	}
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, width)!)
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
	if expr is ast.IncDec {
		// A statement use throws the value away, which is what `i++;` asks for:
		// the step is what it does and the old value is not wanted.
		e.emit_inc_dec(expr, 0)!
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
	e.emit_test(e.floating_of(cond), e.eight_byte_integer(cond.typ), stmt.line, stmt.col)!
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
	e.emit_test(e.floating_of(cond), e.eight_byte_integer(cond.typ), stmt.line, stmt.col)!
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

// emit_do_while writes a loop whose test is at the bottom. That placement is the
// whole difference from emit_while: the body runs before the condition is read even
// once, so `top` is where the body starts and the test sits between the body and the
// jump back. A continue belongs at the test rather than at the jump: landing it on the
// jump would read the condition nowhere and landing it on the top label would read it
// only after the body had run again, and C asks for the condition next.
fn (mut e Emitter) emit_do_while(stmt ast.Stmt) !void {
	cond := stmt.cond or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a do without a condition')
		return error('do without a condition')
	}
	top := e.label()
	end := e.label()
	test := e.label()
	e.place(top)
	e.loops << LoopLabels{
		break_to:    end
		continue_to: test
	}
	e.emit_branch_body(stmt.body)!
	e.loops.pop()
	e.place(test)
	e.emit_expr(cond)!
	e.emit_test(e.floating_of(cond), e.eight_byte_integer(cond.typ), stmt.line, stmt.col)!
	// Round again while the condition holds, which is the branch opposite the one a
	// while takes to leave: a while leaves when the test is zero, and this one goes
	// back when the test is not.
	e.branch(.branch_nonzero, top, stmt.line, stmt.col)!
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
	// A 128-bit integer is the second kind of storage here that is sized by
	// something other than the width of a value: an object of one is sixteen
	// bytes, which is the whole object and not a value it is read at.
	wide := bytes == 0 && e.writes_a_128(written)
	// An object of an aggregate type is sized by the layout the reader worked
	// out rather than by its spelling: `struct S` is a name the back end has no
	// width for, and the members are what say how many bytes the object is.
	width := if bytes > 0 {
		bytes
	} else if wide {
		wide_bytes
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
		bytes:    if wide { wide_bytes } else { bytes }
		wide:     wide
	}
	e.scopes[e.scopes.len - 1][name] = block
	return block
}

// type_width is the width of a value of a type as the source wrote it. An int is
// four bytes; a char is one, which is the width of its slot and of the byte the
// machine stores into it, while every read of it widens to an int (see
// width_of); a pointer is the machine's word, which is what makes `char *` and
// `char **` read and write the same way; a double is eight bytes, which is
// what the machine moves with one instruction; and the 64-bit integers are eight
// bytes, measured on this target with gcc 16.2.1 where `sizeof(long)`,
// `sizeof(long long)`, `sizeof(unsigned long)` and `sizeof(unsigned long long)`
// are each 8 and `sizeof(unsigned int)` is 4. Everything else is a type this back
// end has no instruction for.
fn (e Emitter) type_width(written string) ?int {
	if written == 'int' || written == 'unsigned' || written == 'unsigned int' {
		return 4
	}
	if written == 'char' {
		return 1
	}
	if written == 'double' {
		return 8
	}
	// The spellings `long`, `long int`, `long long`, `long long int`,
	// `unsigned long`, `unsigned long int`, `unsigned long long` and
	// `unsigned long long int` are the eight ways a file writes one of the four
	// 64-bit integer types, and all four are eight bytes.
	if written == 'long' || written == 'long int' || written == 'long long' || written == 'long long int'
		|| written == 'unsigned long' || written == 'unsigned long int'
		|| written == 'unsigned long long' || written == 'unsigned long long int' {
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

// writes_a_128 says whether a type as it was written names one of the 128-bit
// integers. A declaration carries the spelling and not the kind, and the spelling
// is what decides whether a slot is an object of sixteen bytes or a value: the two
// 128-bit kinds are the only types this back end stores without a value.
fn (e Emitter) writes_a_128(written string) bool {
	// A pointer to the type is a pointer. It is one word, type_width already says
	// so for any spelling with a star in it, and what it points at is a separate
	// question this back end answers with a whole-object read. Asking whether the
	// spelling contains the type's name is not enough, because `__int128 *` does:
	// a declaration of one was given sixteen bytes as if it were the object, and
	// then refused the address being stored in it as `a pointer is stored in an
	// object of 128 bits`. Every caller wants the type itself and not a pointer to
	// it: parameters, returns, members, top-level objects and casts all read this.
	return written.contains('__int128') && !written.contains('*')
}

// align rounds a size up to the next multiple of the alignment, which is what
// puts every frame slot on the machine's word. The container rounds file
// offsets with its own copy, since neither module has another use for the
// other's.
fn align(value int, to int) int {
	return (value + to - 1) / to * to
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
fn (mut e Emitter) branch(kind image.FixupKind, name string, line int, col int) !void {
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
fn (mut e Emitter) emit_test(floating bool, wide bool, line int, col int) !void {
	register := e.accumulator(line, col)!
	if floating {
		zero := e.float_scratch(line, col)!
		value := e.float_accumulator(line, col)!
		other := e.scratch(line, col)!
		e.append(e.target.zero_double(zero)!)
		e.append(e.target.double_comparison('!=', value, zero, register, other)!)
	}
	if wide {
		e.append(e.target.test_word(register)!)
	} else {
		e.append(e.target.test(register)!)
	}
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
		ast.Cast {
			// A conversion says what the value is afterwards, so the target type
			// is the answer: a double is a double whichever class its operand
			// was, and the type the reader resolved says which one this is.
			expr.typ.is_floating()
		}
		ast.Index {
			// An element is a double when the type the reader gave the element
			// is one: the element type of the array or the pointee of the
			// pointer, which the node carries.
			expr.typ.kind != .unknown && expr.typ.is_floating()
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
		ast.Conditional {
			// The value is whichever arm ran, converted to the type the two
			// arms have in common, so that type is the answer and not either
			// arm's own.
			if expr.typ.kind != .unknown {
				expr.typ.is_floating()
			} else {
				e.floating_at(expr.then_expr, depth + 1) || e.floating_at(expr.else_expr, depth + 1)
			}
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

// wide_value says whether an expression is an object of one of the 128-bit types
// rather than a value of a narrower one: an object of the same type is a copy of
// its bytes, and anything else stored in one is a value to widen first.
// names_an_object says whether an expression is a name, a member or an element:
// the three shapes that are storage with an address, and so the three a value has
// to be read out of rather than computed into a register.
fn (e Emitter) names_an_object(expr ast.Expr) bool {
	return match expr {
		ast.Ident, ast.Field, ast.Index { true }
		else { false }
	}
}

fn (e Emitter) wide_value(expr ast.Expr) bool {
	return expr.typ.kind in [types.Kind.int128, .unsigned_int128]
}

// store_wide widens a value narrower than sixteen bytes into a 128-bit object. The
// low word of the object is the value and the high word is its sign, which is what
// the language says a value of a narrower type converts to: `-1` stored in one of
// them is every bit of both words, and `5` is five in the low word and zero above
// it. One rule covers both 128-bit types, because a negative value converted to
// the unsigned one wraps to exactly that pattern.
//
// The value is widened to a whole word first: the arithmetic of this back end
// works at the width of the type, so the bits above an int are whatever the
// register held and not its sign. The high word is then the low one shifted right
// by sixty-three bits, which spreads the sign over the word.
//
// The two words are stored one at a time, because the machine has no instruction
// that moves sixteen bytes. The high word is stored first: a store reads the
// accumulator, so the low word waits in the third register until the accumulator
// is free for it.
fn (mut e Emitter) store_wide(slot Slot, expr ast.Expr, line int, col int) !void {
	// A slot's two words are written through its address, which is the same store
	// a member's is: the frame's address plus the slot's offset.
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, slot.offset, register))
	address := e.value_slot(0)
	e.store_accumulator(address, line, col)!
	return e.store_wide_at(address, expr, line, col)
}

// store_wide_at widens a value narrower than sixteen bytes into the two words at an
// address the caller has parked in a slot. The store is the same one a frame slot
// takes, and it goes through an address because the object it is written into may
// be a member of an object, the target of a pointer, or a top-level object rather
// than a local of its own.
//
// The value is computed first and at a depth below the address, so nothing the
// expression does can write over where the address is waiting. The sign word goes
// to the higher of the two addresses and the low word follows: the address register
// holds the member's first byte, and the second store comes back to it rather than
// keeping two addresses alive over the expression that produced the value.
fn (mut e Emitter) store_wide_at(address Slot, expr ast.Expr, line int, col int) !void {
	if e.wide_value(expr) {
		// An object of the type is a copy of its bytes rather than a value to
		// widen, which is the shape an assignment between two of them has; a value
		// of the type that is not an object — the result of an addition, say — is
		// already the pair, and it is written at the address as two words.
		match expr {
			ast.Ident, ast.Field, ast.Index {
				return e.assign_object(address, wide_bytes, expr, line, col)
			}
			else {
				// The value is an expression rather than storage: it is computed
				// here, below the slot the address is parked in, and what it leaves
				// in the registers is the pair the store writes.
				e.emit_value(expr, 1)!
				return e.store_pair_at(address, line, col)
			}
		}
	}
	if e.floating_of(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a double is stored in an object of 128 bits, and this compiler has no conversion from a double to that')
		return error('double into a 128-bit object')
	}
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in an object of 128 bits, and this compiler has no conversion from a pointer to that')
		return error('pointer into a 128-bit object')
	}
	if e.constant(expr) == none && (e.width_of(expr) or { 0 }) != 4 {
		e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot widen into an object of 128 bits')
		return error('value into a 128-bit object')
	}
	accumulator := e.accumulator(line, col)!
	waiting := e.remainder(line, col)!
	pointer := e.scratch(line, col)!
	e.emit_expr_at(expr, 1)!
	e.append(e.target.sign_extend_word(accumulator, accumulator)!)
	e.append(e.target.move_register64(waiting, accumulator)!)
	e.append(e.target.shift_right_arithmetic(accumulator, 63)!)
	e.load_argument(address, pointer, e.target.word_size, line, col)!
	e.append(e.target.add_immediate(pointer, e.target.word_size))
	e.append(e.target.store_indirect(pointer, accumulator, e.target.word_size)!)
	e.append(e.target.move_register64(accumulator, waiting)!)
	e.append(e.target.add_immediate(pointer, -e.target.word_size))
	e.append(e.target.store_indirect(pointer, accumulator, e.target.word_size)!)
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
	if slot.width == 8 {
		// A value narrower than the slot is widened into the whole register
		// before it is written: the store moves eight bytes, so a negative int
		// whose upper half the load cleared would be written as its unsigned
		// reading. Measured on gcc 16.2.1: `long a = -9;` holds -9.
		e.extend_operand_to_word(expr, line, col)!
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

// fits_immediate32 says whether a constant can be written by the one instruction
// this back end writes a constant with, which takes four bytes: a value up to
// 2^32 - 1 written as unsigned, or one down to -2^31 written as signed. Anything
// outside that has no encoding in the instruction, and writing its low four
// bytes would be a wrong value rather than a shorter one.
fn fits_immediate32(value i64) bool {
	return (value >= 0 && value <= 4294967295) || (value >= -2147483648 && value < 0)
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
		// A constant of a 64-bit integer type is written at that width, which is
		// the ten-byte move: the four-byte one below takes four bytes and clears
		// the rest of the register, so a value whose top bit is set would arrive
		// zero-extended rather than as itself.
		if e.eight_byte_integer(expr.typ) {
			register := e.accumulator(expr_line(expr), expr_col(expr))!
			e.append(e.target.move_immediate64(register, u64(value))!)
			return
		}
		// The move below takes four bytes, and a constant that does not fit four
		// bytes cannot be written by it. Such a constant arrives here only when
		// its spelling gave it a type wider than int - `1234567890123456789LL`
		// is a long long - because a narrower literal that did not fit had its
		// type refused where the type was decided. Writing the low four bytes
		// would be a wrong value with no diagnostic, which is the one outcome
		// this compiler treats as a bug, so the constant is refused by name.
		if !fits_immediate32(value) {
			e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: the constant ${value} needs more than the four bytes this back end writes a constant with')
			return error('constant does not fit the immediate')
		}
		register := e.accumulator(expr_line(expr), expr_col(expr))!
		e.append(e.target.move_immediate32(register, u32(value))!)
		return
	}
	match expr {
		ast.IntLit {
			// An integer literal is a constant, so the walk above has already
			// answered for it; this is the same answer for a reader who wonders.
			// It is checked the same way, because the answer and the instruction
			// are one thing.
			register := e.accumulator(expr.line, expr.col)!
			if e.eight_byte_integer(expr.typ) {
				e.append(e.target.move_immediate64(register, u64(expr.value))!)
				return
			}
			if !fits_immediate32(expr.value) {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the constant ${expr.value} needs more than the four bytes this back end writes a constant with')
				return error('constant does not fit the immediate')
			}
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
			e.reference(e.target.load_double_constant(register, 0)!, .float_constant, float_key(expr.value), e.target.name_of(register))
		}
		ast.Ident {
			slot := e.lookup(expr.name) or {
				// Not a local: a top-level object is storage the image holds,
				// and its name is the address of that storage. What is read is
				// the value at the width the object was defined with, which is
				// the same load an element of an array takes.
				if object := e.global_of(expr.name) {
					register := e.accumulator(expr.line, expr.col)!
					e.reference(e.target.address_of(register, 0), .global_address, expr.name, e.target.name_of(register))
					if object.count > 0 {
						// The name of an array is the address of its first
						// element.
						return
					}
					if object.count == 0 && object.width == wide_bytes {
						// A top-level object of a 128-bit type read as a value gets the
						// refusal a local of the type gets: of that width there is no
						// value here, only storage, and the storage is real.
						e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
						return error('128-bit value')
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
			if slot.wide {
				// A 128-bit object is stored, copied and addressed, and it is
				// not a value this back end has: reading the name would have to
				// answer with a value of that width, so the refusal names what
				// the object is good for instead.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
				return error('128-bit value')
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
			if e.writes_a_128(expr.spelling) {
				// The object holds a member of that width, and the read is the
				// value question, which is the one this back end has no answer
				// for: the member's own address is the part that works.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the member ${expr.name}.${expr.member} is declared ${expr.spelling}, and this back end stores an object of that width but has no value of it to read')
				return error('unsupported member type')
			}
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
			e.reference(e.target.address_of(register, 0), .take_address, expr.value, e.target.name_of(register))
		}
		ast.Unary {
			e.emit_unary(expr, depth)!
		}
		ast.Cast {
			e.emit_cast(expr, depth)!
		}
		ast.Binary {
			e.emit_binary(expr, depth)!
		}
		ast.IncDec {
			e.emit_inc_dec(expr, depth)!
		}
		ast.Conditional {
			e.emit_conditional(expr, depth)!
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
			return e.emit_index(expr, depth)
		}
	}
}

// emit_index writes one element, `E1[E2]`: the value at the address the element
// sits at. An element of a named array is read by the path this back end has
// always used, which addresses the array from its place in the frame or in the
// image and scales the index by the width of one element. Every other base goes
// through the general path: the base's own value is the address, because an
// array's name and a pointer are both worth one, and the stride is the size the
// model gives the element's type.
//
// An element that is itself an array is worth the address of its first element,
// which is what an array's name is worth, and it is what `arr[0][1]` needs `arr[0]`
// to be.
fn (mut e Emitter) emit_index(expr ast.Index, depth int) !void {
	if expr.base is ast.Ident {
		name := (expr.base as ast.Ident).name
		if slot := e.lookup(name) {
			if slot.count > 0 {
				return e.emit_named_index(expr, name, depth, true, slot)
			}
		} else if object := e.global_of(name) {
			if object.count > 0 {
				return e.emit_named_index(expr, name, depth, false, Slot{})
			}
		} else {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${name} is not a local of this function')
			return error('unknown name')
		}
	}
	return e.emit_general_index(expr, depth)
}

// emit_named_index reads one element of an array the reader knows the name and
// the place of: a local, whose storage is at an offset in the frame, or a
// top-level object, whose storage is in the image and whose address is a
// reference the layout fills in.
fn (mut e Emitter) emit_named_index(expr ast.Index, name string, depth int, local bool, slot Slot) !void {
	if local {
		e.emit_expr_at(expr.index, depth + 1)!
		base := e.frame_pointer(expr.line, expr.col)!
		register := e.accumulator(expr.line, expr.col)!
		e.element_address(base, register, slot.width, slot.offset, slot.wide, name, expr.line,
			expr.col)!
		if slot.wide {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
			return error('128-bit element')
		}
		if slot.floating {
			// An element of an array of doubles: the address is in a general
			// register and the value is read into a floating-point one, which
			// is the same split the load of a double global makes.
			double_register := e.float_accumulator(expr.line, expr.col)!
			e.append(e.target.load_double_indirect(register, double_register)!)
			return
		}
		e.append(e.target.load_indirect(register, register, slot.width)!)
		return
	}
	// A top-level array: its storage is in the image, so the address of an
	// element is an offset from the address of the object rather than from the
	// frame.
	object := e.global_of(name) or { return error('unknown name') }
	e.emit_expr_at(expr.index, depth + 1)!
	register := e.accumulator(expr.line, expr.col)!
	// The address of the object goes into the scratch register after the index
	// is computed, so that the index expression cannot overwrite it on the way.
	base := e.scratch(expr.line, expr.col)!
	e.reference(e.target.address_of(base, 0), .global_address, name, e.target.name_of(base))
	wide := !object.object && object.width == wide_bytes
	e.element_address(base, register, object.width, 0, wide, name, expr.line, expr.col)!
	if wide {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
		return error('128-bit element')
	}
	if object.floating {
		double_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_double_indirect(register, double_register)!)
		return
	}
	e.append(e.target.load_indirect(register, register, object.width)!)
}

// emit_general_index reads one element whose base is not a name the reader kept
// a place for: a pointer, a member that is an array, the row of a
// two-dimensional array, or a call that hands back an address.
fn (mut e Emitter) emit_general_index(expr ast.Index, depth int) !void {
	e.emit_element_address(expr, depth)!
	if expr.typ.is_array() {
		// The element is an array, so its value is the address of its first
		// element, which is what emit_element_address left in the accumulator.
		return
	}
	address := e.accumulator(expr.line, expr.col)!
	if expr.typ.kind == .double {
		double_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_double_indirect(address, double_register)!)
		return
	}
	width := e.storage_width(expr.typ) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${expr.typ.describe()} is not a value this back end reads')
		return error('unsupported element type')
	}
	e.append(e.target.load_indirect(address, address, width)!)
}

// emit_element_address leaves in the accumulator the address of the element
// `E1[E2]` names: the base's value, which is the address of an array's first
// element or a pointer's own value, plus the index scaled by the size of one
// element. It is the address half of the element read and of the element write,
// which is why the two share it.
fn (mut e Emitter) emit_element_address(expr ast.Index, depth int) !void {
	e.emit_base_address(expr.base, depth + 1)!
	base := e.value_slot(depth)
	e.store_accumulator(base, expr.line, expr.col)!
	e.emit_expr_at(expr.index, depth + 1)!
	index := e.accumulator(expr.line, expr.col)!
	other := e.scratch(expr.line, expr.col)!
	e.load_argument(base, other, e.target.word_size, expr.line, expr.col)!
	stride := e.representation.size_of(expr.typ) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${expr.typ.describe()} has no size this back end can scale an index by')
		return error('no element size')
	}
	e.element_address(other, index, stride, 0, stride == wide_bytes, 'the element', expr.line, expr.col)!
}

// emit_base_address leaves in the accumulator the address a subscript scales from.
// For an array's name that address is what the name is worth, which is the same
// value a read of the name produces - except for an array of 128-bit objects,
// whose name read is refused because there is no value of that width. The address
// of such an array is still real, so it is taken here directly rather than through
// the value read. Every other base is a pointer already, and its own value is the
// address.
fn (mut e Emitter) emit_base_address(base ast.Expr, depth int) !void {
	if base is ast.Ident {
		name := (base as ast.Ident).name
		if slot := e.lookup(name) {
			if slot.count > 0 {
				register := e.accumulator(base.line, base.col)!
				frame := e.frame_pointer(base.line, base.col)!
				e.append(e.target.address_of_slot(frame, slot.offset, register))
				return
			}
		} else if object := e.global_of(name) {
			if object.count > 0 {
				register := e.accumulator(base.line, base.col)!
				e.reference(e.target.address_of(register, 0), .global_address, name, e.target.name_of(register))
				return
			}
		}
	}
	e.emit_expr_at(base, depth)!
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
			e.reference(e.target.address_of(register, 0), .global_address, name, e.target.name_of(register))
			return
		}
	}
	if unary.expr is ast.Field {
		// The member's address is the object's address plus the byte the layout
		// put the member at, which is the same computation a member read makes
		// and stops short of the read.
		e.address_of_member(unary.expr.name, unary.expr.index, unary.expr.offset,
			unary.expr.through_pointer, 0, unary.line, unary.col)!
		return
	}
	if unary.expr is ast.Index {
		// The element's address, which is what the subscript computes before it
		// reads or writes through it.
		e.emit_element_address(unary.expr, 0)!
		return
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
			'${describe_target(expr.base)}[...]'
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
	if unary.op == '*' {
		// Reading through an address is not a computation either: the operand is
		// the address and the value is at it.
		return e.emit_deref(unary, depth)
	}
	if e.wide_value(unary.expr) {
		// A 128-bit operand is a pair rather than a value in the accumulator, so
		// the operators it has a meaning for are computed on the pair.
		return e.emit_wide_unary(unary, depth)
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
			if !e.eight_byte_integer(unary.expr.typ) {
				// Eight bytes that are not an integer is the width of a pointer
				// and the only other width this back end has, so the diagnostic
				// can say what it is.
				e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} takes an int, and this one is a pointer')
				return error('non-int operand')
			}
		}
	}
	e.emit_expr_at(unary.expr, depth + 1)!
	register := e.accumulator(unary.line, unary.col)!
	wide := e.eight_byte_integer(unary.expr.typ)
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
			} else if wide {
				e.append(e.target.negate_word(register)!)
			} else {
				e.append(e.target.negate(register)!)
			}
		}
		'~' {
			if wide {
				e.append(e.target.complement_word(register)!)
			} else {
				e.append(e.target.complement(register)!)
			}
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
			} else if wide {
				e.append(e.target.logical_not_word(register)!)
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

// emit_inc_dec writes `++x`, `--x`, `x++` or `x--` for the name the node holds,
// which is the one operand the parser builds it for: a local in the frame or a
// top-level object in the image, of an integer type.
//
// The step is one, added for `++` and subtracted for `--`. What separates the two
// spellings is the value left in the accumulator: the prefix form leaves the
// object after the step, the postfix form what it held before, so the postfix
// form is the prefix form with the old value parked in a frame slot while the
// step runs and read back at the end. The slot is the one this level of nesting
// already uses for a half-finished value, which is free while the step runs
// because the step evaluates nothing.
//
// A char is stepped and written at its own byte: the read widens it to the int
// the language promotes it to, the step adds an int, and the store cuts the
// result back to a byte, which is what `c++` is defined to do. The step runs at
// the width of the object, so an int wraps at four bytes rather than producing a
// value no int holds.
fn (mut e Emitter) emit_inc_dec(expr ast.IncDec, depth int) !void {
	step := if expr.op == '++' { i32(1) } else { i32(-1) }
	if slot := e.lookup(expr.name) {
		if slot.count > 0 || slot.bytes > 0 || slot.wide || slot.floating {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${expr.name}, and this compiler steps an integer name only')
			return error('inc-dec operand is not an integer name')
		}
		e.load_accumulator(slot, expr.line, expr.col)!
		old := if expr.postfix { e.value_slot(depth) } else { Slot{} }
		if expr.postfix {
			e.store_accumulator(old, expr.line, expr.col)!
		}
		register := e.accumulator(expr.line, expr.col)!
		e.append(e.target.add_immediate(register, step))
		e.store_accumulator(slot, expr.line, expr.col)!
		if expr.postfix {
			e.load_accumulator(old, expr.line, expr.col)!
		}
		return
	}
	if object := e.global_of(expr.name) {
		if object.count > 0 || object.object || object.floating || object.width == wide_bytes {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${expr.name}, and this compiler steps an integer name only')
			return error('inc-dec operand is not an integer name')
		}
		// The object is storage in the image, so its address is a reference the
		// layout fills in and is parked while the step runs: the value is read
		// through the address, stepped, and written back through it.
		register := e.accumulator(expr.line, expr.col)!
		e.reference(e.target.address_of(register, 0), .global_address, expr.name, e.target.name_of(register))
		address := e.value_slot(depth)
		e.store_accumulator(address, expr.line, expr.col)!
		address_register := e.scratch(expr.line, expr.col)!
		e.load_argument(address, address_register, e.target.word_size, expr.line, expr.col)!
		e.append(e.target.load_indirect(address_register, register, object.width)!)
		old := if expr.postfix { e.value_slot(depth + 1) } else { Slot{} }
		if expr.postfix {
			e.store_accumulator(old, expr.line, expr.col)!
		}
		e.append(e.target.add_immediate(register, step))
		e.append(e.target.store_indirect(address_register, register, object.width)!)
		if expr.postfix {
			e.load_accumulator(old, expr.line, expr.col)!
		}
		return
	}
	e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${expr.name}, and no local or top-level object of that name is in scope')
	return error('unknown inc-dec target')
}

// emit_cast writes a conversion. The operand is computed first and what the
// target type is decides whether anything else is written, because the four
// classes this back end carries are the ones a conversion can move between: an
// int of four bytes, the char such a value is narrowed to, a double of eight
// bytes in the floating-point file, and a pointer, which is the machine's word.
//
// A conversion inside one class writes nothing, because the value is already the
// one the target asks for: `(char *)p` is the same bits, `(int)c` is the int the
// load widened the char to, and `(int)p` is the low half of the address, which is
// the half a value of int width is read from. A conversion between two classes is
// the one instruction that widens or narrows the value, and the widening keeps
// its sign, which is what the language asks for when an int becomes a pointer.
//
// A conversion to anything else is refused by name: this back end has no register
// for an unsigned char or a long, and converting a value to one it cannot hold
// would be writing an answer nothing asked for.
// low_word_of_object leaves the low word of a 128-bit object in the accumulator,
// read at the width the caller asks for. Every conversion out of such an object is
// its value taken modulo the width of the target, which is the low word and nothing
// above it: measured on gcc 16.2.1, `(int)` of a stored 300 is 300, `(char)` of one
// is 44, and `(int)` of a stored -1 is -1.
//
// The read is made through the object's own address and at that width, and the bytes
// it takes are the low ones because this target stores a value from its least
// significant byte up. A byte read as a char is given the sign of its own top bit,
// which is what a char is here.
//
// The cast of an object to a narrower type and the store of one into a narrower slot
// are the same read, so both of them come through here rather than each keeping its
// own copy of the sequence.
fn (mut e Emitter) low_word_of_object(expr ast.Expr, width int, line int, col int, depth int) !void {
	match expr {
		ast.Index {
			// An element of an array of 128-bit objects, or of any other
			// element whose low word a conversion asked for: the address of the
			// element, and the word read through it at the width named.
			e.emit_element_address(expr, depth + 1)!
			register := e.accumulator(line, col)!
			e.append(e.target.load_indirect(register, register, width)!)
			if width == 1 {
				e.append(e.target.sign_extend_byte(register)!)
			}
			return
		}
		else {}
	}
	register := e.accumulator(line, col)!
	if !e.names_an_object(expr) {
		// A value of the type that is not an object — the result of an addition,
		// say — is an expression rather than storage: it is emitted here, and what
		// it leaves in the accumulator is the low word, which is what every
		// conversion out of the type reads. Only a name, a member and an element
		// have bytes at an address to read the word out of.
		e.emit_value(expr, depth)!
	} else {
		e.address_of_object(expr, depth)!
		e.append(e.target.load_indirect(register, register, width)!)
	}
	if width == 1 {
		e.append(e.target.sign_extend_byte(register)!)
	}
}

fn (mut e Emitter) emit_cast(cast ast.Cast, depth int) !void {
	target := cast.typ
	if target.kind in [.int128, .unsigned_int128] {
		// A conversion *to* a 128-bit type is the value widened into the pair, the
		// same widening a 128-bit operation does to a narrower operand: the word
		// above holds the sign of the narrower value when that value was signed and
		// zero when it was not. A value that is already a pair converts to nothing,
		// because those two words are the value. Measured on gcc 16.2.1:
		// `(__int128)(char)200` is -56 and `(unsigned __int128)(int)-1` is the
		// 128-bit value of all ones.
		if cast.expr.typ.kind == .double {
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and no instruction here converts a double to a 128-bit value')
			return error('double to 128 bits')
		}
		if e.wide_value(cast.expr) {
			return e.emit_value(cast.expr, depth)
		}
		e.emit_value(cast.expr, depth + 1)!
		width := e.storage_width(cast.expr.typ) or {
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and the narrower type has no width here to widen from')
			return error('no width to widen from')
		}
		// The slot holds the pair the widening writes, which is two words whatever
		// the narrower type's width was: widen_into_pair stores both of them.
		slot := e.reserve(wide_bytes)
		e.widen_into_pair(slot, cast.expr.typ.kind.is_unsigned(), width, cast.line, cast.col)!
		return e.load_pair(slot, cast.line, cast.col)
	}
	if target.kind !in [.int_, .unsigned_int, .char_, .signed_char, .double, .pointer, .long,
		.unsigned_long, .long_long, .unsigned_long_long] {
		e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion to ${cast.spelling} is not one this back end makes, and it converts between int, the four 64-bit integers, char, double and a pointer')
		return error('unsupported conversion')
	}
	if e.wide_value(cast.expr) {
		// A 128-bit object converts to a narrower type by its low word: the
		// value of such a type is the two words the object holds, and every
		// conversion the language allows out of it is that value taken modulo the
		// width of the target, which is the low word and nothing above it.
		// Measured on gcc 16.2.1: `(int)(__int128)300` is 300, `(char)` of one is
		// 44, `(char *)` of one is the low eight bytes, and `(int)(__int128)-1` is
		// -1.
		//
		// The read is made through the object's own address and at the width of
		// the target, and the bytes it takes are the low ones because this target
		// stores a value from its least significant byte up.
		if target.kind == .double {
			// A double of that value is not the low word's bytes: it is the
			// rounding of the whole value, which is wider than the word this back
			// end converts from, so it is refused rather than answered with the
			// low word as though the top of the value were zero.
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from a 128-bit object to ${cast.spelling} is not one this back end makes, and a value that wide does not convert to a floating type here')
			return error('128-bit to a double')
		}
		width := e.storage_width(target) or {
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from a 128-bit object to ${cast.spelling}, and there is no read of that width')
			return error('no read of that width')
		}
		return e.low_word_of_object(cast.expr, width, cast.line, cast.col, depth + 1)
	}
	floating := e.floating_of(cast.expr)
	if target.kind == .double {
		e.emit_expr_at(cast.expr, depth + 1)!
		// A pointer is refused here by the conversion itself, by name.
		e.convert_to_double(cast.expr, cast.line, cast.col)!
		return
	}
	e.emit_expr_at(cast.expr, depth + 1)!
	if floating {
		if target.kind == .pointer {
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from a double to ${cast.spelling}, and a floating type is not a value an address is made of')
			return error('double to a pointer')
		}
		if e.eight_byte_integer(target) {
			// The one instruction here that converts a double to an integer
			// leaves a value of four bytes, so a conversion to a 64-bit type is
			// a different conversion and is refused by name rather than answered
			// with four bytes of a value eight bytes wide.
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and the conversion this back end has writes a value of four bytes')
			return error('double to a 64-bit integer')
		}
		e.convert_to_int(cast.expr, cast.line, cast.col)!
	}
	register := e.accumulator(cast.line, cast.col)!
	// The width of the value in the register now, which decides whether a
	// conversion writes anything: a value already as wide as the target is the
	// one the target asks for, and a char is the int its load widened it to.
	source := e.converted_width(cast.expr.typ) or { 0 }
	if e.eight_byte_integer(target) {
		// A conversion to a 64-bit integer widens a narrower value to the whole
		// register. Which extension applies is the signedness of the *source*
		// and not of the target: `(long)(unsigned int)-1` is 4294967295, and
		// sign-extending it would answer -1. Measured on gcc 16.2.1, which
		// widens an int to a long with cltq and an unsigned int with a 32-bit
		// move.
		if source == 4 {
			if cast.expr.typ.kind.is_unsigned() {
				e.append(e.target.move_register32(register, register)!)
			} else {
				e.append(e.target.sign_extend_word(register, register)!)
			}
		}
		return
	}
	if target.kind == .pointer {
		if !e.is_a_pointer(cast.expr) {
			// An int is four bytes and an address is eight: the value is
			// widened into the whole register with its sign kept.
			e.append(e.target.sign_extend_word(register, register)!)
		}
		return
	}
	if target.kind in [.char_, .signed_char] {
		// The low byte of the register is the char, and the bits above it are
		// that byte's sign, which is what this target's char is.
		e.append(e.target.sign_extend_byte(register)!)
	}
	if e.eight_byte_integer(cast.expr.typ) && target.kind in [.int_, .unsigned_int] {
		// A narrowing from eight bytes to four: the low half is the value taken
		// modulo 2^32, and what sits above it is that half's sign when the target
		// is signed and zero when it is not, because every later read of the
		// value is of the width the conversion named. The source is asked about
		// its kind and not about its width, because a double and a pointer are
		// eight bytes in the register too and neither is an integer this
		// narrowing is written for: `(int)d` is the one instruction that
		// converts a double, and it already leaves a four-byte value.
		if target.kind == .unsigned_int {
			e.append(e.target.move_register32(register, register)!)
		} else {
			e.append(e.target.sign_extend_word(register, register)!)
		}
	}
}

// storage_width is the width of the value at an address of this type: a char is
// one byte, an int is four, and a pointer is the machine's word. A double is read
// by the instruction that moves one rather than at a width here, and a type the
// back end has no load for answers none.
fn (e Emitter) storage_width(t types.Type) ?int {
	return match t.kind {
		.char_, .signed_char { 1 }
		.int_, .unsigned_int { 4 }
		.long, .unsigned_long, .long_long, .unsigned_long_long { 8 }
		.pointer, .array { e.target.word_size }
		else { none }
	}
}

// eight_byte_integer says whether a type is one of the four 64-bit integer types,
// which is the question a value of eight bytes has to be asked before it is
// treated as a pointer: a pointer is eight bytes too, and the machine's word is
// what an address moves in.
fn (e Emitter) eight_byte_integer(t types.Type) bool {
	return t.kind in [types.Kind.long, .unsigned_long, .long_long, .unsigned_long_long]
}

// step_is_wide says whether an operation computes at the width of a word, which is
// when either operand is a 64-bit integer: the usual arithmetic conversions make
// the step's type the wider of the two, so one operand is enough to decide. A
// shift is the one operator whose operands are not converted to a common type, and
// 6.5.7 gives its answer the promoted type of its left operand, so only that side
// decides. The comparison is asked of the operands and not of the step's own type,
// because a comparison of two 64-bit integers is a value of int width.
fn (e Emitter) step_is_wide(step ast.Binary) bool {
	if step.op in ['<<', '>>'] {
		return e.eight_byte_integer(step.left.typ)
	}
	return e.eight_byte_integer(step.left.typ) || e.eight_byte_integer(step.right.typ)
}

// comparison_is_unsigned says whether the order a comparison asks for is the
// unsigned one, which is the signedness of the type the two operands convert to
// and not of either one of them: `-1 < 0u` is false because the int converts to
// an unsigned int, and `-1L < 0u` is true because the unsigned int converts to a
// long. The model answers which type that is; a comparison it has no answer for is
// answered signed, which is the pairing a comparison of two addresses has. Measured
// on gcc 16.2.1: `-1 < 0u` is 0 and `-1 < 0` is 1.
fn (e Emitter) comparison_is_unsigned(step ast.Binary) bool {
	common := types.usual_arithmetic_conversions(step.left.typ, step.right.typ, e.representation) or {
		return false
	}
	return common.kind.is_unsigned()
}

// emit_deref reads through an address: the operand is computed into the register,
// and the value at that address is loaded at the width of what the address points
// at. A char is loaded with its sign, which is what makes it the int the language
// promotes it to, and a double is loaded by the instruction that moves one rather
// than by an integer load of the same width. A pointed-at type with no load here
// is refused by name.
fn (mut e Emitter) emit_deref(unary ast.Unary, depth int) !void {
	e.emit_expr_at(unary.expr, depth + 1)!
	address := e.accumulator(unary.line, unary.col)!
	if unary.typ.kind == .double {
		double_register := e.float_accumulator(unary.line, unary.col)!
		e.append(e.target.load_double_indirect(address, double_register)!)
		return
	}
	width := e.storage_width(unary.typ) or {
		e.diagnostics << problem(unary.line, unary.col, 'unsupported: * reads through an address of ${unary.typ.describe()}, and this back end reads ints, chars, doubles and pointers only')
		return error('unsupported pointed-at type')
	}
	e.append(e.target.load_indirect(address, address, width)!)
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
// The 128-bit value model. A value of the type lives in the pair the result
// register and the one above it form, the low word low: that is the pair a
// multiplication and a division already leave their two-word answer in, and the
// pair a call hands one back in, so a value and a machine result are one shape.
// Nothing here decides which word an instruction works on; that is the backend's.
//
// Two pairs do not fit in the registers a step has while the right side is still
// allowed to call a function, so a step keeps both of its operands in the frame:
// the left pair waits in a slot while the right side is computed, and the right
// pair is read out of its slot one word at a time, because the two words of the
// left value are in the two registers a pair lives in.

// wide_pair_slot is the frame slot one level of nesting keeps one operand of a
// 128-bit step in: sixteen bytes, because the value is two words, one level per
// nesting so an outer step's operand survives the step inside it, and one slot
// per side so the two operands do not overwrite each other.
// wide_working_slot is the block a division of two pairs works in, one block per
// level of nesting so a division inside a division still has its own.
fn (mut e Emitter) wide_working_slot(depth int) WideWorking {
	for e.wide_working.len <= depth {
		block := e.reserve(wide_bytes * 4)
		e.wide_working << WideWorking{
			quotient:  Slot{ offset: block.offset, width: block.width }
			remainder: Slot{ offset: block.offset + wide_bytes, width: block.width }
			counter:   Slot{ offset: block.offset + wide_bytes * 2, width: 8 }
			flags:     Slot{ offset: block.offset + wide_bytes * 3, width: 8 }
		}
	}
	return e.wide_working[depth]
}

// wide_load_word and wide_store_word move one word of a pair between a slot and a
// register, which is what a routine that shifts a pair a bit at a time is made of.
fn (mut e Emitter) wide_load_word(slot Slot, at int, reg backend.Register, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	word := e.target.word_size
	e.append(e.target.load_slot(frame, slot.offset + at * word, reg, word)!)
}

fn (mut e Emitter) wide_store_word(slot Slot, at int, reg backend.Register, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	word := e.target.word_size
	e.append(e.target.store_slot(frame, slot.offset + at * word, reg, word)!)
}

// wide_negate_slot negates a pair where it sits, which is the sign change the
// division needs on an operand and on an answer: the low word is negated, the
// borrow it leaves is added to the high word, and the high word is negated. It is
// the sequence emit_wide_unary writes for a sign change in the registers.
fn (mut e Emitter) wide_negate_slot(slot Slot, line int, col int) !void {
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	e.wide_load_word(slot, 0, low, line, col)!
	e.wide_load_word(slot, 1, high, line, col)!
	e.append(e.target.negate_word(low)!)
	e.append(e.target.add_with_carry_immediate(high, 0)!)
	e.append(e.target.negate_word(high)!)
	e.wide_store_word(slot, 0, low, line, col)!
	e.wide_store_word(slot, 1, high, line, col)!
}

// wide_copy_slot copies a pair from one slot to another.
fn (mut e Emitter) wide_copy_slot(from Slot, to Slot, line int, col int) !void {
	low := e.accumulator(line, col)!
	e.wide_load_word(from, 0, low, line, col)!
	e.wide_store_word(to, 0, low, line, col)!
	e.wide_load_word(from, 1, low, line, col)!
	e.wide_store_word(to, 1, low, line, col)!
}

fn (mut e Emitter) wide_pair_slot(mut pairs []Slot, depth int) Slot {
	for pairs.len <= depth {
		pairs << e.reserve(wide_bytes)
	}
	return pairs[depth]
}

// store_pair writes the pair into a slot, the low word at the slot's own offset
// and the high word eight bytes above it, which is the order the bytes of a
// 128-bit object are in.
fn (mut e Emitter) store_pair(slot Slot, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.append(e.target.store_slot(frame, slot.offset, low, word)!)
	e.append(e.target.store_slot(frame, slot.offset + word, high, word)!)
}

// load_pair reads a pair back out of a slot, and is the other half of store_pair.
fn (mut e Emitter) load_pair(slot Slot, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.append(e.target.load_slot(frame, slot.offset, low, word)!)
	e.append(e.target.load_slot(frame, slot.offset + word, high, word)!)
}

// narrow_width is how wide the value a pair is widened from is. It decides which
// of the extensions applies: a value of a word or more is extended from its own top
// bit, and a narrower one from the top bit of a word after the extension the type
// asks for. A type with no width here is one the value cannot come from, and the
// word is the answer that keeps a pair from being built out of nothing.
fn (mut e Emitter) narrow_width(typ types.Type) int {
	width := e.storage_width(typ) or { return e.target.word_size }
	return width
}

// widen_word_pair widens a value narrower than sixteen bytes into a pair, which is
// what the language asks for when an operand of a narrower type meets a 128-bit
// one, or when a function of a 128-bit type returns one: the value becomes a word
// with its own width's arithmetic, and the word above it is that word's sign if
// the value was signed and zero if it was not. Measured on gcc 16.2.1, which
// widens a signed int with cltq and cqto and an unsigned one with a 32-bit move.
//
// The word above is written even when it is zero, because the operation that reads
// it adds it: leaving whatever the register held there would add that instead.
fn (mut e Emitter) widen_word_pair(unsigned bool, width int, line int, col int) !void {
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	if width >= word {
		// A value as wide as a word is extended from its own top bit whichever type
		// it is converted to, because a value that wide is already a word and the
		// conversion of a pointer or a long to a 128-bit type is the value rather
		// than its unsigned reading. Measured on gcc 16.2.1, which answers
		// `(unsigned __int128)(long)-1` with 2^128 - 1 and not with 2^64 - 1.
		e.append(e.target.move_register64(high, low)!)
		e.append(e.target.shift_right_arithmetic(high, 63)!)
	} else if unsigned {
		e.append(e.target.move_register32(low, low)!)
		e.append(e.target.xor_word(high, high)!)
	} else {
		e.append(e.target.sign_extend_word(low, low)!)
		e.append(e.target.move_register64(high, low)!)
		e.append(e.target.shift_right_arithmetic(high, 63)!)
	}
}

// widen_into_pair is the widening with the pair stored into a slot, the low word at
// the slot's own offset and the high word eight bytes above it, which is the order
// the bytes of a 128-bit object are in.
fn (mut e Emitter) widen_into_pair(slot Slot, unsigned bool, width int, line int, col int) !void {
	e.widen_word_pair(unsigned, width, line, col)!
	frame := e.frame_pointer(line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.append(e.target.store_slot(frame, slot.offset, low, word)!)
	e.append(e.target.store_slot(frame, slot.offset + word, high, word)!)
}

// load_wide_object leaves the two words of an object of the type in the pair. The
// object is read through its own address, which is the path a member, an element
// and a top-level object already share, so nothing here knows which of them it was
// handed. The address arrives in the accumulator and the pair is going to live
// there, so it moves aside first: a load of the low word into the accumulator
// would otherwise be a load through the low word.
fn (mut e Emitter) load_wide_object(expr ast.Expr, depth int) !void {
	line := expr_line(expr)
	col := expr_col(expr)
	e.address_of_object(expr, depth)!
	pointer := e.scratch(line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.append(e.target.move_register64(pointer, low)!)
	e.append(e.target.load_indirect(pointer, low, word)!)
	e.append(e.target.add_immediate(pointer, word))
	e.append(e.target.load_indirect(pointer, high, word)!)
}

// emit_value leaves an operand where the operation that asked for it looks for it.
// An operand of the 128-bit type is a pair: an object of the type is read out of
// its sixteen bytes, and anything else of the type is an expression whose own
// emission left the pair standing. A narrower operand is a value in the
// accumulator, which is where the widening and the comparison both read it.
fn (mut e Emitter) emit_value(expr ast.Expr, depth int) !void {
	if !e.wide_value(expr) {
		return e.emit_expr_at(expr, depth)
	}
	match expr {
		ast.Ident, ast.Field, ast.Index {
			return e.load_wide_object(expr, depth)
		}
		else {
			return e.emit_expr_at(expr, depth)
		}
	}
}

// wide_unsigned says whether a 128-bit expression is the unsigned type, which is
// the question a comparison of two pairs asks to pick between the signed and the
// unsigned order. Only the two 128-bit types answer it: measured on gcc 16.2.1, a
// narrower unsigned operand meeting a signed 128-bit one converts to the signed
// type, so the narrow operand's own signedness does not make the comparison an
// unsigned one.
fn (e Emitter) wide_unsigned(expr ast.Expr) bool {
	return expr.typ.kind == .unsigned_int128
}

// word_operation is one word's part of a two-word operation. The low word takes
// the plain form, which is where the carry or the borrow of the two-word value
// comes from, and the high word takes the form that reads that flag as well. The
// bit operations take the same form on both words.
fn (e Emitter) word_operation(op string, dst backend.Register, src backend.Register, carry_in bool) ![]u8 {
	if op == '+' {
		if carry_in {
			return e.target.add_with_carry(dst, src)
		}
		return e.target.add_reg64(dst, src)
	}
	if op == '-' {
		if carry_in {
			return e.target.subtract_with_borrow(dst, src)
		}
		return e.target.subtract_word(dst, src)
	}
	if op == '&' {
		return e.target.and_word(dst, src)
	}
	if op == '|' {
		return e.target.or_word(dst, src)
	}
	return e.target.xor_word(dst, src)
}

// emit_wide_step folds one step of a 128-bit chain: the left value is parked in
// its slot — widened first if it was narrower, since a value of the type arrives
// as a pair and a value of a narrower type as a word — the right side is computed,
// and the operation then reads both operands out of their slots.
fn (mut e Emitter) emit_wide_step(step ast.Binary, depth int) !void {
	// Every operator the grammar can put between two pairs is implemented here. The
	// three bitwise ones are the exception and they are unreachable rather than
	// unimplemented: they have a form below and no caller from source, because the
	// grammar has no bitwise operator at all. They are refused rather than emitted
	// so that a grammar which grows one cannot land on a form nothing has tested.
	if step.op !in ['+', '-', '*', '/', '%', '<<', '>>', '&', '|', '^', '==', '!=', '<', '>', '<=',
		'>='] {
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} on a 128-bit value is not implemented, and this back end computes no value of that width with it')
		return error('wide operator not implemented')
	}
	left := e.wide_pair_slot(mut e.wide_left, depth)
	if e.wide_value(step.left) {
		e.store_pair(left, step.line, step.col)!
	} else {
		e.widen_into_pair(left, step.left.typ.kind.is_unsigned(), e.narrow_width(step.left.typ), step.line, step.col)!
	}
	if step.op in ['<<', '>>'] {
		// The right operand of a shift is a count rather than a value of the pair's
		// type: it is read as a count and never widened into a pair. The type the
		// answer has is the left operand's, which is therefore the only signedness
		// a shift asks about.
		if value := e.constant(step.right) {
			e.load_pair(left, step.line, step.col)!
			return e.apply_wide_shift(step, e.shift_bits(step, value, 128)!, step.line, step.col)
		}
		// A count the program works out is one the emitter does not know, so the
		// pair stays in its slot while the count is worked out into the register the
		// machine reads one from, and then the pair is loaded over it.
		e.emit_value(step.right, depth + 1)!
		count := e.scratch(step.line, step.col)!
		e.check_count_register(step, count)!
		e.append(e.target.move_register64(count, e.accumulator(step.line, step.col)!)!)
		e.load_pair(left, step.line, step.col)!
		return e.apply_wide_shift_register(step, count, step.line, step.col)
	}
	right := e.wide_pair_slot(mut e.wide_right, depth)
	e.emit_value(step.right, depth + 1)!
	if e.wide_value(step.right) {
		e.store_pair(right, step.line, step.col)!
	} else {
		e.widen_into_pair(right, step.right.typ.kind.is_unsigned(), e.narrow_width(step.right.typ), step.line, step.col)!
	}
	e.load_pair(left, step.line, step.col)!
	return e.apply_wide_binary(step, left, right, depth)
}

// emit_wide_division divides one pair by another by shifting and subtracting, which
// is how a division is done when there is nothing to call. gcc hands this operation
// to libgcc at every optimization level, and this back end links no library and has
// no runtime of its own, so the routine is emitted instead of named.
//
// The dividend is copied into the quotient, which is shifted left one bit at a time;
// the remainder is shifted left with the top bit of the quotient coming in at its
// bottom, and the divisor is subtracted from the remainder whenever it fits, which
// sets the quotient's lowest bit. After one pass per bit of the value the quotient
// holds the answer and the remainder holds the remainder.
//
// The signed form is the unsigned one on absolute values, with the signs put back at
// the end: the remainder takes the dividend's sign and the quotient the two signs
// together, which is what C asks for. INT128_MIN divided by -1 is the case that
// would overflow if the signs were put back by negating the dividend, and it does
// not: the absolute value is divided, the quotient comes out as 2^127, and the signs
// cancel, which is the answer gcc 16.2.1 gives rather than a trap.
//
// A divisor of zero is a trap, in gcc and in the C standard both, and it is the
// machine's own trap here: the routine reaches an actual division by the zero
// divisor, so the fault a program sees is the same one gcc's program sees.
fn (mut e Emitter) emit_wide_division(step ast.Binary, left Slot, right Slot, depth int) !void {
	frame := e.frame_pointer(step.line, step.col)!
	low := e.accumulator(step.line, step.col)!
	high := e.remainder(step.line, step.col)!
	other := e.scratch(step.line, step.col)!
	word := e.target.word_size
	signed := !e.wide_unsigned(step.left) && !e.wide_unsigned(step.right)
	work := e.wide_working_slot(depth)
	// A zero divisor faults in the machine, which is the behaviour the language
	// asks for and the one gcc has, so the reachable instruction is a division by
	// it: nothing after this runs in that case.
	e.wide_load_word(right, 0, low, step.line, step.col)!
	e.wide_load_word(right, 1, other, step.line, step.col)!
	e.append(e.target.or_word(low, other)!)
	divisor_is_not_zero := e.label()
	e.branch(.branch_nonzero, divisor_is_not_zero, step.line, step.col)!
	e.wide_load_word(right, 0, other, step.line, step.col)
	e.append(e.target.move_immediate32(low, 0)!)
	e.append(e.target.move_immediate32(high, 0)!)
	e.append(e.target.divide_pair(other)!)
	e.place(divisor_is_not_zero)
	// Each operand is made positive, and whether it had to be is kept: one word per
	// operand.
	e.append(e.target.move_immediate32(low, 0)!)
	e.append(e.target.store_slot(frame, work.flags.offset, low, word)!)
	e.append(e.target.store_slot(frame, work.flags.offset + word, low, word)!)
	if signed {
		for side in 0 .. 2 {
			operand := if side == 0 { left } else { right }
			e.wide_load_word(operand, 1, low, step.line, step.col)!
			e.append(e.target.test_word(low)!)
			e.append(e.target.set_condition(.less, low)!)
			e.append(e.target.widen_byte(low)!)
			e.append(e.target.store_slot(frame, work.flags.offset + side * word, low, word)!)
			e.append(e.target.test_word(low)!)
			was_positive := e.label()
			e.branch(.branch_zero, was_positive, step.line, step.col)!
			e.wide_negate_slot(operand, step.line, step.col)!
			e.place(was_positive)
		}
	}
	// The quotient starts as the dividend, the remainder as zero, and there is one
	// pass per bit of the value.
	e.wide_copy_slot(left, work.quotient, step.line, step.col)!
	e.append(e.target.move_immediate32(low, 0)!)
	e.wide_store_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_store_word(work.remainder, 1, low, step.line, step.col)!
	e.append(e.target.move_immediate32(low, 128)!)
	e.append(e.target.store_slot(frame, work.counter.offset, low, word)!)
	loop := e.label()
	no_subtraction := e.label()
	done := e.label()
	e.place(loop)
	// The bit the remainder takes in is the top bit of the quotient.
	e.wide_load_word(work.quotient, 1, other, step.line, step.col)!
	e.append(e.target.shift_right_word(other, 63)!)
	// The quotient and the remainder each shift left one, and the bit joins the
	// remainder at its bottom, where the shift has just left a zero.
	e.wide_load_word(work.quotient, 0, low, step.line, step.col)!
	e.wide_load_word(work.quotient, 1, high, step.line, step.col)!
	e.append(e.target.shift_wide_left(high, low, 1)!)
	e.append(e.target.shift_left_word(low, 1)!)
	e.wide_store_word(work.quotient, 0, low, step.line, step.col)!
	e.wide_store_word(work.quotient, 1, high, step.line, step.col)!
	e.wide_load_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_load_word(work.remainder, 1, high, step.line, step.col)!
	e.append(e.target.shift_wide_left(high, low, 1)!)
	e.append(e.target.shift_left_word(low, 1)!)
	e.append(e.target.or_word(low, other)!)
	e.wide_store_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_store_word(work.remainder, 1, high, step.line, step.col)!
	// The subtraction that decides it is also the comparison: the borrow out of the
	// high word says whether the divisor fitted.
	e.wide_load_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_load_word(right, 0, other, step.line, step.col)!
	e.append(e.target.subtract_word(low, other)!)
	e.wide_load_word(work.remainder, 1, low, step.line, step.col)!
	e.wide_load_word(right, 1, other, step.line, step.col)!
	e.append(e.target.subtract_with_borrow(low, other)!)
	e.append(e.target.set_condition(.above_or_equal, low)!)
	e.append(e.target.widen_byte(low)!)
	e.append(e.target.test_word(low)!)
	e.branch(.branch_zero, no_subtraction, step.line, step.col)!
	e.wide_load_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_load_word(right, 0, other, step.line, step.col)!
	e.append(e.target.subtract_word(low, other)!)
	e.wide_store_word(work.remainder, 0, low, step.line, step.col)!
	e.wide_load_word(work.remainder, 1, low, step.line, step.col)!
	e.wide_load_word(right, 1, other, step.line, step.col)!
	e.append(e.target.subtract_with_borrow(low, other)!)
	e.wide_store_word(work.remainder, 1, low, step.line, step.col)!
	e.wide_load_word(work.quotient, 0, low, step.line, step.col)!
	e.append(e.target.move_immediate32(other, 1)!)
	e.append(e.target.or_word(low, other)!)
	e.wide_store_word(work.quotient, 0, low, step.line, step.col)!
	e.place(no_subtraction)
	// One fewer bit to go, and the loop ends when there are none.
	e.append(e.target.load_slot(frame, work.counter.offset, low, word)!)
	e.append(e.target.add_immediate(low, -1))
	e.append(e.target.store_slot(frame, work.counter.offset, low, word)!)
	e.append(e.target.test_word(low)!)
	e.branch(.branch_nonzero, loop, step.line, step.col)!
	e.place(done)
	if signed {
		// The remainder takes the dividend's sign, and the quotient takes the two
		// signs together. Both are written out, because which one is the answer
		// depends on the operator rather than on the routine.
		remainder_kept := e.label()
		e.append(e.target.load_slot(frame, work.flags.offset, low, word)!)
		e.append(e.target.test_word(low)!)
		e.branch(.branch_zero, remainder_kept, step.line, step.col)!
		e.wide_negate_slot(work.remainder, step.line, step.col)!
		e.place(remainder_kept)
		quotient_kept := e.label()
		e.append(e.target.load_slot(frame, work.flags.offset, low, word)!)
		e.append(e.target.load_slot(frame, work.flags.offset + word, other, word)!)
		e.append(e.target.xor_word(low, other)!)
		e.append(e.target.test_word(low)!)
		e.branch(.branch_zero, quotient_kept, step.line, step.col)!
		e.wide_negate_slot(work.quotient, step.line, step.col)!
		e.place(quotient_kept)
	}
	answer := if step.op == '/' { work.quotient } else { work.remainder }
	e.wide_load_word(answer, 0, low, step.line, step.col)!
	e.wide_load_word(answer, 1, high, step.line, step.col)!
}

// check_count_register holds the one register the machine reads a shift count from
// to the count the emitter is about to shift by. The encodings of a computed shift
// name no place for the count, because there is only one place they can name, and a
// count that ended up anywhere else would shift by whatever that register held.
fn (mut e Emitter) check_count_register(binary ast.Binary, reg backend.Register) !void {
	if e.target.carries_shift_count(reg) {
		return
	}
	e.diagnostics << problem(binary.line, binary.col, 'internal: the count of ${binary.op} is in ${e.target.name_of(reg)}, and the machine reads the count of a shift from cl')
	return error('the count is not in cl')
}

// apply_wide_shift shifts a pair by a constant count, with the pair in the
// registers. A shift of one word or more moves the other word across, which is a
// different sequence from a shift of less than one, and gcc 16.2.1's own code at
// -O0 is what both of them are: for a count below 64 the low word comes into the
// high one with an shld and the low one is shifted, and for a count of 64 or more
// one word is moved over the other and the other is cleared. The shift that keeps
// the sign of a signed value is the arithmetic one, which is where the sign of the
// answer comes from once the high word has moved down.
fn (mut e Emitter) apply_wide_shift(step ast.Binary, count u8, line int, col int) !void {
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	unsigned := e.wide_unsigned(step.left)
	if count == 0 {
		// Nothing moves, and the pair in the registers is already the answer.
		return
	}
	if count < 64 {
		if step.op == '<<' {
			e.append(e.target.shift_wide_left(high, low, count)!)
			e.append(e.target.shift_left_word(low, count)!)
		} else {
			e.append(e.target.shift_wide_right(low, high, count)!)
			if unsigned {
				e.append(e.target.shift_right_word(high, count)!)
			} else {
				e.append(e.target.shift_right_arithmetic(high, count)!)
			}
		}
		return
	}
	// A count of a word or more leaves nothing of the first word: the second word
	// moves over it and what is left is filled the way a shift of the word alone
	// would fill it.
	moved := u8(count - 64)
	if step.op == '<<' {
		e.append(e.target.move_register64(high, low)!)
		e.append(e.target.move_immediate32(low, 0)!)
		e.append(e.target.shift_left_word(high, moved)!)
		return
	}
	e.append(e.target.move_register64(low, high)!)
	if unsigned {
		e.append(e.target.move_immediate32(high, 0)!)
		e.append(e.target.shift_right_word(low, moved)!)
	} else {
		// The word that moved down is what the sign is read from, so it is kept in
		// the register above and spread over it before the answer is shifted.
		e.append(e.target.move_register64(high, low)!)
		e.append(e.target.shift_right_arithmetic(high, 63)!)
		e.append(e.target.shift_right_arithmetic(low, moved)!)
	}
}

// apply_wide_shift_register shifts a pair by a count in a register, with the pair in
// the registers. The count decides which of two sequences runs, because the amount
// the second word moves by is not a shift of a register as the first word's is: the
// bit of the count that says the count is a word or more is tested first, and both
// sequences shift by the machine's own reading of the count modulo the word, which
// is the answer a language that calls the count undefined gets from gcc as well.
fn (mut e Emitter) apply_wide_shift_register(step ast.Binary, count backend.Register, line int, col int) !void {
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	unsigned := e.wide_unsigned(step.left)
	over := e.label()
	done := e.label()
	e.append(e.target.test_byte_immediate(count, 64)!)
	e.branch(.branch_zero, over, line, col)!
	// A count of a word or more: the second word moves over the first, and what is
	// left of the count is what the machine reads of it.
	if step.op == '<<' {
		e.append(e.target.move_register64(high, low)!)
		e.append(e.target.move_immediate32(low, 0)!)
		e.append(e.target.shift_left_word_register(high)!)
	} else {
		e.append(e.target.move_register64(low, high)!)
		if unsigned {
			e.append(e.target.move_immediate32(high, 0)!)
			e.append(e.target.shift_right_word_register(low)!)
		} else {
			// The word that moved down is kept in the register above and spread over
			// it, which is where the sign of the answer comes from.
			e.append(e.target.move_register64(high, low)!)
			e.append(e.target.shift_right_arithmetic(high, 63)!)
			e.append(e.target.shift_right_arithmetic_word_register(low)!)
		}
	}
	e.jump(done)!
	e.place(over)
	// A count below a word: the bits that leave one word arrive in the other.
	if step.op == '<<' {
		e.append(e.target.shift_wide_left_register(high, low)!)
		e.append(e.target.shift_left_word_register(low)!)
	} else {
		e.append(e.target.shift_wide_right_register(low, high)!)
		if unsigned {
			e.append(e.target.shift_right_word_register(high)!)
		} else {
			e.append(e.target.shift_right_arithmetic_word_register(high)!)
		}
	}
	e.place(done)
}

// apply_wide_binary does the operation with the left pair in the registers and the
// right pair in a slot, one word of it at a time in the scratch register. A load
// between an instruction and the one that carries into it does not disturb the
// flags, which is what makes reading the second operand in between possible at
// all. Every sequence here is gcc 16.2.1's at -O0, which is where the order of the
// two subtractions and the sign of each answer were read off.
fn (mut e Emitter) apply_wide_binary(step ast.Binary, left Slot, right Slot, depth int) !void {
	frame := e.frame_pointer(step.line, step.col)!
	low := e.accumulator(step.line, step.col)!
	high := e.remainder(step.line, step.col)!
	other := e.scratch(step.line, step.col)!
	word := e.target.word_size
	match step.op {
		'+', '-', '&', '|', '^' {
			e.append(e.target.load_slot(frame, right.offset, other, word)!)
			e.append(e.word_operation(step.op, low, other, false)!)
			e.append(e.target.load_slot(frame, right.offset + word, other, word)!)
			e.append(e.word_operation(step.op, high, other, true)!)
		}
		'/', '%' {
			// A division is a routine rather than a sequence, so it is written
			// where it is called and given both operands: it works in the frame
			// for the whole of itself.
			return e.emit_wide_division(step, left, right, depth)
		}
		'*' {
			// A pair multiplied by a pair, which gcc emits the same way for both
			// signed types at -O0: the low words are multiplied exactly into the
			// pair, and the two cross products are added into the high word of
			// that product. What a cross product carries above its own low word
			// cannot reach the answer, because it is a multiple of 2^128, so gcc
			// adds the two with a lea, which does not set the flags; a plain add
			// is the same instruction here.
			crossed := e.wide_pair_slot(mut e.wide_scratch, depth)
			e.append(e.target.load_slot(frame, left.offset + word, low, word)!)
			e.append(e.target.load_slot(frame, right.offset, other, word)!)
			e.append(e.target.multiply_word(low, other)!)
			e.append(e.target.load_slot(frame, right.offset + word, other, word)!)
			e.append(e.target.load_slot(frame, left.offset, high, word)!)
			e.append(e.target.multiply_word(high, other)!)
			e.append(e.target.add_reg64(low, high))
			e.append(e.target.store_slot(frame, crossed.offset, low, word)!)
			e.append(e.target.load_slot(frame, left.offset, low, word)!)
			e.append(e.target.load_slot(frame, right.offset, other, word)!)
			e.append(e.target.multiply_pair(other)!)
			e.append(e.target.load_slot(frame, crossed.offset, other, word)!)
			e.append(e.target.add_reg64(high, other))
		}
		'==', '!=' {
			// Two pairs are equal when neither word differs, and a difference in
			// either of them has to survive to the condition: the words are xored
			// against the other pair's and ored together, which is gcc's shape.
			e.append(e.target.load_slot(frame, right.offset, other, word)!)
			e.append(e.target.xor_word(low, other)!)
			e.append(e.target.load_slot(frame, right.offset + word, other, word)!)
			e.append(e.target.xor_word(high, other)!)
			e.append(e.target.or_word(low, high)!)
			condition := backend.condition_for(e.target.name, step.op, false)!
			e.append(e.target.set_condition(condition, low)!)
			e.append(e.target.widen_byte(low)!)
		}
		else {
			// The order of two pairs is the borrow out of the subtraction of
			// their low words carried into the subtraction of their high ones,
			// and the condition that reads the result is the unsigned one unless
			// both operands are signed.
			//
			// A strict comparison is written the other way round, because the
			// zero flag of the second subtraction is the zero flag of its own
			// result and not of the 128-bit difference: for two values whose low
			// words differ and whose high words are equal, that subtraction is
			// zero, and a condition that reads the zero flag would answer "not
			// greater" for a value that is greater. `less` and `greater_or_equal`
			// read the sign and overflow flags, which the second subtraction does
			// carry correctly. gcc 16.2.1 emits exactly this at -O0: for `a > b` it
			// subtracts b from a with the sign flag read, and for `a <= b` it does
			// the same and reads `greater_or_equal`.
			swapped := step.op in ['>', '<=']
			unsigned := e.wide_unsigned(step.left) || e.wide_unsigned(step.right)
			from := if swapped { right } else { left }
			against := if swapped { left } else { right }
			e.append(e.target.load_slot(frame, from.offset, low, word)!)
			e.append(e.target.load_slot(frame, from.offset + word, high, word)!)
			e.append(e.target.load_slot(frame, against.offset, other, word)!)
			e.append(e.target.subtract_word(low, other)!)
			e.append(e.target.load_slot(frame, against.offset + word, other, word)!)
			e.append(e.target.subtract_with_borrow(high, other)!)
			compared := if swapped {
				if step.op == '>' { '<' } else { '>=' }
			} else {
				step.op
			}
			condition := backend.condition_for(e.target.name, compared, unsigned)!
			e.append(e.target.set_condition(condition, low)!)
			e.append(e.target.widen_byte(low)!)
		}
	}
}

// store_pair_at writes the pair in the registers at an address the caller parked
// in a slot. It is the same two stores the widening into an object ends with, in
// the same order, because a value of the type computed in the registers is already
// the two words an object of it holds.
fn (mut e Emitter) store_pair_at(address Slot, line int, col int) !void {
	pointer := e.scratch(line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.load_argument(address, pointer, word, line, col)!
	e.append(e.target.store_indirect(pointer, low, word)!)
	e.append(e.target.add_immediate(pointer, word))
	e.append(e.target.store_indirect(pointer, high, word)!)
}

// emit_wide_unary applies a unary operator to a 128-bit value. The sign change is
// the pair's own: the low word is negated, which leaves a borrow behind when it
// was not zero, that borrow is added to the high word, and the high word is
// negated. Measured on gcc 16.2.1, which emits exactly that (negq, adcq $0, negq).
// The complement is the same instruction on both words, and the logical not asks
// whether either word is anything but zero.
fn (mut e Emitter) emit_wide_unary(unary ast.Unary, depth int) !void {
	e.emit_value(unary.expr, depth + 1)!
	low := e.accumulator(unary.line, unary.col)!
	high := e.remainder(unary.line, unary.col)!
	match unary.op {
		'+' {
			return
		}
		'-' {
			e.append(e.target.negate_word(low)!)
			e.append(e.target.add_with_carry_immediate(high, 0)!)
			e.append(e.target.negate_word(high)!)
		}
		'~' {
			e.append(e.target.complement_word(low)!)
			e.append(e.target.complement_word(high)!)
		}
		'!' {
			// A pair is zero when neither of its words is anything but zero, and
			// the answer is a value of the language's int width rather than a byte.
			e.append(e.target.or_word(low, high)!)
			e.append(e.target.test_word(low)!)
			e.append(e.target.set_condition(.equal, low)!)
			e.append(e.target.widen_byte(low)!)
		}
		else {
			e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} on a 128-bit value is not implemented')
			return error('unsupported unary operator')
		}
	}
}

// is_pointer_step says whether a step is one of the two operators that add an
// integer to an address or subtract one from it: `p + 1`, `1 + p` and `p - 1`.
// 6.5.6 scales the integer by the size of the pointed-at type, which is why the
// step is not the integer addition the rest of the arithmetic is.
fn (e Emitter) is_pointer_step(step ast.Binary) bool {
	if step.op == '+' || step.op == '-' {
		return e.is_a_pointer(step.left) || e.is_a_pointer(step.right)
	}
	return false
}

// pointed_size is how many bytes one element of the pointed-at type takes, which
// is what an index is scaled by. An array's name is scaled by the size of one of
// its elements, a pointer by the size of what it points at, and a string by the
// byte a char is.
fn (e Emitter) pointed_size(expr ast.Expr) ?int {
	if expr.typ.is_array() {
		element := expr.typ.element() or { return none }
		return e.representation.size_of(element)
	}
	if expr.typ.is_pointer() {
		pointee := expr.typ.pointee() or { return none }
		return e.representation.size_of(pointee)
	}
	if expr is ast.StrLit {
		return 1
	}
	return none
}

// emit_pointer_step writes an address plus or minus an index: the address is the
// base's own value, the index is scaled by the size of one pointed-at element,
// and the two are added. `p + 1` and `1 + p` are the same address because
// addition commutes, and `p - 1` is the same address with the scaled index
// negated. A step that is not one of those, and a difference of two addresses,
// are refused by name rather than read as an integer addition.
//
// The spine walk has already put the step's left operand in the accumulator, so
// the left side is not emitted again: it is parked while the right side runs, and
// the two are put back together. That is why a chain of steps is walked and not
// re-read at every step.
fn (mut e Emitter) emit_pointer_step(step ast.Binary, depth int) !void {
	left_is_address := e.is_a_pointer(step.left)
	right_is_address := e.is_a_pointer(step.right)
	if left_is_address && right_is_address {
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} on two addresses is not implemented, and the difference of two pointers is a count this back end does not divide by the size of an element')
		return error('pointer step')
	}
	if !left_is_address && step.op != '+' {
		e.diagnostics << problem(step.line, step.col, 'unsupported: the subtraction of an address from an integer is not implemented')
		return error('integer minus pointer')
	}
	stride := e.pointed_size(if left_is_address { step.left } else { step.right }) or {
		spelling := if left_is_address {
			step.left.typ.describe()
		} else {
			step.right.typ.describe()
		}
		e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} scales the index by the size of one element of ${spelling}, and this back end has no size for it')
		return error('no pointee size')
	}
	if left_is_address {
		// The accumulator holds the address and the right side is the index.
		base := e.value_slot(depth)
		e.store_accumulator(base, step.line, step.col)!
		e.emit_expr_at(step.right, depth + 1)!
		// The index is a value of its own type and the address is a word, so
		// the index is extended to a word before it is scaled: a negative index
		// read at four bytes would otherwise arrive zero-extended.
		e.extend_operand_to_word(step.right, step.line, step.col)!
		index := e.accumulator(step.line, step.col)!
		other := e.scratch(step.line, step.col)!
		e.load_argument(base, other, e.target.word_size, step.line, step.col)!
		if step.op == '-' {
			e.append(e.target.negate_word(index)!)
		}
		if stride != 1 {
			e.append(e.target.imul_immediate(index, stride))
		}
		e.append(e.target.add_reg64(index, other))
		return
	}
	// The accumulator holds the index and the right side is the address.
	e.extend_operand_to_word(step.left, step.line, step.col)!
	count := e.value_slot(depth)
	e.store_accumulator(count, step.line, step.col)!
	e.emit_expr_at(step.right, depth + 1)!
	address := e.accumulator(step.line, step.col)!
	index := e.scratch(step.line, step.col)!
	e.load_argument(count, index, e.target.word_size, step.line, step.col)!
	if stride != 1 {
		e.append(e.target.imul_immediate(index, stride))
	}
	e.append(e.target.add_reg64(address, index))
}

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
		if !e.is_pointer_step(step) {
			e.check_int_operands(step)!
		}
		spine << step
		node = step.left
	}
	e.emit_value(node, depth + 1)!
	for i := spine.len - 1; i >= 0; i-- {
		step := spine[i]
		if e.is_pointer_step(step) {
			e.emit_pointer_step(step, depth)!
			continue
		}
		if e.wide_value(step.left) || e.wide_value(step.right) {
			e.emit_wide_step(step, depth)!
			continue
		}
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
		// A step at the width of a word widens an operand narrower than one
		// before the operation reads it, because the load that produced it left
		// four bytes with the rest of the register cleared. The right operand of
		// a shift is a count and not a value of the step's type, so it is left
		// as it is: the machine reads its low byte.
		wide := e.step_is_wide(step)
		if wide {
			e.extend_operand_to_word(step.left, step.line, step.col)!
		}
		e.store_accumulator(slot, step.line, step.col)!
		e.emit_expr_at(step.right, depth + 1)!
		if wide && step.op !in ['<<', '>>'] {
			e.extend_operand_to_word(step.right, step.line, step.col)!
		}
		e.move_operand_to_scratch(step, wide)!
		e.load_accumulator(slot, step.line, step.col)!
		e.apply_binary(step, wide)!
	}
}

// extend_operand_to_word widens an operand narrower than a word into the whole
// register, which is what a step at the width of a word needs: a value read at
// four bytes arrives with the bits above it cleared, so an int operand of a 64-bit
// step would be its unsigned reading rather than its value. The extension is the
// operand's own signedness and not the step's, because what is being converted is
// the value: `-1 + 0L` is -1, and 0xffffffff + 0UL is 4294967295. Measured on gcc
// 16.2.1, which widens an int operand of a long addition with cltq and an unsigned
// int with a 32-bit move.
fn (mut e Emitter) extend_operand_to_word(operand ast.Expr, line int, col int) !void {
	if e.floating_of(operand) || e.is_a_pointer(operand) {
		return
	}
	if (e.converted_width(operand.typ) or { 8 }) == 8 {
		return
	}
	register := e.accumulator(line, col)!
	if operand.typ.kind.is_unsigned() {
		e.append(e.target.move_register32(register, register)!)
	} else {
		e.append(e.target.sign_extend_word(register, register)!)
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

// move_operand_to_scratch puts the value just computed into the scratch register,
// at the width that value has: a comparison of two addresses moves a whole word,
// because the four-byte move beside it would keep the low half of the address and
// zero the rest of the register, and the two addresses would then be compared as
// halves.
fn (mut e Emitter) move_operand_to_scratch(step ast.Binary, wide bool) !void {
	if e.comparison_of_an_address(step) {
		result := e.accumulator(step.line, step.col)!
		other := e.scratch(step.line, step.col)!
		e.append(e.target.move_register64(other, result)!)
		return
	}
	if wide {
		// A step at the width of a word moves the whole register: the four-byte
		// move would keep the low half of the right operand and clear the rest,
		// so a right-hand value whose top bit is set would arrive zero-extended.
		result := e.accumulator(step.line, step.col)!
		other := e.scratch(step.line, step.col)!
		e.append(e.target.move_register64(other, result)!)
		return
	}
	e.move_to_scratch(step.line, step.col)!
}

// comparison_of_an_address says whether this step compares an address with
// something the language lets it be compared with, which is another address or
// the constant zero: 6.3.2.3 makes the constant zero stand for a null pointer, and
// 6.5.9 defines the comparison of two pointers. Measured, gcc 16.2.1 and tcc
// 0.9.28rc both compile `p == 0` in silence and both warn `comparison between
// pointer and integer` for `p == x` with an int x, which is the line this draws:
// an int that is not the constant zero is refused rather than compared at the
// width of its half of the address.
fn (e Emitter) comparison_of_an_address(binary ast.Binary) bool {
	if binary.op !in ['==', '!=', '<', '>', '<=', '>='] {
		return false
	}
	if e.floating_of(binary.left) || e.floating_of(binary.right) {
		return false
	}
	// Two 64-bit integers are eight bytes each and are not addresses: the width
	// is what this function used to tell an address by, because a pointer was the
	// only eight-byte value that reached it.
	if e.eight_byte_integer(binary.left.typ) || e.eight_byte_integer(binary.right.typ) {
		return false
	}
	left := e.width_of(binary.left) or { return false }
	right := e.width_of(binary.right) or { return false }
	if left != e.target.word_size && right != e.target.word_size {
		return false
	}
	// Whichever side is the address, the other one is either an address too or
	// the constant zero.
	if left != e.target.word_size {
		value := e.constant(binary.left) or { return false }
		return value == 0
	}
	if right != e.target.word_size {
		value := e.constant(binary.right) or { return false }
		return value == 0
	}
	return true
}

// check_int_operands reports an operand that is not an int. The operators
// emitted here compute with four-byte values; a pointer on either side is a
// different operation, an address plus a distance or two addresses compared, and
// computing it at the width of whatever the other side was would be a wrong
// program rather than a wrong answer. A double is the one eight-byte value that
// is not a pointer: it is computed by the other path in emit_binary, so it is
// passed over here rather than reported.
fn (mut e Emitter) check_int_operands(binary ast.Binary) !void {
	if e.comparison_of_an_address(binary) {
		// Two addresses are compared at the width of a word by the comparison
		// this back end writes, and an address beside the constant zero stands
		// for a null pointer, so neither is an int operand that was expected and
		// did not arrive.
		return
	}
	for operand in [binary.left, binary.right] {
		if e.wide_value(operand) {
			// A 128-bit operand is sixteen bytes and is compared as a pair by
			// its own path, which is where the width of the target is checked.
			continue
		}
		if e.floating_of(operand) {
			continue
		}
		if width := e.width_of(operand) {
			if width != 4 && !e.eight_byte_integer(operand.typ) {
				// Eight bytes that is not a 64-bit integer is the width of a
				// pointer and the only other width this back end has, so the
				// diagnostic can say what it is.
				e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} takes int operands, and this one is a pointer')
				return error('non-int operand')
			}
		}
	}
}

// apply_binary does the operation the tree asked for, with the left value in the
// accumulator and the right one in the scratch register, and leaves the answer in
// the accumulator.
// shift_count is the count a shift shifts by. Each form of the instruction this
// back end has writes its count into the instruction, so a count the program works
// out rather than writes is refused by its place and by name: the encodings that
// take the count from a register are a step of their own, and a shift by the wrong
// amount is not a wrong answer anyone can see. A count as wide as the type or
// wider is refused the same way, because the language makes that undefined and
// folding it to some answer would be inventing one.
fn (mut e Emitter) shift_bits(binary ast.Binary, value i64, limit int) !u8 {
	if value < 0 || value >= limit {
		e.diagnostics << problem(binary.line, binary.col, 'unsupported: a shift of a ${limit}-bit value by ${value} is not implemented, and the language calls a count that wide undefined')
		return error('shift count out of range')
	}
	return u8(value)
}

fn (mut e Emitter) apply_binary(binary ast.Binary, wide bool) !void {
	result := e.accumulator(binary.line, binary.col)!
	other := e.scratch(binary.line, binary.col)!
	// A 64-bit step computes with the machine's word instructions, which is the
	// width the values already have; a four-byte step keeps the instructions it
	// had. The signedness is the type the operands convert to, because that is the
	// type the operation is defined on: `0xffffffffu / 1` is 4294967295 and not -1,
	// and `18446744073709551615UL / 3` is 6148914691236517205.
	unsigned := binary.typ.kind.is_unsigned()
	match binary.op {
		'+' {
			if wide {
				e.append(e.target.add_reg64(result, other))
			} else {
				e.append(e.target.add(result, other)!)
			}
		}
		'-' {
			if wide {
				e.append(e.target.subtract_word(result, other)!)
			} else {
				e.append(e.target.subtract(result, other)!)
			}
		}
		'*' {
			if wide {
				e.append(e.target.multiply_word(result, other)!)
			} else {
				e.append(e.target.multiply(result, other)!)
			}
		}
		'/' {
			// A division leaves the quotient in the accumulator and what it did
			// not divide in the register above, which is where the two operators
			// read their answers from.
			e.divide_operands(other, wide, unsigned)!
		}
		'%' {
			remainder := e.target.remainder() or {
				e.diagnostics << problem(binary.line, binary.col, "${e.target.name}: the machine's table has no register for a remainder to land in")
				return error('no remainder register')
			}
			e.divide_operands(other, wide, unsigned)!
			if wide {
				e.append(e.target.move_register64(result, remainder)!)
			} else {
				e.append(e.target.move_register32(result, remainder)!)
			}
		}
		'==', '!=', '<', '>', '<=', '>=' {
			// Two addresses are compared at the width of a word: their low
			// halves being equal is not the addresses being equal. Two 64-bit
			// integers are compared at that width too, and the order an unsigned
			// one asks for is the unsigned order.
			if e.comparison_of_an_address(binary) {
				e.append(e.target.compare_word(binary.op, result, other)!)
			} else if wide {
				if e.comparison_is_unsigned(binary) {
					e.append(e.target.compare_word_unsigned(binary.op, result, other)!)
				} else {
					e.append(e.target.compare_word(binary.op, result, other)!)
				}
			} else if e.comparison_is_unsigned(binary) {
				e.append(e.target.compare_unsigned(binary.op, result, other)!)
			} else {
				e.append(e.target.compare(binary.op, result, other)!)
			}
		}
		'&' {
			e.append(e.target.and_word(result, other)!)
		}
		'|' {
			e.append(e.target.or_word(result, other)!)
		}
		'^' {
			e.append(e.target.xor_word(result, other)!)
		}
		'<<' {
			limit := if wide { 64 } else { 32 }
			if value := e.constant(binary.right) {
				e.append(e.target.shift_left_word(result, e.shift_bits(binary, value, limit)!)!)
			} else {
				// The count is one the program works out, so it is in the register
				// the machine reads a count from. The four-byte form is the one whose
				// count the machine reads as a narrow value's count is read, so a
				// count of 33 shifts by the one bit the language leaves of it.
				e.check_count_register(binary, other)!
				if wide {
					e.append(e.target.shift_left_word_register(result)!)
				} else {
					e.append(e.target.shift_left_narrow_register(result)!)
				}
			}
		}
		'>>' {
			// The shift that keeps the sign has to be told the sign, and a
			// four-byte value in the register carries its low four bytes rather
			// than a sign that reaches the top of the register: a signed one is
			// spread over the register first and an unsigned one has its top
			// cleared, and then the shift reads the sign the language means. A
			// value eight bytes wide is the whole register already and needs
			// neither instruction.
			unsigned_shift := binary.left.typ.kind.is_unsigned()
			if !wide {
				if unsigned_shift {
					e.append(e.target.move_register32(result, result)!)
				} else {
					e.append(e.target.sign_extend_word(result, result)!)
				}
			}
			limit := if wide { 64 } else { 32 }
			if value := e.constant(binary.right) {
				bits := e.shift_bits(binary, value, limit)!
				if unsigned_shift {
					e.append(e.target.shift_right_word(result, bits)!)
				} else {
					e.append(e.target.shift_right_arithmetic(result, bits)!)
				}
			} else {
				e.check_count_register(binary, other)!
				if unsigned_shift {
					if wide {
						e.append(e.target.shift_right_word_register(result)!)
					} else {
						e.append(e.target.shift_right_narrow_register(result)!)
					}
				} else {
					if wide {
						e.append(e.target.shift_right_arithmetic_word_register(result)!)
					} else {
						e.append(e.target.shift_right_arithmetic_narrow_register(result)!)
					}
				}
			}
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported binary operator ${binary.op}')
			return error('unsupported binary operator')
		}
	}
}

// divide_operands divides the pair the accumulator and the register above it form
// by the value in the scratch register, reading that pair as the type the
// operands convert to. An unsigned division clears the register above the pair
// first, so the dividend is the value itself and not a value with a sign above it;
// a signed division fills it with the sign. Measured on gcc 16.2.1, whose
// `unsigned int a / b` clears that register and divides with a divl where the
// signed division of the same shape is an idivl after a cdq.
fn (mut e Emitter) divide_operands(other backend.Register, wide bool, unsigned bool) !void {
	if wide {
		if unsigned {
			e.append(e.target.divide_word_unsigned(other)!)
		} else {
			e.append(e.target.divide_word(other)!)
		}
		return
	}
	if unsigned {
		e.append(e.target.divide_unsigned(other)!)
	} else {
		e.append(e.target.divide(other)!)
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
	e.emit_test(e.floating_of(binary.left), e.eight_byte_integer(binary.left.typ), binary.line, binary.col)!
	if is_and {
		e.branch(.branch_zero, settles, binary.line, binary.col)!
	} else {
		e.branch(.branch_nonzero, settles, binary.line, binary.col)!
	}
	// The left side did not settle it, so the right side is the answer.
	e.emit_expr_at(binary.right, depth + 1)!
	e.emit_test(e.floating_of(binary.right), e.eight_byte_integer(binary.right.typ), binary.line, binary.col)!
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

// emit_conditional writes the conditional operator as a branch rather than as a
// computation. The condition is evaluated and tested, the arm it did not select
// is jumped over, and both arms land at one label with their value in the
// register a value lives in. Only the arm the condition selects is evaluated,
// which is what `c99_side_effects == 3 ? 1 : c99_bump()` asks for: the call in
// the arm that is not taken never runs.
//
// A conditional used as a value is the shape this is written for, `int x = a ?
// b : c`, which a statement-level if cannot produce. The two arms are not two
// statements that happen to share a result: the value one of them leaves has to
// be read by whatever the conditional is an operand of, so both are converted
// to the type the conditional is worth before they meet.
fn (mut e Emitter) emit_conditional(conditional ast.Conditional, depth int) !void {
	if e.wide_value(ast.Expr(conditional)) {
		// Two arms of a 128-bit type would each have to leave a pair of
		// registers, and the branch machinery carries one value. Saying so
		// keeps the arms from being emitted at a width nothing reads.
		e.diagnostics << problem(conditional.line, conditional.col, 'unsupported: a conditional whose arms have a 128-bit type is not implemented')
		return error('128-bit conditional')
	}
	e.emit_expr_at(conditional.cond, depth + 1)!
	e.emit_test(e.floating_of(conditional.cond), e.eight_byte_integer(conditional.cond.typ), conditional.line, conditional.col)!
	else_label := e.label()
	end_label := e.label()
	e.branch(.branch_zero, else_label, conditional.line, conditional.col)!
	e.emit_conditional_arm(conditional.then_expr, conditional.typ, depth)!
	e.jump(end_label)!
	e.place(else_label)
	e.emit_conditional_arm(conditional.else_expr, conditional.typ, depth)!
	e.place(end_label)
}

// emit_conditional_arm writes one arm of a conditional and converts it to the
// type the two arms have in common, which is the type the conditional is worth
// and not the arm's own. An arm narrower than the result is widened here: a
// double result converts the arm into the floating-point register, and a result
// of eight bytes extends the arm into the whole general register with the arm's
// own signedness, which is the conversion an int to a long makes. A four-byte
// result is what the register already holds, since a char read into one arrives
// as the int the language promotes it to.
fn (mut e Emitter) emit_conditional_arm(arm ast.Expr, result types.Type, depth int) !void {
	e.emit_expr_at(arm, depth + 1)!
	if result.is_floating() {
		e.convert_to_double(arm, expr_line(arm), expr_col(arm))!
		return
	}
	if e.eight_byte_integer(result) {
		e.extend_operand_to_word(arm, expr_line(arm), expr_col(arm))!
	}
}

// move_to_scratch puts the accumulator into the scratch register, which is where
// the operation that is about to be applied expects the right-hand value.
fn (mut e Emitter) move_to_scratch(line int, col int) !void {
	result := e.accumulator(line, col)!
	other := e.scratch(line, col)!
	e.append(e.target.move_register32(other, result)!)
}

// converted_width is the width of a value held under a type a conversion named:
// four bytes for an int, and the same four for the char such a value is narrowed
// to, because a char in a register is the int the load widened it to. A double is
// eight bytes in the floating-point file and a pointer is the machine's word, and
// a type the back end has no register for answers none.
fn (e Emitter) converted_width(t types.Type) ?int {
	return match t.kind {
		.int_, .char_, .signed_char, .unsigned_int { 4 }
		.long, .unsigned_long, .long_long, .unsigned_long_long { 8 }
		.double { 8 }
		.pointer, .array { e.target.word_size }
		else { none }
	}
}

// width_of is the width of the value an expression has, four bytes for an int
// and the machine's word for a pointer. It is what keeps an int and a pointer
// apart where the machine would otherwise take one for the other, and none is
// the honest answer for an expression this back end cannot size.
fn (e Emitter) width_of(expr ast.Expr) ?int {
	return match expr {
		ast.IntLit {
			// An integer constant is as wide as the type the model gave it: 42
			// is an int, and a constant past what an int holds is a long now
			// that the 64-bit widths are carried. A constant the model gave no
			// type is one the parser refused, and the four bytes are the answer
			// that keeps a refusal from being emitted at a second width.
			e.storage_width(expr.typ) or { 4 }
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
			// A call's value has the width the language returns it with, which
			// is the type its declaration wrote: a double is eight bytes in the
			// floating-point file, a long is eight in the general one, and
			// anything else this back end emits is four.
			e.type_width(e.returns[expr.name]) or { 4 }
		}
		ast.Index {
			// An element is the width of the element's type, with a char
			// promoted to the int the load widens it to. An element that is
			// itself an array is worth the address of its first element.
			if expr.typ.is_array() {
				return e.target.word_size
			}
			width := e.storage_width(expr.typ) or { return none }
			if width == 1 {
				4
			} else {
				width
			}
		}
		ast.Unary {
			if expr.op == '!' {
				4
			} else if expr.op == '&' {
				// The address of a value is a pointer, whatever the width of the
				// value that lives there.
				e.target.word_size
			} else if expr.op == '*' {
				// A read through an address has the width of the class the value
				// at it belongs to: a char arrives as the int it is promoted to,
				// an int as itself, and a pointer as the machine's word.
				e.converted_width(expr.typ)
			} else {
				e.width_of(expr.expr) or { return none }
			}
		}
		ast.Cast {
			// The width of a converted value is the class of the type it was
			// converted to and not the width of its storage: a char in a register
			// is the int the language promotes it to, and a pointer is the
			// machine's word whatever it points at.
			e.converted_width(expr.typ)
		}
		ast.Binary {
			if expr.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
				4
			} else if e.is_pointer_step(expr) {
				// An address moved by an index is still an address, and an
				// address is the machine's word whatever it points at.
				e.target.word_size
			} else if e.floating_of(expr) {
				// An arithmetic step with a double on either side is a double,
				// whichever class the other operand was: the two widths are not
				// equal in the tree, and the value the step produces is one
				// double either way.
				8
			} else if e.step_is_wide(expr) {
				// A step with a 64-bit integer on either side is a value of
				// eight bytes. The two operands need not be the same width: the
				// usual arithmetic conversions make the step's type the wider
				// of the two, the narrower operand is widened where the step is
				// emitted, and the answer is the wider width.
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
		ast.IncDec {
			// The value is the one the operand holds, so it is sized the way
			// the name is: a char is the int the load widens it to, which is
			// the promotion the operator's value gets in an expression.
			e.width_of(ast.Expr(ast.Ident{
				name: expr.name
			})) or { return none }
		}
		ast.Conditional {
			// Both arms are converted to the type the conditional is worth
			// before they meet, so the width is that type's and not the width
			// of whichever arm the tree happens to hold first.
			e.converted_width(expr.typ)
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
	// A call to a function that hands an object of more than two eightbytes back is
	// given the address of this frame's storage for it in the first general register,
	// so the arguments written in the call start one register later.
	mut hidden := false
	if class := e.return_classes[call.name] {
		if class.count > 2 {
			hidden = true
		}
	}
	mut integers := if hidden { 1 } else { 0 }
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
				// An object of more than two eightbytes is passed in memory: the
				// convention puts no register on it at all, and the caller's copy
				// of it goes on the stack in the order its own words are in.
				places << ArgPlace{
					stack:    true
					position: stacked
					object:   true
					words:    c.count
				}
				stacked += c.count
				continue
			}
			if c.count == 2 {
				// Two eightbytes: each takes a register of its own class, and
				// the object goes on the stack whole when either one has none
				// left, which is the answer pair_places gives both sides.
				placed := abi.pair_places(e.target, c.first_floating, c.second_floating,
					integers, doubles)
				if placed.registers {
					places << ArgPlace{
						floating:        c.first_floating
						position:        placed.first
						object:          true
						words:           2
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
					object:   true
					words:    2
				}
				stacked += 2
				continue
			}
		}
		if e.wide_argument(call, i, arg) {
			// A pair of words takes two consecutive argument registers of the
			// general file at once rather than one after the other, so both of
			// them have to be there. A pair with fewer than two left is the case
			// the convention passes in memory, and this back end does not do
			// that: the refusal names the argument and its place in the file.
			if e.pair_argument_registers(integers) == none {
				e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${i + 1} of the call to ${call.name} is a 128-bit value, and the pair it is passed in takes two argument registers at once, which this machine has not got at position ${integers}: the convention passes such a pair in memory, which this back end does not do')
				return error('128-bit argument in memory')
			}
			places << ArgPlace{
				wide:     true
				position: integers
			}
			integers += 2
			continue
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
				words:    1
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
			words:    1
		}
		stacked++
	}
	// The widths the callee's parameters were declared with, read once for the
	// call: every argument asks the same table, and a lookup per argument is a
	// string-keyed map probe in the middle of the emitter's hottest loop.
	widths := e.signatures[call.name] or { []int{} }
	for i, arg in call.args {
		place := places[i]
		line := expr_line(arg)
		col := expr_col(arg)
		if place.object {
			// An object is not read into a slot at all: its own bytes are read
			// after the stack this call takes has been made, either into the
			// registers it goes in or onto the stack itself.
			continue
		}
		if place.wide {
			// A pair is finished into a slot of its own, which is what keeps an
			// argument that calls another function from landing on this one. A
			// value of the type is already the pair; a narrower one is widened
			// into both words, the way a return of a narrower expression from
			// such a function is.
			pair := e.wide_pair_slot(mut e.wide_arguments, depth + i)
			e.emit_value(arg, depth + i + 1)!
			if e.wide_value(arg) {
				e.store_pair(pair, line, col)!
			} else {
				e.widen_into_pair(pair, arg.typ.kind.is_unsigned(), e.narrow_width(arg.typ), line,
					col)!
			}
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
		if e.parameter_wants_a_word(widths, i, arg) {
			// The parameter is a 64-bit integer and the argument is narrower, so
			// the value is widened into the whole register before it is parked:
			// the argument register is loaded at eight bytes, so a negative int
			// left with its upper half cleared would arrive as its unsigned
			// reading. A parameter narrower than the argument needs nothing,
			// because the load reads only the bytes of the parameter.
			e.extend_operand_to_word(arg, line, col)!
		}
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
			if place.object {
				// An object goes on the stack in one piece, its words pushed from
				// the last one to the first: the stack grows down, so the word
				// pushed last is the one at the lowest address, which is the
				// object's first word. The address of the object is taken again
				// for each word, which keeps the register the word travels in
				// free of it, and the object's last word is only as wide as the
				// object has left, so nothing past its end is read.
				class := e.aggregate_argument(call, i) or {
					e.diagnostics << problem(call.line, call.col, 'internal: an object handed over on the stack has no class in the signature of ${call.name}')
					return error('no class')
				}
				mut k := place.words - 1
				for k >= 0 {
					offset := k * width
					read := if offset + width > class.bytes {
						class.bytes - offset
					} else {
						width
					}
					e.address_of_object(arg, depth + i + 1)!
					base := e.accumulator(line, col)!
					if offset > 0 {
						e.append(e.target.add_immediate(base, offset))
					}
					value := e.scratch(line, col)!
					e.append(e.target.load_indirect(base, value, read)!)
					e.append(e.target.push_register(value))
					e.stack_pushed += width
					k--
				}
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
				e.passed_width(call, widths, i, arg, false)!
			}
			register := e.accumulator(line, col)!
			e.load_argument(slot, register, pushed_width, line, col)!
			e.append(e.target.push_register(register))
			e.stack_pushed += width
		}
	}
	if hidden {
		// The address the result goes to: an ordinary argument register load is what
		// this is, and no argument written in the call takes the first one.
		register := e.target.arg_reg(0) or {
			e.diagnostics << problem(call.line, call.col, 'internal: ${e.target.name} has no first general register for the address a returned object goes to')
			return error('no first argument register')
		}
		base := e.frame_pointer(call.line, call.col)!
		e.append(e.target.address_of_slot(base, e.hidden.offset, register))
	}
	for i, arg in call.args {
		place := places[i]
		line := expr_line(arg)
		col := expr_col(arg)
		if place.object && !place.stack {
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
		if place.wide {
			// The two words into the two registers the pair starts at, the low
			// one first. The placement above has already asked whether both are
			// there, so neither of these can fail; falling short here would be
			// this emitter disagreeing with itself.
			pair := e.wide_pair_slot(mut e.wide_arguments, depth + i)
			base := e.frame_pointer(line, col)!
			registers := e.pair_argument_registers(place.position) or {
				e.diagnostics << problem(call.line, call.col, 'internal: ${e.target.name} has not got the two argument registers a 128-bit argument at position ${place.position} was placed in')
				return error('no argument register')
			}
			word := e.target.word_size
			e.append(e.target.load_slot(base, pair.offset, registers[0], word)!)
			e.append(e.target.load_slot(base, pair.offset + word, registers[1], word)!)
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
		width := e.passed_width(call, widths, i, arg, place.floating)!
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
	// A program reaches a library function through the slot the loader fills in,
	// because the function's address is not known until the loader has run. An
	// object has no slots and no loader: it leaves the call for the linker to
	// route, which is what a call to a symbol means in a relocatable file, and
	// what lets the linker bring in a stub for a function in another object.
	if e.compile_only {
		e.reference(e.target.call_near(0), .call_import, call.name, '')
	} else {
		e.reference(e.target.call_slot(0), .call_import, call.name, '')
	}
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
	// object says the argument is an object of an aggregate type rather than a
	// value, which is read from its own bytes. When the object is in registers
	// the second eightbyte of it travels in the register second_floating and
	// second_position name; when it is on the stack it is words eight-byte words
	// of it, which is one for a value, two for an object of two eightbytes and one
	// per eightbyte for an object the convention passes in memory.
	object          bool
	words           int
	second_floating bool
	second_position int
	// wide says the argument is a 128-bit value, which is two words rather than
	// one and takes two consecutive registers of the general file at once. Its
	// pair waits in a slot of its own until the registers are loaded, so nothing
	// of it is read from the slot a value argument waits in.
	wide bool
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

// copy_stack_object copies an object that was passed in memory into the parameter's
// storage. What is on the stack is the object's own bytes, so an eightbyte of either
// class arrives the same way, and the bytes move as many at a time as the machine
// moves in one instruction: eight, then four, then two, then one, which is what an
// object whose size is not a multiple of eight needs.
fn (mut e Emitter) copy_stack_object(object Slot, at int, line int, col int) !void {
	mut done := 0
	for done < object.width {
		remaining := object.width - done
		chunk := if remaining >= 8 {
			8
		} else if remaining >= 4 {
			4
		} else if remaining >= 2 {
			2
		} else {
			1
		}
		register := e.accumulator(line, col)!
		base := e.frame_pointer(line, col)!
		e.append(e.target.load_slot(base, at + done, register, chunk)!)
		e.append(e.target.store_slot(base, i32(object.offset + done), register, chunk)!)
		done += chunk
	}
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

// pair_argument_registers are the two consecutive general registers that carry a
// pair of words at argument position `position`, and none when this machine has
// not got two of them there. A pair takes both registers at once rather than one
// after the other, so a position with one register left is the case the
// convention passes in memory and this back end does not do. One function
// answers it for both sides of a call, because a caller that reached a different
// answer from the callee would hand over words the callee reads from somewhere
// else.
fn (e Emitter) pair_argument_registers(position int) ?[]backend.Register {
	low := e.target.arg_reg(position) or { return none }
	high := e.target.arg_reg(position + 1) or { return none }
	return [low, high]
}

// wide_argument says whether an argument is handed over as a pair of words. A
// function this file defines says so itself, parameter by parameter; a library
// function has no prototype here, so an argument of one of the 128-bit types is
// the answer, which is the same fallback argument_is_double makes. The width of
// the argument is not the question: a pair is sixteen bytes as an object and is
// handed over as two words, and a parameter of an int with a 128-bit argument
// written for it is a call the type model refuses before this sees it.
fn (e Emitter) wide_argument(call ast.Call, position int, arg ast.Expr) bool {
	if wides := e.wide_params[call.name] {
		if position < wides.len {
			return wides[position]
		}
	}
	return e.wide_value(arg)
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
// as an address the program can no longer follow. A parameter of a 64-bit integer
// given a narrower integer is the same kind of exception: the value is widened
// where it is parked, and one narrower than the argument takes the low bytes of it,
// which is the value taken modulo the parameter's width.
fn (mut e Emitter) passed_width(call ast.Call, widths []int, position int, arg ast.Expr, floating bool) !int {
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
		if position < widths.len && widths[position] == e.target.word_size {
			e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${position + 1} of the call to ${call.name} is a double and the parameter holds an address, and there is no conversion between them')
			return error('double into a pointer')
		}
		return 4
	}
	if position < widths.len {
		expected := widths[position]
		if actual != none && actual != expected {
			if e.constant(arg) == none && !e.widening_or_narrowing_integer(actual, expected, arg) {
				e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: argument ${position + 1} of the call to ${call.name} is a value of ${actual} bytes and the parameter is ${expected}')
				return error('argument width')
			}
		}
		return expected
	}
	return actual or {
		e.diagnostics << problem(expr_line(arg), expr_col(arg), 'unsupported: the width of argument ${position + 1} of the call to ${call.name} is one this back end cannot size')
		return error('unknown argument width')
	}
}

// parameter_wants_a_word says whether the argument at a given position is handed
// to a parameter eight bytes wide while the value itself is narrower, which is the
// conversion the call makes and not the value's own width. The widths are the
// callee's, read once by the caller rather than looked up again per argument.
fn (e Emitter) parameter_wants_a_word(widths []int, position int, arg ast.Expr) bool {
	if position >= widths.len || widths[position] != 8 {
		return false
	}
	return (e.converted_width(arg.typ) or { 8 }) == 4
}

// widening_or_narrowing_integer says whether the two widths are a conversion
// between two integer values rather than a mismatch: a four-byte value handed to an
// eight-byte parameter is widened where it is parked, and an eight-byte value
// handed to a four-byte parameter is read as its low bytes, which is the value
// taken modulo the parameter's width. A pointer on either side is not either of
// those, because the bits of an address are not an integer's value.
fn (e Emitter) widening_or_narrowing_integer(actual int, expected int, arg ast.Expr) bool {
	if e.floating_of(arg) || e.is_a_pointer(arg) {
		return false
	}
	return (actual == 4 && expected == 8) || (actual == 8 && expected == 4)
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
fn (e Emitter) global_shape(name string) ?image.GlobalSlot {
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
				return image.GlobalSlot{
					offset: 0
					width:  global.bytes
					count:  global.count
					object: true
				}
			}
			if e.writes_a_128(global.typ) {
				// An object of a 128-bit type at the top level is sixteen bytes of
				// storage and a value type rather than an aggregate: the width is
				// what an element of an array of them scales by, and the count is
				// how many there are. The value question is the one a local of the
				// type has, and it is refused where a name is read as a value
				// rather than here, because the storage is real and the layout and
				// an element address both need this shape.
				return image.GlobalSlot{
					offset: 0
					width:  wide_bytes
					count:  global.count
				}
			}
			element := e.type_width(global.typ) or { return none }
			return image.GlobalSlot{
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

// put_integer writes a constant into a blob as the machine holds a value of the
// given width: little-endian, two's complement. A type wider than the eight bytes
// a constant is held in takes its remaining bytes from the sign, because the
// shift that would reach them shifts by the width of the value itself: V leaves
// that undefined and it answered zero here, so a top-level `__int128 g = -100`
// came out with a zero second word and every program that read the word got the
// wrong answer to a constant the language spells out. The low bytes stay the
// value's own.
fn put_integer(mut blob []u8, at int, value i64, width int) {
	low := u64(value)
	fill := if value < 0 { u8(0xff) } else { u8(0) }
	for i in 0 .. width {
		blob[at + i] = if i < 8 { u8((low >> (8 * i)) & 0xff) } else { fill }
	}
}

// put_double writes a double into a blob as the eight bytes of its value, which
// is the same little-endian image the instruction that reads one expects.
fn put_double(mut blob []u8, at int, value f64, width int) {
	bits := math.f64_bits(value)
	for i in 0 .. width {
		blob[at + i] = u8((bits >> (8 * i)) & 0xff)
	}
}

// global_of is the storage a top-level object has in the image, laid out the
// first time the name is used: the bytes of its constant initializer, or zeros,
// at the width of one element, with every object starting at a word boundary so
// that a word-sized value is never halfway into the one before it. The address of
// a global is not known while the code is emitted - the image is laid out
// afterwards - so every use of it is a reference the layout fills in, which is
// the same mechanism a string literal is addressed by.
fn (mut e Emitter) global_of(name string) ?image.GlobalSlot {
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
		slot := image.GlobalSlot{
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
		put_double(mut e.program.globals_blob, offset, value, element)
	}
	if value := object.init {
		put_integer(mut e.program.globals_blob, offset, value, element)
	}
	// A brace list writes one element at a time, at the width of one element, in
	// the order the list wrote them. The elements the list did not reach stay
	// zero, which is what the storage started as and what C says the rest of a
	// partly initialized array holds.
	for index, value in object.init_floats {
		if index >= count {
			break
		}
		put_double(mut e.program.globals_blob, offset + index * element, value, element)
	}
	for index, value in object.inits {
		if index >= count {
			break
		}
		put_integer(mut e.program.globals_blob, offset + index * element, value, element)
	}
	slot := image.GlobalSlot{
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
fn (mut e Emitter) assign_global(stmt ast.Stmt, object image.GlobalSlot, expr ast.Expr) !void {
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference(e.target.address_of(register, 0), .global_address, stmt.target, e.target.name_of(register))
	address := e.value_slot(0)
	e.store_accumulator(address, stmt.line, stmt.col)!
	if object.width == wide_bytes {
		// A top-level object of a 128-bit type takes the two words a local of it
		// takes, through the address the image holds: the same widening store, and
		// the same copy when the value is another object of the type.
		return e.store_wide_at(address, expr, stmt.line, stmt.col)
	}
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
fn (mut e Emitter) convert_for_global(expr ast.Expr, object image.GlobalSlot, line int, col int) !void {
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
fn (mut e Emitter) reference(bytes []u8, kind image.FixupKind, name string, register string) {
	start := e.program.text.len
	e.program.text << bytes
	e.program.fixups << image.Fixup{
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
		ast.Cast { expr.line }
		ast.Binary { expr.line }
		ast.Call { expr.line }
		ast.Index { expr.line }
		ast.Field { expr.line }
		ast.IncDec { expr.line }
		ast.Conditional { expr.line }
	}
}

fn expr_col(expr ast.Expr) int {
	return match expr {
		ast.IntLit { expr.col }
		ast.FloatLit { expr.col }
		ast.StrLit { expr.col }
		ast.Ident { expr.col }
		ast.Unary { expr.col }
		ast.Cast { expr.col }
		ast.Binary { expr.col }
		ast.Call { expr.col }
		ast.Index { expr.col }
		ast.Field { expr.col }
		ast.IncDec { expr.col }
		ast.Conditional { expr.col }
	}
}

fn problem(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
	}
}
