module linux

import os

// What a `-l` argument comes to: the file behind a library name, and the name
// the image has to carry for it.
//
// A program that runs against a shared library does not name the file it was
// linked against. The image carries the SONAME, the one string the library
// holds inside itself and the loader searches its directories for, so `-lm` on
// a command line is `libm.so.6` in the image. Something has to get from one to
// the other, which is this file: find the file the way a linker does, then read
// the name out of it instead of guessing from the flag.
//
// The search has three steps rather than one, and the reason is what the
// machine actually holds. Measured on glibc 2.44: `/usr/lib/libm.so` is not a
// library but a four-line GNU ld script naming `/usr/lib/libm.so.6`, and there
// is no `/usr/lib/libdl.so` at all, only `libdl.so.2` and an empty `libdl.a`.
// A search that stopped at `libNAME.so` would find nothing for `-ldl`, and a
// reader that took that file for an object would read a text file as one.

// The bytes this file reads out of an ELF64 header and the records below it.
// They are written here rather than taken from `backend/os/elf/elf.v` because
// the two jobs are opposite ones: that module writes one container of a fixed
// shape, this one reads files other tools produced. The class and data bytes
// were the one exception and were shared, on the argument that they mean the
// same thing on both sides, which they do. They stopped being shared when this
// file moved under `backend/os/`: the container module asks the target for its
// machine facts, the target reaches this module, and taking a number from the
// container would have closed a loop between the two.
const elf64_class = 2
const elf64_data_little_endian = 1
const elf64_header_size = 64
const elf64_phoff_at = 32
const elf64_phentsize_at = 54
const elf64_phnum_at = 56
const elf64_ph_size = 56
const elf64_ph_offset_at = 8
const elf64_ph_vaddr_at = 16
const elf64_ph_filesz_at = 32
const elf64_dynamic_size = 16
const program_header_load = u32(1)
const program_header_dynamic = u32(2)
const dynamic_soname = u64(14)
const dynamic_strtab = u64(5)
// The rest of the walk to a library's own symbols: the tags that name the
// symbol table, the hash the loader and this reader count it through, and the
// size of one symbol record. A reader that answers whether a library defines a
// name needs these where the SONAME reader above needed only the string table.
const dynamic_hash = u64(4)
const dynamic_symtab = u64(6)
const dynamic_syment = u64(11)
const dynamic_gnu_hash = u64(0x6ffffef5)
const elf_symbol_size = 24
const symbol_section_undefined = u16(0)

// Segment is one loadable program header of a library, in the terms the string
// table's address is turned into a file offset with: a virtual address is what
// the dynamic table stores, and a file offset is what reading needs.
struct LibrarySegment {
	offset u64
	vaddr  u64
	size   u64
}

// Library is what a -l name comes to: the file the search found and the name the
// image carries for it. The two are not the same string, which is the reason
// both are kept: `-lm` is `/usr/lib/libm.so` on this machine and `libm.so.6` in
// the image, and a caller that has to read the library needs the file.
//
// An archive is the third shape the search answers with. It has no SONAME for
// the image to carry, so `soname` holds its own file name, and `archive` says
// the file is an ar container a link reads members out of rather than a library
// the loader maps.
pub struct Library {
pub:
	path    string
	soname  string
	archive bool // the file is an ar archive, so the link reads its members
}

// resolve_libraries turns the `-l` names the command line gave into the names
// the image carries, in the order they were written and without repeating one.
// An archive is left out: a static archive is not a file the loader maps, so
// naming it would put a DT_NEEDED entry in the image for a file the loader
// cannot open. archive_libraries is where those names go instead.
pub fn resolve_libraries(names []string, dirs []string) ![]string {
	mut out := []string{}
	for library in resolve_library_files(names, dirs)! {
		if library.archive {
			continue
		}
		if library.soname !in out {
			out << library.soname
		}
	}
	return out
}

// archive_libraries is the `-l` names that resolved to a static archive: the
// files a link reads members from and pulls the ones that answer the names the
// link still needs. The names come back in the order they were given, a path is
// not repeated, and a name that resolves to nothing is the same error the
// search answers elsewhere.
pub fn archive_libraries(names []string, dirs []string) ![]Library {
	mut out := []Library{}
	for given in names {
		library := resolve_library(given, dirs)!
		if !library.archive {
			continue
		}
		mut seen := false
		for existing in out {
			if existing.path == library.path {
				seen = true
				break
			}
		}
		if !seen {
			out << library
		}
	}
	return out
}

