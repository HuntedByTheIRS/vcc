module abi

import backend
import types.measured
import types

// The classifier against the measured table, which is what gcc 16.2.1 reports on
// this machine rather than a copy of what the classifier happens to do. The machine
// is a parameter, so the answers below are one machine's answers; the last test is
// the one that says so.

fn member(name string, typ types.Type) types.Member {
	return types.Member{
		name: name
		typ:  typ
	}
}

// class is the answer for the machine the measured table describes.
fn class(declared types.Type) Class {
	return class_of(measured.representation(), declared)
}

// Bytes are asserted alongside the classes because the refusal for an object no
// register carries has to name how large it was.
fn test_a_scalar_is_not_an_object_this_convention_covers() {
	for scalar in [types.int_type(), types.double_type(), types.pointer_to(types.int_type())] {
		answer := class(scalar)
		assert answer.bytes == 0
		assert answer.count == 0
		assert !answer.first_floating
		assert !answer.second_floating
	}
}

fn test_two_doubles_are_two_floating_registers() {
	answer := class(types.struct_type('two_doubles', [
		member('a', types.double_type()),
		member('b', types.double_type()),
	]))
	assert answer.bytes == 16
	assert answer.count == 2
	assert answer.first_floating
	assert answer.second_floating
}

// The eightbyte is classified by what it covers, not by what the object is called:
// an int in the first one makes it the general file's.
fn test_an_int_and_a_double_are_one_general_register_and_one_floating_one() {
	answer := class(types.struct_type('int_then_double', [
		member('a', types.int_type()),
		member('b', types.double_type()),
	]))
	assert answer.bytes == 16
	assert answer.count == 2
	assert !answer.first_floating
	assert answer.second_floating
}

// A double followed by a char is not two floating registers: the second eightbyte
// carries the char, which is not a double, so the general file carries it.
fn test_a_double_and_a_char_are_not_both_floating() {
	answer := class(types.struct_type('double_then_char', [
		member('a', types.double_type()),
		member('b', types.char_type()),
	]))
	assert answer.bytes == 16
	assert answer.count == 2
	assert answer.first_floating
	assert !answer.second_floating
}

// An eightbyte no member covers is the general file's, because the padding in it is
// not a double. `struct { double a; }` is eight bytes and the padding is not reached;
// a struct of twelve is where it shows.
fn test_an_object_of_three_eightbytes_says_how_large_it_is() {
	answer := class(types.struct_type('three_doubles', [
		member('a', types.double_type()),
		member('b', types.double_type()),
		member('c', types.double_type()),
	]))
	assert answer.bytes == 24
	assert answer.count == 3
	assert answer.first_floating
	// Nothing past the second eightbyte is handed over in a register, so the second
	// class is only answered for an object of exactly two of them. An object this
	// large is a copy in memory and this is the size the refusal names.
	assert !answer.second_floating
}

fn test_a_nested_object_is_classified_by_the_members_at_the_bottom_of_it() {
	inner := types.struct_type('inner', [
		member('a', types.double_type()),
		member('b', types.double_type()),
	])
	answer := class(types.struct_type('outer', [member('i', inner)]))
	assert answer.bytes == 16
	assert answer.count == 2
	assert answer.first_floating
	assert answer.second_floating
}

fn test_an_array_member_is_walked_one_element_at_a_time() {
	answer := class(types.struct_type('array_of_two_doubles', [
		member('a', types.array_of(types.double_type(), 2)),
	]))
	assert answer.bytes == 16
	assert answer.count == 2
	assert answer.first_floating
	assert answer.second_floating
}

// The description is the parameter, so a description that carries nothing answers
// nothing rather than answering for the machine this binary was built on. That is
// the difference between a classifier that takes a target and one that reads one.
fn test_a_description_that_carries_nothing_answers_nothing() {
	answer := class_of(types.Representation{}, types.struct_type('two_doubles', [
		member('a', types.double_type()),
		member('b', types.double_type()),
	]))
	assert answer.bytes == 0
	assert answer.count == 0
	assert !answer.first_floating
	assert !answer.second_floating
}

