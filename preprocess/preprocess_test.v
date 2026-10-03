module preprocess

import os
import standard
import time
import tokenize

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

// processed_in is `processed` under a named dialect, which is the mode main.v
// hands the preprocessor. It is what a test about the phases needs, because the
// mode decides a phase's answer and nothing else about the read.
fn processed_in(source string, mode standard.Mode) []string {
	result := preprocess(source, 'test.c', Options{
		dialect: mode
	})
	assert result.diagnostics.len == 0
	mut texts := []string{}
	for tok in result.tokens {
		texts << tok.text
	}
	return texts
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

// The include fixtures spell their directive lines through these, because the
// gate reads the bare spelling of the directive in a V source as C interop —
// which is what it is when a V program asks for a C header.
fn include_line(rest string) string {
	return '${hash}include ${rest}\n'
}

fn include_next_line(rest string) string {
	return '${hash}include_next ${rest}\n'
}

fn test_an_include_is_diagnosed_when_it_cannot_be_found() {
	messages := diagnostics_of(include_line('<no-such-header-anywhere.h>'))
	assert messages.len == 1
	assert messages[0].contains('no-such-header-anywhere.h')
}

// The include tests need real files, so they write a small tree and read it
// back: where a header is found is the whole point of the search order, and
// there is no way to test that without putting one somewhere.
fn fixture_directory() string {
	dir := os.join_path(os.temp_dir(), 'vcc-preprocess-test-${os.getpid()}')
	os.mkdir_all(dir) or {}
	return dir
}

fn test_an_angled_include_is_read_from_the_standard_directories() {
	dir := fixture_directory()
	header := os.join_path(dir, 'angled.h')
	os.write_file(header, 'int from_header;\n') or {}
	result := preprocess(include_line('<angled.h>'), os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'from_header', ';']
	// Every token says which file it was written in, including the ones that
	// were written in a header.
	assert result.tokens[0].file == header
}

fn test_a_quoted_include_is_looked_for_beside_the_file_that_wrote_it_first() {
	dir := fixture_directory()
	beside := os.join_path(dir, 'main.c')
	os.write_file(os.join_path(dir, 'twice.h'), 'int beside;\n') or {}
	other := os.join_path(dir, 'other')
	os.mkdir_all(other) or {}
	os.write_file(os.join_path(other, 'twice.h'), 'int from_elsewhere;\n') or {}
	quoted := preprocess(include_line('"twice.h"'), beside, Options{
		include_dirs:  [other]
		standard_dirs: [other]
	})
	assert quoted.diagnostics.len == 0
	assert quoted.tokens.map(it.text) == ['int', 'beside', ';']
	angled := preprocess(include_line('<twice.h>'), beside, Options{
		include_dirs:  [other]
		standard_dirs: [other]
	})
	assert angled.diagnostics.len == 0
	assert angled.tokens.map(it.text) == ['int', 'from_elsewhere', ';']
}

fn test_an_i_directory_is_searched_for_both_spellings() {
	dir := fixture_directory()
	headers := os.join_path(dir, 'i-headers')
	os.mkdir_all(headers) or {}
	os.write_file(os.join_path(headers, 'given.h'), 'int given;\n') or {}
	for name in ['"given.h"', '<given.h>'] {
		result := preprocess(include_line(name), os.join_path(dir, 'main.c'), Options{
			include_dirs: [headers]
		})
		assert result.diagnostics.len == 0
		assert result.tokens.map(it.text) == ['int', 'given', ';']
	}
}

fn test_a_header_name_with_a_slash_is_read_as_one_name() {
	// `#include <bits/types.h>` is lexed as several tokens — a name, a slash,
	// a name and a dot — and the characters between the brackets are the name
	// of the file.
	dir := fixture_directory()
	bits := os.join_path(dir, 'bits')
	os.mkdir_all(bits) or {}
	os.write_file(os.join_path(bits, 'types.h'), 'int typed;\n') or {}
	result := preprocess(include_line('<bits/types.h>'), os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'typed', ';']
}

fn test_an_absolute_include_is_opened_where_it_points() {
	// An absolute name is the file, so there is nothing to search: both
	// spellings open it, and it is not in any directory the search would
	// reach.
	dir := fixture_directory()
	header := os.join_path(os.abs_path(dir), 'absolute.h')
	os.write_file(header, 'int from_absolute;\n') or {}
	assert os.is_abs_path(header)
	for name in ['"${header}"', '<${header}>'] {
		result := preprocess(include_line(name), os.join_path(dir, 'main.c'), Options{})
		assert result.diagnostics.len == 0
		assert result.tokens.map(it.text) == ['int', 'from_absolute', ';']
		assert result.tokens[0].file == header
	}
}

fn test_an_absolute_include_that_is_not_there_is_refused_by_name() {
	// Nothing was searched for, so the message must not claim directories
	// were looked in.
	missing := os.join_path(os.abs_path(fixture_directory()), 'no-such-absolute.h')
	messages := diagnostics_of(include_line('"${missing}"'))
	assert messages.len == 1
	assert messages[0].contains(missing)
	assert !messages[0].contains('looked in')
}

fn test_an_include_guard_keeps_the_second_read_out() {
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'guarded.h'), '#ifndef GUARDED_H\n#define GUARDED_H\nint once;\n#endif\n') or {}
	source := include_line('<guarded.h>') + include_line('<guarded.h>')
	result := preprocess(source, os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'once', ';']
}

