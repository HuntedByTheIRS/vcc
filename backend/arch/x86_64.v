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

// frame_epilogue closes a function body that is done. The stack pointer goes
// back to where the frame pointer says the frame began, so the whole frame is
// given up in one instruction however much of it the body used; then the saved
// frame pointer comes off the stack and the return address is taken.
pub fn frame_epilogue() []u8 {
	return [u8(0x48), 0x89, 0xec, 0x5d, 0xc3] // mov rsp, rbp; pop rbp; ret
}

// halt stops the machine where it runs. An entry point that has handed control
// to something that never returns has nothing to do afterwards, and halting is
// how it says so rather than running into whatever bytes follow.
pub fn halt() []u8 {
	return [u8(0xf4)]
}

// The instructions a body with locals, branches and arithmetic is made of. They
// have the shape the encoders above have: what the instruction needs comes in,
// the finished bytes go out, and nothing about the length depends on a value the
// emitter has not settled yet.

// Three registers have a job beyond being general storage: the frame pointer is
// where a local is found, the scratch register holds the right-hand value of an
// operation while the left-hand one waits in the result register, and the
// register above the result register is what a division leaves over.
pub const frame_pointer = 'rbp'
pub const scratch_reg = 'ecx'
pub const remainder_reg = 'edx'

// load_slot and store_slot move a value between a register and the frame. The
// displacement is written in the wide form always: the frame is still growing
// while the body is emitted, so the length of an access must not depend on how
// big it ends up. The width is the width of the value, four bytes for an int and
// eight for a pointer, because a move at the other width would read or write a
// neighbouring slot.
pub fn load_slot(base Register, disp i32, dst Register, width int) ![]u8 {
	return slot_move(base, disp, dst, width, false)
}

pub fn store_slot(base Register, disp i32, src Register, width int) ![]u8 {
	return slot_move(base, disp, src, width, true)
}

fn slot_move(base Register, disp i32, operand Register, width int, store bool) ![]u8 {
	if width != 4 && width != 8 {
		return error('${name}: a value of ${width} bytes is not one this machine moves through the frame')
	}
	mut out := []u8{cap: 7}
	mut rex := u8(0x40)
	if width == 8 {
		rex |= 0x08 // REX.W: the value is a wide one
	}
	if operand.code >= 8 {
		rex |= 0x04 // REX.R reaches the register the low three bits cannot name
	}
	if base.code >= 8 {
		rex |= 0x01 // REX.B: the base is one of those too
	}
	if rex != 0x40 {
		out << rex
	}
	opcode := if store { u8(0x89) } else { u8(0x8b) } // the move, in one direction or the other
	out << opcode
	out << u8(0x80 | ((operand.code & 0x07) << 3) | 0x05) // mod 10, rm 101: [base + disp32]
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// frame_reserve opens the space a function's locals live in. The size is an
// immediate because it is not known while the body is written: the emitter
// reserves the space with a zero and fills the number in once the body has been
// walked. The immediate is the wide form so the instruction keeps its length
// when that happens, and frame_reserve_immediate is where the four bytes sit.
pub fn frame_reserve(size u32) []u8 {
	return [u8(0x48), 0x81, 0xec, u8(size & 0xff), u8((size >> 8) & 0xff), u8((size >> 16) & 0xff),
		u8((size >> 24) & 0xff)]
}

pub const frame_reserve_immediate = 3

// The arithmetic this language's ints are computed with, all of it on the 32-bit
// names: the values are four bytes wide, and an operation at eight bytes would
// be an answer about a different value.

pub fn add_reg32(dst Register, src Register) ![]u8 {
	return rm_reg(0x01, dst, src)
}

pub fn sub_reg32(dst Register, src Register) ![]u8 {
	return rm_reg(0x29, dst, src)
}

// cmp_reg32 compares two values and sets the flags; it computes nothing, and the
// comparison the language asks for is those flags read by an instruction after it.
pub fn cmp_reg32(left Register, right Register) ![]u8 {
	return rm_reg(0x39, left, right)
}

// test_reg32 compares a value with zero without producing one: it is how a
// condition becomes a branch.
pub fn test_reg32(reg Register) ![]u8 {
	return rm_reg(0x85, reg, reg)
}

// rm_reg is the two-operand shape whose destination is the r/m operand and whose
// source is the reg field, which is how add, sub, cmp and test are written.
fn rm_reg(opcode u8, rm Register, reg Register) ![]u8 {
	if rm.width != 4 || reg.width != 4 {
		return error('${name}: opcode ${opcode} takes two four-byte registers, and ${rm.name} and ${reg.name} are not both that')
	}
	mut out := []u8{cap: 3}
	mut rex := u8(0x40)
	if reg.code >= 8 {
		rex |= 0x04
	}
	if rm.code >= 8 {
		rex |= 0x01
	}
	if rex != 0x40 {
		out << rex
	}
	out << opcode
	out << u8(0xc0 | ((reg.code & 0x07) << 3) | (rm.code & 0x07))
	return out
}

// imul_reg32 multiplies the destination by the source and leaves the product
// there. The multiply is the one two-operand form whose fields run the other way
// from add and sub: the destination is in the reg field.
pub fn imul_reg32(dst Register, src Register) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: imul takes two four-byte registers, and ${dst.name} and ${src.name} are not both that')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x40)
	if dst.code >= 8 {
		rex |= 0x04
	}
	if src.code >= 8 {
		rex |= 0x01
	}
	if rex != 0x40 {
		out << rex
	}
	out << u8(0x0f)
	out << u8(0xaf)
	out << u8(0xc0 | ((dst.code & 0x07) << 3) | (src.code & 0x07))
	return out
}

