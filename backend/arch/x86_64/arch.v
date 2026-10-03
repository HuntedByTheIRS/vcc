module x86_64

// One machine, in the terms an emitter needs: the registers it has, how they are
// numbered in an instruction, and the encoders for the instructions this
// compiler emits.
//
// Nothing here mentions an operating system. The register a syscall number goes
// in is the one place the two descriptions touch, and it is here because the trap
// instruction is what reads it; the numbers themselves belong to the system, in
// `backend/os`.
//
// A second machine is a directory of its own beside this one, because a V module
// is a directory: two machines in one module would collide on every name they
// share, and this file has no way to say which one it means. `backend/backend.v`
// is where a machine and a system are composed into a target.

pub const name = 'x86_64'

// word_size is the width of the machine's general registers, in bytes.
pub const word_size = 8

// machine is this architecture's number in an object file header, the value ELF
// calls EM_X86_64. The number names the machine, so it lives with the machine
// and not with the format that stores it.
pub const machine = u16(62)

// The relocations this machine's psABI gives a reference between two objects:
// the numbers an object file carries for them. They are the psABI's rather than
// the container format's, because another machine numbers its own differently
// for the same reference, which is why they sit beside `machine` and not in
// `backend/os/elf`.
pub const relocation_call = u32(4) // R_X86_64_PLT32

// relocation_pc_relative is for a distance the code computes rather than jumps
// to: the address of a string, of a constant, or of an object defined at the
// top level.
pub const relocation_pc_relative = u32(2) // R_X86_64_PC32

// syscall_number_reg is the register the kernel reads a syscall number from once
// the trap is taken.
pub const syscall_number_reg = 'eax'

// return_reg is where a function leaves the value it returns. It is named by its
// 32-bit spelling for the same reason every other register here is: the stub's
// values are 32 bits wide, and a caller that wants the wide name asks for that.
pub const return_reg = 'eax'

// The floating-point register file, in the second table the emitter asks for
// argument positions in. It is a separate table because it is a separate file on
// this machine: a double is not passed in the register an int is, and the
// sequence an argument of each class takes is its own, so one table with two
// kinds of register in it would have to be sorted out by whoever read it.
//
// Every one of these is sixteen bytes wide, which is the size of the register
// rather than the size of a value: a double's eight bytes sit in the low half
// and the rest is not part of any value this compiler emits.
pub fn float_registers() []Register {
	return [
		Register{ name: 'xmm0', wide_name: 'xmm0', code: 0, width: 16, call_arg: -1, float_call_arg: 0 },
		Register{ name: 'xmm1', wide_name: 'xmm1', code: 1, width: 16, call_arg: -1, float_call_arg: 1 },
		Register{ name: 'xmm2', wide_name: 'xmm2', code: 2, width: 16, call_arg: -1, float_call_arg: 2 },
		Register{ name: 'xmm3', wide_name: 'xmm3', code: 3, width: 16, call_arg: -1, float_call_arg: 3 },
		Register{ name: 'xmm4', wide_name: 'xmm4', code: 4, width: 16, call_arg: -1, float_call_arg: 4 },
		Register{ name: 'xmm5', wide_name: 'xmm5', code: 5, width: 16, call_arg: -1, float_call_arg: 5 },
		Register{ name: 'xmm6', wide_name: 'xmm6', code: 6, width: 16, call_arg: -1, float_call_arg: 6 },
		Register{ name: 'xmm7', wide_name: 'xmm7', code: 7, width: 16, call_arg: -1, float_call_arg: 7 },
	]
}

// float_return_reg is where a function leaves a floating-point result, and
// float_scratch_reg is where the right-hand value of a floating-point operation
// waits while the left-hand one sits in the first. They are named by their
// sixteen-byte spelling because that is how the table lists this file; the
// instruction reads the eight bytes of a double out of one.
pub const float_return_reg = 'xmm0'
pub const float_scratch_reg = 'xmm1'

// The SSSE3-era two-byte prefix of every scalar double instruction: F2 says the
// operand is one double rather than a packed pair, and 0F is the escape. The
// single-precision form of every one of them writes F3 in that place instead,
// which is what makes a float and a double the same instruction at two widths
// rather than two instruction sets.
const prefix_double = u8(0xf2)
const prefix_float = u8(0xf3)

// The opcodes this file emits for scalar double arithmetic, and the one that
// compares. The comparison is 66 0F 2F because it belongs to the packed
// instruction family and takes the 66 prefix instead of the F2 one.
pub const double_add = u8(0x58)
pub const double_subtract = u8(0x5c)
pub const double_multiply = u8(0x59)
pub const double_divide = u8(0x5e)
const double_int_convert = u8(0x2a)
const double_int_truncate = u8(0x2c)

// double_modrm is the shared shape of every scalar double instruction whose
// second operand is a register: the prefix, the escape, the opcode, and a
// ModRM byte naming the destination in the reg field and the source in the r/m
// one, with mod 11 saying the source is a register rather than an address.
fn double_modrm(opcode u8, dst Register, src Register) ![]u8 {
	return scalar_modrm(prefix_double, opcode, dst, src)
}

// scalar_modrm is that shape with the prefix named, which is the one byte that
// tells a single-precision instruction from a double-precision one. Both
// operands are sixteen-byte registers either way: a float's four bytes sit in
// the low half of one, so the register an instruction names is the same size in
// both.
fn scalar_modrm(prefix u8, opcode u8, dst Register, src Register) ![]u8 {
	if dst.width != 16 || src.width != 16 {
		return error('${name}: a scalar floating-point operand is a sixteen-byte register, and ${dst.name} or ${src.name} is not one')
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
	out << prefix
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((dst.code & 0x07) << 3) | (src.code & 0x07))
	return out
}

// move_double copies one double register into another.
pub fn move_double(dst Register, src Register) ![]u8 {
	return double_modrm(0x10, dst, src)
}

// double_arithmetic applies one of the four operations to the destination and
// the source and leaves the answer in the destination.
pub fn double_arithmetic(opcode u8, dst Register, src Register) ![]u8 {
	if opcode !in [double_add, double_subtract, double_multiply, double_divide] {
		return error('${name}: ${opcode} is not one of the four operations a double is computed with')
	}
	return double_modrm(opcode, dst, src)
}

// compare_double orders two doubles and sets the flags a comparison reads. The
// instruction is Comisd: the four orders are read off ZF, CF and PF, and the
// caller writes one of them into a register because there is no instruction that
// compares a double and leaves a truth value behind.
pub fn compare_double(left Register, right Register) ![]u8 {
	mut out := []u8{cap: 4}
	if left.code >= 8 || right.code >= 8 {
		// Neither register this compiler compares with is above xmm7, so the
		// prefix a wider one needs is not written here rather than written
		// from a value nobody asked for.
		return error('${name}: a double comparison names ${left.name} against ${right.name}, and neither may be above xmm7')
	}
	out << u8(0x66)
	out << u8(0x0f)
	out << u8(0x2f)
	out << u8(0xc0 | ((left.code & 0x07) << 3) | (right.code & 0x07))
	return out
}

// compare_float is the same comparison for two floats. The instruction is
// Comiss, which is Comisd without the 66 prefix: it sets the same four flags in
// the same places, so the code that reads an order out of them serves both.
// Measured against gcc 16.2.1, which compares two floats with comiss.
pub fn compare_float(left Register, right Register) ![]u8 {
	if left.code >= 8 || right.code >= 8 {
		return error('${name}: a float comparison names ${left.name} against ${right.name}, and neither may be above xmm7')
	}
	return [u8(0x0f), u8(0x2f), u8(0xc0 | ((left.code & 0x07) << 3) | (right.code & 0x07))]
}

// int_to_double converts a four-byte integer to a double, and double_to_int
// truncates a double towards zero. The second is the C conversion from a
// floating type to an integer one, which is defined to truncate, and the
// instruction with `tt` in its name is the one that does that rather than the
// one that rounds.
//
// These two are the only instructions here whose operands are one register from
// each file, so they are not a ModRM pair of doubles: the destination is named in
// the reg field and the source in the r/m one, and which of the two is the double
// differs between them. `cvtsi2sd xmm, r/m32` converts an integer into a double
// and `cvttsd2si r32, xmm` converts the other way.
fn double_conversion(opcode u8, reg_field Register, rm Register) []u8 {
	return scalar_conversion(prefix_double, opcode, reg_field, rm)
}

// scalar_conversion is that shape with the prefix named: the integer-to-float
// and float-to-integer instructions come in a single-precision form and a
// double-precision one, and the prefix is the whole of the difference.
fn scalar_conversion(prefix u8, opcode u8, reg_field Register, rm Register) []u8 {
	mut out := []u8{cap: 5}
	mut rex := u8(0x40)
	if reg_field.code >= 8 {
		rex |= 0x04 // REX.R: the reg field names a wider register
	}
	if rm.code >= 8 {
		rex |= 0x01 // REX.B: the r/m field names one
	}
	if rex != 0x40 {
		out << rex
	}
	out << prefix
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((reg_field.code & 0x07) << 3) | (rm.code & 0x07))
	return out
}

