module main

import backend
import cli
import codegen
import optimizer
import os
import parser
import preprocess
import printer
import time
import tokenize

// vcc: read a command line, run the pipeline over one source file, write the
// image. The stages are the modules named after them, and this file is only the
// wiring between them.
fn main() {
	opts := cli.parse(os.args[1..]) or {
		eprintln('vcc: ${err.msg()}')
		eprintln('')
		eprintln(cli.usage(false))
		exit(1)
	}
	if opts.show_help_all {
		println(cli.usage(true))
		return
	}
	if opts.show_help {
		println(cli.usage(false))
		return
	}
	if opts.show_version {
		println(cli.version_line())
		return
	}
	if opts.show_paths {
		println(cli.version_line())
		target := backend.host() or {
			println('target: none')
			return
		}
		println('target: ${target.name}')
		println('optimize: ${opts.optimization.summary()}')
		println('standard: ${standard_line(opts.standard)}')
		if opts.include_dirs.len == 0 {
			println('include: (the -I directories, none given)')
		}
		for dir in opts.include_dirs {
			println('include: ${dir}')
		}
		if opts.nostdinc {
			println('include: (the standard directories, which -nostdinc turns off)')
		} else {
			for dir in standard_include_dirs() {
				println('include: ${dir} (standard)')
			}
		}
		return
	}
	if opts.inputs.len == 0 {
		eprintln('vcc: no input files')
		eprintln('')
		eprintln(cli.usage(false))
		exit(1)
	}
	if opts.compile_only {
		abort('compiling to an object file (-c) is not implemented yet')
		return
	}
	if opts.inputs.len > 1 {
		abort('linking more than one input is not implemented yet')
		return
	}
	path := opts.inputs[0]
	source := read_source(path) or {
		abort('cannot read ${path}: ${err.msg()}')
		return
	}
	mut phases := []cli.Phase{}
	mut started := time.now()
	// Lexing happens inside the preprocessor, which is the stage that knows
	// which file it is reading and what to do with the directives it finds.
	processed := preprocess.preprocess(source, path, preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        opts.defines
		undefines:      opts.undefines
		standard_dirs:  if opts.nostdinc { []string{} } else { standard_include_dirs() }
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
	})
	phases << cli.Phase{
		name:   'preprocess'
		micros: time.since(started).microseconds()
	}
	// A warning is reported and the compile goes on; an error ends it. The
	// difference is asked of the diagnostics themselves rather than counted, so
	// that a stage which hands back a warning is not mistaken for a stage that
	// failed.
	report(path, processed.diagnostics, opts.inhibit_warnings)
	if tokenize.errors(processed.diagnostics).len > 0 {
		exit(1)
	}
	// -M and -dM answer a question about the read and stop there: a build tool
	// asking what a file is made of does not want an object file at the end of
	// its command line.
	if opts.deps {
		write_dependencies(path, processed.files, opts)
		return
	}
	if opts.dump_macros {
		print_macros(processed.macros)
		return
	}
	if opts.preprocess {
		print_tokens(processed.tokens)
		return
	}
	started = time.now()
	parsed := parser.parse(processed.tokens)
	phases << cli.Phase{
		name:   'parse'
		micros: time.since(started).microseconds()
	}
	report(path, parsed.diagnostics, opts.inhibit_warnings)
	if tokenize.errors(parsed.diagnostics).len > 0 {
		exit(1)
	}
	started = time.now()
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	phases << cli.Phase{
		name:   'opt'
		micros: time.since(started).microseconds()
	}
	if opts.print_ast {
		// The tree the emitter would be handed, which is the useful one to read
		// when a level is suspected of doing the wrong thing.
		println(printer.render(optimized))
		return
	}
	started = time.now()
	image := codegen.emit(optimized, codegen.Options{
		target: opts.target
		entry:  'main'
	})
	phases << cli.Phase{
		name:   'emit'
		micros: time.since(started).microseconds()
	}
	report(path, image.diagnostics, opts.inhibit_warnings)
	if tokenize.errors(image.diagnostics).len > 0 {
		exit(1)
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	write_image(out_path, image.bytes) or {
		abort('cannot write ${out_path}: ${err.msg()}')
		return
	}
	if opts.bench {
		for line in cli.bench_lines(phases) {
			eprintln(line)
		}
	}
	if opts.run {
		run_image(out_path, opts.run_args)
	}
}

// read_source takes the path or the source itself, so a pipeline that feeds the
// compiler on standard input works the way it does with tcc.
// standard_line reports what -std bought, which today is a record and nothing
// else: the subset this compiler accepts is the same one whatever is named, and
// claiming otherwise would be a promise the parser does not keep.
fn standard_line(standard string) string {
	if standard == '' {
		return '(none asked for; V passes -std=gnu11)'
	}
	return '${standard} (recorded; the accepted language does not change with it yet)'
}

fn read_source(path string) !string {
	if path == '-' {
		return os.get_raw_stdin().bytestr()
	}
	return os.read_file(path)
}

fn write_image(path string, bytes []u8) ! {
	os.write_file_array(path, bytes)!
	os.chmod(path, 0o755)!
}

// run_image runs what was just compiled and leaves with its exit status, which is
// what `-run` means: the compiler becomes the program it produced.
//
// The program is given the terminal rather than a pipe, because its output is
// the whole reason for running it: a captured stream would arrive after the
// program had finished, on the wrong one of the two, and in one lump.
fn run_image(path string, args []string) {
	mut command := os.quoted_path(path)
	for arg in args {
		command += ' ' + os.quoted_path(arg)
	}
	exit(os.system(command))
}

