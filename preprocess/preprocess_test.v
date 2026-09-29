module preprocess

// The tests drive the preprocessor the way main.v does and read the stream it
// produces, because that stream is the product: everything downstream is
// somebody else's stage.

fn processed(source string) []string {
	result := preprocess(source, 'test.c', Options{})
	assert result.diagnostics.len == 0
	mut texts := []string{}
	for tok in result.tokens {
		texts << tok.text
	}
	return texts
}

fn diagnostics_of(source string) []string {
	result := preprocess(source, 'test.c', Options{})
	mut messages := []string{}
	for diagnostic in result.diagnostics {
		messages << diagnostic.msg
	}
	return messages
}

fn test_text_without_directives_comes_through_unchanged() {
	assert processed('int x = 7;') == ['int', 'x', '=', '7', ';']
}

fn test_the_output_does_not_carry_the_end_of_file_marker() {
	// The parser is handed a token list and the end of it is the end of the
	// list; an eof token in the middle of a folded file would be a lie.
	assert processed('') == []
}

fn test_an_object_like_macro_replaces_its_name() {
	assert processed('#define N 7\nint x = N;') == ['int', 'x', '=', '7', ';']
}

fn test_a_macro_expands_into_another_macro() {
	assert processed('#define A B\n#define B 2\nA') == ['2']
}

fn test_a_macro_that_names_itself_stops() {
	// `#define A B` beside `#define B A` is two macros pointing at each other.
	// The name being expanded is left alone when it comes back around, which is
	// the rule that makes that terminate.
	assert processed('#define A B\n#define B A\nA') == ['A']
}

fn test_a_name_written_twice_expands_twice() {
	assert processed('#define N 1\nN N') == ['1', '1']
}

fn test_undef_takes_a_macro_away() {
	assert processed('#define N 1\n#undef N\nN') == ['N']
}

fn test_a_macro_with_no_replacement_expands_to_nothing() {
	assert processed('#define E\nx E y') == ['x', 'y']
}

fn test_a_directive_line_reaches_nothing_but_the_macro_table() {
	assert processed('#define N 7\nN') == ['7']
}

fn test_a_null_directive_is_read_and_dropped() {
	assert processed('#\nint x;') == ['int', 'x', ';']
}

fn test_a_line_marker_is_read_and_dropped() {
	// A preprocessed stream names where its text came from with these; every
	// token this compiler produces already carries that, so there is nothing
	// left for a marker to say.
	assert processed('# 1 "hello.c"\nint x;') == ['int', 'x', ';']
}

fn test_every_output_token_names_the_file_it_came_from() {
	result := preprocess('int x;', 'dir/test.c', Options{})
	assert result.tokens[0].file == 'dir/test.c'
}

fn test_error_stops_the_stream_with_its_message() {
	messages := diagnostics_of('#error this cannot be compiled\n')
	assert messages.len == 1
	assert messages[0].contains('this cannot be compiled')
}

fn test_an_include_is_not_pretended_to_work() {
	messages := diagnostics_of('#include <stdio.h>\n')
	assert messages.len == 1
	assert messages[0].contains('#include')
}

fn test_a_function_like_macro_is_diagnosed_where_it_is_used() {
	// The definition parses and is remembered; expanding it is what the
	// compiler cannot do yet, and that is what it has to say.
	assert processed('#define F(x) x\n') == []
	messages := diagnostics_of('#define F(x) x\nF(1)\n')
	assert messages.len == 1
	assert messages[0].contains('function-like macro')
}

fn test_an_unknown_directive_is_diagnosed_with_its_name() {
	messages := diagnostics_of('#frobnicate\n')
	assert messages.len == 1
	assert messages[0].contains('frobnicate')
}

fn test_a_define_from_the_command_line_is_in_force_before_the_file_is_read() {
	result := preprocess('int x = N;', 'test.c', Options{
		defines: ['N=7']
	})
	assert result.diagnostics.len == 0
	assert result.tokens[3].text == '7'
}

