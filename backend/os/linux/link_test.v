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
// on one distribution.

fn test_the_link_arguments_name_the_loader_the_start_files_and_the_directories() {
	host := backend.host() or { panic('this test needs the host target') }
	system_dirs := host.library_dirs
	search_dirs := host.library_dirs_for([]string{})
	args := link_arguments(host.interpreter, system_dirs, search_dirs, ['x.o'], ['m'], 'out') or {
		panic(err)
	}
	// The loader is the system's own, and it is written as the linker's flag.
	assert args[0] == '-dynamic-linker'
	assert args[1] == host.interpreter
	// The start files are full paths the same search finds, in the order the
	// link passes them.
	mut before := []string{}
	for stem in start_files_before {
		path := find_file(stem, system_dirs) or { panic('${stem} should be on this machine') }
		assert path in args
		before << path
	}
	crtn := find_file('crtn.o', system_dirs) or { panic('crtn.o should be on this machine') }
	assert crtn in args
	assert args.index(before[0]) < args.index(before[1])
	// The library directories are the search a -l name goes through, written as
	// the linker's -L flags.
	for dir in search_dirs {
		assert '-L${dir}' in args
	}
	assert '-lm' in args
	assert '-lc' in args
	assert args[args.len - 2] == '-o'
	assert args[args.len - 1] == 'out'
	// crtn.o closes what crti.o opened, so it comes after the libraries.
	assert args.index(crtn) > args.index('-lc')
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
	if _ := link_arguments('/lib64/ld-linux-x86-64.so.2', [dir], [dir], ['x.o'], []string{}, 'out') {
		assert false, 'a directory with no start files cannot be linked against'
	} else {
		assert err.msg().contains('crt1.o')
		assert err.msg().contains(dir)
	}
}
