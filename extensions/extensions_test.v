module extensions

import cli

// flags reads a list of arguments that are the extension flags, which is what a
// caller holding only those flags has. Every one of them has to be accepted:
// the point of the helper is that a flag which is not an extension flag is a
// mistake in the test and not a silent pass.
fn flags(args []string) Options {
	mut o := Options{}
	for arg in args {
		accepted := o.accept(arg) or { panic(err) }
		assert accepted, '${arg} is not an extension flag'
	}
	return o
}

fn test_the_registry_has_one_row_per_name() {
	assert registry.len > 0
	mut seen := []string{}
	for row in registry {
		assert row.name != ''
		assert row.brings != ''
		assert !seen.contains(row.name), '${row.name} is in the registry twice'
		seen << row.name
	}
}

fn test_nothing_is_honored_yet() {
	// The whole of what this milestone is allowed to do with an extension: name
	// it. A row that is honored is a row that changes what compiles, and there
	// is no such row.
	for row in registry {
		assert !row.honored
	}
}

fn test_every_extension_is_off_until_it_is_named() {
	o := flags([])
	for row in registry {
		assert !o.enabled(row.name)
	}
	assert o.enabled_names() == []
}

fn test_a_list_of_names_is_accepted() {
	o := flags(['-fvcc-exts=auto,typeof'])
	assert o.enabled('auto')
	assert o.enabled('typeof')
	assert !o.enabled('generic')
	assert o.enabled_names() == ['auto', 'typeof']
}

fn test_all_names_every_extension() {
	o := flags(['-fvcc-exts=all'])
	assert o.enabled_names() == registry.map(it.name)
}

fn test_the_last_mention_of_a_name_wins() {
	off := flags(['-fvcc-exts=auto', '-fno-vcc-exts=auto'])
	assert !off.enabled('auto')
	on := flags(['-fno-vcc-exts=auto', '-fvcc-exts=auto'])
	assert on.enabled('auto')
}

fn test_all_then_off_leaves_the_others_on() {
	// The one clause of the flag that is worth writing down: `all` is the
	// registry, so turning one name off afterwards takes nothing else with it.
	o := flags(['-fvcc-exts=all', '-fno-vcc-exts=x'])
	assert !o.enabled('x')
	for row in registry {
		assert o.enabled(row.name)
	}
}

fn test_all_in_the_other_direction_turns_everything_off() {
	on := flags(['-fvcc-exts=all'])
	assert on.enabled_names() == registry.map(it.name)
	off := flags(['-fvcc-exts=all', '-fno-vcc-exts=all'])
	assert off.enabled_names() == []
}

fn test_naming_something_this_compiler_does_not_have_is_refused() {
	mut o := Options{}
	if _ := o.accept('-fvcc-exts=aotu') {
		assert false, 'a name this compiler does not have is not accepted'
	} else {
		assert err.msg().contains('aotu')
		assert err.msg().contains('none')
		for row in registry {
			assert err.msg().contains(row.name)
		}
	}
}

fn test_turning_off_something_this_compiler_does_not_have_is_accepted() {
	// A build that says -fno-vcc-exts=NAME about a compiler without that name
	// gets what it asked for, which is that the name is off. Refusing it would
	// fail a build over a flag about a feature this compiler never had.
	mut o := Options{}
	assert o.accept('-fno-vcc-exts=x')!
	assert !o.enabled('x')
	assert o.recorded == ['-fno-vcc-exts=x']
}

fn test_a_flag_with_nothing_in_it_is_refused() {
	mut missing := Options{}
	if _ := missing.accept('-fvcc-exts=') {
		assert false, 'a flag with no names is not accepted'
	} else {
		assert err.msg().contains('-fvcc-exts=')
	}
	mut comma := Options{}
	if _ := comma.accept('-fvcc-exts=auto,,typeof') {
		assert false, 'an empty name in a list is not accepted'
	} else {
		assert err.msg().contains('empty')
	}
}

fn test_a_flag_that_is_not_ours_is_left_to_the_command_line() {
	mut o := Options{}
	others := ['-fno-builtin', '-Wpedantic', '-fwrapv', '-fvcc-exts', '-fno-vcc-exts']
	for arg in others {
		assert o.accept(arg)! == false, '${arg} is not an extension flag'
	}
	assert o.recorded.len == 0
	assert o.mentions.len == 0
}

fn test_the_flags_are_recorded_as_they_were_written() {
	o := flags(['-fvcc-exts=auto', '-fno-vcc-exts=auto'])
	assert o.recorded == ['-fvcc-exts=auto', '-fno-vcc-exts=auto']
}

// The command line is where the two halves of the flag family have to add up:
// `cli/` reads the spellings and this module looks the names up, so the check
// starts from a real argument list with other flags around it.
fn test_the_command_line_parses_the_flag_family() {
	opts := cli.parse(['-std=c99', '-fvcc-exts=all', '-fno-vcc-exts=x', 'src.c', '-o', 'out'])!
	assert opts.inputs == ['src.c']
	assert !opts.vcc_extensions.enabled('x')
	for row in registry {
		assert opts.vcc_extensions.enabled(row.name)
	}
	assert opts.vcc_extensions.enabled_names() == registry.map(it.name)
	// Read and acted on, so not in the list of flags that were passed over.
	assert !opts.ignored.contains('-fvcc-exts=all')
	assert !opts.ignored.contains('-fno-vcc-exts=x')
}

fn test_the_command_line_refuses_a_name_it_does_not_have() {
	if _ := cli.parse(['-fvcc-exts=aotu', 'src.c']) {
		assert false, 'a name this compiler does not have is not accepted'
	} else {
		assert err.msg().contains('aotu')
	}
}
