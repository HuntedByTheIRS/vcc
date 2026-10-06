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
	// tls says the definition is a thread-local rather than a function or an
	// object in the writable data: its offset counts from the start of the
	// image's thread-local block, which is where a local-exec reference to it
	// measures from, and every thread gets its own copy of the storage.
	tls bool
	// read_only says the definition is an object in read-only data, which is
	// what a `const` object at file scope is. Its offset counts from the start
	// of the merged read-only data rather than from the writable data, so a
	// reference to it lands on the bytes the definition wrote.
	read_only bool
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
	// weak_imports is the union of the units' weak_imports: every name in
	// `imports` a unit named weakly and none defines. A link does not have to
	// answer one - an undefined weak symbol stands for zero - so these names
	// are left out of the libraries a link asks and the merged image writes
	// them with the weak binding.
	weak_imports map[string]bool
	// tls_slots is the union of the units' tls_slots: every name whose global
	// offset table slot holds how far a thread-local lies below the thread
	// pointer rather than its address. The merged image writes those slots as
	// numbers, so the fact has to survive the merge.
	tls_slots map[string]bool
	// libraries is the union of the units' libraries in first-seen order.
	libraries []string
	// copy_objects is the union of the units' copy_objects in first-seen order,
	// before the ones a unit defines are dropped.
	copy_objects []string
	// globals_alignment is the strictest alignment any unit asked for, which is
	// where the merged writable data has to start.
	globals_alignment int
	// read_only_alignment is the same for the read-only data, which is where the
	// merged read-only data has to start for a section inside it to keep its own
	// alignment.
	read_only_alignment int
}

// private_key is the name a unit's own private definition is recorded under. A
// local label and a name with internal linkage belong to one unit and to no
// other, so two units may hold one each and neither may answer for the other. A
// C identifier cannot hold a colon, so a key built this way cannot meet a name
// a program wrote.
pub fn private_key(unit int, name string) string {
	return '${unit}:${name}'
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
		weak_imports:   map[string]bool{}
		tls_slots:      map[string]bool{}
	}
	for i, unit in units {
		for name, _ in unit.defined {
			names.defined[name] = true
			// A function with internal linkage belongs to its unit and to no
			// other, so it is recorded under a key no other unit can name. Two
			// units may each hold a `static` function of one name, and that is
			// two definitions rather than the multiple definition a link
			// refuses. Recording it under the bare name would also let it
			// satisfy another unit's import of the same name, which internal
			// linkage does not do (6.2.2p2).
			key := if name in unit.internal { private_key(i, name) } else { name }
			record(mut names.definitions, key, Definition{
				unit:     i
				function: true
				weak:     unit.weak[name]
			})!
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
			// A thread-local is not storage in the writable data, and a unit
			// that carries one records it in `tls_labels` instead, which the
			// loop below reads. It is skipped here so one name is not two
			// definitions of one unit.
			if name in unit.tls_labels {
				continue
			}
			// An object with internal linkage is private for the same reason
			// the function above is: two units may each hold a `static` object
			// of one name, and they are two objects with storage of their own.
			key := if name in unit.internal { private_key(i, name) } else { name }
			record(mut names.definitions, key, Definition{
				unit: i
				weak: unit.weak[name]
			})!
		}
		// An object in read-only data is a definition too, and it is the one a
		// `const` object at file scope makes: one unit writes the bytes, another
		// names them, and the reference has to land on the merged read-only data
		// rather than on the writable data a non-const object would live in.
		for name, _ in unit.read_only_globals {
			key := if name in unit.internal { private_key(i, name) } else { name }
			record(mut names.definitions, key, Definition{
				unit:      i
				weak:      unit.weak[name]
				read_only: true
			})!
		}
		// A thread-local a unit defines is a definition like any other: the
		// name binds to the unit that holds the storage, and the offset it
		// answers with counts from the merged block rather than from a blob.
		for name, _ in unit.tls_labels {
			key := if name in unit.internal { private_key(i, name) } else { name }
			record(mut names.definitions, key, Definition{
				unit: i
				weak: unit.weak[name]
				tls:  true
			})!
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
		for name, _ in unit.weak_imports {
			names.weak_imports[name] = true
		}
		for name, _ in unit.tls_slots {
			names.tls_slots[name] = true
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
		if unit.read_only_alignment > names.read_only_alignment {
			names.read_only_alignment = unit.read_only_alignment
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
fn record(mut definitions map[string]Definition, name string, definition Definition) ! {
	if existing := definitions[name] {
		if existing.weak && !definition.weak {
			definitions[name] = definition
			return
		}
		if definition.weak {
			return
		}
		return error('multiple definition of `${name}`')
	}
	definitions[name] = definition
}
