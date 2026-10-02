module elf

import backend
import image

// The relocatable container: what `-c` writes, and what a linker reads back.
//
// A program and an object are the same image in two states. A program has every
// address settled, one segment that maps whole, and a loader that finishes the
// job. An object has none of those things: it is code and data whose addresses
// are decided by whoever links it, so what it carries instead of settled
// addresses is a symbol table saying what it defines and what it needs, and a
// relocation for every place the code left a hole.
//
// The two share the parts that are the same in both: the header, the string
// tables, the symbols, and the byte writers below. They differ in what those
// parts say. A program's symbol table is dynamic and describes what the loader
// looks up by name; an object's is static and describes what a linker resolves.
// There is no program header table here and nothing to map, because a
// relocatable file is not something a kernel starts.
//
// Every machine fact comes from the target, including the two relocation
// numbers, which belong to a machine's psABI rather than to this format.

// elf_type_rel is a relocatable file: code and data whose addresses are not
// settled, which is what makes it an input to a link rather than a program.
const elf_type_rel = u16(1)

// The section header types this file writes. The null section's type is zero, and
// it is written by leaving the zeroes the file was made of in place, so there is
// no constant for it here.
const sht_progbits = u32(1)
const sht_symtab = u32(2)
const sht_strtab = u32(3)
const sht_rela = u32(4)

// The section flags. A relocatable file still says which parts have to be mapped
// together and how, even though none of them has an address yet.
const shf_write = u64(1)
const shf_alloc = u64(2)
const shf_execinstr = u64(4)

// The st_info bytes this file writes. st_info packs two four-bit fields: the low
// half is what the symbol names and the high half is who may see it. The pairs
// this object needs are a section no one refers to by name, an object anything
// may refer to, and, from elf.v, the function those two sit beside.
const symbol_local_section = u8(0x03) // binding local (0), type section (3)
const symbol_global_object = u8(0x11) // binding global (1), type object (1)

// shn_undef is the section a symbol has when this object does not define it: its
// definition is somewhere the linker still has to look.
const shn_undef = u16(0)

const elf_section_header_size = 64

// The section numbers, in the order they are written. The null section every ELF
// file has is number zero, and it is not a place: it is what a symbol with no
// section behind it names, so the table cannot start anywhere else, and nothing
// here counts it.
const section_text = 1
const section_rela_text = 2
const section_rodata = 3
const section_data = 4
const section_symtab = 5
const section_strtab = 6
const section_shstrtab = 7
// The note that says the stack does not have to be executable. It holds nothing,
// and its presence is the whole point: a linker that does not find it has to
// assume the worst and asks about it.
const section_gnu_stack = 8
const section_count = 9

// The three symbols every object has before its own: one per section a reference
// can be made against. A reference to a string is a reference to .rodata at an
// offset, and the section symbol is what says so.
const symbol_text_section = 1
const symbol_rodata_section = 2
const symbol_data_section = 3
// first_global_symbol is where the local symbols stop. The table has to say
// this, because a linker reads the locals out of it once and never again.
const first_global_symbol = 4

// NameOffsets is where each section's name landed in .shstrtab.
struct NameOffsets {
	text      int
	rela      int
	rodata    int
	data      int
	symtab    int
	strtab    int
	shstrtab  int
	gnu_stack int
}

// PartSizes is how long each part of the object is. The sizes are kept apart from
// the offsets because a part's length is not the distance to the next one: the
// layout pads each part to an eight-byte boundary, and a section header has to
// say how long the part is and not how much room it was given.
struct PartSizes {
	text     int
	rodata   int
	data     int
	rela     int
	symtab   int
	strtab   int
	shstrtab int
}

// PartOffsets is where each part of the object landed, as a file offset.
struct PartOffsets {
	text     int
	rodata   int
	data     int
	rela     int
	symtab   int
	strtab   int
	shstrtab int
	headers  int
	total    int
}

// ObjectRelocation is one hole the linker has to fill: where it is in .text,
// which symbol it is against, and what the addend is. call says the reference is
// a call, which a linker may route through a stub, rather than a distance the
// code computes for itself.
struct ObjectRelocation {
	offset int
	symbol int
	addend i64
	call   bool
}

