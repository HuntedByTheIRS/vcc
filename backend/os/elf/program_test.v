module elf

import backend
import image
import os

// The executable container is checked the way the relocatable one is: a program
// built by hand and read back through the headers, because the questions worth
// pinning are about a relocation and a symbol that the emitter's whole output
// cannot show. A program has no section header table, so the values are found
// through the dynamic segment, which is what the loader reads; a test that went
// through sections would find nothing at all.
//
// V compiles each `_test.v` file on its own, so the byte readers and the target
// the relocatable-container tests use are defined again here rather than shared.

fn elf16_at(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn elf32_at(bytes []u8, at int) u32 {
	mut value := u32(0)
	for shift in [0, 8, 16, 24] {
		value |= u32(bytes[at + shift / 8]) << shift
	}
	return value
}

fn elf64_at(bytes []u8, at int) u64 {
	mut value := u64(0)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		value |= u64(bytes[at + shift / 8]) << shift
	}
	return value
}

fn host() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('no x86_64-linux target') }
}

// phdr_at is where one program header begins: after the ELF header, with the
// entry size the header gives.
fn phdr_at(bytes []u8, index int) int {
	return int(elf64_at(bytes, 32)) + index * int(elf16_at(bytes, 54))
}

// dynamic_offset and dynamic_size are where the PT_DYNAMIC segment is in the
// file and how long it is. There is no section header to name it, so the
// program header table is the only way to reach it.
fn dynamic_offset(bytes []u8) int {
	for i in 0 .. int(elf16_at(bytes, 56)) {
		at := phdr_at(bytes, i)
		if elf32_at(bytes, at) == elf_ph_type_dynamic {
			return int(elf64_at(bytes, at + 8))
		}
	}
	return 0
}

fn dynamic_size(bytes []u8) int {
	for i in 0 .. int(elf16_at(bytes, 56)) {
		at := phdr_at(bytes, i)
		if elf32_at(bytes, at) == elf_ph_type_dynamic {
			return int(elf64_at(bytes, at + 32))
		}
	}
	return 0
}

// ProgramTables is where the loader's tables are in the image, as file offsets.
// The addresses in the dynamic table are virtual addresses, and one segment maps
// the whole file at the load base, so subtracting the base gives the offset.
struct ProgramTables {
mut:
	strtab int
	symtab int
	hash   int
	rela   int
	relasz int
}

fn program_tables(bytes []u8, base u64) ProgramTables {
	offset := dynamic_offset(bytes)
	mut tables := ProgramTables{}
	for i in 0 .. dynamic_size(bytes) / elf_dynamic_entry_size {
		tag := elf64_at(bytes, offset + i * elf_dynamic_entry_size)
		value := elf64_at(bytes, offset + i * elf_dynamic_entry_size + 8)
		match tag {
			dt_hash { tables.hash = int(value - base) }
			dt_strtab { tables.strtab = int(value - base) }
			dt_symtab { tables.symtab = int(value - base) }
			dt_rela { tables.rela = int(value - base) }
			dt_relasz { tables.relasz = int(value) }
			else {}
		}
	}
	return tables
}

// dynamic_name reads one zero-terminated name out of the dynamic string table.
fn dynamic_name(bytes []u8, at int) string {
	mut end := at
	for bytes[end] != u8(0) {
		end++
	}
	return bytes[at..end].bytestr()
}

// ProgramSymbol is one entry of the dynamic symbol table, as the loader reads
// it: what it is, where its value is, and how big it is.
struct ProgramSymbol {
	index int
	info  u8
	value u64
	size  u64
	name  string
}

// symbol_of finds a symbol by name. There is no section header to say how many
// entries the table has, so the count comes from the hash table's chain length,
// which is the number of symbols in the dynamic table.
fn symbol_of(bytes []u8, tables ProgramTables, name string) ProgramSymbol {
	count := int(elf32_at(bytes, tables.hash + 4))
	for i in 1 .. count {
		at := tables.symtab + i * elf_symbol_size
		here := dynamic_name(bytes, tables.strtab + int(elf32_at(bytes, at)))
		if here == name {
			return ProgramSymbol{
				index: i
				info:  bytes[at + 4]
				value: elf64_at(bytes, at + 8)
				size:  elf64_at(bytes, at + 16)
				name:  here
			}
		}
	}
	return ProgramSymbol{}
}

