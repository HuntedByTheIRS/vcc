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
	// The read-only data now carries the unwind table after the strings. The
	// sample defines no function body, so the table is empty, but the section
	// itself still pads the read-only blob up to its own alignment.
	assert got.string_blob[0..program.string_blob.len] == program.string_blob
	assert got.eh_frame_run.len == 0
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

// The reader is also checked against an object it did not write. `gcc` puts an
// ordinary C translation unit in sections of its own names, more than the four
// this compiler uses, and a test that only round-trips the tree's own writer
// would never see them. Below is a small object built byte by byte, because the
// section header table is the only way to control the flags that decide which
// blob a section lands in.

// BuildSection is one allocatable section of a hand-built object. `data` is the
// bytes a PROGBITS section holds, or the length of the zero-filled storage a
// NOBITS one asks for.
struct BuildSection {
	name  string
	kind  u32
	flags u64
	align int
	data  []u8
}

// BuildSymbol is one symbol table entry. `shndx` is the section number it is
// defined in, or zero when it is undefined.
struct BuildSymbol {
	name  string
	info  u8
	shndx u16
	value u64
	size  u64
}

// BuildRelocation is one relocation. `target` is the section number the
// relocation applies to, which is what its section header's sh_info names.
struct BuildRelocation {
	target u16
	offset u64
	symbol u32
	kind   u32
	addend i64
}

// sample_sections is six allocatable sections with names of their own: one code
// section, two read-only, three writable, one of them with no bytes in the file.
fn sample_sections() []BuildSection {
	return [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 20, init: u8(0x90)} },
		BuildSection{
			name:  '.myro'
			kind:  1
			flags: 0x2
			align: 8
			data:  [u8(0x11), u8(0x12), u8(0x13), u8(0x14), u8(0x15), u8(0x16), u8(0x17), u8(0x18)]
		},
		BuildSection{
			name:  '.myro2'
			kind:  1
			flags: 0x2
			align: 8
			data:  [u8(0x21), u8(0x22), u8(0x23), u8(0x24)]
		},
		BuildSection{
			name:  '.myrw'
			kind:  1
			flags: 0x3
			align: 8
			data:  [u8(0x31), u8(0x32), u8(0x33), u8(0x34), u8(0x35), u8(0x36), u8(0x37), u8(0x38)]
		},
		BuildSection{ name: '.mybss', kind: 8, flags: 0x3, align: 8, data: []u8{len: 4, init: u8(0)} },
		BuildSection{
			name:  '.myrw2'
			kind:  1
			flags: 0x3
			align: 16
			data:  [u8(0x41), u8(0x42), u8(0x43), u8(0x44)]
		},
	]
}

// sample_symbols are the definitions and the one import a reference reaches in
// the hand-built object.
fn sample_symbols() []BuildSymbol {
	return [
		BuildSymbol{ name: '.myro2', info: 0x03, shndx: 3, value: 0, size: 0 },
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'f', info: 0x12, shndx: 1, value: 4, size: 4 },
		BuildSymbol{ name: 'g', info: 0x11, shndx: 4, value: 2, size: 4 },
		BuildSymbol{ name: 'b', info: 0x11, shndx: 5, value: 0, size: 4 },
		BuildSymbol{ name: 'g2', info: 0x11, shndx: 6, value: 1, size: 4 },
		BuildSymbol{ name: 'ro', info: 0x11, shndx: 2, value: 1, size: 2 },
		BuildSymbol{ name: 'ext', info: 0x10, shndx: 0, value: 0, size: 0 },
	]
}

// sample_relocations holds one of each shape: a direct reference to a code
// symbol, a reference to a section symbol of the read-only blob, a GOTPCREL and
// a REX_GOTPCRELX to an import, a reference to a named read-only symbol, a
// pc-relative reference living in the read-only blob, and one absolute address
// in the writable blob.
fn sample_relocations() []BuildRelocation {
	return [
		BuildRelocation{ target: 1, offset: 0, symbol: 3, kind: 4, addend: -4 },
		BuildRelocation{ target: 1, offset: 4, symbol: 1, kind: 2, addend: 1 },
		BuildRelocation{ target: 1, offset: 8, symbol: 8, kind: 9, addend: -4 },
		BuildRelocation{ target: 1, offset: 12, symbol: 8, kind: 42, addend: -4 },
		BuildRelocation{ target: 1, offset: 16, symbol: 7, kind: 2, addend: -4 },
		BuildRelocation{ target: 2, offset: 4, symbol: 2, kind: 2, addend: 0 },
		BuildRelocation{ target: 4, offset: 0, symbol: 1, kind: 1, addend: 2 },
	]
}

