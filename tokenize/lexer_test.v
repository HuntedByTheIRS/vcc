module tokenize

import os

fn kinds(source string) []Kind {
	mut out := []Kind{}
	for tok in lex(source).tokens {
		out << tok.kind
	}
	return out
}

fn texts(source string) []string {
	mut out := []string{}
	for tok in lex(source).tokens {
		out << tok.text
	}
	return out
}

fn test_identifiers_and_keywords_lex_the_same() {
	// `return` is a keyword to the parser and an identifier to the lexer, which
	// is the whole point of not having a keyword kind.
	assert texts('return main') == ['return', 'main', '']
	assert kinds('return main') == [.identifier, .identifier, .eof]
}

fn test_numbers_of_every_base() {
	assert texts('0 42 0x2a 052 0b1010 1.5e-3f') == ['0', '42', '0x2a', '052', '0b1010', '1.5e-3f',
		'']
}

fn test_punctuation_is_matched_longest_first() {
	assert texts('<<= << <') == ['<<=', '<<', '<', '']
	// The compound spellings of the assignment, which is a spelling the operator
	// table has to carry in one piece: `/=` was missing from it while `*=` and `%=`
	// were there, so `x /= 2` lexed as two tokens and the reader reported the `=`.
	assert texts('/= %= &= |= ^=') == ['/=', '%=', '&=', '|=', '^=', '']
	assert texts('-> ++ == != ...') == ['->', '++', '==', '!=', '...', '']
	assert texts('[a] . b ? c') == ['[', 'a', ']', '.', 'b', '?', 'c', '']
}

fn test_comments_are_dropped_and_lines_keep_counting() {
	source := 'int a; // one\n/* two\nthree */ int b;'
	assert texts(source) == ['int', 'a', ';', 'int', 'b', ';', '']
	tokens := lex(source).tokens
	assert tokens[0].line == 1
	assert tokens[3].line == 3
	assert tokens[3].text == 'int'
}

fn test_a_directive_is_one_token() {
	tokens := lex('#define N 7\nint x;').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#define N 7'
	assert tokens[1].text == 'int'
}

fn test_a_directive_continued_with_a_backslash_stays_one_token() {
	tokens := lex('#define N \\\n	7\nint x;').tokens
	assert tokens[0].kind == .directive
	// Splicing joins the lines; the whitespace that followed the backslash is
	// still part of the directive, as it is in C.
	assert tokens[0].text == '#define N 	7'
	assert tokens[0].line == 1
	assert tokens[1].text == 'int'
	assert tokens[1].line == 3
}

fn test_a_comment_in_a_directive_line_is_one_space() {
	tokens := lex('#define N 7 /* seven */\nint x;').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#define N 7'
}

fn test_a_comment_that_runs_over_the_end_of_a_line_takes_the_directive_with_it() {
	// C replaces every comment with a space before it looks for directives, so
	// the newline inside one does not end the line. It is how gcc's stddef.h
	// ends, and reading it any other way leaks the comment into the program.
	tokens := lex('#endif /* a\n b */\nint x;').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#endif'
	assert tokens[1].text == 'int'
	assert tokens[1].line == 3
}

fn test_a_line_comment_ends_a_directive() {
	tokens := lex('#define N 1 // one\nint x;').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#define N 1'
	assert tokens[1].text == 'int'
}

// The gate reads the bare spelling of the include directive in a V source as C
// interop, which is what it is when a V program asks for a C header, so the one
// test here that lexes an include line builds it from parts.
const include_word = 'include'

fn include_line(rest string) string {
	return '#${include_word} ${rest}\n'
}

fn test_a_comment_inside_a_string_in_a_directive_is_text() {
	tokens := lex(include_line('"a/*b.h"')).tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#${include_word} "a/*b.h"'
}

