module types

// The types of the language, and the questions the standard asks about them.
//
// A type here is a value: a kind, the shapes it is derived from, the qualifiers
// written on it, and for an aggregate the tag it was declared with. It is not a
// spelling. Clause 6 asks questions about the shape of two types, whether they
// are compatible, which one wins a sum, whether a qualifier survives an
// assignment, and a name cannot answer any of them.
//
// Nothing here holds a size or an alignment. Those are facts about the machine
// and the system, so `object.v` asks a target description for them; a number
// written in this file would be a machine fact in the wrong module.

// Kind is the family a type belongs to. `.unknown` is the zero value, and that
// is deliberate: it is what a node carries when the parser could not resolve it,
// a name with no declaration in front of it or a construct this compiler has no
// rule for yet. It is first so an unset type reads as unresolved rather than as
// void.
pub enum Kind {
	unknown
	void_
	bool_
	char_
	signed_char
	unsigned_char
	short
	unsigned_short
	int_
	unsigned_int
	long
	unsigned_long
	long_long
	unsigned_long_long
	// int128 and unsigned_int128 are the two 128-bit integer types, which the
	// GNU compilers have and no standard does: gcc's `__int128`, and the
	// unsigned type its `unsigned __int128` names. Measured on gcc 16.2.1 on
	// this machine, each of them occupies 16 bytes and starts on a 16-byte
	// boundary, `signed __int128` is the signed type under another spelling,
	// and `long __int128` is refused.
	int128
	unsigned_int128
	float
	double
	long_double
	complex_float
	complex_double
	complex_long_double
	// opaque is a name this compiler read as a type and could not resolve: a
	// name a header declares that the tree has no definition for, or a tag that
	// was declared and never defined (`struct _IO_FILE;`). It carries the name
	// in tag. Nothing may be laid out in it, which is what `complete` says.
	opaque
	pointer
	array
	function
	struct_
	union_
	enum_
}

// Qualifiers are the words that sit on a type and say how the object it
// describes may be read and written. They are part of the type: `const char *`
// and `char *` are different types, and an assignment may not drop a qualifier
// the type it writes through has.
pub struct Qualifiers {
pub:
	const_    bool
	volatile_ bool
	restrict_ bool
}

pub fn (q Qualifiers) is_empty() bool {
	return !q.const_ && !q.volatile_ && !q.restrict_
}

// describe spells the qualifiers the way a declaration writes them.
pub fn (q Qualifiers) describe() string {
	mut words := []string{}
	if q.const_ {
		words << 'const'
	}
	if q.volatile_ {
		words << 'volatile'
	}
	if q.restrict_ {
		words << 'restrict'
	}
	return words.join(' ')
}

// contains says whether q has every qualifier in other. It is the question an
// assignment asks about the type on each side of it: an assignment may add a
// qualifier and may not drop one.
pub fn (q Qualifiers) contains(other Qualifiers) bool {
	if other.const_ && !q.const_ {
		return false
	}
	if other.volatile_ && !q.volatile_ {
		return false
	}
	if other.restrict_ && !q.restrict_ {
		return false
	}
	return true
}

// Type is one type. A derived type holds the type it is derived from, and the
// reference is what lets a type contain itself: `char **` is a pointer to a
// pointer to a char, and a value cannot hold that chain.
pub struct Type {
pub mut:
	kind Kind
	// base is the type a pointer points at, the element type of an array, or
	// the type a function returns.
	base &Type = unsafe { nil }
	// count is how many elements an array has, and -1 when no size was written:
	// `int a[]`, or an array whose bound was not a constant this reader could
	// read. It means nothing for any other kind.
	count int
	// members are the members of a struct or a union, in the order they were
	// written.
	members []Member
	// params are the parameters of a function type, in the order they were
	// written. prototyped says the list was written as a prototype: `int f()`
	// names no parameters at all and says nothing about the call either.
	prototyped bool
	variadic   bool
	params     []Param
	// tag is the name an aggregate, an enum or an opaque type was written with,
	// and empty for one written without a name.
	tag string
	// complete says the size of the type is known: every scalar, an array whose
	// element type is complete and whose count is written, an aggregate whose
	// members have been read, an enum whose enumerators have been read. A tag
	// declared and never defined is not complete, and nothing may be laid out
	// in it.
	complete bool
	// underlying is the integer type an enumerated type has: the kind its
	// enumerators require. 6.7.2.2p4 makes it implementation-defined and asks
	// only that every enumerator be representable; measured, gcc 16.2.1 gives
	// an enum with no negative enumerator unsigned int when every value fits
	// unsigned int and unsigned long when one does not, and an enum with a
	// negative enumerator int or long the same way, so the kind is one of
	// those four. It is .unknown for a tag whose body has not been read and
	// for every type that is not an enum.
	underlying Kind
	quals      Qualifiers
}

