module types

import math

// The type model is data, so these tests read the data back: what a kind is, what
// a derived type is derived from, and what two types have to do with each other.

// A double is exactly a long double, so the conversion is a copy of the fields
// and not a rounding. The bytes are gcc 16.2.1's, read back from a long double
// with memcpy for `1.5L`, `-0.0L`, `HUGE_VALL`, `-HUGE_VALL` and
// `__builtin_nanl("")`: an infinity keeps its sign, a NaN keeps its quiet bit,
// and a double subnormal becomes an extended normal because the extended
// exponent range reaches below the double's.
fn test_a_double_converts_to_the_extended_format_bit_for_bit() {
	assert long_double_from_double(0.0).is_zero()
	negative_zero := long_double_from_double(-0.0)
	assert negative_zero.mantissa == 0 && negative_zero.sign_exp == 0x8000
	positive_infinity := long_double_from_double(math.inf(1))
	assert positive_infinity.mantissa == u64(0x8000000000000000)
	assert positive_infinity.sign_exp == 0x7fff
	negative_infinity := long_double_from_double(-math.inf(1))
	assert negative_infinity.mantissa == u64(0x8000000000000000)
	assert negative_infinity.sign_exp == 0xffff
	nan := long_double_from_double(math.nan())
	// The kind is what matters and what is checked: the exponent field all
	// ones with the integer bit and the quiet bit above it set. The payload
	// below them is the double's own, which is why the bytes are not asserted
	// here - gcc's `__builtin_nanl("")` and this host's `math.nan()` carry
	// different payloads, and both are a quiet NaN.
	assert nan.sign_exp == 0x7fff
	assert nan.mantissa & u64(0xc000000000000000) == u64(0xc000000000000000)
	one_and_a_half := long_double_from_double(1.5)
	assert one_and_a_half.mantissa == u64(0xc000000000000000)
	assert one_and_a_half.sign_exp == 0x3fff
	// The smallest double subnormal, 2^-1074, is an extended normal with the
	// extended format's smallest exponent field and the integer bit alone.
	tiny := long_double_from_double(math.f64_from_bits(1))
	assert tiny.mantissa == u64(0x8000000000000000)
	assert tiny.sign_exp == 0x3bcd
}

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
	// The GNU 128-bit floating type ranks above long double and below the
	// complex types, which is the order gcc 16.2.1 measures: `_Float128 + long
	// double` is `_Float128` and `_Float128 + float _Complex` is `float
	// _Complex`.
	assert Kind.long_double.rank() < Kind.float128.rank()
	assert Kind.float128.rank() < Kind.complex_float.rank()
	assert Kind.void_.rank() == -1
}

// A vector is the GNU type `__attribute__((vector_size(N)))` declares: an array
// for storage, sizeof and subscripting, and not an array anywhere else. Measured
// on gcc 16.2.1, a vector is not converted to a pointer (`_Generic(v, int[4]: 1,
// default: 2)` selects the default for a vector) and a vector with the same
// components as an array is a different type from that array.
fn test_a_vector_is_an_array_that_is_not_converted_to_a_pointer() {
	v := vector_of(int_type(), 4)
	assert v.is_array() && v.is_vector()
	assert v.count == 4 && v.describe() == 'int[4]'
	element := v.element() or {
		assert false
		return
	}
	assert element.kind == .int_
	// A plain array of the same shape is not a vector, and the two are not the
	// same type even though they are laid out the same.
	plain := array_of(int_type(), 4)
	assert !plain.is_vector()
	assert !v.same(plain) && !plain.same(v)
	// The value keeps the vector type where an array designator decays, which
	// is what routes `a + b` to the element-wise operator.
	assert decay(v).is_vector()
	assert decay(plain).is_pointer()
	// Two vectors of one component type are one type.
	assert v.same(vector_of(int_type(), 4))
}

