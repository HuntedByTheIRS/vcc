#!/usr/bin/env -S v run

// The benchmark harness. Speed is one of the two constraints this project
// exists to satisfy, so the numbers are produced by a tool that anyone can run
// rather than by whoever happens to be writing a pull request.
//
//   v run tools/bench.vsh                     # a generated workload, vcc against tcc
//   v run tools/bench.vsh file.c              # a workload you name
//   v run tools/bench.vsh --terms 20000       # a bigger generated workload
//   v run tools/bench.vsh --no-compare        # vcc alone
//
// What it measures: wall time and peak memory for the whole compile, and the
// per-phase microseconds vcc reports itself. Wall time is the best of a few runs,
// because the first run of anything pays for a cold page cache and reporting that
// as the number is how benchmarks lie.

import os
import time

const default_terms = 2000
const default_runs = 3

struct Options {
mut:
	files   []string
	terms   int
	runs    int
	compare bool
	tcc     string
}

struct Measurement {
mut:
	wall_ms  f64
	peak_kb  i64
	status   int
	output   string
	measured bool
}

fn main() {
	opts := parse_options(os.args[1..])
	root := os.dir(os.dir(@FILE))
	vcc := build_compiler(root)
	tcc := if opts.compare { find_tcc(opts.tcc) } else { '' }
	workloads := if opts.files.len > 0 {
		opts.files
	} else {
		[write_workload(opts.terms)]
	}
	mut tcc_times := map[string]f64{}
	println(right_pad('workload', 28) + right_pad('compiler', 10) + left_pad('wall ms', 10) +
		left_pad('peak KB', 12) + left_pad('status', 8))
	for workload in workloads {
		name := os.file_name(workload)
		vcc_result := measure('${os.quoted_path(vcc)} -bench ${os.quoted_path(workload)} -o ${os.quoted_path(output_path(workload, 'vcc'))}', opts.runs)
		print_row(name, 'vcc', vcc_result)
		phases(vcc_result.output)
		if tcc != '' {
			tcc_result := measure('${os.quoted_path(tcc)}${tcc_resources(tcc)} -o ${os.quoted_path(output_path(workload, 'tcc'))} ${os.quoted_path(workload)}', opts.runs)
			print_row(name, 'tcc', tcc_result)
			tcc_times[name] = tcc_result.wall_ms
			if tcc_result.status == 0 && tcc_result.wall_ms > 0 {
				ratio := vcc_result.wall_ms / tcc_result.wall_ms
				println('    vcc takes ${fixed(ratio, 2)}x the wall time tcc takes on ${name}')
			}
		}
	}
}

// build_compiler builds the tree under test rather than trusting whatever binary
// is lying around, so the numbers describe the current source.
fn build_compiler(root string) string {
	path := os.join_path(os.temp_dir(), 'vcc-bench-${os.getpid()}')
	result := os.execute('cd ${os.quoted_path(root)} && v -o ${os.quoted_path(path)} . 2>&1')
	if result.exit_code != 0 {
		eprintln('bench: the compiler did not build:')
		eprintln(result.output)
		exit(1)
	}
	return path
}

// write_workload generates a unit the current compiler can actually compile: one
// function returning a large constant expression. It is not the V self-build,
// which is the benchmark that will decide this project, but it is a workload both
// compilers accept and it grows with --terms.
fn write_workload(terms int) string {
	mut parts := []string{}
	for i in 0 .. terms {
		parts << '${i % 97 + 1}'
	}
	path := os.join_path(os.temp_dir(), 'workload-${terms}-terms.c')
	os.write_file(path, 'int main() {\n\treturn ${parts.join(' + ')};\n}\n') or { panic(err) }
	return path
}

// measure runs a command a few times and keeps the fastest successful attempt.
// Peak memory comes from the attempt that was kept, since a peak from a slower
// run belongs to a different measurement.
fn measure(command string, runs int) Measurement {
	mut best := Measurement{}
	mut have_one := false
	for _ in 0 .. runs {
		attempt := measure_once(command)
		if !have_one || prefer(attempt, best) {
			best = attempt
			have_one = true
		}
	}
	return best
}

// prefer says which of two attempts to keep: one that worked over one that did
// not, and the faster of two that agree.
fn prefer(attempt Measurement, best Measurement) bool {
	if attempt.status == 0 && best.status != 0 {
		return true
	}
	if attempt.status != best.status {
		return false
	}
	return attempt.wall_ms < best.wall_ms
}

fn measure_once(command string) Measurement {
	current := time.now()
	result := os.execute('${time_wrapper()}${command} 2>&1')
	elapsed := f64(time.since(current).microseconds()) / 1000.0
	return Measurement{
		wall_ms:  elapsed
		peak_kb:  read_peak(result.output)
		status:   result.exit_code
		output:   result.output
		measured: true
	}
}

// time_wrapper returns the prefix that turns a command into one that also reports
// its own peak memory, or nothing when /usr/bin/time is not installed.
fn time_wrapper() string {
	if os.exists('/usr/bin/time') {
		return '/usr/bin/time -f "peak=%M" '
	}
	return ''
}

