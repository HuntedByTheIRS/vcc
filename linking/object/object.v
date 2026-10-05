module object

import backend
import image

// The reader for a relocatable object: an ELF64 ET_REL file in, the one unit
// the in-house linker merges out.
//
// `backend/os/elf/object.v` writes this shape, so this file is its inverse, but
// it is not written for that writer alone. A unit is three blobs: the code, the
// read-only data and the writable data. Every allocatable section a file holds
// is copied into the blob its other flags name, in section order and at the
// alignment the section asks for, and where it landed is what a reference to a
// place inside it names. The four names this reader used to look for, `.text`,
// `.rodata`, `.data` and `.bss`, are what an object this compiler writes happens
// to call its sections, and each still lands where it did before.
//
// Every field is bounds-checked before it is used, because a linker input is a
// file this compiler did not write and a malformed one has to be refused rather
// than crash the compiler. What it can carry is the code, the read-only data,
// the writable data with its address-valued slots, and the references between
// them. A construct outside that set is named in an error rather than guessed
// at, because a unit that is wrong is worse than a link that stops.

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

// The section flags. SHF_ALLOC is what makes a section part of the unit;
// SHF_EXECINSTR sends it to the code blob and SHF_WRITE to the writable one, and
// a section with neither goes to the read-only blob. SHF_TLS is refused rather
// than carried, because a thread-local's storage is not a place this unit lays
// out.
const shf_write = u64(0x1)
const shf_alloc = u64(0x2)
const shf_execinstr = u64(0x4)
const shf_tls = u64(0x400)

// The section types this reader carries: a section with bytes in the file, the
// zero-filled storage with none, and a note. A constructor table is a type of
// its own and is refused by name, because running one needs an INIT_ARRAY tag
// this container does not write yet.
const sht_progbits = u32(1)
const sht_symtab = u32(2)
const sht_strtab = u32(3)
const sht_rela = u32(4)
const sht_note = u32(7)
const sht_nobits = u32(8)
const sht_init_array = u32(14)
const sht_fini_array = u32(15)
const sht_preinit_array = u32(16)

// The two special section indexes a symbol can name instead of a section. A
// symbol whose value is a constant, or one whose storage the linker has to
// place, is outside what this reader merges.
const shn_abs = u16(0xfff1)
const shn_common = u16(0xfff2)

// The st_type low nibble and the st_bind high nibble the reader looks at.
const stt_object = u8(1)
const stt_section = u8(3)
const stb_local = u8(0)
const stb_weak = u8(2)

// The relocation kinds this reader accepts, by the psABI numbers an ELF64
// x86-64 object carries. The ones with four-byte pc-relative fields come in two
// spellings: a direct reference to a place, and a reference that reaches an
// object through the global offset table so that a position-independent object
// can name one another object may define. They are machine numbers the psABI
// fixes, so they are written here rather than asked of the target, which
// answers only the code kinds and knows two of these six.
const relocation_absolute = u32(1) // R_X86_64_64
const relocation_pc_relative = u32(2) // R_X86_64_PC32
const relocation_plt = u32(4) // R_X86_64_PLT32
const relocation_got_pc_relative = u32(9) // R_X86_64_GOTPCREL
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
	symtab    int
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
		text:              layout.text
		string_blob:       layout.read_only
		globals_blob:      layout.writable
		globals_alignment: layout.alignment
		labels:            map[string]int{}
		defined:           map[string]bool{}
		globals:           map[string]image.GlobalSlot{}
		internal:          map[string]bool{}
		weak:              map[string]bool{}
		strings:           map[string]int{}
		wide_strings:      map[string]int{}
		doubles:           map[string]int{}
		imports:           []string{}
		object_imports:    map[string]bool{}
		copy_objects:      []string{}
		libraries:         []string{}
		bound:             map[string]image.Definition{}
	}
	read_definitions(bytes, sections, layout, mut program)!
	mut reader := Reader{
		bytes:          bytes
		imports:        []string{}
		object_imports: map[string]bool{}
		seen:           map[string]bool{}
	}
	read_relocations(bytes, sections, layout, mut program, mut reader)!
	program.imports = reader.imports
	program.object_imports = reader.object_imports
	return program
}