// `_Float128` is the GNU 128-bit floating type. It is a kind of its own rather
// than long double because its format is IEEE binary128, and this target's long
// double is the x87 extended format; the two are both sixteen bytes but are not
// the same type. Both are the extended kinds this back end carries through the
// same sixteen-byte storage.
fn test_the_float128_kind_is_an_extended_type_of_its_own() {
	assert float128_type().kind == .float128
	assert float128_type().describe() == '__float128'
	assert float128_type().is_floating() && float128_type().kind.is_extended()
	assert long_double_type().kind.is_extended()
	assert !long_double_type().same(float128_type())
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
	v := vla_array_of(int_type(), 3)
	assert v.is_array() && v.vla
	assert v.count == -1
	assert v.vla_id == 3
	assert v.is_complete()
	assert v.describe() == 'int[]'
	// The two are not the same type: an object whose size is computed at run
	// time cannot be a declaration something later completes.
	assert !v.same(array_of(int_type(), -1))
	assert v.same(vla_array_of(int_type(), 3))
	// A variable-length array of a complete element type is complete; one whose
	// element type is not has no size whatever its bound says.
	assert !vla_array_of(opaque_type('size_t'), 3).is_complete()
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

// A qualifier belongs to the declaration and not to the storage, so the spelling
// the back end reads off a type has it taken off. `const double` and `double`
// are the same eight bytes, and the class of a floating object is read off the
// spelling, so a spelling that kept the `const` made `initializer_for` answer the
// integer class for it and wrote a const `double` aggregate as integers.
fn test_storage_spelling_drops_the_qualifiers() {
	const_double := qualified(double_type(), Qualifiers{
		const_: true
	})
	assert const_double.describe() == 'const double'
	assert const_double.storage_spelling() == 'double'
	assert double_type().storage_spelling() == 'double'
	assert float_type().storage_spelling() == 'float'
	// A qualifier on a pointer is dropped too, and the pointee keeps its own.
	assert qualified(pointer_to(double_type()), Qualifiers{
		const_: true
	}).storage_spelling() == 'double *'
	assert pointer_to(const_double).storage_spelling() == 'const double *'
}

// 6.7.6.3p15: in the determination of type compatibility each parameter
// declared with a qualified type is taken as having the unqualified version of
// its declared type. The qualifier belongs to the parameter, so `void *restrict`
// and `void *` are one parameter type and two function types that differ only
// there are one type. The qualifier of what the parameter points at is not the
// parameter's own and stays, so `const void *` and `void *` are two parameter
// types. Measured, gcc 16.2.1 under `-std=c99` accepts
// `void *memcpy(void *restrict, const void *restrict, unsigned long);` against
// `void *memcpy(void *, const void *, unsigned long);` and refuses
// `void f(void *); void f(const void *);` with `conflicting types for f`.
fn test_a_parameters_own_qualifiers_do_not_tell_two_function_types_apart() {
	plain := function_type(void_type(), [
		Param{
			name: 'd'
			typ:  pointer_to(void_type())
		},
	], false, true)
	restricted := function_type(void_type(), [
		Param{
			name: 'd'
			typ:  qualified(pointer_to(void_type()), Qualifiers{
				restrict_: true
			})
		},
	], false, true)
	const_param := function_type(void_type(), [
		Param{
			name: 'd'
			typ:  qualified(pointer_to(void_type()), Qualifiers{
				const_: true
			})
		},
	], false, true)
	volatile_param := function_type(void_type(), [
		Param{
			name: 'd'
			typ:  qualified(pointer_to(void_type()), Qualifiers{
				volatile_: true
			})
		},
	], false, true)
	// Each of the three qualified spellings names the same parameter type as
	// the plain one, so neither declaration is a conflict with the other.
	assert plain.compatible(restricted)
	assert restricted.compatible(plain)
	assert plain.same(restricted)
	assert plain.compatible(const_param)
	assert const_param.compatible(plain)
	assert plain.compatible(volatile_param)
	assert volatile_param.compatible(plain)
	// The qualifier of the pointee is the pointee's own, so a pointer to a const
	// void is a different parameter type from a pointer to void, and the two
	// function types are not compatible. This is the assertion that fails if the
	// unqualification is applied one level too deep.
	to_const := function_type(void_type(), [
		Param{
			name: 'd'
			typ:  pointer_to(qualified(void_type(), Qualifiers{
				const_: true
			}))
		},
	], false, true)
	assert !plain.compatible(to_const)
	assert !to_const.compatible(plain)
	assert !plain.same(to_const)
}

// The qualifier set answers three questions the rest of the model asks of it:
// whether it says anything at all, how a declaration spells it, and whether one
// set contains another.
fn test_an_empty_qualifier_set_says_nothing() {
	assert Qualifiers{}.is_empty()
	assert !Qualifiers{
		const_: true
	}.is_empty()
	assert !Qualifiers{
		volatile_: true
	}.is_empty()
	assert !Qualifiers{
		restrict_: true
	}.is_empty()
}

fn test_restrict_is_a_qualifier_a_declaration_can_write() {
	// The three are spelled in the order a declaration may write them, and
	// restrict is one of them rather than a word this model drops.
	assert Qualifiers{
		restrict_: true
	}.describe() == 'restrict'
	assert Qualifiers{
		const_:    true
		volatile_: true
		restrict_: true
	}.describe() == 'const volatile restrict'
	// A restrict pointer is a different type from a plain one, so the qualifier
	// is carried on the type and not written into the pointer's own shape.
	plain := pointer_to(int_type())
	restricted := qualified(plain, Qualifiers{
		restrict_: true
	})
	assert restricted.describe() == 'int * restrict'
	assert !restricted.same(plain)
}

fn test_restrict_participates_in_the_containment_question() {
	plain := Qualifiers{}
	restrict_q := Qualifiers{
		restrict_: true
	}
	assert restrict_q.contains(plain)
	assert !plain.contains(restrict_q)
	assert restrict_q.contains(restrict_q)
	// Every qualifier the other set names has to be present, so a set asking for
	// const alone does not contain one that also asks for restrict.
	assert !Qualifiers{
		const_: true
	}.contains(restrict_q)
	assert !restrict_q.contains(Qualifiers{
		const_: true
	})
}

// is_unsigned names the kinds a value of which is never negative, which is asked
// where a widened value fills the word above it with a sign or with zero and
// where two 128-bit values pick between the signed and the unsigned order.
fn test_the_unsigned_kinds_are_the_ones_a_value_of_which_is_never_negative() {
	assert Kind.bool_.is_unsigned()
	assert Kind.unsigned_char.is_unsigned()
	assert Kind.unsigned_short.is_unsigned()
	assert Kind.unsigned_int.is_unsigned()
	assert Kind.unsigned_long.is_unsigned()
	assert Kind.unsigned_long_long.is_unsigned()
	assert Kind.unsigned_int128.is_unsigned()
	for k in [Kind.char_, .signed_char, .short, .int_, .long, .long_long, .int128, .enum_, .float,
		.double, .long_double, .complex_double, .pointer, .array, .struct_, .void_, .unknown] {
		assert !k.is_unsigned(), '${k}'
	}
}

fn test_a_complex_kind_names_its_real_component() {
	assert (Kind.complex_float.complex_component() or { Kind.void_ }) == Kind.float
	assert (Kind.complex_double.complex_component() or { Kind.void_ }) == Kind.double
	assert (Kind.complex_long_double.complex_component() or { Kind.void_ }) == Kind.long_double
	// A real kind has no component, and neither has anything else: the answer
	// is none rather than the kind itself.
	assert Kind.double.complex_component() == none
	assert Kind.int_.complex_component() == none
	assert Kind.void_.complex_component() == none
}

fn test_a_real_kind_names_the_complex_type_it_completes() {
	assert (Kind.float.complex_of() or { Kind.void_ }) == Kind.complex_float
	assert (Kind.double.complex_of() or { Kind.void_ }) == Kind.complex_double
	assert (Kind.long_double.complex_of() or { Kind.void_ }) == Kind.complex_long_double
	// A complex kind is not its own component, and an integer has no complex
	// type of its own: the conversions convert it to the component's real type
	// first and then to the complex type the component names.
	assert Kind.complex_double.complex_of() == none
	assert Kind.int_.complex_of() == none
	// The two directions are inverses on the three kinds both of them carry.
	for real in [Kind.float, .double, .long_double] {
		complex := real.complex_of() or {
			assert false, '${real} has a complex type'
			return
		}
		assert (complex.complex_component() or { Kind.void_ }) == real
	}
}

fn test_the_complex_kinds_rank_above_the_floating_ones() {
	assert Kind.long_double.rank() < Kind.complex_float.rank()
	assert Kind.complex_float.rank() < Kind.complex_double.rank()
	assert Kind.complex_double.rank() < Kind.complex_long_double.rank()
	// A kind with no place in the conversion order has no rank, which is what
	// keeps an arithmetic question from being asked of it.
	for k in [Kind.void_, .pointer, .array, .function, .struct_, .union_, .opaque, .unknown] {
		assert k.rank() == -1, '${k}'
	}
}

fn test_every_arithmetic_kind_is_a_form_of_number() {
	for k in [Kind.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short, .int_,
		.unsigned_int, .long, .unsigned_long, .long_long, .unsigned_long_long, .int128,
		.unsigned_int128, .enum_, .float, .double, .long_double, .complex_float, .complex_double,
		.complex_long_double] {
		assert k.is_arithmetic(), '${k}'
	}
	for k in [Kind.void_, .pointer, .array, .function, .struct_, .union_, .opaque, .unknown] {
		assert !k.is_arithmetic(), '${k}'
	}
}

// The type-level predicates are the same questions asked through a value, which
// is the shape a caller with a type rather than a kind has to ask them in.
fn test_a_type_answers_the_kind_questions_it_carries() {
	assert int_type().is_integer() && !int_type().is_floating() && !int_type().is_complex()
	assert float_type().is_floating() && !float_type().is_integer()
	assert complex_double_type().is_complex() && !complex_double_type().is_floating()
	assert int_type().is_arithmetic() && complex_double_type().is_arithmetic()
	assert pointer_to(int_type()).is_scalar() && !pointer_to(int_type()).is_arithmetic()
	assert struct_type('S', []).is_aggregate() && !struct_type('S', []).is_scalar()
	assert array_of(int_type(), 2).is_array() && !array_of(int_type(), 2).is_pointer()
	assert function_type(void_type(), [], false, true).is_function()
	assert void_type().is_void() && !int_type().is_void()
	assert pointer_to(int_type()).is_pointer() && !int_type().is_pointer()
}

fn test_an_unresolved_type_is_not_an_object() {
	// is_object is asked before a declaration is laid out, and a type the model
	// never resolved describes no object to lay out.
	assert !Type{}.is_object()
	assert !Type{}.is_complete()
	assert Type{}.describe() == 'unresolved'
	assert int_type().is_object()
	assert !function_type(void_type(), [], false, true).is_object()
}

fn test_a_pointer_is_complete_whatever_it_points_at() {
	// `struct S *p;` is storage whose size is known, which is what lets a
	// pointer to a type that is not yet complete be declared at all.
	pointer := pointer_to(incomplete_tag(Kind.struct_, 'S'))
	assert pointer.is_pointer() && pointer.is_complete()
	pointed := pointer.pointee() or {
		assert false
		return
	}
	assert !pointed.is_complete()
	// A function type is complete too, and an array of an incomplete element
	// type is not complete however many elements it names.
	assert function_type(void_type(), [], false, true).is_complete()
	assert !array_of(incomplete_tag(Kind.struct_, 'S'), 4).is_complete()
}

fn test_an_opaque_type_describes_the_name_it_was_never_defined_by() {
	assert opaque_type('size_t').describe() == 'size_t'
	assert !opaque_type('size_t').is_complete()
	// A name no declaration carried describes as the empty string rather than as
	// the word for the kind, because the description is the name and there is
	// none to write.
	assert opaque_type('').kind == .opaque
	assert opaque_type('').describe() == ''
}

fn test_a_derived_description_shows_what_each_level_is_derived_from() {
	// An array of pointers and a pointer to an array are two shapes, and the
	// description has to say which brackets belong to which level.
	assert array_of(pointer_to(int_type()), 3).describe() == 'int *[3]'
	assert pointer_to(array_of(int_type(), 3)).describe() == 'int[3]*'
	assert array_of(array_of(char_type(), 2), 3).describe() == 'char[2][3]'
	// A pointer that was never given a base is written as a pointer to void,
	// which is the shape an undeclared `void *` has.
	assert Type{
		kind: .pointer
	}.describe() == 'void *'
	// An array with no base is written with the count it holds, and a count of
	// -1 is the one that means the size was not written.
	assert Type{
		kind: .array
	}.describe() == 'void[0]'
	assert Type{
		kind:  .array
		count: -1
	}.describe() == 'void[]'
}

fn test_a_function_description_names_its_parameters_and_its_sentinel() {
	two := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
		Param{
			name: 'b'
			typ:  char_type()
		},
	], false, true)
	assert two.describe() == 'int (int, char)'
	variadic := function_type(int_type(), [
		Param{
			name: 'n'
			typ:  int_type()
		},
	], true, true)
	assert variadic.describe() == 'int (int, ...)'
	// A variadic list written with no named parameter is still a prototype, and
	// the ellipsis is still written.
	assert function_type(int_type(), [], true, true).describe() == 'int (...)'
	// An array parameter is adjusted to a pointer before it is described, which
	// is what makes two declarations written differently one type.
	adjusting := function_type(void_type(), [
		Param{
			name: 'a'
			typ:  array_of(char_type(), -1)
		},
	], false, true)
	assert adjusting.describe() == 'void (char *)'
	// A list that was not written as a prototype names no parameters and says
	// nothing about a call, which is the difference `()` and `(void)` write.
	assert function_type(void_type(), [], false, true).describe() == 'void (void)'
	// A return type the model never settled reads as unresolved rather than as
	// the void the empty name would look like.
	assert Type{
		kind: .function
	}.describe() == 'void ()'
}

