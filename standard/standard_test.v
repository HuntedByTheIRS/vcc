module standard

import tokenize

fn token(text string) tokenize.Token {
	return tokenize.Token{
		kind: .identifier
		text: text
		line: 1
		col:  1
		file: 'f.c'
	}
}

fn asking(mode Mode) Question {
	return Question{
		mode:         mode
		extensions:   []
		system_files: map[string]bool{}
	}
}

fn test_the_spelling_to_mode_map() {
	assert from_spelling('c89') == .c89
	assert from_spelling('c90') == .c89
	assert from_spelling('c99') == .c99
	assert from_spelling('c11') == .c11
	assert from_spelling('c17') == .c17
	assert from_spelling('c23') == .c23
	assert from_spelling('gnu11') == .gnu11
	assert from_spelling('gnu89') == .gnu89
	assert from_spelling('gnu99') == .gnu99
	assert from_spelling('gnu17') == .gnu17
	assert from_spelling('gnu23') == .gnu23
	assert from_spelling('iso9899:1999') == .c99
	assert from_spelling('iso9899:1990') == .c89
}

fn test_no_spelling_is_an_error() {
	// tcc accepts -std=nonsense and V may hand the compiler any spelling, so
	// everything that is not a mode this compiler has is an answer and not a
	// failure.
	assert from_spelling('nonsense') == .other
	assert from_spelling('c9x') == .other
	assert from_spelling('') == .other
}

fn test_a_mode_can_be_written_back() {
	spellings := ['c89', 'c99', 'c11', 'c17', 'c23', 'gnu89', 'gnu99', 'gnu11', 'gnu17', 'gnu23']
	for spelling in spellings {
		assert from_spelling(spelling).spelling() == spelling
	}
	assert Mode.none.spelling() == ''
	assert Mode.other.spelling() == ''
}

fn test_the_gnu_dialects_are_the_ones_that_take_gnu_c() {
	assert Mode.gnu99.is_gnu()
	assert Mode.gnu11.is_gnu()
	assert !Mode.c99.is_gnu()
	assert !Mode.c11.is_gnu()
}

fn test_a_mode_includes_the_standards_before_it() {
	assert Mode.c99.includes(.c89)
	assert Mode.c11.includes(.c99)
	assert Mode.gnu99.includes(.c99)
	assert !Mode.c99.includes(.c11)
	assert !Mode.c89.includes(.c99)
	// No -std at all, and a spelling this compiler does not implement, are not
	// standards and include nothing.
	assert !Mode.none.includes(.c89)
	assert !Mode.other.includes(.c89)
	assert !Mode.c99.includes(.none)
}

fn test_a_message_names_the_standard_the_mode_asks_about() {
	assert Mode.c99.standard_name() == 'ISO C99'
	assert Mode.gnu99.standard_name() == 'ISO C99'
	assert Mode.c89.standard_name() == 'ISO C90'
	assert Mode.c23.standard_name() == 'ISO C23'
	assert Mode.none.standard_name() == ''
}

fn test_the_table_carries_a_row_for_each_construct() {
	assert features.len > 0
	for feature in features {
		if feature.reserved {
			// A spelling every mode takes has no message to carry and no
			// standard to have come from: the phrase below is the half of a
			// message no mode can print, and a `since` would be a claim about
			// a standard that never had it.
			assert feature.pedantic == '', 'a reserved spelling is reported by no mode'
			assert feature.since == .none
			assert !feature.gnu
			continue
		}
		assert feature.pedantic != ''
		if feature.status == .implemented {
			assert feature.spellings.len > 0, 'an implemented row is found by a spelling'
		}
		if feature.since == .none {
			assert feature.gnu, 'a construct no ISO mode has is a GNU extension'
		}
	}
}

fn test_the_rows_name_the_extensions_that_bring_them_down() {
	// The old shape asserted that no row named an extension, because the flag
	// parsed names and honored none of them. The rows now carry the names, and
	// these four are the whole list the compiler offers the flag.
	mut named := []string{}
	for feature in features {
		if feature.extension == '' {
			continue
		}
		assert feature.since != .none, '${feature.extension} brings a construct down to a mode before the standard that has it'
		assert feature.pedantic != '', '${feature.extension} has no phrase to bring down'
		named << feature.extension
	}
	named.sort()
	assert named == ['auto', 'generic', 'static-assert', 'typeof']
	assert extension_names() == named
}

fn test_a_row_is_reachable_by_its_spelling() {
	assert features.any(it.spellings.contains('__attribute__'))
	assert features.any(it.spellings.contains('__asm__'))
}

