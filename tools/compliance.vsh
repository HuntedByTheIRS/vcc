#!/usr/bin/env -S v run

// The compliance corpus: the one check here that measures this compiler against
// a C library rather than against its own tests. `compliance/main.c` makes about
// nine hundred assertions, checks each at run time, and prints how many held.
//
//   v run tools/compliance.vsh                       # build the tree, then run it
//   v run tools/compliance.vsh --compiler /tmp/vcc   # a compiler you already built
//
// It builds the tree under test first unless a compiler is named, so what runs is
// the current source rather than whatever binary was lying around. It fails when
// the compiler prints anything while compiling the corpus, when the run exits
// non-zero, or when fewer checks hold than the floor below.

import os

// The count the corpus reached when it landed. A floor rather than an equality,
// so that adding checks needs no edit here and losing them is a failure.
const checks_floor = 906

// The mode is gnu99 and not the c99 the corpus documents for gcc, because the
// corpus includes <tgmath.h> and the system header refuses a compiler it does not
// recognise: measured, -std=c99 stops at /usr/include/tgmath.h:802 with
// `#error "Unsupported compiler; you cannot use <tgmath.h>"` and never reaches a
// line of the corpus. -w because the corpus is deliberately not warning-clean
// under this compiler, and -lm because it calls cabsl, csqrtl and cpowl.
const compile_flags = '-std=gnu99 -w -lm'

const corpus_source = 'compliance/main.c'

struct Options {
mut:
	compiler string
}

struct Counts {
	checks int
	passed int
	failed int
}

fn main() {
	opts := parse_options(os.args[1..])
	root := os.dir(os.dir(@FILE))
	source := os.join_path(root, corpus_source)
	if !os.exists(source) {
		eprintln('compliance: ${corpus_source} is missing from ${root}')
		exit(1)
	}
	println('compliance: ${root}')
	built_here := opts.compiler == ''
	compiler := if built_here { build_compiler(root) } else { opts.compiler }
	println('compiler: ${compiler}')

	scratch := os.join_path(os.temp_dir(), 'vcc-compliance-run-${os.getpid()}')
	os.mkdir_all(scratch) or {
		eprintln('compliance: no scratch directory: ${err}')
		exit(1)
	}
	binary := os.join_path(scratch, 'corpus')
	mut cleanup := [scratch]
	if built_here {
		cleanup << compiler
	}

	mut problems := []string{}
	build := os.execute('cd ${os.quoted_path(os.dir(source))} && ${os.quoted_path(compiler)} ${compile_flags} ${os.file_name(source)} -o ${os.quoted_path(binary)} 2>&1')
	println('build:  exit ${build.exit_code}, ${build.output.trim_space().len} bytes printed')
	if build.exit_code != 0 {
		problems << 'the corpus did not build: ${first_lines(build.output, 6)}'
		fail(problems, cleanup)
	}
	if build.output.trim_space() != '' {
		// Compiling the corpus prints nothing at all with -w in force, so anything
		// here is something new rather than a warning that was always there.
		problems << 'the compiler printed while compiling the corpus: ${first_lines(build.output, 6)}'
	}

	// The run happens in the scratch directory: the corpus writes nothing there,
	// and a run from the tree would have somewhere to leave a file if it did.
	run := os.execute('cd ${os.quoted_path(scratch)} && ${os.quoted_path(binary)} 2>&1')
	counts := counts_from(run.output)
	println('run:    exit ${run.exit_code}, ${counts.checks} checks, ${counts.passed} passed, ${counts.failed} failed')
	if counts.checks == 0 {
		problems << 'the corpus printed no count, so it did not reach its end: ${first_lines(run.output, 6)}'
	} else {
		if counts.failed != 0 {
			problems << '${counts.failed} check(s) failed: ${failing_lines(run.output, 10)}'
		}
		if counts.checks < checks_floor {
			problems << 'the corpus reached ${counts.checks} checks, below the floor of ${checks_floor}'
		}
	}
	if run.exit_code != 0 {
		problems << 'the run exited ${run.exit_code}'
	}
	fail(problems, cleanup)
	cleanup_paths(cleanup)
	println('')
	println('compliance: everything holds')
}

// build_compiler builds the tree under test, so the corpus describes the current
// source rather than a binary from an earlier edit.
fn build_compiler(root string) string {
	path := os.join_path(os.temp_dir(), 'vcc-compliance-vcc-${os.getpid()}')
	result := os.execute('cd ${os.quoted_path(root)} && v -o ${os.quoted_path(path)} . 2>&1')
	if result.exit_code != 0 {
		eprintln('compliance: the compiler did not build:')
		eprintln(result.output)
		exit(1)
	}
	return path
}

// counts_from reads the one summary line the corpus prints at its end: `906
// checks, 906 passed, 0 failed`. No such line means the run never got there,
// which is a different failure from a check failing and is reported as one.
fn counts_from(output string) Counts {
	mut counts := Counts{}
	for line in output.split_into_lines() {
		if !line.contains(' checks, ') || !line.contains(' passed, ') || !line.contains(' failed') {
			continue
		}
		fields := line.trim_space().split(' ')
		if fields.len < 6 {
			continue
		}
		counts = Counts{
			checks: fields[0].int()
			passed: fields[2].int()
			failed: fields[4].int()
		}
	}
	return counts
}

// first_lines keeps a failure to a size someone will read: a corpus run prints
// hundreds of lines and the cause is at the front of them.
fn first_lines(text string, limit int) string {
	mut kept := []string{}
	for line in text.trim_space().split_into_lines() {
		if kept.len >= limit {
			break
		}
		kept << line
	}
	return kept.join(' / ')
}

fn failing_lines(output string, limit int) string {
	mut kept := []string{}
	for line in output.split_into_lines() {
		if !line.contains('FAIL') {
			continue
		}
		if kept.len >= limit {
			break
		}
		kept << line.trim_space()
	}
	return kept.join(' / ')
}

fn parse_options(args []string) Options {
	mut opts := Options{}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--compiler' && i + 1 < args.len {
			opts.compiler = args[i + 1]
			i += 2
			continue
		}
		if arg == '-h' || arg == '--help' {
			println('usage: v run tools/compliance.vsh [--compiler PATH]')
			exit(0)
		}
		eprintln('compliance: unknown argument ${arg}')
		println('usage: v run tools/compliance.vsh [--compiler PATH]')
		exit(1)
	}
	return opts
}

fn cleanup_paths(paths []string) {
	for path in paths {
		os.rm(path) or {}
	}
}

// fail reports every problem at once rather than the first, because a change
// that breaks the corpus usually breaks it in more than one place.
fn fail(problems []string, cleanup []string) {
	if problems.len == 0 {
		return
	}
	eprintln('')
	for problem in problems {
		eprintln('compliance: ${problem}')
	}
	eprintln('')
	eprintln('compliance: ${problems.len} problem(s)')
	cleanup_paths(cleanup)
	exit(1)
}
