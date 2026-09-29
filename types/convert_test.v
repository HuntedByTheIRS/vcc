module types

import measured

// One assertion per rule of clause 6.3 that this milestone implements.
//
// The arithmetic cases are measured rather than read off the standard: the
// program below prints the type gcc 16.2.1 gives each sum, and every pair asserted
// here is a line of its output.
//
//   gcc -std=c99 -o measure measure.c && ./measure
//   char + char -> int
//   char + int -> int
//   char + unsigned -> unsigned int
//   short + short -> int
//   short + unsigned -> unsigned int
//   int + unsigned -> unsigned int
//   int + long -> long
//   unsigned + long -> long
//   unsigned + unsigned long -> unsigned long
//   long + unsigned long -> unsigned long
//   long + long long -> long long
//   long long + unsigned long long -> unsigned long long
//   float + int -> float
//   float + double -> double
//   double + long double -> long double
//   _Bool + _Bool -> int
//   _Bool + int -> int

fn promote(t Type) string {
	return integer_promotion(t, measured.representation()) or { return 'refused: ${err.msg()}' }.describe()
}

fn sum(a Type, b Type) string {
	return usual_arithmetic_conversions(a, b, measured.representation()) or {
		return 'refused: ${err.msg()}'
	}.describe()
}

// reason is the diagnostic an assignment would produce, and empty when the
// standard allows it.
fn reason(to Type, from Type, constant_zero bool) string {
	return assignment_problem(to, from, constant_zero) or { return '' }
}

// only_reason says whether the reason an assignment produces is the one this
// case from the measurement file produced.
fn only_reason(to Type, from Type, constant_zero bool, needle string) bool {
	return reason(to, from, constant_zero).contains(needle)
}

fn test_the_integer_promotions_of_6_3_1_1() {
	assert promote(bool_type()) == 'int'
	assert promote(char_type()) == 'int'
	assert promote(signed_char_type()) == 'int'
	assert promote(unsigned_char_type()) == 'int'
	assert promote(short_type()) == 'int'
	assert promote(unsigned_short_type()) == 'int'
	assert promote(enum_type('E')) == 'int'
	// The types that are already at least int rank keep their own type.
	assert promote(int_type()) == 'int'
	assert promote(unsigned_int_type()) == 'unsigned int'
	assert promote(long_type()) == 'long'
	assert promote(unsigned_long_long_type()) == 'unsigned long long'
	// A type that is not an integer promotes to itself, which is what makes the
	// promotion safe to ask of any operand of an arithmetic expression.
	assert promote(float_type()) == 'float'
	assert promote(double_type()) == 'double'
	assert promote(pointer_to(char_type())) == 'char *'
}

// Whether an int can hold every unsigned short value is the one promotion that is
// a width question, so a description that does not carry the widths gets a
// refusal that names what it would have to carry.
fn test_the_unsigned_short_promotion_is_decided_by_the_widths() {
	assert promote(unsigned_short_type()) == 'int'
	refused := integer_promotion(unsigned_short_type(), measured.partial()) or {
		assert err.msg().contains('unsigned short')
		assert err.msg().contains('width of int')
		return
	}
	assert refused.kind == .unknown
}

// Every line of the measured table above, one assertion each.
fn test_the_usual_arithmetic_conversions_of_6_3_1_8() {
	assert sum(char_type(), char_type()) == 'int'
	assert sum(char_type(), int_type()) == 'int'
	assert sum(char_type(), unsigned_int_type()) == 'unsigned int'
	assert sum(short_type(), short_type()) == 'int'
	assert sum(short_type(), unsigned_int_type()) == 'unsigned int'
	assert sum(int_type(), unsigned_int_type()) == 'unsigned int'
	assert sum(int_type(), long_type()) == 'long'
	// The one the widths decide: a long holds every unsigned int value, so the
	// conversion lands on long and not on unsigned int.
	assert sum(unsigned_int_type(), long_type()) == 'long'
	assert sum(unsigned_int_type(), unsigned_long_type()) == 'unsigned long'
	assert sum(long_type(), unsigned_long_type()) == 'unsigned long'
	assert sum(long_type(), long_long_type()) == 'long long'
	assert sum(long_long_type(), unsigned_long_long_type()) == 'unsigned long long'
	assert sum(float_type(), int_type()) == 'float'
	assert sum(float_type(), double_type()) == 'double'
	assert sum(double_type(), long_double_type()) == 'long double'
	assert sum(bool_type(), bool_type()) == 'int'
	assert sum(bool_type(), int_type()) == 'int'
	// The order of the operands does not change the answer.
	assert sum(long_type(), unsigned_int_type()) == 'long'
	assert sum(unsigned_long_type(), long_type()) == 'unsigned long'
	assert sum(long_double_type(), char_type()) == 'long double'
}

