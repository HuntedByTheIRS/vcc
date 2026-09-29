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
		assert feature.pedantic != ''
		if feature.status == .implemented {
			assert feature.spellings.len > 0, 'an implemented row is found by a spelling'
		}
		if feature.since == .none {
			assert feature.gnu, 'a construct no ISO mode has is a GNU extension'
		}
	}
}

fn test_nothing_is_brought_down_by_an_extension_yet() {
	// The flag parses names and honors none of them, so no row may claim an
	// extension: the day one does, that is the day the flag changes what the
	// compiler accepts.
	for feature in features {
		assert feature.extension == ''
	}
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
	// typeof is not implemented, so a program writing it is refused by the
	// parser; a message from this table on top of that refusal would say the
	// same thing twice and would be the wrong thing once the parser lands.
	tokens := [token('typeof'), token('int')]
	assert pedantic_messages(tokens, asking(.c99)).len == 0
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
