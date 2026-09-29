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
	// From the system: the kernel entry points, the registers the kernel expects
	// with them, and where the loader puts the image.
	syscalls           []os.Syscall
	syscall_number_reg string
	syscall_args_regs  []string
	exit_syscall       string
	page_size          u64
	load_base          u64
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
		syscalls:           os.syscalls(arch.name)
		syscall_number_reg: arch.syscall_number_reg
		syscall_args_regs:  os.syscall_args_regs(arch.name)
		exit_syscall:       os.exit_syscall
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