fn test_pragma_once_keeps_the_second_read_out() {
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'once.h'), '#pragma once\nint once;\n') or {}
	source := include_line('<once.h>') + include_line('<once.h>')
	result := preprocess(source, os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'once', ';']
}

fn test_a_file_that_includes_itself_stops_at_the_depth_limit() {
	// With no guard, a file that includes itself is a loop. The preprocessor
	// has to say so rather than find out how much memory the machine has.
	dir := fixture_directory()
	header := os.join_path(dir, 'loop.h')
	os.write_file(header, include_line('<loop.h>')) or {}
	result := preprocess(include_line('<loop.h>'), os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('${max_include_depth}')
}

fn test_an_include_in_a_branch_that_was_not_taken_is_not_read() {
	assert processed('#if 0\n' + include_line('<no-such-header-anywhere.h>') + '#endif\nint x;\n') == [
		'int',
		'x',
		';',
	]
}

fn test_an_include_is_not_read_from_the_conditional_it_skips() {
	// The follow-up to the test above: the file is read when the branch is
	// taken, so the only thing keeping the missing header out of the
	// diagnostics is the conditional.
	messages := diagnostics_of('#if 1\n' + include_line('<no-such-header-anywhere.h>') + '#endif\n')
	assert messages.len == 1
}

fn test_include_next_reads_the_copy_after_the_one_being_read() {
	// The shape the directive exists for: the same header installed in two
	// places, where the first copy hands the rest of its contents to the second
	// with one line. C says the search starts after the directory the file
	// being read was found in.
	dir := fixture_directory()
	first := os.join_path(dir, 'first')
	second := os.join_path(dir, 'second')
	os.mkdir_all(first) or {}
	os.mkdir_all(second) or {}
	handover := include_next_line('<chain.h>')
	os.write_file(os.join_path(first, 'chain.h'), '${handover}int first_copy;\n') or {}
	os.write_file(os.join_path(second, 'chain.h'), 'int second_copy;\n') or {}
	result := preprocess(include_line('<chain.h>'), os.join_path(dir, 'main.c'), Options{
		include_dirs: [first, second]
	})
	assert result.diagnostics.len == 0
	// The handover is an insertion, so the second copy's contents are read
	// where the line is and the first copy goes on after them.
	assert result.tokens.map(it.text) == ['int', 'second_copy', ';', 'int', 'first_copy', ';']
}

fn test_include_next_in_the_last_copy_is_diagnosed() {
	// The copy installed last has nothing after it, and C says that is an error
	// rather than a reason to start the search over.
	dir := fixture_directory()
	only := os.join_path(dir, 'only')
	os.mkdir_all(only) or {}
	os.write_file(os.join_path(only, 'chain.h'), include_next_line('<chain.h>')) or {}
	result := preprocess(include_line('<chain.h>'), os.join_path(dir, 'main.c'), Options{
		include_dirs: [only]
	})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('chain.h')
}

fn test_include_next_in_the_file_the_compiler_was_handed_searches_the_whole_list() {
	// The file the compiler was handed was not found in the list, so there is
	// no directory to start after and the whole list is searched.
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'plain.h'), 'int plain;\n') or {}
	result := preprocess(include_next_line('<plain.h>'), os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'plain', ';']
}

fn test_a_function_like_macro_parses_and_remembers_its_parameters() {
	assert processed('#define F(x) x\n') == []
	assert processed('#define F(x) x\nF(1)\n') == ['1']
	assert processed('#define ADD(a, b) a + b\nADD(1, 2)\n') == ['1', '+', '2']
}

fn test_arguments_are_expanded_before_they_are_put_in_place() {
	assert processed('#define N 7\n#define F(x) x + x\nF(N)\n') == ['7', '+', '7']
}

fn test_a_macro_can_be_called_inside_the_argument_of_another() {
	assert processed('#define twice(x) x + x\n#define N 2\ntwice(twice(N))\n') == ['2', '+', '2',
		'+', '2', '+', '2']
}

fn test_a_comma_inside_parentheses_is_part_of_the_argument() {
	assert processed('#define F(a, b) a b\nF((1, 2), 3)\n') == ['(', '1', ',', '2', ')', '3']
}

fn test_a_macro_name_with_no_parenthesis_is_not_a_call() {
	assert processed('#define F(x) x\nF\n') == ['F']
}