// Member is one member of a struct or a union. bitfield says the member was
// written with a width, and bits is that width; a bitfield of width 0 has no name
// and asks the next unit of its type to start where the member is.
pub struct Member {
pub:
	name     string
	typ      Type
	bitfield bool
	bits     int
	line     int
	col      int
}

// Param is one parameter of a function type. A parameter written with an array
// or a function type is adjusted to a pointer before it is stored here, which is
// what 6.7.5.3 asks for and what makes two declarations of one function agree.
pub struct Param {
pub:
	name string
	typ  Type
	line int
	col  int
}

// is_integer says whether the kind is one of the integer types, `_Bool` and the
// enumerated types included.
pub fn (k Kind) is_integer() bool {
	return k in [Kind.bool_, .char_, .signed_char, .unsigned_char, .short, .unsigned_short, .int_,
		.unsigned_int, .long, .unsigned_long, .long_long, .unsigned_long_long, .int128,
		.unsigned_int128, .enum_]
}

// is_unsigned says whether the kind is an unsigned integer type. It is asked
// where a value narrower than a 128-bit one is widened into one, and where a
// comparison of two 128-bit values picks between the signed and the unsigned
// order: gcc -O0 fills the word above a widened value with its sign or with zero
// depending on this, and compares a pair with a different condition depending on
// it too, measured on gcc 16.2.1.
pub fn (k Kind) is_unsigned() bool {
	return k in [Kind.bool_, .unsigned_char, .unsigned_short, .unsigned_int, .unsigned_long,
		.unsigned_long_long, .unsigned_int128]
}

// is_floating says whether the kind is a real floating type. The complex types
// are not here: they are a pair of floating values, not a floating value.
pub fn (k Kind) is_floating() bool {
	return k in [Kind.float, .double, .long_double]
}

pub fn (k Kind) is_complex() bool {
	return k in [Kind.complex_float, .complex_double, .complex_long_double]
}

// complex_component is the real type of a complex type: `float` for
// `float _Complex`, `double` for `double _Complex`, `long double` for
// `long double _Complex`. It is what 6.3.1.8 calls the corresponding real type
// and the type the usual arithmetic conversions apply their rules to once the
// complex part is set aside. A kind that is not complex answers none.
pub fn (k Kind) complex_component() ?Kind {
	return match k {
		.complex_float { Kind.float }
		.complex_double { Kind.double }
		.complex_long_double { Kind.long_double }
		else { none }
	}
}

// complex_of is the complex type whose component is this real type, and none for
// a kind with no complex type. It is where the usual arithmetic conversions land
// when one operand is complex: the result is complex, and the component is the
// real type the two components converted to.
pub fn (k Kind) complex_of() ?Kind {
	return match k {
		.float { Kind.complex_float }
		.double { Kind.complex_double }
		.long_double { Kind.complex_long_double }
		else { none }
	}
}

pub fn (k Kind) is_arithmetic() bool {
	return k.is_integer() || k.is_floating() || k.is_complex()
}

// is_scalar is arithmetic or pointer, which is what a condition and a cast to
// the integer types may take.
pub fn (k Kind) is_scalar() bool {
	return k.is_arithmetic() || k == .pointer
}

