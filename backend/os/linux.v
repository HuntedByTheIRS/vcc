module os

// Linux, described where it adds something to a bare machine: the kernel entry
// points a program can call, the registers their arguments arrive in, and the
// numbers the loader and the container format are defined by.
//
// A system does not know which machine it is running on, so everything that
// depends on the architecture is asked for by name and answered per architecture.
// A second system is another file in this directory, and it does not need the
// machine's file to exist to be written.

pub const name = 'linux'

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
