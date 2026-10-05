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

// from_specifiers answers a kind, and the kind carries the properties the
// clauses after 6.7.2.2 read off it: whether it is an integer, which of its
// signs the words chose, whether it is floating, and its conversion rank from
// 6.3.1.1. This is the table row by row, so a spelling that starts naming a
// different kind than the standard's fails here.
struct SpecifierRow {
	words       []string
	kind        Kind
	is_integer  bool
	is_signed   bool
	is_unsigned bool
	is_floating bool
	rank        int
}

fn test_every_specifier_names_a_kind_with_its_signedness_and_rank() {
	rows := [
		SpecifierRow{ words: ['void'], kind: .void_, rank: -1 },
		SpecifierRow{ words: ['_Bool'], kind: .bool_, is_integer: true, is_unsigned: true, rank: 0 },
		SpecifierRow{ words: ['char'], kind: .char_, is_integer: true, is_signed: true, rank: 1 },
		SpecifierRow{ words: ['signed', 'char'], kind: .signed_char, is_integer: true, is_signed: true, rank: 1 },
		SpecifierRow{ words: ['unsigned', 'char'], kind: .unsigned_char, is_integer: true, is_unsigned: true, rank: 1 },
		SpecifierRow{ words: ['short'], kind: .short, is_integer: true, is_signed: true, rank: 2 },
		SpecifierRow{ words: ['unsigned', 'short'], kind: .unsigned_short, is_integer: true, is_unsigned: true, rank: 2 },
		SpecifierRow{ words: ['int'], kind: .int_, is_integer: true, is_signed: true, rank: 3 },
		SpecifierRow{ words: ['unsigned'], kind: .unsigned_int, is_integer: true, is_unsigned: true, rank: 3 },
		SpecifierRow{ words: ['long'], kind: .long, is_integer: true, is_signed: true, rank: 4 },
		SpecifierRow{ words: ['unsigned', 'long'], kind: .unsigned_long, is_integer: true, is_unsigned: true, rank: 4 },
		SpecifierRow{ words: ['long', 'long'], kind: .long_long, is_integer: true, is_signed: true, rank: 5 },
		SpecifierRow{ words: ['unsigned', 'long', 'long'], kind: .unsigned_long_long, is_integer: true, is_unsigned: true, rank: 5 },
		SpecifierRow{ words: ['float'], kind: .float, is_floating: true, rank: 7 },
		SpecifierRow{ words: ['double'], kind: .double, is_floating: true, rank: 8 },
		SpecifierRow{ words: ['long', 'double'], kind: .long_double, is_floating: true, rank: 9 },
	]
	for row in rows {
		kind := kind_of(row.words)
		assert kind == row.kind, row.words.join(' ')
		assert kind.is_integer() == row.is_integer, row.words.join(' ')
		assert kind.is_signed_integer() == row.is_signed, row.words.join(' ')
		assert kind.is_unsigned_integer() == row.is_unsigned, row.words.join(' ')
		assert kind.is_floating() == row.is_floating, row.words.join(' ')
		assert kind.rank() == row.rank, row.words.join(' ')
	}
}

// is_unsigned is the question a widened value's sign is read from, and the
// unsigned spellings are exactly the words that name a kind a value of which is
// never negative. `_Bool` is one of them, and the integer words without the
// keyword are not.
fn test_the_unsigned_specifiers_are_the_ones_a_value_of_which_is_never_negative() {
	for words in [
		['_Bool'],
		['unsigned', 'char'],
		['unsigned', 'short'],
		['unsigned'],
		['unsigned', 'int'],
		['unsigned', 'long'],
		['unsigned', 'long', 'long'],
	] {
		assert kind_of(words).is_unsigned(), words.join(' ')
	}
	for words in [
		['char'],
		['signed', 'char'],
		['short'],
		['signed'],
		['int'],
		['long'],
		['long', 'long'],
	] {
		assert !kind_of(words).is_unsigned(), words.join(' ')
	}
	// A floating type and void have no sign here to read.
	assert !kind_of(['float']).is_unsigned()
	assert !kind_of(['void']).is_unsigned()
}

fn test_signed_and_unsigned_written_alone_name_int_and_unsigned_int() {
	signed_kind := kind_of(['signed'])
	assert signed_kind == .int_
	assert signed_kind.is_signed_integer()
	assert signed_kind.rank() == 3
	unsigned_kind := kind_of(['unsigned'])
	assert unsigned_kind == .unsigned_int
	assert unsigned_kind.is_unsigned_integer()
	assert unsigned_kind.rank() == 3
	// The word alone names one type, and the type is the one the description
	// and the scalar table spell.
	assert (from_words(['signed']) or { void_type() }).describe() == 'int'
	assert (from_words(['unsigned']) or { void_type() }).describe() == 'unsigned int'
}

// `long long` names a type of its own and not two longs written twice for
// emphasis: it ranks above long, which is what makes `long + long long`
// convert to long long rather than stopping at the first type either of them
// could be read as.
fn test_long_long_ranks_above_long_and_below_the_128_bit_types() {
	long_kind := kind_of(['long'])
	long_long_kind := kind_of(['long', 'long'])
	unsigned_long_long_kind := kind_of(['unsigned', 'long', 'long'])
	assert long_long_kind == .long_long
	assert unsigned_long_long_kind == .unsigned_long_long
	assert long_kind.rank() == 4
	assert long_long_kind.rank() == 5
	assert unsigned_long_long_kind.rank() == 5
	assert long_kind.rank() < long_long_kind.rank()
	// The 128-bit types rank above it, which is where gcc's conversion rank
	// puts `__int128` and what the conversions in convert_test.v follow.
	assert long_long_kind.rank() < Kind.int128.rank()
	assert (from_words(['long', 'long']) or { void_type() }).describe() == 'long long'
}

