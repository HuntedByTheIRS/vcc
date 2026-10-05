module reloc

import image
import linking.symbols

// Rewriting one unit's references for the merged image. A unit wrote every
// reference as an offset inside the one blob it was building, so the merge moves
// it by the base the unit was placed at. The names stay as they were, because
// the merged tables are keyed by name; only a kind changes, and only where a
// link turns a reference into one the container writes itself.

// fixups appends one unit's rewritten code references to the merged list. The
// caller sizes that list once so no intermediate array is built per unit.
pub fn fixups(unit image.Program, text_base int, mut out []image.Fixup) {
	for fixup in unit.fixups {
		out << image.Fixup{
			start:    fixup.start + text_base
			length:   fixup.length
			kind:     fixup.kind
			name:     fixup.name
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
pub fn data_fixups(unit image.Program, globals_base int, definitions map[string]symbols.Definition, mut out []image.DataFixup) {
	for fixup in unit.data_fixups {
		mut kind := fixup.kind
		if fixup.kind == .import_address {
			if definition := definitions[fixup.name] {
				kind = if definition.function { .function_address } else { .global_address }
			}
		}
		out << image.DataFixup{
			offset: fixup.offset + globals_base
			kind:   kind
			name:   fixup.name
			addend: fixup.addend
		}
	}
}
