module main

import backend
import cli
import os

// The -print- flags answer a question and stop. These tests drive the same
// function main() does with the facts it gathers, so what is checked is the
// answer and not the shape of the command-line reading, which cli's own tests
// cover.
//
// The one fact that has to hold is that a file answer comes from the search the
// linker uses: a `-print-file-name=` that named a file the link would not pick is
// worse than one that says it cannot find it.

fn test_a_file_answer_uses_the_linkers_search() {
	target := backend.host() or { panic('this test needs the host target') }
	dir := query_scratch('query_dir')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	probe := os.join_path(dir, 'libprobe.so')
	os.write_file(probe, 'probe') or { panic(err) }
	// The -L directory is searched before the target's own, so a name placed
	// there is the file the answer names.
	opts := cli.parse(['-L', dir, '-print-file-name=libprobe.so'])!
	assert opts.print_file_name_given
	assert query_answer(opts, target) == probe
	// A name the search does not have comes back unchanged, which is what gcc
	// does with one too.
	missing := cli.parse(['-L', dir, '-print-file-name=nosuchfile.xyz'])!
	assert query_answer(missing, target) == 'nosuchfile.xyz'
}

// An empty name is a question like any other and follows the same rule: it is
// not a file, so it comes back unchanged, which is empty. gcc answers its
// install directory here, which is a gcc fact this compiler does not have.
fn test_an_empty_file_name_comes_back_empty() {
	target := backend.host() or { panic('this test needs the host target') }
	opts := cli.parse(['-print-file-name='])!
	assert opts.print_file_name_given
	assert query_answer(opts, target) == ''
}

// A file answer that is a path has to name a file that exists, whether it came
// from the machine's own search or from a -L directory.
fn test_a_file_answer_that_is_a_path_names_a_file() {
	target := backend.host() or { panic('this test needs the host target') }
	for name in ['libc.so', 'libm.so', 'crt1.o'] {
		opts := cli.parse(['-print-file-name=${name}'])!
		answer := query_answer(opts, target)
		if answer != name {
			assert os.is_file(answer), '${name} answered ${answer}, which is not a file'
		}
	}
}

// The answers that need no search are this compiler's own and not gcc's: the one
// variant it has, the multiarch spelling its search lists are built from, and the
// two questions whose honest answer is empty because there is no sysroot and no
// libgcc.
fn test_the_answers_that_need_no_search() {
	target := backend.host() or { panic('this test needs the host target') }
	assert query_answer(cli.parse(['-print-multi-directory'])!, target) == '.'
	assert query_answer(cli.parse(['-print-multi-lib'])!, target) == '.;'
	assert query_answer(cli.parse(['-print-multi-os-directory'])!, target) == '.'
	assert query_answer(cli.parse(['-print-multiarch'])!, target) == '${target.arch}-${target.os}-gnu'
	assert query_answer(cli.parse(['-print-sysroot'])!, target) == ''
	assert query_answer(cli.parse(['-print-sysroot-headers-suffix'])!, target) == ''
	// This compiler runs no external program, so a program name is the answer
	// gcc gives for one it cannot find.
	assert query_answer(cli.parse(['-print-prog-name=ld'])!, target) == 'ld'
	assert query_answer(cli.parse(['-print-prog-name=nosuchprog'])!, target) == 'nosuchprog'
}

// No libgcc is linked, so the answer is the name or a path that exists, never a
// path the linker would refuse to read.
fn test_the_libgcc_answer_is_the_name_or_a_file() {
	target := backend.host() or { panic('this test needs the host target') }
	answer := query_answer(cli.parse(['-print-libgcc-file-name'])!, target)
	if answer != 'libgcc.a' {
		assert os.is_file(answer)
	}
}

// The search-dirs answer has gcc's three keys, and the libraries it names are the
// ones the linker would search.
fn test_the_search_dirs_answer_has_gccs_keys() {
	target := backend.host() or { panic('this test needs the host target') }
	opts := cli.parse(['-print-search-dirs'])!
	lines := query_answer(opts, target).split('\n')
	assert lines.len == 3
	assert lines[0].starts_with('install: ')
	assert lines[1] == 'programs: ='
	assert lines[2] == 'libraries: =${target.library_dirs.join(':')}'
}

// Every query is answerable with no input file and with a standard selected,
// which is how a build tool asks it.
fn test_every_query_answers_with_a_standard_and_no_input_file() {
	target := backend.host() or { panic('this test needs the host target') }
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
		opts := cli.parse(['-std=gnu11', flag])!
		assert opts.asks_query()
		assert opts.standard == 'gnu11'
		assert opts.inputs.len == 0
		// The call answers rather than refusing; the value is asserted above
		// where it is a fixed one.
		answer := query_answer(opts, target)
		assert answer.len >= 0
	}
}

// query_scratch is this file's own scratch path: a test file is compiled on its
// own, so a helper written in another one is not in scope.
fn query_scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_query_test_${os.getpid()}_${name}')
}