fn test_two_types_differ_in_a_qualifier_or_in_a_shape() {
	assert !qualified(int_type(), Qualifiers{
		const_: true
	}).same(int_type())
	assert !int_type().same(qualified(int_type(), Qualifiers{
		const_: true
	}))
	// The count of an array and the vla flag are part of the type.
	assert !array_of(int_type(), 3).same(array_of(int_type(), 4))
	assert !array_of(int_type(), 3).same(vla_array_of(int_type(), 3))
	// Two function types differ when the list is a prototype in one and not in
	// the other, and when one is variadic and the other is not.
	assert !function_type(int_type(), [], false, true).same(function_type(int_type(), [], false,
		false))
	assert !function_type(int_type(), [], false, true).same(function_type(int_type(), [], true,
		true))
	// The list itself is part of the type, so a different count of parameters is
	// a different type and a different parameter name is not: 6.7.6.3p15 reads
	// only the types.
	one := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
	], false, true)
	two := function_type(int_type(), [
		Param{
			name: 'a'
			typ:  int_type()
		},
		Param{
			name: 'b'
			typ:  int_type()
		},
	], false, true)
	assert !one.same(two)
	assert one.same(function_type(int_type(), [
		Param{
			name: 'another_name'
			typ:  int_type()
		},
	], false, true))
}

