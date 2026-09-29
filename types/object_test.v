module types

import backend

// The size and alignment answers, asserted against the measured table.
//
// The table below is what gcc 16.2.1 reports on this machine (x86_64-linux),
// measured with `sizeof` and `_Alignof` over the kinds and the fixtures the tests
// then use. It is here rather than in object.v because a size is a fact about the
// machine: object.v asks a target description for these numbers, and a
// description that did not carry them answers nothing rather than answering
// something invented.
//
// The one number a target description does carry today is the width of the
// machine's registers, and `test_the_description_carries_the_pointer_and_names`
// checks that the description's pointer entry is what gcc measured.

// measured is the representation backend/ has to be able to answer. Every number
// in it was printed by the program whose command stands beside the test that
// asserts it.
fn measured() Representation {
	mut sizes := map[Kind]int{}
	mut aligns := map[Kind]int{}
	sizes[Kind.bool_] = 1
	aligns[Kind.bool_] = 1
	sizes[Kind.char_] = 1
	aligns[Kind.char_] = 1
	sizes[Kind.signed_char] = 1
	aligns[Kind.signed_char] = 1
	sizes[Kind.unsigned_char] = 1
	aligns[Kind.unsigned_char] = 1
	sizes[Kind.short] = 2
	aligns[Kind.short] = 2
	sizes[Kind.unsigned_short] = 2
	aligns[Kind.unsigned_short] = 2
	sizes[Kind.int_] = 4
	aligns[Kind.int_] = 4
	sizes[Kind.unsigned_int] = 4
	aligns[Kind.unsigned_int] = 4
	sizes[Kind.long] = 8
	aligns[Kind.long] = 8
	sizes[Kind.unsigned_long] = 8
	aligns[Kind.unsigned_long] = 8
	sizes[Kind.long_long] = 8
	aligns[Kind.long_long] = 8
	sizes[Kind.unsigned_long_long] = 8
	aligns[Kind.unsigned_long_long] = 8
	sizes[Kind.float] = 4
	aligns[Kind.float] = 4
	sizes[Kind.double] = 8
	aligns[Kind.double] = 8
	sizes[Kind.long_double] = 16
	aligns[Kind.long_double] = 16
	sizes[Kind.complex_float] = 8
	aligns[Kind.complex_float] = 4
	sizes[Kind.complex_double] = 16
	aligns[Kind.complex_double] = 8
	sizes[Kind.complex_long_double] = 32
	aligns[Kind.complex_long_double] = 16
	sizes[Kind.pointer] = 8
	aligns[Kind.pointer] = 8
	return Representation{
		sizes:  sizes
		aligns: aligns
	}
}

fn size_of(t Type) int {
	return measured().size_of(t) or {
		assert false
		return -1
	}
}

fn align_of(t Type) int {
	return measured().align_of(t) or {
		assert false
		return -1
	}
}

fn layout_of(t Type) Layout {
	return measured().layout(t) or {
		assert false
		return Layout{}
	}
}

fn member(name string, typ Type) Member {
	return Member{
		name: name
		typ:  typ
	}
}

fn bitfield(name string, typ Type, bits int) Member {
	return Member{
		name:     name
		typ:      typ
		bitfield: true
		bits:     bits
	}
}

// gcc -std=c99 -o measure measure.c && ./measure
fn test_the_size_and_alignment_of_every_scalar() {
	assert size_of(bool_type()) == 1 && align_of(bool_type()) == 1
	assert size_of(char_type()) == 1 && align_of(char_type()) == 1
	assert size_of(signed_char_type()) == 1 && align_of(signed_char_type()) == 1
	assert size_of(unsigned_char_type()) == 1 && align_of(unsigned_char_type()) == 1
	assert size_of(short_type()) == 2 && align_of(short_type()) == 2
	assert size_of(unsigned_short_type()) == 2 && align_of(unsigned_short_type()) == 2
	assert size_of(int_type()) == 4 && align_of(int_type()) == 4
	assert size_of(unsigned_int_type()) == 4 && align_of(unsigned_int_type()) == 4
	assert size_of(long_type()) == 8 && align_of(long_type()) == 8
	assert size_of(unsigned_long_type()) == 8 && align_of(unsigned_long_type()) == 8
	assert size_of(long_long_type()) == 8 && align_of(long_long_type()) == 8
	assert size_of(unsigned_long_long_type()) == 8 && align_of(unsigned_long_long_type()) == 8
	assert size_of(float_type()) == 4 && align_of(float_type()) == 4
	assert size_of(double_type()) == 8 && align_of(double_type()) == 8
	assert size_of(long_double_type()) == 16 && align_of(long_double_type()) == 16
	assert size_of(complex_float_type()) == 8 && align_of(complex_float_type()) == 4
	assert size_of(complex_double_type()) == 16 && align_of(complex_double_type()) == 8
	assert size_of(complex_long_double_type()) == 32 && align_of(complex_long_double_type()) == 16
	assert size_of(pointer_to(void_type())) == 8 && align_of(pointer_to(void_type())) == 8
}