fn test_a_macro_that_calls_itself_stops() {
	assert processed('#define F(x) F(x)\nF(1)\n') == ['F', '(', '1', ')']
	assert processed('#define F(x) G(x)\n#define G(x) F(x)\nF(1)\n') == ['F', '(', '1', ')']
}

fn test_the_wrong_number_of_arguments_is_diagnosed() {
	messages := diagnostics_of('#define F(a, b) a b\nF(1)\n')
	assert messages.len == 1
	assert messages[0].contains('takes 2')
}

fn test_a_string_is_made_out_of_the_argument_as_it_was_written() {
	assert processed('#define S(x) #x\nS(hello world)\n') == ['"hello world"']
	assert processed('#define S(x) #x\nS(N)\n#define N 1\n') == ['"N"']
}

fn test_two_tokens_are_joined_into_one_by_a_double_hash() {
	assert processed('#define J(a, b) a ## b\nJ(x, y)\n') == ['xy']
	assert processed('#define J(a, b) a ## b\nJ(, y)\n') == ['y']
}

fn test_the_join_is_how_a_name_is_built_out_of_two_pieces() {
	assert processed('#define NAMED_gcc 1\n#define USE(f) NAMED_ ## f\nUSE(gcc)\n') == ['1']
}

fn test_the_arguments_after_the_named_ones_are_the_variadic_ones() {
	assert processed('#define V(fmt, ...) send(fmt, __VA_ARGS__)\nV("a", 1, 2)\n') == [
		'send',
		'(',
		'"a"',
		',',
		'1',
		',',
		'2',
		')',
	]
}

fn test_a_comma_that_is_only_there_when_there_are_arguments() {
	// gcc's `, ## __VA_ARGS__`: the comma goes when nothing follows it, and is
	// written out as it is when something does.
	assert processed('#define V(fmt, ...) send(fmt, ## __VA_ARGS__)\nV("a")\n') == [
		'send',
		'(',
		'"a"',
		')',
	]
	assert processed('#define V(fmt, ...) send(fmt, ## __VA_ARGS__)\nV("a", 1)\n') == [
		'send',
		'(',
		'"a"',
		',',
		'1',
		')',
	]
}

fn test_an_if_can_call_a_macro_that_takes_arguments() {
	assert processed('#define USE(x) x\n#if USE(1)\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#define LESS(a, b) a < b\n#if LESS(1, 2)\nint x;\n#endif\n') == [
		'int',
		'x',
		';',
	]
}

fn test_an_unknown_directive_is_diagnosed_with_its_name() {
	messages := diagnostics_of('#frobnicate\n')
	assert messages.len == 1
	assert messages[0].contains('frobnicate')
}

fn test_an_argument_is_expanded_even_when_it_names_the_macro_being_expanded() {
	// The inner F is a use of F that is not inside F's own replacement, so it is
	// replaced, and what tcc makes of this file is what this makes of it. That
	// comparison is made when the test runs: the answer that used to be written
	// here was tcc's answer, read once and recorded.
	source := '#define F(x) x\nF(F(1))\n'
	expected := tcc_tokens(source) or {
		eprintln('tcc is not on this machine, so the macro comparison is skipped')
		return
	}
	assert processed(source) == expected
}

