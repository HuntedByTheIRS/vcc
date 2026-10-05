module object

import backend
import backend.os.elf
import image

// The reader is checked against the tree's own writer: a program built here is
// written with `backend.os.elf.object`, read back with `read`, and the two are
// compared field by field. That is the round trip the linker depends on, so the
// assertions are about the references and the definitions rather than about the
// bytes, which the writer's own tests already cover.
//
// The refusals are checked on real objects with one thing broken, because a
// reader that panics or half-reads a malformed file is worse than one that
// stops: the section header table is moved past the end of the file, the
// machine is changed, and a relocation's type is corrupted.

fn host() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('the object tests need the x86_64-linux target') }
}

// sample is a unit with one internal function, two top-level objects, a local
// call, an imported call, and the address of a string. It is small enough to
// read in one look and holds one of each shape the reader has to carry.
fn sample() image.Program {
	mut program := image.Program{}
	program.text = [
		u8(0xe8),
		u8(0),
		u8(0),
		u8(0),
		u8(0), // call callee
		u8(0xc3), // callee: ret
		u8(0xe8),
		u8(0),
		u8(0),
		u8(0),
		u8(0), // call puts
		u8(0x48),
		u8(0x8d),
		u8(0x3d),
		u8(0),
		u8(0),
		u8(0),
		u8(0), // lea rdi, [rip+a string]
		u8(0xc3), // ret
	]
	program.defined['callee'] = true
	program.labels['callee'] = 5
	program.internal['callee'] = true
	program.imports << 'puts'
	program.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_local
		name:   'callee'
	}
	program.fixups << image.Fixup{
		start:  6
		length: 5
		kind:   .call_import
		name:   'puts'
	}
	program.fixups << image.Fixup{
		start:    11
		length:   7
		kind:     .take_address
		name:     'greeting'
		register: 'rdi'
	}
	program.string_blob = [u8(`h`), u8(`i`), u8(0)]
	program.strings['greeting'] = 0
	// An int and a pointer to the string: the pointer is a top-level slot that
	// holds an address, which is the one reference the writable data carries.
	program.globals_blob = [u8(0x2a), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]
	program.globals['x'] = image.GlobalSlot{
		offset: 0
		width:  4
	}
	program.globals['p'] = image.GlobalSlot{
		offset: 8
		width:  8
	}
	program.globals_alignment = 8
	program.data_fixups << image.DataFixup{
		offset: 8
		kind:   .take_address
		name:   'greeting'
	}
	return program
}

fn written(program image.Program) []u8 {
	return elf.object(program, host()) or {
		panic('the object writer refused the sample: ${err.msg()}')
	}
}

// A unit written and read back comes home with its definitions, its data, its
// imports and one relocation per reference, each against the name the writer
// chose: a local call names its callee, an imported call names the import, and
// the string's address is a reference to `.rodata` at the byte the string
// starts at.
fn test_a_relocatable_object_reads_back_as_the_unit_that_wrote_it() {
	program := sample()
	got := read(written(program), host()) or {
		panic('the reader refused an object the writer produced: ${err.msg()}')
	}
	assert got.text == program.text
	assert got.labels['callee'] == 5
	assert got.defined['callee']
	assert got.internal['callee']
	assert got.globals['x'].offset == 0
	assert got.globals['x'].width == 4
	assert got.globals_blob[0] == u8(0x2a)
	assert got.globals['p'].offset == 8
	assert got.globals['p'].width == 8
	assert got.globals_alignment == 8
	assert got.string_blob == program.string_blob
	// The strings and doubles tables stay empty: a reference to the read-only
	// data arrives as a relocation against the section, not as a name.
	assert got.strings.len == 0
	assert got.doubles.len == 0
	assert got.imports == ['puts']
	assert !got.object_imports['puts']
	assert got.relocations.len == 3
	assert got.relocations[0].name == 'callee'
	assert got.relocations[0].offset == 1
	assert got.relocations[0].addend == -4
	assert got.relocations[1].name == 'puts'
	assert got.relocations[1].offset == 7
	assert got.relocations[1].addend == -4
	assert got.relocations[2].name == image.section_key_rodata
	assert got.relocations[2].offset == 14
	assert got.relocations[2].addend == -4
	assert got.data_fixups.len == 1
	assert got.data_fixups[0].kind == .section_address
	assert got.data_fixups[0].name == image.section_key_rodata
	assert got.data_fixups[0].offset == 8
	assert got.data_fixups[0].addend == 0
	assert got.copy_objects.len == 0
	assert got.libraries.len == 0
}

// An object whose section header table is past the end of the file is refused
// by name rather than read partway and crashing.
fn test_a_truncated_object_is_refused() {
	obj := written(sample())
	short := obj[0..obj.len - 8]
	read(short, host()) or {
		assert err.msg().contains('truncated')
		return
	}
	assert false, 'the reader accepted a truncated object'
}

// An object for another machine is refused with both numbers in the message.
fn test_an_object_for_another_machine_is_refused() {
	mut wrong := written(sample()).clone()
	wrong[18] = u8(3) // e_machine = EM_386, not EM_X86_64
	wrong[19] = u8(0)
	read(wrong, host()) or {
		assert err.msg().contains('e_machine')
		return
	}
	assert false, 'the reader accepted an object for another machine'
}

// A relocation whose type this reader does not know is refused with the number,
// rather than carried as a reference of the wrong kind.
fn test_an_unknown_relocation_type_is_refused() {
	mut corrupt := written(sample()).clone()
	rela := rela_text_data_offset(corrupt)
	// The first entry's r_info is eight bytes into .rela.text, and its low four
	// bytes are the relocation type.
	corrupt[rela + 8] = u8(0x7f)
	read(corrupt, host()) or {
		assert err.msg().contains('unknown relocation type')
		return
	}
	assert false, 'the reader accepted an unknown relocation type'
}

// rela_text_data_offset finds where .rela.text's bytes start, read straight out
// of the ELF header and the section headers so that the test does not lean on
// the reader it is checking.
fn rela_text_data_offset(obj []u8) int {
	shoff := int(field_u64(obj, 40))
	shentsize := int(field_u16(obj, 58))
	shnum := int(field_u16(obj, 60))
	shstrndx := int(field_u16(obj, 62))
	shstr := int(field_u64(obj, shoff + shstrndx * shentsize + 24))
	mut found := -1
	for i in 0 .. shnum {
		base := shoff + i * shentsize
		name_off := int(field_u32(obj, base))
		mut end := shstr + name_off
		for end < obj.len && obj[end] != u8(0) {
			end++
		}
		if obj[shstr + name_off..end].bytestr() == '.rela.text' {
			found = int(field_u64(obj, base + 24))
			break
		}
	}
	if found < 0 {
		panic('the object has no .rela.text section')
	}
	return found
}

fn field_u16(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn field_u32(bytes []u8, at int) u32 {
	mut value := u32(0)
	for i in 0 .. 4 {
		value |= u32(bytes[at + i]) << (8 * i)
	}
	return value
}

fn field_u64(bytes []u8, at int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 {
		value |= u64(bytes[at + i]) << (8 * i)
	}
	return value
}
