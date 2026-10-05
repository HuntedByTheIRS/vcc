module elf

import backend
import image
import os

// The three output kinds are checked the same way the dynamic program is: a
// Program built by hand and read back through the headers, because the questions
// worth pinning are about a header, a symbol and a relocation that the emitter's
// whole output cannot show, and about a program the kernel can actually start.
// V compiles each `_test.v` file on its own, so the byte readers here are
// defined again under names this file owns rather than shared with the others.

fn se16(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn se32(bytes []u8, at int) u32 {
	mut value := u32(0)
	for shift in [0, 8, 16, 24] {
		value |= u32(bytes[at + shift / 8]) << shift
	}
	return value
}

fn se64(bytes []u8, at int) u64 {
	mut value := u64(0)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		value |= u64(bytes[at + shift / 8]) << shift
	}
	return value
}

fn se_target() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('no x86_64-linux target') }
}

// se_phdr_at is where one program header begins: after the ELF header, with the
// entry size the header gives.
fn se_phdr_at(bytes []u8, index int) int {
	return int(se64(bytes, 32)) + index * int(se16(bytes, 54))
}

// se_dynamic_offset and se_dynamic_size reach the PT_DYNAMIC segment through the
// program header table, which is the only map a program has.
fn se_dynamic_offset(bytes []u8) int {
	for i in 0 .. int(se16(bytes, 56)) {
		at := se_phdr_at(bytes, i)
		if se32(bytes, at) == elf_ph_type_dynamic {
			return int(se64(bytes, at + 8))
		}
	}
	return 0
}

fn se_dynamic_size(bytes []u8) int {
	for i in 0 .. int(se16(bytes, 56)) {
		at := se_phdr_at(bytes, i)
		if se32(bytes, at) == elf_ph_type_dynamic {
			return int(se64(bytes, at + 32))
		}
	}
	return 0
}

fn se_has_interp(bytes []u8) bool {
	for i in 0 .. int(se16(bytes, 56)) {
		if se32(bytes, se_phdr_at(bytes, i)) == elf_ph_type_interp {
			return true
		}
	}
	return false
}

fn se_needed_count(bytes []u8) int {
	offset := se_dynamic_offset(bytes)
	mut count := 0
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		if se64(bytes, offset + i * elf_dynamic_entry_size) == dt_needed {
			count++
		}
	}
	return count
}

// SeTables is where the loader's tables are in the image, as file offsets. A
// shared object's dynamic addresses are file offsets already, so the base it is
// read with is zero.
struct SeTables {
mut:
	strtab int
	symtab int
	hash   int
	rela   int
	relasz int
}

fn se_tables(bytes []u8, base u64) SeTables {
	offset := se_dynamic_offset(bytes)
	mut tables := SeTables{}
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		tag := se64(bytes, offset + i * elf_dynamic_entry_size)
		value := se64(bytes, offset + i * elf_dynamic_entry_size + 8)
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

fn se_name(bytes []u8, at int) string {
	mut end := at
	for bytes[end] != u8(0) {
		end++
	}
	return bytes[at..end].bytestr()
}

struct SeSymbol {
	index int
	info  u8
	value u64
	size  u64
	name  string
}

// se_symbol_of finds a dynamic symbol by name. There is no section header to say
// how many entries the table has, so the count comes from the hash table's chain
// length, which is the number of symbols in the table.
fn se_symbol_of(bytes []u8, tables SeTables, name string) SeSymbol {
	count := int(se32(bytes, tables.hash + 4))
	for i in 1 .. count {
		at := tables.symtab + i * elf_symbol_size
		here := se_name(bytes, tables.strtab + int(se32(bytes, at)))
		if here == name {
			return SeSymbol{
				index: i
				info:  bytes[at + 4]
				value: se64(bytes, at + 8)
				size:  se64(bytes, at + 16)
				name:  here
			}
		}
	}
	return SeSymbol{}
}

struct SeRelocation {
	offset u64
	info   u64
	addend i64
}

fn se_relative_relocation(bytes []u8, tables SeTables) SeRelocation {
	for i in 0 .. tables.relasz / elf_relocation_size {
		at := tables.rela + i * elf_relocation_size
		info := se64(bytes, at + 8)
		if info & 0xffffffff == relocation_relative {
			return SeRelocation{
				offset: se64(bytes, at)
				info:   info
				addend: i64(se64(bytes, at + 16))
			}
		}
	}
	return SeRelocation{}
}

// A static program is one the kernel starts with no loader: no interpreter
// header, no library named, and every address settled here. The stub the import
// is reached through is laid out the same way as a dynamic program's, and the
// program has to run: the exit status is the one the code was asked for.
fn test_a_static_program_is_an_exec_with_no_interpreter_and_no_library() {
	target := se_target()
	code := target.exit_sequence(7) or { panic('the target has no exit sequence: ${err.msg()}') }
	mut program := image.Program{}
	program.text = code
	program.imports << 'entry'
	program.bound['entry'] = image.Definition{
		offset:   0
		function: true
	}
	program.plts << 'entry'
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	assert se16(bytes, 16) == elf_type_exec
	assert !se_has_interp(bytes)
	assert se_needed_count(bytes) == 0
	path := os.join_path(os.temp_dir(), 'vcc_elf_static_${os.getpid()}')
	os.write_file_array(path, bytes) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	assert result.exit_code == 7
}

// A static link resolves its libraries into the file it writes. A name still
// left to a library is one this link cannot place, and the diagnostic has to
// name it rather than write a file that would start with the name's address
// zero.
fn test_a_static_program_left_to_a_library_is_refused() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0x90)}
	program.imports << 'puts'
	write(program, target, .static_program) or {
		assert err.msg().contains('puts')
		return
	}
	assert false, 'a static program was written with puts left to a library'
}

