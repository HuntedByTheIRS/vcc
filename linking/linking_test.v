module linking

import backend
import image

// The merge is checked on programs built here rather than on the output of
// codegen, because the questions worth pinning are about the merge's own rules:
// which unit a name binds to, where a reference moves to, and what a link
// refuses. A unit is machine code and the tables beside it, and a two-line
// program with the bytes the test names is enough to see the answer.
//
// `link` is handed the host target because the library check reads the system's
// own libraries: a test that made up a target would be checking a machine that
// does not exist.

fn host() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('the link tests need the x86_64-linux target') }
}

fn options(entry string) Options {
	return Options{
		entry:  entry
		target: host()
	}
}

// defining builds a unit that defines one function at the start of its text.
fn defining(name string, code []u8) image.Program {
	mut unit := image.Program{}
	unit.text = code
	unit.defined[name] = true
	unit.labels[name] = 0
	return unit
}

// A unit that defines a function and a second unit that imports it. The name is
// bound to the definition's offset in the merged text, and it is still an import
// because the call reaches it through a slot rather than a direct distance.
fn test_an_import_one_unit_defines_is_bound_to_the_definition() {
	mut stub := defining('main', []u8{len: 4, init: u8(0x90)})
	stub.imports << 'helper'
	helper := defining('helper', [u8(0xcc), u8(0xcc)])
	merged := link([stub, helper], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert merged.text.len == 6
	assert merged.text[4] == u8(0xcc)
	assert 'helper' in merged.bound
	assert merged.bound['helper'].function
	assert merged.bound['helper'].offset == 4
	assert 'helper' in merged.imports
}

// An import no unit defines is still an import and is not bound. `exit` is a
// name the C library defines, which is the library every image runs against, so
// the check passes and the test is about the binding and not the search.
fn test_an_import_no_unit_defines_stays_unbound() {
	mut stub := defining('main', []u8{len: 2, init: u8(0x90)})
	stub.imports << 'exit'
	merged := link([stub], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert 'exit' in merged.imports
	assert 'exit' !in merged.bound
}

// Two strong definitions of one name are what a link refuses, and the message
// names the name so a reader knows which one.
fn test_two_units_defining_one_name_are_refused() {
	main := defining('main', []u8{len: 1, init: u8(0x90)})
	first := defining('dup', [u8(0x11)])
	second := defining('dup', [u8(0x22)])
	link([main, first, second], options('main')) or {
		assert err.msg().contains('multiple definition of')
		assert err.msg().contains('dup')
		return
	}
	assert false, 'the link accepted two strong definitions of one name'
}

// A weak definition and a strong one of the same name are not a conflict: the
// strong one is the definition the image holds and the one a reference binds to.
fn test_a_strong_definition_wins_over_a_weak_one() {
	mut weak := defining('sym', [u8(0x11)])
	weak.weak['sym'] = true
	strong := defining('sym', [u8(0x22)])
	mut main := defining('main', []u8{len: 1, init: u8(0x90)})
	main.imports << 'sym'
	merged := link([weak, strong, main], options('main')) or { panic('the link failed: ${err.msg()}') }
	// The strong unit is the second, so the one byte of the weak unit's code
	// comes first and the strong definition begins at offset 1.
	assert 'sym' in merged.bound
	assert merged.bound['sym'].offset == 1
	assert merged.text[1] == u8(0x22)
}

// A string, a double, and a top-level object all move when their unit is placed:
// the tables keep their keys and their offsets gain the unit's base. The byte at
// each offset is checked, because an offset that is merely plausible is not the
// bytes the program asked for.
fn test_read_only_data_and_globals_are_rebased_into_the_merged_blobs() {
	mut first := defining('main', []u8{len: 0, init: u8(0)})
	first.string_blob = [u8(`h`), u8(`i`), u8(0)]
	first.strings['hi'] = 0
	first.globals_blob = [u8(0x01), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]
	first.globals['one'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	first.globals_alignment = 8
	mut second := image.Program{}
	second.string_blob = [u8(`y`), u8(`o`), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0xf8),
		u8(0x3f)]
	second.strings['yo'] = 0
	second.doubles['1.5'] = 3
	second.globals_blob = [u8(0xaa), u8(0xbb), u8(0xcc), u8(0xdd), u8(0), u8(0), u8(0), u8(0)]
	second.globals['obj'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	second.globals_alignment = 8
	merged := link([first, second], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert merged.string_blob[merged.strings['hi']] == u8(`h`)
	assert merged.string_blob[merged.strings['yo']] == u8(`y`)
	// The double is eight bytes behind its unit's string, in the merged data.
	at := merged.doubles['1.5']
	assert merged.string_blob[at] == u8(0)
	assert merged.string_blob[at + 7] == u8(0x3f)
	// The first unit's object is at the start; the second unit's storage starts
	// at the aligned boundary after the first unit's eight bytes.
	assert merged.globals['one'].offset == 0
	assert merged.globals_blob[merged.globals['one'].offset] == u8(0x01)
	assert merged.globals['obj'].offset == 8
	assert merged.globals_blob[merged.globals['obj'].offset] == u8(0xaa)
	assert merged.globals_blob[merged.globals['obj'].offset + 3] == u8(0xdd)
}

// A data reference to a name this image binds cannot be left for the loader: a
// bound name has no dynamic symbol, so no relocation fills its slot. The
// reference becomes an address the container writes at layout time, a function
// address for a function and a global address for an object, and its offset
// moves with its unit like any other.
fn test_a_bound_data_reference_becomes_an_address_inside_the_image() {
	mut stub := defining('main', []u8{len: 4, init: u8(0x90)})
	stub.imports << 'helper'
	stub.imports << 'object'
	stub.globals_blob = []u8{len: 8}
	stub.globals['unused'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	stub.globals_alignment = 8
	mut importer := image.Program{}
	importer.globals_blob = []u8{len: 16}
	importer.globals['p'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	importer.globals['q'] = image.GlobalSlot{
		offset: 8
		width:  8
	}
	importer.globals_alignment = 8
	importer.data_fixups << image.DataFixup{
		offset: 0
		kind:   .import_address
		name:   'helper'
	}
	importer.data_fixups << image.DataFixup{
		offset: 8
		kind:   .import_address
		name:   'object'
	}
	mut definer := defining('helper', [u8(0xcc)])
	definer.globals_blob = [u8(0x77), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]
	definer.globals['object'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	definer.globals_alignment = 8
	merged := link([stub, importer, definer], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert merged.data_fixups.len == 2
	assert merged.data_fixups[0].kind == .function_address
	assert merged.data_fixups[0].offset == 8
	assert merged.data_fixups[1].kind == .global_address
	assert merged.data_fixups[1].offset == 16
	// The offsets are the defining unit's bytes, in the code and in the data.
	assert merged.bound['helper'].offset == 4
	assert merged.text[merged.bound['helper'].offset] == u8(0xcc)
	assert merged.bound['object'].offset == 24
	assert merged.globals_blob[merged.bound['object'].offset] == u8(0x77)
}

// The entry is the one name the process stub calls, and a link whose units
// define no such function is refused by name rather than left to die at load.
fn test_a_link_whose_units_define_no_entry_names_it() {
	other := defining('other', [u8(0x90)])
	link([other], options('main')) or {
		assert err.msg().contains('main')
		return
	}
	assert false, 'the link accepted an entry that no unit defines'
}

// One unit names an object another unit defines: two slots for one name, and the
// mix of a copy record on one side only. The name is not a copy any more and it
// binds to the defining unit's storage, not to the storage the naming unit holds
// for a library's object. Picking the wrong slot is a wrong address rather than
// a loud failure, which is why the byte is checked.
fn test_an_object_a_unit_defines_binds_to_that_unit_and_is_not_a_copy() {
	mut namer := defining('main', []u8{len: 0, init: u8(0)})
	namer.globals_blob = []u8{len: 8}
	namer.globals['o'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	namer.copy_objects << 'o'
	namer.imports << 'o'
	namer.globals_alignment = 8
	mut definer := image.Program{}
	definer.globals_blob = [u8(0x42), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]
	definer.globals['o'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	definer.globals_alignment = 8
	merged := link([namer, definer], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert 'o' !in merged.copy_objects
	assert merged.globals['o'].offset == 8
	assert merged.globals_blob[merged.globals['o'].offset] == u8(0x42)
	assert merged.bound['o'].offset == 8
}