pub fn (k Kind) is_aggregate() bool {
	return k in [Kind.struct_, .union_, .array]
}

pub fn (k Kind) is_signed_integer() bool {
	return k in [Kind.char_, .signed_char, .short, .int_, .long, .long_long, .int128, .enum_]
}

pub fn (k Kind) is_unsigned_integer() bool {
	return k in [Kind.bool_, .unsigned_char, .unsigned_short, .unsigned_int, .unsigned_long,
		.unsigned_long_long, .unsigned_int128]
}

// rank is the conversion rank of 6.3.1.1. Every signed type has the same rank as
// its unsigned counterpart, which is what makes `unsigned int + int` convert to
// unsigned int rather than to int. `_Bool` is below everything, the character
// types rank below short, and the floating types rank above the integers, in the
// order 6.3.1.8 applies them. The 128-bit integers are the GNU types and rank
// above every type the standard has, which is where gcc's own conversion rank
// puts `__int128`. Measured with `_Generic` on gcc 16.2.1, that ordering is what
// the conversions follow at both ends of it: `__int128` added to any integer type
// the standard has is `__int128`, and added to `float` it is `float`. A kind with
// no rank in that order answers -1: nothing arithmetic may be asked of it.
pub fn (k Kind) rank() int {
	return match k {
		.bool_ { 0 }
		.char_, .signed_char, .unsigned_char { 1 }
		.short, .unsigned_short { 2 }
		.int_, .unsigned_int, .enum_ { 3 }
		.long, .unsigned_long { 4 }
		.long_long, .unsigned_long_long { 5 }
		.int128, .unsigned_int128 { 6 }
		.float { 7 }
		.double { 8 }
		.long_double { 9 }
		.complex_float { 10 }
		.complex_double { 11 }
		.complex_long_double { 12 }
		else { -1 }
	}
}

// is_void and the rest are the questions a caller asks of a type rather than of
// a kind, because a caller usually has a type.
pub fn (t Type) is_void() bool {
	return t.kind == .void_
}

pub fn (t Type) is_integer() bool {
	return t.kind.is_integer()
}

pub fn (t Type) is_floating() bool {
	return t.kind.is_floating()
}

pub fn (t Type) is_complex() bool {
	return t.kind.is_complex()
}

pub fn (t Type) is_arithmetic() bool {
	return t.kind.is_arithmetic()
}

pub fn (t Type) is_scalar() bool {
	return t.kind.is_scalar()
}

pub fn (t Type) is_pointer() bool {
	return t.kind == .pointer
}

pub fn (t Type) is_array() bool {
	return t.kind == .array
}

pub fn (t Type) is_function() bool {
	return t.kind == .function
}

pub fn (t Type) is_aggregate() bool {
	return t.kind.is_aggregate()
}

// is_object says whether the type describes an object rather than a function. A
// function type has no size, cannot be assigned to and cannot be the element of
// an array.
pub fn (t Type) is_object() bool {
	return t.kind != .function && t.kind != .unknown
}

// is_complete says whether the size of the type is known. An `int` is complete,
// an array of four `int`s is complete, a struct whose members have been read is
// complete, and a tag that was declared and never defined is not.
pub fn (t Type) is_complete() bool {
	if t.kind == .array {
		if t.count < 0 {
			return false
		}
		if t.base == unsafe { nil } {
			return false
		}
		return t.base.is_complete()
	}
	if t.kind == .pointer || t.kind == .function {
		// A pointer is complete whether or not what it points at is:
		// `struct S *p;` is storage whose size is known.
		return true
	}
	return t.complete
}

// is_const says whether the type itself is const, which is the question an
// assignment asks of the type it writes through.
pub fn (t Type) is_const() bool {
	return t.quals.const_
}

// pointee is the type a pointer points at, and none for anything else.
pub fn (t Type) pointee() ?Type {
	if t.kind != .pointer || t.base == unsafe { nil } {
		return none
	}
	return *t.base
}

