module types

// The type words a declaration writes in front of a declarator, and the type they
// add up to.
//
// The standard lists the combinations in 6.7.2.2 and this is that list: a
// combination the standard does not have is refused rather than read as the
// nearest one, because `long float` and `unsigned void` are programs gcc refuses
// and a compiler that accepted them would be reading C nobody wrote. The words
// may be written in any order, and the two that may be written twice are `long`
// and `int`.

// from_specifiers answers the kind a run of type words names, and none when the
// run is not one the standard has a type for. The caller reports the refusal: it
// knows where in the file the words were written.
pub fn from_specifiers(words []string) ?Kind {
	mut longs := 0
	mut ints := 0
	// seen is the other words, each once: a word written twice is not a type,
	// except for the two the table allows to repeat.
	mut seen := map[string]bool{}
	for word in words {
		if word == 'long' {
			longs++
			continue
		}
		if word == 'int' {
			ints++
			continue
		}
		if seen[word] {
			return none
		}
		seen[word] = true
	}
	if longs > 2 || ints > 1 {
		return none
	}
	if seen['signed'] && seen['unsigned'] {
		return none
	}
	if seen['void'] {
		if seen.len == 1 && longs == 0 && ints == 0 {
			return Kind.void_
		}
		return none
	}
	if seen['_Bool'] {
		if seen.len == 1 && longs == 0 && ints == 0 {
			return Kind.bool_
		}
		return none
	}
	if seen['_Imaginary'] {
		// C99 makes _Imaginary optional, and this compiler has no model for an
		// imaginary type. It is refused by name rather than read as a complex
		// one, which is a different type.
		return none
	}
	if seen['_Complex'] {
		if seen['float'] {
			if seen.len == 2 && longs == 0 && ints == 0 {
				return Kind.complex_float
			}
			return none
		}
		if seen['double'] {
			if ints != 0 || seen['short'] {
				return none
			}
			if longs == 1 && seen.len == 2 {
				return Kind.complex_long_double
			}
			if longs == 0 && seen.len == 2 {
				return Kind.complex_double
			}
			return none
		}
		if seen.len == 1 && longs == 0 && ints == 0 {
			// A lone `_Complex` is `double _Complex`. Measured: gcc 16.2.1
			// says the two are compatible types and that both occupy 16 bytes.
			return Kind.complex_double
		}
		return none
	}
	if seen['float'] {
		if seen.len == 1 && longs == 0 && ints == 0 {
			return Kind.float
		}
		return none
	}
	if seen['double'] {
		if ints != 0 || seen['short'] {
			return none
		}
		if longs == 1 && seen.len == 1 {
			return Kind.long_double
		}
		if longs == 0 && seen.len == 1 {
			return Kind.double
		}
		return none
	}
	if seen['char'] {
		if longs != 0 || ints != 0 || seen['short'] {
			return none
		}
		if seen['signed'] {
			return Kind.signed_char
		}
		if seen['unsigned'] {
			return Kind.unsigned_char
		}
		if seen.len == 1 {
			return Kind.char_
		}
		return none
	}
	if seen['short'] {
		if longs != 0 {
			return none
		}
		if seen['signed'] {
			return Kind.short
		}
		if seen['unsigned'] {
			return Kind.unsigned_short
		}
		if seen.len == 1 {
			return Kind.short
		}
		return none
	}
	if longs > 0 {
		// `long` and `long long` name a type on their own, and `int` written
		// with either of them adds nothing: `long int` is a long.
		if seen.len == 0 {
			if longs == 1 {
				return Kind.long
			}
			return Kind.long_long
		}
		if seen.len == 1 && seen['signed'] {
			if longs == 1 {
				return Kind.long
			}
			return Kind.long_long
		}
		if seen.len == 1 && seen['unsigned'] {
			if longs == 1 {
				return Kind.unsigned_long
			}
			return Kind.unsigned_long_long
		}
		return none
	}
	if seen['signed'] && seen.len == 1 {
		return Kind.int_
	}
	if seen['unsigned'] && seen.len == 1 {
		return Kind.unsigned_int
	}
	if seen.len == 0 && ints == 1 {
		return Kind.int_
	}
	return none
}

// from_words is from_specifiers with the kind turned into the type, which is what
// a declaration needs. A run of words the table does not have is refused here and
// reported by the reader that wrote them down.
pub fn from_words(words []string) ?Type {
	kind := from_specifiers(words) or { return none }
	return scalar(kind)
}
