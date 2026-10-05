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
//
// The 128-bit types are gcc's rather than the standard's, and every pairing of
// one of them is measured the same way, with one program holding all of the rows
// (the probe and its output are .omh/lanes/w128-types/w128_conversions.c and
// w128_conversions.out, one line per case asserted below):
//
//   __int128 alone -> __int128   unsigned __int128 alone -> unsigned __int128
//   __int128 added to any integer type the standard has -> __int128: _Bool,
//     char, signed char, unsigned char, short, unsigned short, int, unsigned
//     int, long, unsigned long, long long, unsigned long long, an enum, and
//     __int128 itself
//   unsigned __int128 added to the same list, and to itself -> unsigned __int128
//   __int128 + unsigned __int128 -> unsigned __int128, and the other order
//   __int128 + float -> float, + double -> double, + long double -> long double,
//     and the same three rows with unsigned __int128
//   int * + __int128 -> int *, and __int128 + int * -> int *: pointer
//     arithmetic, whose type comes from the pointer and not from a conversion

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
	problem := assignment_problem(to, from, constant_zero) or { return '' }
	return problem.msg
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
	assert promote(enum_type('E', .int_)) == 'int'
	// An enum whose enumerators are non-negative is unsigned int in gcc, and one
	// whose values do not fit int is long or unsigned long. The promotion is the
	// underlying type itself in each case, not always int.
	assert promote(enum_type('E', .unsigned_int)) == 'unsigned int'
	assert promote(enum_type('E', .long)) == 'long'
	assert promote(enum_type('E', .unsigned_long)) == 'unsigned long'
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
// a width question. The description the compiler reads with carries both widths
// now, so the promotion lands on int. A description that carries the width of an
// int and not the width of a short still gets a refusal that names what it would
// have to carry, which is the machinery this test is about.
fn test_the_unsigned_short_promotion_is_decided_by_the_widths() {
	assert promote(unsigned_short_type()) == 'int'
	answered := integer_promotion(unsigned_short_type(), measured.partial())!
	assert answered.kind == .int_
	without_short := Representation{
		sizes:  {
			Kind.int_: 4
		}
		aligns: {
			Kind.int_: 4
		}
	}
	refused := integer_promotion(unsigned_short_type(), without_short) or {
		assert err.msg().contains('unsigned short')
		assert err.msg().contains('width of short')
		assert err.msg().contains('carries no short')
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

fn test_the_usual_arithmetic_conversions_with_a_complex_operand() {
	// 6.3.1.8: an operand of a complex type makes the result complex, and the
	// two corresponding real types follow the rules above, so a real operand
	// takes the component's own rules and the complex part is set aside.
	// Measured with `_Generic` on gcc 16.2.1: `1.0 + 1.0f * _Complex_I` and
	// `1.0f + 1.0 * _Complex_I` are both `double _Complex`, `1.0f + 1.0f *
	// _Complex_I` is `float _Complex`, and `1 + 1.0f * _Complex_I` is
	// `float _Complex`.
	assert sum(double_type(), complex_double_type()) == 'double _Complex'
	assert sum(double_type(), complex_float_type()) == 'double _Complex'
	assert sum(float_type(), complex_float_type()) == 'float _Complex'
	assert sum(int_type(), complex_float_type()) == 'float _Complex'
	assert sum(int_type(), complex_double_type()) == 'double _Complex'
	assert sum(complex_float_type(), complex_double_type()) == 'double _Complex'
	assert sum(long_double_type(), complex_double_type()) == 'long double _Complex'
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
	// The reason carries the class and says the flags decide it, because gcc
	// compiles this program: measured 16.2.1, the same assignment is a warning
	// under -std=c99 and the image runs. A reason the program is wrong for does
	// not carry that.
	dropped := assignment_problem(pointer_to(char_type()), const_char, false) or {
		panic('a dropped qualifier is a problem')
	}
	assert dropped.warning
	assert dropped.class == .discarded_qualifiers
	wrong := assignment_problem(pointer_to(char_type()), pointer_to(int_type()), false) or {
		panic('an incompatible pointee is a problem')
	}
	assert !wrong.warning
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
	// j_function_pointer_from_void and k_void_from_function_pointer: gcc 16.2.1
	// accepts both in every mode and reports them only under -pedantic, so the
	// standard's rule is a pedantic question rather than a constraint the
	// assignment fails. The conversion is allowed, and the objection is named
	// by `function_void_pointer_problem`, which the stage that reports it asks.
	function_pointer := pointer_to(function_type(void_type(), [], false, true))
	assert reason(pointer_to(void_type()), function_pointer, false) == ''
	assert reason(function_pointer, pointer_to(void_type()), false) == ''
	assert (function_void_pointer_problem(pointer_to(void_type()), function_pointer) or {
		''
	}) == 'ISO C forbids conversion of function pointer to object pointer type'
	assert (function_void_pointer_problem(function_pointer, pointer_to(void_type())) or {
		''
	}) == 'ISO C forbids conversion of object pointer to function pointer type'
	// A function type that has not decayed answers the same as a pointer to
	// one, because a cast hands it over that way; there is one question and not
	// one per spelling of the operand.
	assert (function_void_pointer_problem(pointer_to(void_type()), function_type(void_type(), [],
		false, true)) or { '' }) == 'ISO C forbids conversion of function pointer to object pointer type'
	// A conversion between two pointers neither of which is a function pointer
	// or a pointer to void is not this question, and an object pointer converts
	// to a void pointer by the ordinary rule.
	assert (function_void_pointer_problem(pointer_to(int_type()), pointer_to(int_type())) or {
		''
	}) == ''
	assert (function_void_pointer_problem(pointer_to(void_type()), pointer_to(char_type())) or {
		''
	}) == ''
	assert (function_void_pointer_problem(pointer_to(int_type()), int_type()) or { '' }) == ''
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

// The description the compiler itself gets, types.from_target, carries the width
// of a pointer, a char, an int, an unsigned int, the four 64-bit integer kinds, a
// double and the two 128-bit types, and nothing else. A 128-bit operand against a
// `long` is answered anyway, because two types of the same signedness are decided
// by rank and ask for no width; the mixed-signedness rows are the ones that ask,
// so a description that carries the 128-bit width and not the 64-bit one refuses
// `__int128` against an `unsigned long` for the width it does not carry.
// Measured, gcc answers `__int128` for both rows, and the refusal here is a
// change to the target description rather than a guess this function may make.
fn test_a_row_whose_width_the_description_lacks_is_refused() {
	assert sum(int128_type(), long_type()) == '__int128'
	narrow := Representation{
		sizes:  {
			Kind.int128: 16
		}
		aligns: {
			Kind.int128: 16
		}
	}
	refused := usual_arithmetic_conversions(int128_type(), unsigned_long_type(), narrow) or {
		assert err.msg().contains('width of unsigned long')
		return
	}
	assert refused.kind == .unknown
	// The same row against a type whose width the description does carry needs
	// both widths, and there the 16 bytes of the signed 128-bit type hold every
	// value of the 4-byte unsigned one.
	assert sum(int128_type(), unsigned_int_type()) == '__int128'
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
	// The 64-bit kinds are carried now, so the width that is missing here is a
	// short's.
	refused := value_preserving(unsigned_short_type(), int_type(), measured.partial()) or {
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

fn test_the_128_bit_types_in_the_conversions() {
	// The operand on its own: both 128-bit types are above int rank, so a
	// promotion keeps the type it was written with.
	assert promote(int128_type()) == '__int128'
	assert promote(unsigned_int128_type()) == 'unsigned __int128'
	// One signed 128-bit operand against every integer type the standard has.
	// The character and short types promote first, and the unsigned ones are
	// then decided by the width rule, which is the row that asks whether 16
	// bytes hold every value of 4 or 8: measured, `__int128 + unsigned long
	// long` is `__int128`.
	assert sum(int128_type(), int128_type()) == '__int128'
	assert sum(int128_type(), bool_type()) == '__int128'
	assert sum(int128_type(), char_type()) == '__int128'
	assert sum(int128_type(), signed_char_type()) == '__int128'
	assert sum(int128_type(), unsigned_char_type()) == '__int128'
	assert sum(int128_type(), short_type()) == '__int128'
	assert sum(int128_type(), unsigned_short_type()) == '__int128'
	assert sum(int128_type(), int_type()) == '__int128'
	assert sum(int128_type(), unsigned_int_type()) == '__int128'
	assert sum(int128_type(), long_type()) == '__int128'
	assert sum(int128_type(), unsigned_long_type()) == '__int128'
	assert sum(int128_type(), long_long_type()) == '__int128'
	assert sum(int128_type(), unsigned_long_long_type()) == '__int128'
	// An enum's underlying type is int, unsigned int, long or unsigned long, and
	// the row is __int128 for each of them, because a 16-byte type holds every
	// value of a 4-byte or 8-byte one.
	assert sum(int128_type(), enum_type('E', .int_)) == '__int128'
	assert sum(int128_type(), enum_type('E', .unsigned_long)) == '__int128'
	// The same list with the unsigned 128-bit operand, which wins every integer
	// pairing the same way.
	assert sum(unsigned_int128_type(), unsigned_int128_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), bool_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), char_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), unsigned_char_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), short_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), unsigned_short_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), int_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), unsigned_int_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), long_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), unsigned_long_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), long_long_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), unsigned_long_long_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), enum_type('E', .int_)) == 'unsigned __int128'
	// Between the two of them the unsigned type wins the way unsigned int wins
	// over int: neither can hold the other's values and one of them is unsigned.
	assert sum(int128_type(), unsigned_int128_type()) == 'unsigned __int128'
	assert sum(unsigned_int128_type(), int128_type()) == 'unsigned __int128'
	// The order of the operands does not change the answer.
	assert sum(int_type(), int128_type()) == '__int128'
	assert sum(char_type(), int128_type()) == '__int128'
	assert sum(unsigned_int_type(), int128_type()) == '__int128'
	assert sum(long_long_type(), int128_type()) == '__int128'
	assert sum(int_type(), unsigned_int128_type()) == 'unsigned __int128'
	assert sum(char_type(), unsigned_int128_type()) == 'unsigned __int128'
	assert sum(unsigned_int_type(), unsigned_int128_type()) == 'unsigned __int128'
	// The floating types outrank every integer, the 128-bit ones included.
	assert sum(int128_type(), float_type()) == 'float'
	assert sum(unsigned_int128_type(), float_type()) == 'float'
	assert sum(int128_type(), double_type()) == 'double'
	assert sum(unsigned_int128_type(), double_type()) == 'double'
	assert sum(int128_type(), long_double_type()) == 'long double'
	assert sum(unsigned_int128_type(), long_double_type()) == 'long double'
	assert sum(float_type(), int128_type()) == 'float'
	assert sum(double_type(), int128_type()) == 'double'
	// A pointer operand is not arithmetic, so there is no conversion to ask
	// this function for. Measured, gcc types `int * + __int128` and
	// `__int128 + int *` as `int *`, which is pointer arithmetic: the type
	// comes from the pointer, and the reader answers it where it reads the
	// operator.
	pointer_sum := usual_arithmetic_conversions(int128_type(), pointer_to(int_type()), measured.representation()) or {
		assert err.msg().contains('arithmetic')
		return
	}
	assert pointer_sum.kind == .unknown
	unsigned_pointer_sum := usual_arithmetic_conversions(unsigned_int128_type(), pointer_to(int_type()), measured.representation()) or {
		assert err.msg().contains('arithmetic')
		return
	}
	assert unsigned_pointer_sum.kind == .unknown
	// The unsigned counterpart of the signed type is the other 128-bit type.
	counterpart := unsigned_counterpart(int128_type()) or {
		assert false
		unsigned_int128_type()
	}
	assert counterpart.same(unsigned_int128_type())
	// An int assigned to one of them keeps its value, which is the narrow to
	// wide answer of 6.3.1.3, and the width it is compared against is the 16
	// bytes the description carries for the wide one.
	assert reason(int128_type(), int_type(), false) == ''
	assert reason(unsigned_int128_type(), int_type(), false) == ''
	assert value_preserving(int128_type(), int_type(), measured.representation()) or {
		assert false
		return
	}
}