// element is the element type of an array, and none for anything else.
pub fn (t Type) element() ?Type {
	if t.kind != .array || t.base == unsafe { nil } {
		return none
	}
	return *t.base
}

// returns is the type a function returns, read off the base of a function type
// or of a pointer to one.
pub fn (t Type) returns() ?Type {
	if t.kind == .function && t.base != unsafe { nil } {
		return *t.base
	}
	if t.kind == .pointer {
		if pointee := t.pointee() {
			if pointee.kind == .function && pointee.base != unsafe { nil } {
				return *pointee.base
			}
		}
	}
	return none
}

// same says whether two types are the same type rather than two spellings of
// one: the kind, the qualifiers, the shape each is derived from, the members of
// an aggregate and the parameters of a function.
//
// A struct or a union written with a tag is identified by that tag. Its members
// are a property of the tagged type, not a second half of its identity, so two
// readings of one tag are one type even when the first was taken before the body
// that completed it. Comparing member lists here is what made the `struct S` in
// `struct S *p;` read before `struct S { int a; };` a different type from the
// `struct S` the body defines, which is why the assignment of one to the other
// was refused with the same type named on both sides. An aggregate written
// without a tag has no name to be identified by, so its members are what tells
// it from another and they are compared.
pub fn (t Type) same(other Type) bool {
	if t.kind != other.kind || t.quals != other.quals || t.tag != other.tag {
		return false
	}
	if t.count != other.count || t.variadic != other.variadic
		|| t.prototyped != other.prototyped {
		return false
	}
	if !(t.kind in [.struct_, .union_] && t.tag != '') {
		if t.members.len != other.members.len {
			return false
		}
		for i, member in t.members {
			if member.name != other.members[i].name || member.bits != other.members[i].bits
				|| !member.typ.same(other.members[i].typ) {
				return false
			}
		}
	}
	if t.params.len != other.params.len {
		return false
	}
	for i, param in t.params {
		if !param.typ.same(other.params[i].typ) {
			return false
		}
	}
	return same_pointer(t.base, other.base)
}

fn same_pointer(a &Type, b &Type) bool {
	if a == unsafe { nil } || b == unsafe { nil } {
		return a == unsafe { nil } && b == unsafe { nil }
	}
	return a.same(*b)
}

// compatible is the relation 6.2.7 asks about: two types are compatible when
// they are the same type, and the standard's own special cases are here. An
// unknown type is compatible with nothing including itself, and an opaque type
// is compatible with the same name rather than with any other.
//
// `char`, `signed char` and `unsigned char` are three distinct types (6.2.5p15)
// and are not interchangeable here. Measured, gcc 16.2.1, and the flags are worth
// naming because the two mixes are not both refused by the default reading:
// `void f1(char *); void f1(unsigned char *);` is `error: conflicting types for
// f1` under `-std=c99` and under `-std=c99 -pedantic-errors` alike, while passing
// a `char *` where an `unsigned char *` is wanted is silent under `-std=c99`, is
// `warning: pointer targets in passing argument 1 of wants differ in signedness
// [-Wpointer-sign]` under `-std=c99 -Wpointer-sign`, and is an error under
// `-std=c99 -pedantic-errors`. The relation asked here is the one the pedantic
// reading asks.
pub fn (t Type) compatible(other Type) bool {
	if t.kind == .unknown || other.kind == .unknown {
		return false
	}
	if t.same(other) {
		return true
	}
	return false
}

// describe spells the type the way a declaration writes it, qualifiers included.
// It is what `-print-ast` shows and what a diagnostic names, and it is not the
// same question as `spelling`: a declaration is reported the way it was written
// and a type is reported the way the model holds it.
pub fn (t Type) describe() string {
	text := t.describe_unqualified()
	if t.quals.is_empty() {
		return text
	}
	suffix := t.quals.describe()
	if t.kind == .pointer {
		// `char * const` is a const pointer; the const of what it points at is
		// already inside the base's own description.
		return '${text} ${suffix}'
	}
	return '${suffix} ${text}'
}