fn test_an_undefine_from_the_command_line_takes_a_macro_away() {
	result := preprocess('int x = N;', 'test.c', Options{
		undefines: ['N']
	})
	assert result.diagnostics.len == 0
	assert result.tokens[3].text == 'N'
}

fn test_ifdef_reads_the_branch_that_is_taken() {
	assert processed('#ifdef N\nint x;\n#endif\n') == [] // N is not defined
	assert processed('#define N\n#ifdef N\nint x;\n#endif\n') == ['int', 'x', ';']
}

fn test_ifndef_is_the_other_side_of_ifdef() {
	assert processed('#ifndef N\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#define N\n#ifndef N\nint x;\n#endif\n') == []
}

fn test_if_reads_its_expression() {
	assert processed('#if 1\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#if 0\nint x;\n#endif\n') == []
	assert processed('#if 1 + 1 == 2\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#if 1 < 2 && 3 > 2\nint x;\n#endif\n') == ['int', 'x', ';']
}

fn test_a_name_that_is_not_defined_is_zero_in_an_if() {
	assert processed('#if NOPE\nint x;\n#endif\n') == []
	assert processed('#if !NOPE\nint x;\n#endif\n') == ['int', 'x', ';']
}

fn test_defined_answers_from_the_macro_table_before_expansion() {
	assert processed('#define N 1\n#if defined(N)\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#if defined N\nint x;\n#endif\n') == []
	assert processed('#define N 1\n#if defined NOPE\nint x;\n#endif\n') == []
}

fn test_elif_and_else_take_the_first_branch_that_is_true() {
	source := '#if 0\nint a;\n#elif 1\nint b;\n#else\nint c;\n#endif\n'
	assert processed(source) == ['int', 'b', ';']
	source2 := '#if 0\nint a;\n#elif 0\nint b;\n#else\nint c;\n#endif\n'
	assert processed(source2) == ['int', 'c', ';']
}

fn test_only_one_branch_is_read_even_when_two_would_be_true() {
	source := '#if 1\nint a;\n#elif 1\nint b;\n#endif\n'
	assert processed(source) == ['int', 'a', ';']
}

fn test_nested_conditionals_keep_their_own_state() {
	source := '#if 1\n#if 0\nint a;\n#else\nint b;\n#endif\n#endif\n'
	assert processed(source) == ['int', 'b', ';']
	// The inner one is closed by the first #endif and the outer by the second,
	// so text between the two is still inside the outer branch.
	source2 := '#if 1\n#endif\nint a;\n'
	assert processed(source2) == ['int', 'a', ';']
}

fn test_a_define_inside_a_branch_that_was_not_taken_is_not_defined() {
	source := '#if 0\n#define N 1\n#endif\n#ifdef N\nint a;\n#endif\n'
	assert processed(source) == []
}

fn test_a_branch_that_was_not_taken_is_not_evaluated() {
	// Short-circuiting is what keeps this one from being a division by zero.
	assert processed('#if 0 && 1 / 0\nint x;\n#endif\n') == []
	assert processed('#if 1 || 1 / 0\nint x;\n#endif\n') == ['int', 'x', ';']
	messages := diagnostics_of('#if 1 / 0\nint x;\n#endif\n')
	assert messages.len == 1
	assert messages[0].contains('division by zero')
}

fn test_a_conditional_that_is_never_closed_is_diagnosed() {
	messages := diagnostics_of('#if 1\nint x;\n')
	assert messages.len == 1
	assert messages[0].contains('unterminated')
}

fn test_a_conditional_directive_with_nothing_to_belong_to_is_diagnosed() {
	assert diagnostics_of('#endif\n')[0].contains('#endif')
	assert diagnostics_of('#else\n')[0].contains('#else')
	assert diagnostics_of('#elif 1\n')[0].contains('#elif')
}

fn test_a_second_else_has_nothing_left_to_say() {
	messages := diagnostics_of('#if 0\n#else\n#else\n#endif\n')
	assert messages.len == 1
	assert messages[0].contains('#else after #else')
}
