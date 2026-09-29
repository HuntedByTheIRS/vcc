module codegen

import backend

// The ELF64 container, in the shape Linux starts and its dynamic loader
// finishes. A program that calls a shared library is not a header and a code
// blob: the image has to name the loader that will finish the job (PT_INTERP),
// say which library it runs against (a DT_NEEDED entry in the PT_DYNAMIC table),
// and carry enough symbol information for the loader to find each function it
// calls and write its address where the code reads it: a .dynsym, the .hash the
// loader walks to learn how many symbols there are, a .rela.dyn with one
// relocation per imported function, and the slots those relocations fill.
//
// The image is built in one pass over a fixed order of parts, because every
// offset in it is the size of what came before: interpreter, code, string table,
// read-only data, symbol table, hash, slots, relocations, dynamic table. There
// is no section header table; the loader reads the program headers.
//
// The values the target owns (machine id, page size, load base, the loader's
// path) come from its table, so a second system changes the tables and not this
// file.

const elf_magic = [u8(0x7f), `E`, `L`, `F`]

const elf_class_64 = u8(2)
const elf_data_little_endian = u8(1)
const elf_version_current = u8(1)
const elf_type_exec = u16(2)

const elf_header_size = u16(64)
const elf_program_header_size = u16(56)
// PT_INTERP, PT_LOAD, PT_DYNAMIC and PT_GNU_STACK, in that order, always all four.
const elf_program_header_count = u16(4)

// The program header types this container uses.
const elf_ph_type_load = u32(1)
const elf_ph_type_dynamic = u32(2)
const elf_ph_type_interp = u32(3)
const elf_ph_type_gnu_stack = u32(0x6474E551)

// The segment permissions, combined where a segment needs more than one.
const elf_ph_flags_execute = u32(1)
const elf_ph_flags_write = u32(2)
const elf_ph_flags_read = u32(4)

// The dynamic table's tags, from the System V ABI: what the loader is told about
// the program it has been handed.
const dt_null = u64(0)
const dt_needed = u64(1)
const dt_hash = u64(4)
const dt_strtab = u64(5)
const dt_symtab = u64(6)
const dt_rela = u64(7)
const dt_relasz = u64(8)
const dt_relaent = u64(9)
const dt_strsz = u64(10)
const dt_syment = u64(11)
const dt_entry_count = 10 // the nine above, and the null that ends the table

// A relocation that asks the loader to write a symbol's address into a slot.
const relocation_glob_dat = u64(6)

// The st_info byte of every symbol this image imports: global, and of function
// type. The symbols are undefined, which is to say the value comes from
// somewhere else.
const symbol_global_function = u8(0x12)

// Symbols and relocations are fixed-size records in this container.
const elf_symbol_size = 24
const elf_relocation_size = 24
const elf_dynamic_entry_size = 16

// The library every image here runs against. V passes its own libraries on the
// command line and this stub does not link them yet, so an image answers its
// calls out of the one library the system always has.
const shared_library = 'libc.so.6'

// Sections is where each part of the image landed, as a file offset from the
// start of the file. The image is one segment that starts at file offset zero,
// so a file offset and a virtual address differ by the load base and nothing
// else, which is what lets the references be patched in file-offset arithmetic.
struct Sections {
	interp  int
	text    int
	dynstr  int
	strings int
	dynsym  int
	hash    int
	got     int
	rela    int
	dynamic int
	total   int
}

// executable wraps a program in an ELF64 image that a Linux kernel can start and
// a dynamic loader can finish.
fn executable(program Program, target backend.Target) ![]u8 {
	base := target.load_base
	// The loader's path, with the terminator the kernel expects.
	mut interp := target.interpreter.bytes()
	interp << u8(0)
	// The string table: the null entry, the name of each imported symbol, and
	// the library's own name at the offset the dynamic table points at.
	mut dynstr := []u8{}
	dynstr << u8(0)
	mut symbol_names := map[string]int{}
	for name in program.imports {
		symbol_names[name] = dynstr.len
		dynstr << name.bytes()
		dynstr << u8(0)
	}
	needed := dynstr.len
	dynstr << shared_library.bytes()
	dynstr << u8(0)
	sections := layout(program, target, interp.len, dynstr.len)
	mut image := []u8{len: sections.total, init: u8(0)}
	put(mut image, sections.interp, interp)
	put(mut image, sections.text, program.text)
	put(mut image, sections.dynstr, dynstr)
	put(mut image, sections.strings, program.string_blob)
	emit_symbols(mut image, program, sections, symbol_names)
	emit_hash(mut image, program, sections)
	emit_relocations(mut image, program, sections, base)
	emit_dynamic(mut image, program, sections, dynstr.len, needed, base)
	emit_header(mut image, target, base + u64(sections.text))
	emit_program_headers(mut image, target, sections, interp.len)
	patch(mut image, program, target, sections)!
	return image
}