// object wraps a program in an ELF64 relocatable object that a linker can take
// as input.
pub fn object(program image.Program, target backend.Target) ![]u8 {
	// The symbols, in the order the table needs them: the functions this file
	// defines and the objects it defines, each sorted so that the same input
	// gives the same bytes every run, and then the imports in call order, which
	// the emitter already fixed.
	mut functions := program.defined.keys()
	functions.sort()
	mut objects := program.globals.keys()
	objects.sort()
	mut strtab := []u8{}
	strtab << u8(0)
	mut symbol_index := map[string]int{}
	mut name_offset := map[string]int{}
	mut symbol_count := first_global_symbol
	for name in functions {
		symbol_index[name] = symbol_count
		symbol_count++
		name_offset[name] = intern_name(mut strtab, name)
	}
	for name in objects {
		symbol_index[name] = symbol_count
		symbol_count++
		name_offset[name] = intern_name(mut strtab, name)
	}
	for name in program.imports {
		symbol_index[name] = symbol_count
		symbol_count++
		name_offset[name] = intern_name(mut strtab, name)
	}
	// The text, with the jumps inside it settled: both ends of a jump are in
	// .text, and .text is moved as a unit when it is linked, so the distance
	// between two places in it is the same afterwards as it is now. Those need
	// no relocation. Everything else does.
	mut text := program.text.clone()
	mut relocations := []ObjectRelocation{}
	for fixup in program.fixups {
		instruction := fixup.start
		// A relocation names the four bytes the linker writes into, which is the
		// field and not the instruction: the instruction's other bytes are an
		// opcode and its addressing form. Every reference the emitter writes
		// puts a four-byte field at the end of the instruction, so the field is
		// always the last four bytes of it.
		field := instruction + fixup.length - 4
		match fixup.kind {
			.call_local {
				symbol := symbol_index[fixup.name] or {
					return error('${fixup.name} is called but this object defines no such function')
				}
				relocations << ObjectRelocation{
					offset: field
					symbol: symbol
					addend: -4
					call:   true
				}
			}
			.call_import {
				symbol := symbol_index[fixup.name] or {
					return error('${fixup.name} is called but was never imported')
				}
				relocations << ObjectRelocation{
					offset: field
					symbol: symbol
					addend: -4
					call:   true
				}
			}
			.take_address, .float_constant, .single_constant {
				// A string and a floating constant are both read-only data at
				// an offset, so they are the same reference: .rodata at the
				// offset the emitter interned them at.
				where := if fixup.kind == .take_address {
					program.strings[fixup.name] or {
						return error('no string ${fixup.name} in the object')
					}
				} else {
					program.doubles[fixup.name] or {
						return error('no floating constant ${fixup.name} in the object')
					}
				}
				relocations << ObjectRelocation{
					offset: field
					symbol: symbol_rodata_section
					addend: i64(where) - 4
					call:   false
				}
			}
			.global_address, .function_address {
				symbol := symbol_index[fixup.name] or {
					return error('${fixup.name} is addressed but this object defines no such name')
				}
				relocations << ObjectRelocation{
					offset: field
					symbol: symbol
					addend: -4
					call:   false
				}
			}
			.jump_local, .branch_zero, .branch_nonzero {
				where := program.labels[fixup.name] or {
					return error('no code for ${fixup.name}')
				}
				disp := i32(where - (instruction + fixup.length))
				replacement := match fixup.kind {
					.jump_local { target.jump(disp) }
					.branch_zero { target.jump_if_zero(disp) }
					else { target.jump_if_not_zero(disp) }
				}
				if replacement.len != fixup.length {
					return error('the jump to ${fixup.name} was ${fixup.length} bytes and became ${replacement.len}')
				}
				put(mut text, instruction, replacement)
			}
		}
	}
	names, shstrtab := section_names()
	sizes := PartSizes{
		text:     text.len
		rodata:   program.string_blob.len
		data:     program.globals_blob.len
		rela:     relocations.len * elf_relocation_size
		symtab:   symbol_count * elf_symbol_size
		strtab:   strtab.len
		shstrtab: shstrtab.len
	}
	parts := place(sizes)
	mut output := []u8{len: parts.total, init: u8(0)}
	put(mut output, parts.text, text)
	put(mut output, parts.rodata, program.string_blob)
	put(mut output, parts.data, program.globals_blob)
	emit_object_relocations(mut output, parts, relocations, target)
	emit_object_symbols(mut output, parts, program, functions, objects, symbol_index,
		name_offset)
	put(mut output, parts.strtab, strtab)
	put(mut output, parts.shstrtab, shstrtab)
	emit_object_section_headers(mut output, parts, sizes, names)
	emit_object_header(mut output, target, parts)
	return output
}

