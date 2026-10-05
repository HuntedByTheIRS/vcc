module archive

// A reader for the Unix ar container: the members a static library holds and
// the symbol index it carries beside them.
//
// A global magic opens the file, then a run of 60-byte member headers, each
// followed by its data padded to an even boundary. Three names are not members:
// a single slash is GNU's symbol index, /SYM64/ is the same index with 64-bit
// fields, and // is the table long member names live in. A malformed file is
// refused with the field that is wrong, because this reader is handed files
// other tools wrote and a wrong byte has to be a diagnostic rather than a crash
// or a quietly wrong member.

const global_magic = '!<arch>\n'
const header_size = 60
const fmag_first = 0x60
const fmag_second = 0x0a

pub struct Member {
pub:
	name  string
	bytes []u8
}

pub struct Archive {
pub:
	members []Member       // in the order they stand in the file, first real member first
	index   map[string]int // symbol name -> the index into members of the member that defines it
}

// One symbol the index names, held until every member header has been seen so
// its file offset can be turned into a member position.
struct SymEntry {
	name   string
	offset int
}

// read parses an ar archive and answers its real members and the symbol index.
//
// The symbol index stands before the members it names, so the entries are
// collected first and resolved against a map of header offset to member
// position at the end. An archive without an index yields an empty map, which
// is not an error: a static library built without one still links by scanning.
pub fn read(bytes []u8) !Archive {
	if !has_global_magic(bytes) {
		return error('not a Unix ar archive: the file does not start with "!<arch>\\n"')
	}
	mut members := []Member{}
	mut longnames := []u8{}
	mut symbols := []SymEntry{}
	mut member_at := map[int]int{}
	mut offset := 8
	for offset < bytes.len {
		if offset + header_size > bytes.len {
			return error('malformed archive: the member header at byte ${offset} is truncated')
		}
		header := bytes[offset..offset + header_size]
		if header[58] != u8(fmag_first) || header[59] != u8(fmag_second) {
			return error('malformed archive: the member header at byte ${offset} does not end in the two magic bytes')
		}
		raw_name := header[..16].bytestr().trim_space()
		if raw_name == '' {
			return error('malformed archive: the member header at byte ${offset} has an empty name')
		}
		size := decimal_text(header[48..58].bytestr()) or {
			return error('malformed archive: the member header at byte ${offset} has a size field that is not a number')
		}
		data_at := offset + header_size
		if data_at + size > bytes.len {
			return error('malformed archive: the member at byte ${offset} holds ${size} bytes but the file ends first')
		}
		data := bytes[data_at..data_at + size]
		if raw_name == '/' {
			symbols << read_symbol_index(data, false) or { return err }
		} else if raw_name == '/SYM64/' {
			symbols << read_symbol_index(data, true) or { return err }
		} else if raw_name == '//' {
			longnames = data.clone()
		} else {
			name, body := member_name(raw_name, data, size, longnames) or { return err }
			member_at[offset] = members.len
			members << Member{
				name:  name
				bytes: body
			}
		}
		offset = data_at + size + (size & 1)
	}
	mut index := map[string]int{}
	for s in symbols {
		// First definition wins, the way a linker takes the first member that
		// defines a name it is looking for.
		if s.name in index {
			continue
		}
		if mi := member_at[s.offset] {
			index[s.name] = mi
		}
	}
	return Archive{
		members: members
		index:   index
	}
}

// member_for answers the member the index names for a symbol, or none.
pub fn (a Archive) member_for(symbol string) ?Member {
	i := a.index[symbol] or { return none }
	if i < 0 || i >= a.members.len {
		return none
	}
	return a.members[i]
}

// has_global_magic compares the opening bytes against the ar magic. It tests
// byte by byte rather than comparing a slice against a string so the length
// check and the contents check cannot be confused for one another.
fn has_global_magic(bytes []u8) bool {
	if bytes.len < global_magic.len {
		return false
	}
	for i in 0 .. global_magic.len {
		if bytes[i] != global_magic[i] {
			return false
		}
	}
	return true
}

