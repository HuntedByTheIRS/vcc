module object

import backend
import image

// The reader for a relocatable object: an ELF64 ET_REL file in, the one unit
// the in-house linker merges out.
//
// `backend/os/elf/object.v` writes this shape, so this file is its inverse, but
// it is not written for that writer alone. A unit is three blobs: the code, the
// read-only data and the writable data, plus the thread-local block a program
// keeps one copy of per thread. Every allocatable section a file holds is copied
// into the blob its other flags name, in section order and at the alignment the
// section asks for, and where it landed is what a reference to a place inside it
// names. The four names this reader used to look for, `.text`, `.rodata`,
// `.data` and `.bss`, are what an object this compiler writes happens to call
// its sections, and each still lands where it did before.
//
// Beyond those four it carries what a C compiler's object actually holds: a
// thread-local section into the TLS block, a constructor table into the writable
// data with its entries left as address-valued references, a common symbol's
// storage made in the writable data, an absolute symbol folded into the constant
// it names, and the IFUNC names the container has to ask a resolver about. An
// allocatable section of an inert type is carried by its flags; a table a link
// has to interpret, and a TLS section of a type this reader does not carry, are
// refused by name.
//
// Every field is bounds-checked before it is used, because a linker input is a
// file this compiler did not write and a malformed one has to be refused rather
// than crash the compiler. What it can carry is the code, the read-only data,
// the writable data with its address-valued slots, the thread-local storage, and
// the references between them. A construct outside that set is named in an error
// rather than guessed at, because a unit that is wrong is worse than a link that
// stops.

// The constants an ELF64 relocatable file is read with. They are the reader's
// own copies rather than the writer's, because a reader that shared the
// writer's constants could not catch the writer changing them.
const elf_magic = [u8(0x7f), u8(`E`), u8(`L`), u8(`F`)]
const elf_class_64 = u8(2)
const elf_data_little_endian = u8(1)
const elf_type_rel = u16(1)
const elf_header_size = 64
const elf_section_header_size = u16(64)
const elf_symbol_size = 24
const elf_relocation_size = 24

// The largest alignment this reader will place a section or a common symbol's
// storage at. A relocatable object asks for a few kilobytes at most; a number
// past this is a malformed file that would otherwise make the padding loop run
// until memory runs out, so it is refused instead.
const max_section_alignment = 65536

// The largest size this reader will make storage for out of a section that has
// no bytes in the file. A SHT_NOBITS section is storage rather than file
// content, so its size is not bounded by the file the way a section with bytes
// is - `.bss` in one member of the C library asks for sixteen kilobytes inside a
// one-kilobyte file, which is ordinary - and a number past this is a malformed
// file that would otherwise have this compiler allocate whatever it said.
const max_section_size = 1 << 30

// The section flags. SHF_ALLOC is what makes a section part of the unit;
// SHF_EXECINSTR sends it to the code blob and SHF_WRITE to the writable one, and
// a section with neither goes to the read-only blob. SHF_TLS sends a section's
// storage to the thread-local block instead of the three blobs, because every
// thread gets its own copy of it.
const shf_write = u64(0x1)
const shf_alloc = u64(0x2)
const shf_execinstr = u64(0x4)
const shf_tls = u64(0x400)

// The section types this reader knows by number. A PROGBITS section has bytes in
// the file, SHT_NOBITS is the zero-filled storage with none, and SHT_NOTE is a
// note. The two constructor-table types are carried into the writable data
// rather than refused. SHT_PREINIT_ARRAY is still refused by name: a
// pre-initializer runs before a shared object is loaded, which is not a thing
// this container writes. A type outside all of these is carried by its flags
// unless is_a_link_table names it as a table a link has to interpret.
const sht_progbits = u32(1)
const sht_symtab = u32(2)
const sht_strtab = u32(3)
const sht_rela = u32(4)
const sht_hash = u32(5)
const sht_dynamic = u32(6)
const sht_note = u32(7)
const sht_nobits = u32(8)
const sht_rel = u32(9)
const sht_dynsym = u32(11)
const sht_init_array = u32(14)
const sht_fini_array = u32(15)
const sht_preinit_array = u32(16)
const sht_group = u32(17)
const sht_symtab_shndx = u32(18)
const sht_gnu_hash = u32(0x6FFFFFF6)
const sht_gnu_verdef = u32(0x6FFFFFFD)
const sht_gnu_verneed = u32(0x6FFFFFFE)
const sht_gnu_versym = u32(0x6FFFFFFF)

// is_a_link_table says whether a section type is one of the tables a link reads
// rather than bytes a program reads: the symbol and string tables, the
// relocations, the dynamic tables and the versioning tables. An allocatable
// section of a type outside these is data the program may read whatever the type
// is called, which is how this machine's unwind table (GNU_SFRAME, which crt1.o
// carries) and any later one are placed without this reader knowing them by
// number.
fn is_a_link_table(kind u32) bool {
	return match kind {
		sht_symtab, sht_strtab, sht_rel, sht_rela, sht_hash, sht_dynamic, sht_dynsym,
		sht_group, sht_symtab_shndx, sht_gnu_hash, sht_gnu_verdef, sht_gnu_verneed,
		sht_gnu_versym {
			true
		}
		else {
			false
		}
	}
}

// The two special section indexes a symbol can name instead of a section. A
// symbol under SHN_ABS is a constant with no storage, and one under SHN_COMMON
// is a tentative definition whose storage the linker makes.
const shn_abs = u16(0xfff1)
const shn_common = u16(0xfff2)

// The st_type low nibble and the st_bind high nibble the reader looks at. The
// GNU IFUNC type is a definition whose st_value is the offset of the resolver
// function a reference asks for the address of.
const stt_object = u8(1)
const stt_section = u8(3)
const stt_gnu_ifunc = u8(10)
const stb_local = u8(0)
const stb_weak = u8(2)

