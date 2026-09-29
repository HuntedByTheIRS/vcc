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

// return_reg is where a function leaves the value it returns. It is named by its
// 32-bit spelling for the same reason every other register here is: the stub's
// values are 32 bits wide, and a caller that wants the wide name asks for that.
pub const return_reg = 'eax'

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
		Register{ name: 'r8d', wide_name: 'r8', code: 8, width: 4, call_arg: 4 },
		Register{ name: 'r9d', wide_name: 'r9', code: 9, width: 4, call_arg: 5 },
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

// The encoders below have the same shape: each takes the displacement it should
// carry and returns the finished instruction. Nothing about the length depends
// on the displacement, so an emitter that does not know the address yet reserves
// the instruction with a zero and rewrites it once the layout is settled. Every
// one of them ends in the four displacement bytes for that reason.

// mov_reg32 copies one 32-bit register into another. It is how a value moves
// from where a function left it to where the next call takes it from.
pub fn mov_reg32(dst Register, src Register) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: mov r32, r32 cannot move ${src.name} into ${dst.name}, which are not both four bytes wide')
	}
	mut out := []u8{cap: 3}
	mut rex := u8(0x40)
	if src.code >= 8 {
		rex |= 0x04 // REX.R reaches the source register
	}
	if dst.code >= 8 {
		rex |= 0x01 // REX.B reaches the destination register
	}
	if rex != 0x40 {
		out << rex
	}
	out << u8(0x89)
	out << u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))
	return out
}

// call_rel32 calls another instruction in the same code, named by the distance
// from the end of the call. It is how a call to a function defined in the file
// being compiled is written: no symbol, no loader, just an offset.
pub fn call_rel32(disp i32) []u8 {
	value := u32(disp)
	return [u8(0xe8), u8(value & 0xff), u8((value >> 8) & 0xff), u8((value >> 16) & 0xff),
		u8((value >> 24) & 0xff)]
}

// call_rip_slot calls the address held in a quadword found at a displacement
// from the instruction. That is the form a dynamically linked call takes: the
// loader writes the function's address into the slot once, and every call reads
// it, so the code never has to know where the function ended up.
pub fn call_rip_slot(disp i32) []u8 {
	value := u32(disp)
	return [u8(0xff), 0x15, u8(value & 0xff), u8((value >> 8) & 0xff), u8((value >> 16) & 0xff),
		u8((value >> 24) & 0xff)]
}

// lea_rip computes the address of something at a displacement from the
// instruction and writes it into the register. The register is named by its
// 32-bit spelling because that is how the table lists it; the instruction writes
// the whole 64-bit register, which is what an address needs.
pub fn lea_rip(reg Register, disp i32) []u8 {
	mut rex := u8(0x48) // REX.W: the address is a wide register
	if reg.code >= 8 {
		rex |= 0x04 // REX.R reaches registers the low three bits cannot name
	}
	value := u32(disp)
	return [rex, 0x8d, u8(((reg.code & 0x07) << 3) | 0x05), u8(value & 0xff), u8((value >> 8) & 0xff),
		u8((value >> 16) & 0xff), u8((value >> 24) & 0xff)]
}

// frame_prologue opens a function body. It saves the caller's frame pointer and
// adopts the stack pointer, which is what a function needs before it can use the
// stack and what keeps the saved frame findable on the way out.
pub fn frame_prologue() []u8 {
	return [u8(0x55), 0x48, 0x89, 0xe5] // push rbp; mov rbp, rsp
}

// frame_epilogue closes a function body that is done: it gives the frame pointer
// back to the caller and returns to the address the call left on the stack.
pub fn frame_epilogue() []u8 {
	return [u8(0x5d), 0xc3] // pop rbp; ret
}

// halt stops the machine where it runs. An entry point that has handed control
// to something that never returns has nothing to do afterwards, and halting is
// how it says so rather than running into whatever bytes follow.
pub fn halt() []u8 {
	return [u8(0xf4)]
}
