#!/usr/bin/env -S v run

// The front door over the work this tree asks a person to run: build the
// compiler, the gate, the two C corpora, the benchmark, the image, and the
// version report. Every step calls the runner that already owns it, so no count
// or floor lives here to drift; --list names the steps.
//
// The compiler is built under the temp directory for the steps that only need
// one to run cases, and `build -o PATH` puts it where a person wants it. `all`
// runs every step even when one fails, and exits non-zero if any failed. A step
// whose tool is missing is skipped, and fails only when asked for by name.

import os
import time

// The default run: the compiler, then the gate, then both corpora. The gate
// runs `v test .` itself, so the suite is not a step of its own here.
const default_steps = ['build', 'gate', 'compliance', 'regress']

// What `all` runs, each step once; `corpora` is those two runners together.
const every_step = ['build', 'gate', 'test', 'compliance', 'regress', 'bench', 'docker', 'version']

struct Context {
mut:
	root     string
	scratch  string
	compiler string
}

struct Outcome {
mut:
	verdict Verdict
	name    string
	detail  string
	seconds f64
}

enum Verdict {
	passed
	failed
	skipped
}

fn main() {
	mut ctx := Context{
		root:    os.dir(os.dir(@FILE))
		scratch: os.join_path(os.temp_dir(), 'vcc-build-${os.getpid()}')
	}
	args := os.args[1..]
	if args.len == 0 {
		finish(mut ctx, run_all(mut ctx, default_steps, []), false)
		return
	}
	step := args[0]
	if step in ['-h', '--help', '--list', '-l'] {
		usage()
		return
	}
	if step == 'all' {
		finish(mut ctx, run_all(mut ctx, every_step, []), false)
		return
	}
	if step != 'corpora' && step !in every_step {
		eprintln('build: unknown step ${step}')
		usage()
		exit(1)
	}
	finish(mut ctx, run_all(mut ctx, [step], args[1..]), true)
}

// run_all prints each verdict as it lands; a failure does not stop the rest.
fn run_all(mut ctx Context, names []string, args []string) []Outcome {
	mut outcomes := []Outcome{}
	for name in names {
		outcome := run_step(mut ctx, name, args)
		print_outcome(outcome)
		outcomes << outcome
	}
	return outcomes
}

fn run_step(mut ctx Context, name string, args []string) Outcome {
	started := time.now()
	mut outcome := Outcome{ name: name }
	match name {
		'build' { outcome = step_build(mut ctx, args) }
		'test' { outcome = step_runner(mut ctx, 'test', 'v test .', args) }
		'gate' { outcome = step_runner(mut ctx, 'gate', 'v run tools/gate.vsh', args) }
		'bench' { outcome = step_runner(mut ctx, 'bench', 'v run tools/bench.vsh', args) }
		'compliance' { outcome = step_corpus(mut ctx, 'compliance', 'v run tools/compliance.vsh') }
		'regress' { outcome = step_corpus(mut ctx, 'regress', 'v run tools/regress.vsh') }
		'corpora' { outcome = step_corpora(mut ctx) }
		'docker' { outcome = step_docker(mut ctx) }
		'version' { outcome = step_version(mut ctx) }
		else {}
	}
	outcome.seconds = time.since(started).seconds()
	return outcome
}

// step_build is the one place a binary is asked for by name. With -o it lands
// where the caller said, otherwise under the temp directory for the runners.
fn step_build(mut ctx Context, args []string) Outcome {
	mut path := os.join_path(ctx.scratch, 'vcc')
	if args.len > 0 {
		if args[0] != '-o' || args.len < 2 {
			return failed('build', 'only -o PATH is taken here')
		}
		path = args[1]
	}
	os.mkdir_all(os.dir(path)) or {}
	if run_in(ctx.root, 'v -o ${os.quoted_path(path)} .') != 0 {
		return failed('build', 'the compiler did not build')
	}
	ctx.compiler = path
	return Outcome{ verdict: .passed, name: 'build', detail: if args.len > 0 { path } else { '' } }
}

