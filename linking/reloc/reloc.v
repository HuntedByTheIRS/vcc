module reloc

import image
import linking.symbols

// Rewriting one unit's references for the merged image. A unit wrote every
// reference as an offset inside the one blob it was building, so the merge moves
// it by the base the unit was placed at. A reference that names a unit's own
// private definition also changes its name: the merged tables key a private
// label or object by its unit, so the reference has to be written the same way
// or it answers against another unit's entry. Everything else keeps its name,
// because the merged tables are keyed by name; only a kind changes, and only
// where a link turns a reference into one the container writes itself.

// Tables is where one unit's two constructor tables land in the merged writable
// data, and where they began in the unit. A table's entries do not move with the
// unit's writable data: the tables of every unit are placed together at the end
// of the blob, so a field inside one moves to the table's new place instead. The
// zero value says the unit has no table of that kind.
pub struct Tables {
pub:
	init_base   int
	init_offset int
	init_count  int
	fini_base   int
	fini_offset int
	fini_count  int
}

// relocations appends one unit's rewritten relocations to the merged list. A
// field moves with the blob it lies in, so its offset gains that blob's base,
// which is what the place it carries names, except for a field inside one of the
// unit's constructor tables, which moves to the merged table. Its name is keyed
// the way the merged tables key it. A reference into one of the unit's own
// sections gains that section's base in the addend, because the object measured
// the byte from the start of its own copy of the section and the merged copy
// starts somewhere else; a section key keeps its spelling, since the container
// reads it as a place in a merged blob rather than as a symbol. How wide the
// field is comes across unchanged, because the container writes that many bytes.
pub fn relocations(unit image.Program, unit_index int, text_base int, string_base int, globals_base int, tls_base int, init_run_base int, fini_run_base int, eh_frame_base int, tables Tables, mut out []image.Relocation) {
	for relocation in unit.relocations {
		mut addend := relocation.addend
		mut name := relocation.name
		place_base := match relocation.place {
			.text { text_base }
			.read_only { string_base }
			.data { globals_base }
			// A field in the thread-local image moves with the unit's own part
			// of the merged thread-local block, which is a third place the
			// merge lays out rather than one of the two data blobs.
			.tls { tls_base }
		}
		mut field := relocation.offset + place_base
		// A field inside one of the two gathered fragments moves with the
		// fragment, which the merge placed with the other units' fragments rather
		// than with its own unit's text.
		if relocation.place == .text {
			field = text_field(unit, relocation.offset, text_base, init_run_base, fini_run_base)
		}
		// A field inside the unit's `.eh_frame` fragment moves with the gathered
		// table, which the merge laid out with the other units' fragments rather
		// than where this unit's read-only data landed.
		if relocation.place == .read_only {
			if at := eh_frame_field(unit, relocation.offset, eh_frame_base) {
				field = at
			}
		}
		if relocation.place == .data {
			if at := table_field(relocation.offset, tables) {
				field = at
			}
		}
		match relocation.name {
			image.section_key_text {
				addend += text_base
			}
			image.section_key_rodata {
				if at := eh_frame_field(unit, addend, eh_frame_base) {
					addend = at
				} else {
					addend += string_base
				}
			}
			image.section_key_data {
				addend += globals_base
			}
			else {
				name = label_key(unit, unit_index, relocation.name)
			}
		}
		out << image.Relocation{
			offset: field
			place:  relocation.place
			kind:   relocation.kind
			name:   name
			addend: addend
			width:  relocation.width
		}
	}
}

// text_field is where a field at `offset` in the unit's code lands in the merged
// code: inside the run the merge gathered the fragment into, when the offset is
// within one of the two fragments it moves, and at the unit's own text base
// otherwise.
// eh_frame_field is where a field at `offset` in a unit's read-only data lands
// when it is inside the part of it that is this unit's `.eh_frame` fragment. The
// merge gathers those fragments into one table, and a scan from any one of them
// has to reach the rest, so a field inside one moves with it.
fn eh_frame_field(unit image.Program, offset int, eh_frame_base int) ?int {
	run := unit.eh_frame_run
	if run.base < 0 || offset < run.base || offset > run.base + run.len {
		return none
	}
	return eh_frame_base + (offset - run.base)
}

fn text_field(unit image.Program, offset int, text_base int, init_run_base int, fini_run_base int) int {
	if unit.init_run.len > 0 && offset >= unit.init_run.base
		&& offset < unit.init_run.base + unit.init_run.len {
		return init_run_base + (offset - unit.init_run.base)
	}
	if unit.fini_run.len > 0 && offset >= unit.fini_run.base
		&& offset < unit.fini_run.base + unit.fini_run.len {
		return fini_run_base + (offset - unit.fini_run.base)
	}
	return text_base + offset
}