// describe_unqualified is describe without the qualifiers on the type itself,
// which is what a derived description needs: the qualifiers of the pointee are
// part of the pointee's description.
fn (t Type) describe_unqualified() string {
	match t.kind {
		.unknown { return 'unresolved' }
		.void_ { return 'void' }
		.bool_ { return '_Bool' }
		.char_ { return 'char' }
		.signed_char { return 'signed char' }
		.unsigned_char { return 'unsigned char' }
		.short { return 'short' }
		.unsigned_short { return 'unsigned short' }
		.int_ { return 'int' }
		.unsigned_int { return 'unsigned int' }
		.long { return 'long' }
		.unsigned_long { return 'unsigned long' }
		.long_long { return 'long long' }
		.unsigned_long_long { return 'unsigned long long' }
		.int128 { return '__int128' }
		.unsigned_int128 { return 'unsigned __int128' }
		.float { return 'float' }
		.double { return 'double' }
		.long_double { return 'long double' }
		.complex_float { return 'float _Complex' }
		.complex_double { return 'double _Complex' }
		.complex_long_double { return 'long double _Complex' }
		.opaque { return t.tag }
		.pointer {
			if t.base == unsafe { nil } {
				return 'void *'
			}
			inner := t.base.describe()
			if t.base.kind == .pointer || t.base.kind == .array {
				return '${inner}*'
			}
			return '${inner} *'
		}
		.array {
			mut inner := 'void'
			if t.base != unsafe { nil } {
				inner = t.base.describe()
			}
			if t.count < 0 {
				return '${inner}[]'
			}
			return '${inner}[${t.count}]'
		}
		.function {
			mut out := 'void'
			if t.base != unsafe { nil } {
				out = t.base.describe()
			}
			if !t.prototyped {
				return '${out} ()'
			}
			mut parts := []string{}
			for param in t.params {
				parts << param.typ.describe()
			}
			if t.variadic {
				parts << '...'
			}
			if parts.len == 0 {
				// An empty list written as a prototype names no parameters,
				// which is `(void)`; a list that named nothing at all says
				// nothing about a call and is written `()` above.
				return '${out} (void)'
			}
			return '${out} (${parts.join(', ')})'
		}
		.struct_ { return if t.tag == '' { 'struct <anonymous>' } else { 'struct ${t.tag}' } }
		.union_ { return if t.tag == '' { 'union <anonymous>' } else { 'union ${t.tag}' } }
		.enum_ { return if t.tag == '' { 'enum <anonymous>' } else { 'enum ${t.tag}' } }
	}
}

// The scalars. Each is a function rather than a constant because a type holds a
// reference to what it is derived from, and a value built at compile time cannot
// hold one. Every scalar is complete: its size is the machine's business, not a
// question about this value.
pub fn void_type() Type {
	return Type{
		kind:     .void_
		complete: true
	}
}

pub fn bool_type() Type {
	return Type{
		kind:     .bool_
		complete: true
	}
}

pub fn char_type() Type {
	return Type{
		kind:     .char_
		complete: true
	}
}

pub fn signed_char_type() Type {
	return Type{
		kind:     .signed_char
		complete: true
	}
}

pub fn unsigned_char_type() Type {
	return Type{
		kind:     .unsigned_char
		complete: true
	}
}

pub fn short_type() Type {
	return Type{
		kind:     .short
		complete: true
	}
}

pub fn unsigned_short_type() Type {
	return Type{
		kind:     .unsigned_short
		complete: true
	}
}

pub fn int_type() Type {
	return Type{
		kind:     .int_
		complete: true
	}
}

pub fn unsigned_int_type() Type {
	return Type{
		kind:     .unsigned_int
		complete: true
	}
}

pub fn long_type() Type {
	return Type{
		kind:     .long
		complete: true
	}
}

pub fn unsigned_long_type() Type {
	return Type{
		kind:     .unsigned_long
		complete: true
	}
}

