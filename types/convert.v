module types

// The conversions of clause 6.3: the integer promotions, the usual arithmetic
// conversions, decay, the rules for `void *`, and the constraint an assignment
// between two pointer types has to satisfy.
//
// Every rule here is a question about the types and, where the standard's answer
// depends on how wide a type is, about the object representation. Those questions
// are asked of the Representation the caller hands in, so a rule whose answer
// needs a width the target description does not carry is refused rather than
// guessed at with a number this module has no business knowing.

// integer_promotion is 6.3.1.1.
//
// `_Bool`, the character types and `short` all promote to int, and the standard
// guarantees it rather than the machine: int's range is at least -32767 to 32767,
// which holds every value of an 8-bit character type and of a signed short of any
// width an int can match. `unsigned short` is the one that depends on the
// machine, because an int of 16 bits cannot hold 65535, so the representation
// decides it and a description that does not carry both widths gets a refusal.
//
// An enumerated type promotes to the integer type its enumerators require.
// Measured, gcc 16.2.1 does not promote it to int: `enum E { A }; unsigned int
// f(unsigned int); unsigned int f(enum E);` is accepted, so an enum whose
// enumerators are non-negative is compatible with unsigned int, and
// `_Generic((enum c)0 + 0, ...)` is `unsigned int` for such an enum, `int` for
// one with a negative enumerator, and `unsigned long`/`long` for one whose
// values do not fit 32 bits. Every one of those kinds ranks at or above int, so
// the promotion is the underlying type itself.
//
// A type that is not an integer promotes to itself, which is what makes the
// function safe to call on any operand of an arithmetic expression.
pub fn integer_promotion(t Type, rep Representation) !Type {
	if t.kind == .unknown || t.kind == .opaque {
		return error('${t.describe()} has no promotion: it is not a type this compiler resolved')
	}
	if t.kind == .enum_ {
		return t.underlying_type()
	}
	if !t.kind.is_integer() {
		return t
	}
	if t.kind.rank() >= Kind.int_.rank() {
		// int and everything above it keeps its own type: there is no wider
		// signed type that represents every value of a long.
		return scalar(t.kind) or { return t }
	}
	if t.kind == .unsigned_short {
		int_width := rep.size_of(int_type()) or {
			return error('the promotion of unsigned short needs the width of int, which ${missing_note(rep, [
				Kind.int_,
				.short,
			])} does not carry')
		}
		short_width := rep.size_of(short_type()) or {
			return error('the promotion of unsigned short needs the width of short, which ${missing_note(rep, [
				Kind.int_,
				.short,
			])} does not carry')
		}
		if int_width > short_width {
			return int_type()
		}
		return unsigned_int_type()
	}
	return int_type()
}

// usual_arithmetic_conversions is 6.3.1.8: the type both operands of an
// arithmetic operator are converted to before it runs.
//
// The floating types come first, widest wins. Both integer operands are then
// promoted, and the integer rules follow: the same type stays itself, two types
// of the same signedness take the higher rank, and a signed and an unsigned type
// take the unsigned one unless the signed one can represent every value of it, in
// which case the signed one wins. That last question is a width question, so
// `unsigned` and `long` are decided by the representation and refused without it.
//
// A 128-bit operand is an integer that ranks above every integer the standard
// has and below float, so it takes every integer pairing and loses to a floating
// operand; against an unsigned standard type the signed 128-bit type wins on the
// width rule above, because its 16 bytes hold every value a 4-byte or 8-byte
// type has. Measured with `_Generic` on gcc 16.2.1, one row at a time:
// `__int128` added to any integer type the standard has is `__int128`,
// `unsigned __int128` added to the same is `unsigned __int128`, the two 128-bit
// kinds added either way round are `unsigned __int128`, `__int128 + float` is
// `float` and `__int128 + long double` is `long double`. Every one of those rows
// is asserted in the test beside this file.
//
// A pointer operand never reaches the rules above, because a pointer is not
// arithmetic. Measured, gcc types `int * + __int128` and `__int128 + int *` as
// `int *`: that expression is pointer arithmetic and its type comes from the
// pointer rather than from a conversion, which the reader answers where it reads
// the operator.
//
// The complex types follow 6.3.1.8's own first rule: an operand of a complex
// type makes the result complex, and the two corresponding real types follow the
// rules below. The corresponding real type of a complex operand is its
// component, and of a real operand itself, so `double + float _Complex` takes
// the double rules and the result is `double _Complex`. Measured with `_Generic`
// on gcc 16.2.1: `1.0 + 1.0f * _Complex_I` is `double _Complex`,
// `1.0f + 1.0f * _Complex_I` is `float _Complex`, and `1 + 1.0 * _Complex_I` is
// `double _Complex`.
pub fn usual_arithmetic_conversions(a Type, b Type, rep Representation) !Type {
	if a.is_complex() || b.is_complex() {
		combined := usual_arithmetic_conversions(complex_component_type(a), complex_component_type(b), rep)!
		component := combined.kind.complex_of() or {
			return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} have a complex operand whose real type ${combined.describe()} has no complex type')
		}
		return scalar(component) or {
			return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} name ${component}, which is not a type this model has')
		}
	}
	if !a.is_arithmetic() || !b.is_arithmetic() {
		return error('the usual arithmetic conversions need two arithmetic types, and ${a.describe()} and ${b.describe()} are not both arithmetic')
	}
	if a.kind == .long_double || b.kind == .long_double {
		return long_double_type()
	}
	if a.kind == .double || b.kind == .double {
		return double_type()
	}
	if a.kind == .float || b.kind == .float {
		return float_type()
	}
	left := integer_promotion(a, rep)!
	right := integer_promotion(b, rep)!
	if left.kind == right.kind {
		return left
	}
	left_signed := left.kind.is_signed_integer()
	if left_signed == right.kind.is_signed_integer() {
		return if left.kind.rank() > right.kind.rank() { left } else { right }
	}
	signed_side := if left_signed { left } else { right }
	unsigned_side := if left_signed { right } else { left }
	if unsigned_side.kind.rank() >= signed_side.kind.rank() {
		return unsigned_side
	}
	signed_width := rep.size_of(signed_side) or {
		return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} need the width of ${signed_side.describe()}, which ${missing_note(rep, [
			signed_side.kind,
			unsigned_side.kind,
		])} does not carry')
	}
	unsigned_width := rep.size_of(unsigned_side) or {
		return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} need the width of ${unsigned_side.describe()}, which ${missing_note(rep, [
			signed_side.kind,
			unsigned_side.kind,
		])} does not carry')
	}
	if signed_width > unsigned_width {
		return signed_side
	}
	return unsigned_counterpart(signed_side) or {
		return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} have no unsigned counterpart for ${signed_side.describe()}')
	}
}