fn test_macros_that_call_each_other_in_turns_stop() {
	// A name is left as it stands while that name is the one being expanded, and
	// by the time the outer call comes back around the inner ones are that name.
	// The comparison with tcc is made when the test runs, not recorded from a
	// reading of it.
	source := '#define A(x) B(x)\n#define B(x) A(x)\nA(A(A(1)))\n'
	expected := tcc_tokens(source) or {
		eprintln('tcc is not on this machine, so the mutual recursion comparison is skipped')
		return
	}
	assert processed(source) == expected
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

fn test_the_macros_that_describe_the_target_are_defined_before_anything_is_read() {
	// These are the macros a header asks what machine it is on. Without them
	// gcc's own headers fall back to their own guesses, which work but are
	// spelled differently, and a header that branches on a macro nobody
	// defined takes a path nobody tested.
	assert processed('#if __STDC__\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#ifdef __x86_64__\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('#ifdef __linux__\nint x;\n#endif\n') == ['int', 'x', ';']
	assert processed('__SIZE_TYPE__') == ['unsigned', 'long']
	assert processed('__STDC_VERSION__') == ['199901L']
}

fn test_a_command_line_define_wins_over_a_builtin_one() {
	result := preprocess('__SIZE_TYPE__', 'test.c', Options{
		defines: ['__SIZE_TYPE__=int']
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int']
}

fn test_an_undefine_takes_a_builtin_away() {
	assert processed('#undef __STDC__\n#ifdef __STDC__\nint x;\n#endif\n') == []
}

fn test_the_line_and_the_file_are_where_they_were_written() {
	assert processed('\n\n__LINE__') == ['3']
	assert processed('__FILE__') == ['"test.c"']
	assert processed('#define HERE __LINE__\nHERE\nHERE\n') == ['2', '3']
}

fn test_a_header_can_ask_about_a_construct_and_be_told_no() {
	assert processed('#if __has_attribute(__nothrow__)\nint x;\n#endif\n') == []
	assert processed('#ifdef __has_attribute\nint x;\n#endif\n') == ['int', 'x', ';']
}

fn test_line_renumbers_the_lines_that_follow_it() {
	// The number is the number of the line after the directive, so __LINE__ on
	// the next line is that number and a blank line after it is one more.
	assert processed('${hash}line 100\n__LINE__\n') == ['100']
	assert processed('${hash}line 100\n\n__LINE__\n') == ['101']
	// Two of them: the second counts from where the first left the file.
	assert processed('${hash}line 100\n\n${hash}line 5\n__LINE__\n') == ['5']
}

fn test_line_renames_the_file_and_the_line_a_diagnostic_points_at() {
	result := preprocess('${hash}line 42 "generated.c"\n${hash}error here\n', 'test.c', Options{})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].file == 'generated.c'
	assert result.diagnostics[0].line == 42
	assert result.diagnostics[0].msg.contains('here')
}

fn test_line_reports_the_name_it_was_given() {
	result := preprocess('${hash}line 7 "generated.c"\n__FILE__\n', 'test.c', Options{})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['"generated.c"']
}

fn test_line_without_a_number_or_a_name_is_diagnosed() {
	assert diagnostics_of('${hash}line\n').len == 1
	assert diagnostics_of('${hash}line 0\n').len == 1
	assert diagnostics_of('${hash}line 3 nope.c\n').len == 1
}

fn test_counter_counts_the_uses() {
	// It is for a name that has to be different each time a header is read, so
	// the first use is 0 and every use after it is one more.
	assert processed('__COUNTER__ __COUNTER__ __COUNTER__') == ['0', '1', '2']
}

fn test_include_level_is_how_deep_the_read_is() {
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'level.h'), '__INCLUDE_LEVEL__\n') or {}
	source := '__INCLUDE_LEVEL__\n' + include_line('<level.h>')
	result := preprocess(source, os.join_path(dir, 'main.c'), Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['0', '1']
}

fn test_the_clock_macros_are_written_the_way_c_writes_them() {
	// The clock cannot be held still in a test, so what is held onto is the
	// shape: three letters, a two-character day, four digits, and a time.
	date := processed('__DATE__')[0]
	stamp := processed('__TIMESTAMP__')[0]
	clock := processed('__TIME__')[0]
	assert date.len == 13
	assert date[1..4] in ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
		'Nov', 'Dec']
	assert clock.len == 10
	assert clock[3] == `:` && clock[6] == `:`
	assert stamp.len == 26
}

fn test_the_day_in_a_date_is_padded_with_a_space_the_way_c_pads_it() {
	// C writes the day as two characters whether or not it needs both, and pads
	// with a space rather than a zero. The clock is not held still here, but the
	// one-digit case is: this timestamp is a single-digit day in every time zone
	// there is, so what the test is about is the padding and not the date.
	//
	// The shape is "Mmm dd yyyy", so the day's two characters are at 5 and 6:
	// a space and then the digit, where a formatter would have written 0 and 3.
	midday := date_text(time.unix(1699012800))
	assert midday.len == 13
	assert midday[5] == ` `
	assert midday[6] >= `1` && midday[6] <= `9`
}

fn test_a_pragma_written_by_a_macro_is_read_and_left_out() {
	// `_Pragma("...")` is a pragma a macro can write, which is why it has to be
	// an operator: by the time the tokens exist the line has been left behind.
	// This compiler has nothing to say about the pragmas it does not know, so
	// the operator is consumed and nothing is written for it — which is what
	// keeps a declaration a declaration.
	assert processed('#define P _Pragma("GCC diagnostic push")\nP\nint x;\n') == ['int', 'x', ';']
	// Anything else after the name is not the operator, and the name is a name.
	assert processed('int _Pragma;\n') == ['int', '_Pragma', ';']
}

fn test_a_warning_is_reported_and_the_read_goes_on() {
	// A warning is a program saying something about itself — a header being
	// read in a configuration it was not written for says it this way. The
	// program is not wrong, so the compile it is part of does not stop.
	result := preprocess('${hash}warning this build has no such feature\nint x;\n', 'test.c',
		Options{})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].warning
	assert result.diagnostics[0].msg.contains('no such feature')
	assert result.tokens.map(it.text) == ['int', 'x', ';']
}