// layout places every part of the image: one part after another, each at an
// eight-byte boundary, with the whole image rounded up to a page.
fn layout(program Program, target backend.Target, interp_len int, dynstr_len int) Sections {
	mut offset := int(elf_header_size) + int(elf_program_header_count) * int(elf_program_header_size)
	interp := offset
	offset = align(offset + interp_len, 8)
	text := offset
	offset = align(offset + program.text.len, 8)
	dynstr := offset
	offset = align(offset + dynstr_len, 8)
	strings := offset
	offset = align(offset + program.string_blob.len, 8)
	dynsym := offset
	offset = align(offset + (program.imports.len + 1) * elf_symbol_size, 8)
	hash := offset
	offset = align(offset + hash_size(program.imports.len + 1), 8)
	got := offset
	offset = align(offset + program.imports.len * 8, 8)
	rela := offset
	offset = align(offset + program.imports.len * elf_relocation_size, 8)
	dynamic := offset
	offset = align(offset + int(dt_entry_count) * elf_dynamic_entry_size, 8)
	return Sections{
		interp:  interp
		text:    text
		dynstr:  dynstr
		strings: strings
		dynsym:  dynsym
		hash:    hash
		got:     got
		rela:    rela
		dynamic: dynamic
		total:   align(offset, int(target.page_size))
	}
}

// hash_size is the size of the SysV hash table for a symbol count: one bucket,
// an entry in the bucket array for it, and a chain entry per symbol including
// the null one.
fn hash_size(symbol_count int) int {
	return 8 + 4 * (1 + symbol_count)
}

// emit_symbols writes the dynamic symbol table: a null entry the container
// requires, then one entry per imported function. Each is a name in the string
// table, marked global and of function type, with no value and no section,
// because its definition is somewhere this image is not.
fn emit_symbols(mut image []u8, program Program, sections Sections, symbol_names map[string]int) {
	for i, name in program.imports {
		at := sections.dynsym + (i + 1) * elf_symbol_size
		put_u32(mut image, at, u32(symbol_names[name]))
		image[at + 4] = symbol_global_function
	}
}

// emit_hash writes the SysV hash table. Nothing in this image is looked up by
// name, so the buckets and the chains stay zero; the loader reads the header to
// learn how many symbols the table holds.
fn emit_hash(mut image []u8, program Program, sections Sections) {
	put_u32(mut image, sections.hash, 1) // one bucket
	put_u32(mut image, sections.hash + 4, u32(program.imports.len + 1))
}

// emit_relocations writes one relocation per import: the loader resolves the
// symbol and writes its address into the slot named here, which is where every
// call to that function reads it from.
fn emit_relocations(mut image []u8, program Program, sections Sections, base u64) {
	for i, _ in program.imports {
		at := sections.rela + i * elf_relocation_size
		put_u64(mut image, at, base + u64(sections.got + i * 8))
		put_u64(mut image, at + 8, (u64(i + 1) << 32) | relocation_glob_dat)
		// The addend is zero, which says the address itself is the value.
	}
}

// emit_dynamic writes the table that tells the loader what the image needs: the
// library, where the tables are, and how big each record in them is.
fn emit_dynamic(mut image []u8, program Program, sections Sections, dynstr_len int, needed int, base u64) {
	entries := [
		[dt_needed, u64(needed)],
		[dt_hash, base + u64(sections.hash)],
		[dt_strtab, base + u64(sections.dynstr)],
		[dt_symtab, base + u64(sections.dynsym)],
		[dt_rela, base + u64(sections.rela)],
		[dt_relasz, u64(program.imports.len * elf_relocation_size)],
		[dt_relaent, u64(elf_relocation_size)],
		[dt_strsz, u64(dynstr_len)],
		[dt_syment, u64(elf_symbol_size)],
		[dt_null, u64(0)],
	]
	for i, entry in entries {
		put_u64(mut image, sections.dynamic + i * elf_dynamic_entry_size, entry[0])
		put_u64(mut image, sections.dynamic + i * elf_dynamic_entry_size + 8, entry[1])
	}
}

// emit_header writes the ELF header: what the file is, which machine it runs
// on, where execution starts, and where the program headers are.
fn emit_header(mut image []u8, target backend.Target, entry u64) {
	put(mut image, 0, elf_magic)
	image[4] = elf_class_64
	image[5] = elf_data_little_endian
	image[6] = elf_version_current
	// Byte 7 is the ABI, System V, and bytes 8 to 15 are its padding: the zeroes
	// the image was made of are what belongs there, so nothing is written.
	put_u16(mut image, 16, elf_type_exec)
	put_u16(mut image, 18, target.elf_machine)
	put_u32(mut image, 20, 1) // the container version, which is current
	put_u64(mut image, 24, entry)
	put_u64(mut image, 32, u64(elf_header_size)) // the program headers follow
	put_u64(mut image, 40, 0) // no section header table
	put_u32(mut image, 48, 0) // no architecture-specific flags
	put_u16(mut image, 52, elf_header_size)
	put_u16(mut image, 54, elf_program_header_size)
	put_u16(mut image, 56, elf_program_header_count)
	put_u16(mut image, 58, 0)
	put_u16(mut image, 60, 0)
	put_u16(mut image, 62, 0)
}