fn test_a_conversion_this_milestone_has_no_arithmetic_for_is_refused() {
	// The complex types are the back end milestone's, and a conversion that
	// needs one is refused by name rather than approximated with the real type
	// underneath it. Measured: gcc makes `double _Complex` of a double and a
	// `double _Complex`, which is arithmetic this compiler does not emit.
	complex_sum := usual_arithmetic_conversions(double_type(), complex_double_type(), measured.representation()) or {
		assert err.msg().contains('complex')
		return
	}
	assert complex_sum.kind == .unknown
	// A pointer is not arithmetic, and neither is a name this compiler never
	// resolved.
	pointer_sum := usual_arithmetic_conversions(int_type(), pointer_to(int_type()), measured.representation()) or {
		assert err.msg().contains('arithmetic')
		return
	}
	assert pointer_sum.kind == .unknown
	unknown_sum := usual_arithmetic_conversions(int_type(), Type{}, measured.representation()) or {
		assert err.msg().contains('arithmetic')
		return
	}
	assert unknown_sum.kind == .unknown
	// unsigned short + int needs a promotion that needs the widths.
	refused := usual_arithmetic_conversions(unsigned_short_type(), int_type(), measured.partial()) or {
		assert err.msg().contains('width')
		return
	}
	assert refused.kind == .unknown
}

fn test_decay_of_6_3_2_1() {
	// An array becomes a pointer to its first element.
	decayed := decay(array_of(int_type(), 4))
	assert decayed.describe() == 'int *'
	assert decayed.is_pointer()
	// The element keeps its qualifiers: `const int a[4]` decays to
	// `const int *` and not to `int *`.
	const_element := decay(array_of(qualified(int_type(), Qualifiers{
		const_: true
	}), 4))
	assert const_element.describe() == 'const int *'
	// A function becomes a pointer to itself.
	function_pointer := decay(function_type(int_type(), [], false, true))
	assert function_pointer.describe() == 'int (void) *'
	// A type that is neither is left alone, which is what makes the call safe
	// where no decay happens: `&a` is a pointer to the array and `sizeof a` is
	// the size of the array, and neither of them asks for a decay. A string
	// literal keeps its array type until a value is wanted from it.
	array := array_of(int_type(), 4)
	assert decay(pointer_to(array)).describe() == 'int[4]*'
	assert decay(int_type()).kind == .int_
	assert decay(Type{}).kind == .unknown
	assert decay(array_of(char_type(), 3)).describe() == 'char *'
}

