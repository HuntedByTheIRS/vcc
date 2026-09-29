module backend

// A target is described rather than coded: registers, syscall numbers, calling
// conventions and the container constants all live in tables, and the emitter
// asks the tables instead of holding branch-per-architecture logic. Adding a
// target means adding a file like `x86_64.v` and a line in `targets()`.
//
// The descriptions are deliberately partial. They carry what the compiler emits
// today; a table entry that no code path reads is a claim nobody has tested.
pub struct Target {
pub:
	name      string
	os        string
	arch      string
	word_size int
	// elf_machine is the e_machine value for this architecture.
	elf_machine u16
	// page_size is the alignment a loadable segment needs.
	page_size u64
	// load_base is where the first segment is mapped.
	load_base u64
	registers []Register
	syscalls  []Syscall
	// syscall_number_reg holds the syscall number when the trap is taken.
	syscall_number_reg string
	// syscall_args_regs are the kernel's argument registers, in order. They are
	// not the same as the function call registers: the kernel uses r10 where a
	// function call would use rcx.
	syscall_args_regs []string
	// exit_syscall names the syscall that ends a process.
	exit_syscall string
}

// Register is one machine register as the assembler names it, with the encoding
// number the instruction format wants.
pub struct Register {
pub:
	name string
	// wide_name is the same register at the target's word size.
	wide_name string
	// code is the register number used in instruction encodings.
	code u8
	// width is in bytes: 4 for the 32-bit name, 8 for the wide one.
	width int
	// call_arg is the SysV function argument position, or -1 when the register
	// is not an argument register.
	call_arg int
}

// Syscall is a kernel entry point: its number and the registers its arguments
// arrive in, in order.
pub struct Syscall {
pub:
	name   string
	number u32
	args   []string
}

// targets lists the descriptions the compiler can emit for.
pub fn targets() []Target {
	return [x86_64_linux()]
}

// lookup finds a target by name. Names are `arch-os`, the way the compiler
// spells them on the command line.
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
pub fn (t Target) reg(name string) ?Register {
	for r in t.registers {
		if r.name == name || r.wide_name == name {
			return r
		}
	}
	return none
}

// syscall finds a kernel entry point by name.
pub fn (t Target) syscall(name string) ?Syscall {
	for s in t.syscalls {
		if s.name == name {
			return s
		}
	}
	return none
}