// DynamicRelocation is one relocation out of .rela.dyn, read the way the loader
// reads it: the place it writes, the symbol it names, and its kind.
struct DynamicRelocation {
	offset u64
	kind   u64
	symbol int
	addend i64
}

fn relocation_of(bytes []u8, tables ProgramTables, kind u64) DynamicRelocation {
	for i in 0 .. tables.relasz / elf_relocation_size {
		at := tables.rela + i * elf_relocation_size
		info := elf64_at(bytes, at + 8)
		if info & 0xffffffff == kind {
			return DynamicRelocation{
				offset: elf64_at(bytes, at)
				kind:   info & 0xffffffff
				symbol: int(info >> 32)
				addend: i64(elf64_at(bytes, at + 16))
			}
		}
	}
	return DynamicRelocation{}
}

// hash_reaches says whether a name lookup walking the one-bucket chain from the
// bucket head arrives at the given symbol index. It is the property that lets a
// library's own reference to an object this image copies be resolved to this
// image's copy, and it is why the chain is filled instead of left empty.
fn hash_reaches(bytes []u8, tables ProgramTables, index int) bool {
	head := int(elf32_at(bytes, tables.hash + 8))
	mut walk := head
	mut steps := 0
	limit := int(elf32_at(bytes, tables.hash + 4)) + 1
	for walk != 0 && steps < limit {
		if walk == index {
			return true
		}
		walk = int(elf32_at(bytes, tables.hash + 8 + 4 + 4 * walk))
		steps++
	}
	return false
}

fn test_a_program_holds_a_copy_of_an_object_a_library_defines() {
	mut program := image.Program{}
	program.globals_blob = []u8{len: 24, init: u8(0)}
	program.globals['stdout'] = image.GlobalSlot{
		offset: 8
		width:  8
	}
	program.copy_objects << 'stdout'
	target := host()
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	tables := program_tables(bytes, target.load_base)
	symbol := symbol_of(bytes, tables, 'stdout')
	assert symbol.name == 'stdout'
	// The symbol is an object (type 1) whose size is the storage's, which is
	// what the loader copies.
	assert symbol.info & 0xf == 0x1
	assert symbol.size == 8
	assert symbol.value >= target.load_base
	// The relocation is a copy: the loader fills the storage this image holds
	// from the library's definition of the name.
	relocation := relocation_of(bytes, tables, relocation_copy)
	assert relocation.kind == relocation_copy
	assert relocation.symbol == symbol.index
	assert relocation.offset == symbol.value
	assert relocation.addend == 0
	// And the name is findable, so the library's references to it bind here.
	assert hash_reaches(bytes, tables, symbol.index)
}

fn test_a_copy_of_an_array_is_as_many_bytes_as_the_array_is_wide() {
	mut program := image.Program{}
	program.globals_blob = []u8{len: 32, init: u8(0)}
	program.globals['items'] = image.GlobalSlot{
		offset: 0
		width:  4
		count:  3
	}
	program.copy_objects << 'items'
	target := host()
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	tables := program_tables(bytes, target.load_base)
	symbol := symbol_of(bytes, tables, 'items')
	// Three four-byte elements are twelve bytes, and that is how many the
	// loader copies: the size is the whole storage and not one element.
	assert symbol.size == 12
	relocation := relocation_of(bytes, tables, relocation_copy)
	assert relocation.symbol == symbol.index
}

