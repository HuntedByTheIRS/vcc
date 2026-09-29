module tokenize

// The fields a token carries that no single-file stage can fill in.

fn test_a_token_does_not_name_a_file_until_a_stage_that_follows_one() {
	// The lexer reads one file and does not know where it came from; naming it
	// is the preprocessor's job, because that is the stage with more than one
	// file open.
	assert lex('int x;').tokens[0].file == ''
}

fn test_a_diagnostic_carries_an_empty_file_by_default() {
	// Same rule for a diagnostic: the caller that knows the path is the one that
	// prints it, and the field is only for a location inside an include.
	diagnostics := lex('int x = 1 @ 2;').diagnostics
	assert diagnostics.len == 1
	assert diagnostics[0].file == ''
}

fn test_errors_leaves_the_warnings_out() {
	// What stops a compile is an error. A stage that hands back a warning has
	// not failed, and a count of the diagnostics cannot tell the two apart.
	diagnostics := [
		Diagnostic{
			line: 1
			col:  1
			msg:  'an error'
		},
		Diagnostic{
			line:    2
			col:     1
			msg:     'a warning'
			warning: true
		},
	]
	assert errors(diagnostics).len == 1
	assert errors(diagnostics)[0].msg == 'an error'
	assert errors([]Diagnostic{}).len == 0
}