// 6.3.2.1p2: the value a read lvalue is converted to has the unqualified version
// of its type, so a const-qualified struct read as a value is that struct, and
// 6.5.16.1 lets it be assigned or passed wherever the unqualified type is wanted.
// Measured on gcc 16.2.1 with -std=c99 -pedantic-errors: every case below that
// `reason` accepts is a program gcc compiles, and the shape this is for is V's
// own generated C, where a call's parameter is `struct string` and the argument
// is a `const struct string`.
fn test_the_constraint_on_aggregate_assignment_ignores_the_read_side_qualifiers() {
	plain := struct_type('S', [
		Member{
			name: 'a'
			typ:  int_type()
		},
	])
	read_only := qualified(plain, Qualifiers{
		const_: true
	})
	// A const struct passed where the unqualified one is a parameter, which is
	// the same constraint 6.5.2.2 says an argument asks.
	assert reason(plain, read_only, false) == ''
	// The other direction is a plain value assigned into a const object, which
	// the conversion allows. Whether that object may be written is the target
	// question in the test below.
	assert reason(read_only, plain, false) == ''
	// Both operands may be qualified.
	assert reason(read_only, read_only, false) == ''
	// A volatile qualifier drops the same way, because the same line of code
	// calls `unqualified`, which drops every top-level qualifier rather than
	// const alone. Measured, gcc accepts `volatile S vs; S t = vs;`.
	volatile_read := qualified(plain, Qualifiers{
		volatile_: true
	})
	assert reason(plain, volatile_read, false) == ''
	// A qualifier on a member is a property of the type and not of the reading,
	// so two otherwise equal types that differ there are still different: gcc
	// refuses assigning a struct whose member is `const int` to one whose member
	// is `int`.
	const_member := struct_type('', [
		Member{
			name: 'a'
			typ:  qualified(int_type(), Qualifiers{
				const_: true
			})
		},
	])
	plain_member := struct_type('', [
		Member{
			name: 'a'
			typ:  int_type()
		},
	])
	assert only_reason(const_member, plain_member, false, 'not assigned to')
	// Two aggregates of different tags are still different types.
	assert only_reason(plain, struct_type('T', []), false, 'not assigned to')
}