// double_conversion_widened is the same instruction with REX.W, which makes the
// general-register operand eight bytes wide rather than four. The F2 prefix in
// front of the escape is a legacy prefix and REX has to be the last prefix before
// the opcode, so the order is F2 then REX then the escape; a REX written before
// the F2 would sit where the machine does not read it and the instruction would
// convert four bytes again.
fn double_conversion_widened(opcode u8, reg_field Register, rm Register) []u8 {
	mut out := []u8{cap: 5}
	mut rex := u8(0x48) // REX.W: the general register is an eight-byte one
	if reg_field.code >= 8 {
		rex |= 0x04 // REX.R: the reg field names a wider register
	}
	if rm.code >= 8 {
		rex |= 0x01 // REX.B: the r/m field names one
	}
	out << prefix_double
	out << rex
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((reg_field.code & 0x07) << 3) | (rm.code & 0x07))
	return out
}

pub fn int_to_double(dst Register, src Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: an integer is converted into a double register, and ${dst.name} is not one')
	}
	if src.width != 4 {
		return error('${name}: a double comes from a four-byte integer, and ${src.name} is not one')
	}
	return double_conversion(double_int_convert, dst, src)
}

// unsigned_int_to_double converts a four-byte unsigned integer to a double. The
// signed conversion sign-extends its source, so 3000000000u reaches it as
// -1294967296 and the double is not the value the program wrote. An unsigned
// source arrives with zeros above it instead: the four-byte move clears the upper
// half of the whole register (writing a 32-bit register zeroes the 32 bits above
// it), and the eight-byte form of the conversion then reads the value that is
// there. Measured on gcc 16.2.1 at -O0, `(double)u` for an unsigned int is a
// 32-bit load into eax followed by `cvtsi2sdq %rax, %xmm0`; the `js` gcc writes
// before it never branches, because the load already cleared the upper half.
pub fn unsigned_int_to_double(dst Register, src Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: an integer is converted into a double register, and ${dst.name} is not one')
	}
	if src.width != 4 {
		return error('${name}: a double comes from a four-byte integer, and ${src.name} is not one')
	}
	mut out := mov_reg32(src, src)!
	out << double_conversion_widened(double_int_convert, dst, src)
	return out
}

// signed_word_to_double converts an eight-byte signed integer to a double. It is
// the signed conversion of int_to_double at eight bytes: the same F2 0F 2A with
// REX.W in front of it, which is what makes the general register an eight-byte
// one rather than a four-byte one. Measured on gcc 16.2.1 at -O0, whose
// `(double)l` for a long is `cvtsi2sdq %rax, %xmm0`.
pub fn signed_word_to_double(dst Register, src Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: an integer is converted into a double register, and ${dst.name} is not one')
	}
	if src.width != 4 {
		return error('${name}: a double comes from an eight-byte integer, and ${src.name} is not a four-byte register name')
	}
	return double_conversion_widened(double_int_convert, dst, src)
}

// unsigned_word_to_double converts an eight-byte unsigned integer to a double.
// The signed conversion of int_to_double reads the top bit as a sign and an
// eight-byte source fills the whole register, so there is no upper half to clear
// and the fix the four-byte case uses does not carry: 18000000000000000000
// reaches the signed conversion as a negative value.
//
// The value is split at 2^63, which is the boundary the signed conversion reads
// as a sign. Below it the value converts as it stands. At or above it the low bit
// is folded into the word above it (`(value >> 1) | (value & 1)`), which brings
// the value below 2^63 so the signed conversion reads the magnitude, and the
// result is doubled. Doubling a double is exact, and the folded bit is what keeps
// the last place right: dropping it would round the halfway case up where the
// language rounds to even. Measured on gcc 16.2.1 at -O0, whose `(double)u` for an
// unsigned long is this test, this shift and or, and an `addsd %xmm0, %xmm0`.
//
// Subtracting 2^63 from the value, converting the difference and adding 2^63 to
// the double is the shape that reads better and is wrong: the difference is
// rounded to a double first, so adding 2^63 rounds a second time. Read bit for
// bit, `(double)0x80ad45e641aac401` is 0x43e015a8bcc83559 and the two-step form
// gives 0x43e015a8bcc83558, one place low.
pub fn unsigned_word_to_double(dst Register, src Register, scratch Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: an integer is converted into a double register, and ${dst.name} is not one')
	}
	if src.width != 4 || scratch.width != 4 {
		return error('${name}: converting an eight-byte unsigned integer names two four-byte registers, and ${src.name} and ${scratch.name} are not both that')
	}
	if src.code & 0x07 == scratch.code & 0x07 {
		return error('${name}: converting ${src.name} needs a second register for the shifted word, and ${scratch.name} is the same one')
	}
	mut high := mov_reg64(scratch, src)!
	high << shr_reg64(scratch, 1)!
	high << and_immediate(src, 1)!
	high << or_reg64(src, scratch)!
	high << double_conversion_widened(double_int_convert, dst, src)
	high << double_arithmetic(double_add, dst, dst)!
	low := double_conversion_widened(double_int_convert, dst, src)
	mut out := test_reg64(src)!
	// The two jumps are the distance to the next part of this one operation, so
	// each displacement is known here and no label has to be filled in later.
	out << jump_sign_rel32(i32(low.len + 5))
	out << low
	out << jump_rel32(i32(high.len))
	out << high
	return out
}

pub fn double_to_int(dst Register, src Register) ![]u8 {
	if dst.width != 4 {
		return error('${name}: a double is truncated into a four-byte integer, and ${dst.name} is not one')
	}
	if src.width != 16 {
		return error('${name}: a double is truncated out of a double register, and ${src.name} is not one')
	}
	return scalar_conversion(prefix_double, double_int_truncate, dst, src)
}

// The single-precision forms of the same instructions. A float and a double are
// one instruction set at two widths, so each of these is its double counterpart
// with the F3 prefix, and the operand registers are the same sixteen-byte ones:
// a float's four bytes sit in the low half of one.
//
// cvtsi2ss converts a four-byte integer to a float, cvttss2si truncates one
// towards zero into a four-byte integer, and the last two widen and narrow
// between the two floating widths, which both keep the value as closely as the
// narrower type can hold it.
const double_float_convert = u8(0x5a)

pub fn move_float(dst Register, src Register) ![]u8 {
	return scalar_modrm(prefix_float, 0x10, dst, src)
}

pub fn float_arithmetic(opcode u8, dst Register, src Register) ![]u8 {
	if opcode !in [double_add, double_subtract, double_multiply, double_divide] {
		return error('${name}: ${opcode} is not one of the four operations a float is computed with')
	}
	return scalar_modrm(prefix_float, opcode, dst, src)
}

pub fn int_to_float(dst Register, src Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: an integer is converted into a float register, and ${dst.name} is not one')
	}
	if src.width != 4 {
		return error('${name}: a float comes from a four-byte integer, and ${src.name} is not one')
	}
	return scalar_conversion(prefix_float, double_int_convert, dst, src)
}

pub fn float_to_int(dst Register, src Register) ![]u8 {
	if dst.width != 4 {
		return error('${name}: a float is truncated into a four-byte integer, and ${dst.name} is not one')
	}
	if src.width != 16 {
		return error('${name}: a float is truncated out of a floating-point register, and ${src.name} is not one')
	}
	return scalar_conversion(prefix_float, double_int_truncate, dst, src)
}

// float_to_double widens a float into a double, which is exact: every value a
// float holds is a value a double holds. double_to_float narrows one, rounding
// to nearest, which is the conversion the language defines between the two.
pub fn float_to_double(dst Register, src Register) ![]u8 {
	return scalar_modrm(prefix_float, double_float_convert, dst, src)
}

pub fn double_to_float(dst Register, src Register) ![]u8 {
	return scalar_modrm(prefix_double, double_float_convert, dst, src)
}

// double_to_unsigned_int truncates a double into a four-byte unsigned integer.
// The four-byte signed truncation saturates at 2^31, so 3000000000.0 arrives as
// 2147483648. Every value a four-byte unsigned type can hold is below 2^63, so
// the eight-byte form of the same truncation answers all of them exactly. Measured
// on gcc 16.2.1 at -O0: `(unsigned int)d` is one `cvttsd2siq %xmm0, %rax`, and
// `(int)d` is `cvttsd2sil %xmm0, %eax`.
pub fn double_to_unsigned_int(dst Register, src Register) ![]u8 {
	if dst.width != 4 {
		return error('${name}: a double is truncated into a four-byte integer, and ${dst.name} is not one')
	}
	if src.width != 16 {
		return error('${name}: a double is truncated out of a double register, and ${src.name} is not one')
	}
	return double_conversion_widened(double_int_truncate, dst, src)
}

// double_to_signed_word truncates a double into an eight-byte signed integer,
// which is the truncation of double_to_int at eight bytes: the same F2 0F 2C with
// REX.W in front of it. The four-byte form on an eight-byte value would keep the
// low half and round the wrong one of the two. Measured on gcc 16.2.1 at -O0,
// whose `(long)d` is `cvttsd2siq %xmm0, %rax` and whose `(int)d` is the four-byte
// form.
pub fn double_to_signed_word(dst Register, src Register) ![]u8 {
	if dst.width != 4 {
		return error('${name}: a double is truncated into an eight-byte integer, and ${dst.name} is not the register it lands in')
	}
	if src.width != 16 {
		return error('${name}: a double is truncated out of a double register, and ${src.name} is not one')
	}
	return double_conversion_widened(double_int_truncate, dst, src)
}

