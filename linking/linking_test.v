module linking

import backend
import image
import linking.symbols

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

// Two units may each hold a `static` function of one name. The emitter records
// such a name in the unit's `internal` set, and each unit calls its own. The
// merged labels have to hold two entries at two offsets, and each unit's call
// has to be rewritten to its own entry, because the two are different functions
// that happen to share a spelling. Under one bare name the link refused the
// program with `multiple definition`.
fn test_two_units_private_functions_get_two_labels() {
	mut first := defining('main', [u8(0x90), u8(0x90), u8(0xcc), u8(0xcc)])
	first.defined['helper'] = true
	first.internal['helper'] = true
	first.labels['helper'] = 2
	first.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_local
		name:   'helper'
	}
	mut second := image.Program{}
	second.text = [u8(0xee), u8(0xee)]
	second.defined['helper'] = true
	second.internal['helper'] = true
	second.labels['helper'] = 0
	second.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_local
		name:   'helper'
	}
	merged := link([first, second], options('main')) or { panic('the link failed: ${err.msg()}') }
	// The first unit's code is at 0 and the second unit's at 4, so the two
	// helpers land at 2 and 4.
	assert merged.labels['0:helper'] == 2
	assert merged.labels['1:helper'] == 4
	// Each call is rewritten to its own unit's key, so it resolves to its own
	// helper and not to the other unit's.
	assert merged.fixups.len == 2
	assert merged.fixups[0].name == '0:helper'
	assert merged.fixups[0].kind == .call_local
	assert merged.fixups[1].name == '1:helper'
	assert merged.fixups[1].kind == .call_local
	assert merged.labels[merged.fixups[0].name] == 2
	assert merged.labels[merged.fixups[1].name] == 4
	assert merged.text[2] == u8(0xcc)
	assert merged.text[4] == u8(0xee)
}