fn test_a_gnu_construct_is_pedantic_in_a_strict_mode() {
	tokens := [token('int'), token('f'), token('__attribute__'), token('(')]
	messages := pedantic_messages(tokens, asking(.c99))
	assert messages.len == 1
	assert messages[0].msg == 'ISO C99 forbids an attribute'
	assert messages[0].class == .pedantic
	assert messages[0].warning
	assert messages[0].line == 1
	assert messages[0].file == 'f.c'
	// The phrase names no position, because the spelling's position is not
	// something the token-text check can see: a prefix attribute and a postfix
	// one get the same message, and both are attributes.
	prefix := [token('__attribute__'), token('int'), token('f')]
	assert pedantic_messages(prefix, asking(.c99))[0].msg == messages[0].msg
}

fn test_the_asm_row_names_every_shape_the_spelling_marks() {
	// The check matches the token text, and the token opens both an asm
	// statement and an assembler name on a declarator, so a phrase that names
	// only the declarator names something a statement-level use does not have.
	tokens := [token('int'), token('x'), token('__asm__'), token('volatile')]
	messages := pedantic_messages(tokens, asking(.c99))
	assert messages.len == 1
	assert messages[0].msg == 'ISO C99 forbids an asm statement or an assembler name on a declarator'
	assert messages[0].line == 1
	// A declaration with an asm name gets the same phrase, which is the other
	// shape it has to be true of.
	declarator := [token('int'), token('g'), token('('), token('void'), token(')'), token('__asm__')]
	declared := pedantic_messages(declarator, asking(.c99))
	assert declared.len == 1
	assert declared[0].msg == messages[0].msg
}

fn test_a_gnu_dialect_takes_its_own_extensions() {
	tokens := [token('__attribute__'), token('__asm__')]
	assert pedantic_messages(tokens, asking(.gnu99)).len == 0
	assert pedantic_messages(tokens, asking(.gnu11)).len == 0
	// And a strict mode asks about both of them, in the order they are used.
	assert pedantic_messages(tokens, asking(.c11)).len == 2
}

fn test_no_std_and_an_unknown_spelling_ask_nothing() {
	tokens := [token('__attribute__')]
	assert pedantic_messages(tokens, asking(.none)).len == 0
	assert pedantic_messages(tokens, asking(.other)).len == 0
}

fn test_a_construct_the_compiler_refuses_is_not_a_pedantic_message() {
	// _Generic is not implemented, so a program writing it is refused by the
	// parser; a message from this table on top of that refusal would say the
	// same thing twice and would be the wrong thing once the parser lands.
	tokens := [token('_Generic'), token('int')]
	assert pedantic_messages(tokens, asking(.c99)).len == 0
}

// typeof is read by the parser, so the table's row is a message and not a
// duplicate of a refusal. Re-measured on gcc 16.2.1, one mode at a time over
// `typeof(x) y = 2;`: accepted under -std=c23, under -std=gnu99 and with no
// -std at all, and a hard error under -std=c99, -std=c99 -pedantic and
// -std=c99 -pedantic-errors, where the bare spelling is not a keyword and the
// line is read as a call to a function named typeof. The tree reports it under
// -pedantic where gcc fails outright; the modes that report are the modes that
// do not have the construct, and the default mode is not one of them.
fn test_the_typeof_row_reports_outside_c23_and_the_gnu_modes() {
	tokens := [token('typeof'), token('int')]
	assert pedantic_messages(tokens, asking(.c99)).len == 1
	assert pedantic_messages(tokens, asking(.c11))[0].msg == 'ISO C11 forbids the typeof specifier'
	assert pedantic_messages(tokens, asking(.c17)).len == 1
	// C23 has the construct, a GNU dialect takes it as an extension, and no
	// -std at all asks nothing.
	assert pedantic_messages(tokens, asking(.c23)).len == 0
	assert pedantic_messages(tokens, asking(.gnu89)).len == 0
	assert pedantic_messages(tokens, asking(.gnu99)).len == 0
	assert pedantic_messages(tokens, asking(.gnu23)).len == 0
	assert pedantic_messages(tokens, asking(.none)).len == 0
}