// resolve_library_files is the same search with the files kept. A caller that
// only needs the name the image carries asks resolve_libraries; one that has to
// read the library asks this, and the two answer the same libraries in the same
// order.
pub fn resolve_library_files(names []string, dirs []string) ![]Library {
	mut out := []Library{}
	for given in names {
		library := resolve_library(given, dirs)!
		mut seen := false
		for existing in out {
			if existing.soname == library.soname {
				seen = true
				break
			}
		}
		if !seen {
			out << library
		}
	}
	return out
}

// search_dirs is where a library name is looked for: the -L directories in the
// order they were given, then the system's own.
pub fn search_dirs(given []string, system []string) []string {
	mut out := []string{}
	out << given
	out << system
	return out
}

// resolve_library finds the file one `-l` name stands for and the name it should
// be recorded under.
//
// The parameter is `given` rather than `name` because this module declares a
// const `name` for the system it describes, and V will not let a function in the
// module have a local of the same name. The name a caller passed is the one the
// flag wrote; the name that comes back is the library's own.
pub fn resolve_library(given string, dirs []string) !Library {
	if given == '' {
		return error('-l with no library name')
	}
	// `-l:libfoo.so.1` names the file itself, which is how a link asks for one
	// version of a library without the unversioned name to reach it by.
	if given.starts_with(':') {
		wanted := given[1..]
		path := find_file(wanted, dirs) or {
			return error('cannot find ${wanted}: searched ${describe_dirs(dirs)}')
		}
		if path.ends_with('.a') {
			return archive_library(path)
		}
		return Library{
			path:   path
			soname: library_name_of(path)!
		}
	}
	path := find_library(given, dirs) or {
		return error('cannot find -l${given}: searched ${describe_dirs(dirs)}')
	}
	if path.ends_with('.a') {
		return archive_library(path)
	}
	return Library{
		path:   path
		soname: library_name_of(path)!
	}
}

// archive_library is the Library a static archive comes to. The name is the
// file's own, because an archive carries no SONAME and the image asks the loader
// for nothing; `archive` says the file is read as members rather than as an
// object. library_name_of is not called, because it reads an ELF object and
// cannot read an ar container.
fn archive_library(path string) Library {
	return Library{
		path:    path
		soname:  os.base(path)
		archive: true
	}
}

fn describe_dirs(dirs []string) string {
	if dirs.len == 0 {
		return 'no directories'
	}
	return dirs.join(', ')
}

// find_library looks for `lib<name>.so`, then for a versioned `lib<name>.so.N`
// when there is no unversioned name, then for the archive `lib<name>.a`. The
// middle step is the one a plain linker does not take, and it is here because
// the C library on this machine ships libraries that have no unversioned name:
// `-ldl` and `-lpthread` are written on V's own command line and a compiler
// that refused them could not build its host.
fn find_library(given string, dirs []string) ?string {
	stem := 'lib${given}.so'
	if path := find_file(stem, dirs) {
		return path
	}
	mut versioned := []string{}
	for dir in dirs {
		for entry in os.ls(dir) or { []string{} } {
			if !entry.starts_with('${stem}.') {
				continue
			}
			path := os.join_path(dir, entry)
			if os.is_file(path) {
				versioned << path
			}
		}
	}
	if versioned.len > 0 {
		versioned.sort_with_compare(newest_first)
		return versioned[0]
	}
	return find_file('lib${given}.a', dirs)
}

// find_file looks for one file name in the search directories, in order. It is
// the walk a -l name and a `-l:file` both go through, and it is published because
// a query flag asks the same question of one name: `-print-file-name=` answers
// with the file this returns, so the flag and the linker cannot disagree about
// which file a name is.
pub fn find_file(given string, dirs []string) ?string {
	for dir in dirs {
		path := os.join_path(dir, given)
		if os.is_file(path) {
			return path
		}
	}
	return none
}

