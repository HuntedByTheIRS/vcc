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

// relocations appends one unit's rewritten relocations to the merged list. A
// field moves with the blob it lies in, so its offset gains that blob's base,
// which is what the place it carries names. Its name is keyed the way the merged
// tables key it. A reference into one of the unit's own sections gains that
// section's base in the addend, because the object measured the byte from the
// start of its own copy of the section and the merged copy starts somewhere
// else; a section key keeps its spelling, since the container reads it as a
// place in a merged blob rather than as a symbol.
pub fn relocations(unit image.Program, unit_index int, text_base int, string_base int, globals_base int, mut out []image.Relocation) {
	for relocation in unit.relocations {
		mut addend := relocation.addend
		mut name := relocation.name
		place_base := match relocation.place {
			.text { text_base }
			.read_only { string_base }
			.data { globals_base }
		}
		match relocation.name {
			image.section_key_text {
				addend += text_base
			}
			image.section_key_rodata {
				addend += string_base
			}
			image.section_key_data {
				addend += globals_base
			}
			else {
				name = label_key(unit, unit_index, relocation.name)
			}
		}
		out << image.Relocation{
			offset: relocation.offset + place_base
			place:  relocation.place
			kind:   relocation.kind
			name:   name
			addend: addend
		}
	}
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

// label_key is the key a label reference is written under, which has to be the
// key the merged table holds its target under. A name this unit carries no label
// for is not one of its own: the process stub's one code reference calls the
// entry function, which another unit defines, and the merged table holds a name
// with external linkage bare. A name this unit does label is its own, and it is
// private unless it is a function of this unit with external linkage, which the
// whole link names.
fn label_key(unit image.Program, unit_index int, name string) string {
	if name !in unit.labels {
		return name
	}
	if name in unit.defined && name !in unit.internal {
		return name
	}
	return symbols.private_key(unit_index, name)
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