pub fn long_long_type() Type {
	return Type{
		kind:     .long_long
		complete: true
	}
}

pub fn unsigned_long_long_type() Type {
	return Type{
		kind:     .unsigned_long_long
		complete: true
	}
}

pub fn int128_type() Type {
	return Type{
		kind:     .int128
		complete: true
	}
}

pub fn unsigned_int128_type() Type {
	return Type{
		kind:     .unsigned_int128
		complete: true
	}
}

pub fn float_type() Type {
	return Type{
		kind:     .float
		complete: true
	}
}

pub fn double_type() Type {
	return Type{
		kind:     .double
		complete: true
	}
}

pub fn long_double_type() Type {
	return Type{
		kind:     .long_double
		complete: true
	}
}

pub fn complex_float_type() Type {
	return Type{
		kind:     .complex_float
		complete: true
	}
}

pub fn complex_double_type() Type {
	return Type{
		kind:     .complex_double
		complete: true
	}
}

pub fn complex_long_double_type() Type {
	return Type{
		kind:     .complex_long_double
		complete: true
	}
}

// scalar is the type with this kind when the kind has one, and none for a kind
// that is derived or unresolved.
pub fn scalar(kind Kind) ?Type {
	return match kind {
		.void_ { void_type() }
		.bool_ { bool_type() }
		.char_ { char_type() }
		.signed_char { signed_char_type() }
		.unsigned_char { unsigned_char_type() }
		.short { short_type() }
		.unsigned_short { unsigned_short_type() }
		.int_ { int_type() }
		.unsigned_int { unsigned_int_type() }
		.long { long_type() }
		.unsigned_long { unsigned_long_type() }
		.long_long { long_long_type() }
		.unsigned_long_long { unsigned_long_long_type() }
		.int128 { int128_type() }
		.unsigned_int128 { unsigned_int128_type() }
		.float { float_type() }
		.double { double_type() }
		.long_double { long_double_type() }
		.complex_float { complex_float_type() }
		.complex_double { complex_double_type() }
		.complex_long_double { complex_long_double_type() }
		else { none }
	}
}

// opaque_type is a name this compiler read as a type and could not resolve. It
// is not complete, because nothing here knows how much room it takes, and a
// declaration of an object of it is refused for that reason.
pub fn opaque_type(name string) Type {
	return if name == '' { Type{ kind: .opaque } } else { Type{ kind: .opaque, tag: name } }
}

// pointer_to is the type of a pointer to base. The base is copied onto the heap
// so that the pointer outlives the expression that built it.
pub fn pointer_to(base Type) Type {
	return Type{
		kind:     .pointer
		base:     &Type{ ...base }
		complete: true
	}
}

// array_of is the type of an array of count elements of base. A count below zero
// is an array whose size was not written, which is complete only when something
// later writes one.
pub fn array_of(base Type, count int) Type {
	return Type{
		kind:  .array
		base:  &Type{ ...base }
		count: count
	}
}

// function_type is the type of a function returning ret. The parameters are the
// ones the declarator wrote, adjusted the way 6.7.5.3 asks: a parameter of an
// array type is a pointer, and a parameter of a function type is a pointer to
// one.
pub fn function_type(ret Type, params []Param, variadic bool, prototyped bool) Type {
	mut adjusted := []Param{}
	for param in params {
		adjusted << Param{
			name: param.name
			typ:  adjust_parameter(param.typ)
			line: param.line
			col:  param.col
		}
	}
	return Type{
		kind:       .function
		base:       &Type{ ...ret }
		params:     adjusted
		variadic:   variadic
		prototyped: prototyped
		complete:   true
	}
}

// adjust_parameter is the adjustment 6.7.5.3 asks of a parameter that is written
// with an array or a function type. It is the same rule as function-to-pointer
// and array-to-pointer decay, applied at the declaration rather than at the use,
// which is why a definition and a prototype written differently may still
// declare one function.
pub fn adjust_parameter(t Type) Type {
	if t.kind == .array {
		mut element := t.base
		if element == unsafe { nil } {
			element = &Type{ ...void_type() }
		}
		return pointer_to(*element)
	}
	if t.kind == .function {
		return pointer_to(t)
	}
	return t
}

