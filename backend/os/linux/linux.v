module linux

import os

// Linux, described where it adds something to a bare machine: the kernel entry
// points a program can call, the registers their arguments arrive in, and the
// numbers the loader and the container format are defined by.
//
// A system does not know which machine it is running on, so everything that
// depends on the architecture is asked for by name and answered per architecture.
// A second system is a directory of its own beside this one, for the same reason
// a second machine is, and it does not need the machine's file to exist to be
// written.

pub const name = 'linux'

// base_library is the C library every image this system writes runs against,
// whether or not a -l named it: a program written in C has the C library, and
// the container adds it to the image. The reader that checks an image's imports
// reads this library for the same reason, and both name it from here.
pub const base_library = 'libc.so.6'

// base_library_flag is the -l spelling of the C library above. A linker is asked
// for the library by name rather than by file so that its own search resolves
// the name to the script or the file the system keeps, which is how a -l name is
// resolved for every other library; naming the file directly would run around
// that search and, on a machine where the unversioned name is a script that adds
// libc_nonshared.a, would drop the extra file the script brings in.
pub const base_library_flag = 'c'

// LinkKind is which link a command line asked for. The three differ in the
// arguments a linker is given and in nothing else, so they are one value with
// three cases rather than three ways to build a command line.
//
// A program is the dynamic one: the kernel hands it to the loader in
// `interpreter`. A static program names no loader and resolves every library
// into itself, and a shared object is a file another program loads rather than
// one the kernel starts, so it has no entry point and no loader either.
pub enum LinkKind {
	program
	static_program
	shared
}

// StartFiles is what a link puts around the program's own objects: the names
// before them and the names after the libraries. crt1.o holds the entry point
// the kernel lands on, crti.o opens the initialisation and finalisation
// sections, and crtn.o closes them. crtbeginS.o and crtendS.o open and close
// the frame registration a shared object needs, and crtbeginT.o and crtend.o
// the one a static program needs. They are names to be resolved in the
// directories a link searches and not paths, because which directory a system
// keeps them in is this system's layout and lives with the rest of it.
pub struct StartFiles {
pub:
	before []string
	after  []string
}

// start_files are the start files one kind of link is made of.
pub fn start_files(kind LinkKind) StartFiles {
	return match kind {
		.program {
			StartFiles{
				before: ['crt1.o', 'crti.o']
				after:  ['crtn.o']
			}
		}
		.static_program {
			StartFiles{
				before: ['crt1.o', 'crti.o', 'crtbeginT.o']
				after:  ['crtend.o', 'crtn.o']
			}
		}
		.shared {
			StartFiles{
				before: ['crti.o', 'crtbeginS.o']
				after:  ['crtendS.o', 'crtn.o']
			}
		}
	}
}

// link_group are the libraries a static link resolves against each other rather
// than one after the other. It is the one link where the order cannot be
// written down: libgcc's unwinding reaches for the C library's threads and the
// C library's own unwinding reaches for libgcc, and a group is how a linker is
// told to come back to a library it has already passed. The C library ends the
// group, so what the group holds is the toolchain's own support libraries by
// their -l names.
pub const link_group = ['gcc', 'gcc_eh']

// support_dirs are the directories a toolchain keeps the objects that are
// neither a start file in the library directories nor a library a -l name
// finds: crtbeginS.o, crtbeginT.o, crtend.o and crtendS.o, and the libgcc
// archives a static link resolves unwinding against. They sit under one parent
// in a directory named after the toolchain's release, so the release
// directories are listed and searched newest first rather than a release being
// named here.
pub fn support_dirs(machine string, system string) []string {
	return match machine {
		'x86_64' {
			mut dirs := []string{}
			for parent in release_parents(machine, system) {
				dirs << release_dirs(parent)
			}
			dirs
		}
		else {
			[]string{}
		}
	}
}