// The relocation kinds this reader carries, by the psABI numbers an ELF64
// x86-64 object carries, and the width of the field each one fills. The ones
// with four-byte pc-relative fields come in two spellings: a direct reference to
// a place, and a reference that reaches an object through the global offset
// table so that a position-independent object can name one another object may
// define. R_X86_64_64 is the eight-byte address in the writable data and, in the
// code or read-only data, the eight-byte absolute field a table of addresses
// holds. R_X86_64_32 and R_X86_64_32S are the same address cut to four bytes,
// the second of them sign-extended. R_X86_64_PC64 is the eight-byte pc-relative
// field an unwind table's entries carry, which is what crt1.o needs first. The
// two TPOFF kinds are how far a thread-local lies below the thread pointer, four
// bytes and eight. They are machine numbers the psABI fixes, so they are written
// here rather than asked of the target, which answers only the code kinds and
// knows a few of these.
const relocation_absolute = u32(1) // R_X86_64_64
const relocation_pc_relative = u32(2) // R_X86_64_PC32
const relocation_plt = u32(4) // R_X86_64_PLT32
const relocation_got_pc_relative = u32(9) // R_X86_64_GOTPCREL
const relocation_32 = u32(10) // R_X86_64_32
const relocation_32s = u32(11) // R_X86_64_32S
const relocation_tpoff64 = u32(18) // R_X86_64_TPOFF64
// R_X86_64_GOTTPOFF names a global offset table slot whose content is how far
// the thread-local lies below the thread pointer rather than where it is: the
// code loads the slot and reaches the variable through the thread pointer. It is
// the initial-exec model, and the reference itself is a four-byte distance to
// the slot, which is what a `.got` reference is.
const relocation_got_tpoff = u32(22)
const relocation_tpoff32 = u32(23) // R_X86_64_TPOFF32
const relocation_pc64 = u32(24) // R_X86_64_PC64
const relocation_got_pc_relative_x = u32(41) // R_X86_64_GOTPCRELX
const relocation_rex_got_pc_relative_x = u32(42) // R_X86_64_REX_GOTPCRELX

// Blob is which of a unit's three parts a section belongs to. A section that is
// not SHF_ALLOC, or one that is not a type this reader carries, has `none`. The
// three blobs are the shape the link merges: it rebases each one with a base of
// its own, so a field has to know which one moves it.
enum Blob {
	none
	code
	read_only
	writable
	// tls is the thread-local block. It is not one of the three blobs: a
	// section with SHF_TLS keeps the same bytes, but every thread gets its own
	// copy of them, so it is placed at its own base in a block of its own.
	tls
}

// Header is the little of the ELF header that decides where the rest of the
// file is: the section header table, its record size and count, and which
// section holds the section names.
struct Header {
	shoff     int
	shentsize int
	shnum     int
	shstrndx  int
}

// Section is one section header as this reader needs it. Its name is resolved
// once, out of the file's own name table.
struct Section {
mut:
	name_off  int
	name      string
	kind      u32
	flags     u64
	offset    int
	size      int
	link      u32
	info      u32
	addralign int
	entsize   int
}

// Symbol is one symbol table entry, minus the name, which is resolved against
// the string table separately.
struct Symbol {
	info  u8
	other u8
	shndx u16
	value u64
	size  u64
}

// Layout is what the reader decided about a file after walking its section
// header table once: which blob each section belongs to, where each one landed
// inside its blob, the three blobs themselves, and where the symbol table is.
// The blobs are built in section order, so the same file gives the same bytes
// every run.
struct Layout {
	// blob_of and base_of are indexed by section number. A section outside the
	// unit has `none` and a base of zero that is never read.
	blob_of   []Blob
	base_of   []int
	text      []u8
	read_only []u8
	writable  []u8
	// alignment is the strictest alignment any writable section asked for,
	// floored at a word, which is where the merged writable data has to start.
	alignment int
	// read_only_alignment is the same for the read-only sections, which is
	// where the merged read-only data has to start for a section's own alignment
	// to hold inside it.
	read_only_alignment int
	// init_run and fini_run are the two code sections the merge gathers with the
	// same-named section of every other unit.
	init_run     image.CodeRun
	eh_frame_run image.CodeRun
	fini_run     image.CodeRun
	// tls_blob is the initialized image of the thread-local storage this unit
	// defines, and tls_size is how much storage the block asks for in all,
	// which is longer when a zero-filled `.tbss` follows the image. The base
	// of each TLS section inside the block is in base_of.
	tls_blob      []u8
	tls_size      int
	tls_alignment int
	// init_offset, init_count, fini_offset and fini_count describe the two
	// constructor tables this unit carries: where the table starts in the
	// writable data and how many eight-byte entries it holds. An offset of
	// zero with a count of zero is a unit with no table of that kind.
	init_offset int
	init_count  int
	fini_offset int
	fini_count  int
	symtab      int
}

// Resolution is what a relocation's symbol stands for: the name the link
// resolves, and the byte inside one of the unit's blobs when the name is a
// section key rather than a symbol. A reference to a place in a blob is written
// as the blob's key and a byte, so the byte is added to the relocation's own
// addend; a reference to a named symbol is the name alone.
struct Resolution {
	name   string
	offset int
}

// Reader carries the parsed file and the imports seen so far, so that resolving
// a relocation can add to the import list without a second walk.
struct Reader {
	bytes []u8
mut:
	imports        []string
	object_imports map[string]bool
	weak_imports   map[string]bool
	seen           map[string]bool
}

// read turns one ELF64 relocatable object into the unit the linker merges. It
// refuses anything it cannot carry whole, naming the construct and, where there
// is one, the number or offset that made it impossible.
pub fn read(bytes []u8, target backend.Target) !image.Program {
	header := parse_header(bytes, target)!
	sections := parse_sections(bytes, header)!
	layout := lay_out(bytes, sections)!
	mut program := image.Program{
		text:                layout.text
		string_blob:         layout.read_only
		globals_blob:        layout.writable
		globals_alignment:   layout.alignment
		read_only_alignment: layout.read_only_alignment
		init_run:            layout.init_run
		eh_frame_run:        layout.eh_frame_run
		fini_run:            layout.fini_run
		labels:              map[string]int{}
		defined:             map[string]bool{}
		globals:             map[string]image.GlobalSlot{}
		internal:            map[string]bool{}
		weak:                map[string]bool{}
		weak_imports:        map[string]bool{}
		tls_slots:           map[string]bool{}
		read_only_globals:   map[string]GlobalSlot{}
		strings:             map[string]int{}
		wide_strings:        map[string]int{}
		doubles:             map[string]int{}
		imports:             []string{}
		object_imports:      map[string]bool{}
		copy_objects:        []string{}
		libraries:           []string{}
		bound:               map[string]image.Definition{}
		tls_blob:            layout.tls_blob
		tls_size:            layout.tls_size
		tls_alignment:       layout.tls_alignment
		tls_labels:          map[string]int{}
		init_array:          image.ConstructorTable{
			offset: layout.init_offset
			count:  layout.init_count
		}
		fini_array:          image.ConstructorTable{
			offset: layout.fini_offset
			count:  layout.fini_count
		}
		ifuncs:              map[string]bool{}
	}
	read_definitions(bytes, sections, layout, mut program)!
	mut reader := Reader{
		bytes:          bytes
		imports:        []string{}
		object_imports: map[string]bool{}
		weak_imports:   map[string]bool{}
		seen:           map[string]bool{}
	}
	read_relocations(bytes, sections, layout, mut program, mut reader)!
	program.imports = reader.imports
	program.object_imports = reader.object_imports
	program.weak_imports = reader.weak_imports
	return program
}

