#!/usr/bin/env -S v run

// The test suite's inventory: the `*_test.v` files in this tree and the test
// functions in them, plus the C cases in the regression and goldens corpora,
// counted by the same walk in both modes. `v test .` runs the suite; this says
// how big it is, which is the number the README's tests badge is written from,
// so the count has one home instead of a hand-kept one.
//
//   v run tools/tests.vsh            # the count in each file, then the total
//   v run tools/tests.vsh --count    # the total alone, for the badge step
//
// A test is a top-level `fn test_...`, which is the shape `v test` collects: a
// helper sharing the prefix is a test to V as well, so it is one here too. The
// agent working state under `.omh/` is skipped, because nothing in it is the
// tree's.
//
// The C corpora count too, by the rule tools/regress.vsh collects by: the
// numbered .c files under regression/ and goldens/, one case each. A case is a
// test the badge should hold, because the run fails when the compiler stops
// behaving or the golden bytes move, and counting it by the runner's rule keeps
// the badge and the runner from disagreeing about what a case is. A corpus
// directory that is not there yet counts zero; the runner is the thing that
// says a corpus is missing.

import os

const corpora = ['regression', 'goldens']

fn main() {
	root := os.dir(os.dir(@FILE))
	mut total := 0
	mut rows := []string{}
	mut file_rows := 0
	for file in test_files(root) {
		count := count_tests(file)
		if count == 0 {
			continue
		}
		total += count
		file_rows++
		rows << '${count}	${file.replace('${root}/', '')}'
	}
	for corpus in corpora {
		count := count_cases(os.join_path(root, corpus))
		total += count
		rows << '${count}	${corpus}/'
	}
	if '--count' in os.args[1..] {
		println(total)
		return
	}
	for row in rows {
		println(row)
	}
	println('tests: ${total} in ${file_rows} files and ${corpora.len} corpora')
}

// count_cases is the numbered .c files in one corpus directory, the same rule
// tools/regress.vsh collects by. A directory that is not there counts zero
// rather than failing the badge.
fn count_cases(location string) int {
	mut count := 0
	for entry in os.ls(location) or { []string{} } {
		if entry.len < 5 || entry[0] < `0` || entry[0] > `9` {
			continue
		}
		if entry.ends_with('.c') {
			count++
		}
	}
	return count
}

// test_files is every `*_test.v` outside the agent working state. os.walk_ext
// reaches into `.omh/` the way gate.vsh's pure-V walk does, so it is named.
fn test_files(root string) []string {
	mut out := []string{}
	for file in os.walk_ext(root, '_test.v') {
		if file.contains('/.omh/') {
			continue
		}
		out << file
	}
	return out.sorted()
}

// count_tests is the top-level test functions in one file. Indentation is
// allowed for, though a test function is never indented, because a line count
// that depends on the author's spacing is a count that drifts.
fn count_tests(path string) int {
	mut count := 0
	lines := os.read_lines(path) or { return 0 }
	for line in lines {
		if line.trim_space().starts_with('fn test_') {
			count++
		}
	}
	return count
}