// table_field is where a field at `offset` in the unit's writable data lands when
// it is one of a constructor table's entries: the merged table is somewhere else
// in the blob, and the entry keeps its place within its own table. None means the
// field is not in a table and moves with the unit's data.
fn table_field(offset int, tables Tables) ?int {
	if tables.init_count > 0 && offset >= tables.init_offset
		&& offset < tables.init_offset + tables.init_count * 8 {
		return tables.init_base + (offset - tables.init_offset)
	}
	if tables.fini_count > 0 && offset >= tables.fini_offset
		&& offset < tables.fini_offset + tables.fini_count * 8 {
		return tables.fini_base + (offset - tables.fini_offset)
	}
	return none
}

// fixups appends one unit's rewritten code references to the merged list. The
// caller sizes that list once so no intermediate array is built per unit.
pub fn fixups(unit image.Program, unit_index int, text_base int, mut out []image.Fixup) {
	for fixup in unit.fixups {
		out << image.Fixup{
			start:    fixup.start + text_base
			length:   fixup.length
			kind:     fixup.kind
			name:     reference_name(unit, unit_index, fixup.kind, fixup.name)
			register: fixup.register
		}
	}
}

// data_fixups appends one unit's rewritten writable-data references to the merged
// list. A reference to a name this link binds cannot be left to the loader: a
// bound name is not a dynamic symbol, so no relocation will fill its slot. The
// container writes the address itself at layout time for the two kinds that name
// an address inside the image, so a data reference to a bound name becomes the
// one of those its definition calls for, a function address for a function and a
// global address for an object. Every other kind is carried across unchanged.
//
// A bound name keeps its bare name on purpose: its definition is external, so
// the merged table holds it under that name and the rewrite would have nothing
// to find. A reference that already names a function or an object this unit
// defines, and that definition is private, is renamed to the key the merged
// table holds it under.
pub fn data_fixups(unit image.Program, unit_index int, globals_base int, text_base int, string_base int, definitions map[string]symbols.Definition, mut out []image.DataFixup) {
	for fixup in unit.data_fixups {
		mut kind := fixup.kind
		mut name := fixup.name
		mut addend := fixup.addend
		if fixup.kind == .import_address {
			if definition := definitions[fixup.name] {
				kind = if definition.function { .function_address } else { .global_address }
			}
		} else if fixup.kind == .function_address {
			name = label_key(unit, unit_index, fixup.name)
		} else if fixup.kind == .global_address {
			name = object_key(unit, unit_index, fixup.name)
		} else if fixup.kind == .section_address {
			// A section key names a place in one of the unit's own blobs, and
			// the object measured the byte from its own copy of that blob. The
			// merged copy starts elsewhere, so the byte gains its blob's base.
			match name {
				image.section_key_text {
					addend += text_base
				}
				image.section_key_rodata {
					addend += string_base
				}
				image.section_key_data {
					addend += globals_base
				}
				else {}
			}
		}
		out << image.DataFixup{
			offset: fixup.offset + globals_base
			kind:   kind
			name:   name
			addend: addend
		}
	}
}

// reference_name is the name a code reference is written under in the merged
// program. The kinds that name a label take label_key, the one that names a
// top-level object takes object_key, and every other kind names string content
// or a bit pattern rather than a unit symbol, so it is left alone. A call or an
// address of an import is left alone too: an import is never private.
fn reference_name(unit image.Program, unit_index int, kind image.FixupKind, name string) string {
	match kind {
		.call_local, .jump_local, .branch_zero, .branch_nonzero, .function_address {
			return label_key(unit, unit_index, name)
		}
		.global_address {
			return object_key(unit, unit_index, name)
		}
		else {
			return name
		}
	}
}

// label_key is the key a reference is written under, which has to be the key the
// merged tables hold its target under. A name the unit gives internal linkage is
// private, and it is keyed by the unit whether it names code, an object in the
// writable data, an object in the read-only data or a thread-local: two units
// may each hold a `static` of one name, and those are two definitions with
// storage of their own. A jump label the emitter made is private for the same
// reason, because the emitter numbers its labels from zero in each unit and two
// units hold a `.L0` naming a different place. A public definition keeps its
// bare name, and so does a name this unit does not hold at all: the process
// stub's one code reference calls the entry function, which another unit
// defines.
fn label_key(unit image.Program, unit_index int, name string) string {
	if name in unit.internal {
		return symbols.private_key(unit_index, name)
	}
	if name in unit.labels && name !in unit.defined {
		return symbols.private_key(unit_index, name)
	}
	return name
}

// object_key is the same for a reference to a top-level object: internal
// linkage makes the storage private to the unit and the reference takes the
// unit's key, and anything else keeps the merged table's own name.
fn object_key(unit image.Program, unit_index int, name string) string {
	if name in unit.internal {
		return symbols.private_key(unit_index, name)
	}
	return name
}