// struct_type, union_type and enum_type are the aggregate types. An aggregate
// with a body is complete; one whose tag was written with no body is not, which
// is what lets `struct S *p;` be read before S is defined anywhere.
pub fn struct_type(tag string, members []Member) Type {
	return Type{
		kind:     .struct_
		tag:      tag
		members:  members
		complete: true
	}
}

pub fn union_type(tag string, members []Member) Type {
	return Type{
		kind:     .union_
		tag:      tag
		members:  members
		complete: true
	}
}

// incomplete_tag is a tag that was declared and not defined: `struct _IO_FILE;`
// says the name exists and nothing more. A pointer to it can be declared and an
// object of it cannot, which is exactly what `complete` says, and the kind is the
// keyword the declaration wrote.
pub fn incomplete_tag(kind Kind, tag string) Type {
	return Type{
		kind: kind
		tag:  tag
	}
}

// enum_type is an enumerated type whose enumerators require the integer kind
// `underlying`. The tag is what the type was written with and the underlying
// kind is what its enumerators settled; a type with no enumerators read has no
// underlying kind, which is what an incomplete tag written as `enum E;` is.
pub fn enum_type(tag string, underlying Kind) Type {
	return Type{
		kind:       .enum_
		tag:        tag
		complete:   true
		underlying: underlying
	}
}

// LongDouble is the value of an extended-precision floating constant: the
// significand and the sign-and-exponent word of the 80-bit x87 format this
// target gives `long double`, as its own two fields rather than as a host
// number, because no host type here holds one. Measured on gcc 16.2.1 on this
// machine: `sizeof(long double)` is 16 and `_Alignof(long double)` is 16, and a
// long double holds one 80-bit value in the low ten bytes of that storage with
// six bytes of padding above it.
//
// mantissa is the 64-bit significand with its explicit integer bit at bit 63,
// which is the shape the x87 format stores: `1.5L` is mantissa
// 0xc000000000000000. sign_exp holds the sign in bit 15 and the biased exponent
// in bits 14..0, so `1.5L` is 0x3fff. A zero is both fields zero; an infinity
// is the exponent field all ones with the integer bit set.
pub struct LongDouble {
pub:
	mantissa u64
	sign_exp u16
}

// is_zero says whether the value is a zero of either sign.
pub fn (v LongDouble) is_zero() bool {
	return (v.sign_exp & 0x7fff) == 0 && v.mantissa == 0
}

// exponent is the unbiased power of two the significand is scaled by: the value
// is mantissa * 2^(exponent - 63), with the integer bit counted in. It is the
// field minus the bias, and it says nothing for a zero or a subnormal, whose
// field is zero.
pub fn (v LongDouble) exponent() int {
	return int(v.sign_exp & 0x7fff) - 16383
}

// bytes is the object representation the target gives a long double: the ten
// significant bytes of the 80-bit value, least significant first, with the six
// padding bytes above them zero. That is the ten bytes gcc 16.2.1 writes and
// the bytes this compiler writes into a long double it stores.
pub fn (v LongDouble) bytes() [16]u8 {
	mut out := [16]u8{}
	for i in 0 .. 8 {
		out[i] = u8((v.mantissa >> (8 * i)) & 0xff)
	}
	out[8] = u8(v.sign_exp & 0xff)
	out[9] = u8(v.sign_exp >> 8)
	return out
}

// long_double_from_bytes reads a long double back from the object
// representation a store wrote, which is what a copy of one and a conversion
// out of one start from.
pub fn long_double_from_bytes(object [16]u8) LongDouble {
	mut mantissa := u64(0)
	for i in 0 .. 8 {
		mantissa |= u64(object[i]) << (8 * i)
	}
	return LongDouble{
		mantissa: mantissa
		sign_exp: u16(object[8]) | (u16(object[9]) << 8)
	}
}

