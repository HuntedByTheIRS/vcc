module cli

import optimizer
import os

// version is the compiler's own version. The output of `--version` is not
// decoration: V asks a C compiler for its version to decide what it is talking
// to and keys cached build artifacts on the answer.
pub const version = '0.0.1'

pub fn version_line() string {
	return 'vcc ${version} (pure V, stub)'
}

// Options is the command line after it has been read, in the terms the rest of
// the compiler uses.
//
// Flags this stub cannot honor are recorded rather than refused. V passes a
// compiler flags for features it expects to be there (-bt25 and the -Wl,
// passthroughs among them), and a compiler that errors on one of them fails a
// build it was supposed to serve.
pub struct Options {
pub mut:
	inputs       []string
	output       string
	run_args     []string
	include_dirs []string
	library_dirs []string
	libraries    []string
	defines      []string
	undefines    []string
	target       string
	standard     string
	input_type   string
	compile_only bool
	preprocess   bool
	// print_ast stops after the tree is built: nothing is emitted and nothing is
	// written, which is what `-print-ast` is for.
	print_ast        bool
	run              bool
	show_help        bool
	show_help_all    bool
	show_version     bool
	show_paths       bool
	bench            bool
	debug            bool
	inhibit_warnings bool
	// optimization is the -O level and the builtin settings, which belong to the
	// optimizer: it owns the flag list for both, and this file only hands the
	// arguments over.
	optimization optimizer.Options
	// ignored holds every flag that was accepted and not acted on, so a verbose
	// mode can say what was passed over instead of implying it worked.
	ignored []string
}

// Phase is one stage of a compilation with the time it took, which is what
// `-bench` prints.
pub struct Phase {
pub:
	name   string
	micros i64
}

// Cursor walks the arguments. It exists because V has no mutable scalar
// parameters, and a flag that takes a value has to move the reader past it.
struct Cursor {
mut:
	args []string
	pos  int
}

fn (c Cursor) at_end() bool {
	return c.pos >= c.args.len
}

fn (mut c Cursor) next() string {
	arg := c.args[c.pos]
	c.pos++
	return arg
}

// value_of returns the value of the flag the cursor sits on, whether it was
// written joined to the flag or as the next word: `-Idir` and `-I dir` mean the
// same thing to every C compiler, and V writes the joined form. The cursor has
// already moved past the flag when this is called, so the value is what it points
// at now.
fn (mut c Cursor) value_of(joined string) !string {
	if joined != '' {
		return joined
	}
	if c.pos >= c.args.len {
		return error('${c.args[c.pos - 1]} needs a value')
	}
	value := c.args[c.pos]
	c.pos++
	return value
}

// parse reads a command line in the shape tcc uses.
pub fn parse(args []string) !Options {
	expanded := expand_list_files(args)!
	mut opts := Options{
		optimization: optimizer.default_options()
	}
	mut optimization := opts.optimization
	mut positional := []string{}
	mut end_of_flags := false
	mut cursor := Cursor{
		args: expanded
	}
	for !cursor.at_end() {
		arg := cursor.next()
		if end_of_flags {
			positional << arg
			continue
		}
		if arg == '--' {
			end_of_flags = true
			continue
		}
		if arg == '-' || !arg.starts_with('-') {
			positional << arg
			continue
		}
		if arg == '--version' || arg == '-v' {
			opts.show_version = true
		} else if arg == '-vv' {
			opts.show_paths = true
		} else if arg == '-h' {
			opts.show_help = true
		} else if arg == '-hh' {
			opts.show_help_all = true
		} else if arg == '-c' {
			opts.compile_only = true
		} else if arg == '-E' {
			opts.preprocess = true
		} else if arg == '-print-ast' {
			opts.print_ast = true
		} else if arg == '-run' {
			opts.run = true
		} else if arg == '-bench' {
			opts.bench = true
		} else if arg == '-w' {
			opts.inhibit_warnings = true
		} else if arg == '-g' {
			opts.debug = true
		} else if arg == '-o' {
			opts.output = cursor.value_of('')!
		} else if arg.starts_with('-o') {
			opts.output = arg[2..]
		} else if arg == '-I' {
			opts.include_dirs << cursor.value_of('')!
		} else if arg.starts_with('-I') {
			opts.include_dirs << arg[2..]
		} else if arg == '-D' {
			opts.defines << cursor.value_of('')!
		} else if arg.starts_with('-D') {
			opts.defines << arg[2..]
		} else if arg == '-U' {
			opts.undefines << cursor.value_of('')!
		} else if arg.starts_with('-U') {
			opts.undefines << arg[2..]
		} else if arg == '-L' {
			opts.library_dirs << cursor.value_of('')!
		} else if arg.starts_with('-L') {
			opts.library_dirs << arg[2..]
		} else if arg == '-l' {
			opts.libraries << cursor.value_of('')!
		} else if arg.starts_with('-l') {
			opts.libraries << arg[2..]
		} else if arg == '-target' || arg == '--target' {
			opts.target = cursor.value_of('')!
		} else if arg.starts_with('--target=') {
			opts.target = arg[9..]
		} else if arg.starts_with('-std=') {
			opts.standard = arg[5..]
		} else if arg == '-x' {
			opts.input_type = cursor.value_of('')!
		} else if arg == '-MF' || arg == '-B' {
			opts.ignored << '${arg} ${cursor.value_of('')!}'
		} else if optimization.accept_flag(arg) {
			// The optimizer recognized it: -O levels and the -f(no-)builtin
			// spellings. Nothing to do here beyond not recording it as ignored.
		} else {
			// Everything else is accepted and recorded. The list of what V
			// actually passes is in README.md under "What a drop-in has to
			// satisfy"; each of those lands here until the milestone that
			// honors it.
			opts.ignored << arg
		}
	}
	opts.optimization = optimization
	if opts.run && positional.len > 0 {
		opts.inputs = [positional[0]]
		opts.run_args = positional[1..]
	} else {
		opts.inputs = positional
	}
	return opts
}

