module types

// The type model is data, so these tests read the data back: what a kind is, what
// a derived type is derived from, and what two types have to do with each other.

fn test_the_scalar_types_are_complete_and_spelled_the_way_c_writes_them() {
	assert int_type().describe() == 'int'
	assert unsigned_int_type().describe() == 'unsigned int'
	assert long_long_type().describe() == 'long long'
	assert unsigned_long_long_type().describe() == 'unsigned long long'
	// The 128-bit types are spelled the way gcc spells them, which is the only
	// way they are written: no standard has them.
	assert int128_type().describe() == '__int128'
	assert unsigned_int128_type().describe() == 'unsigned __int128'
	// The kind names the type as well, which is the path the model takes when
	// it is working from a kind rather than from a run of words.
	unwrapped_int128 := scalar(Kind.int128) or {
		assert false
		int128_type()
	}
	assert unwrapped_int128.describe() == '__int128'
	unwrapped_unsigned := scalar(Kind.unsigned_int128) or {
		assert false
		unsigned_int128_type()
	}
	assert unwrapped_unsigned.describe() == 'unsigned __int128'
	assert bool_type().describe() == '_Bool'
	assert long_double_type().describe() == 'long double'
	assert complex_double_type().describe() == 'double _Complex'
	assert int_type().is_complete()
	assert void_type().is_complete()
	assert !opaque_type('size_t').is_complete()
}

fn test_the_integer_kinds_know_their_signedness() {
	assert Kind.int_.is_integer() && Kind.int_.is_signed_integer()
	assert Kind.unsigned_int.is_integer() && !Kind.unsigned_int.is_signed_integer()
	assert Kind.unsigned_int.is_unsigned_integer()
	assert Kind.bool_.is_unsigned_integer()
	assert Kind.enum_.is_integer()
	assert !Kind.float.is_integer()
	assert Kind.float.is_floating() && Kind.double.is_floating() && Kind.long_double.is_floating()
	assert Kind.complex_double.is_complex()
	assert !Kind.complex_double.is_floating()
	assert Kind.float.is_arithmetic() && Kind.unsigned_long.is_arithmetic()
	assert Kind.int128.is_integer() && Kind.int128.is_signed_integer()
	assert Kind.unsigned_int128.is_integer() && Kind.unsigned_int128.is_unsigned_integer()
	assert !Kind.unsigned_int128.is_signed_integer()
	assert !Kind.int128.is_floating()
	assert !Kind.pointer.is_arithmetic()
	assert Kind.pointer.is_scalar() && Kind.int_.is_scalar()
	assert !Kind.struct_.is_scalar()
	assert Kind.array.is_aggregate() && Kind.struct_.is_aggregate() && Kind.union_.is_aggregate()
}

// 6.3.1.1. A signed type and its unsigned counterpart have the same rank, which
// is the fact that makes `int + unsigned int` convert to unsigned int.
fn test_the_conversion_ranks_are_the_standards() {
	assert Kind.char_.rank() == Kind.signed_char.rank()
	assert Kind.signed_char.rank() == Kind.unsigned_char.rank()
	assert Kind.short.rank() == Kind.unsigned_short.rank()
	assert Kind.int_.rank() == Kind.unsigned_int.rank()
	assert Kind.long.rank() == Kind.unsigned_long.rank()
	assert Kind.long_long.rank() == Kind.unsigned_long_long.rank()
	assert Kind.bool_.rank() < Kind.char_.rank()
	assert Kind.char_.rank() < Kind.short.rank()
	assert Kind.short.rank() < Kind.int_.rank()
	assert Kind.int_.rank() < Kind.long.rank()
	assert Kind.long.rank() < Kind.long_long.rank()
	// The 128-bit types are the GNU ones: they rank above every integer the
	// standard has and below float, which is where gcc's own conversion rank
	// puts `__int128`. Measured, the conversions follow that ordering at both
	// ends of it: `__int128 + unsigned long long` is `__int128` and
	// `__int128 + float` is `float` (the rows are asserted in convert_test.v).
	assert Kind.int128.rank() == Kind.unsigned_int128.rank()
	assert Kind.long_long.rank() < Kind.int128.rank()
	assert Kind.unsigned_long_long.rank() < Kind.unsigned_int128.rank()
	assert Kind.int128.rank() < Kind.float.rank()
	assert Kind.unsigned_int128.rank() < Kind.float.rank()
	assert Kind.long_long.rank() < Kind.float.rank()
	assert Kind.float.rank() < Kind.double.rank()
	assert Kind.double.rank() < Kind.long_double.rank()
	assert Kind.void_.rank() == -1
}