// lay_out walks the section header table once and copies every allocatable
// section into the blob its flags name, at the alignment it asks for, recording
// where each landed. The four names an object this compiler writes still land
// first in their blob, so such an object reads as it always did. A thread-local
// section goes into the thread-local block, a constructor table into the
// writable data, and an allocatable section of an inert type is carried by its
// flags. A pre-initializer array, a TLS section of a type this reader does not
// carry, and a table a link has to interpret are refused here by name.
//
// The constructor sections of each kind are placed together at the end of the
// writable data, after every ordinary writable section, so that the one table of
// each kind can cover all of its sections contiguously. A file that carries only
// `.init_array` gains nothing from the regrouping; a file that carries a
// `.init_array` and a `.init_array.00000` for a priority gets one table that
// holds both.
fn lay_out(bytes []u8, sections []Section) !Layout {
	mut blob_of := []Blob{len: sections.len, init: .none}
	mut base_of := []int{len: sections.len, init: 0}
	mut is_init := []bool{len: sections.len, init: false}
	mut is_fini := []bool{len: sections.len, init: false}
	mut symtab := -1
	for i, s in sections {
		if s.kind == sht_symtab && symtab < 0 {
			symtab = i
		}
		if (s.flags & shf_alloc) == 0 {
			// A section that is not allocatable is not part of the unit: the
			// section header table, the symbol table, the string tables, a
			// comment, and the debug sections all fall out here without a
			// name being written down for any of them.
			continue
		}
		if s.addralign > max_section_alignment {
			return error('section ${i} (${s.name}) asks for alignment ${s.addralign}, past the ${max_section_alignment} this reader will place a section at')
		}
		if (s.flags & shf_tls) != 0 {
			if s.kind != sht_progbits && s.kind != sht_nobits {
				return error('section ${i} (${s.name}) is SHF_TLS and type ${s.kind}, and this reader carries a TLS section only with bytes (SHT_PROGBITS) or without (SHT_NOBITS)')
			}
			blob_of[i] = .tls
			continue
		}
		if s.kind == sht_preinit_array {
			return error('section ${i} (${s.name}) is type ${s.kind} (SHT_PREINIT_ARRAY), and a pre-initializer runs before a shared object is loaded, which this container does not write')
		}
		if s.kind == sht_init_array {
			blob_of[i] = .writable
			is_init[i] = true
			continue
		}
		if s.kind == sht_fini_array {
			blob_of[i] = .writable
			is_fini[i] = true
			continue
		}
		if s.kind != sht_progbits && s.kind != sht_nobits && s.kind != sht_note {
			// A section of another type is carried by its flags unless it is
			// one of the tables a link has to interpret. Carrying a table as
			// data would place bytes nothing read the meaning of, so each of
			// those is refused by name.
			if is_a_link_table(s.kind) {
				return error('section ${i} (${s.name}) is type ${s.kind}, which is a table this reader does not interpret')
			}
		}
		blob_of[i] = classify(s.flags)
	}
	mut text := []u8{}
	mut read_only := []u8{}
	mut writable := []u8{}
	mut alignment := 8
	mut read_only_alignment := 0
	mut init_run := image.CodeRun{}
	mut eh_frame_run := image.CodeRun{}
	mut fini_run := image.CodeRun{}
	for i, s in sections {
		if blob_of[i] != .code {
			continue
		}
		pad(mut text, align_gap(s.addralign))
		// The two sections the merge gathers rather than placing with their
		// unit: where each one sits here is what the merge has to know to move
		// it, and how long it is and what it asks for are what places it with
		// the other units' fragments.
		if s.name == '.init' {
			init_run = image.CodeRun{
				base:      text.len
				len:       s.size
				alignment: align_gap(s.addralign)
			}
		} else if s.name == '.fini' {
			fini_run = image.CodeRun{
				base:      text.len
				len:       s.size
				alignment: align_gap(s.addralign)
			}
		}
		base_of[i] = text.len
		copy_section(mut text, bytes, s)
	}
	for i, s in sections {
		if blob_of[i] != .read_only {
			continue
		}
		gap := align_gap(s.addralign)
		pad(mut read_only, gap)
		if gap > read_only_alignment {
			read_only_alignment = gap
		}
		base_of[i] = read_only.len
		if s.name == '.eh_frame' {
			eh_frame_run = image.CodeRun{
				base:      read_only.len
				len:       int(s.size)
				alignment: int(s.addralign)
			}
		}
		copy_section(mut read_only, bytes, s)
	}
	// The ordinary writable sections keep section order, and the constructor
	// tables follow them together so each table's entries are contiguous.
	for i, s in sections {
		if blob_of[i] != .writable || is_init[i] || is_fini[i] {
			continue
		}
		gap := align_gap(s.addralign)
		pad(mut writable, gap)
		base_of[i] = writable.len
		copy_section(mut writable, bytes, s)
		if gap > alignment {
			alignment = gap
		}
	}
	mut init_offset := 0
	mut init_count := 0
	for i, s in sections {
		if !is_init[i] {
			continue
		}
		gap := align_gap(s.addralign)
		pad(mut writable, gap)
		base_of[i] = writable.len
		if init_count == 0 {
			init_offset = writable.len
		}
		copy_section(mut writable, bytes, s)
		init_count += s.size / 8
		if gap > alignment {
			alignment = gap
		}
	}
	mut fini_offset := 0
	mut fini_count := 0
	for i, s in sections {
		if !is_fini[i] {
			continue
		}
		gap := align_gap(s.addralign)
		pad(mut writable, gap)
		base_of[i] = writable.len
		if fini_count == 0 {
			fini_offset = writable.len
		}
		copy_section(mut writable, bytes, s)
		fini_count += s.size / 8
		if gap > alignment {
			alignment = gap
		}
	}
	mut tls_blob := []u8{}
	mut tls_size := 0
	mut tls_alignment := 0
	for i, s in sections {
		if blob_of[i] != .tls {
			continue
		}
		gap := align_gap(s.addralign)
		for tls_size % gap != 0 {
			tls_size++
		}
		if s.kind == sht_nobits {
			// A section with no bytes in the file still takes its place in the
			// block, and the storage it asks for is the zero-filled tail.
			base_of[i] = tls_size
			tls_size += s.size
		} else {
			// The initialized image has to reach this section's place even
			// when a zero-filled part came before it.
			for tls_blob.len < tls_size {
				tls_blob << u8(0)
			}
			pad(mut tls_blob, gap)
			base_of[i] = tls_blob.len
			tls_blob << section_bytes(bytes, s)
			if tls_blob.len > tls_size {
				tls_size = tls_blob.len
			}
		}
		if gap > tls_alignment {
			tls_alignment = gap
		}
	}
	if tls_alignment > 0 && tls_alignment < 8 {
		// The block holds addresses as readily as bytes, so its start is kept
		// at eight-byte alignment however little the strictest member asked
		// for.
		tls_alignment = 8
	}
	return Layout{
		blob_of:             blob_of
		base_of:             base_of
		text:                text
		read_only:           read_only
		read_only_alignment: read_only_alignment
		init_run:            init_run
		eh_frame_run:        eh_frame_run
		fini_run:            fini_run
		writable:            writable
		alignment:           alignment
		tls_blob:            tls_blob
		tls_size:            tls_size
		tls_alignment:       tls_alignment
		init_offset:         init_offset
		init_count:          init_count
		fini_offset:         fini_offset
		fini_count:          fini_count
		symtab:              symtab
	}
}

