module types

import backend

// The object representation of a type: how many bytes a value of it occupies,
// where it may start, how its members sit inside it, and how many of those bytes
// hold no member at all.
//
// Every one of those answers is a fact about the machine and the system rather
// than about the language, so none of them is written in this module. A
// Representation is the answer a target description gave, this file is the
// question asked of it, and a kind the description does not carry is refused
// rather than filled in with a number that would be a machine fact in the wrong
// module.

// Representation is what a target description says about the C types it emits
// for: the size of each scalar kind in bytes, its alignment, and the same for a
// pointer. A kind that is not in the tables was not described, and every question
// about it is refused.
pub struct Representation {
pub:
	sizes  map[Kind]int
	aligns map[Kind]int
}

// knows says whether the description carries this kind.
// bits_in_a_byte is the one fact about a target this module states in code
// rather than asks for: the back end describes x86_64 this milestone, and a
// byte there is eight bits. Every size, alignment and member offset below comes
// from the description it is handed; the arithmetic that turns a member's width
// into a bit position counts bits in that byte, which is the only place this
// module needs the width of one.
const bits_in_a_byte = 8

pub fn (r Representation) knows(kind Kind) bool {
	return kind in r.sizes && kind in r.aligns
}

// basic_kinds are the kinds a description has to carry for the type model to
// answer anything: every scalar the language has. The derived kinds are computed
// from these, and a pointer is a fact about the machine rather than about C.
pub fn basic_kinds() []Kind {
	return [Kind.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short, .int_,
		.unsigned_int, .long, .unsigned_long, .long_long, .unsigned_long_long, .float, .double,
		.long_double, .complex_float, .complex_double, .complex_long_double]
}

// Layout is where the members of an aggregate sit and how much room the whole
// object takes.
pub struct Layout {
pub:
	size  int
	align int
	// offsets are the byte offsets of the members, in the order they were
	// written. A bitfield's offset is the byte the storage unit it was placed in
	// starts at.
	offsets []int
	// bits are the bit positions of the members inside the storage unit they
	// were placed in, and -1 for a member that is not a bitfield.
	bits []int
	// padding is the number of bytes of the object no member's own storage
	// covers: the gap in front of an aligned member and the bytes at the end
	// that the alignment rounds up to. A bitfield covers the bytes its bits lie
	// in, which is at most the unit it was placed in.
	padding int
}

// size_of is the number of bytes a value of this type occupies, and none when
// the answer is not known: a description that does not carry the kind, an
// incomplete type, a function or a type this compiler never resolved.
pub fn (r Representation) size_of(t Type) ?int {
	if t.kind == .array {
		if t.count < 0 || t.base == unsafe { nil } {
			return none
		}
		element := r.size_of(*t.base) or { return none }
		return element * t.count
	}
	if t.kind == .struct_ || t.kind == .union_ {
		lay := r.layout(t) or { return none }
		return lay.size
	}
	if t.kind == .enum_ {
		// An enumerated type has the representation of the integer type its
		// enumerators require, which is int, unsigned int, long or unsigned
		// long: measured, gcc 16.2.1 widens an enum whose enumerators do not
		// fit int, so the width is read from the underlying kind and not
		// fixed at int.
		return r.sizes[t.enum_underlying()] or { return none }
	}
	return r.sizes[t.kind] or { return none }
}

// align_of is the boundary a value of this type has to start on, and none when
// the description does not carry it.
pub fn (r Representation) align_of(t Type) ?int {
	if t.kind == .array {
		if t.base == unsafe { nil } {
			return none
		}
		return r.align_of(*t.base)
	}
	if t.kind == .struct_ || t.kind == .union_ {
		lay := r.layout(t) or { return none }
		return lay.align
	}
	if t.kind == .enum_ {
		return r.aligns[t.enum_underlying()] or { return none }
	}
	return r.aligns[t.kind] or { return none }
}