fn test_an_undef_read_takes_the_builtins_away() {
	// -undef is the command line saying it will describe the target itself.
	// The macro that is left undefined stays a name the program can use, which
	// is what a header sees when it asks a compiler that knows nothing.
	assert processed('__STDC__') == ['1']
	result := preprocess('__STDC__', 'test.c', Options{
		undef_builtins: true
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['__STDC__']
}

fn test_a_prelude_file_is_read_before_the_source() {
	dir := fixture_directory()
	prelude := os.join_path(dir, 'pre.h')
	os.write_file(prelude, '#define N 7\nint from_prelude;\n') or { panic(err) }
	result := preprocess('int x = N;', os.join_path(dir, 'main.c'), Options{
		preludes: [
			Prelude{
				path: prelude
			},
		]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'from_prelude', ';', 'int', 'x', '=', '7', ';']
}

fn test_a_macros_only_prelude_leaves_its_text_out() {
	dir := fixture_directory()
	prelude := os.join_path(dir, 'macros.h')
	os.write_file(prelude, '#define M 9\nint from_macros;\n') or { panic(err) }
	result := preprocess('int x = M;', os.join_path(dir, 'main.c'), Options{
		preludes: [
			Prelude{
				path:        prelude
				macros_only: true
			},
		]
	})
	assert result.diagnostics.len == 0
	// The name it defined is defined, and the declaration it held is not in the
	// stream: that is the whole difference between the two flags.
	assert result.tokens.map(it.text) == ['int', 'x', '=', '9', ';']
}

fn test_a_prelude_that_cannot_be_found_is_diagnosed() {
	result := preprocess('int x;', 'test.c', Options{
		preludes: [
			Prelude{
				path: 'no-such-prelude.h'
			},
		]
	})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'cannot find no-such-prelude.h to read before the source'
}

fn test_the_files_the_read_opened_are_reported_in_order() {
	// What a build tool's rule for a file is made of: the file itself first,
	// then each header where it was first read, once, with whether it came from
	// the standard directories.
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'inner.h'), 'int inner;\n') or { panic(err) }
	os.write_file(os.join_path(dir, 'outer.h'), 'int outer;\n' + include_line('"inner.h"')) or {
		panic(err)
	}
	main_path := os.join_path(dir, 'main.c')
	source := 'int before;\n' + include_line('"outer.h"') + 'int after;\n'
	os.write_file(main_path, source) or { panic(err) }
	result := preprocess(source, main_path, Options{
		include_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.files.map(it.path) == [main_path, os.join_path(dir, 'outer.h'),
		os.join_path(dir, 'inner.h')]
	assert result.files.map(it.system) == [false, false, false]
}

fn test_has_include_asks_whether_a_header_is_there() {
	// The question is answered with the search the include does, from the file
	// that asks, and the file the name points at is not read.
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'there.h'), 'int there;\n') or { panic(err) }
	result := preprocess('#if __has_include("there.h")\nint found;\n#else\nint missing;\n#endif\n',
		os.join_path(dir, 'main.c'), Options{})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'found', ';']
	assert processed('#if __has_include("nowhere.h")\nint found;\n#else\nint missing;\n#endif\n') == [
		'int',
		'missing',
		';',
	]
}