fn test_a_pointer_says_what_it_points_at() {
	p := pointer_to(char_type())
	assert p.is_pointer() && p.is_complete()
	assert p.describe() == 'char *'
	pointee := p.pointee() or {
		assert false
		return
	}
	assert pointee.kind == .char_
	pp := pointer_to(p)
	assert pp.describe() == 'char **'
	assert pp.pointee() or {
		assert false
		return
	}.kind == .pointer
	// A pointer to a pointer is still one level deep: the description is the
	// only place the run of stars is written as a run.
	assert pointer_to(pointer_to(int_type())).describe() == 'int **'
}

fn test_an_array_says_how_many_elements_and_of_what() {
	a := array_of(int_type(), 4)
	assert a.is_array() && a.is_complete()
	assert a.describe() == 'int[4]'
	element := a.element() or {
		assert false
		return
	}
	assert element.kind == .int_
	// A size that was not written is not a size: the array is incomplete, which
	// is what lets `int a[]` be a declaration that something else completes.
	open := array_of(int_type(), -1)
	assert !open.is_complete()
	assert open.describe() == 'int[]'
	assert !array_of(opaque_type('size_t'), 4).is_complete()
}

fn test_a_variable_length_array_is_complete_though_its_count_is_not_written() {
	// A bound computed at run time is still a size: the type is complete, and
	// what tells it from `int a[]` is the flag and not the count, because both
	// have -1 there.
	v := vla_array_of(int_type())
	assert v.is_array() && v.vla
	assert v.count == -1
	assert v.is_complete()
	assert v.describe() == 'int[]'
	// The two are not the same type: an object whose size is computed at run
	// time cannot be a declaration something later completes.
	assert !v.same(array_of(int_type(), -1))
	assert v.same(vla_array_of(int_type()))
	// A variable-length array of a complete element type is complete; one whose
	// element type is not has no size whatever its bound says.
	assert !vla_array_of(opaque_type('size_t')).is_complete()
}

fn test_a_function_says_what_it_returns_and_what_it_takes() {
	f := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  char_type()
		},
	], false, true)
	assert f.is_function() && !f.is_object()
	assert f.describe() == 'int (char)'
	assert f.returns() or {
		assert false
		return
	}.kind == .int_
	// `int f()` names no parameters and says nothing about the call, so it is
	// not a prototype and is described as one the way the declaration reads.
	call := function_type(int_type(), [], false, false)
	assert call.describe() == 'int ()'
	assert call.params.len == 0
	// A pointer to a function is the type a declared function pointer has.
	assert pointer_to(f).returns() or {
		assert false
		return
	}.kind == .int_
	assert !pointer_to(int_type()).is_function()
}

// 6.7.5.3: a parameter written with an array type is a pointer, and one written
// with a function type is a pointer to a function.
fn test_a_parameter_of_an_array_or_function_type_is_adjusted() {
	adjusted := adjust_parameter(array_of(char_type(), -1))
	assert adjusted.is_pointer()
	assert adjusted.describe() == 'char *'
	mut f := function_type(int_type(), [], false, true)
	f = adjust_parameter(f)
	assert f.is_pointer()
	// The list was written as a prototype naming no parameters, which is
	// `(void)`; a list that named nothing at all is written `()`.
	assert f.describe() == 'int (void) *'
	// A plain scalar parameter is left alone.
	assert adjust_parameter(int_type()).same(int_type())
}

fn test_qualifiers_are_part_of_the_type() {
	const_int := qualified(int_type(), Qualifiers{
		const_: true
	})
	assert const_int.is_const()
	assert const_int.describe() == 'const int'
	p := pointer_to(const_int)
	assert p.describe() == 'const int *'
	// A const pointer is a different type from a pointer to const, and the
	// description is where that difference is visible.
	const_p := qualified(pointer_to(int_type()), Qualifiers{
		const_: true
	})
	assert const_p.describe() == 'int * const'
	assert !const_p.same(p)
	// Adding a qualifier keeps the ones already on the type.
	both := qualified(const_int, Qualifiers{
		volatile_: true
	})
	assert both.quals.const_ && both.quals.volatile_
	assert both.describe() == 'const volatile int'
	assert unqualified(both).describe() == 'int'
}

