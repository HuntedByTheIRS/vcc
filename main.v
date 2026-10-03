module main

import backend
import cli
import codegen
import diagnostics
import extensions
import optimizer
import os
import parser
import preprocess
import printer
import standard
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
		println('standard: ${standard_line(opts)}')
		println('extensions: ${extensions_line(opts.vcc_extensions)}')
		println('recorded: ${recorded_line(opts.ignored)}')
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
	if opts.inputs.len > 1 {
		abort('linking more than one input is not implemented yet')
		return
	}
	path := opts.inputs[0]
	source := read_source(path) or {
		abort('cannot read ${path}: ${err.msg()}')
		return
	}
	// What the input is decides whether it is read as source at all. An object
	// or an archive is an input to a link, which this compiler does not have
	// yet, and reading one as source answers a wrong input kind with a parse
	// error raised from inside a binary file. The bytes are classified rather
	// than the path so that standard input, which cannot be read twice, is
	// decided by the same rule.
	kind := cli.classify_input(source, path, opts.input_type)
	if kind != .source {
		abort(cli.input_refusal(path, kind))
		return
	}
	mut phases := []cli.Phase{}
	mut started := time.now()
	// Lexing happens inside the preprocessor, which is the stage that knows
	// which file it is reading and what to do with the directives it finds.
	processed := preprocess.preprocess(source, path, preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        language_defines(opts)
		undefines:      opts.undefines
		standard_dirs:  if opts.nostdinc { []string{} } else { standard_include_dirs() }
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
		// The mode goes to the read as well as to the dialect check below,
		// because phase 1 asks it a question before a token exists: whether a
		// trigraph is replaced.
		dialect:        opts.dialect
	})
	phases << cli.Phase{
		name:   'preprocess'
		micros: time.since(started).microseconds()
	}
	// A warning is reported and the compile goes on; an error ends it, and so
	// does a warning the command line promoted. Which is which is asked of the
	// diagnostic and of the policy rather than counted, so that a stage which
	// hands back a warning is not mistaken for a stage that failed.
	//
	// A run that only asks what the file is made of — -M without -MD, -E, -dM —
	// has no compile for that promotion to stop, and its answer is the whole
	// point of the command: a build that passes a promotion flag to a dependency
	// step, which is harmless under gcc and was harmless here before these flags
	// existed, must still get its rule. Measured, gcc reports and writes in that
	// run: `gcc -M -std=c99 -Werror=cpp` over a file carrying a `#warning` exits
	// 0 with the rule and empty stderr, `-dM` exits 0 with the macros, and `-E`
	// writes the stream, where the same command line without a read-only switch
	// exits 1. So both stages of such a run — the preprocessor's own report here
	// and the dialect check below — are reported under the policy a read-only
	// run is reported under, which keeps a message a flag asked for printed and
	// takes its verdict back. A compile keeps the policy the command line gave,
	// so there a promotion still ends it.
	reading_only := (opts.deps && !opts.deps_compile) || opts.preprocess || opts.dump_macros
	policy := if reading_only { opts.warnings.without_promotion() } else { opts.warnings }
	if report(path, processed.diagnostics, policy) > 0 {
		exit(1)
	}
	// The dialect check runs over the stream the preprocessor produced, which is
	// the one place the whole program is in a single list. It reports the
	// constructs the selected mode does not allow and refuses nothing; a message
	// the flags promoted is the only way it can stop a compile. It is reported
	// under the same policy as the stage above, so the two stages of a read-only
	// run agree and neither of them can drop the answer.
	pedantic := standard.pedantic_messages(processed.tokens, standard.Question{
		mode:         opts.dialect
		extensions:   opts.vcc_extensions.enabled_names()
		system_files: system_files(processed.files)
	})
	if report(path, pedantic, policy) > 0 {
		exit(1)
	}
	// -M and -dM answer a question about the read and stop there: a build tool
	// asking what a file is made of does not want an object file at the end of
	// its command line. -MD is the other half of that question — write the rule
	// and compile as well — and its rule goes beside the object unless -MF
	// says otherwise.
	if opts.deps && !opts.deps_compile {
		write_dependencies(path, processed.files, opts)
		return
	}
	if opts.deps {
		write_dependencies(path, processed.files, opts)
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
	// The front end needs the target as much as the emitter does: the width of a
	// pointer and of an int, the offset a member sits at, the type a constant is
	// given and the class an aggregate is handed over in are all the target's, and
	// a second target would make the host the wrong answer for every one of them.
	parsed := parser.parse_for(processed.tokens, parser_target(opts.target))
	phases << cli.Phase{
		name:   'parse'
		micros: time.since(started).microseconds()
	}
	if report(path, parsed.diagnostics, opts.warnings) > 0 {
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
		target:       opts.target
		entry:        'main'
		compile_only: opts.compile_only
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
	})
	phases << cli.Phase{
		name:   'emit'
		micros: time.since(started).microseconds()
	}
	if report(path, image.diagnostics, opts.warnings) > 0 {
		exit(1)
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.compile_only {
		// The object keeps the source's name with .o where its last extension
		// was, which is where a build looks for it without being told.
		object_name(path, opts)
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	if opts.compile_only {
		// A relocatable file is read by a linker and never run, so it is written
		// without the execute bit an image gets.
		write_object(out_path, image.bytes) or {
			abort('cannot write ${out_path}: ${err.msg()}')
			return
		}
	} else {
		write_image(out_path, image.bytes) or {
			abort('cannot write ${out_path}: ${err.msg()}')
			return
		}
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

// language_defines are the -D arguments the compiler hands the preprocessor: the
// macros the selected mode adds, and then the ones the command line wrote. That
// order is what makes a -D win over the mode, the way it wins over a built-in in
// gcc. -undef takes the mode's macros away with every other macro that describes
// the target.
fn language_defines(opts cli.Options) []string {
	if opts.undef_builtins {
		return opts.defines
	}
	// The mode's macros come first, so a -D on the command line still wins over
	// them: a mode is a built-in, and the command line is not.
	mut out := []string{}
	out << preprocess.standard_defines(opts.dialect)
	out << opts.defines
	return out
}

// system_files is the set of files the dialect check stays out of: the headers
// that came from the standard directories, which nobody in the build wrote and
// nobody in the build can fix.
fn system_files(files []preprocess.SourceFile) map[string]bool {
	mut out := map[string]bool{}
	for file in files {
		if file.system {
			out[file.path] = true
		}
	}
	return out
}

// standard_line is what -vv says about the dialect: the spelling the command line
// wrote and the mode it names, so that a build reading the output can tell what
// the flag bought.
fn standard_line(opts cli.Options) string {
	match opts.dialect {
		.none { return '(none asked for; V passes -std=gnu11, which is recorded and not refused)' }
		.other {
			return '${opts.standard} (a spelling this compiler does not implement; recorded, never refused)'
		}
		else {
			return '${opts.standard} (mode ${opts.dialect.spelling()}, ${opts.dialect.standard_name()})'
		}
	}
}

// parser_target is the target the front end resolves widths for: the one the
// command line names, or the machine this binary runs on when it names none.
//
// A name this compiler does not describe is passed on as the host rather than as
// no description at all. The refusal for an unknown target belongs to the
// emitter, which is the layer that reads what the flag means, and a parse that
// could answer no width at all would report the same bad command line as a page
// of refusals about the source, which sends the reader to the wrong file.
fn parser_target(name string) ?backend.Target {
	target := backend.resolve(name) or { return backend.host() }
	return target
}

// extensions_line is what -vv says about the vendor extensions: which are on,
// what each one brings down, and which names exist, so that one command answers
// what -fvcc-exts= did. Every part of it comes from the extension column of the
// standard table, which is the only place an extension is named.
fn extensions_line(chosen extensions.Options) string {
	offered := extensions.names()
	enabled := chosen.enabled_names()
	if enabled.len == 0 {
		return 'none enabled (the names it has are ${offered.join(', ')})'
	}
	mut said := []string{}
	for name in enabled {
		said << '${name} brings down ${extensions.brings(name)}'
	}
	return '${said.join('; ')} (of ${offered.join(', ')})'
}

// recorded_line is what -vv says about the flags the compiler accepted and did
// not act on. They are all there, so a build can see that a flag it passed was
// recorded rather than honored.
fn recorded_line(ignored []string) string {
	if ignored.len == 0 {
		return '(nothing: every flag was acted on)'
	}
	return ignored.join(' ')
}

// read_source takes the path or the source itself, so a pipeline that feeds the
// compiler on standard input works the way it does with tcc.
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

// write_object writes a relocatable file. It is the same bytes as an image and
// not the same kind of file: a linker reads it rather than the kernel running
// it, so it gets no execute bit.
fn write_object(path string, bytes []u8) ! {
	os.write_file_array(path, bytes)!
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
	rule := '${escape_for_make(dependency_target(source, opts))}: ${words.join(' ')}'
	to := dependency_file(source, opts)
	if to == '' {
		// With -M and no -MF the rule goes to the standard output, which is
		// where a build that asked for it reads it from.
		println(rule)
		return
	}
	os.write_file(to, '${rule}\n') or {
		abort('cannot write ${to}: ${err.msg()}')
		return
	}
}

// dependency_file is where the rule is written: the file -MF names, or for
// -MD and -MMD the object's name with .d in place of its extension, which is
// where a build looks for it without being told. It is the object's name and not
// the rule's target: -MT decides what the rule says and not what file it is said
// in. With -M and no -MF there is no file and the rule is printed.
fn dependency_file(source string, opts cli.Options) string {
	if opts.deps_file != '' {
		return opts.deps_file
	}
	if !opts.deps_compile {
		return ''
	}
	base := object_name(source, opts)
	dot := base.last_index('.') or { return '${base}.d' }
	return '${base[..dot]}.d'
}

// dependency_target is what the rule is for: the name -MT or -MQ gives it, or
// the object the compile writes, which is the file make would look for.
fn dependency_target(source string, opts cli.Options) string {
	if opts.deps_target != '' {
		return opts.deps_target
	}
	return object_name(source, opts)
}

// object_name is the file the compile produces: the one named with -o when
// there is one, and the source with its last extension changed to .o otherwise.
fn object_name(source string, opts cli.Options) string {
	if opts.output != '' {
		return opts.output
	}
	dot := source.last_index('.') or { return '${source}.o' }
	return '${source[..dot]}.o'
}

// escape_for_make writes a path so that make reads it as one word with nothing
// read into it: a space ends a word, a `#` starts a comment and a `$` starts a
// variable, so a file whose name has one has to say so.
fn escape_for_make(path string) string {
	return path.replace(' ', '\\ ').replace('#', '\\#').replace('$', '$$')
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

// severity_of is where a diagnostic meets the command line. An error is an error
// whatever the flags say, because nothing silences something that is wrong, and
// a warning carries its class, which is what the policy answers for.
fn severity_of(diagnostic tokenize.Diagnostic, policy diagnostics.Policy) diagnostics.Severity {
	if !diagnostic.warning {
		return .error
	}
	return policy.severity(diagnostic.class)
}

// report prints the diagnostics a stage handed back and answers how many of them
// are errors: a diagnostic that is wrong on its own, and a warning the command
// line promoted to one. What is not printed is a class the flags silenced, which
// is a warning the compiler still counted and a compile that still succeeded.
fn report(path string, raised []tokenize.Diagnostic, policy diagnostics.Policy) int {
	mut errors := 0
	for diagnostic in raised {
		severity := severity_of(diagnostic, policy)
		if severity == .silent {
			continue
		}
		// A diagnostic raised inside an included file names that file; the one
		// the compiler was handed is the fallback for everything else.
		where := if diagnostic.file != '' { diagnostic.file } else { path }
		eprintln(diagnostics.render(where, diagnostic.line, diagnostic.col, severity, diagnostic.msg))
		if severity == .error {
			errors++
		}
	}
	return errors
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
