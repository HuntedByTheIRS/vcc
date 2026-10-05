module archive

// The reader is checked against an archive built here byte by byte, so the
// layout the assertions expect is the layout the builder wrote and not a
// recording of some other tool's output. The archive holds two real members,
// one named the short way and one through the // long-name table, plus the GNU
// symbol index naming a symbol in each.

fn build_test_archive() []u8 {
	b_long := 'long_named_member.o'
	longtab := b_long + '/\n'
	sym_names := ['alpha_sym', 'beta_sym']
	mut sym_len := 4 + 4 * sym_names.len
	for s in sym_names {
		sym_len += s.len + 1
	}
	a_data := [u8(0x01), u8(0x02), u8(0x03)]
	b_data := [u8(0x10), u8(0x11), u8(0x12), u8(0x13), u8(0x14)]

	// The symbol index stands first, so the member offsets are worked out from
	// the sizes before anything is written.
	slash_off := 8
	longtab_off := slash_off + header_size + pad_even(sym_len)
	member_a_off := longtab_off + header_size + pad_even(longtab.len)
	member_b_off := member_a_off + header_size + pad_even(a_data.len)

	mut sym_data := []u8{}
	push_be32(mut sym_data, u32(sym_names.len))
	push_be32(mut sym_data, u32(member_a_off))
	push_be32(mut sym_data, u32(member_b_off))
	for s in sym_names {
		push_str(mut sym_data, s)
		sym_data << u8(0)
	}
	assert sym_data.len == sym_len

	mut out := []u8{}
	push_str(mut out, global_magic)
	push_member(mut out, '/', sym_data)
	push_member(mut out, '//', longtab.bytes())
	push_member(mut out, 'alpha.o/', a_data)
	push_member(mut out, '/0', b_data)
	return out
}

fn build_simple_archive() []u8 {
	mut out := []u8{}
	push_str(mut out, global_magic)
	push_member(mut out, 'x.o/', [u8(0x07), u8(0x08)])
	return out
}

fn test_read_members_and_index() {
	a := read(build_test_archive()) or { panic(err.msg()) }
	assert a.members.len == 2
	assert a.members[0].name == 'alpha.o'
	assert a.members[0].bytes == [u8(0x01), u8(0x02), u8(0x03)]
	assert a.members[1].name == 'long_named_member.o'
	assert a.members[1].bytes == [u8(0x10), u8(0x11), u8(0x12), u8(0x13), u8(0x14)]
	assert a.index.len == 2
	assert a.index['alpha_sym'] == 0
	assert a.index['beta_sym'] == 1
}

fn test_member_for() {
	a := read(build_test_archive()) or { panic(err.msg()) }
	m := a.member_for('beta_sym') or { panic('member_for missed a symbol the index names') }
	assert m.name == 'long_named_member.o'
	assert m.bytes == [u8(0x10), u8(0x11), u8(0x12), u8(0x13), u8(0x14)]
	other := a.member_for('alpha_sym') or { panic('member_for missed alpha_sym') }
	assert other.name == 'alpha.o'
	assert other.bytes == [u8(0x01), u8(0x02), u8(0x03)]
	missing := a.member_for('not_a_symbol') or { Member{} }
	assert missing.name == ''
}

fn test_archive_without_index_has_empty_map() {
	a := read(build_simple_archive()) or { panic(err.msg()) }
	assert a.members.len == 1
	assert a.members[0].name == 'x.o'
	assert a.members[0].bytes == [u8(0x07), u8(0x08)]
	assert a.index.len == 0
}

fn test_bsd_long_name() {
	name := 'a_bsd_named_member.o'
	mut payload := []u8{}
	push_str(mut payload, name)
	payload << u8(0xaa)
	payload << u8(0xbb)
	mut out := []u8{}
	push_str(mut out, global_magic)
	push_member(mut out, '#1/${name.len}', payload)
	a := read(out) or { panic(err.msg()) }
	assert a.members.len == 1
	assert a.members[0].name == name
	assert a.members[0].bytes == [u8(0xaa), u8(0xbb)]
}

fn test_bad_magic_refused() {
	read('not an ar archive here'.bytes()) or {
		assert err.msg() != ''
		return
	}
	assert false, 'read accepted a file whose magic is not the ar magic'
}

fn test_truncated_header_refused() {
	full := build_simple_archive()
	truncated := full[..8 + 20]
	read(truncated) or {
		assert err.msg() != ''
		return
	}
	assert false, 'read accepted an archive whose member header is truncated'
}

fn test_bad_fmag_refused() {
	mut full := build_simple_archive()
	full[8 + 58] = u8(0x58) // 'X' where the first magic byte belongs
	read(full) or {
		assert err.msg() != ''
		return
	}
	assert false, 'read accepted a member header whose fmag is wrong'
}

fn test_malformed_64bit_index_refused() {
	// A /SYM64/ count large enough that count * 8 would overflow a signed
	// integer: the reader must refuse it, not walk off the slice.
	mut sym64 := []u8{}
	sym64 << u8(0x60)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	sym64 << u8(0x00)
	mut out := []u8{}
	push_str(mut out, global_magic)
	push_member(mut out, '/SYM64/', sym64)
	read(out) or {
		assert err.msg() != ''
		return
	}
	assert false, 'read accepted a 64-bit symbol index with an impossible count'
}

// The build helpers below write an ar member the way the format describes:
// a 60-byte header, the data, then one pad byte when the data length is odd.

fn pad_even(n int) int {
	return n + (n & 1)
}

fn push_str(mut out []u8, s string) {
	for i in 0 .. s.len {
		out << s[i]
	}
}

fn push_be32(mut out []u8, v u32) {
	out << u8((v >> 24) & 0xff)
	out << u8((v >> 16) & 0xff)
	out << u8((v >> 8) & 0xff)
	out << u8(v & 0xff)
}

fn member_header(name string, size int) []u8 {
	assert name.len <= 16
	mut h := []u8{}
	push_str(mut h, name)
	for h.len < 16 {
		h << u8(0x20)
	}
	push_str(mut h, '0')
	for h.len < 28 {
		h << u8(0x20)
	}
	push_str(mut h, '0')
	for h.len < 34 {
		h << u8(0x20)
	}
	push_str(mut h, '0')
	for h.len < 40 {
		h << u8(0x20)
	}
	push_str(mut h, '100644')
	for h.len < 48 {
		h << u8(0x20)
	}
	push_str(mut h, size.str())
	for h.len < 58 {
		h << u8(0x20)
	}
	h << u8(0x60)
	h << u8(0x0a)
	assert h.len == header_size
	return h
}

fn push_member(mut out []u8, name string, data []u8) {
	out << member_header(name, data.len)
	out << data
	if (data.len & 1) == 1 {
		out << u8(0x0a)
	}
}
