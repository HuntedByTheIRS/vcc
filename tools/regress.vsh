#!/usr/bin/env -S v run

// Two corpora, one contract each, and both in the same shape: a directory per
// standard whose leaf name is the -std= spelling.
//
//   regression/<standards>/<dialect>/NNNN-group-individual.c
//     A program with `int main(void)`. It prints nothing and exits zero while
//     the compiler behaves; non-zero, or a line of output, is the regression
//     the file was added for.
//
//   goldens/<standards>/<dialect>/NNNN-group-individual.c
//     A program that prints to stdout and exits zero. Its stdout has to equal
//     NNNN-group-individual.expected byte for byte, because a golden is the
//     exact bytes and not a shape that resembles them. The .expected sits
//     beside its program in the same dialect directory.
//
// A case's directory is the standard it is compiled under, so `iso/c99/` is
// compiled -std=c99 and `gnu/gnu99/` -std=gnu99, and a case this compiler
// accepts only in a GNU dialect belongs in the `gnu/` tree beside its ISO
// sibling. A new standard is a new directory and not a change here.
//
//   v run tools/regress.vsh                        # build the tree, then run every case
//   v run tools/regress.vsh --compiler /tmp/vcc    # a compiler you already built
//   v run tools/regress.vsh --only 0001 0002       # the cases you name
//   v run tools/regress.vsh --define NAME          # include the gated cases
//   v run tools/regress.vsh --list                 # print what would run
//   v run tools/regress.vsh --count                # print how many cases there are
//   v run tools/regress.vsh --root /tmp/tree       # read the corpora from another tree
//
// Every case compiles with the standard of its directory, plus -w because a
// case is not required to be warning-clean under this compiler, -lm for the
// math a case may touch, and -x c so the compiler reads the file as C rather
// than guessing from a name it did not write.
//
// The floors below are the number of cases that landed in each corpus. Losing
// one is a failure and adding one is not, so they are floors and not
// equalities. A --only run names its cases and makes no claim about the corpus,
// so it is not held to them. --root exists so this runner can be exercised
// against a corpus in a scratch tree, which is what a runner written before its
// corpus needs.

import os
import time

// The floors are low-water marks: the gate fails if a corpus drops below them, so
// one goes up by one with each case added. Measured on this tree, the corpora hold
// 63 regression and 44 golden cases, well above what the floors ask for, which is
// the point of a floor rather than a tally.
const regression_floor = 63
const goldens_floor = 25

const compile_head = '-x c -std='
const compile_tail = ' -w -lm'

const regression_dir = 'regression'
const goldens_dir = 'goldens'

struct Options {
mut:
	compiler string
	root     string
	defines  []string
	only     []string
	jobs     int
	list     bool
	count    bool
}

// Suite is one dialect directory of one corpus, with its own name as the -std=
// spelling and the cases collected from it.
struct Suite {
	key   string
	kind  string
	rel   string
	dir   string
	mode  string
	files []string
}