fn test_bool_is_one_word_the_other_widths_refuse() {
	kind := kind_of(['_Bool'])
	assert kind == .bool_
	assert kind.is_integer()
	assert kind.is_unsigned_integer()
	assert kind.rank() == 0
	assert (from_words(['_Bool']) or { void_type() }).describe() == '_Bool'
	// `_Bool` is a type of its own and takes no width word beside it, and it is
	// not a word the repeat rule lets through.
	assert from_specifiers(['unsigned', '_Bool']) == none
	assert from_specifiers(['signed', '_Bool']) == none
	assert from_specifiers(['long', '_Bool']) == none
	assert from_specifiers(['short', '_Bool']) == none
	assert from_specifiers(['_Bool', '_Bool']) == none
}

// A typedef name is an ordinary identifier, and an ordinary identifier is not
// one of the type words: the parser resolves `size_t` to the type its
// declaration gave it and never hands the name to this table, so a name that
// arrives here is refused rather than read as its letters happen to suggest.
fn test_a_typedef_name_is_not_read_as_a_type_word() {
	for words in [
		['size_t'],
		['ssize_t'],
		['int32_t'],
		['FILE'],
		['my_type'],
		['size_t', 'int'],
	] {
		assert from_specifiers(words) == none, words.join(' ')
		assert from_words(words) == none, words.join(' ')
	}
}

// A tag is not a run of type words. `struct S` is a keyword and a name, and the
// name is answered by the scope's tag table (scope.v's declare_tag and
// lookup_tag), so the three tag keywords on their own are refused here rather
// than read as some type; the parser resolves the tag and hands the type it
// found, which is the only place a tag becomes a specifier.
fn test_a_tag_keyword_is_not_read_as_a_type_word() {
	for words in [
		['struct'],
		['union'],
		['enum'],
		['struct', 'S'],
		['union', 'U'],
		['enum', 'E'],
		['struct', 'S', 'int'],
	] {
		assert from_specifiers(words) == none, words.join(' ')
		assert from_words(words) == none, words.join(' ')
	}
}

// The words may be written in any order, which is what a declaration's freedom
// to spell `unsigned long` and `long unsigned` both means.
fn test_the_type_words_may_be_written_in_any_order() {
	assert kind_of(['int', 'unsigned']) == .unsigned_int
	assert kind_of(['int', 'long']) == .long
	assert kind_of(['int', 'short']) == .short
	assert kind_of(['char', 'unsigned']) == .unsigned_char
	assert kind_of(['char', 'signed']) == .signed_char
	assert kind_of(['double', 'long']) == .long_double
	assert kind_of(['int', 'signed', 'long']) == .long
	assert kind_of(['int', 'unsigned', 'long']) == .unsigned_long
	assert kind_of(['int', 'long', 'long', 'unsigned']) == .unsigned_long_long
}

// A word written twice is not a type, and only `long` and `int` may repeat:
// 6.7.2.2 lists `long long` and lets `int` be written or left out, and every
// other word said twice is two data types in one declaration, which gcc 16.2.1
// refuses for each row of the first loop.
fn test_a_word_written_twice_is_refused_except_long_and_int() {
	for words in [
		['void', 'void'],
		['char', 'char'],
		['signed', 'char', 'signed'],
		['short', 'short'],
		['float', 'float'],
		['double', 'double'],
		['int', 'int'],
		['long', 'long', 'long', 'long'],
		['long', 'long', 'int', 'int'],
	] {
		assert from_specifiers(words) == none, words.join(' ')
	}
	// `long` may be written twice and `int` may accompany it once, which is
	// what makes `long long int` one type; a third `long` is one too many.
	assert kind_of(['long', 'long']) == .long_long
	assert kind_of(['long', 'long', 'int']) == .long_long
	assert kind_of(['int']) == .int_
	assert from_specifiers(['long', 'long', 'long']) == none
}

// 6.2.5p15: `char`, `signed char` and `unsigned char` are three distinct types,
// so the plain word and the two signed ones name three kinds and not one kind
// under two spellings. They share one rank, which is what makes a sum of two of
// them convert rather than letting one rank win.
fn test_char_signed_and_unsigned_are_three_distinct_types() {
	plain := kind_of(['char'])
	signed_kind := kind_of(['signed', 'char'])
	unsigned_kind := kind_of(['unsigned', 'char'])
	assert plain == .char_
	assert signed_kind == .signed_char
	assert unsigned_kind == .unsigned_char
	assert plain != signed_kind
	assert plain != unsigned_kind
	assert signed_kind != unsigned_kind
	assert plain.rank() == signed_kind.rank()
	assert signed_kind.rank() == unsigned_kind.rank()
	assert plain.is_signed_integer()
	assert signed_kind.is_signed_integer()
	assert unsigned_kind.is_unsigned_integer()
	assert (from_words(['char']) or { void_type() }).describe() == 'char'
	assert (from_words(['signed', 'char']) or { void_type() }).describe() == 'signed char'
	assert (from_words(['unsigned', 'char']) or { void_type() }).describe() == 'unsigned char'
}