// 6.5.16.1 and 6.5.2.2, with gcc 16.2.1 as the oracle: each case below is a
// function in the measurement file, compiled with `-std=c99 -pedantic-errors`
// against the assignment, and the verdict is the assertion.
fn test_the_constraint_on_assignment_between_pointer_types() {
	// a_pointer_to_the_same_type: accepted.
	assert reason(pointer_to(int_type()), pointer_to(int_type()), false) == ''
	// b_void_from_object and c_object_from_void: accepted, a pointer to void
	// converts to and from a pointer to any object type.
	assert reason(pointer_to(void_type()), pointer_to(int_type()), false) == ''
	assert reason(pointer_to(int_type()), pointer_to(void_type()), false) == ''
	// d_adds_a_qualifier: accepted. e_drops_a_qualifier is not:
	// `initialization discards 'const' qualifier from pointer target type`.
	const_char := pointer_to(qualified(char_type(), Qualifiers{
		const_: true
	}))
	assert reason(const_char, pointer_to(char_type()), false) == ''
	assert only_reason(pointer_to(char_type()), const_char, false, 'drops a qualifier')
	// f_different_pointee: `initialization of 'char *' from incompatible pointer
	// type 'int *'`.
	assert only_reason(pointer_to(char_type()), pointer_to(int_type()), false, 'compatible')
	// g_nested_qualifier: `initialization of 'const char **' from incompatible
	// pointer type 'char **'`, because the two pointee types are different
	// pointer types and the qualifier rule reads only the top level.
	assert only_reason(pointer_to(const_char), pointer_to(pointer_to(char_type())), false, 'compatible')
	// h_null_constant: accepted. i_nonzero_integer is not: `initialization of
	// 'int *' from 'int' makes pointer from integer without a cast`.
	assert reason(pointer_to(int_type()), int_type(), true) == ''
	assert only_reason(pointer_to(int_type()), int_type(), false, 'integer constant')
	// j_function_pointer_from_void and k_void_from_function_pointer: `ISO C
	// forbids initialization between function pointer and 'void *'`, and a
	// pointer to void converts only to and from a pointer to an object type.
	function_pointer := pointer_to(function_type(void_type(), [], false, true))
	assert only_reason(pointer_to(void_type()), function_pointer, false, 'object')
	assert only_reason(function_pointer, pointer_to(void_type()), false, 'object')
	// Two pointers to the same function type are compatible.
	int_function := pointer_to(function_type(int_type(), [], false, true))
	assert reason(int_function, pointer_to(function_type(int_type(), [], false, true)), false) == ''
	// e_function_pointer_from_null_constant: accepted. 6.5.16.1 allows an
	// integer constant of value zero to convert to any pointer type, and a
	// pointer to a function is one. Measured, gcc 16.2.1 compiles and runs
	// `int h(int (*fp)(void)); int main(void) { return h(0); }`.
	assert reason(int_function, int_type(), true) == ''
	// The integer still has to be zero: gcc refuses `h(1)` with `passing
	// argument 1 of 'h' makes pointer from integer without a cast`.
	assert only_reason(int_function, int_type(), false, 'integer constant')
	// o_pointer_to_bool: accepted, and it is 6.5.16.1's last allowed form. gcc
	// accepts `int *p; _Bool b = p;` and refuses `int i = p;`.
	assert reason(bool_type(), pointer_to(int_type()), false) == ''
	// l_double_from_int: arithmetic converts, both ways.
	assert reason(double_type(), int_type(), false) == ''
	assert reason(int_type(), double_type(), false) == ''
	// n_pointer_from_pointer_to_void_pointer: accepted, the pointee types are
	// the same.
	assert reason(pointer_to(pointer_to(void_type())), pointer_to(pointer_to(void_type())), false) == ''
	// A pointer where an object is expected is a violation the other way round.
	assert only_reason(int_type(), pointer_to(int_type()), false, 'pointer')
	// Nothing is claimed about a type this compiler did not resolve: the
	// constraint is a question about two types and one of them is not known.
	assert reason(int_type(), Type{}, false) == ''
	// The same question an argument asks, which 6.5.2.2 says is asked as if by
	// assignment.
	assert only_reason(pointer_to(char_type()), pointer_to(int_type()), false, 'compatible')
	// There is no object of type void to assign to.
	assert only_reason(void_type(), int_type(), false, 'void')
}

// 6.3.1.3: a conversion between two integer types either preserves every value or
// it does not, and the difference is the widths.
fn test_a_narrowing_integer_conversion_is_not_value_preserving() {
	assert value_preserving(long_type(), int_type(), measured.representation()) or {
		assert false
		return
	}
	assert !value_preserving(int_type(), long_type(), measured.representation()) or {
		assert false
		return
	}
	assert value_preserving(int_type(), int_type(), measured.representation()) or {
		assert false
		return
	}
	// The same width: an unsigned type holds values its signed counterpart does
	// not, and the other way round.
	assert !value_preserving(unsigned_int_type(), int_type(), measured.representation()) or {
		assert false
		return
	}
	assert !value_preserving(int_type(), unsigned_int_type(), measured.representation()) or {
		assert false
		return
	}
	// A width the description does not carry is a refusal rather than a guess.
	refused := value_preserving(long_type(), int_type(), measured.partial()) or {
		assert err.msg().contains('width')
		return
	}
	assert !refused
	// The question is about integer types, so asking it about a float is refused
	// for that reason instead.
	not_integer := value_preserving(float_type(), int_type(), measured.representation()) or {
		assert err.msg().contains('integer')
		return
	}
	assert !not_integer
}
