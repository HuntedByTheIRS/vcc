module backend

import backend.arch.x86_64
import backend.os.linux

// MachineRegister is a register in the machine's own terms, the form the
// machine's encodings take. It is the machine's Register under the name this
// module's own data speaks: the two register tables a Machine holds and the
// conversion from a handle back to a register. Naming it once here keeps those
// sites from spelling the machine module.
pub type MachineRegister = x86_64.Register

// Machine is the machine half of a composition. It holds the machine's own
// data, so the register file's element type is the machine's and not this
// module's; what the shape fixes is what a second machine has to supply: a
// register file, the width of a register, the number a container header gives
// the architecture, the register a result is left in, the floating-point file,
// and the encoders for the instructions.
pub struct Machine {
pub:
	registers []MachineRegister
	// float_registers is the machine's second file, the one a double is passed
	// and computed in. It is listed separately because it carries its own
	// argument positions: a call numbers its integer arguments and its floating
	// ones in two sequences, so the same position exists in both.
	float_registers []MachineRegister
	// word_size is the width of a register, and elf_machine the number a
	// container header gives this architecture.
	word_size   int
	elf_machine u16
	// return_reg is the register a function leaves its result in, by the name
	// the machine's table uses.
	return_reg string
	// The machine's table read through the composed value: the register a
	// syscall number goes in, the registers a floating-point result and the
	// second operand of a floating-point operation sit in, the frame pointer,
	// the scratch and remainder registers, the register a shift count is read
	// from, and the numbers the machine's relocations and frame instruction
	// carry.
	syscall_number_reg      string
	float_return_reg        string
	float_scratch_reg       string
	frame_pointer_reg       string
	scratch_reg             string
	remainder_reg           string
	shift_count_code        u8
	relocation_call         u32
	relocation_pc_relative  u32
	frame_reserve_immediate int
	// encoders is the machine's instruction set, composed into the target as a
	// value: the emitter's instructions come from here and not from a module.
	encoders x86_64.Encoders
}

// System is the system half of a composition. It holds the system's own data:
// the kernel entry points, the registers the kernel expects with them, where
// the loader puts the image, and where a library named with -l is looked for.
pub struct System {
pub:
	syscalls          []linux.Syscall
	syscall_args_regs []string
	exit_syscall      string
	// interpreter is the loader the kernel starts for a dynamically linked
	// image. A program that calls a shared library has to name it in the image.
	interpreter string
	// library_dirs is where a library named with -l is looked for, the -L
	// directories having been searched first.
	library_dirs []string
	page_size    u64
	load_base    u64
	// base_library_name is the C library every image this system writes runs
	// against, named whether or not a -l asked for it.
	base_library_name string
}

// A target is two descriptions composed: a machine from `backend/arch` and a
// system from `backend/os`. Neither of those knows the other exists, and this is
// the only place they meet. The emitter asks a Target, so a new architecture, a
// new system, or a new fact about either one does not reach codegen.
//
// The machine and the system are held as values, and their fields are read
// through those values: no field of Target names an architecture or an operating
// system. What a second machine supplies is a Machine, what a second system
// supplies is a System, and one function decides what is composed with what.
//
// The description carries what the compiler emits today. An entry no code path
// reads is a claim nobody has tested, so the tables stay partial on purpose.
pub struct Target {
	Machine
	System
pub:
	// name spells the two descriptions the way the command line does.
	name string
	arch string
	os   string
}

// targets lists the descriptions the compiler can emit for. A new target is a
// composition of a machine and a system, not a new branch in the emitter.
pub fn targets() []Target {
	return [x86_64_linux()]
}

// x86_64_linux is the machine `backend/arch/x86_64/arch.v` running the system
// `backend/os/linux/linux.v`. It builds the machine value and the system value
// once, and a Target holds those two values; every field read in this module
// goes through them rather than through the machine's or the system's module.
fn x86_64_linux() Target {
	machine := Machine{
		registers:               x86_64.registers()
		float_registers:         x86_64.float_registers()
		word_size:               x86_64.word_size
		elf_machine:             x86_64.machine
		return_reg:              x86_64.return_reg
		syscall_number_reg:      x86_64.syscall_number_reg
		float_return_reg:        x86_64.float_return_reg
		float_scratch_reg:       x86_64.float_scratch_reg
		frame_pointer_reg:       x86_64.frame_pointer
		scratch_reg:             x86_64.scratch_reg
		remainder_reg:           x86_64.remainder_reg
		shift_count_code:        x86_64.shift_count_code
		relocation_call:         x86_64.relocation_call
		relocation_pc_relative:  x86_64.relocation_pc_relative
		frame_reserve_immediate: x86_64.frame_reserve_immediate
		encoders:                x86_64.encoders()
	}
	system := System{
		syscalls:          linux.syscalls(x86_64.name)
		syscall_args_regs: linux.syscall_args_regs(x86_64.name)
		exit_syscall:      linux.exit_syscall
		interpreter:       linux.interpreter
		library_dirs:      linux.library_dirs(x86_64.name, linux.name)
		page_size:         linux.page_size
		load_base:         linux.load_base
		base_library_name: linux.base_library
	}
	return Target{
		name:    '${x86_64.name}-${linux.name}'
		arch:    x86_64.name
		os:      linux.name
		Machine: machine
		System:  system
	}
}

// lookup finds a target by name, which is `arch-os`.
pub fn lookup(name string) ?Target {
	for target in targets() {
		if target.name == name {
			return target
		}
	}
	return none
}

// host is the target this binary was built to run on.
pub fn host() ?Target {
	$if linux {
		$if amd64 {
			return lookup('x86_64-linux')
		}
	}
	return none
}

// resolve answers the target the command line asks for. An empty name is the
// machine this binary runs on, which is what a compile with no -target means;
// anything else is looked up against the descriptions this module carries.
//
// The refusal lives here with the list it names rather than in a caller, because
// two callers ask and they ask at different times: the driver has to know the
// target before the front end reads anything, since the widths and the aggregate
// layout the parser works out are the target's, and the emitter has to know it
// before it writes a byte. One name that resolves to two answers would be a
// compile whose front end and back end disagree about which machine they are
// describing.
pub fn resolve(name string) !Target {
	if name == '' {
		return host() or { error(no_target()) }
	}
	return lookup(name) or { error(unknown(name)) }
}

// names lists what this compiler emits for.
pub fn names() []string {
	mut out := []string{}
	for target in targets() {
		out << target.name
	}
	return out
}

// unknown is what a name this compiler does not describe is told: the name that
// was asked for, and the ones that exist.
pub fn unknown(name string) string {
	return 'unknown target ${name}: vcc emits ${names().join(', ')}'
}

// no_target is the other refusal: a host this compiler carries no description of,
// which is a build of vcc whose own platform it cannot emit for.
pub fn no_target() string {
	return 'this platform has no backend: vcc emits ${names().join(', ')}'
}

