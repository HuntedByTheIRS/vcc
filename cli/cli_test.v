module cli

import os

fn test_an_input_and_an_output() {
	opts := parse(['seven.c', '-o', 'seven'])!
	assert opts.inputs == ['seven.c']
	assert opts.output == 'seven'
	assert opts.compile_only == false
}

fn test_a_joined_output_value_works_too() {
	opts := parse(['-oseven', 'seven.c'])!
	assert opts.output == 'seven'
	assert opts.inputs == ['seven.c']
}

fn test_joined_and_separate_paths_are_the_same_flag() {
	joined := parse(['-I/usr/include', '-DN=7', '-L/usr/lib', '-lm', 'x.c'])!
	separate := parse(['-I', '/usr/include', '-D', 'N=7', '-L', '/usr/lib', '-l', 'm', 'x.c'])!
	assert joined.include_dirs == separate.include_dirs
	assert joined.defines == separate.defines
	assert joined.library_dirs == separate.library_dirs
	assert joined.libraries == separate.libraries
	assert joined.include_dirs == ['/usr/include']
	assert joined.defines == ['N=7']
}

fn test_the_optimizer_owns_its_flags() {
	opts := parse(['-O2', '-fno-builtin', '-fno-builtin-abs', 'src.c', '-o', 'out'])!
	// Recognized by the optimizer, so not in the ignored list, and not refused.
	assert !opts.ignored.contains('-O2')
	assert !opts.ignored.contains('-fno-builtin')
	assert opts.optimization.level == .o2
	assert !opts.optimization.builtins
	assert opts.optimization.recorded == ['-O2', '-fno-builtin', '-fno-builtin-abs']
	assert opts.optimization.disabled == ['abs']
}

fn test_a_level_this_stub_does_not_implement_is_still_not_refused() {
	opts := parse(['-O9', 'src.c', '-o', 'out'])!
	assert opts.optimization.level == .o0
	assert opts.optimization.recorded == ['-O9']
	assert opts.inputs == ['src.c']
}

fn test_compile_only_and_print_ast_are_their_own_modes() {
	only := parse(['-c', 'src.c', '-o', 'src.o'])!
	assert only.compile_only
	assert only.output == 'src.o'
	assert !only.print_ast
	printed := parse(['-print-ast', 'src.c'])!
	assert printed.print_ast
	assert !printed.compile_only
	assert !printed.ignored.contains('-print-ast')
	// Reading the tree is not a reason to stop reading the command line.
	both := parse(['-O2', '-print-ast', 'src.c'])!
	assert both.print_ast
	assert both.optimization.level == .o2
}

fn test_what_v_passes_is_accepted_rather_than_refused() {
	// The flag set read off the V tree: a compiler that errors on one of these
	// fails a build it was supposed to serve.
	opts := parse(['-std=gnu11', '-w', '-fwrapv', '-bt25', '-B/opt/tcc/lib/tcc', '-g',
		'-Werror=implicit-function-declaration', '-Wl,-rpath,/opt/v', '-DGC_THREADS=1',
		'-DTHREAD_LOCAL_ALLOC=1', '-I/opt/libgc/include', '/opt/libgc.a', 'src.c', '-o', 'out'])!
	assert opts.inputs == ['/opt/libgc.a', 'src.c']
	assert opts.standard == 'gnu11'
	assert opts.defines == ['GC_THREADS=1', 'THREAD_LOCAL_ALLOC=1']
	assert opts.include_dirs == ['/opt/libgc/include']
	assert opts.inhibit_warnings
	assert opts.ignored.contains('-bt25')
	assert opts.ignored.contains('-Wl,-rpath,/opt/v')
	assert opts.ignored.contains('-B/opt/tcc/lib/tcc')
}

fn test_the_standard_is_recorded_from_either_spelling() {
	// V passes -std=gnu11 and a person types -std gnu11. The second one has to
	// be read as a value, or the version name becomes an input file and the
	// failure is about linking rather than about standards.
	joined := parse(['-std=gnu11', 'src.c'])!
	separate := parse(['-std', 'c99', 'src.c'])!
	assert joined.standard == 'gnu11'
	assert separate.standard == 'c99'
	assert joined.inputs == ['src.c']
	assert separate.inputs == ['src.c']
	assert !joined.ignored.contains('-std=gnu11')
	assert !separate.ignored.contains('-std')
}