// newest_first orders two library file names from the same directory by the
// version they carry, so `libm.so.10` is preferred to `libm.so.9` where
// comparing the text would put them the other way round.
fn newest_first(a &string, b &string) int {
	left := version_numbers(os.base(*a))
	right := version_numbers(os.base(*b))
	for i in 0 .. larger(left.len, right.len) {
		x := if i < left.len { left[i] } else { 0 }
		y := if i < right.len { right[i] } else { 0 }
		if x != y {
			return if x > y { -1 } else { 1 }
		}
	}
	return 0
}

// version_numbers reads the parts after the `.so.` in a library's file name.
fn version_numbers(file string) []int {
	dot := file.index('.so.') or { return []int{} }
	mut numbers := []int{}
	for part in file[dot + 4..].split('.') {
		mut value := 0
		mut digits := 0
		for ch in part {
			if ch < `0` || ch > `9` {
				break
			}
			value = value * 10 + int(ch - `0`)
			digits++
		}
		if digits == 0 {
			break
		}
		numbers << value
	}
	return numbers
}

fn larger(a int, b int) int {
	return if a > b { a } else { b }
}

// library_name_of is the name a library file stands for: its SONAME when it
// carries one, and its own file name when it does not.
fn library_name_of(path string) !string {
	text := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	bytes := text.bytes()
	if is_elf(bytes) {
		soname := soname_in(bytes)
		// An object that carries no SONAME is recorded under its own file
		// name, which is what a link does with one.
		return if soname == '' { os.base(path) } else { soname }
	}
	if bytes.len > 7 && bytes[0] == `!` && bytes[1] == `<` {
		return error('${path} is an archive: this linker reads an archive named as an input file, and a -l name resolves to a library the image asks the loader for')
	}
	return script_library_name(text, path)
}

fn is_elf(bytes []u8) bool {
	if bytes.len < 8 {
		return false
	}
	return bytes[0] == 0x7f && bytes[1] == `E` && bytes[2] == `L` && bytes[3] == `F`
}

// soname_in reads the SONAME out of an ELF64 object, and answers an empty string
// for one that has none. The name is found through the dynamic segment and not
// through a section header table, because a linked object is allowed to have
// none: the loader reads the program headers, and so does this.
fn soname_in(bytes []u8) string {
	if bytes.len < elf64_header_size {
		return ''
	}
	if bytes[4] != elf64_class || bytes[5] != elf64_data_little_endian {
		return ''
	}
	phoff := int(read_u64(bytes, elf64_phoff_at))
	entry_size := int(read_u16(bytes, elf64_phentsize_at))
	count := int(read_u16(bytes, elf64_phnum_at))
	mut dynamic_offset := u64(0)
	mut found_dynamic := false
	mut loaded := []LibrarySegment{}
	for i in 0 .. count {
		at := phoff + i * entry_size
		if at + elf64_ph_size > bytes.len {
			return ''
		}
		kind := read_u32(bytes, at)
		if kind == program_header_dynamic {
			dynamic_offset = read_u64(bytes, at + elf64_ph_offset_at)
			found_dynamic = true
		}
		if kind == program_header_load {
			loaded << LibrarySegment{
				offset: read_u64(bytes, at + elf64_ph_offset_at)
				vaddr:  read_u64(bytes, at + elf64_ph_vaddr_at)
				size:   read_u64(bytes, at + elf64_ph_filesz_at)
			}
		}
	}
	if !found_dynamic {
		return ''
	}
	mut strtab := u64(0)
	mut soname_at := u64(0)
	mut at := int(dynamic_offset)
	for at + elf64_dynamic_size <= bytes.len {
		tag := read_u64(bytes, at)
		value := read_u64(bytes, at + 8)
		if tag == 0 {
			break
		}
		if tag == dynamic_strtab {
			strtab = value
		}
		if tag == dynamic_soname {
			soname_at = value
		}
		at += elf64_dynamic_size
	}
	if strtab == 0 || soname_at == 0 {
		return ''
	}
	// The string table is named by an address, and reading needs an offset into
	// the file: the loadable segment the address falls in is what connects the
	// two, which is the one piece of arithmetic that makes this a reader rather
	// than a parser.
	start := file_offset(loaded, strtab + soname_at) or { return '' }
	return read_c_string(bytes, start)
}

