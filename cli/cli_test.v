module cli

import os
import v.vmod

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

// -fPIC and -fpic are the two spellings gcc offers for one thing, and -fno-pic
// takes the addressing back. The flag is read rather than recorded: it decides
// the form of every reference to a top-level object another object may define,
// and a build that passes it and is told nothing is a build that has been told
// nothing. -fPIE names an executable, which is not a shape this compiler
// writes, so it stays in the accepted-and-ignored list rather than being read
// as -fPIC.
fn test_the_position_independent_flag_is_read_from_either_spelling() {
	upper := parse(['-fPIC', 'src.c'])!
	assert upper.pic
	lower := parse(['-fpic', 'src.c'])!
	assert lower.pic
	off := parse(['-fPIC', '-fno-pic', 'src.c'])!
	assert !off.pic
	absent := parse(['src.c'])!
	assert !absent.pic
	pie := parse(['-fPIE', 'src.c'])!
	assert !pie.pic
	assert pie.ignored.contains('-fPIE')
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

fn test_the_emulation_can_be_named() {
	assert parse(['-femulation=gcc', 'x.c'])!.emulation == .gcc
	assert parse(['-femulation', 'clang', 'x.c'])!.emulation == .clang
	assert parse(['-femulation=tcc', 'x.c'])!.emulation == .tcc
	assert parse(['x.c'])!.emulation == .none
}

fn test_an_unknown_emulation_is_refused() {
	if _ := parse(['-femulation=msvc', 'x.c']) {
		assert false, 'a compiler this one cannot present itself as should be refused'
	} else {
		assert err.msg().contains('gcc, clang and tcc')
	}
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

// The -print- family asks a question and stops. Each flag is read rather than
// recorded, because a flag the driver never looks at would be answered as an
// ordinary compile with no input file, which is the one thing a build tool
// asking these questions does not have.
fn test_every_query_flag_is_read_as_a_question() {
	options := [
		'-print-search-dirs',
		'-print-libgcc-file-name',
		'-print-file-name=libc.so',
		'-print-prog-name=ld',
		'-print-multiarch',
		'-print-multi-directory',
		'-print-multi-lib',
		'-print-multi-os-directory',
		'-print-sysroot',
		'-print-sysroot-headers-suffix',
	]
	for flag in options {
		opts := parse([flag])!
		assert opts.asks_query(), '${flag} was not read as a query'
		assert !opts.ignored.contains(flag), '${flag} was recorded as ignored'
		assert opts.inputs.len == 0
	}
}

fn test_a_file_name_query_keeps_its_value_and_the_empty_one() {
	joined := parse(['-print-file-name=libc.so'])!
	assert joined.print_file_name == 'libc.so'
	assert joined.print_file_name_given
	// An empty name is a question too, so "was it given" cannot be read off the
	// value.
	empty := parse(['-print-file-name='])!
	assert empty.print_file_name == ''
	assert empty.print_file_name_given
	assert empty.asks_query()
}

fn test_a_prog_name_query_keeps_its_value() {
	opts := parse(['-print-prog-name=ld'])!
	assert opts.print_prog_name == 'ld'
	assert opts.print_prog_name_given
	assert !opts.ignored.contains('-print-prog-name=ld')
}

fn test_a_query_is_usable_with_a_standard_and_an_empty_command_line() {
	opts := parse(['-std=gnu11', '-print-multi-directory'])!
	assert opts.standard == 'gnu11'
	assert opts.print_multi_directory
	assert opts.asks_query()
}

fn test_an_ordinary_command_line_is_not_a_query() {
	opts := parse(['-std=gnu11', 'src.c', '-o', 'out'])!
	assert !opts.asks_query()
}

fn test_verbose_is_its_own_flag_and_the_version_stays_v() {
	opts := parse(['-verbose', 'x.c'])!
	assert opts.verbose
	assert !opts.ignored.contains('-verbose')
	// -v is the version, the tcc spelling this command line keeps, so the two
	// do not collide.
	printed := parse(['-v'])!
	assert printed.show_version
	assert !printed.verbose
}

fn test_the_search_dirs_text_has_the_shape_gcc_uses() {
	text := search_dirs_text('/opt/vcc', []string{}, ['/usr/local/lib', '/usr/lib'])
	lines := text.split('\n')
	assert lines.len == 3
	assert lines[0] == 'install: /opt/vcc'
	assert lines[1] == 'programs: ='
	assert lines[2] == 'libraries: =/usr/local/lib:/usr/lib'
	// Program directories are the caller's: the same shape with some.
	with_programs := search_dirs_text('/opt/vcc', ['/opt/vcc/bin'], ['/usr/lib']).split('\n')
	assert with_programs[1] == 'programs: =/opt/vcc/bin'
}

fn test_the_usage_lists_the_query_flags() {
	text := usage(false)
	assert text.contains('-print-search-dirs')
	assert text.contains('-print-file-name=NAME')
	assert text.contains('-print-prog-name=NAME')
	assert text.contains('-print-multi-lib')
	assert text.contains('-print-sysroot-headers-suffix')
	assert text.contains('-verbose')
}

// elf_of is the beginning of an ELF64 file of one e_type: the magic, the class
// and data bytes, and the two bytes of the type at offset 16. Classification
// reads no more than this, so a file this long is a file it decides.
fn elf_of(kind u16) string {
	mut bytes := [u8(0x7f), `E`, `L`, `F`, u8(2), u8(1), u8(1), u8(0)]
	bytes << []u8{len: 8}
	bytes << u8(kind & 0xff)
	bytes << u8((kind >> 8) & 0xff)
	return bytes.bytestr()
}

fn input_scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_cli_input_${os.getpid()}_${name}')
}

// An object and an archive are link inputs and not source, and the kind is read
// off the bytes rather than off the name. Reading an object as source is the bug
// this pins: it reported an unexpected character from inside the ELF header,
// which is a wrong reading of a file fed to the wrong stage.
//
// The bytes classified here are the ones the driver hands over, and the last
// case reads a real file back so that what a file's own contents come to is
// covered and not only what the helper writes.
fn test_an_object_or_an_archive_is_classified_and_named() {
	object := elf_of(1)
	assert classify_input(object, 'from_vcc.o', '') == .object
	said := input_refusal('from_vcc.o', .object)
	assert said.contains('from_vcc.o')
	assert said.contains('relocatable object')

	archive := '!<arch>\n'
	assert classify_input(archive, 'libgc.a', '') == .archive
	assert input_refusal('libgc.a', .archive).contains('archive')

	// The other two containers an ELF can be, so that a program or a shared
	// object handed to the compiler is named as itself and not as an object.
	assert classify_input(elf_of(3), 'libm.so', '') == .shared_object
	assert classify_input(elf_of(2), 'a.out', '') == .program

	path := input_scratch('real_object.o')
	os.write_file_array(path, object.bytes()) or { panic(err) }
	on_disk := os.read_file(path) or { panic(err) }
	assert classify_input(on_disk, path, '') == .object
	os.rm(path) or {}
}

// The name is the fallback for bytes that are not a container this reader knows,
// which is a truncated object or a linker script carrying a library's name, and
// what is left is source: a source file, an empty file, and standard input,
// which has no name to fall back on either.
fn test_the_name_decides_what_the_bytes_do_not() {
	assert classify_input('not an elf at all\n', 'cache.tmp.c.o', '') == .object
	assert classify_input('GROUP ( /lib/libdl.so.2 )\n', 'libdl.so', '') == .shared_object
	assert classify_input('int main(void) { return 0; }\n', 'seven.c', '') == .source
	assert classify_input('', 'empty.c', '') == .source
	assert classify_input('int main(void) { return 0; }\n', '-', '') == .source
}

// A -x naming a C language says the input is C whatever the bytes are, which is
// how gcc reads `-x c foo.o`. -x none is gcc's way of cancelling an earlier -x
// and declares nothing, and a -x this compiler has no reader for is left to the
// bytes rather than taken for a promise.
fn test_x_naming_c_overrides_the_bytes() {
	object := elf_of(1)
	assert classify_input(object, 'forced.o', 'c') == .source
	assert classify_input(object, 'forced.o', 'c-header') == .source
	assert classify_input(object, 'forced.o', 'cpp-output') == .source
	assert classify_input(object, 'forced.o', 'none') == .object
	assert classify_input(object, 'forced.o', '') == .object
	assert classify_input(object, 'forced.o', 'assembler') == .object
}

// -external-linker names the program that performs the final link. Both
// spellings work, the joined one and the separated one, and the value is read
// rather than recorded: a build that passes the flag and finds the in-house path
// taken anyway has been told nothing. The -f spelling is not the flag: -f is the
// feature family and linking is not a feature of the C the program is in.
fn test_the_external_linker_can_be_named_in_both_spellings() {
	joined := parse(['-external-linker=ld', 'a.c', 'b.c', '-o', 'out'])!
	separate := parse(['-external-linker', 'ld', 'a.c', 'b.c', '-o', 'out'])!
	assert joined.external_linker == 'ld'
	assert separate.external_linker == 'ld'
	assert joined.inputs == ['a.c', 'b.c']
	assert separate.inputs == ['a.c', 'b.c']
	assert !joined.ignored.contains('-external-linker=ld')
	assert !separate.ignored.contains('-external-linker')
	assert parse(['a.c', '-o', 'out'])!.external_linker == ''
}

fn test_the_external_linker_needs_a_value() {
	if _ := parse(['a.c', '-external-linker']) {
		assert false, '-external-linker with nothing after it should be an error'
	}
}

// A C compiler may not be the external linker. The compiler exists to replace
// the C compiler V vendors, so one finishing C compilation would be circular,
// and the refusal names the flag and points at a linker instead.
fn test_a_c_compiler_may_not_be_the_external_linker() {
	for name in ['gcc', 'cc', 'clang', 'c++', 'tcc'] {
		said := external_linker_refusal(name) or {
			assert false, '${name} is a C compiler and must be refused'
			''
		}
		assert said.contains('-external-linker=${name}')
		assert said.contains('a C compiler is not a linker')
		assert said.contains('ld')
		assert said.contains('lld')
	}
	// The versioned and target-prefixed spellings are the same driver.
	assert external_linker_refusal('gcc-16') != none
	assert external_linker_refusal('clang-15') != none
	assert external_linker_refusal('x86_64-linux-gnu-gcc') != none
	// A program whose name merely starts with a driver's is a different
	// program: clangd is a language server, not a compiler.
	assert external_linker_refusal('ld') == none
	assert external_linker_refusal('lld') == none
	assert external_linker_refusal('ld.lld') == none
	assert external_linker_refusal('ld.gold') == none
	assert external_linker_refusal('clangd') == none
}

// lld is the LLVM linkers' generic driver: invoked as `lld` it cannot choose a
// linker and wants `-flavor gnu` first. Every other name gets nothing before the
// link, because the GNU linkers would reject the word.
fn test_an_lld_name_gets_its_flavor_and_others_get_nothing() {
	assert external_linker_prefix('lld') == ['-flavor', 'gnu']
	assert external_linker_prefix('ld') == []
	assert external_linker_prefix('ld.lld') == []
	assert external_linker_prefix('ld.gold') == []
}

fn test_the_external_linker_is_in_the_help() {
	assert usage(false).contains('-external-linker=NAME')
	assert usage(true).contains('-external-linker')
}

// The two flags that name a kind of link are read and not recorded: a build that
// passes one and is told nothing has been told the flag was passed over, and
// what it asked for is the file that comes out.
fn test_a_kind_of_link_is_read_rather_than_recorded() {
	shared := parse(['-shared', 'x.c'])!
	assert shared.shared
	assert !shared.static_link
	assert shared.ignored.len == 0
	st := parse(['-static', 'x.c'])!
	assert st.static_link
	assert !st.shared
	assert st.ignored.len == 0
	// Both together are read here and decided where a run uses them: whether the
	// two can be combined is a question about the link, not about the spelling.
	both := parse(['-shared', '-static', 'x.c'])!
	assert both.shared && both.static_link
}

// Whether a run reaches a link is one fact, and it is the flags that decide it:
// the kind a link flag names has nothing to decide when the run stops before
// there is one.
fn test_a_run_that_stops_before_a_link_says_so() {
	assert parse(['x.c'])!.links()
	assert parse(['-shared', 'x.c'])!.links()
	assert parse(['-static', '-o', 'out', 'x.c'])!.links()
	assert !parse(['-c', 'x.c'])!.links()
	assert !parse(['-E', 'x.c'])!.links()
	assert !parse(['-M', 'x.c'])!.links()
	assert !parse(['-dM', 'x.c'])!.links()
	assert !parse(['-print-ast', 'x.c'])!.links()
	assert !parse(['-print-multiarch'])!.links()
	// A linker named on a run that stops before a link is a flag with nothing to
	// do rather than an error: the name is read and kept, the run keeps to the
	// ordinary path, and no linker is resolved for it. What the flag would have
	// done is not lost either, because the flag and the run disagree about
	// whether there is a link at all, and the run is the one that decides.
	stopped := parse(['-c', '-external-linker=ld', 'x.c'])!
	assert stopped.external_linker == 'ld'
	assert !stopped.links()
	assert stopped.in_house_link_refusal() == none
}

// The path that runs without a linker writes a program, so the two flags that
// ask for another kind of file are refused by name and the message says what
// would write them. The same flags on a run that stops before a link are not a
// refusal: there is nothing for them to decide.
fn test_the_kind_of_link_is_refused_by_name_when_nothing_writes_it() {
	assert parse(['x.c'])!.in_house_link_refusal() == none
	assert parse(['-c', '-shared', 'x.c'])!.in_house_link_refusal() == none
	assert parse(['-E', '-static', 'x.c'])!.in_house_link_refusal() == none
	shared := parse(['-shared', 'x.c'])!.in_house_link_refusal() or {
		panic('a shared object is not what this path writes')
	}
	assert shared.contains('-shared')
	assert shared.contains('-external-linker=NAME')
	st := parse(['-static', 'x.c'])!.in_house_link_refusal() or {
		panic('a static program is not what this path writes')
	}
	assert st.contains('-static')
	assert st.contains('-external-linker=NAME')
	both := parse(['-shared', '-static', 'x.c'])!.in_house_link_refusal() or {
		panic('a shared object and a static program are different links')
	}
	assert both.contains('-shared') && both.contains('-static')
}

// Both flags at once are refused on either path. A linker given the two takes one
// of them, so the file would be what one flag asked for and the other would be
// gone without a word, which is the outcome the whole flag surface exists to
// avoid.
fn test_two_kinds_of_link_at_once_are_refused() {
	assert parse(['-shared', 'x.c'])!.link_kind_conflict_refusal() == none
	assert parse(['-static', 'x.c'])!.link_kind_conflict_refusal() == none
	conflict := parse(['-shared', '-static', 'x.c'])!.link_kind_conflict_refusal() or {
		panic('a shared object and a static program are two different files')
	}
	assert conflict.contains('-shared') && conflict.contains('-static')
}

fn test_the_kind_of_link_is_in_the_help() {
	assert usage(false).contains('-shared')
	assert usage(false).contains('-static')
}

// With no flags at all the command line still has to answer: every list empty,
// every switch off, and the optimizer at the level it runs when nothing says
// otherwise. This is the baseline a later flag is a change from.
fn test_no_flags_leaves_the_defaults_in_place() {
	opts := parse(['x.c'])!
	assert opts.inputs == ['x.c']
	assert opts.output == ''
	assert opts.include_dirs.len == 0
	assert opts.defines.len == 0
	assert opts.undefines.len == 0
	assert opts.library_dirs.len == 0
	assert opts.libraries.len == 0
	assert opts.preludes.len == 0
	assert opts.ignored.len == 0
	assert opts.target == ''
	assert opts.standard == ''
	assert opts.input_type == ''
	assert opts.emulation == .none
	assert !opts.compile_only
	assert !opts.preprocess
	assert !opts.print_ast
	assert !opts.run
	assert !opts.shared
	assert !opts.static_link
	assert !opts.pic
	assert !opts.verbose
	assert !opts.inhibit_warnings
	assert !opts.undef_builtins
	assert !opts.dump_macros
	assert opts.optimization.level == .o0
	// A command line with no input at all is empty rather than an error; the
	// driver is the one that refuses it, with the usage text.
	assert parse([])!.inputs.len == 0
}

// The output is empty until -o names it. The a.out default is the driver's and
// the usage text says so; this field only ever holds what the command line
// wrote, so a caller can tell "not named" from "named a.out".
fn test_the_output_stays_empty_until_the_flag_names_it() {
	assert parse(['x.c'])!.output == ''
	assert parse(['-o', 'a.out', 'x.c'])!.output == 'a.out'
	assert usage(false).contains('default a.out')
}

// -U, -x and -B are value flags the joined spellings elsewhere do not cover:
// -U has both spellings, and -x and -B only take the next word. -B records the
// flag and its value together, because the recorded list is what a verbose run
// prints and the value is half of what was passed over.
fn test_the_naming_flags_read_their_own_arguments() {
	joined := parse(['-UFOO', '-D', 'BAR', 'x.c'])!
	assert joined.undefines == ['FOO']
	assert joined.defines == ['BAR']
	separate := parse(['-U', 'FOO', 'x.c'])!
	assert separate.undefines == ['FOO']
	assert parse(['-x', 'c', 'x.c'])!.input_type == 'c'
	assert parse(['-B', '/dir', 'x.c'])!.ignored == ['-B /dir']
	assert parse(['-B/dir', 'x.c'])!.ignored == ['-B/dir']
}

// A flag that names a path or a name is given once per directory, header and
// library, so repeating it adds to the list rather than replacing what came
// before. The order is the command line's, which a search reads.
fn test_a_repeated_value_flag_accumulates_in_order() {
	opts := parse(['-I', 'a', '-Ib', '-D', 'ONE', '-DTWO', '-Lx', '-L', 'y', '-lm', '-l', 'pthread',
		'x.c'])!
	assert opts.include_dirs == ['a', 'b']
	assert opts.defines == ['ONE', 'TWO']
	assert opts.library_dirs == ['x', 'y']
	assert opts.libraries == ['m', 'pthread']
}

// A boolean flag that can also be turned off is decided by the last spelling on
// the line, which is what lets a build append -fno-pic to a line that already
// had -fPIC. A flag with no negative spelling stays on however often it is
// written.
fn test_a_repeated_boolean_flag_is_decided_by_the_last_spelling() {
	assert parse(['-fPIC', '-fno-pic', 'x.c'])!.pic == false
	assert parse(['-fno-pic', '-fPIC', 'x.c'])!.pic
	assert parse(['-fno-PIC', '-fpic', 'x.c'])!.pic
	assert parse(['-c', '-c', 'x.c'])!.compile_only
}

// The ignored list is the promise the flag surface makes: what was accepted and
// not acted on is recorded rather than refused, so a verbose run can say what
// it passed over. A flag this compiler reads is not in it.
fn test_the_ignored_list_holds_the_flags_that_were_passed_over() {
	opts := parse(['-bt25', '-Wl,-rpath,/opt/v', '-fwrapv', '-fPIE', '-B/some/dir', 'x.c', '-o',
		'out'])!
	for flag in ['-bt25', '-Wl,-rpath,/opt/v', '-fwrapv', '-fPIE', '-B/some/dir'] {
		assert opts.ignored.contains(flag), '${flag} should be recorded, not refused'
	}
	for read_flag in ['-o', 'out', '-c', '-w', '-verbose', '-print-search-dirs', '-shared'] {
		assert !opts.ignored.contains(read_flag), '${read_flag} is read and not recorded'
	}
}

// The recorded list keeps the order the flags were written in, so the verbose
// output reads the way the command line did.
fn test_the_ignored_list_keeps_the_command_line_order() {
	opts := parse(['-bt25', '-fwrapv', '-Wl,-z,now', 'x.c'])!
	assert opts.ignored == ['-bt25', '-fwrapv', '-Wl,-z,now']
}

// -v is the version, -vv is the paths, and -verbose is the long spelling of the
// detailed report. They are three switches on three fields, so a build that
// asks for one is not answered with another.
fn test_the_version_paths_and_verbose_switches_are_separate() {
	version_flag := parse(['-v'])!
	assert version_flag.show_version
	assert !version_flag.show_paths
	assert !version_flag.verbose
	assert parse(['--version'])!.show_version
	paths := parse(['-vv'])!
	assert paths.show_paths
	assert !paths.show_version
	assert !paths.verbose
	verbose := parse(['-verbose', 'x.c'])!
	assert verbose.verbose
	assert !verbose.show_version
	assert !verbose.show_paths
}

// -h and -hh are the two help flags, and they name the two texts main.v prints:
// -h the short usage and -hh the replacement section as well. They can be given
// together, which is what a command line appending -hh to -h does.
fn test_the_two_help_flags_select_the_two_texts() {
	short := parse(['-h'])!
	assert short.show_help
	assert !short.show_help_all
	all := parse(['-hh'])!
	assert all.show_help_all
	assert !all.show_help
	both := parse(['-h', '-hh'])!
	assert both.show_help && both.show_help_all
}

// -E is a switch of its own and not just "a run that does not link": it says
// the token stream is what comes out, which is a fact the driver reads before
// it decides what to write.
fn test_the_preprocess_flag_is_its_own_switch() {
	opts := parse(['-E', 'x.c'])!
	assert opts.preprocess
	assert !opts.compile_only
	assert !opts.print_ast
	assert !opts.links()
}

// - is an input, and it is the one input with no name to read a kind from. The
// -- marker ends the flags, so a - after it is an input too and the word after
// it is an input rather than a flag.
fn test_standard_input_and_the_end_of_flags_marker() {
	assert parse(['-', '-o', 'out'])!.inputs == ['-']
	assert parse(['--', '-', 'x.c'])!.inputs == ['-', 'x.c']
	assert parse(['--', '-o'])!.inputs == ['-o']
}

// The version line and the usage text both name the binary, because both are
// read by a build tool that has to know which compiler answered.
fn test_the_version_line_and_the_usage_name_the_binary() {
	line := version_line()
	assert line.contains('vcc')
	assert line.contains(version)
	text := usage(false)
	assert text.starts_with('Usage: vcc')
	assert text.contains('vcc')
}

// version is not written in cli.v: it is the version field v.mod names, and this
// pins the two together so a bump to v.mod cannot leave a stale number behind.
fn test_the_version_is_the_one_vmod_names() {
	manifest := vmod.decode(@VMOD_FILE) or { panic(err) }
	assert manifest.version != ''
	assert version == manifest.version
}

// The short usage and the full help differ by the section on what a drop-in
// replacement for the bundled tcc is asked to accept. The short text stops
// before it, and the short text is the one an error prints.
fn test_the_full_help_adds_the_replacement_section() {
	short := usage(false)
	all := usage(true)
	assert short.contains('-print-search-dirs')
	assert !short.contains('What a replacement for the bundled tcc')
	assert all.contains('What a replacement for the bundled tcc')
	assert all.len > short.len
	assert all.contains(short)
}

// The value of a flag is the next word whatever it starts with: -D -foo is a
// define named -foo, and a value is not scanned for flags. A joined value is
// the same string without the flag in front of it.
fn test_a_value_that_looks_like_a_flag_is_still_a_value() {
	opts := parse(['-D', '-foo', '-o', '-weird', 'x.c'])!
	assert opts.defines == ['-foo']
	assert opts.output == '-weird'
	assert opts.inputs == ['x.c']
}
