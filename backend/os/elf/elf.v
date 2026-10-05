module elf

import backend
import backend.os.linux
import image

// The ELF64 container, in the shape Linux starts and its dynamic loader
// finishes. A program that calls a shared library is not a header and a code
// blob: the image has to name the loader that will finish the job (PT_INTERP),
// say which library it runs against (a DT_NEEDED entry in the PT_DYNAMIC table),
// and carry enough symbol information for the loader to find each function it
// calls and write its address where the code reads it: a .dynsym, the .hash the
// loader walks to learn how many symbols there are, a .rela.dyn with one
// relocation per imported function, and the slots those relocations fill.
//
// The image is built in one pass over a fixed order of parts, because every
// offset in it is the size of what came before: interpreter, code, string table,
// read-only data, symbol table, hash, slots, relocations, dynamic table. There
// is no section header table; the loader reads the program headers.
//
// The values the target owns (machine id, page size, load base, the loader's
// path) come from its table, so a second system changes the tables and not this
// file.

const elf_magic = [u8(0x7f), `E`, `L`, `F`]

// The constants a reader outside this module needs are `pub`. The class and data
// bytes are read by the library reader in `codegen/libraries.v`, out of objects
// other tools produced, and the naming constants below are read by the codegen
// tests, back out of an image this module wrote.
pub const elf_class_64 = u8(2)
pub const elf_data_little_endian = u8(1)
const elf_version_current = u8(1)
const elf_type_exec = u16(2)

const elf_header_size = u16(64)
const elf_program_header_size = u16(56)
// PT_INTERP, PT_LOAD, PT_DYNAMIC and PT_GNU_STACK, in that order, always all four.
const elf_program_header_count = u16(4)

// The program header types this container uses.
pub const elf_ph_type_load = u32(1)
pub const elf_ph_type_dynamic = u32(2)
pub const elf_ph_type_interp = u32(3)
const elf_ph_type_gnu_stack = u32(0x6474E551)

// The segment permissions, combined where a segment needs more than one.
const elf_ph_flags_execute = u32(1)
const elf_ph_flags_write = u32(2)
const elf_ph_flags_read = u32(4)

// The dynamic table's tags, from the System V ABI: what the loader is told about
// the program it has been handed.
pub const dt_null = u64(0)
pub const dt_needed = u64(1)
pub const dt_hash = u64(4)
pub const dt_strtab = u64(5)
pub const dt_symtab = u64(6)
pub const dt_rela = u64(7)
pub const dt_relasz = u64(8)
const dt_relaent = u64(9)
const dt_strsz = u64(10)
const dt_syment = u64(11)

// dynamic_entry_count is how many entries the dynamic table holds: the eight
// that describe the image's own tables, one DT_NEEDED per library it runs
// against, and the null that ends it. It is a function rather than a constant
// because the library count is not known until the command line has been read.
fn dynamic_entry_count(library_count int) int {
	return 9 + library_count
}

// A relocation that asks the loader to write a symbol's address into a slot.
pub const relocation_glob_dat = u64(6)
// A relocation that asks the loader to write a symbol's address into the eight
// bytes it names, which is what an imported function's address needs when it is
// the value of an object in the writable data rather than the target of a call.
// It is R_X86_64_64 in this machine's psABI: the symbol's value plus the addend,
// which is zero here.
pub const relocation_absolute = u64(1)
// A relocation that asks the loader to copy a symbol's value into this image:
// the bytes of the symbol's size at the place it names are the storage of an
// object another object defines, and the loader fills them from the library's
// definition. It is R_X86_64_COPY in this machine's psABI, the kind a program
// that is not position independent writes for a variable it names out of a
// shared library.
pub const relocation_copy = u64(5)

// The st_info byte of every symbol this image imports: global, and of function
// type. The symbols are undefined, which is to say the value comes from
// somewhere else.
pub const symbol_global_function = u8(0x12)
// The same byte with the weak binding (2) rather than global (1), which is what
// `__attribute__((weak))` on a definition asks the object to say about it.
pub const symbol_weak_function = u8(0x22)

