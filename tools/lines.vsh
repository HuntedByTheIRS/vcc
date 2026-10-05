#!/usr/bin/env -S v run

// The compiler's size: the `.v` files this tree tracks that are not tests, and
// the lines in them. `v test .` says the compiler works and tools/tests.vsh says
// how many tests there are; this says how much compiler there is, and it is the
// number the README's lines badge is written from, so the count has one home.
//
//   v run tools/lines.vsh            # the lines in each module, then the total
//   v run tools/lines.vsh --count    # the total alone, for the badge step
//
// What counts as the compiler: a `.v` file the tree tracks, minus `*_test.v`,
// which is a test rather than compiler code. `tools/` is out, because a script
// that checks the compiler is not the compiler, and `linking/` is in from the
// start, so it holds zero today and counts itself the day the linker is written.
//
// The files come from `git ls-files` rather than from a walk of the directory
// tree. A walk reaches into `.omh/`, the agent working state, which holds copies
// of sources and probes, and counting those as the compiler is how
// ARCHITECTURE.md came to state a total of 72,068 lines while its own
// per-directory table, which cannot see them, added up to 46,586. A walk also
// counts a source file nobody has added to the tree yet, which is not the
// compiler either.
//
// Lines are physical: a comment and a blank line count, the way `wc -l` counts
// them, so the number does not depend on how the file is punctuated.

import os

fn main() {
	root := os.dir(os.dir(@FILE))
	mut by_module := map[string]int{}
	mut files_by_module := map[string]int{}
	mut total := 0
	mut files := 0
	for path in tracked_sources(root) {
		lines := os.read_lines(os.join_path(root, path)) or { continue }
		module := if path.contains('/') { path.all_before('/') + '/' } else { path }
		by_module[module] = (by_module[module] or { 0 }) + lines.len
		files_by_module[module] = (files_by_module[module] or { 0 }) + 1
		total += lines.len
		files++
	}
	if '--count' in os.args[1..] {
		println(total)
		return
	}
	for module in by_module.keys().sorted() {
		println('${by_module[module]}\t${module} (${files_by_module[module]})')
	}
	println('lines: ${total} in ${files} files')
}

// tracked_sources is the `.v` files git tracks under the root, named relative to
// it, with the tests and the tooling left out. A tree it cannot read is reported
// rather than counted from whatever a walk happens to find.
fn tracked_sources(root string) []string {
	listed := os.execute('git -C ${os.quoted_path(root)} ls-files "*.v"')
	if listed.exit_code != 0 {
		eprintln('lines: git ls-files failed, so what the tree tracks is unknown: ${listed.output.trim_space()}')
		exit(1)
	}
	mut out := []string{}
	for line in listed.output.split_into_lines() {
		path := line.trim_space()
		if path == '' || path.ends_with('_test.v') || path.starts_with('tools/') {
			continue
		}
		out << path
	}
	return out.sorted()
}