// test_an_object_of_its_own_names_reads_into_the_three_blobs checks the general
// rule: every allocatable section is copied into the blob its flags name, in
// section order and at its alignment, and each base is what a reference inside
// it counts from.
fn test_an_object_of_its_own_names_reads_into_the_three_blobs() {
	obj := build_object(sample_sections(), sample_symbols(), sample_relocations())
	got := read(obj, host()) or { panic('the reader refused a hand-built object: ${err.msg()}') }
	assert got.text == []u8{len: 20, init: u8(0x90)}
	// The two read-only sections land at 0 and 8, so .myro2's base is 8.
	assert got.string_blob == [u8(0x11), u8(0x12), u8(0x13), u8(0x14), u8(0x15), u8(0x16), u8(0x17),
		u8(0x18), u8(0x21), u8(0x22), u8(0x23), u8(0x24)]
	// .myrw at 0, .mybss at 8 (four zeroes with no bytes in the file), and
	// .myrw2 at 16 after the padding that brings it to its alignment.
	assert got.globals_blob == [u8(0x31), u8(0x32), u8(0x33), u8(0x34), u8(0x35), u8(0x36), u8(0x37),
		u8(0x38), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0x41), u8(0x42), u8(0x43),
		u8(0x44)]
	assert got.globals_alignment == 16
	// A symbol's offset is its section's base plus its value.
	assert got.labels['f'] == 4
	assert got.defined['f']
	assert got.globals['g'].offset == 2
	assert got.globals['g'].width == 4
	assert got.globals['b'].offset == 8
	assert got.globals['b'].width == 4
	assert got.globals['g2'].offset == 17
	assert got.globals['g2'].width == 4
	// A symbol defined in the read-only blob has no table entry.
	assert !('ro' in got.labels)
	assert !('ro' in got.globals)
	assert got.imports == ['ext']
	// A direct reference to a named code symbol keeps its name.
	assert got.relocations.len == 6
	assert got.relocations[0].place == .text
	assert got.relocations[0].kind == .direct
	assert got.relocations[0].name == 'f'
	assert got.relocations[0].offset == 0
	assert got.relocations[0].addend == -4
	// A section symbol becomes the key of the blob its section landed in, and
	// the byte it stands at rides in the addend: .myro2's base is 8.
	assert got.relocations[1].name == image.section_key_rodata
	assert got.relocations[1].offset == 4
	assert got.relocations[1].addend == 9
	// A reference reached through the global offset table says so, and keeps
	// the name of the import it reaches.
	assert got.relocations[2].kind == .got
	assert got.relocations[2].name == 'ext'
	assert got.relocations[2].offset == 8
	assert got.relocations[2].addend == -4
	assert got.relocations[3].kind == .got
	assert got.relocations[3].name == 'ext'
	assert got.relocations[3].offset == 12
	// A named symbol defined in the read-only blob is resolved as the read-only
	// key with its byte, not as a name.
	assert got.relocations[4].name == image.section_key_rodata
	assert got.relocations[4].offset == 16
	assert got.relocations[4].addend == -3
	// A pc-relative reference living in the read-only blob is the .eh_frame
	// shape: the field is in read-only data and the name is the code's key.
	assert got.relocations[5].place == .read_only
	assert got.relocations[5].kind == .direct
	assert got.relocations[5].name == image.section_key_text
	assert got.relocations[5].offset == 4
	assert got.relocations[5].addend == 0
	// R_X86_64_64 in the writable blob is an eight-byte address, offset into
	// the writable blob, against the read-only section it names.
	assert got.data_fixups.len == 1
	assert got.data_fixups[0].kind == .section_address
	assert got.data_fixups[0].name == image.section_key_rodata
	assert got.data_fixups[0].offset == 0
	assert got.data_fixups[0].addend == 10
}