// Symbols and relocations are fixed-size records in this container.
pub const elf_symbol_size = 24
pub const elf_relocation_size = 24
pub const elf_dynamic_entry_size = 16
// plt_stub_size is how long one call stub is: a jump through a displacement, and
// the four bytes of that displacement.
const plt_stub_size = 6

// Sections is where each part of the image landed, as a file offset from the
// start of the file. The image is one segment that starts at file offset zero,
// so a file offset and a virtual address differ by the load base and nothing
// else, which is what lets the references be patched in file-offset arithmetic.
struct Sections {
	interp int
	text   int
	// plt is the six-byte stub for each imported function an object reached by
	// a direct branch: the call goes to the stub and the stub jumps through the
	// import's slot. A program the emitter wrote in one piece has no stubs and
	// the area is empty.
	plt     int
	dynstr  int
	strings int
	// globals is the storage of the objects defined at the top level: the only
	// part of the image the program writes to as it runs.
	globals int
	dynsym  int
	hash    int
	got     int
	rela    int
	dynamic int
	total   int
}

// executable wraps a program in an ELF64 image that a Linux kernel can start and
// a dynamic loader can finish.
pub fn executable(program image.Program, target backend.Target) ![]u8 {
	base := target.load_base
	// The loader's path, with the terminator the kernel expects.
	mut interp := target.interpreter.bytes()
	interp << u8(0)
	// The libraries the image runs against: the C library first, wherever it
	// was asked for or not, then the ones the -l flags named, each once. A
	// library that is not named here is a library the loader does not map,
	// which is what an undefined symbol at load comes from.
	mut libraries := []string{cap: program.libraries.len + 1}
	libraries << linux.base_library
	for name in program.libraries {
		if name !in libraries {
			libraries << name
		}
	}
	// The string table: the null entry, the name of each imported symbol, and
	// the name of each library the image runs against.
	mut dynstr := []u8{}
	dynstr << u8(0)
	mut symbol_names := map[string]int{}
	for name in program.imports {
		symbol_names[name] = dynstr.len
		dynstr << name.bytes()
		dynstr << u8(0)
	}
	// The names of the objects this image holds a copy of come after the
	// imported functions, the same order their symbols stand in the table.
	for name in program.copy_objects {
		symbol_names[name] = dynstr.len
		dynstr << name.bytes()
		dynstr << u8(0)
	}
	// needed is where each library's name starts in the string table, in the
	// order the DT_NEEDED entries name them.
	mut needed := []int{}
	for name in libraries {
		needed << dynstr.len
		dynstr << name.bytes()
		dynstr << u8(0)
	}
	// How many of the imports a library has to answer for, and each import's
	// index in the dynamic symbol table. Both skip a name whose definition is
	// inside this image, and they are computed once here rather than a name at a
	// time in the emitters, so that every part of the image numbers the symbols
	// the same way.
	external := external_imports(program)
	indices := symbol_indices(program)
	sections := layout(program, target, interp.len, dynstr.len, libraries.len, external)
	// The image a Linux kernel starts is built here. The name is not `image`,
	// because that is the module whose Program this function was handed.
	mut output := []u8{len: sections.total, init: u8(0)}
	put(mut output, sections.interp, interp)
	put(mut output, sections.text, program.text)
	put(mut output, sections.dynstr, dynstr)
	put(mut output, sections.strings, program.string_blob)
	put(mut output, sections.globals, program.globals_blob)
	emit_bound_slots(mut output, program, sections, base)
	emit_symbols(mut output, program, sections, symbol_names, indices, external, base)
	emit_hash(mut output, program, sections, external)
	emit_relocations(mut output, program, sections, indices, external, base)
	emit_dynamic(mut output, program, sections, dynstr.len, needed, external, base)
	emit_header(mut output, target, base + u64(sections.text))
	emit_program_headers(mut output, target, sections, interp.len, libraries.len)
	patch(mut output, program, target, sections)!
	return output
}

