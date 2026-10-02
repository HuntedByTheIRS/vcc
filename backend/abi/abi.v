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

// ---- variadic arguments ----

// The convention passes an argument in a register until the file it belongs to
// runs out and on the stack after that. These are the counts for the machine
// this file describes: six general argument registers and eight vector ones,
// each vector register sixteen bytes because that is the width of the register
// and a double sits in the low half of one.
//
// They are constants rather than a table read off a target, because the numbers
// below have to be known while the numbers are being computed and a machine
// whose counts differed would be a machine with its own copy of this section.
const general_argument_registers = 6
const vector_argument_registers = 8
const one_word = 8
const one_vector = 16

// RegisterArea is the entry save area a variadic callee writes its argument
// registers into, and the numbers a walk through the arguments reads out of it.
//
// A variadic callee cannot know which arguments arrived in registers and which
// on the stack, so its prologue writes every argument register it may have been
// given into a save area in its own frame, and `va_start` points the argument
// list at that area. Where each file of registers starts, how far apart two
// registers of one file sit, and how many of them there are is a fact about the
// machine, which is why it lives here and not in the emitter.
//
// The general registers come first, one machine word each, and the vector
// registers follow, sixteen bytes each: the convention lays the area out that
// way, and every offset a walk computes is an offset into this one area.
pub struct RegisterArea {
pub:
	// gp_at is where the first general argument register is written, and
	// gp_stride how far after it the second one is.
	gp_at     int
	gp_stride int
	gp_count  int
	// fp_at is where the first vector register is written, and fp_stride the
	// distance to the next one. It is not a multiple of the register file's
	// start by accident: the general registers are written in front of it.
	fp_at     int
	fp_stride int
	fp_count  int
	// bytes is how much room the whole area takes in the frame.
	bytes int
}

// register_area is the save area of this convention.
pub fn register_area() RegisterArea {
	gp_stride := one_word
	fp_stride := one_vector
	fp_at := general_argument_registers * gp_stride
	return RegisterArea{
		gp_at:     0
		gp_stride: gp_stride
		gp_count:  general_argument_registers
		fp_at:     fp_at
		fp_stride: fp_stride
		fp_count:  vector_argument_registers
		bytes:     fp_at + vector_argument_registers * fp_stride
	}
}

// ArgumentList is the tag an argument list points at: where a walk through the
// unnamed arguments has got to in each file of registers, where the arguments
// that did not fit in a register start, and where the save area was written.
//
// The four fields are the convention's, in the order and at the offsets it
// gives them: two four-byte counters and two addresses, which is twenty-four
// bytes in all. `argument_list_type` builds the C type from this description and
// `argument_list_offsets_agree_with_the_type` is the test that keeps the two
// from drifting apart.
pub struct ArgumentList {
pub:
	gp_offset_at int
	fp_offset_at int
	overflow_at  int
	area_at      int
	bytes        int
}

// argument_list is the tag's layout on this convention.
pub fn argument_list() ArgumentList {
	return ArgumentList{
		gp_offset_at: 0
		fp_offset_at: 4
		overflow_at:  8
		area_at:      16
		bytes:        24
	}
}

// gp_start is where a walk through the general arguments begins for a function
// with `named` general parameters before the ellipsis. Those parameters arrived
// in the first registers of the file, so the walk starts after them; a function
// with more named parameters than the machine has registers has none of them
// left, and the walk starts at the limit, which sends every general argument to
// the overflow area.
pub fn gp_start(named int) int {
	area := register_area()
	if named >= area.gp_count {
		return gp_limit()
	}
	return area.gp_at + named * area.gp_stride
}

// fp_start is the same number for the vector file.
pub fn fp_start(named int) int {
	area := register_area()
	if named >= area.fp_count {
		return fp_limit()
	}
	return area.fp_at + named * area.fp_stride
}

// gp_limit and fp_limit are the offsets a walk compares its own cursor against:
// below the limit the next argument of that file is in the save area, and at it
// there are no registers left and the argument is in the overflow area.
pub fn gp_limit() int {
	area := register_area()
	return area.gp_at + area.gp_count * area.gp_stride
}

pub fn fp_limit() int {
	area := register_area()
	return area.fp_at + area.fp_count * area.fp_stride
}

// argument_list_type is the C type a header's `__builtin_va_list` names: a
// pointer to the tag above.
//
// The standard's `va_list` is an array of one tag, so that passing one to a
// function passes the address of the tag rather than a copy of it. This compiler
// keeps the address itself as the type, because that is the value every use of
// it wants: `va_start` writes through it, `va_arg` reads and steps it, and a
// `va_list` handed to a library function arrives as the pointer that function
// expects. The member types are the convention's four fields, and the test
// beside this file asserts that the model lays them out at the offsets above
// rather than trusting the two to agree.
pub fn argument_list_type() types.Type {
	members := [
		types.Member{
			name: 'gp_offset'
			typ:  types.unsigned_int_type()
		},
		types.Member{
			name: 'fp_offset'
			typ:  types.unsigned_int_type()
		},
		types.Member{
			name: 'overflow_arg_area'
			typ:  types.pointer_to(types.void_type())
		},
		types.Member{
			name: 'reg_save_area'
			typ:  types.pointer_to(types.void_type())
		},
	]
	return types.pointer_to(types.struct_type('__va_list_tag', members))
}

// is_argument_list says whether a type is an argument list. An object of that
// type is what the four operations over a list are applied to, and an object of
// any other type is not one: reading a walk out of it would read whatever the
// object holds as though it were a tag.
pub fn is_argument_list(typ types.Type) bool {
	// The question is structural and not an identity: the model holds a type as
	// a reference to its pointee, so two readings of one argument list are two
	// values with one shape, and `same` is the model's question for that.
	return typ.same(argument_list_type())
}

// argument_list_tag is the tag `argument_list_type` points at, which a caller
// that wants the type itself rather than an argument list of it asks for.
pub fn argument_list_tag() types.Type {
	if pointee := argument_list_type().pointee() {
		return pointee
	}
	return types.Type{}
}
