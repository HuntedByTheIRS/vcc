module elf

import backend
import backend.os.linux
import image

// The ELF64 container, in the shapes Linux starts and its dynamic loader
// finishes. A program that calls a shared library is not a header and a code
// blob: the image has to name the loader that will finish the job (PT_INTERP),
// say which library it runs against (a DT_NEEDED entry in the PT_DYNAMIC table),
// and carry enough symbol information for the loader to find each function it
// calls and write its address where the code reads it: a .dynsym, the .hash the
// loader walks to learn how many symbols there are, a .rela.dyn with one
// relocation per imported function, and the slots those relocations fill.
//
// There are three kinds of image and one writer behind them. A `.program` is
// the dynamic one: an interpreter, a DT_NEEDED entry per library, and every
// address settled here or by a loader. A `.static_program` resolves its
// libraries into the file, so it names no interpreter and no library, and the
// kernel starts it alone. A `.shared` is a file another program loads: no
// interpreter, no entry point, and every address that points into the image is
// an offset a loader turns into an address once it has chosen where to put it.
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
// elf_type_dyn is a shared object: a file the kernel does not start and a
// loader maps on behalf of a program that asked for it. It has no entry point
// of its own, and every address in it that points into it is an offset a loader
// turns into an address once it has chosen where the object goes.
const elf_type_dyn = u16(3)

const elf_header_size = u16(64)
const elf_program_header_size = u16(56)
// PT_INTERP, PT_LOAD, PT_DYNAMIC and PT_GNU_STACK, in that order. It is how many
// headers a program the kernel starts with a loader has: a shared object has no
// interpreter, so it writes the three that are left, and a static program has no
// interpreter and no dynamic table, so it writes two. An image that defines
// thread-local storage adds a PT_TLS header after the dynamic one, for every
// kind. program_header_count is what decides.
const elf_program_header_count = u16(4)

// The program header types this container uses.
pub const elf_ph_type_load = u32(1)
pub const elf_ph_type_dynamic = u32(2)
pub const elf_ph_type_interp = u32(3)
// PT_TLS names the thread-local storage the image defines. The kernel does not
// map it; the runtime reads it before the first instruction runs and gives every
// thread its own copy of the block: p_filesz bytes copied from p_vaddr, then
// p_memsz - p_filesz zeroed. p_vaddr has to lie inside a PT_LOAD that is mapped
// from the file, because that copy reads it from there.
pub const elf_ph_type_tls = u32(7)
// PT_GNU_EH_FRAME names the unwind table's index. An unwinder reads it before
// it looks at any frame: the header it points at, `.eh_frame_hdr`, holds one
// entry per function body naming the address the body covers and the frame
// description that covers it, sorted by address so the lookup is a binary
// search. A binary whose frames would otherwise be found by scanning the table
// finds none without this header, which is why a program this compiler links
// carries it and not only the table.
const elf_ph_type_gnu_eh_frame = u32(0x6474E550)
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
// The two tables of function addresses the runtime calls around the program's
// own code. Each table is named by where it is and how many bytes it is, which
// is why a non-empty one costs two entries: the address and the size. They only
// exist in an image with a dynamic table, because the table is how the runtime
// learns of them.
pub const dt_init_array = u64(25)
pub const dt_fini_array = u64(26)
pub const dt_init_arraysz = u64(27)
pub const dt_fini_arraysz = u64(28)

// dynamic_entry_count is how many entries the dynamic table holds: the eight
// that describe the image's own tables, one DT_NEEDED per library it runs
// against, two for each of the constructor tables the image has, and the null
// that ends it. It is a function rather than a constant because the library
// count and the two table counts are not known until the program has been read.
fn dynamic_entry_count(library_count int, init_array_count int, fini_array_count int) int {
	mut count := 9 + library_count
	if init_array_count > 0 {
		count += 2
	}
	if fini_array_count > 0 {
		count += 2
	}
	return count
}

// A relocation that asks the loader to write a symbol's address into a slot.
pub const relocation_glob_dat = u64(6)
// A relocation that asks the loader to add the base it loaded the image at to
// an addend and write the sum into the eight bytes the entry names. It is what
// a shared object carries for an address that points into the object itself:
// the address is settled when the object is mapped and not before, so what the
// file holds is the offset and the loader adds where it went. It is
// R_X86_64_RELATIVE in this machine's psABI.
pub const relocation_relative = u64(8)
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
// A relocation that asks the loader to call a resolver and write what it answers
// into the eight bytes the entry names. A name defined by an ifunc is a function
// whose definition is a resolver: the address the program should call is not
// settled until the resolver has run and picked one for the machine it is on.
// The entry names the slot the resolver's answer goes in, and its addend is the
// resolver's own address. It is R_X86_64_IRELATIVE in this machine's psABI.
pub const relocation_irelative = u64(37)

// The st_info byte of every symbol this image imports: global, and of function
// type. The symbols are undefined, which is to say the value comes from
// somewhere else.
pub const symbol_global_function = u8(0x12)
// The same byte with the weak binding (2) rather than global (1), which is what
// `__attribute__((weak))` on a definition asks the object to say about it.
pub const symbol_weak_function = u8(0x22)

// The st_shndx a name this image exports is given. A shared object has no
// section header table to name a real section in, so the index is not a place:
// it is only what tells the loader the symbol is defined here rather than
// undefined and waiting for a library. SHN_UNDEF is what an import carries, and
// leaving this at zero would make an export one too.
const export_section = u16(1)

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
// For a shared object the load base this module writes is zero, because where it
// goes is the loader's to choose and not this module's to know.
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
	// tls is where the thread-local block's initialization image landed. It
	// lies in the same loaded region as the writable data, because the runtime
	// copies it out of the image and a copy reads from what the file mapped.
	tls     int
	dynsym  int
	hash    int
	got     int
	rela    int
	dynamic int
	// eh_frame is the unwind table: one CIE the emitter's prologue rule
	// describes and one FDE per function body, and eh_frame_hdr the table that
	// indexes it by the address each body covers. Both are read-only, both lie
	// in the one segment the image maps, and PT_GNU_EH_FRAME names the second
	// so an unwinder can reach the first without scanning.
	eh_frame     int
	eh_frame_hdr int
	total        int
}

// executable wraps a program in an ELF64 image that a Linux kernel can start and
// a dynamic loader can finish. It is the dynamic kind of `write` under the name
// it had before there were kinds, kept so that a caller that means the dynamic
// program says so without naming a kind.
pub fn executable(program image.Program, target backend.Target) ![]u8 {
	return write(program, target, .program)
}