fn test_qualifiers_containment_is_the_assignment_question() {
	plain := Qualifiers{}
	const_q := Qualifiers{
		const_: true
	}
	assert plain.contains(plain)
	assert const_q.contains(plain)
	assert !plain.contains(const_q)
	assert const_q.contains(const_q)
	assert !const_q.describe().contains('volatile')
	volatile_const := Qualifiers{
		const_:    true
		volatile_: true
	}
	assert volatile_const.describe() == 'const volatile'
	assert volatile_const.contains(const_q)
	assert !const_q.contains(volatile_const)
}

fn test_an_aggregate_is_the_same_type_by_its_tag() {
	// A tag is the identity of a struct or a union: the members are a property
	// of the tagged type and not a second half of its identity. Two readings of
	// one tag are one type, so the same tag with a different member list is the
	// same type too; a redefinition in one scope is a different question, and it
	// is reported where the second declaration is read.
	members := [
		Member{
			name: 'a'
			typ:  int_type()
		},
	]
	s := struct_type('S', members)
	assert s.same(struct_type('S', [
		Member{
			name: 'b'
			typ:  char_type()
		},
	]))
	// A tag read while it was still incomplete and the type its body leaves
	// behind are one type: `struct S *p;` read before `struct S { int a; };`
	// takes a copy with no members, and that copy is the type the body defines.
	// This is the reading a pointer assigned across the two needs, and it is
	// why the members are read through the tag rather than out of the copy.
	incomplete := incomplete_tag(Kind.struct_, 'S')
	assert incomplete.same(s)
	assert s.same(incomplete)
	assert incomplete.is_aggregate()
	// A tag that is never completed stays incomplete, which is what keeps an
	// object of it from being laid out and a size asked of it from being
	// answered.
	assert !incomplete.is_complete()
	// Two different tags are two different types, identical members or not.
	assert !s.same(struct_type('T', members))
	assert !s.same(union_type('S', members))
	// An aggregate written without a tag has no name to be identified by, so
	// its members are what tells it from another.
	assert struct_type('', members).same(struct_type('', members))
	assert !struct_type('', members).same(struct_type('', [
		Member{
			name: 'b'
			typ:  char_type()
		},
	]))
	assert s.describe() == 'struct S'
	assert union_type('U', members).describe() == 'union U'
	assert enum_type('E', .int_).describe() == 'enum E'
	assert struct_type('', []).describe() == 'struct <anonymous>'
	assert s.is_aggregate() && s.is_complete()
}

fn test_compatibility_is_sameness() {
	assert int_type().compatible(int_type())
	assert !int_type().compatible(unsigned_int_type())
	// The three character types are three distinct types (6.2.5p15), and the
	// mixes are refused rather than allowed: measured, gcc 16.2.1 under
	// `-std=c99 -pedantic-errors` reports `conflicting types for f1` for
	// `void f1(char *); void f1(unsigned char *);` and `pointer targets in passing
	// argument 1 of wants differ in signedness` for a `char *` argument to a
	// parameter of `unsigned char *` - the second of which plain `-std=c99`
	// accepts, saying nothing, and `-std=c99 -Wpointer-sign` gives as a warning.
	assert !char_type().compatible(signed_char_type())
	assert !char_type().compatible(unsigned_char_type())
	assert !signed_char_type().compatible(char_type())
	assert !signed_char_type().compatible(unsigned_char_type())
	// Each of them is compatible with itself, which is what makes a string
	// literal fit a `char *` parameter.
	assert char_type().compatible(char_type())
	assert signed_char_type().compatible(signed_char_type())
	assert unsigned_char_type().compatible(unsigned_char_type())
	// A pointer to an unsigned char does not accept a pointer to a char, which
	// is the same rule one level down.
	assert !pointer_to(unsigned_char_type()).compatible(pointer_to(char_type()))
	// An unresolved type is compatible with nothing, itself included, because it
	// is the absence of an answer rather than a type.
	unknown := Type{}
	assert !unknown.compatible(unknown)
	assert !unknown.compatible(int_type())
	assert opaque_type('size_t').compatible(opaque_type('size_t'))
	assert !opaque_type('size_t').compatible(opaque_type('ssize_t'))
	assert pointer_to(int_type()).compatible(pointer_to(int_type()))
	assert !pointer_to(int_type()).compatible(pointer_to(char_type()))
}

