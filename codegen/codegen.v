module codegen

import ast
import backend
import backend.abi
import backend.os.elf
import backend.os.linux
import diagnostics
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
	// link asks for one piece of a link rather than a program: the same code and
	// data with no process stub and no entry requirement, because which unit
	// defines the entry and which one carries the stub is the link's decision
	// and not this unit's. The result carries the image.Program and no
	// container bytes, and the linker merges the programs and writes one
	// container over the merged result. A name this unit only declares is left
	// as an import for the linker to bind, which is why the unresolved-import
	// check at the end of the walk is left out here: a sibling unit may be the
	// definition the check would have looked for.
	link bool
	// start_only asks for the process stub and nothing else: the instructions
	// the kernel lands on, which call the entry function and leave through the
	// library's exit. It walks no declaration of the unit and it does not
	// require the unit to define the entry, because the stub only references
	// the name. The reference stays local, so the linker resolves it against
	// the labels of whichever unit defines the entry, and a link with no such
	// unit gets an undefined reference. Like link, the result carries the
	// image.Program and no container bytes.
	start_only bool
	// pic is -fPIC: a relocatable object reaches every top-level object another
	// object may define through the global offset table, so that a shared link
	// has no direct reference to a symbol that can be interposed. It only means
	// anything for a relocatable object: the program this compiler writes has
	// every address settled here, so its addressing is unchanged whether the
	// flag is given or not.
	pic bool
	// link_kind is which kind of file the wrapper writes for this unit: a
	// program, a static program, or a shared object. It is the command line's
	// -shared and -static decision, and it is an option here because a single
	// input is wrapped at the end of this walk rather than by the linker, which
	// wraps the merged program instead. An object this compiler writes as an
	// input to a link is not one of these, and neither is a link unit: both
	// leave the container to somebody else.
	link_kind linux.LinkKind = .program
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
	bytes []u8
	// program is the emitted unit the container was written over, and it is the
	// emitter's own Program rather than a copy of the bytes. A slice or a map
	// field is a reference, so handing the struct out costs nothing, and a
	// caller that merges several units of a link reads the programs here. The
	// bytes stay what they always were: the container, and empty for a link
	// unit, which leaves the container to the linker.
	program     image.Program
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
	// single is set for a slot holding a float: the same register file as a
	// double and four bytes rather than eight, which is why it is a second flag
	// and not a third value of the one above. Every load and store of such a
	// slot has to be four bytes wide, and the value has to be rounded to that
	// width before it is written.
	single bool
	// unsigned is set for a slot whose declared type is an unsigned integer one.
	// The width does not answer it and neither does the spelling at the point a
	// value is stored, so it travels with the slot: a double converted into an
	// unsigned four-byte slot has to be converted at a width every value of that
	// type fits in, and the same conversion into a signed one saturates.
	unsigned bool
	// boolean is set for a slot holding a `_Bool`. Every store into one converts
	// the value to 0 or 1, which is a step neither the width nor the signedness
	// of the slot asks for, so it travels with the slot the way the signedness
	// does.
	boolean bool
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
	// long_double is set for a slot holding a long double, which is the same
	// sixteen bytes of storage for a different reason: the extended format has
	// no register this back end computes in, so the value lives in memory and
	// the name of such a slot is the address of it.
	long_double bool
	// complex is set for a slot holding an object of a complex type: two
	// components of the same real type, stored one after the other, which is the
	// layout the model measured and the one gcc hands over. Such a slot is an
	// object and not a value, so the bytes are what travel and what are copied;
	// the width says which complex type it is, sixteen bytes for a
	// `double _Complex` and eight for a `float _Complex`. It is a flag of its
	// own because a struct can be eight bytes and a pair of ints sixteen, and a
	// conversion to or from a complex type is not a conversion a struct has.
	complex bool
	// vla is set for a slot holding a variable-length array. Such a slot does not
	// hold the array: its storage was claimed on the stack when the declaration
	// ran, and the slot holds two words, the address of the first element and how
	// many bytes the array is. count is -1 for one, so this is the flag that says
	// the name is an array at all; width is the size of one element.
	vla bool
	// vla_base and vla_size are the frame slots those two words live in. They are
	// offsets rather than Slots because a Slot cannot contain one of itself, and
	// they are reserved for the declaration and never given out again.
	vla_base int
	vla_size int
	// captured is set for an object of an enclosing function that a nested
	// function reaches through the static chain: the offset is still the
	// object's offset in the frame it was declared in, but the frame is the
	// enclosing one, which is where the chain points rather than where rbp
	// does. A captured slot is addressed from the chain pointer and a local one
	// from rbp, which is the one thing every place that turns a slot into an
	// address has to ask, so it asks this.
	captured bool
	// capture_owner is the symbol of the function whose frame a captured slot
	// lives in. Only the frame of the function a nested function is written in
	// is a register away: an object of a function further out would take a walk
	// of the chain, which is not written, so a use of such an object is refused
	// by name where it is used.
	capture_owner string
}

// is_array says the slot holds an array, whether its size was written or is
// computed at run time. count alone answers for the first kind and vla for the
// second, and the two differ exactly where a bound is a value.
fn (s Slot) is_array() bool {
	return s.count > 0 || s.vla
}

// LoopLabels are the two places a loop's body can leave by: where the loop ends,
// for a break, and where it goes round again, for a continue. A switch is a
// break target of its own and not a loop, so it appears here with is_switch set:
// a break inside it leaves it, and a continue inside it belongs to the loop
// outside, which is the binding C asks for and the one a single innermost
// target gets wrong.
struct LoopLabels {
	break_to    string
	continue_to string
	// is_switch says this entry is a switch statement and not a loop, so a
	// continue in its body looks past it for the loop it belongs to.
	is_switch bool
	// scopes_at_entry is how many scopes were open where the loop began. The
	// loop's own body is the next scope, so a break or a continue leaves every
	// scope from here on, and that is what says which blocks' variable-length
	// array storage the jump has to give back before it goes.
	scopes_at_entry int
}

// CaseTarget is one case or default label of the switch being emitted: the
// constant it matches, the machine label its statement is placed at, and
// whether it is the default one. A switch's dispatch compares the controlling
// expression against every non-default value and jumps to the matching label;
// the default is where it goes when none matches. When the label wrote a range,
// `case low ... high:`, value is the low end, high the high one, and is_range
// says the dispatch tests a run rather than one value.
struct CaseTarget {
	value      i64
	high       i64
	is_range   bool
	label      string
	is_default bool
}

// SwitchState is the switch whose body is being emitted: its labels in the order
// the body writes them, and how many of them emission has reached. The parser
// wrote every case label as a statement of its own, so the body's statements are
// what names the arms, and this is what matches each of them to its target.
struct SwitchState {
mut:
	cases []CaseTarget
	next  int
}

// CaseWalk is one statement list a walk of a switch body is in the middle of:
// where it is in the list, and the list itself. It is a frame of an explicit
// stack rather than a recursion, because how deeply blocks nest is what the
// source says and not something a compiler chooses.
struct CaseWalk {
mut:
	list []ast.Stmt
	at   int
}

// Cleanup is one object a block has to run a function on when the block ends:
// the object's name and type, and the function the object's
// `__attribute__((cleanup(name)))` named. GCC 6.4.1 gives that function one
// parameter, a pointer to the object, so the call this is emitted as is the
// function with the object's address.
struct Cleanup {
	name     string
	typ      types.Type
	function string
	line     int
	col      int
}

// LabelUse is where a goto named a label: the position the diagnostic about a
// label nothing defines belongs at.
struct LabelUse {
	line int
	col  int
}

// PendingNested is a nested function waiting to be emitted, with the scopes of
// the block it was written in. The objects the enclosing function had declared
// where the definition was read are the ones the nested function may reach, and
// a copy of the scope stack is what carries them to the point the nested
// function is emitted, after the enclosing body has been emitted and its own
// scopes are gone.
struct PendingNested {
	decl   ast.FnDecl
	scopes []map[string]Slot
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
	// link says this emitter is writing one piece of a link and not a program:
	// no process stub, no entry requirement, and no container. The program it
	// builds is one input to the linker, which merges it with its siblings and
	// resolves a name this unit left as an import against a definition one of
	// them provides.
	link bool
	// start_only says this emitter writes the process stub and nothing else.
	// The stub is the one body emit_start carries, so a linker that wants it in
	// a unit of its own gets exactly the instructions a program gets.
	start_only bool
	// pic says a relocatable object reaches a non-static top-level object
	// through the global offset table rather than through a direct reference.
	pic bool
	// link_kind is which kind of file the wrapper writes, and nothing before
	// the wrapper reads it.
	link_kind linux.LinkKind
	// internal is every top-level object this unit defines with internal
	// linkage: the names the declaration wrote `static`. A reference to one is
	// direct under any addressing, because no other object can define the name
	// and there is nothing for the global offset table to protect it from.
	internal map[string]bool
	unit     ast.TranslationUnit
	// libraries are the -l names the command line gave, and library_dirs the
	// -L directories they are looked for in. Both are resolved into the names
	// the image carries before anything is emitted.
	libraries    []string
	library_dirs []string
mut:
	program     image.Program
	diagnostics []tokenize.Diagnostic
	// signatures is the width of each parameter of every function whose
	// parameter list this file declares, definition or not, so that a call
	// hands each argument over at the width the declaration expects.
	signatures map[string][]int
	// float_params says, for the same functions, which parameters are doubles.
	// The width cannot answer that on its own: a double is eight bytes and so is
	// a pointer, and the two travel through different registers.
	float_params map[string][]bool
	// single_params says, for the same functions, which of those parameters are
	// floats rather than doubles. Both travel through the floating-point file,
	// so float_params answers which file and this answers at which of the two
	// widths the value is handed over and stored.
	single_params map[string][]bool
	// unsigned_params says, for the same functions, which parameters are of an
	// unsigned integer type. It is what a double handed to such a parameter is
	// truncated against: the destination's signedness is not on the double, and
	// the parameter's type is the one place a call knows it.
	unsigned_params map[string][]bool
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
	// extended_params says, for the same functions, which parameters are the
	// extended floating type. Such a parameter is passed in memory, sixteen
	// bytes at a time, rather than in a register, so a call has to know which
	// parameters those are and the width cannot answer it: a long double is
	// sixteen bytes and is not handed over in any register.
	extended_params map[string][]bool
	// complex_long_double_params says, for the same functions, which parameters
	// are the extended complex type. Such a parameter is a thirty-two byte object
	// handed over in memory and returned on the x87 stack, so a call has to know
	// which parameters those are; neither the width nor the scalar extended
	// question answers it.
	complex_long_double_params map[string][]bool
	// complex_long_double_returns says, for the same functions, which of them
	// hand an extended complex value back. The value comes back on the x87 stack
	// rather than in a register, which no return class can describe.
	complex_long_double_returns map[string]bool
	// return_classes says, for the same functions, which of them hand an object
	// of an aggregate type back, and how many bytes of one. The value comes back
	// in the register its class names rather than converted.
	return_classes map[string]abi.Class
	// returning is the return type of the function being emitted, as it was
	// written, which is what a return statement's value is converted to.
	returning string
	// returning_complex_long_double says the function being emitted hands a
	// `long double _Complex` back. The value comes back on the x87 stack as two
	// extended components rather than in a register or an object class, which
	// neither the spelling nor the return class names, so a return statement
	// asks this instead.
	returning_complex_long_double bool
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
	// vla_saves is the stack of blocks being emitted, one entry per scope in
	// scopes and in the same order: the frame offset of the word a scope saved
	// the stack pointer in when it first declared a variable-length array, or
	// -1 for a scope that never did. A block gives its storage back when it
	// ends by restoring the stack pointer from that word, and the same word is
	// what a break, a continue or a goto leaving the block restores from.
	vla_saves []int
	// vla_label_counts is, for every named label of the function being emitted,
	// how many variable-length array scopes enclose it. A goto that leaves such
	// scopes puts the stack pointer back to the innermost one its target sits
	// in, and the count is what names that scope without the emitter having to
	// match scope identities across the two walks. It is empty for a function
	// that declares no variable-length array.
	vla_label_counts map[string]int
	// cleanups is the stack of blocks being emitted, one entry per scope in
	// scopes and in the same order: the objects declared in that block with
	// `__attribute__((cleanup(name)))`, in the order they were declared. A
	// block runs them where it ends, innermost first and within one block in
	// reverse declaration order, and every way control leaves a block runs
	// them too: a return, a break, a continue or a goto.
	cleanups [][]Cleanup
	// cleanup_label_counts is, for every named label of the function being
	// emitted, how many of those cleanup blocks enclose it. A goto runs the
	// cleanups of the blocks between itself and its target, and the count is
	// what names them without the emitter having to match scope identities
	// across the two walks. It is empty for a function that declares none.
	cleanup_label_counts map[string]int
	// chain is the frame slot a nested function's static chain lives in: the
	// frame pointer of the function it is written in, handed to it in the chain
	// register at every call and kept in the slot for the body to read. It is
	// none for a function defined at the top level, which has no enclosing
	// frame to reach.
	chain ?Slot
	// function_symbol is the symbol of the function being emitted and
	// enclosing_symbol that of the function it is written in, both as the
	// reader mangled them and both empty at the top level. A nested function
	// reaches the frame of the function it is written in through one chain
	// link, so how the two symbols compare is what says whether a captured
	// object is that one link away.
	function_symbol  string
	enclosing_symbol string
	// nested_functions maps the symbol of a nested function to the symbol of
	// the function it is written in. A call to a nested function has to put
	// that function's frame pointer into the chain register, and this is where
	// the call reads which frame that is.
	nested_functions map[string]string
	// pending_nested is the nested functions of the function being emitted,
	// each with the scopes of the block it was written in. They are held back
	// so the enclosing body is emitted first: a nested function is a function
	// of its own, emitted after the function that writes it, and nothing in the
	// enclosing body depends on it being anywhere in particular.
	pending_nested []PendingNested
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
	// variadic says the function being emitted is one whose parameter list ends
	// in an ellipsis. named_gp and named_fp are how many of its named parameters
	// arrived in each argument register file, and named_stacked how many words of
	// them went on the stack: together they are where a walk through the unnamed
	// arguments starts, in the registers and in memory.
	variadic      bool
	named_gp      int
	named_fp      int
	named_stacked int
	// save_area is where the prologue of a variadic function wrote the argument
	// registers, and none for a function that wrote none. A walk through the
	// arguments reads the registers out of it.
	save_area ?Slot
	// argument_lists are the objects of this function whose declared type is an
	// argument list: the ones a `va_list` declaration made, and the parameters a
	// function was handed one in. The four operations over a list are applied to
	// one of these and refused elsewhere, because an object that is not a list
	// holds something that is not a tag, and a walk through it reads that
	// something as though it were.
	argument_lists []string
	// stack_pushed is how many bytes the call being emitted has pushed for the
	// arguments its registers ran out for, and zero when it pushed none. The
	// caller gives those bytes back once the call returns, so the frame is where
	// it was and the slots keep their offsets.
	stack_pushed int
	// values is the scratch area, one slot per level of expression nesting,
	// where a half-finished value waits while the other half is computed.
	values []Slot
	// callees is where a call through an expression keeps the address it calls
	// while the arguments are evaluated and loaded, one slot per level of
	// nesting. It is a list of its own rather than a level of values because an
	// argument is emitted into the value slot of its own depth, and the last
	// argument's depth is the one the address would otherwise wait in: the
	// address has to outlive every argument, and a value slot at that depth
	// does not.
	callees []Slot
	// slot_base is where that area starts for the expression being emitted. It
	// is zero for an ordinary expression, so a depth indexes the list from its
	// beginning. A statement expression raises it for the length of its body so
	// the statements inside wait above every slot the expression around the
	// construct is using: without that, `a + ({ b = 1; b; })` would let the body
	// write over the slot `a` is waiting in, which is a wrong value rather than
	// a refused one.
	slot_base int
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
	// A switch is on this stack too, because a break inside one leaves it: the
	// entry says which it is.
	loops []LoopLabels
	// switches is the switch statements being emitted, innermost last. A case
	// label is placed as its statement comes out of the walk, and the entry
	// says which target of the switch that is.
	switches []SwitchState
	// goto_labels is where each named label of the function being emitted is,
	// by the name the source wrote. A label a goto reaches before it is placed
	// is created here by the goto, which is what makes a forward jump a jump to
	// a label that is not in the text yet.
	goto_labels map[string]string
	// goto_placed says which of those labels have been placed. A name that is
	// used and never placed is a goto to a label nothing defines, which is
	// reported once the whole body has been emitted.
	goto_placed map[string]bool
	// goto_used is where each name was used, for that diagnostic.
	goto_used map[string]LabelUse
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

// vla_no_save is the entry a scope that has not claimed variable-length array
// storage carries in the emitter's save stack. A real entry is a frame offset,
// which is negative, so -1 is a value no offset can be and the two are told
// apart by comparing against this rather than by the sign of the offset.
const vla_no_save = -1

// max_emit_depth is the nesting an expression may have before it is reported.
// Parentheses are the only way to get deeper in the grammar, and a tree past
// this is a tree that would take the stack out rather than one a program writes.
const max_emit_depth = 200

// max_emit_chain is how many terms one operator chain may carry before it is
// reported. A chain is not nesting: `a + b + c ...` is one node deep in the
// grammar however many terms it has, the parser reads it left to right, and the
// emitter walks its left spine with a loop, so max_emit_depth does not see it and
// the stack does not either. What is left is the work: the emitter asks the width
// of everything below a term once per term, so a chain of n terms costs about
// n*n/2 classifier steps, and a chain is counted rather than walked past this.
// The count is chosen above the two thousand terms the benchmark's workload and
// the long-chain tests use, so nothing the tree compiles today is refused.
const max_emit_chain = 4096

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
//
// Three modes ask for less than a program. compile_only leaves the addresses to
// a linker and wraps the unit as a relocatable object. link asks for one piece
// of a link: no process stub, no entry requirement, and no container, so the
// linker merges the programs and writes one container over the merged result.
// start_only asks for the process stub alone. The result carries the emitted
// unit in `program` for every mode, and `bytes` holds the container a program
// or an object gets, which a link unit leaves empty for the linker.
pub fn emit(unit ast.TranslationUnit, opts Options) Result {
	target := resolve_target(opts.target) or {
		return Result{
			diagnostics: [problem(1, 1, err.msg())]
		}
	}
	// A program has to start somewhere and a kernel starts it at one place, so a
	// program without the entry function is one this compiler cannot produce. An
	// object is not a program: it starts nowhere, and which function a link makes
	// the entry is not decided here. Neither is a link unit: the entry is a
	// sibling unit's business, and the linker checks the merged program once. A
	// stub-only unit references the entry rather than defining it, so it is not
	// asked for one either.
	// A shared object is not asked for an entry: nothing starts it, and what it
	// hands out is a definition something else calls. The container writes an
	// entry point of zero for it, so the name is not resolved here.
	entry := if opts.entry == '' { 'main' } else { opts.entry }
	if !opts.compile_only && !opts.link && !opts.start_only && opts.link_kind != .shared
		&& entry_definition(unit, entry) == none {
		return Result{
			target:      target
			diagnostics: [problem(1, 1, 'no definition of ${entry} in this translation unit')]
		}
	}
	// The names this unit defines with internal linkage, collected before the
	// walk so that an address taken before the object is laid out still knows
	// it is a local one. Only the names a definition gave, because a name
	// `static` only declares cannot be the object of a reference.
	mut internal := map[string]bool{}
	for global in unit.globals {
		if global.static_ {
			internal[global.name] = true
		}
	}
	mut emitter := Emitter{
		target:         target
		representation: types.from_target(target).representation
		entry:          entry
		compile_only:   opts.compile_only
		link:           opts.link
		start_only:     opts.start_only
		pic:            opts.pic
		link_kind:      opts.link_kind
		internal:       internal
		unit:           unit
		libraries:      opts.libraries
		library_dirs:   opts.library_dirs
	}
	// Nothing is written from a tree the model did not type. The check runs
	// before the layout, so a tree it refuses produces no image at all. A
	// stub-only unit walks no declaration and references no value, so there is
	// nothing for the check to read and it is left out.
	if !emitter.start_only {
		emitter.refuse_unresolved() or {
			if emitter.diagnostics.len == 0 {
				emitter.diagnostics << problem(1, 1, 'internal: the tree could not be checked: ${err.msg()}')
			}
			return Result{
				target:      target
				diagnostics: emitter.diagnostics
			}
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
	// The unit opens with the process stub when the emitter wrote one: a program
	// gets it, and a stub-only unit is nothing but it. A link unit, an object and
	// a shared object get none, which is what tells the linker that the place the
	// process begins is a name the link resolved rather than this unit's stub.
	if !opts.compile_only && !opts.link && opts.link_kind != .shared {
		emitter.program.stub = true
	}
	// A diagnostic that stops the compile means the translation unit was not
	// emitted, so the image goes away with it. A warning does not: this back
	// end raises one for a construct the standard does not have and the flags
	// decide its fate, and the caller reads the same question - `report` counts
	// the errors after the policy is applied - to decide whether to write the
	// image. Dropping it here on any diagnostic would write nothing while the
	// caller saw no error, which is a program that compiles and then does not
	// exist.
	if tokenize.errors(emitter.diagnostics).len > 0 {
		return Result{
			target:      target
			diagnostics: emitter.diagnostics
		}
	}
	return Result{
		bytes:       image_bytes
		program:     emitter.program
		target:      target
		diagnostics: emitter.diagnostics
	}
}

// start_stub returns the process stub as a Program of its own: the code the
// kernel lands on, the call it makes to the entry function, and the exit it
// leaves through. It writes the same emit_start a program gets, so a linker
// that wants the stub in a unit of its own gets exactly the instructions it
// would have got at the front of a program, and there is one body rather than
// two copies that can drift apart. The reference to the entry stays local, so
// the linker resolves it against the labels of whichever unit defines the
// entry, and a link with no such unit gets an undefined reference the way a
// call to a missing function does. No declaration is walked: the unit this
// builds is empty and the stub is all there is.
pub fn start_stub(entry string, opts Options) Result {
	target := resolve_target(opts.target) or {
		return Result{
			diagnostics: [problem(1, 1, err.msg())]
		}
	}
	mut emitter := Emitter{
		target:         target
		representation: types.from_target(target).representation
		entry:          if entry == '' { 'main' } else { entry }
		start_only:     true
		link_kind:      opts.link_kind
	}
	emitter.emit_start() or {
		if emitter.diagnostics.len == 0 {
			emitter.diagnostics << problem(1, 1, 'internal: the process stub could not be produced: ${err.msg()}')
		}
		return Result{
			target:      target
			diagnostics: emitter.diagnostics
		}
	}
	// The unit is the process stub and nothing else, which is what tells the
	// linker that the place the process begins is this unit's text rather than a
	// name the link resolved.
	emitter.program.stub = true
	return Result{
		program:     emitter.program
		target:      target
		diagnostics: emitter.diagnostics
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
		if candidate.name == entry && candidate.defined {
			found = candidate
		}
	}
	return found
}

// build lays the whole program out: the entry point the kernel jumps to, then
// every function with a body, then the container that holds them.
//
// A stub-only unit stops at the entry point: the stub is the whole of what was
// asked for, so no declaration is walked, no library is resolved and no
// container is written.
fn (mut e Emitter) build() ![]u8 {
	if e.start_only {
		e.emit_start()!
		return []u8{}
	}
	// The libraries the image will name are settled before a byte is written.
	// A -l name with no file behind it is an error a link makes, and the
	// alternative is worse than an error: a program that compiles and then
	// dies at load with an undefined symbol says nothing about the flag that
	// asked for the library.
	// An object names no libraries. What a translation unit runs against is
	// decided when it is linked, so a -l on a -c command line is not this
	// stage's business, and resolving one here would fail a compile over a
	// library the object never mentions. A link unit does name its libraries,
	// because one of the units of a link carries the -l flags the whole link
	// runs against, and the merged program lists them once.
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
	// The names and the parameter classifications come first so that a call
	// binds to a prototype wherever in the file it is written. The width and the
	// class are the ones the declaration gives the parameter, and a call reads
	// them whether or not this file wrote the body: C converts an argument to the
	// visible parameter type, so a float parameter takes the argument as a float
	// at a definition and at a declaration alike, and default argument promotion
	// answers only when no prototype is in scope. A declaration with a parameter
	// this back end cannot size is left out of the table, because its own
	// emission is where that is reported.
	// A nested function is a function of its own, so its name and the classes of
	// its parameters are settled here with the top-level names, before a body is
	// emitted: a call to a nested function binds to its prototype wherever in the
	// file it is written, exactly as a call to a top-level name does. The nested
	// functions are gathered from the bodies that write them, and the function
	// that writes one emits it after its own body, so this list is for the tables
	// alone; a definition reached only here is not emitted here.
	mut declared_functions := e.unit.decls.clone()
	for decl in e.unit.decls {
		if decl.defined {
			declared_functions << collect_nested(decl.body)
		}
	}
	for decl in declared_functions {
		e.returns[decl.name] = decl.ret
		if decl.ret_type.kind == .complex_long_double {
			e.complex_long_double_returns[decl.name] = true
		}
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
		if decl.defined {
			e.program.defined[decl.name] = true
			// A weak definition is one the object's symbol table marks WEAK
			// rather than GLOBAL, which is what `__attribute__((weak))` asked
			// for. Only a definition has a binding here: a weak prototype of a
			// function this file does not define is an import, and what its
			// binding is is the linker's business.
			if decl.weak {
				e.program.weak[decl.name] = true
			}
			// A definition the file wrote `static` has internal linkage, so
			// its object symbol wears the local binding and another unit may
			// define the same name. A prototype never reaches the symbol
			// table, so only a definition is recorded here.
			if decl.static_ {
				e.program.internal[decl.name] = true
			}
			// A nested function is written inside a body, so its name is not a
			// name any other translation unit can reach: the symbol is local
			// the way a `static` definition's is, whether or not the enclosing
			// function was. The dot in the symbol keeps it from colliding with
			// any C name even so.
			if decl.nested {
				e.program.internal[decl.name] = true
			}
		}
		// A definition and a prototype are both a parameter list this back end
		// can read, so both fill the same tables. Only a body written here makes
		// the name one the image defines. A declaration with no parameters is
		// `(void)` or an old-style no-prototype list, and neither classifies an
		// argument, so it is left out and a call through it promotes instead.
		if decl.defined || decl.params.len > 0 {
			mut widths := []int{}
			mut classes := []bool{}
			mut singles := []bool{}
			mut unsigneds := []bool{}
			mut aggregates := []abi.Class{}
			mut wides := []bool{}
			mut extendeds := []bool{}
			mut complexes := []bool{}
			mut sized := true
			for param in decl.params {
				// Which parameters are 128-bit values is read here rather than
				// from the width below, because the width of such a parameter is
				// not the width it is handed over at: it travels as a pair of
				// words in two registers at once.
				wides << e.writes_a_128(param.typ)
				// A long double parameter is passed in memory rather than in a
				// register, so which parameters are one is a question the width
				// cannot answer and a call has to be told.
				extendeds << abi.travels_on_the_x87_stack(param.resolved)
				// A `long double _Complex` parameter is a thirty-two byte object
				// handed over in memory, which neither the width nor the scalar
				// extended question names.
				complexes << (param.resolved.kind == .complex_long_double)
				// A parameter that is an object of an aggregate type is handed
				// over as its bytes in one register: how many bytes it is and
				// which file the register belongs to are the two facts the call
				// needs, and both are the target's answer for the type the
				// declaration resolved to.
				class := e.class_of(param.resolved)
				if class.bytes > 0 {
					widths << class.bytes
					classes << class.first_floating
					singles << false
					unsigneds << false
					aggregates << class
					continue
				}
				aggregates << abi.Class{}
				if width := e.type_width(param.typ) {
					widths << width
					// A parameter of either floating type travels in the
					// floating-point file, so the class is true for both and the
					// width is what tells them apart.
					classes << (e.writes_a_double(param.typ) || e.writes_a_float(param.typ))
					singles << e.writes_a_float(param.typ)
					unsigneds << e.written_is_unsigned(param.typ)
				} else if e.writes_a_128(param.typ) {
					// The object is sixteen bytes; the value is a pair. The
					// width goes in the table so that the parameters beside
					// this one keep their own positions and widths.
					widths << wide_bytes
					classes << false
					singles << false
					unsigneds << false
				} else {
					sized = false
				}
			}
			e.wide_params[decl.name] = wides
			e.extended_params[decl.name] = extendeds
			e.complex_long_double_params[decl.name] = complexes
			if sized {
				e.signatures[decl.name] = widths
				e.float_params[decl.name] = classes
				e.single_params[decl.name] = singles
				e.unsigned_params[decl.name] = unsigneds
				e.aggregate_params[decl.name] = aggregates
			}
		}
	}
	// The process stub is the place the kernel lands on: it calls the entry
	// function and hands its result to the library's exit, or to the kernel's
	// exit when the link is static. An object has no such place, so it gets
	// none; a link decides what the program starts at. Nor does a link unit:
	// the link carries the stub in a unit of its own, so writing one here would
	// give the merged program two. Nor a shared object: nothing starts it and
	// its entry point is zero, so a stub there would be bytes no one reaches.
	if !e.compile_only && !e.link && e.link_kind != .shared {
		e.emit_start()!
	}
	for decl in e.unit.decls {
		if !decl.defined {
			continue
		}
		e.emit_function(decl)!
	}
	// Every object the file defines is storage the unit holds, whether or not a
	// function in the file names it. What a translation unit provides is what it
	// defines (6.9p5), and an object's storage is laid out only when global_of is
	// asked for it, so a definition a function never reached was left out of the
	// image and out of the symbol table with it. The objects a function already
	// referenced were placed as they were reached; this asks for every remaining
	// definition in the order it was written, which is what keeps the storage at
	// the same offsets and the object at the same bytes every run.
	e.place_defined_objects()
	// Every import this image made has to have something to bind to. The loader
	// resolves each name out of a library the image names, and a name none of
	// them defines is a program that cannot start. It is the question a link
	// answers by refusing an undefined reference, and this compiler knows the
	// imports because it wrote them: leaving the question to the loader is what
	// turned an unresolved symbol into a compile that succeeded and a binary
	// that died at load with nothing on the compiler's stderr. An object is not
	// a program and is left out, because a linker resolves its symbols later.
	// A link unit is left out for the same reason: a name it does not define may
	// be a sibling unit's, and the linker runs this check once over the merged
	// program, where every sibling's definitions are visible.
	//
	// A shared object is left out because the check would be wrong for it: its
	// imports are what a loader resolves when the object is mapped, so a name no
	// library on this machine defines is still a name the object can be loaded
	// with. The container refuses a name the file itself cannot leave
	// unresolved when the kind is a static program, which is where that belongs.
	if !e.compile_only && !e.link && e.link_kind != .shared {
		dirs := linux.search_dirs(e.library_dirs, e.target.library_dirs)
		// The names a program reaches out of a library are the functions it
		// calls and the objects it copies, and both have to bind: a copy is not
		// an import in the image, but it is a name the program cannot start
		// without, and the loader would refuse it with nothing on this
		// compiler's stderr. So the question is asked of both, and a name no
		// library defines is refused here by name, the way a link refuses an
		// undefined reference.
		mut requested := e.program.imports.clone()
		requested << e.program.copy_objects
		// A weak import is not a name a library has to answer, whatever brought
		// the image here: an undefined weak symbol stands for zero, which is what
		// the runtime's own startup files reach their optional hooks with.
		requested = requested.filter(it !in e.program.weak_imports)
		unresolved := linux.unresolved_imports(requested, e.libraries, dirs)
		if unresolved.len > 0 {
			for name in unresolved {
				e.diagnostics << problem(1, 1, 'undefined reference to `${name}`: no library the image names defines it')
			}
			return error('unresolved imports')
		}
	}
	// A link unit is not wrapped: its program is one input to the linker, which
	// merges it with its siblings and wraps the merged result once. Returning
	// no bytes says that, and the caller reads the program out of the result
	// instead.
	if e.link {
		return []u8{}
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
		bytes = elf.write(e.program, e.target, e.link_kind) or {
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
		// A nested function is a body of its own, and a constant in it is the
		// emitter's to write just as one in the enclosing body is, so the walk
		// reaches into it. Nothing else of the nested definition is checked
		// here: its name and its parameter classes were settled with the
		// top-level ones, and its statements are the ones this walks.
		if nested := stmt.nested_fn() {
			e.check_statements(nested.body, depth)!
		}
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
	// The kernel's argument vector is read off the stack before the stack is
	// put on the boundary a call wants, because the layout is written against
	// the stack pointer the kernel left and the alignment would move it. An
	// entry function that declares no parameters simply does not read the
	// registers; one that declares `char **envp` finds the kernel's
	// environment in the third.
	e.append(e.target.loader_arguments()!)
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
	if e.link_kind == .static_program {
		// A static program leaves through the exit syscall. The library's exit
		// is what flushes a buffered stream, and a program with no library has
		// nothing to flush through it: the call would be the one import a
		// static link cannot resolve, so the kernel's own exit takes its place.
		// The status is already in the register the call to the entry function
		// left it in, and the sequence moves it where the kernel reads it.
		e.append(e.target.exit_sequence_from(result)!)
		e.append(e.target.halt())
		return
	}
	e.append(e.target.move_register32(status, result)!)
	e.import_symbol('exit')
	e.reference(e.target.call_slot(0), .call_import, 'exit', '')
	// The library's exit does not return. If it ever did, it would be a bug
	// somewhere else, and stopping here is better than running into the bytes
	// that follow.
	e.append(e.target.halt())
}

// collect_nested gathers the functions a body defines inside itself, in the
// order they are written, walking the blocks a statement can hold a definition
// in and the bodies of the functions it finds. A function written inside a
// nested function is a function of the unit like any other, so it is gathered
// here too: its name and the classes of its parameters have to be in the tables
// before any body is emitted, or a call to it would be left to the linker.
fn collect_nested(stmts []ast.Stmt) []ast.FnDecl {
	mut out := []ast.FnDecl{}
	for stmt in stmts {
		if decl := stmt.nested_fn() {
			out << decl
			out << collect_nested(decl.body)
		}
		out << collect_nested(stmt.body)
		out << collect_nested(stmt.then_body)
		out << collect_nested(stmt.else_body)
		out << collect_nested(stmt.step)
	}
	return out
}

// slot_base_register is the register a slot is addressed from: the frame pointer
// of the function being emitted for an object that function declares itself, or
// the static-chain pointer for an object of the function a nested function is
// written in. Every place that turns a slot into an address asks this, so a
// captured object is reached through the chain everywhere it is used and a local
// object is reached through the frame everywhere, without either question being
// asked twice.
//
// A nested function reaches the frame of the function it is written in through
// one chain link: a call hands that frame pointer over in the chain register and
// the entry stores it in the chain slot. An object of a function further out
// would take a walk of the chain, which is not written, and neither is a captured
// object this back end moves with an instruction that cannot take the chain
// register as its base: an object of either floating type, a 128-bit integer, a
// long double, a complex object, a variable-length array and an object of an
// aggregate type. Both are refused here, by name, where the object is used,
// rather than addressed wrongly.
fn (mut e Emitter) slot_base_register(slot Slot, line int, col int) !backend.Register {
	if !slot.captured {
		return e.frame_pointer(line, col)
	}
	if slot.capture_owner != e.enclosing_symbol {
		e.diagnostics << problem(line, col, 'unsupported: ${e.function_symbol} uses an object declared in ${slot.capture_owner}, and only an object of the function it is written in is reached through the static chain')
		return error('an object captured from a function further out')
	}
	if slot.floating || slot.single || slot.wide || slot.long_double || slot.complex || slot.vla
		|| (slot.bytes > 0 && slot.count == 0) {
		e.diagnostics << problem(line, col, 'unsupported: ${e.function_symbol} uses an object of the enclosing function whose declared type this back end does not reach through the static chain; only an integer or pointer scalar, or an array of them, is')
		return error('a captured object of a type the chain cannot carry')
	}
	chain := e.chain or {
		e.diagnostics << problem(line, col, 'internal: ${e.function_symbol} reaches an object of its enclosing function and has no static chain')
		return error('no static chain')
	}
	register := e.static_chain(line, col)!
	base := e.frame_pointer(line, col)!
	e.append(e.target.load_slot(base, i32(chain.offset), register, e.target.word_size)!)
	return register
}

// load_call_chain puts the frame pointer of the function a nested function is
// written in into the chain register, where the callee reads it on entry. A
// nested function of this function is handed this function's frame; a nested
// function of the function this one is written in is handed the frame this one
// was itself handed, so two functions written side by side in one body see the
// same enclosing objects.
fn (mut e Emitter) load_call_chain(owner string, line int, col int) !void {
	register := e.static_chain(line, col)!
	if owner == e.function_symbol {
		base := e.frame_pointer(line, col)!
		e.append(e.target.move_register64(register, base)!)
		return
	}
	if owner == e.enclosing_symbol {
		chain := e.chain or {
			e.diagnostics << problem(line, col, 'internal: ${e.function_symbol} calls a nested function of its enclosing function and has no static chain')
			return error('no static chain')
		}
		base := e.frame_pointer(line, col)!
		e.append(e.target.load_slot(base, i32(chain.offset), register, e.target.word_size)!)
		return
	}
	e.diagnostics << problem(line, col, 'unsupported: ${e.function_symbol} calls a nested function written in ${owner}, and only a nested function of this function or of the function it is written in is called')
	return error('a nested function out of reach')
}

// record_nested keeps a nested function until the function that writes it is
// done, with the scopes of the block the definition was read in. The scopes are
// copied and every object in them is marked captured, because the frame those
// offsets belong to is the enclosing one: the nested function's own frame does
// not hold them, so each is reached from the chain.
//
// An object already marked captured came from a function further out and keeps
// its owner, which is one link more than the nested function can walk, so a use
// of it is refused where it is used.
fn (mut e Emitter) record_nested(decl ast.FnDecl) {
	mut scopes := []map[string]Slot{cap: e.scopes.len}
	for scope in e.scopes {
		mut marked := map[string]Slot{}
		for name, slot in scope {
			captured := if slot.captured {
				slot
			} else {
				Slot{
					...slot
					captured:      true
					capture_owner: e.function_symbol
				}
			}
			marked[name] = captured
		}
		scopes << marked
	}
	e.pending_nested << PendingNested{
		decl:   decl
		scopes: scopes
	}
}

// emit_nested emits a nested function after the function that writes it. The
// scopes the definition was read in are the scopes the nested function's body is
// emitted with, which is what lets a name of the enclosing function resolve
// inside it, and they are put away afterwards: the enclosing function is done
// with its scopes, and the next function starts with none.
fn (mut e Emitter) emit_nested(pending PendingNested) !void {
	e.scopes = pending.scopes
	e.emit_function(pending.decl)!
	e.scopes = []
}

// emit_function writes one function: its frame, its parameters into their slots,
// its statements, and a return of zero when the body can fall off the end
// without a return of its own. C says the entry function does that, and every
// function here needs it, because falling through would otherwise hand the
// caller whatever the last call left in the result register.
fn (mut e Emitter) emit_function(decl ast.FnDecl) !void {
	// Which function is being emitted and which function wrote it are what a
	// captured object is answered against: an object is reached through the
	// chain when it belongs to the function this one is written in. The nested
	// functions of this body are read here too, so a call inside the body finds
	// the frame pointer it has to hand over, and the chain a nested function
	// keeps is emptied: a function declared at the top level has no enclosing
	// frame and one declared in a body gets its own slot below.
	e.function_symbol = decl.name
	e.enclosing_symbol = decl.owner
	e.chain = none
	e.nested_functions = map[string]string{}
	for nested in collect_nested(decl.body) {
		e.nested_functions[nested.name] = nested.owner
	}
	e.pending_nested = []
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
	} else if !abi.travels_on_the_x87_stack(decl.ret_type)
		&& decl.ret_type.kind != .complex_long_double
		&& decl.ret_type.kind != .pointer && decl.ret != 'int' && decl.ret != 'unsigned int'
		&& decl.ret != 'void'
		&& decl.ret != 'double' && decl.ret != 'float'
		&& !e.eight_byte_integer(types.from_words(decl.ret.split(' ')) or { types.Type{} })
		&& !e.narrow_integer_spelling(decl.ret) {
		e.diagnostics << problem(decl.line, decl.col, 'unsupported: ${decl.name} returns ${decl.ret}, and only int, unsigned int, the four 64-bit integers, the narrow integer types, float, double, a pointer and void are implemented')
		return error('unsupported return type')
	}
	e.returning = decl.ret
	e.returning_complex_long_double = decl.ret_type.kind == .complex_long_double
	e.return_class = ret_class
	if e.hidden_bytes > 0 {
		e.hidden = e.reserve(e.hidden_bytes)
	}
	// A nested function is handed the frame pointer of the function it is
	// written in, and keeps it: the chain slot is where the body of a captured
	// object is read from, so it is reserved before the parameters, which may
	// themselves be stored beside it.
	if decl.nested {
		e.chain = e.reserve(e.target.word_size)
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
	// The chain register is only a value a call put there, and the call that
	// follows the entry reads it before anything else does: a nested function
	// stores it in its chain slot on entry, so every object of the function it
	// is written in can be read from it afterwards. The store is after the
	// frame is open because the slot is at an offset from rbp.
	if slot := e.chain {
		register := e.static_chain(decl.line, decl.col)!
		base := e.frame_pointer(decl.line, decl.col)!
		e.append(e.target.store_slot(base, i32(slot.offset), register, e.target.word_size)!)
	}
	// A goto that leaves a block claiming a variable-length array's storage
	// restores the stack pointer from the scope it lands inside, and the pre-pass
	// records how many such scopes enclose each named label. A function that
	// declares no such array has none to leave and skips the walk.
	e.vla_label_counts = map[string]int{}
	if function_has_vla(decl.body) {
		e.vla_label_counts = vla_label_counts(decl.body)
	}
	// A goto that leaves a block whose objects carry a cleanup runs them before
	// it jumps, and this pre-pass records how many such blocks enclose each
	// named label, for the same reason the one above does.
	e.cleanup_label_counts = map[string]int{}
	if function_has_cleanups(decl.body) {
		e.cleanup_label_counts = cleanup_label_counts(decl.body)
	}
	e.push_scope()
	// The numbers a walk through the unnamed arguments starts from are this
	// function's and not the last one's, so they are reset here whatever the
	// declaration turns out to be.
	e.variadic = decl.resolved.variadic
	e.named_gp = 0
	e.named_fp = 0
	e.named_stacked = 0
	e.save_area = none
	e.argument_lists = []
	// A function that is handed an argument list is not a variadic definition,
	// but its parameter is a list all the same: `void f(va_list ap)` may walk it,
	// which is how a function that formats its arguments on behalf of a variadic
	// one is written.
	for param in decl.params {
		if abi.is_argument_list(param.resolved) {
			e.argument_lists << param.name
		}
	}
	if e.variadic {
		// A variadic callee is handed arguments it cannot name, and no
		// instruction says where they went: the convention puts each one in a
		// register until that file runs out and on the stack after that. Writing
		// every argument register into a save area costs a few instructions on
		// entry and is what makes a walk through the arguments possible at all.
		// The registers are written before the parameters are stored, because
		// storing one uses the result register.
		e.save_area = e.save_argument_registers(decl)!
	}
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
		if param.resolved.kind == .complex_long_double {
			// A `long double _Complex` parameter arrives in memory as
			// thirty-two bytes, the real part at the lower address, and the
			// caller pushed the four words. An odd number of eight-byte words
			// before it is a padding word the caller wrote, so the same rule a
			// long double follows applies and the value still starts at a
			// multiple of sixteen. Measured on gcc 16.2.1: the callee reads
			// its first with `fldt 16(%rbp)` and `fldt 32(%rbp)`.
			if stacked % 2 == 1 {
				stacked++
			}
			object := e.declare(param.name, param.typ, 0, 0, 0, param.line, param.col, false)!
			at := 2 * e.target.word_size + stacked * e.target.word_size
			e.copy_stack_object(object, at, param.line, param.col)!
			stacked += 4
			continue
		}
		if abi.travels_on_the_x87_stack(param.resolved) {
			// A long double parameter arrives in memory: sixteen bytes at the
			// alignment the type has, which is sixteen. An odd number of
			// eight-byte words before it is a padding word the caller wrote, so
			// it is skipped and the value still starts at a multiple of
			// sixteen. Measured on gcc 16.2.1: `addl` reads its first long
			// double with `fldt 16(%rbp)` and its second with `fldt 32(%rbp)`.
			if stacked % 2 == 1 {
				stacked++
			}
			object := e.declare(param.name, param.typ, 0, 0, 0, param.line, param.col, false)!
			at := 2 * e.target.word_size + stacked * e.target.word_size
			e.copy_stack_object(object, at, param.line, param.col)!
			stacked += 2
			continue
		}
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
			object := e.declare(param.name, param.typ, 0, 0, 0, param.line, param.col, false)!
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
			object := e.declare(param.name, param.typ, 0, class.bytes, 0, param.line, param.col, false)!
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
		slot := e.declare(param.name, param.typ, 0, 0, 0, param.line, param.col, false)!
		// The arguments a sequence ran out for arrive on the stack, and where
		// they are is the caller's side of the same rule: the first one the
		// caller pushed is at the return address, so sixteen bytes past the
		// frame pointer counting the frame pointer and the return address, and
		// the ones after it follow one machine word apart.
		at := 2 * e.target.word_size + stacked * e.target.word_size
		if slot.single {
			// A float parameter arrives as four bytes in the floating-point
			// register its position names, and is stored into a four-byte slot.
			// A float that ran out of registers arrives on the stack in the low
			// four bytes of a word.
			if register := e.target.float_arg_reg(doubles) {
				e.store_single_register(slot, register, param.line, param.col)!
				doubles++
				continue
			}
			float_register := e.float_accumulator(param.line, param.col)!
			base := e.frame_pointer(param.line, param.col)!
			e.append(e.target.load_float_slot(base, at, float_register)!)
			e.store_single_register(slot, float_register, param.line, param.col)!
			stacked++
			continue
		}
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
	// Where a walk through the unnamed arguments starts: past the named ones in
	// each register file, and past the words of the named ones that went on the
	// stack. The counts the loop kept are exactly that.
	if e.variadic {
		e.named_gp = integers
		e.named_fp = doubles
		e.named_stacked = stacked
	}
	returned := e.emit_statements(decl.body)!
	// Every label a goto in this function named has to be a label this function
	// wrote, and the question is about the whole body: a jump to a label the
	// function never writes would be an instruction to an address the image
	// does not hold.
	e.report_undefined_labels()
	if !returned {
		if decl.ret == 'double' || decl.ret == 'float' {
			// A function that falls off its end returns zero, and zero as a
			// floating value is the floating-point register file's own zero
			// rather than the integer one: the caller reads the value out of the
			// other register, and an int zero there would be whatever the body
			// left. Clearing the whole register gives +0.0 in the low four bytes
			// of a float and in the eight of a double.
			register := e.float_accumulator(decl.line, decl.col)!
			e.append(e.target.zero_double(register)!)
		} else if e.returning_complex_long_double {
			// The value comes back as two extended components on the x87
			// stack, so the zero is two of them: the imaginary part is pushed
			// first so the real part is st(0), which is the order a caller
			// pops them in.
			e.append(e.target.extended_zero())
			e.append(e.target.extended_zero())
		} else if e.writes_a_long_double(decl.ret) {
			// A long double comes back on the x87 stack, so the zero a function
			// that falls off its end leaves is pushed there: an int zero in the
			// result register would be read as no long double at all.
			e.append(e.target.extended_zero())
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
	e.callees = []Slot{}
	e.slot_base = 0
	e.vla_saves = []int{}
	e.cleanups = [][]Cleanup{}
	e.wide_left = []Slot{}
	e.wide_right = []Slot{}
	e.wide_scratch = []Slot{}
	e.wide_arguments = []Slot{}
	e.wide_working = []WideWorking{}
	// The named labels of a function are that function's, and the maps that
	// hold them start empty for each one: a label is a name for a place inside
	// one function, and a goto cannot reach out of the function it is written
	// in. The jumps themselves keep their own numbering across the file.
	e.goto_labels = map[string]string{}
	e.goto_placed = map[string]bool{}
	e.goto_used = map[string]LabelUse{}
	// A nested function is a function of its own and is emitted here, after the
	// function that writes it: its body may call that function back and it reads
	// that function's frame through the chain, so the enclosing body was emitted
	// first and its frame is the one the chain names. The scopes are set to the
	// ones the definition was read in, and each nested function puts them away
	// when it is done.
	pending := e.pending_nested
	e.pending_nested = []
	for nested in pending {
		e.emit_nested(nested)!
	}
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
				e.emit_assign(stmt, 0)!
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
			.switch_stmt {
				e.emit_switch(stmt)!
			}
			.case_stmt {
				e.emit_case_label(stmt, false)!
			}
			.default_stmt {
				e.emit_case_label(stmt, true)!
			}
			.label_stmt {
				e.emit_label(stmt)!
			}
			.goto_stmt {
				e.emit_goto(stmt)!
			}
			.asm_stmt {
				e.emit_asm(stmt)!
			}
			.nested_function {
				// A function defined here is not run here: its body is emitted
				// after the function that writes it, and what this place does is
				// remember the definition with the scopes it was written in.
				if decl := stmt.nested_fn() {
					e.record_nested(decl)
				}
			}
		}
	}
	return returned
}

// emit_asm writes the machine code of a statement-level GNU asm.
//
// A statement with no instruction text and no operands does nothing a compiler
// can see. Its whole content is the constraint on what may be moved across it,
// and this compiler moves nothing across it: the one optimizer pass,
// `fold-builtins` in `optimizer/`, folds a call to a constant and touches
// neither the order of a statement nor a memory access, so the `"memory"`
// clobber that `__asm__ __volatile__("" ::: "memory")` writes has no work to do
// and the statement is emitted as nothing. That is exactly what the source
// asked the compiler to assume, and it is the whole of what this accepts. A
// pass that reordered or elided a memory access across the statement would have
// to honour that clobber before it could run under this tree.
//
// A statement that writes an instruction is refused by name, with its text and
// its location. Emitting nothing for one would be a value the program asked for
// and did not get, which is the wrong answer this compiler does not write: the
// emitter has no way to place an instruction's registers from a constraint
// string, so the honest half step is to refuse rather than to guess. The refusal
// is placed here, at the statement, and not where the statement was read, so a
// body the program never reaches is not a refusal: `parser/declarations.v`
// skips a `static` definition nothing in the file names before its body is
// read, and a statement in one of those is never seen at all.
fn (mut e Emitter) emit_asm(stmt ast.Stmt) !void {
	if stmt.asm_is_goto() || stmt.asm_goto_labels().len > 0 {
		return e.emit_asm_goto(stmt)
	}
	if stmt.asm_text().len > 0 || stmt.asm_outputs() > 0 || stmt.asm_inputs() > 0 {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the asm statement ${stmt.asm_spelling()} is not emitted by this compiler')
		return error('asm statement')
	}
}

// emit_asm_goto emits the one shape an asm goto can take here: a template of
// the form `jmp %lN`, an unconditional jump to the Nth label of the statement's
// GotoLabels list, counting from zero. That is the shape glibc's helpers use to
// reach a label, and it is the whole of what a template can mean in this back
// end: this compiler writes machine code directly and has no assembler to run a
// general template through, so any other template is refused by name, with its
// text and its location, rather than guessed at. A template naming a label the
// list does not hold is refused the same way, and a list with no labels is
// refused because there is then no label for a template to name.
fn (mut e Emitter) emit_asm_goto(stmt ast.Stmt) !void {
	labels := stmt.asm_goto_labels()
	if stmt.asm_outputs() > 0 || stmt.asm_inputs() > 0 {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the asm goto ${stmt.asm_spelling()} has operands, and only a template that jumps to a named label is emitted here')
		return error('asm goto with operands')
	}
	if labels.len == 0 {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the asm goto ${stmt.asm_spelling()} names no label for its template to jump to')
		return error('asm goto without a label')
	}
	index := jump_label_index(stmt.asm_text()) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the asm goto template ${stmt.asm_spelling()} is not an unconditional jump to a label, and only `jmp %lN` jumping to a named label is emitted here')
		return error('asm goto template')
	}
	if index >= labels.len {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the asm goto template ${stmt.asm_spelling()} names label ${index}, and its list holds ${labels.len}')
		return error('asm goto label')
	}
	name := labels[index]
	if !(name in e.goto_used) {
		e.goto_used[name] = LabelUse{
			line: stmt.line
			col:  stmt.col
		}
	}
	e.jump(e.named_label(name))!
}

// jump_label_index is the label number a `jmp %lN` template names, counting from
// zero, and none for every other template. This is the one shape the asm goto
// path emits: an unconditional jump to one of the statement's own labels, with
// `%l0` the first. Space around the words is allowed, which is what a template
// written as "jmp %l0\n" leaves; the `%l` and the number are kept together,
// because that is one operator and gcc reads it that way too.
fn jump_label_index(text string) ?int {
	s := text.trim_space()
	if !s.starts_with('jmp') {
		return none
	}
	rest := s[3..].trim_space()
	if !rest.starts_with('%l') {
		return none
	}
	digits := rest[2..]
	if digits.len == 0 {
		return none
	}
	mut value := 0
	for i in 0 .. digits.len {
		c := digits[i]
		if c < 0x30 || c > 0x39 {
			return none
		}
		value = value * 10 + int(c - 0x30)
	}
	return value
}

// emit_return writes the value into the register a function's results arrive in
// and closes the frame. Every return leaves the same way, whatever the function
// did before it. The value is converted to the function's return type where the
// two are different classes, which is the same conversion a call makes for an
// argument: `return 1;` in a function returning a double returns 1.0, and
// `return 1.5;` in one returning an int returns 1.
fn (mut e Emitter) emit_return(stmt ast.Stmt) !void {
	expr := stmt.expr or {
		if e.returning == 'void' {
			// A return without a value is the form C allows in a function whose
			// return type is void (6.8.6.4p1), and it leaves the way a return with
			// a value does once the value is written: the frame is closed and
			// control goes back to the caller.
			//
			// The objects the body's blocks asked a cleanup for run here, because
			// this is a place control leaves them all at once.
			e.run_cleanups_above(0)!
			e.append(e.target.frame_epilogue())
			return
		}
		e.diagnostics << problem(stmt.line, stmt.col, 'a constraint violation: return without a value in a function that returns ${e.returning}')
		return error('return without a value')
	}
	if e.returning == 'void' {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: return with a value in a function that returns void')
		return error('return with a value')
	}
	if e.cleanups_live() {
		// The objects this function's blocks asked a cleanup for run where the
		// function leaves, which a return is. The value goes through the frame
		// on the way, so that the calls and the value do not share a register.
		return e.emit_return_with_cleanups(expr, stmt)
	}
	if e.return_class.bytes > 0 {
		if e.return_class.count > 2 {
			// The object goes to the address this call was given, which the function
			// kept in the frame, and the call answers with that address in the
			// accumulator: both addresses are parked, because a copy needs two
			// registers and neither of them can hold an address.
			e.object_hand_over_address(expr, e.return_class, 0)!
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
		// The object is evaluated once and its address parked, rather than a
		// second time for the first eightbyte: an expression that is not
		// already an object, such as a complex sum, has to build one, and
		// building it again for the second read would use the register the
		// first read left the second eightbyte in.
		address := e.value_slot(0)
		e.object_hand_over_address(expr, e.return_class, 0)!
		e.store_accumulator(address, stmt.line, stmt.col)!
		if e.return_class.count == 2 {
			// The second eightbyte is read first and eight bytes further in, and
			// the object's address is read again for the first one, because the
			// address travels in the register the first general eightbyte goes
			// back in.
			e.load_accumulator(address, stmt.line, stmt.col)!
			base := e.accumulator(stmt.line, stmt.col)!
			e.append(e.target.add_immediate(base, e.target.word_size))
			e.load_return_eightbyte(base, 1, e.return_class.bytes - e.target.word_size,
				e.return_class.second_floating, stmt.line, stmt.col)!
		}
		e.load_accumulator(address, stmt.line, stmt.col)!
		base := e.accumulator(stmt.line, stmt.col)!
		e.load_return_eightbyte(base, 0, e.target.word_size, e.return_class.first_floating,
			stmt.line, stmt.col)!
		e.append(e.target.frame_epilogue())
		return
	}
	if e.returning_complex_long_double {
		// The value comes back as two extended components on the x87 stack,
		// which is neither the object-class path above nor the single extended
		// value below.
		return e.emit_complex_long_double_return(expr, stmt.line, stmt.col)
	}
	if e.writes_a_long_double(e.returning) {
		// A long double comes back on the x87 stack and not in a register, so
		// the value is put there instead of being converted into the result
		// register.
		return e.emit_extended_return(expr, stmt.line, stmt.col)
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
			e.widen_word_pair(expr.typ.is_unsigned_type(), e.narrow_width(expr.typ), stmt.line,
				stmt.col)!
		}
		e.append(e.target.frame_epilogue())
		return
	}
	e.emit_expr(expr)!
	e.convert_to_return(expr, stmt.line, stmt.col)!
	e.append(e.target.frame_epilogue())
}

// emit_return_with_cleanups hands a value back out of a function whose blocks
// declared objects with a cleanup attribute. The value is computed first and
// parked in the frame, the cleanups run, and the value goes back where the
// caller reads it: a cleanup is a call, and a call clobbers the register a
// result is handed back in, so a value left in that register across the call
// would not be the value the program returned.
//
// A value handed back as an object is refused rather than written. Parking one
// needs its bytes copied out of the object first, and an object the cleanups may
// be about to free is not a thing to read afterwards; a scalar, a float and a
// double are one value and park in one slot.
fn (mut e Emitter) emit_return_with_cleanups(expr ast.Expr, stmt ast.Stmt) !void {
	if e.return_class.bytes > 0 || e.returning_complex_long_double || e.writes_a_128(e.returning)
		|| e.writes_a_long_double(e.returning) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a return of an object out of a function whose blocks carry a cleanup attribute')
		return error('object return with cleanups')
	}
	e.emit_expr(expr)!
	e.convert_to_return(expr, stmt.line, stmt.col)!
	floating := e.returning == 'float' || e.returning == 'double'
	// The value gets a slot of its own rather than one of the expression slots,
	// because the calls below evaluate their own arguments through those and
	// would write over what is parked here.
	value := e.reserve(e.target.word_size)
	if floating {
		e.store_float_accumulator(value, e.returning == 'float', stmt.line, stmt.col)!
	} else {
		e.store_accumulator(value, stmt.line, stmt.col)!
	}
	e.run_cleanups_above(0)!
	if floating {
		e.load_float_accumulator(value, e.returning == 'float', stmt.line, stmt.col)!
	} else {
		e.load_accumulator(value, stmt.line, stmt.col)!
	}
	e.append(e.target.frame_epilogue())
}

// convert_to_return makes the value being returned the class the function
// returns. Both directions are conversions the language defines, and the one that
// is refused is a pointer: a function returning an int or a double has no
// conversion to make from an address, and the answer would be half of it or an
// address that is no longer one.
//
// A return type narrower than an int is the one case where the conversion cuts
// the value rather than widening it: the machine hands back an int in the
// register whatever the type says, and the language makes the caller's value the
// one of that type, so `short f(void) { return 70000; }` answers 4464 and not
// 70000. Measured on gcc 16.2.1, which narrows in the callee the same way.
fn (mut e Emitter) convert_to_return(expr ast.Expr, line int, col int) !void {
	if e.returning == 'double' {
		return e.convert_to_double(expr, line, col)
	}
	if e.long_double_of(expr) {
		// The one conversion out of the extended type this back end writes is
		// the conversion to a double, which is the branch above. Every other
		// return type is a conversion it does not make, and the value the
		// expression left is the address of its sixteen bytes, so returning it
		// unconverted would hand the caller that address as an int or a float.
		// It is refused by name, the way the same conversion is refused at a
		// cast, a store and an argument.
		return e.refuse_a_long_double_conversion(e.returning, line, col)
	}
	if e.returning == 'float' {
		// A function returning a float rounds what it returns to four bytes,
		// which is the conversion the language makes and the reason the value a
		// caller reads is the float's own and not the double it was computed
		// from.
		return e.convert_to_single(expr, line, col)
	}
	if e.floating_of(expr) {
		// The return type is written rather than resolved here, so its width is
		// read off the same spelling the signedness is read off. A floating
		// expression returned from a 64-bit integer function converts at that
		// width: reading it as an int and widening the result answers the wrong
		// number, which is what lane-uconv64 was there to fix.
		returning := types.from_words(e.returning.split(' ')) or { types.Type{} }
		e.convert_to_int(expr, e.written_is_unsigned(e.returning), e.storage_width(returning) or { 0 },
			line, col)!
	} else if e.returns_eight_byte_integer() {
		// A function whose return type is a 64-bit integer leaves the whole
		// register as its value, so a narrower expression is widened into it the
		// same way an operand of a 64-bit step is: `return -1;` in a function
		// returning a long answers -1.
		e.extend_operand_to_word(expr, line, col)!
	}
	if kind := e.narrow_return_kind() {
		register := e.accumulator(line, col)!
		e.narrow_register(kind, register, (e.storage_width(expr.typ) or { 4 }) == 8)!
	}
}

// narrow_return_kind is the kind of a return type narrower than an int, or none
// for every other type. It is the question the cut in convert_to_return turns on
// and the same list the return-type check admits.
fn (e Emitter) narrow_return_kind() ?types.Kind {
	typ := types.from_words(e.returning.split(' ')) or { return none }
	return if typ.kind in [.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short] {
		typ.kind
	} else {
		none
	}
}

// narrow_integer_spelling says whether a written type is one of the integer kinds
// narrower than an int. A function of one of those types returns a value the
// caller reads at the type's own width, which is the width the register's low
// bits hold, so the type is one the emitter has a return for.
fn (e Emitter) narrow_integer_spelling(written string) bool {
	typ := types.from_words(written.split(' ')) or { return false }
	return typ.kind in [.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short]
}

// narrow_register cuts the value in a register to the width of a narrow integer
// kind and puts it back, which is the cut both a conversion to one of those types
// and a return of one make: `(short)70000` and `short f(void) { return 70000; }`
// are the same 4464. The word flag says the value arrived as a whole 64-bit
// register, which is what decides the width the `_Bool` case tests: a `_Bool` is
// not a cut but a comparison, so the value is 1 for everything that is not zero,
// and a 64-bit value with nothing in its low four bytes is still not zero.
fn (mut e Emitter) narrow_register(kind types.Kind, register backend.Register, word bool) !void {
	match kind {
		.bool_ {
			if word {
				e.append(e.target.test_word(register)!)
			} else {
				e.append(e.target.test(register)!)
			}
			e.append(e.target.set_condition(backend.Condition.not_equal, register)!)
			e.append(e.target.widen_byte(register)!)
		}
		.char_, .signed_char { e.append(e.target.sign_extend_byte(register)!) }
		.unsigned_char { e.append(e.target.widen_byte(register)!) }
		.short { e.append(e.target.sign_extend_half(register)!) }
		.unsigned_short { e.append(e.target.zero_extend_half(register)!) }
		else {}
	}
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
	if size_expr := stmt.decl_vla_size() {
		// A variable-length array is the one declaration whose storage is
		// claimed while the program runs rather than reserved by the frame.
		return e.emit_vla_decl(stmt, size_expr)
	}
	// An object of an aggregate type is sized by the layout the reader worked
	// out, and that size may legitimately be zero: a structure with no members
	// is a complete object of no bytes. measured tells declare the zero is the
	// object's size and not a spelling it has no width for.
	measured := e.known_aggregate_bytes(stmt.resolved()) != none
	slot := e.declare(stmt.decl_name, stmt.decl_type, stmt.decl_count, stmt.bytes(), stmt.decl_stride(),
		stmt.line, stmt.col, measured)!
	// What makes an object an argument list is the type it was declared with,
	// because that is what says how the four operations over a list may treat it.
	if abi.is_argument_list(stmt.resolved()) {
		e.argument_lists << stmt.decl_name
	}
	if stmt.cleanup() != '' && e.cleanups.len > 0 {
		// The object is in the block this declaration sits in, and the function
		// its cleanup attribute named runs on it where that block ends. The
		// record is kept here rather than where the block is closed because the
		// block is emitted as it is read, and the slot the object got is what
		// the call needs the address of, not the name alone.
		e.cleanups[e.cleanups.len - 1] << Cleanup{
			name:     stmt.decl_name
			typ:      stmt.resolved()
			function: stmt.cleanup()
			line:     stmt.line
			col:      stmt.col
		}
	}
	init := stmt.init or { return }
	if slot.long_double && slot.count == 0 {
		// An object of the extended type declared with a value: the value is
		// copied if it is a long double, and converted by the machine's x87 moves
		// if it is a double, a float or an integer.
		return e.store_long_double(slot, init, stmt.line, stmt.col, 0)
	}
	if slot.complex {
		// A complex object is written by the conversion its type names rather
		// than by a copy: a real initializer is a complex value with a zero
		// imaginary part, which is 6.3.2.2 and not a byte copy.
		return e.store_complex_local(slot, stmt.decl_type, init, stmt.line, stmt.col, 0)
	}
	if slot.wide {
		// A 128-bit object declared with a value takes one of three things: a copy
		// of another object of the type, the pair a computation left in the
		// registers, or a narrower value widened into the two words. The store asks
		// the value which of the three it is, so a declaration and an assignment
		// share one path.
		return e.store_wide(slot, init, stmt.line, stmt.col, 0)
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
		return e.assign_object_local(declared, slot, 0)
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

// emit_vla_decl claims a variable-length array's storage where the declaration
// runs. The size is a value the program computed, so the frame cannot reserve it:
// the bytes are rounded up to the alignment a call needs and subtracted from the
// stack pointer, and the address the stack pointer became is kept as the array's
// base. The size before rounding is kept too, because that is what sizeof answers
// with. The stack pointer before the subtraction is saved when the block has not
// saved one yet, and the block's exit puts it back: that is what gives the
// storage back at the end of the block rather than only at the end of the
// function, so a loop body that declares an array does not grow the stack every
// time round.
fn (mut e Emitter) emit_vla_decl(stmt ast.Stmt, size_expr ast.Expr) !void {
	if stmt.init != none {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.decl_name} is a variable-length array, and a variable-length array may not be initialized')
		return error('VLA initializer')
	}
	slot := e.declare_vla(stmt.decl_name, stmt.decl_stride(), stmt.line, stmt.col)!
	// The size the object is, before the frame rounds it up: sizeof answers with
	// this and not with the padded size, because padding is a fact about the
	// stack and not about the object.
	e.emit_expr_at(size_expr, 1)!
	register := e.accumulator(stmt.line, stmt.col)!
	base := e.frame_pointer(stmt.line, stmt.col)!
	e.append(e.target.store_slot(base, i32(slot.vla_size), register, e.target.word_size)!)
	// The stack pointer before this declaration's storage is subtracted is what
	// the block puts back when it ends, so the first variable-length array in a
	// block saves it into a frame slot the block's exit restores from. A later
	// declaration in the same block needs no save of its own: putting the stack
	// pointer back to the first one gives all of them back at once. The save is
	// written before the subtraction and not after, because after it the stack
	// pointer is the array's base and no longer the value to return to.
	if e.vla_saves.len > 0 && e.vla_saves[e.vla_saves.len - 1] == vla_no_save {
		restore := e.reserve(e.target.word_size)
		save_stack := e.target.stack_pointer() or {
			e.diagnostics << problem(stmt.line, stmt.col, '${e.target.name}: the machine has no stack pointer to save before a variable-length array claims its storage')
			return error('no stack pointer')
		}
		e.append(e.target.store_slot(base, i32(restore.offset), save_stack, e.target.word_size)!)
		e.vla_saves[e.vla_saves.len - 1] = restore.offset
	}
	// Round up to the boundary a call needs, so that a call inside the body
	// reaches a function whose frame is aligned, and lower the stack pointer by
	// that much. What the stack pointer becomes is where the array starts.
	e.append(e.target.add_immediate(register, frame_alignment - 1))
	e.append(e.target.and_immediate(register, -frame_alignment)!)
	e.append(e.target.sub_rsp_register(register)!)
	stack := e.target.stack_pointer() or {
		e.diagnostics << problem(stmt.line, stmt.col, '${e.target.name}: the machine has no stack pointer to claim a variable-length array against')
		return error('no stack pointer')
	}
	e.append(e.target.store_slot(base, i32(slot.vla_base), stack, e.target.word_size)!)
}

// emit_assign evaluates the value and writes it into the slot the name lives in.
// The name has to be in scope: an assignment to a name that was never declared
// has nowhere to go, and a guessed slot would be someone else's variable.
fn (mut e Emitter) emit_assign(stmt ast.Stmt, depth int) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned without a value')
		return error('assignment without a value')
	}
	// A compound assignment whose target is reached through an address is
	// written by the path that computes that address once and reads and writes
	// through it. A name target is not one of those: reading a name has no side
	// effect to repeat, and the expansion in expr is emitted directly below.
	if stmt.compound != '' && (stmt.field != none || stmt.deref() != none || stmt.subscript() != none || stmt.index != none) {
		return e.assign_compound(stmt, depth)
	}
	if deref := stmt.deref() {
		return e.assign_deref(stmt, deref, expr, depth)
	}
	if member := stmt.field {
		return e.assign_member(stmt, *member, expr, depth)
	}
	if subscript := stmt.subscript() {
		return e.assign_subscript(stmt, subscript, expr, depth)
	}
	if subscript := stmt.index {
		return e.assign_element(stmt, subscript, expr, depth)
	}
	target := e.lookup(stmt.target) or {
		// A top-level object is written through its address in the image, the
		// same way a local is written through its place in the frame.
		if object := e.global_of(stmt.target) {
			if object.object && object.count == 0 {
				return e.assign_object_global(stmt, object, depth)
			}
			return e.assign_global(stmt, object, expr, depth)
		}
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned to, and no local of that name is in scope')
		return error('unknown assignment target')
	}
	if target.long_double && target.count == 0 {
		// The same store a declaration of the type makes: the target's address
		// is worked out, the value is converted or copied, and the sixteen bytes
		// are written.
		return e.store_long_double(target, expr, stmt.line, stmt.col, depth)
	}
	if target.complex {
		return e.assign_complex_local(stmt, target, depth)
	}
	if target.wide {
		// A wide target is sixteen bytes of storage, and what is written into it is
		// one of three things: a copy of another object of the type, a pair a
		// computation left in the registers, or a narrower value widened. The store
		// asks the value which of the three it is, so every wide assignment and
		// every wide declaration shares one path.
		return e.store_wide(target, expr, stmt.line, stmt.col, depth)
	}
	if target.bytes > 0 {
		return e.assign_object_local(stmt, target, depth)
	}
	if e.wide_value(expr) {
		// The same read the declaration makes: the low word of the object, at the
		// width of the slot it is written into. The floating slot is refused for
		// the same reason it is there.
		if target.floating {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a conversion from a 128-bit object to a slot that holds a double is not one this back end makes, and a value that wide does not convert to a floating type here')
			return error('128-bit to a double')
		}
		e.low_word_of_object(expr, target.width, stmt.line, stmt.col, depth + 1)!
		return e.store_accumulator(target, stmt.line, stmt.col)
	}
	// The value is read one level deeper than the assignment is written at, so
	// that its own half-finished values sit above the slots this store uses.
	e.emit_expr_at(expr, depth)!
	e.store_value(target, expr, stmt.line, stmt.col)!
}

// assign_deref writes through an address: the target is a dereference, so what
// the store needs is the address the expression it reads through gives, and the
// value is written at the width of the type the pointer points at. This is the
// store side of the read emit_deref already makes, and it reuses the same
// widths: a char is one byte, an int four, a pointer the machine's word, and a
// double is written by the instruction that moves one.
//
// The address is computed first and parked in a value slot while the value is
// read, which is the order the element and the member stores use: the value's
// own expression can call a function, and the call would leave its result in the
// register the address was in. The value is emitted one level down so it cannot
// use the slot the address is waiting in.
//
// A value wider than the object written to, or narrower, is refused by name, and
// so is a pointed-at type this back end has no store for: writing either at a
// guessed width would take bytes from a neighbouring object. A char object is
// the one exception, because the language stores an int value in a char by
// taking its low byte, which is what makes `*cp = 1` one byte.
fn (mut e Emitter) assign_deref(stmt ast.Stmt, target ast.Expr, expr ast.Expr, depth int) !void {
	unary := target as ast.Unary
	// The address is the value of the expression the dereference reads
	// through: `*p` writes at the address p holds, and `**pp` writes at the
	// address the outer read gives, which is the value of `*pp`.
	e.emit_expr_at(unary.expr, depth + 1)!
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	if unary.typ.kind.is_extended() {
		// A write through an address of the extended type is the store an
		// object of the type makes, at the address the pointer holds: sixteen
		// bytes are not a width the machine moves in one instruction.
		return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
	}
	if unary.typ.kind == .double {
		return e.assign_double_at(stmt, address, expr, depth)
	}
	width := e.storage_width(unary.typ) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: *p is assigned through an address of ${unary.typ.describe()}, and this back end writes ints, chars, doubles and pointers only')
		return error('unsupported pointed-at type')
	}
	e.emit_expr_at(expr, depth + 1)!
	address_register := e.scratch(stmt.line, stmt.col)!
	if e.floating_of(expr) {
		// A double written into an integer object converts first, because the
		// store moves the integer the conversion produced and not the bits of
		// the double. The pointed-at type is the destination and it is resolved
		// here, so its signedness is read off it rather than off a spelling.
		e.convert_to_int(expr, unary.typ.is_unsigned_type(), width, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, width)!)
		return
	}
	value_width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	// The width check is the one store_value makes for a name: a constant is
	// written at the width of the object because a constant says nothing about
	// its own width, a value narrower than the object is converted to the
	// object's type, and a wider one is refused. A char object takes an int by
	// its low byte, which is the narrowing the language also defines and the
	// check leaves alone.
	if e.constant(expr) == none && value_width > width && !(width < 4 && value_width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored through an address of ${unary.typ.describe()}, which holds ${width}')
		return error('width mismatch')
	}
	if width == 8 {
		// A value narrower than the object is widened into the whole register
		// before it is written, which is what a store into a name of that
		// width does: the store moves eight bytes, so an int whose upper half
		// the load cleared would be written as its unsigned reading.
		e.extend_operand_to_word(expr, stmt.line, stmt.col)!
	}
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, width)!)
}

// assign_compound writes `E1 op= E2` where E1 is reached through an address: a
// member (`s.m` or `p->m`), an element of an array, or what a pointer points at
// (`*p`). The operator exists as a construct of its own in C because E1 is
// evaluated once. Written as `E1 = E1 op E2` an index like `a[i++]` would be
// stepped twice, once for the read and once for the write, which is a different
// program, so the address is computed once, parked, and both the read and the
// write go through it.
//
// The address is the one the increment machinery computes for the same shapes,
// and the operator is applied by the apply_binary and apply_float the expression
// reader uses, so this is a shared path rather than a second idea about
// arithmetic. A name target does not come here: reading a name has no side
// effect to repeat and the expansion in expr is emitted directly. What cannot be
// written through a parked address here is refused by name rather than
// half-emitted: a bitfield, a pointer (whose `+=` scales by the pointee size),
// and the 128-bit, complex and long double objects this back end has no value
// for.
fn (mut e Emitter) assign_compound(stmt ast.Stmt, depth int) !void {
	value := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= has no value')
		return error('compound assignment without a value')
	}
	binary := value as ast.Binary
	destination := binary.left
	written := destination.typ.describe()
	if destination.typ.kind == .unknown {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= writes an object whose type this compiler cannot resolve')
		return error('unknown compound target type')
	}
	if destination is ast.Field {
		if destination.bitfield {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= to the bitfield ${destination.name}.${destination.member} is not implemented, and this back end does not step a bitfield in place')
			return error('bitfield compound assignment')
		}
	}
	if destination.typ.kind.is_complex() {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= to an object of ${written} is not implemented, and this back end keeps one value of a complex type in a register')
		return error('complex compound assignment')
	}
	if destination.typ.kind.is_extended() {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= to an object of ${written} is not one this back end makes at the width of the type')
		return error('long double compound assignment')
	}
	if destination.typ.kind in [.int128, .unsigned_int128] {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= to an object of ${written} is not implemented')
		return error('wide compound assignment')
	}
	if destination.typ.is_pointer() {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= to an object of ${written} is not implemented, and an integer added to a pointer is scaled by the size of what it points at')
		return error('pointer compound assignment')
	}
	// The address of the target, computed once and parked while the value is
	// read. The increment path computes the same address for the same shapes, so
	// it is the one used here rather than a fourth copy of that computation.
	e.inc_dec_address(destination, depth + 1)!
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	mut single := destination.typ.kind == .float
	mut double := destination.typ.kind == .double
	if destination is ast.Field {
		single = single || e.writes_a_float(destination.spelling)
		double = double || e.writes_a_double(destination.spelling)
	}
	if single || double {
		return e.assign_compound_float(stmt, binary, address, single, depth)
	}
	width := e.storage_width(destination.typ) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the compound assignment ${stmt.compound}= writes an object of ${written}, and this back end stores ints, chars, floats, doubles and pointers only')
		return error('unsupported compound width')
	}
	// The old value is read through the parked address, at the width and
	// signedness of the object. A step at the width of a word widens an operand
	// narrower than one before the operation reads it, because the load that
	// produced it left four bytes with the rest of the register cleared.
	wide := e.step_is_wide(binary)
	load_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, load_register, e.target.word_size, stmt.line, stmt.col)!
	register := e.accumulator(stmt.line, stmt.col)!
	e.load_indirect_value(load_register, register, destination.typ.is_unsigned_type(), width)!
	if wide {
		e.extend_operand_to_word(destination, stmt.line, stmt.col)!
	}
	left := e.value_slot(depth + 1)
	e.store_accumulator(left, stmt.line, stmt.col)!
	e.emit_expr_at(binary.right, depth + 2)!
	if wide && binary.op !in ['<<', '>>'] {
		e.extend_operand_to_word(binary.right, stmt.line, stmt.col)!
	}
	e.move_operand_to_scratch(binary, wide)!
	e.load_accumulator(left, stmt.line, stmt.col)!
	e.apply_binary(binary, wide)!
	e.normalize_a_bool_store(destination.typ.kind == .bool_, wide, stmt.line, stmt.col)!
	// The scratch register may have been used by the value's own expression, so
	// the address is read back into it here rather than kept across that
	// emission. The result that is written is the accumulator's, which the load
	// of the address does not touch.
	store_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, store_register, e.target.word_size, stmt.line, stmt.col)!
	result := e.accumulator(stmt.line, stmt.col)!
	e.append(e.target.store_indirect(store_register, result, width)!)
}

// assign_compound_float is assign_compound for an object in the floating-point
// file: the old value is read at the object's width, the written expression is
// converted to the same class, and the arithmetic is the instruction that class
// takes. It is the floating form of the step the expression reader makes, with
// the left operand read through the parked address instead of emitted.
fn (mut e Emitter) assign_compound_float(stmt ast.Stmt, binary ast.Binary, address Slot, single bool, depth int) !void {
	value := e.float_accumulator(stmt.line, stmt.col)!
	load_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, load_register, e.target.word_size, stmt.line, stmt.col)!
	if single {
		e.append(e.target.load_float_indirect(load_register, value)!)
	} else {
		e.append(e.target.load_double_indirect(load_register, value)!)
	}
	left := e.value_slot(depth + 1)
	e.store_float_accumulator(left, single, stmt.line, stmt.col)!
	e.emit_expr_at(binary.right, depth + 2)!
	e.convert_to_float_class(binary.right, single, stmt.line, stmt.col)!
	e.move_float_to_scratch(single, stmt.line, stmt.col)!
	e.load_float_accumulator(left, single, stmt.line, stmt.col)!
	e.apply_float(binary, single)!
	store_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, store_register, e.target.word_size, stmt.line, stmt.col)!
	if single {
		e.append(e.target.store_float_indirect(store_register, value)!)
	} else {
		e.append(e.target.store_double_indirect(store_register, value)!)
	}
}

// assign_double_at writes a double through an address, which is the floating
// file's version of the store above: the eight bytes move with the instruction
// that moves a double rather than with the integer store of the same width.
// An integer value converts to a double first; a pointer is not converted into
// one, and is refused by name rather than written as the bits of an address.
fn (mut e Emitter) assign_double_at(stmt ast.Stmt, address Slot, expr ast.Expr, depth int) !void {
	if !e.floating_of(expr) && e.is_a_pointer(expr) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored through an address of double, and there is no conversion between them')
		return error('pointer into a double')
	}
	e.emit_expr_at(expr, depth + 1)!
	e.convert_to_double(expr, stmt.line, stmt.col)!
	value := e.float_accumulator(stmt.line, stmt.col)!
	address_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_double_indirect(address_register, value)!)
}

// assign_object_local writes an object into a local object: the destination's
// address is the frame's address plus the slot's offset, parked in a value slot
// while the value is read.
fn (mut e Emitter) assign_object_local(stmt ast.Stmt, target Slot, depth int) !void {
	expr_value := stmt.expr or { return error('assignment without a value') }
	register := e.accumulator(stmt.line, stmt.col)!
	frame := e.slot_base_register(target, stmt.line, stmt.col)!
	e.append(e.target.address_of_slot(frame, target.offset, register))
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	return e.assign_object(address, target.width, expr_value, stmt.line, stmt.col, depth)
}

// assign_object_global writes an object into a top-level object: the destination's
// address is in the image, so it is a reference the layout fills in rather than an
// offset from the frame.
fn (mut e Emitter) assign_object_global(stmt ast.Stmt, object image.GlobalSlot, depth int) !void {
	expr_value := stmt.expr or { return error('assignment without a value') }
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference_object_address(register, stmt.target)
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	return e.assign_object(address, object.width, expr_value, stmt.line, stmt.col, depth)
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
fn (mut e Emitter) assign_object(address Slot, width int, expr ast.Expr, line int, col int, depth int) !void {
	if expr is ast.Call {
		if class := e.call_return_class(expr) {
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
				e.emit_expr_at(expr, depth + 1)!
				return e.copy_frame_object(e.hidden, address, class.bytes, line, col)
			}
			e.emit_expr_at(expr, depth + 1)!
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
	e.address_of_object(expr, depth + 1)!
	source := e.value_slot(depth + 1)
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
		base := e.slot_base_register(source, line, col)!
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
	if parameter := call_parameter(call, position) {
		// The callee's parameter type is the object that travels, so its class is
		// the target's answer for that type rather than a table entry.
		class := abi.class_of(e.representation, parameter)
		if class.bytes > 0 {
			return class
		}
		return none
	}
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
	if expr is ast.Comma {
		// A compound literal written where its statement does not describe a
		// single evaluation: the left operand is the stores that initialize
		// the object and the right operand names it, so the stores run first
		// and the object is what the right operand is.
		e.emit_effect(expr.left, depth + 1)!
		return e.address_of_object(expr.right, depth)
	}
	if expr is ast.Ident {
		e.address_of_member(expr.name, ?ast.Expr(none), 0, false, depth, expr.line, expr.col)!
		return
	}
	if expr is ast.Field {
		e.field_address(expr, depth, expr.line, expr.col)!
		return
	}
	if expr is ast.Index {
		// An element is at the base's value plus the index scaled by the size
		// of one element, which is the address emit_element_address computes.
		e.emit_element_address(expr, depth)!
		return
	}
	if expr is ast.Unary {
		if expr.op == '*' {
			// The address of what a pointer points at is the pointer's own
			// value, which is what the operand is worth.
			e.emit_expr_at(expr.expr, depth)!
			return
		}
	}
	if expr.typ.kind.is_complex() {
		// A complex value that is not a name, a member or an element has no
		// storage of its own: it is computed into a temporary and the address of
		// that is what the object is worth, which is what a call hands over and
		// what a return reads.
		object := e.complex_object(expr, depth + 1)!
		frame := e.frame_pointer(expr_line(expr), expr_col(expr))!
		register := e.accumulator(expr_line(expr), expr_col(expr))!
		e.append(e.target.address_of_slot(frame, i32(object.offset), register))
		return
	}
	if expr.typ.kind in [.struct_, .union_] {
		// An object of an aggregate type that is not a name, a member or an
		// element has no storage of its own: it is materialized into a
		// temporary of this level and the address of that is what the object
		// is worth. A conditional whose two arms have the same struct type is
		// the shape C99 6.5.15p3 gives that type to and 6.5.16 then assigns
		// from, and V's own generated C writes one at hello.c:2699.
		object := e.aggregate_object(expr, depth + 1)!
		frame := e.frame_pointer(expr_line(expr), expr_col(expr))!
		register := e.accumulator(expr_line(expr), expr_col(expr))!
		e.append(e.target.address_of_slot(frame, i32(object.offset), register))
		return
	}
	e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: an object handed over by value has to be a name, an element or a member, and this expression is not one')
	return error('not an object')
}

// aggregate_object evaluates an object of an aggregate type into storage and
// answers the frame slot that holds it. It is the aggregate counterpart of
// complex_object, and for the same reason: no register holds an object, so an
// expression that is not a name, a member or an element is computed into a
// temporary of this level. What makes the result a value rather than a name for
// the arm the conditional chose is that the arm's bytes are copied, which is
// the copy 6.5.16 assigns from.
fn (mut e Emitter) aggregate_object(expr ast.Expr, depth int) !Slot {
	size := e.representation.size_of(expr.typ) or {
		e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: ${expr.typ.describe()} is an object whose size this back end does not know')
		return error('unknown object size')
	}
	object := e.reserve(size)
	e.emit_aggregate_into(object, expr, depth + 1)!
	return object
}

// emit_aggregate_into writes the value of an expression of an aggregate type
// into an object the caller has reserved. A conditional is one shape: the
// condition picks an arm, and that arm's bytes are written into the destination
// so neither arm is aliased. A call is the other: what it hands back arrives in
// the registers the class names, or in the storage the call lent the callee when
// the object is more than two eightbytes, and that is a value this back end
// already knows how to write. Every other shape reaching here is an object with
// no path in this back end yet, and it is refused with the same words a name, an
// element or a member are not needed for.
fn (mut e Emitter) emit_aggregate_into(destination Slot, expr ast.Expr, depth int) !void {
	if expr is ast.Comma {
		// A compound literal written where its statement does not describe a
		// single evaluation: the left operand is the stores that initialize
		// the object, runs first, and the object is what the right operand is.
		e.emit_effect(expr.left, depth + 1)!
		return e.emit_aggregate_into(destination, expr.right, depth)
	}
	if expr is ast.Conditional {
		e.emit_condition(expr.cond, depth + 1, expr.line, expr.col)!
		else_label := e.label()
		end_label := e.label()
		e.branch(.branch_zero, else_label, expr.line, expr.col)!
		e.write_aggregate_value(destination, expr.then_expr, depth)!
		e.jump(end_label)!
		e.place(else_label)
		e.write_aggregate_value(destination, expr.else_expr, depth)!
		e.place(end_label)
		return
	}
	if expr is ast.Call {
		// A call of an aggregate type has a path: assign_object writes the
		// bytes the call hands back, and the destination's address is parked
		// for it the way the conditional's arms park it. A call with no return
		// class names no object this back end hands over, so it falls through
		// to the refusal below rather than to a copy of nothing.
		if e.call_return_class(expr) != none {
			return e.write_aggregate_value(destination, expr, depth)
		}
	}
	e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: an object handed over by value has to be a name, an element or a member, and this expression is not one')
	return error('not an object')
}

// write_aggregate_value writes one value of an aggregate type into storage this
// level reserved. The destination's address is parked in a value slot and the
// value is written through assign_object, which is the copy an assignment
// between two objects makes: a call's result arrives in the registers its class
// names and is stored, and anything else is an object of the same type whose
// bytes are read from its own address. One arm of a conditional and a call's
// result are the two values this is asked to write.
fn (mut e Emitter) write_aggregate_value(destination Slot, arm ast.Expr, depth int) !void {
	line := expr_line(arm)
	col := expr_col(arm)
	frame := e.frame_pointer(line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, i32(destination.offset), register))
	address := e.value_slot(depth)
	e.store_accumulator(address, line, col)!
	return e.assign_object(address, destination.width, arm, line, col, depth)
}

// field_address leaves the address of a member in the accumulator, whatever the
// object it is read from. A member of a name is addressed by address_of_member,
// which knows where the frame and the image keep the object. A member whose
// object is an expression - a call's result, a chained arrow, a parenthesised
// pointer, an element of an array - is addressed from the object's own address,
// or, when the access is written with `->`, from the pointer value the object is
// worth. The member's own offset into the object is added either way.
fn (mut e Emitter) field_address(field ast.Field, depth int, line int, col int) !void {
	if base := field.base {
		if field.through_pointer {
			e.emit_expr_at(base, depth + 1)!
		} else {
			e.field_object_address(base, depth + 1)!
		}
		register := e.accumulator(line, col)!
		if field.offset != 0 {
			e.append(e.target.add_immediate(register, field.offset))
		}
		return
	}
	return e.address_of_member(field.name, field.index, field.offset, field.through_pointer, depth, line, col)
}

// field_object_address leaves in the accumulator the address of the object a
// member is read from, when that object is not a name. It is address_of_object
// with one more shape: an object handed back by a call. A call of more than two
// eightbytes writes its result into the storage the caller lent it, so the
// address is that storage's. A smaller object comes back in the registers, so it
// is spilled into a slot of its own first and the member is read from there.
fn (mut e Emitter) field_object_address(expr ast.Expr, depth int) !void {
	if expr is ast.Call {
		if class := e.call_return_class(expr) {
			if class.count > 2 {
				e.emit_expr_at(expr, depth + 1)!
				register := e.accumulator(expr.line, expr.col)!
				frame := e.frame_pointer(expr.line, expr.col)!
				e.append(e.target.address_of_slot(frame, e.hidden.offset, register))
				return
			}
			temp := e.reserve(align(class.bytes, e.target.word_size))
			e.emit_expr_at(expr, depth + 1)!
			base := e.scratch(expr.line, expr.col)!
			frame := e.frame_pointer(expr.line, expr.col)!
			e.append(e.target.address_of_slot(frame, temp.offset, base))
			e.store_return_eightbyte(base, 0, e.target.word_size, class.first_floating, expr.line,
				expr.col)!
			if class.count == 2 {
				e.append(e.target.add_immediate(base, e.target.word_size))
				e.store_return_eightbyte(base, 1, class.bytes - e.target.word_size,
					class.second_floating, expr.line, expr.col)!
			}
			register := e.accumulator(expr.line, expr.col)!
			home := e.frame_pointer(expr.line, expr.col)!
			e.append(e.target.address_of_slot(home, temp.offset, register))
			return
		}
	}
	return e.address_of_object(expr, depth)
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
			frame := e.slot_base_register(slot, line, col)!
			e.append(e.target.address_of_slot(frame, slot.offset, base))
		} else if object := e.global_of(name) {
			if object.count == 0 {
				e.diagnostics << problem(line, col, 'unsupported: ${name} is read as an array, and it is not one')
				return error('not an array')
			}
			stride = object.width
			e.reference_object_address(base, name)
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
		if through_pointer {
			// The element the index names is a pointer, and `->` reads the
			// member from the object its value names: the register holds the
			// element's own storage, so the pointer is read out of it before the
			// member's byte is added. Reading the member from the storage itself
			// would answer from the pointer's bytes.
			e.load_indirect_value(register, register, false, e.target.word_size)!
		}
		if offset != 0 {
			e.append(e.target.add_immediate(register, offset))
		}
		return
	}

	slot := e.lookup(name) or {
		// A top-level object: it has no slot in the frame, so the address of the
		// member is the address of the object in the image plus the byte the
		// layout gave the member. `global_of` also lays the storage out the
		// first time the name is used, which is what an address of it needs: a
		// reference the layout fills in is meaningless until there is an object
		// to point at.
		if object := e.global_of(name) {
			register := e.accumulator(line, col)!
			e.reference_object_address(register, name)
			if through_pointer {
				// The name is a pointer at the top level, so what is in the
				// image is the address of the object: read it out of the
				// storage and the member's byte is added to that. Reading
				// through the address of the storage itself would answer from
				// the object's own bytes, which is the wrong object.
				e.load_indirect_value(register, register, object.unsigned, e.target.word_size)!
			}
			if offset != 0 {
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
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.address_of_slot(base, slot.offset + offset, register))
}

fn (mut e Emitter) assign_member(stmt ast.Stmt, member ast.Field, expr ast.Expr, depth int) !void {
	if e.writes_a_complex(member.spelling) {
		// A member of a complex type is two components inside another object,
		// and the store is the two-component copy a local of the type takes,
		// written at the member's own address. The object the member lies in
		// may be a pointer's target or a top-level object, so the store cannot
		// be an offset from the frame.
		destination := types.from_words(member.spelling.split(' ')) or {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the member ${member.name}.${member.member} is declared ${member.spelling}, and this back end has no complex type of that spelling to write')
			return error('unsupported member type')
		}
		e.field_address(member, depth + 1, stmt.line, stmt.col)!
		address := e.value_slot(depth)
		e.store_accumulator(address, stmt.line, stmt.col)!
		source := e.complex_object_as(expr, destination, depth + 1)!
		return e.copy_complex_into(address, source, destination.kind, stmt.line, stmt.col)
	}
	if e.writes_a_128(member.spelling) {
		// A member of that width takes a value narrower than it the way an object
		// of the type does, through the member's own address: the object the
		// member lies in may be a pointer's target or a top-level object, so the
		// store cannot be an offset from the frame.
		e.field_address(member, depth + 1, stmt.line, stmt.col)!
		address := e.value_slot(depth)
		e.store_accumulator(address, stmt.line, stmt.col)!
		return e.store_wide_at(address, expr, stmt.line, stmt.col, depth)
	}
	if e.writes_a_long_double(member.spelling) {
		// A member of the extended type takes a value the way an object of the
		// type does, through the member's own address: the object the member
		// lies in may be a pointer's target or a top-level object, so the store
		// cannot be an offset from the frame.
		e.field_address(member, depth + 1, stmt.line, stmt.col)!
		address := e.value_slot(depth)
		e.store_accumulator(address, stmt.line, stmt.col)!
		return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
	}
	if member.typ.kind in [types.Kind.struct_, .union_] {
		// A member of an aggregate type takes a value of its own type the way a
		// whole object does: the bytes are copied from the value's address to the
		// member's address, and neither object is read as a value. The object the
		// member lies in may be a pointer's target or a top-level object, so the
		// member is addressed through field_address the way a scalar member is,
		// and the copy is the one an aggregate assignment already makes.
		width := e.representation.size_of(member.typ) or {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the member ${member.name}.${member.member} is declared ${member.spelling}, and this back end has no size for it')
			return error('unsupported member type')
		}
		e.field_address(member, depth + 1, stmt.line, stmt.col)!
		address := e.value_slot(depth)
		e.store_accumulator(address, stmt.line, stmt.col)!
		return e.assign_object(address, width, expr, stmt.line, stmt.col, depth)
	}
	width := e.type_width(member.spelling) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the member ${member.name}.${member.member} is declared ${member.spelling}, and this back end stores ints, chars, floats, doubles and pointers only')
		return error('unsupported member type')
	}
	e.field_address(member, depth + 1, stmt.line, stmt.col)!
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	e.emit_expr_at(expr, depth + 1)!
	address_register := e.scratch(stmt.line, stmt.col)!
	member_name := '${member.name}.${member.member}'
	if member.bitfield {
		return e.assign_member_bits(stmt, member, expr, address, address_register, width,
			member_name)
	}
	if e.writes_a_float(member.spelling) {
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in the member ${member_name}, which holds a float, and there is no conversion between them')
			return error('pointer into a float')
		}
		e.convert_to_single(expr, stmt.line, stmt.col)!
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_float_indirect(address_register, value)!)
		return
	}
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
		e.convert_to_int(expr, e.written_is_unsigned(member.spelling), width, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, width)!)
		return
	}
	value_width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	// The width check is the one a store through an address makes, because that
	// is what a member store is: a constant is written at the width of the
	// member, since a constant says nothing about its own width, a value
	// narrower than the member is converted to the member's type, and a wider
	// one is refused - except into a member narrower than four bytes, where the
	// language converts an int by taking the low byte or the low two of it.
	if e.constant(expr) == none && value_width > width && !(width < 4 && value_width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored into the member ${member_name}, which holds ${width}')
		return error('width mismatch')
	}
	if width == 8 && value_width != 8 {
		// A value narrower than the member is widened into the whole register
		// before it is written, the way a store into a name of that width does:
		// the store moves eight bytes, so an int whose upper half the load
		// cleared would otherwise be written as its unsigned reading.
		e.extend_operand_to_word(expr, stmt.line, stmt.col)!
	}
	// A store into a `_Bool` member makes the value 0 or 1, which is the member's
	// own type rather than the width the store is made at.
	e.normalize_a_bool_store(e.declares_a_bool(member.spelling), value_width == 8, stmt.line,
		stmt.col)!
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, width)!)
}

// assign_member_bits writes a value into one bitfield member without touching the
// other members that share its storage unit. A whole-unit store is what the plain
// member store is and it is wrong here: two bitfields in one unit would clobber
// each other, which is a silent wrong value. Instead the unit is read, the
// field's bits are cleared, the value's bits are moved up into their place and
// ORed in, and the whole unit is written back. The address of the unit was parked
// before the value was computed, so a value that calls a function cannot lose it.
//
// The value is converted to the member's declared type the way any integer store
// into that type is, because what the field holds is a value of that type cut to
// the field's width; a `_Bool` field is made 0 or 1 first, which is the rule for
// every store into one. A storage unit wider than four bytes is refused by name:
// the field's clear mask is written as a four-byte immediate, and the eight-byte
// case would need a width this instruction does not carry, so it is named rather
// than written wrong.
fn (mut e Emitter) assign_member_bits(stmt ast.Stmt, member ast.Field, expr ast.Expr, address Slot, address_register backend.Register, width int, member_name string) !void {
	if member.unit_width <= 0 || member.unit_width > 4 {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the bitfield ${member_name} lies in a ${member.unit_width}-byte storage unit, and this back end writes a bitfield only in a unit of four bytes or fewer')
		return error('unsupported bitfield unit')
	}
	if e.floating_of(expr) {
		e.convert_to_int(expr, e.written_is_unsigned(member.spelling), width, stmt.line, stmt.col)!
	} else {
		value_width := e.width_of(expr) or {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
			return error('unknown width')
		}
		if e.constant(expr) == none && value_width > width && !(width < 4 && value_width == 4) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored into the member ${member_name}, which holds ${width}')
			return error('width mismatch')
		}
		e.normalize_a_bool_store(e.declares_a_bool(member.spelling), value_width == 8, stmt.line,
			stmt.col)!
	}
	register := e.accumulator(stmt.line, stmt.col)!
	unit_bits := member.unit_width * 8
	// Cut the value to the field's width, then move it up to where the field
	// sits, so what is ORed into the unit is exactly the field's bits and
	// nothing above them.
	if member.bit_width < unit_bits {
		e.append(e.target.and_immediate(register, i32((u64(1) << member.bit_width) - 1))!)
	}
	if member.bit_offset > 0 {
		e.append(e.target.shift_left_word(register, u8(member.bit_offset))!)
	}
	// Read the unit, clear the field's bits, OR the value's bits in, and write
	// the unit back. A field that fills the unit has nothing to clear, so the
	// clear mask is zero and the value is written as it stands.
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	unit := e.remainder(stmt.line, stmt.col)!
	e.append(e.target.load_indirect_unsigned(address_register, unit, member.unit_width)!)
	mut clear := i32(0)
	if member.bit_width < unit_bits {
		clear = i32(~(((u32(1) << member.bit_width) - 1) << member.bit_offset))
	}
	e.append(e.target.and_immediate(unit, clear)!)
	e.append(e.target.or_word(unit, register)!)
	e.append(e.target.store_indirect(address_register, unit, member.unit_width)!)
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
//
// address_only is set when the caller wants the element's address and not a value in
// it, which is what an element that is itself an array is: the row of a two- or
// three-dimensional object. Such a row is addressed like any other stride - a multiply
// and an add - and the sixteen-byte refusal does not apply, because no sixteen-byte
// load or store follows.
fn (mut e Emitter) element_address(base backend.Register, index backend.Register, stride int, offset int, wide bool, address_only bool, name string, line int, col int) !void {
	if stride == wide_bytes && !wide && !address_only {
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
fn (mut e Emitter) assign_element(stmt ast.Stmt, subscript ast.Expr, expr ast.Expr, depth int) !void {
	slot := e.lookup(stmt.target) or {
		// A top-level array is addressed from its storage in the image instead
		// of from the frame: the address of the object is what the element is an
		// offset from.
		if object := e.global_of(stmt.target) {
			if object.count == 0 {
				e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned an element of it, and it is not an array')
				return error('not an array')
			}
			e.emit_subscript_index(subscript, depth)!
			register := e.accumulator(stmt.line, stmt.col)!
			base := e.scratch(stmt.line, stmt.col)!
			e.reference_object_address(base, stmt.target)
			is_wide := !object.object && object.width == wide_bytes
			long_double := e.global_array_is_long_double(stmt.target)
			e.element_address(base, register, object.width, 0, is_wide || long_double, false, stmt.target,
				stmt.line,
				stmt.col)!
			address := e.value_slot(depth)
			e.store_accumulator(address, stmt.line, stmt.col)!
			if long_double {
				// An element of the extended type, at an address the image
				// holds: the value goes in through the path an object of the
				// type uses.
				return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
			}
			if is_wide {
				// An element of that width takes the two words an object of the type
				// takes, through the element's own address.
				return e.store_wide_at(address, expr, stmt.line, stmt.col, depth)
			}
			e.emit_expr_at(expr, depth + 1)!
			address_register := e.scratch(stmt.line, stmt.col)!
			if object.single {
				if !e.floating_of(expr) && e.is_a_pointer(expr) {
					e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in an element that holds a float, and there is no conversion between them')
					return error('pointer into a float')
				}
				e.convert_to_single(expr, stmt.line, stmt.col)!
				value := e.float_accumulator(stmt.line, stmt.col)!
				e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
				e.append(e.target.store_float_indirect(address_register, value)!)
				return
			}
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
				e.convert_to_int(expr, e.written_is_unsigned(e.global_written(stmt.target)), object.width, stmt.line, stmt.col)!
				value := e.accumulator(stmt.line, stmt.col)!
				e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
				e.append(e.target.store_indirect(address_register, value, object.width)!)
				return
			}
			width := e.width_of(expr) or {
				e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
				return error('unknown width')
			}
			// A constant is written at the width of the element, because a
			// constant says nothing about its own width: this is what a store
			// into a local already does, and an element of a top-level array is
			// the same store at an address the image holds. A value narrower
			// than the element is converted to its type, and a wider one is
			// refused, except into an element narrower than four bytes, where
			// the language converts an int by taking its low byte or its low two.
			if e.constant(expr) == none && width > object.width && !(object.width < 4 && width == 4) {
				e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${width} bytes is stored into an element of ${stmt.target}, which holds ${object.width}')
				return error('width mismatch')
			}
			if object.width == 8 && width != 8 {
				// A value narrower than the element is widened into the whole
				// register before it is written, the way a store into a name
				// of that width does: the store moves eight bytes, so a
				// negative constant whose upper half the immediate cleared
				// would otherwise be written as its unsigned reading.
				e.extend_operand_to_word(expr, stmt.line, stmt.col)!
			}
			// An element of a `_Bool` array holds 0 or 1 whatever was written
			// into it, and the type is the declaration's because the storage in
			// the image carries a width and not a signedness or a `_Bool`.
			e.normalize_a_bool_store(e.declares_a_bool(e.global_written(stmt.target)),
				width == 8, stmt.line, stmt.col)!
			value := e.accumulator(stmt.line, stmt.col)!
			e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
			e.append(e.target.store_indirect(address_register, value, object.width)!)
			return
		}
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned to, and no local of that name is in scope')
		return error('unknown assignment target')
	}
	if !slot.is_array() {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an element of ${stmt.target} is written, and ${stmt.target} is not an array')
		return error('not an array')
	}
	e.emit_subscript_index(subscript, depth)!
	register := e.accumulator(stmt.line, stmt.col)!
	mut base := e.slot_base_register(slot, stmt.line, stmt.col)!
	mut offset := slot.offset
	if slot.vla {
		// The array is not in the frame but at an address the frame holds, so
		// the base is that address rather than the frame pointer. The base goes
		// in the scratch register because the index is already in the
		// accumulator and element_address adds the two together.
		base = e.scratch(stmt.line, stmt.col)!
		e.load_vla_base(slot, base, stmt.line, stmt.col)!
		offset = 0
	}
	e.element_address(base, register, slot.width, offset, slot.wide || slot.long_double, slot.complex, stmt.target,
		stmt.line, stmt.col)!
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	if slot.long_double {
		// An element of the extended type is sixteen bytes at an address this
		// back end can compute; the value goes in through the path an object of
		// the type uses, because sixteen bytes is not a width the machine moves
		// in one instruction.
		return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
	}
	if slot.complex {
		// An element of an array of complex values is two components at an
		// address the index computed, and it takes the same two-component copy
		// a local of the type takes. The stride is the element size, so its
		// width is what says which of the two complex types this is.
		kind := if slot.width == 4 { types.Kind.complex_float } else { types.Kind.complex_double }
		source := e.complex_object_as(expr, complex_type_of(kind), depth + 1)!
		return e.copy_complex_into(address, source, kind, stmt.line, stmt.col)
	}
	if slot.wide {
		// An element of that width takes the two words an object of the type takes,
		// through the element's own address.
		return e.store_wide_at(address, expr, stmt.line, stmt.col, depth)
	}
	e.emit_expr_at(expr, depth + 1)!
	address_register := e.scratch(stmt.line, stmt.col)!
	if slot.single {
		// An element of an array of floats: the value is rounded to four bytes
		// if it is not one already, and written with the instruction that moves
		// a float rather than with the integer store, which would write the bits
		// of something that is not a float.
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in an element that holds a float, and there is no conversion between them')
			return error('pointer into a float')
		}
		e.convert_to_single(expr, stmt.line, stmt.col)!
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_float_indirect(address_register, value)!)
		return
	}
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
		e.convert_to_int(expr, slot.unsigned, slot.width, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, slot.width)!)
		return
	}
	width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	// A constant is written at the width of the element, because a constant
	// says nothing about its own width: this is what a store into a local
	// already does, and an element is the same store at a computed address. A
	// value narrower than the element is converted to its type, and a wider one
	// is refused, except into an element narrower than four bytes, where the
	// language converts an int by taking its low byte or its low two.
	if e.constant(expr) == none && width > slot.width && !(slot.width < 4 && width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${width} bytes is stored into an element of ${slot.width}')
		return error('width mismatch')
	}
	if slot.width == 8 && width != 8 {
		// A value narrower than the element is widened into the whole register
		// before it is written, the way a store into a name of that width does:
		// the store moves eight bytes, so a negative constant whose upper half
		// the immediate cleared would otherwise be written as its unsigned
		// reading.
		e.extend_operand_to_word(expr, stmt.line, stmt.col)!
	}
	// An element of a local array of `_Bool` holds 0 or 1, and the slot carries
	// that fact because the element type is what the declaration wrote.
	e.normalize_a_bool_store(slot.boolean, width == 8, stmt.line, stmt.col)!
	value := e.accumulator(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	e.append(e.target.store_indirect(address_register, value, slot.width)!)
}

// assign_subscript writes a value into the element a computed address names: the
// address is the one emit_element_address leaves, parked in a slot while the
// value is computed, and the value is written through it at the width of the
// element's type. It is the write half of the general element read, and it is
// what `3[p] = 9` and an element written through a pointer go through.
fn (mut e Emitter) assign_subscript(stmt ast.Stmt, subscript ast.Expr, expr ast.Expr, depth int) !void {
	index := subscript as ast.Index
	e.emit_element_address(index, depth + 1)!
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	address_register := e.scratch(stmt.line, stmt.col)!
	if index.typ.kind.is_extended() {
		// An element of the extended type, at an address computed from a
		// pointer: the value goes in through the path an object of the type
		// uses, and the expression has not been emitted yet because that path
		// emits it.
		return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
	}
	e.emit_expr_at(expr, depth + 1)!
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
		// The element's type is the destination, and it is resolved here, so
		// its signedness is read off it.
		e.convert_to_int(expr, index.typ.is_unsigned_type(), width, stmt.line, stmt.col)!
		value := e.accumulator(stmt.line, stmt.col)!
		e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
		e.append(e.target.store_indirect(address_register, value, width)!)
		return
	}
	value_width := e.width_of(expr) or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
		return error('unknown width')
	}
	// A constant is written at the width of the element, because a constant
	// says nothing about its own width: this is what a store into a local
	// already does, and an element reached through an address is the same store
	// at a computed address. A value narrower than the element is converted to
	// its type, and a wider one is refused, except into an element narrower than
	// four bytes, where the language converts an int by taking its low byte or
	// its low two.
	if e.constant(expr) == none && value_width > width && !(width < 4 && value_width == 4) {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a value of ${value_width} bytes is stored into an element of ${width}')
		return error('width mismatch')
	}
	if width == 8 && value_width != 8 {
		// A value narrower than the element is widened into the whole register
		// before it is written, the way a store into a name of that width does:
		// the store moves eight bytes, so a negative constant whose upper half
		// the immediate cleared would otherwise be written as its unsigned
		// reading.
		e.extend_operand_to_word(expr, stmt.line, stmt.col)!
	}
	// An element of a `_Bool` array holds 0 or 1, and the element's type is
	// resolved here, which is where the answer is read from.
	e.normalize_a_bool_store(index.typ.kind == .bool_, value_width == 8, stmt.line, stmt.col)!
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
	if expr is ast.StmtExpr {
		// A statement expression written as a statement is the construct used
		// for what its body does, which is one of the two ways gcc's assert
		// writes it: the value, when there is one, is thrown away.
		e.emit_statement_expression(expr as ast.StmtExpr, false)!
		return
	}
	if expr.typ.is_void() {
		// A void expression in a statement is evaluated for its side effects and
		// its (nonexistent) value thrown away, which is what 6.8.3 says of an
		// expression statement and 6.3.2.2 of a void expression.
		e.emit_discard(expr, 0)!
		return
	}
	e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: an expression statement is emitted when it is a call, and this one is not a call')
	return error('not a call')
}

// emit_discard evaluates a void expression for its side effects and throws the
// value away. A conversion to void and a read through an address of void are
// the two void expressions this tree has, and both throw what their operand is
// worth, so the operand is evaluated and nothing is loaded from or converted
// from it.
fn (mut e Emitter) emit_discard(expr ast.Expr, depth int) !void {
	match expr {
		ast.Cast {
			e.emit_discard_operand(expr.expr, depth + 1)!
		}
		ast.Unary {
			e.emit_expr_at(expr.expr, depth + 1)!
		}
		ast.Comma {
			// Both operands are evaluated for what they do and the value of
			// the right one is thrown away like the left's.
			e.emit_effect(expr.left, depth + 1)!
			e.emit_effect(expr.right, depth + 1)!
		}
		ast.StmtExpr {
			// The statements run for what they do and the construct's value,
			// when it has one, is thrown away.
			e.emit_statement_expression(expr, false)!
		}
		ast.Call {
			e.emit_call(expr, depth)!
		}
		ast.IncDec {
			e.emit_inc_dec(expr, depth)!
		}
		else {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: a ${expr.typ.describe()} expression in a statement is not one this back end evaluates for its side effects')
			return error('void expression shape')
		}
	}
}

// emit_effect evaluates one operand of a comma for what it does. A void operand
// is produced by the reader a void statement uses, and a value operand is
// emitted as itself with its register simply not read, which is what throwing a
// value away means.
fn (mut e Emitter) emit_effect(expr ast.Expr, depth int) !void {
	if expr.typ.is_void() {
		return e.emit_discard(expr, depth)
	}
	e.emit_expr_at(expr, depth)!
}

// emit_discard_operand evaluates the operand of a conversion to void for what it
// does and throws its value away. A name that is an object of an aggregate type
// is the one operand with nothing left to do: its value is not one a register
// holds, and reading a name is not something an expression does, so the
// conversion emits nothing. That is what makes `(void)e;` for a structure with
// no members a statement with no code, and it holds for a structure with members
// too, where reading the object as a value is not implemented for the same
// reason. Every other operand is evaluated as it would be for its value.
fn (mut e Emitter) emit_discard_operand(expr ast.Expr, depth int) !void {
	if expr is ast.Ident && expr.typ.kind in [.struct_, .union_, .array] {
		return
	}
	e.emit_expr_at(expr, depth)!
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
	e.emit_condition(cond, 0, stmt.line, stmt.col)!
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
	e.emit_condition(cond, 0, stmt.line, stmt.col)!
	e.branch(.branch_zero, end, stmt.line, stmt.col)!
	// The body can leave by jumping to either end of the loop, so both labels
	// are known while it is emitted.
	e.loops << LoopLabels{
		break_to:        end
		continue_to:     continue_to
		scopes_at_entry: e.scopes.len
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
		break_to:        end
		continue_to:     test
		scopes_at_entry: e.scopes.len
	}
	e.emit_branch_body(stmt.body)!
	e.loops.pop()
	e.place(test)
	e.emit_condition(cond, 0, stmt.line, stmt.col)!
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

// emit_jump_out writes a break or a continue, which are two different questions
// about the loop and switch statements around them.
//
// A break belongs to the innermost of either: `break` inside a loop inside a
// switch leaves the loop, because a loop encloses the break more closely than
// the switch does. A continue belongs to the innermost loop, and a switch on the
// way in is not one, so a continue inside a switch inside a loop goes round the
// loop: two functions with a switch in them and a single innermost target for
// both get that wrong in opposite directions.
fn (mut e Emitter) emit_jump_out(stmt ast.Stmt, is_break bool) !void {
	if is_break {
		if e.loops.len == 0 {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: break outside a loop or a switch')
			return error('break outside a loop or a switch')
		}
		// A break leaves the loop or switch, and with it every block it opened:
		// the storage those blocks claimed goes back before the jump, so a body
		// that declared a variable-length array does not leak it by breaking out.
		e.restore_vla_scopes_above(e.loops[e.loops.len - 1].scopes_at_entry)
		// The objects those blocks asked a cleanup for run too, for the same
		// reason: the block's own exit is not reached when control jumps out of
		// it.
		e.run_cleanups_above(e.cleanup_scopes_below(e.loops[e.loops.len - 1].scopes_at_entry))!
		e.jump(e.loops[e.loops.len - 1].break_to)!
		return
	}
	mut at := e.loops.len - 1
	for at >= 0 {
		if !e.loops[at].is_switch {
			e.restore_vla_scopes_above(e.loops[at].scopes_at_entry)
			e.run_cleanups_above(e.cleanup_scopes_below(e.loops[at].scopes_at_entry))!
			e.jump(e.loops[at].continue_to)!
			return
		}
		at--
	}
	e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: continue outside a loop')
	return error('continue outside a loop')
}

// emit_switch writes the dispatch of a switch and then its body, so that control
// falls from one case into the next the way the labels are written.
//
// The controlling expression is evaluated once, into a slot of its own, because
// the dispatch compares it once per case label and the expression is a program
// of its own: `switch (setjmp(buf))` is a call the standard requires to happen
// once and to answer the value the labels are matched against. It is widened to
// the machine's word before it is stored, so the comparisons below are word
// comparisons of values that are all sign or zero extended the same way, and a
// case value is converted to the operand's type the same way C converts it.
//
// The comparison chain is a loop and not a recursion, and it is one comparison
// per case, two for a range: the corpus writes a switch with 1023 labels and a
// few thousand is the size a switch is allowed to reach.
fn (mut e Emitter) emit_switch(stmt ast.Stmt) !void {
	cond := stmt.cond or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a switch without a controlling expression')
		return error('switch without an expression')
	}
	width := e.converted_width(cond.typ) or { e.target.word_size }
	unsigned := cond.typ.is_unsigned_type()
	e.emit_expr(cond)!
	e.extend_operand_to_word(cond, stmt.line, stmt.col)!
	operand := e.reserve(e.target.word_size)
	e.store_accumulator(operand, stmt.line, stmt.col)!
	end := e.label()
	mut cases := []CaseTarget{}
	e.collect_cases(stmt.body, mut cases)
	mut default_label := ''
	for target in cases {
		if target.is_default {
			default_label = target.label
		}
	}
	accumulator := e.accumulator(stmt.line, stmt.col)!
	other := e.scratch(stmt.line, stmt.col)!
	for target in cases {
		if target.is_default {
			continue
		}
		if target.is_range {
			// A range is `low <= v <= high`, which is two comparisons rather
			// than one per value: `case 'A' ... 'Z':` is two, and a run over a
			// 64-bit type is still two where expanding the run would be
			// millions. A value below the run or above it skips this label and
			// the dispatch goes on to the next case. The operand is reloaded
			// for the second comparison because the first leaves its answer in
			// the accumulator, which is where a comparison writes its result.
			skip := e.label()
			low := case_constant_in(target.value, width, unsigned)
			high := case_constant_in(target.high, width, unsigned)
			e.load_accumulator(operand, stmt.line, stmt.col)!
			e.append(e.target.move_immediate64(other, u64(low))!)
			if unsigned {
				e.append(e.target.compare_word_unsigned('<', accumulator, other)!)
			} else {
				e.append(e.target.compare_word('<', accumulator, other)!)
			}
			e.emit_test(cond, stmt.line, stmt.col)!
			e.branch(.branch_nonzero, skip, stmt.line, stmt.col)!
			e.load_accumulator(operand, stmt.line, stmt.col)!
			e.append(e.target.move_immediate64(other, u64(high))!)
			if unsigned {
				e.append(e.target.compare_word_unsigned('>', accumulator, other)!)
			} else {
				e.append(e.target.compare_word('>', accumulator, other)!)
			}
			e.emit_test(cond, stmt.line, stmt.col)!
			e.branch(.branch_nonzero, skip, stmt.line, stmt.col)!
			e.jump(target.label)!
			e.place(skip)
			continue
		}
		e.load_accumulator(operand, stmt.line, stmt.col)!
		e.append(e.target.move_immediate64(other, u64(case_constant_in(target.value, width, unsigned)))!)
		e.append(e.target.compare_word('==', accumulator, other)!)
		// A branch reads flags and the comparison above leaves its answer as a 0
		// or a 1 instead. The value is tested explicitly, so the branch depends
		// on that value and not on which flags happen to have survived the two
		// instructions that produced it.
		// The controlling expression is passed for its type and not for its
		// value: the accumulator holds the comparison's answer, and `cond`
		// is what says which width this test reads it at.
		e.emit_test(cond, stmt.line, stmt.col)!
		e.branch(.branch_nonzero, target.label, stmt.line, stmt.col)!
	}
	if default_label != '' {
		e.jump(default_label)!
	} else {
		e.jump(end)!
	}
	// The body runs with the switch as the break target and without a continue
	// target of its own, which is what the entry says.
	e.loops << LoopLabels{
		break_to:        end
		continue_to:     ''
		is_switch:       true
		scopes_at_entry: e.scopes.len
	}
	e.switches << SwitchState{
		cases: cases
		next:  0
	}
	e.emit_branch_body(stmt.body)!
	e.switches.pop()
	e.loops.pop()
	e.place(end)
}

// case_constant_in is a case label's constant as a value of the controlling
// expression's type, which is the conversion 6.8.4.2 asks for: the constant is
// converted to the promoted type of the controlling expression, and a value that
// does not fit wraps. Measured on gcc 16.2.1, `switch ((char)1) { case 257: }`
// warns that the value is greater than the type's maximum and matches nothing,
// and `switch (u) { case -1: }` on an `unsigned` matches when u is 4294967295.
//
// The width is the width of a value of the operand's type in a register and not
// its storage, because the operand was widened to the machine's word before it
// was stored and this is what it was widened to.
fn case_constant_in(value i64, width int, unsigned bool) i64 {
	if width >= 8 {
		return value
	}
	if width == 4 {
		return if unsigned { i64(u32(value)) } else { i64(i32(value)) }
	}
	if width == 2 {
		return if unsigned { i64(u16(value)) } else { i64(i16(value)) }
	}
	return if unsigned { i64(u8(value)) } else { i64(i8(value)) }
}

// collect_cases walks a switch body and gives every case and default label a
// machine label, in the order emission will meet them.
//
// The walk is the one emission makes: statements in the order they are written,
// a block's contents where the block is, an if's two bodies in the order they
// run, and a loop's body before its step. That order is what makes the labels
// line up with the statements, because emission consumes this list from the
// front as it places each of them.
//
// A switch inside the body is not walked into: its labels belong to it, and the
// dispatch of this one must not jump to them. The walk carries its own stack
// rather than recursing, because the depth is what the source writes.
fn (mut e Emitter) collect_cases(body []ast.Stmt, mut cases []CaseTarget) {
	mut stack := []CaseWalk{}
	if body.len > 0 {
		stack << CaseWalk{
			list: body
		}
	}
	for stack.len > 0 {
		top := stack.len - 1
		if stack[top].at >= stack[top].list.len {
			stack.pop()
			continue
		}
		at := stack[top].at
		stmt := stack[top].list[at]
		stack[top].at = at + 1
		match stmt.kind {
			.case_stmt {
				cases << CaseTarget{
					value:    stmt.case_value()
					high:     stmt.case_value_high()
					is_range: stmt.case_is_range()
					label:    e.label()
				}
			}
			.default_stmt {
				cases << CaseTarget{
					label:      e.label()
					is_default: true
				}
			}
			.switch_stmt {
				// The labels of a nested switch are its own.
			}
			.block {
				if stmt.body.len > 0 {
					stack << CaseWalk{
						list: stmt.body
					}
				}
			}
			.if_stmt {
				if stmt.else_body.len > 0 {
					stack << CaseWalk{
						list: stmt.else_body
					}
				}
				if stmt.then_body.len > 0 {
					stack << CaseWalk{
						list: stmt.then_body
					}
				}
			}
			.while_stmt {
				if stmt.step.len > 0 {
					stack << CaseWalk{
						list: stmt.step
					}
				}
				if stmt.body.len > 0 {
					stack << CaseWalk{
						list: stmt.body
					}
				}
			}
			.do_while_stmt {
				if stmt.body.len > 0 {
					stack << CaseWalk{
						list: stmt.body
					}
				}
			}
			else {}
		}
	}
}

// emit_case_label places the machine label of one case or default statement. The
// targets are consumed in the order collect_cases gave them out, which is the
// order the statements are emitted, so the label this statement settles is the
// one the dispatch jumps to for its value. A label with no target left, or one
// whose kind does not match the target it reached, means the walk and the
// emission disagree, and that is reported rather than papered over.
fn (mut e Emitter) emit_case_label(stmt ast.Stmt, is_default bool) !void {
	if e.switches.len == 0 {
		e.diagnostics << problem(stmt.line, stmt.col, 'internal: a case label is being emitted outside a switch')
		return error('case label outside a switch')
	}
	at := e.switches.len - 1
	state := e.switches[at]
	if state.next >= state.cases.len {
		e.diagnostics << problem(stmt.line, stmt.col, 'internal: a switch has more case labels than its dispatch was built from')
		return error('case label with no target')
	}
	target := state.cases[state.next]
	e.switches[at].next = state.next + 1
	if target.is_default != is_default {
		e.diagnostics << problem(stmt.line, stmt.col, 'internal: the case labels of a switch do not line up with its dispatch')
		return error('case label out of line')
	}
	e.place(target.label)
}

// emit_goto writes a jump to a named label. The label is created here if no
// label statement has placed it yet, which is what a forward jump is: the label
// table is settled once every label of the file is known, so a jump may be
// written before the place it lands on. What is not settled until then is
// whether a label of that name is written at all.
fn (mut e Emitter) emit_goto(stmt ast.Stmt) !void {
	if target := stmt.goto_expr() {
		// A computed goto jumps to the address the expression is worth, so the
		// value is evaluated and the machine jumps to the register holding it.
		// The named-label machinery is not involved: the program wrote an
		// address and not a name, and whether that address names a label of
		// this function is not a question the compiler asks, which is what gcc
		// does with `goto *p` as well. No variable-length array's stack is
		// given back, because there is no label name to say which scope the
		// target is in; gcc leaves that to the program too.
		e.emit_expr(target)!
		register := e.accumulator(stmt.line, stmt.col)!
		e.append(e.target.jump_register(register)!)
		return
	}
	label := stmt.label()
	if !(label in e.goto_used) {
		e.goto_used[label] = LabelUse{
			line: stmt.line
			col:  stmt.col
		}
	}
	// A goto that leaves a block which claimed a variable-length array's storage
	// gives that storage back before it jumps, because the block's own exit is not
	// reached. The label's enclosing scopes are a prefix of the goto's, so the
	// count of them names the innermost one the label sits in and the stack
	// pointer is put back to what that scope saved. A label inside no such scope
	// takes the outermost one, whose saved value is the frame's own stack
	// pointer.
	mut active := []int{}
	for offset in e.vla_saves {
		if offset != vla_no_save {
			active << offset
		}
	}
	if active.len > 0 {
		enclosing := e.vla_label_counts[label]
		mut at := 0
		if enclosing > 0 {
			at = enclosing - 1
			if at >= active.len {
				at = active.len - 1
			}
		}
		e.restore_stack_pointer(active[at])
	}
	// A goto that leaves a block whose objects asked a cleanup for one runs them
	// before it jumps, in the order the blocks were entered, innermost first. The
	// label's enclosing blocks are a prefix of the goto's, so the count of the
	// ones that declared such an object names what is being left behind. A label
	// this function does not define has no count, and the undefined label is
	// reported where the function's labels are placed.
	if e.cleanups_live() {
		e.run_cleanups_above(e.cleanup_label_counts[label])!
	}
	e.jump(e.named_label(label))!
}

// emit_label places the label a goto jumps to. Two labels of one name in a
// function are refused, which is what gcc reports as a duplicate label: a name
// for two places is not a name.
fn (mut e Emitter) emit_label(stmt ast.Stmt) !void {
	label := stmt.label()
	if e.goto_placed[label] {
		e.diagnostics << problem(stmt.line, stmt.col, 'duplicate label ${label}')
		return error('duplicate label')
	}
	name := e.named_label(label)
	e.place(name)
	e.goto_placed[label] = true
}

// named_label is the machine label a function's named label is emitted at,
// created the first time the name is met so that a goto written before the label
// and one written after it are the same label.
fn (mut e Emitter) named_label(name string) string {
	if existing := e.goto_labels[name] {
		return existing
	}
	created := e.label()
	e.goto_labels[name] = created
	return created
}

// report_undefined_labels refuses a goto whose label the function never writes.
// The jump itself is an instruction to a label the file does not hold, so the
// image is not written at all; the label is still placed here, so that the
// layout stage has one to resolve and the refusal is the diagnostic rather than
// a crash in a stage below it.
fn (mut e Emitter) report_undefined_labels() {
	for name, used in e.goto_used {
		if name in e.goto_placed {
			continue
		}
		e.diagnostics << problem(used.line, used.col, 'unsupported: label ${name} is used but not defined')
		e.place(e.named_label(name))
	}
}

// known_aggregate_bytes answers the storage an object of an aggregate type takes
// when the model laid the type out, and none when the declaration is not such an
// object. A struct or union the reader completed has a size the model worked out,
// which is zero for a structure with no members; everything else - a scalar, a
// pointer, an array - the back end sizes from its spelling, and a type the model
// never completed has no size to answer. The two are told apart here so that a
// measured zero is not read as a spelling with no width.
fn (e Emitter) known_aggregate_bytes(typ types.Type) ?int {
	if typ.kind !in [types.Kind.struct_, .union_] || !typ.is_complete() {
		return none
	}
	return e.representation.size_of(typ)
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
fn (mut e Emitter) declare(name string, written string, count int, bytes int, stride int, line int, col int, measured bool) !Slot {
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
	// A long double is the other object sized by a width rather than by a value:
	// sixteen bytes, the format's own size, and a slot whose name is the address
	// of the object for the same reason a 128-bit one is.
	long_double := bytes == 0 && e.writes_a_long_double(written)
	// An object of an aggregate type is sized by the layout the reader worked
	// out rather than by its spelling: `struct S` is a name the back end has no
	// width for, and the members are what say how many bytes the object is.
	// stride is the size of one element of an array declaration, which for an
	// array of arrays is the whole row and larger than the scalar spelling: it
	// is what an index scales by and what the count reserves together. It is
	// zero for a declaration that is not an array.
	// measured says bytes is the size the model gave an aggregate object and
	// not the fallback zero a declaration the back end sizes from its spelling
	// leaves behind. The two are told apart because a structure with no members
	// is a complete object of zero bytes: `struct empty e;` is storage nothing
	// occupies, and the classifier below would otherwise read the zero as a
	// spelling it has no width for. See known_aggregate_bytes.
	width := if stride > 0 {
		stride
	} else if bytes > 0 {
		bytes
	} else if measured {
		0
	} else if wide {
		wide_bytes
	} else if long_double {
		long_double_bytes
	} else {
		e.type_width(written) or {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is declared ${written}, and this back end stores ints, chars, floats, doubles and pointers only')
			return error('unsupported type')
		}
	}
	slot := if count > 0 { e.reserve(count * width) } else { e.reserve(width) }
	block := Slot{
		offset:      slot.offset
		width:       width
		count:       count
		floating:    bytes == 0 && e.writes_a_double(written)
		single:      bytes == 0 && e.writes_a_float(written)
		unsigned:    e.written_is_unsigned(written)
		boolean:     written == '_Bool'
		bytes:       if wide { wide_bytes } else { bytes }
		wide:        wide
		long_double: long_double
		offset:      slot.offset
		width:       width
		count:       count
		floating:    bytes == 0 && e.writes_a_double(written)
		single:      bytes == 0 && e.writes_a_float(written)
		unsigned:    e.written_is_unsigned(written)
		boolean:     written == '_Bool'
		bytes:       if wide { wide_bytes } else { bytes }
		wide:        wide
		complex:     e.writes_a_complex(written)
	}
	e.scopes[e.scopes.len - 1][name] = block
	return block
}

// declare_vla gives a variable-length array's declaration its place: two words in
// the frame, one for the address of the first element and one for the size in
// bytes, because the array itself is claimed on the stack when the declaration
// runs and not reserved here. elem is the size of one element, which is what an
// index scales by. The name is an array to every reader of the slot, and vla is
// what says its storage is somewhere the frame's fixed size does not reach.
fn (mut e Emitter) declare_vla(name string, elem int, line int, col int) !Slot {
	if e.scopes.len > 0 {
		if name in e.scopes[e.scopes.len - 1] {
			e.diagnostics << problem(line, col, 'unsupported: ${name} is declared twice in the same block')
			return error('redeclared')
		}
	}
	if elem <= 0 {
		e.diagnostics << problem(line, col, 'internal: ${name} is a variable-length array of elements with no size')
		return error('no element size')
	}
	base := e.reserve(e.target.word_size)
	size := e.reserve(e.target.word_size)
	block := Slot{
		width:    elem
		count:    -1
		vla:      true
		vla_base: base.offset
		vla_size: size.offset
	}
	e.scopes[e.scopes.len - 1][name] = block
	return block
}

// load_vla_base leaves the address a variable-length array's first element is at in
// a register. The address was stored when the declaration ran, because the frame
// the object lives in was not known before that: it is what the stack pointer
// became after the declaration subtracted the object's size from it.
fn (mut e Emitter) load_vla_base(slot Slot, register backend.Register, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.load_slot(base, i32(slot.vla_base), register, e.target.word_size)!)
}

// writes_a_complex says whether a spelling names an object of a complex type.
// The spelling is what a declaration carries and not the resolved type, so the
// words are read the same way the reader read them: `double _Complex` and
// `_Complex` are both a `double _Complex`, `float _Complex` is the other, and
// `long double _Complex` is the extended one, whose components are sixteen bytes
// each.
fn (e Emitter) writes_a_complex(written string) bool {
	typ := types.from_words(written.split(' ')) or { return false }
	return typ.kind in [types.Kind.complex_float, types.Kind.complex_double,
		types.Kind.complex_long_double]
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
	if written == 'int' || written == 'unsigned' || written == 'unsigned int' || written == 'signed' {
		return 4
	}
	// The extended complex type is the one complex spelling whose width is not
	// read off a component the machine moves in one instruction: it is two
	// sixteen-byte components. The questions above answer the smaller complex
	// types through the class the aggregate path gives them, but their slot is
	// still sized here, and this is the width of the largest of the three.
	if typ := types.from_words(written.split(' ')) {
		if typ.kind == .complex_long_double {
			return complex_long_double_bytes
		}
	}
	if written == 'char' {
		return 1
	}
	// The narrow integer types. `_Bool` and the two character types are one
	// byte each, and `short` and `unsigned short` are two whatever order their
	// words were written in. The spelling is what a declaration carries, so the
	// words a file may write are each listed. Measured on gcc 16.2.1 on this
	// target: `sizeof(_Bool)`, `sizeof(signed char)` and `sizeof(unsigned char)`
	// are 1, and `sizeof(short)` and `sizeof(unsigned short)` are 2.
	if written == '_Bool' || written == 'signed char' || written == 'unsigned char' {
		return 1
	}
	if written == 'short' || written == 'short int' || written == 'signed short'
		|| written == 'signed short int' || written == 'unsigned short'
		|| written == 'unsigned short int' {
		return 2
	}
	if written == 'double' {
		return 8
	}
	// A long double is the extended format: sixteen bytes of storage. Measured
	// on gcc 16.2.1 on this target, `sizeof(long double)` is 16 and so is
	// `_Alignof(long double)`, which is the size the model lays an object of the
	// type out with; the back end needs the same number here for the storage of
	// a top-level object and for the width of the sixteen bytes a copy moves.
	if written == 'long double' || written == '__float128' {
		return long_double_bytes
	}
	if written == 'float' {
		return 4
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

// writes_a_float says whether a type as it was written names a float. It is the
// four-byte member of the same register file a double travels in, so every
// question about which file a value lives in answers yes for both and the two
// are told apart by this and by width alone. A pointer to one is a pointer: the
// name is the type without a star, and a spelling carrying one is refused here
// for the reason writes_a_128 refuses it.
fn (e Emitter) writes_a_float(written string) bool {
	return written == 'float'
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

// written_is_unsigned says whether a type as it was written names an unsigned
// integer type. The reader has already resolved every spelling this asks about,
// so this asks the same question it did and not a second reading of the text:
// `unsigned` and `unsigned int` are one type, and neither is `unsigned long`.
fn (e Emitter) written_is_unsigned(written string) bool {
	typ := types.from_words(written.split(' ')) or { return false }
	return typ.is_unsigned_type()
}

// declares_a_bool says whether a written type is `_Bool`, which is the question a
// store into that object turns on: 6.3.1.2 makes the object hold 0 or 1 whatever
// was written into it, and that is a step the width of the object does not ask
// for.
fn (e Emitter) declares_a_bool(written string) bool {
	typ := types.from_words(written.split(' ')) or { return false }
	return typ.kind == .bool_
}

// normalize_a_bool_store makes the value in the accumulator 0 or 1 when the object
// it is about to be stored into is a `_Bool`. The rule holds for every store into
// one and not only the ones a frame slot or a conversion goes through: a member,
// an element of an array and a top-level object each hold 0 or 1 after a store,
// and gcc 16.2.1 leaves 1 for `s.b = 3` and for `a[0] = 2`. The word flag says the
// value arrived as a whole 64-bit register, where a test of four bytes would call
// a value of 2^32 zero.
fn (mut e Emitter) normalize_a_bool_store(boolean bool, word bool, line int, col int) !void {
	if !boolean {
		return
	}
	register := e.accumulator(line, col)!
	e.narrow_register(.bool_, register, word)!
}

// normalize_a_bool_value makes the value just computed 0 or 1 in the
// accumulator, which is what a conversion to `_Bool` is: 6.3.1.2 asks whether
// the value compares equal to zero and not what its low byte holds. A value
// eight bytes wide is tested as a whole word, so `_Bool b = 1ULL << 40` leaves 1
// where a four-byte test of the low half answers zero, and an address whose low
// four bytes are zero is not called null. A floating value is compared with zero
// in the floating-point file, which is the comparison a condition already makes,
// so `_Bool b = 0.5` leaves 1 where truncating to an integer leaves zero; a long
// double is refused there by name, because a truth test on one is not a
// comparison this back end writes.
fn (mut e Emitter) normalize_a_bool_value(value ast.Expr, line int, col int) !void {
	if e.floating_of(value) || e.long_double_of(value) {
		// emit_test compares the value with zero and leaves 0 or 1 in the
		// accumulator, and refuses a long double by name.
		return e.emit_test(value, line, col)
	}
	register := e.accumulator(line, col)!
	word := e.eight_byte_integer(value.typ) || e.is_a_pointer(value)
	return e.narrow_register(.bool_, register, word)
}

// normalize_a_bool_constant is the value a `_Bool` object is defined with: 6.3.1.2
// makes the object hold 0 or 1 whatever constant the declaration wrote, so
// `_Bool g = 2;` holds 1 and not 2, which is what gcc 16.2.1 leaves in the image.
fn (e Emitter) normalize_a_bool_constant(written string, value i64) i64 {
	if e.declares_a_bool(written) && value != 0 {
		return 1
	}
	return value
}

// global_written is the type a top-level object was declared with, as it was
// written. The object's storage in the image carries a width and not a type, so a
// value stored into it reads the signedness off the declaration.
fn (e Emitter) global_written(name string) string {
	if global := e.global_definition(name) {
		return global.typ
	}
	return ''
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
	level := depth + e.slot_base
	for e.values.len <= level {
		e.values << e.reserve(e.target.word_size)
	}
	return e.values[level]
}

// callee_slot is the frame slot a call through an expression keeps the address
// it calls in while the arguments are evaluated and the argument registers are
// loaded. It is keyed by depth the way a value slot is, so a call nested in the
// argument of another call gets a slot of its own, but it is a separate list:
// an argument is emitted into the value slot of its own depth, and the address
// this slot holds has to survive all of them.
fn (mut e Emitter) callee_slot(depth int) Slot {
	level := depth + e.slot_base
	for e.callees.len <= level {
		e.callees << e.reserve(e.target.word_size)
	}
	return e.callees[level]
}

// push_scope opens a block and pop_scope closes it. Names are found in the
// blocks being emitted, innermost first, so a declaration inside a block
// shadows one outside it and does not outlive it.
fn (mut e Emitter) push_scope() {
	e.scopes << map[string]Slot{}
	e.vla_saves << vla_no_save
	e.cleanups << []Cleanup{}
}

fn (mut e Emitter) pop_scope() {
	// The objects a block declared with `__attribute__((cleanup(name)))` run
	// where the block ends, a block at a time and within one block in reverse
	// declaration order, before the block's storage goes back. A call that
	// cannot be written has already recorded its diagnostic, and the run fails
	// on that rather than on a missing instruction, so the error is not carried
	// out of a function every scope's exit would otherwise have to be fallible
	// through.
	if e.cleanups.len > 0 {
		e.run_cleanups_of_scope(e.cleanups.len - 1) or {}
	}
	// A block that claimed a variable-length array's storage gives it back where
	// the block ends: the stack pointer goes back to what it was before the
	// block's first such declaration subtracted from it, so a loop whose body
	// declares one does not grow the stack every time round.
	if e.vla_saves.len > 0 {
		offset := e.vla_saves[e.vla_saves.len - 1]
		if offset != vla_no_save {
			e.restore_stack_pointer(offset)
		}
		e.vla_saves.pop()
	}
	if e.cleanups.len > 0 {
		e.cleanups.pop()
	}
	e.scopes.pop()
}

// restore_stack_pointer puts the stack pointer back to the value a block saved in
// a frame slot before it claimed a variable-length array's storage. That word is
// written by the declaration and read here, at the block's exit or on the way out
// of it, and it is the whole of what giving the storage back costs.
fn (mut e Emitter) restore_stack_pointer(offset int) {
	base := e.target.frame_pointer() or { return }
	stack := e.target.stack_pointer() or { return }
	bytes := e.target.load_slot(base, i32(offset), stack, e.target.word_size) or { return }
	e.append(bytes)
}

// restore_vla_scopes_above gives back the storage every variable-length array
// scope opened at or above depth claimed, which is what a break, a continue or a
// goto leaving those scopes has to do before it jumps. The outermost such scope
// is the one restored: its saved pointer is the lowest of them, so putting the
// stack pointer back to it gives every inner one back at once.
fn (mut e Emitter) restore_vla_scopes_above(depth int) {
	mut at := depth
	for at < e.vla_saves.len {
		if e.vla_saves[at] != vla_no_save {
			e.restore_stack_pointer(e.vla_saves[at])
			return
		}
		at++
	}
}

// run_cleanups_of_scope runs the objects one block declared with
// `__attribute__((cleanup(name)))`, in reverse declaration order, which is the
// order GCC 6.4.1 gives them.
fn (mut e Emitter) run_cleanups_of_scope(at int) !void {
	if at < 0 || at >= e.cleanups.len {
		return
	}
	list := e.cleanups[at]
	mut i := list.len - 1
	for i >= 0 {
		e.emit_cleanup_call(list[i])!
		i--
	}
}

// run_cleanups_above runs every cleanup block after the `enclosing`-th one that
// has any, innermost first. `enclosing` is how many such blocks the place
// control is going to sits inside, so what runs is the blocks being left behind:
// every block for a return, and the blocks between a goto and its target, a
// break and its loop, or a continue and its loop.
fn (mut e Emitter) run_cleanups_above(enclosing int) !void {
	mut declared := []int{}
	for at, list in e.cleanups {
		if list.len > 0 {
			declared << at
		}
	}
	mut i := declared.len - 1
	for i >= enclosing {
		e.run_cleanups_of_scope(declared[i])!
		i--
	}
}

// cleanup_scopes_below is how many cleanup blocks lie below a scope depth, which
// is what a break or a continue leaving that depth has to run.
fn (e Emitter) cleanup_scopes_below(depth int) int {
	mut count := 0
	for at := 0; at < depth && at < e.cleanups.len; at++ {
		if e.cleanups[at].len > 0 {
			count++
		}
	}
	return count
}

// cleanups_live says whether any block being emitted declared an object with a
// cleanup attribute. It is the question a return turns on, and the one the
// pre-pass that counted the blocks around each label was worth running for.
fn (e Emitter) cleanups_live() bool {
	for list in e.cleanups {
		if list.len > 0 {
			return true
		}
	}
	return false
}

// emit_cleanup_call writes the call a cleanup attribute asks for: the named
// function with the address of the object. GCC 6.4.1 gives the function one
// parameter, a pointer to a type compatible with the object, and the address is
// the same one `&object` writes anywhere else.
fn (mut e Emitter) emit_cleanup_call(c Cleanup) !void {
	object := ast.Expr(ast.Ident{
		name: c.name
		typ:  c.typ
		line: c.line
		col:  c.col
	})
	address := ast.Expr(ast.Unary{
		op:   '&'
		expr: object
		typ:  types.pointer_to(c.typ)
		line: c.line
		col:  c.col
	})
	call := ast.Expr(ast.Call{
		name: c.function
		args: [address]
		typ:  types.void_type()
		line: c.line
		col:  c.col
	})
	e.emit_expression_statement(ast.Stmt{
		kind: .expr_stmt
		expr: call
		line: c.line
		col:  c.col
	})!
}

// VlaCounter counts, for each named label of a function, how many scopes that
// declared a variable-length array enclose it. active has one entry per scope
// being walked, in the nesting order emission uses, and says whether that scope
// has declared one yet. A scope's entry becomes true when its first such
// declaration is met, because a label written before a declaration is not
// enclosed by the storage that declaration claims.
struct VlaCounter {
mut:
	active []bool
	counts map[string]int
}

// vla_label_counts walks a function body and answers, for every named label, how
// many variable-length array scopes enclose it. The walk is the one emission
// makes — statements in order, a block's contents where the block is, an if's two
// arms, a loop's body before its step — so a count names the scope emission will
// have on its stack when the label is reached.
fn vla_label_counts(body []ast.Stmt) map[string]int {
	mut counter := VlaCounter{
		counts: map[string]int{}
	}
	counter.scope(body)
	return counter.counts
}

fn (mut c VlaCounter) scope(stmts []ast.Stmt) {
	c.active << false
	for stmt in stmts {
		c.statement(stmt)
	}
	c.active.pop()
}

fn (mut c VlaCounter) statement(stmt ast.Stmt) {
	match stmt.kind {
		.block { c.scope(stmt.body) }
		.var_decl {
			if stmt.decl_vla_size() != none && c.active.len > 0 {
				c.active[c.active.len - 1] = true
			}
		}
		.if_stmt {
			if stmt.then_body.len > 0 {
				c.scope(stmt.then_body)
			}
			if stmt.else_body.len > 0 {
				c.scope(stmt.else_body)
			}
		}
		.while_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
			// A for loop's step runs in the scope around the loop, which is where
			// emission writes it, so it is walked without opening a scope.
			for step in stmt.step {
				c.statement(step)
			}
		}
		.do_while_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
		}
		.switch_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
		}
		.label_stmt {
			mut enclosing := 0
			for declared in c.active {
				if declared {
					enclosing++
				}
			}
			c.counts[stmt.label()] = enclosing
		}
		else {}
	}
}

// function_has_vla says whether any statement in a function declares a
// variable-length array, so that the label pre-pass runs only where a goto could
// have storage to give back.
fn function_has_vla(stmts []ast.Stmt) bool {
	for stmt in stmts {
		if statement_has_vla(stmt) {
			return true
		}
	}
	return false
}

fn statement_has_vla(stmt ast.Stmt) bool {
	match stmt.kind {
		.block { return function_has_vla(stmt.body) }
		.var_decl { return stmt.decl_vla_size() != none }
		.if_stmt { return function_has_vla(stmt.then_body) || function_has_vla(stmt.else_body) }
		.while_stmt { return function_has_vla(stmt.body) || function_has_vla(stmt.step) }
		.do_while_stmt { return function_has_vla(stmt.body) }
		.switch_stmt { return function_has_vla(stmt.body) }
		else { return false }
	}
}

// CleanupCounter counts, for each named label of a function, how many blocks
// that declared an object with a cleanup attribute enclose it. It is the walk
// VlaCounter makes over a different mark, and the reason is the same: a goto
// that leaves such a block runs what the block asked for before it jumps, and
// the count of them names which blocks are being left.
struct CleanupCounter {
mut:
	active []bool
	counts map[string]int
}

fn cleanup_label_counts(body []ast.Stmt) map[string]int {
	mut counter := CleanupCounter{
		counts: map[string]int{}
	}
	counter.scope(body)
	return counter.counts
}

fn (mut c CleanupCounter) scope(stmts []ast.Stmt) {
	c.active << false
	for stmt in stmts {
		c.statement(stmt)
	}
	c.active.pop()
}

fn (mut c CleanupCounter) statement(stmt ast.Stmt) {
	match stmt.kind {
		.block { c.scope(stmt.body) }
		.var_decl {
			if stmt.cleanup() != '' && c.active.len > 0 {
				c.active[c.active.len - 1] = true
			}
		}
		.if_stmt {
			if stmt.then_body.len > 0 {
				c.scope(stmt.then_body)
			}
			if stmt.else_body.len > 0 {
				c.scope(stmt.else_body)
			}
		}
		.while_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
			// A for loop's step runs in the scope around the loop, which is
			// where emission writes it, so it is walked without opening a scope.
			for step in stmt.step {
				c.statement(step)
			}
		}
		.do_while_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
		}
		.switch_stmt {
			if stmt.body.len > 0 {
				c.scope(stmt.body)
			}
		}
		.label_stmt {
			mut enclosing := 0
			for declared in c.active {
				if declared {
					enclosing++
				}
			}
			c.counts[stmt.label()] = enclosing
		}
		else {}
	}
}

// function_has_cleanups says whether any statement in a function declares an
// object with a cleanup attribute, so that the label pre-pass runs only where a
// goto could have a call to make before it jumps.
fn function_has_cleanups(stmts []ast.Stmt) bool {
	for stmt in stmts {
		if statement_has_cleanups(stmt) {
			return true
		}
	}
	return false
}

fn statement_has_cleanups(stmt ast.Stmt) bool {
	match stmt.kind {
		.block { return function_has_cleanups(stmt.body) }
		.var_decl { return stmt.cleanup() != '' }
		.if_stmt {
			return function_has_cleanups(stmt.then_body) || function_has_cleanups(stmt.else_body)
		}
		.while_stmt { return function_has_cleanups(stmt.body) || function_has_cleanups(stmt.step) }
		.do_while_stmt { return function_has_cleanups(stmt.body) }
		.switch_stmt { return function_has_cleanups(stmt.body) }
		else { return false }
	}
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
fn (mut e Emitter) emit_test(value ast.Expr, line int, col int) !void {
	if e.long_double_of(value) {
		// The truth value of a long double is its comparison with zero, which
		// the x87 stack makes in the long-double file; the value's address is
		// in the accumulator, where the comparison reads it.
		return e.emit_extended_test(line, col)
	}
	register := e.accumulator(line, col)!
	if e.floating_of(value) {
		// Zero is the other operand, in the scratch register of the same file,
		// and the comparison is the one for the width: comparing a float's four
		// bytes with Comisd would read the bits above the value as part of it,
		// and a float zero with anything but zeros above it would answer as
		// though it were not zero.
		zero := e.float_scratch(line, col)!
		floating := e.float_accumulator(line, col)!
		other := e.scratch(line, col)!
		e.append(e.target.zero_double(zero)!)
		if e.single_of(value) {
			e.append(e.target.float_comparison('!=', floating, zero, register, other)!)
		} else {
			e.append(e.target.double_comparison('!=', floating, zero, register, other)!)
		}
	}
	if e.eight_byte_integer(value.typ) || e.is_a_pointer(value) {
		// A pointer is tested at the width of an address and not at the width
		// of an int, because the low four bytes of 0x100000000 are zero: a
		// four-byte test calls that pointer, which is not null, equal to the
		// null pointer. Measured with gcc 16.2.1, `int *p =
		// (int *)0x100000000ULL; if (p)` takes the branch there; a four-byte
		// test here did not, and a truth value for a pointer is the answer
		// this tree treats as its worst bug rather than a near miss.
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

// static_chain is the register a nested function is handed the frame pointer of
// the function it is written in through, and the one a call to a nested function
// puts it in. It is asked here rather than at each use so that the machine's
// answer and the diagnostic for a machine that has none are in one place.
fn (mut e Emitter) static_chain(line int, col int) !backend.Register {
	return e.target.static_chain() or {
		e.diagnostics << problem(line, col, "${e.target.name}: the machine's table has no register for the static chain, and a nested function has no enclosing frame to reach without one")
		return error('no static chain register')
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

// store_register writes a register into a slot at the slot's width. A slot
// holding a `_Bool` converts the value on the way in: 6.3.1.2 says every store
// into one makes the value 0 or 1, so `_Bool b = 42;` leaves 1 and not 42.
fn (mut e Emitter) store_register(slot Slot, register backend.Register, line int, col int) !void {
	if slot.boolean {
		e.append(e.target.test(register)!)
		e.append(e.target.set_condition(backend.Condition.not_equal, register)!)
		e.append(e.target.widen_byte(register)!)
	}
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.store_slot(base, slot.offset, register, slot.width)!)
}

// store_accumulator writes the accumulator into a slot, at the slot's width.
fn (mut e Emitter) store_accumulator(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	e.store_register(slot, register, line, col)!
}

// load_accumulator reads a slot into the accumulator, at the slot's width. A
// one- or two-byte value is widened by the read, with its sign or, for a slot
// whose type is unsigned, with zero above it.
fn (mut e Emitter) load_accumulator(slot Slot, line int, col int) !void {
	register := e.accumulator(line, col)!
	base := e.slot_base_register(slot, line, col)!
	if slot.unsigned && slot.width < 4 {
		e.append(e.target.load_slot_unsigned(base, slot.offset, register, slot.width)!)
		return
	}
	e.append(e.target.load_slot(base, slot.offset, register, slot.width)!)
}

// load_argument reads one argument slot into the register that carries that
// position, at the width the argument is passed at. A char or a short argument is
// read at its own width whatever width the call asks for, because the read is
// what widens it: four bytes from a one-byte slot would take the padding with
// them.
fn (mut e Emitter) load_argument(slot Slot, register backend.Register, width int, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	if slot.width < 4 {
		if slot.unsigned {
			e.append(e.target.load_slot_unsigned(base, slot.offset, register, slot.width)!)
			return
		}
		e.append(e.target.load_slot(base, slot.offset, register, slot.width)!)
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
	base := e.slot_base_register(slot, line, col)!
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
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.load_double_slot(base, slot.offset, register)!)
}

// load_double_argument reads an argument slot into the floating-point register
// that carries its position. It mirrors load_argument, and a double is always
// eight bytes wide, so there is no promotion to take into account here.
fn (mut e Emitter) load_double_argument(slot Slot, register backend.Register, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.load_double_slot(base, slot.offset, register)!)
}

// The same four moves at four bytes, for a slot that holds a float. They are
// separate functions rather than a width parameter on the ones above because the
// instruction is a different one at this width, and every caller of one of these
// has already decided which width the value is.
fn (mut e Emitter) store_single_register(slot Slot, register backend.Register, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.store_float_slot(base, slot.offset, register)!)
}

fn (mut e Emitter) store_single_accumulator(slot Slot, line int, col int) !void {
	register := e.float_accumulator(line, col)!
	e.store_single_register(slot, register, line, col)!
}

fn (mut e Emitter) load_single_accumulator(slot Slot, line int, col int) !void {
	register := e.float_accumulator(line, col)!
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.load_float_slot(base, slot.offset, register)!)
}

fn (mut e Emitter) load_single_argument(slot Slot, register backend.Register, line int, col int) !void {
	base := e.slot_base_register(slot, line, col)!
	e.append(e.target.load_float_slot(base, slot.offset, register)!)
}

// floating_of says whether an expression's value travels in the floating-point
// register file, which both of the floating types do: a float and a double are
// one class of storage and two widths, and this is the question of the class.
// The width is asked separately, by single_of, and the places that compute with
// a value ask both because the instruction that adds a float is not the
// instruction that adds a double.
//
// A constant written as one, a name whose storage holds one, a call that returns
// one, and an operation on one all answer yes, while a comparison answers an int
// however its operands are spelled.
//
// The clause the parser resolved is the answer where there is one. An operation
// is asked its own type rather than its operands, which is the difference between
// one lookup and a descent per term: measured, the chain `1 + 1 + ... + 1` of
// twenty thousand terms is folded into one constant by the emitter, and asking its
// operands term by term instead took the stack out in this function before the
// fold could run.
//
// A tree assembled by hand carries no clause, so the shape is asked instead, down
// to the depth the emitter's own walk stops at: a floating constant is a floating
// value, a name is one if its slot is, and a call is one if the function returns
// one. A tree this reader cannot type is then not a tree that can take the stack
// out either.
fn (e Emitter) floating_of(expr ast.Expr) bool {
	return e.floating_at(expr, 0)
}

// single_of says whether an expression's value is a float rather than a double:
// four bytes in the same register file, which is what decides the width of the
// instruction that moves or computes with it.
//
// It is written as the same walk floating_of makes, case by case, so that the
// two agree on every shape: a value answers single_of only where it answers
// floating_of, and double_of is the difference between them. That is what makes
// `double_of` a usable question rather than a fourth walk with its own bugs.
fn (e Emitter) single_of(expr ast.Expr) bool {
	return e.single_at(expr, 0)
}

// double_of is the eight-byte member of the floating-point class: the class an
// operation on it is computed in, and the class the other operand is converted
// to when one is on either side.
fn (e Emitter) double_of(expr ast.Expr) bool {
	return e.floating_of(expr) && !e.single_of(expr)
}

fn (e Emitter) floating_at(expr ast.Expr, depth int) bool {
	if depth > max_emit_depth {
		return false
	}
	// A long double is a floating type in the language and not a value of the
	// register file this walk is about: it lives in memory, so no path that asks
	// this question computes with it. The guard is here rather than in each arm
	// because a long double reaches them all as `is_floating`.
	if expr.typ.kind.is_extended() {
		return false
	}
	return match expr {
		ast.FloatLit {
			true
		}
		ast.Ident {
			if slot := e.lookup(expr.name) {
				// The name of an array is the address of its first element,
				// which is a pointer and not a floating value, however its
				// elements are read.
				slot.count == 0 && (slot.floating || slot.single)
			} else {
				e.global_is_floating(expr.name)
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
		ast.Assign {
			// The value written, whose type is the object's: the whole
			// expression is floating when the object is.
			expr.typ.kind != .unknown && expr.typ.is_floating()
		}
		ast.Comma {
			// Worth the value of its right operand, so that operand's type
			// is the answer.
			expr.typ.kind != .unknown && expr.typ.is_floating()
		}
		ast.StmtExpr {
			// Worth the value of its last expression statement, whose type
			// the reader resolved for the node.
			expr.typ.kind != .unknown && expr.typ.is_floating()
		}
		ast.Index {
			// An element is a floating value when the type the reader gave the
			// element is one: the element type of the array or the pointee of
			// the pointer, which the node carries. The base of a subscript is
			// an expression rather than a name, so the element's own type is
			// what answers and not a slot looked up by the name the base used
			// to be.
			expr.typ.kind != .unknown && expr.typ.is_floating()
		}
		ast.Field {
			// A member whose declared type is a floating one is a floating
			// value, and the reader kept that type as the spelling of the
			// member.
			e.writes_a_double(expr.spelling) || e.writes_a_float(expr.spelling)
		}
		ast.IncDec {
			// The value is the object after the step, whose class is the
			// object's own: a double or a float name, element or member is a
			// floating value, and the reader resolved that type for the node.
			expr.typ.kind != .unknown && expr.typ.is_floating()
		}
		ast.Call {
			// A call that hands an object back hands its bytes over in the
			// register its class names, so the floating class is the same answer
			// as a function that returns a double or a float. The clause the
			// reader resolved is the answer where there is one, which is what
			// types a call this emitter has no name for: a call the reader built
			// itself from the compiler's own spellings is not a call to a
			// function the program declares, and its clause is the only thing
			// that says whether the value it hands over is a floating one.
			if expr.typ.kind != .unknown {
				return expr.typ.is_floating()
			}
			// A call written to an expression carries the type the parser
			// resolved onto the callee, which is the other source for the same
			// answer: either one can be the one that got set.
			if typ := indirect_call_returns(expr) {
				return typ.is_floating()
			}
			e.returns[expr.name] == 'double' || e.returns[expr.name] == 'float'
				|| e.return_classes[expr.name].first_floating
		}
		else {
			false
		}
	}
}

// single_at is the same walk asked for the four-byte member of the class, and it
// is the same walk rather than a second idea: every case that answers here also
// answers floating_at, and the cases that are not a float do not.
fn (e Emitter) single_at(expr ast.Expr, depth int) bool {
	if depth > max_emit_depth {
		return false
	}
	// The same guard floating_at carries: the extended type is not a value of
	// this register file at either width.
	if expr.typ.kind.is_extended() {
		return false
	}
	return match expr {
		ast.FloatLit {
			// The reader gives a constant with an `f` suffix the float type and
			// any other floating constant the double one, so the constant's
			// own type is the answer.
			expr.typ.kind == .float
		}
		ast.Ident {
			if slot := e.lookup(expr.name) {
				slot.count == 0 && slot.single
			} else {
				e.global_is_single(expr.name)
			}
		}
		ast.Unary {
			if expr.typ.kind != .unknown {
				return expr.typ.kind == .float
			}
			(expr.op == '-' || expr.op == '+') && e.single_at(expr.expr, depth + 1)
		}
		ast.Binary {
			if expr.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
				false
			} else if expr.typ.kind != .unknown {
				// The usual arithmetic conversions make a step with a double
				// anywhere in it a double step, so the node's own type is the
				// answer and an operand being a float does not make it one.
				expr.typ.kind == .float
			} else {
				(e.single_at(expr.left, depth + 1) || e.single_at(expr.right, depth + 1))
					&& !(e.double_of(expr.left) || e.double_of(expr.right))
			}
		}
		ast.Cast {
			expr.typ.kind == .float
		}
		ast.Index {
			// The same question floating_at asks of an element, at four bytes:
			// the element's own type is the answer.
			expr.typ.kind == .float
		}
		ast.Field {
			e.writes_a_float(expr.spelling)
		}
		ast.IncDec {
			// The same question at four bytes: the object is a float, so the
			// value the operator leaves in the floating file is one.
			expr.typ.kind == .float
		}
		ast.Call {
			// The same question at four bytes, and the reader's clause is the
			// answer where it has one.
			if expr.typ.kind != .unknown {
				return expr.typ.kind == .float
			}
			if typ := indirect_call_returns(expr) {
				return typ.kind == .float
			}
			e.returns[expr.name] == 'float'
		}
		ast.Conditional {
			// The value is whichever arm ran, converted to the type the two
			// arms have in common, so that type is the answer and not either
			// arm's own.
			if expr.typ.kind != .unknown {
				expr.typ.kind == .float
			} else {
				e.floating_at(expr.then_expr, depth + 1) || e.floating_at(expr.else_expr, depth + 1)
			}
		}
		ast.Assign, ast.Comma {
			// The node's own type is the type of the value it leaves, which
			// the reader resolved, so it decides this the way it decides
			// whether the value is floating at all.
			expr.typ.kind == .float
		}
		ast.StmtExpr {
			// The same question about a statement expression's value, whose
			// type is the node's own clause.
			expr.typ.kind == .float
		}
		else {
			false
		}
	}
}

// convert_to_double makes sure the value just computed is a double, widening the
// int in the accumulator when it is not, and a float into one when the value is
// one. It is the C conversion between a narrower floating type and a wider one
// and between an integer type and a floating one, applied where the language asks
// for it: an operand of an operation the other side made a double, a value stored
// into a slot that holds one, an argument a parameter is one for, and the value a
// function returning a double returns.
fn (mut e Emitter) convert_to_double(expr ast.Expr, line int, col int) !void {
	if e.long_double_of(expr) {
		// The value is in memory at the address the expression left in the
		// accumulator, and the machine converts it on its x87 stack.
		return e.extended_to_double(expr, line, col)
	}
	if e.double_of(expr) {
		return
	}
	if e.single_of(expr) {
		// A float widens to a double exactly: every finite float is a value the
		// wider format holds, so the instruction that converts one is a
		// widening and not a rounding, and it is never the wrong answer.
		register := e.float_accumulator(line, col)!
		e.append(e.target.float_to_double(register, register)!)
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
	width := e.storage_width(expr.typ) or { 0 }
	if width == 8 {
		if expr.typ.is_unsigned_type() {
			// An eight-byte unsigned value fills the whole register, so there
			// is no upper half to clear and the four-byte fix does not carry.
			// The value is split at 2^63, which is a sequence the machine
			// composes and which needs a second register for the shifted word.
			scratch := e.scratch(line, col)!
			e.append(e.target.unsigned_word_to_double(double_register, integer, scratch)!)
			return
		}
		// An eight-byte signed value converts at eight bytes. The four-byte
		// conversion would read the low half and call the top bit of it a
		// sign, which a long or a long long is not a four-byte value for.
		e.append(e.target.signed_word_to_double(double_register, integer)!)
		return
	}
	if expr.typ.is_unsigned_type() && width == 4 {
		// A four-byte unsigned value can be at or above 2^31, which is where the
		// signed conversion reads the top bit as a sign. A narrower unsigned type
		// is already below that boundary, and a source eight bytes wide is the
		// range split above, so only the four-byte case takes the zero-extending
		// conversion.
		e.append(e.target.unsigned_int_to_double(double_register, integer)!)
		return
	}
	e.append(e.target.int_to_double(double_register, integer)!)
}

// convert_to_single makes the value just computed a float, rounding it to four
// bytes when it is wider. That rounding is the whole difference between a float
// and a double and it happens here, at the one place a value becomes a float, so
// that no later use of it can round it a second way: a double is narrowed with
// the instruction that rounds to nearest even, and an integer is converted the
// way the language converts one.
fn (mut e Emitter) convert_to_single(expr ast.Expr, line int, col int) !void {
	if e.single_of(expr) {
		return
	}
	if e.long_double_of(expr) {
		// The conversion to a float narrows twice and truncates nowhere, but the
		// nine-byte store that would make it is not the instruction this back
		// end writes, so the destination is refused by name like every other
		// destination but a double.
		return e.refuse_a_long_double_conversion('float', line, col)
	}
	if e.double_of(expr) {
		register := e.float_accumulator(line, col)!
		e.append(e.target.double_to_float(register, register)!)
		return
	}
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is not converted to a float, and there is no conversion between an address and a floating type')
		return error('pointer to a float')
	}
	integer := e.accumulator(line, col)!
	double_register := e.float_accumulator(line, col)!
	e.append(e.target.int_to_float(double_register, integer)!)
}

// convert_to_int is the other direction: the floating value in the
// floating-point accumulator is truncated towards zero into the integer in the
// general one, which is what the language defines an integer conversion from a
// floating type to do. The instruction that does it is a different one at each
// width of the destination, so the destination's width chooses which is written.
// A value out of range is not reported, because the language leaves the result of
// the conversion undefined for one: the answer is the instruction's. The one place
// that is not gcc's answer is an unsigned destination whose value is at or above
// 2^64, where the bit the target operation puts back is the one already set; the
// machine operation says what that leaves.
//
// The destination's signedness is a parameter rather than something this can read
// off the double: an unsigned destination can hold values at and above the
// boundary where the signed truncation saturates, which is 2^31 for a four-byte
// one and 2^63 for an eight-byte one, while a signed destination has no such
// values and its conversion is the one the machine has.
fn (mut e Emitter) convert_to_int(expr ast.Expr, unsigned_target bool, target_width int, line int, col int) !void {
	if e.long_double_of(expr) {
		// The destination truncates toward zero and the machine's instruction
		// rounds to nearest even, so the two answers differ for a fractional
		// value and the destination is refused by name.
		return e.refuse_a_long_double_conversion('an integer of ${target_width} bytes', line, col)
	}
	if !e.floating_of(expr) {
		return
	}
	float_register := e.float_accumulator(line, col)!
	integer := e.accumulator(line, col)!
	if e.single_of(expr) {
		if target_width == 8 {
			// A float widens to a double exactly, and the truncation at eight
			// bytes is the double's: the four-byte truncation alone saturates
			// at 2^31, which a float at 3e9 is above.
			e.append(e.target.float_to_double(float_register, float_register)!)
		} else {
			e.append(e.target.float_to_int(integer, float_register)!)
			return
		}
	}
	if target_width == 8 {
		if unsigned_target {
			// An eight-byte unsigned destination holds values at and above
			// 2^63, which the signed truncation saturates, so the value is
			// split at that boundary. It is the machine's operation and it
			// takes a general register for 2^63 and a double register to hold
			// it in.
			scratch := e.scratch(line, col)!
			float_scratch := e.float_scratch(line, col)!
			e.append(e.target.double_to_unsigned_word(integer, float_register, scratch, float_scratch)!)
			return
		}
		e.append(e.target.double_to_signed_word(integer, float_register)!)
		return
	}
	e.append(e.target.double_to_int(integer, float_register)!)
	if unsigned_target {
		e.append(e.target.double_to_unsigned_int(integer, float_register)!)
		return
	}
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
			return slot.is_array()
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
fn (mut e Emitter) store_wide(slot Slot, expr ast.Expr, line int, col int, depth int) !void {
	// A slot's two words are written through its address, which is the same store
	// a member's is: the frame's address plus the slot's offset.
	frame := e.slot_base_register(slot, line, col)!
	register := e.accumulator(line, col)!
	e.append(e.target.address_of_slot(frame, slot.offset, register))
	address := e.value_slot(depth)
	e.store_accumulator(address, line, col)!
	return e.store_wide_at(address, expr, line, col, depth)
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
fn (mut e Emitter) store_wide_at(address Slot, expr ast.Expr, line int, col int, depth int) !void {
	if e.wide_value(expr) {
		// An object of the type is a copy of its bytes rather than a value to
		// widen, which is the shape an assignment between two of them has; a value
		// of the type that is not an object — the result of an addition, say — is
		// already the pair, and it is written at the address as two words.
		match expr {
			ast.Ident, ast.Field, ast.Index {
				return e.assign_object(address, wide_bytes, expr, line, col, depth)
			}
			else {
				// The value is an expression rather than storage: it is computed
				// here, below the slot the address is parked in, and what it leaves
				// in the registers is the pair the store writes.
				e.emit_value(expr, depth + 1)!
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
	e.emit_expr_at(expr, depth + 1)!
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
// (`char *p = 0` is a zero of pointer width). A value narrower than the slot is
// converted to the slot's type first, which is the conversion the language makes
// when a value is assigned to an object of another type (6.5.16.1) and the one
// extend_operand_to_word writes for the store below: `long v = i` is the int
// sign-extended into the whole slot, and an unsigned int takes zeros there. A
// value wider than the slot is refused, because the store moves the slot's bytes
// and the top of the value would be dropped; storing a pointer in four bytes is
// that case.
//
// A slot holding a double is the exception to that, and the reason the check is
// written around the conversion: the language converts an integer to a double
// and a double to an integer where one is stored in the other, which is a
// different value of a different width rather than a wrong one, so the value is
// converted first and the width it had no longer describes it. A pointer is one
// of the two conversions that does not exist, and it is refused by name.
//
// A slot holding a `_Bool` is the other exception, and the reason it is answered
// before the check: 6.3.1.2 makes every store into one hold 0 or 1 whatever the
// width of the value, so the value is compared with zero in its own domain
// instead of cut to the slot's byte. A long double is refused there by name, and
// so is a shape this back end cannot test.
fn (mut e Emitter) store_value(slot Slot, expr ast.Expr, line int, col int) !void {
	floating := e.floating_of(expr)
	if slot.boolean {
		// Every store into a `_Bool` makes the value 0 or 1 (6.3.1.2), which is
		// a comparison with zero and not a store at the slot's one byte: a wide
		// value whose low byte is zero, a fraction, and a non-null address all
		// leave 1. The comparison is made at the value's own width first, and
		// the store then writes the 0 or 1 it leaves.
		e.normalize_a_bool_value(expr, line, col)!
		e.store_accumulator(slot, line, col)!
		return
	}
	if e.long_double_of(expr) && !slot.single && !slot.floating {
		// A value of the extended type stored in a slot of another type is a
		// conversion out of it, and the only one this back end writes is the
		// conversion to a double. An integer slot is refused by name rather
		// than written with the bits of the address the value is at.
		return e.refuse_a_long_double_conversion('an integer of ${slot.width} bytes', line, col)
	}
	if slot.single {
		// A slot holding a float takes the value converted to one, which rounds
		// a double to four bytes and converts an integer, and then stores it
		// with the instruction that moves four bytes. A pointer is refused for
		// the reason it is refused for a double: there is no conversion between
		// an address and a floating type.
		if !floating && e.is_a_pointer(expr) {
			e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a slot that holds a float, and there is no conversion between them')
			return error('pointer into a float')
		}
		e.convert_to_single(expr, line, col)!
		e.store_single_accumulator(slot, line, col)!
		return
	}
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
		e.convert_to_int(expr, slot.unsigned, slot.width, line, col)!
		e.store_accumulator(slot, line, col)!
		return
	}
	if e.constant(expr) == none {
		width := e.width_of(expr) or {
			e.diagnostics << problem(line, col, 'unsupported: the value is one this back end cannot size, so it cannot be stored')
			return error('unknown width')
		}
		if width > slot.width && !(slot.width < 4 && width == 4) {
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
	if expr.typ.kind.is_complex() {
		// A complex value is two components and the accumulator is one register.
		// Every context that wants one has a complex path that answers for it —
		// an object it is written into, a call it is handed to, a comparison it
		// is part of — so an expression reaching here is one no complex path
		// took, and it is refused by name rather than read as its real part.
		e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: a value of type ${expr.typ.describe()} is two components, and a complex value used as a single one is not computed here')
		return error('complex value as a value')
	}
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
			if expr.typ.kind.is_extended() {
				// A long double constant is materialized into a frame
				// temporary. Its value is sixteen bytes and not a register
				// width, so what the expression is worth is the address of them.
				e.emit_extended_literal(expr, expr.line, expr.col)!
				return
			}
			// A floating constant of either width is read-only data and an
			// instruction that says where they are. The machine has no form of
			// a floating move that takes the value in the instruction, so the
			// bytes go in the image and are read from it, which is also what
			// makes two constants with the same value one entry.
			//
			// The two widths are two entries and two instructions: four bytes
			// read by the move that reads a float, eight by the move that reads
			// a double. Reading a float's entry with the eight-byte move would
			// read the four bytes of it and then whatever was interned after
			// it, which is a value nobody wrote.
			register := e.float_accumulator(expr.line, expr.col)!
			if expr.typ.kind == .float {
				e.intern_single(expr.value)
				e.reference(e.target.load_float_constant(register, 0)!, .single_constant, single_key(expr.value),
					e.target.name_of(register))
			} else {
				e.intern_double(expr.value)
				e.reference(e.target.load_double_constant(register, 0)!, .float_constant, float_key(expr.value),
					e.target.name_of(register))
			}
		}
		ast.ComplexLit {
			// An imaginary constant is a complex value, and a complex value is
			// two components rather than the one a register here holds. Where
			// one is wanted the complex paths answer for it; a context that
			// asks for a scalar at this point has nowhere to put it, so it is
			// refused by name rather than read as its imaginary part alone.
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: the imaginary constant ${expr.text} is a complex value used where a scalar is wanted')
			return error('complex constant as a scalar')
		}
		ast.Ident {
			slot := e.lookup(expr.name) or {
				// Not a local: a top-level object is storage the image holds,
				// and its name is the address of that storage. What is read is
				// the value at the width the object was defined with, which is
				// the same load an element of an array takes.
				if object := e.global_of(expr.name) {
					register := e.accumulator(expr.line, expr.col)!
					e.reference_object_address(register, expr.name)
					if object.count > 0 {
						// The name of an array is the address of its first
						// element.
						return
					}
					if object.count == 0 && e.global_is_long_double(expr.name) {
						// An object of the extended type read as a value is
						// its address: sixteen bytes are in memory and there is
						// no register of that width to read them into.
						return
					}
					if object.count == 0 && object.width == wide_bytes {
						// A top-level object of a 128-bit type read as a value gets the
						// refusal a local of the type gets: of that width there is no
						// value here, only storage, and the storage is real.
						e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
						return error('128-bit value')
					}
					if object.single {
						// A float is read through its address with the
						// four-byte instruction, for the same reason: the
						// value lives in the floating file and the address in
						// the general one.
						float_register := e.float_accumulator(expr.line, expr.col)!
						e.append(e.target.load_float_indirect(register, float_register)!)
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
					e.load_indirect_value(register, register, object.unsigned, object.width)!
					return
				}
				if e.is_function_name(expr.name) {
					// 6.3.2.1: a function designator used where a value is
					// wanted is the pointer to the function, so a name that is
					// a function this unit names, defined here or declared
					// elsewhere, is worth the address of that function.
					e.emit_function_address(expr.name, expr.line, expr.col) or {
						return error('no function address')
					}
					return
				}
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is not a constant and is not a local of this function')
				return error('unknown name')
			}
			if slot.long_double && slot.count == 0 {
				// The name of an object of the extended type is the address of
				// its sixteen bytes, which is what a value of the type is worth
				// everywhere in this back end.
				return e.leave_address(slot, expr.line, expr.col)
			}
			if slot.wide {
				// A 128-bit object is stored, copied and addressed, and it is
				// not a value this back end has: reading the name would have to
				// answer with a value of that width, so the refusal names what
				// the object is good for instead.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
				return error('128-bit value')
			}
			if slot.bytes > 0 && slot.count == 0 {
				// The name of an object of an aggregate type is the object, and
				// a value of a struct type is not a value this back end moves:
				// a member of it and its address are, so the refusal names the
				// shape that is not implemented instead of reading the object's
				// first bytes as an int. An array of such objects is not one of
				// them: its name is the address of its first element, which is
				// what the array branch below answers and what `p = t` needs.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.name} is an object of an aggregate type, and using it as a value is not implemented; a member of it, or its address, is')
				return error('aggregate value')
			}
			if slot.vla {
				// A variable-length array's name is worth the address of its
				// first element, which is the address the declaration stored;
				// the frame slot holds that address and not the array.
				register := e.accumulator(expr.line, expr.col)!
				e.load_vla_base(slot, register, expr.line, expr.col)!
				return
			}
			if slot.count > 0 {
				// An array's name is worth the address of its first element: in
				// an expression it is what a pointer is, which is what makes
				// `puts(buf)` and `strlen(buf)` work with an array.
				register := e.accumulator(expr.line, expr.col)!
				base := e.slot_base_register(slot, expr.line, expr.col)!
				e.append(e.target.address_of_slot(base, slot.offset, register))
				return
			}
			if slot.single {
				e.load_single_accumulator(slot, expr.line, expr.col)!
				return
			}
			if slot.floating {
				e.load_double_accumulator(slot, expr.line, expr.col)!
				return
			}
			e.load_accumulator(slot, expr.line, expr.col)!
		}
		ast.Field {
			if expr.typ.is_array() {
				// A member whose type is an array decays to a pointer to its
				// first element wherever a value is wanted (6.3.2.1p3), the
				// way an array's name does: the value it is worth is the
				// member's own address, and the bytes of the array are not read
				// as a value. The two places the operand is not decayed never
				// reach here: `sizeof` is folded to its constant where it is
				// written, and `&` takes the address without reading the member.
				//
				// A flexible array member has no length, so there is no width
				// to read its contents at and no size to guess: its storage is
				// the bytes past the object, and the address of those bytes is
				// what `memcpy(fam.data, ...)` is handed. This is the one value
				// a flexible member can be.
				e.field_address(expr, depth, expr.line, expr.col)!
				return
			}
			if e.writes_a_long_double(expr.spelling) {
				// A member of the extended type is sixteen bytes at an offset
				// into the object that holds it, and the value of the member is
				// the address of those bytes.
				e.field_address(expr, depth, expr.line, expr.col)!
				return
			}
			// A member is the value at an offset into an object: the address of
			// the object plus the offset the model's layout put the member at,
			// read at the width of the member's type. A double member is read
			// with the instruction that moves one rather than with the integer
			// load of the same width.
			if e.writes_a_complex(expr.spelling) {
				// The member is two components, and this is the value question,
				// which is the one this back end has no answer for; the
				// member's own address is the part that works, and every
				// context that places a complex value goes through it.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the member ${expr.name}.${expr.member} is declared ${expr.spelling}, and a value of that type is two components where this back end keeps one value in a register')
				return error('unsupported member type')
			}
			if e.writes_a_128(expr.spelling) {
				// The object holds a member of that width, and the read is the
				// value question, which is the one this back end has no answer
				// for: the member's own address is the part that works.
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the member ${expr.name}.${expr.member} is declared ${expr.spelling}, and this back end stores an object of that width but has no value of it to read')
				return error('unsupported member type')
			}
			width := e.type_width(expr.spelling) or {
				e.diagnostics << problem(expr.line, expr.col, 'unsupported: the member ${expr.name}.${expr.member} is declared ${expr.spelling}, and this back end stores ints, chars, floats, doubles and pointers only')
				return error('unsupported member type')
			}
			e.field_address(expr, depth, expr.line, expr.col)!
			register := e.accumulator(expr.line, expr.col)!
			if e.writes_a_float(expr.spelling) {
				float_register := e.float_accumulator(expr.line, expr.col)!
				e.append(e.target.load_float_indirect(register, float_register)!)
				return
			}
			if e.writes_a_double(expr.spelling) {
				double_register := e.float_accumulator(expr.line, expr.col)!
				e.append(e.target.load_double_indirect(register, double_register)!)
				return
			}
			if expr.bitfield {
				return e.load_bitfield(register, expr, width)
			}
			e.load_indirect_value(register, register, e.written_is_unsigned(expr.spelling), width)!
		}
		ast.StrLit {
			// A string is the address of its bytes: the image holds the bytes
			// and the instruction says where they landed. A wide literal's
			// bytes are picked out of their own table, because the same run of
			// bytes can be a narrow literal's as well.
			if expr.unit == 4 {
				e.intern_wide(expr.value)
				register := e.accumulator(expr.line, expr.col)!
				e.reference(e.target.address_of(register, 0), .take_wide_address, expr.value,
					e.target.name_of(register))
			} else {
				e.intern(expr.value)
				register := e.accumulator(expr.line, expr.col)!
				e.reference(e.target.address_of(register, 0), .take_address, expr.value,
					e.target.name_of(register))
			}
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
		ast.Assign {
			e.emit_assign_expression(expr, depth)!
		}
		ast.Comma {
			e.emit_comma(expr, depth)!
		}
		ast.StmtExpr {
			// `({ ... })` used as a value: the body runs for what it does and
			// the last expression statement's value is what the construct is
			// worth, which is left in the register a value lives in.
			e.emit_statement_expression(expr, true)!
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
			// A call through an expression says the same thing through the
			// type the parser resolved onto the call.
			if typ := indirect_call_returns(expr) {
				if typ.is_void() {
					e.diagnostics << problem(expr.line, expr.col, 'unsupported: the call is used as a value, and what it calls returns void')
					return error('void value')
				}
			} else if e.returns[expr.name] == 'void' {
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
// check_subscript_index refuses an extended value used as a subscript. A
// subscript is an integer the back end loads into a general register, and the
// value of a long double is the address of its bytes, so an index of the type
// would be that address scaled by the element size and read from nowhere: gcc
// converts the index to an integer, and that conversion is one this back end
// refuses by name everywhere else.
fn (mut e Emitter) check_subscript_index(index ast.Expr) !void {
	if e.long_double_of(index) {
		e.diagnostics << problem(expr_line(index), expr_col(index), 'unsupported: a long double is used as a subscript, and converting an index from a value of that type is not a conversion this back end makes')
		return error('long double subscript')
	}
}

// emit_subscript_index reads the index of a subscript and widens it to a word
// before the element address scales it. 6.5.6p8 converts the index to the
// pointer's arithmetic type, and a signed value of four bytes would otherwise
// arrive zero-extended: an index of -1 read at four bytes is 4294967295, which
// scaled by the element size lands four gigabytes past the base rather than at
// the element before it. extend_operand_to_word widens a signed index with its
// sign and leaves an unsigned one zero-extended, which is the same conversion
// for that type, and does nothing to a value already a word wide.
// emit_pointer_step widens the index of `p + i` the same way. The widened value
// is left in the accumulator, where both element-address paths expect the index.
fn (mut e Emitter) emit_subscript_index(index ast.Expr, depth int) !void {
	e.check_subscript_index(index)!
	e.emit_expr_at(index, depth)!
	e.extend_operand_to_word(index, expr_line(index), expr_col(index))!
}

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
		e.emit_subscript_index(expr.index, depth + 1)!
		base := e.slot_base_register(slot, expr.line, expr.col)!
		register := e.accumulator(expr.line, expr.col)!
		e.element_address(base, register, slot.width, slot.offset, slot.wide || slot.long_double,
			expr.typ.is_array(), name, expr.line, expr.col)!
		if expr.typ.is_array() {
			// The element is itself an array, so reading it is not a load: its
			// value is the address of its first element, which is what
			// element_address left in the accumulator. Loading the bytes of the
			// whole row would answer with the first element's value as though
			// the row were a scalar, and stepping an index by that value is a
			// wrong address.
			return
		}
		if slot.wide {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
			return error('128-bit element')
		}
		if slot.long_double {
			// An element of an array of long doubles: what the element is worth
			// is the address element_address left, the way a scalar name of the
			// type is.
			return
		}
		if slot.single {
			// An element of an array of floats: the address is in a general
			// register and the value is read into a floating-point one, four
			// bytes at a time.
			float_register := e.float_accumulator(expr.line, expr.col)!
			e.append(e.target.load_float_indirect(register, float_register)!)
			return
		}
		if slot.floating {
			// An element of an array of doubles: the address is in a general
			// register and the value is read into a floating-point one, which
			// is the same split the load of a double global makes.
			double_register := e.float_accumulator(expr.line, expr.col)!
			e.append(e.target.load_double_indirect(register, double_register)!)
			return
		}
		e.load_indirect_value(register, register, slot.unsigned, slot.width)!
		return
	}
	// A top-level array: its storage is in the image, so the address of an
	// element is an offset from the address of the object rather than from the
	// frame.
	object := e.global_of(name) or { return error('unknown name') }
	e.emit_subscript_index(expr.index, depth + 1)!
	register := e.accumulator(expr.line, expr.col)!
	// The address of the object goes into the scratch register after the index
	// is computed, so that the index expression cannot overwrite it on the way.
	base := e.scratch(expr.line, expr.col)!
	e.reference_object_address(base, name)
	long_double := e.global_array_is_long_double(name)
	// A 128-bit integer and a long double are both sixteen bytes, but only the
	// integer has no value this back end reads: an element of a top-level array
	// of long doubles is the address of its bytes, the same as a local one, so
	// the wide-object refusal is kept off it.
	wide := !object.object && object.width == wide_bytes && !long_double
	e.element_address(base, register, object.width, 0, wide || long_double, expr.typ.is_array(), name,
		expr.line,
		expr.col)!
	if expr.typ.is_array() {
		// The element is an array, so its value is the address of its first
		// element, which is what element_address left in the accumulator.
		return
	}
	if wide {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${name} is an object of 128 bits, and this back end stores one and copies one but has no value of that width to read')
		return error('128-bit element')
	}
	if !object.floating && !object.single && e.global_array_is_long_double(name) {
		// An element of a top-level array of long doubles: its value is the
		// address element_address left, exactly as a local element of the type.
		return
	}
	if object.single {
		float_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_float_indirect(register, float_register)!)
		return
	}
	if object.floating {
		double_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_double_indirect(register, double_register)!)
		return
	}
	e.load_indirect_value(register, register, object.unsigned, object.width)!
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
	if expr.typ.kind.is_extended() {
		// An element of the extended type is the address emit_element_address
		// left, which is what a value of the type is worth.
		return
	}
	if expr.typ.kind == .float {
		float_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_float_indirect(address, float_register)!)
		return
	}
	if expr.typ.kind == .double {
		double_register := e.float_accumulator(expr.line, expr.col)!
		e.append(e.target.load_double_indirect(address, double_register)!)
		return
	}
	width := e.storage_width(expr.typ) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${expr.typ.describe()} is not a value this back end reads')
		return error('unsupported element type')
	}
	e.load_indirect_value(address, address, expr.typ.is_unsigned_type(), width)!
}

// emit_element_address leaves in the accumulator the address of the element
// `E1[E2]` names: the base's value, which is the address of an array's first
// element or a pointer's own value, plus the index scaled by the size of one
// element. It is the address half of the element read and of the element write,
// which is why the two share it.
fn (mut e Emitter) emit_element_address(expr ast.Index, depth int) !void {
	if stride_expr := expr.vla_stride {
		return e.emit_dynamic_element_address(expr, stride_expr, depth)
	}
	e.emit_base_address(expr.base, depth + 1)!
	base := e.value_slot(depth)
	e.store_accumulator(base, expr.line, expr.col)!
	e.emit_subscript_index(expr.index, depth + 1)!
	index := e.accumulator(expr.line, expr.col)!
	other := e.scratch(expr.line, expr.col)!
	e.load_argument(base, other, e.target.word_size, expr.line, expr.col)!
	stride := e.representation.size_of(expr.typ) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: an element of ${expr.typ.describe()} has no size this back end can scale an index by')
		return error('no element size')
	}
	e.element_address(other, index, stride, 0, stride == wide_bytes, expr.typ.is_array(), 'the element', expr.line, expr.col)!
}

// emit_dynamic_element_address is emit_element_address for an element whose stride
// is a value rather than a constant: the row of a variable-length array is as many
// bytes as its bound says, and the bound is computed where the subscript runs. The
// three values the address is made of need a register or a slot each, so the stride
// and the index are parked while the base is addressed, and the machine's multiply
// scales the index by the stride. The address is left in the accumulator the way
// the constant-stride path leaves it, so the read and the write that follow do not
// know which path produced it.
fn (mut e Emitter) emit_dynamic_element_address(expr ast.Index, stride_expr ast.Expr, depth int) !void {
	e.emit_expr_at(stride_expr, depth + 1)!
	stride_slot := e.reserve(e.target.word_size)
	e.store_accumulator(stride_slot, expr.line, expr.col)!
	e.emit_subscript_index(expr.index, depth + 1)!
	index_slot := e.reserve(e.target.word_size)
	e.store_accumulator(index_slot, expr.line, expr.col)!
	e.emit_base_address(expr.base, depth + 1)!
	base := e.remainder(expr.line, expr.col)!
	accumulator := e.accumulator(expr.line, expr.col)!
	e.append(e.target.move_register64(base, accumulator)!)
	e.load_accumulator(index_slot, expr.line, expr.col)!
	index := e.accumulator(expr.line, expr.col)!
	stride := e.scratch(expr.line, expr.col)!
	frame := e.frame_pointer(expr.line, expr.col)!
	e.append(e.target.load_slot(frame, i32(stride_slot.offset), stride, e.target.word_size)!)
	e.append(e.target.multiply_word(index, stride)!)
	e.append(e.target.add_reg64(index, base))
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
			if slot.vla {
				// A variable-length array's storage is at the address its
				// declaration stored, not at an offset from the frame: the
				// frame held that address and nothing of the array.
				register := e.accumulator(base.line, base.col)!
				e.load_vla_base(slot, register, base.line, base.col)!
				return
			}
			if slot.count > 0 {
				register := e.accumulator(base.line, base.col)!
				frame := e.slot_base_register(slot, base.line, base.col)!
				e.append(e.target.address_of_slot(frame, slot.offset, register))
				return
			}
		} else if object := e.global_of(name) {
			if object.count > 0 {
				register := e.accumulator(base.line, base.col)!
				e.reference_object_address(register, name)
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
//
// depth is the level the address is taken at, and it travels through because
// the address of an array element and the address of a member of a non-name
// object are computed through the frame slot of that level. A level one too
// shallow lands on a slot an enclosing call already parked an argument in.
fn (mut e Emitter) emit_address(unary ast.Unary, depth int) !void {
	register := e.accumulator(unary.line, unary.col)!
	if unary.expr is ast.Ident {
		name := unary.expr.name
		if slot := e.lookup(name) {
			if slot.vla {
				// The object is at the address the declaration stored, so its
				// address is that value and not a place in the frame.
				e.load_vla_base(slot, register, unary.line, unary.col)!
				return
			}
			base := e.slot_base_register(slot, unary.line, unary.col)!
			e.append(e.target.address_of_slot(base, slot.offset, register))
			return
		}
		if _ := e.global_of(name) {
			e.reference_object_address(register, name)
			return
		}
		if e.is_function_name(name) {
			// `&f` is the same value a bare `f` is worth where a value is
			// wanted: 6.3.2.1 does not give a function designator an address
			// operator of its own.
			return e.emit_function_address(name, unary.line, unary.col)
		}
	}
	if unary.expr is ast.Field {
		if unary.expr.bitfield {
			// A bitfield is not an object with an address of its own: it is a
			// run of bits inside a storage unit it shares, so `&s.a` has no
			// byte to give. gcc refuses it too, and a refusal by name is what
			// keeps this from handing back the unit's address as though it
			// were the field's.
			e.diagnostics << problem(unary.line, unary.col, 'unsupported: the address of the bitfield ${unary.expr.name}.${unary.expr.member} is taken, and a bitfield does not have an address of its own')
			return error('address of a bitfield')
		}
		// The member's address is the object's address plus the byte the layout
		// put the member at, which is the same computation a member read makes
		// and stops short of the read.
		e.field_address(unary.expr, depth, unary.line, unary.col)!
		return
	}
	if unary.expr is ast.Index {
		// The element's address, which is what the subscript computes before it
		// reads or writes through it.
		e.emit_element_address(unary.expr, depth)!
		return
	}
	if unary.expr is ast.Comma {
		// The address of a compound literal written where its statement does
		// not describe a single evaluation: the left operand initializes the
		// object, runs first for that, and the address is the right operand's.
		e.emit_effect(unary.expr.left, depth + 1)!
		return e.emit_address(ast.Unary{
			op:   '&'
			expr: unary.expr.right
			typ:  unary.typ
			line: unary.line
			col:  unary.col
		}, depth)
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
	if unary.op == '&&' {
		// The address of a label, `&&name`. The operand is a label name and
		// not a value to read, so it is not evaluated here: what is written is
		// the address of the place the label names.
		return e.emit_label_address(unary)
	}
	if unary.op == '&' {
		// Taking an address is not a computation on a value: the operand is not
		// read at all, and what is taken is where it lives. The depth travels
		// with it for the frame slots the computation needs.
		return e.emit_address(unary, depth)
	}
	if unary.op == '*' {
		// Reading through an address is not a computation either: the operand is
		// the address and the value is at it.
		return e.emit_deref(unary, depth)
	}
	if unary.op == '__real__' || unary.op == '__imag__' {
		// One part of a complex value is the component the operator names, read
		// out of the pair into a floating-point register. The value is real and
		// lives in one register, which is why the node's own type is the
		// component's and the paths that want a floating value reach here.
		return e.emit_complex_part(unary, depth)
	}
	if e.long_double_of(unary.expr) {
		// The logical not asks whether the value is zero, which is the
		// comparison with zero the x87 stack makes. The sign change is the
		// stack's own negate, which flips the sign bit in place, and the
		// unary plus computes nothing at all: the operand's address is the
		// value. Anything else is refused by name.
		if unary.op == '!' {
			return e.emit_extended_logical_not(unary, depth)
		}
		if unary.op == '-' {
			return e.emit_extended_negate(unary, depth)
		}
		if unary.op == '+' {
			return e.emit_expr_at(unary.expr, depth)
		}
		return e.refuse_a_long_double_operation(unary.op, unary.line, unary.col)
	}
	if e.wide_value(unary.expr) {
		// A 128-bit operand is a pair rather than a value in the accumulator, so
		// the operators it has a meaning for are computed on the pair.
		return e.emit_wide_unary(unary, depth)
	}
	floating := e.floating_of(unary.expr)
	single := e.single_of(unary.expr)
	if floating {
		// Three operators have a meaning for a floating value: the sign change,
		// the unary plus that computes nothing, and the logical not, which asks
		// whether the value is zero. The complement is a bit operation on an
		// integer, and ISO C refuses it on a floating operand rather than
		// defining one.
		if unary.op != '+' && unary.op != '-' && unary.op != '!' {
			e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} takes an integer operand, and this one is a floating value')
			return error('operator on a floating value')
		}
	} else if width := e.width_of(unary.expr) {
		if width != 4 && unary.op != '+' && unary.op != '!' {
			if !e.eight_byte_integer(unary.expr.typ) {
				// Eight bytes that are not an integer is the width of a pointer
				// and the only other width this back end has, so the diagnostic
				// can say what it is. The three operators that reach here are
				// the sign change, the unary plus and the complement: the last
				// two compute on an integer, and the sign change is refused on
				// a pointer by gcc 16.2.1 as well. The logical not is not one of
				// them, because 6.5.3.3 gives it a scalar operand and a pointer
				// is a scalar.
				e.diagnostics << problem(unary.line, unary.col, 'unsupported: ${unary.op} takes an int, and this one is a pointer')
				return error('non-int operand')
			}
		}
	}
	e.emit_expr_at(unary.expr, depth + 1)!
	register := e.accumulator(unary.line, unary.col)!
	// A pointer is eight bytes and is asked whether it is the null pointer by
	// the same word-wide not a 64-bit integer is: a four-byte test would call a
	// pointer null whose only set bit is above the four bytes.
	wide := e.eight_byte_integer(unary.expr.typ) || e.is_a_pointer(unary.expr)
	match unary.op {
		'+' {}
		'-' {
			if floating {
				// The machine negates an integer and has no instruction that
				// negates a floating value, so the sign bit is flipped through
				// a general register. Subtracting from zero would round a
				// signalling NaN into a quiet one and turn -0.0 into 0.0,
				// neither of which is the value the operator asks for. The bit
				// is a different one at each width, which is why the two
				// instructions are two: flipping bit 63 of a float's register
				// is not the sign of the float.
				if single {
					e.append(e.target.negate_single(e.float_accumulator(unary.line, unary.col)!, register)!)
				} else {
					e.append(e.target.negate_double(e.float_accumulator(unary.line, unary.col)!, register)!)
				}
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

// emit_assign_expression writes an assignment that is used as a value. The store
// is the one an assignment statement makes, so the node is turned into the
// statement the store reader takes and that reader writes the bytes. What the
// expression is worth is the value of the object after the store: 6.5.16 gives
// the assignment the value of its left operand after the assignment, which is
// the value written converted to the object's type. That value is read back from
// the object rather than kept in a register, because the store paths leave what
// they wrote in whichever register the machine needed and every shape of the
// object has a read that answers with its value.
//
// The target has to be one of the places the statement reader addresses. The
// parser refuses the others, so a node with a target this reader does not know
// was written by something that got past it; it is refused here by name rather
// than stored through an address that was never computed.
fn (mut e Emitter) emit_assign_expression(assign ast.Assign, depth int) !void {
	stmt := assignment_statement(assign) or {
		e.diagnostics << problem(assign.line, assign.col, 'unsupported: the target of this assignment expression is ${describe_target(assign.target)}, and this back end writes a name, an element, a member or a dereference')
		return error('assignment expression target')
	}
	e.emit_assign(stmt, depth)!
	e.emit_expr_at(assign.target, depth + 1)!
}

// assignment_statement turns an assignment expression into the statement the
// store reader takes. The two carry the same three things - what is written,
// what it is written into, and where it was written - and the statement reader
// already addresses every place an assignment can write, so the store is not
// written a second time here.
fn assignment_statement(assign ast.Assign) ?ast.Stmt {
	mut target := ''
	mut subscript := ?ast.Expr(none)
	mut member := ?&ast.Field(none)
	mut deref := ?ast.Expr(none)
	match assign.target {
		ast.Ident {
			target = assign.target.name
		}
		ast.Index {
			subscript = ast.Expr(assign.target)
		}
		ast.Field {
			member = assign.target.boxed()
		}
		ast.Unary {
			if assign.target.op != '*' {
				return none
			}
			deref = ast.Expr(assign.target)
		}
		else {
			return none
		}
	}
	// The element or the address an assignment writes through is what the
	// statement needs an extra part for, and an assignment to a name has
	// neither: building one for every assignment would put back the bytes the
	// extra part exists to keep out of the node.
	mut extra := ?&ast.StmtExtra(none)
	if subscript != none || deref != none {
		extra = &ast.StmtExtra{
			subscript: subscript
			deref:     deref
		}
	}
	return ast.Stmt{
		kind:   .assign
		expr:   assign.value
		target: target
		field:  member
		extra:  extra
		line:   assign.line
		col:    assign.col
	}
}

// emit_comma writes `E1 , E2`. 6.5.17 sequences the left before the right and
// makes the expression worth the value of its right operand, so the left is
// evaluated for what it does and the value it leaves is overwritten by the
// right. Each operand goes through emit_effect, which is what a value thrown
// away means: a conversion to void, a call for its effect and a statement
// expression with no value are the shapes a value is thrown away in, and for
// every other shape the register is simply not read.
fn (mut e Emitter) emit_comma(comma ast.Comma, depth int) !void {
	e.emit_effect(comma.left, depth + 1)!
	e.emit_effect(comma.right, depth + 1)!
}

// emit_statement_expression writes `({ ... })`, a GNU statement expression: the
// body's statements in the order they were written, and then the value
// expression, which is what the construct is worth and is left in the register
// a value lives in.
//
// The body is a scope, so a name it declares does not outlive the construct,
// and its half-finished values wait above every slot the expression around it
// is using, so a statement expression can be an operand of an operator without
// its body writing over the operand that operator is holding.
//
// A construct with no value is void, which gcc refuses where a value is
// required and accepts where the value is thrown away; as_value says which use
// this is. A value the register cannot hold - an aggregate, or a width this
// back end has no value of - is refused by name rather than copied through a
// register that would keep only part of it.
fn (mut e Emitter) emit_statement_expression(expr ast.StmtExpr, as_value bool) !void {
	if as_value && expr.typ.is_void() {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: a statement expression used as a value has no value, because its last statement is not an expression statement')
		return error('statement expression without a value')
	}
	if as_value && expr.typ.kind in [.struct_, .union_, .array] {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: a statement expression whose value is ${expr.typ.describe()} is not one this back end returns, and the value of a statement expression has to be a value a register holds')
		return error('aggregate statement expression value')
	}
	saved := e.slot_base
	e.slot_base = e.values.len
	// The body is one scope and the value expression is emitted inside it, so
	// a name the body declares is visible to the expression that is the
	// construct's value: `({ int a = 4; a; })` reads the `a` it declared.
	e.push_scope()
	_ := e.emit_statements(expr.body)!
	if value := expr.value {
		e.emit_expr_at(value, 0)!
	}
	e.pop_scope()
	e.slot_base = saved
}

// inc_dec_step is how far one `++` or `--` moves the operand. It is one for an
// integer name, which is the increment of an integer, and the size of what is
// pointed at for a pointer name: 6.5.2.4 gives a pointer's increment the meaning
// of `p = p + 1`, and 6.5.6 scales that by the pointed-at type, so a `char *`
// steps one and an `int *` four. A pointer whose pointed-at type has no size -
// `void *`, a pointer to a function, a pointer to a struct that was declared and
// never defined - has no step to compute, and is refused by name rather than
// moved by one byte.
fn (mut e Emitter) inc_dec_step(expr ast.IncDec) !i32 {
	sign := if expr.op == '++' { i32(1) } else { i32(-1) }
	if !expr.typ.is_pointer() {
		return sign
	}
	pointee := expr.typ.pointee() or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on this object, which is ${expr.typ.describe()}, and a pointer with nothing pointed at has no step')
		return error('inc-dec operand points at nothing')
	}
	size := e.representation.size_of(pointee) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on this object, which is ${expr.typ.describe()}, and what it points at has no size to step by')
		return error('inc-dec operand points at a type with no size')
	}
	if size > 0x7fffffff {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on this object, which is ${expr.typ.describe()}, and a step that many bytes wide is not one this back end writes')
		return error('inc-dec step is too wide')
	}
	return sign * i32(size)
}

// emit_inc_dec writes `++x`, `--x`, `x++` or `x--` for the object the node
// holds. The object is named four ways - a name in the frame or the image, an
// element, a member, or what a pointer points at - and each is read, stepped and
// written back in place. A name keeps the frame-and-image path it has always had;
// the other three go through the object's own address, which is the machinery an
// assignment already uses for an lvalue. A floating object is a step of its own
// width rather than a count of bytes, so it is handled separately.
//
// The step is one for an integer, added for `++` and subtracted for `--`, and
// the size of what is pointed at for a pointer, which is the step 6.5.2.4 gives
// a pointer's increment through 6.5.6. What separates the two spellings is the
// value left in the accumulator: the prefix form leaves the object after the
// step, the postfix form what it held before, so the postfix form is the prefix
// form with the old value parked in a frame slot while the step runs and read
// back at the end.
//
// A char is stepped and written at its own byte: the read widens it to the int
// the language promotes it to, the step adds an int, and the store cuts the
// result back to a byte, which is what `c++` is defined to do. The step runs at
// the width of the object, so an int wraps at four bytes rather than producing a
// value no int holds.
fn (mut e Emitter) emit_inc_dec(expr ast.IncDec, depth int) !void {
	if expr.typ.kind == .float || expr.typ.kind == .double {
		return e.emit_inc_dec_floating(expr, depth)
	}
	step := e.inc_dec_step(expr)!
	operand := expr.operand
	if operand is ast.Ident {
		return e.emit_inc_dec_name(expr, operand, step, depth)
	}
	return e.emit_inc_dec_object(expr, step, depth)
}

// emit_inc_dec_name steps an object named by a name, which lives either in the
// frame or in the image. The frame case reads the slot directly; the image case
// reads through the address the layout gives the object.
fn (mut e Emitter) emit_inc_dec_name(expr ast.IncDec, name ast.Ident, step i32, depth int) !void {
	if slot := e.lookup(name.name) {
		if slot.count > 0 || slot.bytes > 0 || slot.wide || slot.floating || slot.single
			|| slot.long_double || slot.vla {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${name.name}, and this compiler steps a scalar object only')
			return error('inc-dec operand is not a scalar object')
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
	if object := e.global_of(name.name) {
		if object.count > 0 || object.object || object.floating || object.single || object.width == wide_bytes
			|| e.global_is_long_double(name.name) {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${name.name}, and this compiler steps a scalar object only')
			return error('inc-dec operand is not a scalar object')
		}
		// The object is storage in the image, so its address is a reference the
		// layout fills in and is parked while the step runs: the value is read
		// through the address, stepped, and written back through it.
		register := e.accumulator(expr.line, expr.col)!
		e.reference_object_address(register, name.name)
		address := e.value_slot(depth)
		e.store_accumulator(address, expr.line, expr.col)!
		address_register := e.scratch(expr.line, expr.col)!
		e.load_argument(address, address_register, e.target.word_size, expr.line, expr.col)!
		e.load_indirect_value(address_register, register, object.unsigned, object.width)!
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
	e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on ${name.name}, and no local or top-level object of that name is in scope')
	return error('unknown inc-dec target')
}

// emit_inc_dec_object steps an element, a member, or what a pointer points at.
// The object's address is computed with the same machinery an assignment uses -
// the element address, the member address, and the pointer's own value - and
// parked while the value is read through it. The value is stepped at the width of
// the object and written back through the same address.
fn (mut e Emitter) emit_inc_dec_object(expr ast.IncDec, step i32, depth int) !void {
	operand := expr.operand
	if operand is ast.Field {
		if operand.bitfield {
			e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on the bitfield ${operand.name}.${operand.member}, and this back end does not step a bitfield in place')
			return error('bitfield increment')
		}
	}
	e.inc_dec_address(operand, depth + 1)!
	address := e.value_slot(depth)
	e.store_accumulator(address, expr.line, expr.col)!
	address_register := e.scratch(expr.line, expr.col)!
	e.load_argument(address, address_register, e.target.word_size, expr.line, expr.col)!
	width := e.storage_width(expr.typ) or {
		e.diagnostics << problem(expr.line, expr.col, 'unsupported: ${expr.op} on an object of ${expr.typ.describe()}, and this back end has no width to step it at')
		return error('unsupported width')
	}
	register := e.accumulator(expr.line, expr.col)!
	e.load_indirect_value(address_register, register, expr.typ.kind.is_unsigned(), width)!
	old := if expr.postfix { e.value_slot(depth + 1) } else { Slot{} }
	if expr.postfix {
		e.store_accumulator(old, expr.line, expr.col)!
	}
	e.append(e.target.add_immediate(register, step))
	e.normalize_a_bool_store(expr.typ.kind == .bool_, width == 8, expr.line, expr.col)!
	e.append(e.target.store_indirect(address_register, register, width)!)
	if expr.postfix {
		e.load_accumulator(old, expr.line, expr.col)!
	}
}

// emit_inc_dec_floating steps an object of a floating type, which is one add or
// subtract of the right width: a float by 1.0f at four bytes and a double by 1.0
// at eight. The step is not a byte count - there is no stride for a value that is
// not a pointer - so the object's address is taken and the value is read into the
// floating-point register, the constant is loaded into the scratch one, and the
// arithmetic is the same instruction a `d + 1.0` uses. The postfix form parks the
// old value in a slot the way the integer path does and reads it back at the end.
fn (mut e Emitter) emit_inc_dec_floating(expr ast.IncDec, depth int) !void {
	single := expr.typ.kind == .float
	e.inc_dec_address(expr.operand, depth + 1)!
	address := e.value_slot(depth)
	e.store_accumulator(address, expr.line, expr.col)!
	address_register := e.scratch(expr.line, expr.col)!
	e.load_argument(address, address_register, e.target.word_size, expr.line, expr.col)!
	value := e.float_accumulator(expr.line, expr.col)!
	if single {
		e.append(e.target.load_float_indirect(address_register, value)!)
	} else {
		e.append(e.target.load_double_indirect(address_register, value)!)
	}
	old := if expr.postfix { e.value_slot(depth + 1) } else { Slot{} }
	if expr.postfix {
		if single {
			e.store_single_accumulator(old, expr.line, expr.col)!
		} else {
			e.store_double_accumulator(old, expr.line, expr.col)!
		}
	}
	other := e.float_scratch(expr.line, expr.col)!
	if single {
		e.intern_single(1.0)
		e.reference(e.target.load_float_constant(other, 0)!, .single_constant, single_key(1.0),
			e.target.name_of(other))
	} else {
		e.intern_double(1.0)
		e.reference(e.target.load_double_constant(other, 0)!, .float_constant, float_key(1.0),
			e.target.name_of(other))
	}
	op := if expr.op == '++' { '+' } else { '-' }
	if single {
		e.append(e.target.float_arithmetic(op, value, other)!)
		e.append(e.target.store_float_indirect(address_register, value)!)
	} else {
		e.append(e.target.double_arithmetic(op, value, other)!)
		e.append(e.target.store_double_indirect(address_register, value)!)
	}
	if expr.postfix {
		if single {
			e.load_single_accumulator(old, expr.line, expr.col)!
		} else {
			e.load_double_accumulator(old, expr.line, expr.col)!
		}
	}
}

// inc_dec_address leaves the address of the object an increment steps in the
// accumulator, which is the address the load and the store go through. A name
// lives in the frame or in the image; an element is addressed from its base; a
// member from the object that holds it, or from the pointer `->` reads; and what
// a pointer points at is the pointer's own value.
fn (mut e Emitter) inc_dec_address(operand ast.Expr, depth int) !void {
	if operand is ast.Ident {
		if slot := e.lookup(operand.name) {
			register := e.accumulator(operand.line, operand.col)!
			frame := e.slot_base_register(slot, operand.line, operand.col)!
			e.append(e.target.address_of_slot(frame, slot.offset, register))
			return
		}
		if object := e.global_of(operand.name) {
			if object.count > 0 || object.object || object.width == wide_bytes {
				e.diagnostics << problem(operand.line, operand.col, 'unsupported: ${operand.name} is not a scalar object, and this compiler steps a scalar object only')
				return error('not a scalar object')
			}
			register := e.accumulator(operand.line, operand.col)!
			e.reference_object_address(register, operand.name)
			return
		}
		e.diagnostics << problem(operand.line, operand.col, 'unsupported: ${operand.name} is stepped, and no declaration of that name is in scope')
		return error('unknown inc-dec target')
	}
	if operand is ast.Index {
		e.emit_element_address(operand, depth)!
		return
	}
	if operand is ast.Field {
		e.field_address(operand, depth, operand.line, operand.col)!
		return
	}
	if operand is ast.Unary {
		if operand.op == '*' {
			e.emit_expr_at(operand.expr, depth)!
			return
		}
	}
	e.diagnostics << problem(expr_line(operand), expr_col(operand), 'unsupported: this object cannot be stepped, and this compiler steps a name, an element, a member or what a pointer points at only')
	return error('not a step target')
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
	// A cast to an enumerated type is a cast to the integer type its
	// enumerators require: the value a program gets is that type's, and the
	// width and signedness come from it. Measured, `(unsigned int)(enum c)0`
	// under gcc 16.2.1 is an unsigned int, and the instruction is the one that
	// conversion takes.
	target := cast.typ.underlying_type()
	// 6.5.16.1 does not let a pointer to void and a pointer to a function
	// convert to one another, which gcc 16.2.1 takes in every mode and reports
	// only under -pedantic; this tree does the same, and the question is asked
	// here where a cast is written. Both values are an address of the machine's
	// word, so the conversion is the operand itself and writes no instruction,
	// and the operand is emitted as it stands.
	if message := types.function_void_pointer_problem(cast.typ, cast.expr.typ) {
		e.diagnostics << pedantic(cast.line, cast.col, message)
		return e.emit_expr_at(cast.expr, depth + 1)
	}
	if target.kind.is_extended() {
		// A conversion to the extended type: a source of the same type is the
		// same value, and anything else is converted into a temporary whose
		// address the conversion is worth.
		return e.emit_extended_cast(cast, depth)
	}
	if e.long_double_of(cast.expr) && target.kind != .double {
		// A conversion out of the extended type and into anything but a double:
		// the machine's truncating store rounds to nearest even rather than
		// toward zero, and the language's conversion truncates, so the plain
		// instruction would be a wrong value for a fractional long double.
		e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from long double to ${cast.spelling} is not one this back end makes, and the machine instruction that takes a value out of the extended format is not the truncation the language asks for; only a conversion to double is implemented')
		return error('long double conversion')
	}
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
		e.widen_into_pair(slot, cast.expr.typ.is_unsigned_type(), width, cast.line, cast.col)!
		return e.load_pair(slot, cast.line, cast.col)
	}
	if target.kind !in [.int_, .unsigned_int, .bool_, .char_, .signed_char, .unsigned_char, .short,
		.unsigned_short, .double, .float, .pointer, .long, .unsigned_long, .long_long,
		.unsigned_long_long] {
		e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion to ${cast.spelling} is not one this back end makes, and it converts between int, the four 64-bit integers, the character types, short, _Bool, float, double and a pointer')
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
	if target.kind == .float {
		// A conversion to a float: a double is rounded to four bytes and an
		// integer is converted to the nearest float, which is the same
		// conversion the language makes when a value is stored into a float.
		// A pointer is refused by name for the reason it is refused for a
		// double.
		e.convert_to_single(cast.expr, cast.line, cast.col)!
		return
	}
	if floating {
		if target.kind == .pointer {
			e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from a double to ${cast.spelling}, and a floating type is not a value an address is made of')
			return error('double to a pointer')
		}
		if target.kind == .bool_ {
			// A floating value converted to `_Bool` is the comparison with zero
			// and not the truncation to an integer: 6.3.1.2 makes `(_Bool)-0.5`
			// 1, where truncating -0.5 toward zero leaves 0 and the store then
			// reports the value as zero. Measured on gcc 16.2.1.
			return e.normalize_a_bool_value(cast.expr, cast.line, cast.col)
		}
		if e.eight_byte_integer(target) {
			// The conversion is made at the destination's width, so a 64-bit
			// integer target is the eight-byte truncation and nothing here
			// widens a value that is already whole.
			e.convert_to_int(cast.expr, target.is_unsigned_type(), e.target.word_size, cast.line, cast.col)!
			return
		}
		e.convert_to_int(cast.expr, target.is_unsigned_type(), e.storage_width(target) or { 0 }, cast.line, cast.col)!
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
			if cast.expr.typ.is_unsigned_type() {
				e.append(e.target.move_register32(register, register)!)
			} else {
				e.append(e.target.sign_extend_word(register, register)!)
			}
		}
		return
	}
	if target.kind == .pointer {
		if !e.is_a_pointer(cast.expr) {
			if source == 8 {
				// An address is eight bytes and so is this value in the
				// register: a long, an unsigned long or a long long that holds
				// an address is left as it is. Narrowing it to four bytes and
				// widening the low word back would answer an address the value
				// never was, and the high word is exactly what the round trip
				// is asked to keep.
			} else if source == 4 {
				// A four-byte source is widened into the whole register, and
				// which bits open above it is the source's own signedness: an
				// int keeps its sign, and an unsigned int takes zeros. Measured
				// on gcc 16.2.1: `(char *)0xffffffffu` is the address
				// 0xffffffff, which sign-extending would have made all ones.
				if cast.expr.typ.is_unsigned_type() {
					e.append(e.target.move_register32(register, register)!)
				} else {
					e.append(e.target.sign_extend_word(register, register)!)
				}
			} else {
				// A source this back end cannot size is not a value an address
				// is made of, and answering with a plausible one would be a
				// wrong address rather than a refusal.
				e.diagnostics << problem(cast.line, cast.col, 'unsupported: a conversion from ${cast.expr.typ.describe()} to ${cast.spelling} is not one this back end makes, and the value has no width here to widen into an address')
				return error('no width for the address')
			}
		}
		return
	}
	if target.kind in [.char_, .signed_char] {
		// The low byte of the register is the char, and the bits above it are
		// that byte's sign, which is what this target's char is.
		e.append(e.target.sign_extend_byte(register)!)
	}
	if target.kind == .unsigned_char {
		// The same narrowing with zero above the byte rather than its sign,
		// which is what a value converted to an unsigned char carries.
		e.append(e.target.widen_byte(register)!)
	}
	if target.kind == .short {
		e.append(e.target.sign_extend_half(register)!)
	}
	if target.kind == .unsigned_short {
		e.append(e.target.zero_extend_half(register)!)
	}
	if target.kind == .bool_ {
		// 6.3.1.2: a value converted to _Bool is 0 when it is zero and 1 when it
		// is not, which is the comparison `x != 0` written out. The question is
		// asked at the width the value has in the register, so a long or a
		// pointer is tested as a whole word and the top half of 4294967296 is
		// not read as a zero word.
		if (e.storage_width(cast.expr.typ) or { 4 }) == 8 {
			e.append(e.target.test_word(register)!)
		} else {
			e.append(e.target.test(register)!)
		}
		e.append(e.target.set_condition(backend.Condition.not_equal, register)!)
		e.append(e.target.widen_byte(register)!)
		return
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
	return match t.enum_underlying() {
		.bool_, .char_, .signed_char, .unsigned_char { 1 }
		.short, .unsigned_short { 2 }
		.int_, .unsigned_int { 4 }
		.long, .unsigned_long, .long_long, .unsigned_long_long { 8 }
		.pointer, .array { e.target.word_size }
		else { none }
	}
}

// load_indirect_value reads a value of the given width through an address in a
// register. A one- or two-byte value is widened on the way in, and which bits go
// above it is the type's signedness: an unsigned character type or an unsigned
// short takes zeros there and anything else takes the value's sign. A store into
// one is the same instruction either way, because the bytes written are the low
// ones of the value in both cases. The value's register is separate from the
// address's because one caller keeps the address in a register while the value
// lands in the accumulator.
fn (mut e Emitter) load_indirect_value(address backend.Register, destination backend.Register, unsigned bool, width int) !void {
	if unsigned && width < 4 {
		e.append(e.target.load_indirect_unsigned(address, destination, width)!)
		return
	}
	e.append(e.target.load_indirect(address, destination, width)!)
}

// load_bitfield reads a bitfield member's own bits out of the storage unit it
// shares with the members around it. The unit is read at its full width and the
// field is shifted down to the bottom of the register, then extended back to the
// width of the register: a signed field keeps its sign, and an unsigned one is
// filled with zero. The shift pair that extends it also clears the bits above the
// field, so no separate mask is needed, and that is what makes the read agree
// with gcc for a field narrower than its storage unit. The unit is read zero-
// filled because the field's bits are then cut out of the low end of it: reading
// it with its sign would put ones above the unit that no mask below the field
// could tell from the field's own sign.
fn (mut e Emitter) load_bitfield(register backend.Register, field ast.Field, width int) !void {
	unit := if field.unit_width > 0 { field.unit_width } else { width }
	if unit <= 0 || unit > 8 {
		e.diagnostics << problem(field.line, field.col, 'unsupported: the bitfield ${field.name}.${field.member} lies in a storage unit this back end has no load for')
		return error('unsupported bitfield unit')
	}
	e.append(e.target.load_indirect_unsigned(register, register, unit)!)
	if field.bit_offset > 0 {
		e.append(e.target.shift_right_word(register, u8(field.bit_offset))!)
	}
	if field.bit_width > 0 && field.bit_width < 64 {
		extend := u8(64 - field.bit_width)
		e.append(e.target.shift_left_word(register, extend)!)
		if e.written_is_unsigned(field.spelling) {
			e.append(e.target.shift_right_word(register, extend)!)
		} else {
			e.append(e.target.shift_right_arithmetic(register, extend)!)
		}
	}
}

// eight_byte_integer says whether a type is one of the four 64-bit integer types,
// which is the question a value of eight bytes has to be asked before it is
// treated as a pointer: a pointer is eight bytes too, and the machine's word is
// what an address moves in.
fn (e Emitter) eight_byte_integer(t types.Type) bool {
	return t.enum_underlying() in [types.Kind.long, .unsigned_long, .long_long, .unsigned_long_long]
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
	return common.is_unsigned_type()
}

// emit_deref reads through an address: the operand is computed into the register,
// and the value at that address is loaded at the width of what the address points
// at. A char is loaded with its sign, which is what makes it the int the language
// promotes it to, and a double is loaded by the instruction that moves one rather
// than by an integer load of the same width. A pointed-at type with no load here
// is refused by name.
//
// An operand that points at a function is the one case with nothing in memory to
// read: 6.5.3.2p4 makes `*` on it the function designator, and a function value
// is the address of its code, which is what the operand is already worth. A
// function name is worth that address through 6.3.2.1p4 and a pointer to a
// function holds it, so the operand is emitted and no load follows.
fn (mut e Emitter) emit_deref(unary ast.Unary, depth int) !void {
	if unary.typ.is_function() {
		return e.emit_expr_at(unary.expr, depth)
	}
	e.emit_expr_at(unary.expr, depth + 1)!
	address := e.accumulator(unary.line, unary.col)!
	if unary.typ.is_array() {
		// `*p` where p points at an array is the array, and an array's value is
		// the address of its first element: the elements are at the address and
		// are not read here. Measured on gcc 16.2.1: `int (*row)[3] = &arr;
		// (*row)[1]` reads arr[1], and reading the array's bytes into a register
		// instead leaves a small number where an address was expected, so a
		// subscript of it reads through that number.
		return
	}
	if unary.typ.kind == .double {
		double_register := e.float_accumulator(unary.line, unary.col)!
		e.append(e.target.load_double_indirect(address, double_register)!)
		return
	}
	if unary.typ.kind.is_extended() {
		// The object at the address is a long double, whose value is the address
		// of its sixteen bytes: there is no register to read them into.
		return
	}
	width := e.storage_width(unary.typ) or {
		e.diagnostics << problem(unary.line, unary.col, 'unsupported: * reads through an address of ${unary.typ.describe()}, and this back end reads ints, chars, doubles and pointers only')
		return error('unsupported pointed-at type')
	}
	e.load_indirect_value(address, address, unary.typ.is_unsigned_type(), width)!
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
	frame := e.slot_base_register(slot, line, col)!
	word := e.target.word_size
	e.append(e.target.load_slot(frame, slot.offset + at * word, reg, word)!)
}

fn (mut e Emitter) wide_store_word(slot Slot, at int, reg backend.Register, line int, col int) !void {
	frame := e.slot_base_register(slot, line, col)!
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
	frame := e.slot_base_register(slot, line, col)!
	low := e.accumulator(line, col)!
	high := e.remainder(line, col)!
	word := e.target.word_size
	e.append(e.target.store_slot(frame, slot.offset, low, word)!)
	e.append(e.target.store_slot(frame, slot.offset + word, high, word)!)
}

// load_pair reads a pair back out of a slot, and is the other half of store_pair.
fn (mut e Emitter) load_pair(slot Slot, line int, col int) !void {
	frame := e.slot_base_register(slot, line, col)!
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
	frame := e.slot_base_register(slot, line, col)!
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
		e.widen_into_pair(left, step.left.typ.is_unsigned_type(), e.narrow_width(step.left.typ), step.line, step.col)!
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
		e.widen_into_pair(right, step.right.typ.is_unsigned_type(), e.narrow_width(step.right.typ), step.line, step.col)!
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
	e.wide_load_word(right, 0, other, step.line, step.col)!
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

// is_pointer_step says whether a step is one of the operators that add an
// integer to an address, subtract one from it, or subtract one address from
// another: `p + 1`, `1 + p`, `p - 1` and `q - p`. 6.5.6 scales the integer by the
// size of the pointed-at type and divides two addresses' byte difference by the
// same size, which is why none of these is the integer operation the rest of the
// arithmetic is.
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
		// A string is scaled by the size of one of its characters: a byte for an
		// ordinary string and four for a wide one, whose elements are wchar_t.
		element := expr.typ.element() or { return none }
		return e.representation.size_of(element)
	}
	return none
}

// emit_pointer_step writes an address plus or minus an index, or the difference
// of two addresses. For an index: the address is the base's own value, the index
// is scaled by the size of one pointed-at element, and the two are added. `p + 1`
// and `1 + p` are the same address because addition commutes, and `p - 1` is the
// same address with the scaled index negated.
//
// The spine walk has already put the step's left operand in the accumulator, so
// the left side is not emitted again: it is parked while the right side runs, and
// the two are put back together. That is why a chain of steps is walked and not
// re-read at every step.
fn (mut e Emitter) emit_pointer_step(step ast.Binary, depth int) !void {
	left_is_address := e.is_a_pointer(step.left)
	right_is_address := e.is_a_pointer(step.right)
	if left_is_address && right_is_address {
		return e.emit_pointer_difference(step, depth)
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

// emit_pointer_difference writes `q - p` for two addresses: the difference of
// their byte values divided by the size of one pointed-at element, which is the
// count 6.5.6p9 asks for. The count is 6.5.6p9's `ptrdiff_t`, which the reader
// types as a signed `long` on this target, so the division is the signed one: a
// difference that reads the bytes as unsigned answers `p - q` with a huge
// positive count where the language asks for a negative one.
//
// The spine walk has already put the left address in the accumulator, so the left
// side is parked while the right side runs; the right address is copied to the
// scratch register, the left is loaded back into the accumulator, and the two are
// subtracted at the width of a word. The element size is a constant the reader
// and this back end both know, so it reaches the divisor register as an immediate
// and the pair the accumulator and the register above it form is divided by it.
//
// The difference of two byte addresses is exact in the element size, so the signed
// division has no remainder to drop. A pair whose element type has no size, or
// whose two element types differ, was refused where it was written, and the size
// read here is the left operand's own.
//
// Measured on gcc 16.2.1: for `int a[6]` with `p = &a[0]` and `q = &a[4]`, `q - p`
// is 4 and `p - q` is -4; over the same addresses through `char *` they are 16 and
// -16; and `(q - p) < 0` is 1 for the negative one, which is the signedness this
// division keeps.
fn (mut e Emitter) emit_pointer_difference(step ast.Binary, depth int) !void {
	if step.op != '-' {
		e.diagnostics << problem(step.line, step.col, 'unsupported: the sum of two addresses is not an expression this compiler types')
		return error('sum of two addresses')
	}
	stride := e.difference_stride(step) or {
		e.diagnostics << problem(step.line, step.col, 'unsupported: the difference of two addresses counts elements of ${step.left.typ.describe()}, and this back end has no size for one')
		return error('no element size for a difference')
	}
	base := e.value_slot(depth)
	e.store_accumulator(base, step.line, step.col)!
	e.emit_expr_at(step.right, depth + 1)!
	right := e.accumulator(step.line, step.col)!
	left := e.scratch(step.line, step.col)!
	e.append(e.target.move_register64(left, right)!)
	e.load_argument(base, right, e.target.word_size, step.line, step.col)!
	e.append(e.target.subtract_word(right, left)!)
	if stride != 1 {
		e.append(e.target.move_immediate64(left, u64(stride))!)
		e.append(e.target.divide_word(left)!)
	}
}

// difference_stride is how many bytes one element of the difference's pointed-at
// type takes, which is what the byte difference is divided by. It is the element
// size `pointed_size` already answers for an array or a pointer, with one case
// added: the GNU dialects accept the difference of two `void *`, whose pointed-at
// type has no size, and gcc 16.2.1 counts such a difference in bytes, so a `void *`
// steps by one. Measured on gcc 16.2.1 with `-std=gnu99`: `void *a = b, *c = b + 5;`
// gives `c - a` as 5.
fn (e Emitter) difference_stride(step ast.Binary) ?int {
	if step.left.typ.is_pointer() {
		pointee := step.left.typ.pointee() or { return none }
		if pointee.is_void() {
			return 1
		}
	}
	return e.pointed_size(step.left)
}

fn (mut e Emitter) emit_binary(binary ast.Binary, depth int) !void {
	if binary.typ.is_vector() {
		// A vector value in an expression position other than the initializer
		// of a vector declaration is not implemented here. The parser lowers
		// `v4si c = a + b;` into element stores, so the sum never reaches this
		// back end as a value; one that does - `(a + b)[0]`, or a sum handed to
		// a function - has no path, and refusing it by name is the honest
		// answer rather than computing one lane or a wrong width.
		e.diagnostics << problem(binary.line, binary.col, 'unsupported: the vector value ${binary.typ.describe()} is used where this back end does not compute it, and a vector is implemented only as the initialized object of a declaration')
		return error('vector value')
	}
	// A step with a complex operand is a comparison: the arithmetic is written by
	// the complex paths into an object, and a step that reaches here is one whose
	// value is wanted in the accumulator, which is a comparison and nothing else,
	// because C99 defines no ordering on the complex types.
	if binary.left.typ.kind.is_complex() || binary.right.typ.kind.is_complex() {
		return e.emit_complex_comparison(binary, depth)
	}
	if e.extended_step(binary) {
		return e.emit_extended_binary(binary, depth)
	}
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
		spine << step
		node = step.left
	}
	// The chain is counted before a term of it is classified. A chain is one node
	// deep in the grammar however many terms it has, so max_emit_depth does not
	// see it, and asking the width of the part below a term is work that grows
	// with the chain. A chain past max_emit_chain is reported here, at the operand
	// it starts from, rather than walked and classified term by term.
	if spine.len > max_emit_chain {
		start := spine[spine.len - 1].left
		e.diagnostics << problem(expr_line(start), expr_col(start), 'unsupported: this expression is a chain of ${spine.len} operators, more than the ${max_emit_chain} this back end emits')
		return error('operator chain too long')
	}
	for step in spine {
		if e.long_double_of(step.left) || e.long_double_of(step.right) {
			// An operation on a long double is refused where it is written. The
			// machine's SSE register file is as wide as a double, so computing
			// it here would store a value narrower than the type says it is,
			// with no diagnostic, which is the outcome this tree treats as a bug.
			return e.refuse_a_long_double_operation(step.op, step.line, step.col)
		}
	}
	for step in spine {
		if !e.is_pointer_step(step) {
			e.check_int_operands(step)!
		}
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
		// A division by a constant zero is not refused here. C99 6.6 makes it an
		// error only where a constant expression is required, and this is not
		// such a place: measured against gcc 16.2.1, `x / 0`,
		// `1 ? 2 : (x / 0)` and `1 ? 2 : (1/0)` all compile there, with a
		// warning at most, while this emitter refused all three. A division that
		// runs is undefined behaviour, which is not the same thing as a
		// diagnostic, and the two conditional arms above are not even evaluated.
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
		if e.computed_in_floats(step) {
			single := e.computed_in_singles(step)
			e.convert_to_float_class(step.left, single, step.line, step.col)!
			e.store_float_accumulator(slot, single, step.line, step.col)!
			e.emit_expr_at(step.right, depth + 1)!
			e.convert_to_float_class(step.right, single, step.line, step.col)!
			e.move_float_to_scratch(single, step.line, step.col)!
			e.load_float_accumulator(slot, single, step.line, step.col)!
			e.apply_float(step, single)!
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
	if operand.typ.is_unsigned_type() {
		e.append(e.target.move_register32(register, register)!)
	} else {
		e.append(e.target.sign_extend_word(register, register)!)
	}
}

// computed_in_floats says whether a step's operands are computed in the
// floating-point file. The language's usual arithmetic conversions make a step
// with a floating operand on either side a floating step, whether the operator is
// arithmetic or a comparison: `d < 1` compares a double with the int widened to
// one, and answers with an int. A step that is neither a comparison nor one of
// the four arithmetic operators is refused where it is folded, because the
// operators that need integer operands do not have a floating form the language
// defines.
fn (e Emitter) computed_in_floats(step ast.Binary) bool {
	if !(e.floating_of(step.left) || e.floating_of(step.right)) {
		return false
	}
	return step.op == '+' || step.op == '-' || step.op == '*' || step.op == '/'
		|| step.op in ['==', '!=', '<', '>', '<=', '>=']
}

// computed_in_singles says whether such a step is computed at four bytes. The
// usual arithmetic conversions decide that from the operands: a float with an
// integer or another float is a float step, and a double anywhere in the step
// makes the whole of it a double step. Where the step carries the type the reader
// resolved, that type is the answer; the operand rule is for a tree assembled by
// hand, which no reader has resolved.
fn (e Emitter) computed_in_singles(step ast.Binary) bool {
	if !e.computed_in_floats(step) {
		return false
	}
	if step.typ.kind != .unknown {
		return step.typ.kind == .float
	}
	return !(e.double_of(step.left) || e.double_of(step.right))
}

// convert_to_float_class makes an operand of a floating step the class the step
// is computed in, which is the operand's own class when it is already that one and
// the conversion the language defines otherwise.
fn (mut e Emitter) convert_to_float_class(expr ast.Expr, single bool, line int, col int) !void {
	if single {
		return e.convert_to_single(expr, line, col)
	}
	return e.convert_to_double(expr, line, col)
}

// store_float_accumulator and load_float_accumulator park a half-finished
// operand of a floating step in a frame slot and read it back. The slot is the
// same one at both widths; what differs is how many of its bytes the instruction
// moves, which is why the width travels here.
fn (mut e Emitter) store_float_accumulator(slot Slot, single bool, line int, col int) !void {
	if single {
		return e.store_single_accumulator(slot, line, col)
	}
	return e.store_double_accumulator(slot, line, col)
}

fn (mut e Emitter) load_float_accumulator(slot Slot, single bool, line int, col int) !void {
	if single {
		return e.load_single_accumulator(slot, line, col)
	}
	return e.load_double_accumulator(slot, line, col)
}

// apply_float does the operation the tree asked for with both values in the
// floating-point file, the left in the accumulator and the right in the scratch
// register, and leaves a floating value in the accumulator or an int there when
// the operator was a comparison. The instruction is the one for the width the
// step is computed at: adding two doubles and adding two floats are two
// instructions, and computing the second with the first would round once at the
// end instead of at every step.
fn (mut e Emitter) apply_float(step ast.Binary, single bool) !void {
	value := e.float_accumulator(step.line, step.col)!
	other := e.float_scratch(step.line, step.col)!
	match step.op {
		'+', '-', '*', '/' {
			if single {
				e.append(e.target.float_arithmetic(step.op, value, other)!)
			} else {
				e.append(e.target.double_arithmetic(step.op, value, other)!)
			}
		}
		'==', '!=', '<', '>', '<=', '>=' {
			// The answer to a comparison is an int, so it is read out of the
			// flags into the general register file: the floating-point one
			// holds values and not truth values. Comiss and Comisd set the same
			// flags in the same places, so the code that reads an order out of
			// them is the same code at both widths.
			integer := e.accumulator(step.line, step.col)!
			byte_scratch := e.scratch(step.line, step.col)!
			if single {
				e.append(e.target.float_comparison(step.op, value, other, integer, byte_scratch)!)
			} else {
				e.append(e.target.double_comparison(step.op, value, other, integer, byte_scratch)!)
			}
		}
		else {
			e.diagnostics << problem(step.line, step.col, 'unsupported: ${step.op} takes integer operands, and one of these is a floating value')
			return error('operator on a floating value')
		}
	}
}

// move_float_to_scratch puts the floating-point accumulator into the
// floating-point scratch register, which is where the operation that is about to
// be applied expects the right-hand value. The move is the one for the step's
// width: a float's four bytes and a double's eight are two instructions.
fn (mut e Emitter) move_float_to_scratch(single bool, line int, col int) !void {
	result := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	if single {
		e.append(e.target.move_float(other, result)!)
		return
	}
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
	unsigned := binary.typ.is_unsigned_type()
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
			unsigned_shift := binary.left.typ.is_unsigned_type()
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
//
// The operands are scalars. 6.5.13 and 6.5.14 give both operators an operand of
// scalar type, which is an arithmetic type or a pointer, and each side is asked
// whether it is zero by emit_test. A pointer's question is its comparison with
// the null pointer, which is the word-wide test emit_test writes, so a pointer
// is an operand here rather than an int that did not arrive: gcc 16.2.1 compiles
// `p && "message"` and `q || "message"` for both a null and a non-null pointer,
// and the int-operand check this call used to make refused all of them.
fn (mut e Emitter) emit_short_circuit(binary ast.Binary, depth int) !void {
	result := e.accumulator(binary.line, binary.col)!
	settles := e.label()
	end := e.label()
	is_and := binary.op == '&&'
	// The jump the left side takes when it has already settled the answer: out
	// of an and when it is false, out of an or when it is true.
	e.emit_condition(binary.left, depth + 1, binary.line, binary.col)!
	if is_and {
		e.branch(.branch_zero, settles, binary.line, binary.col)!
	} else {
		e.branch(.branch_nonzero, settles, binary.line, binary.col)!
	}
	// The left side did not settle it, so the right side is the answer.
	e.emit_condition(binary.right, depth + 1, binary.line, binary.col)!
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
	// 6.5.15 evaluates only the arm the condition selects, and a condition the
	// reader folded to a literal selects the same arm on every run. Writing the
	// other arm would hand the back end a construct that never executes, so a
	// construct it cannot emit for the untaken arm would refuse a program it
	// should accept. `isinf` on a long double is that shape: the type dispatch
	// its false test carries names a call for a type the machine does not have,
	// and only the arm the constant does not select is left to be emitted.
	if conditional.cond is ast.IntLit {
		value := (conditional.cond as ast.IntLit).value
		arm := if value != 0 { conditional.then_expr } else { conditional.else_expr }
		if conditional.typ.kind.is_extended() {
			temp := e.extended_temp(arm, depth + 1)!
			return e.leave_address(temp, conditional.line, conditional.col)
		}
		return e.emit_conditional_arm(arm, conditional.typ, depth)
	}
	if conditional.typ.kind.is_extended() {
		// The two arms are values of the extended type, and a value of that type
		// is the address of its sixteen bytes, so the branch carries the address
		// of whichever arm ran the way it carries a register elsewhere.
		return e.emit_extended_conditional(conditional, depth)
	}
	if e.wide_value(ast.Expr(conditional)) {
		// Two arms of a 128-bit type would each have to leave a pair of
		// registers, and the branch machinery carries one value. Saying so
		// keeps the arms from being emitted at a width nothing reads.
		e.diagnostics << problem(conditional.line, conditional.col, 'unsupported: a conditional whose arms have a 128-bit type is not implemented')
		return error('128-bit conditional')
	}
	if conditional.omitted_middle {
		return e.emit_reuse_conditional(conditional, depth)
	}
	e.emit_condition(conditional.cond, depth + 1, conditional.line, conditional.col)!
	else_label := e.label()
	end_label := e.label()
	e.branch(.branch_zero, else_label, conditional.line, conditional.col)!
	e.emit_conditional_arm(conditional.then_expr, conditional.typ, depth)!
	e.jump(end_label)!
	e.place(else_label)
	e.emit_conditional_arm(conditional.else_expr, conditional.typ, depth)!
	e.place(end_label)
}

// emit_reuse_conditional writes the GNU `a ?: b`, whose middle operand was left
// out and is the condition's own value. The condition is evaluated once and the
// value it leaves is the middle operand's: measured on gcc 16.2.1, `x++ ?: y`
// steps x a single time and is worth the value x held before the step, so a shape
// that read the condition twice would run its side effect twice.
//
// The test and the branch leave the value where the condition's own evaluation
// put it, in the register a value lives in, so no temporary is needed to keep it:
// for an integer or pointer condition the truth test writes no register, and for
// a floating condition the test reads the floating-point register and leaves it
// alone. The arm the condition selects is then that same value, and only the
// conversion to the type the conditional is worth is left to make, which is the
// conversion `emit_conditional_arm` makes for a written arm.
fn (mut e Emitter) emit_reuse_conditional(conditional ast.Conditional, depth int) !void {
	condition := conditional.cond
	e.emit_condition(condition, depth + 1, conditional.line, conditional.col)!
	else_label := e.label()
	end_label := e.label()
	e.branch(.branch_zero, else_label, conditional.line, conditional.col)!
	if conditional.typ.is_floating() {
		if conditional.typ.kind == .float {
			e.convert_to_single(condition, conditional.line, conditional.col)!
		} else {
			e.convert_to_double(condition, conditional.line, conditional.col)!
		}
	} else if e.eight_byte_integer(conditional.typ) {
		e.extend_operand_to_word(condition, conditional.line, conditional.col)!
	}
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
//
// A float result converts the arm to a float and not to a double, which is the
// difference between the two floating widths: the arm's value has to be the type
// the conditional is worth, and a whole-number float widened to double puts its
// four bytes in the upper half of the register, so the float store a use of the
// conditional makes reads the low half and finds zero. An arm already a float
// needs no conversion, an integer arm is converted into the register, and a
// double arm is narrowed to the result the conditional has.
fn (mut e Emitter) emit_conditional_arm(arm ast.Expr, result types.Type, depth int) !void {
	e.emit_expr_at(arm, depth + 1)!
	if result.is_floating() {
		if result.kind == .float {
			e.convert_to_single(arm, expr_line(arm), expr_col(arm))!
		} else {
			e.convert_to_double(arm, expr_line(arm), expr_col(arm))!
		}
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
	return match t.enum_underlying() {
		.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short, .int_,
		.unsigned_int {
			4
		}
		.long, .unsigned_long, .long_long, .unsigned_long_long { 8 }
		.double { 8 }
		// A float in a register is four bytes, which is the width a conversion
		// reads it at: the value a cast to an integer left in the general
		// register is four bytes wide because the float it came from was.
		.float { 4 }
		.pointer, .array { e.target.word_size }
		else { none }
	}
}

// width_of is the width of the value an expression has, four bytes for an int
// and the machine's word for a pointer. It is what keeps an int and a pointer
// apart where the machine would otherwise take one for the other, and none is
// the honest answer for an expression this back end cannot size.
//
// The left spine of an operator chain is walked with a loop and only a genuinely
// nested operand recurses, for the reason the constant fold and the emitter's own
// walk do it: `a + b + c ...` is one node deep in the grammar and thousands deep in
// the tree, and asking the width of the part below each term is what used to take
// the stack out at about two thousand terms. Measured on an 8 MB stack, a chain of
// three thousand `+ x` terms took signal 11 here while the same chain of constants
// folded; the loop is what makes the count max_emit_chain checks reachable.
fn (e Emitter) width_of(expr ast.Expr) ?int {
	return e.width_of_at(expr, 0)
}

fn (e Emitter) width_of_at(expr ast.Expr, depth int) ?int {
	if depth > max_emit_depth {
		return none
	}
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
			// A floating constant is the width its suffix named: four bytes for
			// a float, and eight for a double, whose bytes live in the image and
			// are read into a floating-point register.
			if expr.typ.kind == .float { 4 } else { 8 }
		}
		ast.ComplexLit {
			// An imaginary constant is a complex value, so the width a value
			// of it is sized at is the size the model laid out for its type.
			// A type the description does not carry has no answer here.
			e.storage_width(expr.typ)
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
			//
			// A member whose type is an array is not read at all: it decays to
			// a pointer to its first element (6.3.2.1p3), so the value it is
			// worth is the machine's word. A flexible array member is the same,
			// and it has no width of its own to answer with.
			if expr.typ.is_array() {
				return e.target.word_size
			}
			width := e.type_width(expr.spelling) or { return none }
			return if width < 4 { 4 } else { width }
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
					return if object.width < 4 { 4 } else { object.width }
				}
				if e.is_function_name(expr.name) {
					// 6.3.2.1: a function designator used as a value is the
					// pointer to the function, which is the machine's word.
					return e.target.word_size
				}
				return none
			}
			// An array's name is the address of its first element, which is a
			// pointer. A char in an expression is an int: the language promotes
			// it, and the load that reads it is where that happens, so the width
			// of the value is the width of the read rather than of the slot.
			if slot.is_array() {
				e.target.word_size
			} else if slot.width < 4 {
				4
			} else {
				slot.width
			}
		}
		ast.Call {
			// A call's value has the width the language returns it with, which
			// is the type its declaration wrote: a double is eight bytes in the
			// floating-point file, a long is eight in the general one, and
			// anything else this back end emits is four. A narrow integer return
			// type is four as well, because the register holds the widened value
			// the way it holds an int, which is the width every use of it reads.
			// A call through an expression reads the same answer off the type the
			// parser resolved onto the call.
			if typ := indirect_call_returns(expr) {
				width := e.type_width(typ.describe()) or { 4 }
				return if width < 4 { 4 } else { width }
			}
			// A call the unit declares no return type for is one the reader
			// built itself from a spelling in the compiler's own namespace: the
			// machine builtins and the argument-list operations. The type the
			// reader resolved onto the call is the only thing that says how
			// wide its value is, and a 64-bit fetch whose result was sized at
			// four bytes would be refused where it is stored in a 64-bit
			// object.
			if expr.name !in e.returns {
				if width := e.converted_width(expr.typ) {
					return width
				}
			}
			width := e.type_width(e.returns[expr.name]) or { 4 }
			if width < 4 { 4 } else { width }
		}
		ast.Index {
			// An element is the width of the element's type, with a char
			// promoted to the int the load widens it to. An element that is
			// itself an array is worth the address of its first element.
			if expr.typ.is_array() {
				return e.target.word_size
			}
			width := e.storage_width(expr.typ) or { return none }
			if width < 4 {
				4
			} else {
				width
			}
		}
		ast.Unary {
			if expr.op == '&&' {
				// The address of a label is a `void *`, so the machine's word.
				e.target.word_size
			} else if expr.op == '!' {
				4
			} else if expr.op == '&' {
				// The address of a value is a pointer, whatever the width of the
				// value that lives there.
				e.target.word_size
			} else if expr.op == '*' {
				// A read through an address has the width of the class the value
				// at it belongs to: a char arrives as the int it is promoted to,
				// an int as itself, and a pointer as the machine's word.
				if expr.typ.is_function() {
					// A read through an operand that points at a function is the
					// function designator again (6.5.3.2p4), and a designator used
					// where a value is wanted is the pointer to the function
					// (6.3.2.1p4): the value is the machine's word, and there is
					// nothing at an address to read.
					return e.target.word_size
				}
				e.converted_width(expr.typ)
			} else if expr.op == '__real__' || expr.op == '__imag__' {
				// One component of a complex value, at the component's own
				// width: a part is a real value of the component's type, so the
				// node's own type answers the same way a converted value's does.
				e.converted_width(expr.typ)
			} else {
				e.width_of_at(expr.expr, depth + 1) or { return none }
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
			// Walk the left spine with a loop. Each step on it is asked the
			// same four questions in the same order, and the walk stops at the
			// first step whose answer the step alone decides, or at the operand
			// under the last step. The part below a step is its own width only
			// where that asked-for width equals the step's right operand's, so
			// the answers are folded back up the spine once the leaf is known.
			mut spine := []ast.Binary{}
			mut node := ast.Expr(expr)
			mut decided := false
			mut answer := 0
			for node is ast.Binary {
				step := node as ast.Binary
				if step.op in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'] {
					// A comparison is a value of int width however wide its
					// operands are.
					answer = 4
					decided = true
					break
				}
				if e.is_pointer_step(step) {
					// An address moved by an index is still an address, and an
					// address is the machine's word whatever it points at.
					answer = e.target.word_size
					decided = true
					break
				}
				if e.floating_of(step) {
					// An arithmetic step with a floating operand on either side
					// is a step of that class, whichever class the other operand
					// was: the two widths are not equal in the tree, and the
					// value the step produces is one value of the floating class
					// either way. Which of the two widths it is comes from the
					// conversions the step was computed with, so the step is
					// asked the same question the emitter asks before it writes
					// the instruction.
					answer = if e.computed_in_singles(step) { 4 } else { 8 }
					decided = true
					break
				}
				if e.step_is_wide(step) {
					// A step with a 64-bit integer on either side is a value of
					// eight bytes. The two operands need not be the same width:
					// the usual arithmetic conversions make the step's type the
					// wider of the two, the narrower operand is widened where the
					// step is emitted, and the answer is the wider width.
					answer = 8
					decided = true
					break
				}
				spine << step
				node = step.left
			}
			mut width := if decided {
				answer
			} else {
				e.width_of_at(node, depth + 1) or { return none }
			}
			for i := spine.len - 1; i >= 0; i-- {
				right := e.width_of_at(spine[i].right, depth + 1) or { return none }
				if width != right {
					return none
				}
			}
			width
		}
		ast.IncDec {
			// The value is the one the operand holds, so it is sized the way
			// the operand is: a char is the int the load widens it to, which
			// is the promotion the operator's value gets in an expression.
			e.width_of_at(expr.operand, depth + 1) or { return none }
		}
		ast.Conditional {
			// Both arms are converted to the type the conditional is worth
			// before they meet, so the width is that type's and not the width
			// of whichever arm the tree happens to hold first.
			e.converted_width(expr.typ)
		}
		ast.Assign, ast.Comma {
			// An assignment is worth the object's value after the store and a
			// comma the value of its right operand; both are the type the
			// reader resolved for the node, which is what the width comes from.
			e.converted_width(expr.typ)
		}
		ast.StmtExpr {
			// A statement expression is worth its last expression statement's
			// value, whose type the reader resolved for the node.
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

// emit_function_address leaves the address of a function in the accumulator. 6.3.2.1
// makes a function designator used as a value the pointer to that function, so
// `int (*p)(void) = f;` and `p = &f;` both reach this: what a value of a function
// type is worth is where the function's code begins. A function this file defines
// has its code here, so the address is a reference the layout fills in. One the
// file only declares has its code somewhere the image is not, so its address is a
// symbol the loader resolves: it is read out of the slot the loader fills, the same
// slot a call to that function goes through, and in an object the reference is left
// for the linker the way a call to a declared function is. The address is not known
// while it is written, so it is filled in either way.
fn (mut e Emitter) emit_function_address(name string, line int, col int) !void {
	register := e.accumulator(line, col)!
	if name in e.program.defined {
		e.reference(e.target.address_of(register, 0), .function_address, name, e.target.name_of(register))
		return
	}
	if name !in e.returns {
		e.diagnostics << problem(line, col, 'unsupported: the address of ${name} is not implemented, and only a function this unit declares has one this back end can take')
		return error('no function address')
	}
	e.import_symbol(name)
	if e.compile_only {
		// An object has no slots and no loader: it leaves the reference for the
		// linker to route, which is what a call to a symbol means in a
		// relocatable file.
		e.reference(e.target.address_of(register, 0), .import_address, name, e.target.name_of(register))
	} else {
		e.reference(e.target.load_slot_value(register, 0), .import_address, name, e.target.name_of(register))
	}
}

// emit_label_address leaves the address of a label in the accumulator, which is
// the value of `&&name`. The label is a place in the function being emitted, so
// its address is a reference the layout fills in, the same reference a function
// designator's address is and through the same kind: the layout resolves a
// label name against the function's own label table. Writing the name is a use
// of the label, so a name no label statement writes is reported once the whole
// function has been emitted, exactly as a goto to one is.
fn (mut e Emitter) emit_label_address(unary ast.Unary) !void {
	if unary.expr !is ast.Ident {
		e.diagnostics << problem(unary.line, unary.col, 'unsupported: the address of a label is taken with && and what follows must be a label name')
		return error('no label name')
	}
	name := unary.expr.name
	if !(name in e.goto_used) {
		e.goto_used[name] = LabelUse{
			line: unary.line
			col:  unary.col
		}
	}
	register := e.accumulator(unary.line, unary.col)!
	e.reference(e.target.address_of(register, 0), .function_address, e.named_label(name), e.target.name_of(register))
}

// is_function_name says whether a name is a function this unit names, whether it
// defines the function or only declares it. 6.3.2.1 makes either one, written
// where a value is wanted, the pointer to that function, so both are worth where a
// value is wanted; only where the address comes from differs.
fn (e Emitter) is_function_name(name string) bool {
	return name in e.program.defined || name in e.returns
}

// emit_callee_value leaves the address a call goes to in the accumulator. It is
// the value of the callee with 6.3.2.1's conversion applied: a function designator
// is the address of its code, and the dereference of a pointer to a function is
// that pointer itself, because `(*fp)(1, 2)` calls the address fp holds and a
// value of a function type is not something this machine reads out of memory.
fn (mut e Emitter) emit_callee_value(callee ast.Expr, depth int) !void {
	if callee is ast.Unary {
		if callee.op == '*' {
			return e.emit_expr_at(callee.expr, depth)
		}
	}
	if callee is ast.Ident {
		// A local of the same name is the object it names, so the designator is
		// read as a function only when nothing in scope holds that name.
		if e.lookup(callee.name) == none && e.is_function_name(callee.name) {
			return e.emit_function_address(callee.name, callee.line, callee.col)
		}
	}
	return e.emit_expr_at(callee, depth)
}

// The four operations over an argument list are not calls to a name: the reader
// built them from spellings in the compiler's own namespace, and the answer for
// each is a sequence of instructions rather than a symbol the loader would look
// for. They are answered here, before the call path, because that path would
// otherwise write a call to a name the image does not hold.
//
// Each of them is the calling convention's, read out of `backend/abi`: where the
// register files start, which register carries which argument, and where the
// arguments that did not fit in a register are. Nothing here decides any of it.

// the_argument_list answers the slot of the object a name denotes when that
// object is an argument list, and refuses the name when it is not.
//
// An object that is not a list holds something that is not a tag, and every one
// of the four operations would read that something as though it were one: a
// `va_arg(int x, int)` would take the value of x for the address of a tag and
// read a walk out of whatever it happens to point at. gcc 16.2.1 refuses every
// one of these, and so does this.
fn (mut e Emitter) the_argument_list(name string, operation string, line int, col int) ?Slot {
	slot := e.lookup(name) or {
		e.diagnostics << problem(line, col, 'unsupported: ${operation} names ${name}, and this function declares no object of that name')
		return none
	}
	if name !in e.argument_lists {
		e.diagnostics << problem(line, col, 'unsupported: ${operation} names ${name}, and ${name} is not an argument list: only an object declared with the argument-list type, which is what a `va_list` declaration makes, is one')
		return none
	}
	return slot
}

// save_argument_registers writes every argument register the caller may have
// filled into a save area in this frame, and answers the slot the area is.
//
// The vector registers are written at eight bytes each rather than at their own
// width: a variadic argument of a floating type is a double, which arrives in the
// low half of the register, and a sixteen-byte move would need the area on a
// sixteen-byte boundary, which a frame slot does not promise.
fn (mut e Emitter) save_argument_registers(decl ast.FnDecl) !Slot {
	area := abi.register_area()
	slot := e.reserve(area.bytes)
	base := e.frame_pointer(decl.line, decl.col)!
	for i in 0 .. area.gp_count {
		register := e.target.arg_reg(i) or {
			e.diagnostics << problem(decl.line, decl.col, 'internal: ${e.target.name} has not got the general argument register ${i + 1}, which the variadic save area writes')
			return error('no argument register')
		}
		e.append(e.target.store_slot(base, i32(slot.offset + i * area.gp_stride), register, e.target.word_size)!)
	}
	for i in 0 .. area.fp_count {
		register := e.target.float_arg_reg(i) or {
			e.diagnostics << problem(decl.line, decl.col, 'internal: ${e.target.name} has not got the vector argument register ${i + 1}, which the variadic save area writes')
			return error('no vector argument register')
		}
		e.append(e.target.store_double_slot(base, i32(slot.offset + area.fp_at + i * area.fp_stride), register)!)
	}
	return slot
}

// emit_va_start fills in the argument list a program declared, out of the save
// area the prologue wrote.
//
// The list is the tag the convention walks: where each register file has got to,
// where the arguments that went on the stack start, and where the registers were
// saved. Three of the four are known here without looking at anything at run
// time, because this is a property of the function being emitted: the counts of
// its named parameters say where each file has got to, and how many words of
// them the caller put on the stack says where the first unnamed word is. Only the
// save area is the frame's own address, which the prologue wrote down as a slot.
fn (mut e Emitter) emit_va_start(call ast.Call) !void {
	line := call.line
	col := call.col
	if !e.variadic {
		e.diagnostics << problem(line, col, 'unsupported: __builtin_va_start fills in an argument list, and a function whose parameter list ends in an ellipsis is the only one that has unnamed arguments')
		return error('no unnamed arguments')
	}
	area := e.save_area or {
		e.diagnostics << problem(line, col, 'internal: the variadic save area of this function was not written by its prologue')
		return error('no save area')
	}
	list := abi.argument_list()
	name := (call.args[0] as ast.Ident).name
	destination := e.the_argument_list(name, '__builtin_va_start', line, col) or {
		return error('no argument list')
	}
	base := e.frame_pointer(line, col)!
	slot := e.reserve(list.bytes)
	work := e.accumulator(line, col)!
	pointer := e.scratch(line, col)!
	// Where a walk through each register file starts, which is past the named
	// parameters that arrived in it.
	e.append(e.target.move_immediate32(work, u32(abi.gp_start(e.named_gp)))!)
	e.append(e.target.address_of_slot(base, i32(slot.offset + list.gp_offset_at), pointer))
	e.append(e.target.store_indirect(pointer, work, 4)!)
	e.append(e.target.move_immediate32(work, u32(abi.fp_start(e.named_fp)))!)
	e.append(e.target.address_of_slot(base, i32(slot.offset + list.fp_offset_at), pointer))
	e.append(e.target.store_indirect(pointer, work, 4)!)
	// The first word of the caller's stack past the named arguments. The return
	// address and the frame pointer are the two words between the frame pointer
	// and that first word, which is why the two are in the sum.
	e.append(e.target.address_of_slot(base, i32(2 * e.target.word_size + e.named_stacked * e.target.word_size), work))
	e.append(e.target.address_of_slot(base, i32(slot.offset + list.overflow_at), pointer))
	e.append(e.target.store_indirect(pointer, work, 8)!)
	// The registers the prologue saved.
	e.append(e.target.address_of_slot(base, area.offset, work))
	e.append(e.target.address_of_slot(base, i32(slot.offset + list.area_at), pointer))
	e.append(e.target.store_indirect(pointer, work, 8)!)
	// The list the program named points at the tag just filled in.
	e.append(e.target.address_of_slot(base, slot.offset, work))
	e.store_register(destination, work, line, col)!
}

// emit_va_arg reads the next argument out of a list and steps the list past it.
//
// The list holds two cursors, one per register file, and an address past the
// arguments that did not fit in a register. An argument of a floating type comes
// out of the vector file and one of every other type out of the general file; a
// cursor that has reached the end of its file sends the read to the address
// instead, which is where the caller put the arguments the registers ran out for.
// The cursor is advanced after every read, so the next call reads the argument
// after this one; that step is what a copy of the list is for, and what makes the
// two copies independent.
fn (mut e Emitter) emit_va_arg(call ast.Call) !void {
	line := call.line
	col := call.col
	if call.typ.kind !in [types.Kind.int_, .unsigned_int, .long, .unsigned_long, .long_long,
		.unsigned_long_long, .pointer, .double] {
		e.diagnostics << problem(line, col, 'unsupported: __builtin_va_arg reads ${call.typ.describe()} out of an argument list, and an int, a 64-bit integer, a pointer and a double are the arguments this back end reads')
		return error('unsupported argument type')
	}
	list := abi.argument_list()
	area := abi.register_area()
	floating := call.typ.kind == .double
	width := if floating { e.target.word_size } else { e.storage_width(call.typ) or { 0 } }
	name := (call.args[0] as ast.Ident).name
	source := e.the_argument_list(name, '__builtin_va_arg', line, col) or {
		return error('no argument list')
	}
	base := e.frame_pointer(line, col)!
	work := e.accumulator(line, col)!
	pointer := e.scratch(line, col)!
	cursor := e.remainder(line, col)!
	// The list keeps its place in the frame, so the read and the step both go
	// through the address the name holds rather than through a copy of the tag.
	e.append(e.target.load_slot(base, source.offset, pointer, e.target.word_size)!)
	// Is there a register of this file left? A cursor below the limit means yes;
	// at the limit the walk reads the caller's stack instead.
	e.append(e.target.move_register64(work, pointer)!)
	e.append(e.target.add_immediate(work, i32(if floating {
		list.fp_offset_at
	} else {
		list.gp_offset_at
	})))
	e.append(e.target.load_indirect(work, cursor, 4)!)
	e.append(e.target.move_immediate32(work, u32(if floating {
		abi.fp_limit()
	} else {
		abi.gp_limit()
	}))!)
	e.append(e.target.compare_unsigned('<', cursor, work)!)
	e.append(e.target.test(cursor)!)
	stacked := e.label()
	e.branch(.branch_zero, stacked, line, col)!
	// A register carries it: the argument is at the save area plus the cursor,
	// which is where the prologue wrote the register it arrived in.
	e.append(e.target.move_register64(work, pointer)!)
	e.append(e.target.add_immediate(work, i32(if floating {
		list.fp_offset_at
	} else {
		list.gp_offset_at
	})))
	e.append(e.target.load_indirect(work, cursor, 4)!)
	e.append(e.target.move_register64(work, pointer)!)
	e.append(e.target.add_immediate(work, i32(list.area_at)))
	e.append(e.target.load_indirect(work, work, 8)!)
	e.append(e.target.add_reg64(work, cursor))
	e.append(e.target.add_immediate(cursor, i32(if floating {
		area.fp_stride
	} else {
		area.gp_stride
	})))
	e.append(e.target.add_immediate(pointer, i32(if floating {
		list.fp_offset_at
	} else {
		list.gp_offset_at
	})))
	e.append(e.target.store_indirect(pointer, cursor, 4)!)
	if floating {
		register := e.float_accumulator(line, col)!
		e.append(e.target.load_double_indirect(work, register)!)
	} else {
		e.append(e.target.load_indirect(work, work, width)!)
	}
	done := e.label()
	e.jump(done)!
	e.place(stacked)
	// The registers had none left: the argument is the word the overflow address
	// names, and the address moves past it.
	e.append(e.target.move_register64(cursor, pointer)!)
	e.append(e.target.add_immediate(cursor, i32(list.overflow_at)))
	e.append(e.target.load_indirect(cursor, work, 8)!)
	e.append(e.target.move_register64(cursor, work)!)
	e.append(e.target.add_immediate(cursor, i32(e.target.word_size)))
	e.append(e.target.add_immediate(pointer, i32(list.overflow_at)))
	e.append(e.target.store_indirect(pointer, cursor, 8)!)
	if floating {
		register := e.float_accumulator(line, col)!
		e.append(e.target.load_double_indirect(work, register)!)
	} else {
		e.append(e.target.load_indirect(work, work, width)!)
	}
	e.place(done)
}

// emit_va_copy copies one argument list into another.
//
// The copy gets a tag of its own and the source's tag is written into it, rather
// than the destination being pointed at the source's tag: after the copy the two
// lists walk independently, and stepping one past an argument must not move the
// other. The source is read before the destination's slot is written, because
// evaluating it may call a function and a call is free to use every register the
// copy is about to use.
fn (mut e Emitter) emit_va_copy(call ast.Call) !void {
	line := call.line
	col := call.col
	list := abi.argument_list()
	name := (call.args[0] as ast.Ident).name
	destination := e.the_argument_list(name, '__builtin_va_copy', line, col) or {
		return error('no argument list')
	}
	e.emit_expr_at(call.args[1], 1)!
	source := e.accumulator(line, col)!
	pointer := e.scratch(line, col)!
	work := e.remainder(line, col)!
	e.append(e.target.move_register64(pointer, source)!)
	copied := e.reserve(list.bytes)
	base := e.frame_pointer(line, col)!
	e.append(e.target.address_of_slot(base, copied.offset, work))
	mut at := 0
	for at < list.bytes {
		if at > 0 {
			e.append(e.target.add_immediate(pointer, i32(e.target.word_size)))
			e.append(e.target.add_immediate(work, i32(e.target.word_size)))
		}
		e.append(e.target.load_indirect(pointer, source, 8)!)
		e.append(e.target.store_indirect(work, source, 8)!)
		at += 8
	}
	e.append(e.target.address_of_slot(base, copied.offset, work))
	e.store_register(destination, work, line, col)!
}

// emit_va_end finishes with an argument list. On this convention there is
// nothing to give back: the list is storage in the frame and the save area is
// the frame's, so the operation is the end of the walk and no instruction.
fn (mut e Emitter) emit_va_end(call ast.Call) !void {
	if call.args.len != 1 {
		e.diagnostics << problem(call.line, call.col, 'internal: __builtin_va_end takes one argument list')
		return error('wrong arity')
	}
}

// The machine builtins: the atomic operations and the two trailing-zero counts.
// The reader built them from reserved spellings, and each is answered with the
// machine's own instruction rather than with a call to a name no image holds, so
// they are answered here, before the call path, for the same reason the
// argument-list operations are.
//
// The memory order decides the form, and the reader folded it to a number before
// this stage saw anything. Measured on gcc 16.2.1 at -O2 on this machine: a load
// is the ordinary load at every order; a store is a plain store at relaxed and
// release and an xchg at sequential consistency; an exchange, a fetch and a
// compare-exchange each take their locked instruction at every order; and a
// sequentially consistent fence is a full barrier while an acquire or a release
// fence emits nothing. This reads that number and does not guess at it.
//
// Each argument is evaluated at the depth of the call plus its own place in the
// argument list, the way the call path evaluates an ordinary call's arguments,
// because a value slot is keyed by that depth. Evaluating at a fixed depth
// instead lets an argument's temporary land on the slot an earlier argument's
// value is waiting in, and the earlier argument is then read back as the
// temporary: `pair(__builtin_ctz(1), __builtin_ctzll(1ULL << 40))` answered with
// the 64-bit count's own operand.
//
// An atomic operation reads and writes the type its pointer names, and its
// value operand is converted to that type before the instruction runs: a signed
// value narrower than the type keeps its sign when it is widened into the word
// the instruction reads, so `(unsigned long long)-1` adds all ones and not the
// 0xffffffff a zero-extended 32-bit read would give.

// atomic_target_width is the width of the object an atomic builtin operates on,
// which is what its pointer argument names. A width this back end has no atomic
// instruction for is refused by name rather than read at the width of something
// smaller.
fn (mut e Emitter) atomic_target_width(call ast.Call, spelling string) ?int {
	pointer := types.decay(call.args[0].typ)
	pointee := pointer.pointee() or {
		e.diagnostics << problem(call.line, call.col, 'unsupported: ${spelling} operates through ${pointer.describe()}, and this back end reads and writes what a pointer names')
		return none
	}
	width := e.storage_width(pointee) or {
		e.diagnostics << problem(call.line, call.col, 'unsupported: ${spelling} operates on ${pointee.describe()}, and this back end reads and writes ints, chars and pointers')
		return none
	}
	if width != 1 && width != 2 && width != 4 && width != 8 {
		e.diagnostics << problem(call.line, call.col, 'unsupported: ${spelling} operates on an object of ${width} bytes, and this back end has an atomic instruction at one, two, four or eight')
		return none
	}
	return width
}

// atomic_order_value is the memory order the reader folded into the call.
fn atomic_order_value(expr ast.Expr) int {
	if expr is ast.IntLit {
		return int(expr.value)
	}
	return -1
}

// widen_machine_value brings a value a narrow atomic operation left in the
// register up to the width of the type it is worth, the way any other read of
// that type would: a char with its sign when the type is signed and with zeros
// when it is not, and a short the same way. A four- or eight-byte operation
// writes the whole register.
fn (mut e Emitter) widen_machine_value(typ types.Type, destination backend.Register, width int) !void {
	if width >= 4 {
		return
	}
	unsigned := typ.is_unsigned_type()
	if width == 1 {
		if unsigned {
			e.append(e.target.widen_byte(destination)!)
		} else {
			e.append(e.target.sign_extend_byte(destination)!)
		}
		return
	}
	if unsigned {
		e.append(e.target.zero_extend_half(destination)!)
	} else {
		e.append(e.target.sign_extend_half(destination)!)
	}
}

// emit_atomic_load reads the value a pointer names. The read is the ordinary read
// at every order -- this machine does not reorder a load of an aligned object --
// and it widens a char or a short the way a plain read of that type does.
fn (mut e Emitter) emit_atomic_load(call ast.Call, depth int) !void {
	width := e.atomic_target_width(call, '__atomic_load_n') or {
		return error('the width of __atomic_load_n')
	}
	unsigned := call.typ.is_unsigned_type()
	e.emit_expr_at(call.args[0], depth + 1)!
	address := e.scratch(call.line, call.col)!
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.move_register64(address, accumulator)!)
	e.load_indirect_value(address, accumulator, unsigned, width)!
}

// emit_atomic_store writes a value through a pointer. At sequential consistency
// the store is an xchg, whose implicit lock is the barrier the order asks for; at
// relaxed and release it is the plain store, which this machine does not reorder
// past the instructions around it.
fn (mut e Emitter) emit_atomic_store(call ast.Call, depth int) !void {
	width := e.atomic_target_width(call, '__atomic_store_n') or {
		return error('the width of __atomic_store_n')
	}
	order := atomic_order_value(call.args[2])
	base := e.frame_pointer(call.line, call.col)!
	address_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[0], depth + 1)!
	e.store_accumulator(address_slot, call.line, call.col)!
	value_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[1], depth + 2)!
	e.extend_operand_to_word(call.args[1], call.line, call.col)!
	e.store_accumulator(value_slot, call.line, call.col)!
	address := e.scratch(call.line, call.col)!
	e.append(e.target.load_slot(base, address_slot.offset, address, e.target.word_size)!)
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.load_slot_unsigned(base, value_slot.offset, accumulator, width)!)
	if order == 5 {
		e.append(e.target.atomic_exchange(address, accumulator, width)!)
		return
	}
	e.append(e.target.store_indirect(address, accumulator, width)!)
}

// emit_atomic_exchange swaps a value with the one a pointer names and answers the
// value memory held before: gcc's `exchange` returns the previous value, and the
// machine's xchg leaves exactly that in the register.
fn (mut e Emitter) emit_atomic_exchange(call ast.Call, depth int) !void {
	width := e.atomic_target_width(call, '__atomic_exchange_n') or {
		return error('the width of __atomic_exchange_n')
	}
	base := e.frame_pointer(call.line, call.col)!
	address_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[0], depth + 1)!
	e.store_accumulator(address_slot, call.line, call.col)!
	value_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[1], depth + 2)!
	e.extend_operand_to_word(call.args[1], call.line, call.col)!
	e.store_accumulator(value_slot, call.line, call.col)!
	address := e.scratch(call.line, call.col)!
	e.append(e.target.load_slot(base, address_slot.offset, address, e.target.word_size)!)
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.load_slot_unsigned(base, value_slot.offset, accumulator, width)!)
	e.append(e.target.atomic_exchange(address, accumulator, width)!)
	e.widen_machine_value(call.typ, accumulator, width)!
}

// emit_atomic_fetch adds a value into the object a pointer names and answers the
// value that was there before, which is what the machine's xadd leaves in the
// register. A subtraction is the same instruction over a negated register, since
// the reader has already told the two apart by name.
fn (mut e Emitter) emit_atomic_fetch(call ast.Call, subtract bool, depth int) !void {
	spelling := if subtract { '__atomic_fetch_sub' } else { '__atomic_fetch_add' }
	width := e.atomic_target_width(call, spelling) or {
		return error('the width of ${spelling}')
	}
	base := e.frame_pointer(call.line, call.col)!
	address_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[0], depth + 1)!
	e.store_accumulator(address_slot, call.line, call.col)!
	value_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[1], depth + 2)!
	e.extend_operand_to_word(call.args[1], call.line, call.col)!
	e.store_accumulator(value_slot, call.line, call.col)!
	address := e.scratch(call.line, call.col)!
	e.append(e.target.load_slot(base, address_slot.offset, address, e.target.word_size)!)
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.load_slot_unsigned(base, value_slot.offset, accumulator, width)!)
	if subtract {
		if width == 8 {
			e.append(e.target.negate_word(accumulator)!)
		} else {
			e.append(e.target.negate(accumulator)!)
		}
	}
	e.append(e.target.atomic_fetch_add(address, accumulator, width)!)
	e.widen_machine_value(call.typ, accumulator, width)!
}

// emit_atomic_compare_exchange compares what the expected pointer names with the
// object and, when they agree, stores the desired value and answers 1; when they
// differ it writes back what memory held through the expected pointer and answers
// 0. The value to compare against travels in the accumulator because the machine's
// cmpxchg compares the accumulator implicitly, and the zero flag carries the
// answer until it is turned into the int the standard gives the question.
fn (mut e Emitter) emit_atomic_compare_exchange(call ast.Call, depth int) !void {
	width := e.atomic_target_width(call, '__atomic_compare_exchange_n') or {
		return error('the width of __atomic_compare_exchange_n')
	}
	base := e.frame_pointer(call.line, call.col)!
	address_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[0], depth + 1)!
	e.store_accumulator(address_slot, call.line, call.col)!
	expected_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[1], depth + 2)!
	e.store_accumulator(expected_slot, call.line, call.col)!
	desired_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[2], depth + 3)!
	e.extend_operand_to_word(call.args[2], call.line, call.col)!
	e.store_accumulator(desired_slot, call.line, call.col)!
	address := e.scratch(call.line, call.col)!
	e.append(e.target.load_slot(base, address_slot.offset, address, e.target.word_size)!)
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.load_slot(base, expected_slot.offset, accumulator, e.target.word_size)!)
	e.append(e.target.load_indirect(accumulator, accumulator, width)!)
	desired := e.remainder(call.line, call.col)!
	e.append(e.target.load_slot_unsigned(base, desired_slot.offset, desired, width)!)
	e.append(e.target.atomic_compare_exchange(address, desired, width)!)
	// The zero flag says whether it stored. On success the jump skips the
	// write-back; on failure the machine has left the value memory held in the
	// accumulator and the standard asks for it to be written back through the
	// expected pointer before the answer is read. Neither move below disturbs the
	// flags the compare-exchange set, so the jump and the answer read the same one.
	stored := e.label()
	e.branch(.branch_zero, stored, call.line, call.col)!
	e.append(e.target.load_slot(base, expected_slot.offset, desired, e.target.word_size)!)
	e.append(e.target.store_indirect(desired, accumulator, width)!)
	e.place(stored)
	e.append(e.target.set_condition(backend.Condition.equal, accumulator)!)
	e.append(e.target.widen_byte(accumulator)!)
}

// emit_atomic_thread_fence is the barrier between the operations before it and
// the ones after. Only the sequentially consistent order asks for an instruction
// on this machine; an acquire or a release fence orders nothing the instruction
// stream does not already, so nothing is emitted for one, which is what gcc does.
fn (mut e Emitter) emit_atomic_thread_fence(call ast.Call) !void {
	if atomic_order_value(call.args[0]) == 5 {
		e.append(e.target.memory_fence())
	}
}

// emit_count_trailing answers `__builtin_ctz` and `__builtin_ctzll` with the
// index of the lowest set bit, which is one bsf at either width. gcc answers an
// int for both, and a program that asks this of zero has asked a question with no
// answer; the value the machine then leaves is undefined, as it is for gcc.
fn (mut e Emitter) emit_count_trailing(call ast.Call, depth int) !void {
	e.emit_expr_at(call.args[0], depth + 1)!
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.bit_scan_forward(accumulator, accumulator, call.name == '__builtin_ctzll')!)
}

// emit_count_leading answers `__builtin_clz` and `__builtin_clzll` with the
// number of leading zero bits, which is one bsr and one xor at either width. gcc
// answers an int for both, and a program that asks this of zero has asked a
// question with no answer; the value the machine then leaves is undefined, as it
// is for gcc.
fn (mut e Emitter) emit_count_leading(call ast.Call, depth int) !void {
	e.emit_expr_at(call.args[0], depth + 1)!
	accumulator := e.accumulator(call.line, call.col)!
	e.append(e.target.count_leading(accumulator, accumulator, call.name == '__builtin_clzll')!)
}

// emit_return_address answers `__builtin_return_address(0)` with the address the
// call that reached this function left. A frame opens with `push rbp; mov rbp,
// rsp`, so the saved frame pointer is at [rbp] and the return address is the word
// above it at [rbp + word_size]: one load and the answer is that word. The
// emitter's frames are all frame-pointer based, which is what makes the word a
// fixed offset from the frame pointer rather than something to walk for.
fn (mut e Emitter) emit_return_address(call ast.Call) !void {
	base := e.frame_pointer(call.line, call.col)!
	register := e.accumulator(call.line, call.col)!
	e.append(e.target.load_slot(base, i32(e.target.word_size), register, e.target.word_size)!)
}

// emit_byte_swap answers `__builtin_bswap16` and `__builtin_bswap32` with the
// instruction that reverses a value's bytes. The argument is evaluated into the
// accumulator, where the instruction works in place, and the two builtins differ
// only in which width the back end swaps.
fn (mut e Emitter) emit_byte_swap(call ast.Call, depth int) !void {
	e.emit_expr_at(call.args[0], depth + 1)!
	register := e.accumulator(call.line, call.col)!
	if call.name == '__builtin_bswap16' {
		e.append(e.target.byte_swap_16(register)!)
	} else {
		e.append(e.target.byte_swap_32(register)!)
	}
}

// emit_bit_operation answers `__builtin_popcount` with the number of one bits in
// the argument, and `__builtin_parity` with that number masked to its low bit,
// which is the parity the standard defines. The argument is evaluated into the
// accumulator, the count is computed there through a scratch register, and the
// parity is one more mask: the count's lowest bit is 1 exactly when the number of
// one bits is odd.
fn (mut e Emitter) emit_bit_operation(call ast.Call, depth int) !void {
	e.emit_expr_at(call.args[0], depth + 1)!
	register := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	e.append(e.target.bit_count(register, scratch)!)
	if call.name == '__builtin_parity' {
		e.append(e.target.and_immediate(register, 1)!)
	}
}

// emit_overflow answers `__builtin_add_overflow` and `__builtin_mul_overflow`: the
// two operands are added or multiplied and the result the operation wraps to is
// stored through the third argument, while the answer is whether it overflowed.
// The operands are evaluated into slots first, because an operand can be an
// expression that calls a function and the registers have to be free for it, and
// each is widened to a word as it is stored, so the operation reads the values
// they are and not whatever sat above a narrower one.
//
// The width the operation runs in is the result type's, and that is what makes the
// flag the answer: a four-byte add's overflow flag is the overflow of the int the
// result is, and a word add's is the overflow of the 64-bit integer the result is.
// The reader has refused an operand whose value the result type cannot hold, so the
// width the operation runs in changes no operand's value.
//
// A signed result reads the machine's signed overflow flag. An unsigned one cannot
// use that flag: the carry out of an add is what says an unsigned sum left the
// result, and for a multiply the bytes of the product above the result's are, which
// a signed multiply's flag does not state. Both are read here, so an unsigned
// result and a signed one are the same operation with a different question asked of
// it.
fn (mut e Emitter) emit_overflow(call ast.Call, depth int) !void {
	multiply := call.name == '__builtin_mul_overflow'
	result := call.args[2].typ.pointee() or {
		e.diagnostics << problem(call.line, call.col, '${e.target.name}: ${call.name} stores its result through a pointer, and this one names no object')
		return error('no result type')
	}
	wide := e.eight_byte_integer(result)
	unsigned := result.is_unsigned_type()
	store_width := if wide { 8 } else { 4 }
	a_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[0], depth + 1)!
	e.extend_operand_to_word(call.args[0], call.line, call.col)!
	e.store_accumulator(a_slot, call.line, call.col)!
	b_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[1], depth + 2)!
	e.extend_operand_to_word(call.args[1], call.line, call.col)!
	e.store_accumulator(b_slot, call.line, call.col)!
	pointer_slot := e.reserve(e.target.word_size)
	e.emit_expr_at(call.args[2], depth + 3)!
	e.store_accumulator(pointer_slot, call.line, call.col)!
	base := e.frame_pointer(call.line, call.col)!
	accumulator := e.accumulator(call.line, call.col)!
	scratch := e.scratch(call.line, call.col)!
	pointer := e.remainder(call.line, call.col)!
	e.load_accumulator(a_slot, call.line, call.col)!
	e.append(e.target.load_slot(base, i32(b_slot.offset), scratch, e.target.word_size)!)
	if multiply {
		if unsigned {
			if wide {
				// `mul` leaves the product's bytes above the result in the register
				// above, which is where a product too large for the result sits.
				e.append(e.target.multiply_pair(scratch)!)
				e.append(e.target.test_word(pointer)!)
			} else {
				// A four-byte result takes operands of at most four bytes, so the
				// word product is the whole product and its bytes above the fourth
				// are what says it did not fit.
				e.append(e.target.multiply_word(accumulator, scratch)!)
				e.append(e.target.move_register64(pointer, accumulator)!)
				e.append(e.target.shift_right_word(pointer, 32)!)
				e.append(e.target.test_word(pointer)!)
			}
			e.append(e.target.set_condition(backend.Condition.not_equal, scratch)!)
		} else {
			if wide {
				e.append(e.target.multiply_word(accumulator, scratch)!)
			} else {
				e.append(e.target.multiply(accumulator, scratch)!)
			}
			e.append(e.target.set_condition(backend.Condition.overflow, scratch)!)
		}
	} else {
		if wide {
			e.append(e.target.add_reg64(accumulator, scratch))
		} else {
			e.append(e.target.add(accumulator, scratch)!)
		}
		// The carry is the unsigned sum leaving the result, and it is the flag the
		// signed add leaves as its unsigned half.
		condition := if unsigned { backend.Condition.below } else { backend.Condition.overflow }
		e.append(e.target.set_condition(condition, scratch)!)
	}
	e.append(e.target.widen_byte(scratch)!)
	// The result the operation wrapped to, through the pointer the third argument was.
	e.append(e.target.load_slot(base, i32(pointer_slot.offset), pointer, e.target.word_size)!)
	e.append(e.target.store_indirect(pointer, accumulator, store_width)!)
	// And the answer itself: the overflow flag, which the widen has already made 0 or 1.
	e.append(e.target.move_register32(accumulator, scratch)!)
}

// emit_alloc answers `__builtin_alloca(size)`: it claims `size` bytes on the
// calling function's stack and leaves their address in the accumulator. The size is
// rounded up to the boundary a call needs and subtracted from the stack pointer, the
// same two steps a variable-length array's declaration makes, so the storage sits
// below the frame and every access through the frame pointer is untouched; the value
// the stack pointer became is the address the call is worth.
//
// The lifetime is what separates this from a variable-length array: the standard
// says an alloca'd object lives until the function returns, so no block saves and
// restores the stack pointer around this call, and the frame's own epilogue, which
// puts the stack pointer back to the frame pointer, is what gives the storage back
// at the end. The size is widened to a word first, so an int argument arrives at the
// subtraction as the value it is and not with whatever the register held above it.
fn (mut e Emitter) emit_alloc(call ast.Call, depth int) !void {
	e.emit_expr_at(call.args[0], depth + 1)!
	e.extend_operand_to_word(call.args[0], call.line, call.col)!
	register := e.accumulator(call.line, call.col)!
	e.append(e.target.add_immediate(register, frame_alignment - 1))
	e.append(e.target.and_immediate(register, -frame_alignment)!)
	e.append(e.target.sub_rsp_register(register)!)
	stack := e.target.stack_pointer() or {
		e.diagnostics << problem(call.line, call.col, '${e.target.name}: the machine has no stack pointer to claim __builtin_alloca storage against')
		return error('no stack pointer')
	}
	e.append(e.target.move_register64(register, stack)!)
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
	// The bytes this call pushes for the arguments its registers ran out for have
	// to be counted from what was already on the stack when it started, because a
	// call an argument is made of is emitted while this call's own pushes are
	// standing. That inner call is a call of its own: it gives back the bytes it
	// pushed and leaves the count where it found it, which is this call's count
	// and not zero.
	entry_pushed := e.stack_pushed
	// The argument-list operations and the machine builtins are answered before
	// anything else: they reach the emitter as calls, and the path below would
	// write a call to a name no image holds.
	match call.name {
		'__builtin_va_start' {
			return e.emit_va_start(call)
		}
		'__builtin_va_arg' {
			return e.emit_va_arg(call)
		}
		'__builtin_va_copy' {
			return e.emit_va_copy(call)
		}
		'__builtin_va_end' {
			return e.emit_va_end(call)
		}
		'__atomic_load_n' {
			return e.emit_atomic_load(call, depth)
		}
		'__atomic_store_n' {
			return e.emit_atomic_store(call, depth)
		}
		'__atomic_exchange_n' {
			return e.emit_atomic_exchange(call, depth)
		}
		'__atomic_compare_exchange_n' {
			return e.emit_atomic_compare_exchange(call, depth)
		}
		'__atomic_fetch_add' {
			return e.emit_atomic_fetch(call, false, depth)
		}
		'__atomic_fetch_sub' {
			return e.emit_atomic_fetch(call, true, depth)
		}
		'__atomic_thread_fence' {
			return e.emit_atomic_thread_fence(call)
		}
		'__builtin_ctz', '__builtin_ctzll' {
			return e.emit_count_trailing(call, depth)
		}
		'__builtin_clz', '__builtin_clzll' {
			return e.emit_count_leading(call, depth)
		}
		'__builtin_return_address' {
			return e.emit_return_address(call)
		}
		'__builtin_unreachable', '__builtin_trap' {
			e.append(e.target.unreachable())
			return
		}
		'__builtin_bswap16', '__builtin_bswap32' {
			return e.emit_byte_swap(call, depth)
		}
		'__builtin_popcount', '__builtin_parity' {
			return e.emit_bit_operation(call, depth)
		}
		'__builtin_add_overflow', '__builtin_mul_overflow' {
			return e.emit_overflow(call, depth)
		}
		'__builtin_alloca' {
			return e.emit_alloc(call, depth)
		}
		'atexit' {
			// glibc defines atexit in libc_nonshared.a, the static half of
			// the C library, and not in the shared libc.so.6 whose dynamic
			// symbol table this image resolves against, so the name resolves
			// against no library the image names. It is a wrapper around
			// __cxa_atexit, which libc.so.6 does export, and this emits it
			// rather than importing a name nothing holds. A unit that defines
			// its own atexit is left alone: the call then binds to that
			// definition.
			if call.callee == none && call.args.len == 1 && call.name !in e.program.defined {
				return e.emit_atexit(call, depth)
			}
		}
		else {}
	}
	// A call that hands a long double back leaves it on the x87 stack rather
	// than in the result register. The call is written the same way as any
	// other, and what it is worth to the expression around it is settled after
	// the call runs, at each of the places below that emit one.
	mut places := []ArgPlace{cap: call.args.len}
	// A call written to an expression calls the address that expression is
	// worth. The address is computed before anything else and waits in a slot of
	// its own, because the register it is computed into is the same one every
	// argument is loaded through, and the argument registers are loaded last.
	mut indirect := false
	mut callee_slot := Slot{}
	if expression := call.callee {
		callee_slot = e.callee_slot(depth)
		e.emit_callee_value(expression, depth + call.args.len + 1)!
		e.store_accumulator(callee_slot, call.line, call.col)!
		indirect = true
	}
	// A call to a function that hands an object of more than two eightbytes back is
	// given the address of this frame's storage for it in the first general register,
	// so the arguments written in the call start one register later.
	mut hidden := false
	if class := e.call_return_class(call) {
		if class.count > 2 {
			hidden = true
		}
	}
	mut integers := if hidden { 1 } else { 0 }
	mut doubles := 0
	mut stacked := 0
	for i, arg in call.args {
		if e.long_double_argument(call, i, arg) != none {
			// A long double is handed over in memory: sixteen bytes, at the
			// alignment the type has, which is sixteen. An odd number of
			// eight-byte words already on the stack therefore takes a padding
			// word first so that the argument starts at a multiple of sixteen.
			// The value is pushed in the stack pass, where its two words are
			// written straight from the value's sixteen bytes.
			pad := stacked % 2 == 1
			if pad {
				stacked++
			}
			places << ArgPlace{
				stack:    true
				position: stacked
				extended: true
				pad:      pad
				words:    2
			}
			stacked += 2
			continue
		}
		if e.complex_long_double_argument(call, i, arg) {
			// A `long double _Complex` is handed over in memory as thirty-two
			// bytes, at the alignment the type has, which is sixteen. An odd
			// number of eight-byte words already on the stack therefore takes a
			// padding word first, the same rule a long double argument follows.
			// The value is pushed in the stack pass, where its four words are
			// written straight from the object's bytes.
			pad := stacked % 2 == 1
			if pad {
				stacked++
			}
			places << ArgPlace{
				stack:               true
				position:            stacked
				extended:            true
				complex_long_double: true
				pad:                 pad
				words:               4
			}
			stacked += 4
			continue
		}
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
	widths := e.call_widths(call)
	for i, arg in call.args {
		place := places[i]
		line := expr_line(arg)
		col := expr_col(arg)
		if place.extended {
			// A long double is written in the stack pass, which pushes its two
			// words straight from the value's sixteen bytes rather than parking
			// the address of them in a slot.
			continue
		}
		if place.object {
			// An object is not read into a slot of its own: its own bytes are
			// read after the stack this call takes has been made, either into
			// the registers it goes in or onto the stack itself. The address
			// those bytes are read through is taken here for an object the
			// convention hands over in registers, and parked in this level's
			// value slot, rather than where the registers are loaded: building
			// the object a converted argument needs uses the floating-point
			// register, and that register holds the arguments already loaded
			// once the loading pass has started. An object on the stack is left
			// to the stack pass, which runs before any register is loaded.
			if !place.stack {
				class := e.aggregate_argument(call, i) or {
					e.diagnostics << problem(call.line, call.col, 'internal: an object handed over in two registers has no class in the signature of ${call.name}')
					return error('no class')
				}
				e.object_hand_over_address(arg, class, depth + i + 1)!
				e.store_accumulator(e.value_slot(depth + i), line, col)!
			}
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
				e.widen_into_pair(pair, arg.typ.is_unsigned_type(), e.narrow_width(arg.typ), line,
					col)!
			}
			continue
		}
		if class := e.aggregate_argument(call, i) {
			// An object is handed over as its bytes: the address of the object
			// is taken and the one eightbyte the convention puts in a register
			// is read from it. A struct of one double is bits moved through the
			// floating file, which is the same eight bytes.
			e.object_hand_over_address(arg, class, depth + i + 1)!
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
			single := e.argument_is_single(call, i)
			e.convert_to_float_class(arg, single, line, col)!
			slot := e.value_slot(depth + i)
			if single {
				// The word the argument is parked in is eight bytes and the
				// value is four, so the half above it is cleared rather than
				// left holding whatever the frame had: a float that ran out of
				// registers is pushed as the low half of a word, and the top of
				// that word would otherwise be the frame's business.
				register := e.accumulator(line, col)!
				e.append(e.target.move_immediate32(register, u32(0))!)
				e.store_accumulator(slot, line, col)!
				e.store_single_accumulator(slot, line, col)!
				continue
			}
			e.store_double_accumulator(slot, line, col)!
			continue
		}
		e.emit_expr_at(arg, depth + i + 1)!
		// A double handed to a parameter that is not one is truncated to the
		// integer the parameter holds, which is the conversion the language
		// defines between the two classes. The parameter's own width is what
		// that truncation is made at, and a call to something this file does
		// not define has no parameter to read it from, so the argument's own
		// width is the answer there.
		parameter_width := if i < widths.len { widths[i] } else { e.width_of(arg) or { 4 } }
		e.convert_to_int(arg, e.argument_is_unsigned(call, i, arg), parameter_width, line, col)!
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
			if place.extended {
				// A long double goes on the stack as its own sixteen bytes: the
				// words are pushed from the last to the first, so the low word
				// is at the lower address the callee reads first. The value is
				// materialized once and its address parked, because an
				// expression computed here is materialized by taking its
				// address and a second take per word would compute it twice.
				// When an odd number of eight-byte words was already on the
				// stack, the padding word is reserved after the two, so it lands
				// below them and the value still starts at a multiple of
				// sixteen. A `long double _Complex` argument is the same shape
				// at four words: the address of its thirty-two bytes, which the
				// argument path builds where a real argument has to become a
				// complex value first.
				if place.complex_long_double {
					e.complex_long_double_argument_address(arg, depth + i + 1)!
				} else {
					e.emit_expr_at(arg, depth + i + 1)!
				}
				source := e.value_slot(depth + i)
				e.store_accumulator(source, line, col)!
				mut k := place.words - 1
				for k >= 0 {
					base := e.accumulator(line, col)!
					e.load_argument(source, base, e.target.word_size, line, col)!
					if k > 0 {
						e.append(e.target.add_immediate(base, k * width))
					}
					value := e.scratch(line, col)!
					e.append(e.target.load_indirect(base, value, width)!)
					e.append(e.target.push_register(value))
					e.stack_pushed += width
					k--
				}
				if place.pad {
					e.append(e.target.frame_reserve(u32(width)))
					e.stack_pushed += width
				}
				continue
			}
			if place.object {
				// An object goes on the stack in one piece, its words pushed from
				// the last one to the first: the stack grows down, so the word
				// pushed last is the one at the lowest address, which is the
				// object's first word. The object's address is taken once and
				// parked, because an object computed here, a call's result or a
				// conditional of them, is materialized by taking its address: a
				// second take for each word would compute the object once per
				// word, so a call would run once per word and each run's
				// temporary would overwrite the last. The object's last word is
				// only as wide as the object has left, so nothing past its end is
				// read.
				class := e.aggregate_argument(call, i) or {
					e.diagnostics << problem(call.line, call.col, 'internal: an object handed over on the stack has no class in the signature of ${call.name}')
					return error('no class')
				}
				e.object_hand_over_address(arg, class, depth + i + 1)!
				source := e.value_slot(depth + i)
				e.store_accumulator(source, line, col)!
				mut k := place.words - 1
				for k >= 0 {
					offset := k * width
					read := if offset + width > class.bytes {
						class.bytes - offset
					} else {
						width
					}
					base := e.accumulator(line, col)!
					e.load_argument(source, base, e.target.word_size, line, col)!
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
		if place.extended {
			// A long double was pushed whole in the stack pass; no register is
			// loaded for it.
			continue
		}
		if place.object && !place.stack {
			// The object's own bytes, read straight into the two argument
			// registers: the second eightbyte is eight bytes further in, and the
			// general file is handed only the bytes the object has left. An
			// object whose two eightbytes did not both fit is on the stack and
			// was pushed already, and reading a register for it would hand the
			// object over twice and clobber the arguments beside it. The address
			// was taken in the value pass and waits in this argument's slot, so
			// nothing here builds an object and no argument register is touched
			// but the two this object is read into.
			class := e.aggregate_argument(call, i) or {
				e.diagnostics << problem(call.line, call.col, 'internal: an object handed over in two registers has no class in the signature of ${call.name}')
				return error('no class')
			}
			e.load_accumulator(e.value_slot(depth + i), line, col)!
			base := e.accumulator(line, col)!
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
				e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} passes more floating-point arguments than the machine has registers for')
				return error('too many arguments')
			}
			if e.argument_is_single(call, i) {
				e.load_single_argument(slot, register, line, col)!
				continue
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
	if indirect {
		// The address is read back into the accumulator after the argument
		// registers are loaded, because loading them is the last thing that
		// could disturb it and the accumulator carries no argument of this
		// convention. The call then goes to the address rather than to a name.
		e.load_accumulator(callee_slot, call.line, call.col)!
		register := e.accumulator(call.line, call.col)!
		e.append(e.target.call_register(register)!)
		e.release_call_stack(entry_pushed)
		return e.store_extended_result(call, call.line, call.col)
	}
	if call.name in e.program.defined {
		// A call to a nested function hands it the frame pointer of the function
		// it is written in, in the chain register, before the jump: that is what
		// makes an object of the enclosing function readable inside the nested
		// body. It goes in after the arguments are loaded, because the chain
		// register carries no argument of this convention, so no argument that
		// was just put in a register is disturbed.
		if owner := e.nested_functions[call.name] {
			e.load_call_chain(owner, call.line, call.col)!
		}
		e.reference(e.target.call_near(0), .call_local, call.name, '')
		e.release_call_stack(entry_pushed)
		return e.store_extended_result(call, call.line, call.col)
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
	e.release_call_stack(entry_pushed)
	return e.store_extended_result(call, call.line, call.col)
}

// emit_atexit writes the wrapper glibc defines for atexit, which this image
// cannot take from the C library: atexit lives in libc_nonshared.a, the static
// half, and not in the shared libc.so.6 whose dynamic symbol table is what the
// link check at the end of build reads, so the name is one no library the image
// names answers for. Emitting the wrapper is the function's definition and not
// a stand-in for one, the way this emitter already answers the argument-list
// operations and the machine builtins itself. glibc's atexit is
//
//	int atexit(void (*func)(void)) {
//		return __cxa_atexit((void (*)(void *))func, NULL, __dso_handle);
//	}
//
// so the call is one to __cxa_atexit, which libc.so.6 does export, and the
// value the wrapper is worth is __cxa_atexit's own result, which is what glibc
// returns.
//
// The third argument is a null handle. This image writes its own start instead
// of linking crt1.o and crtbegin.o, and a program is never finalized as a
// shared object, so a per-image handle would be read only by a __cxa_finalize
// this program never calls. glibc's exit runs every handler registered through
// __cxa_atexit regardless of the handle it was registered with, so the
// observable behaviour, the handlers in reverse order of registration once
// after main returns, is the same as gcc's. Measured on gcc 16.2.1:
// `__cxa_atexit(f, 0, 0)` returns 0 and f runs at exit exactly as glibc's own
// atexit arranges.
fn (mut e Emitter) emit_atexit(call ast.Call, depth int) !void {
	wrapper := ast.Call{
		name: '__cxa_atexit'
		args: [
			call.args[0],
			e.null_pointer(call.line, call.col),
			e.null_pointer(call.line, call.col),
		]
		typ:  call.typ
		line: call.line
		col:  call.col
	}
	return e.emit_call(wrapper, depth)
}

// null_pointer is the null pointer constant the wrapper above hands over where
// the C library's own atexit writes NULL. It is a zero typed as a pointer, so
// the call passes a whole word for it the way it passes the handler: the value
// the argument is worth is the address zero, and the width the argument is
// handed over at is the width a pointer argument has.
fn (e Emitter) null_pointer(line int, col int) ast.Expr {
	return ast.Expr(ast.IntLit{
		value: 0
		text:  '0'
		typ:   types.pointer_to(types.void_type())
		line:  line
		col:   col
	})
}

// release_call_stack gives back the stack a call took for the arguments its
// registers ran out for. It runs after the call and not before it, because the
// arguments have to still be on the stack when the callee reads them; that is
// the one ordering this has to get right, and the machine code says so when it
// is wrong.
//
// `entry` is what `stack_pushed` was when the call started. Only the bytes this
// call pushed are released, and the count is put back to `entry` rather than
// cleared, because an enclosing call's stack arguments can be standing while
// this one is emitted: an argument that is itself a call is evaluated after the
// enclosing call has pushed the arguments written before it, and clearing the
// count here would give those bytes back early, so the enclosing call's later
// release would not match and the callee would read its arguments from the
// wrong place.
fn (mut e Emitter) release_call_stack(entry int) {
	pushed := e.stack_pushed - entry
	if pushed > 0 {
		e.append(e.target.stack_release(u32(pushed)))
	}
	e.stack_pushed = entry
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
	// extended says the argument is a long double, which travels in memory as
	// sixteen bytes rather than in any register. It is written in the stack pass
	// like an object, pushing its two words straight from the value's bytes.
	extended bool
	// complex_long_double says the argument is a `long double _Complex`, which
	// travels in memory as thirty-two bytes and comes back on the x87 stack. It
	// is written in the stack pass like a long double, pushing four words.
	complex_long_double bool
	// pad says the sixteen-byte-aligned extended argument this place is one of
	// needed a padding word before it, because an odd number of eight-byte words
	// was already on the stack. The word is reserved below the two the value
	// pushes, so the argument still starts at a multiple of sixteen.
	pad bool
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

// argument_is_double says whether an argument is handed over as a double. The
// declaration's parameter list says so itself, parameter by parameter, whether
// or not this file wrote the body; a call through a declaration with no
// parameters has no parameter type to consult, so the argument's own type is
// the answer.
fn (e Emitter) argument_is_double(call ast.Call, position int, arg ast.Expr) bool {
	if parameter := call_parameter(call, position) {
		// The callee's parameter list is in front of the call, so it decides:
		// a float parameter is a floating-class argument, and an int one is not.
		return parameter.is_floating()
	}
	if classes := e.float_params[call.name] {
		if position < classes.len {
			return classes[position]
		}
	}
	return e.floating_of(arg)
}

// argument_is_single says whether an argument is handed over as a float rather
// than a double. The declaration's parameter list says so itself, parameter by
// parameter, whether or not this file wrote the body. A call through a
// declaration with no parameters has no parameter type to consult, and a float
// argument to one is promoted to a double, which is the default argument
// promotion the language defines for a call whose parameter types are not known:
// so the fallback is false rather than the argument's own type, and
// `printf("%f", f)` hands over the double printf reads.
//
// The argument is not asked because the answer is not the argument's to give:
// whether the value is a float before the call is not whether it is one at the
// parameter.
fn (e Emitter) argument_is_single(call ast.Call, position int) bool {
	if parameter := call_parameter(call, position) {
		return parameter.kind == .float
	}
	if singles := e.single_params[call.name] {
		if position < singles.len {
			return singles[position]
		}
	}
	return false
}

// argument_is_unsigned says whether an argument is handed to an unsigned integer
// parameter. The declaration's parameter list says so itself, parameter by
// parameter, whether or not this file wrote the body; a call through a
// declaration with no parameters has no parameter type to consult, so the
// argument's own type is the answer, which is the same fallback
// argument_is_double makes.
fn (e Emitter) argument_is_unsigned(call ast.Call, position int, arg ast.Expr) bool {
	if parameter := call_parameter(call, position) {
		return parameter.is_unsigned_type()
	}
	if unsigneds := e.unsigned_params[call.name] {
		if position < unsigneds.len {
			return unsigneds[position]
		}
	}
	return arg.typ.is_unsigned_type()
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
	if parameter := call_parameter(call, position) {
		return parameter.kind in [types.Kind.int128, .unsigned_int128]
	}
	if wides := e.wide_params[call.name] {
		if position < wides.len {
			return wides[position]
		}
	}
	return e.wide_value(arg)
}

// call_parameter says what type the parameter at `position` of the call's callee
// has, and none when the call's callee does not name one. A call written to an
// expression reads the type that expression is worth, which for a pointer to a
// function is the parameter list its declaration wrote, so a call through such a
// pointer has a prototype in front of it the way a call to a declared name does.
// A callee that is a function type names its parameters directly; one that is a
// pointer is followed to the function it points at.
fn call_parameter(call ast.Call, position int) ?types.Type {
	signature := call_signature(call) or { return none }
	if position >= signature.params.len {
		return none
	}
	return signature.params[position].typ
}

// indirect_call_returns is the type a call through an expression is worth, and none
// for a call written to a name. The parser resolved the type the callee's function
// returns onto the call, so a call through a pointer to a function knows what its
// value is and how it travels the way a call to a declared name does: the pointer
// carries the return type its declaration wrote. A call written to a name reads
// that from the tables the declarations filled instead, which is why this answers
// none for one.
fn indirect_call_returns(call ast.Call) ?types.Type {
	if call.callee == none || call.typ.kind == .unknown {
		return none
	}
	return call.typ
}

// call_return_class is how the object a call hands back travels, and none for a
// call that hands back a value. A call written to a name reads the class the
// declaration's return type filled; a call through an expression reads the class
// of the type the parser resolved onto the call, which is the return type the
// pointer carries. It is the same answer either way, because the class of an
// object is the target's answer for its type.
fn (e Emitter) call_return_class(call ast.Call) ?abi.Class {
	if typ := indirect_call_returns(call) {
		class := abi.class_of(e.representation, typ)
		if class.bytes > 0 {
			return class
		}
		return none
	}
	if class := e.return_classes[call.name] {
		return class
	}
	return none
}

// call_signature is the function type a call's callee is worth calling: for an
// expression, the function it is or the function a pointer to it points at, and
// none when the callee names no parameters at all. A call written to a name has
// its parameters in the table the declarations filled, so this answers none and
// the caller reads that table instead.
fn call_signature(call ast.Call) ?types.Type {
	callee := call.callee or { return none }
	mut signature := callee.typ
	if signature.is_pointer() {
		signature = signature.pointee() or { return none }
	}
	if !signature.is_function() || !signature.prototyped {
		return none
	}
	return signature
}

// call_widths is the width of each parameter the call's callee names, for the
// calls whose parameter types are known. A call written to a name reads the table
// the declarations filled; a call written to an expression reads the type of that
// expression, which for a pointer to a function is a parameter list this back end
// sizes the same way. A callee that names no parameters, or one whose parameter
// this back end cannot size, answers with no widths, and passed_width then falls
// back to the argument's own width the way it does for a library function with no
// prototype here.
fn (e Emitter) call_widths(call ast.Call) []int {
	if call.callee == none {
		return e.signatures[call.name] or { []int{} }
	}
	signature := call_signature(call) or { return []int{} }
	mut widths := []int{cap: signature.params.len}
	for parameter in signature.params {
		class := abi.class_of(e.representation, parameter.typ)
		if class.bytes > 0 {
			widths << class.bytes
			continue
		}
		if width := e.type_width(parameter.typ.describe()) {
			widths << width
		} else if parameter.typ.kind in [types.Kind.int128, .unsigned_int128] {
			widths << wide_bytes
		} else {
			return []int{}
		}
	}
	return widths
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

// import_object records a name another object defines as an undefined symbol of
// the table, and marks it an object rather than a function so that the symbol's
// type says what it is. The order is the order the names are first reached in,
// the same as an imported function.
fn (mut e Emitter) import_object(name string) {
	if name !in e.program.imports {
		e.program.imports << name
	}
	e.program.object_imports[name] = true
}

// import_copy_object records a name this image holds storage for and the loader
// fills by copying the library's object into it, once. The name's slot in
// `globals` carries the width the symbol's size is read from, so only the order
// is kept here, and it is the order the names are first reached in, the same as
// an imported function, so that the same input writes the same bytes.
fn (mut e Emitter) import_copy_object(name string) {
	if name !in e.program.copy_objects {
		e.program.copy_objects << name
	}
}

// global_definition is the declaration of a top-level object by name: one this
// unit defines, or one it declares with no storage here. A definition is
// storage the image holds; an `extern` declaration is a name another object
// defines, which this unit can reach and has nothing to place for. The two are
// one question here because a reader that wants the type or the width does not
// care which it is, and the place that lays out storage asks `global_of` rather
// than this.
fn (e Emitter) global_definition(name string) ?ast.Global {
	for global in e.unit.globals {
		if global.name == name {
			return global
		}
	}
	for global in e.unit.extern_objects {
		if global.name == name {
			return global
		}
	}
	return none
}

// global_shape is what a top-level object's declaration says about its storage:
// the width of one element and how many there are. It asks the tree rather than
// the image, so an expression can ask it while it is being sized, before anything
// has needed the address of the object and laid the storage out.
fn (e Emitter) global_shape(name string) ?image.GlobalSlot {
	if slot := e.program.globals[name] {
		return slot
	}
	if global := e.global_definition(name) {
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
		// The width of one element is the size of the element's own type, which
		// for an array of arrays is the row and not the scalar at the bottom:
		// `int a[2][3]` steps by twelve bytes per row, and reading the written
		// spelling `int` would give four and overlap the rows. A scalar element
		// resolves to the same answer the spelling does.
		element := if global.count > 0 {
			if elem := global.resolved.element() {
				e.representation.size_of(elem) or { e.type_width(global.typ) or { return none } }
			} else {
				e.type_width(global.typ) or { return none }
			}
		} else {
			e.type_width(global.typ) or { return none }
		}
		return image.GlobalSlot{
			offset:   0
			width:    element
			count:    if global.count > 0 { global.count } else { 0 }
			floating: e.writes_a_double(global.typ)
			single:   e.writes_a_float(global.typ)
			unsigned: e.written_is_unsigned(global.typ)
		}
	}
	return none
}

// global_is_floating says whether a top-level object was defined as a floating
// value. A read of the name has to go through the floating-point file, and the
// tree says so before the storage has been laid out, so this asks the declaration
// rather than the blob.
fn (e Emitter) global_is_floating(name string) bool {
	if global := e.global_definition(name) {
		// An array's name is an address, so only an object that holds one
		// floating value is read as one.
		return global.count == 0
			&& (e.writes_a_double(global.typ) || e.writes_a_float(global.typ))
	}
	return false
}

// global_is_single is the same question asked for the four-byte member of the
// class, which is what decides the width of the load that reads it.
fn (e Emitter) global_is_single(name string) bool {
	if global := e.global_definition(name) {
		return global.count == 0 && e.writes_a_float(global.typ)
	}
	return false
}

// global_element_is_floating is the same question about one element of a
// top-level array: `a[0]` is a floating value when a is an array of them, which
// is the class the element is read and written with.
fn (e Emitter) global_element_is_floating(name string) bool {
	if global := e.global_definition(name) {
		return global.count > 0
			&& (e.writes_a_double(global.typ) || e.writes_a_float(global.typ))
	}
	return false
}

// global_element_is_single is that question at four bytes.
fn (e Emitter) global_element_is_single(name string) bool {
	if global := e.global_definition(name) {
		return global.count > 0 && e.writes_a_float(global.typ)
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

// put_bitfield writes a constant into one bitfield inside its storage unit in a
// blob, leaving the unit's other bits alone: the members of a struct that share
// a unit each hold their own bits, and a whole-unit write for one would clobber
// the rest. The unit is read, the field's bits are cleared, the low bits of the
// value are moved up into their place and ORed in, and the unit is written
// back. A value wider than the field is cut to the field's width, which is the
// truncation a store into the field makes. The unit is at most eight bytes,
// which is the widest storage unit a bitfield can be laid out in.
fn put_bitfield(mut blob []u8, at int, value i64, bit_offset int, bit_width int, unit_width int) {
	mut unit := u64(0)
	for i in 0 .. unit_width {
		unit |= u64(blob[at + i]) << (8 * i)
	}
	mask := if bit_width >= 64 { ~u64(0) } else { (u64(1) << bit_width) - 1 }
	unit = (unit & ~(mask << bit_offset)) | ((u64(value) & mask) << bit_offset)
	for i in 0 .. unit_width {
		blob[at + i] = u8((unit >> (8 * i)) & 0xff)
	}
}

// put_single writes a float into a blob as the four bytes of its value, which is
// the same little-endian image the instruction that reads one expects. It is not
// put_double at a narrower width: the low four bytes of the double of 1.5 are
// zeros, and the four bytes of the float 1.5 are not. A float array at the top
// level written with the double bytes came out all zeros, which is the wrong
// value with no diagnostic.
fn put_single(mut blob []u8, at int, value f64) {
	bits := math.f32_bits(f32(value))
	for i in 0 .. 4 {
		blob[at + i] = u8((bits >> (8 * i)) & 0xff)
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

// place_global is where the next top-level object's storage begins. The object
// starts at the alignment its declaration asked for with `aligned(N)`, or at the
// word size when it asked for none, which is the alignment the objects already
// had. The strictest alignment any object asked for is kept on the image, because
// every offset is measured from the start of the blob and an object can only land
// at its alignment if the blob itself starts there.
fn (mut e Emitter) place_global(asked int) int {
	to := if asked > e.target.word_size { asked } else { e.target.word_size }
	if to > e.program.globals_alignment {
		e.program.globals_alignment = to
	}
	for e.program.globals_blob.len % to != 0 {
		e.program.globals_blob << u8(0)
	}
	return e.program.globals_blob.len
}

// global_of is the storage a top-level object has in the image, laid out the
// first time the name is used: the bytes of its constant initializer, or zeros,
// at the width of one element, with every object starting at a word boundary so
// that a word-sized value is never halfway into the one before it. The address of
// a global is not known while the code is emitted - the image is laid out
// afterwards - so every use of it is a reference the layout fills in, which is
// the same mechanism a string literal is addressed by.
fn (mut e Emitter) global_of(name string) ?image.GlobalSlot {
	// An object with internal linkage is recorded as such as soon as its
	// storage is asked for, because the object writer binds the name local and
	// the symbol table has to know before it is written.
	if e.internal[name] {
		e.program.internal[name] = true
	}
	if slot := e.program.globals[name] {
		return slot
	}
	object := e.global_definition(name) or { return none }
	if object.external {
		// An object another object defines. An object file leaves the name
		// undefined and every reference to it is one a linker resolves: the
		// symbol is imported with no storage here and the relocation names it.
		if e.compile_only {
			e.import_object(name)
			return e.global_shape(name)
		}
		// A program this back end links itself holds the storage for the
		// object and the loader copies the library's object into it, which is
		// the copy relocation a program that is not position independent
		// writes for a variable it names out of a shared library. The storage
		// is laid out here, zeros to start, and the name is recorded so the
		// container writes the symbol and the relocation that fills it.
		return e.place_copy_object(name, object)
	}
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
		offset := e.place_global(object.alignment)
		space := if object.count > 0 { object.count * object.bytes } else { object.bytes }
		e.program.globals_blob << []u8{len: space, init: u8(0)}
		// The slot is registered before its initializer is written, because an
		// initializer that is an address may name the object itself
		// (`struct S { struct S *next; } s = {&s};`) and asking for its storage
		// again has to find this slot rather than lay it out a second time and
		// never stop.
		slot := image.GlobalSlot{
			offset:   offset
			width:    object.bytes
			count:    object.count
			object:   true
			unsigned: e.written_is_unsigned(object.typ)
		}
		e.program.globals[name] = slot
		// A union initialized in braces holds that value in its first member,
		// which sits at the beginning of the object: the constant is written
		// there at the member's width and the rest of the union stays zero.
		// An address initializing a pointer first member is written at the
		// same byte, as a reference the layout resolves.
		if object.resolved.kind == .union_ && object.resolved.members.len > 0 {
			first := object.resolved.members[0]
			member_width := e.type_width(first.typ.describe()) or { object.bytes }
			if value := object.init_float {
				if first.typ.kind == .float {
					put_single(mut e.program.globals_blob, offset, value)
				} else {
					put_double(mut e.program.globals_blob, offset, value, member_width)
				}
			}
			if value := object.init {
				put_integer(mut e.program.globals_blob, offset, value, member_width)
			}
		}
		// A struct's brace initializer wrote a constant into each of the members
		// it named, at the byte the layout gave the member and at the member's
		// own width, which is the width a store into that member writes. The
		// members the list did not reach are the zeros the storage started as
		// (6.7.8p21). The value is converted the way the member's own store
		// converts it, `_Bool` included. A member that holds an address gets a
		// reference the layout resolves instead of bytes written here.
		for member in object.member_inits {
			if value := member.init_float {
				if member.spelling == 'float' {
					put_single(mut e.program.globals_blob, offset + member.offset, value)
				} else {
					put_double(mut e.program.globals_blob, offset + member.offset, value, member.width)
				}
			}
			if value := member.init {
				written := e.normalize_a_bool_constant(member.spelling, value)
				if member.bitfield {
					put_bitfield(mut e.program.globals_blob, offset + member.offset, written,
						member.bit_offset, member.bit_width, member.unit_width)
				} else {
					put_integer(mut e.program.globals_blob, offset + member.offset, written,
						member.width)
				}
			}
			if address := member.address {
				e.write_data_address(address, offset + member.offset)
			}
		}
		if address := object.address {
			e.write_data_address(address, offset)
		}
		return slot
	}
	count := if shape.count > 0 { shape.count } else { 1 }
	offset := e.place_global(object.alignment)
	e.program.globals_blob << []u8{len: count * element, init: u8(0)}
	// The slot is registered before its initializer is written, because an
	// initializer that is an address may name the object itself (`int *p =
	// &p;`) and asking for its storage again has to find this slot rather than
	// lay it out a second time and never stop.
	slot := image.GlobalSlot{
		offset:   offset
		width:    element
		count:    shape.count
		floating: shape.floating
		single:   shape.single
		unsigned: shape.unsigned
	}
	e.program.globals[name] = slot
	single := e.writes_a_float(object.typ)
	if value := object.init_float {
		if single {
			put_single(mut e.program.globals_blob, offset, value)
		} else {
			put_double(mut e.program.globals_blob, offset, value, element)
		}
	}
	if value := object.init {
		put_integer(mut e.program.globals_blob, offset, e.normalize_a_bool_constant(object.typ,
			value), element)
	}
	if value := object.init_long {
		// A long double object at the top level starts as the sixteen bytes of
		// the constant the reader computed, which is the value gcc's assembler
		// would name for the same initializer.
		put_extended_value(mut e.program.globals_blob, offset, value)
	}
	// A brace list writes one element at a time, at the width of one element, in
	// the order the list wrote them. The elements the list did not reach stay
	// zero, which is what the storage started as and what C says the rest of a
	// partly initialized array holds.
	for index, value in object.init_floats {
		if index >= count {
			break
		}
		if single {
			put_single(mut e.program.globals_blob, offset + index * element, value)
		} else {
			put_double(mut e.program.globals_blob, offset + index * element, value, element)
		}
	}
	for index, value in object.inits {
		if index >= count {
			break
		}
		put_integer(mut e.program.globals_blob, offset + index * element,
			e.normalize_a_bool_constant(object.typ, value), element)
	}
	// A table whose elements are addresses writes each element the way a scalar
	// one is written, at one element's offset into the storage: a written number
	// is the null pointer constant it is, and an address is a reference the
	// layout resolves, which is why it is not bytes here.
	for index, address in object.address_inits {
		if index >= count {
			break
		}
		if value := address.number {
			put_integer(mut e.program.globals_blob, offset + index * element, value, element)
			continue
		}
		e.write_data_address(address, offset + index * element)
	}
	if address := object.address {
		e.write_data_address(address, offset)
	}
	return slot
}

// place_copy_object lays out the storage a program this back end links holds for
// an object another object defines, and records the name so the container writes
// the dynamic symbol and the copy relocation that fills it. It is the shape a
// non-position-independent image uses for a variable it names out of a shared
// library: the image carries the variable and the loader copies the library's
// value into it when the program starts, so a reference to the name is a
// reference to this image's storage. The storage is the object's own size, which
// is read from the slot the layout registers, and the symbol carries that size
// because it is how many bytes the loader copies. The object has no initializer
// here - its value comes from the library - so the storage starts as zeros.
fn (mut e Emitter) place_copy_object(name string, object ast.Global) ?image.GlobalSlot {
	shape := e.global_shape(name) or { return none }
	// One object, so as many elements as the declaration counted, or one when it
	// wrote no count. An object of an aggregate type is the layout's byte size
	// whether or not the declaration counted elements.
	count := if shape.count > 0 { shape.count } else { 1 }
	offset := e.place_global(object.alignment)
	e.program.globals_blob << []u8{len: count * shape.width, init: u8(0)}
	slot := image.GlobalSlot{
		offset:   offset
		width:    shape.width
		count:    shape.count
		object:   shape.object
		floating: shape.floating
		single:   shape.single
		unsigned: shape.unsigned
	}
	e.program.globals[name] = slot
	e.import_copy_object(name)
	return slot
}

// place_defined_objects lays out the storage of every object the file defines,
// so that an object no function in this file names is still part of the unit.
// It walks the definitions in the order they were written and asks global_of
// for each name, which places the one definition and the objects its
// initializer names along with it; a definition a function already reached is
// already placed and is returned as it is. The order is the source's and never
// a map's, because the offsets global_of writes come from the position in the
// blob and the image is required to be the same bytes for the same input.
fn (mut e Emitter) place_defined_objects() {
	for global in e.unit.globals {
		// An object the file defined with `static` has internal linkage, which
		// is a question about its symbol binding and not about its storage: it
		// is laid out here like any other, and the object writer marks it
		// local. It is recorded for every definition in the unit, whether or
		// not a function reached it, because the symbol table names them all.
		if global.static_ {
			e.program.internal[global.name] = true
		}
		if _ := e.global_of(global.name) {
		}
	}
}

// write_data_address records the eight bytes of a top-level object that hold the
// address of something rather than a number. The address is not settled while the
// bytes are written, so the bytes stay zero and a reference is recorded for the
// layout, which runs after every definition has been read: that is what lets an
// initializer name an object defined later or the object itself. The name is a
// function this unit defines, a function the loader resolves, an object, or a
// string literal, and the four are different references. A name that is none of
// them is refused by name rather than written as an address that would be wrong.
fn (mut e Emitter) write_data_address(address ast.AddressInit, at int) {
	if address.string {
		e.intern(address.name)
		e.program.data_fixups << image.DataFixup{
			offset: at
			kind:   .take_address
			name:   address.name
			addend: address.offset
		}
		return
	}
	if address.name in e.program.defined {
		e.program.data_fixups << image.DataFixup{
			offset: at
			kind:   .function_address
			name:   address.name
			addend: address.offset
		}
		return
	}
	if address.name in e.returns {
		e.import_symbol(address.name)
		e.program.data_fixups << image.DataFixup{
			offset: at
			kind:   .import_address
			name:   address.name
			addend: address.offset
		}
		return
	}
	if slot := e.global_of(address.name) {
		if !address.explicit && slot.count == 0 && !slot.object {
			// The bare name of a scalar object is its value, and a value is
			// not a constant a file-scope initializer may hold. gcc 16.2.1
			// rejects `static int x; static int *p = &x; static int *q = p;`
			// with `initializer element is not constant`, so the address of
			// the storage is not written in its place.
			e.diagnostics << problem(address.line, address.col, 'unsupported: ${address.name} is a scalar object, and its bare name as a file-scope initializer is its value, which is not a constant expression')
			return
		}
		e.program.data_fixups << image.DataFixup{
			offset: at
			kind:   .global_address
			name:   address.name
			addend: address.offset
		}
		return
	}
	e.diagnostics << problem(address.line, address.col, 'unsupported: ${address.name} is named where an address is wanted, and no declaration of it is in scope')
}

// assign_global writes a value into the storage of a top-level object: the
// address of it is loaded out of the image, parked in a scratch slot while the
// value is computed - the value can read the object again - and then the value is
// written through the address.
fn (mut e Emitter) assign_global(stmt ast.Stmt, object image.GlobalSlot, expr ast.Expr, depth int) !void {
	register := e.accumulator(stmt.line, stmt.col)!
	e.reference_object_address(register, stmt.target)
	address := e.value_slot(depth)
	e.store_accumulator(address, stmt.line, stmt.col)!
	if e.global_is_long_double(stmt.target) {
		// A top-level object of the extended type takes a value the way a local
		// of it does, through the address the image holds: sixteen bytes are
		// not a width the machine moves in one instruction.
		return e.store_long_double_at(address, expr, stmt.line, stmt.col, depth)
	}
	if object.width == wide_bytes {
		// A top-level object of a 128-bit type takes the two words a local of it
		// takes, through the address the image holds: the same widening store, and
		// the same copy when the value is another object of the type.
		return e.store_wide_at(address, expr, stmt.line, stmt.col, depth)
	}
	e.emit_expr_at(expr, depth + 1)!
	e.convert_for_global(expr, object, e.written_is_unsigned(e.global_written(stmt.target)), stmt.line,
		stmt.col)!
	address_register := e.scratch(stmt.line, stmt.col)!
	e.load_argument(address, address_register, e.target.word_size, stmt.line, stmt.col)!
	if object.single {
		// A top-level object holding a float takes the value converted to a
		// float, written through the address the image holds with the
		// four-byte store.
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: a pointer is stored in a top-level object that holds a float, and there is no conversion between them')
			return error('pointer into a float')
		}
		e.convert_to_single(expr, stmt.line, stmt.col)!
		value := e.float_accumulator(stmt.line, stmt.col)!
		e.append(e.target.store_float_indirect(address_register, value)!)
		return
	}
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
fn (mut e Emitter) convert_for_global(expr ast.Expr, object image.GlobalSlot, unsigned_target bool, line int, col int) !void {
	if object.single {
		// A top-level object holding a float takes the value converted to a
		// float, for the same reason a slot holding one does.
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a top-level object that holds a float, and there is no conversion between them')
			return error('pointer into a float')
		}
		return e.convert_to_single(expr, line, col)
	}
	if object.floating {
		if !e.floating_of(expr) && e.is_a_pointer(expr) {
			e.diagnostics << problem(line, col, 'unsupported: a pointer is stored in a top-level object that holds a double, and there is no conversion between them')
			return error('pointer into a double')
		}
		return e.convert_to_double(expr, line, col)
	}
	if e.floating_of(expr) {
		return e.convert_to_int(expr, unsigned_target, object.width, line, col)
	}
	if width := e.width_of(expr) {
		if width > object.width && !(object.width < 4 && width == 4) {
			e.diagnostics << problem(line, col, 'unsupported: a value of ${width} bytes is stored into an object that holds ${object.width}')
			return error('width mismatch')
		}
		if object.width == 8 && width != 8 {
			// A value narrower than the object is widened into the whole
			// register before it is written, the way a store into a name of
			// that width does: the store moves eight bytes, so an int whose
			// upper half the load cleared would be written as its unsigned
			// reading.
			e.extend_operand_to_word(expr, line, col)!
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

// wide_char_width is the width of the wchar_t this target gives, four bytes. It
// is both the alignment a wide literal's entry needs and the number of zero
// bytes that end one.
const wide_char_width = 4

// intern_wide puts a wide string literal into the image's read-only data once,
// keyed by the bytes of its characters, and ends the entry with a zero wchar_t,
// which is four zero bytes. It is a table of its own because those bytes can also
// be a narrow literal's, and the two are different objects: a narrow literal's
// entry ends with one zero byte and its object is a byte longer than the wide
// one's, so one table would hand one of them the other's entry.
//
// The entry starts where a wchar_t starts. A narrow literal interned before it
// can be an odd number of bytes long, and a function that reads a wide string is
// not owed an unaligned address: measured, glibc's swprintf answers a
// misaligned `%ls` argument with something other than the count it should, and
// the same program is right one byte either side of that offset. The unit's
// read-only data is declared to the same alignment, so the entry's offset in the
// blob is its offset in the image however the blob is placed.
fn (mut e Emitter) intern_wide(value string) {
	if value in e.program.wide_strings {
		return
	}
	for e.program.string_blob.len % wide_char_width != 0 {
		e.program.string_blob << u8(0)
	}
	if wide_char_width > e.program.read_only_alignment {
		e.program.read_only_alignment = wide_char_width
	}
	e.program.wide_strings[value] = e.program.string_blob.len
	e.program.string_blob << value.bytes()
	for _ in 0 .. wide_char_width {
		e.program.string_blob << u8(0)
	}
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

// single_key is the key one float is interned under: the text of the four bytes
// it is made of, behind an `f` so that it can never be the key of a double. The
// `f` is what keeps the two widths apart in the one table they share, and the
// bits are what make two spellings of one value a single entry.
fn single_key(value f64) string {
	return 'f${math.f32_bits(f32(value))}'
}

// intern_single is intern_double at four bytes: the bytes of the float the value
// rounds to, which is the value a float of it holds. It is four bytes and not
// eight because the instruction that reads it reads four, and the entry is what
// that instruction reads.
fn (mut e Emitter) intern_single(value f64) string {
	key := single_key(value)
	if key in e.program.doubles {
		return key
	}
	e.program.doubles[key] = e.program.string_blob.len
	bits := math.f32_bits(f32(value))
	for i in 0 .. 4 {
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

// reference_object_address leaves the address of a top-level object in the
// register. Under the in-house path the address is a distance from the
// instruction that the layout settles, which is what every object reference has
// always been. In a position-independent object an object another object may
// define is reached through the global offset table instead: the instruction
// loads the object's own address out of the table entry the linker builds,
// because a direct distance to a symbol that can be interposed is what a shared
// link refuses. An object with internal linkage cannot be defined elsewhere, so
// it keeps the direct reference even there, which is what makes its relocation
// unchanged whether -fPIC is given or not.
fn (mut e Emitter) reference_object_address(register backend.Register, name string) {
	if e.compile_only && e.pic && !e.internal[name] {
		e.reference(e.target.load_slot_value(register, 0), .got_address, name, e.target.name_of(register))
		return
	}
	e.reference(e.target.address_of(register, 0), .global_address, name, e.target.name_of(register))
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
		ast.ComplexLit { expr.line }
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
		ast.Assign { expr.line }
		ast.Comma { expr.line }
		ast.StmtExpr { expr.line }
	}
}

fn expr_col(expr ast.Expr) int {
	return match expr {
		ast.IntLit { expr.col }
		ast.FloatLit { expr.col }
		ast.ComplexLit { expr.col }
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
		ast.Assign { expr.col }
		ast.Comma { expr.col }
		ast.StmtExpr { expr.col }
	}
}

fn problem(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
	}
}

// pedantic is a diagnostic about a construct the selected standard does not
// have, which the flags decide the fate of: -Wpedantic reports it, -pedantic-errors
// and -Werror=pedantic promote it to an error, and -w or -Wno-pedantic silence it.
// It does not stop a compile on its own, which is the difference between it and
// `problem`, so a caller uses it for a construct this back end can emit and that
// the standard merely does not allow.
fn pedantic(line int, col int, msg string) tokenize.Diagnostic {
	return tokenize.Diagnostic{
		line:    line
		col:     col
		msg:     msg
		warning: true
		class:   diagnostics.Class.pedantic
	}
}

// ---------------------------------------------------------------------------
// Complex values.
//
// A complex value is two components of the same real type, stored one after the
// other. That is what gcc 16.2.1 lays out and what it hands over: a
// `double _Complex` is sixteen bytes with the real part first, a `float _Complex`
// is eight, and a parameter of one travels in two floating-point registers, one
// eightbyte each, or one when the whole object is eight bytes. The model in
// types/ carries the widths and the alignments, and backend/abi classifies every
// eightbyte of one as floating, so a complex object travels the path a struct of
// its two components travels.
//
// What is left is the arithmetic and the conversions, and their shape here is
// forced by the machine: a value lives in one register and a complex value is
// two, so a complex value is never in the accumulator. It lives in the frame,
// and an operation writes its result into an object. The accumulator holds an
// address when an address is what is wanted.
// ---------------------------------------------------------------------------

// complex_bytes is the size of an object of a complex type, read from the model
// rather than computed here, because the model is where the measured layout is.
fn (e Emitter) complex_bytes(t types.Type) ?int {
	if !t.kind.is_complex() {
		return none
	}
	return e.representation.size_of(t)
}

// complex_component_width is the width of one component: eight bytes for a
// `double _Complex`, four for a `float _Complex`, and sixteen for the extended
// complex type, whose components are the extended format.
fn complex_component_width(t types.Type) int {
	if t.kind == .complex_long_double {
		return long_double_bytes
	}
	return if t.kind == .complex_float { 4 } else { 8 }
}

// complex_component_offset is where a component starts inside the object. 6.2.5
// leaves the layout to the implementation, and gcc 16.2.1 measured: the real part
// is first and the imaginary part immediately after it.
fn complex_component_offset(t types.Type, which int) int {
	return which * complex_component_width(t)
}

// complex_component_single says whether the components are four bytes each, which
// is the `float _Complex` whose components round at every step the way a float
// does.
fn complex_component_single(t types.Type) bool {
	return t.kind == .complex_float
}

// complex_type_of is the type of a complex kind, for the places that reach a kind
// and need the type to ask the model for a size.
fn complex_type_of(kind types.Kind) types.Type {
	if kind == .complex_float {
		return types.complex_float_type()
	}
	if kind == .complex_long_double {
		return types.complex_long_double_type()
	}
	return types.complex_double_type()
}

// load_complex_component reads one component of a complex object into a
// floating-point register, at the width the object's type says.
fn (mut e Emitter) load_complex_component(frame backend.Register, register backend.Register, offset int, single bool) !void {
	if single {
		e.append(e.target.load_float_slot(frame, i32(offset), register)!)
	} else {
		e.append(e.target.load_double_slot(frame, i32(offset), register)!)
	}
}

// store_complex_component writes one component back, at the same width.
fn (mut e Emitter) store_complex_component(frame backend.Register, register backend.Register, offset int, single bool) !void {
	if single {
		e.append(e.target.store_float_slot(frame, i32(offset), register)!)
	} else {
		e.append(e.target.store_double_slot(frame, i32(offset), register)!)
	}
}

// complex_step applies one arithmetic operator to two component registers. The
// operator names are the language's, and the width picks the machine's file:
// `mulsd` for a double and `mulss` for a float, which is the difference between
// rounding once at the end and rounding at every step.
fn (mut e Emitter) complex_step(value backend.Register, other backend.Register, op string, single bool) !void {
	if single {
		e.append(e.target.float_arithmetic(op, value, other)!)
		return
	}
	e.append(e.target.double_arithmetic(op, value, other)!)
}

// emit_complex_part reads the component `__real__` or `__imag__` names out of a
// complex value into the floating-point register a real value lives in. The
// operand is materialised as an object first, because a complex value is two
// registers and never the accumulator; a name whose storage is the frame answers
// with that storage and nothing is copied, and everything else is computed into a
// temporary of this level. The real part is the first component of the pair and
// the imaginary part the second, at the width the component has: eight bytes for
// a `double _Complex` and four for a `float _Complex`.
//
// The parser refuses an operand whose component this back end has no width for,
// and this is asked again here because the emitter reads types rather than the
// reader's decisions: a `long double _Complex` is a component this back end does
// not move, and reading it at the width of a double would be a wrong value.
fn (mut e Emitter) emit_complex_part(unary ast.Unary, depth int) !void {
	line := unary.line
	col := unary.col
	value := unary.expr.typ
	if !value.kind.is_complex() {
		e.diagnostics << problem(line, col, 'unsupported: ${unary.op} reads one part of a complex value, and this operand is ${value.describe()}')
		return error('not a complex operand')
	}
	if value.kind == .complex_long_double {
		// The parts of the extended complex type are the extended format's
		// sixteen bytes each, and the real part is the lower of the two. A
		// value of the extended type is the address of those bytes, so the
		// part is the address of the component inside the object.
		object := e.complex_object_as(unary.expr, value, depth + 1)!
		which := if unary.op == '__imag__' { 1 } else { 0 }
		component := Slot{
			offset: object.offset + which * complex_long_double_component
			width:  long_double_bytes
		}
		return e.leave_address(component, line, col)
	}
	object := e.complex_object_as(unary.expr, value, depth + 1)!
	which := if unary.op == '__imag__' { 1 } else { 0 }
	single := complex_component_single(value)
	frame := e.frame_pointer(line, col)!
	register := e.float_accumulator(line, col)!
	offset := object.offset + complex_component_offset(value, which)
	e.load_complex_component(frame, register, offset, single)!
}

// complex_object evaluates a complex expression into storage and answers the
// frame slot that holds the object. A name whose storage is the frame answers
// with that storage and nothing is copied; everything else is computed into a
// temporary of this level, because there is no register that holds both
// components.
fn (mut e Emitter) complex_object(expr ast.Expr, depth int) !Slot {
	return e.complex_object_as(expr, expr.typ, depth)
}

// complex_object_as is complex_object with the type the object is to have, which
// is the expression's own except where 6.3.2.2 converts a real value, or a
// complex value of the other width, into that type.
fn (mut e Emitter) complex_object_as(expr ast.Expr, destination types.Type, depth int) !Slot {
	if expr is ast.Ident {
		if source := e.lookup(expr.name) {
			if source.complex && source.width == (e.complex_bytes(destination) or { 0 }) {
				return source
			}
		}
	}
	width := e.complex_bytes(destination) or {
		e.diagnostics << problem(expr_line(expr), expr_col(expr), 'unsupported: ${destination.describe()} is not a complex type this back end moves')
		return error('not a complex type')
	}
	object := e.reserve(width)
	e.emit_complex_into_type(object, destination, expr, depth + 1)!
	return object
}

// emit_complex_into_type writes the value of an expression into an object of a
// complex type. The destination's type is what the value is converted to, which
// is the one thing this function knows that the expression does not: 6.3.2.2
// makes a real value a complex one with a zero imaginary part, and makes a
// complex value of the other width the same shape at the wider component type.
fn (mut e Emitter) emit_complex_into_type(dest Slot, destination types.Type, expr ast.Expr, depth int) !void {
	line := expr_line(expr)
	col := expr_col(expr)
	if destination.kind == .complex_long_double {
		// The extended complex type travels and computes differently from the
		// two register-sized ones, so it takes a path of its own.
		return e.emit_long_double_complex_into(dest, expr, depth)
	}
	// A real value is the case a hand-over needs, and the imaginary part is
	// written as zero rather than left: the object may be storage that held
	// something else, and a program reading the imaginary part would read it.
	if expr.typ.is_arithmetic() && !expr.typ.kind.is_complex() {
		return e.emit_real_into_complex(dest, destination, expr, depth)
	}
	if !expr.typ.kind.is_complex() {
		e.diagnostics << problem(line, col, 'unsupported: a value of type ${expr.typ.describe()} is not converted to ${destination.describe()}, and this back end converts a real value and a complex value to a complex type')
		return error('not a complex conversion')
	}
	if expr.typ.kind != destination.kind {
		// The value is materialised at its own width first and then converted,
		// because the two are different questions: what the expression is worth,
		// and what the destination holds.
		source := e.complex_object_as(expr, expr.typ, depth + 1)!
		return e.convert_complex(dest, destination, source, expr.typ, line, col)
	}
	if expr is ast.Ident {
		if local := e.lookup(expr.name) {
			if local.complex {
				return e.copy_complex_frame(local, dest, dest.width, line, col)
			}
		}
	}
	if expr is ast.ComplexLit {
		return e.store_imaginary_constant(dest, destination, expr)
	}
	if expr is ast.Binary {
		return e.emit_complex_arithmetic(dest, expr, depth)
	}
	if expr is ast.Call {
		return e.emit_complex_call(dest, expr, depth)
	}
	if expr is ast.Cast {
		// A cast to a complex type converts what it wraps, which is this same
		// conversion at the same destination type.
		return e.emit_complex_into_type(dest, destination, expr.expr, depth)
	}
	if expr is ast.Unary {
		if expr.op == '-' {
			source := e.complex_object(expr.expr, depth + 1)!
			return e.negate_complex(dest, destination, source, line, col)
		}
		if expr.op == '+' {
			source := e.complex_object(expr.expr, depth + 1)!
			return e.copy_complex_frame(source, dest, dest.width, line, col)
		}
	}
	if expr is ast.Conditional {
		// 6.5.15 evaluates only the arm the condition selects. glibc's
		// <tgmath.h> spells every complex dispatch as a conditional whose
		// condition the reader folds and whose arms name calls at each of the
		// three complex widths: `creal(conj(z))` reaches here as a call to
		// `creal` whose argument is the conditional `conj` expands to, whose
		// taken arm is a `double _Complex` `conj` call and whose untaken arm
		// names `conjl`, a `long double _Complex` this back end does not move.
		// Writing both arms would hand the emitter a type it refuses, so the
		// constant condition is folded to the arm it selects, which is the
		// fold emit_conditional makes for a scalar.
		if expr.cond is ast.IntLit {
			value := (expr.cond as ast.IntLit).value
			arm := if value != 0 { expr.then_expr } else { expr.else_expr }
			return e.emit_complex_into_type(dest, destination, arm, depth)
		}
		// A complex value is two components in the frame and never one
		// register, so the branch carries no value between the arms: each arm
		// writes the same destination object and the object holds whichever
		// arm ran. The condition is evaluated before either arm, which is the
		// order 6.5.15 gives it.
		e.emit_condition(expr.cond, depth + 1, expr.line, expr.col)!
		else_label := e.label()
		end_label := e.label()
		e.branch(.branch_zero, else_label, expr.line, expr.col)!
		e.emit_complex_into_type(dest, destination, expr.then_expr, depth + 1)!
		e.jump(end_label)!
		e.place(else_label)
		e.emit_complex_into_type(dest, destination, expr.else_expr, depth + 1)!
		e.place(end_label)
		return
	}
	if expr is ast.Ident || expr is ast.Field || expr is ast.Index {
		// Storage that is not the frame: a member, an element, or a name whose
		// storage is in the image. Its address is taken and the bytes copied,
		// the same copy an object hand-over makes.
		e.address_of_object(expr, depth + 1)!
		source_address := e.value_slot(depth + 1)
		e.store_accumulator(source_address, line, col)!
		frame := e.frame_pointer(line, col)!
		register := e.accumulator(line, col)!
		e.append(e.target.address_of_slot(frame, i32(dest.offset), register))
		destination_address := e.value_slot(depth)
		e.store_accumulator(destination_address, line, col)!
		return e.copy_address_object(source_address, destination_address, dest.width, line, col)
	}
	e.diagnostics << problem(line, col, 'unsupported: a value of type ${destination.describe()} written as this expression is not one this back end computes')
	return error('unsupported complex value')
}

// emit_real_into_complex writes a real value into a complex object: the real part
// is the value converted to the component's type and the imaginary part is zero.
// 6.3.2.2 is the rule, and the zero is written rather than left alone, because
// the object is storage that may have held something else.
fn (mut e Emitter) emit_real_into_complex(dest Slot, destination types.Type, expr ast.Expr, depth int) !void {
	line := expr_line(expr)
	col := expr_col(expr)
	if e.is_a_pointer(expr) {
		e.diagnostics << problem(line, col, 'unsupported: a pointer is not converted to ${destination.describe()}')
		return error('pointer to complex')
	}
	single := complex_component_single(destination)
	e.emit_expr(expr)!
	if single {
		e.convert_to_single(expr, line, col)!
	} else {
		e.convert_to_double(expr, line, col)!
	}
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	zero := e.float_scratch(line, col)!
	e.append(e.target.zero_double(zero)!)
	e.store_complex_component(frame, value, dest.offset, single)!
	e.store_complex_component(frame, zero, dest.offset + complex_component_width(destination), single)!
}

// copy_complex_frame copies one complex object in the frame to another. Both are
// frame slots, so the copy is a load and a store per eightbyte through the
// scratch register: sixteen bytes is two moves and eight is one, and neither
// address is held in a register because the frame pointer names both.
fn (mut e Emitter) copy_complex_frame(source Slot, destination Slot, width int, line int, col int) !void {
	if source.offset == destination.offset && !source.captured && !destination.captured {
		return
	}
	source_base := e.slot_base_register(source, line, col)!
	destination_base := e.slot_base_register(destination, line, col)!
	register := e.scratch(line, col)!
	mut done := 0
	for done < width {
		e.append(e.target.load_slot(source_base, i32(source.offset + done), register, 8)!)
		e.append(e.target.store_slot(destination_base, i32(destination.offset + done), register, 8)!)
		done += 8
	}
}

// complex_object_bytes is the whole object: two components of the width above,
// which is the sixteen bytes measured for a `double _Complex` and the eight for
// a `float _Complex`.
fn complex_object_bytes(kind types.Kind) int {
	return 2 * complex_component_width(complex_type_of(kind))
}

// copy_complex_into writes a complex object's components to the address a slot
// holds. A member of a complex type takes this rather than the frame copy,
// because the object the member lies in may be a pointer's target and the store
// then cannot be an offset from the frame.
fn (mut e Emitter) copy_complex_into(address Slot, source Slot, kind types.Kind, line int, col int) !void {
	single := kind == .complex_float
	step := complex_component_width(complex_type_of(kind))
	bytes := complex_object_bytes(kind)
	frame := e.slot_base_register(source, line, col)!
	base := e.scratch(line, col)!
	e.load_argument(address, base, e.target.word_size, line, col)!
	mut offset := 0
	for offset < bytes {
		if offset > 0 {
			e.append(e.target.add_immediate(base, offset))
		}
		if single {
			value := e.float_accumulator(line, col)!
			e.append(e.target.load_float_slot(frame, i32(source.offset + offset), value)!)
			e.append(e.target.store_float_indirect(base, value)!)
		} else {
			value := e.float_accumulator(line, col)!
			e.append(e.target.load_double_slot(frame, i32(source.offset + offset), value)!)
			e.append(e.target.store_double_indirect(base, value)!)
		}
		offset += step
	}
}

// convert_complex converts a complex value of one width to the other, one
// component at a time: each component is the conversion 6.3.1.5 and 6.3.1.6
// define between a float and a double, and each is rounded on its own.
fn (mut e Emitter) convert_complex(dest Slot, destination types.Type, source Slot, source_type types.Type, line int, col int) !void {
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	from_single := complex_component_single(source_type)
	to_single := complex_component_single(destination)
	mut which := 0
	for which < 2 {
		from_offset := source.offset + complex_component_offset(source_type, which)
		to_offset := dest.offset + complex_component_offset(destination, which)
		e.load_complex_component(frame, value, from_offset, from_single)!
		if from_single && !to_single {
			e.append(e.target.float_to_double(value, value)!)
		} else if !from_single && to_single {
			e.append(e.target.double_to_float(value, value)!)
		}
		e.store_complex_component(frame, value, to_offset, to_single)!
		which++
	}
}

// negate_complex flips the sign of both components, which is what the unary minus
// of a complex value is: 6.5.3.3 negates the real and imaginary parts separately
// and there is no instruction that negates both at once.
fn (mut e Emitter) negate_complex(dest Slot, destination types.Type, source Slot, line int, col int) !void {
	e.copy_complex_frame(source, dest, dest.width, line, col)!
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	bits := e.scratch(line, col)!
	single := complex_component_single(destination)
	mut which := 0
	for which < 2 {
		offset := dest.offset + complex_component_offset(destination, which)
		e.load_complex_component(frame, value, offset, single)!
		if single {
			e.append(e.target.negate_single(value, bits)!)
		} else {
			e.append(e.target.negate_double(value, bits)!)
		}
		e.store_complex_component(frame, value, offset, single)!
		which++
	}
}

// store_imaginary_constant writes an imaginary constant: the real part is zero
// and the imaginary part is the coefficient the file wrote. 6.4.4.2 is why the
// real part is zero rather than absent: the constant is a complex value and not
// the real one it looks like.
fn (mut e Emitter) store_imaginary_constant(dest Slot, destination types.Type, expr ast.ComplexLit) !void {
	frame := e.frame_pointer(expr.line, expr.col)!
	value := e.float_accumulator(expr.line, expr.col)!
	zero := e.float_scratch(expr.line, expr.col)!
	single := complex_component_single(destination)
	e.append(e.target.zero_double(zero)!)
	e.store_complex_component(frame, zero, dest.offset, single)!
	if single {
		e.intern_single(expr.value)
		e.reference(e.target.load_float_constant(value, 0)!, .single_constant, single_key(expr.value),
			e.target.name_of(value))
	} else {
		e.intern_double(expr.value)
		e.reference(e.target.load_double_constant(value, 0)!, .float_constant, float_key(expr.value),
			e.target.name_of(value))
	}
	e.store_complex_component(frame, value, dest.offset + complex_component_width(destination), single)!
}

// emit_imaginary_constant_from_value is store_imaginary_constant for the places
// that have a value and a type rather than a node.
fn (mut e Emitter) emit_imaginary_constant_value(dest Slot, destination types.Type, value f64, line int,
	col int) !void {
	frame := e.frame_pointer(line, col)!
	register := e.float_accumulator(line, col)!
	zero := e.float_scratch(line, col)!
	single := complex_component_single(destination)
	e.append(e.target.zero_double(zero)!)
	e.store_complex_component(frame, zero, dest.offset, single)!
	if single {
		e.intern_single(value)
		e.reference(e.target.load_float_constant(register, 0)!, .single_constant, single_key(value),
			e.target.name_of(register))
	} else {
		e.intern_double(value)
		e.reference(e.target.load_double_constant(register, 0)!, .float_constant, float_key(value),
			e.target.name_of(register))
	}
	e.store_complex_component(frame, register, dest.offset + complex_component_width(destination), single)!
}

// emit_complex_arithmetic writes a complex arithmetic step into an object. Both
// operands are materialised at the step's own type, which is the wider of the two
// when they differ, so a component read is always at one width. The four
// operators are the language's: two of them are one machine instruction per
// component and the other two are a formula each, and the formula is the one
// design decision here. It is written out where it is used.
fn (mut e Emitter) emit_complex_arithmetic(dest Slot, binary ast.Binary, depth int) !void {
	left := e.complex_object_as(binary.left, binary.typ, depth + 1)!
	right := e.complex_object_as(binary.right, binary.typ, depth + 1)!
	match binary.op {
		'+', '-' {
			return e.emit_complex_sum(dest, binary, left, right, depth)
		}
		'*' {
			return e.emit_complex_product(dest, binary, left, right, depth)
		}
		'/' {
			return e.emit_complex_quotient(dest, binary, left, right, depth)
		}
		else {
			e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} is not an operator this back end computes a complex value with')
			return error('unsupported complex operator')
		}
	}
}

// emit_complex_sum writes the sum or the difference of two complex values: one
// instruction per component, the real part from the real parts and the imaginary
// part from the imaginary ones. Measured on gcc 16.2.1, which compiles `z + w` to
// one addsd per component and `z - w` to one subsd per component.
fn (mut e Emitter) emit_complex_sum(dest Slot, binary ast.Binary, left Slot, right Slot, depth int) !void {
	frame := e.frame_pointer(binary.line, binary.col)!
	value := e.float_accumulator(binary.line, binary.col)!
	other := e.float_scratch(binary.line, binary.col)!
	single := complex_component_single(binary.typ)
	width := complex_component_width(binary.typ)
	mut which := 0
	for which < 2 {
		e.load_complex_component(frame, value, left.offset + which * width, single)!
		e.load_complex_component(frame, other, right.offset + which * width, single)!
		e.complex_step(value, other, binary.op, single)!
		e.store_complex_component(frame, value, dest.offset + which * width, single)!
		which++
	}
}

// emit_complex_product writes the product of two complex values, and this is the
// one design decision this work took deliberately.
//
// gcc 16.2.1 compiles a complex multiply to a call to libgcc's `__muldc3` -- the
// helper that also gets the answer right when a partial product overflows or
// underflows even though the true product does not, which is the boundary the
// standard's Annex G describes. This compiler has no such helper to call: the
// only library a program's image names is one the command line named with `-l`,
// so an image that called `__muldc3` would be an undefined symbol at load under
// the very command line this work is measured with. That trades a wrong answer in
// one corner for a program that does not start at all.
//
// The formula below is therefore the arithmetic itself: `ac - bd` for the real
// part and `ad + bc` for the imaginary one. It is exact for every product whose
// partial products are representable, which is every product of well-behaved
// values and includes the corpus's own `(3+4i)(1-2i) = 11-2i`. Measured against
// gcc 16.2.1 over the 20736 products of the twelve extreme operands {1e308,
// 1e307, 1e200, 1e155, 1e154, 1e-154, 1e-155, 1e-200, 1e-308, 3, 1e16, 1e-16} in
// each of the four components, this formula agreed with gcc's `__muldc3` on every
// one, so the boundary the helper exists for did not appear over that set and the
// product keeps the formula. The division beside it is a different matter and is
// refused where it cannot be right. The four partial products are written to the
// frame before they are combined, so an operand that is also the destination is
// read before it is written.
fn (mut e Emitter) emit_complex_product(dest Slot, binary ast.Binary, left Slot, right Slot, depth int) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	single := complex_component_single(binary.typ)
	width := complex_component_width(binary.typ)
	work := e.reserve(4 * width)
	// ac and bd.
	e.load_complex_component(frame, value, left.offset, single)!
	e.load_complex_component(frame, other, right.offset, single)!
	e.complex_step(value, other, '*', single)!
	e.store_complex_component(frame, value, work.offset, single)!
	e.load_complex_component(frame, value, left.offset + width, single)!
	e.load_complex_component(frame, other, right.offset + width, single)!
	e.complex_step(value, other, '*', single)!
	e.store_complex_component(frame, value, work.offset + width, single)!
	// The real part is ac - bd.
	e.load_complex_component(frame, value, work.offset, single)!
	e.load_complex_component(frame, other, work.offset + width, single)!
	e.complex_step(value, other, '-', single)!
	e.store_complex_component(frame, value, dest.offset, single)!
	// ad and bc.
	e.load_complex_component(frame, value, left.offset, single)!
	e.load_complex_component(frame, other, right.offset + width, single)!
	e.complex_step(value, other, '*', single)!
	e.store_complex_component(frame, value, work.offset + 2 * width, single)!
	e.load_complex_component(frame, value, left.offset + width, single)!
	e.load_complex_component(frame, other, right.offset, single)!
	e.complex_step(value, other, '*', single)!
	e.store_complex_component(frame, value, work.offset + 3 * width, single)!
	// The imaginary part is ad + bc.
	e.load_complex_component(frame, value, work.offset + 2 * width, single)!
	e.load_complex_component(frame, other, work.offset + 3 * width, single)!
	e.complex_step(value, other, '+', single)!
	e.store_complex_component(frame, value, dest.offset + width, single)!
}

// emit_complex_quotient writes the quotient of two complex values with the same
// arithmetic gcc 16.2.1 carries, so its answers are gcc's rather than merely
// close ones.
//
// gcc sends a `double _Complex` division to libgcc's __divdc3, and there is no
// such symbol an image this compiler builds can name, so the arithmetic that
// helper performs is emitted instead. The naive formula this back end would
// otherwise write, `(a*c + b*d) / (c*c + d*d)`, answers differently from gcc on
// 16079 of the 20736 pairs of the twelve extreme operands {1e308, 1e307, 1e200,
// 1e155, 1e154, 1e-154, 1e-155, 1e-200, 1e-308, 3, 1e16, 1e-16} in each of the
// four components: `c*c + d*d` overflows as soon as a component of the divisor
// is large.
//
// The scaled division C99's Annex G.5.1 describes is the shape of __divdc3, and
// the arithmetic below is read from that helper rather than from the standard's
// sketch. The sketch alone is not enough. Measured against gcc over the same
// 20736 pairs, the plain scaled formula still differs on 1848 of them, for two
// reasons that are both in __divdc3. First, before the ratio is formed the four
// operands are scaled: halved when the large component is at or above
// RBIG = DBL_MAX/2, multiplied by RMINSCAL = 1/DBL_EPSILON when it is below
// RMIN2 = DBL_EPSILON, and multiplied by RMINSCAL again when the two components
// of one operand are both small enough that the division could underflow.
// Second, the products and sums are contracted into fused multiply-adds, which
// round once where a separate multiply and add round twice; the same arithmetic
// without the contraction still differs on 390 pairs. So the scaling tests are
// emitted in __divdc3's order and the target's fused multiply-add where gcc uses
// one. Measured with `gcc 16.2.1 -O0 -fno-builtin -lm` and printed with %.17g,
// the comparison over those 20736 pairs reports 0 differences.
//
// A `float _Complex` division takes the other path: gcc's __divsc3 promotes both
// operands to double, computes the simple formula there, and rounds each
// component back to a float, which is what emit_complex_quotient_single emits.
fn (mut e Emitter) emit_complex_quotient(dest Slot, binary ast.Binary, left Slot, right Slot, depth int) !void {
	_ = depth
	if complex_component_single(binary.typ) {
		return e.emit_complex_quotient_single(dest, binary, left, right)
	}
	return e.emit_complex_quotient_double(dest, binary, left, right)
}

// The scaling constants C99's Annex G.5.1 division needs, read off gcc 16.2.1's
// libgcc __divdc3 as compiled on x86-64: half the largest finite double, the
// smallest normal, the machine epsilon, its reciprocal, and the product of the
// first and third.
const complex_rbig = 8.988465674311579e307
const complex_rmin = 2.2250738585072014e-308
const complex_rmin2 = 2.220446049250313e-16
const complex_rminscal = 4.503599627370496e15
const complex_rmax2 = 1.9958403095347196e292
const complex_half = 0.5

// emit_complex_quotient_double is the boundary-exact scaled division. The four
// components are copied into writable slots so the scaling can rewrite them and
// so an operand that is also the destination is read before it is written, and
// every intermediate is a frame slot: the two floating-point registers the
// machine offers are loaded from a slot, combined, and stored back, which keeps
// the sequence of operations the one __divdc3 performs.
fn (mut e Emitter) emit_complex_quotient_double(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	// The four components, the ratio, the denominator, and room for two
	// products and sums, eight bytes each.
	work := e.reserve(8 * 8)
	wa := work.offset
	wb := work.offset + 8
	wc := work.offset + 16
	wd := work.offset + 24
	wr := work.offset + 32
	we := work.offset + 40
	wt := work.offset + 48
	wt2 := work.offset + 56
	e.copy_complex_frame(left, Slot{ offset: wa, width: 16 }, 16, line, col)!
	e.copy_complex_frame(right, Slot{ offset: wc, width: 16 }, 16, line, col)!
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	// if (|c| < |d|) the large component is d; else it is c.
	less := e.label()
	done := e.label()
	e.load_complex_component(frame, value, wc, false)!
	e.complex_quotient_magnitude(value, false, line, col)!
	e.load_complex_component(frame, other, wd, false)!
	e.complex_quotient_magnitude(other, false, line, col)!
	e.complex_quotient_compare('<', value, other, false, .branch_nonzero, less, line, col)!
	// |c| >= |d|: ratio = d / c, denom = d * ratio + c, and c is the large one.
	e.complex_quotient_scaling(frame, wa, wb, wc, wd, wc, false, line, col)!
	e.complex_quotient_step('/', frame, wd, wc, wr, false, line, col)!
	e.complex_quotient_fused('+', frame, wd, wr, wc, we, false, line, col)!
	e.complex_quotient_tail(frame, dest, wa, wb, wc, wd, wr, we, wt, wt2, false, true, line, col)!
	e.jump(done)!
	e.place(less)
	// |c| < |d|: ratio = c / d, denom = c * ratio + d, and d is the large one.
	e.complex_quotient_scaling(frame, wa, wb, wc, wd, wd, false, line, col)!
	e.complex_quotient_step('/', frame, wc, wd, wr, false, line, col)!
	e.complex_quotient_fused('+', frame, wc, wr, wd, we, false, line, col)!
	e.complex_quotient_tail(frame, dest, wa, wb, wc, wd, wr, we, wt, wt2, false, false, line, col)!
	e.place(done)
}

// emit_complex_quotient_single computes a `float _Complex` quotient the way gcc
// 16.2.1 does. Its __divsc3 promotes both operands to double, computes the
// simple formula there, and rounds each component back to a float; measured
// against gcc over the 20736 pairs of the twelve float extremes in each of the
// four components, this agreed with it on every one.
fn (mut e Emitter) emit_complex_quotient_single(dest Slot, binary ast.Binary, left Slot, right Slot) !void {
	line := binary.line
	col := binary.col
	frame := e.frame_pointer(line, col)!
	// Six eight-byte slots: the four components as doubles, the denominator,
	// and one numerator.
	work := e.reserve(6 * 8)
	wa := work.offset
	wb := work.offset + 8
	wc := work.offset + 16
	wd := work.offset + 24
	wr := work.offset + 32
	we := work.offset + 40
	e.complex_quotient_promote(frame, left.offset, wa, line, col)!
	e.complex_quotient_promote(frame, left.offset + 4, wb, line, col)!
	e.complex_quotient_promote(frame, right.offset, wc, line, col)!
	e.complex_quotient_promote(frame, right.offset + 4, wd, line, col)!
	// denom = cc*cc + dd*dd
	e.complex_quotient_step('*', frame, wd, wd, wr, false, line, col)!
	e.complex_quotient_fused('+', frame, wc, wc, wr, wr, false, line, col)!
	// real = (aa*cc + bb*dd) / denom
	e.complex_quotient_step('*', frame, wb, wd, we, false, line, col)!
	e.complex_quotient_fused('+', frame, wa, wc, we, we, false, line, col)!
	e.complex_quotient_step('/', frame, we, wr, we, false, line, col)!
	e.complex_quotient_narrow_store(frame, we, dest.offset, line, col)!
	// imaginary = (bb*cc - aa*dd) / denom
	e.complex_quotient_step('*', frame, wa, wd, we, false, line, col)!
	e.complex_quotient_fused('-', frame, wb, wc, we, we, false, line, col)!
	e.complex_quotient_step('/', frame, we, wr, we, false, line, col)!
	e.complex_quotient_narrow_store(frame, we, dest.offset + 4, line, col)!
}

// complex_quotient_tail writes the two components of the quotient after the
// ratio and the denominator are known. `wa` and `wb` are a and b, `wc` and `wd`
// are c and d, `wr` and `we` are the ratio and the denominator, and `c_large`
// says which component the branch was chosen on: when c is large the real part
// is b*ratio + a and the imaginary part is b - a*ratio, and when d is large they
// are a*ratio + b and b*ratio - a. Each is divided by the denominator, and when
// the ratio is subnormal the products are formed through a divided operand
// instead, which is __divdc3's alternate order.
fn (mut e Emitter) complex_quotient_tail(frame backend.Register, dest Slot, wa int, wb int, wc int, wd int, wr int, we int, wt int, wt2 int, single bool, c_large bool, line int, col int) !void {
	alt := e.label()
	end_alt := e.label()
	e.complex_quotient_magnitude_branch(frame, wr, complex_rmin, '>', single, .branch_zero, alt, line, col)!
	if c_large {
		// real = (b*ratio + a) / denom, imaginary = (b - a*ratio) / denom.
		e.complex_quotient_fused('+', frame, wb, wr, wa, wt, single, line, col)!
		e.complex_quotient_step('/', frame, wt, we, wt, single, line, col)!
		e.complex_quotient_store(frame, wt, dest.offset, single, line, col)!
		e.complex_quotient_fused('neg+', frame, wa, wr, wb, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset + 8, single, line, col)!
	} else {
		// real = (a*ratio + b) / denom, imaginary = (b*ratio - a) / denom.
		e.complex_quotient_fused('+', frame, wa, wr, wb, wt, single, line, col)!
		e.complex_quotient_step('/', frame, wt, we, wt, single, line, col)!
		e.complex_quotient_store(frame, wt, dest.offset, single, line, col)!
		e.complex_quotient_fused('-', frame, wb, wr, wa, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset + 8, single, line, col)!
	}
	e.jump(end_alt)!
	e.place(alt)
	if c_large {
		// t = b / c; real = d*t + a; t = a / c; imaginary = b - d*t.
		e.complex_quotient_step('/', frame, wb, wc, wt, single, line, col)!
		e.complex_quotient_fused('+', frame, wd, wt, wa, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset, single, line, col)!
		e.complex_quotient_step('/', frame, wa, wc, wt, single, line, col)!
		e.complex_quotient_fused('neg+', frame, wd, wt, wb, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset + 8, single, line, col)!
	} else {
		// t = a / d; real = c*t + b; t = b / d; imaginary = c*t - a.
		e.complex_quotient_step('/', frame, wa, wd, wt, single, line, col)!
		e.complex_quotient_fused('+', frame, wc, wt, wb, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset, single, line, col)!
		e.complex_quotient_step('/', frame, wb, wd, wt, single, line, col)!
		e.complex_quotient_fused('-', frame, wc, wt, wa, wt2, single, line, col)!
		e.complex_quotient_step('/', frame, wt2, we, wt2, single, line, col)!
		e.complex_quotient_store(frame, wt2, dest.offset + 8, single, line, col)!
	}
	e.place(end_alt)
}

// complex_quotient_scaling scales the four components the way __divdc3 does
// before the ratio is formed. `large` is the component whose magnitude decides
// the branch: halve the four when it is at or above RBIG, multiply them by
// RMINSCAL when it is below RMIN2, and multiply them by RMINSCAL when both
// components of one operand are small enough that the division could underflow.
// The tests are emitted in the order the helper makes them and short-circuit the
// same way.
fn (mut e Emitter) complex_quotient_scaling(frame backend.Register, wa int, wb int, wc int, wd int, large int, single bool, line int, col int) !void {
	offsets := [wa, wb, wc, wd]
	half_done := e.label()
	do_scale := e.label()
	second := e.label()
	after := e.label()
	// if (|large| >= RBIG) halve every operand.
	e.complex_quotient_magnitude_branch(frame, large, complex_rbig, '<', single, .branch_nonzero, half_done, line, col)!
	e.complex_quotient_scale(frame, offsets, complex_half, single, line, col)!
	e.place(half_done)
	// if (|large| < RMIN2) scale up; else the composite test on a, b and large.
	e.complex_quotient_magnitude_branch(frame, large, complex_rmin2, '<', single, .branch_nonzero, do_scale, line, col)!
	e.complex_quotient_magnitude_branch(frame, wa, complex_rmin, '<', single, .branch_zero, second, line, col)!
	e.complex_quotient_magnitude_branch(frame, wb, complex_rmax2, '<', single, .branch_zero, second, line, col)!
	e.complex_quotient_magnitude_branch(frame, large, complex_rmax2, '<', single, .branch_zero, second, line, col)!
	e.jump(do_scale)!
	e.place(second)
	e.complex_quotient_magnitude_branch(frame, wb, complex_rmin, '<', single, .branch_zero, after, line, col)!
	e.complex_quotient_magnitude_branch(frame, wa, complex_rmax2, '<', single, .branch_zero, after, line, col)!
	e.complex_quotient_magnitude_branch(frame, large, complex_rmax2, '<', single, .branch_zero, after, line, col)!
	e.place(do_scale)
	e.complex_quotient_scale(frame, offsets, complex_rminscal, single, line, col)!
	e.place(after)
}

// complex_quotient_scale multiplies each component in place by one factor, held
// in a floating register while the four are walked.
fn (mut e Emitter) complex_quotient_scale(frame backend.Register, offsets []int, factor f64, single bool, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	e.complex_quotient_constant(other, factor, single)!
	for offset in offsets {
		e.load_complex_component(frame, value, offset, single)!
		e.complex_step(value, other, '*', single)!
		e.store_complex_component(frame, value, offset, single)!
	}
}

// complex_quotient_step applies one scalar operator to two slots and leaves the
// answer in a third.
fn (mut e Emitter) complex_quotient_step(op string, frame backend.Register, left int, right int, dst int, single bool, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	e.load_complex_component(frame, value, left, single)!
	e.load_complex_component(frame, other, right, single)!
	e.complex_step(value, other, op, single)!
	e.store_complex_component(frame, value, dst, single)!
}

// complex_quotient_fused leaves `multiplier * multiplicand + addend` in the
// destination slot with one rounding, which is the contraction gcc's own complex
// division is built from. The operator picks the add, the subtract or a negated
// form.
fn (mut e Emitter) complex_quotient_fused(op string, frame backend.Register, multiplicand int, multiplier int, addend int, dst int, single bool, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	e.load_complex_component(frame, value, multiplicand, single)!
	e.load_complex_component(frame, other, multiplier, single)!
	if single {
		e.append(e.target.fused_single(op, value, other, frame, i32(addend))!)
	} else {
		e.append(e.target.fused_double(op, value, other, frame, i32(addend))!)
	}
	e.store_complex_component(frame, value, dst, single)!
}

// complex_quotient_magnitude_branch compares the magnitude of one component
// against a constant, in the order the operator names, and branches when it
// holds. `kind` is the branch the caller wants: nonzero for the comparison
// itself and zero for its negation, which is how the short-circuit tests are
// written out.
fn (mut e Emitter) complex_quotient_magnitude_branch(frame backend.Register, offset int, constant f64, op string, single bool, kind image.FixupKind, name string, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	other := e.float_scratch(line, col)!
	e.load_complex_component(frame, value, offset, single)!
	e.complex_quotient_magnitude(value, single, line, col)!
	e.complex_quotient_constant(other, constant, single)!
	e.complex_quotient_compare(op, value, other, single, kind, name, line, col)!
}

// complex_quotient_compare leaves the truth of the comparison in a general
// register and branches on it, which is the shape emit_complex_condition uses.
fn (mut e Emitter) complex_quotient_compare(op string, left backend.Register, right backend.Register, single bool, kind image.FixupKind, name string, line int, col int) !void {
	result := e.accumulator(line, col)!
	bits := e.scratch(line, col)!
	if single {
		e.append(e.target.float_comparison(op, left, right, result, bits)!)
	} else {
		e.append(e.target.double_comparison(op, left, right, result, bits)!)
	}
	e.append(e.target.test(result)!)
	e.branch(kind, name, line, col)!
}

// complex_quotient_magnitude clears the sign bit of a floating register, which
// is the magnitude the scaling and the subnormal-ratio tests read.
fn (mut e Emitter) complex_quotient_magnitude(register backend.Register, single bool, line int, col int) !void {
	gp := e.scratch(line, col)!
	if single {
		e.append(e.target.absolute_single(register, gp)!)
	} else {
		e.append(e.target.absolute_double(register, gp)!)
	}
}

// complex_quotient_constant loads a floating constant into a register, at the
// width the components have. The bytes are interned once and read back relative
// to the instruction.
fn (mut e Emitter) complex_quotient_constant(register backend.Register, value f64, single bool) !void {
	if single {
		e.intern_single(value)
		e.reference(e.target.load_float_constant(register, 0)!, .single_constant, single_key(value), e.target.name_of(register))
	} else {
		e.intern_double(value)
		e.reference(e.target.load_double_constant(register, 0)!, .float_constant, float_key(value), e.target.name_of(register))
	}
}

// complex_quotient_store writes one slot to another.
fn (mut e Emitter) complex_quotient_store(frame backend.Register, source int, dst int, single bool, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	e.load_complex_component(frame, value, source, single)!
	e.store_complex_component(frame, value, dst, single)!
}

// complex_quotient_promote widens one float component to a double, which is how
// gcc's __divsc3 begins.
fn (mut e Emitter) complex_quotient_promote(frame backend.Register, source int, dst int, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	e.append(e.target.load_float_slot(frame, i32(source), value)!)
	e.append(e.target.float_to_double(value, value)!)
	e.append(e.target.store_double_slot(frame, i32(dst), value)!)
}

// complex_quotient_narrow_store rounds one double slot back to a float and
// writes it where the quotient's component goes.
fn (mut e Emitter) complex_quotient_narrow_store(frame backend.Register, source int, dst int, line int, col int) !void {
	value := e.float_accumulator(line, col)!
	e.append(e.target.load_double_slot(frame, i32(source), value)!)
	e.append(e.target.double_to_float(value, value)!)
	e.append(e.target.store_float_slot(frame, i32(dst), value)!)
}

// emit_complex_comparison leaves 0 or 1 in the accumulator for `z == w` and
// `z != w`. 6.5.9 makes two complex values equal when the real parts are equal
// and the imaginary parts are, which is two comparisons combined: equal when both
// are equal and unequal when either is. Measured on gcc 16.2.1, `z == w` compares
// the real parts and then the imaginary ones. The remaining orders are refused by
// name, because C99 defines no ordering on the complex types.
fn (mut e Emitter) emit_complex_comparison(binary ast.Binary, depth int) !void {
	if binary.op !in ['==', '!='] {
		e.diagnostics << problem(binary.line, binary.col, 'unsupported: ${binary.op} is not an operator this back end computes on complex values, and C99 defines no order on the complex types')
		return error('unsupported complex comparison')
	}
	// The operands are materialised at the complex type the comparison is made
	// at, which is the complex one when the other side is real: 6.3.2.2 makes a
	// real value a complex one with a zero imaginary part, and that is what the
	// comparison reads.
	kind := if binary.left.typ.kind.is_complex() { binary.left.typ } else { binary.right.typ }
	left := e.complex_object_as(binary.left, kind, depth + 1)!
	right := e.complex_object_as(binary.right, kind, depth + 1)!
	frame := e.frame_pointer(binary.line, binary.col)!
	value := e.float_accumulator(binary.line, binary.col)!
	other := e.float_scratch(binary.line, binary.col)!
	result := e.accumulator(binary.line, binary.col)!
	bits := e.scratch(binary.line, binary.col)!
	single := complex_component_single(kind)
	width := complex_component_width(kind)
	// A slot of this node's own, and not a value slot: the value slots are how
	// the call machinery parks the arguments it has already computed, and a
	// comparison written inside an argument would overwrite one of them.
	keep := e.reserve(e.target.word_size)
	// The real parts first, and the answer is kept while the imaginary parts are
	// compared, because the second comparison needs the register the first one
	// used as its scratch.
	e.load_complex_component(frame, value, left.offset, single)!
	e.load_complex_component(frame, other, right.offset, single)!
	if single {
		e.append(e.target.float_comparison(binary.op, value, other, result, bits)!)
	} else {
		e.append(e.target.double_comparison(binary.op, value, other, result, bits)!)
	}
	e.store_accumulator(keep, binary.line, binary.col)!
	e.load_complex_component(frame, value, left.offset + width, single)!
	e.load_complex_component(frame, other, right.offset + width, single)!
	if single {
		e.append(e.target.float_comparison(binary.op, value, other, result, bits)!)
	} else {
		e.append(e.target.double_comparison(binary.op, value, other, result, bits)!)
	}
	e.load_argument(keep, bits, e.target.word_size, binary.line, binary.col)!
	if binary.op == '==' {
		e.append(e.target.and_word(result, bits)!)
	} else {
		e.append(e.target.or_word(result, bits)!)
	}
}

// emit_complex_condition leaves the truth of a complex value in the accumulator
// as zero or one: 6.3.2.1 makes a complex value true when either component is not
// zero, which is two comparisons against zero combined the way the equality is.
fn (mut e Emitter) emit_complex_condition(cond ast.Expr, line int, col int) !void {
	object := e.complex_object(cond, 0)!
	frame := e.frame_pointer(line, col)!
	value := e.float_accumulator(line, col)!
	zero := e.float_scratch(line, col)!
	result := e.accumulator(line, col)!
	bits := e.scratch(line, col)!
	single := complex_component_single(cond.typ)
	width := complex_component_width(cond.typ)
	keep := e.reserve(e.target.word_size)
	e.append(e.target.zero_double(zero)!)
	e.load_complex_component(frame, value, object.offset, single)!
	if single {
		e.append(e.target.float_comparison('!=', value, zero, result, bits)!)
	} else {
		e.append(e.target.double_comparison('!=', value, zero, result, bits)!)
	}
	e.store_accumulator(keep, line, col)!
	e.load_complex_component(frame, value, object.offset + width, single)!
	if single {
		e.append(e.target.float_comparison('!=', value, zero, result, bits)!)
	} else {
		e.append(e.target.double_comparison('!=', value, zero, result, bits)!)
	}
	e.load_argument(keep, bits, e.target.word_size, line, col)!
	e.append(e.target.or_word(result, bits)!)
	e.append(e.target.test(result)!)
}

// emit_complex_call writes the complex object a call hands back into storage. The
// value arrives the way the class says it travels: two eightbytes, each in the
// register a value of its class comes back in, which for a complex value is the
// two floating-point registers the convention uses for a pair of them. The
// address of the destination is loaded after the call, into the general register,
// because the returned value is in the floating-point ones.
fn (mut e Emitter) emit_complex_call(dest Slot, call ast.Call, depth int) !void {
	if e.returns_a_complex_long_double(call) {
		// The value comes back on the x87 stack, st(0) the real part and st(1)
		// the imaginary one. The call machinery puts the pair into a temporary
		// of its own and leaves the address of that in the accumulator, so the
		// thirty-two bytes are copied into this destination.
		e.emit_call(call, depth + 1)!
		source := e.value_slot(depth + 1)
		e.store_accumulator(source, call.line, call.col)!
		frame := e.frame_pointer(call.line, call.col)!
		base := e.accumulator(call.line, call.col)!
		e.append(e.target.address_of_slot(frame, i32(dest.offset), base))
		destination := e.value_slot(depth + 2)
		e.store_accumulator(destination, call.line, call.col)!
		return e.copy_address_object(source, destination, complex_long_double_bytes, call.line,
			call.col)
	}
	class := e.call_return_class(call) or {
		e.diagnostics << problem(call.line, call.col, 'unsupported: the call to ${call.name} is used as a complex value, and its type is not one this back end hands over as an object')
		return error('not an object return')
	}
	e.emit_call(call, depth + 1)!
	frame := e.frame_pointer(call.line, call.col)!
	base := e.accumulator(call.line, call.col)!
	e.append(e.target.address_of_slot(frame, i32(dest.offset), base))
	e.store_return_eightbyte(base, 0, e.target.word_size, class.first_floating, call.line, call.col)!
	if class.count == 2 {
		e.append(e.target.add_immediate(base, e.target.word_size))
		e.store_return_eightbyte(base, 1, class.bytes - e.target.word_size, class.second_floating,
			call.line, call.col)!
	}
}

// object_hand_over_address leaves in the accumulator the address of the object an
// expression is handed over as. An argument or a return of an object type is the
// address of its storage; a real value handed to a complex object is the one
// exception, because 6.3.2.2 makes it a complex value whose imaginary part is
// zero, and that object does not exist until this builds it.
fn (mut e Emitter) object_hand_over_address(expr ast.Expr, class abi.Class, depth int) !void {
	// The destination is a complex object when both its eightbytes are floating
	// and no byte of it is anything but a component, which the class says and the
	// argument's own type does not: a real value handed to one, and a complex
	// value of the other width, are both built here rather than found.
	if class.first_floating && (class.count == 1 || class.second_floating) {
		destination := if class.bytes > 8 {
			types.complex_double_type()
		} else {
			types.complex_float_type()
		}
		if expr.typ.is_arithmetic() && !expr.typ.kind.is_complex() {
			object := e.reserve(class.bytes)
			e.emit_real_into_complex(object, destination, expr, depth + 1)!
			frame := e.frame_pointer(expr_line(expr), expr_col(expr))!
			register := e.accumulator(expr_line(expr), expr_col(expr))!
			e.append(e.target.address_of_slot(frame, i32(object.offset), register))
			return
		}
		if expr.typ.kind.is_complex() && expr.typ.kind != destination.kind {
			object := e.reserve(class.bytes)
			e.emit_complex_into_type(object, destination, expr, depth + 1)!
			frame := e.frame_pointer(expr_line(expr), expr_col(expr))!
			register := e.accumulator(expr_line(expr), expr_col(expr))!
			e.append(e.target.address_of_slot(frame, i32(object.offset), register))
			return
		}
	}
	e.address_of_object(expr, depth + 1)!
}

// store_complex_local writes a declaration's initializer into the complex object
// it declares. The value is converted to the object's type, which is the one
// place a real initializer becomes a complex value with a zero imaginary part.
fn (mut e Emitter) store_complex_local(slot Slot, written string, init ast.Expr, line int, col int,
	depth int) !void {
	destination := types.from_words(written.split(' ')) or {
		e.diagnostics << problem(line, col, 'unsupported: ${written} is not a type this back end moves a complex value of')
		return error('unknown complex type')
	}
	source := e.complex_object_as(init, destination, depth)!
	return e.copy_complex_frame(source, slot, slot.width, line, col)
}

// assign_complex_local writes a value into a complex object named by a local.
fn (mut e Emitter) assign_complex_local(stmt ast.Stmt, target Slot, depth int) !void {
	expr := stmt.expr or {
		e.diagnostics << problem(stmt.line, stmt.col, 'unsupported: ${stmt.target} is assigned without a value')
		return error('assignment without a value')
	}
	destination := if target.width == 8 {
		types.complex_float_type()
	} else {
		types.complex_double_type()
	}
	source := e.complex_object_as(expr, destination, depth)!
	return e.copy_complex_frame(source, target, target.width, stmt.line, stmt.col)
}

// emit_condition leaves the truth of a condition in the accumulator as zero or
// one. A complex condition is the one that is not a value the accumulator can
// hold, so it is computed here rather than read out of a register.
fn (mut e Emitter) emit_condition(cond ast.Expr, depth int, line int, col int) !void {
	if cond.typ.kind.is_complex() {
		return e.emit_complex_condition(cond, line, col)
	}
	e.emit_expr_at(cond, depth)!
	return e.emit_test(cond, line, col)
}
