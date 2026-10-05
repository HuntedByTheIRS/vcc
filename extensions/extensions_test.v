module extensions

import cli
import standard

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

fn test_the_names_are_one_per_extension() {
	// There is no list here to keep in step with the table: the names are the
	// extension column of standard's feature rows, and the table cannot name
	// one extension twice.
	offered := names()
	assert offered.len > 0
	mut seen := []string{}
	for name in offered {
		assert name != ''
		assert brings(name) != '', '${name} names no construct the table describes'
		assert !seen.contains(name), '${name} is in the table twice'
		seen << name
	}
}

// The two directions the two modules have to agree in, which is the check the
// string comparison never had: every name the flag offers comes from a row, and
// every row that names an extension names one the flag offers.
fn test_every_name_comes_from_a_row_and_every_row_name_is_offered() {
	for name in names() {
		assert standard.features.any(it.extension == name), '${name} names no construct'
	}
	for feature in standard.features {
		if feature.extension == '' {
			continue
		}
		assert known(feature.extension), '${feature.extension} is not a name the flag offers'
	}
}

fn test_every_extension_is_off_until_it_is_named() {
	o := flags([])
	for name in names() {
		assert !o.enabled(name)
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
	assert o.enabled_names() == names()
}

fn test_the_last_mention_of_a_name_wins() {
	off := flags(['-fvcc-exts=auto', '-fno-vcc-exts=auto'])
	assert !off.enabled('auto')
	on := flags(['-fno-vcc-exts=auto', '-fvcc-exts=auto'])
	assert on.enabled('auto')
}

fn test_all_then_off_leaves_the_others_on() {
	// The one clause of the flag that is worth writing down: `all` is the names
	// the table carries, so turning one name off afterwards takes nothing else
	// with it.
	o := flags(['-fvcc-exts=all', '-fno-vcc-exts=x'])
	assert !o.enabled('x')
	for name in names() {
		assert o.enabled(name)
	}
}

fn test_all_in_the_other_direction_turns_everything_off() {
	on := flags(['-fvcc-exts=all'])
	assert on.enabled_names() == names()
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
		for name in names() {
			assert err.msg().contains(name)
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
	for name in names() {
		assert opts.vcc_extensions.enabled(name)
	}
	assert opts.vcc_extensions.enabled_names() == names()
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

fn test_one_flag_may_name_several_extensions_to_turn_off() {
	// The off flag takes a list like the on flag, which is what lets a build
	// say -fno-vcc-exts=auto,typeof over a tree that had both on.
	o := flags(['-fvcc-exts=all', '-fno-vcc-exts=auto,typeof'])
	assert !o.enabled('auto')
	assert !o.enabled('typeof')
	assert o.enabled('generic')
	assert o.enabled('static-assert')
	assert o.enabled_names() == ['generic', 'static-assert']
	assert o.recorded == ['-fvcc-exts=all', '-fno-vcc-exts=auto,typeof']
}

fn test_a_name_named_twice_in_one_flag_is_mentioned_twice() {
	// A mention is what a flag said and not what a run decided, so a name
	// written twice leaves two of them; what is on is one name, because the
	// list a run reports carries no name twice.
	o := flags(['-fvcc-exts=auto,auto'])
	assert o.mentions.len == 2
	assert o.mentions[0].name == 'auto'
	assert o.mentions[0].on
	assert o.mentions[1].name == 'auto'
	assert o.mentions[1].on
	assert o.enabled('auto')
	assert o.enabled_names() == ['auto']
}

fn test_all_beside_a_name_leaves_that_name_on() {
	o := flags(['-fvcc-exts=all,auto'])
	assert o.enabled_names() == names()
	// all writes one mention per name, so the list is longer than the line.
	assert o.mentions.len == names().len + 1
	assert o.recorded == ['-fvcc-exts=all,auto']
}

fn test_every_name_the_flag_offers_can_be_named_and_turned_off() {
	// One name at a time, both directions: a name the table carries is a name
	// the flag takes on its own line, and turning it back off leaves nothing on.
	for name in names() {
		on := flags(['-fvcc-exts=${name}'])
		assert on.enabled(name), name
		assert on.enabled_names() == [name], name
		off := flags(['-fvcc-exts=${name}', '-fno-vcc-exts=${name}'])
		assert !off.enabled(name), name
		assert off.enabled_names() == [], name
	}
}

fn test_the_mentions_keep_the_order_the_flags_were_written_in() {
	// The order is the whole reason the list exists: the last mention of a name
	// is the one that counts, so a later flag has to come later in the list.
	o := flags(['-fno-vcc-exts=auto', '-fvcc-exts=auto', '-fno-vcc-exts=auto'])
	assert o.mentions.len == 3
	assert o.mentions.map(it.name) == ['auto', 'auto', 'auto']
	assert o.mentions.map(it.on) == [false, true, false]
	assert !o.enabled('auto')
	assert o.recorded == ['-fno-vcc-exts=auto', '-fvcc-exts=auto', '-fno-vcc-exts=auto']
}