// file_offset turns an address a dynamic table holds into an offset in the file
// the table was read from. The loadable segment the address falls in is what
// connects the two, and both readers here need it: the SONAME is an address in
// the string table and the symbols are named out of the same table.
fn file_offset(loaded []LibrarySegment, address u64) ?int {
	for segment in loaded {
		if address < segment.vaddr || address >= segment.vaddr + segment.size {
			continue
		}
		return int(segment.offset + (address - segment.vaddr))
	}
	return none
}

// ScriptTarget is the file a GNU ld script names: the word as the script wrote
// it, and the path it resolves to beside the script. Both are kept, because a
// reader that cannot open the file has to say which word named it.
struct ScriptTarget {
	word string
	path string
}

// script_target reads the first file a GNU ld script names. `libm.so` on this
// machine is a script that reads:
//
//	/* GNU ld script
//	OUTPUT_FORMAT(elf64-x86-64)
//	GROUP ( /usr/lib/libm.so.6  AS_NEEDED ( /usr/lib/libmvec.so.1 ) ) */
//
// The first word inside the group is the library the script stands for. A
// script names its library either absolutely or as a file beside itself; both
// are paths a directory of the script resolves.
fn script_target(text string, path string) ?ScriptTarget {
	for marker in ['GROUP', 'INPUT'] {
		open := text.index('${marker} (') or { continue }
		if open < 0 {
			continue
		}
		rest := text[open + marker.len + 2..]
		// The whitespace inside the parentheses is the script author's, so the
		// word starts after it: `GROUP ( /usr/lib/libm.so.6` has one space to
		// skip before the first character that is part of a name.
		mut at := 0
		for at < rest.len && is_script_space(rest[at]) {
			at++
		}
		mut word := ''
		for at < rest.len && !is_script_space(rest[at]) && rest[at] != `)` {
			word += rest[at].ascii_str()
			at++
		}
		if word == '' {
			continue
		}
		target := if word.starts_with('/') {
			word
		} else {
			os.join_path(os.dir(path), word)
		}
		return ScriptTarget{
			word: word
			path: target
		}
	}
	return none
}

// script_library_name reads the library out of a GNU ld script: the first file
// the script names, read the way any other library's name is.
fn script_library_name(text string, path string) !string {
	target := script_target(text, path) or {
		return error('${path} is neither an object file nor a library script this compiler reads')
	}
	if !os.is_file(target.path) {
		return error('${path} names ${target.word}, which is not a file')
	}
	bytes := os.read_file(target.path) or {
		return error('cannot read ${target.path}: ${err.msg()}')
	}
	if !is_elf(bytes.bytes()) {
		return error('${path} names ${target.word}, which is not an object file')
	}
	soname := soname_in(bytes.bytes())
	if soname != '' {
		return soname
	}
	return os.base(target.path)
}

// LibrarySymbols is one shared library's dynamic symbol table, opened for the
// question the caller has: whether the library defines a name. The bytes are
// held because naming a symbol means reading it out of the string table, and the
// offsets are where that table and the symbols begin.
//
// The hash fields are the GNU hash, when the library carries one, which glibc
// does. They are what turns "does this library define that name" into a hash
// probe rather than a walk of every symbol it holds: a program imports a handful
// of names and the library defines thousands, so the walk would cost one full
// scan per import. `hashed` is false for a library with no GNU hash, and the
// walk is used then.
struct LibrarySymbols {
	bytes  []u8
	str_at int
	sym_at int
	count  int
	stride int
	hashed bool
	// bloom_at is where the bloom filter's words begin, bloom_size how many
	// there are, and bloom_shift the shift the filter mixes the hash with.
	bloom_at    int
	bloom_size  int
	bloom_shift u32
	// buckets_at is where the buckets begin and nbuckets how many; chain_at is
	// where the chains begin and symoffset the first symbol a chain names.
	buckets_at int
	nbuckets   int
	chain_at   int
	symoffset  int
}