// reg finds a register by the name it is written with. Both spellings of the
// same register answer, because callers name the width they mean.
pub fn (t &Target) reg(name string) ?Register {
	for i, r in t.registers {
		if r.name == name || r.wide_name == name {
			return Register{
				file:  .general
				index: i
			}
		}
	}
	return none
}

// arg_reg is the register that carries argument `position` of a function call,
// or none once the machine's convention has run out of registers. Callers ask
// for a position rather than for a register name so that a second machine with a
// different convention is a table, not an emitter change.
pub fn (t &Target) arg_reg(position int) ?Register {
	for i, r in t.registers {
		if r.call_arg == position {
			return Register{
				file:  .general
				index: i
			}
		}
	}
	return none
}

// float_reg finds a register in the machine's floating-point file by name.
pub fn (t &Target) float_reg(name string) ?Register {
	for i, r in t.float_registers {
		if r.name == name || r.wide_name == name {
			return Register{
				file:  .floating
				index: i
			}
		}
	}
	return none
}

// float_arg_reg is the register that carries floating-point argument `position`.
// It is a second sequence on purpose: a call to `printf("%f", 1.5)` numbers the
// format string in the integer sequence and the double in this one, so both
// start at zero.
pub fn (t &Target) float_arg_reg(position int) ?Register {
	for i, r in t.float_registers {
		if r.float_call_arg == position {
			return Register{
				file:  .floating
				index: i
			}
		}
	}
	return none
}

// float_return is where a function leaves a floating-point result, and
// float_scratch is where the right-hand value of a floating-point operation
// waits while the left-hand one sits in the first. They are the same pair of
// roles the general register file has, one file over.
pub fn (t &Target) float_return() ?Register {
	return t.float_reg(t.float_return_reg)
}

pub fn (t &Target) float_scratch() ?Register {
	return t.float_reg(t.float_scratch_reg)
}

// syscall finds a kernel entry point by name.
pub fn (t &Target) syscall(name string) ?linux.Syscall {
	for s in t.syscalls {
		if s.name == name {
			return s
		}
	}
	return none
}

// exit_sequence is everything needed to stop the process with a status: the
// status into the first argument register, the syscall number into the number
// register, then the trap. It is the one place the two descriptions have to
// agree, so it is written to read both tables rather than to know either: a
// system that numbers its exit call differently, or a machine that reads the
// number from another register, is a table that changed.
pub fn (t &Target) exit_sequence(code u8) ![]u8 {
	exit_call := t.syscall(t.exit_syscall) or {
		return error('${t.name}: no ${t.exit_syscall} syscall in the table')
	}
	if exit_call.args.len == 0 {
		return error('${t.name}: ${exit_call.name} is described with no argument register')
	}
	number_reg := t.reg(t.syscall_number_reg) or {
		return error('${t.name}: no register named ${t.syscall_number_reg}')
	}
	status_reg := t.reg(exit_call.args[0]) or {
		return error('${t.name}: no register named ${exit_call.args[0]}')
	}
	mut out := t.encoders.mov_imm32(t.describe(status_reg), u32(code))!
	out << t.encoders.mov_imm32(t.describe(number_reg), exit_call.number)!
	out << t.encoders.trap()
	return out
}

// The instructions an emitter puts around its own code. Each one takes the
// displacement it should carry, so the emitter can lay an image out first and
// fill the references in afterwards; the length of the instruction does not
// depend on where it points, which is what makes that safe. Each of these asks
// the machine's file for the encoding rather than spelling it here, so the
// composition stays the only place the two descriptions meet.

// call_near is a call to a function in the same image, at a distance from the
// end of the call.
pub fn (t &Target) call_near(disp i32) []u8 {
	return t.encoders.call_rel32(disp)
}

// call_slot is a call to the address a quadword holds, found through a
// displacement from the instruction. A dynamically linked program reaches the
// library's functions this way, because the library's address is not known until
// the loader has run.
pub fn (t &Target) call_slot(disp i32) []u8 {
	return t.encoders.call_rip_slot(disp)
}

// load_slot_value reads the value a slot holds, found through a displacement from
// the instruction. It is the load form of call_slot: a dynamically linked
// function's address is read out of the slot the loader fills rather than called
// through it, which is what lets a program hold the address in a pointer.
pub fn (t &Target) load_slot_value(reg Register, disp i32) []u8 {
	return t.encoders.load_rip_slot(t.describe(reg), disp)
}

// call_register calls the address a register holds: the indirect form, for a call
// written to an expression rather than to a name. It carries no reference, because
// the address is in the register rather than at a place in the image.
pub fn (t &Target) call_register(reg Register) ![]u8 {
	return t.encoders.call_register(t.describe(reg))
}

// call_relocation is the number an object file gives a call, for a reference the
// linker still has to fill in: a call to a symbol this object does not define,
// or one it leaves to the linker to route.
pub fn (t &Target) call_relocation() u32 {
	return t.relocation_call
}

// address_relocation is the number an object file gives a distance the code
// computes rather than jumps to, which is every reference to data.
pub fn (t &Target) address_relocation() u32 {
	return t.relocation_pc_relative
}

// address_of computes the address of a byte string in the image and puts it in
// the register, which is how a string argument is passed.
pub fn (t &Target) address_of(reg Register, disp i32) []u8 {
	return t.encoders.lea_rip(t.describe(reg), disp)
}

// move_immediate32 is how a constant reaches the result register. move_immediate64
// is the same move for a value that needs all eight bytes of the register, which
// is what a constant of a 64-bit integer type is written with: the four-byte move
// clears the bits above the value, so a value whose top bit is set would arrive
// zero-extended rather than as itself.
pub fn (t &Target) move_immediate32(reg Register, value u32) ![]u8 {
	return t.encoders.mov_imm32(t.describe(reg), value)
}

pub fn (t &Target) move_immediate64(reg Register, value u64) ![]u8 {
	return t.encoders.mov_imm64(t.describe(reg), value)
}

// move_register32 copies one register into another, which is how a value a
// function returned reaches the register the next call reads it from.
pub fn (t &Target) move_register32(dst Register, src Register) ![]u8 {
	return t.encoders.mov_reg32(t.describe(dst), t.describe(src))
}

// frame_prologue and frame_epilogue are the two ends of a function body.
pub fn (t &Target) frame_prologue() []u8 {
	return t.encoders.frame_prologue()
}

pub fn (t &Target) frame_epilogue() []u8 {
	return t.encoders.frame_epilogue()
}

// halt stops the machine. It is what follows a call that is not expected to
// return, so that control never runs past the code that was emitted.
pub fn (t &Target) halt() []u8 {
	return t.encoders.halt()
}