// pair_places is the one answer a caller and a callee both have to reach, so the two
// sequences are checked apart: two general eightbytes take two registers of the
// general file, two floating ones take two of the floating file, and a mixed object
// takes one of each. The positions are what a caller that has already placed two
// general arguments would get, which is why the cursors are not both zero.
fn test_a_pair_of_eightbytes_takes_a_register_of_each_its_classes_name() {
	target := backend.host() or { panic('this test needs the host target') }
	general := pair_places(target, false, false, 2, 0)
	assert general.first == 2
	assert general.second == 3
	assert general.integers == 4
	assert general.doubles == 0
	assert general.registers

	floating := pair_places(target, true, true, 2, 1)
	assert floating.first == 1
	assert floating.second == 2
	assert floating.integers == 2
	assert floating.doubles == 3
	assert floating.registers

	mixed := pair_places(target, true, false, 2, 1)
	assert mixed.first == 1
	assert mixed.second == 2
	assert mixed.integers == 3
	assert mixed.doubles == 2
	assert mixed.registers
}

// An object whose second eightbyte has no register of its class left is two words on
// the stack whole, and the answer says so rather than splitting it between a register
// and a word of memory: a caller that split one and a callee that did not would read
// a word from somewhere the caller never wrote.
fn test_a_pair_that_does_not_fit_is_not_split() {
	target := backend.host() or { panic('this test needs the host target') }
	// The last general register carries the first eightbyte and the sequence is spent.
	late := pair_places(target, false, false, 5, 0)
	assert !late.registers
	spent := pair_places(target, true, true, 0, 7)
	assert !spent.registers
}

// The save area and the argument list, against the layout the model gives the
// type the header names. The numbers the emitter reads are the ones this file
// states, and the type a header's `__builtin_va_list` resolves to is built from
// the same description; this test is what keeps the two from drifting apart.

fn test_the_argument_list_offsets_agree_with_the_type() {
	list := argument_list()
	layout := measured.representation().layout(argument_list_tag()) or {
		assert false
		return
	}
	assert layout.offsets.len == 4
	assert layout.offsets[0] == list.gp_offset_at
	assert layout.offsets[1] == list.fp_offset_at
	assert layout.offsets[2] == list.overflow_at
	assert layout.offsets[3] == list.area_at
	assert layout.size == list.bytes
}

fn test_a_named_parameter_moves_the_start_of_a_walk() {
	area := register_area()
	// Nothing named: both walks start at the front of their own file.
	assert gp_start(0) == area.gp_at
	assert fp_start(0) == area.fp_at
	// The second general parameter starts the walk one word in; the second
	// vector parameter starts it one register in, which is sixteen bytes.
	assert gp_start(2) == area.gp_at + 2 * area.gp_stride
	assert fp_start(2) == area.fp_at + 2 * area.fp_stride
}

// A function with as many named parameters as the machine has registers has
// none left for the unnamed ones, and the walk starts at the limit so that every
// one of them is read from the overflow area.
fn test_a_walk_with_no_registers_left_reads_memory() {
	assert gp_start(general_argument_registers) == gp_limit()
	assert gp_start(general_argument_registers + 3) == gp_limit()
	assert fp_start(vector_argument_registers) == fp_limit()
}

// The two limits are measured, not derived from a taste: gcc 16.2.1 on this
// machine writes six general registers and eight vector ones, which is 48 bytes
// of general registers followed by 128 bytes of vector ones, and the save area
// is 176 bytes.
fn test_the_limits_are_the_ones_the_convention_gives() {
	area := register_area()
	assert gp_limit() == 48
	assert fp_limit() == 176
	assert area.bytes == 176
	assert area.fp_at == 48
}

// A header writes `typedef __builtin_va_list __gnuc_va_list;` and the reader
// sizes a declaration from the spelling, which is the resolved type written
// out. A pointer spelling is what makes a `va_list` one word in a frame.
fn test_the_argument_list_type_is_a_pointer() {
	spelling := argument_list_type().describe()
	assert spelling.contains('*')
	assert spelling.contains('__va_list_tag')
}