fn test_two_untagged_aggregates_differ_by_their_members() {
	// An aggregate with no tag has no name to be identified by, so the members
	// are what tells it from another: a different name or a different type is a
	// different type, and the members are compared in order.
	a := struct_type('', [
		Member{
			name: 'x'
			typ:  int_type()
		},
	])
	assert a.same(struct_type('', [
		Member{
			name: 'x'
			typ:  int_type()
		},
	]))
	assert !a.same(struct_type('', [
		Member{
			name: 'y'
			typ:  int_type()
		},
	]))
	assert !a.same(struct_type('', [
		Member{
			name: 'x'
			typ:  char_type()
		},
	]))
	// A bitfield width is part of a member's identity, so two bitfields of one
	// type at two widths are two members.
	one_bit := struct_type('', [
		Member{
			name:     'b'
			typ:      unsigned_int_type()
			bitfield: true
			bits:     1
		},
	])
	two_bits := struct_type('', [
		Member{
			name:     'b'
			typ:      unsigned_int_type()
			bitfield: true
			bits:     2
		},
	])
	assert !one_bit.same(two_bits)
	// The kind is compared first, so an untagged struct is not an untagged
	// union that happens to have the same member.
	assert !a.same(union_type('', [
		Member{
			name: 'x'
			typ:  int_type()
		},
	]))
}