// double_to_unsigned_word truncates a double into an eight-byte unsigned integer.
// The signed truncation saturates at 2^63 and answers a value of exactly 2^63 with
// the integer-indefinite pattern, so a double at or above the boundary is split the
// way the conversion the other direction is: 2^63 is taken off the double, the
// difference is below 2^63 and truncates as a signed value, and the bit that was
// taken off is set again in the integer. A double below the boundary truncates as
// it stands.
//
// The comparison is Comisd against 2^63, which is a double no instruction carries
// as an immediate for this file, so its bits are moved in from a general register:
// 0x43E0000000000000. Measured on gcc 16.2.1 at -O0, whose `(unsigned long)d` is
// this bound, this subtraction, this truncation, and the sign bit put back, which
// gcc flips with an exclusive-or and this sets with a bit test and set.
//
// A double at or above 2^64 is out of range, and the language leaves the answer
// undefined rather than giving it one. The subtraction then leaves a value the
// truncation cannot hold, which answers with the integer-indefinite pattern
// 0x8000000000000000, and the bit set again is the one already set: this compiler
// answers 0x8000000000000000 there. gcc's exclusive-or clears that bit instead, so
// gcc answers 0. Both answers are undefined and neither is a rule this file invents.
pub fn double_to_unsigned_word(dst Register, src Register, scratch Register, float_scratch Register) ![]u8 {
	if dst.width != 4 || scratch.width != 4 {
		return error('${name}: a double is truncated into an eight-byte unsigned integer named by two four-byte registers, and ${dst.name} and ${scratch.name} are not both that')
	}
	if src.width != 16 || float_scratch.width != 16 {
		return error('${name}: the range split of a double names two double registers, and ${src.name} and ${float_scratch.name} are not both that')
	}
	if dst.code & 0x07 == scratch.code & 0x07 {
		return error('${name}: converting into ${dst.name} needs a second register for 2^63, and ${scratch.name} is the same one')
	}
	if src.code & 0x07 == float_scratch.code & 0x07 {
		return error('${name}: the range split of a double needs a second double register for 2^63, and ${float_scratch.name} is the same one as ${src.name}')
	}
	// 2^63 as a double is the exponent 0x43E and no mantissa, which is the value
	// the comparison and the subtraction are against.
	bits_2_63 := u64(0x43e0000000000000)
	mut high := double_arithmetic(double_subtract, src, float_scratch)!
	high << double_conversion_widened(double_int_truncate, dst, src)
	high << set_top_bit(dst)!
	low := double_conversion_widened(double_int_truncate, dst, src)
	mut out := mov_imm64(scratch, bits_2_63)!
	out << move_word_to_double(float_scratch, scratch)!
	out << compare_double(src, float_scratch)!
	// The two jumps are the distance to the next part of this one operation, so
	// each displacement is known here and no label has to be filled in later.
	out << jump_below_rel32(i32(high.len + 5))
	out << high
	out << jump_rel32(i32(low.len))
	out << low
	return out
}

// Movq, in both directions, between a general register and the low half of a
// double one. It is how the sign of a double is reached, since there is no
// instruction that negates one.
const movq_to_float = u8(0x6e)
const movq_from_float = u8(0x7e)

fn movq_modrm(opcode u8, first Register, second Register) []u8 {
	mut out := []u8{cap: 5}
	out << u8(0x66)
	out << u8(0x48) // REX.W: the general register is an eight-byte one
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((first.code & 0x07) << 3) | (second.code & 0x07))
	return out
}

// negate_double flips the sign bit of a double. The bit is reached through a
// general register, because the machine negates an integer and not a floating
// value: the two moves carry the eight bytes out and back, and the bit test and
// complement instruction flips bit 63 between them. It is exact for every input
// including zero and a NaN, where `0 - x` would round a signalling NaN into a
// quiet one and turn -0.0 into 0.0.
pub fn negate_double(reg Register, gp Register) ![]u8 {
	if reg.width != 16 || gp.width != 4 {
		return error('${name}: negating a double names a sixteen-byte register and a four-byte one, and ${reg.name} or ${gp.name} is neither')
	}
	mut out := movq_modrm(movq_from_float, reg, gp)
	// btc rax, 63: the bit test and complement, with the bit in the immediate.
	// REX.W is what makes it operate on the eight bytes of the register rather
	// than on the low four: without it the instruction reads the bit number
	// modulo 32 and clears the upper half, which flips bit 31 and leaves a value
	// the program never wrote. Measured, `double a = -3.5; a < 0.0` answered 0
	// with that bit flipped instead of bit 63.
	out << u8(0x48)
	out << u8(0x0f)
	out << u8(0xba)
	out << u8(0xf8 | (gp.code & 0x07))
	out << u8(63)
	out << movq_modrm(movq_to_float, reg, gp)
	return out
}

// negate_single flips the sign bit of a float, which is bit 31 of the low four
// bytes and not bit 63. The moves and the bit test are the same instructions,
// with the bit test left at four bytes: that is exactly the difference, because
// the REX.W that negate_double writes reaches bit 63 and leaves a float's own
// sign bit alone. Measured against gcc 16.2.1, whose `-f` for a float is this
// sequence with btc eax, 31.
pub fn negate_single(reg Register, gp Register) ![]u8 {
	if reg.width != 16 || gp.width != 4 {
		return error('${name}: negating a float names a sixteen-byte register and a four-byte one, and ${reg.name} or ${gp.name} is neither')
	}
	if reg.code >= 8 || gp.code >= 8 {
		// Negating a double refuses the same registers for the same reason: the
		// REX prefix a wider one needs is not written here.
		return error('${name}: negating a float names ${reg.name} and ${gp.name}, and only the first eight have the encoding written here')
	}
	mut out := movq_modrm(movq_from_float, reg, gp)
	// btc eax, 31: the bit test and complement with the bit in the immediate,
	// without REX.W so that it reads the bit number modulo 32 and writes the low
	// four bytes.
	out << u8(0x0f)
	out << u8(0xba)
	out << u8(0xf8 | (gp.code & 0x07))
	out << u8(31)
	out << movq_modrm(movq_to_float, reg, gp)
	return out
}

// move_word_to_double copies a general register into a double register, the same
// movq of the sign flip written the other way (0x6E rather than 0x7E). It is how
// the range split of a double into an unsigned word gets 2^63, which is a value
// no instruction carries as an immediate for the floating-point file.
pub fn move_word_to_double(dst Register, src Register) ![]u8 {
	if dst.width != 16 {
		return error('${name}: a word is moved into a double register, and ${dst.name} is not one')
	}
	if src.width != 4 {
		return error('${name}: a word is moved into a double register from a general one, and ${src.name} is not a four-byte register name')
	}
	return movq_modrm(movq_to_float, dst, src)
}

// set_top_bit sets bit 63 of a word register, which the range split of a double
// into an unsigned word uses to put 2^63 back into a truncated value: the value
// below 2^63 has that bit clear, so setting it adds 2^63. It is bit test and set
// with the bit in the immediate (0F BA /5), REX.W so the bit is 63 and not 31.
pub fn set_top_bit(reg Register) ![]u8 {
	if reg.width != 4 {
		return error('${name}: ${reg.name} is not a register to name a word operation with')
	}
	mut out := []u8{cap: 5}
	mut rex := u8(0x48) // REX.W: the bit is above the low four bytes
	if reg.code >= 8 {
		rex |= 0x01 // REX.B reaches the register
	}
	out << rex
	out << u8(0x0f)
	out << u8(0xba) // the group whose reg field of five is the bit set
	out << u8(0xe8 | (reg.code & 0x07))
	out << u8(63)
	return out
}

// zero_double clears a register, which is the one double constant that needs no
// memory: the exclusive-or of a value with itself is zero, and the instruction
// leaves the flags alone so a comparison before it still stands.
//
// The encoding is the packed-double exclusive or of a register with itself, 66 0F
// 57 /r. That 66 is not the scalar prefix: the scalar form the rest of this file
// uses writes F2, and F2 0F 57 is not an instruction at all. Measured, emitting
// it produced bytes the processor refuses and a program that died on an illegal
// instruction the first time `!d` was evaluated.
pub fn zero_double(reg Register) ![]u8 {
	if reg.width != 16 {
		return error('${name}: a double register is sixteen bytes, and ${reg.name} is not one')
	}
	if reg.code >= 8 {
		return error('${name}: clearing a double register names ${reg.name}, and only the first eight have the encoding written here')
	}
	return [u8(0x66), u8(0x0f), u8(0x57), u8(0xc0 | ((reg.code & 0x07) << 3) | (reg.code & 0x07))]
}

// load_double_slot, store_double_slot and load_double_rip move one double
// between the frame and a register, and between the image's read-only data and
// a register. The displacement is written wide for the reason every other frame
// access writes it wide: the frame is still growing while the body is emitted,
// so the length of an access must not depend on how big it ends up.
//
// load_float_slot, store_float_slot and load_float_rip are the same three moves
// for a float. They are the same instruction with the single-precision prefix,
// and they move four bytes rather than eight.
pub fn load_double_slot(base Register, disp i32, dst Register) ![]u8 {
	return scalar_slot_move(prefix_double, base, disp, dst, false)
}