// Register is one of a machine's registers as this side of the seam sees it: a handle
// the machine that produced it interprets and nothing else does. The emitter gets one
// from the target and hands it back to the target; it never asks what is inside, which
// is what lets a second machine carry its registers in its own terms instead of having
// to accept this one's.
//
// file says which of the machine's register files the register is in, and index where
// it sits in that file's table. Neither half means anything on its own: the same pair
// names a different register on a different machine, and the number is never computed
// outside the machine that published the table it indexes.
pub struct Register {
pub:
	file  RegisterFile
	index int
}

// RegisterFile is one of a machine's register files. A machine that keeps the registers
// a double travels in apart from the rest has two, which is what lets a call number its
// integer arguments and its floating-point ones in two sequences that both start at
// zero. A machine that keeps one file answers with the general kind for everything.
pub enum RegisterFile {
	general
	floating
}

// describe answers the register a handle names, in the terms the machine's instruction
// encodings are written in. It is the one place a handle becomes a register again, and
// the reason the handle is an index: every question about a register is asked here, so
// no other file has to know how a machine stores one.
pub fn (t &Target) describe(handle Register) MachineRegister {
	return match handle.file {
		.general { t.registers[handle.index] }
		.floating { t.float_registers[handle.index] }
	}
}

// name_of is what the machine calls this register. The emitter needs the name for two
// things that are not questions about an encoding: what a reference in the image is
// recorded under, and what a diagnostic says.
pub fn (t &Target) name_of(handle Register) string {
	return t.describe(handle).name
}

// carries_shift_count says whether this is the register the machine reads a shift count
// from. The encodings of a computed shift name no place for the count, because there is
// only one place they can name, so a count that ended up anywhere else would shift by
// whatever that register happened to hold. The emitter needs to ask this, and asking it
// by the register's bit pattern would be the emitter knowing an encoding.
pub fn (t &Target) carries_shift_count(handle Register) bool {
	return t.describe(handle).code == t.shift_count_code
}

// The instructions a body with locals, branches and arithmetic needs, in the
// same spirit as the ones above: each asks the machine's file for the encoding
// rather than spelling one here.

// frame_pointer is the register a local is found at, scratch is where the
// right-hand value of an operation waits while the left-hand one sits in the
// result register, and remainder is where a division leaves what did not divide
// evenly.
pub fn (t &Target) frame_pointer() ?Register {
	return t.reg(t.frame_pointer_reg)
}

pub fn (t &Target) scratch() ?Register {
	return t.reg(t.scratch_reg)
}

pub fn (t &Target) remainder() ?Register {
	return t.reg(t.remainder_reg)
}

// frame_reserve opens the space a function's locals live in. The size is not
// known while the body is written, so frame_immediate_offset is where it sits in
// those bytes and the emitter fills it in once the body has been walked.
// push_register and stack_release are the two instructions a call's arguments
// past the registers need: the caller puts them on the stack before the call and
// gives the stack back after it, and the callee reads them from where the
// convention says they are.
pub fn (t &Target) push_register(reg Register) []u8 {
	return t.encoders.push_register(t.describe(reg))
}

pub fn (t &Target) stack_release(size u32) []u8 {
	return t.encoders.stack_release(size)
}

pub fn (t &Target) frame_reserve(size u32) []u8 {
	return t.encoders.frame_reserve(size)
}

pub fn (t &Target) frame_immediate_offset() int {
	return t.frame_reserve_immediate
}

// loader_arguments is what the kernel hands a process on its stack, moved into
// the registers a call passes its first arguments in: the count of the
// arguments, the vector of their addresses, and the environment. A process
// starts with the stack pointer pointing at the count, the addresses just above
// it, and the environment after the null that ends the vector, so the count is
// read through the vector register before that register is given the vector's
// own address. The entry point asks for this before it aligns the stack, because
// the layout is written against the stack pointer the kernel left and aligning
// would move it.
pub fn (t &Target) loader_arguments() ![]u8 {
	stack := t.reg('rsp') or {
		return error('${t.name}: no stack pointer to read the argument vector from')
	}
	count := t.arg_reg(0) or {
		return error('${t.name}: no register carries the argument count')
	}
	vector := t.arg_reg(1) or {
		return error('${t.name}: no register carries the argument vector')
	}
	mut out := []u8{cap: 24}
	// The vector register holds the address of the count for one instruction,
	// and then moves up one word to where the addresses of the arguments begin.
	out << t.move_register64(vector, stack)!
	out << t.load_indirect(vector, count, 4)!
	out << t.add_immediate(vector, 8)
	// The environment begins one word past the null that ends the vector: the
	// vector's address, one word per argument, and one word for the null.
	if env := t.arg_reg(2) {
		out << t.address_of_element(vector, count, 8, 8, env)!
	}
	return out
}

// align_stack is how the entry point makes the stack aligned before it calls
// anything: a process is started on whatever stack the kernel left, and every
// frame this compiler opens assumes the boundary is where the convention puts it.
pub fn (t &Target) align_stack() []u8 {
	return t.encoders.align_stack()
}

// sub_rsp_register lowers the stack pointer by an amount a register holds, which is
// how a variable-length array claims its storage: the size is a value the program
// computes, so the instruction that opens the space is a subtraction of one
// register from another and not the fixed one frame_reserve writes.
pub fn (t &Target) sub_rsp_register(src Register) ![]u8 {
	return t.encoders.sub_rsp_register(t.describe(src))
}

// stack_pointer is the register the stack is at, which a variable-length array's
// declaration reads once it has claimed its storage: the address of the array is
// what the stack pointer became.
pub fn (t &Target) stack_pointer() ?Register {
	return t.reg('rsp')
}

// load_slot and store_slot move a value between the frame and a register at the
// width the value has: four bytes for an int, eight for a pointer.
pub fn (t &Target) load_slot(base Register, disp i32, dst Register, width int) ![]u8 {
	return t.encoders.load_slot(t.describe(base), disp, t.describe(dst), width)
}

// load_slot_unsigned is the same read of a one- or two-byte value with zero above
// it rather than its sign, which is what a read of an `unsigned char` or an
// `unsigned short` is.
pub fn (t &Target) load_slot_unsigned(base Register, disp i32, dst Register, width int) ![]u8 {
	return t.encoders.load_slot_unsigned(t.describe(base), disp, t.describe(dst), width)
}

pub fn (t &Target) store_slot(base Register, disp i32, src Register, width int) ![]u8 {
	return t.encoders.store_slot(t.describe(base), disp, t.describe(src), width)
}

// The address of a value in the frame, the address of one element of it, and the
// moves through an address: what an array needs to be read and written one
// element at a time.
// add_immediate folds a constant into a register. A member of an object named by a
// pointer is read at the pointer's value plus the member's offset, and this is the
// addition that makes the two one address.
pub fn (t &Target) add_immediate(dst Register, value i32) []u8 {
	return t.encoders.add_immediate(t.describe(dst), value)
}