// value_preserving is 6.3.1.3: whether every value of one integer type is a value
// of the other, which is the difference between a conversion and an
// implementation-defined one. It is the question a diagnostic about a narrowing
// conversion asks, and it needs the widths.
pub fn value_preserving(to Type, from Type, rep Representation) !bool {
	if !to.is_integer() || !from.is_integer() {
		return error('whether ${from.describe()} converts to ${to.describe()} without a change of value is a question about integer types')
	}
	// An enumerated type is asked about the integer type its enumerators
	// require, which is the type a value of it converts to and from.
	to_type := to.underlying_type()
	from_type := from.underlying_type()
	if to_type.kind == from_type.kind {
		return true
	}
	to_width := rep.size_of(to_type) or {
		return error('whether ${from.describe()} converts to ${to.describe()} without a change of value needs the width of ${to.describe()}, which ${missing_note(rep, [
			to_type.kind,
			from_type.kind,
		])} does not carry')
	}
	from_width := rep.size_of(from_type) or {
		return error('whether ${from.describe()} converts to ${to.describe()} without a change of value needs the width of ${from.describe()}, which ${missing_note(rep, [
			to_type.kind,
			from_type.kind,
		])} does not carry')
	}
	if to_width > from_width {
		return true
	}
	if to_width < from_width {
		return false
	}
	// The same width: only a signed type can hold everything an unsigned type of
	// the same width holds, and it cannot.
	if to_type.kind.is_unsigned_integer() && from_type.kind.is_signed_integer() {
		return false
	}
	if to_type.kind.is_signed_integer() && from_type.kind.is_unsigned_integer() {
		return false
	}
	return true
}

// decay is 6.3.2.1: an array becomes a pointer to its first element, and a
// function becomes a pointer to itself, which is what a value of either type
// means in an expression that reads it.
//
// It is not applied everywhere, and the places it is not are the places the
// standard calls out: `&a` is a pointer to the array and not to its first
// element, `sizeof a` is the size of the whole array, and a string literal used
// to initialize an array of characters keeps its array type. The caller asks for
// a decay where a value is wanted, and those three places do not ask.
pub fn decay(t Type) Type {
	if t.kind == .array && t.base != unsafe { nil } {
		// The element carries the qualifiers, since `const int a[4]` is an
		// array of const int; the array's own qualifiers are merged in for a
		// reader that put them there instead.
		return pointer_to(qualified(*t.base, t.quals))
	}
	if t.kind == .function {
		return pointer_to(unqualified(t))
	}
	return t
}