// layout answers where each member of an aggregate goes and how big the whole
// object is. The rules are the SysV x86-64 ones, and every case below is asserted
// against a measurement from gcc 16.2.1 in the tests beside this file.
//
// A member that is not a bitfield starts on the first byte boundary its alignment
// allows. A bitfield starts at the current bit position when its width fits
// inside the storage unit of its declared type that the position falls in, and at
// the next unit boundary when it does not; a bitfield of width 0 starts the next
// unit at the current position. The object's alignment is the largest alignment
// of its members, and its size is rounded up to that.
pub fn (r Representation) layout(t Type) ?Layout {
	if t.kind != .struct_ && t.kind != .union_ {
		size := r.size_of(t) or { return none }
		align := r.align_of(t) or { return none }
		return Layout{
			size:  size
			align: align
		}
	}
	if !t.is_complete() {
		// A tag that was declared and never defined has no members to lay out
		// and no size to round up, so there is no answer to give. Answering
		// zero would be a silent wrong size for a type nothing can size, and
		// it is the size `sizeof` reads: measured, gcc 16.2.1 refuses
		// `struct S; sizeof(struct S);` with `invalid application of 'sizeof'
		// to an incomplete type`, and this compiler laid it out as zero bytes
		// and emitted a program that exited 0.
		return none
	}
	if t.kind == .union_ {
		return r.union_layout(t)
	}
	mut offsets := []int{}
	mut bits := []int{}
	mut covered := []bool{}
	mut align := 1
	mut pos := 0
	for member in t.members {
		if member.promoted {
			// A promoted member is a view of a member of an unnamed struct or
			// union that is itself a member of this object (6.7.2.1p13). It
			// takes no room of its own - the unnamed member holds the bytes -
			// so the walk does not move, and its offset is where the unnamed
			// member sits plus the offset it was given inside it. The unnamed
			// member precedes it, so its own offset is already known.
			owner_layout := r.layout(t.members[member.owner].typ) or { return none }
			offsets << offsets[member.owner] + owner_layout.offsets[member.inner_index]
			bits << owner_layout.bits[member.inner_index]
			continue
		}
		member_align := r.align_of(member.typ) or { return none }
		member_size := r.member_size(member) or { return none }
		if member.bitfield {
			if !member.typ.is_integer() {
				// Only an integer type has a width to count bits in, so a
				// bitfield of anything else is not a layout this file can
				// answer.
				return none
			}
			unit := bits_in_a_byte * member_size
			if unit <= 0 {
				return none
			}
			if member.bits == 0 {
				pos = round_up(pos, unit)
				offsets << pos / bits_in_a_byte
				bits << 0
				align = larger(align, member_align)
				continue
			}
			if member.bits > unit {
				// A width wider than its own type is a declaration gcc refuses
				// (`width of 'a' exceeds its type`), and there is nothing to
				// lay out.
				return none
			}
			mut at := pos
			if (at % unit) + member.bits > unit {
				at = ((at / unit) + 1) * unit
			}
			// The unit is the aligned storage unit of the declared type the
			// position falls in, and the bit is the position inside it.
			offsets << (at - (at % unit)) / bits_in_a_byte
			bits << at % unit
			align = larger(align, member_align)
			cover(mut covered, at, member.bits)
			pos = at + member.bits
			continue
		}
		offset := round_up((pos + bits_in_a_byte - 1) / bits_in_a_byte, member_align)
		offsets << offset
		bits << -1
		align = larger(align, member_align)
		cover(mut covered, offset * bits_in_a_byte, member_size * bits_in_a_byte)
		pos = (offset + member_size) * bits_in_a_byte
	}
	size := round_up((pos + bits_in_a_byte - 1) / bits_in_a_byte, align)
	return Layout{
		size:    size
		align:   align
		offsets: offsets
		bits:    bits
		padding: size - covered_bytes(covered)
	}
}

// union_layout lays a union out: every member starts at the beginning of the
// object, the size is the largest member, and a bitfield takes the whole storage
// unit of its type. Measured: `union { unsigned a:1; }` is four bytes and
// `union { char a:1; }` is one, on gcc 16.2.1.
fn (r Representation) union_layout(t Type) ?Layout {
	mut offsets := []int{}
	mut bits := []int{}
	mut align := 1
	mut size := 0
	for member in t.members {
		if member.promoted {
			// A promoted member is a view of a member of an unnamed struct or
			// union inside this union (6.7.2.1p13). Every member of a union
			// starts at the beginning, so the unnamed member it came from does
			// too, and the offset is the one it was given inside it. It adds
			// nothing to the size or the alignment, which the unnamed member
			// already settles.
			owner_layout := r.layout(t.members[member.owner].typ) or { return none }
			offsets << owner_layout.offsets[member.inner_index]
			bits << owner_layout.bits[member.inner_index]
			continue
		}
		member_align := r.align_of(member.typ) or { return none }
		member_size := r.member_size(member) or { return none }
		if member.bitfield && !member.typ.is_integer() {
			return none
		}
		offsets << 0
		bits << if member.bitfield { 0 } else { -1 }
		align = larger(align, member_align)
		size = larger(size, member_size)
	}
	size = round_up(size, align)
	return Layout{
		size:    size
		align:   align
		offsets: offsets
		bits:    bits
		padding: 0
	}
}