fn test_the_same_tag_is_one_type_whatever_was_written_under_it() {
	// A tag is the identity: two member lists written under one tag are one
	// type, which is the reading a pointer assigned across an incomplete
	// declaration and a later definition needs.
	assert struct_type('S', [
		Member{
			name: 'a'
			typ:  int_type()
		},
	]).same(struct_type('S', [
		Member{
			name: 'b'
			typ:  char_type()
		},
	]))
	// A named struct and a named union are not one type even with the same tag,
	// and an enum is identified by its tag the same way.
	assert !struct_type('S', []).same(union_type('S', []))
	assert enum_type('E', .int_).same(enum_type('E', .int_))
	assert !enum_type('E', .int_).same(enum_type('F', .int_))
}

fn test_scalar_answers_for_every_kind_that_has_a_name() {
	for kind in basic_kinds() {
		typ := scalar(kind) or {
			assert false, '${kind} has a scalar type'
			return
		}
		assert typ.kind == kind
		assert typ.is_complete()
	}
	// The derived and unresolved kinds have no scalar: asking for one is not the
	// same question as talking about a pointer, which is a shape.
	for kind in [Kind.pointer, .array, .function, .struct_, .union_, .opaque, .unknown] {
		assert scalar(kind) == none, '${kind}'
	}
}

