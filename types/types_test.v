module types

// The type model is data, so these tests read the data back: what a kind is, what
// a derived type is derived from, and what two types have to do with each other.

fn test_the_scalar_types_are_complete_and_spelled_the_way_c_writes_them() {
	assert int_type().describe() == 'int'
	assert unsigned_int_type().describe() == 'unsigned int'
	assert long_long_type().describe() == 'long long'
	assert unsigned_long_long_type().describe() == 'unsigned long long'
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

fn test_an_aggregate_is_the_same_type_by_its_tag_and_the_members_under_it() {
	members := [
		Member{
			name: 'a'
			typ:  int_type()
		},
	]
	s := struct_type('S', members)
	assert s.same(struct_type('S', [
		Member{
			name: 'a'
			typ:  int_type()
		},
	]))
	// The same tag with different members is not the same type, and the two
	// cannot both be declared in one scope: the declaration that read the second
	// one reports the redefinition.
	assert !s.same(struct_type('S', [
		Member{
			name: 'b'
			typ:  char_type()
		},
	]))
	assert s.describe() == 'struct S'
	assert union_type('U', members).describe() == 'union U'
	assert enum_type('E').describe() == 'enum E'
	assert struct_type('', []).describe() == 'struct <anonymous>'
	assert !s.same(struct_type('T', members))
	assert !s.same(union_type('S', members))
	assert s.is_aggregate() && s.is_complete()
}

fn test_compatibility_is_sameness() {
	assert int_type().compatible(int_type())
	assert !int_type().compatible(unsigned_int_type())
	// The three character types are three distinct types (6.2.5p15), and the
	// mixes are refused rather than allowed: measured, gcc 16.2.1 reports
	// `conflicting types for f1` for `void f1(char *); void f1(unsigned char *);`
	// and `pointer targets in passing argument 1 of wants differ in signedness`
	// for a `char *` argument to a parameter of `unsigned char *`.
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