// external_imports is how many of the program's names in `imports` a library
// has to answer for: every name that is not in `bound`. It is the count of
// symbols the dynamic table carries and of relocations the image emits, so the
// parts that size those tables ask it rather than `program.imports.len`, which
// counts the bound names too.
fn external_imports(program image.Program) int {
	mut count := 0
	for name in program.imports {
		if name !in program.bound {
			count++
		}
	}
	return count
}

// symbol_indices is each import's index in the dynamic symbol table, position
// for position with `program.imports`. The null symbol is index 0 and a name
// whose definition is inside this image is not in the table at all, so a name's
// index is one plus the number of external imports before it, which is not its
// position in `imports`. The two stop agreeing as soon as one import is bound.
// A call reads its slot by the position and a relocation names its symbol by
// this index, so the two are different numbers and must not be confused.
fn symbol_indices(program image.Program) []int {
	mut indices := []int{len: program.imports.len}
	mut next := 1
	for i, name in program.imports {
		if name in program.bound {
			continue
		}
		indices[i] = next
		next++
	}
	return indices
}

// layout places every part of the image: one part after another, each at an
// eight-byte boundary, with the whole image rounded up to a page.
fn layout(program image.Program, target backend.Target, interp_len int, dynstr_len int, library_count int, external int) Sections {
	mut offset := int(elf_header_size) + int(elf_program_header_count) * int(elf_program_header_size)
	interp := offset
	offset = align(offset + interp_len, 8)
	text := offset
	offset = align(offset + program.text.len, 8)
	// The call stubs follow the code they are reached from: six bytes each,
	// one per imported function an object called by a direct branch.
	plt := offset
	offset = align(offset + program.plts.len * plt_stub_size, 8)
	dynstr := offset
	offset = align(offset + dynstr_len, 8)
	strings := offset
	offset = align(offset + program.string_blob.len, 8)
	// The storage of the top-level objects starts at the strictest alignment any
	// object asked for with `aligned(N)`. An object's address is the load base
	// plus its offset in the image, and the load base is page aligned, so
	// aligning the offset here is what makes an address the object's declaration
	// asked for land where it was asked to.
	gl := if program.globals_alignment > 8 { program.globals_alignment } else { 8 }
	offset = align(offset, gl)
	globals := offset
	offset = align(offset + program.globals_blob.len, 8)
	dynsym := offset
	// One null entry the container requires, then one per external imported
	// function and one per object this image holds a copy of. A name whose
	// definition is inside this image gets no entry, because nothing outside
	// the image has to answer for it.
	offset = align(offset + (external + program.copy_objects.len + 1) * elf_symbol_size, 8)
	hash := offset
	offset = align(offset + hash_size(external + program.copy_objects.len + 1), 8)
	got := offset
	// A slot for every import, the bound ones included: a call to a bound name
	// still goes through its slot, so the slot index is the import's position
	// in `imports`, which is what the call's fixup was written against, and the
	// layout must not compact the slots the way it compacts the symbols.
	offset = align(offset + program.imports.len * 8, 8)
	rela := offset
	// One relocation per external import, one copy relocation per object this
	// image holds a copy of, plus one per address in the writable data that
	// names a symbol the loader resolves.
	offset = align(offset + (external + program.copy_objects.len +
		program.import_data_count()) * elf_relocation_size, 8)
	dynamic := offset
	offset = align(offset + dynamic_entry_count(library_count) * elf_dynamic_entry_size, 8)
	return Sections{
		interp:  interp
		text:    text
		plt:     plt
		dynstr:  dynstr
		strings: strings
		globals: globals
		dynsym:  dynsym
		hash:    hash
		got:     got
		rela:    rela
		dynamic: dynamic
		total:   align(offset, int(target.page_size))
	}
}

