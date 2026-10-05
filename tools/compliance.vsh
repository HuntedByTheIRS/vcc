#!/usr/bin/env -S v run

// The compliance corpus used to be one translation unit carrying nine hundred
// assertions. It is a directory now. `compliance/monolithic.c` is that unit, and
// each `NNN-*.c` beside it holds one of its checks together with the
// declarations and the statements that check needs. Every tiny file is a
// program: it compiles on its own, runs on its own, and exits non-zero when its
// check fails, so a failure names a file and a line in that file.
//
//   v run tools/compliance.vsh                        # build the tree, then run every test
//   v run tools/compliance.vsh --compiler /tmp/vcc    # a compiler you already built
//   v run tools/compliance.vsh --only 017 018         # the named tests only
//   v run tools/compliance.vsh --define C99_TRIGRAPHS # include the gated tests
//   v run tools/compliance.vsh --list                 # print what would run
//   v run tools/compliance.vsh --count                # print how many tests there are
//
// A test carrying a `requires-define: NAME` line exercises a construct this
// compiler accepts only when NAME is defined, so it is skipped unless --define
// names it. The construct is off by default, and running the check with it off
// would pass by not compiling the thing under test.
//
// The floor below is the number of test files that landed. Losing one is a
// failure; adding one is not, so it is a floor and not an equality.

import os
import time

const tests_floor = 999
const checks_floor = 906

// gnu99 rather than the c99 the corpus documents for gcc, because several tests
// include <tgmath.h> and the system header refuses a compiler it does not
// recognise: measured, -std=c99 stops at /usr/include/tgmath.h:802 with
// `#error "Unsupported compiler; you cannot use <tgmath.h>"`. -w because some
// tests are deliberately not warning-clean under this compiler, and -lm for the
// long double complex functions.
//
// -x c is for the tests that keep their check in a .h file because what they
// test is what a header declares. The compiler has to read those as C; handed
// `foo.h` alone, both this compiler and gcc treat it as a header, and gcc then
// says `linker input file unused because linking not done`.
const compile_flags = '-x c -std=gnu99 -w -lm'

const corpus_dir = 'compliance'
const monolithic = 'monolithic.c'

struct Options {
mut:
	compiler string
	defines  []string
	only     []string
	jobs     int
	list     bool
	count    bool
}

struct Outcome {
	file   string
	stage  string
	detail string
}

// Work is the queue the workers pull from, and where their results land.
struct Work {
mut:
	cursor   int
	outcomes []Outcome
}

fn main() {
	opts := parse_options(os.args[1..])
	root := os.dir(os.dir(@FILE))
	tests_dir := os.join_path(root, corpus_dir)
	if !os.exists(tests_dir) {
		eprintln('compliance: ${corpus_dir} is missing from ${root}')
		exit(1)
	}
	tests := collect_tests(tests_dir, opts)
	if opts.count {
		// the number of tests in the corpus, whatever --only would narrow it to.
		// The badge in README.md reads this number, so it is counted by the same
		// code that decides what a test file is.
		println(collect_tests(tests_dir, Options{}).len)
		return
	}
	if tests.len == 0 {
		eprintln('compliance: no test files in ${tests_dir}')
		exit(1)
	}
	if opts.list {
		for test in tests {
			println(test)
		}
		return
	}
	built_here := opts.compiler == ''
	compiler := if built_here { build_compiler(root) } else { opts.compiler }
	scratch := os.join_path(os.temp_dir(), 'vcc-compliance-${os.getpid()}')
	os.mkdir_all(scratch) or {
		eprintln('compliance: no scratch directory: ${err}')
		exit(1)
	}
	os.mkdir_all(os.join_path(scratch, 'run')) or {}
	mut cleanup := [scratch]
	if built_here {
		cleanup << compiler
	}
	println('compliance: ${tests.len} tests in ${corpus_dir}')
	println('compiler:   ${compiler}')

	started := time.ticks()
	shared work := Work{}
	mut threads := []thread{}
	for _ in 0 .. worker_count(opts) {
		threads << spawn test_all(tests, tests_dir, compiler, scratch, opts.defines, shared work)
	}
	threads.wait()
	elapsed := f64(time.ticks() - started) / 1000.0

	mut problems := []string{}
	mut skipped := 0
	for outcome in work.outcomes {
		if outcome.stage == 'skip' {
			skipped++
			continue
		}
		if outcome.stage == 'ok' {
			continue
		}
		problems << '${outcome.file}: ${outcome.stage}: ${outcome.detail}'
	}
	ran := work.outcomes.len - problems.len - skipped
	println('ran:        ${ran} passed, ${problems.len} failed, ${skipped} skipped in ${elapsed:.1f}s')

	// the whole corpus in one translation unit, which is what step 3 of the
	// bootstrap chain compiles and what the check count floor is about
	whole := run_monolithic(tests_dir, compiler, scratch)
	if whole.stage != 'ok' {
		problems << 'monolithic.c: ${whole.stage}: ${whole.detail}'
	} else {
		println('monolithic: ${whole.detail}')
	}

	// every collected file counts towards the floor whether it ran, failed or
	// was skipped: the floor is about the corpus not losing tests
	if tests.len < tests_floor {
		problems << 'only ${tests.len} test files, below the floor of ${tests_floor}'
	}
	if problems.len > 0 {
		eprintln('')
		for problem in problems {
			eprintln('compliance: ${problem}')
		}
		eprintln('')
		eprintln('compliance: ${problems.len} problem(s)')
		cleanup_paths(cleanup)
		exit(1)
	}
	cleanup_paths(cleanup)
	println('')
	println('compliance: every test holds')
}

