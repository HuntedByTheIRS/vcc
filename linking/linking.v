module linking

import backend
import backend.os.linux
import image
import linking.place
import linking.reloc
import linking.symbols

// The in-house linker's merge: the units of one link in, the single program a
// container writes out. A run of the compiler emits one unit per translation
// unit, and the driver emits the process stub as one more, so a link is handed
// programs that were each laid out from offset zero and asked to place them one
// after another and settle the references between them.
//
// The merge is four questions in order, and each one has its own module: which
// names the units define and where (`symbols/`), where each unit's data lands
// (`place/`), how each reference moves with it (`reloc/`), and what wraps the
// result (`output/`). A name is resolved through a map and never by scanning the
// units, because the reference count of a real link is what decides whether this
// stays linear.

// Options is what the caller asks a link for. The frozen shape the driver is
// written against: `entry` names the function the process stub calls and is used
// for one diagnostic, and the rest is the command line's own material carried
// through to the container.
pub struct Options {
pub:
	// entry is the name of the function the process stub calls. It is used for
	// one diagnostic: a link none of whose units defines it.
	entry  string
	target backend.Target
	// libraries are the -l names the command line gave, in order.
	libraries []string
	// library_dirs are the -L directories, in order.
	library_dirs []string
}

// link merges the units of one link into a single program. units[0] is the
// process stub, so text offset 0 is the stub and the image's entry point is
// text offset 0. Every unit was emitted with codegen's link mode.
pub fn link(units []image.Program, options Options) !image.Program {
	if units.len == 0 {
		return error('a link has no units')
	}
	// The names come first: their resolution is what decides which unit's
	// storage an object binds to and which references are bound at all.
	names := symbols.collect(units)!
	// A shared object has no entry: nothing starts it, so there is no name to
	// resolve here and no diagnostic to make about one. An empty entry is how
	// the caller says that, and the container writes an entry point of zero for
	// that kind of link.
	if options.entry != '' {
		entry := names.definitions[options.entry] or {
			return error('no definition of ${options.entry} in any unit of the link')
		}
		if !entry.function {
			return error('the entry ${options.entry} names an object and not a function')
		}
	}
	layout := place.lay(units, names.globals_alignment)
	read_only := merge_read_only(units, layout)
	// bound is the truth a reference is answered from: the names whose definition
	// is inside this image. It is built before the copy list is filtered, because
	// a name both lists carry is one the filtering has to drop from the copies.
	bound := bind(units, layout, names)!
	// The references a unit carried as relocations are merged like its fixups,
	// and the imported functions among them need a stub: a unit read back from
	// a relocatable object reaches a library function with a direct branch, and
	// a direct branch cannot read the value a slot holds, so the container gives
	// each such name a stub and the call goes there instead.
	merged_relocations := merge_relocations(units, layout)
	mut plts := []string{}
	for relocation in merged_relocations {
		// A reference that goes through the global offset table reads the
		// table's slot, not a stub, and a direct branch to a name the link
		// defines reaches it without either.
		if relocation.kind != .direct {
			continue
		}
		if is_section_key(relocation.name) {
			continue
		}
		if relocation.name in names.definitions {
			continue
		}
		if relocation.name in names.object_imports {
			// A direct reference to an object in a shared library would have
			// to read the object's address out of the table, which is a
			// reference this linker does not build. It is named rather than
			// pointed at a wrong address.
			return error('${relocation.name} is an object a relocatable object reaches through the global offset table, and this linker builds no such reference: -external-linker links an input this compiler cannot place yet')
		}
		if relocation.name in names.imports && relocation.name !in plts {
			plts << relocation.name
		}
	}
	mut copies := []string{cap: names.copy_objects.len}
	for name in names.copy_objects {
		// A copy object a unit defines is not a copy any more: the image holds
		// the object itself, and the loader is not asked to fill it.
		if name !in names.definitions {
			copies << name
		}
	}
	mut merged := image.Program{
		text:              merge_text(units, layout)
		labels:            merge_labels(units, layout)
		string_blob:       read_only.blob
		strings:           read_only.strings
		wide_strings:      read_only.wide_strings
		doubles:           read_only.doubles
		globals_blob:      merge_globals_blob(units, layout)
		globals:           merge_globals(units, layout, names.definitions)
		globals_alignment: names.globals_alignment
		defined:           names.defined
		weak:              names.weak
		internal:          names.internal
		imports:           names.imports
		object_imports:    names.object_imports
		libraries:         names.libraries
		copy_objects:      copies
		bound:             bound
		fixups:            merge_fixups(units, layout)
		data_fixups:       merge_data_fixups(units, layout, names.definitions)
		relocations:       merged_relocations
		plts:              plts
	}
	// Every reference that is still external has to be answerable by a library
	// the image names, or the program dies at load with nothing on the
	// compiler's stderr. The copies are checked beside the imports because a
	// copy is a name the loader has to find too, even though it is not an
	// import in the image. The check is the one codegen already makes, so the
	// message is its message.
	mut requested := []string{cap: names.imports.len + copies.len}
	for name in names.imports {
		if name !in bound {
			requested << name
		}
	}
	for name in copies {
		if name !in requested {
			requested << name
		}
	}
	dirs := linux.search_dirs(options.library_dirs, options.target.library_dirs)
	unresolved := linux.unresolved_imports(requested, options.libraries, dirs)
	if unresolved.len > 0 {
		return error('undefined reference to `${unresolved[0]}`: no library the image names defines it')
	}
	return merged
}

