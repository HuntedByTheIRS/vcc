module abi

import backend
import types

// The third axis of a target, beside the machine and the system: not how an
// instruction is encoded and not what the kernel gives, but which register a value
// of a given type travels in. What a caller has to put somewhere and what a callee
// has to look for it in is one agreement, and this module is where it is written.

// Class is how an object of an aggregate type is handed over by value on a machine.
// The convention splits an object into eightbytes of eight bytes each and gives
// every one of them a class, which is the register file that carries it, so an
// object of sixteen bytes or fewer is one or two registers and nothing else has to
// be known about it.
//
// bytes is the size of the object, and zero for anything that is not an object of
// an aggregate type, which is handed over as a value of its own width. count is how
// many eightbytes the object was split into, and is three or more for an object
// larger than two of them, which is the case this compiler does not hand over.
// first_floating and second_floating say which file carries each of the first two
// eightbytes: the floating-point one when every member the eightbyte covers is a
// double, and the general one otherwise.
pub struct Class {
pub:
	bytes           int
	count           int
	first_floating  bool
	second_floating bool
}

// class_of is how an object of an aggregate type is handed over by value on the
// machine `r` describes, and zero for anything else.
//
// The description is a parameter and not something this file looks up, because the
// answer is a fact about the machine and the answer for one machine is wrong for
// another: a rule that read a description for itself could only ever read one of
// them. An object larger than two eightbytes answers with its size and its count so
// that a refusal can name how large it is, because that object is a copy in memory
// and no register carries it.
pub fn class_of(r types.Representation, declared types.Type) Class {
	if declared.kind !in [types.Kind.struct_, .union_] {
		return Class{}
	}
	bytes := object_bytes(r, declared)
	if bytes == 0 {
		return Class{}
	}
	count := (bytes + 7) / 8
	return Class{
		bytes:           bytes
		count:           count
		first_floating:  eightbyte_is_floating(r, declared, 0)
		second_floating: count == 2 && eightbyte_is_floating(r, declared, 1)
	}
}

// PairPlaces is where the two eightbytes of an object of two of them go, and it is
// the one answer a caller and a callee both have to reach, because an object the
// caller puts in a register and the callee expects in memory arrives as whatever
// happened to be in the register.
//
// The convention places an object of two eightbytes in registers when both of them
// have a register of their own class left, and in memory when either one does not:
// the object is not split between the two. registers is false in that second case,
// and then the object is two words on the stack, first eightbyte at the lower
// address.
pub struct PairPlaces {
pub:
	first     int
	second    int
	integers  int
	doubles   int
	registers bool
}

// pair_places answers where an object of two eightbytes goes when `integers` and
// `doubles` registers of each sequence are used already, and whether it fits at all.
//
// The caller placing an argument and the callee reading one both ask this, and they
// have to reach the same answer: a caller that reached one and a callee that reached
// the other would read words from somewhere the caller never wrote. It is here for
// that reason, because the rule is the convention's and belongs beside the class that
// feeds it, and not inside either side of the call.
pub fn pair_places(target backend.Target, first_floating bool, second_floating bool, integers int, doubles int) PairPlaces {
	// How far each sequence moves for the first eightbyte, and for the second one
	// on top of that: an object of two eightbytes takes a register per eightbyte
	// from the sequence that eightbyte's class names, so two general eightbytes
	// take two general registers and a mixed pair takes one of each.
	first_integer := if first_floating { 0 } else { 1 }
	first_double := if first_floating { 1 } else { 0 }
	second_integer := first_integer + (if second_floating { 0 } else { 1 })
	second_double := first_double + (if second_floating { 1 } else { 0 })
	mut fits := true
	if first_floating {
		if target.float_arg_reg(doubles) == none {
			fits = false
		}
	} else if target.arg_reg(integers) == none {
		fits = false
	}
	if second_floating {
		if target.float_arg_reg(doubles + first_double) == none {
			fits = false
		}
	} else if target.arg_reg(integers + first_integer) == none {
		fits = false
	}
	return PairPlaces{
		first:     if first_floating { doubles } else { integers }
		second:    if second_floating { doubles + first_double } else { integers + first_integer }
		integers:  integers + second_integer
		doubles:   doubles + second_double
		registers: fits
	}
}

// object_bytes is how many bytes of storage an object of this type takes, and zero
// for a type that is not an object of an aggregate type or whose layout the
// description cannot give. It is not the same question as the size a declaration
// takes in a frame, which is asked by the parser, because a question about the
// calling convention is only ever asked about an object that is handed over.
fn object_bytes(r types.Representation, declared types.Type) int {
	if declared.kind !in [types.Kind.struct_, .union_] || !declared.is_complete() {
		return 0
	}
	layout := r.layout(declared) or { return 0 }
	return layout.size
}

// EightbyteCover is what a byte range of an object covers: whether a member of the
// object has bytes in the range at all, and whether a member in it is anything but
// a double.
struct EightbyteCover {
mut:
	covered bool
	other   bool
}

// eightbyte_is_floating says whether a register of the floating-point file carries
// the eightbyte that starts at `which` eightbytes into an object: every member that
// eightbyte covers is a double, and a member covers it.
//
// An eightbyte carrying a member that is not a double is carried by the general
// file, which is what the convention says for an eightbyte that is both; so is an
// eightbyte no member covers, because the padding bytes in it are not a double and
// a register of the general file carries anything this compiler lays out.
fn eightbyte_is_floating(r types.Representation, declared types.Type, which int) bool {
	mut cover := EightbyteCover{}
	note_eightbyte(r, declared, 0, which * 8, which * 8 + 8, mut cover)
	return cover.covered && !cover.other
}

// note_eightbyte marks what a byte range of an object covers. A member that is
// itself an object of an aggregate type is walked into, because the range carries
// the members at the bottom of the layout and not the object that holds them; an
// element of an array likewise, one element at a time.
fn note_eightbyte(r types.Representation, declared types.Type, base int, low int, high int, mut cover EightbyteCover) {
	layout := r.layout(declared) or { return }
	for i, member in declared.members {
		if i >= layout.offsets.len {
			break
		}
		note_member(r, member.typ, base + layout.offsets[i], low, high, mut cover)
	}
}

// note_member marks what the bytes of one member cover, given where the member
// starts. A member whose bytes lie entirely outside the range covers nothing in it,
// and a member that lies across a boundary covers both eightbytes it lies in, which
// is how a double that straddled one would be classified and how an object of an
// aggregate type is.
fn note_member(r types.Representation, typ types.Type, start int, low int, high int, mut cover EightbyteCover) {
	size := r.size_of(typ) or { return }
	if size <= 0 || start + size <= low || start >= high {
		return
	}
	if typ.kind in [types.Kind.struct_, .union_] {
		note_eightbyte(r, typ, start, low, high, mut cover)
		return
	}
	if typ.kind == .array {
		element := typ.element() or { return }
		element_size := r.size_of(element) or { return }
		if element_size <= 0 {
			return
		}
		mut at := start
		for at < start + size {
			note_member(r, element, at, low, high, mut cover)
			at += element_size
		}
		return
	}
	cover.covered = true
	if typ.kind != .double {
		cover.other = true
	}
}