// open_library_symbols reads a library far enough to answer symbol questions:
// the program headers, the dynamic table, and the hash the symbol count comes
// from. It answers none for a file that is not an object this reader can read.
fn open_library_symbols(path string) ?LibrarySymbols {
	// The file is read once and a GNU ld script is followed from the same
	// bytes, so a `-lm` costs one read of the script and one of the library
	// rather than two of each.
	mut bytes := os.read_bytes(path) or { return none }
	if !is_elf(bytes) {
		target := script_target(bytes.bytestr(), path) or { return none }
		if !os.is_file(target.path) {
			return none
		}
		bytes = os.read_bytes(target.path) or { return none }
		if !is_elf(bytes) {
			return none
		}
	}
	if bytes.len < elf64_header_size {
		return none
	}
	if bytes[4] != elf64_class || bytes[5] != elf64_data_little_endian {
		return none
	}
	phoff := int(read_u64(bytes, elf64_phoff_at))
	entry_size := int(read_u16(bytes, elf64_phentsize_at))
	count := int(read_u16(bytes, elf64_phnum_at))
	mut dynamic_offset := u64(0)
	mut found_dynamic := false
	mut loaded := []LibrarySegment{}
	for i in 0 .. count {
		at := phoff + i * entry_size
		if at + elf64_ph_size > bytes.len {
			return none
		}
		kind := read_u32(bytes, at)
		if kind == program_header_dynamic {
			dynamic_offset = read_u64(bytes, at + elf64_ph_offset_at)
			found_dynamic = true
		}
		if kind == program_header_load {
			loaded << LibrarySegment{
				offset: read_u64(bytes, at + elf64_ph_offset_at)
				vaddr:  read_u64(bytes, at + elf64_ph_vaddr_at)
				size:   read_u64(bytes, at + elf64_ph_filesz_at)
			}
		}
	}
	if !found_dynamic {
		return none
	}
	mut strtab := u64(0)
	mut symtab := u64(0)
	mut hash := u64(0)
	mut gnu_hash := u64(0)
	mut syment := u64(elf_symbol_size)
	mut at := int(dynamic_offset)
	for at + elf64_dynamic_size <= bytes.len {
		tag := read_u64(bytes, at)
		value := read_u64(bytes, at + 8)
		if tag == 0 {
			break
		}
		if tag == dynamic_strtab {
			strtab = value
		} else if tag == dynamic_symtab {
			symtab = value
		} else if tag == dynamic_syment {
			syment = value
		} else if tag == dynamic_hash {
			hash = value
		} else if tag == dynamic_gnu_hash {
			gnu_hash = value
		}
		at += elf64_dynamic_size
	}
	if strtab == 0 || symtab == 0 {
		return none
	}
	stride := int(syment)
	// Sixteen bytes is the smallest a symbol record can be; anything narrower
	// means the table this reader reached is not one.
	if stride < 16 {
		return none
	}
	str_at := file_offset(loaded, strtab) or { return none }
	sym_at := file_offset(loaded, symtab) or { return none }
	symbols := symbol_count(bytes, loaded, hash, gnu_hash) or { return none }
	mut hashed := false
	mut bloom_at := 0
	mut bloom_size := 0
	mut bloom_shift := u32(0)
	mut buckets_at := 0
	mut nbuckets := 0
	mut chain_at := 0
	mut symoffset := 0
	if gnu_hash != 0 {
		if base := file_offset(loaded, gnu_hash) {
			if base + 16 <= bytes.len {
				bucket_count := int(read_u32(bytes, base))
				first_symbol := int(read_u32(bytes, base + 4))
				bloom_count := int(read_u32(bytes, base + 8))
				shift := read_u32(bytes, base + 12)
				bloom_first := base + 16
				bucket_first := bloom_first + bloom_count * 8
				chain_first := bucket_first + 4 * bucket_count
				if bucket_count > 0 && bloom_count > 0 && chain_first <= bytes.len {
					hashed = true
					bloom_at = bloom_first
					bloom_size = bloom_count
					bloom_shift = shift
					buckets_at = bucket_first
					nbuckets = bucket_count
					chain_at = chain_first
					symoffset = first_symbol
				}
			}
		}
	}
	return LibrarySymbols{
		bytes:       bytes
		str_at:      str_at
		sym_at:      sym_at
		count:       symbols
		stride:      stride
		hashed:      hashed
		bloom_at:    bloom_at
		bloom_size:  bloom_size
		bloom_shift: bloom_shift
		buckets_at:  buckets_at
		nbuckets:    nbuckets
		chain_at:    chain_at
		symoffset:   symoffset
	}
}