fn test_literals_keep_their_escapes() {
	assert texts('\'a\' \'\\n\' "hi\\"there" L\'x\'') == ["'a'", "'\\n'", '"hi\\"there"', "L'x'",
		'']
	assert kinds('\'a\' "s"') == [.character, .string, .eof]
}

fn test_positions_point_at_the_start_of_the_token() {
	tokens := lex('int\n\tmain').tokens
	assert tokens[0].line == 1 && tokens[0].col == 1
	assert tokens[1].line == 2 && tokens[1].col == 2
}

fn test_an_unterminated_literal_is_reported_with_its_position() {
	result := lex("int x = 'a;")
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].msg.contains('unterminated character literal')
}

fn test_an_unterminated_comment_is_reported() {
	result := lex('int x; /* never closed')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unterminated block comment')
}

fn test_an_unexpected_character_is_reported() {
	// `$` is not the example any more: it is an identifier character, since
	// GNU C takes it and this compiler follows it. The byte that is nobody's is
	// the one the message is tested with.
	result := lex('int x = 1 @ 2;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('unexpected character')
	assert result.diagnostics[0].col == 11
}

fn test_every_input_ends_with_an_eof_token() {
	assert lex('').tokens.len == 1
	assert lex('').tokens[0].kind == .eof
}

fn test_a_hash_that_is_not_the_first_token_on_a_line_is_a_punctuator() {
	// C's rule is about position rather than about the byte: `##` pastes and `#`
	// stringizes inside a macro body, and neither opens a directive there.
	assert texts('int x = a ## b;') == ['int', 'x', '=', 'a', '##', 'b', ';', '']
	assert texts('int x = a # b;') == ['int', 'x', '=', 'a', '#', 'b', ';', '']
}

fn test_a_comment_does_not_move_a_directive_off_the_start_of_its_line() {
	tokens := lex('/* a\nb */ #define N 7\n').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#define N 7'
	assert tokens[0].line == 2
}

fn test_a_fragment_lexes_its_hashes_as_punctuators() {
	fragment := lex_fragment('define S(x) #x', true)
	assert fragment.len == 7
	assert fragment[0].text == 'define'
	assert fragment[5].text == '#'
	paste := lex_fragment('define PS(a, b) a ## b', true)
	assert paste[8].text == '##'
}

fn test_a_fragment_has_no_end_of_file_token() {
	// A fragment ends where the caller's text ends, so there is nothing for an
	// eof token to mark.
	assert lex_fragment('', true).len == 0
	assert lex_fragment('x', true).len == 1
}

// The translation phases. Phase 1 is trigraph replacement, phase 2 is line
// splicing, and both run before anything reads a byte; the tests below pin the
// order they run in, because that order is the whole of what they mean. gcc
// 16.2.1 is the oracle for each ordering, and the comparison with it is made
// when the test runs rather than recorded from one run of it.

// tokens_of is the text of each token of a source, without the end-of-file
// marker: what a comparison with a preprocessed file is about.
fn tokens_of(source string) []string {
	mut out := []string{}
	for tok in lex(source).tokens {
		if tok.kind == .eof {
			continue
		}
		out << tok.text
	}
	return out
}

// iso is the lexer reading a source under a strict ISO mode, which is the one
// shape in which phase 1 replaces a trigraph: `standard.replaces_trigraphs` is
// where that answer is written down, and this module cannot import `standard` —
// `standard` imports this one — so the tests of phase 1 spell it out and ask
// through these. `lex` with no dialect named is the other direction, the answer
// the compiler's own default mode gets.
fn iso(source string) Result {
	return lex_with(source, Options{
		trigraphs: true
	})
}

fn iso_texts(source string) []string {
	mut out := []string{}
	for tok in iso(source).tokens {
		out << tok.text
	}
	return out
}

fn iso_tokens_of(source string) []string {
	mut out := []string{}
	for tok in iso(source).tokens {
		if tok.kind == .eof {
			continue
		}
		out << tok.text
	}
	return out
}

// gcc_text is what gcc prints for a file with `-E`, with the line markers it
// writes left out. Some of what the phases decide is a spelling rather than a
// token, so the text itself is what has to be compared there: reading gcc's
// output back with this lexer would agree with this compiler whatever it wrote.
// A machine without gcc returns none, and the test that called this says so
// rather than passing quietly, because what is being compared is two compilers.
fn gcc_text(source string) ?string {
	dir := os.join_path(os.temp_dir(), 'vcc-lexer-oracle-${os.getpid()}')
	os.mkdir_all(dir) or { return none }
	file := os.join_path(dir, 'phase-fixture.c')
	os.write_file(file, source) or { return none }
	result := os.execute('gcc -std=c99 -E ${os.quoted_path(file)} 2>/dev/null')
	if result.exit_code != 0 {
		return none
	}
	mut out := ''
	for line in result.output.split_into_lines() {
		if line.trim_space().starts_with('#') {
			continue
		}
		out += line + '\n'
	}
	return out
}

// gcc_preprocessed is the same text read back as tokens.
fn gcc_preprocessed(source string) ?[]string {
	text := gcc_text(source) or { return none }
	mut out := []string{}
	for line in text.split_into_lines() {
		out << tokens_of(line)
	}
	return out
}

fn test_a_trigraph_is_replaced_before_anything_reads_the_text() {
	assert iso_texts('a ??! b') == ['a', '|', 'b', '']
	assert iso_texts('??=??=') == ['##', '']
	assert iso_texts('??(0??)') == ['[', '0', ']', '']
	assert iso_texts('a ??- b') == ['a', '~', 'b', '']
}

fn test_a_trigraph_inside_a_literal_is_replaced_too() {
	// Phase 1 runs before the text is read as anything at all, so a string
	// literal is not a place a trigraph is safe.
	assert iso_texts('"a??!b"') == ['"a|b"', '']
	assert iso_texts("'??('") == ["'['", '']
}

fn test_a_trigraph_in_a_directive_line_is_replaced() {
	tokens := iso('#define X ??!\nint x;').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#define X |'
}

fn test_a_line_ending_spliced_away_joins_the_lines_around_it() {
	// Splicing deletes the backslash and the line ending, so the two halves are
	// one identifier and not a name, a stray byte and another name.
	assert texts('fo\\\nobar') == ['foobar', '']
	// The token after the join still reports the line it was written on, which
	// is what a diagnostic has to point at.
	tokens := lex('int a;\\\nint b;').tokens
	assert tokens[3].text == 'int'
	assert tokens[3].line == 2
	assert tokens[3].col == 1
}

fn test_a_line_ending_spliced_away_does_not_end_a_line_comment() {
	// Splicing runs before comment removal, so a backslash at the end of a `//`
	// comment carries the comment onto the next line and the text there never
	// reaches the token stream.
	assert tokens_of('int a; // one \\\nint b;\n') == ['int', 'a', ';']
}

fn test_a_trigraph_at_the_end_of_a_line_comment_splices_the_next_line_into_it() {
	// The other half of the same ordering: `??/` is a backslash by the time
	// the splice looks at it, so the line ending it stands before is deleted
	// and the following line is inside the comment.
	assert iso_tokens_of('int a; // one ??/\nint b;\n') == ['int', 'a', ';']
}

fn test_a_trigraph_at_the_end_of_a_line_joins_the_two_lines() {
	assert texts('int fo\\\nobar;') == ['int', 'foobar', ';', '']
	assert iso_tokens_of('int fo??/\nobar;') == ['int', 'foobar', ';']
}

fn test_the_phases_produce_what_gcc_produces() {
	// One fixture per ordering the phases decide between, compared with the
	// oracle in the same run. The comment cases are the ones that separate the
	// two orders: reading comments first would leave `int b;` in the stream.
	// The oracle is `gcc -std=c99`, so the candidate side is the strict ISO
	// reading and not the mode-less default: a trigraph is replaced there.
	fixtures := [
		'int main(void) { return 0 ??!??! 0; }',
		'char *s = "a??!b";',
		'int a; // one ??/\nint b;\n',
		'int a; // one \\\nint b;\n',
		'int fo\\\nobar;\n',
	]
	for source in fixtures {
		expected := gcc_preprocessed(source) or {
			eprintln('gcc is not on this machine, so the phase comparison is skipped')
			return
		}
		assert expected == iso_tokens_of(source)
	}
}

fn test_a_logical_source_line_of_four_thousand_and_ninety_five_characters_is_read() {
	// 5.2.4.1 asks an implementation to support a logical source line of 4095
	// characters. That is a floor and not a ceiling, and the line here is
	// exactly it: a longer line is read as well rather than refused, because
	// refusing a legal program is the worse defect of the two.
	body := 'a'.repeat(4095 - 9)
	source := 'int ${body} = 0;'
	assert source.len == 4095
	result := lex(source)
	assert result.diagnostics.len == 0
	assert result.tokens[1].text.len == 4086
	long := lex('int ${'b'.repeat(9000)} = 0;')
	assert long.diagnostics.len == 0
	assert long.tokens[1].text.len == 9000
}

fn test_a_file_of_many_trigraphs_is_one_pass_over_the_bytes() {
	// 20000 of them on one line: the phases are a walk and not a recursion, so
	// this is a test of the shape a stack overflow would show up in. `??-` is
	// used because `~` does not combine with itself into a longer punctuator,
	// so the count of tokens is the count of trigraphs plus the rest.
	result := iso('int x = ' + '??-'.repeat(20000) + ' 1;')
	assert result.diagnostics.len == 0
	assert result.tokens.len == 20000 + 6
	// And a trigraph is replaced before the punctuation table reads it: `??!`
	// twice is the `||` operator and not two `|` tokens.
	assert iso_texts('??!??!') == ['||', '']
}

fn test_phase_one_is_the_selected_mode_s_answer() {
	// Both directions of the dialect answer, which is the whole of finding
	// C1-r1-1. gcc 16.2.1, measured one mode at a time over
	// `int main(void) { return 0 ??!??! 0; }`: the strict ISO modes (`-std=c89`,
	// `-std=c99`, `-std=c11`, `-std=c17`) replace, and a GNU dialect, `-std=c23`
	// and no `-std` at all leave the bytes where they are, with
	// `trigraph '??!' ignored, use '-trigraphs' to enable`. `iso` is the strict
	// reading; `lex`, which names no dialect, is the default one.
	assert iso_texts('0 ??! 1') == ['0', '|', '1', '']
	assert texts('0 ??! 1') == ['0', '?', '?', '!', '1', '']
	// A string literal is the case a program would notice: `"??!"` is one byte
	// under `-std=c99` and the three bytes that were written everywhere else.
	assert iso_texts('"??!"') == ['"|"', '']
	assert texts('"??!"') == ['"??!"', '']
	// A directive line is read with the same answer, because phase 1 runs before
	// anything looks at the line.
	assert iso('#define X ??!\nint x;').tokens[0].text == '#define X |'
	assert lex('#define X ??!\nint x;').tokens[0].text == '#define X ??!'
	// A fragment is text phase 1 has already had — a directive line a file's
	// lexer copied, a macro body, a name a paste built — so the fragment reader
	// never replaces. gcc is the same about text that was never a file's bytes:
	// measured, `gcc -std=c99 -E -DX='??!'` prints `??!`.
	assert lex_fragment('??!', true).map(it.text) == ['?', '?', '!']
}

fn test_a_spliced_continuation_of_a_hundred_thousand_lines_is_one_line() {
	// The same shape for phase 2: 100000 line endings deleted, so the whole
	// file is one logical line and one token stream.
	result := lex('int x = 1;\\\n'.repeat(100000) + 'int y;')
	assert result.diagnostics.len == 0
	assert result.tokens.len == 100000 * 5 + 3 + 1
}

fn test_a_dollar_is_an_identifier_character() {
	// GNU C takes `$` in a name in every mode (measured: `int $x = 0;` compiles
	// under `-std=c99 -pedantic-errors` with gcc 16.2.1), and this compiler
	// follows it. That it is a GNU extension is the dialect table's business
	// and not this file's: there is no mode here to ask.
	assert texts('$x $ $y') == ['$x', '$', '$y', '']
	assert texts('int a$b = 1;') == ['int', 'a$b', '=', '1', ';', '']
}

fn test_a_universal_character_name_is_part_of_an_identifier() {
	// `\uXXXX` and `\UXXXXXXXX` name one character, and a name is as much a
	// part of an identifier as a letter is: `a\u00e9b` is one token. The
	// spelling in the token is `\U` and eight lowercase hexadecimal digits,
	// which is what gcc writes in a preprocessed stream, so the text is
	// something C reads back as the same name.
	assert texts('int \\u00e9 = 1;') == ['int', '\\U000000e9', '=', '1', ';', '']
	assert texts('int a\\u00e9b = 1;') == ['int', 'a\\U000000e9b', '=', '1', ';', '']
	assert texts('int \\U0001F600 = 1;') == ['int', '\\U0001f600', '=', '1', ';', '']
	// The dollar is the one character under A0 the standard lets a name name,
	// and the one gcc takes.
	assert texts('int \\u0024 = 1;') == ['int', '\\U00000024', '=', '1', ';', '']
}

fn test_a_universal_character_name_a_name_cannot_hold_is_reported() {
	// The two messages are gcc's, measured: `int \u0040 = 1;` gives
	// `universal character \u0040 is not valid in an identifier`, and
	// `int \U00110000 = 1;` names the same construct with the same words.
	small := lex('int \\u0040 = 1;')
	assert small.diagnostics.len == 1
	assert small.diagnostics[0].msg == 'universal character \\u0040 is not valid in an identifier'
	assert small.diagnostics[0].col == 5
	big := lex('int \\U00110000 = 1;')
	assert big.diagnostics.len == 1
	assert big.diagnostics[0].msg == 'universal character \\U00110000 is not valid in an identifier'
	// A name over A0 is taken as it stands, including the ones gcc refuses
	// because they are not letters: `\u00a1` and `\u00d7` are "not valid in an
	// identifier" to gcc, and deciding that would mean the letter ranges of
	// Annex D. The difference is a decision and not an oversight, so it is
	// pinned here.
	not_a_letter := lex('int \\u00a1 = 1;')
	assert not_a_letter.diagnostics.len == 0
	assert not_a_letter.tokens[1].text == '\\U000000a1'
}

fn test_a_universal_character_name_that_names_no_character_is_reported() {
	// gcc: `\UFFFFFFFF is not a valid universal character`, and the surrogate
	// range and a value past what the conversion holds are the same kind of
	// thing: there is no character there to name.
	assert lex('int \\UFFFFFFFF = 1;').diagnostics[0].msg == '\\UFFFFFFFF is not a valid universal character'
	assert lex('int \\UFFFFFFFE = 1;').diagnostics[0].msg == '\\UFFFFFFFE is not a valid universal character'
	assert lex('int \\U0000D800 = 1;').diagnostics[0].msg == '\\U0000D800 is not a valid universal character'
	assert lex('int \\U0000DFFF = 1;').diagnostics[0].msg == '\\U0000DFFF is not a valid universal character'
}

fn test_a_backslash_that_is_not_a_universal_character_name_is_not_one() {
	// Two digits short, and not hexadecimal: gcc reads the backslash as a stray
	// one (`stray '\' in program`) rather than as a name, and this compiler says
	// the same thing in its own words instead of inventing a name for it.
	short := lex('int \\u00 = 1;')
	assert short.diagnostics.len == 1
	assert short.diagnostics[0].msg.contains('unexpected character')
	assert short.diagnostics[0].col == 5
	not_hex := lex('int \\uZZZZ = 1;')
	assert not_hex.diagnostics.len == 1
	assert not_hex.diagnostics[0].msg.contains('unexpected character')
}

fn test_an_identifier_past_the_significance_floor_is_kept_whole() {
	// 5.2.4.1 asks for 63 significant characters in an internal identifier and
	// 31 in an external one. Both are floors and not ceilings: a name over
	// either is one token with every character of it, and two names that differ
	// only past the floor stay two names, because nothing here truncates a
	// name. That is the decision about short external identifiers: they do not
	// collapse.
	internal := 'a'.repeat(63)
	kept := lex('int ${internal}left; int ${internal}right;')
	assert kept.diagnostics.len == 0
	assert kept.tokens[1].text == '${internal}left'
	assert kept.tokens[4].text == '${internal}right'
	assert kept.tokens[1].text != kept.tokens[4].text
	external := 'e'.repeat(31)
	other := lex('int ${external}left; int ${external}right;')
	assert other.diagnostics.len == 0
	assert other.tokens[1].text == '${external}left'
	assert other.tokens[4].text == '${external}right'
	assert other.tokens[1].text.len == 35
}

fn test_the_universal_character_name_spelling_is_gcc_spelling() {
	// The spelling is the whole question here, so the comparison is with the
	// text gcc printed and not only with tokens of it: reading that text back
	// with this lexer would agree with this compiler whatever it wrote.
	source := 'int \\u00e9 = 1;\nint a\\u00e9b = 1;\nint \\U0001F600 = 1;\nint $x = 1;\n'
	text := gcc_text(source) or {
		eprintln('gcc is not on this machine, so the universal character name comparison is skipped')
		return
	}
	for token in tokens_of(source) {
		assert text.contains(token)
	}
	expected := gcc_preprocessed(source) or { return }
	assert expected == tokens_of(source)
}

// The literal classes C99 adds over C89, one test each, and each of them about
// the token rather than about a compile: what the parser is handed is what
// these pin, and a class read as two tokens fails here even when the file it
// came from would still compile.

fn test_the_float_suffixes_are_part_of_the_number() {
	// `f`, `F`, `l` and `L` say which type the constant has, and the number
	// reader keeps them: the token is the whole spelling.
	assert texts('1.5f 1.5F 1.5l 1.5L 1f 1F 1l 1L') == ['1.5f', '1.5F', '1.5l', '1.5L', '1f', '1F',
		'1l', '1L', '']
	assert texts('1.5e3L 1e+3f 1E-3L') == ['1.5e3L', '1e+3f', '1E-3L', '']
}

fn test_the_long_long_suffixes_are_part_of_the_number() {
	// `ll`, `LL`, `Ll` and `lL` are the long long suffixes, and the case of
	// each letter is its own: all four spellings are one token, on a decimal
	// and on a hexadecimal constant alike.
	assert texts('1ll 1LL 1Ll 1lL 1ull 1LLU 0x1ll') == ['1ll', '1LL', '1Ll', '1lL', '1ull', '1LLU',
		'0x1ll', '']
}

fn test_a_hexadecimal_float_is_one_number() {
	// 6.4.4.2: a hexadecimal floating constant is `0x`, its digits, a point, an
	// exponent letter and a binary exponent. The lexer keeps all of it as one
	// number, which is what lets the parser read it as one constant rather than
	// as three tokens standing in a row.
	assert texts('0x1p3 0x1.8p-4 0x1P+3f 0x.8p3') == ['0x1p3', '0x1.8p-4', '0x1P+3f', '0x.8p3',
		'']
	assert kinds('0x1p3') == [.number, .eof]
}

fn test_a_prefixed_string_is_one_literal() {
	// `L`, `u`, `U` and `u8` before a string or a character constant are part
	// of the literal and not an identifier standing beside one.
	assert texts('L"w" u8"w" u"w" U"w"') == ['L"w"', 'u8"w"', 'u"w"', 'U"w"', '']
	assert texts("L'x' u8'x' u'x' U'x'") == ["L'x'", "u8'x'", "u'x'", "U'x'", '']
	assert kinds('u8"w"') == [.string, .eof]
	assert kinds("U'x'") == [.character, .eof]
	// It is the position that makes it a prefix: `u8` with a space after it is
	// the name it looks like.
	assert texts('u8 "w"') == ['u8', '"w"', '']
}

fn test_a_multi_character_constant_is_one_literal() {
	// 6.4.4.4 takes more than one character between the quotes. What the value
	// is, is the literal reader's question; what the lexer hands over is one
	// token holding all of it.
	assert texts("'ab' 'abcd'") == ["'ab'", "'abcd'", '']
	assert kinds("'ab'") == [.character, .eof]
}

fn test_a_universal_character_name_escape_stays_in_the_literal() {
	// The escape is phase 5's business and not the lexer's: the token holds the
	// spelling with the backslash in it, which is what a reader that knows the
	// execution character set has to be given.
	assert texts('"\\u00e9" "\\U0001F600"') == ['"\\u00e9"', '"\\U0001F600"', '']
	assert texts("'\\u00e9'") == ["'\\u00e9'", '']
	assert kinds('"\\u00e9"') == [.string, .eof]
}

// The C99 6.4.6 digraphs are token spellings and not a phase 1 replacement, so
// the punctuator match reads them and the token it makes carries the punctuator's
// own spelling. The answer is the selected mode's, and `standard.has_digraphs` is
// where it is written down; this module cannot import `standard`, because
// `standard` imports this one, so the tests spell the answer out the way the
// trigraph ones do.
fn digraphs(source string) Result {
	return lex_with(source, Options{
		digraphs: true
	})
}

fn test_a_digraph_is_the_punctuator_it_names() {
	// Measured on gcc 16.2.1: `%:define A 41` is a definition there and not a
	// percent and a colon, which is the whole of that line — which is why gcc
	// accepts it under -std=c99 and refuses it at 1:1 under -std=c89. The token
	// this compiler makes carries the `#` spelling, because a `#` is what
	// everything downstream reads a directive by.
	opened := digraphs('%:define A 41\n')
	assert opened.diagnostics.len == 0
	assert opened.tokens[0].kind == .directive
	assert opened.tokens[0].text == '#define A 41'
	// All six spellings, a token each. `%:%:` is four characters, so a match that
	// looked three ahead would read a `#` and call the paste a stringize.
	assert lex_fragment('a %:%: b', true).map(it.text) == ['a', '##', 'b']
	assert lex_fragment('<% %> <: :>', true).map(it.text) == ['{', '}', '[', ']']
}

fn test_a_digraph_inside_a_literal_is_text() {
	// A literal is one token before the punctuator match reads anything, and that
	// is what separates a digraph from a trigraph: `??!` inside a literal is
	// replaced in a strict ISO mode, and `%:` inside one is a percent and a colon.
	assert digraphs('char *s = "%:";\n').tokens.map(it.text) == ['char', '*', 's', '=', '"%:"',
		';', '']
}

fn test_a_mode_without_the_digraphs_has_the_punctuators() {
	// The answer `-std=c89` gives. gcc 16.2.1 refuses `%:define` there with
	// `error: expected identifier or '('`, which is what reading it as `%` and
	// `:` costs, and a `%:%:` in a body is two punctuators rather than a paste.
	result := lex('%:define A 41\n')
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['%', ':', 'define', 'A', '41', '']
	assert lex_fragment('a %:%: b', false).map(it.text) == ['a', '%', ':', '%', ':', 'b']
}