fn test_the_standard_needs_a_value() {
	if _ := parse(['src.c', '-std']) {
		assert false, '-std with nothing after it should be an error'
	}
}

fn test_run_mode_splits_the_source_from_the_program_arguments() {
	opts := parse(['-run', 'prog.c', 'one', 'two'])!
	assert opts.run
	assert opts.inputs == ['prog.c']
	assert opts.run_args == ['one', 'two']
}

fn test_a_double_dash_puts_everything_after_it_in_the_program_arguments() {
	opts := parse(['-run', 'prog.c', '--', '-o', 'weird'])!
	assert opts.inputs == ['prog.c']
	assert opts.run_args == ['-o', 'weird']
}

fn test_standard_input_is_an_input() {
	opts := parse(['-', '-o', 'out'])!
	assert opts.inputs == ['-']
}

fn test_a_missing_value_is_an_error() {
	if _ := parse(['-o']) {
		assert false, '-o with nothing after it should be an error'
	} else {
		assert true
	}
}

fn test_a_list_file_is_spliced_in_place() {
	path := os.join_path(os.temp_dir(), 'vcc_cli_test_${os.getpid()}.txt')
	os.write_file(path, '-std=gnu11	-bt25\n-o out\nsrc.c\n')!
	opts := parse(['@${path}'])!
	os.rm(path) or {}
	assert opts.output == 'out'
	assert opts.inputs == ['src.c']
	assert opts.standard == 'gnu11'
	assert opts.ignored == ['-bt25']
}

fn test_an_unknown_flag_is_recorded_not_refused() {
	opts := parse(['-something-new', 'x.c'])!
	assert opts.inputs == ['x.c']
	assert opts.ignored == ['-something-new']
}

fn test_the_target_can_be_named() {
	assert parse(['-target', 'x86_64-linux', 'x.c'])!.target == 'x86_64-linux'
}

fn test_bench_lines_carry_the_phase_and_the_time() {
	lines := bench_lines([Phase{
		name:   'lex'
		micros: 41
	}])
	assert lines == ['bench lex: 41us']
}

fn test_usage_mentions_the_output_and_the_version_flags() {
	text := usage(true)
	assert text.contains('-o outfile')
	assert text.contains('--version')
	assert text.contains('libgc.a')
	assert text.contains('-std version')
}

fn test_undef_and_dm_are_their_own_modes() {
	opts := parse(['-undef', '-dM', 'x.c'])!
	assert opts.undef_builtins
	assert opts.dump_macros
}

fn test_the_two_dependency_modes_differ_by_the_system_headers() {
	full := parse(['-M', 'x.c'])!
	assert full.deps && full.deps_system
	user := parse(['-MM', 'x.c'])!
	assert user.deps && !user.deps_system
}

fn test_the_dependency_file_can_be_joined_or_separate() {
	joined := parse(['-MM', '-MFout.d', 'x.c'])!
	assert joined.deps_file == 'out.d'
	separate := parse(['-MM', '-MF', 'out.d', 'x.c'])!
	assert separate.deps_file == 'out.d'
}

fn test_a_prelude_keeps_the_order_it_was_given_in() {
	opts := parse(['-imacros', 'macros.h', '-include', 'pre.h', 'x.c'])!
	assert opts.preludes.len == 2
	assert opts.preludes[0].path == 'macros.h'
	assert opts.preludes[0].macros_only
	assert opts.preludes[1].path == 'pre.h'
	assert opts.preludes[1].macros_only == false
}

fn test_the_dependency_modes_that_also_compile() {
	full := parse(['-MD', 'x.c'])!
	assert full.deps && full.deps_system && full.deps_compile
	user := parse(['-MMD', 'x.c'])!
	assert user.deps && !user.deps_system && user.deps_compile
	stopping := parse(['-M', 'x.c'])!
	assert stopping.deps && !stopping.deps_compile
}

