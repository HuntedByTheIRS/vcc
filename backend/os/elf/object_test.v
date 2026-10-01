module elf

import backend
import image

// The relocatable container is checked against a program built by hand rather
// than one the emitter produced, because the properties worth pinning are ones
// the emitter's own output cannot show: where a relocation points, what it is
// against, and what an object deliberately does not contain. A program the
// emitter wrote would make the test depend on the whole front end to ask a
// question about a section header.

// The bytes a test asks about, read back out of the object the way a linker
// would: through the header, and then through the section header table.

fn u16_at(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn u32_at(bytes []u8, at int) u32 {
	mut value := u32(0)
	for shift in [0, 8, 16, 24] {
		value |= u32(bytes[at + shift / 8]) << shift
	}
	return value
}

fn u64_at(bytes []u8, at int) u64 {
	mut value := u64(0)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		value |= u64(bytes[at + shift / 8]) << shift
	}
	return value
}

fn section_header_at(bytes []u8, index int) int {
	return int(u64_at(bytes, 40)) + index * elf_section_header_size
}

fn section_offset(bytes []u8, index int) int {
	return int(u64_at(bytes, section_header_at(bytes, index) + 24))
}

fn section_size(bytes []u8, index int) int {
	return int(u64_at(bytes, section_header_at(bytes, index) + 32))
}

// relocation_offset, relocation_symbol and relocation_addend read one entry of
// the relocation table the way a linker does.
fn relocation_offset(bytes []u8, index int) u64 {
	at := section_offset(bytes, section_rela_text) + index * elf_relocation_size
	return u64_at(bytes, at)
}

fn relocation_info(bytes []u8, index int) u64 {
	at := section_offset(bytes, section_rela_text) + index * elf_relocation_size
	return u64_at(bytes, at + 8)
}

fn relocation_addend(bytes []u8, index int) i64 {
	at := section_offset(bytes, section_rela_text) + index * elf_relocation_size
	return i64(u64_at(bytes, at + 16))
}

fn relocation_count(bytes []u8) int {
	return section_size(bytes, section_rela_text) / elf_relocation_size
}

fn symbol_entry_at(bytes []u8, index int) int {
	return section_offset(bytes, section_symtab) + index * elf_symbol_size
}

fn x86_64() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('no x86_64-linux target') }
}

// one_call is a translation unit with a single function that calls another one
// in the same file: five bytes of call, then the callee.
fn one_call() image.Program {
	mut program := image.Program{}
	program.text = [u8(0xe8), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.defined['callee'] = true
	program.labels['callee'] = 5
	program.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_local
		name:   'callee'
	}
	return program
}

fn test_the_object_is_a_relocatable_file_and_not_a_program() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert bytes.len > int(elf_header_size)
	assert bytes[0..4] == elf_magic
	assert bytes[4] == elf_class_64
	assert bytes[5] == elf_data_little_endian
	// A relocatable file, which is the whole difference from the other container
	// this module writes: no entry point, no program headers, nothing to map.
	assert u16_at(bytes, 16) == elf_type_rel
	assert u16_at(bytes, 18) == 62 // EM_X86_64, from the target
	assert u64_at(bytes, 24) == 0 // no entry point
	assert u64_at(bytes, 32) == 0 // no program header table
	assert u64_at(bytes, 40) != 0 // and a section header table instead
	assert u16_at(bytes, 54) == 0 // no program header size
	assert u16_at(bytes, 56) == 0 // no program headers
	assert u16_at(bytes, 58) == elf_section_header_size
	assert u16_at(bytes, 60) == section_count
	assert u16_at(bytes, 62) == section_shstrtab
}