// write wraps a program in an ELF64 image of the kind the command line asked
// for. `.program` is the dynamic one, `.static_program` resolves every library
// into the file, and `.shared` is a file another program loads with dlopen. The
// three share every part that does not depend on how the file is used; what
// changes between them is the interpreter, the libraries named, the base added
// to an address that points into the image, and what the symbol table exports.
pub fn write(program image.Program, target backend.Target, kind linux.LinkKind) ![]u8 {
	check_kind(program, kind)!
	shared := kind == .shared
	// A shared object is placed by whoever loads it, so this module adds no base
	// to anything: every address that points into the image is written as an
	// offset and travels with a relocation that adds the real base. A program,
	// static or dynamic, is placed at the target's own load base.
	base := if shared { u64(0) } else { target.load_base }
	// The loader's path, with the terminator the kernel expects. Only a dynamic
	// program names one: a static program is started by the kernel alone, and a
	// shared object is not started by the kernel at all.
	mut interp := []u8{}
	if kind == .program {
		interp = target.interpreter.bytes()
		interp << u8(0)
	}
	// The libraries the image runs against: the C library first, wherever it
	// was asked for or not, then the ones the -l flags named, each once. A
	// library that is not named here is a library the loader does not map,
	// which is what an undefined symbol at load comes from. A static program
	// names none: every library it uses is resolved into the file.
	mut libraries := []string{cap: program.libraries.len + 1}
	if kind != .static_program {
		libraries << linux.base_library
		for name in program.libraries {
			if name !in libraries {
				libraries << name
			}
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
	// The names this image defines and offers to whatever loads it. Only a
	// shared object exports: a program, static or dynamic, is the whole file
	// and nothing looks a name up in it.
	exports := if shared { export_names(program) } else { []string{} }
	for name in exports {
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
	// inside this image, and they are computed once here rather than a name at
	// a time in the emitters, so that every part of the image numbers the
	// symbols the same way.
	external := external_imports(program, kind)
	indices := symbol_indices(program)
	// The relocations the loader applies that name a symbol, and the ones that
	// only add the load base. The second kind is a shared object's, and it is
	// the count that sizes the table; the entries themselves are written where
	// the addresses they cover are.
	loader_data := loader_data_count(program, kind)
	// The names this image defines and something reaches through the global
	// offset table. Each needs a slot of its own, after the imports' slots,
	// which is what a position-independent object asks for when it reaches a
	// top-level object through the table.
	extra := got_extra_names(program)
	relative := relative_count(program, kind, extra)
	// The slots an ifunc name is reached through: each gets an IRELATIVE entry
	// beside whatever the loader already writes there, so the resolver's answer
	// replaces the address of the resolver itself.
	irelative := irelative_count(program, extra)
	relocation_total := external + program.copy_objects.len + loader_data + relative +
		irelative
	// A thread-local block turns into a PT_TLS header, and a dynamic table the
	// runtime reads turns into a PT_DYNAMIC header. The two are counted here
	// because the header table's size is what every offset after it counts
	// from, and the layout has to know before it places the first part.
	has_tls := program.tls_size > 0
	has_dynamic := kind != .static_program
	// A program with function bodies carries the table that describes them and
	// the header that indexes it. An image with no body carries neither, and
	// writes the same bytes it wrote before there was a table.
	has_eh_frame := program.function_runs.len > 0
	header_count := program_header_count(kind, has_tls, has_eh_frame)
	sections := layout(program, target, interp.len, dynstr.len, libraries.len, external,
		exports.len, extra.len, relocation_total, header_count, has_dynamic)
	// The image a Linux kernel starts is built here. The name is not `image`,
	// because that is the module whose Program this function was handed.
	mut output := []u8{len: sections.total, init: u8(0)}
	put(mut output, sections.interp, interp)
	put(mut output, sections.text, program.text)
	put(mut output, sections.dynstr, dynstr)
	put(mut output, sections.strings, program.string_blob)
	put(mut output, sections.globals, program.globals_blob)
	put(mut output, sections.tls, program.tls_blob)
	emit_bound_slots(mut output, program, sections, base)!
	emit_extra_slots(mut output, program, sections, extra, base)!
	emit_symbols(mut output, program, sections, symbol_names, indices, external, base, exports,
		kind)
	emit_hash(mut output, program, sections, external, exports.len, kind)
	emit_relocations(mut output, program, sections, indices, external, base, loader_data,
		extra, shared, kind)!
	// A static program writes no table here, and no header points at one.
	if has_dynamic {
		emit_dynamic(mut output, sections, program, dynstr.len, needed, base, relocation_total)
	}
	// The unwind table and the header that indexes it are written here rather
	// than by a relocation: the layout has settled where the code and the two
	// tables lie, so the distance an FDE measures to its body is the finished
	// layout's own, and the load base cancels out of it.
	put(mut output, sections.eh_frame, image_eh_frame_section(program, sections.text,
		sections.eh_frame))
	put(mut output, sections.eh_frame_hdr, image_eh_frame_header(program, sections.text,
		sections.eh_frame, sections.eh_frame_hdr))
	// A shared object has no entry point: the loader calls the initializers and
	// then whatever the program that loaded it names, and there is no place in
	// the file for the kernel to jump to.
	entry := if shared { u64(0) } else { base + u64(sections.text + program.entry_place) }
	e_type := if shared { elf_type_dyn } else { elf_type_exec }
	emit_header(mut output, target, entry, e_type, header_count)
	emit_program_headers(mut output, target, sections, program, interp.len, libraries.len,
		kind, has_tls, has_eh_frame, base)
	patch(mut output, program, target, sections, base, extra)!
	return output
}

// check_kind refuses the two links whose input this container cannot honestly
// finish, before a byte is written. Each refusal names the thing that cannot be
// resolved, because a file that loads with an address left to zero is worse than
// a link that stops and says which name it could not place.
fn check_kind(program image.Program, kind linux.LinkKind) ! {
	match kind {
		.static_program {
			// A static link resolves every library into the file it writes, so
			// a name still left to a library is one this link cannot finish:
			// the kernel starts the program with no loader, and nothing would
			// ever write that name's address.
			for name in program.imports {
				// A weak import is not left to a library: an undefined weak
				// symbol stands for zero, so there is nothing for a loader to
				// write and nothing for this link to resolve. `__gmon_start__` is
				// the one every static program has, because crti.o's `.init` reads
				// it before it reads anything else.
				if name in program.bound || name in program.weak_imports {
					continue
				}
				return error('${name} is not resolved into this static link: a static link resolves its libraries into the file, and this link left ${name} to a library')
			}
		}
		.shared {
			// A copy relocation asks a loader to copy a library's object into
			// this image's storage before the program runs, which is a
			// non-position-independent executable's shape and not a shared
			// object's: a shared object has no storage of that name for a
			// library to fill.
			if program.copy_objects.len > 0 {
				return error('${program.copy_objects[0]} is a library object this link holds a copy of, and a shared object does not copy a library object into itself')
			}
		}
		.program {}
	}
}

// program_header_count is how many program headers the kind is written with: a
// dynamic program names its interpreter and has four, a shared object has the
// load, dynamic and stack headers, and a static program has the load and stack
// headers alone, because it carries no dynamic table for a loader to read and
// nothing loads it. An image with thread-local storage adds one more, the PT_TLS
// header the runtime reads the block out of, and it is a header of its own for
// every kind that defines a thread-local.
fn program_header_count(kind linux.LinkKind, has_tls bool, has_eh_frame bool) int {
	mut count := match kind {
		.program { int(elf_program_header_count) }
		.static_program { 2 }
		.shared { 3 }
	}
	if has_tls {
		count++
	}
	// An image with function bodies carries PT_GNU_EH_FRAME for the table that
	// indexes them, and it is a header of its own for every kind.
	if has_eh_frame {
		count++
	}
	return count
}

// external_imports is how many of the program's names in `imports` a library has
// to answer for: every name that is not in `bound`. It is the count of symbols
// the dynamic table carries and of relocations the image emits, so the parts
// that size those tables ask it rather than `program.imports.len`, which counts
// the bound names too. A static program answers for none: `check_kind` has
// already refused the link that left one unresolved.
fn external_imports(program image.Program, kind linux.LinkKind) int {
	if kind == .static_program {
		return 0
	}
	mut count := 0
	for name in program.imports {
		if name !in program.bound {
			count++
		}
	}
	return count
}

// loader_data_count is how many references inside the writable data name a
// symbol the loader resolves rather than an address this image settles. Each one
// costs a dynamic relocation that names a symbol. A static program has none,
// because nothing in it is left to a loader.
fn loader_data_count(program image.Program, kind linux.LinkKind) int {
	if kind == .static_program {
		return 0
	}
	return program.import_data_count()
}

// relative_count is how many addresses a shared object carries as offsets beside
// the relocation that adds the load base to them: the slot of every import whose
// definition is inside the image, the slot of every name the image defines that
// something reaches through the table, and the address every data fixup writes
// for a name the image defines. Every other kind of image settles those
// addresses itself and needs none.
fn relative_count(program image.Program, kind linux.LinkKind, extra []string) int {
	if kind != .shared {
		return 0
	}
	mut count := extra.len
	for name in program.imports {
		if name in program.bound {
			count++
		}
	}
	for fixup in program.data_fixups {
		if fixup.kind != .import_address {
			count++
		}
	}
	return count
}

// irelative_count is how many slots the image fills by asking a resolver: one
// per slot it writes for a name `program.ifuncs` marks, which is a name whose
// definition is a resolver that picks the function to call. The slots are the
// bound imports' own and the extra names', the same two runs `got_slot` answers
// for, and a name with no slot in the image is reached directly and needs none.
fn irelative_count(program image.Program, extra []string) int {
	mut count := 0
	for name in program.imports {
		if name in program.bound && name in program.ifuncs {
			count++
		}
	}
	for name in extra {
		if name in program.ifuncs {
			count++
		}
	}
	return count
}

// export_names is the names a shared object defines and offers to whatever loads
// it: every function this image defines and every object it holds, with the
// internal ones left out, because internal linkage is a promise that the name
// does not leave the image (6.2.2p3). The two sets are sorted, functions before
// objects, so the same program writes the same table every run; `defined` and
// `globals` are maps and a map's order is not. `labels` is not the set to read:
// it holds the jump labels inside a function beside the function names, and a
// name a C identifier cannot spell (`.L0`) is not something to export.
fn export_names(program image.Program) []string {
	mut functions := program.defined.keys()
	functions.sort()
	mut objects := program.globals.keys()
	objects.sort()
	mut names := []string{}
	for name in functions {
		if name !in program.internal {
			names << name
		}
	}
	for name in objects {
		if name !in program.internal {
			names << name
		}
	}
	return names
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

// got_extra_names is the names reached through the global offset table that this
// image defines rather than imports, in the order the relocations carry them and
// without a repeat. A position-independent object reaches every top-level object
// through the table, its own included, so a link of such objects asks for a slot
// for a name one of its own units defines. The slot holds that definition's
// address, which is what a linker would have resolved from the object the name
// came from. A section key stands for a place rather than for a name a slot can
// hold, and it is not one of these.
fn got_extra_names(program image.Program) []string {
	mut names := []string{}
	for relocation in program.relocations {
		if relocation.kind != .got {
			continue
		}
		if relocation.name in program.imports || relocation.name in names {
			continue
		}
		if relocation.name == image.section_key_text
			|| relocation.name == image.section_key_rodata
			|| relocation.name == image.section_key_data {
			continue
		}
		names << relocation.name
	}
	return names
}

// got_slot is the address of the global offset table slot for a name: the
// import's own position in `imports` for a name a library answers, and a slot
// after those for a name this image defines and something reaches through the
// table. The first is where a call fixup written against the position reads and
// where a position-independent reference to an imported object points; the
// second is the same place for an object the image settled itself.
fn got_slot(program image.Program, sections Sections, name string, extra []string) !int {
	for i, symbol in program.imports {
		if symbol == name {
			return sections.got + i * 8
		}
	}
	for i, symbol in extra {
		if symbol == name {
			return sections.got + (program.imports.len + i) * 8
		}
	}
	return error('${name} is reached through the global offset table and neither an import of this image nor a definition in it stands for it')
}

// layout places every part of the image: one part after another, each at an
// eight-byte boundary, with the whole image rounded up to a page. `relocation_total`
// is how many entries the relocation table holds, because it is not the symbol
// count: a shared object carries entries that name no symbol, and a program
// carries entries for addresses in its data.
fn layout(program image.Program, target backend.Target, interp_len int, dynstr_len int, library_count int, external int, export_count int, got_extra int, relocation_total int, header_count int, has_dynamic bool) Sections {
	mut offset := int(elf_header_size) + header_count * int(elf_program_header_size)
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
	// The read-only data starts at the strictest alignment any of its sections
	// asked for. A compiler loads a sixteen-byte constant with one instruction
	// that faults on a misaligned place, and the unit's own part of this data is
	// placed at that alignment, so the whole of it has to begin there too.
	string_align := if program.read_only_alignment > 1 { program.read_only_alignment } else { 8 }
	offset = align(offset, string_align)
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
	// The thread-local block's initialization image sits in the writable data,
	// inside the one PT_LOAD segment the file maps, because the runtime copies
	// it out of p_vaddr and that read has to find the file's bytes. It is
	// aligned to the block's own alignment, which is what PT_TLS's p_align
	// says and keeps p_vaddr congruent to p_offset modulo p_align.
	tls_align := if program.tls_alignment > 1 { program.tls_alignment } else { 1 }
	offset = align(offset, tls_align)
	tls := offset
	offset = align(offset + program.tls_blob.len, 8)
	dynsym := offset
	// One null entry the container requires, then one per external imported
	// function, one per object this image holds a copy of, and one per name the
	// image exports. A name whose definition is inside this image gets no entry
	// as an import, because nothing outside has to answer for it, but a shared
	// object gives it one as an export, because something outside wants to.
	offset = align(offset + (external + program.copy_objects.len + export_count + 1) *
		elf_symbol_size, 8)
	hash := offset
	offset = align(offset + hash_size(external + program.copy_objects.len + export_count + 1), 8)
	got := offset
	// A slot for every import, the bound ones included: a call to a bound name
	// still goes through its slot, so the slot index is the import's position
	// in `imports`, which is what the call's fixup was written against, and the
	// layout must not compact the slots the way it compacts the symbols. The
	// slots of the names this image defines and something reaches through the
	// table follow them, at the positions `got_slot` gives them.
	offset = align(offset + (program.imports.len + got_extra) * 8, 8)
	rela := offset
	// One relocation per external import, one copy relocation per object this
	// image holds a copy of, one per address in the writable data that names a
	// symbol the loader resolves, and, for a shared object, one per address that
	// points into the image and waits for the base it is loaded at.
	offset = align(offset + relocation_total * elf_relocation_size, 8)
	// A static program carries no dynamic table: no loader runs before it and
	// nothing reads one, which is the shape a reader looks for to tell a static
	// program from one a loader finishes.
	dynamic := offset
	if has_dynamic {
		offset = align(offset + dynamic_entry_count(library_count, program.init_array.count,
			program.fini_array.count) * elf_dynamic_entry_size, 8)
	}
	// The unwind table and the header that indexes it come last, in the
	// read-only part of the image the one segment maps. They are placed after
	// every part whose offset is already spoken for, so adding them moves
	// nothing that came before, which is what keeps every reference the layout
	// has already settled pointing where it did.
	eh_frame := offset
	offset = align(offset + program_eh_frame_size(program), 8)
	eh_frame_hdr := offset
	offset = align(offset + program_eh_frame_hdr_size(program), 4)
	return Sections{
		interp:       interp
		text:         text
		plt:          plt
		dynstr:       dynstr
		strings:      strings
		globals:      globals
		tls:          tls
		dynsym:       dynsym
		hash:         hash
		got:          got
		rela:         rela
		dynamic:      dynamic
		eh_frame:     eh_frame
		eh_frame_hdr: eh_frame_hdr
		total:        align(offset, int(target.page_size))
	}
}

// program_eh_frame_size is how many bytes the image's `.eh_frame` takes: the one
// CIE, one twenty-byte FDE per function body, and the four-byte zero-length
// record that ends the table. An image with no body has no table and takes no
// bytes.
fn program_eh_frame_size(program image.Program) int {
	if program.function_runs.len == 0 {
		return 0
	}
	return frame_cie().len + program.function_runs.len * 20 + 4
}

// program_eh_frame_hdr_size is how many bytes the header takes: the version and
// the three encoding bytes, the four-byte table address and the four-byte entry
// count, then eight bytes (an address and an FDE pointer) per function body. An
// image with no body has no header and takes no bytes.
fn program_eh_frame_hdr_size(program image.Program) int {
	if program.function_runs.len == 0 {
		return 0
	}
	return 12 + program.function_runs.len * 8
}

// eh_frame_address_order is the program's function bodies in the order the header's
// table has to hold them: by address, because the unwinder binary-searches the
// table and a scan that met them out of order would look in the wrong half. A
// program's bodies are usually written in address order already, so the sort
// costs little and makes the table correct whatever order the emitter wrote.
fn eh_frame_address_order(program image.Program) []image.CodeRun {
	mut runs := program.function_runs.clone()
	runs.sort(a.base < b.base)
	return runs
}

// image_eh_frame_section builds the image's `.eh_frame`: the one CIE that describes
// this emitter's prologue, then one FDE per function body in address order, then
// a zero-length record that ends the table the way a scan which does not go
// through the header stops.
//
// An FDE names the body's place and length and carries no instructions of its
// own, because the CIE's rule describes the whole prologue. The initial location
// is a four-byte signed distance from the field itself to where the body begins,
// which is the encoding the CIE names (DW_EH_PE_pcrel | DW_EH_PE_sdata4): the
// same rule the object writer states, except that here the link has settled
// every address, so the distance is written rather than left to a relocation.
// The load base cancels out of the subtraction because both fields move with the
// image.
fn image_eh_frame_section(program image.Program, text int, eh_frame int) []u8 {
	if program.function_runs.len == 0 {
		return []u8{}
	}
	mut table := frame_cie()
	for run in eh_frame_address_order(program) {
		entry := table.len
		mut fde := []u8{len: 20, init: u8(0)}
		put_u32(mut fde, 0, 16) // the entry below, minus these four
		// The four bytes at offset four point back at the CIE: the distance
		// from the field to the CIE's first byte, which is the table's start.
		put_u32(mut fde, 4, u32(entry + 4))
		location := (text + run.base) - (eh_frame + entry + 8)
		put_u32(mut fde, 8, u32(i32(location)))
		put_u32(mut fde, 12, u32(run.len))
		table << fde
	}
	table << [u8(0), u8(0), u8(0), u8(0)]
	return table
}

// image_eh_frame_header builds the image's `.eh_frame_hdr`: the version and the three
// encoding bytes an unwinder reads before the table, the address of `.eh_frame`,
// how many entries there are, and one entry per function body in address order.
//
// The first field is a four-byte distance from itself to the table (pcrel,
// sdata4), the count is a plain four-byte number (udata4, absolute), and each
// entry is two four-byte distances measured from the start of this header
// (datarel, sdata4): the address a body begins at and the FDE that describes it.
// The encodings and the datarel base are gcc's, read off a binary it wrote.
fn image_eh_frame_header(program image.Program, text int, eh_frame int, header int) []u8 {
	if program.function_runs.len == 0 {
		return []u8{}
	}
	runs := eh_frame_address_order(program)
	mut hdr := []u8{len: 12 + runs.len * 8, init: u8(0)}
	hdr[0] = 1 // version 1
	// The pointer to `.eh_frame` is pcrel|sdata4, the entry count is
	// udata4|absolute, and the search table is datarel|sdata4.
	hdr[1] = 0x1b
	hdr[2] = 0x03
	hdr[3] = 0x3b
	put_u32(mut hdr, 4, u32(i32(eh_frame - (header + 4))))
	put_u32(mut hdr, 8, u32(runs.len))
	for i, run in runs {
		at := 12 + i * 8
		location := (text + run.base) - header
		put_u32(mut hdr, at, u32(i32(location)))
		fde := frame_cie().len + i * 20
		put_u32(mut hdr, at + 4, u32(i32((eh_frame + fde) - header)))
	}
	return hdr
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
// have written had the symbol come from outside. For a shared object the load
// base is zero, so what the slot holds is the file offset; `emit_relocations`
// pairs it with the R_X86_64_RELATIVE entry that adds the real base when the
// object is mapped.
// iplt_end is where the array of IRELATIVE entries this image carries stops. The
// array is what the C library's startup walks, from the name at its front to the
// name at its back, calling each entry's resolver. A link defines those two
// names itself, and the object reaches them through the global offset table, so
// the container is what writes their slots: a slot nothing writes holds zero and
// the walk is empty, which leaves every ifunc slot holding its resolver instead
// of the implementation the resolver would have chosen.
fn iplt_end(program image.Program, sections Sections) int {
	return sections.rela + irelative_count(program, got_extra_names(program)) * elf_relocation_size
}

fn emit_bound_slots(mut output []u8, program image.Program, sections Sections, base u64) ! {
	// The two names the startup walks the relocation array between are answered by
	// the container rather than by a unit, so their slots hold the array's ends.
	for i, name in program.imports {
		if name == '__rela_iplt_start' {
			put_u64(mut output, sections.got + i * 8, base + u64(sections.rela))
		}
		if name == '__rela_iplt_end' {
			put_u64(mut output, sections.got + i * 8, base + u64(iplt_end(program, sections)))
		}
	}
	for i, name in program.imports {
		definition := program.bound[name] or { continue }
		// A thread-local this image holds is reached the way any other one is:
		// the code reads the slot and adds it to the thread pointer, so the
		// slot holds how far below that pointer the variable lies rather than
		// an address. Writing the address instead and reading it through the
		// thread pointer lands somewhere no page holds, which is what a printf
		// that touches `errno` did.
		if name in program.tls_slots {
			put_u64(mut output, sections.got + i * 8, u64(tpoff_of(program, name, 0)!))
			continue
		}
		at := if definition.function {
			sections.text + definition.offset
		} else {
			sections.globals + definition.offset
		}
		put_u64(mut output, sections.got + i * 8, base + u64(at))
	}
}

// emit_extra_slots writes the slots of the names this image defines and
// something reaches through the global offset table, after the imports' slots.
// The address is the definition's own, which is what a slot holds: the same
// treatment the bound imports' slots get, and for the same reason, since a name
// the image settled needs no library to answer for it. A shared object's base is
// zero here, so the slot holds the file offset and the R_X86_64_RELATIVE entry
// emit_relocations writes beside it adds the base the loader chose.
fn emit_extra_slots(mut output []u8, program image.Program, sections Sections, extra []string, base u64) ! {
	for i, name in extra {
		at := relocation_referent_of(program, sections, name)!
		// A slot a `.gottpoff` reference reads holds how far the thread-local
		// lies below the thread pointer rather than its address: the code loads
		// the slot and reaches the variable through the thread pointer. The
		// offset is known here because the whole thread-local block is this
		// image's, which is what the initial-exec model needs.
		if name in program.tls_slots {
			put_u64(mut output, sections.got + (program.imports.len + i) * 8, u64(tpoff_of(program, name, 0)!))
			continue
		}
		put_u64(mut output, sections.got + (program.imports.len + i) * 8, base + u64(at))
	}
}

// emit_symbols writes the dynamic symbol table: a null entry the container
// requires, then one entry per external imported function, one per object this
// image holds a copy of, and one per name a shared object exports.
//
// A bound name gets no entry as an import, because its definition is inside this
// image and nothing outside has to answer for it; its slot is filled by
// emit_bound_slots instead. An imported function is a name in the string table,
// marked global and of function type, with no value and no section, because its
// definition is somewhere this image is not. An object this image copies is the
// other way round: the definition the loader copies from is the library's, and
// the entry here says where the copy goes and how big it is, so its type is
// object and it carries a value and a size. The size is the one thing the loader
// reads to know how many bytes to copy, and it is the storage's own size, the
// same width the object writer gives a definition. The section index is left
// undefined for a copy because this image has no section header table to name
// one in, and the loader's copy path reads the size and the place, not the
// section.
//
// An exported name is a symbol this image defines, and the loader finds it by
// name, so it carries the binding, the type of what it names, the file offset of
// the definition, and, for an object, the storage's size. Its section index is
// the one non-zero value this file uses, because a symbol with SHN_UNDEF is one
// the loader skips when it is looking for a definition, and an export the loader
// skips is an export in name only.
fn emit_symbols(mut output []u8, program image.Program, sections Sections, symbol_names map[string]int, indices []int, external int, base u64, exports []string, kind linux.LinkKind) {
	// A static program has no loader, so an entry in its dynamic symbol table
	// answers nothing: every name the image needs is settled by the link, and an
	// import still left over is one that stands for zero. The room the layout
	// made says the same thing, because `external_imports` is zero for a static
	// program, and a table that writes more entries than the room it was given
	// runs off the end of the image.
	if kind != .static_program {
		for i, name in program.imports {
			if name in program.bound {
				continue
			}
			at := sections.dynsym + indices[i] * elf_symbol_size
			put_u32(mut output, at, u32(symbol_names[name]))
			output[at + 4] = if name in program.weak_imports {
				symbol_weak_function
			} else {
				symbol_global_function
			}
		}
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
	for i, name in exports {
		at := sections.dynsym + (external + program.copy_objects.len + i + 1) * elf_symbol_size
		put_u32(mut output, at, u32(symbol_names[name]))
		put_u16(mut output, at + 6, export_section)
		if name in program.defined {
			output[at + 4] = symbol_global_function
			where := program.labels[name] or { 0 }
			put_u64(mut output, at + 8, base + u64(sections.text + where))
			continue
		}
		slot := program.globals[name] or { image.GlobalSlot{} }
		width := if slot.count > 0 { slot.width * slot.count } else { slot.width }
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
// they find it through this chain. A shared object exports names for the same
// reason one step further out: whatever loads it looks those names up here. The
// symbols are the external imports, the copies and the exports, in the order
// their entries stand in the dynamic table, starting at one because the null
// symbol is never in a chain. A bound name is in none of those sets.
fn emit_hash(mut output []u8, program image.Program, sections Sections, external int, export_count int, kind linux.LinkKind) {
	put_u32(mut output, sections.hash, 1) // one bucket
	put_u32(mut output, sections.hash + 4, u32(external + program.copy_objects.len + export_count + 1))
	mut head := u32(0)
	mut index := 1
	// A bound name has no entry in the dynamic table, so it is in no chain
	// either; only the external imports are, and they number the chain the way
	// they number the symbol table. A static program has no loader, so it has no
	// external import at all: the room the layout made is `external`, which is
	// zero for one, and a chain that writes more entries than that runs past the
	// end of the table and over whatever section follows it.
	if kind != .static_program {
		for name in program.imports {
			if name in program.bound {
				continue
			}
			put_u32(mut output, sections.hash + 8 + 4 * (1 + index), head)
			head = u32(index)
			index++
		}
	}
	for _ in program.copy_objects {
		put_u32(mut output, sections.hash + 8 + 4 * (1 + index), head)
		head = u32(index)
		index++
	}
	for _ in 0 .. export_count {
		put_u32(mut output, sections.hash + 8 + 4 * (1 + index), head)
		head = u32(index)
		index++
	}
	put_u32(mut output, sections.hash + 8, head)
}

// emit_relocations writes the dynamic relocation table. The first run names a
// symbol for the loader to resolve: the loader writes the symbol's address into
// the slot a call reads (R_X86_64_GLOB_DAT), copies a library object into this
// image's storage (R_X86_64_COPY), or writes an imported symbol's address into
// the eight bytes a data fixup points at (R_X86_64_64). The last run, which only
// a shared object has, names no symbol: it tells the loader to add the base it
// loaded this object at to an addend and store the sum, which is what every
// address the object holds that points into itself needs.
//
// A bound name gets no symbol relocation: its slot is filled by the layout, not
// by the loader. The relocation's place is the import's own position in
// `imports`, which is where its slot is, and the symbol it names is the import's
// index in the dynamic table, which is a different number as soon as one import
// is bound.
//
// The run at the end is the ifuncs': a slot the image wrote for a name whose
// definition is a resolver gets an R_X86_64_IRELATIVE entry, which tells the
// loader to call the resolver and store what it answers. The entry names no
// symbol, because the answer is not a name's address, and its addend is the
// resolver's own address, which the loader calls.
fn emit_relocations(mut output []u8, program image.Program, sections Sections, indices []int, external int, base u64, loader_data int, extra []string, shared bool, kind linux.LinkKind) ! {
	mut entry := 0
	// A static program writes no relocation for an import: there is no loader to
	// read one, and every import still left over stands for zero rather than
	// waiting for a slot to be filled. The room the layout made is
	// `external_imports`' answer, which is zero for a static program, so this is
	// also the loop that has to agree with it.
	if kind != .static_program {
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
	// address before this module sees the program. A static program resolves
	// every name itself, so it has none of these.
	if loader_data > 0 {
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
			// The addend is the byte a part of the symbol starts at, so an
			// address of a part of an imported object points at the part and
			// not at the whole object.
			put_u64(mut output, at + 16, u64(fixup.addend))
			entry++
		}
	}
	// The entries a shared object adds for the addresses it holds that point
	// into itself: the slot of each import whose definition is inside the image,
	// and the address each data fixup writes for a name the image defines. The
	// place is the address of the field, and the addend is the file offset the
	// field holds, which the loader turns into the value at the base it chose.
	// The count is `relative`, and the two runs that read the program's own
	// lists to fill it are the two `relative_count` counted.
	if shared {
		for i, name in program.imports {
			definition := program.bound[name] or { continue }
			at := if definition.function {
				sections.text + definition.offset
			} else {
				sections.globals + definition.offset
			}
			where := sections.rela + entry * elf_relocation_size
			put_u64(mut output, where, u64(sections.got + i * 8))
			put_u64(mut output, where + 8, relocation_relative)
			put_u64(mut output, where + 16, u64(at))
			entry++
		}
		for fixup in program.data_fixups {
			if fixup.kind == .import_address {
				continue
			}
			referent := referent_of(program, sections, fixup.kind, fixup.name, extra)!
			where := sections.rela + entry * elf_relocation_size
			put_u64(mut output, where, u64(sections.globals + fixup.offset))
			put_u64(mut output, where + 8, relocation_relative)
			put_u64(mut output, where + 16, u64(referent + fixup.addend))
			entry++
		}
		// The slots of the names the image defines and something reaches
		// through the table hold an address inside the object the same way, so
		// they are carried as offsets too.
		for i, name in extra {
			at := relocation_referent_of(program, sections, name)!
			where := sections.rela + entry * elf_relocation_size
			put_u64(mut output, where, u64(sections.got + (program.imports.len + i) * 8))
			put_u64(mut output, where + 8, relocation_relative)
			put_u64(mut output, where + 16, u64(at))
			entry++
		}
	}
	// The slots an ifunc name is reached through. The slot already holds the
	// resolver's address, because a bound name's slot gets its definition and
	// the definition of an ifunc is the resolver; the IRELATIVE entry is what
	// tells the loader to call it and replace that address with the answer.
	// The entry names no symbol and its addend is the resolver's address, which
	// is what the loader calls. A name no slot stands for is reached directly
	// and needs none.
	for i, name in program.imports {
		if name !in program.bound || name !in program.ifuncs {
			continue
		}
		definition := program.bound[name] or { continue }
		resolver := if definition.function {
			sections.text + definition.offset
		} else {
			sections.globals + definition.offset
		}
		where := sections.rela + entry * elf_relocation_size
		put_u64(mut output, where, base + u64(sections.got + i * 8))
		put_u64(mut output, where + 8, relocation_irelative)
		put_u64(mut output, where + 16, base + u64(resolver))
		entry++
	}
	for i, name in extra {
		if name !in program.ifuncs {
			continue
		}
		resolver := relocation_referent_of(program, sections, name)!
		where := sections.rela + entry * elf_relocation_size
		put_u64(mut output, where, base + u64(sections.got + (program.imports.len + i) * 8))
		put_u64(mut output, where + 8, relocation_irelative)
		put_u64(mut output, where + 16, base + u64(resolver))
		entry++
	}
}

// emit_dynamic writes the table that tells the loader what the image needs: each
// library it runs against, where the tables are, and how big each record in them
// is. The DT_NEEDED entries come first and are the only part of the table whose
// length depends on the command line; a static program has none, so its table
// describes only its own parts. The two constructor tables are named by address
// and size when the image has them, and they lie in the writable data, so the
// address is the load base plus the storage's own offset.
fn emit_dynamic(mut output []u8, sections Sections, program image.Program, dynstr_len int, needed []int, base u64, relocation_total int) {
	mut entries := [][]u64{}
	for offset in needed {
		entries << [dt_needed, u64(offset)]
	}
	entries << [dt_hash, base + u64(sections.hash)]
	entries << [dt_strtab, base + u64(sections.dynstr)]
	entries << [dt_symtab, base + u64(sections.dynsym)]
	entries << [dt_rela, base + u64(sections.rela)]
	entries << [dt_relasz, u64(relocation_total * elf_relocation_size)]
	entries << [dt_relaent, u64(elf_relocation_size)]
	entries << [dt_strsz, u64(dynstr_len)]
	entries << [dt_syment, u64(elf_symbol_size)]
	if program.init_array.count > 0 {
		entries << [dt_init_array, base + u64(sections.globals + program.init_array.offset)]
		entries << [dt_init_arraysz, u64(program.init_array.count * 8)]
	}
	if program.fini_array.count > 0 {
		entries << [dt_fini_array, base + u64(sections.globals + program.fini_array.offset)]
		entries << [dt_fini_arraysz, u64(program.fini_array.count * 8)]
	}
	entries << [dt_null, u64(0)]
	for i, entry in entries {
		put_u64(mut output, sections.dynamic + i * elf_dynamic_entry_size, entry[0])
		put_u64(mut output, sections.dynamic + i * elf_dynamic_entry_size + 8, entry[1])
	}
}

// emit_header writes the ELF header: what the file is, which machine it runs
// on, where execution starts, and where the program headers are. A shared object
// has no entry point, so its e_entry is zero, and its type is ET_DYN: the kernel
// does not start it, a loader maps it.
fn emit_header(mut output []u8, target backend.Target, entry u64, e_type u16, header_count int) {
	put(mut output, 0, elf_magic)
	output[4] = elf_class_64
	output[5] = elf_data_little_endian
	output[6] = elf_version_current
	// Byte 7 is the ABI, System V, and bytes 8 to 15 are its padding: the zeroes
	// the image was made of are what belongs there, so nothing is written.
	put_u16(mut output, 16, e_type)
	put_u16(mut output, 18, target.elf_machine)
	put_u32(mut output, 20, 1) // the container version, which is current
	put_u64(mut output, 24, entry)
	put_u64(mut output, 32, u64(elf_header_size)) // the program headers follow
	put_u64(mut output, 40, 0) // no section header table
	put_u32(mut output, 48, 0) // no architecture-specific flags
	put_u16(mut output, 52, elf_header_size)
	put_u16(mut output, 54, elf_program_header_size)
	put_u16(mut output, 56, u16(header_count))
	put_u16(mut output, 58, 0)
	put_u16(mut output, 60, 0)
	put_u16(mut output, 62, 0)
}

// emit_program_headers writes the program headers the kernel and the loader read
// before any of the code runs: the interpreter when the kind has one, the one
// segment that maps the whole image, the dynamic table when the kind has one,
// the thread-local block when the image defines one, and the stack. The kind
// settles the first three, and a thread-local is a header of its own for every
// kind, which is why it is passed in rather than read off the kind.
fn emit_program_headers(mut output []u8, target backend.Target, sections Sections, program image.Program, interp_len int, library_count int, kind linux.LinkKind, has_tls bool, has_eh_frame bool, base u64) {
	mut at := int(elf_header_size)
	// PT_INTERP: the loader the kernel hands the process to. Only a dynamic
	// program names one; the other two kinds write no header here.
	if kind == .program {
		put_u32(mut output, at, elf_ph_type_interp)
		put_u32(mut output, at + 4, elf_ph_flags_read)
		put_u64(mut output, at + 8, u64(sections.interp))
		put_u64(mut output, at + 16, base + u64(sections.interp))
		put_u64(mut output, at + 24, base + u64(sections.interp))
		put_u64(mut output, at + 32, u64(interp_len))
		put_u64(mut output, at + 40, u64(interp_len))
		put_u64(mut output, at + 48, 1)
		at += int(elf_program_header_size)
	}
	// PT_LOAD: the whole image, at the load base. It is readable, writable and
	// executable because the code, the strings and the slots the loader writes
	// all live in it.
	put_u32(mut output, at, elf_ph_type_load)
	put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write | elf_ph_flags_execute)
	put_u64(mut output, at + 8, 0)
	put_u64(mut output, at + 16, base)
	put_u64(mut output, at + 24, base)
	put_u64(mut output, at + 32, u64(sections.total))
	put_u64(mut output, at + 40, u64(sections.total))
	put_u64(mut output, at + 48, target.page_size)
	at += int(elf_program_header_size)
	// PT_DYNAMIC: the table the loader reads. A static program writes no such
	// header, because it writes no such table: nothing loads it and nothing
	// reads one, and a reader that finds none calls it statically linked.
	if kind != .static_program {
		size := u64(dynamic_entry_count(library_count, program.init_array.count,
			program.fini_array.count) * elf_dynamic_entry_size)
		put_u32(mut output, at, elf_ph_type_dynamic)
		put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write)
		put_u64(mut output, at + 8, u64(sections.dynamic))
		put_u64(mut output, at + 16, base + u64(sections.dynamic))
		put_u64(mut output, at + 24, base + u64(sections.dynamic))
		put_u64(mut output, at + 32, size)
		put_u64(mut output, at + 40, size)
		put_u64(mut output, at + 48, 8)
		at += int(elf_program_header_size)
	}
	// PT_TLS: the thread-local block. It is read-only, and its p_vaddr is where
	// the initialization image sits inside the segment that maps the file,
	// because the runtime copies p_filesz bytes out of it. p_memsz is the
	// block's size rounded to its alignment, the same roundup the runtime does,
	// and it is longer than p_filesz when a zero-filled part follows the image.
	if has_tls {
		put_u32(mut output, at, elf_ph_type_tls)
		put_u32(mut output, at + 4, elf_ph_flags_read)
		put_u64(mut output, at + 8, u64(sections.tls))
		put_u64(mut output, at + 16, base + u64(sections.tls))
		put_u64(mut output, at + 24, base + u64(sections.tls))
		put_u64(mut output, at + 32, u64(program.tls_blob.len))
		put_u64(mut output, at + 40, u64(tls_memsz(program)))
		put_u64(mut output, at + 48, u64(tls_alignment_of(program)))
		at += int(elf_program_header_size)
	}
	// PT_GNU_EH_FRAME: the header that indexes the unwind table. An unwinder
	// finds it here and reads the table through it, so a body whose FDE it
	// would not reach by scanning is still described. It is read-only, its
	// p_vaddr is where the header lies in the one segment the image maps, and
	// its alignment is the four bytes every field in the header is.
	if has_eh_frame {
		size := u64(program_eh_frame_hdr_size(program))
		put_u32(mut output, at, elf_ph_type_gnu_eh_frame)
		put_u32(mut output, at + 4, elf_ph_flags_read)
		put_u64(mut output, at + 8, u64(sections.eh_frame_hdr))
		put_u64(mut output, at + 16, base + u64(sections.eh_frame_hdr))
		put_u64(mut output, at + 24, base + u64(sections.eh_frame_hdr))
		put_u64(mut output, at + 32, size)
		put_u64(mut output, at + 40, size)
		put_u64(mut output, at + 48, 4)
		at += int(elf_program_header_size)
	}
	// PT_GNU_STACK: the stack is readable and writable, and executable only when
	// the program runs code out of it, which is what a nested function's address
	// needs: the stub that carries the enclosing frame is written into the frame
	// and jumped into.
	put_u32(mut output, at, elf_ph_type_gnu_stack)
	put_u32(mut output, at + 4, elf_ph_flags_read | elf_ph_flags_write | if program.executable_stack {
		elf_ph_flags_execute
	} else {
		u32(0)
	})
	put_u64(mut output, at + 48, 0x10)
}

// patch fills in every reference now that every offset is settled. It runs after
// the parts are in place, because a displacement depends on the whole layout.
// `base` is the number an address that points into the image is written at: the
// target's load base for a program, static or dynamic, and zero for a shared
// object, whose addresses are offsets until a loader places it.
fn patch(mut output []u8, program image.Program, target backend.Target, sections Sections, base u64, extra []string) ! {
	for fixup in program.fixups {
		referent := referent_of(program, sections, fixup.kind, fixup.name, extra)!
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
				// The instruction loads an imported object's address out of the
				// global offset table, which is what a position-independent
				// object carries. The referent is the address of the import's
				// slot, computed the same way the other address references are:
				// the layout has settled where the slot is, and the instruction
				// reads that address into a register.
				register := target.reg(fixup.register) or {
					return error('no register named ${fixup.register} to compute an address into')
				}
				replacement = target.address_of(register, disp)
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
	// address and not the first's. For a shared object the base is zero, so the
	// address is written as its file offset and the R_X86_64_RELATIVE entry
	// emit_relocations writes beside it adds the base the loader chose.
	for fixup in program.data_fixups {
		if fixup.kind == .import_address {
			continue
		}
		referent := referent_of(program, sections, fixup.kind, fixup.name, extra)!
		put_u64(mut output, sections.globals + fixup.offset, base + u64(referent + fixup.addend))
	}
	// The references a unit carried as relocations are fields the unit already
	// wrote, so only the field is filled in, and how wide it is decides how many
	// bytes of the answer go there. A narrow field is four bytes and this
	// compiler's own references and an instruction's displacement are narrow; a
	// wide field is eight and an unwind table's entries and an eight-byte
	// address are wide. A `.direct` value is the distance from the field to what
	// the name stands for, with the object's own addend added to the name's
	// address; a call's addend is minus four, which is the psABI's way of
	// measuring the distance from the end of the field while naming where the
	// instruction began. A `.got` value is the same distance, to the name's
	// global offset table slot rather than to the name. An `.absolute` value is
	// the address itself, and when the name is empty it is the addend alone,
	// which is how a constant an absolute symbol names arrives. A `.tpoff` value
	// is how far below the thread pointer the name lies. `place` says which of
	// the unit's blobs the field is in, because an unwind table refers to the
	// code from a blob of its own.
	for relocation in program.relocations {
		field := relocation_section(sections, relocation.place) + relocation.offset
		value := relocation_value(program, sections, base, extra, field, relocation)!
		match relocation.width {
			.narrow { put_u32(mut output, field, u32(i32(value))) }
			.wide { put_u64(mut output, field, u64(value)) }
		}
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

// relocation_section is the base of the blob a relocation's field lies in. It is
// the place the unit recorded when the reference was read, and the three are the
// three blobs a unit is made of; a field the emitter wrote is in the code.
fn relocation_section(sections Sections, place image.RelocationPlace) int {
	return match place {
		.text { sections.text }
		.read_only { sections.strings }
		.tls { sections.tls }
		.data { sections.globals }
	}
}

// relocation_referent_of is where a relocation's name stands in the image. It
// answers the same question referent_of answers for a fixup, for the names a
// relocation can carry: one of the unit's own section keys, an imported function
// reached through its stub, or a symbol some unit of the link defines.
fn relocation_referent_of(program image.Program, sections Sections, name string) !int {
	// The array of IRELATIVE entries this image carries is the container's, so its
	// two ends are answered here, before any table a name could be bound in. The C
	// library's startup walks from the first to the second and asks each entry's
	// resolver for the implementation to put in the slot that entry names. A link
	// defines these two names itself; a link that leaves them to the rule for an
	// undefined weak symbol gives both the value zero, and the walk is empty.
	if name == '__rela_iplt_start' {
		return sections.rela
	}
	if name == '__rela_iplt_end' {
		return sections.rela + irelative_count(program, got_extra_names(program)) * elf_relocation_size
	}
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
	// A name the linker answers with the image's own start is offset zero here:
	// every address in the image is this offset plus the base, so a reference
	// that measures from a place in the image and one that writes the address
	// both come out right.
	if definition := program.bound[name] {
		if definition.image_base {
			return 0
		}
	}
	// An object a unit defines in read-only data: the merged read-only data is
	// where its bytes are, and the offset a bound definition carries counts from
	// its start.
	if slot := program.read_only_globals[name] {
		return sections.strings + slot.offset
	}
	if offset := program.labels[name] {
		return sections.text + offset
	}
	if slot := program.globals[name] {
		return sections.globals + slot.offset
	}
	// A name the link answers itself is in no unit's table: the constructor
	// tables' four ends and the image's own bounds are places in the writable
	// data, and the offset the link recorded for one counts from the start of
	// that section. Everything a unit defines was found above, so a definition
	// reaching this point is one of the link's own answers.
	if definition := program.bound[name] {
		return sections.globals + definition.offset
	}
	return error('${name} is named by a relocation and no unit of this link defines it and no stub stands for it')
}

// tls_alignment_of is the alignment the thread-local block asks for: the
// strictest any member asked for, and at least one, because a block whose
// members all asked for a byte still begins on a byte boundary.
fn tls_alignment_of(program image.Program) int {
	return if program.tls_alignment > 1 { program.tls_alignment } else { 1 }
}

// tls_memsz is the storage the thread-local block asks for at run time: the
// unit's tls_size rounded up to the block's alignment. glibc's
// __libc_setup_tls rounds the p_memsz it reads from PT_TLS the same way,
// roundup(memsz, align), and puts the thread pointer at the end of that rounded
// block, so a tpoff measured against anything else points at the wrong byte.
fn tls_memsz(program image.Program) int {
	return align(program.tls_size, tls_alignment_of(program))
}

// tpoff_of is how far below the thread pointer a thread-local lies. The thread
// pointer sits at the end of the block, so the offset is the name's place in
// the block plus its addend minus the block's rounded size:
//
//	tls_labels[name] + addend - tls_memsz
//
// Written as an address difference it is (tls_vaddr + tls_labels[name]) + addend
// - (tls_vaddr + tls_memsz), where tls_vaddr is where the initialization image
// was placed; the placement cancels out, which is why the offset does not depend
// on where the image was loaded. The size is rounded as roundup(tls_size,
// tls_alignment), the rounding __libc_setup_tls does, because the thread pointer
// goes at the end of the rounded block and the offset has to agree with it.
fn tpoff_of(program image.Program, name string, addend int) !i64 {
	offset := program.tls_labels[name] or {
		// An undefined weak symbol stands for zero (ELF), and the offset of a
		// thread-local that lies at zero is the offset of the start of the
		// block. The C library declares its own locale members weak so that a
		// link which never pulls the data still finishes, and a reference to
		// one is settled the same way: a zero offset rather than an error.
		if name in program.weak_imports {
			return i64(addend - tls_memsz(program))
		}
		return error('${name} is measured from the thread pointer and is not a thread-local of this image')
	}
	return i64(offset + addend - tls_memsz(program))
}

// relocation_value is the number a relocatable reference carries once every
// address is settled. `field` is where the field itself is, because a direct or
// global-offset reference is a distance from it and the absolute and tpoff kinds
// are not. An empty name with the absolute kind is a constant rather than a
// place, and the addend is the whole of it; an undefined weak symbol is the
// other name with no place to point at.
fn relocation_value(program image.Program, sections Sections, base u64, extra []string, field int, relocation image.Relocation) !i64 {
	match relocation.kind {
		.direct {
			return i64(relocation_referent_of(program, sections, relocation.name)! +
				relocation.addend - field)
		}
		.got {
			return i64(got_slot(program, sections, relocation.name, extra)! +
				relocation.addend - field)
		}
		.absolute {
			if relocation.name == '' {
				return i64(relocation.addend)
			}
			where := relocation_referent_of(program, sections, relocation.name) or {
				// An undefined weak symbol stands for the address zero (ELF),
				// and a name nothing in the link defines is that symbol: the
				// runtime's own crtbegin.o is where the shape is met, an
				// absolute reference to `_ITM_deregisterTMCloneTable` in the
				// `mov $0, %eax` that the `test %rax, %rax` under it then
				// skips the call over. The addend is the whole of what the
				// field holds, because the zero is the whole of the symbol's
				// value; the image's base in its place would have the code
				// jump to the base rather than skip.
				if relocation.name in program.weak_imports {
					return i64(relocation.addend)
				}
				return err
			}
			return i64(base) + i64(where + relocation.addend)
		}
		.tpoff {
			return tpoff_of(program, relocation.name, relocation.addend)!
		}
	}
}

// referent_of is where one reference points, as an offset into the image. It is
// asked with a kind and a name rather than a reference, because the same
// question is asked of a reference in the code and of one in the writable data.
fn referent_of(program image.Program, sections Sections, kind image.FixupKind, name string, extra []string) !int {
	// The array of IRELATIVE entries this image carries is the container's, so its
	// two ends are answered here, before any table a name could be bound in. The C
	// library's startup walks from the first to the second and asks each entry's
	// resolver for the implementation to put in the slot that entry names. A link
	// defines these two names itself; a link that leaves them to the rule for an
	// undefined weak symbol gives both the value zero, and the walk is empty.
	if name == '__rela_iplt_start' {
		return sections.rela
	}
	if name == '__rela_iplt_end' {
		return iplt_end(program, sections)
	}
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
			// An object a unit defines in read-only data is not in `globals`,
			// which is the storage this image holds in the writable section: its
			// bytes are in the merged read-only data and a reference to it names
			// that offset the same way. The definition is looked for before the
			// slot, because a unit that only refers to the object puts a slot in
			// `globals` for it too, and a slot is not where the bytes are.
			if slot := program.read_only_globals[name] {
				return sections.strings + slot.offset
			}
			if definition := program.bound[name] {
				// A name the link answers itself, which is one of the bounds of
				// the image or of a constructor table it placed.
				return sections.globals + definition.offset
			}
			return sections.globals + (program.globals[name] or {
				return error('no global ${name} in the image')
			}).offset
		}
		.got_address {
			// A reference to an object through the global offset table: the
			// place is the slot, which this image lays out, and not the
			// object's own address when a loader is the one that settles it.
			return got_slot(program, sections, name, extra)!
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