// and_immediate masks a register with a constant. It is what cuts a value down to
// the width of the field it is being stored into, and what clears those bits in
// the storage unit the field shares before the value's bits are put in.
pub fn (t &Target) and_immediate(dst Register, value i32) ![]u8 {
	return t.encoders.and_immediate(t.describe(dst), value)
}

// add_reg64 and imul_immediate are the two steps that reach an element whose
// stride the scaled address cannot write: multiply the index by the stride, add
// the array's address.
pub fn (t &Target) add_reg64(dst Register, src Register) []u8 {
	return t.encoders.add_reg64(t.describe(dst), t.describe(src))
}

pub fn (t &Target) imul_immediate(dst Register, value i32) []u8 {
	return t.encoders.imul_immediate(t.describe(dst), value)
}

pub fn (t &Target) address_of_slot(base Register, disp i32, dst Register) []u8 {
	return t.encoders.address_of_slot(t.describe(base), disp, t.describe(dst))
}

pub fn (t &Target) address_of_element(base Register, index Register, scale int, disp i32, dst Register) ![]u8 {
	return t.encoders.address_of_element(t.describe(base), t.describe(index), scale, disp, t.describe(dst))
}

pub fn (t &Target) load_indirect(address Register, dst Register, width int) ![]u8 {
	return t.encoders.load_indirect(t.describe(address), t.describe(dst), width)
}

// load_indirect_unsigned is the same read of a one- or two-byte value with zero
// above it rather than its sign, which is what reading an element of an
// `unsigned char` or `unsigned short` array asks for.
pub fn (t &Target) load_indirect_unsigned(address Register, dst Register, width int) ![]u8 {
	return t.encoders.load_indirect_unsigned(t.describe(address), t.describe(dst), width)
}

pub fn (t &Target) store_indirect(address Register, src Register, width int) ![]u8 {
	return t.encoders.store_indirect(t.describe(address), t.describe(src), width)
}

// The atomic operations, named for what the language's builtins ask for rather
// than for the instruction that carries each. The emitter decides which order
// takes which form; these forward the operation and the width, and the machine
// file owns the encoding.
//
// A load is the ordinary load and needs no method: this machine does not reorder
// a naturally aligned load and the emitter already has load_indirect for it. A
// store is a plain store at every order but the sequentially consistent one,
// whose barrier is the exchange, so a store is told which by the emitter.

// atomic_exchange swaps the value in memory with the register's and leaves the
// old memory value in the register. Its encoding carries the lock itself, so it
// serves both the exchange builtin and the sequentially consistent store.
pub fn (t &Target) atomic_exchange(address Register, value Register, width int) ![]u8 {
	return t.encoders.exchange_indirect(t.describe(address), t.describe(value), width)
}

// atomic_compare_exchange is the lock cmpxchg: the accumulator holds what is
// expected and receives what memory held when they differ, and the register
// holds the value to store when they agree.
pub fn (t &Target) atomic_compare_exchange(address Register, value Register, width int) ![]u8 {
	return t.encoders.compare_exchange_indirect(t.describe(address), t.describe(value), width)
}

// atomic_fetch_add adds the register's value into memory and leaves the old
// memory value in the register, which is the value both fetch_add and, with the
// register negated first, fetch_sub answer with.
pub fn (t &Target) atomic_fetch_add(address Register, value Register, width int) ![]u8 {
	return t.encoders.fetch_add_indirect(t.describe(address), t.describe(value), width)
}

// memory_fence is the barrier a sequentially consistent fence asks for. An
// acquire or a release fence is nothing on this machine and emits no instruction.
pub fn (t &Target) memory_fence() []u8 {
	return t.encoders.memory_fence()
}

// bit_scan_forward is the index of the lowest set bit, which is what the two
// count-trailing builtins are worth. `wide` asks for the eight-byte form.
pub fn (t &Target) bit_scan_forward(dst Register, src Register, wide bool) ![]u8 {
	return t.encoders.bit_scan_forward(t.describe(dst), t.describe(src), wide)
}

// The two widenings a conversion between the value classes needs. A byte is
// widened with its sign kept, which is what converting a value to a char is; a
// word is widened into the whole register, which is what converting an int to a
// pointer is, because a pointer is the machine's word.
pub fn (t &Target) sign_extend_byte(reg Register) ![]u8 {
	return t.encoders.sign_extend_byte(t.describe(reg))
}

// sign_extend_half and zero_extend_half widen the low two bytes of a register
// into the whole register, the sign kept and zero above it respectively, which is
// what a value converted to a short or an unsigned short is narrowed with.
pub fn (t &Target) sign_extend_half(reg Register) ![]u8 {
	return t.encoders.sign_extend_half(t.describe(reg))
}

pub fn (t &Target) zero_extend_half(reg Register) ![]u8 {
	return t.encoders.zero_extend_half(t.describe(reg))
}

pub fn (t &Target) sign_extend_word(dst Register, src Register) ![]u8 {
	return t.encoders.sign_extend_word(t.describe(dst), t.describe(src))
}

// shift_right_arithmetic spreads the sign of a value over the whole register,
// which is what storing a value narrower than the word it goes into needs.
pub fn (t &Target) shift_right_arithmetic(reg Register, bits u8) ![]u8 {
	return t.encoders.shift_right_arithmetic(t.describe(reg), bits)
}

// The arithmetic, named for what the language asks for rather than for the
// instruction that carries it.
pub fn (t &Target) add(dst Register, src Register) ![]u8 {
	return t.encoders.add_reg32(t.describe(dst), t.describe(src))
}

pub fn (t &Target) subtract(dst Register, src Register) ![]u8 {
	return t.encoders.sub_reg32(t.describe(dst), t.describe(src))
}

pub fn (t &Target) multiply(dst Register, src Register) ![]u8 {
	return t.encoders.imul_reg32(t.describe(dst), t.describe(src))
}

// divide divides the result register by another one, signed. The sign goes over
// the register above first, because that pair is what the machine divides: the
// quotient is left in the result register and the remainder above it.
pub fn (t &Target) divide(src Register) ![]u8 {
	mut out := t.encoders.cdq()
	out << t.encoders.idiv_reg32(t.describe(src))!
	return out
}

// divide_unsigned is the same division with the pair read as unsigned: the
// register above is cleared rather than filled with the sign, and the machine
// divides the pair as a value twice as wide. Measured on gcc 16.2.1 at -O0, whose
// `unsigned int g(unsigned int a, unsigned int b) { return a / b; }` clears the
// register above with a four-byte move of zero and then divides with a divl. The
// register is cleared here by xoring it with itself, which writes the same zero in
// fewer bytes.
pub fn (t &Target) divide_unsigned(src Register) ![]u8 {
	high := t.remainder() or {
		return error('${t.name}: the division needs the register above the result one to clear, and the table has none')
	}
	mut out := t.encoders.xor_reg64(t.describe(high), t.describe(high))!
	out << t.encoders.div_reg32(t.describe(src))!
	return out
}

