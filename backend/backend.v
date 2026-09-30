module backend

import backend.arch
import backend.os

// A target is two descriptions composed: a machine from `backend/arch` and a
// system from `backend/os`. Neither of those knows the other exists, and this is
// the only place they meet. The emitter asks a Target, so a new architecture, a
// new system, or a new fact about either one does not reach codegen.
//
// The description carries what the compiler emits today. An entry no code path
// reads is a claim nobody has tested, so the tables stay partial on purpose.
pub struct Target {
pub:
	// name spells the two descriptions the way the command line does.
	name string
	arch string
	os   string
	// From the machine: its register file, the width of a register, and the
	// number a container header gives this architecture.
	word_size   int
	registers   []arch.Register
	elf_machine u16
	// float_registers is the machine's second file, the one a double is passed
	// and computed in. It is listed separately because it carries its own
	// argument positions: a call numbers its integer arguments and its floating
	// ones in two sequences, so the same position exists in both.
	float_registers []arch.Register
	// return_reg is the register a function leaves its result in, by the name
	// the machine's table uses.
	return_reg string
	// From the system: the kernel entry points, the registers the kernel expects
	// with them, and where the loader puts the image.
	syscalls           []os.Syscall
	syscall_number_reg string
	syscall_args_regs  []string
	exit_syscall       string
	// interpreter is the loader the kernel starts for a dynamically linked
	// image. A program that calls a shared library has to name it in the image.
	interpreter string
	// library_dirs is where a library named with -l is looked for, the -L
	// directories having been searched first.
	library_dirs []string
	page_size    u64
	load_base    u64
}

// targets lists the descriptions the compiler can emit for. A new target is a
// composition of a machine and a system, not a new branch in the emitter.
pub fn targets() []Target {
	return [x86_64_linux()]
}