// merge_text builds the merged text at its final length and copies each unit in
// at its base. The units are read in the order they were given and the bases are
// the layout's, so the same units produce the same bytes every run. A second
// full copy of a unit is never kept: its bytes move into this blob once.
fn merge_text(units []image.Program, layout place.Layout) []u8 {
	mut text := []u8{len: layout.text_len}
	for i, unit in units {
		fill(mut text, layout.text_bases[i], unit.text)
	}
	return text
}

// merge_labels unions the units' labels, each moved by its unit's text base, so
// that a reference in the merged code finds the same place it named inside its
// unit. A label is public when it names a function the unit defines with
// external linkage; everything else is private to the unit, which is a `static`
// function's entry and every jump label the emitter made. The emitter numbers
// its jump labels from zero in each unit, so two units can both hold a `.L0`
// naming a different place, and a private label is keyed by its unit for that
// reason. A public key is the name itself and the first unit to name it keeps
// it, because two units naming one public function is the emitter's to prevent
// rather than something a link can reconcile after the fact.
fn merge_labels(units []image.Program, layout place.Layout) map[string]int {
	mut labels := map[string]int{}
	for i, unit in units {
		for name, offset in unit.labels {
			key := if name in unit.defined && name !in unit.internal {
				name
			} else {
				symbols.private_key(i, name)
			}
			if key !in labels {
				labels[key] = offset + layout.text_bases[i]
			}
		}
	}
	return labels
}

// ReadOnly is the one read-only blob and the three tables that point into it.
// A string, a wide string, and a double all live in the same bytes and are
// looked up in their own table, which is the shape one unit already has, so the
// merge keeps the tables apart and only moves their offsets.
struct ReadOnly {
	blob         []u8
	strings      map[string]int
	wide_strings map[string]int
	doubles      map[string]int
}

// merge_read_only concatenates the units' read-only data at its final length and
// rebases each of the three tables into it. A table is keyed by the bytes or the
// bit pattern the entry stands for, so two units holding the same entry hold the
// same thing and the first unit's offset is as good as the second's.
fn merge_read_only(units []image.Program, layout place.Layout) ReadOnly {
	mut blob := []u8{len: layout.string_len}
	mut strings := map[string]int{}
	mut wide_strings := map[string]int{}
	mut doubles := map[string]int{}
	for i, unit in units {
		base := layout.string_bases[i]
		fill(mut blob, base, unit.string_blob)
		for name, offset in unit.strings {
			if name !in strings {
				strings[name] = offset + base
			}
		}
		for name, offset in unit.wide_strings {
			if name !in wide_strings {
				wide_strings[name] = offset + base
			}
		}
		for name, offset in unit.doubles {
			if name !in doubles {
				doubles[name] = offset + base
			}
		}
	}
	return ReadOnly{
		blob:         blob
		strings:      strings
		wide_strings: wide_strings
		doubles:      doubles
	}
}

// merge_globals_blob concatenates the units' writable data at its final length.
// The layout put each unit at its alignment, so the gaps between units are the
// padding that makes those alignments true, and they stay zero.
fn merge_globals_blob(units []image.Program, layout place.Layout) []u8 {
	mut blob := []u8{len: layout.globals_len}
	for i, unit in units {
		fill(mut blob, layout.globals_bases[i], unit.globals_blob)
	}
	return blob
}

