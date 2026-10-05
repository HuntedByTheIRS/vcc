#!/usr/bin/env -S v run

// The test suite's inventory: the `*_test.v` files in this tree and the test
// functions in them, counted by the same walk in both modes. `v test .` runs
// the suite; this says how big it is, which is the number the README's tests
// badge is written from, so the count has one home instead of a hand-kept one.
//
//   v run tools/tests.vsh            # the count in each file, then the total
//   v run tools/tests.vsh --count    # the total alone, for the badge step
//
// A test is a top-level `fn test_...`, which is the shape `v test` collects: a
// helper sharing the prefix is a test to V as well, so it is one here too. The
// agent working state under `.omh/` is skipped, because nothing in it is the
// tree's.

import os

fn main() {
	root := os.dir(os.dir(@FILE))
	mut total := 0
	mut rows := []string{}
	for file in test_files(root) {
		count := count_tests(file)
		if count == 0 {
			continue
		}
		total += count
		rows << '${count}\t${file.replace('${root}/', '')}'
	}
	if '--count' in os.args[1..] {
		println(total)
		return
	}
	for row in rows {
		println(row)
	}
	println('tests: ${total} in ${rows.len} files')
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