// section_names builds .shstrtab and remembers where each name landed in it. The
// null byte comes first because offset zero has to mean no name.
fn section_names() (NameOffsets, []u8) {
	mut table := []u8{}
	table << u8(0)
	text := intern_name(mut table, '.text')
	rela := intern_name(mut table, '.rela.text')
	rodata := intern_name(mut table, '.rodata')
	data := intern_name(mut table, '.data')
	symtab := intern_name(mut table, '.symtab')
	strtab := intern_name(mut table, '.strtab')
	shstrtab := intern_name(mut table, '.shstrtab')
	gnu_stack := intern_name(mut table, '.note.GNU-stack')
	return NameOffsets{
		text:      text
		rela:      rela
		rodata:    rodata
		data:      data
		symtab:    symtab
		strtab:    strtab
		shstrtab:  shstrtab
		gnu_stack: gnu_stack
	}, table
}

// intern_name adds a name to a string table and answers where it starts.
fn intern_name(mut table []u8, name string) int {
	at := table.len
	table << name.bytes()
	table << u8(0)
	return at
}

// place puts every part of the object one after another at an eight-byte
// boundary. Nothing is rounded up to a page, because nothing here is mapped: the
// file is read by a linker and not by a kernel.
fn place(sizes PartSizes) PartOffsets {
	mut offset := int(elf_header_size)
	text := offset
	offset = align(offset + sizes.text, 8)
	rodata := offset
	offset = align(offset + sizes.rodata, 8)
	data := offset
	offset = align(offset + sizes.data, 8)
	rela := offset
	offset = align(offset + sizes.rela, 8)
	symtab := offset
	offset = align(offset + sizes.symtab, 8)
	strtab := offset
	offset = align(offset + sizes.strtab, 8)
	shstrtab := offset
	offset = align(offset + sizes.shstrtab, 8)
	headers := offset
	return PartOffsets{
		text:     text
		rodata:   rodata
		data:     data
		rela:     rela
		symtab:   symtab
		strtab:   strtab
		shstrtab: shstrtab
		headers:  headers
		total:    offset + section_count * elf_section_header_size
	}
}

// emit_object_relocations writes one relocation per hole: the place in .text,
// the symbol it is against packed together with the kind of reference it is, and
// the addend. The addend is -4 for every reference whose instruction reads the
// field as a distance from its own end, which is each of them here: the four
// bytes of the field are counted from the address after them, and for a
// reference to data the object's offset goes on top of that.
fn emit_object_relocations(mut output []u8, parts PartOffsets, relocations []ObjectRelocation, target backend.Target) {
	for i, relocation in relocations {
		at := parts.rela + i * elf_relocation_size
		kind := if relocation.call { target.call_relocation() } else { target.address_relocation() }
		put_u64(mut output, at, u64(relocation.offset))
		put_u64(mut output, at + 8, (u64(relocation.symbol) << 32) | u64(kind))
		put_u64(mut output, at + 16, u64(relocation.addend))
	}
}

// emit_object_symbols writes the static symbol table: the null entry the format
// requires, one entry per section a reference can be made against, and then what
// this object defines and what it needs. A function's value is where its code
// begins in .text, an object's is where its storage begins in .data, and an
// import has no value and no section, because its definition is somewhere this
// object is not.
fn emit_object_symbols(mut output []u8, parts PartOffsets, program image.Program, functions []string, objects []string, symbol_index map[string]int, name_offset map[string]int) {
	put_symbol(mut output, parts.symtab + symbol_text_section * elf_symbol_size, 0,
		symbol_local_section, section_text, 0, 0)
	put_symbol(mut output, parts.symtab + symbol_rodata_section * elf_symbol_size, 0,
		symbol_local_section, section_rodata, 0, 0)
	put_symbol(mut output, parts.symtab + symbol_data_section * elf_symbol_size, 0,
		symbol_local_section, section_data, 0, 0)
	for name in functions {
		at := parts.symtab + symbol_index[name] * elf_symbol_size
		where := program.labels[name] or { 0 }
		put_symbol(mut output, at, name_offset[name] or { 0 }, symbol_global_function,
			section_text, u64(where), 0)
	}
	for name in objects {
		at := parts.symtab + symbol_index[name] * elf_symbol_size
		slot := program.globals[name] or { image.GlobalSlot{} }
		// An object's size is one element wide, or as many elements as it was
		// defined with.
		width := if slot.count > 0 { slot.width * slot.count } else { slot.width }
		put_symbol(mut output, at, name_offset[name] or { 0 }, symbol_global_object,
			section_data, u64(slot.offset), u64(width))
	}
	for name in program.imports {
		at := parts.symtab + symbol_index[name] * elf_symbol_size
		put_symbol(mut output, at, name_offset[name] or { 0 }, symbol_global_function,
			shn_undef, 0, 0)
	}
}