// align_gap is the alignment a section has to be placed at: the number it asks
// for, or one when it asks for none. A place is always at least one byte apart.
fn align_gap(addralign int) int {
	return if addralign > 1 { addralign } else { 1 }
}

// classify is which blob a section's other flags send it to. It is asked only
// of an allocatable section, so every answer is one of the three.
fn classify(flags u64) Blob {
	if (flags & shf_execinstr) != 0 {
		return .code
	}
	if (flags & shf_write) != 0 {
		return .writable
	}
	return .read_only
}

// pad appends the zeroes that bring a blob up to the next multiple of the
// alignment a section asks for, which is where that section has to start for
// its own alignment to be true in the merged image.
fn pad(mut blob []u8, alignment int) {
	for blob.len % alignment != 0 {
		blob << u8(0)
	}
}

// copy_section appends one section to its blob: its file bytes when it has
// them, and as many zeroes as its size says when it is SHT_NOBITS, which is the
// storage a file carries no bytes for.
fn copy_section(mut blob []u8, bytes []u8, section Section) {
	if section.kind == sht_nobits {
		for _ in 0 .. section.size {
			blob << u8(0)
		}
		return
	}
	blob << section_bytes(bytes, section)
}

// read_definitions walks the symbol table and records what this object defines.
// A symbol defined in the code blob becomes a label, an object in the writable
// blob becomes a global slot, and either one carries its linkage and its weak
// binding with it. A symbol defined in the read-only blob gets no table entry:
// its place is named by the section key when a reference reaches it. A symbol
// defined in a thread-local section is recorded in the thread-local labels and
// in the definitions the container reads, because a thread-local is neither a
// label in the code nor a slot in the writable data. A common symbol is a
// tentative definition, and its storage is made here in the writable blob, at
// the alignment its value asks for, recorded the way a .bss definition is. An
// IFUNC is a definition whose value is a resolver function, so it is recorded in
// the ifunc set the container has to ask. A section symbol and an unnamed symbol
// are the file's own scaffolding and are skipped, and an absolute symbol has no
// storage to record.
fn read_definitions(bytes []u8, sections []Section, layout Layout, mut program image.Program) ! {
	if layout.symtab < 0 {
		return
	}
	symtab := sections[layout.symtab]
	if symtab.link >= u32(sections.len) {
		return error('the symbol table names section ${symtab.link} as its string table and the file has ${sections.len} sections')
	}
	strtab := section_bytes(bytes, sections[int(symtab.link)])
	count := symtab.size / elf_symbol_size
	for i in 1 .. count {
		sym := parse_symbol(bytes, symtab, i)!
		kind := sym.info & 0xf
		bind := sym.info >> 4
		if sym.shndx == shn_abs || kind == stt_section {
			continue
		}
		if int(sym.shndx) >= layout.blob_of.len && sym.shndx != shn_common {
			continue
		}
		name := symbol_name(bytes, symtab, strtab, i)!
		if name == '' {
			continue
		}
		if sym.shndx == shn_common {
			// A tentative definition: the link has to make the storage, and
			// this unit makes it in its own writable blob, at the alignment the
			// symbol's value names.
			align := if sym.value > 1 { int(sym.value) } else { 1 }
			if align > max_section_alignment {
				return error('common symbol ${name} asks for alignment ${sym.value}, past the ${max_section_alignment} this reader will place storage at')
			}
			pad(mut program.globals_blob, align)
			width := if sym.size > 0 { int(sym.size) } else { 8 }
			program.globals[name] = image.GlobalSlot{
				offset: program.globals_blob.len
				width:  width
			}
			for _ in 0 .. int(sym.size) {
				program.globals_blob << u8(0)
			}
			// The blob has to start at the strictest alignment any of its
			// members asked for, or a member's offset inside it would not be a
			// multiple of its own alignment in the merged image.
			if align > program.globals_alignment {
				program.globals_alignment = align
			}
			record_linkage(mut program, name, bind)
			continue
		}
		match layout.blob_of[int(sym.shndx)] {
			.code {
				program.labels[name] = layout.base_of[int(sym.shndx)] + int(sym.value)
				program.defined[name] = true
				record_linkage(mut program, name, bind)
			}
			.writable {
				width := if sym.size > 0 { int(sym.size) } else { 8 }
				program.globals[name] = image.GlobalSlot{
					offset: layout.base_of[int(sym.shndx)] + int(sym.value)
					width:  width
				}
				record_linkage(mut program, name, bind)
			}
			.read_only {
				// An object defined in read-only data: a `const` object at
				// file scope, or a name the C library's own headers define.
				// A reference to it names a place the merged read-only data
				// has to hold, so where it lies in this unit's part of that
				// blob is recorded the way a writable object's slot is.
				width := if sym.size > 0 { int(sym.size) } else { 8 }
				program.read_only_globals[name] = image.GlobalSlot{
					offset: layout.base_of[int(sym.shndx)] + int(sym.value)
					width:  width
				}
				record_linkage(mut program, name, bind)
			}
			.tls {
				offset := layout.base_of[int(sym.shndx)] + int(sym.value)
				program.tls_labels[name] = offset
				// The container reads the same number as a definition, so a
				// `.tpoff` reference to the name resolves to it rather than to
				// a place in one of the three blobs.
				program.bound[name] = image.Definition{
					offset:   offset
					function: false
					tls:      true
				}
				record_linkage(mut program, name, bind)
			}
			.none {}
		}
		if kind == stt_gnu_ifunc {
			program.ifuncs[name] = true
		}
	}
}

