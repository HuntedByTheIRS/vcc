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

// A wide string is the same reference against the same section, read out of the
// wide table rather than the narrow one. The two tables hold one key at
// different offsets, so an answer taken from the wrong table is visible: the
// addend is the wide entry's offset and not the narrow one's.
fn test_a_reference_to_a_wide_string_is_read_from_the_wide_table() {
	mut program := one_call()
	program.string_blob = []u8{len: 16, init: u8(0)}
	program.strings['same'] = 0
	program.wide_strings['same'] = 8
	program.fixups << image.Fixup{
		start:    5
		length:   5
		kind:     .take_wide_address
		name:     'same'
		register: 'eax'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert relocation_count(bytes) == 2
	assert u32(relocation_info(bytes, 1) >> 32) == symbol_rodata_section
	assert relocation_addend(bytes, 1) == 4 // 8 - 4, the wide entry and not 0 - 4
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

// A position-independent object reaches an object another object may define
// through the global offset table: the instruction loads the address out of a
// table entry the linker builds rather than computing the distance to the
// object itself, and that distance is the relocation a shared link refuses.
// Measured on gcc 16.2.1 with -fPIC -c, which writes R_X86_64_REX_GOTPCRELX
// (42) where a plain compile writes R_X86_64_PC32 (2) for the same source.
fn test_a_reference_through_the_global_offset_table_is_its_own_relocation() {
	mut program := image.Program{}
	program.text = [u8(0x48), u8(0x8b), u8(0x05), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.globals['counter'] = image.GlobalSlot{
		offset: 0
		width:  4
	}
	program.fixups << image.Fixup{
		start:    0
		length:   7
		kind:     .got_address
		name:     'counter'
		register: 'rax'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert relocation_count(bytes) == 1
	// The field is the four bytes at the end of the instruction and the addend
	// is what a linker expects for a displacement it writes into them.
	assert relocation_offset(bytes, 0) == 3
	assert u32(relocation_info(bytes, 0) & 0xffffffff) == x86_64().got_relocation()
	// The object is defined here, so the entry before the first global is not
	// where its symbol sits: the one object is the first global.
	assert u32(relocation_info(bytes, 0) >> 32) == first_global_symbol
	assert relocation_addend(bytes, 0) == -4
	assert u16_at(bytes, symbol_entry_at(bytes, first_global_symbol) + 6) == section_data
}

// An object with internal linkage is a local symbol and keeps the direct
// reference: no other object can define the name, so there is nothing for the
// linker to interpose and the table would name a fact the code already has. The
// table has to say where the locals stop, and it stops after this one.
fn test_an_object_with_internal_linkage_is_a_local_symbol() {
	mut program := image.Program{}
	program.text = [u8(0x48), u8(0x8d), u8(0x05), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.globals['hidden'] = image.GlobalSlot{
		offset: 0
		width:  4
	}
	program.internal['hidden'] = true
	program.fixups << image.Fixup{
		start:    0
		length:   7
		kind:     .global_address
		name:     'hidden'
		register: 'rax'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	entry := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[entry + 4] == symbol_local_object
	assert u16_at(bytes, entry + 6) == section_data
	assert u32_at(bytes, section_header_at(bytes, section_symtab) + 44) == first_global_symbol + 1
	assert relocation_count(bytes) == 1
	assert u32(relocation_info(bytes, 0) & 0xffffffff) == x86_64().address_relocation()
}

// An object another object defines is an undefined symbol with the object type
// rather than the function type: a reference through the table is a reference
// to storage, and a reader that took the symbol for code would call it.
fn test_an_imported_object_is_an_undefined_symbol_of_the_object_type() {
	mut program := image.Program{}
	program.text = [u8(0x48), u8(0x8b), u8(0x05), u8(0), u8(0), u8(0), u8(0), u8(0xc3)]
	program.imports << 'counter'
	program.object_imports['counter'] = true
	program.fixups << image.Fixup{
		start:    0
		length:   7
		kind:     .got_address
		name:     'counter'
		register: 'rax'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	entry := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[entry + 4] == symbol_global_object
	assert u16_at(bytes, entry + 6) == shn_undef
	assert u64_at(bytes, entry + 8) == 0
	assert relocation_count(bytes) == 1
	assert u32(relocation_info(bytes, 0) & 0xffffffff) == x86_64().got_relocation()
}

// The relocations against the writable data live in a table of their own, and
// these read one entry out of it the way a linker does.

fn data_relocation_offset(bytes []u8, index int) u64 {
	at := section_offset(bytes, section_rela_data) + index * elf_relocation_size
	return u64_at(bytes, at)
}

fn data_relocation_info(bytes []u8, index int) u64 {
	at := section_offset(bytes, section_rela_data) + index * elf_relocation_size
	return u64_at(bytes, at + 8)
}

fn data_relocation_addend(bytes []u8, index int) i64 {
	at := section_offset(bytes, section_rela_data) + index * elf_relocation_size
	return i64(u64_at(bytes, at + 16))
}

fn data_relocation_count(bytes []u8) int {
	return section_size(bytes, section_rela_data) / elf_relocation_size
}

// A top-level pointer whose value is a function's address is eight bytes of
// .data, and the bytes are zero in a relocatable file because there are no
// addresses yet: the relocation names the function and the linker writes its
// value in. The addend is zero, because the value is the address itself.
fn test_a_pointer_to_a_function_is_a_data_relocation_against_it() {
	mut program := image.Program{}
	program.defined['inc'] = true
	program.labels['inc'] = 0
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['fp'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .function_address
		name:   'inc'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert data_relocation_count(bytes) == 1
	assert data_relocation_offset(bytes, 0) == 0
	// `inc` is the first function this object defines, so it is the first
	// global symbol in the table.
	info := data_relocation_info(bytes, 0)
	assert u32(info >> 32) == first_global_symbol
	// The reference is an address rather than a distance, so the relocation is
	// the absolute R_X86_64_64 rather than the PC-relative one the code uses.
	assert u32(info & 0xffffffff) == u32(relocation_absolute)
	assert data_relocation_addend(bytes, 0) == 0
}

// A pointer to a string is against the read-only section at the offset the
// emitter interned the literal at, which is the same reference a `take_address`
// in the code is.
fn test_a_pointer_to_a_string_is_against_the_read_only_section() {
	mut program := image.Program{}
	program.string_blob = []u8{len: 8, init: u8(0)}
	program.strings['hi'] = 0
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['s'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .take_address
		name:   'hi'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert data_relocation_count(bytes) == 1
	assert u32(data_relocation_info(bytes, 0) >> 32) == symbol_rodata_section
	// The addend is the string's own offset and not the -4 a distance would
	// carry, because the value is an address and not a displacement.
	assert data_relocation_addend(bytes, 0) == 0
}

// A pointer to a function the loader resolves is against the undefined symbol,
// so a linker carries it through the way it carries a call to that function.
fn test_a_pointer_to_an_import_is_against_that_symbol() {
	mut program := image.Program{}
	program.imports << 'puts'
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['fp'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .import_address
		name:   'puts'
	}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	assert data_relocation_count(bytes) == 1
	// `fp` is the object this file defines, at the first global index, and the
	// import comes after it: puts is the symbol at first_global_symbol + 1.
	puts := symbol_entry_at(bytes, first_global_symbol + 1)
	assert u16_at(bytes, puts + 6) == shn_undef
	assert u32(data_relocation_info(bytes, 0) >> 32) == first_global_symbol + 1
	assert data_relocation_addend(bytes, 0) == 0
}

// A data relocation this object cannot carry is refused rather than written as
// something a linker would resolve to a wrong address.
fn test_a_data_reference_this_object_cannot_carry_is_refused() {
	mut program := image.Program{}
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['fp'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .call_local
		name:   'inc'
	}
	if _ := object(program, x86_64()) {
		assert false, 'an object was written for a data reference that is not an address'
	}
}

// A definition whose declaration asked for the weak binding carries it into the
// object's symbol table: st_info says WEAK where a plain definition says GLOBAL.
// It is what `__attribute__((weak))` asks for, and what a linker reads when it
// decides which of two definitions of a name to take.
fn test_a_weak_definition_is_weak_in_the_symbol_table() {
	mut program := one_call()
	program.weak['callee'] = true
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	callee := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[callee + 4] == symbol_weak_function
	// The rest of the entry is the same: the same name, the same section, the
	// same value. Only the binding changed.
	assert u16_at(bytes, callee + 6) == section_text
	assert u64_at(bytes, callee + 8) == 5
}

// A definition with internal linkage is a local symbol, and the format wants
// every local before every global, so it stands with the section symbols ahead
// of where a linker starts reading globals. That is what keeps two translation
// units from meeting over a name each defines with `static` (6.2.2p3): a local
// symbol is this object's own and a linker never resolves it against another.
fn test_a_static_definition_is_a_local_symbol() {
	mut program := one_call()
	program.internal['callee'] = true
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	// The null entry and the three section symbols come first; the static
	// function is the next local.
	callee := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[callee + 4] == symbol_local_function
	assert u16_at(bytes, callee + 6) == section_text
	assert u64_at(bytes, callee + 8) == 5
	// It is a local, so the first global is one past it, and the table says so.
	assert u32_at(bytes, section_header_at(bytes, section_symtab) + 44) == first_global_symbol + 1
	// A call to it is still a relocation against this symbol: the reference to
	// a local definition is resolved inside the object.
	assert u32(relocation_info(bytes, 0) >> 32) == first_global_symbol
}

// A static object is the same answer with the object type in the low nibble,
// which is the pair that tells the two local definitions apart.
fn test_a_static_object_is_a_local_symbol() {
	mut program := image.Program{}
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['keep'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.internal['keep'] = true
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	keep := symbol_entry_at(bytes, first_global_symbol)
	assert bytes[keep + 4] == symbol_local_object
	assert u16_at(bytes, keep + 6) == section_data
	assert u64_at(bytes, keep + 8) == 0
	assert u32_at(bytes, section_header_at(bytes, section_symtab) + 44) == first_global_symbol + 1
}

// name_at reads a null-terminated name out of a string table the way a linker
// does, so a test can check that a table holds the name an offset points at.
fn name_at(bytes []u8, at int) string {
	mut end := at
	for end < bytes.len && bytes[end] != 0 {
		end++
	}
	return bytes[at..end].bytestr()
}

// The section header table is the last thing in the file and the only map a
// relocatable file has: there is no program header table, so the three fields
// that would place one say nothing, and the file ends where the table ends. The
// null section comes first and every byte of it is zero.
fn test_the_section_header_table_ends_the_file_and_its_null_entry_is_zero() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	headers := int(u64_at(bytes, 40))
	assert headers > 0
	assert headers % 8 == 0
	assert headers + section_count * elf_section_header_size == bytes.len
	assert u16_at(bytes, 60) == section_count
	for i in 0 .. elf_section_header_size {
		assert bytes[headers + i] == 0
	}
	assert u64_at(bytes, 32) == 0 // no program header table
	assert u16_at(bytes, 54) == 0 // and no entry size for one
	assert u16_at(bytes, 56) == 0 // and no count of one
}

// The three sections that hold the program carry the flags a linker maps them by
// and the alignment it places them at. Code is allocated and executable and
// aligned to sixteen, read-only data is allocated and aligned to eight, and
// writable data adds the write flag. The code the .text header names is the
// program's text byte for byte.
fn test_the_program_sections_carry_their_flags_and_alignment() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	text := section_header_at(bytes, section_text)
	assert u32_at(bytes, text + 4) == sht_progbits
	assert u64_at(bytes, text + 8) == shf_alloc | shf_execinstr
	assert u64_at(bytes, text + 16) == 0 // no address: the linker decides those
	assert u64_at(bytes, text + 48) == 16
	assert u64_at(bytes, text + 56) == 0
	rodata := section_header_at(bytes, section_rodata)
	assert u32_at(bytes, rodata + 4) == sht_progbits
	assert u64_at(bytes, rodata + 8) == shf_alloc
	assert u64_at(bytes, rodata + 48) == 8
	assert u64_at(bytes, rodata + 56) == 0
	data := section_header_at(bytes, section_data)
	assert u32_at(bytes, data + 4) == sht_progbits
	assert u64_at(bytes, data + 8) == shf_alloc | shf_write
	assert u64_at(bytes, data + 48) == 8
	assert u64_at(bytes, data + 56) == 0
	offset := section_offset(bytes, section_text)
	size := section_size(bytes, section_text)
	assert bytes[offset..offset + size] == one_call().text
}

// Both relocation sections are of the RELA kind the format defines for an
// explicit addend, and each names the symbol table it is resolved against and
// the section it relocates. The entry size is the format's own twenty-four bytes.
fn test_the_relocation_sections_name_their_symbol_table_and_target_section() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	rela_text := section_header_at(bytes, section_rela_text)
	assert u32_at(bytes, rela_text + 4) == sht_rela
	assert u64_at(bytes, rela_text + 8) == 0
	assert u32_at(bytes, rela_text + 40) == section_symtab
	assert u32_at(bytes, rela_text + 44) == section_text
	assert u64_at(bytes, rela_text + 48) == 8
	assert u64_at(bytes, rela_text + 56) == elf_relocation_size
	rela_data := section_header_at(bytes, section_rela_data)
	assert u32_at(bytes, rela_data + 4) == sht_rela
	assert u32_at(bytes, rela_data + 40) == section_symtab
	assert u32_at(bytes, rela_data + 44) == section_data
	assert u64_at(bytes, rela_data + 48) == 8
	assert u64_at(bytes, rela_data + 56) == elf_relocation_size
}

// The symbol table links to the string table its names live in, its info field
// is the index of the first global symbol, and its entry size is the format's.
// The string tables around it say no link and align to a byte, because a name is
// read a byte at a time.
fn test_the_symbol_and_string_sections_name_their_links_and_entry_sizes() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	symtab := section_header_at(bytes, section_symtab)
	assert u32_at(bytes, symtab + 4) == sht_symtab
	assert u64_at(bytes, symtab + 8) == 0
	assert u32_at(bytes, symtab + 40) == section_strtab
	assert u32_at(bytes, symtab + 44) == first_global_symbol
	assert u64_at(bytes, symtab + 48) == 8
	assert u64_at(bytes, symtab + 56) == elf_symbol_size
	for index in [section_strtab, section_shstrtab] {
		header := section_header_at(bytes, index)
		assert u32_at(bytes, header + 4) == sht_strtab
		assert u32_at(bytes, header + 40) == 0
		assert u32_at(bytes, header + 44) == 0
		assert u64_at(bytes, header + 48) == 1
		assert u64_at(bytes, header + 56) == 0
	}
}

// A symbol entry carries where its name starts in the string table, its
// visibility, the section it belongs to, and how large it is. A top-level object
// of three eight-byte elements is twenty-four bytes, and its visibility is the
// default, which is a zero. The null entry before it is all zeroes.
fn test_a_symbol_entry_carries_its_name_offset_visibility_and_size() {
	mut program := image.Program{}
	program.globals['keep'] = image.GlobalSlot{
		offset: 0
		width:  8
		count:  3
	}
	program.globals_blob = []u8{len: 24, init: u8(0)}
	bytes := object(program, x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	for i in 0 .. elf_symbol_size {
		assert bytes[symbol_entry_at(bytes, 0) + i] == 0
	}
	entry := symbol_entry_at(bytes, first_global_symbol)
	name := name_at(bytes, section_offset(bytes, section_strtab) + int(u32_at(bytes, entry)))
	assert name == 'keep'
	assert bytes[entry + 5] == 0 // st_other: default visibility
	assert u16_at(bytes, entry + 6) == section_data
	assert u64_at(bytes, entry + 8) == 0 // the storage begins at the section's start
	assert u64_at(bytes, entry + 16) == 24
}

// A string table starts with a null byte, because offset zero has to mean no
// name, and every name after it is null-terminated. The section headers name
// their sections through .shstrtab, so a table laid out wrongly would point a
// header at the middle of a name.
fn test_the_string_tables_start_with_a_null_byte_and_hold_each_name() {
	bytes := object(one_call(), x86_64()) or {
		panic('the object was not written: ${err.msg()}')
	}
	strtab := section_offset(bytes, section_strtab)
	assert bytes[strtab] == 0
	assert name_at(bytes, strtab) == ''
	symtab := section_offset(bytes, section_symtab)
	callee := int(u32_at(bytes, symtab + first_global_symbol * elf_symbol_size))
	assert name_at(bytes, strtab + callee) == 'callee'
	shstrtab := section_offset(bytes, section_shstrtab)
	assert bytes[shstrtab] == 0
	indices := [
		section_text,
		section_rela_text,
		section_rodata,
		section_data,
		section_symtab,
		section_strtab,
		section_shstrtab,
		section_gnu_stack,
		section_rela_data,
	]
	expected := ['.text', '.rela.text', '.rodata', '.data', '.symtab', '.strtab', '.shstrtab',
		'.note.GNU-stack', '.rela.data']
	for i, index in indices {
		header := section_header_at(bytes, index)
		offset := int(u32_at(bytes, header))
		assert name_at(bytes, shstrtab + offset) == expected[i]
	}
}
