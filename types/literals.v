module types

// The type of an integer constant, which 6.4.4.1 settles from the spelling as
// much as from the value: the suffix says which types may be considered, and the
// base says whether an unsigned type may be, and then the value picks the first
// one that can hold it.
//
// It is here rather than with the literal reader in the lexer because it is a
// question about types and their widths, and the widths are the object
// representation's. Every suffix and base combination below is the list 6.4.4.1
// gives, in the order it gives them.

// integer_constant_type answers the type of an integer constant written as
// `text`, whose value is `value`.
//
// A value that fits in the range every int has needs no width to decide: the
// standard requires int to hold -32767 to 32767 whatever the machine, so a
// constant in that range is an int on every target this compiler could ever
// describe. Past that range the representation decides, and a description that
// does not carry the widths gets a refusal instead of a guess.
pub fn integer_constant_type(text string, value i64, rep Representation) !Type {
	mut spelling := text
	mut has_unsigned := false
	mut longs := 0
	mut index := spelling.len
	for index > 0 {
		last := spelling[index - 1]
		if last == `u` || last == `U` {
			has_unsigned = true
			index--
			continue
		}
		if last == `l` || last == `L` {
			longs++
			index--
			continue
		}
		break
	}
	if longs > 2 {
		return error('${text} is not an integer constant: it has more than two l suffixes')
	}
	spelling = spelling[..index]
	if spelling.len == 0 {
		return error('${text} is not an integer constant')
	}
	mut decimal := true
	if spelling.len > 1 && spelling[0] == `0` {
		decimal = false
		if spelling.len > 2 && (spelling[1] == `x` || spelling[1] == `X`) {
			decimal = false
		}
	}
	candidates := candidates_for(decimal, has_unsigned, longs)
	if candidates.len == 0 {
		return error('${text} is not an integer constant: it has a suffix the standard does not list')
	}
	// A value that fits in the range every type of the first candidate has is
	// that type on every machine, so no width is needed. Anything else needs the
	// widths: a larger value might still be an int, on a machine whose int is
	// wider than the standard requires.
	if fits_guaranteed(candidates[0], value) {
		return scalar(candidates[0]) or { return error('${text} has no type') }
	}
	mut missing := false
	for kind in candidates {
		fits := fits_with(kind, value, rep) or {
			missing = true
			false
		}
		if fits {
			return scalar(kind) or { return error('${text} has no type') }
		}
	}
	if missing {
		return error('the type of the integer constant ${text} needs the widths of the types it could be, which ${missing_note(rep, candidates)} does not carry')
	}
	return error('the integer constant ${text} is too large for every type it could be')
}

// candidates_for is the list 6.4.4.1 gives, in order. A decimal constant is
// signed unless its suffix asks otherwise, and an octal or hexadecimal one may
// take an unsigned type that holds it.
fn candidates_for(decimal bool, has_unsigned bool, longs int) []Kind {
	if decimal {
		if has_unsigned {
			return match longs {
				0 { [Kind.unsigned_int, .unsigned_long, .unsigned_long_long] }
				1 { [Kind.unsigned_long, .unsigned_long_long] }
				else { [Kind.unsigned_long_long] }
			}
		}
		return match longs {
			0 { [Kind.int_, .long, .long_long] }
			1 { [Kind.long, .long_long] }
			else { [Kind.long_long] }
		}
	}
	if has_unsigned {
		return match longs {
			0 { [Kind.unsigned_int, .unsigned_long, .unsigned_long_long] }
			1 { [Kind.unsigned_long, .unsigned_long_long] }
			else { [Kind.unsigned_long_long] }
		}
	}
	return match longs {
		0 { [Kind.int_, .unsigned_int, .long, .unsigned_long, .long_long, .unsigned_long_long] }
		1 { [Kind.long, .unsigned_long, .long_long, .unsigned_long_long] }
		else { [Kind.long_long, .unsigned_long_long] }
	}
}

// fits_guaranteed says whether every type of this kind holds the value, whatever
// the machine: 5.2.4.2.1 requires int to be at least 16 bits, long at least 32
// and long long at least 64.
fn fits_guaranteed(kind Kind, value i64) bool {
	bits := match kind {
		.int_ { 16 }
		.unsigned_int { 16 }
		.long { 32 }
		.unsigned_long { 32 }
		.long_long { 64 }
		.unsigned_long_long { 64 }
		else { 0 }
	}
	if bits == 0 {
		return false
	}
	return within(kind, value, bits)
}

// fits_with asks the representation, and refuses when it does not carry the kind.
fn fits_with(kind Kind, value i64, rep Representation) !bool {
	kind_type := scalar(kind) or { return error('${kind} is not a scalar kind') }
	size := rep.size_of(kind_type) or {
		return error('the width of ${kind_type.describe()} is not in the description')
	}
	return within(kind, value, bits_in_a_byte * size)
}

// within says whether a value is one of the values a type of this signedness and
// this many bits holds.
//
// The value arrives as the 64-bit pattern the literal reader built, which is why
// the top bit being set is a case of its own. `18446744073709551615` is 2^64 - 1,
// and no signed type holds it; the pattern of it read as a signed 64-bit value is
// -1. The only types that hold the pattern are the 64-bit unsigned ones, so a
// value with its top bit set fits an unsigned 64-bit type and nothing else.
// A narrower type holds neither reading: 2^64 - 1 is past every one of them, and
// so is the 64-bit pattern of any value that reaches 2^63. Measured on gcc 16.2.1:
// `18446744073709551615` with no suffix is refused as `integer constant is so
// large that it is unsigned`, the same value with `ULL` is `unsigned long long`,
// and `0xffffffffffffffff` is `unsigned long`.
fn within(kind Kind, value i64, bits int) bool {
	if bits >= 64 {
		if kind.is_unsigned_integer() {
			return true
		}
		return value >= 0
	}
	if value < 0 {
		return false
	}
	limit := i64(1) << (bits - 1)
	if kind.is_unsigned_integer() {
		return value < limit * 2
	}
	return value < limit
}