// record_linkage marks a definition with the binding its st_info byte carries.
// A local binding is what a file-scope `static` gives a name, and a weak one is
// what a definition a link may replace carries.
fn record_linkage(mut program image.Program, name string, bind u8) {
	if bind == stb_local {
		program.internal[name] = true
	}
	if bind == stb_weak {
		program.weak[name] = true
	}
}

// read_relocations walks every SHT_RELA section whose target lies in one of the
// blobs and reads one reference out of each entry. A reference in the code or in
// read-only data is a field of four or eight bytes the link fills in: a direct
// pc-relative distance, a global offset table slot, an absolute address, or how
// far a thread-local lies below the thread pointer. A reference in writable data
// is an eight-byte address and becomes a data fixup, unless it is an entry of a
// constructor table, which is always an eight-byte absolute reference the link
// writes rather than a fixup this unit settles. A reference to an absolute
// symbol folds to the number the symbol names, with an empty name: the container
// is told that an absolute relocation with an empty name writes its addend and
// nothing else. A relocation that applies to a thread-local section is refused,
// because this reader carries no reference inside thread-local storage. Anything
// else is refused with its number and, where the psABI names it, that name. The
// section header table is walked in order, so the imports a file names keep a
// deterministic first-seen order.
fn read_relocations(bytes []u8, sections []Section, layout Layout, mut program image.Program, mut reader Reader) ! {
	for reloca in sections {
		if reloca.kind != sht_rela {
			continue
		}
		if int(reloca.info) >= sections.len {
			continue
		}
		target := sections[int(reloca.info)]
		target_blob := layout.blob_of[int(reloca.info)]
		place := relocation_place(target_blob) or { continue }
		symtab := referenced_symtab(sections, reloca)!
		if symtab.link >= u32(sections.len) {
			return error('the symbol table names section ${symtab.link} as its string table and the file has ${sections.len} sections')
		}
		strtab := section_bytes(bytes, sections[int(symtab.link)])
		base := layout.base_of[int(reloca.info)]
		is_table := target.kind == sht_init_array || target.kind == sht_fini_array
		count := reloca.size / elf_relocation_size
		for entry in 0 .. count {
			at := reloca.offset + entry * elf_relocation_size
			r_offset := read_u64(bytes, at)!
			r_info := read_u64(bytes, at + 8)!
			r_addend := i64(read_u64(bytes, at + 16)!)
			kind := u32(r_info & 0xffffffff)
			sym_index := int(r_info >> 32)
			sym := parse_symbol(bytes, symtab, sym_index)!
			if place == .tls {
				// A field in the thread-local image holds an address the link
				// writes, the eight bytes a table entry or a writable object's
				// initializer holds: the loader makes every thread's copy from
				// this image, so whatever in it points outside has to be the
				// final address. A distance would name where the image happens
				// to lie in the file, which is not where the copy ends.
				if kind != relocation_absolute {
					return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${relocation_absolute} (R_X86_64_64) in thread-local storage')
				}
				resolution := reader.resolve(symtab, strtab, sym_index, sym, layout)!
				program.relocations << image.Relocation{
					offset: base + int(r_offset)
					place:  .tls
					kind:   image.RelocationKind.absolute
					name:   resolution.name
					addend: int(r_addend) + resolution.offset
					width:  image.RelocationWidth.wide
				}
				continue
			}
			if place == .data {
				if is_table {
					// A constructor table entry: eight bytes holding an
					// address the link writes, always absolute.
					if kind != relocation_absolute {
						return error('unknown relocation type ${kind} at offset ${r_offset}: a constructor table entry is R_X86_64_64 (${relocation_absolute})')
					}
					if sym.shndx == shn_abs {
						program.relocations << image.Relocation{
							offset: base + int(r_offset)
							place:  place
							kind:   image.RelocationKind.absolute
							name:   ''
							addend: int(sym.value) + int(r_addend)
							width:  image.RelocationWidth.wide
						}
						continue
					}
					resolution := reader.resolve(symtab, strtab, sym_index, sym, layout)!
					program.relocations << image.Relocation{
						offset: base + int(r_offset)
						place:  place
						kind:   image.RelocationKind.absolute
						name:   resolution.name
						addend: int(r_addend) + resolution.offset
						width:  image.RelocationWidth.wide
					}
					continue
				}
				if kind != relocation_absolute {
					return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${relocation_absolute} (R_X86_64_64) in the writable data')
				}
				if sym.shndx == shn_abs {
					// An eight-byte field holding a constant the symbol names.
					program.relocations << image.Relocation{
						offset: base + int(r_offset)
						place:  place
						kind:   image.RelocationKind.absolute
						name:   ''
						addend: int(sym.value) + int(r_addend)
						width:  image.RelocationWidth.wide
					}
					continue
				}
				resolution := reader.resolve(symtab, strtab, sym_index, sym, layout)!
				fixup_kind := if (sym.info & 0xf) == stt_section {
					image.FixupKind.section_address
				} else {
					image.FixupKind.import_address
				}
				program.data_fixups << image.DataFixup{
					offset: base + int(r_offset)
					kind:   fixup_kind
					name:   resolution.name
					addend: int(r_addend) + resolution.offset
				}
				continue
			}
			if sym.shndx == shn_abs {
				// A symbol with no storage: the field holds the constant the
				// symbol names, so there is nothing for the link to resolve and
				// the empty name tells it to write the addend alone.
				reference := reference_of(kind) or { return error(unknown_relocation_message(kind, r_offset)) }
				program.relocations << image.Relocation{
					offset: base + int(r_offset)
					place:  place
					kind:   image.RelocationKind.absolute
					name:   ''
					addend: int(sym.value) + int(r_addend)
					width:  reference.width
				}
				continue
			}
			reference := reference_of(kind) or { return error(unknown_relocation_message(kind, r_offset)) }
			resolution := reader.resolve(symtab, strtab, sym_index, sym, layout)!
			// A `.gottpoff` reference reads a slot whose content is how far the
			// thread-local lies below the thread pointer rather than its address,
			// so the name is marked as one whose slot holds a number this link
			// writes instead of an address it fills in.
			if kind == relocation_got_tpoff {
				program.tls_slots[resolution.name] = true
			}
			program.relocations << image.Relocation{
				offset: base + int(r_offset)
				place:  place
				kind:   reference.kind
				name:   resolution.name
				addend: int(r_addend) + resolution.offset
				width:  reference.width
			}
		}
	}
}