// enum_underlying_kind is the integer kind an enum's enumerators require, from
// the smallest and largest value the list gave them. Measured, gcc 16.2.1 asks
// two questions in this order: whether any enumerator is negative, and then how
// wide the largest one is. An enum with no negative value is unsigned int, and
// unsigned long when a value does not fit unsigned int; one with a negative
// value is int, and long when a value does not fit int. The four kinds are the
// whole answer, because -fshort-enums is off and a value outside the 64-bit
// range is one this reader did not fold.
pub fn enum_underlying_kind(min i64, max i64) Kind {
	if min >= 0 {
		if max <= u32_max {
			return .unsigned_int
		}
		return .unsigned_long
	}
	if min >= i32_min && max <= i32_max {
		return .int_
	}
	return .long
}

// u32_max, i32_min and i32_max are the bounds the enum rule above is written
// against: the largest unsigned 32-bit value and the two ends of int. They are
// spelled here because the rule is about what an int and an unsigned int hold,
// which is a fact about the C types and not about this machine's word.
const u32_max = i64(4294967295)
const i32_min = i64(-2147483648)
const i32_max = i64(2147483647)

// enum_constant_kind is the integer kind a *use* of an enumerator has, which is
// not always the kind the enum itself has. Measured, gcc 16.2.1 gives an
// enumerator of an enum whose underlying type is int or unsigned int the type
// int when the value fits int and that underlying type when it does not, and
// gives every enumerator of an enum whose underlying type is long or unsigned
// long that wider type, even one whose value would fit int. So `enum col { R };
// enum mid { M = 4000000000 }; enum both { E = -1, F = 4000000000 };` has R and
// M of type int and unsigned int, and E and F of type long.
pub fn enum_constant_kind(underlying Kind, value i64) Kind {
	if underlying in [.long, .unsigned_long] {
		return underlying
	}
	if value >= i32_min && value <= i32_max {
		return .int_
	}
	return underlying
}

// enum_underlying is the integer kind an enumerated type has, and the type's own
// kind for every other type. It is what the size of an enum and the signedness
// of a value of one are read from.
pub fn (t Type) enum_underlying() Kind {
	if t.kind == .enum_ {
		return t.underlying
	}
	return t.kind
}

// underlying_type is the integer type an enumerated type is compatible with:
// the type its enumerators require. Every other type is itself, which is what
// makes it safe to ask of any type.
pub fn (t Type) underlying_type() Type {
	if t.kind == .enum_ {
		return scalar(t.enum_underlying()) or { return t }
	}
	return t
}

// storage_spelling is the type as the back end reads it: an enumerated type is
// spelled as the integer type its enumerators require, and every other type as
// itself. The back end sizes and signs a value from a spelling, and it has a
// form for `unsigned int` and none for `enum c99_small`, so an enum's storage is
// the type gcc 16.2.1 gives it and not the tag it was written with.
pub fn (t Type) storage_spelling() string {
	return t.underlying_type().describe()
}

// is_unsigned_type says whether a value of this type is unsigned, reading an
// enumerated type as the integer type its enumerators require. It is the
// question the emitter asks a value before it widens or compares it, and asking
// the kind alone would answer for an enum as if it were int.
pub fn (t Type) is_unsigned_type() bool {
	return t.enum_underlying().is_unsigned()
}

// qualified is t with the qualifiers of other added, which is how `const int` is
// built from the words of a declaration.
pub fn qualified(t Type, other Qualifiers) Type {
	mut out := t
	out.quals = Qualifiers{
		const_:    t.quals.const_ || other.const_
		volatile_: t.quals.volatile_ || other.volatile_
		restrict_: t.quals.restrict_ || other.restrict_
	}
	return out
}

// unqualified is t with no qualifiers on it. The pointee keeps its own, which is
// the difference between `char * const` and `const char *`.
pub fn unqualified(t Type) Type {
	mut out := t
	out.quals = Qualifiers{}
	return out
}