pub fn store_double_slot(base Register, disp i32, src Register) ![]u8 {
	return scalar_slot_move(prefix_double, base, disp, src, true)
}

pub fn load_float_slot(base Register, disp i32, dst Register) ![]u8 {
	return scalar_slot_move(prefix_float, base, disp, dst, false)
}

pub fn store_float_slot(base Register, disp i32, src Register) ![]u8 {
	return scalar_slot_move(prefix_float, base, disp, src, true)
}

fn scalar_slot_move(prefix u8, base Register, disp i32, operand Register, store bool) ![]u8 {
	if operand.width != 16 {
		return error('${name}: a floating value is moved through a sixteen-byte register, and ${operand.name} is not one')
	}
	mut out := []u8{cap: 9}
	if operand.code >= 8 || base.code >= 8 {
		return error('${name}: a frame access names ${operand.name} and ${base.name}, and neither may be above the seventh register')
	}
	out << prefix
	out << u8(0x0f)
	out << u8(if store { 0x11 } else { 0x10 })
	out << u8(0x80 | ((operand.code & 0x07) << 3) | 0x05) // mod 10, rm 101: [base + disp32]
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// load_double_rip reads a double out of the image's read-only data, at a
// displacement from the instruction. It is how a floating constant reaches a
// register: the eight bytes are in the image and the instruction says where.
// load_float_rip reads the four bytes of a single-precision constant the same
// way.
pub fn load_double_rip(dst Register, disp i32) ![]u8 {
	return scalar_rip_move(prefix_double, dst, disp)
}

pub fn load_float_rip(dst Register, disp i32) ![]u8 {
	return scalar_rip_move(prefix_float, dst, disp)
}

fn scalar_rip_move(prefix u8, dst Register, disp i32) ![]u8 {
	if dst.width != 16 || dst.code >= 8 {
		return error('${name}: a floating constant is loaded into one of the first eight floating-point registers, and ${dst.name} is not one')
	}
	mut out := []u8{cap: 8}
	out << prefix
	out << u8(0x0f)
	out << u8(0x10)
	out << u8(((dst.code & 0x07) << 3) | 0x05) // mod 00, rm 101: [rip + disp32]
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// load_double_indirect and store_double_indirect move a double between a
// register and the address in another register, which is what an object the
// program addresses itself is read and written through. The float pair beside
// them is the same two instructions at four bytes.
pub fn load_double_indirect(address Register, dst Register) ![]u8 {
	return scalar_indirect_move(prefix_double, address, dst, false)
}

pub fn store_double_indirect(address Register, src Register) ![]u8 {
	return scalar_indirect_move(prefix_double, address, src, true)
}

pub fn load_float_indirect(address Register, dst Register) ![]u8 {
	return scalar_indirect_move(prefix_float, address, dst, false)
}

pub fn store_float_indirect(address Register, src Register) ![]u8 {
	return scalar_indirect_move(prefix_float, address, src, true)
}

// The x87 moves are how a long double is loaded from and stored to memory. The
// machine has no register file for extended precision: the value lives in
// memory and the conversions load it onto the x87 stack, which is where the
// machine keeps eighty bits, and store it back. Each is two bytes with a mod-00
// memory operand named by the address register, the way the scalar indirect
// moves name one; unlike those, the second byte is the whole instruction, since
// the x87 opcode extension carries the operation and there is no register field
// holding a value. The address is named with mod 00, the way the scalar indirect
// moves name one: mod 11 would make the byte a register operand of the x87
// stack, which is a different instruction and, for most of these fields, one
// the machine does not have.
//
// The pairs are the conversions the long double type needs and nothing more:
// `fldt`/`fstpt` move the extended format itself, `fldl`/`fstpl` move a double
// through the extended stack so the conversion is done by the machine, and
// `fildl`/`fildll`/`fistpl`/`fistpll` do the same for a signed integer four and
// eight bytes wide.
fn x87_indirect_move(prefix u8, field u8, address Register) ![]u8 {
	low := address.code & 0x07
	if low == 4 || low == 5 {
		return error('${name}: an address in ${address.name} cannot be named without a displacement')
	}
	return [prefix, u8((field << 3) | low)]
}

// load_extended and store_extended are the extended format itself: `fldt` reads
// the ten bytes of a long double out of memory and `fstpt` writes them back.
pub fn load_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdb, 5, address)
}

pub fn store_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdb, 7, address)
}

// load_double_extended and store_double_extended do a double through the same
// stack, which is what makes a double convertible to and from the extended
// format without a routine of its own.
pub fn load_double_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdd, 0, address)
}

pub fn store_double_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdd, 3, address)
}

// The integer conversions: `fildl` and `fildll` read a four- and an eight-byte
// integer onto the stack, and `fistpl` and `fistpll` write one back.
pub fn load_int_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdb, 0, address)
}

pub fn load_word_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdf, 5, address)
}

pub fn store_int_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdb, 3, address)
}

pub fn store_word_extended(address Register) ![]u8 {
	return x87_indirect_move(0xdf, 7, address)
}

fn scalar_indirect_move(prefix u8, address Register, operand Register, store bool) ![]u8 {
	if operand.width != 16 {
		return error('${name}: a floating value is moved through a sixteen-byte register, and ${operand.name} is not one')
	}
	low := address.code & 0x07
	if low == 4 || low == 5 {
		return error('${name}: an address in ${address.name} cannot be named without a displacement')
	}
	mut out := []u8{cap: 4}
	out << prefix
	out << u8(0x0f)
	out << u8(if store { 0x11 } else { 0x10 })
	out << u8(((operand.code & 0x07) << 3) | low) // mod 00: [address]
	return out
}

// The setcc codes a double comparison is read with. They are the unsigned ones
// rather than the signed ones the integer comparison above uses: a double
// comparison puts `below` in the carry flag and `unordered` in the parity flag,
// and never touches the sign or overflow flags that setl and setg read.
pub const float_equal = u8(0x94) // sete, which is set for an unordered pair too
pub const float_not_equal = u8(0x95) // setne
pub const float_below = u8(0x92) // setb, the carry flag
pub const float_above = u8(0x97) // seta
pub const float_below_or_equal = u8(0x96) // setbe
pub const float_above_or_equal = u8(0x93) // setae
pub const float_parity = u8(0x9a) // setp, which is set when the pair was unordered
pub const float_not_parity = u8(0x9b) // setnp

// float_set writes one flag into the low byte of a register. It is set_condition
// above with an opcode chosen by the caller, because the two comparisons on this
// machine do not leave the same flags behind.
pub fn float_set(opcode u8, reg Register) ![]u8 {
	byte_operand(reg)!
	return [u8(0x0f), opcode, u8(0xc0 | (reg.code & 0x07))]
}

// set_float_condition writes the outcome of a double comparison into a register
// as zero or one. The four orders are not four flags: less is the carry flag
// with the unordered case taken back out, equal is the zero flag with it taken
// out too, and the two `not equal` and `not less` forms are the ones that want
// it left in. The pair of instructions is why this reads as a sequence rather
// than as one opcode: the machine compares and leaves flags, and something has
// to turn those flags into the value the language's operator has.
pub fn set_float_condition(op string, reg Register, scratch Register) ![]u8 {
	if reg.code & 0x07 == scratch.code & 0x07 {
		return error('${name}: writing a comparison into ${reg.name} needs a second byte register for the unordered case, and ${scratch.name} is the same one')
	}
	byte_operand(reg)!
	byte_operand(scratch)!
	mut out := []u8{cap: 12}
	match op {
		'==' {
			// Ordered and equal: the zero flag without the unordered case.
			out << float_set(float_equal, reg)!
			out << float_set(float_not_parity, scratch)!
			out << and_bytes(reg, scratch)
		}
		'!=' {
			// Not equal, or unordered: an unordered pair is not equal.
			out << float_set(float_not_equal, reg)!
			out << float_set(float_parity, scratch)!
			out << or_bytes(reg, scratch)
		}
		'<' {
			out << float_set(float_below, reg)!
			out << float_set(float_not_parity, scratch)!
			out << and_bytes(reg, scratch)
		}
		'<=' {
			out << float_set(float_below_or_equal, reg)!
			out << float_set(float_not_parity, scratch)!
			out << and_bytes(reg, scratch)
		}
		'>' {
			// `above` is false for an unordered pair already, since both the
			// zero flag and the carry flag are set then, so no second
			// instruction is needed.
			out << float_set(float_above, reg)!
		}
		'>=' {
			out << float_set(float_above_or_equal, reg)!
		}
		else {
			return error('${name}: ${op} is not an order this machine has a condition for')
		}
	}
	out << movzx_byte(reg)!
	return out
}

// and_bytes and or_bytes combine the two one-byte answers the unordered case
// needs into one. `and al, cl` is 20 /r and `or al, cl` is 08 /r, both with mod
// 11 and the source in the reg field.
fn and_bytes(dst Register, src Register) []u8 {
	return [u8(0x20), u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))]
}

fn or_bytes(dst Register, src Register) []u8 {
	return [u8(0x08), u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))]
}

