#!/usr/bin/env -S v run

// The local gate: the checks a pull request has to pass, runnable before pushing
// so that CI never holds an opinion the author did not already know.
//
//   v run tools/gate.vsh
//
// Six steps: formatting, the pure-V rule, the build, the test suite, the links
// between the documents at the root, and the workflows. Each one reports on its
// own line, and the exit status is zero only when all of them pass.

import os

const c_source_extensions = ['.c', '.h', '.cc', '.cpp', '.hpp', '.S', '.s']

// The directories that may hold C, as input to the compiler rather than as part
// of it: the C99 corpus under compliance/, one program per fixed bug under
// regression/, and the recorded-output programs under goldens/.
const test_c_directories = ['compliance/', 'regression/', 'goldens/']

fn main() {
	root := os.dir(os.dir(@FILE))
	println('gate: ${root}')
	mut failures := []string{}
	report('formatting', check_formatting(root), mut failures)
	report('pure V', check_pure_v(root), mut failures)
	report('build', check_build(root), mut failures)
	report('tests', check_tests(root), mut failures)
	report('documents', check_documents(root), mut failures)
	report('workflows', check_workflows(root), mut failures)
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
// sources in the tree, and C interop in the compiler's own sources. A test
// directory holds C the compiler is handed rather than C the compiler is built
// from, so a C source there is the directory's purpose and not a break in the
// rule: compliance/ is the C99 corpus, regression/ one program per bug that must
// not come back, goldens/ the programs whose output is compared against a
// recording. Everywhere else a C source is a failure. The interop scan below has
// no such exception for a test directory, because a .v file there is still this
// compiler's source; tools/ and .omh/ are the only places skipped there, since
// the scripts and the agent notes name these patterns on purpose.
fn check_pure_v(root string) []string {
	mut problems := []string{}
	for extension in c_source_extensions {
		for file in os.walk_ext(root, extension) {
			if is_c_input_directory(file, root) {
				continue
			}
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

// is_c_input_directory reports whether a path sits under one of the directories
// that hold C as input to the compiler rather than as part of it. The slash is
// part of the prefix, so a file named goldens-old.c at the root is not mistaken
// for one inside goldens/.
fn is_c_input_directory(file string, root string) bool {
	for directory in test_c_directories {
		if file.starts_with('${root}/${directory}') {
			return true
		}
	}
	return false
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
	// Which file failed is not the whole of what someone needs: V prints the failing
	// function and the assertion under the FAIL line, up to a rule of dashes, and
	// keeping only the FAIL lines made a CI failure say which file failed and never
	// why. Measured on V 0.5.2, the shape is
	//
	//   FAIL    10.405 ms /path/x_test.v
	//   /path/x_test.v:4: fn test_name
	//      > assert 1 == 2
	//        Left value (len: 1): `1`
	//   --------------------------------------------------------------------------
	//
	// and the reason is the lines between the first and the third.
	mut problems := []string{}
	mut under_failure := false
	for line in result.output.split_into_lines() {
		if line.starts_with('FAIL') {
			under_failure = true
			problems << line.trim_space()
			continue
		}
		if under_failure && line.starts_with('---') {
			under_failure = false
			continue
		}
		if line.contains('Summary for all V') {
			under_failure = false
			problems << line.trim_space()
			continue
		}
		if under_failure {
			problems << line.trim_space()
		}
	}
	if problems.len == 0 {
		problems << 'v test failed: ${result.output.trim_space()}'
	}
	return problems
}

// check_workflows reads the CI configuration for the two things the files cannot
// check about themselves: every workflow pins the same V commit, and every action
// is pinned to a version rather than to a branch that moves under it.
//
// Two workflows that pin different V commits would be testing two compilers and
// calling it one CI, and the failure would look like flakiness rather than like
// the disagreement it is.
fn check_workflows(root string) []string {
	mut problems := []string{}
	mut pinned := map[string]string{}
	workflows := os.walk_ext(os.join_path(root, '.github', 'workflows'), '.yml')
	if workflows.len == 0 {
		problems << 'no workflows under .github/workflows'
		return problems
	}
	for file in workflows {
		name := os.file_name(file)
		mut commit := ''
		for line in os.read_lines(file) or { continue } {
			trimmed := line.trim_space()
			if trimmed.starts_with('V_COMMIT:') {
				commit = value_after(trimmed, ':')
				if commit.len != 40 || !is_hex(commit) {
					problems << '${name}: V_COMMIT is not a 40-character commit hash'
				}
			}
			if trimmed.starts_with('- uses:') || trimmed.starts_with('uses:') {
				target := value_after(trimmed, 'uses:')
				at := target.last_index('@') or { -1 }
				if at >= 0 && !target[at + 1..].starts_with('v') {
					problems << '${name}: ${target} is not pinned to a version'
				}
			}
		}
		if commit == '' {
			problems << '${name}: no V_COMMIT, so nothing says which V it runs against'
			continue
		}
		pinned[name] = commit
	}
	mut by_commit := map[string][]string{}
	for name, commit in pinned {
		// The append has to go back into the map: appending to a missing map
		// value lands in a temporary and is dropped.
		mut names := by_commit[commit] or { []string{} }
		names << name
		by_commit[commit] = names
	}
	if by_commit.len > 1 {
		mut described := []string{}
		for commit, names in by_commit {
			described << '${commit[..8]} (${names.join(', ')})'
		}
		problems << 'the workflows pin different V commits: ${described.join('; ')}'
	}
	return problems
}

fn value_after(line string, separator string) string {
	at := line.index(separator) or { return '' }
	return line[at + separator.len..].trim_space()
}

fn is_hex(text string) bool {
	for character in text {
		if !(character >= `0` && character <= `9`) && !(character >= `a` && character <= `f`) {
			return false
		}
	}
	return true
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