// expand_list_files splices the contents of an @file argument in place, so a
// long command line can live in a file. Words are split on whitespace; there is
// no quoting inside a list file yet.
fn expand_list_files(args []string) ![]string {
	mut out := []string{}
	for arg in args {
		if !arg.starts_with('@') || arg.len == 1 {
			out << arg
			continue
		}
		path := arg[1..]
		text := os.read_file(path) or { return error('cannot read the argument list ${path}') }
		for word in text.fields() {
			out << word
		}
	}
	return out
}

// bench_lines renders the per-phase timings `-bench` prints.
pub fn bench_lines(phases []Phase) []string {
	mut out := []string{}
	for phase in phases {
		out << 'bench ${phase.name}: ${phase.micros}us'
	}
	return out
}

// usage is the text `-h` prints, and `-hh` adds the part about what a compiler
// in this position is asked to accept.
pub fn usage(all bool) string {
	mut out := []string{}
	out << 'Usage: vcc [options...] [-o outfile] infile.c'
	out << ''
	out << 'A C compiler written in V, meant to replace the tcc that V vendors in'
	out << 'thirdparty/tcc. Status: a stub. It compiles a function that returns a'
	out << 'constant, and says so for everything else.'
	out << ''
	out << 'General options:'
	out << '  -o outfile    set the output filename (default a.out)'
	out << '  -run          compile to a temporary file and run it'
	out << '  -c            compile to an object file only (not implemented yet)'
	out << '  -E            print the token stream and stop'
	out << '  -print-ast    print the tree the emitter would be given, then stop'
	out << '  -bench        print per-phase timings'
	out << '  -v --version  show the version'
	out << '  -vv           show the version, the target and the include paths'
	out << '  -h -hh        show this, show more help'
	out << '  -w -g         accepted for compatibility; the stub warns about nothing'
	out << '  -O0 -O1 -O2 -O3 -Os   optimization level (default -O0)'
	out << '  -fno-builtin  do not compute calls to library functions the compiler knows'
	out << '  -fno-builtin-NAME  the same for one function'
	out << '  -Idir -Dname -Uname -Ldir -llib -std=version -x type -o outfile'
	if all {
		out << ''
		out << 'What a replacement for the bundled tcc is asked to accept, and what'
		out << 'this compiler does with each one today:'
		out << '  -std=gnu11 -std=c99   recorded, the standard is fixed for now'
		out << '  -fwrapv -fPIC -w -g   accepted and ignored'
		out << '  -Werror=name          accepted and ignored'
		out << '  -Btcc -Idir -Ldir     accepted; -I and -L paths are recorded, -B is not used yet'
		out << '  -bt25 -Wl,...         accepted and ignored, as a non-tcc compiler must'
		out << '  -print-ast            nothing is written and nothing is linked; the dump is'
		out << '                        the tree after the optimizer, which is what the emitter'
		out << '                        would see'
		out << '  -O<level>             -O0 through -O3, and -Os; every level is recorded,'
		out << '                        and -O1 upwards turns on the passes that exist'
		out << '  -fno-builtin          calls to abs and friends stay calls; the reserved'
		out << '                        __builtin_ spellings still fold'
		out << '  -DGC_THREADS=1 ...    recorded; nothing is preprocessed yet'
		out << '  @listfile             expanded before anything else'
		out << '  -                     read the source from standard input'
		out << 'The V toolchain also hands the compiler its own GC library,'
		out << 'thirdparty/tcc/lib/libgc.a, as an ordinary input. It is accepted and'
		out << 'not linked yet, like any other archive.'
	}
	return out.join('\n')
}
