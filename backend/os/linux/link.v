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
// `kind` is which link was asked for: a program the loader starts, a static
// program the kernel starts with every library resolved into it, or a shared
// object another program loads. `interpreter` is the dynamic loader the program
// names and is named by that kind alone, `dirs` is where a -l name and a start
// file are both looked for, written as the linker's own -L flags as well as
// being the search this file resolves a start file through, `objects` are the
// inputs in the order the command line gave them (this compiler's emitted
// objects and the foreign ones alike), `libraries` are the -l names the
// command line asked for in order, and `output` is the file to write.
//
// The C library is asked for by its -l name and placed after the libraries the
// command line named, which is what a C program needs and what a -l name is for;
// the last start file follows the libraries because that is where the C runtime
// closes the sections the first one opened. A static link is the exception to
// that order: its libraries go in a group, because libgcc and the C library
// reach for each other and the only way to ask a linker to come back to a
// library it has passed is to name the set it may come back to.
pub fn link_arguments(kind LinkKind, interpreter string, dirs []string, objects []string, libraries []string, output string) ![]string {
	mut args := []string{}
	match kind {
		.program {
			// The loader is a program's own fact: the kernel hands the image to
			// it. A shared object is loaded by whoever names it, and a static
			// program is started with no loader at all.
			args << '-dynamic-linker'
			args << interpreter
		}
		.static_program {
			args << '-static'
		}
		.shared {
			args << '-shared'
		}
	}
	files := start_files(kind)
	for stem in files.before {
		args << find_file(stem, dirs) or {
			return error('cannot find ${stem}: searched ${describe_dirs(dirs)}')
		}
	}
	for dir in dirs {
		args << '-L${dir}'
	}
	args << objects
	for library in libraries {
		args << '-l${library}'
	}
	if kind == .static_program {
		args << '--start-group'
		for library in link_group {
			args << '-l${library}'
		}
	}
	args << '-l${base_library_flag}'
	if kind == .static_program {
		args << '--end-group'
	}
	for stem in files.after {
		args << find_file(stem, dirs) or {
			return error('cannot find ${stem}: searched ${describe_dirs(dirs)}')
		}
	}
	args << '-o'
	args << output
	return args
}
