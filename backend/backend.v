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
	page_size   u64
	load_base   u64
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
		elf_machine:        arch.machine
		return_reg:         arch.return_reg
		syscalls:           os.syscalls(arch.name)
		syscall_number_reg: arch.syscall_number_reg
		syscall_args_regs:  os.syscall_args_regs(arch.name)
		exit_syscall:       os.exit_syscall
		interpreter:        os.interpreter
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