// typeof_unqual is narrower than typeof, and the row says so: it became
// standard in C23 and no GNU dialect has it as an extension of its own.
// Measured on gcc 16.2.1, `typeof(x) y = 2;` is accepted under -std=gnu99 while
// `typeof_unqual(x) y = 2;` is a hard error there, and the GNU mode is the mode
// that separates the two rows.
fn test_the_typeof_unqual_row_is_c23_and_not_a_gnu_extension() {
	tokens := [token('typeof_unqual')]
	strict := [Mode.c89, .c99, .c11, .c17]
	for mode in strict {
		assert pedantic_messages(tokens, asking(mode)).len == 1
	}
	assert pedantic_messages(tokens, asking(.c99))[0].msg == 'ISO C99 forbids the typeof_unqual specifier'
	// Every GNU dialect before C23 reports it, which is what gcc does.
	older := [Mode.gnu89, .gnu99, .gnu11, .gnu17]
	for mode in older {
		assert pedantic_messages(tokens, asking(mode)).len == 1
	}
	// C23 has it, and gnu23 includes C23 rather than taking it as an extension.
	assert pedantic_messages(tokens, asking(.c23)).len == 0
	assert pedantic_messages(tokens, asking(.gnu23)).len == 0
	assert pedantic_messages(tokens, asking(.none)).len == 0
}

// A mode that does not have the construct is a different thing from one that
// does not allow it, and the diagnostic says which. The bare spellings are
// reported as diagnostics the compiler raises on its own account, which no flag
// silences; a construct a mode merely does not allow stays a pedantic message.
// Measured on gcc 16.2.1: plain `typeof` under -std=c99 exits 1 with -w written
// on the command line, so the refusal is not the flags' to take back.
fn test_a_mode_without_the_construct_reports_it_and_not_as_a_warning() {
	bare := pedantic_messages([token('typeof')], asking(.c99))[0]
	assert !bare.warning
	assert bare.class == .cpp
	unqual := pedantic_messages([token('typeof_unqual')], asking(.gnu99))[0]
	assert !unqual.warning
	assert unqual.class == .cpp
	// The rows that are a question about the dialect keep the pedantic class: the
	// flags decide whether the reader is told, and a compile is not stopped.
	question := pedantic_messages([token('__int128')], asking(.c99))[0]
	assert question.warning
	assert question.class == .pedantic
}

// A double underscore on both sides of a name puts it in the reserved
// namespace, which no mode has to grant and none may refuse. Measured on gcc
// 16.2.1, `__typeof__(x) y = 2;`, `__typeof(x) y = 2;` and
// `__typeof_unqual__(x) y = 2;` are accepted under -std=c89 ... -std=c23 and
// under -std=gnu99, `-std=c99 -pedantic-errors` included, with empty stderr.
// The rows are in the table so a reader finds the spellings where the others
// are, and the check reports none of them in any mode.
fn test_the_underscored_spellings_are_reserved_and_never_reported() {
	// One row carries the two spellings of the qualified specifier and one row
	// the unqualified one, and both say the same thing: every mode takes it.
	qualified := features.filter(it.spellings.contains('__typeof__'))
	assert qualified.len == 1
	assert qualified[0].spellings == ['__typeof__', '__typeof']
	assert qualified[0].reserved
	assert qualified[0].since == .none
	assert !qualified[0].gnu
	assert qualified[0].pedantic == ''
	unqualified := features.filter(it.spellings.contains('__typeof_unqual__'))
	assert unqualified.len == 1
	assert unqualified[0].spellings == ['__typeof_unqual__']
	assert unqualified[0].reserved
	assert unqualified[0].since == .none
	assert !unqualified[0].gnu
	assert unqualified[0].pedantic == ''
	// The reserved property is not on a row that also carries a bare spelling:
	// the bare ones are the two the modes report.
	for feature in features {
		for spelling in ['typeof', 'typeof_unqual'] {
			if feature.spellings.contains(spelling) {
				assert !feature.reserved, spelling
			}
		}
	}
	// And no mode reports any of the three, `-pedantic-errors` included.
	modes := [
		Mode.c89,
		.c99,
		.c11,
		.c17,
		.c23,
		.gnu89,
		.gnu99,
		.gnu11,
		.gnu17,
		.gnu23,
		.none,
		.other,
	]
	for mode in modes {
		tokens := [token('__typeof__'), token('__typeof'), token('__typeof_unqual__')]
		assert pedantic_messages(tokens, asking(mode)).len == 0, mode.spelling()
	}
	// A program that writes a reserved spelling beside a bare one hears about
	// the bare one only, in the mode that lacks it.
	pair := [token('typeof'), token('__typeof__')]
	assert pedantic_messages(pair, asking(.c99)).len == 1
	assert pedantic_messages(pair, asking(.c23)).len == 0
}