// hash_size is the size of the SysV hash table for a symbol count: one bucket,
// an entry in the bucket array for it, and a chain entry per symbol including
// the null one.
fn hash_size(symbol_count int) int {
	return 8 + 4 * (1 + symbol_count)
}

// emit_bound_slots writes the slot of every import whose definition is inside
// this image. A bound name is called through a slot the same way a library
// function is, so the slot still exists and the call still reads it, but the
// address it must hold is known here rather than to a loader. The definition
// says whether it is an offset into the code or into the writable data, and the
// slot gets that address at the load base, which is the address the loader would
// have written had the symbol come from outside.
fn emit_bound_slots(mut output []u8, program image.Program, sections Sections, base u64) {
	for i, name in program.imports {
		definition := program.bound[name] or { continue }
		at := if definition.function {
			sections.text + definition.offset
		} else {
			sections.globals + definition.offset
		}
		put_u64(mut output, sections.got + i * 8, base + u64(at))
	}
}

// emit_symbols writes the dynamic symbol table: a null entry the container
// requires, then one entry per external imported function and one per object
// this image holds a copy of. A bound name gets no entry, because its
// definition is inside this image and nothing outside has to answer for it; its
// slot is filled by emit_bound_slots instead. An imported function is a name in
// the string table, marked
// global and of function type, with no value and no section, because its
// definition is somewhere this image is not. An object this image copies is the
// other way round: the definition the loader copies from is the library's, and
// the entry here says where the copy goes and how big it is, so its type is
// object and it carries a value and a size. The size is the one thing the loader
// reads to know how many bytes to copy, and it is the storage's own size, the
// same width the object writer gives a definition. The section index is left
// undefined because this image has no section header table to name one in, and
// the loader's copy path reads the size and the place, not the section.
fn emit_symbols(mut output []u8, program image.Program, sections Sections, symbol_names map[string]int, indices []int, external int, base u64) {
	for i, name in program.imports {
		if name in program.bound {
			continue
		}
		at := sections.dynsym + indices[i] * elf_symbol_size
		put_u32(mut output, at, u32(symbol_names[name]))
		output[at + 4] = symbol_global_function
	}
	for i, name in program.copy_objects {
		at := sections.dynsym + (external + i + 1) * elf_symbol_size
		slot := program.globals[name] or { image.GlobalSlot{} }
		width := if slot.count > 0 { slot.width * slot.count } else { slot.width }
		put_u32(mut output, at, u32(symbol_names[name]))
		output[at + 4] = symbol_global_object
		put_u64(mut output, at + 8, base + u64(sections.globals + slot.offset))
		put_u64(mut output, at + 16, u64(width))
	}
}

// emit_hash writes the SysV hash table. It has one bucket, so every symbol hangs
// off the same chain and the table is correct whatever the names are: the bucket
// names the first symbol of the chain and each symbol's chain entry names the
// next. The chain is filled rather than left empty, because a name lookup walks
// it: the loader finds a symbol by hashing its name to a bucket and following the
// chain, so a symbol that is in no chain is not found. An image whose references
// the library resolves never needs to be searched by name, which is why the chain
// used to be empty, but an image that holds a copy of a library object does: the
// library's own references to that object have to find this image's copy, and
// they find it through this chain. The symbols are the external imports and the
// copies, in the order their entries stand in the dynamic table, starting at one
// because the null symbol is never in a chain. A bound name is in neither set.
fn emit_hash(mut output []u8, program image.Program, sections Sections, external int) {
	put_u32(mut output, sections.hash, 1) // one bucket
	put_u32(mut output, sections.hash + 4, u32(external + program.copy_objects.len + 1))
	mut head := u32(0)
	mut index := 1
	// A bound name has no entry in the dynamic table, so it is in no chain
	// either; only the external imports are, and they number the chain the way
	// they number the symbol table.
	for name in program.imports {
		if name in program.bound {
			continue
		}
		put_u32(mut output, sections.hash + 8 + 4 * (1 + index), head)
		head = u32(index)
		index++
	}
	for _ in program.copy_objects {
		put_u32(mut output, sections.hash + 8 + 4 * (1 + index), head)
		head = u32(index)
		index++
	}
	put_u32(mut output, sections.hash + 8, head)
}