// relocation_place is which of a unit's blobs a section's field lies in, as the
// image names it, or none when the section is not part of the unit. The
// thread-local image is one of them: a field in it is copied to every thread, so
// it holds an address the link writes.
fn relocation_place(blob Blob) ?image.RelocationPlace {
	if blob == .code {
		return image.RelocationPlace.text
	}
	if blob == .read_only {
		return image.RelocationPlace.read_only
	}
	if blob == .writable {
		return image.RelocationPlace.data
	}
	if blob == .tls {
		return image.RelocationPlace.tls
	}
	return none
}

// Reference is how a field in the code or read-only data reaches what it names,
// and how wide the field is.
struct Reference {
	kind  image.RelocationKind
	width image.RelocationWidth
}

// reference_of is how a kind of relocation reaches what it names, and the width
// of the field it fills, or none for a kind this reader refuses. Types 2, 4 and
// 9 through 42 are the four-byte pc-relative forms; 1, 18 and 24 are eight bytes;
// 10 and 11 are a four-byte absolute address; 23 is a four-byte thread pointer
// offset.
fn reference_of(kind u32) ?Reference {
	width := field_width(kind) or { return none }
	match kind {
		relocation_pc_relative, relocation_plt, relocation_pc64 {
			return Reference{image.RelocationKind.direct, width}
		}
		relocation_got_pc_relative, relocation_got_pc_relative_x,
		relocation_rex_got_pc_relative_x, relocation_got_tpoff {
			return Reference{image.RelocationKind.got, width}
		}
		relocation_absolute, relocation_32, relocation_32s {
			return Reference{image.RelocationKind.absolute, width}
		}
		relocation_tpoff32, relocation_tpoff64 {
			return Reference{image.RelocationKind.tpoff, width}
		}
		else {
			return none
		}
	}
}

// field_width is how many bytes the field a relocation fills occupies: eight for
// the addresses a table of addresses holds, four for everything else this reader
// carries. None is a kind it does not carry.
fn field_width(kind u32) ?image.RelocationWidth {
	return match kind {
		relocation_absolute, relocation_pc64, relocation_tpoff64 {
			image.RelocationWidth.wide
		}
		relocation_pc_relative, relocation_plt, relocation_got_pc_relative,
		relocation_got_pc_relative_x, relocation_rex_got_pc_relative_x,
		relocation_got_tpoff, relocation_32, relocation_32s, relocation_tpoff32 {
			image.RelocationWidth.narrow
		}
		else {
			none
		}
	}
}

// relocation_name is the psABI name of a relocation kind this reader refuses: the
// thread-local models it does not carry, the sizes, and the GOT forms that need a
// table it does not build. A number outside these has no name here and is
// reported by its number alone.
fn relocation_name(kind u32) string {
	return match kind {
		3 { 'R_X86_64_GOT32' }
		16 { 'R_X86_64_DTPMOD64' }
		17 { 'R_X86_64_DTPOFF64' }
		19 { 'R_X86_64_TLSGD' }
		20 { 'R_X86_64_TLSLD' }
		21 { 'R_X86_64_DTPOFF32' }
		22 { 'R_X86_64_GOTTPOFF' }
		25 { 'R_X86_64_GOTOFF64' }
		26 { 'R_X86_64_GOTPC32' }
		27 { 'R_X86_64_GOT64' }
		28 { 'R_X86_64_GOTPCREL64' }
		29 { 'R_X86_64_GOTPC64' }
		30 { 'R_X86_64_GOTPLT64' }
		31 { 'R_X86_64_PLTOFF64' }
		32 { 'R_X86_64_SIZE32' }
		33 { 'R_X86_64_SIZE64' }
		34 { 'R_X86_64_GOTPC32_TLSDESC' }
		35 { 'R_X86_64_TLSDESC_CALL' }
		36 { 'R_X86_64_TLSDESC' }
		else { '' }
	}
}