// lay_out walks the section header table once and copies every allocatable
// section into the blob its flags name, at the alignment it asks for, recording
// where each landed. The four names an object this compiler writes still land
// first in their blob, so such an object reads as it always did. A TLS section,
// a constructor table, or an allocatable section of a type this reader does not
// carry is refused here, by name and type.
fn lay_out(bytes []u8, sections []Section) !Layout {
	mut blob_of := []Blob{len: sections.len, init: .none}
	mut base_of := []int{len: sections.len, init: 0}
	mut text := []u8{}
	mut read_only := []u8{}
	mut writable := []u8{}
	mut alignment := 8
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
		if (s.flags & shf_tls) != 0 {
			return error('section ${i} (${s.name}) is SHF_TLS, and this reader does not carry thread-local storage')
		}
		if s.kind == sht_init_array || s.kind == sht_fini_array || s.kind == sht_preinit_array {
			return error('section ${i} (${s.name}) is type ${s.kind} (SHT_INIT_ARRAY, SHT_FINI_ARRAY or SHT_PREINIT_ARRAY), and running a constructor needs a constructor table this container does not write')
		}
		if s.kind != sht_progbits && s.kind != sht_nobits && s.kind != sht_note {
			return error('section ${i} (${s.name}) is type ${s.kind}, and this reader carries SHT_PROGBITS (${sht_progbits}), SHT_NOBITS (${sht_nobits}) and SHT_NOTE (${sht_note})')
		}
		blob := classify(s.flags)
		gap := if s.addralign > 1 { s.addralign } else { 1 }
		match blob {
			.code {
				pad(mut text, gap)
				base_of[i] = text.len
				copy_section(mut text, bytes, s)
			}
			.read_only {
				pad(mut read_only, gap)
				base_of[i] = read_only.len
				copy_section(mut read_only, bytes, s)
			}
			.writable {
				pad(mut writable, gap)
				base_of[i] = writable.len
				copy_section(mut writable, bytes, s)
				if gap > alignment {
					alignment = gap
				}
			}
			.none {}
		}
		blob_of[i] = blob
	}
	return Layout{
		blob_of:   blob_of
		base_of:   base_of
		text:      text
		read_only: read_only
		writable:  writable
		alignment: alignment
		symtab:    symtab
	}
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
// its place is named by the section key when a reference reaches it. A section
// symbol and an unnamed symbol are the file's own scaffolding and are skipped.
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
		if sym.shndx == shn_abs || sym.shndx == shn_common || kind == stt_section {
			continue
		}
		if int(sym.shndx) >= layout.blob_of.len {
			continue
		}
		name := symbol_name(bytes, symtab, strtab, i)!
		if name == '' {
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
			.read_only, .none {}
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
// three blobs and reads one reference out of each entry. A reference in the code
// or in read-only data is a four-byte pc-relative field, direct or through the
// global offset table; a reference in writable data is an eight-byte address and
// becomes a data fixup. Anything else is refused with its number. The section
// header table is walked in order, so the imports a file names keep a
// deterministic first-seen order.
fn read_relocations(bytes []u8, sections []Section, layout Layout, mut program image.Program, mut reader Reader) ! {
	for reloca in sections {
		if reloca.kind != sht_rela {
			continue
		}
		if int(reloca.info) >= sections.len {
			continue
		}
		place := relocation_place(layout.blob_of[int(reloca.info)]) or { continue }
		symtab := referenced_symtab(sections, reloca)!
		if symtab.link >= u32(sections.len) {
			return error('the symbol table names section ${symtab.link} as its string table and the file has ${sections.len} sections')
		}
		strtab := section_bytes(bytes, sections[int(symtab.link)])
		base := layout.base_of[int(reloca.info)]
		count := reloca.size / elf_relocation_size
		for entry in 0 .. count {
			at := reloca.offset + entry * elf_relocation_size
			r_offset := read_u64(bytes, at)!
			r_info := read_u64(bytes, at + 8)!
			r_addend := i64(read_u64(bytes, at + 16)!)
			kind := u32(r_info & 0xffffffff)
			sym_index := int(r_info >> 32)
			sym := parse_symbol(bytes, symtab, sym_index)!
			if place == .data {
				if kind != relocation_absolute {
					return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${relocation_absolute} (R_X86_64_64) in the writable data')
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
			} else {
				reference := reference_kind(kind) or {
					return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${relocation_pc_relative} (R_X86_64_PC32), ${relocation_plt} (R_X86_64_PLT32), ${relocation_got_pc_relative} (R_X86_64_GOTPCREL), ${relocation_got_pc_relative_x} (R_X86_64_GOTPCRELX) and ${relocation_rex_got_pc_relative_x} (R_X86_64_REX_GOTPCRELX) in the code and read-only data')
				}
				resolution := reader.resolve(symtab, strtab, sym_index, sym, layout)!
				program.relocations << image.Relocation{
					offset: base + int(r_offset)
					place:  place
					kind:   reference
					name:   resolution.name
					addend: int(r_addend) + resolution.offset
				}
			}
		}
	}
}

// relocation_place is which of a unit's three blobs a section's field lies in,
// as the image names it, or none when the section is not part of the unit.
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
	return none
}

// reference_kind is how a four-byte pc-relative reference reaches what it names:
// the name itself for a direct reference, or the global offset table's slot for
// it for the three GOTPCREL spellings. None means a kind this reader does not
// carry.
fn reference_kind(kind u32) ?image.RelocationKind {
	if kind == relocation_pc_relative || kind == relocation_plt {
		return .direct
	}
	if kind == relocation_got_pc_relative || kind == relocation_got_pc_relative_x
		|| kind == relocation_rex_got_pc_relative_x {
		return .got
	}
	return none
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
// its value; a named symbol defined in the code or writable blob keeps its
// name, because it is a label or a global slot the link already holds. An
// undefined symbol is an import, and its type says whether the link is looking
// for a function or an object.
fn (mut r Reader) resolve(symtab Section, strtab []u8, index int, sym Symbol, layout Layout) !Resolution {
	kind := sym.info & 0xf
	if sym.shndx == shn_abs {
		return error('the relocation names symbol ${index}, which is SHN_ABS and lives at no offset in any section')
	}
	if sym.shndx == shn_common {
		return error('the relocation names symbol ${index}, which is SHN_COMMON and this reader does not lay out common storage')
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
	if sym.shndx == 0 {
		if name == '' {
			return error('the relocation names undefined symbol ${index}, which has no name')
		}
		if kind == stt_object {
			r.object_imports[name] = true
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
	size := field_int(read_u64(bytes, base + 32)!, 'the size of section ${index}', bytes.len)!
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