// 6.3.1p1: the left operand of an assignment has to be a modifiable lvalue, and
// an object is not one when it is const-qualified or when it is a structure or
// union with a const-qualified member, through contained aggregates and array
// elements included. This is the half of the rule the relaxation above must not
// swallow: the read drops the qualifier, and the write is refused.
//
// Measured on gcc 16.2.1 with -std=c99 -pedantic-errors: `const S s; S t; s = t;`
// is `assignment of read-only variable 's'`, and a struct with a const member is
// refused with the same message, which is the refusal pinned below.
fn test_an_object_that_may_not_be_written_is_refused_as_the_target() {
	plain := struct_type('S', [
		Member{
			name: 'a'
			typ:  int_type()
		},
	])
	// An unqualified object is a modifiable lvalue.
	assert (assignment_target_problem(plain) or { '' }) == ''
	// A const-qualified one is not, and the refusal names the type.
	read_only := qualified(plain, Qualifiers{
		const_: true
	})
	read_only_problem := assignment_target_problem(read_only) or { '' }
	assert read_only_problem.contains('const-qualified')
	assert read_only_problem.contains('modifiable lvalue')
	// A struct with a const-qualified member is not modifiable either, and the
	// member may sit inside a member aggregate or an array element.
	const_member := struct_type('', [
		Member{
			name: 'a'
			typ:  qualified(int_type(), Qualifiers{
				const_: true
			})
		},
	])
	member_problem := assignment_target_problem(const_member) or { '' }
	assert member_problem.contains('const-qualified member')
	assert member_problem.contains('modifiable lvalue')
	nested := struct_type('', [
		Member{
			name: 'inner'
			typ:  const_member
		},
	])
	assert (assignment_target_problem(nested) or { '' }).contains('const-qualified member')
	arrayed := struct_type('', [
		Member{
			name: 'items'
			typ:  array_of(const_member, 2)
		},
	])
	assert (assignment_target_problem(arrayed) or { '' }).contains('const-qualified member')
	assert const_member.has_const_member()
	assert nested.has_const_member()
	assert arrayed.has_const_member()
	assert !plain.has_const_member()
	// A volatile object is still a modifiable lvalue, so only const is refused.
	volatile_object := qualified(plain, Qualifiers{
		volatile_: true
	})
	assert (assignment_target_problem(volatile_object) or { '' }) == ''
}