// unknown_relocation_message is the error a kind outside what this reader carries
// is refused with: the number, the psABI name where it has one, and the list of
// numbers this reader does accept.
fn unknown_relocation_message(kind u32, offset u64) string {
	name := relocation_name(kind)
	named := if name == '' { '' } else { ' (${name})' }
	return 'unknown relocation type ${kind}${named} at offset ${offset}: this reader accepts ${relocation_pc_relative} (R_X86_64_PC32), ${relocation_plt} (R_X86_64_PLT32), ${relocation_got_pc_relative} (R_X86_64_GOTPCREL), ${relocation_got_pc_relative_x} (R_X86_64_GOTPCRELX), ${relocation_rex_got_pc_relative_x} (R_X86_64_REX_GOTPCRELX), ${relocation_absolute} (R_X86_64_64), ${relocation_32} (R_X86_64_32), ${relocation_32s} (R_X86_64_32S), ${relocation_pc64} (R_X86_64_PC64), ${relocation_tpoff32} (R_X86_64_TPOFF32) and ${relocation_tpoff64} (R_X86_64_TPOFF64) and ${relocation_got_tpoff} (R_X86_64_GOTTPOFF) in the code and read-only data'
}

// referenced_symtab is the symbol table a relocation section reads its symbols
// from, which the section names in sh_link.
fn referenced_symtab(sections []Section, reloca Section) !Section {
	if reloca.link >= u32(sections.len) {
		return error('the relocation section names symbol table ${reloca.link} and the file has ${sections.len} sections')
	}
	symtab := sections[int(reloca.link)]
	if symtab.kind != sht_symtab {
		return error('the relocation section names section ${reloca.link} as its symbol table and it is not SHT_SYMTAB')
	}
	return symtab
}

// resolve is the name a relocation is written under and the byte the name
// stands at inside the unit. A section symbol becomes the key of the blob its
// section was copied into, with the section's own base; a named symbol defined
// in the read-only blob becomes the read-only key, with its section's base and
// its value; a named symbol defined in the code, writable or thread-local block
// keeps its name, because it is a label, a global slot or a thread-local the link
// already holds. A common symbol is a definition whose storage this reader made
// in the writable blob, so it keeps its name too. An absolute symbol never
// reaches here: a reference to one is folded to the constant it names before
// resolve is asked. An undefined symbol is an import, and its type says whether
// the link is looking for a function or an object.
fn (mut r Reader) resolve(symtab Section, strtab []u8, index int, sym Symbol, layout Layout) !Resolution {
	kind := sym.info & 0xf
	if sym.shndx == shn_abs {
		return error('the relocation names symbol ${index}, which is SHN_ABS and lives at no offset in any section')
	}
	if kind == stt_section {
		key := section_key_of(sym.shndx, layout) or {
			return error('the relocation names section symbol ${index} of section ${sym.shndx}, and this reader carries no such section')
		}
		return Resolution{
			name:   key
			offset: layout.base_of[int(sym.shndx)] + int(sym.value)
		}
	}
	name := symbol_name(r.bytes, symtab, strtab, index)!
	if sym.shndx == shn_common {
		if name == '' {
			return error('the relocation names common symbol ${index}, which has no name')
		}
		return Resolution{
			name:   name
			offset: 0
		}
	}
	if sym.shndx == 0 {
		if name == '' {
			return error('the relocation names undefined symbol ${index}, which has no name')
		}
		if kind == stt_object {
			r.object_imports[name] = true
		}
		// A reference to a symbol no unit defines is what a link has to answer,
		// unless the reference is weak: an undefined weak symbol stands for zero
		// (ELF), and the runtime's own startup files are full of them -
		// `__gmon_start__` in the `.init` of crti.o, the transaction hooks in
		// crtbegin.o. Carrying the name keeps a reference to it resolvable; the
		// mark is what keeps it out of the libraries a link asks.
		if sym.info >> 4 == stb_weak {
			r.weak_imports[name] = true
		}
		if name !in r.seen {
			r.seen[name] = true
			r.imports << name
		}
		return Resolution{
			name:   name
			offset: 0
		}
	}
	blob := if int(sym.shndx) < layout.blob_of.len {
		layout.blob_of[int(sym.shndx)]
	} else {
		Blob.none
	}
	if blob == .none {
		return error('the relocation names symbol ${index} (${name}) defined in section ${sym.shndx}, which this reader does not handle')
	}
	if name == '' {
		return error('the relocation names defined symbol ${index} in section ${sym.shndx}, which has no name')
	}
	if blob == .read_only {
		return Resolution{
			name:   image.section_key_rodata
			offset: layout.base_of[int(sym.shndx)] + int(sym.value)
		}
	}
	return Resolution{
		name:   name
		offset: 0
	}
}

// section_key_of is the image's name for the blob a section was copied into, or
// none when the section is not part of the unit. Both a section symbol and a
// named symbol the reader keeps no table entry for resolve through it, so a
// reference to a place is a key and a byte rather than a name.
fn section_key_of(shndx u16, layout Layout) ?string {
	if int(shndx) >= layout.blob_of.len {
		return none
	}
	blob := layout.blob_of[int(shndx)]
	if blob == .code {
		return image.section_key_text
	}
	if blob == .read_only {
		return image.section_key_rodata
	}
	if blob == .writable {
		return image.section_key_data
	}
	return none
}

// parse_header reads the ELF header and refuses a file that is not a relocatable
// object for the target. It is where the four identity checks live: the magic,
// the class, the byte order and the file type, plus the machine.
fn parse_header(bytes []u8, target backend.Target) !Header {
	if bytes.len < elf_header_size {
		return error('truncated file: ${bytes.len} bytes is less than the ${elf_header_size}-byte ELF header')
	}
	if bytes[0] != elf_magic[0] || bytes[1] != elf_magic[1] || bytes[2] != elf_magic[2]
		|| bytes[3] != elf_magic[3] {
		return error('not ELF: the file does not begin with 0x7f 45 4c 46')
	}
	if bytes[4] != elf_class_64 {
		return error('not ELF64: the file is ELF class ${bytes[4]}')
	}
	if bytes[5] != elf_data_little_endian {
		return error('not little-endian: the file is ELF data encoding ${bytes[5]}')
	}
	e_type := read_u16(bytes, 16)!
	if e_type != elf_type_rel {
		return error('not ET_REL: e_type is ${e_type}, and a linker input is ET_REL (${elf_type_rel})')
	}
	e_machine := read_u16(bytes, 18)!
	if e_machine != target.elf_machine {
		return error('e_machine ${e_machine} is not ${target.elf_machine} (${target.name})')
	}
	shoff := read_u64(bytes, 40)!
	shentsize := read_u16(bytes, 58)!
	shnum := read_u16(bytes, 60)!
	shstrndx := read_u16(bytes, 62)!
	if shentsize < elf_section_header_size {
		return error('the section header table has ${shentsize}-byte entries, and this reader needs ${elf_section_header_size}')
	}
	table_end := shoff + u64(shnum) * u64(shentsize)
	if shoff > u64(bytes.len) || table_end > u64(bytes.len) {
		return error('truncated file: the section header table ends at ${table_end} and the file is ${bytes.len} bytes')
	}
	if shstrndx >= shnum {
		return error('the file names section ${shstrndx} as its section name table and has ${shnum} sections')
	}
	return Header{
		shoff:     int(shoff)
		shentsize: int(shentsize)
		shnum:     int(shnum)
		shstrndx:  int(shstrndx)
	}
}

