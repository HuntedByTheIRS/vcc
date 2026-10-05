module symbols

import image

// The names of one link: the union of the units' symbol tables, with the
// definitions resolved to the one unit each name binds to.
//
// A reference inside one unit is written against that unit's tables, and after
// the units are merged it has to be answered against the merged ones. The work
// is the same for every reference, so it is done once here and read back from a
// map rather than by walking the units again per name: a link of V's own objects
// has a reference count in the hundreds of thousands, and a scan per reference
// would make the cost quadratic in what the link was handed.

// Definition is where a name is defined: which of the units, and whether the
// definition is a function in the unit's text or an object in its writable data.
// weak is the binding the definition was written with, and it is what decides
// which of two definitions of one name wins.
pub struct Definition {
pub:
	unit     int
	function bool
	weak     bool
}

// Names is what the units define, need, and name, collected into one answer.
pub struct Names {
pub mut:
	// definitions is every name a unit defines, resolved to the one unit a
	// reference binds to. It holds functions and objects alike, because a
	// reference in the writable data can name either.
	definitions map[string]Definition
	// defined is the union of the units' `defined`: every function the image
	// defines. It becomes the merged program's field of the same name.
	defined map[string]bool
	// weak is the names whose resolved definition is weak. A name some unit
	// defines weakly and another strongly is not weak here, because the strong
	// definition is the one the image holds.
	weak map[string]bool
	// internal is the union of the names any unit gives internal linkage, which
	// a file-scope `static` asks for (6.2.2p3).
	internal map[string]bool
	// imports is the union of the units' imports in first-seen order, the order
	// the -l names and the references were first written in. It keeps a bound
	// name, because a call to one still reaches it through a slot.
	imports []string
	// object_imports is the union of the units' object_imports. It stays a
	// subset of `imports`, which is what the field means in one unit.
	object_imports map[string]bool
	// libraries is the union of the units' libraries in first-seen order.
	libraries []string
	// copy_objects is the union of the units' copy_objects in first-seen order,
	// before the ones a unit defines are dropped.
	copy_objects []string
	// globals_alignment is the strictest alignment any unit asked for, which is
	// where the merged writable data has to start.
	globals_alignment int
}

// collect builds the union of the units' symbol tables and resolves each name a
// unit defines to the one definition a reference binds to. A name two units
// define is an error unless one definition is weak, which is the rule a link
// applies and the reason a conflict is reported here and not at the reference.
pub fn collect(units []image.Program) !Names {
	mut names := Names{
		definitions:    map[string]Definition{}
		defined:        map[string]bool{}
		weak:           map[string]bool{}
		internal:       map[string]bool{}
		object_imports: map[string]bool{}
	}
	for i, unit in units {
		for name, _ in unit.defined {
			names.defined[name] = true
			record(mut names.definitions, name, i, true, unit.weak[name])!
		}
		// A name in `globals` is a definition only when this unit holds its
		// storage. A unit that merely names an `extern` object puts a slot in
		// `globals` too, and records the name in `copy_objects` to say the
		// storage is a copy of a library's. Such a name is not a definition
		// here, and the unit that defines it is the one that has a slot and no
		// copy record.
		for name, _ in unit.globals {
			if name in unit.copy_objects {
				continue
			}
			record(mut names.definitions, name, i, false, unit.weak[name])!
		}
		for name, _ in unit.internal {
			names.internal[name] = true
		}
		for name in unit.imports {
			if name !in names.imports {
				names.imports << name
			}
		}
		for name, _ in unit.object_imports {
			if name in names.imports {
				names.object_imports[name] = true
			}
		}
		for name in unit.libraries {
			if name !in names.libraries {
				names.libraries << name
			}
		}
		for name in unit.copy_objects {
			if name !in names.copy_objects {
				names.copy_objects << name
			}
		}
		if unit.globals_alignment > names.globals_alignment {
			names.globals_alignment = unit.globals_alignment
		}
	}
	// The weak names are the ones the resolved definition carries, not the ones
	// any unit wrote: a strong definition of a name another unit wrote weak is
	// the definition the image holds, and the name is not weak in the image.
	for name, definition in names.definitions {
		if definition.weak {
			names.weak[name] = true
		}
	}
	return names
}

// record settles one definition of one name. A strong definition replaces a weak
// one, a weak definition leaves a strong one in place, two weak definitions keep
// the first, and two strong definitions are what a link refuses by name.
fn record(mut definitions map[string]Definition, name string, unit int, function bool, weak bool) ! {
	definition := Definition{
		unit:     unit
		function: function
		weak:     weak
	}
	if existing := definitions[name] {
		if existing.weak && !weak {
			definitions[name] = definition
			return
		}
		if weak {
			return
		}
		return error('multiple definition of `${name}`')
	}
	definitions[name] = definition
}
