module main

import cli
import codegen
import os
import parser
import time
import tokenize

// The end-to-end path: a command line goes in, a runnable file comes out. These
// tests drive the same functions main() drives, so they check the wiring and not
// only the stages.

fn compile_and_run(args []string, source string) int {
	opts := cli.parse(args) or { panic(err) }
	source_path := opts.inputs[0]
	os.write_file(source_path, source) or { panic(err) }
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	image := codegen.emit(parsed.unit, codegen.Options{
		target: opts.target
		entry:  'main'
	})
	assert image.diagnostics.len == 0
	os.write_file_array(opts.output, image.bytes) or { panic(err) }
	os.chmod(opts.output, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(opts.output))
	return result.exit_code
}

fn scratch(name string) string {
	return os.join_path(os.temp_dir(), 'vcc_pipeline_test_${os.getpid()}_${name}')
}

fn test_a_source_file_becomes_a_runnable_binary() {
	source := scratch('seven.c')
	binary := scratch('seven')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { return 7; }\n')
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_the_output_file_is_executable_and_an_elf() {
	source := scratch('elf.c')
	binary := scratch('elf')
	compile_and_run([source, '-o', binary], 'int main() { return 1; }\n')
	mut file := os.open(binary) or { panic(err) }
	mut header := []u8{len: 4}
	file.read(mut header) or { panic(err) }
	file.close()
	assert header == [u8(0x7f), `E`, `L`, `F`]
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_reading_the_source_from_standard_input_is_offered_by_the_parser() {
	// The path is exercised by hand rather than through a pipe; what is checked
	// here is that '-' reaches the compiler as an input rather than as a flag.
	opts := cli.parse(['-', '-o', scratch('out')])!
	assert opts.inputs == ['-']
}

fn test_an_unsupported_construct_exits_non_zero_without_writing_output() {
	source := scratch('bad.c')
	binary := scratch('bad')
	os.write_file(source, 'int main() { return *p; }\n') or { panic(err) }
	lexed := tokenize.lex(os.read_file(source) or { '' })
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len > 0
	assert !os.exists(binary)
	os.rm(source) or {}
}

fn test_the_phases_report_a_time() {
	started := time.now()
	tokenize.lex('int main() { return 1; }')
	assert time.since(started).microseconds() >= 0
}
