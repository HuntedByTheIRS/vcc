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
