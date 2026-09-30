module types

// 6.7.2.2 is a table, so these tests are the table: every combination the
// standard lists, and the combinations gcc refuses that a reader might be
// tempted to read as the nearest one.

fn test_every_combination_the_table_has() {
	assert from_specifiers(['void']) or {
		assert false
		return
	} == .void_
	assert from_specifiers(['char']) or {
		assert false
		return
	} == .char_
	assert from_specifiers(['signed', 'char']) or {
		assert false
		return
	} == .signed_char
	assert from_specifiers(['char', 'signed']) or {
		assert false
		return
	} == .signed_char
	assert from_specifiers(['unsigned', 'char']) or {
		assert false
		return
	} == .unsigned_char
	assert from_specifiers(['short']) or {
		assert false
		return
	} == .short
	assert from_specifiers(['short', 'int']) or {
		assert false
		return
	} == .short
	assert from_specifiers(['signed', 'short', 'int']) or {
		assert false
		return
	} == .short
	assert from_specifiers(['unsigned', 'short', 'int']) or {
		assert false
		return
	} == .unsigned_short
	assert from_specifiers(['int']) or {
		assert false
		return
	} == .int_
	assert from_specifiers(['signed']) or {
		assert false
		return
	} == .int_
	assert from_specifiers(['signed', 'int']) or {
		assert false
		return
	} == .int_
	assert from_specifiers(['unsigned']) or {
		assert false
		return
	} == .unsigned_int
	assert from_specifiers(['unsigned', 'int']) or {
		assert false
		return
	} == .unsigned_int
	assert from_specifiers(['long']) or {
		assert false
		return
	} == .long
	assert from_specifiers(['long', 'int']) or {
		assert false
		return
	} == .long
	assert from_specifiers(['signed', 'long', 'int']) or {
		assert false
		return
	} == .long
	assert from_specifiers(['long', 'unsigned']) or {
		assert false
		return
	} == .unsigned_long
	assert from_specifiers(['unsigned', 'long', 'int']) or {
		assert false
		return
	} == .unsigned_long
	assert from_specifiers(['long', 'long']) or {
		assert false
		return
	} == .long_long
	assert from_specifiers(['long', 'long', 'int']) or {
		assert false
		return
	} == .long_long
	assert from_specifiers(['signed', 'long', 'long']) or {
		assert false
		return
	} == .long_long
	assert from_specifiers(['unsigned', 'long', 'long', 'int']) or {
		assert false
		return
	} == .unsigned_long_long
	assert from_specifiers(['long', 'long', 'unsigned']) or {
		assert false
		return
	} == .unsigned_long_long
	assert from_specifiers(['_Bool']) or {
		assert false
		return
	} == .bool_
	assert from_specifiers(['float']) or {
		assert false
		return
	} == .float
	assert from_specifiers(['double']) or {
		assert false
		return
	} == .double
	assert from_specifiers(['long', 'double']) or {
		assert false
		return
	} == .long_double
	assert from_specifiers(['float', '_Complex']) or {
		assert false
		return
	} == .complex_float
	assert from_specifiers(['double', '_Complex']) or {
		assert false
		return
	} == .complex_double
	assert from_specifiers(['_Complex']) or {
		assert false
		return
	} == .complex_double
	assert from_specifiers(['long', 'double', '_Complex']) or {
		assert false
		return
	} == .complex_long_double
}

fn test_from_words_answers_the_type_and_not_only_the_kind() {
	typ := from_words(['unsigned', 'long']) or {
		assert false
		return
	}
	assert typ.describe() == 'unsigned long'
	assert typ.is_complete()
	assert from_words(['nonsense']) == none
	assert from_words([]) == none
}

// The width of a _BitInt is the type, so the reader answers the 128-bit type for
// the one width this compiler has a value of that size for, and none for every
// other width. Measured on gcc 16.2.1: `_BitInt(65)` occupies sixteen bytes and
// wraps at 65 bits, so it is not the 128-bit pair under another name.
fn test_a_bitint_word_is_the_128_bit_type_at_one_width_and_no_other() {
	signed_128 := from_words(['_BitInt(128)']) or {
		assert false
		return
	}
	assert signed_128.describe() == '__int128'
	assert (from_specifiers(['_BitInt(128)']) or { Kind.void_ }) == Kind.int128
	assert (from_specifiers(['signed', '_BitInt(128)']) or { Kind.void_ }) == Kind.int128
	assert (from_specifiers(['unsigned', '_BitInt(128)']) or { Kind.void_ }) == Kind.unsigned_int128
	// A width this compiler has no value for is none, and so is a word that is
	// not a width at all, which is what a caller other than the parser hands in.
	assert from_specifiers(['_BitInt(64)']) == none
	assert from_specifiers(['_BitInt(8)']) == none
	assert from_specifiers(['_BitInt(0)']) == none
	assert from_specifiers(['_BitInt()']) == none
	assert from_specifiers(['_BitInt(abc)']) == none
	assert from_specifiers(['_BitInt(']) == none
	assert from_specifiers(['_BitInt(128)', 'short']) == none
	assert from_specifiers(['_BitInt(128)', 'long']) == none
}