// emit_program_headers writes the four program headers the kernel and the loader
// read before any of the code runs.
fn emit_program_headers(mut image []u8, target backend.Target, sections Sections, interp_len int) {
	mut at := int(elf_header_size)
	// PT_INTERP: the loader the kernel hands the process to.
	put_u32(mut image, at, elf_ph_type_interp)
	put_u32(mut image, at + 4, elf_ph_flags_read)
	put_u64(mut image, at + 8, u64(sections.interp))
	put_u64(mut image, at + 16, target.load_base + u64(sections.interp))
	put_u64(mut image, at + 24, target.load_base + u64(sections.interp))
	put_u64(mut image, at + 32, u64(interp_len))
	put_u64(mut image, at + 40, u64(interp_len))
	put_u64(mut image, at + 48, 1)
	at += int(elf_program_header_size)
	// PT_LOAD: the whole image, at the load base. It is readable, writable and
	// executable because the code, the strings and the slots the loader writes
	// all live in it.
	put_u32(mut image, at, elf_ph_type_load)
	put_u32(mut image, at + 4, elf_ph_flags_read | elf_ph_flags_write | elf_ph_flags_execute)
	put_u64(mut image, at + 8, 0)
	put_u64(mut image, at + 16, target.load_base)
	put_u64(mut image, at + 24, target.load_base)
	put_u64(mut image, at + 32, u64(sections.total))
	put_u64(mut image, at + 40, u64(sections.total))
	put_u64(mut image, at + 48, target.page_size)
	at += int(elf_program_header_size)
	// PT_DYNAMIC: the table the loader reads.
	put_u32(mut image, at, elf_ph_type_dynamic)
	put_u32(mut image, at + 4, elf_ph_flags_read | elf_ph_flags_write)
	put_u64(mut image, at + 8, u64(sections.dynamic))
	put_u64(mut image, at + 16, target.load_base + u64(sections.dynamic))
	put_u64(mut image, at + 24, target.load_base + u64(sections.dynamic))
	put_u64(mut image, at + 32, u64(int(dt_entry_count) * elf_dynamic_entry_size))
	put_u64(mut image, at + 40, u64(int(dt_entry_count) * elf_dynamic_entry_size))
	put_u64(mut image, at + 48, 8)
	at += int(elf_program_header_size)
	// PT_GNU_STACK: the stack is readable and writable and not executable, which
	// is what a program that never runs code from it should say.
	put_u32(mut image, at, elf_ph_type_gnu_stack)
	put_u32(mut image, at + 4, elf_ph_flags_read | elf_ph_flags_write)
	put_u64(mut image, at + 48, 0x10)
}

// patch fills in every reference now that every offset is settled. It runs after
// the parts are in place, because a displacement depends on the whole layout.
fn patch(mut image []u8, program Program, target backend.Target, sections Sections) ! {
	for fixup in program.fixups {
		referent := referent_of(program, sections, fixup)!
		instruction := sections.text + fixup.start
		disp := i32(referent - (instruction + fixup.length))
		mut replacement := []u8{}
		match fixup.kind {
			.call_local {
				replacement = target.call_near(disp)
			}
			.call_import {
				replacement = target.call_slot(disp)
			}
			.take_address {
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.address_of(register, disp)
			}
			.jump_local {
				replacement = target.jump(disp)
			}
			.branch_zero {
				replacement = target.jump_if_zero(disp)
			}
			.branch_nonzero {
				replacement = target.jump_if_not_zero(disp)
			}
		}
		if replacement.len != fixup.length {
			return error('the reference to ${fixup.name} was ${fixup.length} bytes and became ${replacement.len}')
		}
		put(mut image, instruction, replacement)
	}
}

// referent_of is where one reference points, as an offset into the image.
fn referent_of(program Program, sections Sections, fixup Fixup) !int {
	match fixup.kind {
		.call_local, .jump_local, .branch_zero, .branch_nonzero {
			return sections.text + (program.labels[fixup.name] or {
				return error('no code for ${fixup.name}')
			})
		}
		.call_import {
			for i, name in program.imports {
				if name == fixup.name {
					return sections.got + i * 8
				}
			}
			return error('${fixup.name} is called but was never imported')
		}
		.take_address {
			return sections.strings + (program.strings[fixup.name] or {
				return error('no string ${fixup.name} in the image')
			})
		}
	}
}

fn put(mut image []u8, offset int, bytes []u8) {
	for i, byte in bytes {
		image[offset + i] = byte
	}
}

fn put_u16(mut image []u8, offset int, value u16) {
	image[offset] = u8(value & 0xff)
	image[offset + 1] = u8((value >> 8) & 0xff)
}

fn put_u32(mut image []u8, offset int, value u32) {
	for shift in [0, 8, 16, 24] {
		image[offset + shift / 8] = u8((value >> shift) & 0xff)
	}
}

fn put_u64(mut image []u8, offset int, value u64) {
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		image[offset + shift / 8] = u8((value >> shift) & 0xff)
	}
}

// align rounds a size up to the next multiple of the alignment.
fn align(value int, to int) int {
	return (value + to - 1) / to * to
}
