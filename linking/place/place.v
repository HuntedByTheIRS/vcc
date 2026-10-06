module place

import image

// Where each unit lands in the merged program. One link concatenates three kinds
// of data, and an offset a unit carries is measured from the start of its own
// copy of one of them, so every offset has to be moved by the base the unit was
// placed at. The bases are computed once here and read by the merge, because
// recomputing a running total per reference is the same answer bought at a cost
// that grows with the reference count.

// Layout is where each unit's text, read-only data, and writable data begin in
// the merged program, and how long each merged blob is. The lengths are what the
// merge allocates its output at, so each blob is built once at its final size.
pub struct Layout {
pub mut:
	text_bases    []int
	string_bases  []int
	globals_bases []int
	text_len      int
	string_len    int
	globals_len   int
	// tls_bases is where each unit's thread-local storage begins in the merged
	// block and tls_len is how long the whole block is, which is what a
	// `tpoff` reference measures from: the block sits below the thread pointer
	// and a thread-local's distance from it is its offset in the block minus
	// the block's own length. tls_alignment is the strictest alignment any
	// member asked for, which is what the thread pointer has to be set to.
	tls_bases     []int
	tls_len       int
	tls_alignment int
	// init_bases and fini_bases are where each unit's two constructor tables
	// land, and init_len and fini_len are how long the two places they land in
	// are. The tables are placed together at the end of the writable data
	// rather than inside the unit that holds them: a dynamic table names one
	// table, and the runtime walks one range, so two units with a constructor
	// each have to end up in one run. constructor_base is where that run
	// starts.
	init_bases       []int
	fini_bases       []int
	init_len         int
	fini_len         int
	constructor_base int
}

// lay places the units in the order they were given. Text and read-only data are
// concatenated as they stand, because a reference to either is written as an
// offset from the start of the unit's own blob and the base is the whole of what
// changes. Writable data is placed the same way except that each unit starts at
// the strictest alignment any unit asked for: an object's address is its offset
// in the merged blob, so an object whose declaration asked for more than the
// word size only lands at its alignment when the unit's storage begins there.
pub fn lay(units []image.Program, globals_alignment int) Layout {
	mut layout := Layout{
		text_bases:    []int{cap: units.len}
		string_bases:  []int{cap: units.len}
		globals_bases: []int{cap: units.len}
		tls_bases:     []int{cap: units.len}
		init_bases:    []int{cap: units.len}
		fini_bases:    []int{cap: units.len}
		tls_alignment: 1
	}
	step := if globals_alignment > 0 { globals_alignment } else { 1 }
	for unit in units {
		layout.text_bases << layout.text_len
		layout.text_len += unit.text.len
		layout.string_bases << layout.string_len
		layout.string_len += unit.string_blob.len
		for layout.globals_len % step != 0 {
			layout.globals_len++
		}
		layout.globals_bases << layout.globals_len
		layout.globals_len += unit.globals_blob.len
		// Thread-local storage is placed the way the writable data is, each
		// unit at the alignment its members asked for, because a thread-local
		// answers with its offset in this block.
		tls_step := if unit.tls_alignment > 1 { unit.tls_alignment } else { 1 }
		layout.tls_len = align_up(layout.tls_len, tls_step)
		layout.tls_bases << layout.tls_len
		layout.tls_len += unit.tls_size
		if unit.tls_alignment > layout.tls_alignment {
			layout.tls_alignment = unit.tls_alignment
		}
	}
	// The constructor tables come last so that a unit's own storage keeps the
	// offsets it was laid out with: only a table's entries move, and they move
	// to a place the layout knows before the merge rewrites them.
	layout.constructor_base = align_up(layout.globals_len, 8)
	layout.globals_len = layout.constructor_base
	for unit in units {
		if unit.init_array.count > 0 {
			layout.init_bases << layout.globals_len
			layout.globals_len += unit.init_array.count * 8
			layout.init_len += unit.init_array.count * 8
		} else {
			layout.init_bases << layout.globals_len
		}
	}
	for unit in units {
		if unit.fini_array.count > 0 {
			layout.fini_bases << layout.globals_len
			layout.globals_len += unit.fini_array.count * 8
			layout.fini_len += unit.fini_array.count * 8
		} else {
			layout.fini_bases << layout.globals_len
		}
	}
	return layout
}

// align_up rounds a length up to the next multiple of an alignment. A unit
// whose thread-locals or tables ask for an alignment longer than one byte has
// to start there, the same way a unit's writable data does.
fn align_up(length int, alignment int) int {
	if alignment <= 1 {
		return length
	}
	mut at := length
	for at % alignment != 0 {
		at++
	}
	return at
}
