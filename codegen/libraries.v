module codegen

import backend.os.elf
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

// The offsets this file reads out of an ELF64 header and the records below it.
// They are written here rather than taken from `backend/os/elf/elf.v` because
// the two jobs are opposite ones: that module writes one container of a fixed
// shape, this one reads files other tools produced. The class byte and the data
// byte are the one exception, and they are shared: they mean the same thing on
// both sides.
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

// Segment is one loadable program header of a library, in the terms the string
// table's address is turned into a file offset with: a virtual address is what
// the dynamic table stores, and a file offset is what reading needs.
struct LibrarySegment {
	offset u64
	vaddr  u64
	size   u64
}

// resolve_libraries turns the `-l` names the command line gave into the names
// the image carries, in the order they were written and without repeating one.
pub fn resolve_libraries(names []string, dirs []string) ![]string {
	mut out := []string{}
	for name in names {
		soname := resolve_library(name, dirs)!
		if soname !in out {
			out << soname
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

// resolve_library finds the file one `-l` name stands for and answers the name
// it should be recorded under.
fn resolve_library(name string, dirs []string) !string {
	if name == '' {
		return error('-l with no library name')
	}
	// `-l:libfoo.so.1` names the file itself, which is how a link asks for one
	// version of a library without the unversioned name to reach it by.
	if name.starts_with(':') {
		wanted := name[1..]
		path := find_file(wanted, dirs) or {
			return error('cannot find ${wanted}: searched ${describe_dirs(dirs)}')
		}
		return library_name_of(path)!
	}
	path := find_library(name, dirs) or {
		return error('cannot find -l${name}: searched ${describe_dirs(dirs)}')
	}
	if path.ends_with('.a') {
		return error('-l${name} is ${path}, an archive, and linking an archive is not implemented yet')
	}
	return library_name_of(path)!
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
fn find_library(name string, dirs []string) ?string {
	stem := 'lib${name}.so'
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
	return find_file('lib${name}.a', dirs)
}

fn find_file(name string, dirs []string) ?string {
	for dir in dirs {
		path := os.join_path(dir, name)
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
		name := soname_in(bytes)
		// An object that carries no SONAME is recorded under its own file
		// name, which is what a link does with one.
		return if name == '' { os.base(path) } else { name }
	}
	if bytes.len > 7 && bytes[0] == `!` && bytes[1] == `<` {
		return error('${path} is an archive, and linking an archive is not implemented yet')
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
	if bytes[4] != elf.elf_class_64 || bytes[5] != elf.elf_data_little_endian {
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
	wanted := strtab + soname_at
	for segment in loaded {
		if wanted < segment.vaddr || wanted >= segment.vaddr + segment.size {
			continue
		}
		start := int(segment.offset + (wanted - segment.vaddr))
		return read_c_string(bytes, start)
	}
	return ''
}

// script_library_name reads the library out of a GNU ld script. `libm.so` on
// this machine is one, and it reads:
//
//	/* GNU ld script
//	OUTPUT_FORMAT(elf64-x86-64)
//	GROUP ( /usr/lib/libm.so.6  AS_NEEDED ( /usr/lib/libmvec.so.1 ) ) */
//
// The first word inside the group is the library the script stands for, so the
// answer is that file's own name read the way any other library's is.
fn script_library_name(text string, path string) !string {
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
		// A script names its library either absolutely or as a file beside
		// itself; both are paths a directory of the script resolves.
		target := if word.starts_with('/') {
			word
		} else {
			os.join_path(os.dir(path), word)
		}
		if !os.is_file(target) {
			return error('${path} names ${word}, which is not a file')
		}
		bytes := os.read_file(target) or {
			return error('cannot read ${target}: ${err.msg()}')
		}
		if !is_elf(bytes.bytes()) {
			return error('${path} names ${word}, which is not an object file')
		}
		name := soname_in(bytes.bytes())
		if name != '' {
			return name
		}
		return os.base(target)
	}
	return error('${path} is neither an object file nor a library script this compiler reads')
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