// member_name resolves the name of a real member from the header's name field
// and its data. Three name forms reach here:
//
//   - `name/`, a short name whose trailing slash is a terminator;
//   - `/N`, the name at byte offset N of the // long-name table;
//   - `#1/L`, the BSD form where the first L bytes of the data are the name.
//
// The body is the member's data, which for the BSD form is what follows the
// name inside the data. The trailing slash and any padding are never part of
// the reported name.
fn member_name(raw string, data []u8, size int, longnames []u8) !(string, []u8) {
	if raw.starts_with('#1/') {
		length := decimal_text(raw[3..]) or {
			return error('malformed archive: a BSD member names a name length that is not a number')
		}
		if length < 0 || length > size {
			return error('malformed archive: a BSD member name runs past its own data')
		}
		name := data[..length].bytestr().trim_right('\x00\r\n').trim_space()
		return name, data[length..size]
	}
	if raw.starts_with('/') {
		off := decimal_text(raw[1..]) or {
			return error('malformed archive: a member names a long-name offset that is not a number')
		}
		name := long_name(longnames, off) or {
			return error('malformed archive: a member names a long-name offset outside the name table')
		}
		return name, data
	}
	if raw.ends_with('/') {
		return raw[..raw.len - 1], data
	}
	return raw, data
}

// long_name reads the name at off in the // table, running to the next newline.
// The stored form ends the name with a slash before the newline, so a trailing
// slash and any padding come off before the name is answered.
fn long_name(table []u8, off int) ?string {
	if off < 0 || off >= table.len {
		return none
	}
	mut end := off
	for end < table.len && table[end] != u8(0x0a) {
		end++
	}
	mut name := table[off..end].bytestr()
	name = name.trim_right('\x00\r\n')
	if name.ends_with('/') {
		name = name[..name.len - 1]
	}
	return name.trim_space()
}

// read_symbol_index reads the GNU symbol index: a big-endian count, then that
// many big-endian byte offsets, then that many NUL-terminated names in the same
// order. The 64-bit form, /SYM64/, is the same with eight-byte fields.
fn read_symbol_index(data []u8, wide bool) ![]SymEntry {
	unit := if wide { 8 } else { 4 }
	if data.len < unit {
		return error('malformed archive: the symbol index is shorter than its count field')
	}
	mut count := 0
	if wide {
		count = int(be64(data, 0))
	} else {
		count = int(be32(data, 0))
	}
	if count < 0 {
		return error('malformed archive: the symbol index names a negative count')
	}
	// Compare against the room the data leaves before multiplying: count * unit
	// from a hostile 64-bit count could overflow and turn the bound check into a
	// no-op.
	if count > (data.len - unit) / unit {
		return error('malformed archive: the symbol index names more entries than it holds')
	}
	names_at := unit + count * unit
	mut out := []SymEntry{}
	mut pos := names_at
	for i in 0 .. count {
		mut off := 0
		if wide {
			off = int(be64(data, unit + i * unit))
		} else {
			off = int(be32(data, unit + i * unit))
		}
		start := pos
		for pos < data.len && data[pos] != u8(0) {
			pos++
		}
		if pos >= data.len {
			return error('malformed archive: the symbol index ends before its last name')
		}
		out << SymEntry{
			name:   data[start..pos].bytestr()
			offset: off
		}
		pos++
	}
	return out
}

// decimal_text parses a space-padded decimal field. It answers none rather than
// zero for text that is empty or holds anything but digits, so a caller can
// refuse the field instead of reading a wrong number.
fn decimal_text(text string) ?int {
	s := text.trim_space()
	if s.len == 0 {
		return none
	}
	mut value := 0
	for i in 0 .. s.len {
		c := s[i]
		if c < u8(0x30) || c > u8(0x39) {
			return none
		}
		value = value * 10 + (int(c) - 0x30)
	}
	return value
}

// be32 and be64 read an unsigned big-endian field. The callers bounds-check the
// archive before calling, so the reads here stay inside the slice they are given.
fn be32(data []u8, at int) u32 {
	return u32(data[at]) << 24 | u32(data[at + 1]) << 16 | u32(data[at + 2]) << 8 | u32(data[at + 3])
}

fn be64(data []u8, at int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 {
		value = value << 8 | u64(data[at + i])
	}
	return value
}
