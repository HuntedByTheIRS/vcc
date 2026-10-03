module types

import backend
import measured

// The size and alignment answers, asserted against the measured table.
//
// The table below is what gcc 16.2.1 reports on this machine (x86_64-linux),
// measured with `sizeof` and `_Alignof` over the kinds and the fixtures the tests
// then use. It is here rather than in object.v because a size is a fact about the
// machine: object.v asks a target description for these numbers, and a
// description that did not carry them answers nothing rather than answering
// something invented.
//
// The entries a target description does carry are the width of the machine's
// registers and the width of the integer the back end writes a constant at, and
// `test_the_description_carries_the_pointer_and_the_written_int` checks that both
// of those are what gcc measured.

fn size_of(t Type) int {
	return measured.representation().size_of(t) or {
		assert false
		return -1
	}
}

fn align_of(t Type) int {
	return measured.representation().align_of(t) or {
		assert false
		return -1
	}
}

fn layout_of(t Type) Layout {
	return measured.representation().layout(t) or {
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

// The command that produced the table is in types/measured/measured.v.
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
	assert size_of(int128_type()) == 16 && align_of(int128_type()) == 16
	assert size_of(unsigned_int128_type()) == 16 && align_of(unsigned_int128_type()) == 16
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
	assert measured.representation().size_of(array_of(int_type(), -1)) == none
}

// An enumerated type has the representation of the integer type its enumerators
// require. Measured on gcc 16.2.1: an enum whose enumerators all fit int, with or
// without a negative value, is size 4 alignment 4 and compatible with int or
// unsigned int; one with a negative value and one above INT_MAX is size 8
// alignment 8, and one whose values do not fit unsigned int is size 8 alignment
// 8. The underlying kind carries which of the four it is.
fn test_an_enumerated_type_has_the_representation_of_its_underlying_type() {
	assert size_of(enum_type('E', .int_)) == 4
	assert align_of(enum_type('E', .int_)) == 4
	assert size_of(enum_type('E', .unsigned_int)) == 4
	assert align_of(enum_type('E', .unsigned_int)) == 4
	assert size_of(enum_type('E', .long)) == 8
	assert align_of(enum_type('E', .long)) == 8
	assert size_of(enum_type('E', .unsigned_long)) == 8
	assert align_of(enum_type('E', .unsigned_long)) == 8
	assert size_of(qualified(enum_type('E', .int_), Qualifiers{
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

// A 128-bit member is laid out around its own alignment the way any other type
// of that width is: measured on gcc 16.2.1, `struct { char c; __int128 v; }` is
// 32 bytes with v at 16, and `struct { __int128 v; char c; }` is 32 bytes with c
// at 16. `long double` has the same width and alignment on this target, so the
// two layouts are the same shape.
fn test_a_128_bit_member_is_laid_out_at_its_alignment() {
	cv := struct_type('q_char_i128', [member('c', char_type()), member('v', int128_type())])
	cv_layout := layout_of(cv)
	assert cv_layout.size == 32 && cv_layout.align == 16
	assert cv_layout.offsets == [0, 16]
	assert cv_layout.padding == 15
	vc := struct_type('q_i128_char', [member('v', int128_type()), member('c', char_type())])
	vc_layout := layout_of(vc)
	assert vc_layout.size == 32 && vc_layout.align == 16
	assert vc_layout.offsets == [0, 16]
	// A union takes the largest member at the beginning, and its alignment is
	// the strictest one at 16.
	u := union_type('q_i128_union', [member('c', char_type()), member('v', int128_type())])
	u_layout := layout_of(u)
	assert u_layout.size == 16 && u_layout.align == 16
	// An array of three of them is 48 bytes, which is what gcc gives
	// `sizeof(__int128[3])`.
	assert size_of(array_of(int128_type(), 3)) == 48
}

// The description the compiler builds is what the emitter's questions are
// answered from, so the 128-bit width has to be in it and not only in the
// measured table the tests read.
fn test_the_compiler_carries_the_128_bit_width() {
	target := backend.host() or {
		assert false
		return
	}
	rep := from_target(target).representation
	assert rep.size_of(int128_type()) or { -1 } == 16
	assert rep.align_of(int128_type()) or { -1 } == 16
	assert rep.size_of(unsigned_int128_type()) or { -1 } == 16
	assert rep.align_of(unsigned_int128_type()) or { -1 } == 16
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
	representation := measured.representation()
	// void and a function type describe no object at all.
	assert representation.size_of(void_type()) == none
	assert representation.size_of(function_type(int_type(), [], false, true)) == none
	// A tag that was declared and never defined is not complete, so nothing can
	// be laid out in it. Measured: gcc refuses `sizeof(struct undeclared)` with
	// `invalid application of 'sizeof' to an incomplete type`.
	assert representation.size_of(opaque_type('struct _IO_FILE')) == none
	assert representation.align_of(opaque_type('struct _IO_FILE')) == none
	assert representation.layout(opaque_type('struct _IO_FILE')) == none
	// A tag whose body was never read is incomplete with an empty member list,
	// which is not the same as a struct of no members: there is no layout to
	// answer, and answering zero would be a size for a type nothing can size.
	undeclared := incomplete_tag(Kind.struct_, 'undeclared')
	assert representation.size_of(undeclared) == none
	assert representation.align_of(undeclared) == none
	assert representation.layout(undeclared) == none
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
	// An enumerated type has the representation of its underlying type, so a
	// description that carries int answers for the enum whose underlying kind is int.
	assert partial.size_of(enum_type('E', .int_)) or { -1 } == 4
	holder := struct_type('holder', [member('a', int_type()), member('b', long_type())])
	assert partial.layout(holder) == none
}

// backend answers the width of a pointer and the width of the integer the back
// end writes a constant at, and names the rest. This test is the interface the
// plan assigns between types/ and backend/: the pointer width comes out of the
// machine's own table, the integer width is the one the back end writes at, and
// everything else has to be added to the description before a question that needs
// it can be answered.
fn test_the_description_carries_the_pointer_and_the_written_int() {
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
	// Measured the same way: int and unsigned int are 4 bytes with an alignment
	// of 4, which is the width the back end writes every integer constant at.
	described_int := description.representation.size_of(int_type()) or { -1 }
	described_int_align := description.representation.align_of(int_type()) or { -1 }
	assert described_int == 4
	assert described_int_align == 4
	assert description.representation.size_of(unsigned_int_type()) or { -1 } == 4
	// The complex types are carried, and the widths and alignments are the ones
	// measured on gcc 16.2.1: `sizeof(float _Complex)` is 8 with an alignment of
	// 4, `sizeof(double _Complex)` is 16 with an alignment of 8, and
	// `sizeof(long double _Complex)` is 32 with an alignment of 16. The width
	// the back end does not move is still a width the model can give out
	// truthfully for a layout question, which is what a member of the type asks.
	assert description.representation.size_of(complex_float_type()) or { -1 } == 8
	assert description.representation.align_of(complex_float_type()) or { -1 } == 4
	assert description.representation.size_of(complex_double_type()) or { -1 } == 16
	assert description.representation.align_of(complex_double_type()) or { -1 } == 8
	assert description.representation.size_of(complex_long_double_type()) or { -1 } == 32
	assert description.representation.align_of(complex_long_double_type()) or { -1 } == 16
	// Every other scalar kind is named as missing: the description carries no
	// width for an aggregate or a complex type, and a question that needs one is
	// refused rather than answered with a number that would be a machine
	// fact in the wrong module.
	//
	// The four 64-bit integer kinds are carried, and that is what the emitter
	// moving eight bytes at a time made true: a `long` is 8 bytes with an
	// alignment of 8 on this target, measured, and the 64-bit instructions
	// compute with exactly those bytes. They left this list in the commit that
	// gave the back end a value of that width.
	//
	// A char is carried, and the question that needs it is the layout of an
	// aggregate: where the member after a char member starts is the char's width
	// and nothing else's. The back end has a form for one already, since a char
	// is a byte in its slot and an int when it is read, so the width is one the
	// model can give out truthfully.
	// A float is carried for the same reason the char is: the emitter has a
	// four-byte form for one, so the model can give out its width truthfully.
	// Measured the same way: `sizeof(float)` is 4 with an alignment of 4.
	//
	// The character types, `_Bool` and the two-byte integers are carried for the
	// same reason: the emitter loads and stores a one- or two-byte value, so a
	// width the model gives out is one the back end moves. Measured the same way:
	// `sizeof(_Bool)`, `sizeof(char)`, `sizeof(signed char)` and
	// `sizeof(unsigned char)` are each 1 with an alignment of 1, and `sizeof(short)`
	// and `sizeof(unsigned short)` are each 2 with an alignment of 2.
	// A `long double` is carried: the model lays one out at sixteen bytes with an
	// alignment of sixteen, measured on gcc 16.2.1, which is the storage the back
	// end claims for it. It left this list in the commit that gave the extended
	// type a form.
	carried := [Kind.int_, .unsigned_int, .double, .float, .char_, .signed_char, .unsigned_char,
		.bool_, .short, .unsigned_short, .long, .unsigned_long, .long_long, .unsigned_long_long,
		.long_double, .complex_float, .complex_double, .complex_long_double]
	mut expected_missing := []Kind{}
	for kind in basic_kinds() {
		if kind !in carried {
			expected_missing << kind
		}
	}
	assert description.missing == expected_missing
	assert !description.missing.contains(Kind.int_)
	assert !description.missing.contains(Kind.unsigned_int)
	assert !description.missing.contains(Kind.pointer)
	assert !description.missing.contains(Kind.long)
	assert !description.missing.contains(Kind.long_long)
	assert !description.missing.contains(Kind.unsigned_long)
	assert !description.missing.contains(Kind.unsigned_long_long)
	assert !description.missing.contains(Kind.short)
	assert !description.missing.contains(Kind.unsigned_short)
	// Measured with gcc 16.2.1 on this target: `sizeof(char)` is 1 with an
	// alignment of 1.
	assert description.representation.size_of(char_type()) or { -1 } == 1
	assert description.representation.align_of(char_type()) or { -1 } == 1
	// Measured the same way: `sizeof(short)` is 2 with an alignment of 2.
	assert description.representation.size_of(short_type()) or { -1 } == 2
	assert description.representation.align_of(short_type()) or { -1 } == 2
	assert description.representation.size_of(unsigned_short_type()) or { -1 } == 2
	assert description.representation.align_of(unsigned_short_type()) or { -1 } == 2
	// `sizeof(long)` and `sizeof(long long)` are 8 with an alignment of 8, and
	// case_00 prints the whole table: `long 8/8  unsigned long 8/8  long long
	// 8/8  unsigned long long 8/8`.
	for wide in [long_type(), long_long_type()] {
		assert description.representation.size_of(wide) or { -1 } == 8
		assert description.representation.align_of(wide) or { -1 } == 8
	}
	assert description.representation.size_of(unsigned_long_type()) or { -1 } == 8
	assert description.representation.size_of(unsigned_long_long_type()) or { -1 } == 8
	// The double is carried because the back end moves one, and the two numbers
	// are the measured ones rather than a guess: `sizeof(double)` is 8 with an
	// alignment of 8 on this target.
	assert !description.missing.contains(Kind.double)
	assert description.representation.size_of(double_type()) or { -1 } == 8
	assert description.representation.align_of(double_type()) or { -1 } == 8
	assert measured.representation().size_of(double_type()) or { -1 } == 8
	assert measured.representation().align_of(double_type()) or { -1 } == 8
	// The extended type is carried too: the model lays one out at sixteen bytes
	// with an alignment of sixteen, measured on gcc 16.2.1, so the description
	// gives out that width rather than naming the type missing.
	assert description.representation.size_of(long_double_type()) or { -1 } == 16
	assert description.representation.align_of(long_double_type()) or { -1 } == 16
	assert description.representation.size_of(float_type()) or { -1 } == 4
	assert description.representation.align_of(float_type()) or { -1 } == 4
	// The description and the measured table agree about every entry both of
	// them carry, which is what keeps the two numbers in the description from
	// drifting away from what gcc says the target is.
	assert measured.representation().size_of(pointer) or { -1 } == described_size
	assert measured.representation().size_of(int_type()) or { -1 } == described_int
	assert measured.representation().align_of(int_type()) or { -1 } == described_int_align
	assert measured.representation().size_of(unsigned_int_type()) or { -1 } ==
		description.representation.size_of(unsigned_int_type()) or { -1 }
}

// 6.7.2.1p13: the members of an unnamed struct or union member are members of
// the aggregate that contains it, found by name and carrying the byte and bit
// offset the layout gave them inside that unnamed member. These tests build the
// aggregates the rule is about and read those offsets.
//
// The numbers are the ones gcc 16.2.1 printed on this target for the same
// declarations, measured with `sizeof` and `offsetof`, which a member written
// directly into the outer aggregate would print too: the promotion only changes
// which names reach a member, not where it sits.
fn member_named(t Type, name string) ?Member {
	for m in t.members {
		if m.name == name {
			return m
		}
	}
	return none
}

fn member_offset(t Type, name string) int {
	layout := layout_of(t)
	for i, m in t.members {
		if m.name == name {
			return layout.offsets[i]
		}
	}
	assert false
	return -1
}

fn member_bit(t Type, name string) int {
	layout := layout_of(t)
	for i, m in t.members {
		if m.name == name {
			return layout.bits[i]
		}
	}
	assert false
	return -1
}

// An unnamed union in a struct. Its members both sit where the union sits, which
// is 8 because the long member aligns the union at 8; the members beside it are
// at 0 and 16, so a lookup that answered the wrong index would be caught.
// Measured on gcc 16.2.1: sizeof is 24, lead is 0, u8 and u64 are 8, tail is 16.
fn test_an_unnamed_union_puts_its_members_in_the_enclosing_struct() {
	u := union_type('', [member('u8', char_type()), member('u64', long_type())])
	s := struct_type('P', [member('lead', char_type()), member('', u), member('tail', char_type())])
	assert size_of(s) == 24
	assert member_named(s, 'u8') != none && member_named(s, 'u64') != none
	assert member_offset(s, 'lead') == 0
	assert member_offset(s, 'u8') == 8
	assert member_offset(s, 'u64') == 8
	assert member_offset(s, 'tail') == 16
}

// An unnamed struct in a struct. Its members are at different offsets inside it,
// so this is the row that tells a lookup answering the first member of the
// unnamed aggregate from one answering the name it was asked for.
// Measured on gcc 16.2.1: sizeof is 32, lead is 0, a is 8, b is 16, tail is 24.
fn test_an_unnamed_struct_puts_its_members_in_the_enclosing_struct() {
	inner := struct_type('', [member('a', char_type()), member('b', long_type())])
	s := struct_type('S', [member('lead', char_type()), member('', inner), member('tail',
		char_type())])
	assert size_of(s) == 32
	assert member_offset(s, 'a') == 8
	assert member_offset(s, 'b') == 16
	assert member_offset(s, 'tail') == 24
}

// The shape V's own definition of IError has: an unnamed struct carrying two
// bitfields inside an unnamed union inside a struct. The bitfields are read
// through the union, so their byte is the union's and their bits are the ones
// the unnamed struct's layout gave them: _typ at bit 0 of 31 bits and
// _object_is_boxed at bit 31. Measured on gcc 16.2.1: sizeof is 16, _object is
// 0, _interface_meta, _typ and _object_is_boxed are all at 8, and writing _typ
// and _object_is_boxed fills the low four bytes of the union.
fn test_a_bitfield_of_an_unnamed_struct_inside_an_unnamed_union_keeps_its_bits() {
	bits := struct_type('', [bitfield('_typ', unsigned_int_type(), 31), bitfield('_object_is_boxed',
		unsigned_int_type(), 1)])
	union_ := union_type('', [member('_interface_meta', pointer_to(int_type())), member('', bits)])
	e := struct_type('IError', [member('_object', pointer_to(int_type())), member('', union_)])
	assert size_of(e) == 16
	assert member_offset(e, '_object') == 0
	assert member_offset(e, '_interface_meta') == 8
	assert member_offset(e, '_typ') == 8
	assert member_offset(e, '_object_is_boxed') == 8
	typ := member_named(e, '_typ') or {
		assert false
		return
	}
	assert typ.bitfield && typ.bits == 31
	boxed := member_named(e, '_object_is_boxed') or {
		assert false
		return
	}
	assert boxed.bitfield && boxed.bits == 1
	assert member_bit(e, '_typ') == 0
	assert member_bit(e, '_object_is_boxed') == 31
}

// A named union member beside an unnamed one is an ordinary member: its own
// members are reached through its name and are not promoted. Measured on gcc
// 16.2.1: sizeof is 8, anon is 0, n is 4, and `n.inner` exists while a bare
// `inner` does not.
fn test_a_named_union_beside_an_unnamed_one_is_reached_through_its_name() {
	anon_union := union_type('', [member('anon', int_type())])
	named := union_type('Named', [member('inner', int_type())])
	s := struct_type('C', [member('', anon_union), member('n', named)])
	assert size_of(s) == 8
	assert member_offset(s, 'anon') == 0
	assert member_offset(s, 'n') == 4
	assert member_named(s, 'inner') == none
	n := member_named(s, 'n') or {
		assert false
		return
	}
	assert n.typ.kind == .union_
}

// The control the rule must not move: an aggregate with no unnamed struct or
// union in it has exactly the members its body wrote, in order, none of them
// promoted. This is the named path that must not be narrowed or shifted.
fn test_an_aggregate_without_an_unnamed_member_is_unchanged() {
	plain := struct_type('G', [member('a', int_type()), member('b', char_type())])
	assert plain.members.len == 2
	assert plain.members[0].name == 'a' && plain.members[0].promoted == false
	assert plain.members[1].name == 'b' && plain.members[1].promoted == false
	named_union := struct_type('F', [member('n', union_type('U', [member('a', int_type())]))])
	assert named_union.members.len == 1
	assert named_union.members[0].name == 'n' && named_union.members[0].promoted == false
}

// 6.7.2.1p13 makes the names an unnamed member contributes distinct from every
// other name, and gcc 16.2.1 refuses `struct { union { int x; }; union { long x;
// }; };` as `duplicate member 'x'`. A name two members would answer to is marked
// here so that no lookup finds it, which is a refusal rather than a silent pick
// of one of them.
fn test_a_name_two_unnamed_members_would_both_answer_is_not_found() {
	first := union_type('', [member('x', int_type())])
	second := union_type('', [member('x', long_type())])
	both := struct_type('D', [member('', first), member('', second)])
	assert member_named(both, 'x') == none
	assert both.members.any(it.name.contains('ambiguous'))
}

// The same collision between a member written in the body and one an unnamed
// member contributes: the written name is not silently preferred.
fn test_a_name_an_unnamed_member_collides_with_is_not_found() {
	union_ := union_type('', [member('x', int_type())])
	s := struct_type('E', [member('x', int_type()), member('', union_)])
	assert member_named(s, 'x') == none
	assert s.members.any(it.name.contains('ambiguous'))
}