fn test_has_include_reads_the_name_between_the_brackets() {
	// The contents of <...> are the name of the file and not an expression:
	// `nested/angled.h` arrives from the lexer as five tokens.
	dir := fixture_directory()
	os.mkdir_all(os.join_path(dir, 'nested')) or { panic(err) }
	os.write_file(os.join_path(dir, 'nested', 'angled.h'), 'int there;\n') or { panic(err) }
	result := preprocess('#if __has_include(<nested/angled.h>)\nint found;\n#endif\n', 'test.c', Options{
		standard_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['int', 'found', ';']
}

fn test_what_this_compiler_can_be_told_is_answered_with_no() {
	// No attributes are honored and no extensions are offered, so the honest
	// answer is the one that sends a header down the path it wrote for a
	// compiler like this one.
	assert processed('#if __has_attribute(packed)\nint yes;\n#else\nint no;\n#endif\n') == [
		'int',
		'no',
		';',
	]
	assert processed('#if __has_builtin(__builtin_trap)\nint yes;\n#else\nint no;\n#endif\n') == [
		'int',
		'no',
		';',
	]
}

fn test_a_program_that_defines_one_of_the_names_for_itself_is_asked_first() {
	assert processed('#define __has_attribute(x) 1\n#if __has_attribute(packed)\nint yes;\n#endif\n') == [
		'int',
		'yes',
		';',
	]
}

fn test_a_has_include_with_no_closing_bracket_is_diagnosed() {
	result := preprocess('#if __has_include(<stdio.h>\nint x;\n#endif\n', 'test.c', Options{})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == '__has_include( has no closing )'
}

fn test_a_has_include_with_nothing_in_it_is_diagnosed() {
	result := preprocess('#if __has_include()\nint x;\n#endif\n', 'test.c', Options{})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == '__has_include( wants a "file" or a <file>'
}

fn test_a_macro_that_takes_no_arguments_still_takes_arguments() {
	// `#define C() nothing` is a macro that has to be called: `C(1)` is a
	// mistake to report, and not a name to expand with a bracket left standing
	// after it — which is what an object-like reading of it would do.
	assert processed('#define C() nothing\nC()\n') == ['nothing']
	result := preprocess('#define C() nothing\nC(1)\n', 'test.c', Options{})
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'C takes 0 arguments and 1 was given'
}

fn test_a_bracket_on_the_next_line_is_not_a_parameter_list() {
	// What tells the two shapes apart is the bracket being against the name:
	// `#define F (x) x` is an object-like macro whose body is `(x) x`.
	assert processed('#define F (x) x\nF\n') == ['(', 'x', ')', 'x']
	assert processed('#define F (x) x\nF(3)\n') == ['(', 'x', ')', 'x', '(', '3', ')']
}

fn test_a_define_on_the_command_line_can_take_arguments() {
	result := preprocess('F(3)', 'test.c', Options{
		defines: ['F(x)=((x)+1)']
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['(', '(', '3', ')', '+', '1', ')']
	// And the name on its own is still not a use of it: a macro that takes
	// arguments is only one where it is called.
	alone := preprocess('F', 'test.c', Options{
		defines: ['F(x)=((x)+1)']
	})
	assert alone.diagnostics.len == 0
	assert alone.tokens.map(it.text) == ['F']
}

// tcc_tokens is what tcc prints for a file with `-E`, read back as the text of
// each token. The line markers tcc writes are not part of the program, and the
// tokens are read with this compiler's lexer, so what is compared is two
// preprocessors and not this one with a note about itself. A machine without
// tcc returns none, and the test that called this says so rather than passing
// quietly.
fn tcc_tokens(source string) ?[]string {
	dir := fixture_directory()
	file := os.join_path(dir, 'oracle-fixture.c')
	os.write_file(file, source) or { return none }
	result := os.execute('tcc -E ${os.quoted_path(file)} 2>/dev/null')
	if result.exit_code != 0 {
		return none
	}
	mut out := []string{}
	for line in result.output.split_into_lines() {
		if line.trim_space().starts_with('#') {
			continue
		}
		for tok in tokenize.lex(line).tokens {
			if tok.kind != .eof {
				out << tok.text
			}
		}
	}
	return out
}

// Phase 6 is over the token stream, and these are its tests: what the parser is
// handed is one literal where the program wrote two, and never a value the
// program did not write.

fn test_two_adjacent_string_literals_are_one_literal() {
	assert processed('char s[] = "a" "b";') == ['char', 's', '[', ']', '=', '"ab"', ';']
	// Three in a row, and an empty one in the middle: the join is over the text
	// between the quotes, whatever it is.
	assert processed('char s[] = "a" "b" "c";') == ['char', 's', '[', ']', '=', '"abc"', ';']
	assert processed('char s[] = "" "ab";') == ['char', 's', '[', ']', '=', '"ab"', ';']
	// A literal a macro produced is adjacent to the one written beside it: the
	// join is over the stream phase 4 left behind.
	assert processed('#define S "a"\nchar s[] = S "b";') == ['char', 's', '[', ']', '=', '"ab"',
		';']
	// A token between two literals is a token between two literals.
	assert processed('char s[] = "a" + "b";') == ['char', 's', '[', ']', '=', '"a"', '+', '"b"',
		';']
}

fn test_the_joined_literal_is_the_literal_the_same_text_alone_would_be() {
	// The invariant the join has to have, and one a test can fail on: the quotes
	// are dropped once, no character of either half is lost, and the two halves
	// are in the order they were written.
	assert processed('char s[] = "a" "b";') == processed('char s[] = "ab";')
	assert processed('char s[] = "x" "" "y";') == processed('char s[] = "xy";')
	assert processed('char s[] = L"a" L"b";') == processed('char s[] = L"ab";')
}

fn test_a_wide_and_a_narrow_literal_join_into_a_wide_one() {
	// C99 6.4.5p4: a run of adjacent narrow and wide string literals is
	// concatenated, and the result is wide if any of them was wide. gcc agrees,
	// and the measurement is the one that says what "wide" is here:
	// `sizeof(L"a" "b")` is 12, which is three wide characters.
	assert processed('char s[] = L"a" "b";') == ['char', 's', '[', ']', '=', 'L"ab"', ';']
	assert processed('char s[] = "a" L"b";') == ['char', 's', '[', ']', '=', 'L"ab"', ';']
}

fn test_adjacency_is_the_token_stream_and_not_a_line() {
	// A header read between two literals is not between them either, because
	// what phase 6 sees is the tokens phase 4 left. gcc is the same: `char a[] =
	// "a"` with a header holding `"b"` and a `;` after it is three bytes
	// (measured).
	dir := fixture_directory()
	os.write_file(os.join_path(dir, 'adjacent.h'), '"b"\n') or { return }
	source := 'char s[] = "a"\n${include_line('"adjacent.h"')};\n'
	result := preprocess(source, os.join_path(dir, 'main.c'), Options{
		include_dirs: [dir]
	})
	assert result.diagnostics.len == 0
	assert result.tokens.map(it.text) == ['char', 's', '[', ']', '=', '"ab"', ';']
}

fn test_an_escape_belongs_to_the_literal_it_was_written_in() {
	// Each literal's escapes are interpreted before the literals are joined,
	// which is what gcc does: `sizeof("\1" "2")` is three bytes and the first of
	// them is 1, and `sizeof("\x41" "b")` is three whose first byte is 65 and
	// second is 98. Joined as spellings they would be `"\12"` and `"\x41b"`,
	// and `"\x41b"` is one byte of value 27 with a warning from gcc about a hex
	// escape out of range, which is a value the program did not write. So that
	// join is not made and the diagnostic names both literals.
	assert processed('char s[] = "\\101" "b";') == ['char', 's', '[', ']', '=', '"\\101b"', ';']
	assert processed('char s[] = "a" "\\nb";') == ['char', 's', '[', ']', '=', '"a\\nb"', ';']
	by_hex := diagnostics_of('char s[] = "\\x41" "b";')
	assert by_hex.len == 1
	assert by_hex[0].contains('"\\x41"')
	assert by_hex[0].contains('"b"')
	by_octal := diagnostics_of('char s[] = "\\1" "2";')
	assert by_octal.len == 1
	assert by_octal[0].contains('"\\1"')
	assert by_octal[0].contains('"2"')
}

fn test_a_pair_of_literals_c99_has_no_rule_for_is_named() {
	// `u8`, `u` and `U` are not C99's — in C99 mode there is no such literal at
	// all — and under `-std=c11` the message `unsupported non-standard
	// concatenation of string literals` is what gcc refuses by *name*, and it
	// refuses only a pair of two different prefixes with it; it accepts the
	// narrow-and-`u8` pair, and concatenates `"a" u"b"` into the prefixed type.
	// This compiler has no C11 literal of those types and no place for the
	// result, so it refuses every pair whose two sides are not two narrow-or-wide
	// literals by name rather than joining them into a type the program did not
	// ask for; joining the `u8` pair is C11 work.
	narrow_and_u8 := diagnostics_of('char s[] = "a" u8"b";')
	assert narrow_and_u8.len == 1
	assert narrow_and_u8[0].contains('narrow string literal')
	assert narrow_and_u8[0].contains('u8 string literal')
	wide_and_u := diagnostics_of('char s[] = L"a" u"b";')
	assert wide_and_u.len == 1
	assert wide_and_u[0].contains('wide string literal')
	// Two of the same kind are one literal, which is what C11 says of them and
	// harmless here: the literal reader refuses the type itself, by name.
	assert processed('char s[] = u8"a" u8"b";') == ['char', 's', '[', ']', '=', 'u8"ab"', ';']
}

fn test_phase_one_is_gated_by_the_dialect_the_command_line_chose() {
	// The mode reaches the lexer through the preprocessor, which is the wiring
	// main.v does, and `standard.replaces_trigraphs` is the answer it is asked
	// for. Finding C1-r1-1, with gcc 16.2.1 as the oracle, measured one mode at
	// a time over `int main(void) { return 0 ??!??! 0; }`: the strict ISO modes
	// up to C17 replace (rc 0, and the line is `0 || 0`), while a GNU dialect,
	// C23 and no `-std` at all leave the bytes alone (rc 1,
	// `trigraph '??!' ignored, use '-trigraphs' to enable`). `-std=nonsense` is
	// recorded and refused nothing, so it takes the default dialect's answer,
	// which is gnu-like.
	assert processed_in('int x = 0 ??! 1;', .c99) == ['int', 'x', '=', '0', '|', '1', ';']
	assert processed_in('int x = 0 ??! 1;', .c11) == ['int', 'x', '=', '0', '|', '1', ';']
	for mode in [standard.Mode.none, .other, .c23, .gnu89, .gnu99, .gnu11, .gnu17, .gnu23] {
		assert processed_in('int x = 0 ??! 1;', mode) == ['int', 'x', '=', '0', '?', '?', '!',
			'1', ';']
	}
	// A string literal is where a program would feel it: `"??!"` is one byte
	// under `-std=c99` and the three bytes it wrote everywhere else.
	assert processed_in('char *s = "??!";', .c99) == ['char', '*', 's', '=', '"|"', ';']
	assert processed_in('char *s = "??!";', .gnu99) == ['char', '*', 's', '=', '"??!"', ';']
}

fn test_a_digraph_is_the_punctuator_it_names() {
	// The six C99 spellings on the path a program takes: `%:` opens a directive
	// the same way `#` does, `%:%:` pastes in a macro body, and the brackets and
	// braces are the punctuators they name. Measured on gcc 16.2.1 with
	// `gcc -std=c99 -E`: the definitions produce no output and the use line prints
	// `int dg_var_3 = (3) * 2;`, so the paste happened. gcc writes `int y<:2:>;`
	// back as it was spelled, which is its output's spelling rather than its
	// tokens; what this compiler hands over is tokens, and the `[` is a `[`.
	source := '%:define A 41\n%:define PASTE(a, b) a %:%: b\n%:define X(n) int PASTE(dg_var_, n) = (n) * 2\nX(3);\nint y<:2:>;\n'
	assert processed_in(source, .c99) == ['int', 'dg_var_3', '=', '(', '3', ')', '*', '2', ';',
		'int', 'y', '[', '2', ']', ';']
}

fn test_c89_is_the_one_mode_without_the_digraph_spellings() {
	// Under the mode they arrived after, `%:define` is a percent and a colon, so
	// it is not a directive and the line reaches the parser as it stands. gcc
	// 16.2.1 refuses the same file at 1:1 with `error: expected identifier or
	// '('`, which is what reading it that way costs.
	assert processed_in('%:define A 41\n', .c89) == ['%', ':', 'define', 'A', '41']
	// Every other mode reads it as a definition, gnu89 included, which is what
	// gcc does with a feature its own strict mode of the same standard lacks.
	assert processed_in('%:define A 41\nA\n', .gnu89) == ['41']
	assert processed_in('%:define A 41\nA\n', .none) == ['41']
}

fn test_a_character_constant_may_name_its_encoding_in_an_if() {
	// C99 6.4.4.4 lets a character constant say which encoding it holds, and what the #if
	// evaluator wants is the value, which the prefix does not change. This is not a
	// corner: glibc's <bits/wchar.h> asks `#elif L'\0' - 1 > 0` to choose between the
	// limits of a signed and an unsigned wchar_t, so an evaluator that could not read the
	// prefix could not read <wchar.h> at all.
	assert processed("${hash}if L'a' == 97\nint a;\n${hash}endif\n") == ['int', 'a', ';']
	assert processed("${hash}if u'a' == 97\nint a;\n${hash}endif\n") == ['int', 'a', ';']
	assert processed("${hash}if U'a' == 97\nint a;\n${hash}endif\n") == ['int', 'a', ';']
	// The prefix is not read as part of the value, which is the claim the header's
	// branch turns on: `L'\0'` has to be zero for the chain to pick the other arm.
	chained := "${hash}if L'\\0' - 1 > 0\nint a;\n${hash}elif L'\\0' + 0 == 0\nint b;\n${hash}endif\n"
	assert processed(chained) == ['int', 'b', ';']
}

fn test_a_diagnostic_about_an_if_names_where_the_construct_is() {
	// The expression is the rest of the directive's line, so a construct in it is at the
	// line and column it holds in the file, and not at line 1 column 1 of a copy of part
	// of one line. gcc reports these same two numbers for the same file.
	first := preprocess('int x;\n${hash}if "a" == 1\nint a;\n${hash}endif\n', 'test.c', Options{})
	assert first.diagnostics.len == 1
	assert first.diagnostics[0].line == 2
	assert first.diagnostics[0].col == 5
	// The column tracks the construct whatever the directive is indented by, because it
	// is computed from where the expression starts in the line and not from the
	// expression alone.
	indented := preprocess('int x;\n    ${hash}if "a" == 1\nint a;\n${hash}endif\n', 'test.c', Options{})
	assert indented.diagnostics.len == 1
	assert indented.diagnostics[0].line == 2
	assert indented.diagnostics[0].col == 9
}

fn test_a_gnu_dialect_claims_a_gnu_compiler() {
	// glibc's __GNUC_PREREQ is `(__GNUC__ << 16) + __GNUC_MINOR__ >= ...`, so a
	// dialect that claims to be a GNU compiler has to give both of those names, and
	// not just the first. <tgmath.h> and the 132 other headers under /usr/include
	// that ask about __GNUC__ read them; without them <tgmath.h> is an #error, and
	// with a claim below 4.3 it is a different #error.
	gnu := standard_defines(.gnu99, .none)
	assert '__GNUC__=4' in gnu
	assert '__GNUC_MINOR__=3' in gnu
	assert '__GNUC_PATCHLEVEL__=1' in gnu
	// The claim belongs to the spelling, so every GNU spelling has it and the ISO
	// ones and the unrecognized ones do not. The second argument is the emulation,
	// and what naming one does to this claim is the next test's subject.
	assert standard_defines(.gnu11, .none).len == 3
	assert standard_defines(.gnu23, .none).len == 3
	assert standard_defines(.c89, .none) == []
	assert standard_defines(.c11, .none) == []
	assert standard_defines(.other, .none) == []
	// c99 is the mode that also hides what the standard does not have.
	assert standard_defines(.c99, .none) == ['__STRICT_ANSI__=1']
}
