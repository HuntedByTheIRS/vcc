module codegen

import backend

// The ELF64 container. The compiler emits one loadable segment holding the
// headers and the code, which is all a static program with no data needs: the
// segment is mapped at the target's load base, the entry point is the first
// instruction of the code, and the kernel does the rest.
//
// The values the target owns (machine id, page size, load base) come from its
// table, so a second architecture changes the tables and not this file.

const elf_magic = [u8(0x7f), `E`, `L`, `F`]

const elf_class_64 = u8(2)
const elf_data_little_endian = u8(1)
const elf_version_current = u8(1)
const elf_type_exec = u16(2)
const elf_ph_type_load = u32(1)
const elf_ph_flags_read_exec = u32(5)

const elf_header_size = u16(64)
const elf_program_header_size = u16(56)

// executable wraps machine code in an ELF64 executable: headers, padding up to
// the first page, then the code.
fn executable(code []u8, target backend.Target) []u8 {
	code_offset := target.page_size
	total := code_offset + u64(code.len)
	mut image := []u8{cap: int(total)}
	emit_elf_header(mut image, target, u64(target.load_base) + code_offset)
	emit_program_header(mut image, target, total)
	for u64(image.len) < code_offset {
		image << u8(0)
	}
	image << code
	return image
}

fn emit_elf_header(mut image []u8, target backend.Target, entry u64) {
	for byte in elf_magic {
		image << byte
	}
	image << elf_class_64
	image << elf_data_little_endian
	image << elf_version_current
	image << u8(0) // ELF ABI: System V
	for _ in 0 .. 8 {
		image << u8(0) // padding
	}
	push_u16(mut image, elf_type_exec)
	push_u16(mut image, target.elf_machine)
	push_u32(mut image, 1) // EV_CURRENT
	push_u64(mut image, entry)
	push_u64(mut image, u64(elf_header_size)) // program headers follow the header
	push_u64(mut image, 0) // no section headers
	push_u32(mut image, 0) // no flags
	push_u16(mut image, elf_header_size)
	push_u16(mut image, elf_program_header_size)
	push_u16(mut image, 1) // one program header
	push_u16(mut image, 0) // no section header entries
	push_u16(mut image, 0)
	push_u16(mut image, 0)
}

fn emit_program_header(mut image []u8, target backend.Target, total u64) {
	push_u32(mut image, elf_ph_type_load)
	push_u32(mut image, elf_ph_flags_read_exec)
	push_u64(mut image, 0) // the segment starts at the beginning of the file
	push_u64(mut image, target.load_base)
	push_u64(mut image, target.load_base)
	push_u64(mut image, total) // file image
	push_u64(mut image, total) // and memory image, identical
	push_u64(mut image, target.page_size)
}

fn push_u16(mut image []u8, value u16) {
	image << u8(value & 0xff)
	image << u8((value >> 8) & 0xff)
}

fn push_u32(mut image []u8, value u32) {
	for shift in [0, 8, 16, 24] {
		image << u8((value >> shift) & 0xff)
	}
}

fn push_u64(mut image []u8, value u64) {
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		image << u8((value >> shift) & 0xff)
	}
}