// put_symbol writes one 24-byte symbol table entry.
fn put_symbol(mut output []u8, at int, name int, info u8, section u16, value u64, size u64) {
	put_u32(mut output, at, u32(name))
	output[at + 4] = info
	// st_other is the symbol's visibility, which is the default here.
	put_u16(mut output, at + 6, section)
	put_u64(mut output, at + 8, value)
	put_u64(mut output, at + 16, size)
}

// emit_object_section_headers writes the section header table, which a
// relocatable file needs and a program does not: a linker reads the sections it
// is told about, and there are no program headers to read instead.
fn emit_object_section_headers(mut output []u8, parts PartOffsets, sizes PartSizes, names NameOffsets) {
	// The null section is the whole of offset zero in the table, and the zeroes
	// the file was made of are what belongs there, so nothing is written.
	put_section_header(mut output, parts.headers + section_text * elf_section_header_size,
		names.text, sht_progbits, shf_alloc | shf_execinstr, parts.text, sizes.text,
		0, 0, 16, 0)
	put_section_header(mut output, parts.headers + section_rela_text * elf_section_header_size,
		names.rela, sht_rela, 0, parts.rela, sizes.rela,
		section_symtab, section_text, 8, elf_relocation_size)
	put_section_header(mut output, parts.headers + section_rodata * elf_section_header_size,
		names.rodata, sht_progbits, shf_alloc, parts.rodata, sizes.rodata,
		0, 0, 8, 0)
	put_section_header(mut output, parts.headers + section_data * elf_section_header_size,
		names.data, sht_progbits, shf_alloc | shf_write, parts.data, sizes.data,
		0, 0, 8, 0)
	put_section_header(mut output, parts.headers + section_symtab * elf_section_header_size,
		names.symtab, sht_symtab, 0, parts.symtab, sizes.symtab,
		section_strtab, first_global_symbol, 8, elf_symbol_size)
	put_section_header(mut output, parts.headers + section_strtab * elf_section_header_size,
		names.strtab, sht_strtab, 0, parts.strtab, sizes.strtab,
		0, 0, 1, 0)
	put_section_header(mut output, parts.headers + section_shstrtab * elf_section_header_size,
		names.shstrtab, sht_strtab, 0, parts.shstrtab, sizes.shstrtab,
		0, 0, 1, 0)
	put_section_header(mut output, parts.headers + section_gnu_stack * elf_section_header_size,
		names.gnu_stack, sht_progbits, 0, 0, 0, 0, 0, 1, 0)
}

fn put_section_header(mut output []u8, at int, name int, kind u32, flags u64, offset int, size int, link u32, info u32, alignment u64, entry_size u64) {
	put_u32(mut output, at, u32(name))
	put_u32(mut output, at + 4, kind)
	put_u64(mut output, at + 8, flags)
	put_u64(mut output, at + 16, 0) // no address: the linker decides those
	put_u64(mut output, at + 24, u64(offset))
	put_u64(mut output, at + 32, u64(size))
	put_u32(mut output, at + 40, link)
	put_u32(mut output, at + 44, info)
	put_u64(mut output, at + 48, alignment)
	put_u64(mut output, at + 56, entry_size)
}

// emit_object_header writes the ELF header. A relocatable file has no entry
// point, no program headers and no segment, so the three fields describing those
// say nothing, and the field that matters is where the section headers start.
fn emit_object_header(mut output []u8, target backend.Target, parts PartOffsets) {
	put(mut output, 0, elf_magic)
	output[4] = elf_class_64
	output[5] = elf_data_little_endian
	output[6] = elf_version_current
	// Byte 7 is the ABI, System V, and bytes 8 to 15 are its padding: the zeroes
	// the file was made of are what belongs there, so nothing is written.
	put_u16(mut output, 16, elf_type_rel)
	put_u16(mut output, 18, target.elf_machine)
	put_u32(mut output, 20, 1) // the container version, which is current
	put_u64(mut output, 24, 0) // no entry point
	put_u64(mut output, 32, 0) // no program headers
	put_u64(mut output, 40, u64(parts.headers))
	put_u32(mut output, 48, 0) // no architecture-specific flags
	put_u16(mut output, 52, elf_header_size)
	put_u16(mut output, 54, 0) // no program header size
	put_u16(mut output, 56, 0) // no program headers
	put_u16(mut output, 58, elf_section_header_size)
	put_u16(mut output, 60, section_count)
	put_u16(mut output, 62, section_shstrtab)
}