// A thread-local section is carried into the unit's own TLS block rather than
// refused: the initialized bytes go into tls_blob, a zero-filled section adds to
// tls_size, each thread-local symbol's offset inside the block is recorded in
// tls_labels, and a `.tpoff` reference to the name is a thread pointer offset.
fn test_a_thread_local_section_is_carried_into_the_tls_block() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 8, init: u8(0x90)} },
		BuildSection{
			name:  '.tdata'
			kind:  1
			flags: 0x403 // SHF_TLS | SHF_WRITE | SHF_ALLOC
			align: 8
			data:  [u8(0x01), u8(0x02), u8(0x03), u8(0x04), u8(0x05), u8(0x06), u8(0x07), u8(0x08)]
		},
		BuildSection{ name: '.tbss', kind: 8, flags: 0x403, align: 8, data: []u8{len: 16, init: u8(0)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'tls', info: 0x11, shndx: 2, value: 0, size: 8 },
		BuildSymbol{ name: 'tlsb', info: 0x11, shndx: 3, value: 0, size: 16 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 23, addend: 0 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a thread-local object: ${err.msg()}')
	}
	assert got.tls_blob == [u8(0x01), u8(0x02), u8(0x03), u8(0x04), u8(0x05), u8(0x06), u8(0x07),
		u8(0x08)]
	// Eight bytes of image and sixteen of zero-filled storage, at eight-byte
	// alignment because the strictest member asked for it.
	assert got.tls_size == 24
	assert got.tls_alignment == 8
	assert got.tls_labels['tls'] == 0
	assert got.tls_labels['tlsb'] == 8
	// The container reads the same number as a thread-local definition.
	assert got.bound['tls'].tls
	assert got.bound['tls'].offset == 0
	assert !('tls' in got.labels)
	assert got.relocations.len == 1
	assert got.relocations[0].place == .text
	assert got.relocations[0].kind == .tpoff
	assert got.relocations[0].width == .narrow
	assert got.relocations[0].name == 'tls'
	assert got.relocations[0].offset == 0
	assert got.relocations[0].addend == 0
}

// A constructor table is carried into the writable data: its sections are copied
// there, the table records where and how many eight-byte entries it holds, and
// each entry's own R_X86_64_64 becomes a wide absolute reference the link fills
// in. A unit with an `.init_array` and an `.init_array.00000` for a priority gets
// one table covering both.
fn test_a_constructor_table_is_carried_into_the_writable_data() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 8, init: u8(0x90)} },
		BuildSection{
			name:  '.mydata'
			kind:  1
			flags: 0x3
			align: 8
			data:  [u8(0xaa), u8(0xbb), u8(0xcc), u8(0xdd), u8(0xee), u8(0xff), u8(0x11), u8(0x22)]
		},
		BuildSection{ name: '.init_array', kind: 14, flags: 0x3, align: 8, data: []u8{len: 16, init: u8(0)} },
		BuildSection{ name: '.init_array.00000', kind: 14, flags: 0x3, align: 8, data: []u8{len: 8, init: u8(0)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'ctor1', info: 0x12, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'ctor2', info: 0x12, shndx: 1, value: 4, size: 0 },
	]
	relocations := [
		BuildRelocation{ target: 3, offset: 0, symbol: 2, kind: 1, addend: 0 },
		BuildRelocation{ target: 3, offset: 8, symbol: 3, kind: 1, addend: 0 },
		BuildRelocation{ target: 4, offset: 0, symbol: 2, kind: 1, addend: 0 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a constructor object: ${err.msg()}')
	}
	// .mydata lands at 0, then the two array sections together at 8 and 24.
	assert got.globals_blob.len == 32
	assert got.globals_blob[0] == u8(0xaa)
	assert got.init_array.offset == 8
	assert got.init_array.count == 3
	assert got.fini_array.count == 0
	assert got.relocations.len == 3
	assert got.relocations[0].place == .data
	assert got.relocations[0].kind == .absolute
	assert got.relocations[0].width == .wide
	assert got.relocations[0].name == 'ctor1'
	assert got.relocations[0].offset == 8
	assert got.relocations[0].addend == 0
	assert got.relocations[1].name == 'ctor2'
	assert got.relocations[1].offset == 16
	assert got.relocations[2].name == 'ctor1'
	assert got.relocations[2].offset == 24
}