// member_size is how many bytes a member takes in the layout. A member whose type
// is an array with no size written takes none: it is a flexible array member,
// which the standard says does not count in the size of the object it sits at the
// end of. Measured: `struct { int n; char data[]; }` is four bytes.
fn (r Representation) member_size(member Member) ?int {
	if member.typ.kind == .array && member.typ.count < 0 {
		return 0
	}
	return r.size_of(member.typ)
}

// Description is what a target description answered when it was asked for the
// object representation of the C types: the representation of the entries it
// carries, and the kinds it does not carry at all.
pub struct Description {
pub:
	representation Representation
	missing        []Kind
}

// from_target asks a target description for the object representation.
//
// Two entries are facts about the machine, and both of them are measured rather
// than read off the standard. The width and the alignment of a pointer are the
// width of the machine's general registers, which is what `codegen` already
// reads out of `word_size`. The width of an int and of an unsigned int is four
// bytes, which is what the back end writes a constant at: measured on this
// target with gcc 16.2.1, `sizeof(int)` and `sizeof(unsigned int)` are 4 with an
// alignment of 4, and `codegen`'s own `type_width` answers the same four bytes
// for `int`.
//
// The four 64-bit integer kinds are carried because the back end computes at
// eight bytes now, for the same reason the four-byte ones are: measured with
// `printf("%zu", sizeof(long))` on gcc 16.2.1, `long`, `unsigned long`,
// `long long` and `unsigned long long` are each 8 bytes with an alignment of 8
// on this target, and the emitter's 64-bit instructions move exactly those eight
// bytes. Measured before the 64-bit kinds were carried: `int main(void)
// { return 4294967295 > 2147483647; }` was read as an int comparison and returned
// 0 where ISO C and gcc return 1, which is why a width the description does not
// carry is refused by name rather than guessed at with the nearest one.
//
// The character types and `_Bool` are carried, and they left this table only when
// the back end could move a value of their width: a char and a `_Bool` live in one
// byte, and the emitter loads and stores each of them at that width. Before that
// they were missing for the same reason `long double` still is, that a width the
// back end cannot move is a width the model must not hand out.
//
// A double is carried for the same reason the int is: the back end has the
// instruction for it, so the model can answer a question about its width
// truthfully. Measured on this target with gcc 16.2.1, `sizeof(double)` is 8
// with an alignment of 8, and `codegen`'s `movsd` moves exactly those eight
// bytes.
//
// A float is carried for the same reason and with the same measurement behind
// it: `sizeof(float)` is 4 with an alignment of 4, and the emitter's
// single-precision instructions move those four bytes. A float is not a double
// of a smaller width: `0.1f` and `0.1` are different values, which is why the
// model has to hand out four bytes for one. `long double` stays out because the
// back end emits none of it, and a width it cannot move is a width the model
// must not hand out.
pub fn from_target(target backend.Target) Description {
	mut sizes := map[Kind]int{}
	mut aligns := map[Kind]int{}
	sizes[Kind.pointer] = target.word_size
	aligns[Kind.pointer] = target.word_size
	// The width every integer constant is written at, and the unsigned reading
	// of the same four bytes: `4294967295U` is an unsigned int whose value the
	// back end holds at that width.
	//
	// The character types and `_Bool` are one byte, which the back end moves now:
	// it loads and stores a one-byte value with the instructions a char needs,
	// and a read of one widens it to the int the promotion makes it. The width is
	// asked for by the layout of an aggregate with a member of one of those
	// types, where a member's width decides the offset of the member after it.
	// Measured on this target with gcc 16.2.1: `sizeof(_Bool)`, `sizeof(char)`,
	// `sizeof(signed char)` and `sizeof(unsigned char)` are each 1 with an
	// alignment of 1.
	sizes[Kind.bool_] = 1
	aligns[Kind.bool_] = 1
	sizes[Kind.char_] = 1
	aligns[Kind.char_] = 1
	// The character types whose spelling carries the sign, and the two-byte
	// integers. Measured on this target with gcc 16.2.1: `signed char` and
	// `unsigned char` are each 1 byte with an alignment of 1, and `short` and
	// `unsigned short` are each 2 bytes with an alignment of 2. The machine moves
	// a value of either width and a read of one widens it to the int the promotion
	// makes it, so these widths are what the layout of an aggregate with such a
	// member and the promotion of an `unsigned short` are asked for from here.
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
	// The four 64-bit integer kinds. Measured on this target with gcc 16.2.1:
	// each is 8 bytes with an alignment of 8, which is the width the emitter's
	// 64-bit instructions move. `unsigned` and `unsigned int` are one kind, so
	// `unsigned` is answered above.
	sizes[Kind.long] = 8
	aligns[Kind.long] = 8
	sizes[Kind.unsigned_long] = 8
	aligns[Kind.unsigned_long] = 8
	sizes[Kind.long_long] = 8
	aligns[Kind.long_long] = 8
	sizes[Kind.unsigned_long_long] = 8
	aligns[Kind.unsigned_long_long] = 8
	// A float is four bytes with an alignment of four, measured on gcc 16.2.1
	// on this target, which is the width the emitter's single-precision
	// instructions move.
	sizes[Kind.float] = 4
	aligns[Kind.float] = 4
	sizes[Kind.double] = 8
	aligns[Kind.double] = 8
	// A long double is the x87 extended format: sixteen bytes of storage with an
	// alignment of sixteen, holding one 80-bit value in the low ten bytes.
	// Measured on this target with gcc 16.2.1: `sizeof(long double)` is 16 and
	// `_Alignof(long double)` is 16. The width is carried because the back end
	// moves those sixteen bytes: an object of the type is reserved, stored and
	// copied as an object, and the value's own read and write go through the
	// x87 stack, which is what the conversions at the end of this file describe.
	sizes[Kind.long_double] = 16
	aligns[Kind.long_double] = 16
	// A complex type is two components of its real type, one after the other:
	// `float _Complex` is two floats and `double _Complex` is two doubles.
	// Measured on this target with gcc 16.2.1 on a program that printed
	// `sizeof` and `_Alignof`, `sizeof(float _Complex)` is 8 with an alignment
	// of 4, `sizeof(double _Complex)` is 16 with an alignment of 8, and
	// `sizeof(long double _Complex)` is 32 with an alignment of 16. The two
	// widths the back end moves are carried; `long double _Complex` is carried
	// for the questions about its size and layout, because a member of it
	// decides where the member after it starts, and an object of it is refused
	// by name where the back end is asked for a value, since it has no value of
	// a `long double` either.
	sizes[Kind.complex_float] = 8
	aligns[Kind.complex_float] = 4
	sizes[Kind.complex_double] = 16
	aligns[Kind.complex_double] = 8
	sizes[Kind.complex_long_double] = 32
	aligns[Kind.complex_long_double] = 16
	// The 128-bit integers are carried for the questions that are about the
	// size of a type rather than about a value of one: `sizeof(__int128)` is
	// 16, a member of that type starts on a 16-byte boundary, and a struct
	// holding one is laid out around those two numbers. Measured on gcc 16.2.1
	// on this target. The back end has no value of that width, and a
	// declaration of an object of one is refused by its spelling rather than by
	// a width this table gave out: the width here decides a layout, which is a
	// question the model answers, and never a value, which is the emitter's.
	sizes[Kind.int128] = 16
	aligns[Kind.int128] = 16
	sizes[Kind.unsigned_int128] = 16
	aligns[Kind.unsigned_int128] = 16
	mut missing := []Kind{}
	for kind in basic_kinds() {
		if kind !in sizes {
			missing << kind
		}
	}
	return Description{
		representation: Representation{
			sizes:  sizes
			aligns: aligns
		}
		missing:        missing
	}
}

// round_up is the next multiple of alignment at or after value.
fn round_up(value int, alignment int) int {
	if alignment <= 1 {
		return value
	}
	return ((value + alignment - 1) / alignment) * alignment
}

fn larger(a int, b int) int {
	return if a > b { a } else { b }
}

// cover marks the bytes a value of width bits starting at bit occupies, so that
// padding can be counted at the end. A width of 0 marks nothing.
fn cover(mut marked []bool, bit int, width int) {
	if width <= 0 {
		return
	}
	last := (bit + width - 1) / bits_in_a_byte
	for index := bit / bits_in_a_byte; index <= last; index++ {
		for marked.len <= index {
			marked << false
		}
		marked[index] = true
	}
}

fn covered_bytes(marked []bool) int {
	mut count := 0
	for byte in marked {
		if byte {
			count++
		}
	}
	return count
}
