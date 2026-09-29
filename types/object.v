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
		// An enumerated type has the representation of int on this target.
		// Measured: gcc 16.2.1 gives every enum, with negative enumerators or
		// with one above INT_MAX, a size of 4 bytes and an alignment of 4.
		return r.sizes[Kind.int_] or { return none }
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
		return r.aligns[Kind.int_] or { return none }
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
	if t.kind == .union_ {
		return r.union_layout(t)
	}
	mut offsets := []int{}
	mut bits := []int{}
	mut covered := []bool{}
	mut align := 1
	mut pos := 0
	for member in t.members {
		member_align := r.align_of(member.typ) or { return none }
		member_size := r.member_size(member) or { return none }
		if member.bitfield {
			if !member.typ.is_integer() {
				// Only an integer type has a width to count bits in, so a
				// bitfield of anything else is not a layout this file can
				// answer.
				return none
			}
			unit := 8 * member_size
			if unit <= 0 {
				return none
			}
			if member.bits == 0 {
				pos = round_up(pos, unit)
				offsets << pos / 8
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
			offsets << (at - (at % unit)) / 8
			bits << at % unit
			align = larger(align, member_align)
			cover(mut covered, at, member.bits)
			pos = at + member.bits
			continue
		}
		offset := round_up((pos + 7) / 8, member_align)
		offsets << offset
		bits << -1
		align = larger(align, member_align)
		cover(mut covered, offset * 8, member_size * 8)
		pos = (offset + member_size) * 8
	}
	size := round_up((pos + 7) / 8, align)
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
// One entry is a fact the description carries today: the width of the machine's
// general registers, which is what `codegen` already reads out of `word_size` for
// the width of a pointer and is the width of an address. Everything else the C
// types need, the width and the alignment of each integer and floating kind, is
// not in the description yet, so those kinds are named in `missing` and no number
// stands in for them.
//
// A pointer's alignment is taken to be its width because the machine's registers
// are the unit an address is held in, which is the reading measured on this
// target: gcc 16.2.1 reports `void *` as 8 bytes and alignment 8.
pub fn from_target(target backend.Target) Description {
	mut sizes := map[Kind]int{}
	mut aligns := map[Kind]int{}
	sizes[Kind.pointer] = target.word_size
	aligns[Kind.pointer] = target.word_size
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
	last := (bit + width - 1) / 8
	for index := bit / 8; index <= last; index++ {
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