// step_runner passes arguments through, so bench keeps its flags.
fn step_runner(mut ctx Context, name string, command string, args []string) Outcome {
	mut full := command
	for arg in args {
		full += ' ${os.quoted_path(arg)}'
	}
	if run_in(ctx.root, full) != 0 {
		return failed(name, 'exit non-zero')
	}
	return Outcome{ verdict: .passed, name: name }
}

// ensure_compiler builds the tree once into the scratch directory, so the two
// corpus runners do not each build it again.
fn ensure_compiler(mut ctx Context) string {
	if ctx.compiler != '' {
		return ctx.compiler
	}
	os.mkdir_all(ctx.scratch) or {}
	path := os.join_path(ctx.scratch, 'vcc')
	if run_in(ctx.root, 'v -o ${os.quoted_path(path)} .') != 0 {
		return ''
	}
	ctx.compiler = path
	return path
}

// step_corpus hands the runner a compiler and lets it keep its own floors.
fn step_corpus(mut ctx Context, name string, command string) Outcome {
	compiler := ensure_compiler(mut ctx)
	if compiler == '' {
		return failed(name, 'the compiler did not build')
	}
	if run_in(ctx.root, '${command} --compiler ${os.quoted_path(compiler)}') != 0 {
		return failed(name, 'exit non-zero')
	}
	return Outcome{ verdict: .passed, name: name }
}

// step_corpora runs both runners even if the first fails, so both answers land.
fn step_corpora(mut ctx Context) Outcome {
	mut broken := []string{}
	if step_corpus(mut ctx, 'compliance', 'v run tools/compliance.vsh').verdict != .passed {
		broken << 'compliance'
	}
	if step_corpus(mut ctx, 'regress', 'v run tools/regress.vsh').verdict != .passed {
		broken << 'regress'
	}
	if broken.len > 0 {
		return failed('corpora', '${broken.join(' and ')} failed')
	}
	return Outcome{ verdict: .passed, name: 'corpora' }
}

// step_docker builds the image from the committed Dockerfile, copies the binary
// out of a container, asks its version, and hands it a program to compile and
// run. The build clones V at the pinned commit, so the line before it warns.
fn step_docker(mut ctx Context) Outcome {
	if (os.find_abs_path_of_executable('docker') or { '' }) == '' {
		return Outcome{ verdict: .skipped, name: 'docker', detail: 'docker is not on PATH' }
	}
	os.mkdir_all(ctx.scratch) or {}
	image := 'vcc-build-${os.getpid()}'
	println('docker: building ${image} from the Dockerfile, which clones V at the pinned commit and builds it; this takes minutes')
	if run_in(ctx.root, 'docker build -t ${image} .') != 0 {
		docker_cleanup('', image)
		return failed('docker', 'docker build exited non-zero')
	}
	id := capture('docker create ${image}').trim_space()
	binary := os.join_path(ctx.scratch, 'vcc-docker')
	if id == '' || run_in('', 'docker cp ${id}:/vcc ${os.quoted_path(binary)}') != 0 {
		docker_cleanup(id, image)
		return failed('docker', 'the container gave up no /vcc')
	}
	answer := capture('${os.quoted_path(binary)} --version').trim_space()
	program := os.join_path(ctx.scratch, 'seven.c')
	exe := os.join_path(ctx.scratch, 'seven')
	os.write_file(program, 'int main(void) { return 7; }\n') or {
		docker_cleanup(id, image)
		return failed('docker', 'could not write a test program: ${err}')
	}
	if run_in(ctx.scratch, '${os.quoted_path(binary)} ${os.quoted_path(program)} -o ${os.quoted_path(exe)}') != 0 {
		docker_cleanup(id, image)
		return failed('docker', 'the copied binary could not compile a program')
	}
	status := run_in(ctx.scratch, os.quoted_path(exe))
	docker_cleanup(id, image)
	if answer == '' {
		return failed('docker', 'the copied binary did not answer --version')
	}
	if status != 7 {
		return failed('docker', 'the compiled program exited ${status}, and its source says 7')
	}
	return Outcome{ verdict: .passed, name: 'docker', detail: answer }
}