// x86_64_linux is the machine `backend/arch/x86_64.v` running the system
// `backend/os/linux.v`. Every field comes from one of the two, which is what
// makes the composition checkable: nothing here decides anything itself.
fn x86_64_linux() Target {
	return Target{
		name:               '${arch.name}-${os.name}'
		arch:               arch.name
		os:                 os.name
		word_size:          arch.word_size
		registers:          arch.registers()
		float_registers:    arch.float_registers()
		elf_machine:        arch.machine
		return_reg:         arch.return_reg
		syscalls:           os.syscalls(arch.name)
		syscall_number_reg: arch.syscall_number_reg
		syscall_args_regs:  os.syscall_args_regs(arch.name)
		exit_syscall:       os.exit_syscall
		interpreter:        os.interpreter
		library_dirs:       os.library_dirs(arch.name, os.name)
		page_size:          os.page_size
		load_base:          os.load_base
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

// reg finds a register by the name it is written with. Both spellings of the
// same register answer, because callers name the width they mean.
pub fn (t Target) reg(name string) ?arch.Register {
	for r in t.registers {
		if r.name == name || r.wide_name == name {
			return r
		}
	}
	return none
}

// arg_reg is the register that carries argument `position` of a function call,
// or none once the machine's convention has run out of registers. Callers ask
// for a position rather than for a register name so that a second machine with a
// different convention is a table, not an emitter change.
pub fn (t Target) arg_reg(position int) ?arch.Register {
	for r in t.registers {
		if r.call_arg == position {
			return r
		}
	}
	return none
}

// float_reg finds a register in the machine's floating-point file by name.
pub fn (t Target) float_reg(name string) ?arch.Register {
	for r in t.float_registers {
		if r.name == name || r.wide_name == name {
			return r
		}
	}
	return none
}

// float_arg_reg is the register that carries floating-point argument `position`.
// It is a second sequence on purpose: a call to `printf("%f", 1.5)` numbers the
// format string in the integer sequence and the double in this one, so both
// start at zero.
pub fn (t Target) float_arg_reg(position int) ?arch.Register {
	for r in t.float_registers {
		if r.float_call_arg == position {
			return r
		}
	}
	return none
}

// float_return is where a function leaves a floating-point result, and
// float_scratch is where the right-hand value of a floating-point operation
// waits while the left-hand one sits in the first. They are the same pair of
// roles the general register file has, one file over.
pub fn (t Target) float_return() ?arch.Register {
	return t.float_reg(arch.float_return_reg)
}

pub fn (t Target) float_scratch() ?arch.Register {
	return t.float_reg(arch.float_scratch_reg)
}

// syscall finds a kernel entry point by name.
pub fn (t Target) syscall(name string) ?os.Syscall {
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
pub fn (t Target) exit_sequence(code u8) ![]u8 {
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
	mut out := arch.mov_imm32(status_reg, u32(code))!
	out << arch.mov_imm32(number_reg, exit_call.number)!
	out << arch.trap()
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
pub fn (t Target) call_near(disp i32) []u8 {
	return arch.call_rel32(disp)
}

// call_slot is a call to the address a quadword holds, found through a
// displacement from the instruction. A dynamically linked program reaches the
// library's functions this way, because the library's address is not known until
// the loader has run.
pub fn (t Target) call_slot(disp i32) []u8 {
	return arch.call_rip_slot(disp)
}

// address_of computes the address of a byte string in the image and puts it in
// the register, which is how a string argument is passed.
pub fn (t Target) address_of(reg arch.Register, disp i32) []u8 {
	return arch.lea_rip(reg, disp)
}

// move_immediate32 loads a constant into a register.
pub fn (t Target) move_immediate32(reg arch.Register, value u32) ![]u8 {
	return arch.mov_imm32(reg, value)
}

// move_register32 copies one register into another, which is how a value a
// function returned reaches the register the next call reads it from.
pub fn (t Target) move_register32(dst arch.Register, src arch.Register) ![]u8 {
	return arch.mov_reg32(dst, src)
}

// frame_prologue and frame_epilogue are the two ends of a function body.
pub fn (t Target) frame_prologue() []u8 {
	return arch.frame_prologue()
}

pub fn (t Target) frame_epilogue() []u8 {
	return arch.frame_epilogue()
}

// halt stops the machine. It is what follows a call that is not expected to
// return, so that control never runs past the code that was emitted.
pub fn (t Target) halt() []u8 {
	return arch.halt()
}

// Register is the machine's register, named again here because it is what the
// functions below hand back: a caller asks this module for a machine fact and
// should not have to reach into the machine's own file to say what it received.
pub type Register = arch.Register

// The instructions a body with locals, branches and arithmetic needs, in the
// same spirit as the ones above: each asks the machine's file for the encoding
// rather than spelling one here.

// frame_pointer is the register a local is found at, scratch is where the
// right-hand value of an operation waits while the left-hand one sits in the
// result register, and remainder is where a division leaves what did not divide
// evenly.
pub fn (t Target) frame_pointer() ?arch.Register {
	return t.reg(arch.frame_pointer)
}

pub fn (t Target) scratch() ?arch.Register {
	return t.reg(arch.scratch_reg)
}

pub fn (t Target) remainder() ?arch.Register {
	return t.reg(arch.remainder_reg)
}

// frame_reserve opens the space a function's locals live in. The size is not
// known while the body is written, so frame_immediate_offset is where it sits in
// those bytes and the emitter fills it in once the body has been walked.
// push_register and stack_release are the two instructions a call's arguments
// past the registers need: the caller puts them on the stack before the call and
// gives the stack back after it, and the callee reads them from where the
// convention says they are.
pub fn (t Target) push_register(reg arch.Register) []u8 {
	return arch.push_register(reg)
}

pub fn (t Target) stack_release(size u32) []u8 {
	return arch.stack_release(size)
}

pub fn (t Target) frame_reserve(size u32) []u8 {
	return arch.frame_reserve(size)
}

pub fn (t Target) frame_immediate_offset() int {
	return arch.frame_reserve_immediate
}

// align_stack is how the entry point makes the stack aligned before it calls
// anything: a process is started on whatever stack the kernel left, and every
// frame this compiler opens assumes the boundary is where the convention puts it.
pub fn (t Target) align_stack() []u8 {
	return arch.align_stack()
}

// load_slot and store_slot move a value between the frame and a register at the
// width the value has: four bytes for an int, eight for a pointer.
pub fn (t Target) load_slot(base arch.Register, disp i32, dst arch.Register, width int) ![]u8 {
	return arch.load_slot(base, disp, dst, width)
}

pub fn (t Target) store_slot(base arch.Register, disp i32, src arch.Register, width int) ![]u8 {
	return arch.store_slot(base, disp, src, width)
}

// The address of a value in the frame, the address of one element of it, and the
// moves through an address: what an array needs to be read and written one
// element at a time.
// add_immediate folds a constant into a register. A member of an object named by a
// pointer is read at the pointer's value plus the member's offset, and this is the
// addition that makes the two one address.
pub fn (t Target) add_immediate(dst arch.Register, value i32) []u8 {
	return arch.add_immediate(dst, value)
}

// add_reg64 and imul_immediate are the two steps that reach an element whose
// stride the scaled address cannot write: multiply the index by the stride, add
// the array's address.
pub fn (t Target) add_reg64(dst arch.Register, src arch.Register) []u8 {
	return arch.add_reg64(dst, src)
}

pub fn (t Target) imul_immediate(dst arch.Register, value i32) []u8 {
	return arch.imul_immediate(dst, value)
}

pub fn (t Target) address_of_slot(base arch.Register, disp i32, dst arch.Register) []u8 {
	return arch.address_of_slot(base, disp, dst)
}

pub fn (t Target) address_of_element(base arch.Register, index arch.Register, scale int, disp i32, dst arch.Register) ![]u8 {
	return arch.address_of_element(base, index, scale, disp, dst)
}

pub fn (t Target) load_indirect(address arch.Register, dst arch.Register, width int) ![]u8 {
	return arch.load_indirect(address, dst, width)
}

pub fn (t Target) store_indirect(address arch.Register, src arch.Register, width int) ![]u8 {
	return arch.store_indirect(address, src, width)
}

// The two widenings a conversion between the value classes needs. A byte is
// widened with its sign kept, which is what converting a value to a char is; a
// word is widened into the whole register, which is what converting an int to a
// pointer is, because a pointer is the machine's word.
pub fn (t Target) sign_extend_byte(reg arch.Register) ![]u8 {
	return arch.sign_extend_byte(reg)
}

pub fn (t Target) sign_extend_word(dst arch.Register, src arch.Register) ![]u8 {
	return arch.sign_extend_word(dst, src)
}

// shift_right_arithmetic spreads the sign of a value over the whole register,
// which is what storing a value narrower than the word it goes into needs.
pub fn (t Target) shift_right_arithmetic(reg arch.Register, bits u8) ![]u8 {
	return arch.shift_right_arithmetic(reg, bits)
}

// The arithmetic, named for what the language asks for rather than for the
// instruction that carries it.
pub fn (t Target) add(dst arch.Register, src arch.Register) ![]u8 {
	return arch.add_reg32(dst, src)
}

pub fn (t Target) subtract(dst arch.Register, src arch.Register) ![]u8 {
	return arch.sub_reg32(dst, src)
}

pub fn (t Target) multiply(dst arch.Register, src arch.Register) ![]u8 {
	return arch.imul_reg32(dst, src)
}

// divide divides the result register by another one, signed. The sign goes over
// the register above first, because that pair is what the machine divides: the
// quotient is left in the result register and the remainder above it.
pub fn (t Target) divide(src arch.Register) ![]u8 {
	mut out := arch.cdq()
	out << arch.idiv_reg32(src)!
	return out
}

pub fn (t Target) negate(reg arch.Register) ![]u8 {
	return arch.neg_reg32(reg)
}

pub fn (t Target) complement(reg arch.Register) ![]u8 {
	return arch.not_reg32(reg)
}

// test and compare set the flags a branch reads. test compares a value with zero;
// compare puts two values in the order the operator names and turns the flags
// into a value of the language's int width, zero or one.
pub fn (t Target) test(reg arch.Register) ![]u8 {
	return arch.test_reg32(reg)
}

// logical_not answers whether a value is zero, as the language's not operator
// asks: the value is compared with zero and the flags become a value of int
// width, which is the same shape a comparison has and the reason it is written
// here rather than as an instruction of its own.
pub fn (t Target) logical_not(reg arch.Register) ![]u8 {
	mut out := arch.test_reg32(reg)!
	out << arch.set_condition(arch.Condition.equal, reg)!
	out << arch.movzx_byte(reg)!
	return out
}

pub fn (t Target) compare(op string, left arch.Register, right arch.Register) ![]u8 {
	condition := condition_of(t.name, op)!
	mut out := arch.cmp_reg32(left, right)!
	out << arch.set_condition(condition, left)!
	out << arch.movzx_byte(left)!
	return out
}

// compare_word is the same comparison at the width of a word, which is what two
// addresses are compared at: comparing the low halves of two addresses would call
// two different ones equal.
pub fn (t Target) compare_word(op string, left arch.Register, right arch.Register) ![]u8 {
	condition := condition_of(t.name, op)!
	mut out := arch.cmp_reg64(left, right)!
	out << arch.set_condition(condition, left)!
	out << arch.movzx_byte(left)!
	return out
}

// move_register64 copies one register into another at the width of a word, which
// is how an address moves from where it was computed to where it is wanted.
pub fn (t Target) move_register64(dst arch.Register, src arch.Register) ![]u8 {
	return arch.mov_reg64(dst, src)
}

// condition_of is the order an operator names as the machine's condition, and the
// one place the two translations between an operator and an instruction's test
// meet: a comparison and a branch both ask it.
fn condition_of(target string, op string) !arch.Condition {
	return match op {
		'==' { arch.Condition.equal }
		'!=' { arch.Condition.not_equal }
		'<' { arch.Condition.less }
		'>' { arch.Condition.greater }
		'<=' { arch.Condition.less_or_equal }
		'>=' { arch.Condition.greater_or_equal }
		else { return error('${target}: ${op} is not an order this machine has a condition for') }
	}
}

// The double instructions, named for what the language asks for rather than for
// the instruction that carries it. A double is not a wide int: the machine moves
// it, computes it and compares it with a different set of instructions, which is
// why these are written beside the ones above rather than as a width on them.
pub fn (t Target) load_double_slot(base arch.Register, disp i32, dst arch.Register) ![]u8 {
	return arch.load_double_slot(base, disp, dst)
}

pub fn (t Target) store_double_slot(base arch.Register, disp i32, src arch.Register) ![]u8 {
	return arch.store_double_slot(base, disp, src)
}

// load_double_constant reads a double out of the image's read-only data, which
// is where a floating constant lives: the eight bytes are the value, and the
// instruction names the place they are at relative to itself.
pub fn (t Target) load_double_constant(dst arch.Register, disp i32) ![]u8 {
	return arch.load_double_rip(dst, disp)
}

pub fn (t Target) load_double_indirect(address arch.Register, dst arch.Register) ![]u8 {
	return arch.load_double_indirect(address, dst)
}

pub fn (t Target) store_double_indirect(address arch.Register, src arch.Register) ![]u8 {
	return arch.store_double_indirect(address, src)
}

pub fn (t Target) move_double(dst arch.Register, src arch.Register) ![]u8 {
	return arch.move_double(dst, src)
}

// double_arithmetic applies an arithmetic operator to two doubles. The operator
// names are the language's, so the four instructions stay in the machine's file.
pub fn (t Target) double_arithmetic(op string, dst arch.Register, src arch.Register) ![]u8 {
	opcode := match op {
		'+' { arch.double_add }
		'-' { arch.double_subtract }
		'*' { arch.double_multiply }
		'/' { arch.double_divide }
		else {
			return error('${t.name}: ${op} is not an operation this machine computes a double with')
		}
	}
	return arch.double_arithmetic(opcode, dst, src)
}

// double_comparison puts two doubles in the order the operator names and leaves
// the answer in a register as zero or one. The comparison itself only sets
// flags, so the answer is read out of them, and for the orders where an
// unordered pair would otherwise answer wrongly a second flag is read and
// combined with the first. A NaN is not less than, equal to, or greater than
// anything, and the pair of flags is what says so.
pub fn (t Target) double_comparison(op string, left arch.Register, right arch.Register, reg arch.Register, scratch arch.Register) ![]u8 {
	mut out := arch.compare_double(left, right)!
	out << arch.set_float_condition(op, reg, scratch)!
	return out
}

// zero_double clears a register. It is how the right-hand side of a comparison
// against zero is made without a constant in memory.
pub fn (t Target) zero_double(reg arch.Register) ![]u8 {
	return arch.zero_double(reg)
}

// negate_double flips the sign of a double through a general register, because
// the machine has an instruction that negates an integer and none that negates a
// floating value.
pub fn (t Target) negate_double(reg arch.Register, gp arch.Register) ![]u8 {
	return arch.negate_double(reg, gp)
}

// int_to_double widens a four-byte integer to a double, and double_to_int
// truncates a double to a four-byte integer. Those are the two conversions the
// language asks for between the classes, and the machine keeps them in the
// floating-point file, which is why they are named here.
pub fn (t Target) int_to_double(dst arch.Register, src arch.Register) ![]u8 {
	return arch.int_to_double(dst, src)
}

pub fn (t Target) double_to_int(dst arch.Register, src arch.Register) ![]u8 {
	return arch.double_to_int(dst, src)
}

// The jumps. The distance is filled in once the whole function is laid out,
// which is why a jump is written here with a displacement the emitter will patch.
pub fn (t Target) jump(disp i32) []u8 {
	return arch.jump_rel32(disp)
}

pub fn (t Target) jump_if_zero(disp i32) []u8 {
	return arch.jump_zero_rel32(disp)
}

pub fn (t Target) jump_if_not_zero(disp i32) []u8 {
	return arch.jump_nonzero_rel32(disp)
}