fn test_the_rule_can_be_given_a_target() {
	assert parse(['-MD', '-MT', 'build/seven.o', 'x.c'])!.deps_target == 'build/seven.o'
	assert parse(['-MD', '-MQ', 'a b.o', 'x.c'])!.deps_target == 'a b.o'
}

// elf_of is the beginning of an ELF64 file of one e_type: the magic, the class
// and data bytes, and the two bytes of the type at offset 16. Classification
// reads no more than this, so a file this long is a file it decides.
fn elf_of(kind u16) []u8 {
	mut bytes := [u8(0x7f), `E`, `L`, `F`, u8(2), u8(1), u8(1), u8(0)]
	bytes << []u8{len: 8}
	bytes << u8(kind & 0xff)
	bytes << u8((kind >> 8) & 0xff)
	return bytes
}

fn input_scratch_dir() string {
	dir := os.join_path(os.temp_dir(), 'vcc_cli_input_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// An object and an archive are link inputs and not source, and the kind is read
// off the file rather than off its name. Reading an object as source is the bug
// this pins: it reported an unexpected character from inside the ELF header,
// which is a wrong reading of a file that is not the wrong kind of file only
// because nobody had said what it was.
fn test_an_object_or_an_archive_is_classified_and_named() {
	dir := input_scratch_dir()
	object := os.join_path(dir, 'from_vcc.o')
	os.write_file_array(object, elf_of(1)) or { panic(err) }
	assert classify_input(object, '') == .object
	said := input_refusal(object, classify_input(object, ''))
	assert said.contains(object)
	assert said.contains('relocatable object')

	archive := os.join_path(dir, 'libgc.a')
	os.write_file_array(archive, '!<arch>\n'.bytes()) or { panic(err) }
	assert classify_input(archive, '') == .archive
	assert input_refusal(archive, .archive).contains('archive')

	// The other two containers an ELF can be, so that a program or a shared
	// object handed to the compiler is named as itself and not as an object.
	shared := os.join_path(dir, 'libm.so')
	os.write_file_array(shared, elf_of(3)) or { panic(err) }
	assert classify_input(shared, '') == .shared_object
	program := os.join_path(dir, 'a.out')
	os.write_file_array(program, elf_of(2)) or { panic(err) }
	assert classify_input(program, '') == .program

	// The name is the fallback for a file whose magic is not one the reader
	// knows, which is a truncated object or a linker script carrying a
	// library's name.
	script := os.join_path(dir, 'libdl.so')
	os.write_file(script, 'GROUP ( /lib/libdl.so.2 )\n') or { panic(err) }
	assert classify_input(script, '') == .shared_object
	named := os.join_path(dir, 'cache.tmp.c.o')
	os.write_file(named, 'not an elf at all\n') or { panic(err) }
	assert classify_input(named, '') == .object

	for path in [object, archive, shared, program, script, named] {
		os.rm(path) or {}
	}
}

// What is left is source, and a -x naming a C language says so regardless of the
// name the file carries: gcc reads `-x c foo.o` as C and so does this.
fn test_what_is_left_is_source_and_x_can_say_so() {
	dir := input_scratch_dir()
	source := os.join_path(dir, 'seven.c')
	os.write_file(source, 'int main(void) { return 0; }\n') or { panic(err) }
	assert classify_input(source, '') == .source

	// A path that cannot be opened is left to the driver's own message about
	// the file it could not read, rather than guessed at here.
	assert classify_input(os.join_path(dir, 'nothing_here.c'), '') == .source
	// Standard input has no file behind it and is source.
	assert classify_input('-', '') == .source

	object := os.join_path(dir, 'forced.o')
	os.write_file_array(object, elf_of(1)) or { panic(err) }
	assert classify_input(object, 'c') == .source
	assert classify_input(object, 'c-header') == .source
	assert classify_input(object, '') == .object
	// -x none is gcc's way of cancelling an earlier -x, so it declares nothing.
	assert classify_input(object, 'none') == .object
	assert classify_input(object, 'assembler') == .object

	for path in [source, object] {
		os.rm(path) or {}
	}
}