// step_version prints the three facts that drift: the binary, v.mod, ci.yml.
fn step_version(mut ctx Context) Outcome {
	root := ctx.root
	mut binary := os.join_path(root, 'vcc')
	built := !os.exists(binary)
	if built {
		binary = ensure_compiler(mut ctx)
		if binary == '' {
			return failed('version', 'the compiler did not build')
		}
	}
	answer := capture('${os.quoted_path(binary)} --version').trim_space()
	named := read_named(root, 'v.mod', 'version:')
	pin := read_named(os.join_path(root, '.github', 'workflows'), 'ci.yml', 'V_COMMIT:')
	println('binary:  ${answer}${if built { ' (built for this run)' } else { '' }}')
	println('v.mod:   ${named}')
	println('V pin:   ${pin} (.github/workflows/ci.yml)')
	if named != '' && answer != '' && !answer.contains(named) {
		println('drift:   the binary and v.mod name different versions')
	}
	if answer == '' || named == '' || pin == '' {
		return failed('version', 'a fact is missing: binary "${answer}", v.mod "${named}", ci.yml "${pin}"')
	}
	return Outcome{ verdict: .passed, name: 'version' }
}

// finish cleans the scratch directory and says which steps failed or skipped.
fn finish(mut ctx Context, outcomes []Outcome, named bool) {
	os.rmdir_all(ctx.scratch) or {}
	mut failed_steps := []string{}
	mut skipped_steps := []string{}
	for outcome in outcomes {
		match outcome.verdict {
			.failed { failed_steps << outcome.name }
			.skipped { skipped_steps << outcome.name }
			.passed {}
		}
	}
	println('')
	if skipped_steps.len > 0 {
		println('build: skipped ${skipped_steps.join(', ')}')
	}
	if failed_steps.len > 0 {
		eprintln('build: ${failed_steps.len} step(s) failed: ${failed_steps.join(', ')}')
		exit(1)
	}
	if named && skipped_steps.len > 0 {
		eprintln('build: ${skipped_steps.join(', ')} was asked for and could not run')
		exit(1)
	}
	println('build: everything passes')
}

fn print_outcome(outcome Outcome) {
	detail := if outcome.detail != '' { '  ${outcome.detail}' } else { '' }
	println('  ${outcome.name}: ${outcome.verdict} (${outcome.seconds:.1f}s)${detail}')
}

// read_named reads one `key: value` line, so neither fact is copied into here.
fn read_named(root string, file string, key string) string {
	text := os.read_file(os.join_path(root, file)) or { return '' }
	for line in text.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with(key) {
			return trimmed.all_after(key).trim_space().trim("'")
		}
	}
	return ''
}

fn docker_cleanup(id string, image string) {
	if id != '' {
		os.system('docker rm -f ${id} >/dev/null 2>&1')
	}
	os.system('docker rmi -f ${image} >/dev/null 2>&1')
}

fn run_in(root string, command string) int {
	if root == '' {
		return os.system(command)
	}
	return os.system('cd ${os.quoted_path(root)} && ${command}')
}

// capture is stdout alone. V's os.execute folds stderr into the same stream, so a
// warning beside the value would land in it; stderr is sent away before reading.
fn capture(command string) string {
	return os.execute('${command} 2>/dev/null').output
}

fn failed(name string, detail string) Outcome {
	return Outcome{ verdict: .failed, name: name, detail: detail }
}

fn usage() {
	println('usage: v run tools/build.vsh [STEP] [args]')
	println('  build [-o PATH]   build the compiler only')
	println('  test              the unit suite, `v test .`')
	println('  gate              tools/gate.vsh')
	println('  compliance        the corpus under compliance/, a directory per standard')
	println('  regress           the regression and golden corpora')
	println('  corpora           compliance and regress together')
	println('  bench [args]      tools/bench.vsh, args passed through')
	println('  docker            build the image, then run the binary in it')
	println('  version           the binary, v.mod, and the pinned V commit')
	println('  all               every step, then a summary')
	println('with no step: build the compiler, then the gate, then both corpora')
}