// cdq spreads the sign of the result register across the register above it. A
// signed division divides that pair, so the sign extension is the first half of
// one and is written here beside the division it belongs to.
pub fn cdq() []u8 {
	return [u8(0x99)]
}

// idiv_reg32 divides the pair formed by the result register and the one above it
// by a register. The quotient lands in the result register and the remainder in
// the register above it, which is where the language's two division operators
// read their answers from.
pub fn idiv_reg32(src Register) ![]u8 {
	return one_operand(src, 0x07)
}

// neg_reg32 and not_reg32 are the two operations on one value the language
// spells as unary operators: the sign change and the bitwise complement.
pub fn neg_reg32(reg Register) ![]u8 {
	return one_operand(reg, 0x03)
}

pub fn not_reg32(reg Register) ![]u8 {
	return one_operand(reg, 0x02)
}

// one_operand is the group of operations that take a single value: the operation
// is in the reg field and the value is the r/m one.
fn one_operand(reg Register, group u8) ![]u8 {
	if reg.width != 4 {
		return error('${name}: ${reg.name} is not a four-byte register for a one-operand operation')
	}
	mut out := []u8{cap: 2}
	if reg.code >= 8 {
		out << u8(0x41)
	}
	out << u8(0xf7)
	out << u8(0xc0 | ((group & 0x07) << 3) | (reg.code & 0x07))
	return out
}

// Condition is what a comparison is testing for. The names are the orders, and
// which machine code each one is belongs to this file.
pub enum Condition {
	equal
	not_equal
	less
	greater
	less_or_equal
	greater_or_equal
}

// code is the low nibble the machine numbers each order with.
pub fn (c Condition) code() u8 {
	return match c {
		.equal { 0x94 }
		.not_equal { 0x95 }
		.less { 0x9c }
		.greater { 0x9f }
		.less_or_equal { 0x9e }
		.greater_or_equal { 0x9d }
	}
}

// set_condition writes the outcome of the comparison just made into the low byte
// of a register, as zero or one. Only one byte is written, so only the first
// four registers can be the destination.
pub fn set_condition(condition Condition, reg Register) ![]u8 {
	byte_operand(reg)!
	return [u8(0x0f), u8(0x90 | condition.code()), u8(0xc0 | (reg.code & 0x07))]
}

// movzx_byte widens that byte into the whole register: the language's comparison
// is a value of int width, and the bits above the byte have to be zero for the
// value to be one.
pub fn movzx_byte(reg Register) ![]u8 {
	byte_operand(reg)!
	return [u8(0x0f), 0xb6, u8(0xc0 | ((reg.code & 0x07) << 3) | (reg.code & 0x07))]
}

// byte_operand refuses a destination that has no one-byte name. The table lists
// registers at their 32-bit spelling, and the low byte of the first four of them
// is what a conditional set can reach; a wider register number would need a REX
// prefix and a different byte name, which nothing here asks for.
fn byte_operand(reg Register) ! {
	if reg.code >= 4 {
		return error('${name}: a one-byte operand is the low byte of one of the first four registers, and ${reg.name} is not one of them')
	}
}

// The jumps a branch is made of. The unconditional one goes to the distance it
// carries; the two conditional ones go there when the flags the last comparison
// set say zero or not zero, which is how a condition becomes a branch.
pub fn jump_rel32(disp i32) []u8 {
	value := u32(disp)
	return [u8(0xe9), u8(value & 0xff), u8((value >> 8) & 0xff), u8((value >> 16) & 0xff),
		u8((value >> 24) & 0xff)]
}

pub fn jump_zero_rel32(disp i32) []u8 {
	return conditional_jump(0x84, disp)
}

pub fn jump_nonzero_rel32(disp i32) []u8 {
	return conditional_jump(0x85, disp)
}

// conditional_jump is the two-byte opcode form: 0F, then the opcode the condition
// owns, then the distance.
fn conditional_jump(opcode u8, disp i32) []u8 {
	value := u32(disp)
	return [u8(0x0f), opcode, u8(value & 0xff), u8((value >> 8) & 0xff), u8((value >> 16) & 0xff),
		u8((value >> 24) & 0xff)]
}