// A common symbol's storage is made in the writable data at the alignment its
// value names, and the name is recorded the way a `.bss` definition is.
fn test_a_common_symbol_gets_storage_in_the_writable_data() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 8, init: u8(0x90)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'shared', info: 0x11, shndx: 0xfff2, value: 16, size: 32 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 1, addend: 0 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a common symbol: ${err.msg()}')
	}
	assert got.globals['shared'].offset == 0
	assert got.globals['shared'].width == 32
	assert got.globals_blob.len == 32
	assert got.globals_alignment == 16
	assert !got.defined['shared']
	// The storage is recorded, so a reference to the name resolves to it.
	assert got.relocations.len == 1
	assert got.relocations[0].kind == .absolute
	assert got.relocations[0].width == .wide
	assert got.relocations[0].name == 'shared'
	assert got.relocations[0].addend == 0
}

// A reference to an absolute symbol folds to the constant the symbol names, with
// an empty name: the container is told the addend is the whole value.
fn test_an_absolute_symbol_folds_to_a_constant() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 8, init: u8(0x90)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'CONST', info: 0x11, shndx: 0xfff1, value: 0x1000, size: 0 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 1, addend: 4 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused an absolute symbol: ${err.msg()}')
	}
	assert got.relocations.len == 1
	assert got.relocations[0].kind == .absolute
	assert got.relocations[0].width == .wide
	assert got.relocations[0].name == ''
	assert got.relocations[0].addend == 0x1004
	assert got.imports.len == 0
}

// An eight-byte pc-relative field is carried as a wide direct reference, which is
// what an unwind table's entries carry.
fn test_a_pc64_field_is_a_wide_direct_reference() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 16, init: u8(0x90)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'f', info: 0x12, shndx: 1, value: 4, size: 4 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 24, addend: -8 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a PC64 reference: ${err.msg()}')
	}
	assert got.relocations.len == 1
	assert got.relocations[0].place == .text
	assert got.relocations[0].kind == .direct
	assert got.relocations[0].width == .wide
	assert got.relocations[0].name == 'f'
	assert got.relocations[0].offset == 0
	assert got.relocations[0].addend == -8
}

// R_X86_64_64 in the read-only data is an eight-byte absolute field, which is
// what a .sframe unwind table's entry holds.
fn test_an_absolute_field_in_the_read_only_data_is_wide() {
	sections := [
		BuildSection{ name: '.myro', kind: 1, flags: 0x2, align: 8, data: []u8{len: 8, init: u8(0)} },
	]
	symbols := [
		BuildSymbol{ name: '.myro', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'ext', info: 0x10, shndx: 0, value: 0, size: 0 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 1, addend: -8 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a read-only absolute field: ${err.msg()}')
	}
	assert got.relocations.len == 1
	assert got.relocations[0].place == .read_only
	assert got.relocations[0].kind == .absolute
	assert got.relocations[0].width == .wide
	assert got.relocations[0].name == 'ext'
	assert got.relocations[0].addend == -8
}

// An IFUNC symbol is a definition whose value is the resolver function's offset,
// and its name is recorded so the container can ask the resolver for the address
// to use.
fn test_an_ifunc_symbol_is_recorded() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 16, init: u8(0x90)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'memcpy', info: 0x0a, shndx: 1, value: 4, size: 0 },
	]
	got := read(build_object(sections, symbols, []BuildRelocation{}), host()) or {
		panic('the reader refused an IFUNC symbol: ${err.msg()}')
	}
	assert got.ifuncs['memcpy']
	assert got.labels['memcpy'] == 4
	assert got.defined['memcpy']
}

// A thread-local model this reader does not carry is refused by name rather than
// treated as another kind. A general-dynamic reference is carried, but only as
// the paired two-instruction sequence a compiler writes; a `lea` with no call to
// the general-dynamic helper after it is not that shape and is refused by name.
fn test_a_thread_local_reference_that_is_not_the_paired_sequence_is_refused() {
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: []u8{len: 8, init: u8(0x90)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'ext', info: 0x10, shndx: 0, value: 0, size: 0 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 0, symbol: 2, kind: 19, addend: -4 },
	]
	obj := build_object(sections, symbols, relocations)
	read(obj, host()) or {
		assert err.msg().contains('TLSGD')
		assert err.msg().contains('__tls_get_addr')
		return
	}
	assert false, 'the reader accepted a general-dynamic reference that is not the paired sequence'
}

