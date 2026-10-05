module cli

import diagnostics
import extensions
import optimizer
import os
import preprocess
import standard
import v.vmod

// version is the compiler's own version, the one v.mod names. v.mod is the
// single source: this constant is what --version prints, what __VCC_VERSION__
// carries into a program, and what the release workflow names a release after.
// The text is embedded in the binary when this module is compiled (`@VMOD_FILE`),
// so nothing reads v.mod when the compiler runs and a binary copied somewhere
// without its source still answers. The answer is not decoration: V asks a C
// compiler for its version to decide what it is talking to and keys cached build
// artifacts on it.
pub const version = vmod_version()

// vmod_version picks the version out of the v.mod text the build embedded. A
// v.mod that does not parse, or one that names no version, stops the run rather
// than answering with an empty string.
fn vmod_version() string {
	manifest := vmod.decode(@VMOD_FILE) or { panic('v.mod is not readable: ${err}') }
	if manifest.version == '' {
		panic('v.mod names no version')
	}
	return manifest.version
}

pub fn version_line() string {
	return 'vcc ${version} (pure V)'
}

// Options is the command line after it has been read, in the terms the rest of
// the compiler uses.
//
// Flags this compiler cannot honor are recorded rather than refused. V passes a
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
	standard string
	dialect  standard.Mode
	// emulation is -femulation: the compiler whose own identity macros this
	// compiler defines in place of its own, so that a program branching on
	// __GNUC__, __clang__ or __TINYC__ sees the compiler the flag names.
	emulation preprocess.Emulation
	// external_linker is -external-linker: a program on PATH that performs the
	// final link in place of this compiler's own emitter path, so that the
	// inputs it cannot consume yet — a relocatable object, an archive — can be
	// linked before an in-house linker exists. An empty name is the flag unset,
	// which is every behaviour exactly as it was. The name is a command-line
	// fact; whether it may be used at all is policy, and it is refused where the
	// flag is read.
	external_linker string
	input_type      string
	compile_only    bool
	// shared is -shared: the link writes a shared object another program loads
	// rather than a program the kernel starts. It is a kind of link and not a
	// kind of compilation, so it says nothing about a run that stops before a
	// link, which is what -c does.
	shared bool
	// pic is -fPIC/-fpic: the object a compile writes reaches every top-level
	// object another object may define through the global offset table rather
	// than through a direct reference, which is what lets the object be linked
	// into a shared object. -fno-pic and -fno-PIC turn it off again. It is a
	// fact about a relocatable object, so it says nothing about the program the
	// path with no -c and no linker writes: that image has every address
	// settled here and a direct reference is what it uses. -fPIE and -fpie are
	// not read: PIE names an executable, which is not a shape this compiler
	// writes, so those spellings stay in `ignored` like the rest of the -f
	// family it cannot honor.
	pic bool
	// static_link is -static: the link resolves every library into the file
	// rather than leaving the loader to map it, and the program that comes out
	// names no loader and no library.
	static_link bool
	preprocess  bool
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
	// The -print- family asks the compiler a question and stops, which is how a
	// build tool finds out where the compiler's files are without compiling
	// anything. Each records the question rather than answering it: the answers
	// need the target and the system's directories, which this module does not
	// read, so the driver gathers them and this file only holds the flag surface.
	// A value flag keeps its own "was it given" bit because an empty name is a
	// question too.
	print_search_dirs            bool
	print_libgcc_file_name       bool
	print_file_name              string
	print_file_name_given        bool
	print_prog_name              string
	print_prog_name_given        bool
	print_multiarch              bool
	print_multi_directory        bool
	print_multi_lib              bool
	print_multi_os_directory     bool
	print_sysroot                bool
	print_sysroot_headers_suffix bool
	// verbose is -verbose: report what the compiler is doing in detail. gcc
	// spells this -v, which is already the version here (as it is in tcc, whose
	// command line this one keeps), so the long spelling is the free one. It
	// writes to stderr so that it cannot corrupt a -E or a -print- answer.
	verbose bool
	// inhibit_warnings is -w: the one boolean a caller that only wants "was -w
	// given" reads. What the warning flags actually decide is per class, which
	// is what the policy below is for, and this is that policy's suppress.
	inhibit_warnings bool
	// warnings is the policy the diagnostic flags built, in the order they were
	// written: which class is reported, which is promoted to an error, and which
	// -w silenced. The classes are diagnostics.Class.
	warnings diagnostics.Policy
	// vcc_extensions is the extension state the -fvcc-exts= flags built. Every
	// extension is off unless it was named.
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
		} else if arg == '-shared' {
			// -shared is a link option: which file comes out, not how the
			// source is read. -c stops before a link, so the two do not
			// conflict and a run with both writes an object.
			opts.shared = true
		} else if arg == '-static' {
			opts.static_link = true
		} else if arg == '-E' {
			opts.preprocess = true
		} else if arg == '-print-ast' {
			opts.print_ast = true
		} else if arg == '-run' {
			opts.run = true
		} else if arg == '-bench' {
			opts.bench = true
		} else if arg == '-print-search-dirs' {
			opts.print_search_dirs = true
		} else if arg == '-print-libgcc-file-name' {
			opts.print_libgcc_file_name = true
		} else if arg.starts_with('-print-file-name=') {
			opts.print_file_name = arg['-print-file-name='.len..]
			opts.print_file_name_given = true
		} else if arg.starts_with('-print-prog-name=') {
			opts.print_prog_name = arg['-print-prog-name='.len..]
			opts.print_prog_name_given = true
		} else if arg == '-print-multiarch' {
			opts.print_multiarch = true
		} else if arg == '-print-multi-directory' {
			opts.print_multi_directory = true
		} else if arg == '-print-multi-lib' {
			opts.print_multi_lib = true
		} else if arg == '-print-multi-os-directory' {
			opts.print_multi_os_directory = true
		} else if arg == '-print-sysroot' {
			opts.print_sysroot = true
		} else if arg == '-print-sysroot-headers-suffix' {
			opts.print_sysroot_headers_suffix = true
		} else if arg == '-verbose' {
			opts.verbose = true
		} else if opts.warnings.accept(arg) {
			// The diagnostic policy took the flag: -w, -W<class>, -Wno-<class>,
			// -Werror=<class>, -pedantic or -pedantic-errors. A -W spelling about
			// something this compiler does not classify is not taken here and
			// falls through to the recorded list, which is what keeps -Wl,... and
			// -Werror=implicit-function-declaration accepted by a compiler that
			// acts on neither.
			opts.inhibit_warnings = opts.warnings.suppress
		} else if arg.starts_with('-fvcc-exts=') || arg.starts_with('-fno-vcc-exts=') {
			// The family is read here and the names are looked up in
			// `extensions/`, which reads them from the standard table, because
			// the spellings are a command-line fact and what a name means is
			// not. A name this compiler does not have is an error, since naming
			// an extension is a request; a name it has is recorded.
			opts.vcc_extensions.accept(arg)!
		} else if arg == '-g' {
			opts.debug = true
		} else if arg == '-fPIC' || arg == '-fpic' {
			// The two spellings gcc offers for the same thing. Read rather than
			// recorded: a build that passes -fPIC and gets an object a shared
			// link refuses has been told nothing by a flag that landed in a
			// list. -fno-pic and -fno-PIC are the other half of the pair, so a
			// build can turn it back off.
			opts.pic = true
		} else if arg == '-fno-pic' || arg == '-fno-PIC' {
			opts.pic = false
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
		} else if arg == '-femulation' {
			opts.emulation = preprocess.emulation_from_spelling(cursor.value_of('')!)!
		} else if arg.starts_with('-femulation=') {
			opts.emulation = preprocess.emulation_from_spelling(arg[12..])!
		} else if arg == '-external-linker' {
			// The value is a program name and not this compiler's own feature,
			// so the flag is not spelled -f: the -f spelling is the feature
			// family (-fno-builtin, -fvcc-exts), and linking is not a feature
			// of the C the program is in. It is read and never recorded, so a
			// build cannot pass it and be told later that nothing happened.
			opts.external_linker = cursor.value_of('')!
		} else if arg.starts_with('-external-linker=') {
			opts.external_linker = arg['-external-linker='.len..]
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

// asks_query says whether a -print- flag was written, which is what makes the
// run a question rather than a compile: it answers and stops, so it needs no
// input file and a build tool can ask it before it has one.
pub fn (opts Options) asks_query() bool {
	return opts.print_search_dirs || opts.print_libgcc_file_name
		|| opts.print_file_name_given || opts.print_prog_name_given
		|| opts.print_multiarch || opts.print_multi_directory || opts.print_multi_lib
		|| opts.print_multi_os_directory || opts.print_sysroot
		|| opts.print_sysroot_headers_suffix
}

// links says whether this run reaches a link. A run that stops earlier has
// nothing for a linker to do, and each of those is an option here rather than a
// list of flag names compared where the question is asked: -c writes a
// relocatable object, -E, -M, -MD and -dM answer a question about the source,
// -print-ast dumps the tree, and a -print- query answers before an input is
// read. It is what the two places that decide whether to link ask.
pub fn (opts Options) links() bool {
	return !opts.compile_only && !opts.preprocess && !opts.print_ast && !opts.dump_macros
		&& !opts.deps && !opts.asks_query()
}

// link_kind_conflict_refusal is the message for a command line that gives both
// of the flags naming a kind of link, and none when it gives at most one. The
// two ask for different files: a shared object is loaded by a program that names
// it, and a static program is started by the kernel with its libraries inside
// it, so no single link is both and the other flag would be dropped in silence.
pub fn (opts Options) link_kind_conflict_refusal() ?string {
	if opts.shared && opts.static_link {
		return '-shared and -static ask for different links: a shared object is loaded by a program that names it, and a static program is started with its libraries inside it'
	}
	return none
}

// in_house_link_refusal is the message for a command line whose kind of link the
// path with no linker does not write, and none when it writes it: that path
// writes a program, linked against the shared C library, so a shared object and
// a static program are both refused by name and the message says what would
// write them. A run that stops before a link is not one of these, because
// neither flag has anything to decide about a run that never reaches one, and
// neither is a plain run, which is the program this path writes.
pub fn (opts Options) in_house_link_refusal() ?string {
	if !opts.links() {
		return none
	}
	if conflict := opts.link_kind_conflict_refusal() {
		return conflict
	}
	if opts.shared {
		return '-shared needs -external-linker=NAME: this compiler writes a program linked against the shared C library, and a linker is what writes the shared object'
	}
	if opts.static_link {
		return '-static needs -external-linker=NAME: this compiler writes a program linked against the shared C library, and a linker is what resolves the libraries into the file'
	}
	return none
}

// search_dirs_text renders `-print-search-dirs` in the shape gcc uses: where the
// compiler is, where its helper programs are looked for, and where its libraries
// are looked for. gcc names its private install tree and its cc1/as/collect2
// directories; this compiler is one binary that runs no program, so the caller
// passes the directory the binary is in and no program directories, and the
// libraries are the ones the linker really searches.
pub fn search_dirs_text(install string, program_dirs []string, library_dirs []string) string {
	mut out := []string{}
	out << 'install: ${install}'
	out << 'programs: =${program_dirs.join(':')}'
	out << 'libraries: =${library_dirs.join(':')}'
	return out.join('\n')
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
	out << 'thirdparty/tcc. It compiles a subset of C to a Linux x86-64 executable and'
	out << 'refuses the rest with a diagnostic naming the construct and its location.'
	out << ''
	out << 'General options:'
	out << '  -o outfile    set the output filename (default a.out)'
	out << '  -run          compile to a temporary file and run it'
	out << '  -c            compile to an object file only, without linking'
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
	out << '  -fPIC -fpic   position-independent code for a relocatable object: a'
	out << '                top-level object another object may define is reached'
	out << '                through the global offset table, so the object links into'
	out << '                a shared object; -fno-pic turns it back off'
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
	out << '  -std=version  -std version   the dialect: the spelling selects the mode'
	out << '                the construct table is checked against (c89 through c29'
	out << '                and the gnu dialects of each); a spelling this compiler'
	out << '                does not implement is recorded and never refused'
	out << '  -Wpedantic -pedantic      report what the selected dialect forbids'
	out << '  -pedantic-errors          the same as an error (-Werror=pedantic too)'
	out << '  -Wclass -Wno-class        one class of diagnostic, on or off: the last'
	out << '                            mention of a class on the line is the one that'
	out << '                            counts'
	out << '  -fvcc-exts=NAME[,NAME]    turn vendor extensions on: a list of names,'
	out << '  -fvcc-exts=all            or every name the compiler has'
	out << '  -fno-vcc-exts=NAME        turn one off again'
	out << '  -fno-vcc-exts=all         or all of them'
	out << '  -femulation=NAME  define the identity macros of NAME (gcc, clang or'
	out << '                    tcc) in place of the ones this compiler invented'
	out << '  -external-linker=NAME  hand the final link to NAME, a linker found on'
	out << '                    PATH. This compiler compiles each .c input with its'
	out << '                    own -c machinery, then NAME links those objects and'
	out << '                    the inputs it cannot read: a relocatable object, an'
	out << '                    archive. NAME must not be a C compiler (cc, gcc,'
	out << '                    clang, c++, tcc); name ld or lld instead. A run that'
	out << '                    stops before a link (-c, -E, -M, -MD, -dM,'
	out << '                    -print-ast) has nothing for NAME to do and the flag'
	out << '                    goes unused. With the flag unset every input is'
	out << '                    refused exactly as before'
	out << '  -shared               what the link writes: a shared object another'
	out << '                        program loads, with no entry point and no loader'
	out << '  -static               a program with every library resolved into itself'
	out << '                        and no loader named in it'
	out << '                        both are work a linker does here: without'
	out << '                        -external-linker=NAME each is refused by name'
	out << '                        rather than written as a program'
	out << ''
	out << 'Query options, which answer a question and stop without compiling (gcc'
	out << 'spells these the same way; each needs no input file and exits 0):'
	out << '  -print-search-dirs        the directories searched for programs and libraries'
	out << '  -print-file-name=NAME     the file NAME resolves to, or NAME unchanged when'
	out << '                            the search does not have it'
	out << '  -print-libgcc-file-name   the libgcc.a the search has, or the name when it has'
	out << '                            none: this compiler links no libgcc'
	out << '  -print-prog-name=NAME     the program NAME; this compiler runs no external'
	out << '                            program, so the name comes back unchanged'
	out << '  -print-multiarch          the target multiarch tuple'
	out << '  -print-multi-directory    the subdirectory of the variant compiled: .'
	out << '  -print-multi-lib          the variant and its options: .;'
	out << '  -print-multi-os-directory the system library directory relative to this'
	out << '                            compiler: .'
	out << '  -print-sysroot            the sysroot: empty, this compiler uses the host'
	out << '  -print-sysroot-headers-suffix  the headers suffix: empty, as the sysroot is'
	out << '  -verbose                  report the phases, the files read, the search'
	out << '                            paths and the libraries resolved to stderr,'
	out << '                            without changing what is compiled'
	if all {
		out << ''
		out << 'What a replacement for the bundled tcc is asked to accept, and what'
		out << 'this compiler does with each one today:'
		out << '  -std=gnu11 -std c99   both spellings; the spelling selects a dialect mode,'
		out << '                        and one this compiler does not implement is recorded,'
		out << '                        never refused'
		out << '  -Wpedantic -pedantic   the constructs the selected dialect does not allow,'
		out << '                        in vcc words; -pedantic-errors and -Werror=pedantic'
		out << '                        make them errors and -w or -Wno-pedantic silence them'
		out << '  -fvcc-exts=NAME[,NAME]  turn the vendor extensions on, per name'
		out << '  -fvcc-exts=all          or every name the compiler has'
		out << '  -fno-vcc-exts=NAME      turn one off again'
		out << '  -fno-vcc-exts=all       or all of them'
		out << '  the names are ${extensions.names().join(', ')}'
		out << '  -fPIC -fpic -fno-pic  the addressing of a relocatable object: a'
		out << '                        top-level object another object may define is'
		out << '                        reached through the global offset table when'
		out << '                        this is on, and through a direct reference'
		out << '                        when it is off. It is a fact about an object,'
		out << '                        so the program this compiler writes itself is'
		out << '                        unchanged. -fPIE and -fpie are accepted and'
		out << '                        ignored: they name an executable, which is not'
		out << '                        a shape this compiler writes'
		out << '  -fwrapv -g            accepted and ignored'
		out << '  -Werror=name          accepted and ignored, except the classes above'
		out << '  -Btcc -Idir          accepted; -I directories are searched for headers,'
		out << '                        -B is not used yet'
		out << '  -Ldir -llib           -L directories are searched for a -l name, and the'
		out << '                        library that is found is named in the image, which is'
		out << '                        what makes its symbols resolve when the program loads'
		out << '  -bt25 -Wl,...         accepted and ignored, as a non-tcc compiler must'
		out << '  -print-ast            nothing is written and nothing is linked; the dump is'
		out << '                        the tree after the optimizer, which is what the emitter'
		out << '                        would see'
		out << '  -print-* queries      print where a file, a program, the sysroot or the'
		out << '                        library search directories are, and stop without'
		out << '                        compiling anything; gcc spells these the same way'
		out << '  -verbose              report what the compiler did to stderr without'
		out << '                        changing what it compiled'
		out << '  -O<level>             -O0 through -O3, and -Os; every level is recorded,'
		out << '                        and -O1 upwards turns on the passes that exist'
		out << '  -fno-builtin          calls to abs and friends stay calls; the reserved'
		out << '                        __builtin_ spellings still fold'
		out << '  -Dname=value -Uname  in force before the source is read, as if written'
		out << '                        above it as #define and #undef'
		out << '  @listfile             expanded before anything else'
		out << '  -                     read the source from standard input'
		out << 'The V toolchain also hands the compiler its own GC library,'
		out << 'thirdparty/tcc/lib/libgc.a, as an ordinary input. An object or an'
		out << 'archive is named as such and refused; linking one is not implemented'
		out << 'yet, and neither is reading one as source. -external-linker=NAME is'
		out << 'the one answer to that: it hands the link, objects and archives'
		out << 'included, to a linker the system already has.'
	}
	return out.join('\n')
}