// Case is one file to compile and run, the corpus it came from, which decides
// the contract its run is held to, and the standard of the directory it sits in.
struct Case {
	kind  string
	suite string
	dir   string
	mode  string
	file  string
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
	root := if opts.root != '' { opts.root } else { os.dir(os.dir(@FILE)) }
	for corpus in [regression_dir, goldens_dir] {
		if !os.exists(os.join_path(root, corpus)) {
			eprintln('regress: ${corpus} is missing from ${root}')
			exit(1)
		}
	}
	if opts.count {
		// the number of cases in both corpora, whatever --only would narrow it
		// to. The regressions badge in README.md records it as the corpus size
		// and counts failing cases separately, so this number and that count
		// come from the same code that decides what a case is.
		println(total_cases(root))
		return
	}
	suites := collect_suites(root, opts)
	cases := flatten(suites)
	if cases.len == 0 {
		eprintln('regress: no cases in ${root}')
		exit(1)
	}
	if opts.list {
		for one in cases {
			println('${one.kind}/${one.suite}/${one.file}')
		}
		return
	}
	built_here := opts.compiler == ''
	compiler := if built_here { build_compiler(root) } else { opts.compiler }
	scratch := os.join_path(os.temp_dir(), 'vcc-regress-${os.getpid()}')
	os.mkdir_all(scratch) or {
		eprintln('regress: no scratch directory: ${err}')
		exit(1)
	}
	// the suite directories are made once up front: several workers creating
	// `run/regression/iso-c99` at the same time race inside mkdir_all, which
	// reports File exists for a segment another worker made a moment ago
	for suite in suites {
		os.mkdir_all(os.join_path(scratch, 'run', suite.kind, suite_slug(suite.rel))) or {}
	}
	mut cleanup := [scratch]
	if built_here {
		cleanup << compiler
	}
	mut regression_cases := 0
	mut goldens_cases := 0
	for one in cases {
		if one.kind == regression_dir {
			regression_cases++
		} else {
			goldens_cases++
		}
	}
	for suite in suites {
		println('regress:    ${suite.key}: ${suite.files.len} cases (-std=${suite.mode})')
	}
	println('cases:      ${regression_cases} regression, ${goldens_cases} golden')
	println('compiler:   ${compiler}')