// parse_sections reads the section header table and resolves each section's name
// out of the file's own name table. A section's bytes are checked to lie inside
// the file before any of them are read.
fn parse_sections(bytes []u8, header Header) ![]Section {
	mut sections := []Section{cap: header.shnum}
	for i in 0 .. header.shnum {
		sections << raw_section(bytes, header, i)!
	}
	str := sections[header.shstrndx]
	if str.kind != sht_strtab {
		return error("section ${header.shstrndx} names the file's sections and is not SHT_STRTAB")
	}
	shstrtab := section_bytes(bytes, str)
	for i in 0 .. sections.len {
		mut s := sections[i]
		s.name = cstr(shstrtab, s.name_off)!
		sections[i] = s
	}
	return sections
}

// raw_section reads one section header without its name. A section with file
// bytes has to end inside the file; a SHT_NOBITS section has none, so only where
// it would start is checked.
fn raw_section(bytes []u8, header Header, index int) !Section {
	base := header.shoff + index * header.shentsize
	name_off := read_u32(bytes, base)!
	kind := read_u32(bytes, base + 4)!
	flags := read_u64(bytes, base + 8)!
	offset := field_int(read_u64(bytes, base + 24)!, 'the offset of section ${index}', bytes.len)!
	// A section with bytes in the file has to end inside it. A SHT_NOBITS one
	// has no bytes there at all: its size is the storage the program wants, so
	// it is bounded by what this reader will allocate and not by the file's
	// length.
	size := if kind == sht_nobits {
		field_int(read_u64(bytes, base + 32)!, 'the size of section ${index}', max_section_size)!
	} else {
		field_int(read_u64(bytes, base + 32)!, 'the size of section ${index}', bytes.len)!
	}
	link := read_u32(bytes, base + 40)!
	info := read_u32(bytes, base + 44)!
	addralign := read_u64(bytes, base + 48)!
	entsize := read_u64(bytes, base + 56)!
	if kind != sht_nobits && offset + size > bytes.len {
		return error('section ${index} ends at ${offset + size} and the file is ${bytes.len} bytes')
	}
	return Section{
		name_off:  int(name_off)
		kind:      kind
		flags:     flags
		offset:    offset
		size:      size
		link:      link
		info:      info
		addralign: int(addralign)
		entsize:   int(entsize)
	}
}

// parse_symbol reads one symbol table entry. The entry has to lie inside the
// table, whose own bytes were checked when its section header was read.
fn parse_symbol(bytes []u8, symtab Section, index int) !Symbol {
	count := symtab.size / elf_symbol_size
	if index < 0 || index >= count {
		return error('symbol index ${index} is outside the ${count} entries of the symbol table')
	}
	at := symtab.offset + index * elf_symbol_size
	if at + elf_symbol_size > bytes.len {
		return error('symbol ${index} ends at ${at + elf_symbol_size} and the file is ${bytes.len} bytes')
	}
	return Symbol{
		info:  bytes[at + 4]
		other: bytes[at + 5]
		shndx: read_u16(bytes, at + 6)!
		value: read_u64(bytes, at + 8)!
		size:  read_u64(bytes, at + 16)!
	}
}

// symbol_name is the name one symbol table entry points at, read out of the
// string table its table names.
fn symbol_name(bytes []u8, symtab Section, strtab []u8, index int) !string {
	at := symtab.offset + index * elf_symbol_size
	offset := read_u32(bytes, at)!
	return cstr(strtab, int(offset))
}

// section_bytes is one section's bytes in the file, which were checked to lie
// inside it when the header was read.
fn section_bytes(bytes []u8, section Section) []u8 {
	if section.size == 0 {
		return []u8{}
	}
	return bytes[section.offset..section.offset + section.size]
}

// cstr reads a NUL-terminated name out of a string table. A name that runs to
// the end of the table without a terminator is refused rather than cut short.
fn cstr(bytes []u8, at int) !string {
	if at < 0 || at >= bytes.len {
		return error('a name at ${at} is outside the ${bytes.len} bytes of a string table')
	}
	mut end := at
	for end < bytes.len && bytes[end] != u8(0) {
		end++
	}
	if end >= bytes.len {
		return error('a name at ${at} has no terminator in a string table of ${bytes.len} bytes')
	}
	return bytes[at..end].bytestr()
}

// field_int turns a u64 header field into an int only when it fits inside the
// file, so a length the file cannot hold is refused rather than truncated.
fn field_int(value u64, what string, limit int) !int {
	if value > u64(limit) {
		return error('${what} is ${value}, past the ${limit} bytes of the file')
	}
	return int(value)
}

fn read_u16(bytes []u8, at int) !u16 {
	if at < 0 || at + 2 > bytes.len {
		return error('a two-byte field at ${at} is outside the ${bytes.len} bytes of the file')
	}
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn read_u32(bytes []u8, at int) !u32 {
	if at < 0 || at + 4 > bytes.len {
		return error('a four-byte field at ${at} is outside the ${bytes.len} bytes of the file')
	}
	mut value := u32(0)
	for i in 0 .. 4 {
		value |= u32(bytes[at + i]) << (8 * i)
	}
	return value
}

fn read_u64(bytes []u8, at int) !u64 {
	if at < 0 || at + 8 > bytes.len {
		return error('an eight-byte field at ${at} is outside the ${bytes.len} bytes of the file')
	}
	mut value := u64(0)
	for i in 0 .. 8 {
		value |= u64(bytes[at + i]) << (8 * i)
	}
	return value
}