// A shared object is a file another program loads: the header says ET_DYN, there
// is no interpreter and no entry point, and the names this image defines are
// exported in the dynamic symbol table, each at the file offset of its
// definition. An import whose definition is inside the image has its slot filled
// with the offset and an R_X86_64_RELATIVE entry beside it, because where the
// object goes is the loader's to choose. Both are pinned here: the slot holds the
// same offset the relocation's addend carries.
fn test_a_shared_object_is_dynamic_and_exports_what_it_defines() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 16, init: u8(0)}
	program.text[4] = u8(0xab)
	program.defined['exported_fn'] = true
	program.labels['exported_fn'] = 4
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['exported_obj'] = image.GlobalSlot{
		offset: 0
		width:  4
		count:  2
	}
	program.imports << 'bound_fn'
	program.bound['bound_fn'] = image.Definition{
		offset:   4
		function: true
	}
	bytes := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	assert se16(bytes, 16) == elf_type_dyn
	assert !se_has_interp(bytes)
	assert se64(bytes, 24) == 0 // no entry point
	tables := se_tables(bytes, 0)
	// The function is exported as a function, and its value is the file offset
	// the label named: the byte there is the one the text holds at offset four.
	exported := se_symbol_of(bytes, tables, 'exported_fn')
	assert exported.name == 'exported_fn'
	assert exported.info & 0xf == 0x2
	assert bytes[int(exported.value)] == u8(0xab)
	// The object is exported as an object, and its size is its whole storage:
	// two four-byte elements.
	object := se_symbol_of(bytes, tables, 'exported_obj')
	assert object.name == 'exported_obj'
	assert object.info & 0xf == 0x1
	assert object.size == 8
	// The bound import's slot is an address that points into the image, so it is
	// an offset beside a relocation that adds the load base, and the offset is
	// the definition's: the same place the exported function's label named.
	relative := se_relative_relocation(bytes, tables)
	assert relative.info & 0xffffffff == relocation_relative
	assert relative.addend == i64(exported.value)
	assert se64(bytes, int(relative.offset)) == u64(relative.addend)
}

// A copy relocation asks a loader to copy a library's object into this image's
// storage, which is a non-position-independent executable's shape and not a
// shared object's. The refusal names the object.
fn test_a_shared_object_that_would_copy_a_library_object_is_refused() {
	target := se_target()
	mut program := image.Program{}
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['stdout'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.copy_objects << 'stdout'
	write(program, target, .shared) or {
		assert err.msg().contains('stdout')
		return
	}
	assert false, 'a shared object was written with a copy relocation'
}

// The same Program has to write the same bytes every run, and the two symbol
// sets a shared object exports are maps, whose order is not the program's. The
// exports are sorted, so the index of `a` is below the index of `b` however the
// maps were built, and the two writes are compared byte for byte.
fn test_a_shared_object_is_the_same_every_run() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0x90)}
	program.string_blob = []u8{len: 8, init: u8(0)}
	program.strings['s'] = 0
	program.globals_blob = []u8{len: 16, init: u8(0)}
	program.globals['a'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.globals['b'] = image.GlobalSlot{
		offset: 8
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .take_address
		name:   's'
	}
	first := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	second := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	assert first == second
	tables := se_tables(first, 0)
	assert se_symbol_of(first, tables, 'a').index < se_symbol_of(first, tables, 'b').index
}