fn test_has_vla_reaches_through_the_array_levels() {
	// A variable-length array is one whose size the program computes at run
	// time, and an array of one is the same question one level down. A pointer
	// never is, whatever it addresses.
	assert vla_array_of(int_type(), 1).has_vla()
	assert array_of(vla_array_of(int_type(), 1), 2).has_vla()
	assert !array_of(int_type(), 2).has_vla()
	assert !int_type().has_vla()
	assert !pointer_to(vla_array_of(int_type(), 1)).has_vla()
}

fn test_an_array_parameter_with_no_element_type_becomes_a_void_pointer() {
	// The adjustment reads the element type off the base, and a base the reader
	// never settled leaves a pointer to void rather than a pointer to nothing.
	adjusted := adjust_parameter(Type{
		kind: .array
	})
	assert adjusted.is_pointer()
	assert adjusted.describe() == 'void *'
}

fn test_the_enum_rule_reads_the_bounds_it_is_written_against() {
	// The four answers turn at UINT_MAX, INT_MIN and INT_MAX exactly: one at a
	// boundary stays in the narrower kind and one past it moves out.
	assert enum_underlying_kind(0, 4294967295) == .unsigned_int
	assert enum_underlying_kind(0, 4294967296) == .unsigned_long
	assert enum_underlying_kind(-1, 4294967295) == .long
	assert enum_underlying_kind(-2147483648, 2147483647) == .int_
	assert enum_underlying_kind(-2147483649, 2147483647) == .long
	// A minimum of zero is what makes the enum unsigned, whatever its maximum:
	// an enum with no negative enumerator is never signed.
	assert enum_underlying_kind(0, 0) == .unsigned_int
	assert enum_underlying_kind(-1, 0) == .int_
}

fn test_an_enumerator_is_int_until_its_value_leaves_int() {
	// The rule reads the enum's underlying kind first: every enumerator of a
	// long or unsigned long enum is that kind, and one of a 4-byte enum is int
	// while the value fits and the underlying kind after that.
	assert enum_constant_kind(.int_, 0) == .int_
	assert enum_constant_kind(.int_, -2147483648) == .int_
	assert enum_constant_kind(.int_, 2147483647) == .int_
	assert enum_constant_kind(.unsigned_int, -2147483648) == .int_
	assert enum_constant_kind(.unsigned_int, 2147483648) == .unsigned_int
	assert enum_constant_kind(.long, 0) == .long
	assert enum_constant_kind(.unsigned_long, 0) == .unsigned_long
}

fn test_a_long_double_reports_its_unbiased_exponent() {
	// The value is mantissa * 2^(exponent - 63), so 1.5 is exponent zero, 2.0 is
	// one and 0.5 is minus one.
	assert long_double_from_double(1.5).exponent() == 0
	assert long_double_from_double(2.0).exponent() == 1
	assert long_double_from_double(0.5).exponent() == -1
	// A zero has an exponent field of zero, so the method answers the field
	// minus the bias even though there is no power of two for it to name.
	assert long_double_from_double(0.0).is_zero()
	assert long_double_from_double(0.0).exponent() == -16383
	// A negative zero is a zero too, which is what makes the check read the
	// sign apart from the magnitude.
	assert long_double_from_double(-0.0).is_zero()
}

fn test_a_long_double_round_trips_through_its_object_bytes() {
	for value in [0.0, -0.0, 1.5, -1.5, 2.0, 0.1] {
		original := long_double_from_double(value)
		restored := long_double_from_bytes(original.bytes())
		assert restored.mantissa == original.mantissa
		assert restored.sign_exp == original.sign_exp
	}
	// The ten significant bytes are the significand least significant first and
	// then the sign-and-exponent word; the six above them hold no part of the
	// value. For 1.5 the significand is c000000000000000 and the field 3fff.
	bytes := long_double_from_double(1.5).bytes()
	assert bytes[0] == u8(0) && bytes[6] == u8(0)
	assert bytes[7] == u8(0xc0)
	assert bytes[8] == u8(0xff) && bytes[9] == u8(0x3f)
	assert bytes[10] == u8(0) && bytes[15] == u8(0)
	// A NaN's quiet bit and payload survive the store and the read, which is what
	// a copy of one and a conversion out of one start from.
	nan := long_double_from_double(math.nan())
	read_back := long_double_from_bytes(nan.bytes())
	assert read_back.sign_exp == nan.sign_exp
	assert read_back.mantissa == nan.mantissa
}