// read_peak takes the peak memory out of /usr/bin/time's report. Wall time comes
// from the clock around the whole call instead, because /usr/bin/time resolves
// only to hundredths of a second and everything here finishes faster than that.
fn read_peak(output string) i64 {
	for line in output.split_into_lines() {
		if !line.contains('peak=') {
			continue
		}
		for part in line.split(' ') {
			if part.starts_with('peak=') {
				return part[5..].i64()
			}
		}
	}
	return 0
}

// phases prints what vcc reported about its own stages, which is where a
// regression in one stage is visible before it shows up in the total.
fn phases(output string) {
	mut reported := []string{}
	for line in output.split_into_lines() {
		if line.starts_with('bench ') {
			reported << line[6..]
		}
	}
	if reported.len > 0 {
		println('    vcc phases: ${reported.join(', ')}')
	}
}

fn print_row(workload string, compiler string, result Measurement) {
	status := if result.status == 0 { 'ok' } else { '${result.status}' }
	peak := if result.peak_kb > 0 { '${result.peak_kb}' } else { '-' }
	println(right_pad(workload, 28) + right_pad(compiler, 10) + left_pad(fixed(result.wall_ms, 2), 10) +
		left_pad(peak, 12) + left_pad(status, 8))
	if result.status != 0 {
		lines := result.output.split_into_lines()
		if lines.len > 0 {
			println('    ${lines[0]}')
		}
	}
}

// right_pad and left_pad lay out the table. V 0.5.2 has one of these on string
// and not the other, so both live here rather than half the layout being
// inconsistent.
fn right_pad(text string, width int) string {
	if text.len >= width {
		return text
	}
	return text + ' '.repeat(width - text.len)
}

fn left_pad(text string, width int) string {
	if text.len >= width {
		return text
	}
	return ' '.repeat(width - text.len) + text
}

// fixed prints a float with the given number of decimals without relying on a
// format specifier, since the widths and precisions here have to survive a V
// version change that nobody is watching.
fn fixed(value f64, decimals int) string {
	mut scale := 1.0
	for _ in 0 .. decimals {
		scale *= 10.0
	}
	scaled := int(value * scale + 0.5)
	whole := scaled / int(scale)
	part := scaled % int(scale)
	if decimals == 0 {
		return '${whole}'
	}
	mut text := '${part}'
	for text.len < decimals {
		text = '0${text}'
	}
	return '${whole}.${text}'
}

fn output_path(workload string, compiler string) string {
	return os.join_path(os.temp_dir(), 'vcc-bench-out-${os.getpid()}-${compiler}-${os.file_name(workload)}')
}

// find_tcc finds the tcc that V vendors, which is the compiler this project is
// meant to replace and the only comparison that matters.
fn find_tcc(explicit string) string {
	if explicit != '' {
		return explicit
	}
	from_env := os.getenv('VCC_TCC')
	if from_env != '' {
		return from_env
	}
	v := os.find_abs_path_of_executable('v') or { return '' }
	candidate := os.join_path(os.dir(os.real_path(v)), 'thirdparty', 'tcc', 'tcc.exe')
	if os.exists(candidate) {
		return candidate
	}
	eprintln('bench: no vendored tcc found next to ${v}; pass --tcc PATH or --no-compare')
	return ''
}

// tcc_resources points a vendored tcc at its own runtime and headers. Without
// this it cannot find libtcc1.a, which is how V calls it too: V passes
// -B<thirdparty>/tcc/lib/tcc and the matching include and library directories.
fn tcc_resources(tcc string) string {
	tcc_dir := os.dir(tcc)
	runtime := os.join_path(tcc_dir, 'lib', 'tcc')
	include := os.join_path(tcc_dir, 'lib', 'tcc', 'include')
	library := os.join_path(tcc_dir, 'lib', 'tcc')
	if !os.exists(runtime) {
		return ''
	}
	return ' -B${runtime} -I${include} -L${library}'
}

fn parse_options(args []string) Options {
	mut opts := Options{
		terms:   default_terms
		runs:    default_runs
		compare: true
	}
	mut i := 0
	for i < args.len {
		arg := args[i]
		if arg == '--terms' && i + 1 < args.len {
			opts.terms = args[i + 1].int()
			i += 2
			continue
		}
		if arg == '--runs' && i + 1 < args.len {
			opts.runs = args[i + 1].int()
			i += 2
			continue
		}
		if arg == '--tcc' && i + 1 < args.len {
			opts.tcc = args[i + 1]
			i += 2
			continue
		}
		if arg == '--no-compare' {
			opts.compare = false
			i++
			continue
		}
		if arg == '-h' || arg == '--help' {
			println('usage: v run tools/bench.vsh [--terms N] [--runs N] [--tcc PATH] [--no-compare] [file.c ...]')
			exit(0)
		}
		opts.files << arg
		i++
	}
	if opts.runs < 1 {
		opts.runs = 1
	}
	if opts.terms < 1 {
		opts.terms = default_terms
	}
	return opts
}