fn temporary_path() string {
	return os.join_path(os.temp_dir(), 'vcc-run-${os.getpid()}')
}

// print_tokens is what `-E` does: the stream the parser would be handed, one
// token per line, with the file and the position each token was written at.
fn print_tokens(tokens []tokenize.Token) {
	for tok in tokens {
		println('${tok.file}:${tok.line}:${tok.col}\t${tok.kind}\t${tok.text}')
	}
}

// write_dependencies is what `-M` does: the make rule that says what the file
// is made of. It is printed, or written where -MF says, and the compile stops
// there — make reads the rule to decide whether to run the compile at all, and
// running it as well would be doing the work twice.
//
// -MM leaves the headers that came from the standard directories out of the
// rule: a build that already knows where the C library is does not need to be
// told again, and a rule naming /usr/include changes whenever the machine does.
fn write_dependencies(source string, files []preprocess.SourceFile, opts cli.Options) {
	mut words := []string{}
	for file in files {
		if !opts.deps_system && file.system {
			continue
		}
		words << escape_for_make(file.path)
	}
	rule := '${escape_for_make(dependency_target(source, opts.output))}: ${words.join(' ')}'
	if opts.deps_file != '' {
		os.write_file(opts.deps_file, '${rule}\n') or {
			abort('cannot write ${opts.deps_file}: ${err.msg()}')
			return
		}
		return
	}
	// The rule names what a build would have asked for, so the output path is
	// the object file's; with -M and -MF there is none and the rule goes to the
	// standard output, which is where a build reads it from.
	println(rule)
}

// dependency_target is what the rule is for: the file named with -o when there
// is one, and the source with its last extension changed to .o otherwise, which
// is the file make would look for.
fn dependency_target(source string, output string) string {
	if output != '' {
		return output
	}
	dot := source.last_index('.') or { return '${source}.o' }
	return '${source[..dot]}.o'
}

// escape_for_make writes a path so that make reads it as one word: a space ends
// a word in a rule, so a file whose name has one has to say so.
fn escape_for_make(path string) string {
	return path.replace(' ', '\\ ')
}

// print_macros is what `-dM` does: what is defined when the read ends, one
// definition per line, in the shape the program itself would have written it.
// It is how a build checks what a compiler believes about the target before it
// relies on it, and how a person asks why a branch was not taken.
fn print_macros(macros []preprocess.Macro) {
	for macro in macros {
		mut texts := []string{}
		for token in macro.body {
			texts << token.text
		}
		mut head := '#define ${macro.name}'
		if macro.takes_arguments() {
			mut params := macro.params.clone()
			if macro.variadic {
				params << '...'
			}
			head += '(${params.join(', ')})'
		}
		body := texts.join(' ')
		if body == '' {
			println(head)
			continue
		}
		println('${head} ${body}')
	}
}

fn report(path string, diagnostics []tokenize.Diagnostic, inhibit_warnings bool) {
	for diagnostic in diagnostics {
		if diagnostic.warning && inhibit_warnings {
			// `-w` is the command line asking not to be told. The warning is
			// still a warning and the compile still succeeds; it is only not
			// printed.
			continue
		}
		// A diagnostic raised inside an included file names that file; the one
		// the compiler was handed is the fallback for everything else.
		where := if diagnostic.file != '' { diagnostic.file } else { path }
		mut label := ''
		if diagnostic.warning {
			label = 'warning: '
		}
		eprintln('${where}:${diagnostic.line}:${diagnostic.col}: ${label}${diagnostic.msg}')
	}
}

fn abort(message string) {
	eprintln('vcc: ${message}')
	exit(1)
}

// standard_include_dirs are the directories searched for <stdio.h> after the -I
// ones, unless -nostdinc says not to search any. They are the host's, because
// this compiler brings no headers of its own: what it compiles against is the C
// library the machine already has, and the headers that describe it.
//
// The compiler's own headers live with the GCC that ships them — stddef.h and
// stdarg.h, which every standard header expects to find — one directory per
// version, and the newest one is the one meant to be read. A machine can carry
// headers for more than one target side by side there (a cross compiler, a
// mingw toolchain); only the directories whose names describe the target being
// compiled for are read, so a cross compiler's stddef.h is never picked up
// because its name happens to sort last.
fn standard_include_dirs() []string {
	target := backend.host() or { return []string{} }
	mut dirs := []string{}
	dirs << '/usr/local/include'
	mut gcc_dirs := []string{}
	for machine in os.ls('/usr/lib/gcc') or { []string{} } {
		if !machine.contains(target.arch) || !machine.contains(target.os) {
			continue
		}
		for version in os.ls('/usr/lib/gcc/${machine}') or { []string{} } {
			candidate := '/usr/lib/gcc/${machine}/${version}/include'
			if os.is_dir(candidate) {
				gcc_dirs << candidate
			}
		}
	}
	gcc_dirs.sort()
	if gcc_dirs.len > 0 {
		dirs << gcc_dirs.last()
	}
	// Debian and its relatives keep the architecture's own headers in a
	// directory named after the target; on a machine that has no such split
	// this simply does not exist.
	arch_dir := '/usr/include/${target.arch}-${target.os}-gnu'
	if os.is_dir(arch_dir) {
		dirs << arch_dir
	}
	dirs << '/usr/include'
	return dirs
}