// xor_byte flips the low bit of a byte, which is how the answer to "is this
// double zero" becomes the answer to "is this double not zero" without a second
// comparison.
pub fn xor_byte(reg Register, value u8) ![]u8 {
	byte_operand(reg)!
	if value > 1 {
		return error('${name}: only the low bit of a byte has a one-byte exclusive-or, and ${value} does not fit in it')
	}
	return [u8(0x80), u8(0xf0 | (reg.code & 0x07)), value]
}

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
	// float_call_arg is the same position in the separate sequence the
	// floating-point file takes its arguments from, or -1 in a table that has
	// no such sequence. An int and a double are numbered in their own
	// sequence, so both can hold position zero for the same call.
	float_call_arg int = -1
}

// shift_count_code is the register number the machine reads a shift count from. The
// encodings of a shift by a computed count name no register, because there is only one
// place they can name, so the count has to be there and this is what says so.
pub const shift_count_code = u8(1)

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

// mov_imm64 encodes `mov <reg>, <imm>` at the width of a word, where the
// immediate is eight bytes in the instruction. It is what a constant too wide for
// the four-byte immediate is written with, and measured on gcc 16.2.1 at -O0,
// `long f(void) { return 9223372036854775807; }` is a movabs of that ten-byte
// form. An initializer at the top level is the same eight bytes in the image
// rather than an instruction, so this is the path an expression takes.
pub fn mov_imm64(reg Register, imm u64) ![]u8 {
	if reg.width != 4 {
		return error('${name}: mov r64, imm64 cannot name ${reg.name}, which is ${reg.width} bytes wide')
	}
	mut out := []u8{cap: 10}
	mut rex := u8(0x48) // REX.W: the destination is the whole register
	if reg.code >= 8 {
		rex |= 0x01 // REX.B reaches register numbers that do not fit in three bits
	}
	out << rex
	out << u8(0xb8 + (reg.code & 0x07))
	for i in 0 .. 8 {
		out << u8((imm >> (8 * i)) & 0xff)
	}
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

// load_rip_slot reads the eight bytes held in a quadword found at a displacement
// from the instruction, which is the load form of call_rip_slot: a dynamically
// linked function's address is read out of its slot rather than called through it,
// so a program can put that address in a pointer. The encoding is the move that
// reads a quadword with the r/m field naming the next instruction, which is how
// the machine spells a displacement from the program counter; the register that
// receives the value needs a REX prefix of its own when it is one of r8 and up.
pub fn load_rip_slot(reg Register, disp i32) []u8 {
	mut rex := u8(0x48) // REX.W: the value is a wide register
	if reg.code >= 8 {
		rex |= 0x04 // REX.R reaches registers the low three bits cannot name
	}
	value := u32(disp)
	return [rex, 0x8b, u8(((reg.code & 0x07) << 3) | 0x05), u8(value & 0xff), u8((value >> 8) & 0xff),
		u8((value >> 16) & 0xff), u8((value >> 24) & 0xff)]
}

// call_register calls the address a register holds, which is the form a call
// written to an expression takes: the expression's value is read into a register
// and the call goes there. The opcode is the indirect group with the mod field set
// to the register itself, so no memory is read and there is no displacement to
// write; r8 and up need a REX prefix for the same reason mov_imm32 does. A register
// whose low three bits are 4 or 5 cannot be named without a SIB byte or a
// displacement, and this form writes neither, so it is refused by name.
pub fn call_register(reg Register) ![]u8 {
	low := reg.code & 0x07
	if low == 4 || low == 5 {
		return error('${name}: a call through ${reg.name} cannot be named without a SIB byte or a displacement, and this form writes neither')
	}
	mut out := []u8{cap: 3}
	if reg.code >= 8 {
		out << u8(0x41) // REX.B: the r/m field names a wider register
	}
	out << u8(0xff)
	out << u8(0xd0 | low) // mod 11, reg field 2: call r/m64
	return out
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
// big it ends up. The width is the width of the value: four bytes for an int,
// eight for a pointer, one for a char and two for a short, and a move at any
// other width would read or write a neighbouring slot. One byte is the machine's
// byte move, two bytes is that move with the operand-size prefix, and one or two
// bytes are read by the load that widens what it read to the width of the
// register it lands in. That load is where C's promotion of a char or a short to
// an int happens, and it is why such a value read out of the frame can be added
// to an int as it stands.
//
// A load that widens reads its operand as a signed value: the bits above it
// arrive as its sign, which is what a read of a char or a short is. A load of an
// unsigned character type or an unsigned short is the same read with the other
// extension, and that is load_slot_unsigned.
pub fn load_slot(base Register, disp i32, dst Register, width int) ![]u8 {
	return slot_move(base, disp, dst, width, false, true)
}

// load_slot_unsigned is a load of a one- or two-byte value with its bits above
// the value filled with zero rather than its sign, which is what reading an
// `unsigned char` or an `unsigned short` asks for. A value four or eight bytes
// wide fills the whole register either way, so those two read the same.
pub fn load_slot_unsigned(base Register, disp i32, dst Register, width int) ![]u8 {
	return slot_move(base, disp, dst, width, false, false)
}

pub fn store_slot(base Register, disp i32, src Register, width int) ![]u8 {
	return slot_move(base, disp, src, width, true, true)
}

fn slot_move(base Register, disp i32, operand Register, width int, store bool, signed bool) ![]u8 {
	if width != 1 && width != 2 && width != 4 && width != 8 {
		return error('${name}: a value of ${width} bytes is not one this machine moves through the frame')
	}
	mut out := []u8{cap: 10}
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
	// A two-byte store carries the operand-size prefix, which comes before the
	// REX byte. A two-byte load that widens does not: the instruction names a
	// four-byte destination and a two-byte source on its own.
	if store && width == 2 {
		out << u8(0x66)
	}
	// A byte operand is named by the low three bits of the register code, and
	// without a REX byte those three bits name only the four byte registers of
	// the first four: the prefix is what makes 4 to 7 name spl, bpl, sil and dil
	// instead. It is always written when the value is a byte, because a prefix
	// that only says where the registers are is legal, and a missing one would
	// silently name a different register.
	if width == 1 || rex != 0x40 {
		out << rex
	}
	if store {
		// A byte store, a two-byte store, or a four- or eight-byte one.
		out << u8(if width == 1 { 0x88 } else { 0x89 })
	} else if width == 1 {
		// Two bytes of opcode: the byte load that widens its operand, so that
		// what lands in the register is the value the language means.
		out << u8(0x0f)
		out << u8(if signed { 0xbe } else { 0xb6 })
	} else if width == 2 {
		// movsx or movzx r32, r/m16: a two-byte value widened into the register,
		// which is the read a short of either signedness arrives as.
		out << u8(0x0f)
		out << u8(if signed { 0xbf } else { 0xb7 })
	} else {
		out << u8(0x8b) // the move, in one direction or the other
	}
	out << u8(0x80 | ((operand.code & 0x07) << 3) | 0x05) // mod 10, rm 101: [base + disp32]
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// address_of_slot computes the address of a value in the frame, which is what an
// array's name is worth in an expression: the value of an array is the address
// of its first element, and that is an instruction of its own. The displacement
// is written wide for the same reason a slot move writes it wide — the frame is
// still growing while the body is emitted.
pub fn address_of_slot(base Register, disp i32, dst Register) []u8 {
	mut out := []u8{cap: 7}
	rex := u8(0x48) | (if dst.code >= 8 { u8(0x04) } else { u8(0) }) | (if base.code >= 8 {
		u8(0x01)
	} else {
		u8(0)
	})
	out << rex
	out << u8(0x8d) // lea
	out << u8(0x80 | ((dst.code & 0x07) << 3) | 0x05) // mod 10, rm 101: [base + disp32]
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// address_of_element computes the address of one element of an array: the frame,
// an index scaled by the width of an element, and the array's own displacement,
// in one instruction. The scale is the width, so a char array scales by one and
// an int array by four. The index is read as an unsigned value, which is what a
// subscript outside the array would be anyway: a program that reads one is
// already wrong, and this is the address it asked for.
pub fn address_of_element(base Register, index Register, scale int, disp i32, dst Register) ![]u8 {
	if scale != 1 && scale != 2 && scale != 4 && scale != 8 {
		return error('${name}: an index cannot be scaled by ${scale}')
	}
	if index.code & 0x07 == 4 {
		// The SIB byte names rsp's slot as "no index at all", so an index in rsp
		// is not something this encoding can write down.
		return error('${name}: an index in ${index.name} cannot be named by a scaled address')
	}
	mut out := []u8{cap: 8}
	rex := u8(0x48) | (if dst.code >= 8 { u8(0x04) } else { u8(0) }) | (if index.code >= 8 {
		u8(0x02)
	} else {
		u8(0)
	}) | (if base.code >= 8 {
		u8(0x01)
	} else {
		u8(0)
	})
	out << rex
	out << u8(0x8d) // lea
	out << u8(0x80 | ((dst.code & 0x07) << 3) | 0x04) // mod 10, rm 100: a SIB byte follows
	shift := match scale {
		1 { u8(0) }
		2 { u8(1) }
		4 { u8(2) }
		else { u8(3) }
	}
	out << u8((shift << 6) | ((index.code & 0x07) << 3) | (base.code & 0x07))
	value := u32(disp)
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// load_indirect and store_indirect move a value between a register and the
// address in another register, which is what an element of an array is once its
// address has been computed. A byte or a two-byte value is loaded with the load
// that widens it, the same one a frame slot uses, so an element of a char or short
// array arrives as the int the language promotes it to.
pub fn load_indirect(address Register, dst Register, width int) ![]u8 {
	return indirect_move(address, dst, width, false, true)
}

// load_indirect_unsigned is that read of a one- or two-byte value with the bits
// above it filled with zero rather than its sign, which is what reading an
// element of an `unsigned char` or `unsigned short` array asks for.
pub fn load_indirect_unsigned(address Register, dst Register, width int) ![]u8 {
	return indirect_move(address, dst, width, false, false)
}

pub fn store_indirect(address Register, src Register, width int) ![]u8 {
	return indirect_move(address, src, width, true, true)
}

fn indirect_move(address Register, operand Register, width int, store bool, signed bool) ![]u8 {
	if width != 1 && width != 2 && width != 4 && width != 8 {
		return error('${name}: a value of ${width} bytes is not one this machine moves through an address')
	}
	low := address.code & 0x07
	if low == 4 || low == 5 {
		// rsp and rbp are the two the encoding cannot name where a register
		// goes: those two codes mean something else there, and a displacement of
		// zero written in would read the wrong memory.
		return error('${name}: an address in ${address.name} cannot be named without a displacement')
	}
	mut out := []u8{cap: 6}
	mut rex := u8(0x40)
	if width == 8 {
		rex |= 0x08
	}
	if operand.code >= 8 {
		rex |= 0x04
	}
	if address.code >= 8 {
		rex |= 0x01
	}
	// A two-byte store carries the operand-size prefix, which comes before the
	// REX byte; a two-byte load that widens names its widths itself.
	if store && width == 2 {
		out << u8(0x66)
	}
	// The prefix rule for a byte operand is the one the frame moves follow: the
	// low three bits name a different register when it is missing.
	if width == 1 || rex != 0x40 {
		out << rex
	}
	if store {
		out << u8(if width == 1 { 0x88 } else { 0x89 })
	} else if width == 1 {
		out << u8(0x0f)
		out << u8(if signed { 0xbe } else { 0xb6 })
	} else if width == 2 {
		out << u8(0x0f)
		out << u8(if signed { 0xbf } else { 0xb7 })
	} else {
		out << u8(0x8b)
	}
	out << u8(((operand.code & 0x07) << 3) | low) // mod 00: [address]
	return out
}

// frame_reserve opens the space a function's locals live in. The size is an
// immediate because it is not known while the body is written: the emitter
// reserves the space with a zero and fills the number in once the body has been
// walked. The immediate is the wide form so the instruction keeps its length
// when that happens, and frame_reserve_immediate is where the four bytes sit.
// push_register hands one value over on the stack, which is where an argument
// past the registers goes. The machine's push moves eight bytes and takes eight
// off the stack pointer, and a register whose code is eight or more needs the
// prefix byte that reaches it.
pub fn push_register(reg Register) []u8 {
	mut out := []u8{cap: 2}
	if reg.code >= 8 {
		out << u8(0x41)
	}
	out << u8(0x50 | (reg.code & 0x07))
	return out
}

// stack_release gives back the stack a call's own arguments took, so the frame
// is where it was before the call and the function's own slots keep the offsets
// they were written with. It is the other half of push_register, and it also
// gives back the one word an odd number of them took to keep the call aligned.
pub fn stack_release(size u32) []u8 {
	return [u8(0x48), 0x81, 0xc4, u8(size & 0xff), u8((size >> 8) & 0xff), u8((size >> 16) & 0xff),
		u8((size >> 24) & 0xff)] // add rsp, imm32
}

pub fn frame_reserve(size u32) []u8 {
	return [u8(0x48), 0x81, 0xec, u8(size & 0xff), u8((size >> 8) & 0xff), u8((size >> 16) & 0xff),
		u8((size >> 24) & 0xff)]
}

pub const frame_reserve_immediate = 3

// align_stack drops the stack pointer to the boundary a call wants. The entry
// point runs on the stack the kernel handed the process, and what that stack was
// aligned to is not this compiler's to assume: one instruction here makes every
// frame below it start where the convention says, whatever the kernel left.
pub fn align_stack() []u8 {
	return [u8(0x48), 0x83, 0xe4, 0xf0] // and rsp, -16
}

// The arithmetic this language's ints are computed with, all of it on the 32-bit
// names: the values are four bytes wide, and an operation at eight bytes would
// be an answer about a different value.

// add_immediate folds a constant into a register, which is how a member's offset
// joins the address the object was found at. The constant is written in four bytes
// and the machine extends it, so every offset a layout produces is reachable.
pub fn add_immediate(dst Register, value i32) []u8 {
	mut out := []u8{cap: 7}
	out << if dst.code >= 8 { u8(0x49) } else { u8(0x48) } // REX.W, with B when the code needs it
	out << u8(0x81) // the group opcode, with /0 for add
	out << u8(0xc0 | (dst.code & 0x07))
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// and_immediate masks a register with a constant, which is how the low bit of a
// value is reached on its own. It is the same group opcode as add_immediate with
// /4 in the reg field, and the constant is written in the four bytes that keep
// the instruction's length from depending on its value.
pub fn and_immediate(dst Register, value i32) ![]u8 {
	mut out := []u8{cap: 7}
	out << if dst.code >= 8 { u8(0x49) } else { u8(0x48) } // REX.W, with B when the code needs it
	out << u8(0x81) // the group opcode, with /4 for the and
	out << u8(0xe0 | (dst.code & 0x07))
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// add_reg64 adds one register into another at the full width of an address. An
// element of an aggregate array cannot be scaled by the stride when that stride is
// not a power of two, so the index is multiplied and this adds the array's address.
pub fn add_reg64(dst Register, src Register) []u8 {
	mut out := []u8{cap: 3}
	out << u8(0x48) | (if dst.code >= 8 { u8(0x01) } else { u8(0) }) | (if src.code >= 8 {
		u8(0x04)
	} else {
		u8(0)
	}) // REX.W, B for the destination and R for the source
	out << u8(0x01) // add r/m64, r64
	out << u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))
	return out
}

// imul_immediate multiplies a register by a constant in place, which is how an
// index becomes a byte offset when the stride is not one the machine's scaled
// address can write. The constant is four bytes and the result is the full width
// of the register.
pub fn imul_immediate(dst Register, value i32) []u8 {
	mut out := []u8{cap: 7}
	out << u8(0x48) | (if dst.code >= 8 { u8(0x05) } else { u8(0) }) // REX.W, with B and R for the one register
	out << u8(0x69) // imul r64, r/m64, imm32
	out << u8(0xc0 | ((dst.code & 0x07) << 3) | (dst.code & 0x07)) // the register is both operands
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

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

// cmp_reg64 compares two addresses and sets the flags. It is the same shape at
// the width of a word, because two addresses whose low halves are equal are not
// equal: the upper halves are the half that tells them apart.
pub fn cmp_reg64(left Register, right Register) ![]u8 {
	return rm_reg64(0x39, left, right)
}

// mov_reg64 copies one register into another at the width of a word, which is what
// an address needs: the four-byte copy beside this one keeps the low half of the
// address and zeroes the rest of the register.
pub fn mov_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x89, dst, src)
}

// rm_reg64 is rm_reg with REX.W, which is what makes an operation eight bytes wide
// on a register whose number is the same either way.
fn rm_reg64(opcode u8, rm Register, reg Register) ![]u8 {
	if rm.width != 4 || reg.width != 4 {
		return error('${name}: opcode ${opcode} takes two registers with a four-byte name, and ${rm.name} and ${reg.name} are not')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W
	if reg.code >= 8 {
		rex |= 0x04
	}
	if rm.code >= 8 {
		rex |= 0x01
	}
	out << rex
	out << opcode
	out << u8(0xc0 | ((reg.code & 0x07) << 3) | (rm.code & 0x07))
	return out
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

// cqo is cdq at the width of a word: it fills the register above the result one
// with the sign of the whole eight bytes there, which is the pair a signed
// division of eight-byte values divides. Measured on gcc 16.2.1 at -O0, where
// `long f(long a, long b) { return a / b; }` is a cqto and then an idivq of a
// word, and `unsigned long g(unsigned long a, unsigned long b) { return a % b; }`
// clears the register above with a four-byte move instead.
pub fn cqo() []u8 {
	return [u8(0x48), u8(0x99)]
}

// idiv_reg32 divides the pair formed by the result register and the one above it
// by a register. The quotient lands in the result register and the remainder in
// the register above it, which is where the language's two division operators
// read their answers from.
pub fn idiv_reg32(src Register) ![]u8 {
	return one_operand(src, 0x07)
}

// div_reg32 is the same division with the pair read as unsigned. Measured on gcc
// 16.2.1 at -O0, whose `unsigned int g(unsigned int a, unsigned int b) { return
// a / b; }` clears the register above and divides with a divl where the signed
// division of the same shape is an idivl.
pub fn div_reg32(src Register) ![]u8 {
	return one_operand(src, 0x06)
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
//
// The first six read the flags a comparison of signed values leaves: the zero flag
// for the two equalities, and the sign and overflow flags together for the four
// orderings. The last four are the same orders for unsigned values, which read the
// carry flag instead, and they are the ones a value two words wide is read with:
// the flags standing after the low word of one is subtracted from the low word of
// the other are the flags of the borrow, and every order of the pair follows from
// the carry flag of that subtraction and the flags of the subtraction of the high
// words.
pub enum Condition {
	equal
	not_equal
	less
	greater
	less_or_equal
	greater_or_equal
	below
	below_or_equal
	above
	above_or_equal
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
		.below { 0x92 }
		.below_or_equal { 0x96 }
		.above { 0x97 }
		.above_or_equal { 0x93 }
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

// sign_extend_byte widens a byte into the whole register with its sign kept,
// which is the instruction a value converted to a char is narrowed with: the low
// byte of the register is the char and the bits above it are its sign, not zero.
pub fn sign_extend_byte(reg Register) ![]u8 {
	byte_operand(reg)!
	return [u8(0x0f), 0xbe, u8(0xc0 | ((reg.code & 0x07) << 3) | (reg.code & 0x07))]
}

// sign_extend_half and zero_extend_half widen the low two bytes of a register
// into the whole register, with the sign kept and with zero above the value
// respectively. They are what a value converted to a short or an unsigned short
// is narrowed with, the two-byte shape of sign_extend_byte and movzx_byte. A
// register above the first eight needs the REX prefix that names it, since
// neither instruction can reach one without.
pub fn sign_extend_half(reg Register) ![]u8 {
	return half_extension(reg, 0xbf)
}

pub fn zero_extend_half(reg Register) ![]u8 {
	return half_extension(reg, 0xb7)
}

fn half_extension(reg Register, opcode u8) ![]u8 {
	mut out := []u8{cap: 4}
	// The source is the register's low three bits with REX.B, and the destination
	// is the same register with REX.R, because movsx and movzx name one register
	// in each field and both are this one.
	if reg.code >= 8 {
		out << u8(0x45) // REX.R | REX.B
	}
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((reg.code & 0x07) << 3) | (reg.code & 0x07))
	return out
}

// sign_extend_word widens a four-byte value into the whole register with its sign
// kept. A pointer is eight bytes and an int is four, so a conversion between them
// is this instruction: `(char *)0` is zero either way, and an int with the top bit
// set is an address whose upper half cannot be left as whatever was there.
pub fn sign_extend_word(dst Register, src Register) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: movsxd takes two registers with a four-byte name, and ${src.name} into ${dst.name} is not')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W: the destination is the whole register
	if src.code >= 8 {
		rex |= 0x04 // REX.R reaches the source
	}
	if dst.code >= 8 {
		rex |= 0x01 // REX.B reaches the destination
	}
	out << rex
	out << u8(0x63) // movsxd r64, r/m32
	out << u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))
	return out
}

// shift_right_arithmetic shifts the whole register right and copies the sign into
// the bits that open at the top, which is how the sign of a value is spread over
// the bits of it: `sar rax, 63` is every bit of a value that is negative and no
// bit of one that is not. That is what a value narrower than the word it is
// stored in needs: the bits above the sign have to be its sign and not whatever
// the register held. The count is in the instruction rather than in a register,
// because it is a count the emitter knows when it writes it.
pub fn shift_right_arithmetic(reg Register, bits u8) ![]u8 {
	if reg.width != 4 {
		return error('${name}: ${reg.name} is not a register to shift')
	}
	if bits >= 64 {
		return error('${name}: a shift of ${bits} bits is wider than the register')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W: the whole register is shifted
	if reg.code >= 8 {
		rex |= 0x01 // REX.B reaches the register
	}
	out << rex
	out << u8(0xc1) // a shift by the count in the next byte
	out << u8(0xf8 | (reg.code & 0x07)) // group 7, the arithmetic shift
	out << bits
	return out
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

// jump_sign_rel32 goes to the distance it carries when the sign flag the last
// operation set says the value was negative, which is how the range split above
// asks whether an integer has its top bit set.
pub fn jump_sign_rel32(disp i32) []u8 {
	return conditional_jump(0x88, disp)
}

// jump_below_rel32 goes there when the carry flag says the left value was below
// the right one, which is the order a double comparison leaves for `below`: a
// Comisd puts the carry flag up when the first operand is the smaller, so this is
// the branch the range split of a double into an unsigned word takes.
pub fn jump_below_rel32(disp i32) []u8 {
	return conditional_jump(0x82, disp)
}

// conditional_jump is the two-byte opcode form: 0F, then the opcode the condition
// owns, then the distance.
fn conditional_jump(opcode u8, disp i32) []u8 {
	value := u32(disp)
	return [u8(0x0f), opcode, u8(value & 0xff), u8((value >> 8) & 0xff), u8((value >> 16) & 0xff),
		u8((value >> 24) & 0xff)]
}

// The instructions a value two words wide needs. Such a value lives in a pair of
// registers: the low word in the result register, which is where an expression's
// value is computed and where a function leaves what it returns, and the high word
// in the register above it, which is also where a division leaves its remainder.
// Every function below says which side of that pair it works on, because that is
// the whole difference between adding the low words of two of them and adding the
// high ones, and a primitive whose side is not written down is one the caller has
// to guess at.
//
// The two registers are the ones the arithmetic above already names: `return_reg`
// holds the low word of the pair and `remainder_reg` the high one.

// sub_reg64 subtracts the source from the destination at the width of a word. It
// is the low word of a two-word subtraction, and the borrow it leaves in the carry
// flag is what sbb_reg64 takes out of the high words next. Both operands are the
// low words of the pair.
pub fn sub_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x29, dst, src)
}

// adc_reg64 adds the source and the carry flag into the destination. It is the
// high word of a two-word addition: the low words go through add first and the
// carry out of that addition is added in here, so the pair of an addition is add
// then adc. Both operands are the high words of the pair.
pub fn adc_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x11, dst, src)
}

// adc_immediate adds a constant and the carry flag into the destination, in the
// four bytes of immediate the machine extends. It is the carry into the high word
// of a two-word negation: negating the low word leaves a borrow in the flag when
// that word was not zero, and this is how that borrow reaches the high word, with
// a constant of zero. The immediate is written in four bytes rather than the one
// the machine has for a small constant, because every immediate this file writes
// is four bytes wide and the length of an instruction may not depend on its value.
pub fn adc_immediate(dst Register, value i32) ![]u8 {
	if dst.width != 4 {
		return error('${name}: an addition with carry and an immediate takes a register four bytes wide, and ${dst.name} is not one')
	}
	mut out := []u8{cap: 7}
	out << u8(0x48) | (if dst.code >= 8 { u8(0x01) } else { u8(0) }) // REX.W, with B when the code needs it
	out << u8(0x81) // the group opcode, with /2 for the addition with carry
	out << u8(0xd0 | (dst.code & 0x07))
	out << u8(value & 0xff)
	out << u8((value >> 8) & 0xff)
	out << u8((value >> 16) & 0xff)
	out << u8((value >> 24) & 0xff)
	return out
}

// sbb_reg64 subtracts the source and the carry flag from the destination, which is
// the high word of a two-word subtraction: sub leaves the borrow of the low words
// in the carry flag and this takes it out of the high ones. Both operands are the
// high words of the pair.
//
// The same instruction is how two words are compared as unsigned values, read for
// its flags rather than for its result: the low words are subtracted from each
// other and then the high ones, and the flags standing after the second
// subtraction are the order of the two values. `setb` over flags from `sub` alone
// would answer about the low words, which is why the borrow has to be carried into
// the high word before the flags are read.
pub fn sbb_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x19, dst, src)
}