// worker_count keeps the machine usable: every test compiles, and the compiler
// under test is not a small program.
fn worker_count(opts Options) int {
	if opts.jobs > 0 {
		return opts.jobs
	}
	return 8
}

// test_all runs tests until the queue is empty. The queue is shared, so the
// cursor moves under a lock and the thread count decides how many compilers run
// at once.
fn test_all(tests []string, dir string, compiler string, scratch string, defines []string, shared work Work) {
	for {
		mut index := -1
		lock work {
			if work.cursor < tests.len {
				index = work.cursor
				work.cursor++
			}
		}
		if index < 0 {
			return
		}
		outcome := run_one(tests[index], dir, compiler, scratch, defines)
		lock work {
			work.outcomes << outcome
		}
	}
}

// run_one compiles a test, runs it, and reports the first thing that went
// wrong. A test that passes prints nothing and exits zero, so any output at all
// is a finding rather than noise to filter.
fn run_one(file string, dir string, compiler string, scratch string, defines []string) Outcome {
	path := os.join_path(dir, file)
	if needs_define(required_define(path), defines) {
		return Outcome{file, 'skip', 'needs -D${required_define(path)}'}
	}
	stem := file.all_before_last('.')
	mut flags := compile_flags
	for define in defines {
		flags += ' -D${define}'
	}
	exe := os.join_path(scratch, stem)
	build := os.execute('cd ${os.quoted_path(dir)} && ${os.quoted_path(compiler)} ${flags} ${os.quoted_path(file)} -o ${os.quoted_path(exe)} 2>&1')
	if build.exit_code != 0 {
		return Outcome{file, 'build', first_lines(build.output, 3)}
	}
	// each test gets its own directory: several write c99_stdio_*.txt, and one
	// directory for the whole run lets them read each other's leavings
	rundir := os.join_path(scratch, 'run', stem)
	// the parent is made once up front: eight workers creating `run/` at the same
	// time race inside mkdir_all, which reports File exists for a segment another
	// worker made a moment ago
	os.mkdir_all(rundir) or {}
	run := os.execute('cd ${os.quoted_path(rundir)} && ${os.quoted_path(exe)} 2>&1')
	if run.exit_code != 0 {
		return Outcome{file, 'run', first_lines(run.output, 3)}
	}
	// no `if finding := f(x); finding != '' {` here: V 0.5.2 ends the file with
	// `unexpected eof, expecting }` on that form, measured
	finding := finding_output(run.output)
	if finding != '' {
		return Outcome{file, 'output', first_lines(finding, 3)}
	}
	return Outcome{file, 'ok', ''}
}

// run_monolithic runs the corpus as one translation unit and reads its own
// summary line. It prints as it goes, so its contract is the count rather than
// silence.
fn run_monolithic(dir string, compiler string, scratch string) Outcome {
	exe := os.join_path(scratch, 'monolithic')
	build := os.execute('cd ${os.quoted_path(dir)} && ${os.quoted_path(compiler)} ${compile_flags} ${monolithic} -o ${os.quoted_path(exe)} 2>&1')
	if build.exit_code != 0 {
		return Outcome{monolithic, 'build', first_lines(build.output, 3)}
	}
	run := os.execute('cd ${os.quoted_path(scratch)} && ${os.quoted_path(exe)} 2>&1')
	mut summary := ''
	for line in run.output.split_into_lines() {
		if line.contains(' checks, ') && line.contains(' failed') {
			summary = line.trim_space()
		}
	}
	if run.exit_code != 0 || summary == '' {
		return Outcome{monolithic, 'run', 'exit ${run.exit_code}, ${first_lines(run.output, 3)}'}
	}
	if summary.all_before(' checks').int() < checks_floor {
		return Outcome{monolithic, 'run', '${summary} is below the floor of ${checks_floor} checks'}
	}
	return Outcome{monolithic, 'ok', summary}
}