// assignment_problem is the constraint on assignment, 6.5.16.1, and with it the
// constraint on an argument, which 6.5.2.2 says is checked as if by assignment.
// It answers with the reason the assignment is a constraint violation, and with
// none when it is one the standard allows.
//
// It is the one place the pointer rules of 6.5.16.1 live: a pointer to void
// converts to and from a pointer to any object or incomplete type and not to a
// pointer to a function, two pointers are compatible when they point to
// compatible types, and the qualifiers on the type being pointed at survive.
// A second implementation of the same relation would be a second answer waiting
// to disagree with this one.
//
// constant_zero says the source is an integer constant expression with the value
// zero, which is the null pointer constant: it converts to every pointer type,
// while any other integer does not convert to one at all.
pub fn assignment_problem(to Type, from Type, constant_zero bool) ?string {
	if to.kind == .unknown || from.kind == .unknown {
		// Nothing is claimed about a type this compiler did not resolve.
		return none
	}
	if to.is_arithmetic() && from.is_arithmetic() {
		// 6.5.16.1: an arithmetic value converts to every arithmetic type. A
		// complex target takes a real value with a zero imaginary part, and a
		// real target takes a complex value with its imaginary part dropped,
		// which is the conversion 6.3.1.7 defines and not a constraint
		// violation. Measured on gcc 16.2.1: `double d = 1.0 + 2.0 * I;` is
		// accepted and d is 1.0.
		return none
	}
	if to.is_pointer() {
		target := to.pointee() or { return none }
		if from.is_pointer() {
			source := from.pointee() or { return none }
			if target.is_void() && source.is_function() {
				// 6.5.16.1 converts a pointer to void to and from a pointer to
				// an object or incomplete type, and a function type is neither,
				// so this conversion is outside the standard. Measured, gcc
				// 16.2.1 accepts it in every mode and reports it only under
				// -pedantic, so it is a question the flags decide and not an
				// error: the conversion is allowed here, and the caller raises
				// the pedantic diagnostic with `function_void_pointer_problem`.
				return none
			}
			if source.is_void() && target.is_function() {
				// The direction the paragraph above names is the one from the
				// function pointer, and this is the one to it; both are the
				// same extension and both are allowed for the same reason.
				return none
			}
			if (target.is_void() && source.is_object()) || (source.is_void() && target.is_object()) {
				if !target.quals.contains(source.quals) {
					return 'a constraint violation: ${to.describe()} drops a qualifier that ${from.describe()} has on the type it points to'
				}
				return none
			}
			if !unqualified(target).compatible(unqualified(source)) {
				return 'a constraint violation: ${from.describe()} does not point to a type compatible with what ${to.describe()} points to'
			}
			if !target.quals.contains(source.quals) {
				return 'a constraint violation: ${to.describe()} drops a qualifier that ${from.describe()} has on the type it points to'
			}
			return none
		}
		// 6.5.16.1: the only integer that converts to a pointer is the integer
		// constant expression with the value zero, the null pointer constant,
		// and that holds for every pointer type, a pointer to a function
		// included. Measured, gcc 16.2.1 compiles and runs
		// `int h(int (*fp)(void)) { return 0; } int main(void) { return h(0); }`
		// under `-std=c99 -pedantic-errors`, and refuses `h(1)`, so the question
		// is asked before the target says what it points to.
		if from.is_integer() {
			if constant_zero {
				return none
			}
			return 'a constraint violation: ${from.describe()} is an integer and ${to.describe()} is a pointer, and only an integer constant of value zero converts to one'
		}
		if target.is_function() {
			return 'a constraint violation: only a pointer to an object or an incomplete type converts to ${to.describe()}, and it points to a function'
		}
		return 'a constraint violation: ${from.describe()} is an integer and ${to.describe()} is a pointer, and only an integer constant of value zero converts to one'
	}
	if from.is_pointer() {
		// 6.5.16.1's last form: the target is _Bool and the source is a pointer.
		// Measured, gcc 16.2.1 accepts `int *p; _Bool b = p;` under
		// `-std=c99 -pedantic-errors`, where an int target with the same source
		// is refused.
		if to.kind == .bool_ {
			return none
		}
		return 'a constraint violation: ${from.describe()} is a pointer and ${to.describe()} is not'
	}
	if to.is_void() {
		return 'a constraint violation: there is no object of type void to assign to'
	}
	if to.is_function() {
		return 'a constraint violation: a function type is not the type of an object, so nothing is assigned to ${to.describe()}'
	}
	if to.is_aggregate() || from.is_aggregate() {
		// 6.5.16.1: an object of a struct or union type is assigned to an object
		// of the same type and to nothing else. Two declarations of one tag are
		// one type, so the copy is the bytes of the object and no conversion is
		// involved.
		//
		// The top-level qualifiers are not part of that sameness. 6.3.2.1p2
		// says the value a read lvalue is converted to has the unqualified
		// version of its type, so `const struct string` read as a value is a
		// `struct string`, and assigning or passing it where the unqualified
		// type is wanted is what gcc 16.2.1 accepts. A const-qualified member is
		// a property of the type rather than of the reading, so two types that
		// differ in a member's qualifiers are still told apart here. Whether the
		// object written to may be written at all is a separate question, asked
		// by `assignment_target_problem` where the target is known to be one.
		if to.is_aggregate() && from.is_aggregate() && unqualified(to).same(unqualified(from)) {
			return none
		}
		return 'a constraint violation: ${from.describe()} is not assigned to ${to.describe()}, and an object of an aggregate type is assigned to an object of its own type'
	}
	return none
}