// and_reg64, or_reg64 and xor_reg64 apply a bitwise operator to one word of the
// pair. A two-word value needs one instruction per word, because the machine's
// operators are a word wide: the low words are combined with each other and the
// high words with each other, and neither answer depends on the other word.
pub fn and_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x21, dst, src)
}

pub fn or_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x09, dst, src)
}

pub fn xor_reg64(dst Register, src Register) ![]u8 {
	return rm_reg64(0x31, dst, src)
}

// test_reg64 compares one word of the pair with zero and sets the flags without
// producing a value. It is how the low word of a two-word value is asked whether
// it is zero, as the first half of asking whether the whole value is.
pub fn test_reg64(reg Register) ![]u8 {
	return rm_reg64(0x85, reg, reg)
}

// shl_reg64 and shr_reg64 shift one word of the pair left or right by a count in
// the instruction. They are the word-local half of a two-word shift: a shift left
// of the pair is shld_immediate of the high word with the low word's top bits
// coming down into it, then shl of the low word, and a shift right is the same
// with shrd_immediate and shr.
pub fn shl_reg64(reg Register, bits u8) ![]u8 {
	return shift_immediate(0x04, reg, bits)
}

pub fn shr_reg64(reg Register, bits u8) ![]u8 {
	return shift_immediate(0x05, reg, bits)
}