fn test_an_array_is_its_element_size_times_its_count() {
	assert size_of(array_of(char_type(), 7)) == 7 && align_of(array_of(char_type(), 7)) == 1
	assert size_of(array_of(int_type(), 3)) == 12 && align_of(array_of(int_type(), 3)) == 4
	assert size_of(array_of(double_type(), 2)) == 16 && align_of(array_of(double_type(), 2)) == 8
	assert measured().size_of(array_of(int_type(), -1)) == none
}

// An enumerated type has the representation of int. Measured on gcc 16.2.1: an
// enum with a negative enumerator is size 4 alignment 4 and compatible with int,
// and an enum with an enumerator above INT_MAX is size 4 alignment 4 and
// compatible with unsigned int. The size and the alignment are the same either
// way, which is the part this model answers.
fn test_an_enumerated_type_has_the_representation_of_the_int_type() {
	assert size_of(enum_type('E')) == 4
	assert align_of(enum_type('E')) == 4
	assert size_of(qualified(enum_type('E'), Qualifiers{
		const_: true
	})) == 4
}

// gcc -std=c99 -o layout layout.c && ./layout
fn test_a_struct_is_laid_out_with_its_padding() {
	// struct p_char_int { char a; int b; }: offsetof b is 4, three bytes of
	// padding in front of it.
	ci := struct_type('p_char_int', [member('a', char_type()), member('b', int_type())])
	ci_layout := layout_of(ci)
	assert ci_layout.size == 8 && ci_layout.align == 4
	assert ci_layout.offsets == [0, 4]
	assert ci_layout.padding == 3
	// struct p_char_double { char a; double b; }: offsetof b is 8.
	cd := struct_type('p_char_double', [member('a', char_type()), member('b', double_type())])
	cd_layout := layout_of(cd)
	assert cd_layout.size == 16 && cd_layout.align == 8
	assert cd_layout.offsets == [0, 8]
	assert cd_layout.padding == 7
	// struct p_char_ld { char c; long double ld; }: offsetof ld is 16.
	cld := struct_type('p_char_ld', [member('c', char_type()), member('ld', long_double_type())])
	cld_layout := layout_of(cld)
	assert cld_layout.size == 32 && cld_layout.align == 16
	assert cld_layout.offsets == [0, 16]
	// struct p_short_char { short s; char c; }: two bytes of trailing padding.
	sc := struct_type('p_short_char', [member('s', short_type()), member('c', char_type())])
	sc_layout := layout_of(sc)
	assert sc_layout.size == 4 && sc_layout.align == 2
	assert sc_layout.offsets == [0, 2]
	assert sc_layout.padding == 1
	// struct p_int_char { int a; char b; }: three bytes at the end.
	ic := struct_type('p_int_char', [member('a', int_type()), member('b', char_type())])
	ic_layout := layout_of(ic)
	assert ic_layout.size == 8 && ic_layout.align == 4
	assert ic_layout.padding == 3
	// struct p_char_char { char a; char b; }: nothing to pad.
	cc := struct_type('p_char_char', [member('a', char_type()), member('b', char_type())])
	cc_layout := layout_of(cc)
	assert cc_layout.size == 2 && cc_layout.align == 1
	assert cc_layout.padding == 0
	// struct m7 { int a; char b; short c; }: offsetof c is 6, one byte of
	// padding in front of it.
	m7 := struct_type('m7', [member('a', int_type()), member('b', char_type()),
		member('c', short_type())])
	m7_layout := layout_of(m7)
	assert m7_layout.size == 8 && m7_layout.align == 4
	assert m7_layout.offsets == [0, 4, 6]
	assert m7_layout.padding == 1
	// struct arr { int a[3]; } and struct flex { int n; char data[]; }: a
	// flexible array member takes no room in the object before it.
	assert size_of(struct_type('arr', [member('a', array_of(int_type(), 3))])) == 12
	flex := struct_type('flex', [member('n', int_type()), member('data', array_of(char_type(), -1))])
	assert size_of(flex) == 4 && align_of(flex) == 4
	// An empty struct has no members to cover anything, and gcc gives it size 0
	// and alignment 1.
	empty := struct_type('p_empty', [])
	assert size_of(empty) == 0 && align_of(empty) == 1
}