// collect_tests is every numbered file in the corpus. `--only` narrows it to the
// names given, which is how one test gets looked at without waiting for nine
// hundred builds.
fn collect_tests(dir string, opts Options) []string {
	mut tests := []string{}
	for entry in os.ls(dir) or { []string{} } {
		if entry.len < 5 || entry[0] < `0` || entry[0] > `9` {
			continue
		}
		if !entry.ends_with('.c') && !entry.ends_with('.h') {
			continue
		}
		if opts.only.len > 0 && !matches_only(entry, opts.only) {
			continue
		}
		tests << entry
	}
	return tests.sorted()
}

// needs_define is true when a test says it wants a define that was not given.
// It exists as a function because V 0.5.2 does not parse the one-line form of
// this test: `if gate := f(x); gate != '' && !(gate in defines) {` ends the file
// with `unexpected eof, expecting }`, measured.
fn needs_define(gate string, defines []string) bool {
	if gate == '' {
		return false
	}
	for define in defines {
		if define == gate {
			return false
		}
	}
	return true
}

// required_define reads the `requires-define: NAME` line a gated test carries.
fn required_define(path string) string {
	text := os.read_file(path) or { return '' }
	for line in text.split_into_lines() {
		if line.contains('requires-define:') {
			return line.all_after('requires-define:').trim_space()
		}
	}
	return ''
}

fn matches_only(entry string, only []string) bool {
	for want in only {
		if entry == want || entry.starts_with(want) || entry.all_before('-') == want {
			return true
		}
	}
	return false
}

// build_compiler builds the tree under test, so the tests describe the current
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

// finding_output is the test's output with the corpus's section banners taken
// out. A widened test carries the `sec_begin("15b stdin redirected")` call that
// opened its section in the monolith, so it prints that line on the way to a
// check that holds; the banner is not a finding, anything else is.
fn finding_output(text string) string {
	mut kept := []string{}
	for line in text.trim_space().split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('[') && trimmed.ends_with(']') {
			continue
		}
		// the corpus prints this on purpose: `perror("expected failure (this
		// line is intentional)")`, compliance/monolithic.c:11634
		if trimmed.contains('expected failure (this line is intentional)') {
			continue
		}
		kept << trimmed
	}
	return kept.join(' / ')
}

// first_lines keeps a failure to a size someone will read: a compiler run prints
// hundreds of lines and the cause is at the front of them.
fn first_lines(text string, limit int) string {
	mut kept := []string{}
	for line in text.trim_space().split_into_lines() {
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
		match arg {
			'--compiler' {
				if i + 1 < args.len {
					opts.compiler = args[i + 1]
					i += 2
				} else {
					eprintln('compliance: --compiler needs a path')
					exit(1)
				}
			}
			'--define' {
				if i + 1 < args.len {
					opts.defines << args[i + 1]
					i += 2
				} else {
					eprintln('compliance: --define needs a name')
					exit(1)
				}
			}
			'--only' {
				i++
				for i < args.len && !args[i].starts_with('-') {
					opts.only << args[i]
					i++
				}
			}
			'-j', '--jobs' {
				if i + 1 < args.len {
					opts.jobs = args[i + 1].int()
					i += 2
				} else {
					eprintln('compliance: -j needs a number')
					exit(1)
				}
			}
			'--list' {
				opts.list = true
				i++
			}
			'--count' {
				opts.count = true
				i++
			}
			'-h', '--help' {
				usage()
				exit(0)
			}
			else {
				eprintln('compliance: unknown argument ${arg}')
				usage()
				exit(1)
			}
		}
	}
	return opts
}

fn usage() {
	println('usage: v run tools/compliance.vsh [--compiler PATH] [--define NAME]...')
	println('                                  [--only NNN]... [-j N] [--list] [--count]')
}

fn cleanup_paths(paths []string) {
	for stale in paths {
		os.rmdir_all(stale) or {}
	}
}