// defines says whether the library names a symbol. The comparison is over the
// bytes of the name rather than a string built from them, because a caller asks
// about a handful of names and building one string per symbol in the library
// would cost far more than the comparisons save. Every defined symbol is kept
// and not only the global ones, because a name the loader can be asked to
// resolve is the question here and leaving one out would refuse an import that
// would have worked.
fn (t LibrarySymbols) defines(given string) bool {
	wanted := given.bytes()
	if t.hashed {
		return t.defines_through_the_hash(wanted)
	}
	return t.defines_by_walking(wanted)
}

// defines_through_the_hash asks the GNU hash the way the loader does: the bloom
// filter first, which answers "no" for most names without touching a bucket, and
// then one bucket and its chain. It is what keeps the question from costing a
// walk of every symbol the library defines for every name the image imports.
fn (t LibrarySymbols) defines_through_the_hash(wanted []u8) bool {
	hash := gnu_hash_of(wanted)
	first_bit := int(hash % u32(64))
	second_bit := int((hash >> t.bloom_shift) % u32(64))
	mask := (u64(1) << first_bit) | (u64(1) << second_bit)
	bloom_word := read_u64(t.bytes, t.bloom_at + 8 * int((hash / u32(64)) % u32(t.bloom_size)))
	if (bloom_word & mask) != mask {
		return false
	}
	bucket := int(read_u32(t.bytes, t.buckets_at + 4 * int(hash % u32(t.nbuckets))))
	if bucket < t.symoffset || bucket >= t.count {
		return false
	}
	mut index := bucket
	for index < t.count {
		word_at := t.chain_at + 4 * (index - t.symoffset)
		if word_at + 4 > t.bytes.len {
			break
		}
		chain_word := read_u32(t.bytes, word_at)
		if (chain_word | 1) == (hash | 1) {
			entry := t.sym_at + index * t.stride
			if entry + t.stride <= t.bytes.len {
				name_at := int(read_u32(t.bytes, entry))
				if name_at != 0 && bytes_are_c_string(t.bytes, t.str_at + name_at, wanted) {
					return true
				}
			}
		}
		if (chain_word & 1) != 0 {
			break
		}
		index++
	}
	return false
}

// defines_by_walking is the walk for a library with no GNU hash, which is an old
// DT_HASH one. It reads every defined symbol and compares its name, so it is the
// slow path; the hash path above exists because this one is what a program that
// imports many names pays for.
fn (t LibrarySymbols) defines_by_walking(wanted []u8) bool {
	for i in 0 .. t.count {
		entry := t.sym_at + i * t.stride
		if entry + t.stride > t.bytes.len {
			break
		}
		name_at := int(read_u32(t.bytes, entry))
		if name_at == 0 {
			continue
		}
		if read_u16(t.bytes, entry + 6) == symbol_section_undefined {
			continue
		}
		if bytes_are_c_string(t.bytes, t.str_at + name_at, wanted) {
			return true
		}
	}
	return false
}

// gnu_hash_of is the hash a GNU hash table is keyed by: the same string hash the
// loader computes, so the bucket and chain this reader reaches are the ones the
// loader would.
fn gnu_hash_of(name []u8) u32 {
	mut hash := u32(5381)
	for ch in name {
		hash = (hash << 5) + hash + u32(ch)
	}
	return hash
}

// names is every symbol the library defines, as a set. It builds one string per
// symbol, so it is for a caller that wants the whole table rather than a few
// names in it.
fn (t LibrarySymbols) names() map[string]bool {
	mut out := map[string]bool{}
	for i in 0 .. t.count {
		entry := t.sym_at + i * t.stride
		if entry + t.stride > t.bytes.len {
			break
		}
		name_at := int(read_u32(t.bytes, entry))
		if name_at == 0 {
			continue
		}
		if read_u16(t.bytes, entry + 6) == symbol_section_undefined {
			continue
		}
		out[read_c_string(t.bytes, t.str_at + name_at)] = true
	}
	return out
}

// library_symbols answers the names a shared library defines, so a caller can
// inspect the whole table. A path that is not a library this reader can read
// answers none rather than an error: a -l name with no file behind it is already
// reported by the search, and the caller decides what an unreadable library
// means.
pub fn library_symbols(path string) ?map[string]bool {
	table := open_library_symbols(path) or { return none }
	return table.names()
}