// The 128-bit integer is a GNU extension and no ISO mode has it, so the row
// reports in every strict mode and is silent in a GNU one. Measured on gcc
// 16.2.1, which warns `ISO C does not support '__int128' types` under
// `-std=c99 -pedantic`, makes it an error under `-pedantic-errors`, says the
// same under `-std=c23 -pedantic-errors`, and says nothing under `-std=gnu99`.
fn test_the_128_bit_row_reports_in_a_strict_mode_only() {
	tokens := [token('__int128')]
	strict := pedantic_messages(tokens, asking(.c99))
	assert strict.len == 1
	assert strict[0].msg == 'ISO C99 forbids the __int128 type'
	assert pedantic_messages(tokens, asking(.c23)).len == 1
	assert pedantic_messages(tokens, asking(.gnu99)).len == 0
	assert pedantic_messages(tokens, asking(.gnu11)).len == 0
	// `unsigned __int128` is found by the same token, so a strict mode reports
	// it for the run of words the unsigned type is written with as well.
	unsigned_run := [token('unsigned'), token('__int128')]
	assert pedantic_messages(unsigned_run, asking(.c99)).len == 1
}

// The 128-bit type C23 added is part of C23 and of no earlier standard, so a
// mode before C23 reports it and a C23 mode does not. Measured on gcc 16.2.1,
// which warns `ISO C does not support '_BitInt(128)' before C23` under
// `-std=c99 -pedantic`, says it under c11 and gnu99 too, makes it an error under
// `-pedantic-errors`, and says nothing under `-std=c23` or `-std=gnu23`.
fn test_the_bitint_row_reports_before_c23_only() {
	tokens := [token('_BitInt')]
	strict := pedantic_messages(tokens, asking(.c99))
	assert strict.len == 1
	assert strict[0].msg == 'ISO C99 forbids the _BitInt type'
	assert pedantic_messages(tokens, asking(.c11)).len == 1
	// A GNU mode does not grant the type the way it grants a GNU extension:
	// gnu99 reports it too, which is what the row's gnu flag is not set for.
	assert pedantic_messages(tokens, asking(.gnu99)).len == 1
	assert pedantic_messages(tokens, asking(.c23)).len == 0
	// A declaration written `unsigned _BitInt(128)` is found by the same token.
	unsigned_run := [token('unsigned'), token('_BitInt')]
	assert pedantic_messages(unsigned_run, asking(.c99)).len == 1
}

fn test_a_system_header_is_not_the_program() {
	tokens := [tokenize.Token{
		kind: .identifier
		text: '__attribute__'
		line: 4
		col:  1
		file: '/usr/include/stdio.h'
	}]
	mut question := asking(.c99)
	question.system_files['/usr/include/stdio.h'] = true
	assert pedantic_messages(tokens, question).len == 0
}

fn test_an_extension_brings_a_construct_down_to_this_mode() {
	table := [
		Feature{
			spellings: ['_Generic']
			since:     .c11
			gnu:       false
			extension: 'generic'
			pedantic:  'the _Generic selection'
			status:    .implemented
		},
	]
	tokens := [token('_Generic')]
	mut question := asking(.c99)
	// In c99 the construct is beyond the mode, and the row says which
	// extension brings it down.
	assert uses(tokens, table, question).len == 1
	question.extensions = ['generic']
	assert uses(tokens, table, question).len == 0
	// The extension is not the only way in: the standard that made the
	// construct standard takes it as it is.
	question = asking(.c11)
	assert uses(tokens, table, question).len == 0
}

fn test_a_row_that_is_not_implemented_yet_is_read_by_nothing() {
	table := [
		Feature{
			spellings: ['_Generic']
			since:     .c11
			gnu:       false
			extension: ''
			pedantic:  'the _Generic selection'
			status:    .unimplemented
		},
	]
	assert uses([token('_Generic')], table, asking(.c99)).len == 0
}

fn test_a_static_assertion_is_not_read_and_is_therefore_not_checked() {
	// The row is unimplemented and unchecked because the tree does not read a
	// static assertion: at file scope the parser refuses it, and inside a
	// function body the statement path reads the token as a call, which is the
	// parser's defect and not a reading the table may claim. Promoting the row
	// would report the construct in front of that refusal, which is the noise
	// the status rule keeps out; the day the parser reads one, the status
	// changes and the message below is what the check will print.
	rows := features.filter(it.spellings.contains('_Static_assert'))
	assert rows.len == 1
	assert rows[0].status == .unimplemented
	assert rows[0].since == .c11
	assert !rows[0].gnu
	assert rows[0].pedantic == 'the _Static_assert declaration'
	assert pedantic_messages([token('_Static_assert')], asking(.c99)).len == 0
}