// divide_word divides at the width of a word, signed: the accumulator's sign is
// spread over the register above it first, which is the pair the machine divides.
pub fn (t &Target) divide_word(src Register) ![]u8 {
	mut out := t.encoders.cqo()
	out << t.encoders.idiv_reg64(t.describe(src))!
	return out
}

// divide_word_unsigned is that division with the pair read as unsigned, which is
// what `18446744073709551615 / 3` asks for: the register above is cleared, so the
// dividend is the value itself and not a value with a sign above it.
pub fn (t &Target) divide_word_unsigned(src Register) ![]u8 {
	high := t.remainder() or {
		return error('${t.name}: the division needs the register above the result one to clear, and the table has none')
	}
	mut out := t.encoders.xor_reg64(t.describe(high), t.describe(high))!
	out << t.encoders.div_reg64(t.describe(src))!
	return out
}

pub fn (t &Target) negate(reg Register) ![]u8 {
	return t.encoders.neg_reg32(t.describe(reg))
}

pub fn (t &Target) complement(reg Register) ![]u8 {
	return t.encoders.not_reg32(t.describe(reg))
}

// test and compare set the flags a branch reads. test compares a value with zero;
// compare puts two values in the order the operator names and turns the flags
// into a value of the language's int width, zero or one.
pub fn (t &Target) test(reg Register) ![]u8 {
	return t.encoders.test_reg32(t.describe(reg))
}

// logical_not answers whether a value is zero, as the language's not operator
// asks: the value is compared with zero and the flags become a value of int
// width, which is the same shape a comparison has and the reason it is written
// here rather than as an instruction of its own.
pub fn (t &Target) logical_not(reg Register) ![]u8 {
	mut out := t.encoders.test_reg32(t.describe(reg))!
	out << t.encoders.set_condition(Condition.equal, t.describe(reg))!
	out << t.encoders.movzx_byte(t.describe(reg))!
	return out
}

// logical_not_word is the same question asked of a value eight bytes wide, which
// is what `!x` on a 64-bit integer is: testing the low four bytes would call
// 4294967296 zero.
pub fn (t &Target) logical_not_word(reg Register) ![]u8 {
	mut out := t.encoders.test_reg64(t.describe(reg))!
	out << t.encoders.set_condition(Condition.equal, t.describe(reg))!
	out << t.encoders.movzx_byte(t.describe(reg))!
	return out
}

pub fn (t &Target) compare(op string, left Register, right Register) ![]u8 {
	condition := condition_of(t.name, op)!
	mut out := t.encoders.cmp_reg32(t.describe(left), t.describe(right))!
	out << t.encoders.set_condition(condition, t.describe(left))!
	out << t.encoders.movzx_byte(t.describe(left))!
	return out
}

// compare_word is the same comparison at the width of a word, which is what two
// addresses are compared at: comparing the low halves of two addresses would call
// two different ones equal.
pub fn (t &Target) compare_word(op string, left Register, right Register) ![]u8 {
	condition := condition_of(t.name, op)!
	mut out := t.encoders.cmp_reg64(t.describe(left), t.describe(right))!
	out << t.encoders.set_condition(condition, t.describe(left))!
	out << t.encoders.movzx_byte(t.describe(left))!
	return out
}

// compare_unsigned and compare_word_unsigned are the same two comparisons with the
// orders read as unsigned, which is what the comparison of two `unsigned int` or
// two `unsigned long` values asks for: measured on gcc 16.2.1 at -O0,
// `unsigned int h(unsigned int a, unsigned int b) { return a < b; }` ends in a
// setb and not in the setl a signed comparison of the same values ends in, and
// `-1 < 0u` is false where `-1 < 0` is true.
pub fn (t &Target) compare_unsigned(op string, left Register, right Register) ![]u8 {
	condition := condition_for(t.name, op, true)!
	mut out := t.encoders.cmp_reg32(t.describe(left), t.describe(right))!
	out << t.encoders.set_condition(condition, t.describe(left))!
	out << t.encoders.movzx_byte(t.describe(left))!
	return out
}

pub fn (t &Target) compare_word_unsigned(op string, left Register, right Register) ![]u8 {
	condition := condition_for(t.name, op, true)!
	mut out := t.encoders.cmp_reg64(t.describe(left), t.describe(right))!
	out << t.encoders.set_condition(condition, t.describe(left))!
	out << t.encoders.movzx_byte(t.describe(left))!
	return out
}

// move_register64 copies one register into another at the width of a word, which
// is how an address moves from where it was computed to where it is wanted.
pub fn (t &Target) move_register64(dst Register, src Register) ![]u8 {
	return t.encoders.mov_reg64(t.describe(dst), t.describe(src))
}

// condition_of is the order an operator names as the machine's condition, and the
// one place the two translations between an operator and an instruction's test
// meet: a comparison and a branch both ask it.
fn condition_of(target string, op string) !Condition {
	return condition_for(target, op, false)
}

// condition_for is the condition one operator asks for, with the signedness of
// the comparison named. Four of the six exist in both forms, and which form a
// comparison wants is the type of its operands; the equalities are the same
// condition either way. A value two words wide is compared with the borrow out of
// the subtraction of its low words, which lands in the carry flag, so the orders
// that a pair is ordered by are the unsigned ones: measured on gcc 16.2.1, the
// code for `a < b` on two unsigned 128-bit values and on two signed ones differs
// in the setcc alone.
pub fn condition_for(target string, op string, unsigned bool) !Condition {
	if unsigned {
		return match op {
			'==' { Condition.equal }
			'!=' { Condition.not_equal }
			'<' { Condition.below }
			'>' { Condition.above }
			'<=' { Condition.below_or_equal }
			'>=' { Condition.above_or_equal }
			else {
				return error('${target}: ${op} is not an order this machine has a condition for')
			}
		}
	}
	return match op {
		'==' { Condition.equal }
		'!=' { Condition.not_equal }
		'<' { Condition.less }
		'>' { Condition.greater }
		'<=' { Condition.less_or_equal }
		'>=' { Condition.greater_or_equal }
		else { return error('${target}: ${op} is not an order this machine has a condition for') }
	}
}

// The double instructions, named for what the language asks for rather than for
// the instruction that carries it. A double is not a wide int: the machine moves
// it, computes it and compares it with a different set of instructions, which is
// why these are written beside the ones above rather than as a width on them.
pub fn (t &Target) load_double_slot(base Register, disp i32, dst Register) ![]u8 {
	return t.encoders.load_double_slot(t.describe(base), disp, t.describe(dst))
}

pub fn (t &Target) store_double_slot(base Register, disp i32, src Register) ![]u8 {
	return t.encoders.store_double_slot(t.describe(base), disp, t.describe(src))
}

