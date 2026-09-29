module cli

import diagnostics
import extensions
import optimizer
import os
import preprocess
import standard

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
	// nostdinc is -nostdinc: do not look in the standard directories at all,
	// which is what a build says when it is compiling against a C library that
	// is not the one the machine's headers describe.
	nostdinc     bool
	library_dirs []string
	libraries    []string
	defines      []string
	undefines    []string
	target       string
	// standard is the -std= spelling as it was written, and dialect is the mode
	// that spelling names. Both are kept because both are asked for: the
	// spelling is what the command line, a verbose mode and a build compare
	// against, and the mode is what the rest of the compiler asks its questions
	// of. Every spelling has a mode, including the ones this compiler does not
	// implement, because a spelling that stops a build is worse than a flag
	// that does nothing.
	standard     string
	dialect      standard.Mode
	input_type   string
	compile_only bool
	preprocess   bool
	// print_ast stops after the tree is built: nothing is emitted and nothing is
	// written, which is what `-print-ast` is for.
	print_ast     bool
	run           bool
	show_help     bool
	show_help_all bool
	show_version  bool
	show_paths    bool
	bench         bool
	debug         bool
	// inhibit_warnings is -w: the one boolean a caller that only wants "was -w
	// given" reads. What the warning flags actually decide is per class, which
	// is what the policy below is for, and this is that policy's suppress.
	inhibit_warnings bool
	// warnings is the policy the diagnostic flags built, in the order they were
	// written: which class is reported, which is promoted to an error, and which
	// -w silenced. The classes are diagnostics.Class.
	warnings diagnostics.Policy
	// vcc_extensions is the extension state the -fvcc-exts= flags built. Every
	// extension is off unless it was named, and none is honored yet.
	vcc_extensions extensions.Options
	// preludes are the -include and -imacros files in the order they were
	// given: read before the source is, as if their lines were the first lines
	// of it, with the flag deciding whether their text is kept.
	preludes []preprocess.Prelude
	// undef_builtins is -undef: the macros that describe the target are not
	// defined, which is what a build asks for when it wants to compile for a
	// target this compiler does not describe.
	undef_builtins bool
	// dump_macros is -dM: print what is defined when the read ends.
	dump_macros bool
	// deps asks for the make-style rule listing what the file is made of.
	// deps_system decides whether the headers that came from the standard
	// directories are in it, deps_file says where it is written, and
	// deps_compile says the compile goes on afterwards — -M and -MM stop at
	// the rule, -MD and -MMD write it and keep going. deps_target is the name
	// the rule is for, when -MT or -MQ gives one.
	deps         bool
	deps_system  bool
	deps_file    string
	deps_compile bool
	deps_target  string
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
		} else if opts.warnings.accept(arg) {
			// The diagnostic policy took the flag: -w, -W<class>, -Wno-<class>,
			// -Werror=<class>, -pedantic or -pedantic-errors. A -W spelling about
			// something this compiler does not classify is not taken here and
			// falls through to the recorded list, which is what keeps -Wl,... and
			// -Werror=implicit-function-declaration accepted by a compiler that
			// acts on neither.
			opts.inhibit_warnings = opts.warnings.suppress
		} else if arg.starts_with('-fvcc-exts=') || arg.starts_with('-fno-vcc-exts=') {
			// The family is read here and the registry is consulted in
			// `extensions/`, because the spellings are a command-line fact and
			// what a name means is not. A name this compiler does not have is an
			// error, since naming an extension is a request; a name it has is
			// recorded and changes nothing, because none is honored yet.
			opts.vcc_extensions.accept(arg)!
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
		} else if arg == '-nostdinc' {
			opts.nostdinc = true
		} else if arg == '-undef' {
			opts.undef_builtins = true
		} else if arg == '-dM' {
			opts.dump_macros = true
		} else if arg == '-M' {
			opts.deps = true
			opts.deps_system = true
		} else if arg == '-MM' {
			opts.deps = true
		} else if arg == '-MD' {
			// The spelling a build tool reaches for: the rule is written and
			// the compile goes on, so one command line does both.
			opts.deps = true
			opts.deps_system = true
			opts.deps_compile = true
		} else if arg == '-MMD' {
			opts.deps = true
			opts.deps_compile = true
		} else if arg == '-MT' || arg == '-MQ' {
			// The target the rule is for, when the build knows a better name
			// than the object file's. -MQ is gcc's spelling for the same
			// question asked with make's quoting in mind; the quoting happens
			// where the rule is written, for both of them.
			opts.deps_target = cursor.value_of('')!
		} else if arg == '-MF' {
			opts.deps_file = cursor.value_of('')!
		} else if arg.starts_with('-MF') {
			opts.deps_file = arg[3..]
		} else if arg == '-include' {
			opts.preludes << preprocess.Prelude{
				path: cursor.value_of('')!
			}
		} else if arg == '-imacros' {
			opts.preludes << preprocess.Prelude{
				path:        cursor.value_of('')!
				macros_only: true
			}
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
		} else if arg == '-std' {
			// Both spellings, because V writes -std=gnu11 and a person writes
			// -std gnu11, and a compiler that takes one of them turns the other
			// into an input file named gnu11. The spelling is recorded as written
			// and the mode is what it names; a spelling this compiler does not
			// implement is a mode like any other and not a failure.
			opts.standard = cursor.value_of('')!
			opts.dialect = standard.from_spelling(opts.standard)
		} else if arg.starts_with('-std=') {
			opts.standard = arg[5..]
			opts.dialect = standard.from_spelling(opts.standard)
		} else if arg == '-x' {
			opts.input_type = cursor.value_of('')!
		} else if arg == '-B' {
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
	out << '  -E            preprocess and print the token stream, then stop'
	out << '  -print-ast    print the tree the emitter would be given, then stop'
	out << '  -bench        print per-phase timings'
	out << '  -v --version  show the version'
	out << '  -vv           show the version, the target, the mode, the extensions, the'
	out << '                recorded flags and the paths'
	out << '  -h -hh        show this, show more help'
	out << '  -w            do not print warnings, whatever asked for them'
	out << '  -O0 -O1 -O2 -O3 -Os   optimization level (default -O0)'
	out << '  -fno-builtin  do not compute calls to library functions the compiler knows'
	out << '  -fno-builtin-NAME  the same for one function'
	out << '  -Idir -Dname -Uname -Ldir -llib -x type -o outfile'
	out << '  -nostdinc     do not search the standard directories for headers'
	out << '  -M -MM        print a make rule for what the file needs instead of'
	out << '                compiling; -MM leaves the system headers out'
	out << '  -MD -MMD      write that rule and compile as well'
	out << '  -MF file      write that rule to a file instead of to the output'
	out << '  -MT -MQ name  the name the rule is for, when it is not the object'
	out << '  -include file read a file before the source, as if its lines were'
	out << '                the first lines of it'
	out << '  -imacros file read a file before the source for its macros only'
	out << '  -undef        do not define the macros that describe the target'
	out << '  -dM           print the macros that are defined when the read ends'
	out << '  -std=version  -std version   the dialect: c99 and gnu99 are the ones'
	out << '                this compiler honors, and every other spelling is'
	out << '                recorded and never refused'
	out << '  -Wpedantic -pedantic      report what the selected dialect forbids'
	out << '  -pedantic-errors          the same as an error (-Werror=pedantic too)'
	out << '  -Wclass -Wno-class        one class of diagnostic, on or off: the last'
	out << '                            mention of a class on the line is the one that'
	out << '                            counts'
	out << '  -fvcc-exts=NAME[,NAME]    turn vendor extensions on: a list of names,'
	out << '  -fvcc-exts=all            or every name the compiler has'
	out << '  -fno-vcc-exts=NAME        turn one off again'
	out << '  -fno-vcc-exts=all         or all of them'
	if all {
		out << ''
		out << 'What a replacement for the bundled tcc is asked to accept, and what'
		out << 'this compiler does with each one today:'
		out << '  -std=gnu11 -std c99   both spellings; c99 and gnu99 select the dialect,'
		out << '                        and every other spelling is recorded, never refused'
		out << '  -Wpedantic -pedantic   the constructs the selected dialect does not allow,'
		out << '                        in vcc words; -pedantic-errors and -Werror=pedantic'
		out << '                        make them errors and -w or -Wno-pedantic silence them'
		out << '  -fvcc-exts=NAME[,NAME]  turn the vendor extensions on, per name'
		out << '  -fvcc-exts=all          or every name the compiler has'
		out << '  -fno-vcc-exts=NAME      turn one off again'
		out << '  -fno-vcc-exts=all       or all of them; nothing is honored yet, so a'
		out << '                        name is recorded and changes no compile'
		out << '  -fwrapv -fPIC -g       accepted and ignored'
		out << '  -Werror=name          accepted and ignored, except the classes above'
		out << '  -Btcc -Idir -Ldir     accepted; -I directories are searched for headers,'
		out << '                        -L paths are recorded, -B is not used yet'
		out << '  -bt25 -Wl,...         accepted and ignored, as a non-tcc compiler must'
		out << '  -print-ast            nothing is written and nothing is linked; the dump is'
		out << '                        the tree after the optimizer, which is what the emitter'
		out << '                        would see'
		out << '  -O<level>             -O0 through -O3, and -Os; every level is recorded,'
		out << '                        and -O1 upwards turns on the passes that exist'
		out << '  -fno-builtin          calls to abs and friends stay calls; the reserved'
		out << '                        __builtin_ spellings still fold'
		out << '  -Dname=value -Uname  in force before the source is read, as if written'
		out << '                        above it as #define and #undef'
		out << '  @listfile             expanded before anything else'
		out << '  -                     read the source from standard input'
		out << 'The V toolchain also hands the compiler its own GC library,'
		out << 'thirdparty/tcc/lib/libgc.a, as an ordinary input. It is accepted and'
		out << 'not linked yet, like any other archive.'
	}
	return out.join('\n')
}
