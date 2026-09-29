module main

import backend
import cli
import codegen
import optimizer
import os
import parser
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
			println('include: (the standard directories, which are not used yet)')
		}
		for dir in opts.include_dirs {
			println('include: ${dir}')
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
	lexed := tokenize.lex(source)
	phases << cli.Phase{
		name:   'lex'
		micros: time.since(started).microseconds()
	}
	if lexed.diagnostics.len > 0 {
		report(path, lexed.diagnostics)
		exit(1)
	}
	if opts.preprocess {
		print_tokens(lexed.tokens)
		return
	}
	started = time.now()
	parsed := parser.parse(lexed.tokens)
	phases << cli.Phase{
		name:   'parse'
		micros: time.since(started).microseconds()
	}
	report(path, parsed.diagnostics)
	if parsed.diagnostics.len > 0 {
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
	report(path, image.diagnostics)
	if image.diagnostics.len > 0 {
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
fn run_image(path string, args []string) {
	mut command := os.quoted_path(path)
	for arg in args {
		command += ' ' + os.quoted_path(arg)
	}
	result := os.execute(command)
	if result.exit_code < 0 {
		abort('cannot run ${path}: ${result.output}')
	}
	exit(result.exit_code)
}

fn temporary_path() string {
	return os.join_path(os.temp_dir(), 'vcc-run-${os.getpid()}')
}

// print_tokens is what `-E` does today: the token stream, one token per line.
// The preprocessor is a later milestone, so nothing is expanded and the text is
// what was written.
fn print_tokens(tokens []tokenize.Token) {
	for tok in tokens {
		if tok.kind == .eof {
			break
		}
		println('${tok.line}:${tok.col}\t${tok.kind}\t${tok.text}')
	}
}

fn report(path string, diagnostics []tokenize.Diagnostic) {
	for diagnostic in diagnostics {
		// A diagnostic raised inside an included file names that file; the one
		// the compiler was handed is the fallback for everything else.
		where := if diagnostic.file != '' { diagnostic.file } else { path }
		eprintln('${where}:${diagnostic.line}:${diagnostic.col}: ${diagnostic.msg}')
	}
}

fn abort(message string) {
	eprintln('vcc: ${message}')
	exit(1)
}
