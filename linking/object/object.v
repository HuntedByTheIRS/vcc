module object

import backend
import image

// The reader for a relocatable object: an ELF64 ET_REL file in, the one unit
// the in-house linker merges out.
//
// `backend/os/elf/object.v` writes this shape, so this file is its inverse: it
// walks the same section order, reads the same symbol table layout, and turns
// each relocation back into the reference the writer left for the link. Every
// field is bounds-checked before it is used, because a linker input is a file
// this compiler did not write and a malformed one has to be refused rather than
// crash the compiler.
//
// What it can carry is what the writer can put in an object: the code, the
// read-only data, the writable data with its address-valued slots, and the
// references between them. A construct outside that set is named in an error
// rather than guessed at, because a unit that is wrong is worse than a link
// that stops.

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

const sht_symtab = u32(2)
const sht_strtab = u32(3)
const sht_rela = u32(4)
const sht_nobits = u32(8)

// The two special section indexes a symbol can name instead of a section. A
// symbol whose value is a constant, or one whose storage the linker has to
// place, is outside what this reader merges.
const shn_abs = u16(0xfff1)
const shn_common = u16(0xfff2)

// The st_type low nibble and the st_bind high nibble the reader looks at.
const stt_object = u8(1)
const stt_func = u8(2)
const stt_section = u8(3)
const stb_local = u8(0)
const stb_weak = u8(2)

// relocation_absolute is R_X86_64_64: the eight bytes hold the symbol's value
// plus the addend, which is the one relocation kind a top-level pointer
// initializer needs. It is a machine number the psABI fixes, so it is written
// here rather than asked of the target, which answers only the code kinds.
const relocation_absolute = u32(1)

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

// Indices is where each section this reader cares about landed, or minus one
// when the file has none. `.bss` has no bytes in the file, but a symbol can be
// defined there and its storage is the zeroes the reader appends after `.data`.
struct Indices {
mut:
	text   int = -1
	rodata int = -1
	data   int = -1
	bss    int = -1
	symtab int = -1
}