// emit_relocations writes one relocation per external import: the loader
// resolves the symbol and writes its address into the slot named here, which is
// where every call to that function reads it from. A bound name gets none: its
// slot is filled by the layout, not by the loader. The relocation's place is the
// import's own position in `imports`, which is where its slot is, and the symbol
// it names is the import's index in the dynamic table, which is a different
// number as soon as one import is bound.
fn emit_relocations(mut output []u8, program image.Program, sections Sections, indices []int, external int, base u64) {
	mut entry := 0
	for i, name in program.imports {
		if name in program.bound {
			continue
		}
		at := sections.rela + entry * elf_relocation_size
		put_u64(mut output, at, base + u64(sections.got + i * 8))
		put_u64(mut output, at + 8, (u64(indices[i]) << 32) | relocation_glob_dat)
		// The addend is zero, which says the address itself is the value.
		entry++
	}
	// One copy relocation per object this image holds a copy of: the place is
	// the storage in this image, and the symbol is the one the entry in the
	// dynamic table names. The addend is zero, because the copy fills the
	// storage itself rather than an offset into it.
	for i, name in program.copy_objects {
		slot := program.globals[name] or { image.GlobalSlot{} }
		at := sections.rela + (entry + i) * elf_relocation_size
		put_u64(mut output, at, base + u64(sections.globals + slot.offset))
		put_u64(mut output, at + 8,
			(u64(external + i + 1) << 32) | relocation_copy)
	}
	entry += program.copy_objects.len
	// One more relocation per address in the writable data that names a symbol
	// the loader resolves: the address goes into the eight bytes the data fixup
	// points at, and the symbol is the same one its calls go through. Such a
	// fixup is never bound, because the link rewrites a bound one to a direct
	// address before this module sees the program.
	for fixup in program.data_fixups {
		if fixup.kind != .import_address {
			continue
		}
		mut index := -1
		for i, name in program.imports {
			if name == fixup.name {
				index = i
			}
		}
		if index < 0 {
			continue
		}
		at := sections.rela + entry * elf_relocation_size
		put_u64(mut output, at, base + u64(sections.globals + fixup.offset))
		put_u64(mut output, at + 8, (u64(indices[index]) << 32) | relocation_absolute)
		// The addend is the byte a part of the symbol starts at, so an address
		// of a part of an imported object points at the part and not at the
		// whole object.
		put_u64(mut output, at + 16, u64(fixup.addend))
		entry++
	}
}

// emit_dynamic writes the table that tells the loader what the image needs: each
// library it runs against, where the tables are, and how big each record in them
// is. The DT_NEEDED entries come first and are the only part of the table whose
// length depends on the command line.
fn emit_dynamic(mut output []u8, program image.Program, sections Sections, dynstr_len int, needed []int, external int, base u64) {
	mut entries := [][]u64{}
	for offset in needed {
		entries << [dt_needed, u64(offset)]
	}
	entries << [dt_hash, base + u64(sections.hash)]
	entries << [dt_strtab, base + u64(sections.dynstr)]
	entries << [dt_symtab, base + u64(sections.dynsym)]
	entries << [dt_rela, base + u64(sections.rela)]
	entries << [dt_relasz,
		u64((external + program.copy_objects.len + program.import_data_count()) * elf_relocation_size)]
	entries << [dt_relaent, u64(elf_relocation_size)]
	entries << [dt_strsz, u64(dynstr_len)]
	entries << [dt_syment, u64(elf_symbol_size)]
	entries << [dt_null, u64(0)]
	for i, entry in entries {
		put_u64(mut output, sections.dynamic + i * elf_dynamic_entry_size, entry[0])
		put_u64(mut output, sections.dynamic + i * elf_dynamic_entry_size + 8, entry[1])
	}
}