	started := time.ticks()
	shared work := Work{}
	mut threads := []thread{}
	for _ in 0 .. worker_count(opts) {
		threads << spawn run_all(cases, compiler, scratch, opts.defines, shared work)
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

	// every collected file counts towards the floor whether it ran, failed or
	// was skipped: the floor is about the corpus not losing cases. A --only run
	// names its cases and makes no claim about the corpus, so it is not held to
	// a full run's floors.
	if opts.only.len == 0 {
		if regression_cases < regression_floor {
			problems << 'only ${regression_cases} regression cases, below the floor of ${regression_floor}'
		}
		if goldens_cases < goldens_floor {
			problems << 'only ${goldens_cases} golden cases, below the floor of ${goldens_floor}'
		}
	}
	if problems.len > 0 {
		eprintln('')
		for problem in problems {
			eprintln('regress: ${problem}')
		}
		eprintln('')
		eprintln('regress: ${problems.len} problem(s)')
		cleanup_paths(cleanup)
		exit(1)
	}
	cleanup_paths(cleanup)
	println('')
	println('regress: every case holds')
}

// worker_count keeps the machine usable: every case compiles, and the compiler
// under test is not a small program.
fn worker_count(opts Options) int {
	if opts.jobs > 0 {
		return opts.jobs
	}
	return 8
}

// collect_suites walks <corpus>/<standards>/<dialect>/ for both corpora and
// collects the cases in each dialect directory. A .c directly under a corpus or
// directly under a standards tree is not a case: the dialect directory is where
// cases live.
fn collect_suites(root string, opts Options) []Suite {
	mut suites := []Suite{}
	for corpus in [regression_dir, goldens_dir] {
		corpus_path := os.join_path(root, corpus)
		for standards in os.ls(corpus_path) or { []string{} } {
			standards_dir := os.join_path(corpus_path, standards)
			if !os.is_dir(standards_dir) {
				continue
			}
			for dialect in os.ls(standards_dir) or { []string{} } {
				dialect_dir := os.join_path(standards_dir, dialect)
				if !os.is_dir(dialect_dir) {
					continue
				}
				rel := os.join_path(standards, dialect)
				suites << Suite{
					key:   '${corpus}/${rel}'
					kind:  corpus
					rel:   rel
					dir:   dialect_dir
					mode:  dialect
					files: collect_cases(dialect_dir, opts)
				}
			}
		}
	}
	suites.sort(a.key < b.key)
	return suites
}

// flatten is every collected case with the corpus and the dialect it belongs
// to, which is the order the workers pull from.
fn flatten(suites []Suite) []Case {
	mut cases := []Case{}
	for suite in suites {
		for file in suite.files {
			cases << Case{
				kind:  suite.kind
				suite: suite.rel
				dir:   suite.dir
				mode:  suite.mode
				file:  file
			}
		}
	}
	return cases
}

// total_cases counts both corpora, for the badge.
fn total_cases(root string) int {
	mut count := 0
	for suite in collect_suites(root, Options{}) {
		count += suite.files.len
	}
	return count
}

// suite_slug names a suite's scratch directories: `iso/c99` becomes `iso-c99`.
fn suite_slug(rel string) string {
	return rel.replace('/', '-')
}

// run_all runs cases until the queue is empty. The queue is shared, so the
// cursor moves under a lock and the thread count decides how many compilers run
// at once.
fn run_all(cases []Case, compiler string, scratch string, defines []string, shared work Work) {
	for {
		mut index := -1
		lock work {
			if work.cursor < cases.len {
				index = work.cursor
				work.cursor++
			}
		}
		if index < 0 {
			return
		}
		outcome := run_one(cases[index], compiler, scratch, defines)
		lock work {
			work.outcomes << outcome
		}
	}
}

// run_one compiles a case under the standard of its directory and runs it under
// the contract its corpus gives it, reporting the first thing that went wrong.
fn run_one(one Case, compiler string, scratch string, defines []string) Outcome {
	path := os.join_path(one.dir, one.file)
	label := '${one.kind}/${one.suite}/${one.file}'
	gate := required_define(path)
	if needs_define(gate, defines) {
		return Outcome{label, 'skip', 'needs -D${gate}'}
	}
	stem := one.file.all_before_last('.')
	slug := suite_slug(one.suite)
	flags := case_flags(one.mode, defines)
	// the corpus and the dialect are part of the binary's name: a golden and a
	// regression case may share a number and a stem
	exe := os.join_path(scratch, '${one.kind}-${slug}-${stem}')
	build := os.execute('cd ${os.quoted_path(one.dir)} && ${os.quoted_path(compiler)} ${flags} ${os.quoted_path(one.file)} -o ${os.quoted_path(exe)} 2>&1')
	if build.exit_code != 0 {
		return Outcome{label, 'build', first_lines(build.output, 3)}
	}
	rundir := os.join_path(scratch, 'run', one.kind, slug, stem)
	os.mkdir_all(rundir) or {}
	if one.kind == goldens_dir {
		return run_golden(label, one.file, one.dir, exe, rundir)
	}
	// a regression case passes by saying nothing: the compiler's own warnings
	// are off with -w, so any line at all is something the case did not mean to
	// print
	run := os.execute('cd ${os.quoted_path(rundir)} && ${os.quoted_path(exe)} 2>&1')
	if run.exit_code != 0 {
		return Outcome{label, 'run', exit_detail(run)}
	}
	finding := run.output.trim_space()
	if finding != '' {
		return Outcome{label, 'output', first_lines(finding, 3)}
	}
	return Outcome{label, 'ok', ''}
}

// case_flags is the compile line for one dialect: the standard is the
// directory's own name, and the defines are the ones --define named.
fn case_flags(mode string, defines []string) string {
	mut flags := '${compile_head}${mode}${compile_tail}'
	for define in defines {
		flags += ' -D${define}'
	}
	return flags
}

// run_golden holds a case to the bytes in its .expected file. stdout and stderr
// go to files of their own, because the comparison is the program's stdout and
// not whatever a shell or a runtime might add to the stream. The file name is
// asked for rather than read off the label, because the label carries the
// dialect and `all_after('/')` would answer behind the first slash.
fn run_golden(label string, file string, location string, exe string, rundir string) Outcome {
	stem := file.all_before_last('.')
	expected := os.join_path(location, '${stem}.expected')
	if !os.exists(expected) {
		return Outcome{label, 'golden', 'no ${stem}.expected beside it'}
	}
	out_path := os.join_path(rundir, 'stdout')
	err_path := os.join_path(rundir, 'stderr')
	run := os.execute('cd ${os.quoted_path(rundir)} && ${os.quoted_path(exe)} > ${os.quoted_path(out_path)} 2> ${os.quoted_path(err_path)}')
	if run.exit_code != 0 {
		stderr_text := os.read_file(err_path) or { '' }
		mut detail := 'exit ${run.exit_code}'
		if stderr_text.trim_space() != '' {
			detail += ', ${first_lines(stderr_text, 3)}'
		}
		return Outcome{label, 'run', detail}
	}
	got := os.read_file(out_path) or { return Outcome{label, 'golden', 'the run left no stdout to read'} }
	want := os.read_file(expected) or { return Outcome{label, 'golden', 'the expected file could not be read'} }
	if got != want {
		return Outcome{label, 'output', first_lines(describe_diff(want, got), 3)}
	}
	return Outcome{label, 'ok', ''}
}

// exit_detail names the status a run died with, and keeps whatever the program
// printed on the way, which is usually where the cause is.
fn exit_detail(run os.Result) string {
	mut detail := 'exit ${run.exit_code}'
	if run.output.trim_space() != '' {
		detail += ', ${first_lines(run.output, 3)}'
	}
	return detail
}

// describe_diff names the first lines where the two streams part, and falls
// back to a byte-level note when every line agrees and only the trailing bytes
// differ.
fn describe_diff(want string, got string) string {
	want_lines := want.split_into_lines()
	got_lines := got.split_into_lines()
	mut limit := want_lines.len
	if got_lines.len > limit {
		limit = got_lines.len
	}
	mut shown := []string{}
	mut i := 0
	for i < limit && shown.len < 3 {
		w := if i < want_lines.len { want_lines[i] } else { '<nothing>' }
		g := if i < got_lines.len { got_lines[i] } else { '<nothing>' }
		if w != g {
			shown << 'line ${i + 1}: want ${w} got ${g}'
		}
		i++
	}
	if shown.len == 0 {
		return 'stdout differs by trailing bytes'
	}
	return shown.join(' / ')
}

// collect_cases is every numbered .c in a dialect directory. `--only` narrows
// it to the names given, which is how one case gets looked at without building
// the whole corpus.
fn collect_cases(dir string, opts Options) []string {
	mut files := []string{}
	for entry in os.ls(dir) or { []string{} } {
		if entry.len < 5 || entry[0] < `0` || entry[0] > `9` {
			continue
		}
		if !entry.ends_with('.c') {
			continue
		}
		if opts.only.len > 0 && !matches_only(entry, opts.only) {
			continue
		}
		files << entry
	}
	return files.sorted()
}

// needs_define is true when a case says it wants a define that was not given.
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

// required_define reads the `requires-define: NAME` line a gated case carries.
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

// build_compiler builds the tree under test, so the cases describe the current
// source rather than a binary from an earlier edit.
fn build_compiler(root string) string {
	path := os.join_path(os.temp_dir(), 'vcc-regress-vcc-${os.getpid()}')
	result := os.execute('cd ${os.quoted_path(root)} && v -o ${os.quoted_path(path)} . 2>&1')
	if result.exit_code != 0 {
		eprintln('regress: the compiler did not build:')
		eprintln(result.output)
		exit(1)
	}
	return path
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
					eprintln('regress: --compiler needs a path')
					exit(1)
				}
			}
			'--root' {
				if i + 1 < args.len {
					opts.root = args[i + 1]
					i += 2
				} else {
					eprintln('regress: --root needs a path')
					exit(1)
				}
			}
			'--define' {
				if i + 1 < args.len {
					opts.defines << args[i + 1]
					i += 2
				} else {
					eprintln('regress: --define needs a name')
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
					eprintln('regress: -j needs a number')
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
				eprintln('regress: unknown argument ${arg}')
				usage()
				exit(1)
			}
		}
	}
	return opts
}

fn usage() {
	println('usage: v run tools/regress.vsh [--compiler PATH] [--root PATH] [--define NAME]...')
	println('                               [--only NNN]... [-j N] [--list] [--count]')
}

fn cleanup_paths(paths []string) {
	for stale in paths {
		// a scratch directory and the compiler built beside it: rmdir_all takes
		// the directory, rm takes the file, and either one is silent when the
		// path has already gone
		os.rmdir_all(stale) or {}
		os.rm(stale) or {}
	}
}