// load_float_slot and store_float_slot are the same two moves for a float,
// which is four bytes rather than eight. Both are the one instruction with the
// single-precision prefix, so a caller that knows which width a slot holds does
// not have to know an encoding to read or write it.
pub fn (t &Target) load_float_slot(base Register, disp i32, dst Register) ![]u8 {
	return t.encoders.load_float_slot(t.describe(base), disp, t.describe(dst))
}

pub fn (t &Target) store_float_slot(base Register, disp i32, src Register) ![]u8 {
	return t.encoders.store_float_slot(t.describe(base), disp, t.describe(src))
}

// load_double_constant reads a double out of the image's read-only data, which
// is where a floating constant lives: the eight bytes are the value, and the
// instruction names the place they are at relative to itself.
pub fn (t &Target) load_double_constant(dst Register, disp i32) ![]u8 {
	return t.encoders.load_double_rip(t.describe(dst), disp)
}

// load_float_constant is the same read of a single-precision constant, which is
// four bytes in the image rather than eight.
pub fn (t &Target) load_float_constant(dst Register, disp i32) ![]u8 {
	return t.encoders.load_float_rip(t.describe(dst), disp)
}

pub fn (t &Target) load_double_indirect(address Register, dst Register) ![]u8 {
	return t.encoders.load_double_indirect(t.describe(address), t.describe(dst))
}

pub fn (t &Target) store_double_indirect(address Register, src Register) ![]u8 {
	return t.encoders.store_double_indirect(t.describe(address), t.describe(src))
}

// load_float_indirect and store_float_indirect are the same pair of moves for a
// value four bytes wide.
pub fn (t &Target) load_float_indirect(address Register, dst Register) ![]u8 {
	return t.encoders.load_float_indirect(t.describe(address), t.describe(dst))
}

pub fn (t &Target) store_float_indirect(address Register, src Register) ![]u8 {
	return t.encoders.store_float_indirect(t.describe(address), t.describe(src))
}

// The x87 moves are the conversions a long double needs. A long double is not a
// value in a register file, so there is no register to describe: each of these
// names an address the way the scalar indirect moves do, and the instruction
// itself carries the operation. `load_extended`/`store_extended` move the
// extended format, the double and integer pairs move a value of that type
// through the extended stack so the machine does the conversion.
pub fn (t &Target) load_extended(address Register) ![]u8 {
	return t.encoders.load_extended(t.describe(address))
}

pub fn (t &Target) store_extended(address Register) ![]u8 {
	return t.encoders.store_extended(t.describe(address))
}

pub fn (t &Target) load_double_extended(address Register) ![]u8 {
	return t.encoders.load_double_extended(t.describe(address))
}

pub fn (t &Target) store_double_extended(address Register) ![]u8 {
	return t.encoders.store_double_extended(t.describe(address))
}

pub fn (t &Target) load_int_extended(address Register) ![]u8 {
	return t.encoders.load_int_extended(t.describe(address))
}

pub fn (t &Target) load_word_extended(address Register) ![]u8 {
	return t.encoders.load_word_extended(t.describe(address))
}

pub fn (t &Target) store_int_extended(address Register) ![]u8 {
	return t.encoders.store_int_extended(t.describe(address))
}

pub fn (t &Target) store_word_extended(address Register) ![]u8 {
	return t.encoders.store_word_extended(t.describe(address))
}

pub fn (t &Target) move_double(dst Register, src Register) ![]u8 {
	return t.encoders.move_double(t.describe(dst), t.describe(src))
}

// move_float copies one floating-point register into another at four bytes.
pub fn (t &Target) move_float(dst Register, src Register) ![]u8 {
	return t.encoders.move_float(t.describe(dst), t.describe(src))
}

// double_arithmetic applies an arithmetic operator to two doubles. The operator
// names are the language's, so the four instructions stay in the machine's file.
pub fn (t &Target) double_arithmetic(op string, dst Register, src Register) ![]u8 {
	return t.encoders.double_arithmetic(op, t.describe(dst), t.describe(src))
}

// float_arithmetic is the same four operations computed at four bytes, which is
// how a float expression rounds at every step rather than carrying a double
// through it.
pub fn (t &Target) float_arithmetic(op string, dst Register, src Register) ![]u8 {
	return t.encoders.float_arithmetic(op, t.describe(dst), t.describe(src))
}

// double_comparison puts two doubles in the order the operator names and leaves
// the answer in a register as zero or one. The comparison itself only sets
// flags, so the answer is read out of them, and for the orders where an
// unordered pair would otherwise answer wrongly a second flag is read and
// combined with the first. A NaN is not less than, equal to, or greater than
// anything, and the pair of flags is what says so.
pub fn (t &Target) double_comparison(op string, left Register, right Register, reg Register, scratch Register) ![]u8 {
	mut out := t.encoders.compare_double(t.describe(left), t.describe(right))!
	out << t.encoders.set_float_condition(op, t.describe(reg), t.describe(scratch))!
	return out
}

// float_comparison is the same comparison at four bytes. Only the instruction
// that sets the flags differs; the orders are read out of the flags the same
// way, because Comiss sets them where Comisd does.
pub fn (t &Target) float_comparison(op string, left Register, right Register, reg Register, scratch Register) ![]u8 {
	mut out := t.encoders.compare_float(t.describe(left), t.describe(right))!
	out << t.encoders.set_float_condition(op, t.describe(reg), t.describe(scratch))!
	return out
}

// zero_double clears a register. It is how the right-hand side of a comparison
// against zero is made without a constant in memory.
pub fn (t &Target) zero_double(reg Register) ![]u8 {
	return t.encoders.zero_double(t.describe(reg))
}

// negate_double flips the sign of a double through a general register, because
// the machine has an instruction that negates an integer and none that negates a
// floating value.
pub fn (t &Target) negate_double(reg Register, gp Register) ![]u8 {
	return t.encoders.negate_double(t.describe(reg), t.describe(gp))
}

// negate_single is the same sign flip at four bytes, which is bit 31 rather than
// bit 63 of the register the float sits in.
pub fn (t &Target) negate_single(reg Register, gp Register) ![]u8 {
	return t.encoders.negate_single(t.describe(reg), t.describe(gp))
}

// int_to_double widens a four-byte integer to a double, and double_to_int
// truncates a double to a four-byte integer. Those are the two conversions the
// language asks for between the classes, and the machine keeps them in the
// floating-point file, which is why they are named here.
pub fn (t &Target) int_to_double(dst Register, src Register) ![]u8 {
	return t.encoders.int_to_double(t.describe(dst), t.describe(src))
}

pub fn (t &Target) double_to_int(dst Register, src Register) ![]u8 {
	return t.encoders.double_to_int(t.describe(dst), t.describe(src))
}