// The paired general-dynamic sequence is relaxed into the local-exec one in
// place, because the variable it names is one the image holds: the two
// instructions that reach the general-dynamic helper become the two that read
// the thread pointer and add the variable's offset, the call is not a reference
// the link carries, and one thread pointer offset reference is recorded at the
// `lea`'s displacement in the new sequence.
fn test_a_paired_general_dynamic_reference_is_relaxed_to_local_exec() {
	// The general-dynamic pair as a compiler writes it: a `data16 rex.W lea` and
	// a `data16 data16 rex.W call`, sixteen bytes together.
	mut code := []u8{}
	code << [u8(0x66), u8(0x48), u8(0x8d), u8(0x3d), u8(0), u8(0), u8(0), u8(0)]
	code << [u8(0x66), u8(0x66), u8(0x48), u8(0xe8), u8(0), u8(0), u8(0), u8(0)]
	sections := [
		BuildSection{ name: '.mycode', kind: 1, flags: 0x6, align: 16, data: code },
		BuildSection{ name: '.tbss', kind: 8, flags: 0x403, align: 8, data: []u8{len: 8, init: u8(0)} },
	]
	symbols := [
		BuildSymbol{ name: '.mycode', info: 0x03, shndx: 1, value: 0, size: 0 },
		BuildSymbol{ name: 'setting', info: 0x11, shndx: 2, value: 0, size: 8 },
		BuildSymbol{ name: '__tls_get_addr', info: 0x10, shndx: 0, value: 0, size: 0 },
	]
	relocations := [
		BuildRelocation{ target: 1, offset: 4, symbol: 2, kind: 19, addend: -4 },
		BuildRelocation{ target: 1, offset: 12, symbol: 3, kind: 4, addend: -4 },
	]
	got := read(build_object(sections, symbols, relocations), host()) or {
		panic('the reader refused a paired general-dynamic reference: ${err.msg()}')
	}
	// The local-exec sequence: `mov %fs:0,%rax` then `lea disp32(%rax),%rax`,
	// with the displacement left zero for the link to fill.
	assert got.text == [
		u8(0x64),
		u8(0x48),
		u8(0x8b),
		u8(0x04),
		u8(0x25),
		u8(0x00),
		u8(0x00),
		u8(0x00),
		u8(0x00),
		u8(0x48),
		u8(0x8d),
		u8(0x80),
		u8(0x00),
		u8(0x00),
		u8(0x00),
		u8(0x00),
	]
	// One reference, at the new sequence's `lea` displacement, and the call the
	// relaxation removed is not an import of the unit.
	assert got.relocations.len == 1
	assert got.relocations[0].kind == .tpoff
	assert got.relocations[0].place == .text
	assert got.relocations[0].width == .narrow
	assert got.relocations[0].name == 'setting'
	assert got.relocations[0].offset == 12
	assert got.relocations[0].addend == 0
	assert '__tls_get_addr' !in got.imports
	assert got.tls_labels['setting'] == 0
}

// A reference to a symbol defined in a section that is not part of the unit is
// refused by name, the same way the reader refused it before it carried
// sections of its own.
fn test_a_symbol_outside_the_unit_is_refused() {
	mut sections := sample_sections()
	sections << BuildSection{
		name:  '.dead'
		kind:  1
		flags: 0
		align: 1
		data:  [u8(0xde), u8(0xad)]
	}
	mut symbols := sample_symbols()
	symbols << BuildSymbol{ name: 'dead', info: 0x11, shndx: 7, value: 0, size: 2 }
	mut relocs := []BuildRelocation{}
	relocs << BuildRelocation{
		target: 1
		offset: 0
		symbol: u32(symbols.len)
		kind:   2
		addend: -4
	}
	obj := build_object(sections, symbols, relocs)
	read(obj, host()) or {
		assert err.msg().contains('does not handle')
		return
	}
	assert false, 'the reader accepted a reference to a section outside the unit'
}

