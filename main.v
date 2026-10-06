module main

import backend
import backend.os.linux
import cli
import codegen
import diagnostics
import extensions
import image as unit
import linking
import linking.archive
import linking.object
import linking.output
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
		println('emulation: ${emulation_line(opts)}')
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
	if opts.verbose {
		verbose_print(verbose_header_lines(opts))
	}
	// A -print- flag asks a question and stops, so it needs no input file. That
	// is how a build system asks a compiler where its things are before it has
	// anything to compile: it reads the answer off the standard output and does
	// not want a file, an object or a diagnostic beside it.
	if opts.asks_query() {
		target := backend.resolve(opts.target) or {
			abort(err.msg())
			return
		}
		if opts.verbose {
			verbose_print(verbose_query_lines(opts, target))
		}
		println(query_answer(opts, target))
		return
	}
	if opts.inputs.len == 0 {
		eprintln('vcc: no input files')
		eprintln('')
		eprintln(cli.usage(false))
		exit(1)
	}
	// -external-linker is its own path: it links the inputs this compiler cannot
	// consume and is taken before the single-input refusals below, because those
	// refusals are what the flag exists to lift. A run that stops before a link
	// keeps to the ordinary path and the flag goes unused, the way a linker flag
	// that names a tool a run never reaches does anywhere else: it asks for
	// something the run does not do, and refusing the command line would make a
	// flag that decides nothing an error.
	if opts.external_linker != '' && opts.links() {
		external_link(opts)
		return
	}
	// -shared and -static decide what a link writes, and the path with no linker
	// writes all three kinds of file: the container has a shape for each. Both
	// flags are therefore read here rather than refused. The one command line
	// that is refused is the pair asking for different files, because a link
	// that took one flag would drop the other without a word.
	if refusal := opts.link_kind_conflict_refusal() {
		abort(refusal)
	}
	// More than one input is a link, and a link is the linker's job: every
	// input is compiled as one unit of it, the merge settles the references
	// between them, and the container writes the one program. The single-input
	// path below writes that container from the one program it emitted
	// instead, which is why the stub is a detail of its emitter there and a
	// unit of the link here. A run that stops before a link has no list of
	// units to hand over, and each of those options reads one file, so it is
	// refused by name rather than linked from a subset of what it was given.
	if opts.inputs.len > 1 {
		if !opts.links() {
			abort('more than one input is a link, and this run stops before one: -c, -E, -M and -print-ast each read one file, so name the inputs one command at a time')
			return
		}
		link_inputs(opts)
		return
	}
	if opts.verbose {
		verbose_print(verbose_include_dir_lines(opts))
	}
	path := opts.inputs[0]
	source := read_source(path) or {
		abort('cannot read ${path}: ${err.msg()}')
		return
	}
	// What the input is decides whether it is read as source at all. An object
	// or an archive is an input to a link rather than a file to parse, and
	// reading one as source answers a wrong input kind with a parse error
	// raised from inside a binary file. The bytes are classified rather than the
	// path so that standard input, which cannot be read twice, is decided by the
	// same rule.
	//
	// A single object or archive is a link with one input, so a run that writes
	// a program hands it to the linker's path, which reads it as the unit it
	// holds. The options that read one file stop before a link and are refused
	// by name. A program or a shared object is a link input this compiler does
	// not read at all.
	kind := cli.classify_input(source, path, opts.input_type)
	if kind != .source {
		if !opts.links() || (kind != .object && kind != .archive) {
			abort(cli.input_refusal(path, kind))
			return
		}
		if path == '-' {
			abort('standard input holds ${kind.describe()}, and a link reads its inputs from files')
			return
		}
		link_inputs(opts)
		return
	}
	// A static program is linked rather than written from one unit, because the
	// only static program that can reach a library is the one the library
	// itself starts. Which of the two a static link needs is decided once its
	// units are read, in the linker's path below, so every static link takes
	// that path and one rule decides it.
	if opts.links() && link_kind(opts) == .static_program {
		link_inputs(opts)
		return
	}
	mut phases := []cli.Phase{}
	mut started := time.now()
	// Lexing happens inside the preprocessor, which is the stage that knows
	// which file it is reading and what to do with the directives it finds.
	processed := preprocess.preprocess(source, path, read_options(opts))
	phases << cli.Phase{
		name:   'preprocess'
		micros: time.since(started).microseconds()
	}
	if opts.verbose {
		verbose_print(verbose_file_lines(processed.files))
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
	pedantic := dialect_messages(processed, opts)
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
		pic:          opts.pic
		link_kind:    link_kind(opts)
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
	if opts.verbose {
		verbose_print(verbose_result_lines(opts, phases, image.bytes, out_path))
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

// read_options is what every input is read with, whether it is the one file the
// ordinary path reads or one more unit of a link: the same -I, -D, -U, prelude
// and dialect, so that a link's units are read the way the same files read one
// command at a time would be.
fn read_options(opts cli.Options) preprocess.Options {
	return preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        language_defines(opts)
		undefines:      opts.undefines
		standard_dirs:  if opts.nostdinc { []string{} } else { standard_include_dirs() }
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
		// The mode goes to the read as well as to the dialect check, because
		// phase 1 asks it a question before a token exists: whether a trigraph
		// is replaced.
		dialect:        opts.dialect
	}
}

// dialect_messages are the constructs the selected mode does not allow, read off
// the stream the preprocessor produced. It is the same check for one unit of a
// link as for the one file the ordinary path reads.
fn dialect_messages(processed preprocess.Result, opts cli.Options) []tokenize.Diagnostic {
	return standard.pedantic_messages(processed.tokens, standard.Question{
		mode:         opts.dialect
		extensions:   opts.vcc_extensions.enabled_names()
		system_files: system_files(processed.files)
	})
}

// link_needs is the names a link still has to find outside its units: the
// imports of its units that no unit in the link defines. An archive is asked
// for these and for nothing else, so a name one unit defines is never a reason
// to pull a member that also defines it.
fn link_needs(units []unit.Program) map[string]bool {
	mut provided := map[string]bool{}
	for entry in units {
		for name, _ in entry.defined {
			provided[name] = true
		}
		for name, _ in entry.globals {
			provided[name] = true
		}
	}
	mut needed := map[string]bool{}
	for entry in units {
		for symbol in entry.imports {
			if symbol !in provided {
				needed[symbol] = true
			}
		}
	}
	return needed
}

// pull_archives pulls the members of every archive that answer a name the link
// still needs, and sweeps the whole set again while a sweep pulled anything. A
// static link resolves its libraries against each other rather than one after
// the other: libgcc's unwinding reaches for the C library's threads and the C
// library reaches for libgcc, so coming back to an archive already passed is
// the only order that finishes. A member is read once, whichever sweep reached
// it, and the names are walked in sorted order rather than off the map, so one
// set of archives and one set of needs always pull the same members in the same
// order and the same link writes the same bytes. A member nothing refers to
// stays out, which is what makes a library of many objects cost only the parts
// the program asks for.
fn pull_archives(archives []archive.Archive, target backend.Target, mut needed map[string]bool) ![]unit.Program {
	mut pulled := map[string]bool{}
	mut out := []unit.Program{}
	mut again := true
	for again {
		again = false
		for a, parts in archives {
			mut names := parts.index.keys()
			names.sort()
			for name in names {
				if !needed[name] {
					continue
				}
				index := parts.index[name]
				key := '${a}:${index}'
				if key in pulled {
					continue
				}
				pulled[key] = true
				member := parts.members[index]
				entry := object.read(member.bytes, target) or {
					return error('${member.name}: ${err.msg()}')
				}
				for symbol in entry.imports {
					needed[symbol] = true
				}
				out << entry
				again = true
			}
		}
	}
	return out
}

// read_unit reads one file as the relocatable object a link merges. The start
// files of a link are objects of this compiler's own reading, so a link that
// puts the C library's startup around its program reads them the way it reads
// an object the command line named.
fn read_unit(path string, target backend.Target) !unit.Program {
	source := read_source(path)!
	return object.read(source.bytes(), target)
}

// has_constructors says whether any unit of the link carries a constructor or
// destructor table, which is what decides whether whoever starts the image has
// to run anything before `main`.
fn has_constructors(units []unit.Program) bool {
	for unit in units {
		if unit.init_array.count > 0 || unit.fini_array.count > 0 {
			return true
		}
	}
	return false
}

// needs_a_library says whether the units name a function or an object that none
// of them defines, which is what makes a link reach outside itself. The names a
// unit defines are collected first and the imports asked against them, because a
// name one unit imports and another defines is the link's own business and not a
// library's.
fn needs_a_library(units []unit.Program) bool {
	mut defined := map[string]bool{}
	for unit in units {
		for name, _ in unit.defined {
			defined[name] = true
		}
		for name, _ in unit.globals {
			defined[name] = true
		}
	}
	for unit in units {
		for name in unit.imports {
			if name !in defined {
				return true
			}
		}
	}
	return false
}

// link_inputs is the multi-input path. Every input is compiled as one unit of a
// link, the units are merged with the process stub, and the one program the link
// calls for is written. The stub is built here and placed first, because text
// offset zero is the stub and so the image's entry point is text offset zero
// whatever the units do with a `main` of their own; the single-input path has
// the emitter write that stub into the one image instead.
fn link_inputs(opts cli.Options) {
	if opts.verbose {
		verbose_print(verbose_include_dir_lines(opts))
	}
	target := backend.resolve(opts.target) or {
		abort(err.msg())
		return
	}
	// A shared object has no process stub: nothing starts it and the image's
	// entry point is zero. Every other kind of link starts at a stub this
	// compiler writes, unless the units bring an entry point of their own,
	// which is what the C library's start files do; that is decided below,
	// once the units are read, because it is the units that say whether the
	// link reaches a library.
	output_kind := link_kind(opts)
	mut units := []unit.Program{cap: opts.inputs.len + 1}
	mut reading := i64(0)
	mut parsing := i64(0)
	mut optimizing := i64(0)
	mut emitting := i64(0)
	mut archives := []archive.Archive{}
	for path in opts.inputs {
		source := read_source(path) or {
			abort('cannot read ${path}: ${err.msg()}')
			return
		}
		// What the input is decides how it is read, by the rule the single-input
		// path uses: source is compiled into a unit, an object is read back into
		// the unit it holds, and an archive is held until the names the link
		// needs are known. A program or a shared object is an input this
		// compiler does not read, and reading one as source would answer a wrong
		// input kind with a parse error raised from inside a binary file.
		kind := cli.classify_input(source, path, opts.input_type)
		if kind == .object {
			read := object.read(source.bytes(), target) or {
				abort('${path}: ${err.msg()}')
				return
			}
			units << read
			continue
		}
		if kind == .archive {
			archives << archive.read(source.bytes()) or {
				abort('${path}: ${err.msg()}')
				return
			}
			continue
		}
		if kind != .source {
			abort(cli.input_refusal(path, kind))
			return
		}
		mut started := time.now()
		processed := preprocess.preprocess(source, path, read_options(opts))
		reading += time.since(started).microseconds()
		if opts.verbose {
			verbose_print(verbose_file_lines(processed.files))
		}
		if report(path, processed.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		if report(path, dialect_messages(processed, opts), opts.warnings) > 0 {
			exit(1)
		}
		started = time.now()
		parsed := parser.parse_for(processed.tokens, parser_target(opts.target))
		parsing += time.since(started).microseconds()
		if report(path, parsed.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		started = time.now()
		optimized := optimizer.optimize(parsed.unit, opts.optimization)
		optimizing += time.since(started).microseconds()
		started = time.now()
		emitted := codegen.emit(optimized, codegen.Options{
			target:       opts.target
			link:         true
			libraries:    opts.libraries
			library_dirs: opts.library_dirs
		})
		emitting += time.since(started).microseconds()
		if report(path, emitted.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		units << emitted.program
	}
	// A -l name that resolved to an archive is an input of the same kind as an
	// archive file the command line named, and its members are pulled by the
	// same rule below. Nothing else about the name is kept: the image asks the
	// loader for no name for a static archive, so the archive contributes no
	// DT_NEEDED entry.
	if opts.libraries.len > 0 {
		named := target.archive_libraries(opts.libraries, opts.library_dirs) or {
			abort(err.msg())
			return
		}
		for file in named {
			source := read_source(file.path) or {
				abort('cannot read ${file.path}: ${err.msg()}')
				return
			}
			archives << archive.read(source.bytes()) or {
				abort('${file.path}: ${err.msg()}')
				return
			}
		}
	}
	// A static link that reaches a library is started by the C library's own
	// entry point instead of by a stub this compiler writes: the library's
	// startup is what sets the thread pointer up, runs the constructors and
	// reaches `main`, and a program that calls printf without any of that dies
	// before it prints. Whether this link is one of those is whether its units
	// name a function or an object none of them defines.
	//
	// The start files come from the system's own description, resolved in the
	// directories a link searches, and they go around the units in the order a
	// link puts them: crt1.o holds the entry point, so it is what the merged
	// text begins with and what the image's entry point is.
	reach := output_kind == .static_program && needs_a_library(units)
	mut entry := if output_kind == .shared { '' } else { 'main' }
	if reach {
		before, after := target.start_file_paths(.static_program, opts.library_dirs) or {
			abort(err.msg())
			return
		}
		// The start files go in front of the units, in the order a link places
		// them, so the last one is prepended first and crt1.o ends up at text
		// offset zero, where the container reads the entry point from.
		mut i := before.len
		for i > 0 {
			i--
			units.prepend(read_unit(before[i], target) or {
				abort('${before[i]}: ${err.msg()}')
				return
			})
		}
		for path in after {
			units << read_unit(path, target) or {
				abort('${path}: ${err.msg()}')
				return
			}
		}
		for path in target.static_support_libraries(opts.library_dirs) {
			source := read_source(path) or {
				abort('cannot read ${path}: ${err.msg()}')
				return
			}
			archives << archive.read(source.bytes()) or {
				abort('${path}: ${err.msg()}')
				return
			}
		}
		entry = '_start'
	} else if output_kind != .shared {
		stub := codegen.start_stub(entry, codegen.Options{
			target:    opts.target
			link_kind: output_kind
		})
		// The stub is emitted from a constant entry name and the exit
		// sequence, so it has nothing to report; a diagnostic here is this
		// compiler failing rather than an input. It goes through the one place
		// a diagnostic becomes text, with no file to name because it has none.
		if report('', stub.diagnostics, opts.warnings) > 0 {
			exit(1)
		}
		units.prepend(stub.program)
	}
	// An archive is pulled apart only for the names the link still needs. A
	// member whose symbols nothing refers to stays where it is, the way a linker
	// leaves it, so a library of many objects adds the ones the program asks
	// for. The names already defined by a unit in the link are not needs, and
	// the first unit is the stub, whose one import is the entry, so `main` is
	// wanted from the start.
	if archives.len > 0 {
		mut needed := link_needs(units)
		units << pull_archives(archives, target, mut needed) or {
			abort(err.msg())
			return
		}
	}
	// A constructor table is run by whoever starts the program: the loader for a
	// dynamic one, the C library's own startup for a static one, which walks the
	// table by its two end names. A static program with neither has nothing to
	// walk it and the stub this compiler writes calls `main` and leaves, so the
	// constructor would be silently skipped. A wrong answer that is quiet is the
	// worst outcome available, so such a link stops here and names the pair.
	if output_kind == .static_program && !reach && has_constructors(units) {
		abort("a static program with a constructor needs the C library's startup to run it, and this link reaches no library: the constructor would never run")
		return
	}
	mut started := time.now()
	merged := linking.link(units, linking.Options{
		entry:        entry
		target:       target
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
	}) or {
		abort(err.msg())
		return
	}
	bytes := output.image(merged, target, link_kind(opts)) or {
		abort(err.msg())
		return
	}
	linked := time.since(started).microseconds()
	// One line per phase for the whole command, because a build reading -bench
	// wants what the link cost rather than a row per input: each number is the
	// sum over the units and the last one is the merge and the container.
	mut phases := []cli.Phase{}
	phases << cli.Phase{
		name:   'preprocess'
		micros: reading
	}
	phases << cli.Phase{
		name:   'parse'
		micros: parsing
	}
	phases << cli.Phase{
		name:   'opt'
		micros: optimizing
	}
	phases << cli.Phase{
		name:   'emit'
		micros: emitting
	}
	phases << cli.Phase{
		name:   'link'
		micros: linked
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	write_image(out_path, bytes) or {
		abort('cannot write ${out_path}: ${err.msg()}')
		return
	}
	if opts.verbose {
		verbose_print(verbose_result_lines(opts, phases, bytes, out_path))
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
// macros that identify this compiler, the ones the selected mode adds, and then
// the ones the command line wrote. That order is what makes a -D win over the
// mode and over the identity, the way it wins over a built-in in gcc. -undef
// takes all of the compiler's own macros away with every other macro that
// describes the target.
fn language_defines(opts cli.Options) []string {
	if opts.undef_builtins {
		return opts.defines
	}
	mut out := []string{}
	out << preprocess.identity_defines(cli.version)
	out << preprocess.standard_defines(opts.dialect, opts.emulation)
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

// emulation_line is what -vv says about -femulation: the compiler whose identity
// macros the build asked for, or that it asked for none and this compiler's own
// are the answer.
fn emulation_line(opts cli.Options) string {
	if opts.emulation == .none {
		return '(none; this compiler reports its own identity)'
	}
	return '${opts.emulation.spelling()} (the identity macros of that compiler are defined)'
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

// link_kind is which link the command line asked for, read off the two flags
// that name one. Whether the two may both be given is decided where the run is
// refused and not here, so this answers and does not judge.
fn link_kind(opts cli.Options) linux.LinkKind {
	if opts.shared {
		return .shared
	}
	if opts.static_link {
		return .static_program
	}
	return .program
}

// external_link performs the final link with the program -external-linker named.
//
// It is the one path that links more than one input and inputs that are not C:
// each .c input runs the same stages -c runs and becomes a relocatable object, a
// foreign object or an archive is passed to the linker as it stands, and the
// linker writes the program. Every failure is reported and ends the run
// non-zero. The in-house path is never taken in place of a link that was asked
// for: a link that quietly did nothing is the worst outcome this flag can have,
// and the reason the tool is resolved before any object is written. A run that
// stops before a link never arrives here; the caller asks `links()` first.
fn external_link(opts cli.Options) {
	// Two kinds of link at once is one kind of link dropped in silence: the
	// linker would be given one of the two flags and the file would not be what
	// the other asked for.
	if refusal := opts.link_kind_conflict_refusal() {
		abort(refusal)
	}
	if refusal := cli.external_linker_refusal(opts.external_linker) {
		abort(refusal)
	}
	program := cli.external_linker_path(opts.external_linker) or {
		abort('cannot find ${opts.external_linker}: -external-linker names a linker the system must have on PATH')
		return
	}
	target := backend.resolve(opts.target) or {
		abort(err.msg())
		return
	}
	mut objects := []string{}
	mut all_source := true
	for index, input in opts.inputs {
		// The input is read once and classified from its bytes, the same rule
		// the single-input path uses; a classification by name alone would read
		// a foreign object as source.
		source := read_source(input) or {
			abort('cannot read ${input}: ${err.msg()}')
			return
		}
		match cli.classify_input(source, input, opts.input_type) {
			.source {
				bytes := compile_source_object(input, source, opts) or {
					abort('${input}: ${err.msg()}')
					return
				}
				object_path := link_object_path(index)
				write_object(object_path, bytes) or {
					abort('cannot write ${object_path}: ${err.msg()}')
					return
				}
				objects << object_path
			}
			.object, .shared_object, .archive {
				all_source = false
				objects << input
			}
			.program {
				abort('${input}: a program is not an input to a link')
				return
			}
		}
	}
	out_path := if opts.output != '' {
		opts.output
	} else if opts.run {
		temporary_path()
	} else {
		'a.out'
	}
	args := target.external_link_arguments(link_kind(opts), objects, opts.library_dirs, opts.libraries, out_path) or {
		abort(err.msg())
		return
	}
	// A tool whose name does not say which linker it is gets its own word first
	// (lld's `-flavor gnu`); everything else gets nothing before the link.
	mut invocation := cli.external_linker_prefix(opts.external_linker)
	invocation << args
	// A file an earlier link left is not allowed to stand in for one this run
	// did not write: the run reports a failure and the output has to agree.
	os.rm(out_path) or {}
	// What happened is said rather than left to be inferred. Every input being C
	// this compiler could link itself is the case that must not look like the
	// in-house path was taken quietly, so it says which tool did the link.
	if all_source {
		eprintln('vcc: every input is C this compiler could link itself; the link is handed to ${opts.external_linker} because -external-linker was given')
	} else {
		eprintln('vcc: the link is handed to ${opts.external_linker} (-external-linker)')
	}
	command := link_command_line(program, invocation)
	if opts.verbose {
		eprintln('link: ${command}')
	}
	status := os.system(command)
	if status != 0 {
		// The linker's own stderr reached the terminal as it ran; the status is
		// carried out rather than replaced, so a failed link is a failed compile
		// to whatever started it.
		os.rm(out_path) or {}
		exit(status)
	}
	if opts.run {
		run_image(out_path, opts.run_args)
	}
}

// compile_source_object runs the stages -c runs over one source and answers the
// bytes of the relocatable object they produce. It states the sequence main()
// runs for a source because that sequence reports through the command line's
// warning policy and stops at the first stage that fails; the external link
// needs the same stages with the object as their product, and sharing the whole
// sequence would make it carry the verbose hooks and the early modes as well.
//
// The emitter is asked for the -c product: a relocatable container, no entry
// point required, and no import checked, because a linker resolves the symbols
// of an object and the linker here is the one the flag named.
fn compile_source_object(path string, source string, opts cli.Options) ![]u8 {
	processed := preprocess.preprocess(source, path, preprocess.Options{
		include_dirs:   opts.include_dirs
		defines:        language_defines(opts)
		undefines:      opts.undefines
		standard_dirs:  if opts.nostdinc { []string{} } else { standard_include_dirs() }
		preludes:       opts.preludes
		undef_builtins: opts.undef_builtins
		dialect:        opts.dialect
	})
	if report(path, processed.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	pedantic := standard.pedantic_messages(processed.tokens, standard.Question{
		mode:         opts.dialect
		extensions:   opts.vcc_extensions.enabled_names()
		system_files: system_files(processed.files)
	})
	if report(path, pedantic, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	parsed := parser.parse_for(processed.tokens, parser_target(opts.target))
	if report(path, parsed.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	image := codegen.emit(optimized, codegen.Options{
		target:       opts.target
		entry:        'main'
		compile_only: true
		pic:          opts.pic
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
	})
	if report(path, image.diagnostics, opts.warnings) > 0 {
		return error('the compile stopped at a diagnostic')
	}
	return image.bytes
}

// link_object_path is where one input's relocatable object is written on its
// way to the linker. It is named after the process and the input's place on the
// command line so that a run over many inputs does not write one over another.
fn link_object_path(index int) string {
	return os.join_path(os.temp_dir(), 'vcc-extlink-${os.getpid()}-${index}.o')
}

// link_command_line is the one place the linker invocation becomes a shell
// command, with every word quoted so a path with a space survives it.
fn link_command_line(program string, args []string) string {
	mut command := os.quoted_path(program)
	for arg in args {
		command += ' ' + os.quoted_path(arg)
	}
	return command
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

// query_answer answers the -print- question the command line asked. The answers
// are this compiler's own and come from the same description the compile uses: a
// file resolves through the linker's search, and the target's multiarch spelling
// is the one its own search lists are built from.
//
// gcc answers questions about its private tree - its install directory, its cc1
// and its as - which this compiler does not have, because it is one binary that
// runs no program and writes the container itself. Where that is the reason, the
// answer is the one gcc gives for a thing it cannot find, and the comment says so.
//
// When more than one query is written, the first of these in this order is the
// one answered, which is the order gcc's own answers come out in: a file query
// first, then the variant queries, then the sysroot.
fn query_answer(opts cli.Options, target backend.Target) string {
	if opts.print_file_name_given {
		// The file the linker's search finds, or the name back unchanged when it
		// finds none. An empty name is not a file and comes back empty, which is
		// the same rule and not gcc's special answer of its install directory.
		return target.library_file(opts.print_file_name, opts.library_dirs) or {
			opts.print_file_name
		}
	}
	if opts.print_prog_name_given {
		// This compiler runs no external program: it emits the container
		// itself, so there is no name it could resolve to a path. gcc prints a
		// program name unchanged for one it cannot find, and every name is one
		// this compiler cannot find.
		return opts.print_prog_name
	}
	if opts.print_libgcc_file_name {
		// No libgcc is linked, so this answers what a search of the libraries
		// finds for libgcc.a: on a machine that keeps it beside gcc the search
		// has none and the name comes back, which is gcc's answer for a libgcc
		// it does not have.
		return target.library_file('libgcc.a', opts.library_dirs) or { 'libgcc.a' }
	}
	if opts.print_multi_directory {
		// One compilation variant exists, and its directory is the default one.
		return '.'
	}
	if opts.print_multi_lib {
		// That one variant, named by the directory it lives in and no options.
		return '.;'
	}
	if opts.print_multi_os_directory {
		// There is no multilib tree to move through: the system's own library
		// directories are what the search looks in, so the relative directory
		// is the one this compiler is already in.
		return '.'
	}
	if opts.print_multiarch {
		// The target's multiarch spelling, which is the name this compiler
		// builds both of its search lists from. gcc here prints an empty line
		// because it is configured without multiarch.
		return '${target.arch}-${target.os}-gnu'
	}
	if opts.print_sysroot {
		// A sysroot is a tree to compile against instead of the running system,
		// and this compiler has none: its headers and libraries are the host's,
		// so the answer is empty and not a directory.
		return ''
	}
	if opts.print_sysroot_headers_suffix {
		// The suffix goes with the sysroot, and there is no sysroot. gcc makes
		// this a fatal error because it has no suffix to give; an empty answer
		// is the same fact in a form a build can use, so the run still exits 0.
		return ''
	}
	return cli.search_dirs_text(install_dir(), []string{}, target.library_dirs_for(opts.library_dirs))
}

// install_dir is the directory the running compiler is in. gcc names its private
// install tree here because that is where its own files are; this compiler is one
// binary with no tree beside it, so the directory holding the binary is the only
// "where the compiler is" there is.
fn install_dir() string {
	return os.dir(os.executable())
}

// The -verbose report. gcc's -v prints the cc1, as and collect2 command lines it
// runs; this compiler runs none of those, so what follows is what it can honestly
// report: which compiler and target this is, where headers and libraries are
// looked for, what was read, and what went into the file. Every line goes to
// stderr through verbose_print and nothing here changes what is compiled, so a
// -E stream or a -print- answer on the standard output is left alone.
//
// Each stage hands back its lines rather than printing them, so the stages can be
// read in a test and there is one place that writes them.

// verbose_header_lines names the compiler, the target and the dialect, the facts
// gcc's -v opens with.
fn verbose_header_lines(opts cli.Options) []string {
	mut out := []string{}
	out << 'vcc version ${cli.version} (pure V)'
	target := backend.resolve(opts.target) or {
		out << 'target: none (${err.msg()})'
		return out
	}
	out << 'target: ${target.name}'
	out << 'standard: ${standard_line(opts)}'
	return out
}

// verbose_query_lines shows the search a query answer came from, which is the
// detail gcc's -v prints beside a -print- answer.
fn verbose_query_lines(opts cli.Options, target backend.Target) []string {
	return ['libraries: =${target.library_dirs_for(opts.library_dirs).join(':')}']
}

// verbose_include_dir_lines is where a header is looked for, in the order it is
// searched, which is what a person reads to see why a header resolved where it
// did.
fn verbose_include_dir_lines(opts cli.Options) []string {
	mut out := []string{}
	for dir in opts.include_dirs {
		out << 'include: ${dir}'
	}
	if opts.nostdinc {
		out << 'include: (the standard directories, which -nostdinc turns off)'
		return out
	}
	for dir in standard_include_dirs() {
		out << 'include: ${dir} (standard)'
	}
	return out
}

// verbose_file_lines is what the read opened: the source and every header that was
// included, which is the list -M writes as a rule.
fn verbose_file_lines(files []preprocess.SourceFile) []string {
	mut out := []string{}
	for file in files {
		kind := if file.system { ' (system)' } else { '' }
		out << 'read: ${file.path}${kind}'
	}
	return out
}

// verbose_result_lines closes the report with what this compiler did instead of
// running a linker: it wrote the container itself, so there is no command line to
// show. What it can show is the phases and what the image will carry - the loader,
// the C library, the libraries a -l named, and the file - which is the part of
// gcc's -v a build reads to see what got linked.
fn verbose_result_lines(opts cli.Options, phases []cli.Phase, bytes []u8, out_path string) []string {
	mut out := []string{}
	for phase in phases {
		out << 'phase: ${phase.name} ${phase.micros}us'
	}
	target := backend.resolve(opts.target) or { return out }
	out << 'link: no linker is run; this compiler writes the container itself'
	out << '  interpreter: ${target.interpreter}'
	out << '  library: ${target.base_library()} (the C library every image names)'
	for library in target.resolve_libraries(opts.libraries, opts.library_dirs) or {
		[]backend.Library{}
	} {
		out << '  library: ${library.soname} (${library.path})'
	}
	out << '  written: ${out_path} (${bytes.len} bytes)'
	return out
}

// verbose_print is the one place -verbose reaches a stream: stderr, so that the
// standard output stays whatever the command was asked for.
fn verbose_print(lines []string) {
	for line in lines {
		eprintln(line)
	}
}