// Every one of these is a declaration gcc 16.2.1 refuses under -std=c99, which is
// what makes refusing it in the table right rather than cautious. The message for
// each was measured with `gcc -std=c99 -fsyntax-only`.
fn test_combinations_the_standard_does_not_have_are_refused() {
	// both `long` and `float` in declaration specifiers
	assert from_specifiers(['long', 'float']) == none
	// both `unsigned` and `void` in declaration specifiers
	assert from_specifiers(['unsigned', 'void']) == none
	// both `unsigned` and `signed` in declaration specifiers
	assert from_specifiers(['signed', 'unsigned']) == none
	assert from_specifiers(['unsigned', 'signed', 'int']) == none
	// two or more data types in declaration specifiers
	assert from_specifiers(['int', 'int']) == none
	assert from_specifiers(['float', 'double']) == none
	assert from_specifiers(['_Bool', 'int']) == none
	assert from_specifiers(['char', 'int']) == none
	assert from_specifiers(['void', 'char']) == none
	assert from_specifiers(['double', 'double']) == none
	// both `short` and `float` in declaration specifiers
	assert from_specifiers(['short', 'float']) == none
	// duplicate `unsigned`
	assert from_specifiers(['unsigned', 'char', 'unsigned']) == none
	// both `long long` and `double` in declaration specifiers
	assert from_specifiers(['long', 'double', 'long']) == none
	// `long long long` is one too many
	assert from_specifiers(['long', 'long', 'long']) == none
	// two `int` words are one too many even with a type word
	assert from_specifiers(['short', 'int', 'int']) == none
	// C99 makes _Imaginary optional and this compiler has no imaginary type
	assert from_specifiers(['_Imaginary']) == none
	assert from_specifiers(['float', '_Imaginary']) == none
	// an empty run of words is not a type: C89 read that as int, C99 does not
	assert from_specifiers([]) == none
	// a word that names no type at all
	assert from_specifiers(['size_t']) == none
}

// kind_of is the kind a run of words names, and it asserts when the table
// refuses the run, so a combination that stops being accepted fails here rather
// than being read as a zero value.
fn kind_of(words []string) Kind {
	return from_specifiers(words) or {
		assert false
		Kind.unknown
	}
}

// The 128-bit type is gcc's and takes the integer words the other widths take,
// minus the ones that name a width of their own. The refusals were measured with
// `gcc -std=gnu99 -fsyntax-only`, which says `long __int128` is "both '__int128'
// and 'long' in declaration specifiers", `__int128 short` is "both 'short' and
// '__int128'", and `float __int128` is "two or more data types in declaration
// specifiers".
fn test_the_128_bit_type_and_the_words_that_combine_with_it() {
	// `__int128` is the signed type and `unsigned __int128` the other one.
	assert kind_of(['__int128']) == .int128
	assert kind_of(['unsigned', '__int128']) == .unsigned_int128
	assert kind_of(['signed', '__int128']) == .int128
	// The words may be written in either order: measured, gcc accepts
	// `__int128 unsigned` and `__int128 signed` as well.
	assert kind_of(['__int128', 'unsigned']) == .unsigned_int128
	assert kind_of(['__int128', 'signed']) == .int128
	// A word that names a width of its own contradicts the 128-bit type.
	assert from_specifiers(['long', '__int128']) == none
	assert from_specifiers(['__int128', 'long']) == none
	assert from_specifiers(['long', 'long', '__int128']) == none
	assert from_specifiers(['__int128', 'short']) == none
	assert from_specifiers(['__int128', 'int']) == none
	assert from_specifiers(['float', '__int128']) == none
	assert from_specifiers(['__int128', 'double']) == none
	// Both signednesses at once is the refusal the other widths make too.
	assert from_specifiers(['signed', 'unsigned', '__int128']) == none
	// A qualifier never reaches this table: the parser keeps it beside the type
	// words rather than among them, so `const __int128 v;` arrives as the run
	// `['__int128']` with the qualifier carried separately. A run that carries
	// one anyway is not a run of type words, and is refused.
	assert from_specifiers(['const', '__int128']) == none
}