// function_void_pointer_problem names the standard's objection to a conversion
// between a pointer to a function and a pointer to void, which 6.5.16.1 does
// not allow: a pointer to void converts to and from a pointer to an object or
// incomplete type, and a function type is neither. Measured, gcc 16.2.1 accepts
// the conversion in every mode and reports it only under -pedantic, so it is a
// question the flags decide rather than an error, and `assignment_problem`
// allows it. This is what a caller asks to raise that diagnostic, and the
// direction is named the way gcc names it.
//
// Either side may arrive as the function type itself or as a pointer to one: a
// function designator has not decayed everywhere the question is asked, and the
// answer is the same either way. A pointer to void is only ever a pointer.
pub fn function_void_pointer_problem(to Type, from Type) ?string {
	target_function := to.is_function() || (to.is_pointer() && (to.pointee() or { return none }).is_function())
	source_function := from.is_function() || (from.is_pointer() && (from.pointee() or { return none }).is_function())
	target_void := to.is_pointer() && (to.pointee() or { return none }).is_void()
	source_void := from.is_pointer() && (from.pointee() or { return none }).is_void()
	if target_void && source_function {
		return 'ISO C forbids conversion of function pointer to object pointer type'
	}
	if source_void && target_function {
		return 'ISO C forbids conversion of object pointer to function pointer type'
	}
	return none
}

// assignment_target_problem is the half of 6.5.16.1 that is about the operand
// written rather than the operand read: the left operand of an assignment has to
// be a modifiable lvalue. 6.3.1p1 says an object is not one when it is
// const-qualified, or when it is a structure or union with a const-qualified
// member, and a name with a subscript or a member is not one where the object it
// is read from fails the same test.
//
// This is asked apart from `assignment_problem` because the two operands differ
// in direction. A read value drops its top-level qualifiers, so a `const struct
// string` may initialize a `struct string`; but an object declared const may not
// be written at all, and initializing a const object with the same type is the
// one write that is allowed, which is why the question is asked where the
// target is known to be written rather than where a type is merely converted.
//
// The type does not carry the difference between `const int *p` and `int *const
// p`, and it does not need to: a pointer's own qualifiers are read off the
// pointer type and the pointee's from the base, so a target that is a
// dereference comes here as the pointee's type and a target that is a name comes
// here as the declared one.
pub fn assignment_target_problem(to Type) ?string {
	if to.is_const() {
		return 'a constraint violation: ${to.describe()} is const-qualified, and a const-qualified object is not a modifiable lvalue'
	}
	if to.is_aggregate() && to.has_const_member() {
		return 'a constraint violation: ${to.describe()} has a const-qualified member, and an object of a type with one is not a modifiable lvalue'
	}
	return none
}

// complex_component_type is the type the usual arithmetic conversions apply to a
// complex operand: its corresponding real type, which is its component, and
// itself for every other type. 6.3.1.8 sets the complex part of the result
// aside and applies the real rules to these two.
fn complex_component_type(t Type) Type {
	if component := t.kind.complex_component() {
		return scalar(component) or { return t }
	}
	return t
}

// unsigned_counterpart is the unsigned type of the same rank as a signed one,
// which is where the usual arithmetic conversions land when neither type can hold
// the other's values.
fn unsigned_counterpart(t Type) ?Type {
	return match t.kind {
		.char_, .signed_char { unsigned_char_type() }
		.short { unsigned_short_type() }
		.int_, .enum_ { unsigned_int_type() }
		.long { unsigned_long_type() }
		.long_long { unsigned_long_long_type() }
		.int128 { unsigned_int128_type() }
		else { none }
	}
}

// missing_note names the entries a description would have to carry for a rule to
// have an answer, so the refusal says what to add rather than only that the
// question could not be answered.
fn missing_note(rep Representation, kinds []Kind) string {
	mut names := []string{}
	for kind in kinds {
		if !rep.knows(kind) {
			names << kind_name(kind)
		}
	}
	if names.len == 0 {
		return 'the target description'
	}
	return 'the target description, which carries no ${names.join(' and no ')}'
}

// kind_name spells a kind the way a declaration does, for a diagnostic that names
// the missing entries rather than only their number.
fn kind_name(kind Kind) string {
	scalar_type := scalar(kind) or { return '${kind}' }
	return scalar_type.describe()
}
