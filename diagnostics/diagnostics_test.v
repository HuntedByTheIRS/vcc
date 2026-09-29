module diagnostics

fn test_a_warning_carries_a_label_and_an_error_does_not() {
	assert render('a.c', 1, 2, .warning, 'something noticed') == 'a.c:1:2: warning: something noticed'
	assert render('a.c', 1, 2, .error, 'something wrong') == 'a.c:1:2: something wrong'
}

fn test_the_class_a_name_names() {
	pedantic := class_of('pedantic') or { panic('pedantic is a class') }
	cpp := class_of('cpp') or { panic('cpp is a class') }
	assert pedantic == .pedantic
	assert cpp == .cpp
	if _ := class_of('implicit-function-declaration') {
		assert false, 'a name the compiler does not classify is not a class'
	}
}

fn test_pedantic_is_silent_until_it_is_asked_for() {
	mut policy := Policy{}
	assert policy.severity(.pedantic) == .silent
	// The class the compiler reports on its own account stays reported.
	assert policy.severity(.cpp) == .warning
	assert policy.accept('-Wpedantic')
	assert policy.severity(.pedantic) == .warning
}

fn test_the_last_mention_of_a_class_wins() {
	mut off_last := Policy{}
	assert off_last.accept('-Wpedantic')
	assert off_last.accept('-Wno-pedantic')
	assert off_last.severity(.pedantic) == .silent

	mut on_last := Policy{}
	assert on_last.accept('-Wno-pedantic')
	assert on_last.accept('-Wpedantic')
	assert on_last.severity(.pedantic) == .warning
}

fn test_pedantic_is_the_same_flag_as_wpedantic() {
	mut policy := Policy{}
	assert policy.accept('-pedantic')
	assert policy.severity(.pedantic) == .warning
}

fn test_pedantic_errors_is_the_promotion_werror_names() {
	mut promoted := Policy{}
	assert promoted.accept('-pedantic-errors')
	assert promoted.severity(.pedantic) == .error

	mut named := Policy{}
	assert named.accept('-Werror=pedantic')
	assert named.severity(.pedantic) == .error

	// -pedantic-errors asks for the diagnostic and makes it an error, so a
	// -Wno-pedantic after it takes the diagnostic away altogether.
	promoted.accept('-Wno-pedantic')
	assert promoted.severity(.pedantic) == .silent
}

fn test_w_silences_whichever_side_of_a_mention_it_is_written_on() {
	orders := [
		['-w', '-Wpedantic'],
		['-Wpedantic', '-w'],
		['-w', '-pedantic-errors'],
		['-pedantic-errors', '-w'],
		['-pedantic', '-w', '-pedantic-errors'],
	]
	for order in orders {
		mut policy := Policy{}
		for flag in order {
			assert policy.accept(flag)
		}
		assert policy.severity(.pedantic) == .silent
		assert policy.severity(.cpp) == .silent
	}
}

fn test_a_flag_about_something_else_is_left_to_the_command_line() {
	mut policy := Policy{}
	assert !policy.accept('-Wl,-rpath,/opt/v')
	assert !policy.accept('-Werror=implicit-function-declaration')
	assert !policy.accept('-Wno-unknown-warning')
	assert !policy.accept('-Wall')
	assert !policy.accept('-Werror')
	assert !policy.accept('-O2')
	assert policy.mentions.len == 0
	assert !policy.suppress
}
