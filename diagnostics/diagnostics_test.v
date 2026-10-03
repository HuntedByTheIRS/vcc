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

fn test_a_run_that_only_reads_is_not_stopped_by_a_promotion() {
	mut promoted := Policy{}
	assert promoted.accept('-pedantic-errors')
	assert promoted.severity(.pedantic) == .error
	reading := promoted.without_promotion()
	assert reading.severity(.pedantic) == .warning
	// Everything else is what it was: the class the compiler reports on its own
	// account is a warning either way, and a class nobody asked about stays
	// silent.
	assert reading.severity(.cpp) == .warning
	mut plain := Policy{}
	assert plain.without_promotion().severity(.pedantic) == .silent
	// A diagnostic the command line silenced stays silenced, and -w keeps its
	// hold whatever the order was.
	mut silenced := Policy{}
	assert silenced.accept('-pedantic-errors')
	assert silenced.accept('-Wno-pedantic')
	quiet := silenced.without_promotion()
	assert quiet.severity(.pedantic) == .silent
	mut suppressed := Policy{}
	assert suppressed.accept('-w')
	assert suppressed.accept('-pedantic-errors')
	held := suppressed.without_promotion()
	assert held.severity(.pedantic) == .silent
	assert held.severity(.cpp) == .silent
	// -Werror=pedantic is the same promotion under its other name.
	mut named := Policy{}
	assert named.accept('-Werror=pedantic')
	assert named.severity(.pedantic) == .error
	assert named.without_promotion().severity(.pedantic) == .warning
}

fn test_the_class_the_standard_requires_is_reported_and_then_promoted() {
	mut plain := Policy{}
	// gcc reports this one without being asked, which is the whole of what
	// separates it from the pedantic class.
	assert plain.severity(.required) == .warning

	// Nothing names it, so a flag naming it is left to the command line rather
	// than taken as a mention: gcc has no -W spelling for the class either,
	// which is why -Wno-pedantic does not silence it.
	mut unnamed := Policy{}
	assert !unnamed.accept('-Wrequired')
	assert unnamed.mentions.len == 0
	assert unnamed.severity(.required) == .warning

	mut after_pedantic_off := Policy{}
	assert after_pedantic_off.accept('-Wno-pedantic')
	assert after_pedantic_off.severity(.required) == .warning

	// -pedantic-errors is what promotes it, measured on gcc 16.2.1.
	mut promoted := Policy{}
	assert promoted.accept('-pedantic-errors')
	assert promoted.severity(.required) == .error
	assert promoted.severity(.pedantic) == .error

	mut suppressed := Policy{}
	assert suppressed.accept('-w')
	assert suppressed.severity(.required) == .silent

	// A run that only reads keeps the message and takes the verdict back.
	mut reading := Policy{}
	assert reading.accept('-pedantic-errors')
	assert reading.without_promotion().severity(.required) == .warning
}