// Reader carries the parsed file and the imports seen so far, so that resolving
// a relocation can add to the import list without a second walk.
struct Reader {
	bytes    []u8
	sections []Section
	indices  Indices
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
	indices := locate(sections)
	// The code, the read-only data and the writable data are each one section
	// copied out of the file. `.bss` has no bytes: its storage is the zeroes
	// appended after `.data`, which is what the writer's single `.data` section
	// already looks like.
	mut text := []u8{}
	if indices.text >= 0 {
		text = section_bytes(bytes, sections[indices.text]).clone()
	}
	mut string_blob := []u8{}
	if indices.rodata >= 0 {
		string_blob = section_bytes(bytes, sections[indices.rodata]).clone()
	}
	mut data_blob := []u8{}
	if indices.data >= 0 {
		data_blob = section_bytes(bytes, sections[indices.data]).clone()
	}
	data_end := align_up(data_blob.len, 8)
	bss_size := if indices.bss >= 0 { sections[indices.bss].size } else { 0 }
	mut globals_blob := data_blob.clone()
	if bss_size > 0 {
		for globals_blob.len < data_end {
			globals_blob << u8(0)
		}
		for _ in 0 .. bss_size {
			globals_blob << u8(0)
		}
	}
	mut globals_alignment := 8
	if indices.data >= 0 && sections[indices.data].addralign > globals_alignment {
		globals_alignment = sections[indices.data].addralign
	}
	if indices.bss >= 0 && sections[indices.bss].addralign > globals_alignment {
		globals_alignment = sections[indices.bss].addralign
	}
	mut program := image.Program{
		text:              text
		string_blob:       string_blob
		globals_blob:      globals_blob
		globals_alignment: globals_alignment
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
	read_definitions(bytes, sections, indices, data_end, mut program)!
	mut reader := Reader{
		bytes:          bytes
		sections:       sections
		indices:        indices
		imports:        []string{}
		object_imports: map[string]bool{}
		seen:           map[string]bool{}
	}
	read_relocations(bytes, sections, indices, target, mut program, mut reader)!
	program.imports = reader.imports
	program.object_imports = reader.object_imports
	return program
}

// read_definitions walks the symbol table and records what this object defines:
// a function whose section is `.text` becomes a label, an object whose section
// is `.data` or `.bss` becomes a global slot, and either one carries its
// linkage and its weak binding with it. A section symbol and an unnamed symbol
// are the file's own scaffolding and are skipped.
fn read_definitions(bytes []u8, sections []Section, indices Indices, data_end int, mut program image.Program) ! {
	if indices.symtab < 0 {
		return
	}
	symtab := sections[indices.symtab]
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
		name := symbol_name(bytes, symtab, strtab, i)!
		if name == '' {
			continue
		}
		if indices.text >= 0 && sym.shndx == u16(indices.text) && kind == stt_func {
			program.labels[name] = int(sym.value)
			program.defined[name] = true
			record_linkage(mut program, name, bind)
		} else if (indices.data >= 0 && sym.shndx == u16(indices.data))
			|| (indices.bss >= 0 && sym.shndx == u16(indices.bss)) {
			base := if indices.bss >= 0 && sym.shndx == u16(indices.bss) { data_end } else { 0 }
			width := if sym.size > 0 { int(sym.size) } else { 8 }
			program.globals[name] = image.GlobalSlot{
				offset: int(sym.value) + base
				width:  width
			}
			record_linkage(mut program, name, bind)
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

// read_relocations walks every SHT_RELA section whose target is `.text` or
// `.data` and reads one reference out of each entry. The code references are
// read first, then the writable data's, so the imports they name keep a
// deterministic first-seen order.
fn read_relocations(bytes []u8, sections []Section, indices Indices, target backend.Target, mut program image.Program, mut reader Reader) ! {
	for code in [true, false] {
		for reloca in sections {
			if reloca.kind != sht_rela {
				continue
			}
			is_text := code && indices.text >= 0 && reloca.info == u32(indices.text)
			is_data := !code && indices.data >= 0 && reloca.info == u32(indices.data)
			if !is_text && !is_data {
				continue
			}
			symtab := referenced_symtab(sections, reloca)!
			if symtab.link >= u32(sections.len) {
				return error('the symbol table names section ${symtab.link} as its string table and the file has ${sections.len} sections')
			}
			strtab := section_bytes(bytes, sections[int(symtab.link)])
			count := reloca.size / elf_relocation_size
			for entry in 0 .. count {
				at := reloca.offset + entry * elf_relocation_size
				r_offset := read_u64(bytes, at)!
				r_info := read_u64(bytes, at + 8)!
				r_addend := i64(read_u64(bytes, at + 16)!)
				kind := u32(r_info & 0xffffffff)
				sym_index := int(r_info >> 32)
				sym := parse_symbol(bytes, symtab, sym_index)!
				if is_text {
					if kind != target.call_relocation() && kind != target.address_relocation() {
						return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${target.call_relocation()} (call) and ${target.address_relocation()} (address) in the code')
					}
					name := reader.resolve(symtab, strtab, sym_index, sym)!
					program.relocations << image.Relocation{
						offset: int(r_offset)
						name:   name
						addend: int(r_addend)
					}
				} else {
					if kind != relocation_absolute {
						return error('unknown relocation type ${kind} at offset ${r_offset}: this reader accepts ${relocation_absolute} (R_X86_64_64) in the writable data')
					}
					name := reader.resolve(symtab, strtab, sym_index, sym)!
					fixup_kind := if (sym.info & 0xf) == stt_section {
						image.FixupKind.section_address
					} else {
						image.FixupKind.import_address
					}
					program.data_fixups << image.DataFixup{
						offset: int(r_offset)
						kind:   fixup_kind
						name:   name
						addend: int(r_addend)
					}
				}
			}
		}
	}
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

// resolve is the name a relocation is written under. A section symbol becomes
// the key of the section it names, so a string or a place in the data is a
// reference to `.rodata` or `.data` rather than to a symbol. A named symbol
// keeps its name. An undefined one is an import, and its type says whether the
// link is looking for a function or an object.
fn (mut r Reader) resolve(symtab Section, strtab []u8, index int, sym Symbol) !string {
	kind := sym.info & 0xf
	if sym.shndx == shn_abs {
		return error('the relocation names symbol ${index}, which is SHN_ABS and lives at no offset in any section')
	}
	if sym.shndx == shn_common {
		return error('the relocation names symbol ${index}, which is SHN_COMMON and this reader does not lay out common storage')
	}
	if kind == stt_section {
		key := section_key_of(sym.shndx, r.indices) or {
			return error('the relocation names section symbol ${index} of section ${sym.shndx}, and this reader knows .text, .rodata and .data')
		}
		return key
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
		return name
	}
	_ := section_key_of(sym.shndx, r.indices) or {
		return error('the relocation names symbol ${index} (${name}) defined in section ${sym.shndx}, which this reader does not handle')
	}
	if name == '' {
		return error('the relocation names defined symbol ${index} in section ${sym.shndx}, which has no name')
	}
	return name
}

// section_key_of is the image's name for one of a unit's own sections, or none
// when the section is one this reader does not carry. `.bss` answers `.data`
// because the reader merges the two: the empty storage becomes the zeroes
// appended after the writable data.
fn section_key_of(shndx u16, indices Indices) ?string {
	if indices.text >= 0 && shndx == u16(indices.text) {
		return image.section_key_text
	}
	if indices.rodata >= 0 && shndx == u16(indices.rodata) {
		return image.section_key_rodata
	}
	if indices.data >= 0 && shndx == u16(indices.data) {
		return image.section_key_data
	}
	if indices.bss >= 0 && shndx == u16(indices.bss) {
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

// locate is where each section this reader cares about landed. The first
// section of a name wins, so a file with two `.text` sections keeps the one a
// linker would read first.
fn locate(sections []Section) Indices {
	mut indices := Indices{}
	for i, s in sections {
		match s.name {
			'.text' {
				if indices.text < 0 {
					indices.text = i
				}
			}
			'.rodata' {
				if indices.rodata < 0 {
					indices.rodata = i
				}
			}
			'.data' {
				if indices.data < 0 {
					indices.data = i
				}
			}
			'.bss' {
				if indices.bss < 0 {
					indices.bss = i
				}
			}
			else {
				if s.kind == sht_symtab && indices.symtab < 0 {
					indices.symtab = i
				}
			}
		}
	}
	return indices
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

// align_up rounds a size up to the next multiple of the alignment.
fn align_up(value int, to int) int {
	return (value + to - 1) / to * to
}