// release_parents are the directories whose subdirectories are toolchain
// releases. The name of one is a target triple, and the vendor in the middle of
// a triple is the distribution's word for itself, which is why the machine at
// the front and the system at the back are what it is matched by rather than a
// whole name being written here.
fn release_parents(machine string, system string) []string {
	root := '/usr/lib/gcc'
	if !os.is_dir(root) {
		return []string{}
	}
	mut found := []string{}
	for entry in os.ls(root) or { []string{} } {
		path := os.join_path(root, entry)
		if os.is_dir(path) && entry.starts_with('${machine}-') && entry.ends_with('-${system}-gnu') {
			found << path
		}
	}
	return found
}

// release_dirs lists the release directories under one parent, newest first.
// The name of one is the release number and nothing else, and when more than
// one release is installed the newest is the one a build picks by default.
fn release_dirs(parent string) []string {
	if !os.is_dir(parent) {
		return []string{}
	}
	mut found := []string{}
	for entry in os.ls(parent) or { []string{} } {
		path := os.join_path(parent, entry)
		if os.is_dir(path) {
			found << path
		}
	}
	found.sort_with_compare(fn (a &string, b &string) int {
		left := release_number(os.base(*a))
		right := release_number(os.base(*b))
		if left == right {
			return 0
		}
		return if left > right { -1 } else { 1 }
	})
	return found
}

// release_number is the number a release directory is named after, and 0 for a
// name that carries none, which sorts that directory last.
fn release_number(name string) int {
	mut end := 0
	for end < name.len && name[end] >= `0` && name[end] <= `9` {
		end++
	}
	if end == 0 {
		return 0
	}
	return name[..end].int()
}

// Syscall is a kernel entry point: what a compiler can call it, the number the
// kernel expects in the number register, and the registers its arguments arrive
// in, in order.
pub struct Syscall {
pub:
	name   string
	number u32
	args   []string
}

// syscalls is this system's entry points for one machine. The numbers are per
// system and per machine both: Linux numbers read, write and exit differently on
// every architecture it runs on, so they cannot live with the machine.
pub fn syscalls(machine string) []Syscall {
	return match machine {
		'x86_64' {
			[
				Syscall{ name: 'read', number: 0, args: ['rdi', 'rsi', 'rdx'] },
				Syscall{ name: 'write', number: 1, args: ['rdi', 'rsi', 'rdx'] },
				Syscall{ name: 'exit', number: 60, args: ['rdi'] },
				Syscall{ name: 'exit_group', number: 231, args: ['rdi'] },
			]
		}
		else {
			[]Syscall{}
		}
	}
}

// syscall_args_regs is where the kernel takes arguments, in order. It is not the
// function call convention: on x86-64 the fourth syscall argument is in r10,
// where a function call would put it in rcx, because the trap instruction
// overwrites rcx on its way in.
pub fn syscall_args_regs(machine string) []string {
	return match machine {
		'x86_64' { ['rdi', 'rsi', 'rdx', 'r10', 'r8', 'r9'] }
		else { []string{} }
	}
}

// exit_syscall is the entry point that ends the process. Which one it is can
// change: exit_group ends every thread, which is what a program that started
// alone means by exit.
pub const exit_syscall = 'exit'

// interpreter is the dynamic loader the kernel hands a program to when the
// program names one. A shared library is not mapped by the kernel and ld.so is
// not something a program can call before it exists: the path is the one link
// between an image and the library it runs against.
pub const interpreter = '/lib64/ld-linux-x86-64.so.2'

// page_size is the alignment a loadable segment needs. load_base is where the
// first one is mapped, and it is a system's number because the kernel is what
// decides how low a program may be loaded.
pub const page_size = u64(0x1000)
pub const load_base = u64(0x400000)

// library_dirs is where a library named with -l is looked for when -L says
// nothing, in the order they are searched. Which directories a system keeps its
// shared libraries in is a fact about that system, so the list is here and not
// in the emitter that needs it.
//
// The architecture-and-system directory in the middle is the layout Debian and
// its relatives use; on a machine without that split the path is not there and
// the search moves past it. The names are per machine for the same reason the
// syscalls are: a library built for another machine would not run here.
pub fn library_dirs(machine string, system string) []string {
	return match machine {
		'x86_64' { ['/usr/local/lib', '/usr/lib/${machine}-${system}-gnu', '/usr/lib', '/lib'] }
		else { []string{} }
	}
}
