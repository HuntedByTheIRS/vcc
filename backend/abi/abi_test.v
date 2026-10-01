module abi

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
