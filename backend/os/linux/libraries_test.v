module linux

import backend
import os

// The library reader. A `-l` name becomes a file, and the name the image
// carries is read out of that file rather than guessed from the flag, so these
// tests are about the shapes that file comes in on this machine.
//
// They followed the reader out of the emitter when it moved here. The subject is
// this system's libraries and this system's linker scripts, which is what makes
// them tests of the system rather than of the emitter that happens to ask.

// A directory of its own per test, so two of them running at once do not write
// over each other's libraries.
fn library_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'vcc_libraries_${os.getpid()}_${name}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// `libm.so` on this machine is a GNU ld script rather than an object file, and
// what the script names is the library it stands for. The path inside the script
// is the one this machine keeps the library in, found the way the search finds
// libraries: written out as `/usr/lib/libm.so.6` the fixture would assert the
// layout of the machine it was written on, and the same library lives in
// `/usr/lib/x86_64-linux-gnu` on a Debian-derived system.
fn test_a_library_script_names_the_library_behind_it() {
	dir := library_dir('script')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	target := find_system_library(system_dirs, 'libm.so.6') or {
		panic('this test needs a libm.so.6 on the machine it runs on')
	}
	os.write_file(os.join_path(dir, 'libprobe.so'),
		'/* GNU ld script\nOUTPUT_FORMAT(elf64-x86-64)\nGROUP ( ${target} ) */\n') or {
		panic(err)
	}
	resolved := resolve_libraries(['probe'], [dir]) or { panic(err) }
	assert resolved == ['libm.so.6']
}

// An archive is a file a link would take and this compiler cannot: saying so by
// name is what keeps a program from being built without the code it asked for.
fn test_an_archive_is_refused_by_name() {
	dir := library_dir('archive')
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'libprobe.a'), '!<arch>\n') or { panic(err) }
	if _ := resolve_libraries(['probe'], [dir]) {
		assert false, 'an archive is not a library this compiler can link'
	} else {
		assert err.msg().contains('libprobe.a')
		assert err.msg().contains('archive')
	}
}

// A library with no unversioned name is still found: glibc 2.44 ships
// `libdl.so.2` and no `libdl.so`, so a search that stopped at the unversioned
// name would fail `-ldl` on V's own command line. The version is compared as
// numbers, because sorting the file names as text puts `.10` before `.2`.
fn test_a_versioned_library_is_found_and_the_newest_version_wins() {
	dir := library_dir('versioned')
	defer {
		os.rmdir_all(dir) or {}
	}
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	older := find_system_library(system_dirs, 'libm.so.6') or { return }
	newer := find_system_library(system_dirs, 'libdl.so.2') or { return }
	copy_bytes(older, os.join_path(dir, 'libprobe.so.2'))
	copy_bytes(newer, os.join_path(dir, 'libprobe.so.10'))
	resolved := resolve_libraries(['probe'], [dir]) or { panic(err) }
	assert resolved == ['libdl.so.2']
}

fn find_system_library(dirs []string, name string) ?string {
	for dir in dirs {
		path := os.join_path(dir, name)
		if os.is_file(path) {
			return path
		}
	}
	return none
}

// The symbol reader: a library the search finds answers the names it defines.
// That is what lets a caller tell an import that will resolve when the loader
// runs from one that will not.
fn test_a_library_answers_the_symbols_it_defines() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	libc := find_system_library(system_dirs, 'libc.so.6') or { return }
	symbols := library_symbols(libc) or { panic('the C library should read as one') }
	assert 'exit' in symbols
	assert 'printf' in symbols
	assert 'nowhere' !in symbols
}

// `libm.so` on this machine is a GNU ld script, so the reader has to follow it
// to `libm.so.6` to find the names it defines. fetestexcept is in libm and not
// in the C library, so it is the name that proves the script was followed.
fn test_a_library_behind_a_script_answers_its_symbols() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	script := find_system_library(system_dirs, 'libm.so') or { return }
	symbols := library_symbols(script) or { panic('a library script should name a library that reads') }
	assert 'fetestexcept' in symbols
	assert 'sqrt' in symbols
	assert 'nowhere' !in symbols
}

// The question the caller asks: which imports no library the image names
// provides. A symbol in the C library resolves, a symbol only in libm resolves
// when -lm is on the command line, and a name in neither is reported.
fn test_an_import_no_library_provides_is_reported() {
	system_dirs := backend.host() or { panic('this test needs the host target') }.library_dirs
	assert unresolved_imports(['exit', 'nowhere'], [], system_dirs) == ['nowhere']
	if find_system_library(system_dirs, 'libm.so') != none {
		assert unresolved_imports(['fetestexcept'], ['m'], system_dirs).len == 0
		assert unresolved_imports(['fetestexcept'], [], system_dirs) == ['fetestexcept']
	}
}

fn copy_bytes(from string, to string) {
	bytes := os.read_bytes(from) or { panic(err) }
	os.write_file_array(to, bytes) or { panic(err) }
}