// sum_with is sum with the object representation the caller names, for the
// cases where the widths are the thing under test rather than this target's.
fn sum_with(a Type, b Type, rep Representation) string {
	return usual_arithmetic_conversions(a, b, rep) or {
		return 'refused: ${err.msg()}'
	}.describe()
}

// 6.7.6.3p15: two function types are compatible when they return compatible
// types and take compatible parameter types, and the parameter names are not
// part of either. The parameter adjustment of 6.7.5.3 has already happened when
// the type is built, so two declarations written differently but meaning one
// function come out equal here.
fn test_two_function_types_are_compatible_when_return_and_parameters_match() {
	one := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  char_type()
		},
	], false, true)
	// The same signature under another parameter name is the same type.
	other_name := function_type(int_type(), [
		Param{
			name: 'value'
			typ:  char_type()
		},
	], false, true)
	assert one.compatible(other_name)
	assert other_name.compatible(one)
	// A pointer to a function compares through the pointer.
	assert pointer_to(one).compatible(pointer_to(other_name))
	// A prototype that names no parameters is `(void)`, and two of those are one
	// type.
	no_parameters := function_type(int_type(), [], false, true)
	assert no_parameters.compatible(function_type(int_type(), [], false, true))
	// A function that returns nothing has a return type, and it is part of the
	// comparison like any other.
	no_return := function_type(void_type(), [], false, true)
	assert no_return.compatible(function_type(void_type(), [], false, true))
}

