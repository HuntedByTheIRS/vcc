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
	text_bases     []int
	string_bases   []int
	eh_frame_len   int
	eh_frame_bases []int
	globals_bases  []int
	text_len       int
	string_len     int
	globals_len    int
	// tls_bases is where each unit's thread-local storage begins in the merged
	// block and tls_len is how long the whole block is, which is what a
	// `tpoff` reference measures from: the block sits below the thread pointer
	// and a thread-local's distance from it is its offset in the block minus
	// the block's own length. tls_alignment is the strictest alignment any
	// member asked for, which is what the thread pointer has to be set to.
	tls_bases     []int
	tls_len       int
	tls_alignment int
	// init_run_base and init_run_len are where the gathered `.init` fragments
	// lie in the merged code and how long that run is, and init_run_bases is
	// where each unit's own fragment landed inside it. The fini run has the same
	// three, for `.fini`. Both runs come first in the merged code and the units'
	// own text follows them, because the branch at the end of one fragment has to
	// reach the beginning of the next.
	init_run_base  int
	init_run_len   int
	init_run_bases []int
	fini_run_base  int
	fini_run_len   int
	fini_run_bases []int
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

// lay places the units in the order they were given. Text is concatenated as it
// stands, because a reference to it is written as an offset from the start of
// the unit's own blob and the base is the whole of what changes. Writable data
// and read-only data are placed the same way except that each unit starts at the
// strictest alignment any unit asked for: an object's address is its offset in
// the merged blob, so an object whose declaration asked for more than the word
// size only lands at its alignment when the unit's storage begins there. The
// read-only data needs it for the same reason and not only for an object's
// address: a compiler loads a sixteen-byte constant with one instruction that
// faults on a misaligned place, and strings and constants share the section.
pub fn lay(units []image.Program, globals_alignment int, read_only_alignment int) Layout {
	mut layout := Layout{
		text_bases:     []int{cap: units.len}
		string_bases:   []int{cap: units.len}
		eh_frame_bases: []int{cap: units.len}
		globals_bases:  []int{cap: units.len}
		tls_bases:      []int{cap: units.len}
		init_bases:     []int{cap: units.len}
		fini_bases:     []int{cap: units.len}
		init_run_bases: []int{cap: units.len}
		fini_run_bases: []int{cap: units.len}
		tls_alignment:  1
	}
	// Each fragment lands at the end of its run so far, at the alignment it asks
	// for, which is what puts the fragment that opens `.init` and the one that
	// closes it next to each other when no other unit carries one.
	for unit in units {
		layout.init_run_len = align_up(layout.init_run_len, run_alignment(unit.init_run))
		layout.init_run_bases << layout.init_run_len
		layout.init_run_len += unit.init_run.len
	}
	layout.fini_run_base = layout.init_run_len
	for unit in units {
		layout.fini_run_len = align_up(layout.fini_run_len, run_alignment(unit.fini_run))
		layout.fini_run_bases << layout.init_run_len + layout.fini_run_len
		layout.fini_run_len += unit.fini_run.len
	}
	layout.text_len = layout.init_run_len + layout.fini_run_len
	step := if globals_alignment > 0 { globals_alignment } else { 1 }
	string_step := if read_only_alignment > 0 { read_only_alignment } else { 1 }
	// The gathered `.eh_frame` fragments come first in the merged read-only
	// data, one after another in unit order, because a scan that starts at one
	// of them has to reach the rest: the unwinder reads the table from the
	// fragment a start file points at and stops at the first record whose
	// length is zero. The fragments are packed byte to byte, the way a link packs
	// them into one output section, because a gap of zero bytes ends the scan.
	for unit in units {
		run := unit.eh_frame_run
		alignment := if run.alignment > 1 { run.alignment } else { 1 }
		layout.eh_frame_len = align_up(layout.eh_frame_len, alignment)
		layout.eh_frame_bases << layout.eh_frame_len
		layout.eh_frame_len += run.len
	}
	layout.string_len = layout.eh_frame_len
	for unit in units {
		layout.text_bases << layout.text_len
		layout.text_len += unit.text.len
		layout.string_len = align_up(layout.string_len, string_step)
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
fn run_alignment(run image.CodeRun) int {
	return if run.alignment > 1 { run.alignment } else { 1 }
}

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
