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
	}
	return layout
}