fn test_a_pointer_to_a_function_is_read_off_the_pointer() {
	f := function_type(void_type(), [], false, true)
	pf := pointer_to(f)
	returned := pf.returns() or {
		assert false
		return
	}
	assert returned.is_void()
	assert pointer_to(int_type()).returns() == none
	assert int_type().pointee() == none
	assert int_type().element() == none
}

fn test_scalar_answers_for_the_kinds_that_have_a_type() {
	assert scalar(Kind.int_) or {
		assert false
		return
	}.same(int_type())
	assert scalar(Kind.long_double) or {
		assert false
		return
	}.describe() == 'long double'
	assert scalar(Kind.pointer) == none
	assert scalar(Kind.unknown) == none
	assert int_type().is_object() && !function_type(void_type(), [], false, true).is_object()
}

// The integer type an enum has is settled by the range of its enumerators, one
// row at a time against gcc 16.2.1. A non-negative enum is unsigned int until a
// value does not fit, and then unsigned long; an enum with a negative value is
// int until a value does not fit, and then long. The bounds are the ones the
// rule is written against: UINT_MAX, INT_MIN and INT_MAX.
fn test_an_enum_type_is_settled_by_the_range_of_its_enumerators() {
	assert enum_underlying_kind(0, 0) == .unsigned_int
	assert enum_underlying_kind(1, 3) == .unsigned_int
	assert enum_underlying_kind(0, 65535) == .unsigned_int
	assert enum_underlying_kind(0, 4294967295) == .unsigned_int
	assert enum_underlying_kind(0, 4294967296) == .unsigned_long
	assert enum_underlying_kind(0, 9223372036854775807) == .unsigned_long
	assert enum_underlying_kind(-3, 3) == .int_
	assert enum_underlying_kind(-2147483648, 2147483647) == .int_
	assert enum_underlying_kind(-1, 4000000000) == .long
	assert enum_underlying_kind(-1, 9223372036854775807) == .long
}

// A use of an enumerator has the type gcc 16.2.1 gives it, which is not always
// the enum's own type: an enumerator of a 4-byte enum that fits int is an int
// even when the enum is unsigned int, and every enumerator of a long or unsigned
// long enum is that wider type.
fn test_an_enumerator_has_the_type_gcc_gives_a_use_of_it() {
	assert enum_constant_kind(.unsigned_int, 0) == .int_
	assert enum_constant_kind(.unsigned_int, 65535) == .int_
	assert enum_constant_kind(.unsigned_int, 4000000000) == .unsigned_int
	assert enum_constant_kind(.int_, -3) == .int_
	assert enum_constant_kind(.int_, 2147483647) == .int_
	assert enum_constant_kind(.long, -1) == .long
	assert enum_constant_kind(.long, 4000000000) == .long
	assert enum_constant_kind(.unsigned_long, 5000000000) == .unsigned_long
}

// An enumerated type is compatible with the integer type its enumerators
// require, and carries that type's representation: `underlying_type` answers the
// scalar, and `storage_spelling` spells it for a back end that has no spelling
// for the tag.
fn test_an_enum_answers_with_its_underlying_type() {
	e := enum_type('E', .unsigned_int)
	assert e.enum_underlying() == .unsigned_int
	assert e.underlying_type().describe() == 'unsigned int'
	assert e.storage_spelling() == 'unsigned int'
	assert e.is_unsigned_type()
	assert !enum_type('E', .int_).is_unsigned_type()
	assert enum_type('E', .long).underlying_type().describe() == 'long'
	// A type that is not an enum answers with itself, which is what makes these
	// safe to ask of any type.
	assert int_type().enum_underlying() == .int_
	assert int_type().underlying_type().describe() == 'int'
	assert int_type().storage_spelling() == 'int'
	assert !int_type().is_unsigned_type()
}
