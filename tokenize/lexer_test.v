module tokenize

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

fn test_a_comment_inside_a_string_in_a_directive_is_text() {
	tokens := lex('#include "a/*b.h"\n').tokens
	assert tokens[0].kind == .directive
	assert tokens[0].text == '#include "a/*b.h"'
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