// emit_header writes the ELF header: what the file is, which machine it runs
// on, where execution starts, and where the program headers are.
fn emit_header(mut output []u8, target backend.Target, entry u64) {
	put(mut output, 0, elf_magic)
	output[4] = elf_class_64
	output[5] = elf_data_little_endian
	output[6] = elf_version_current
	// Byte 7 is the ABI, System V, and bytes 8 to 15 are its padding: the zeroes
	// the image was made of are what belongs there, so nothing is written.
	put_u16(mut output, 16, elf_type_exec)
	put_u16(mut output, 18, target.elf_machine)
	put_u32(mut output, 20, 1) // the container version, which is current
	put_u64(mut output, 24, entry)
	put_u64(mut output, 32, u64(elf_header_size)) // the program headers follow
	put_u64(mut output, 40, 0) // no section header table
	put_u32(mut output, 48, 0) // no architecture-specific flags
	put_u16(mut output, 52, elf_header_size)
	put_u16(mut output, 54, elf_program_header_size)
	put_u16(mut output, 56, elf_program_header_count)
	put_u16(mut output, 58, 0)
	put_u16(mut output, 60, 0)
	put_u16(mut output, 62, 0)
}

// emit_program_headers writes the four program headers the kernel and the loader
// read before any of the code runs.
fn emit_program_headers(mut output []u8, target backend.Target, sections Sections, interp_len int, library_count int) {
	mut at := int(elf_header_size)
	// PT_INTERP: the loader the kernel hands the process to.
	put_u32(mut output, at, elf_ph_type_interp)
	put_u32(mut output, at + 4, elf_ph_flags_read)
	put_u64(mut output, at + 8, u64(sections.interp))
	put_u64(mut output, at + 16, target.load_base + u64(sections.interp))
	put_u64(mut output, at + 24, target.load_base + u64(sections.interp))
	put_u64(mut output, at + 32, u64(interp_len))
	put_u64(mut output, at + 40, u64(interp_len))
	put_u64(mut output, at + 48, 1)
	at += int(elf_program_header_size)
	// PT_LOAD: the whole image, at the load base. It is readable, writable and
	// executable because the code, the strings and the slots the loader writes
	// all live in it.
	put_u32(mut output, at, elf_ph_type_load)
	put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write | elf_ph_flags_execute)
	put_u64(mut output, at + 8, 0)
	put_u64(mut output, at + 16, target.load_base)
	put_u64(mut output, at + 24, target.load_base)
	put_u64(mut output, at + 32, u64(sections.total))
	put_u64(mut output, at + 40, u64(sections.total))
	put_u64(mut output, at + 48, target.page_size)
	at += int(elf_program_header_size)
	// PT_DYNAMIC: the table the loader reads.
	put_u32(mut output, at, elf_ph_type_dynamic)
	put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write)
	put_u64(mut output, at + 8, u64(sections.dynamic))
	put_u64(mut output, at + 16, target.load_base + u64(sections.dynamic))
	put_u64(mut output, at + 24, target.load_base + u64(sections.dynamic))
	put_u64(mut output, at + 32, u64(dynamic_entry_count(library_count) * elf_dynamic_entry_size))
	put_u64(mut output, at + 40, u64(dynamic_entry_count(library_count) * elf_dynamic_entry_size))
	put_u64(mut output, at + 48, 8)
	at += int(elf_program_header_size)
	// PT_GNU_STACK: the stack is readable and writable and not executable, which
	// is what a program that never runs code from it should say.
	put_u32(mut output, at, elf_ph_type_gnu_stack)
	put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write)
	put_u64(mut output, at + 48, 0x10)
}