fn test_a_program_that_defines_its_own_objects_has_no_copy_relocation() {
	mut program := image.Program{}
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['counter'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	target := host()
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	tables := program_tables(bytes, target.load_base)
	// A program that copies nothing asks the loader for nothing, so there is no
	// copy relocation in it.
	assert relocation_of(bytes, tables, relocation_copy).kind == 0
}

// slot_at reads the eight bytes of an import's global offset table slot. The
// slot is at the import's position in `imports`, and the table sits just before
// the relocation section: every slot is eight bytes and both sections are
// eight-byte aligned, so the section begins one slot past the last import. The
// index here is a position in `imports`, which is the number a call's fixup was
// written against and not a dynamic symbol index.
fn slot_at(bytes []u8, tables ProgramTables, import_count int, index int) u64 {
	return elf64_at(bytes, tables.rela - import_count * 8 + index * 8)
}

// A name whose definition the link resolved inside this image is called through
// a slot like a library function, but nothing outside the image answers for it.
// The slot has to hold the definition's own address and the name has to be
// absent from the dynamic table, while the library import beside it keeps both
// its entry and its relocation. The library's symbol index is the one thing this
// test is here to pin: with the bound name gone from the table, the library's
// index is one and its position in `imports` is two, so a relocation that named
// the position would point at the wrong place.
fn test_a_bound_name_gets_no_symbol_and_its_slot_holds_the_definition() {
	mut program := image.Program{}
	program.text = []u8{len: 16, init: u8(0x90)}
	program.imports << 'bound_fn'
	program.imports << 'library_fn'
	program.bound['bound_fn'] = image.Definition{
		offset:   0
		function: true
	}
	target := host()
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	tables := program_tables(bytes, target.load_base)
	// The dynamic table holds the null symbol and the one library import: the
	// bound name is not in it and is not counted by the hash chain.
	assert elf32_at(bytes, tables.hash + 4) == 2
	assert symbol_of(bytes, tables, 'bound_fn').index == 0
	// The library name keeps its entry, and its index is one rather than its
	// position in `imports`, which is two.
	library := symbol_of(bytes, tables, 'library_fn')
	assert library.name == 'library_fn'
	assert library.index == 1
	assert library.info & 0xf == 0x2
	// The relocation still names that entry, and it is the only relocation.
	relocation := relocation_of(bytes, tables, relocation_glob_dat)
	assert relocation.kind == relocation_glob_dat
	assert relocation.symbol == library.index
	assert tables.relasz == elf_relocation_size
	// The bound name's slot holds the definition's address, which is the entry
	// point plus the definition's offset into the code. The entry point is the
	// start of the text at the load base.
	assert slot_at(bytes, tables, program.imports.len, 0) == elf64_at(bytes, 24)
	// The library's slot is left at zero for the loader to fill.
	assert slot_at(bytes, tables, program.imports.len, 1) == 0
}

// A program whose every import the link resolved inside this image asks the
// loader for nothing: no dynamic symbol beyond the null one, no relocation at
// all, and a relocation section the dynamic table declares as empty. The slot
// still exists, because a call reads it, and it holds the definition's address.
fn test_a_program_whose_only_import_is_bound_has_no_relocation() {
	mut program := image.Program{}
	program.text = []u8{len: 16, init: u8(0x90)}
	program.imports << 'bound_fn'
	program.bound['bound_fn'] = image.Definition{
		offset:   4
		function: true
	}
	target := host()
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	tables := program_tables(bytes, target.load_base)
	assert elf32_at(bytes, tables.hash + 4) == 1
	assert symbol_of(bytes, tables, 'bound_fn').index == 0
	assert tables.relasz == 0
	assert relocation_of(bytes, tables, relocation_glob_dat).kind == 0
	// The slot exists and holds the code's start plus the definition's offset.
	assert slot_at(bytes, tables, program.imports.len, 0) == elf64_at(bytes, 24) + 4
}

// The layout with a bound name has to produce an image the kernel starts, not
// only one whose bytes read correctly. The text comes from the target's own
// encoders, the way the emitter composes it, and the bound name is one whose
// code is never called: laying its slot out must not disturb the program that
// runs. The exit status is the code the sequence was asked for.
fn test_a_program_with_a_bound_name_runs() {
	target := host()
	code := target.exit_sequence(42) or { panic('the target has no exit sequence: ${err.msg()}') }
	mut program := image.Program{}
	program.text = code
	program.imports << 'never_called'
	program.bound['never_called'] = image.Definition{
		offset:   0
		function: true
	}
	bytes := executable(program, target) or { panic('the program was not written: ${err.msg()}') }
	path := os.join_path(os.temp_dir(), 'vcc_elf_bound_${os.getpid()}')
	os.write_file_array(path, bytes) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	assert result.exit_code == 42
}