// The emitter numbers its jump labels from zero in each unit, so two units that
// each contain a loop both name a label `.L0`. The merge used to keep the first
// unit's offset for it, and the second unit's jump then landed in the first
// unit's code. Two entries and two rewritten jumps are what fixes that, and the
// offsets are the thing to assert: no error was ever raised for this one.
fn test_two_units_local_labels_of_one_name_get_two_offsets() {
	mut first := defining('main', [u8(0x90), u8(0x90)])
	first.labels['.L0'] = 1
	first.fixups << image.Fixup{
		start:  0
		length: 2
		kind:   .jump_local
		name:   '.L0'
	}
	mut second := image.Program{}
	second.text = [u8(0x90), u8(0x90)]
	second.labels['.L0'] = 0
	second.fixups << image.Fixup{
		start:  0
		length: 2
		kind:   .jump_local
		name:   '.L0'
	}
	merged := link([first, second], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert merged.labels['0:.L0'] == 1
	assert merged.labels['1:.L0'] == 2
	assert merged.fixups[0].name == '0:.L0'
	assert merged.fixups[1].name == '1:.L0'
	// The first jump lands at 1 and the second at 2, which is each unit's own
	// label; one key naming the first offset for both is the wrong jump this
	// test exists to catch.
	assert merged.labels[merged.fixups[0].name] == 1
	assert merged.labels[merged.fixups[1].name] == 2
}

// Two units may each hold a `static` object of one name. Each keeps its own
// storage in the merged writable data, and each unit's `.global_address`
// reference is rewritten to its own slot. A bare name would have merged the two
// into one, and the second unit would read the first unit's bytes.
fn test_two_units_private_objects_get_two_slots() {
	mut first := defining('main', [u8(0x90)])
	first.globals_blob = [u8(0x01), u8(0), u8(0), u8(0)]
	first.globals['counter'] = image.GlobalSlot{
		offset: 0
		width:  4
	}
	first.internal['counter'] = true
	first.data_fixups << image.DataFixup{
		offset: 0
		kind:   .global_address
		name:   'counter'
	}
	mut second := image.Program{}
	second.globals_blob = [u8(0x02), u8(0), u8(0), u8(0)]
	second.globals['counter'] = image.GlobalSlot{
		offset: 0
		width:  4
	}
	second.internal['counter'] = true
	second.data_fixups << image.DataFixup{
		offset: 0
		kind:   .global_address
		name:   'counter'
	}
	merged := link([first, second], options('main')) or { panic('the link failed: ${err.msg()}') }
	// The first unit's storage is at 0 and the second unit's at 4.
	assert merged.globals['0:counter'].offset == 0
	assert merged.globals['1:counter'].offset == 4
	assert merged.globals_blob[0] == u8(0x01)
	assert merged.globals_blob[4] == u8(0x02)
	// Each reference names its own unit's slot, so it points at its own bytes.
	assert merged.data_fixups.len == 2
	assert merged.data_fixups[0].name == '0:counter'
	assert merged.data_fixups[0].offset == 0
	assert merged.data_fixups[1].name == '1:counter'
	assert merged.data_fixups[1].offset == 4
}

// A `static int helper` in one unit does not answer another unit's call to
// `helper`. Internal linkage is not visible outside its unit (6.2.2p2), so the
// call binds to a library symbol or to nothing, and no library defines this one.
// The static is held under its own unit's key alone, so the import stays
// external and the link refuses the call by name.
fn test_a_static_definition_does_not_answer_another_units_import() {
	mut definer := defining('helper', [u8(0xcc)])
	definer.internal['helper'] = true
	mut caller := defining('main', []u8{len: 4, init: u8(0x90)})
	caller.imports << 'helper'
	caller.imports << 'exit'
	caller.fixups << image.Fixup{
		start:  0
		length: 5
		kind:   .call_import
		name:   'helper'
	}
	names := symbols.collect([definer, caller]) or { panic('collect failed: ${err.msg()}') }
	// The static is a definition of its own unit and under its own key, and no
	// bare `helper` is one, so a link cannot resolve the import to it.
	assert '0:helper' in names.definitions
	assert 'helper' !in names.definitions
	// The library check then refuses the call. `exit` is a real library name,
	// so the miss it reports is `helper` and not an unreadable library.
	link([definer, caller], options('main')) or {
		assert err.msg().contains('undefined reference')
		assert err.msg().contains('helper')
		return
	}
	assert false, 'the link bound an import to another unit static definition'
}

// The process stub's one code reference calls the entry function, which another
// unit defines, and the stub carries no label of its own for that name. A name a
// unit holds no label for is not one of its private labels, so the reference
// keeps the bare name and finds the defining unit's entry. Keying it as private
// to the stub would leave the merged table with nothing to answer it, and a
// program with an entry would be refused.
fn test_the_stub_calls_an_entry_another_unit_defines() {
	mut stub := image.Program{}
	// A `call rel32` placeholder, which is the shape of the stub's first
	// instruction.
	stub.text = [u8(0xe8), u8(0), u8(0), u8(0), u8(0)]
	stub.fixups << image.Fixup{
		start:  1
		length: 4
		kind:   .call_local
		name:   'main'
	}
	entry := defining('main', [u8(0xcc)])
	merged := link([stub, entry], options('main')) or { panic('the link failed: ${err.msg()}') }
	// `main` is the second unit's entry, placed after the stub's five bytes, and
	// the reference still names it the way the merged table holds it.
	assert merged.fixups.len == 1
	assert merged.fixups[0].name == 'main'
	assert merged.labels['main'] == 5
	assert merged.text[5] == u8(0xcc)
}

// The names a program's own runtime reaches for describe the image rather than
// a symbol in a library: `__data_start` and `data_start` are the start of the
// writable data and `_end` is its end, so a link that is asked for them answers
// from the layout it made rather than refusing them as undefined. The two starts
// come before the end, and the end is past the storage the units brought.
fn test_the_image_answers_the_data_bounds_its_own_runtime_reaches_for() {
	mut main := defining('main', []u8{len: 1, init: u8(0x90)})
	main.globals_blob = [u8(0x01), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]
	main.globals['one'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	main.globals_alignment = 8
	main.imports << '__data_start'
	main.imports << 'data_start'
	main.imports << '_end'
	merged := link([main], options('main')) or { panic('the link failed: ${err.msg()}') }
	assert '__data_start' in merged.bound
	assert 'data_start' in merged.bound
	assert '_end' in merged.bound
	assert merged.bound['__data_start'].offset == 0
	assert merged.bound['data_start'].offset == 0
	assert merged.bound['_end'].offset == merged.globals_blob.len
	assert merged.bound['data_start'].offset < merged.bound['_end'].offset
}