// The return type is compared as well as the parameters, so two functions that
// take the same arguments and return different types are two types. void is a
// return type of its own and not the absence of one.
fn test_two_function_types_differ_in_the_return_type() {
	int_return := function_type(int_type(), [], false, true)
	char_return := function_type(char_type(), [], false, true)
	assert !int_return.compatible(char_return)
	assert !char_return.compatible(int_return)
	assert !int_return.compatible(function_type(void_type(), [], false, true))
	assert !function_type(void_type(), [], false, true).compatible(int_return)
}

// 6.7.6.3: the parameter type list is part of the type, so a different count of
// parameters is a different function type.
fn test_two_function_types_differ_in_the_parameter_count() {
	none_taken := function_type(int_type(), [], false, true)
	one_taken := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
	], false, true)
	two_taken := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
		Param{
			name: 'b'
			typ:  int_type()
		},
	], false, true)
	assert !none_taken.compatible(one_taken)
	assert !one_taken.compatible(none_taken)
	assert !one_taken.compatible(two_taken)
	assert !two_taken.compatible(one_taken)
}

// The types of the parameters are compared in order, so a different type in one
// position is a different function type.
fn test_two_function_types_differ_in_a_parameter_type() {
	takes_int := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
	], false, true)
	takes_char := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  char_type()
		},
	], false, true)
	assert !takes_int.compatible(takes_char)
	assert !takes_char.compatible(takes_int)
	takes_int_char := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
		Param{
			name: 'b'
			typ:  char_type()
		},
	], false, true)
	takes_char_int := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  char_type()
		},
		Param{
			name: 'b'
			typ:  int_type()
		},
	], false, true)
	assert !takes_int_char.compatible(takes_char_int)
}

