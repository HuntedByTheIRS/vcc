module linux

import backend
import os

// The external link's argument list. What the flag buys is a link performed by a
// program the system has, and the command line it is given has to name the same
// places the in-house image does: the loader, the start files and the library
// directories all come from this system's description and not from this test.
//
// The start files are looked for on this machine because that is what the
// builder does; a machine without them is not a machine this compiler can link
// on, and the test says so rather than asserting a path that would only be true
// on one distribution. The same goes for the toolchain's own directory, which is
// where the start files a shared object and a static program need are kept: on a
// machine that has a compiler and no toolchain beside it, those two links cannot
// be made at all, and that is a fact about the machine rather than about the
// argument list.

fn start_file_in(dirs []string, stem string) string {
	return find_file(stem, dirs) or {
		panic('${stem} should be on this machine, in one of ${describe_dirs(dirs)}')
	}
}

// A link that brings its own entry point leaves crt1.o out and keeps the rest of the
// program's start files, and crtbegin.o is the one that matters: it is where
// __dso_handle is defined, which libc_nonshared.a's atexit reaches for.
fn test_the_stub_start_files_leave_out_the_entry_point_and_keep_the_rest() {
	stub := stub_start_files()
	program := start_files(.program)
	assert 'crt1.o' !in stub.before
	assert 'crti.o' in stub.before
	assert 'crtbegin.o' in stub.before
	assert stub.before.len == program.before.len - 1
	assert stub.after == program.after
}

fn test_the_link_arguments_name_the_loader_the_start_files_and_the_directories() {
	host := backend.host() or { panic('this test needs the host target') }
	dirs := host.link_dirs([]string{})
	args := link_arguments(.program, host.interpreter, dirs, ['x.o'], ['m'], 'out') or {
		panic(err)
	}
	// The loader is the system's own, and it is written as the linker's flag.
	assert args[0] == '-dynamic-linker'
	assert args[1] == host.interpreter
	// The start files are full paths the same search finds, in the order the
	// link passes them.
	files := start_files(.program)
	mut before := []string{}
	for stem in files.before {
		path := start_file_in(dirs, stem)
		assert path in args
		before << path
	}
	crtn := start_file_in(dirs, 'crtn.o')
	assert crtn in args
	assert args.index(before[0]) < args.index(before[1])
	// The compiler's own pair is part of a program's link too, and it sits
	// inside the C library's: crtbegin.o before -lc, crtend.o after it. Its
	// absence is not a missing name but an undefined __dso_handle, which
	// libc_nonshared.a's atexit reaches for.
	crtbegin := start_file_in(dirs, 'crtbegin.o')
	crtend := start_file_in(dirs, 'crtend.o')
	assert crtbegin in args
	assert crtend in args
	assert args.index(crtbegin) < args.index('-lc')
	assert args.index(crtend) > args.index('-lc')
	// The other two pairs belong to the other two links: a program takes the
	// bare pair, a shared object the S pair, a static program the T pair.
	assert start_file_in(dirs, 'crtbeginS.o') !in args
	assert start_file_in(dirs, 'crtbeginT.o') !in args
	// The directories a -l name is looked for in are the linker's own -L flags.
	for dir in dirs {
		assert '-L${dir}' in args
	}
	assert '-lm' in args
	assert '-lc' in args
	assert args[args.len - 2] == '-o'
	assert args[args.len - 1] == 'out'
	// crtn.o closes what crti.o opened, so it comes after the libraries.
	assert args.index(crtn) > args.index('-lc')
}

// A shared object is loaded rather than started, so no entry point and no loader
// are part of it: crt1.o, which holds the point the kernel lands on, is not an
// input at all, and what replaces it is the frame registration a library needs.
fn test_a_shared_object_is_loaded_rather_than_started() {
	host := backend.host() or { panic('this test needs the host target') }
	dirs := host.link_dirs([]string{})
	args := link_arguments(.shared, host.interpreter, dirs, ['x.o'], []string{}, 'libx.so') or {
		panic(err)
	}
	assert '-shared' in args
	assert '-dynamic-linker' !in args
	assert start_file_in(dirs, 'crt1.o') !in args
	assert start_file_in(dirs, 'crtbeginS.o') in args
	assert start_file_in(dirs, 'crtendS.o') in args
	// The static program's pair is not this one: the two register frames in
	// different ways and a link takes one pair or the other.
	assert start_file_in(dirs, 'crtbeginT.o') !in args
	assert '-lc' in args
	assert args[args.len - 2] == '-o'
	assert args[args.len - 1] == 'libx.so'
}

// A static program is started by the kernel with no loader, and its libraries are
// one group rather than a sequence: libgcc's unwinding reaches for the C
// library's threads and the C library's unwinding reaches for libgcc, so the
// order cannot be written down and the linker is told the set instead.
fn test_a_static_program_resolves_its_libraries_into_itself() {
	host := backend.host() or { panic('this test needs the host target') }
	dirs := host.link_dirs([]string{})
	args := link_arguments(.static_program, host.interpreter, dirs, ['x.o'], ['m'], 'out') or {
		panic(err)
	}
	assert '-static' in args
	assert '-dynamic-linker' !in args
	assert start_file_in(dirs, 'crtbeginT.o') in args
	assert start_file_in(dirs, 'crtend.o') in args
	assert start_file_in(dirs, 'crtbeginS.o') !in args
	open := args.index('--start-group')
	close := args.index('--end-group')
	assert open > 0
	assert close > open
	for library in link_group {
		assert args.index('-l${library}') > open
	}
	// The C library ends the group, because it is what reaches back into it.
	assert args.index('-lc') > open
	assert args.index('-lc') < close
	// A -l the command line named is placed by where it was written and is not
	// swept into the group: the group is the toolchain resolving itself.
	assert args.index('-lm') < open
}

// A directory of its own, because the test file is compiled on its own and the
// helper in the library test's file is not in scope here.
fn link_scratch_dir(name string) string {
	dir := os.join_path(os.temp_dir(), 'vcc_link_${os.getpid()}_${name}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

// A directory with no start files cannot be handed to a linker: the miss is
// reported by the file's name and the directories that were searched, and no
// argument list is produced from it.
fn test_a_start_file_that_is_missing_is_reported_by_name() {
	dir := link_scratch_dir('nolink')
	defer {
		os.rmdir_all(dir) or {}
	}
	if _ := link_arguments(.program, '/lib64/ld-linux-x86-64.so.2', [dir], ['x.o'], []string{}, 'out') {
		assert false, 'a directory with no start files cannot be linked against'
	} else {
		assert err.msg().contains('crt1.o')
		assert err.msg().contains(dir)
	}
}