// An unknown relocation type in a foreign object is refused with the number,
// the same way it is for an object this compiler wrote.
fn test_an_unknown_relocation_in_a_foreign_object_is_refused() {
	mut obj := build_object(sample_sections(), sample_symbols(), sample_relocations())
	at := section_data_offset(obj, '.rela.mycode')
	set_u32(mut obj, at + 8, 0x7f) // the first entry's relocation type
	read(obj, host()) or {
		assert err.msg().contains('unknown relocation type')
		return
	}
	assert false, 'the reader accepted an unknown relocation type'
}

// build_object writes an ELF64 relocatable object byte by byte, because the
// section header table is the only place the flags that decide a section's blob
// are set, and a test that only round-trips the tree's own writer would never
// exercise them. The section order is the given sections, then .shstrtab,
// .strtab, .symtab, and one .rela section per target.
fn build_object(sections []BuildSection, symbols []BuildSymbol, relocations []BuildRelocation) []u8 {
	mut shstr := []u8{}
	shstr << u8(0)
	mut section_name := []int{}
	section_name << 0
	for s in sections {
		section_name << intern(mut shstr, s.name)
	}
	mut targets := []u16{}
	for r in relocations {
		if r.target !in targets {
			targets << r.target
		}
	}
	mut rela_name := []int{}
	for t in targets {
		rela_name << intern(mut shstr, '.rela' + sections[int(t) - 1].name)
	}
	shstrtab_name := intern(mut shstr, '.shstrtab')
	strtab_name := intern(mut shstr, '.strtab')
	symtab_name := intern(mut shstr, '.symtab')
	shstrtab_index := 1 + sections.len
	strtab_index := shstrtab_index + 1
	symtab_index := strtab_index + 1
	first_rela := symtab_index + 1
	section_count := first_rela + targets.len
	mut strtab := []u8{}
	strtab << u8(0)
	mut symbol_name := []int{}
	symbol_name << 0
	for s in symbols {
		symbol_name << intern(mut strtab, s.name)
	}
	mut symtab := []u8{len: (symbols.len + 1) * 24, init: u8(0)}
	for i, s in symbols {
		at := (i + 1) * 24
		set_u32(mut symtab, at, u32(symbol_name[i + 1]))
		symtab[at + 4] = s.info
		set_u16(mut symtab, at + 6, s.shndx)
		set_u64(mut symtab, at + 8, s.value)
		set_u64(mut symtab, at + 16, s.size)
	}
	mut rela_bytes := [][]u8{}
	for t in targets {
		mut count := 0
		for r in relocations {
			if r.target == t {
				count++
			}
		}
		mut buf := []u8{len: count * 24, init: u8(0)}
		mut at := 0
		for r in relocations {
			if r.target != t {
				continue
			}
			set_u64(mut buf, at, r.offset)
			set_u64(mut buf, at + 8, (u64(r.symbol) << 32) | u64(r.kind))
			set_u64(mut buf, at + 16, u64(r.addend))
			at += 24
		}
		rela_bytes << buf
	}
	mut out := []u8{len: 64, init: u8(0)}
	mut data_offset := []int{len: section_count, init: 0}
	mut data_size := []int{len: section_count, init: 0}
	for i, s in sections {
		if s.kind == 8 {
			// NOBITS holds no bytes in the file, only a size.
			for out.len % 8 != 0 {
				out << u8(0)
			}
			data_offset[i + 1] = out.len
			data_size[i + 1] = s.data.len
			continue
		}
		data_offset[i + 1] = place_block(mut out, 8, s.data)
		data_size[i + 1] = s.data.len
	}
	data_offset[shstrtab_index] = place_block(mut out, 8, shstr)
	data_size[shstrtab_index] = shstr.len
	data_offset[strtab_index] = place_block(mut out, 8, strtab)
	data_size[strtab_index] = strtab.len
	data_offset[symtab_index] = place_block(mut out, 8, symtab)
	data_size[symtab_index] = symtab.len
	for i, buf in rela_bytes {
		index := first_rela + i
		data_offset[index] = place_block(mut out, 8, buf)
		data_size[index] = buf.len
	}
	for out.len % 8 != 0 {
		out << u8(0)
	}
	shoff := out.len
	out << []u8{len: section_count * 64, init: u8(0)}
	out[0] = 0x7f
	out[1] = 0x45
	out[2] = 0x4c
	out[3] = 0x46
	out[4] = 2 // ELFCLASS64
	out[5] = 1 // ELFDATA2LSB
	out[6] = 1 // EV_CURRENT
	set_u16(mut out, 16, 1) // ET_REL
	set_u16(mut out, 18, 62) // EM_X86_64
	set_u32(mut out, 20, 1)
	set_u64(mut out, 40, u64(shoff))
	set_u16(mut out, 52, 64)
	set_u16(mut out, 58, 64)
	set_u16(mut out, 60, u16(section_count))
	set_u16(mut out, 62, u16(shstrtab_index))
	put_header(mut out, shoff, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	for i, s in sections {
		put_header(mut out, shoff + (i + 1) * 64, u32(section_name[i + 1]), s.kind, s.flags,
			data_offset[i + 1], data_size[i + 1], 0, 0, u64(s.align), 0)
	}
	put_header(mut out, shoff + shstrtab_index * 64, u32(shstrtab_name), 3, 0,
		data_offset[shstrtab_index], data_size[shstrtab_index], 0, 0, 1, 0)
	put_header(mut out, shoff + strtab_index * 64, u32(strtab_name), 3, 0,
		data_offset[strtab_index], data_size[strtab_index], 0, 0, 1, 0)
	put_header(mut out, shoff + symtab_index * 64, u32(symtab_name), 2, 0,
		data_offset[symtab_index], data_size[symtab_index], u32(strtab_index), 1, 8, 24)
	for i, t in targets {
		index := first_rela + i
		put_header(mut out, shoff + index * 64, u32(rela_name[i]), 4, 0, data_offset[index],
			data_size[index], u32(symtab_index), u32(t), 8, 24)
	}
	return out
}

// section_header_offset finds the file offset of one named section's header,
// read straight out of the object so the refusal tests can corrupt a field
// without leaning on the reader they check.
fn section_header_offset(obj []u8, name string) int {
	shoff := int(field_u64(obj, 40))
	shentsize := int(field_u16(obj, 58))
	shnum := int(field_u16(obj, 60))
	shstrndx := int(field_u16(obj, 62))
	shstr := int(field_u64(obj, shoff + shstrndx * shentsize + 24))
	for i in 0 .. shnum {
		base := shoff + i * shentsize
		name_off := int(field_u32(obj, base))
		mut end := shstr + name_off
		for end < obj.len && obj[end] != u8(0) {
			end++
		}
		if obj[shstr + name_off..end].bytestr() == name {
			return base
		}
	}
	panic('the object has no section named ${name}')
}

// section_data_offset is where one named section's bytes start.
fn section_data_offset(obj []u8, name string) int {
	return int(field_u64(obj, section_header_offset(obj, name) + 24))
}

// place_block pads the object to an eight-byte boundary and appends one block,
// answering where it landed.
fn place_block(mut out []u8, alignment int, data []u8) int {
	for out.len % alignment != 0 {
		out << u8(0)
	}
	at := out.len
	out << data
	return at
}

// intern adds a NUL-terminated name to a string table and answers where it
// starts.
fn intern(mut table []u8, name string) int {
	at := table.len
	table << name.bytes()
	table << u8(0)
	return at
}

// put_header writes one 64-byte section header.
fn put_header(mut out []u8, at int, name u32, kind u32, flags u64, offset int, size int, link u32, info u32, alignment u64, entsize u64) {
	set_u32(mut out, at, name)
	set_u32(mut out, at + 4, kind)
	set_u64(mut out, at + 8, flags)
	set_u64(mut out, at + 16, 0)
	set_u64(mut out, at + 24, u64(offset))
	set_u64(mut out, at + 32, u64(size))
	set_u32(mut out, at + 40, link)
	set_u32(mut out, at + 44, info)
	set_u64(mut out, at + 48, alignment)
	set_u64(mut out, at + 56, entsize)
}

fn set_u16(mut bytes []u8, at int, value u16) {
	bytes[at] = u8(value & 0xff)
	bytes[at + 1] = u8((value >> 8) & 0xff)
}

fn set_u32(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 {
		bytes[at + i] = u8((value >> (8 * i)) & 0xff)
	}
}

fn set_u64(mut bytes []u8, at int, value u64) {
	for i in 0 .. 8 {
		bytes[at + i] = u8((value >> (8 * i)) & 0xff)
	}
}