fn test_a_relocation_points_at_the_field_and_not_at_the_instruction() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert relocation_count(bytes) == 1
	// The instruction begins at zero and is five bytes, so the four bytes the
	// linker writes are at one. A relocation at zero overwrites the opcode, and
	// the linker writes a number where the call's opcode was.
	assert relocation_offset(bytes, 0) == 1
	// The symbol is `callee`, which sits after the null entry and the three
	// section symbols, and the addend is -4 for every reference measured from
	// the end of its own field.
	info := relocation_info(bytes, 0)
	assert u32(info >> 32) == first_global_symbol
	assert u32(info & 0xffffffff) == x86_64().call_relocation()
	assert relocation_addend(bytes, 0) == -4
}

fn test_the_symbol_table_puts_every_local_before_the_first_global() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	// The table says where the locals stop, and the three section symbols are
	// the locals it has.
	assert u32_at(bytes, section_header_at(bytes, section_symtab) + 44) == first_global_symbol
	for index in [symbol_text_section, symbol_rodata_section, symbol_data_section] {
		assert bytes[symbol_entry_at(bytes, index) + 4] == symbol_local_section
	}
	callee := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[callee + 4] == symbol_global_function
	assert u16_at(bytes, callee + 6) == section_text
	// The function's value is where its code begins in .text.
	assert u64_at(bytes, callee + 8) == 5
}

fn test_a_reference_to_a_string_is_against_the_read_only_section() {
	mut program := one_call()
	// Eight bytes of string, and a reference to the second one.
	program.string_blob = [u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), `h`, `i`]
	program.strings['hi'] = 8
	program.fixups << image.Fixup{
		start:    5
		length:   5
		kind:     .take_address
		name:     'hi'
		register: 'eax'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert relocation_count(bytes) == 2
	// The string is not a symbol of its own, so the reference is against the
	// section it lives in at the offset the emitter interned it at, and the -4
	// is the same distance from the end of the field.
	assert u32(relocation_info(bytes, 1) >> 32) == symbol_rodata_section
	assert u32(relocation_info(bytes, 1) & 0xffffffff) == x86_64().address_relocation()
	assert relocation_addend(bytes, 1) == 4 // 8 - 4
	// And the second instruction is five bytes long, so its field is at 6.
	assert relocation_offset(bytes, 1) == 6
}

fn test_a_jump_inside_the_text_needs_no_relocation() {
	mut program := image.Program{}
	// A jump forward over one byte, and the label it goes to.
	program.text = [u8(0xe9), u8(0), u8(0), u8(0), u8(0), u8(0x90), u8(0xc3)]
	program.labels['end'] = 6
	program.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .jump_local
		name:   'end'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	// Both ends of the jump are in .text, and .text is moved as a unit when it
	// is linked, so the distance is settled here and a linker has nothing to do.
	assert relocation_count(bytes) == 0
	text := section_offset(bytes, section_text)
	assert bytes[text] == 0xe9
	assert i32(u32_at(bytes, text + 1)) == 1 // 6 - (0 + 5)
}

fn test_a_definition_this_object_does_not_have_is_left_undefined() {
	mut program := image.Program{}
	program.text = [u8(0xe8), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.imports << 'puts'
	program.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_import
		name:   'puts'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert relocation_count(bytes) == 1
	// Its value is nothing and its section is nothing, because the definition is
	// somewhere this object is not; that is what makes it something to link.
	puts := symbol_entry_at(bytes, first_global_symbol)
	assert u16_at(bytes, puts + 6) == shn_undef
	assert u64_at(bytes, puts + 8) == 0
	// A call to it is a call to a symbol, which is what a linker can route.
	assert u32(relocation_info(bytes, 0) & 0xffffffff) == x86_64().call_relocation()
}

fn test_a_reference_with_no_symbol_behind_it_is_refused() {
	mut program := image.Program{}
	program.text = [u8(0xe8), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_import
		name:   'nowhere'
	}
	// An object that named a symbol it never declared would produce a file whose
	// relocation a linker cannot resolve, and a diagnostic is better than a file
	// that fails at link time with nothing pointing at the cause.
	if _ := object(program, x86_64()) {
		assert false, 'an object was written for a call to a symbol that was never imported'
	}
}
