#!/usr/bin/env -S v run

// The local gate: the checks a pull request has to pass, runnable before pushing
// so that CI never holds an opinion the author did not already know.
//
//   v run tools/gate.vsh
//
// Five steps: formatting, the pure-V rule, the build, the test suite, and the
// links between the documents at the root. Each one reports on its own line, and
// the exit status is zero only when all of them pass.

import os

const c_source_extensions = ['.c', '.h', '.cc', '.cpp', '.hpp', '.S', '.s']

fn main() {
	root := os.dir(os.dir(@FILE))
	println('gate: ${root}')
	mut failures := []string{}
	report('formatting', check_formatting(root), mut failures)
	report('pure V', check_pure_v(root), mut failures)
	report('build', check_build(root), mut failures)
	report('tests', check_tests(root), mut failures)
	report('documents', check_documents(root), mut failures)
	if failures.len > 0 {
		eprintln('')
		eprintln('gate: ${failures.len} step(s) failed: ${failures.join(', ')}')
		exit(1)
	}
	println('')
	println('gate: everything passes')
}

// report prints one step's verdict and keeps its name for the summary, so a
// failure says which gate closed rather than only what it printed.
fn report(name string, problems []string, mut failures []string) {
	print('  ${name}: ')
	if problems.len == 0 {
		println('ok')
		return
	}
	println('failed')
	for problem in problems {
		eprintln('    ${problem}')
	}
	failures << name
}

// check_formatting asks `v fmt -verify`, the same formatter every contributor
// runs. A gate using a different one would be a second opinion nobody asked for.
fn check_formatting(root string) []string {
	result := run(root, 'v fmt -verify .')
	if result.exit_code == 0 {
		return []
	}
	mut problems := []string{}
	for line in result.output.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.contains('is not formatted') || trimmed.starts_with('diff ') {
			problems << trimmed
		}
	}
	if problems.len == 0 {
		problems << 'v fmt -verify failed: ${result.output.trim_space()}'
	}
	return problems
}

// check_pure_v enforces the first constraint by looking for what breaks it: C
// sources in the tree, and C interop in the compiler's own sources. The scripts
// under tools/ are skipped, because they name these patterns on purpose.
fn check_pure_v(root string) []string {
	mut problems := []string{}
	for extension in c_source_extensions {
		for file in os.walk_ext(root, extension) {
			problems << '${file.replace('${root}/', '')}: C source in a tree that is V only'
		}
	}
	interop := ['#include ', '#flag ', 'C.']
	for file in os.walk_ext(root, '.v') {
		if file.contains('/tools/') || file.contains('/.omh/') {
			continue
		}
		relative := file.replace('${root}/', '')
		lines := os.read_lines(file) or { continue }
		for i, line in lines {
			trimmed := line.trim_space()
			if trimmed.starts_with('//') {
				continue
			}
			for pattern in interop {
				if trimmed.contains(pattern) {
					problems << '${relative}:${i + 1}: ${pattern.trim_space()} brings C into the compiler'
				}
			}
		}
	}
	return problems
}

fn check_build(root string) []string {
	binary := os.join_path(os.temp_dir(), 'vcc-gate-${os.getpid()}')
	result := run(root, 'v -o ${os.quoted_path(binary)} .')
	os.rm(binary) or {}
	if result.exit_code != 0 {
		return ['the compiler did not build: ${result.output.trim_space()}']
	}
	return []
}

fn check_tests(root string) []string {
	result := run(root, 'v test .')
	if result.exit_code == 0 {
		return []
	}
	// The failing lines and the summary are what someone needs without scrolling
	// through the whole run.
	mut problems := []string{}
	for line in result.output.split_into_lines() {
		if line.starts_with('FAIL') || line.contains('Summary for all V') {
			problems << line.trim_space()
		}
	}
	if problems.len == 0 {
		problems << 'v test failed: ${result.output.trim_space()}'
	}
	return problems
}

// check_documents follows the relative links between the documents. One pointing
// at a file that moved is worse than no link at all.
fn check_documents(root string) []string {
	mut problems := []string{}
	for file in os.walk_ext(root, '.md') {
		if file.contains('/.omh/') {
			continue
		}
		relative := file.replace('${root}/', '')
		lines := os.read_lines(file) or { continue }
		for i, line in lines {
			for target in link_targets(line) {
				if target.starts_with('http') || target.starts_with('mailto')
					|| target.starts_with('#') {
					continue
				}
				path := target.split('#')[0]
				if path == '' {
					continue
				}
				resolved := if path.starts_with('/') {
					os.join_path(root, path[1..])
				} else {
					os.join_path(os.dir(file), path)
				}
				if !os.exists(resolved) {
					problems << '${relative}:${i + 1}: ${target} does not exist'
				}
			}
		}
	}
	return problems
}

// link_targets pulls the targets out of markdown links written on one line, which
// is how every link in these documents is written.
fn link_targets(line string) []string {
	mut out := []string{}
	mut rest := line
	for {
		start := rest.index('](') or { break }
		rest = rest[start + 2..]
		end := rest.index(')') or { break }
		out << rest[..end]
		rest = rest[end..]
	}
	return out
}

fn run(root string, command string) os.Result {
	return os.execute('cd ${os.quoted_path(root)} && ${command} 2>&1')
}