// 6.7.6.3: a function type written with no parameter list says nothing about the
// arguments a call may pass and is not a prototype; a prototype that names no
// parameters says the function takes none. The two are different types, so two
// declarations of one function may not mix them.
fn test_a_function_without_a_parameter_list_is_not_compatible_with_a_prototype() {
	no_list := function_type(int_type(), [], false, false)
	prototype_none := function_type(int_type(), [], false, true)
	prototype_one := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
	], false, true)
	assert !no_list.compatible(prototype_none)
	assert !prototype_none.compatible(no_list)
	assert !no_list.compatible(prototype_one)
	assert !prototype_one.compatible(no_list)
	// Two functions that both wrote no list are one type.
	assert no_list.compatible(function_type(int_type(), [], false, false))
	// The type itself says which of the two spellings it was.
	assert prototype_none.prototyped
	assert !no_list.prototyped
}

// The variadic flag is part of the type: `int f(int)` and `int f(int, ...)` do
// not declare one function.
fn test_two_function_types_differ_when_one_is_variadic() {
	fixed := function_type(int_type(), [
		Param{
			name: 'n'
			typ:  int_type()
		},
	], false, true)
	variadic := function_type(int_type(), [
		Param{
			name: 'n'
			typ:  int_type()
		},
	], true, true)
	assert !fixed.compatible(variadic)
	assert !variadic.compatible(fixed)
	assert variadic.compatible(function_type(int_type(), [
		Param{
			name: 'n'
			typ:  int_type()
		},
	], true, true))
}

// 6.7.5.3: a parameter written with an array type is written as a pointer and
// one written with a function type as a pointer to a function, so a definition
// written `void f(char a[])` and a prototype written `void f(char *a)` declare
// one function and not two.
fn test_a_parameter_written_as_an_array_or_a_function_is_adjusted_before_the_comparison() {
	as_array := function_type(void_type(), [
		Param{
			name: 'a'
			typ:  array_of(char_type(), -1)
		},
	], false, true)
	as_pointer := function_type(void_type(), [
		Param{
			name: 'a'
			typ:  pointer_to(char_type())
		},
	], false, true)
	assert as_array.compatible(as_pointer)
	assert as_pointer.compatible(as_array)
	// A pointer to an array is not the same parameter type as the array: only
	// the array spelling is adjusted, and the pointer spelling is left alone.
	assert !as_array.compatible(function_type(void_type(), [
		Param{
			name: 'a'
			typ:  pointer_to(array_of(char_type(), -1))
		},
	], false, true))
	// A function type as a parameter becomes a pointer to one.
	callback := function_type(int_type(), [], false, true)
	as_function := function_type(void_type(), [
		Param{
			name: 'cb'
			typ:  callback
		},
	], false, true)
	as_function_pointer := function_type(void_type(), [
		Param{
			name: 'cb'
			typ:  pointer_to(callback)
		},
	], false, true)
	assert as_function.compatible(as_function_pointer)
	assert as_function_pointer.compatible(as_function)
}

// 6.3.1.3: two integer types of the same width are decided by signedness and not
// by rank, so the same width reads as preserving a value only when no value can
// be lost. `long` and `long long` are both eight bytes on this target and both
// signed, so each holds every value of the other, while an unsigned type of one
// width cannot hold a signed one's.
fn test_value_preserving_at_the_same_width_reads_the_signedness() {
	rep := measured.representation()
	assert value_preserving(long_type(), long_long_type(), rep) or {
		assert false
		return
	}
	assert value_preserving(long_long_type(), long_type(), rep) or {
		assert false
		return
	}
	assert !value_preserving(unsigned_long_type(), long_long_type(), rep) or {
		assert false
		return
	}
	assert !value_preserving(long_long_type(), unsigned_long_type(), rep) or {
		assert false
		return
	}
	// A wider target holds every value of a narrower source, and a narrower one
	// does not, whether or not a sign is involved.
	assert value_preserving(unsigned_long_type(), unsigned_int_type(), rep) or {
		assert false
		return
	}
	assert !value_preserving(unsigned_int_type(), unsigned_long_type(), rep) or {
		assert false
		return
	}
	assert value_preserving(int_type(), bool_type(), rep) or {
		assert false
		return
	}
	// An enumerated type is asked about the integer type its enumerators
	// require, so it preserves an int in both directions.
	assert value_preserving(enum_type('E', .int_), int_type(), rep) or {
		assert false
		return
	}
	assert value_preserving(int_type(), enum_type('E', .int_), rep) or {
		assert false
		return
	}
}