// gcc -std=c99 -o layout layout.c && ./layout (the first line)
fn test_a_bitfield_starts_where_its_width_fits_in_its_own_unit() {
	// struct bf_u1 { unsigned a:1; } and struct bf_u1_31 { unsigned a:1;
	// unsigned b:31; } are both four bytes: the unit is the declared type.
	assert size_of(struct_type('bf_u1', [bitfield('a', unsigned_int_type(), 1)])) == 4
	packed := struct_type('bf_u1_31', [bitfield('a', unsigned_int_type(), 1), bitfield('b',
		unsigned_int_type(), 31)])
	packed_layout := layout_of(packed)
	assert packed_layout.size == 4 && packed_layout.align == 4
	assert packed_layout.offsets == [0, 0]
	assert packed_layout.bits == [0, 1]
	// struct bf_char1 { char a:1; } and struct bf_uchar44 { unsigned char a:4;
	// unsigned char b:4; } are one byte each.
	assert size_of(struct_type('bf_char1', [bitfield('a', char_type(), 1)])) == 1
	byte_packed := struct_type('bf_uchar44', [bitfield('a', unsigned_char_type(), 4),
		bitfield('b', unsigned_char_type(), 4)])
	byte_layout := layout_of(byte_packed)
	assert byte_layout.size == 1 && byte_layout.align == 1
	assert byte_layout.bits == [0, 4]
	// struct m1 { unsigned a:3; unsigned char b:4; }: the second bitfield fits
	// in the byte its own unit starts in, so the object is four bytes and not
	// eight, which is what tells the bit-offset rule apart from a unit per
	// member.
	m1 := struct_type('m1', [bitfield('a', unsigned_int_type(), 3), bitfield('b',
		unsigned_char_type(), 4)])
	m1_layout := layout_of(m1)
	assert m1_layout.size == 4 && m1_layout.align == 4
	assert m1_layout.offsets == [0, 0]
	assert m1_layout.bits == [0, 3]
	// struct m2 { char a; unsigned b:1; }: the bitfield sits at bit 8 and the
	// object is rounded up to the alignment the bitfield brings with it.
	m2 := struct_type('m2', [member('a', char_type()), bitfield('b', unsigned_int_type(), 1)])
	m2_layout := layout_of(m2)
	assert m2_layout.size == 4 && m2_layout.align == 4
	assert m2_layout.offsets == [0, 0]
	assert m2_layout.bits == [-1, 8]
	// struct m4 { unsigned a:20; unsigned char b:4; }: the second fits in the
	// byte at offset two.
	m4 := struct_type('m4', [bitfield('a', unsigned_int_type(), 20), bitfield('b',
		unsigned_char_type(), 4)])
	m4_layout := layout_of(m4)
	assert m4_layout.size == 4
	assert m4_layout.offsets == [0, 2]
	assert m4_layout.bits == [0, 4]
	// struct m6 { unsigned a:1; unsigned :0; unsigned b:1; }: a zero-width
	// bitfield starts the next unit of its type, so b lands at bit 32 and the
	// object is eight bytes.
	m6 := struct_type('m6', [bitfield('a', unsigned_int_type(), 1), bitfield('', unsigned_int_type(),
		0), bitfield('b', unsigned_int_type(), 1)])
	m6_layout := layout_of(m6)
	assert m6_layout.size == 8 && m6_layout.align == 4
	assert m6_layout.bits == [0, 0, 0]
	assert m6_layout.offsets == [0, 4, 4]
	// struct bf_mixed { char a; unsigned b:3; int c; }: c shares the unit with
	// the bitfield and starts at offset four, and the object is eight bytes.
	mixed := struct_type('bf_mixed', [member('a', char_type()), bitfield('b', unsigned_int_type(),
		3), member('c', int_type())])
	mixed_layout := layout_of(mixed)
	assert mixed_layout.size == 8 && mixed_layout.align == 4
	assert mixed_layout.offsets == [0, 0, 4]
	assert mixed_layout.bits == [-1, 8, -1]
	assert mixed_layout.padding == 2
}