// patch fills in every reference now that every offset is settled. It runs after
// the parts are in place, because a displacement depends on the whole layout.
fn patch(mut output []u8, program image.Program, target backend.Target, sections Sections) ! {
	for fixup in program.fixups {
		referent := referent_of(program, sections, fixup.kind, fixup.name)!
		instruction := sections.text + fixup.start
		disp := i32(referent - (instruction + fixup.length))
		mut replacement := []u8{}
		match fixup.kind {
			.call_local {
				replacement = target.call_near(disp)
			}
			.call_import {
				replacement = target.call_slot(disp)
			}
			.take_address, .take_wide_address {
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.address_of(register, disp)
			}
			.float_constant {
				register := target.float_reg(fixup.register) or {
					return error('no floating-point register named ${fixup.register} to read a constant into')
				}
				replacement = target.load_double_constant(register, disp)!
			}
			.single_constant {
				// The same read at four bytes: the register is the same one, and
				// the instruction that fills it is the one that moves a float.
				register := target.float_reg(fixup.register) or {
					return error('no floating-point register named ${fixup.register} to read a constant into')
				}
				replacement = target.load_float_constant(register, disp)!
			}
			.global_address {
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.address_of(register, disp)
			}
			.got_address {
				// The load of an object's address out of the global offset
				// table is what a position-independent object carries. A
				// program has no such table and no emitter writes one for it,
				// so reaching this is refused rather than patched.
				return error('${fixup.name} is reached through the global offset table, which is a relocatable object and not the program this path writes')
			}
			.function_address {
				// The address of a function is computed the way the address of
				// a top-level object is: the layout has settled where the code
				// begins and the instruction reads that address into a register.
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.address_of(register, disp)
			}
			.import_address {
				// The address of a function the loader resolves is read out of
				// the slot the loader writes it into, the same slot a call to
				// that function goes through. The layout has settled where the
				// slot is, so the instruction reads its value into a register.
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.load_slot_value(register, disp)
			}
			.jump_local {
				replacement = target.jump(disp)
			}
			.branch_zero {
				replacement = target.jump_if_zero(disp)
			}
			.branch_nonzero {
				replacement = target.jump_if_not_zero(disp)
			}
		}
		if replacement.len != fixup.length {
			return error('the reference to ${fixup.name} was ${fixup.length} bytes and became ${replacement.len}')
		}
		put(mut output, instruction, replacement)
	}
	// The references inside the writable data are the eight bytes of an address
	// each, written once every address is settled. An imported symbol's address
	// is not known until the loader runs, so its bytes are left at zero and the
	// dynamic table fills them in (emit_relocations); every other kind is an
	// address this image settles, and it is written here. The addend is the byte
	// a part of the object starts at, so `&a[3]` writes the fourth element's
	// address and not the first's.
	for fixup in program.data_fixups {
		if fixup.kind == .import_address {
			continue
		}
		referent := referent_of(program, sections, fixup.kind, fixup.name)!
		put_u64(mut output, sections.globals + fixup.offset, target.load_base + u64(referent + fixup.addend))
	}
	// The references a unit carried as relocations are four-byte fields the unit
	// already wrote, so only the field is filled in: the value is the distance
	// from the field to what the name stands for, and the object's own addend is
	// added to the name's address. A call's addend is minus four, which is the
	// psABI's way of measuring the distance from the end of the field while
	// naming where the instruction began.
	for relocation in program.relocations {
		field := sections.text + relocation.offset
		referent := relocation_referent_of(program, sections, relocation.name)!
		put_u32(mut output, field, u32(i32(referent + relocation.addend - field)))
	}
	// Each stub jumps through the slot of the import it stands for: the
	// displacement is measured from the end of the stub, and the loader writes
	// the function's address into the slot the jump reads.
	for i, name in program.plts {
		stub := sections.plt + i * plt_stub_size
		index := program.imports.index(name)
		if index < 0 {
			return error('${name} needs a call stub and is not among the imports of this image')
		}
		slot := sections.got + index * 8
		put(mut output, stub, target.jump_slot(i32(slot - (stub + plt_stub_size))))
	}
}

