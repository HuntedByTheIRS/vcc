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
// An enumerated type promotes to int in this model. Measured, gcc 16.2.1 does
// not agree: `enum E { A }; unsigned int f(unsigned int); unsigned int f(enum E);`
// is accepted, and the same pair written with int is refused as conflicting
// types, so gcc gives an enum whose enumerators are non-negative the compatible
// type unsigned int and promotes it accordingly. This model holds the int
// reading instead, which is a divergence from gcc recorded here to be settled by
// the milestone that owns enumerators, because that is where an enumerator's
// value can decide the compatible type.
//
// A type that is not an integer promotes to itself, which is what makes the
// function safe to call on any operand of an arithmetic expression.
pub fn integer_promotion(t Type, rep Representation) !Type {
	if t.kind == .unknown || t.kind == .opaque {
		return error('${t.describe()} has no promotion: it is not a type this compiler resolved')
	}
	if t.kind == .enum_ {
		return int_type()
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
// The complex types are the back end milestone's, so a conversion that needs one
// is refused by name rather than approximated with the real type underneath it.
pub fn usual_arithmetic_conversions(a Type, b Type, rep Representation) !Type {
	if a.is_complex() || b.is_complex() {
		return error('the usual arithmetic conversions of ${a.describe()} and ${b.describe()} need the complex types, which this compiler has no arithmetic for yet')
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
	if to.kind == from.kind {
		return true
	}
	to_width := rep.size_of(to) or {
		return error('whether ${from.describe()} converts to ${to.describe()} without a change of value needs the width of ${to.describe()}, which ${missing_note(rep, [
			to.kind,
			from.kind,
		])} does not carry')
	}
	from_width := rep.size_of(from) or {
		return error('whether ${from.describe()} converts to ${to.describe()} without a change of value needs the width of ${from.describe()}, which ${missing_note(rep, [
			to.kind,
			from.kind,
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
	if to.kind.is_unsigned_integer() && from.kind.is_signed_integer() {
		return false
	}
	if to.kind.is_signed_integer() && from.kind.is_unsigned_integer() {
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
	if to.is_complex() || from.is_complex() {
		return 'the arithmetic on the complex types belongs to the back end milestone, so ${from.describe()} is not assigned to ${to.describe()} yet'
	}
	if to.is_arithmetic() && from.is_arithmetic() {
		return none
	}
	if to.is_pointer() {
		target := to.pointee() or { return none }
		if from.is_pointer() {
			source := from.pointee() or { return none }
			if target.is_void() && source.is_function() {
				return 'a constraint violation: a pointer to void converts only to and from a pointer to an object type, and ${from.describe()} points to a function'
			}
			if source.is_void() && target.is_function() {
				return 'a constraint violation: a pointer to void converts only to and from a pointer to an object type, and ${to.describe()} points to a function'
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
		if to.is_aggregate() && from.is_aggregate() && to.same(from) {
			return none
		}
		return 'a constraint violation: ${from.describe()} is not assigned to ${to.describe()}, and an object of an aggregate type is assigned to an object of its own type'
	}
	return none
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
