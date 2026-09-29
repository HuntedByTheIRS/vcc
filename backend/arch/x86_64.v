module arch

// One machine, in the terms an emitter needs: the registers it has, how they are
// numbered in an instruction, and the encoders for the instructions this
// compiler emits.
//
// Nothing here mentions an operating system. The register a syscall number goes
// in is the one place the two descriptions touch, and it is here because the trap
// instruction is what reads it; the numbers themselves belong to the system, in
// `backend/os`. A second architecture is another file in this directory, and
// `backend/backend.v` composes it with a system rather than branching on it.

pub const name = 'x86_64'

// word_size is the width of the machine's general registers, in bytes.
pub const word_size = 8

// machine is this architecture's number in an object file header, the value ELF
// calls EM_X86_64. The number names the machine, so it lives with the machine
// and not with the format that stores it.
pub const machine = u16(62)

// syscall_number_reg is the register the kernel reads a syscall number from once
// the trap is taken.
pub const syscall_number_reg = 'eax'

// Register is one machine register as it is written, with the number the
// instruction encoding wants and the argument position it carries.
pub struct Register {
pub:
	name string
	// wide_name is the same register at the machine's word size.
	wide_name string
	// code is the register number used in instruction encodings.
	code u8
	// width is in bytes: 4 for the 32-bit name, 8 for the wide one.
	width int
	// call_arg is the SysV function argument position, or -1 when the register
	// does not carry one.
	call_arg int
}

// registers is the general register file. The stub emits with the 32-bit names,
// and both spellings are listed so a caller can ask for the width it means.
pub fn registers() []Register {
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

// mov_imm32 encodes `mov <reg>, <imm>` for the 32-bit name of a register. The
// destination is in the low three bits of the opcode, and r8 and up need a REX
// prefix to reach register numbers that do not fit in three bits.
pub fn mov_imm32(reg Register, imm u32) ![]u8 {
	if reg.width != 4 {
		return error('${name}: mov r32, imm32 cannot name ${reg.name}, which is ${reg.width} bytes wide')
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

// trap encodes the instruction that enters the kernel, which on this machine is
// `syscall`. The instruction is the machine's; what the kernel does with it is
// the system's.
pub fn trap() []u8 {
	return [u8(0x0f), 0x05]
}
