module types

import measured

// The type of an integer constant, measured with gcc 16.2.1 rather than read off
// the table in the standard. The program below prints, for each spelling, which
// of the six candidate types gcc gives it: `__builtin_types_compatible_p` on
// `__typeof__` of each literal, compiled with -std=c99 and run on this machine.
//
//	0 42 32767 32768 2147483647 077777 0777777 0x7fffffff        int
//	2147483648 4294967295 4294967296 0x100000000                 long
//	0x80000000 0xffffffff                                        unsigned int
//	42u 42U 4294967295u                                          unsigned int
//	42l 42L                                                      long
//	42ul 42lu 0xfffffffful                                       unsigned long
//	42ll 42LL                                                    long long
//	42ull 42ULL                                 unsigned long long
//
// The values in the test are the ones those literals have, so a reader can see
// which of them the widths decide and which of them the standard settles.

fn constant_type(text string, value i64) string {
	rep := measured.representation()
	typ := integer_constant_type(text, value, rep) or { return 'refused: ${err.msg()}' }
	return typ.describe()
}

fn test_a_value_every_int_holds_is_an_int_without_asking_the_widths() {
	partial := measured.partial()
	// The standard requires int to hold -32767 to 32767 on every machine, so
	// these three answers need no width at all and hold even for a description
	// that carries nothing but a pointer.
	plain := Representation{}
	assert integer_constant_type('0', 0, plain) or { Type{} }.same(int_type())
	assert integer_constant_type('42', 42, plain) or { Type{} }.same(int_type())
	assert integer_constant_type('32767', 32767, plain) or { Type{} }.same(int_type())
	assert integer_constant_type('077777', 32767, plain) or { Type{} }.same(int_type())
	assert constant_type('32768', 32768) == 'int'
	assert constant_type('0777777', 262143) == 'int'
}

fn test_the_base_of_a_constant_decides_whether_an_unsigned_type_may_hold_it() {
	// 2147483648 does not fit in an int, and written in decimal it goes to a
	// long; written in hexadecimal the same value is an unsigned int.
	assert constant_type('2147483648', 2147483648) == 'long'
	assert constant_type('0x80000000', 2147483648) == 'unsigned int'
	assert constant_type('0xffffffff', 4294967295) == 'unsigned int'
	assert constant_type('4294967295', 4294967295) == 'long'
	assert constant_type('4294967296', 4294967296) == 'long'
	assert constant_type('0x100000000', 4294967296) == 'long'
	assert constant_type('2147483647', 2147483647) == 'int'
	assert constant_type('0x7fffffff', 2147483647) == 'int'
}

fn test_a_suffix_names_the_types_that_may_be_considered() {
	assert constant_type('42u', 42) == 'unsigned int'
	assert constant_type('42U', 42) == 'unsigned int'
	assert constant_type('4294967295u', 4294967295) == 'unsigned int'
	assert constant_type('42l', 42) == 'long'
	assert constant_type('42L', 42) == 'long'
	assert constant_type('42ul', 42) == 'unsigned long'
	assert constant_type('42lu', 42) == 'unsigned long'
	assert constant_type('0xfffffffful', 4294967295) == 'unsigned long'
	assert constant_type('42ll', 42) == 'long long'
	assert constant_type('42LL', 42) == 'long long'
	assert constant_type('42ull', 42) == 'unsigned long long'
	assert constant_type('42ULL', 42) == 'unsigned long long'
}

fn test_a_width_the_description_does_not_carry_is_refused_rather_than_guessed() {
	// A value every int holds still answers, because the standard settles it and
	// no width is needed.
	assert integer_constant_type('42', 42, measured.partial()) or { Type{} }.same(int_type())
	// 2147483647 is past the range every int is required to have, so the widths
	// decide it and the description has no answer: the refusal names the fact
	// that is missing instead of guessing a type.
	mut named := false
	refused := integer_constant_type('2147483647', 2147483647, measured.partial()) or {
		named = err.msg().contains('widths') && err.msg().contains('int')
		Type{}
	}
	assert named
	assert refused.kind == .unknown
}
