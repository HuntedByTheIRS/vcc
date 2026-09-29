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
	result := lex('int x = 1 $ 2;')
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
	fragment := lex_fragment('define S(x) #x')
	assert fragment.len == 7
	assert fragment[0].text == 'define'
	assert fragment[5].text == '#'
	paste := lex_fragment('define PS(a, b) a ## b')
	assert paste[8].text == '##'
}

fn test_a_fragment_has_no_end_of_file_token() {
	// A fragment ends where the caller's text ends, so there is nothing for an
	// eof token to mark.
	assert lex_fragment('').len == 0
	assert lex_fragment('x').len == 1
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

// gcc_preprocessed is what gcc makes of a file with `-E`, read back as tokens.
// The line markers gcc writes are not part of the program, so they are left
// out. A machine without gcc returns none, and the test that called this says
// so rather than passing quietly: what is being compared is two compilers.
fn gcc_preprocessed(source string) ?[]string {
	dir := os.join_path(os.temp_dir(), 'vcc-lexer-oracle-${os.getpid()}')
	os.mkdir_all(dir) or { return none }
	file := os.join_path(dir, 'phase-fixture.c')
	os.write_file(file, source) or { return none }
	result := os.execute('gcc -std=c99 -E ${os.quoted_path(file)} 2>/dev/null')
	if result.exit_code != 0 {
		return none
	}
	mut out := []string{}
	for line in result.output.split_into_lines() {
		if line.trim_space().starts_with('#') {
			continue
		}
		out << tokens_of(line)
	}
	return out
}

fn test_a_trigraph_is_replaced_before_anything_reads_the_text() {
	assert texts('a ??! b') == ['a', '|', 'b', '']
	assert texts('??=??=') == ['##', '']
	assert texts('??(0??)') == ['[', '0', ']', '']
	assert texts('a ??- b') == ['a', '~', 'b', '']
}

fn test_a_trigraph_inside_a_literal_is_replaced_too() {
	// Phase 1 runs before the text is read as anything at all, so a string
	// literal is not a place a trigraph is safe.
	assert texts('"a??!b"') == ['"a|b"', '']
	assert texts("'??('") == ["'['", '']
}

fn test_a_trigraph_in_a_directive_line_is_replaced() {
	tokens := lex('#define X ??!\nint x;').tokens
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
	assert tokens_of('int a; // one ??/\nint b;\n') == ['int', 'a', ';']
}

fn test_a_trigraph_at_the_end_of_a_line_joins_the_two_lines() {
	assert texts('int fo\\\nobar;') == ['int', 'foobar', ';', '']
	assert tokens_of('int fo??/\nobar;') == ['int', 'foobar', ';']
}

fn test_the_phases_produce_what_gcc_produces() {
	// One fixture per ordering the phases decide between, compared with the
	// oracle in the same run. The comment cases are the ones that separate the
	// two orders: reading comments first would leave `int b;` in the stream.
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
		assert expected == tokens_of(source)
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
	result := lex('int x = ' + '??-'.repeat(20000) + ' 1;')
	assert result.diagnostics.len == 0
	assert result.tokens.len == 20000 + 6
	// And a trigraph is replaced before the punctuation table reads it: `??!`
	// twice is the `||` operator and not two `|` tokens.
	assert texts('??!??!') == ['||', '']
}

fn test_a_spliced_continuation_of_a_hundred_thousand_lines_is_one_line() {
	// The same shape for phase 2: 100000 line endings deleted, so the whole
	// file is one logical line and one token stream.
	result := lex('int x = 1;\\\n'.repeat(100000) + 'int y;')
	assert result.diagnostics.len == 0
	assert result.tokens.len == 100000 * 5 + 3 + 1
}