// shld_immediate shifts the destination left and fills the bits that open at the
// bottom with the top bits of the source, as if the two registers held one value
// twice as wide. It is how the high word of a two-word left shift is made, with
// the low word as the source. shrd_immediate is the same to the right and is how
// the low word of a two-word right shift is made, with the high word as the
// source. A single word's shift cannot do either: the bits that belong at the
// bottom of the high word are in the low word, and a shl would bring zeros down
// instead.
//
// The count is in the instruction rather than in a register because it is a count
// the emitter knows when it writes the instruction. A count of zero shifts nothing
// and is allowed.
pub fn shld_immediate(dst Register, src Register, bits u8) ![]u8 {
	return shift_pair_immediate(0xa4, dst, src, bits)
}

pub fn shrd_immediate(dst Register, src Register, bits u8) ![]u8 {
	return shift_pair_immediate(0xac, dst, src, bits)
}

// shift_immediate is a shift whose count is in the instruction, one of the
// operations the machine's C1 opcode holds: the operation is in the reg field and
// the operand is the r/m one. The arithmetic shift above writes the same shape
// with the opcode of its own operation.
fn shift_immediate(group u8, reg Register, bits u8) ![]u8 {
	if reg.width != 4 {
		return error('${name}: a shift of a word names a register four bytes wide, and ${reg.name} is not one')
	}
	if bits >= 64 {
		return error('${name}: a shift of ${bits} bits is wider than the register')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W: the whole word is shifted
	if reg.code >= 8 {
		rex |= 0x01 // REX.B reaches the register
	}
	out << rex
	out << u8(0xc1) // a shift by the count in the next byte
	out << u8(0xc0 | ((group & 0x07) << 3) | (reg.code & 0x07))
	out << bits
	return out
}

// shift_register is a shift whose count is in CL, which is the register the machine
// takes a count in: the operation is in the reg field and the count is in the
// register rather than in the instruction. The machine reads the low six bits of
// CL and no more, which is why the count of a computed shift is answered modulo the
// register's width by the machine itself rather than refused as the immediate form
// refuses a count as wide as the value. `wide` is the difference between the word
// form and the four-byte one, and the four-byte one is what a value narrower than a
// word is shifted with so that its count is read as a narrow one's count is.
fn shift_register(group u8, reg Register, wide bool) ![]u8 {
	if reg.width != 4 {
		return error('${name}: a shift names a register four bytes wide, and ${reg.name} is not one')
	}
	mut out := []u8{cap: 3}
	if wide {
		mut rex := u8(0x48) // REX.W: the whole word is shifted
		if reg.code >= 8 {
			rex |= 0x01
		}
		out << rex
	} else if reg.code >= 8 {
		out << u8(0x41) // REX.B reaches the register; the four-byte form needs no REX.W
	}
	out << u8(0xd3) // the count is in CL
	out << u8(0xc0 | ((group & 0x07) << 3) | (reg.code & 0x07))
	return out
}

// The six forms of it, and each of the four-byte ones shifts a value narrower than
// a word the way the language shifts it: the machine reads five bits of the count.
pub fn shift_left_narrow(reg Register) ![]u8 {
	return shift_register(0x04, reg, false)
}

pub fn shift_right_narrow(reg Register) ![]u8 {
	return shift_register(0x05, reg, false)
}

pub fn shift_right_arithmetic_narrow(reg Register) ![]u8 {
	return shift_register(0x07, reg, false)
}

pub fn shift_left_word_register(reg Register) ![]u8 {
	return shift_register(0x04, reg, true)
}

pub fn shift_right_word_register(reg Register) ![]u8 {
	return shift_register(0x05, reg, true)
}

pub fn shift_right_arithmetic_register(reg Register) ![]u8 {
	return shift_register(0x07, reg, true)
}

// shift_pair_register is shld and shrd with the count in CL, which is what a shift
// of a value two words wide needs when the count is not written in the program: it
// moves the bits of one word into the other end of the other, and with the count in
// a register the machine reads six bits of it.
fn shift_pair_register(opcode u8, dst Register, src Register) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: opcode ${opcode} takes two registers four bytes wide, and ${dst.name} and ${src.name} are not both that')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W: the values are words
	if dst.code >= 8 {
		rex |= 0x01
	}
	if src.code >= 8 {
		rex |= 0x04
	}
	out << rex
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))
	return out
}