// int_to_float and float_to_int are the same two conversions at four bytes.
pub fn (t &Target) int_to_float(dst Register, src Register) ![]u8 {
	return t.encoders.int_to_float(t.describe(dst), t.describe(src))
}

pub fn (t &Target) float_to_int(dst Register, src Register) ![]u8 {
	return t.encoders.float_to_int(t.describe(dst), t.describe(src))
}

// float_to_double widens a float into a double and double_to_float narrows one
// back, which is the conversion between the two floating types. Both operands
// are in the floating-point file, so neither touches a general register.
pub fn (t &Target) float_to_double(dst Register, src Register) ![]u8 {
	return t.encoders.float_to_double(t.describe(dst), t.describe(src))
}

pub fn (t &Target) double_to_float(dst Register, src Register) ![]u8 {
	return t.encoders.double_to_float(t.describe(dst), t.describe(src))
}

// unsigned_int_to_double converts an unsigned four-byte integer to a double. The
// signed conversion reads the top bit as a sign, so the source reaches this one
// zero-extended instead.
pub fn (t &Target) unsigned_int_to_double(dst Register, src Register) ![]u8 {
	return t.encoders.unsigned_int_to_double(t.describe(dst), t.describe(src))
}

// The same conversion for an unsigned four-byte integer: the signed instruction
// reads its top bit as a sign, so the destination has to be converted at a width
// every unsigned four-byte value fits in.
pub fn (t &Target) double_to_unsigned_int(dst Register, src Register) ![]u8 {
	return t.encoders.double_to_unsigned_int(t.describe(dst), t.describe(src))
}

// signed_word_to_double and unsigned_word_to_double are the same conversion where
// the source is eight bytes wide. The signed one is the four-byte conversion at
// eight bytes; the unsigned one is the range split, which gives the source a
// second register to fold its low bit into and the word above it.
pub fn (t &Target) signed_word_to_double(dst Register, src Register) ![]u8 {
	return t.encoders.signed_word_to_double(t.describe(dst), t.describe(src))
}

pub fn (t &Target) unsigned_word_to_double(dst Register, src Register, scratch Register) ![]u8 {
	return t.encoders.unsigned_word_to_double(t.describe(dst), t.describe(src), t.describe(scratch))
}

// double_to_signed_word and double_to_unsigned_word truncate a double into an
// eight-byte integer. The unsigned one takes a general register for 2^63 and a
// double register to hold it in, because the boundary is a double and no
// instruction here carries one as an immediate for the floating-point file.
pub fn (t &Target) double_to_signed_word(dst Register, src Register) ![]u8 {
	return t.encoders.double_to_signed_word(t.describe(dst), t.describe(src))
}

pub fn (t &Target) double_to_unsigned_word(dst Register, src Register, scratch Register, float_scratch Register) ![]u8 {
	return t.encoders.double_to_unsigned_word(t.describe(dst), t.describe(src), t.describe(scratch), t.describe(float_scratch))
}

// The jumps. The distance is filled in once the whole function is laid out,
// which is why a jump is written here with a displacement the emitter will patch.
pub fn (t &Target) jump(disp i32) []u8 {
	return t.encoders.jump_rel32(disp)
}

pub fn (t &Target) jump_if_zero(disp i32) []u8 {
	return t.encoders.jump_zero_rel32(disp)
}

pub fn (t &Target) jump_if_not_zero(disp i32) []u8 {
	return t.encoders.jump_nonzero_rel32(disp)
}

// The instructions a value two words wide needs. Such a value lives in the pair the
// result register and the one above it form: the low word in the result register,
// which is where a value is computed, and the high word in the register above it,
// which is also where a division leaves its remainder. Each function says which
// word it works on. Nothing here decides which word a caller wants; it forwards
// the machine's instruction and the name carries the side.

pub fn (t &Target) subtract_word(dst Register, src Register) ![]u8 {
	return t.encoders.sub_reg64(t.describe(dst), t.describe(src))
}

// add_with_carry is the high word of a two-word addition: it adds the carry out of
// the addition of the low words as well as the two sources. It reads the flags the
// instruction before it left, so it is always the second instruction of the pair.
pub fn (t &Target) add_with_carry(dst Register, src Register) ![]u8 {
	return t.encoders.adc_reg64(t.describe(dst), t.describe(src))
}

// add_with_carry_immediate is the same addition with the second value in the
// instruction. The high word of a two-word negation takes a carry of zero through
// it: negating the low word leaves a borrow in the flag when that word was not
// zero, and no register is free to hold the zero being added.
pub fn (t &Target) add_with_carry_immediate(dst Register, value i32) ![]u8 {
	return t.encoders.adc_immediate(t.describe(dst), value)
}

// subtract_with_borrow is the high word of a two-word subtraction: it takes the
// borrow out of the subtraction of the low words as well as subtracting the two
// sources. The flags it leaves are the order of the two words, which is the
// comparison a value two words wide is made of.
pub fn (t &Target) subtract_with_borrow(dst Register, src Register) ![]u8 {
	return t.encoders.sbb_reg64(t.describe(dst), t.describe(src))
}

pub fn (t &Target) and_word(dst Register, src Register) ![]u8 {
	return t.encoders.and_reg64(t.describe(dst), t.describe(src))
}

pub fn (t &Target) or_word(dst Register, src Register) ![]u8 {
	return t.encoders.or_reg64(t.describe(dst), t.describe(src))
}

pub fn (t &Target) xor_word(dst Register, src Register) ![]u8 {
	return t.encoders.xor_reg64(t.describe(dst), t.describe(src))
}

// test_word asks one word whether it is zero and sets the flags without producing
// a value, which is how the first half of a two-word value is asked.
pub fn (t &Target) test_word(reg Register) ![]u8 {
	return t.encoders.test_reg64(t.describe(reg))
}

// shift_left_word and shift_right_word shift one word of the pair by a constant
// count, and shift_wide_left and shift_wide_right shift the two words as one value
// twice as wide: the bits that leave the word being shifted are not lost but come
// in at the other end of the word beside it, which is what the middle word of a
// shift of a value wider than one word needs.
pub fn (t &Target) shift_left_word(reg Register, bits u8) ![]u8 {
	return t.encoders.shl_reg64(t.describe(reg), bits)
}

pub fn (t &Target) shift_right_word(reg Register, bits u8) ![]u8 {
	return t.encoders.shr_reg64(t.describe(reg), bits)
}

pub fn (t &Target) shift_wide_left(dst Register, src Register, bits u8) ![]u8 {
	return t.encoders.shld_immediate(t.describe(dst), t.describe(src), bits)
}

pub fn (t &Target) shift_wide_right(dst Register, src Register, bits u8) ![]u8 {
	return t.encoders.shrd_immediate(t.describe(dst), t.describe(src), bits)
}