// relocation_referent_of is where a relocation's name stands in the image. It
// answers the same question referent_of answers for a fixup, for the names a
// relocation can carry: one of the unit's own section keys, an imported function
// reached through its stub, or a symbol some unit of the link defines.
fn relocation_referent_of(program image.Program, sections Sections, name string) !int {
	match name {
		image.section_key_text { return sections.text }
		image.section_key_rodata { return sections.strings }
		image.section_key_data { return sections.globals }
		else {}
	}
	// A direct branch cannot reach the value a slot holds, so an imported
	// function is reached through the stub that jumps through its slot.
	for i, stub in program.plts {
		if stub == name {
			return sections.plt + i * plt_stub_size
		}
	}
	if offset := program.labels[name] {
		return sections.text + offset
	}
	if slot := program.globals[name] {
		return sections.globals + slot.offset
	}
	return error('${name} is named by a relocation and no unit of this link defines it and no stub stands for it')
}

// referent_of is where one reference points, as an offset into the image. It is
// asked with a kind and a name rather than a reference, because the same
// question is asked of a reference in the code and of one in the writable data.
fn referent_of(program image.Program, sections Sections, kind image.FixupKind, name string) !int {
	match kind {
		.call_local, .jump_local, .branch_zero, .branch_nonzero, .function_address {
			return sections.text + (program.labels[name] or {
				return error('no code for ${name}')
			})
		}
		.call_import, .import_address {
			for i, symbol in program.imports {
				if symbol == name {
					return sections.got + i * 8
				}
			}
			return error('${name} is called but was never imported')
		}
		.take_address {
			return sections.strings + (program.strings[name] or {
				return error('no string ${name} in the image')
			})
		}
		.take_wide_address {
			return sections.strings + (program.wide_strings[name] or {
				return error('no wide string ${name} in the image')
			})
		}
		.float_constant, .single_constant {
			// A floating constant is eight bytes in the same read-only data a
			// string lives in, and a float is four, so the section is the same
			// one and only the table it was interned in differs.
			return sections.strings + (program.doubles[name] or {
				return error('no floating constant ${name} in the image')
			})
		}
		.section_address {
			// The name is one of the unit's own section keys and the addend is
			// the byte inside it, so the place is the section's base and the
			// caller's addend picks the byte. It is how a relocatable object
			// names a string or a double it points at, where this compiler's
			// own emitter names the interned entry instead.
			match name {
				image.section_key_text { return sections.text }
				image.section_key_rodata { return sections.strings }
				image.section_key_data { return sections.globals }
				else {
					return error('${name} is not a section of this image')
				}
			}
		}
		.global_address {
			return sections.globals + (program.globals[name] or {
				return error('no global ${name} in the image')
			}).offset
		}
		.got_address {
			// A reference to an object through the global offset table is what
			// a relocatable object carries, and the table is built by whoever
			// links it. This path writes a program with every address settled
			// here and no such table, and the emitter never writes one for a
			// program, so this is a broken promise rather than an input: it is
			// named instead of being pointed at a wrong address.
			return error('${name} is reached through the global offset table, which is a relocatable object and not the program this path writes')
		}
	}
}

fn put(mut output []u8, offset int, bytes []u8) {
	for i, byte in bytes {
		output[offset + i] = byte
	}
}

fn put_u16(mut output []u8, offset int, value u16) {
	output[offset] = u8(value & 0xff)
	output[offset + 1] = u8((value >> 8) & 0xff)
}

fn put_u32(mut output []u8, offset int, value u32) {
	for shift in [0, 8, 16, 24] {
		output[offset + shift / 8] = u8((value >> shift) & 0xff)
	}
}

fn put_u64(mut output []u8, offset int, value u64) {
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		output[offset + shift / 8] = u8((value >> shift) & 0xff)
	}
}

// align rounds a size up to the next multiple of the alignment.
fn align(value int, to int) int {
	return (value + to - 1) / to * to
}