// merge_globals rebases each top-level object's slot into the merged writable
// data. A name one unit defines binds to that unit's slot; a name no unit
// defines is a copy of a library's object and the first unit to name it keeps
// its storage. Reading the defining unit's slot matters: a unit that only names
// an `extern` object has a slot of its own, and binding a reference to that
// storage instead of the object's is a wrong address rather than a loud failure.
// An object with internal linkage is private to its unit, so two units may each
// hold a `static` object of one name; such a slot is keyed by its unit, the same
// key symbols.collect recorded its definition under, and the definition lookup
// uses that key or it would read another unit's answer.
fn merge_globals(units []image.Program, layout place.Layout, definitions map[string]symbols.Definition) map[string]image.GlobalSlot {
	mut globals := map[string]image.GlobalSlot{}
	for i, unit in units {
		for name, slot in unit.globals {
			key := if name in unit.internal { symbols.private_key(i, name) } else { name }
			if definition := definitions[key] {
				if definition.function || definition.unit != i {
					continue
				}
			} else if key in globals {
				continue
			}
			globals[key] = image.GlobalSlot{
				offset:   slot.offset + layout.globals_bases[i]
				width:    slot.width
				count:    slot.count
				object:   slot.object
				floating: slot.floating
				single:   slot.single
				unsigned: slot.unsigned
			}
		}
	}
	return globals
}

// merge_fixups sizes the merged reference list once and has each unit append its
// rewritten references, so no per-unit array is built only to be copied again.
fn merge_fixups(units []image.Program, layout place.Layout) []image.Fixup {
	mut count := 0
	for unit in units {
		count += unit.fixups.len
	}
	mut fixups := []image.Fixup{cap: count}
	for i, unit in units {
		reloc.fixups(unit, i, layout.text_bases[i], mut fixups)
	}
	return fixups
}

// merge_data_fixups is the same for the references in the writable data, which
// also need the definitions because a bound name changes the kind of reference
// the container writes.
fn merge_data_fixups(units []image.Program, layout place.Layout, definitions map[string]symbols.Definition) []image.DataFixup {
	mut count := 0
	for unit in units {
		count += unit.data_fixups.len
	}
	mut fixups := []image.DataFixup{cap: count}
	for i, unit in units {
		reloc.data_fixups(unit, i, layout.globals_bases[i], layout.text_bases[i],
			layout.string_bases[i], definitions, mut fixups)
	}
	return fixups
}

// merge_relocations sizes the merged relocation list once and has each unit
// append its rewritten references, the way merge_fixups does for the references
// the emitter left as fixups.
fn merge_relocations(units []image.Program, layout place.Layout) []image.Relocation {
	mut count := 0
	for unit in units {
		count += unit.relocations.len
	}
	mut relocations := []image.Relocation{cap: count}
	for i, unit in units {
		reloc.relocations(unit, i, layout.text_bases[i], layout.string_bases[i],
			layout.globals_bases[i], mut relocations)
	}
	return relocations
}

// is_section_key says whether a relocation's name is one of a unit's own section
// keys rather than a symbol. Such a name points at a place in a merged blob and
// never at a symbol table entry, so it is not a name a stub or a library check
// can be asked about.
fn is_section_key(name string) bool {
	return name == image.section_key_text || name == image.section_key_rodata
		|| name == image.section_key_data
}

// bind answers, for each name the image needs and one of its units defines, where
// the definition is. An import that is a definition is bound; a copy object that
// is a definition is bound too, which is why both lists are walked. The offset
// points into the merged text for a function and into the merged writable data
// for an object, which is the one place a caller can turn it back into an
// address.
fn bind(units []image.Program, layout place.Layout, names symbols.Names) !map[string]image.Definition {
	mut bound := map[string]image.Definition{}
	for name in names.imports {
		if name in names.definitions {
			bound[name] = definition_at(units, layout, names.definitions[name], name)!
		}
	}
	for name in names.copy_objects {
		if name in names.definitions && name !in bound {
			bound[name] = definition_at(units, layout, names.definitions[name], name)!
		}
	}
	return bound
}

// definition_at is where one resolved definition lives in the merged program.
// A function's place is its label, which every unit records for the functions it
// defines; an object's is its slot in the unit's writable data.
fn definition_at(units []image.Program, layout place.Layout, definition symbols.Definition, name string) !image.Definition {
	if definition.function {
		offset := units[definition.unit].labels[name] or {
			return error('the link binds ${name} to a function unit ${definition.unit} defines and has no label for')
		}
		return image.Definition{
			offset:   offset + layout.text_bases[definition.unit]
			function: true
		}
	}
	slot := units[definition.unit].globals[name] or {
		return error('the link binds ${name} to an object unit ${definition.unit} defines and has no storage for')
	}
	return image.Definition{
		offset:   slot.offset + layout.globals_bases[definition.unit]
		function: false
	}
}

// fill copies one unit's bytes into the merged blob at the base it was placed
// at. It is a byte loop rather than a growing array because the blob is already
// the length it will be, and appending per unit is what the layout exists to
// avoid.
fn fill(mut dst []u8, at int, src []u8) {
	for i, byte in src {
		dst[at + i] = byte
	}
}