pub fn shld_register(dst Register, src Register) ![]u8 {
	return shift_pair_register(0xa5, dst, src)
}

pub fn shrd_register(dst Register, src Register) ![]u8 {
	return shift_pair_register(0xad, dst, src)
}

// test_byte_immediate tests one byte register against a constant and sets the flags
// for that test, which is how the bit of a shift count that decides which sequence
// runs is read without changing the count.
pub fn test_byte_immediate(reg Register, value u8) ![]u8 {
	if reg.width != 4 {
		return error('${name}: a byte test names the register four bytes wide whose low byte it tests, and ${reg.name} is not one')
	}
	mut out := []u8{cap: 3}
	if reg.code >= 8 {
		out << u8(0x41) // REX.B reaches the register's low byte
	}
	out << u8(0xf6) // the group whose reg field of zero is the test
	out << u8(0xc0 | (reg.code & 0x07))
	out << value
	return out
}

// shift_pair_immediate is shld and shrd: the destination is the r/m operand, the
// source is the reg field, and the count is in the last byte.
fn shift_pair_immediate(opcode u8, dst Register, src Register, bits u8) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: opcode ${opcode} takes two registers four bytes wide, and ${dst.name} and ${src.name} are not both that')
	}
	if bits >= 64 {
		return error('${name}: a shift of ${bits} bits is wider than the register')
	}
	mut out := []u8{cap: 5}
	mut rex := u8(0x48) // REX.W
	if src.code >= 8 {
		rex |= 0x04 // REX.R reaches the source
	}
	if dst.code >= 8 {
		rex |= 0x01 // REX.B reaches the destination
	}
	out << rex
	out << u8(0x0f)
	out << opcode
	out << u8(0xc0 | ((src.code & 0x07) << 3) | (dst.code & 0x07))
	out << bits
	return out
}

// mul_reg64 multiplies the result register by the source and leaves the product in
// the pair, the low word in the result register and the high word above it. Both
// values are read as unsigned. imul_reg64 is the same multiply with both read as
// signed, and the two differ in the high word of the product whenever an operand
// has its top bit set.
//
// This is not the two-operand imul above: that one takes a destination and a
// source and keeps the low word of the product in the destination, where this one
// takes a single source, multiplies the result register by it, and keeps both
// words.
pub fn mul_reg64(src Register) ![]u8 {
	return one_operand64(src, 0x04)
}

pub fn imul_reg64(src Register) ![]u8 {
	return one_operand64(src, 0x05)
}

// imul_word64 multiplies the second register into the first and keeps the low
// word of the answer, which is all of it that a pair's multiplication wants: the
// cross products of two pairs are added into a high word, and the part of each
// product above its low word is beyond the 128 bits of the answer and is dropped.
// Measured on gcc 16.2.1, whose multiply of two __int128 values is two of these,
// an lea that drops its own carry, and a mul.
pub fn imul_word64(dst Register, src Register) ![]u8 {
	if dst.width != 4 || src.width != 4 {
		return error('${name}: a two-operand imul takes two registers named four bytes wide, and ${dst.name} and ${src.name} are not both that')
	}
	mut out := []u8{cap: 4}
	mut rex := u8(0x48) // REX.W: the values are words
	if dst.code >= 8 {
		rex |= 0x04
	}
	if src.code >= 8 {
		rex |= 0x01
	}
	out << rex
	out << u8(0x0f)
	out << u8(0xaf)
	out << u8(0xc0 | ((dst.code & 0x07) << 3) | (src.code & 0x07))
	return out
}

// div_reg64 and idiv_reg64 divide the pair by the source: the dividend is the low
// word in the result register and the high word above it, and the quotient comes
// back to the result register with the remainder above it. The first reads the
// pair as unsigned and the second as signed.
//
// Dividing a value narrower than the pair is a sign extension of it into the high
// word first, which is a step of the caller's rather than one of these.
pub fn div_reg64(src Register) ![]u8 {
	return one_operand64(src, 0x06)
}

pub fn idiv_reg64(src Register) ![]u8 {
	return one_operand64(src, 0x07)
}

// neg_reg64 is the sign change and not_reg64 the bitwise complement, each at the
// width of a word, so each of them is one word of the pair. A two-word negation is
// neither of them alone: the low word is negated, the borrow that leaves is added
// into the high word with adc_immediate, and the high word is negated too.
pub fn neg_reg64(reg Register) ![]u8 {
	return one_operand64(reg, 0x03)
}

pub fn not_reg64(reg Register) ![]u8 {
	return one_operand64(reg, 0x02)
}

// one_operand64 is the group of operations that take a single value at the width
// of a word: the operation is in the reg field and the value is the r/m one. It is
// one_operand above with REX.W, which is the whole difference between the same
// operation on a four-byte value and on an eight-byte one.
fn one_operand64(reg Register, group u8) ![]u8 {
	if reg.width != 4 {
		return error('${name}: ${reg.name} is not a register four bytes wide to name a word operation with')
	}
	mut out := []u8{cap: 3}
	mut rex := u8(0x48) // REX.W: the value is a word
	if reg.code >= 8 {
		rex |= 0x01 // REX.B reaches the register
	}
	out << rex
	out << u8(0xf7)
	out << u8(0xc0 | ((group & 0x07) << 3) | (reg.code & 0x07))
	return out
}