// unresolved_imports answers which of an image's imports no library it names
// provides. The C library is always one of them, because every image this system
// writes runs against it whether or not a flag named it; the rest are the -l
// names on the command line.
//
// An import none of those libraries defines is what a link refuses as an
// undefined reference, and it is the shape this compiler used to leave in an
// image: the compile succeeded, and the program died at load with a symbol
// lookup error naming nothing the compiler had said. A library the reader cannot
// read contributes nothing, and when the C library itself cannot be read the
// check is not made at all, because the loader reads the same file and a compile
// refused over this reader's failure would be a worse answer than the loader's.
pub fn unresolved_imports(imports []string, names []string, dirs []string) []string {
	if imports.len == 0 {
		return []string{}
	}
	base := find_file(base_library, dirs) or { return []string{} }
	mut tables := []LibrarySymbols{}
	if table := open_library_symbols(base) {
		tables << table
	} else {
		return []string{}
	}
	for library in resolve_library_files(names, dirs) or { []Library{} } {
		if table := open_library_symbols(library.path) {
			tables << table
		}
	}
	mut out := []string{}
	for given in imports {
		mut found := false
		for table in tables {
			if table.defines(given) {
				found = true
				break
			}
		}
		if !found {
			out << given
		}
	}
	return out
}

// bytes_are_c_string says whether the bytes at an offset are the given name
// followed by the terminator a name in a string table ends with. Comparing the
// bytes in place is what keeps the symbol question from building a string for
// every symbol in the library.
fn bytes_are_c_string(bytes []u8, at int, wanted []u8) bool {
	if at < 0 {
		return false
	}
	for i, ch in wanted {
		index := at + i
		if index >= bytes.len || bytes[index] != ch {
			return false
		}
	}
	end := at + wanted.len
	return end < bytes.len && bytes[end] == 0
}

// symbol_count is how many entries a library's dynamic symbol table holds. The
// count is not stored beside the table: it is derived from the hash the loader
// walks, and glibc 2.44's `libc.so.6` carries a GNU hash and no DT_HASH, so the
// GNU hash is the one that has to be read here. Its buckets hold the highest
// symbol index of each chain, and a chain ends at the first word whose low bit
// is set, so the last index plus one is the count.
fn symbol_count(bytes []u8, loaded []LibrarySegment, hash u64, gnu_hash u64) ?int {
	if gnu_hash != 0 {
		base := file_offset(loaded, gnu_hash) or { return none }
		if base + 16 > bytes.len {
			return none
		}
		nbuckets := int(read_u32(bytes, base))
		symoffset := int(read_u32(bytes, base + 4))
		bloom_size := int(read_u32(bytes, base + 8))
		// A bloom word is the machine's word, eight bytes on this target.
		buckets_at := base + 16 + bloom_size * 8
		if buckets_at + 4 * nbuckets > bytes.len {
			return none
		}
		mut last := 0
		for i in 0 .. nbuckets {
			bucket := int(read_u32(bytes, buckets_at + 4 * i))
			if bucket > last {
				last = bucket
			}
		}
		if last == 0 {
			return symoffset
		}
		chain_at := buckets_at + 4 * nbuckets
		mut index := last
		for {
			word_at := chain_at + 4 * (index - symoffset)
			if word_at + 4 > bytes.len {
				return none
			}
			if read_u32(bytes, word_at) & 1 != 0 {
				break
			}
			index++
		}
		return index + 1
	}
	if hash != 0 {
		base := file_offset(loaded, hash) or { return none }
		if base + 8 > bytes.len {
			return none
		}
		// The second word of a DT_HASH table is the chain count, which is the
		// symbol count.
		return int(read_u32(bytes, base + 4))
	}
	return none
}

// is_script_space says whether a byte separates two words of a linker script.
fn is_script_space(ch u8) bool {
	return ch == ` ` || ch == `	` || ch == `\n` || ch == `\r`
}

fn read_u16(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn read_u32(bytes []u8, at int) u32 {
	mut value := u32(0)
	for i in 0 .. 4 {
		value |= u32(bytes[at + i]) << (8 * i)
	}
	return value
}

fn read_u64(bytes []u8, at int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 {
		value |= u64(bytes[at + i]) << (8 * i)
	}
	return value
}

fn read_c_string(bytes []u8, at int) string {
	if at < 0 || at >= bytes.len {
		return ''
	}
	mut out := []u8{}
	mut i := at
	for i < bytes.len && bytes[i] != 0 {
		out << bytes[i]
		i++
	}
	return out.bytestr()
}