// gcc -std=c99 -o layout layout.c && ./layout (union u1, u_char_int, u_double)
fn test_a_union_is_its_largest_member_at_the_beginning() {
	// union u_char_int { char c; int i; } is four bytes, and union u_double
	// { double d; long long l; } is eight.
	uc := union_type('u_char_int', [member('c', char_type()), member('i', int_type())])
	uc_layout := layout_of(uc)
	assert uc_layout.size == 4 && uc_layout.align == 4
	assert uc_layout.offsets == [0, 0]
	ud := union_type('u_double', [member('d', double_type()), member('l', long_long_type())])
	assert size_of(ud) == 8 && align_of(ud) == 8
	// A union holding a struct is as big as the struct, and one holding a
	// bitfield is as big as the storage unit of the bitfield's type.
	inner := struct_type('m7', [member('a', int_type()), member('b', char_type()),
		member('c', short_type())])
	assert size_of(union_type('u1', [member('s', inner), member('c', char_type())])) == 8
	mut bits_only := union_type('u_bit', [bitfield('a', unsigned_int_type(), 1)])
	assert size_of(bits_only) == 4
	bits_only = union_type('u_bit_char', [bitfield('a', char_type(), 1)])
	assert size_of(bits_only) == 1
}

fn test_a_type_with_no_size_has_no_answer() {
	representation := measured()
	// void and a function type describe no object at all.
	assert representation.size_of(void_type()) == none
	assert representation.size_of(function_type(int_type(), [], false, true)) == none
	// A tag that was declared and never defined is not complete, so nothing can
	// be laid out in it. Measured: gcc refuses `sizeof(struct undeclared)` with
	// `invalid application of 'sizeof' to an incomplete type`.
	assert representation.size_of(opaque_type('struct _IO_FILE')) == none
	assert representation.align_of(opaque_type('struct _IO_FILE')) == none
	assert representation.layout(opaque_type('struct _IO_FILE')) == none
	// A struct with an incomplete member has no layout of its own.
	holder := struct_type('holder', [member('f', opaque_type('struct _IO_FILE'))])
	assert representation.size_of(holder) == none
	// An array of nothing has no size either, and a member this reader could not
	// size is reported rather than counted as zero.
	assert representation.size_of(array_of(void_type(), 2)) == none
}

// A description that does not carry a kind refuses every question about it rather
// than answering the zero value of a map, which is the failure this test is here
// to catch.
fn test_a_description_that_does_not_carry_a_kind_refuses_the_question() {
	partial := Representation{
		sizes:  {
			Kind.int_: 4
		}
		aligns: {
			Kind.int_: 4
		}
	}
	assert partial.knows(Kind.int_)
	assert !partial.knows(Kind.long)
	assert partial.size_of(int_type()) or { -1 } == 4
	assert partial.size_of(long_type()) == none
	assert partial.align_of(long_type()) == none
	// An enumerated type has the representation of int, so a description that
	// carries int answers for the enum as well.
	assert partial.size_of(enum_type('E')) or { -1 } == 4
	holder := struct_type('holder', [member('a', int_type()), member('b', long_type())])
	assert partial.layout(holder) == none
}

// backend answers one entry today and names the rest. This test is the interface
// the plan assigns between types/ and backend/: the pointer width comes out of
// the description, everything else has to be added to it.
fn test_the_description_carries_the_pointer_and_names_what_it_does_not_carry() {
	target := backend.host() or {
		assert false
		return
	}
	description := from_target(target)
	// Measured with `gcc -std=c99 -o measure measure.c && ./measure`: void * is
	// 8 bytes with an alignment of 8, which is the machine's register width.
	pointer := pointer_to(void_type())
	described_size := description.representation.size_of(pointer) or { -1 }
	described_align := description.representation.align_of(pointer) or { -1 }
	assert described_size == 8
	assert described_align == 8
	// Every scalar kind is named as missing, and an int has no size until the
	// description carries one.
	assert description.missing == basic_kinds()
	assert description.representation.size_of(int_type()) == none
	assert description.representation.size_of(long_double_type()) == none
	assert !description.missing.contains(Kind.pointer)
	// The description and the measured table agree about the one entry both of
	// them carry.
	assert measured().size_of(pointer) or { -1 } == described_size
}