// The promotion is asked of any operand of an arithmetic expression, and a type
// this compiler never resolved has no promotion: the refusal names the missing
// answer rather than reading an unresolved type as int.
fn test_the_promotion_of_a_type_the_compiler_never_resolved_is_refused() {
	unknown_refused := integer_promotion(Type{}, measured.representation()) or {
		assert err.msg().contains('promotion')
		return
	}
	assert unknown_refused.kind == .unknown
	opaque_refused := integer_promotion(opaque_type('size_t'), measured.representation()) or {
		assert err.msg().contains('promotion')
		return
	}
	assert opaque_refused.kind == .unknown
}

// 6.3.1.8: when a signed and an unsigned operand have ranks that would hand the
// result to the unsigned one, the two widths are compared first, and a signed
// type no wider than the unsigned one gives way to the unsigned type of the
// signed side's own rank. On widths a target may have, where `long` and
// `unsigned int` are both four bytes, `long` cannot hold every unsigned int
// value, so the conversion lands on `unsigned long` and not on `long`.
fn test_the_usual_arithmetic_conversions_fall_back_to_the_unsigned_counterpart() {
	narrow := Representation{
		sizes:  {
			Kind.long:         4
			Kind.unsigned_int: 4
		}
		aligns: {
			Kind.long:         4
			Kind.unsigned_int: 4
		}
	}
	assert sum_with(long_type(), unsigned_int_type(), narrow) == 'unsigned long'
	assert sum_with(unsigned_int_type(), long_type(), narrow) == 'unsigned long'
	// With the widths this target has, the eight-byte long holds every value of
	// the four-byte unsigned int, so the signed side wins instead.
	assert sum(long_type(), unsigned_int_type()) == 'long'
}

// 6.5.16.1: a pointer to void converts to and from a pointer to any object or
// incomplete type, and a struct declared but never defined is exactly such an
// incomplete type. Two pointers to the same incomplete tag are compatible, and a
// pointer to an incomplete struct does not point to a type compatible with int.
fn test_a_pointer_to_an_incomplete_type_converts_to_and_from_a_void_pointer() {
	incomplete := incomplete_tag(Kind.struct_, 'S')
	to_incomplete := pointer_to(incomplete)
	void_pointer := pointer_to(void_type())
	assert reason(to_incomplete, void_pointer, false) == ''
	assert reason(void_pointer, to_incomplete, false) == ''
	// The same tag names the same type whether or not the body was read.
	assert reason(to_incomplete, pointer_to(incomplete_tag(Kind.struct_, 'S')), false) == ''
	// An object pointer of another type is not compatible with it.
	assert only_reason(pointer_to(int_type()), to_incomplete, false, 'compatible')
	assert only_reason(to_incomplete, pointer_to(int_type()), false, 'compatible')
}

// 6.5.16.1: a pointer to void converts to and from a pointer to any object type,
// and the qualifier on the type it points at survives the conversion. Adding a
// qualifier on the way to void is allowed; dropping one is the reason the
// standard requires a diagnostic for, and the reason carries `warning` because
// gcc still compiles the program.
fn test_a_void_pointer_conversion_that_drops_a_pointee_qualifier_is_a_warning() {
	const_int := qualified(int_type(), Qualifiers{
		const_: true
	})
	dropped := assignment_problem(pointer_to(void_type()), pointer_to(const_int), false) or {
		panic('dropping const through a void pointer is a problem')
	}
	assert dropped.warning
	assert dropped.class == .discarded_qualifiers
	assert dropped.msg.contains('drops a qualifier')
	// Adding the same qualifier on the way to void is allowed, and a void
	// pointer from a plain int pointer has no qualifier to drop.
	const_void := pointer_to(qualified(void_type(), Qualifiers{
		const_: true
	}))
	assert reason(const_void, pointer_to(int_type()), false) == ''
	assert reason(pointer_to(void_type()), pointer_to(int_type()), false) == ''
}