// The shifts whose count is in a register rather than in the instruction. Each is
// what a shift by a count the program works out needs, and the machine reads the
// count modulo the register's width rather than being told not to.
pub fn (t &Target) shift_left_narrow_register(reg Register) ![]u8 {
	return t.encoders.shift_left_narrow(t.describe(reg))
}

pub fn (t &Target) shift_right_narrow_register(reg Register) ![]u8 {
	return t.encoders.shift_right_narrow(t.describe(reg))
}

pub fn (t &Target) shift_right_arithmetic_narrow_register(reg Register) ![]u8 {
	return t.encoders.shift_right_arithmetic_narrow(t.describe(reg))
}

pub fn (t &Target) shift_left_word_register(reg Register) ![]u8 {
	return t.encoders.shift_left_word_register(t.describe(reg))
}

pub fn (t &Target) shift_right_word_register(reg Register) ![]u8 {
	return t.encoders.shift_right_word_register(t.describe(reg))
}

pub fn (t &Target) shift_right_arithmetic_word_register(reg Register) ![]u8 {
	return t.encoders.shift_right_arithmetic_register(t.describe(reg))
}

pub fn (t &Target) shift_wide_left_register(dst Register, src Register) ![]u8 {
	return t.encoders.shld_register(t.describe(dst), t.describe(src))
}

pub fn (t &Target) shift_wide_right_register(dst Register, src Register) ![]u8 {
	return t.encoders.shrd_register(t.describe(dst), t.describe(src))
}

pub fn (t &Target) test_byte_immediate(reg Register, value u8) ![]u8 {
	return t.encoders.test_byte_immediate(t.describe(reg), value)
}

// multiply_pair and multiply_pair_signed multiply the result register by the
// source and leave the two-word product in the pair.
// multiply_word multiplies one word by another and keeps the low word of the
// answer. A pair's multiplication uses it for the two cross products, whose upper
// halves cannot reach the answer.
pub fn (t &Target) multiply_word(dst Register, src Register) ![]u8 {
	return t.encoders.imul_word64(t.describe(dst), t.describe(src))
}

pub fn (t &Target) multiply_pair(src Register) ![]u8 {
	return t.encoders.mul_reg64(t.describe(src))
}

pub fn (t &Target) multiply_pair_signed(src Register) ![]u8 {
	return t.encoders.imul_reg64(t.describe(src))
}

// divide_pair and divide_pair_signed divide the pair by the source and leave the
// quotient in the result register with the remainder above it, which is where the
// language's two division operators read their answers from.
pub fn (t &Target) divide_pair(src Register) ![]u8 {
	return t.encoders.div_reg64(t.describe(src))
}

pub fn (t &Target) divide_pair_signed(src Register) ![]u8 {
	return t.encoders.idiv_reg64(t.describe(src))
}

pub fn (t &Target) negate_word(reg Register) ![]u8 {
	return t.encoders.neg_reg64(t.describe(reg))
}

pub fn (t &Target) complement_word(reg Register) ![]u8 {
	return t.encoders.not_reg64(t.describe(reg))
}

// Condition is the machine's condition, named here for the same reason Register is
// above: a caller asks this module for a machine fact and should not have to reach
// into the machine's own file to say what it received. The unsigned orders are the
// ones a value two words wide is compared with, because the borrow out of the
// subtraction of the low words is a carry flag and not a sign flag.
pub type Condition = x86_64.Condition

// set_condition writes the outcome of the comparison whose flags are standing into
// the low byte of a register, as zero or one. It is the instruction a comparison of
// two words ends with, and it is here rather than inside a comparison method
// because the flags a caller hands it come from the subtraction of the pair, which
// that caller wrote. The byte is widened with widen_byte.
pub fn (t &Target) set_condition(condition Condition, reg Register) ![]u8 {
	return t.encoders.set_condition(condition, t.describe(reg))
}

// widen_byte turns that one byte into a value of the language's int width, since a
// comparison is a value of that width and not a byte.
pub fn (t &Target) widen_byte(reg Register) ![]u8 {
	return t.encoders.movzx_byte(t.describe(reg))
}

// Library is one -l name resolved to a file: the file the search found and the
// name the image carries for it. The two are not the same string, which is why
// both are kept, and it is the system's own answer rather than a shape invented
// here.
pub struct Library {
pub:
	path   string
	soname string
}

// library_dirs_for is where a -l name is searched for: the -L directories in the
// order they were given, then the target's own. The linker and the query flags
// both ask this, so there is one search and not two.
pub fn (t &Target) library_dirs_for(given []string) []string {
	return linux.search_dirs(given, t.library_dirs)
}

// library_file is the file a name resolves to in that search, or none when the
// search does not have it. It is `linux.find_file`, the same walk a -l name and a
// `-l:file` take, so `-print-file-name=` answers with a file the linker would
// really pick and answers the name unchanged when there is none.
pub fn (t &Target) library_file(name string, given []string) ?string {
	return linux.find_file(name, t.library_dirs_for(given))
}

// resolve_libraries is the linker's own resolution of the -l names: the file
// behind each one and the name the image carries, in the order they were given
// and without repeating one. A query that reports what the link would do asks
// this rather than resolving again.
pub fn (t &Target) resolve_libraries(names []string, given []string) ![]Library {
	files := linux.resolve_library_files(names, t.library_dirs_for(given))!
	mut out := []Library{}
	for file in files {
		out << Library{
			path:   file.path
			soname: file.soname
		}
	}
	return out
}

// base_library is the C library every image this system writes runs against,
// named whether or not a -l asked for it. It is reported with the resolved
// libraries so that a description of what the image carries is complete.
pub fn (t &Target) base_library() string {
	return t.base_library_name
}

// link_dirs is everywhere a link on this system looks for a file: the
// directories a -l name goes through, with the toolchain's own support
// directory last. It is last so that a library the system keeps is the one a -l
// name resolves to, and it is in the list at all because crtbeginS.o,
// crtbeginT.o, crtend.o and the libgcc archives are in no other directory.
pub fn (t &Target) link_dirs(given []string) []string {
	mut dirs := t.library_dirs_for(given)
	dirs << linux.support_dirs(t.arch, t.os)
	return dirs
}

// external_link_arguments is the command line a linker named with
// -external-linker is given. The loader, the start files and the library
// directories all come from the system's description through linux, so the
// external link and the in-house image name the same places and a second system
// is a second directory rather than a second set of strings here.
//
// `kind` is which link was asked for, `objects` are the inputs in command-line
// order, `given_dirs` are the -L directories the command line added,
// `libraries` are its -l names, and `output` is where the file is written.
pub fn (t &Target) external_link_arguments(kind linux.LinkKind, objects []string, given_dirs []string, libraries []string, output string) ![]string {
	return linux.link_arguments(kind, t.interpreter, t.link_dirs(given_dirs), objects, libraries, output)
}
