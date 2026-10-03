module linux

// The command line an external linker is given, built from this system's own
// description of itself. The flag that reaches here is `-external-linker`, and
// what it buys is a link for the inputs this compiler cannot consume yet: a
// relocatable object, an archive. Nothing here decides that a link should
// happen; it answers what a link on this system is made of.
//
// Everything a path is taken from lives in this directory and its neighbours:
// the start files are names resolved through the same search a -l name goes
// through, the loader is `interpreter` from linux.v, and the directories are
// `library_dirs` from linux.v. A caller passes what the command line added
// (its -L directories) and this file puts the system's own beside them, so a
// linker asked by this compiler searches exactly what the in-house path would.

// link_arguments is the ordered argument list for the linker.
//
// `interpreter` is the dynamic loader the image names, `start_dirs` is where the
// start files are looked for, `search_dirs` is where a -l name is looked for and
// is written as the linker's own -L flags, `objects` are the inputs in the order
// the command line gave them (this compiler's emitted objects and the foreign
// ones alike), `libraries` are the -l names the command line asked for in order,
// and `output` is the program to write.
//
// The C library is asked for by its -l name and placed after the libraries the
// command line named, which is what a C program needs and what a -l name is for;
// crtn.o follows the libraries because that is where the C runtime closes the
// sections crti.o opened.
pub fn link_arguments(interpreter string, start_dirs []string, search_dirs []string, objects []string, libraries []string, output string) ![]string {
	mut args := []string{}
	args << '-dynamic-linker'
	args << interpreter
	for stem in start_files_before {
		args << find_file(stem, start_dirs) or {
			return error('cannot find ${stem}: searched ${describe_dirs(start_dirs)}')
		}
	}
	for dir in search_dirs {
		args << '-L${dir}'
	}
	args << objects
	for library in libraries {
		args << '-l${library}'
	}
	args << '-l${base_library_flag}'
	for stem in start_files_after {
		args << find_file(stem, start_dirs) or {
			return error('cannot find ${stem}: searched ${describe_dirs(start_dirs)}')
		}
	}
	args << '-o'
	args << output
	return args
}
