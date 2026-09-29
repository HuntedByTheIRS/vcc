module backend

// The x86-64 Linux target and the instruction encodings that belong to it. A
// second architecture adds a file shaped like this one: a table of registers and
// syscalls, plus the encoders its instruction formats need.

const syscall_trap = [u8(0x0f), 0x05] // syscall

fn x86_64_registers() []Register {
	return [
		Register{ name: 'eax', wide_name: 'rax', code: 0, width: 4, call_arg: -1 },
		Register{ name: 'ecx', wide_name: 'rcx', code: 1, width: 4, call_arg: 3 },
		Register{ name: 'edx', wide_name: 'rdx', code: 2, width: 4, call_arg: 2 },
		Register{ name: 'ebx', wide_name: 'rbx', code: 3, width: 4, call_arg: -1 },
		Register{ name: 'esp', wide_name: 'rsp', code: 4, width: 4, call_arg: -1 },
		Register{ name: 'ebp', wide_name: 'rbp', code: 5, width: 4, call_arg: -1 },
		Register{ name: 'esi', wide_name: 'rsi', code: 6, width: 4, call_arg: 1 },
		Register{ name: 'edi', wide_name: 'rdi', code: 7, width: 4, call_arg: 0 },
		Register{ name: 'r8d', wide_name: 'r8', code: 8, width: 4, call_arg: 5 },
		Register{ name: 'r9d', wide_name: 'r9', code: 9, width: 4, call_arg: 4 },
		Register{ name: 'r10d', wide_name: 'r10', code: 10, width: 4, call_arg: -1 },
		Register{ name: 'r11d', wide_name: 'r11', code: 11, width: 4, call_arg: -1 },
		Register{ name: 'r12d', wide_name: 'r12', code: 12, width: 4, call_arg: -1 },
		Register{ name: 'r13d', wide_name: 'r13', code: 13, width: 4, call_arg: -1 },
		Register{ name: 'r14d', wide_name: 'r14', code: 14, width: 4, call_arg: -1 },
		Register{ name: 'r15d', wide_name: 'r15', code: 15, width: 4, call_arg: -1 },
	]
}

fn x86_64_syscalls() []Syscall {
	return [
		Syscall{ name: 'read', number: 0, args: ['rdi', 'rsi', 'rdx'] },
		Syscall{ name: 'write', number: 1, args: ['rdi', 'rsi', 'rdx'] },
		Syscall{ name: 'exit', number: 60, args: ['rdi'] },
		Syscall{ name: 'exit_group', number: 231, args: ['rdi'] },
	]
}

fn x86_64_linux() Target {
	return Target{
		name:               'x86_64-linux'
		os:                 'linux'
		arch:               'x86_64'
		word_size:          8
		elf_machine:        62
		page_size:          0x1000
		load_base:          0x400000
		registers:          x86_64_registers()
		syscalls:           x86_64_syscalls()
		syscall_number_reg: 'eax'
		syscall_args_regs:  ['rdi', 'rsi', 'rdx', 'r10', 'r8', 'r9']
		exit_syscall:       'exit'
	}
}

// mov_imm32 encodes `mov <reg>, <imm>` for the 32-bit name of a register. The
// destination is in the low three bits of the opcode, and r8-r15 need a REX
// prefix to reach the extended register numbers.
pub fn (t Target) mov_imm32(reg Register, imm u32) ![]u8 {
	if reg.width != 4 {
		return error('${t.name}: mov r32, imm32 cannot name ${reg.name}, which is ${reg.width} bytes wide')
	}
	mut out := []u8{cap: 6}
	if reg.code >= 8 {
		out << u8(0x41) // REX.B
	}
	out << u8(0xb8 + (reg.code & 0x07))
	out << u8(imm & 0xff)
	out << u8((imm >> 8) & 0xff)
	out << u8((imm >> 16) & 0xff)
	out << u8((imm >> 24) & 0xff)
	return out
}

// trap encodes the instruction that enters the kernel.
pub fn (t Target) trap() ![]u8 {
	return syscall_trap.clone()
}

// exit_sequence is everything needed to stop the process with a status: the
// status into the first argument register, the syscall number into the number
// register, then the trap. It reads the tables rather than hardcoding which
// register is which, so a target that puts its syscall number elsewhere needs no
// change here.
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
	mut out := t.mov_imm32(status_reg, u32(code))!
	out << t.mov_imm32(number_reg, exit_call.number)!
	out << t.trap()!
	return out
}
