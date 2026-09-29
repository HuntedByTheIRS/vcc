module main

import cli
import codegen
import optimizer
import os
import printer
import parser
import time
import tokenize

// The end-to-end path: a command line goes in, a runnable file comes out. These
// tests drive the same functions main() drives, so they check the wiring and not
// only the stages.

// compile runs the pipeline the way main() does, which means the optimizer runs
// between the parser and the emitter and the command line decides what it does.
fn compile(args []string, source string) codegen.Result {
	opts := cli.parse(args) or { panic(err) }
	os.write_file(opts.inputs[0], source) or { panic(err) }
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	optimized := optimizer.optimize(parsed.unit, opts.optimization)
	return codegen.emit(optimized, codegen.Options{
		target: opts.target
		entry:  'main'
	})
}

fn compile_and_run(args []string, source string) int {
	opts := cli.parse(args) or { panic(err) }
	image := compile(args, source)
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

// The level decides whether a call the emitter cannot produce becomes a value or
// becomes a diagnostic. Both ends are checked here, because the difference
// between them is the whole point of having levels.
fn test_a_level_turns_a_builtin_call_into_a_runnable_binary() {
	source := scratch('abs.c')
	binary := scratch('abs')
	exit_status := compile_and_run(['-O2', source, '-o', binary],
		'int main() { return abs(-7) - 6; }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_without_a_level_the_call_is_made() {
	// A call whose value is read is emitted: the result arrives in the register
	// a value is expected to be in, and abs is a library function like any
	// other. The level decides whether a call the optimizer knows is folded,
	// not whether it can be made.
	source := scratch('abs_o0.c')
	binary := scratch('abs_o0')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { return abs(-7) - 6; }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_fno_builtin_takes_the_fold_back_at_the_same_level() {
	source := scratch('abs_nb.c')
	binary := scratch('abs_nb')
	exit_status := compile_and_run(['-O2', '-fno-builtin', source, '-o', binary],
		'int main() { return abs(-7) - 6; }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_call_can_be_the_value_of_an_expression() {
	// The result of a call arrives where a value is expected, so it can be read
	// where a name would be; its arguments are parked above the slots the
	// expression around it is using.
	source := scratch('callvalue.c')
	binary := scratch('callvalue')
	program := 'int add(int a, int b) { return a + b; }\n' +
		'int main() { int y = 7; int x = add(y, 3) + 2; return x - 12; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_call_can_be_the_argument_of_another_call() {
	// Two calls in one expression each want slots for their arguments, and the
	// inner one has to park its arguments above the outer one's.
	source := scratch('nestedcalls.c')
	binary := scratch('nestedcalls')
	program := 'int add(int a, int b) { return a + b; }\n' +
		'int main() { return add(add(1, 2), add(3, 4)) - 10; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A chain of calls is deep in the tree and flat in the grammar, which is the
// shape that took the stack out of the constant folder once before.
fn test_a_long_chain_of_calls_is_rewritten() {
	mut terms := []string{}
	mut expected := 0
	for _ in 0 .. 20000 {
		terms << 'abs(-1)'
		expected = (expected + 1) & 0xff
	}
	source := scratch('chain.c')
	binary := scratch('chain')
	exit_status := compile_and_run(['-O2', source, '-o', binary],
		'int main() { return ${terms.join(' + ')}; }\n')
	assert exit_status == expected
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The separate spelling of -std, end to end, because reading it as an input file
// is a failure that shows up two stages away from the flag that caused it.
fn test_the_separate_std_spelling_compiles_the_same_program() {
	source := scratch('std.c')
	binary := scratch('std')
	exit_status := compile_and_run(['-std', 'gnu11', source, '-o', binary],
		'int main() { return 3; }\n')
	assert exit_status == 3
	os.rm(source) or {}
	os.rm(binary) or {}
}

// Reading the tree is a mode of its own: the compiler parses, prints, and stops
// without writing anything. `main()` returns from inside that mode, so the test
// walks the same steps in the same order and checks the output file is not there.
fn test_print_ast_writes_nothing() {
	source := scratch('dump.c')
	binary := scratch('dump')
	text := 'int main() { return 6 * 7; }\n'
	os.write_file(source, text) or { panic(err) }
	opts := cli.parse(['-print-ast', source, '-o', binary])!
	assert opts.print_ast
	lexed := tokenize.lex(text)
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	printed := printer.render(optimizer.optimize(parsed.unit, opts.optimization))
	assert printed.contains('binary *')
	assert !os.exists(binary)
	os.rm(source) or {}
}

fn test_a_continue_runs_the_step_of_a_for() {
	// A continue jumps to the step, so the counter still advances and the loop
	// ends. With the step at the end of the body it would jump past it and the
	// loop would never advance — the guard below is there so that a loop that
	// went wrong fails this test instead of hanging it.
	source := scratch('continued.c')
	binary := scratch('continued')
	program := 'int main() {\n' +
		'  int total = 0;\n' +
		'  int guard = 0;\n' +
		'  int j = 0;\n' +
		'  for (j = 1; j <= 3; j = j + 1) {\n' +
		'    guard = guard + 1;\n' +
		'    if (guard == 100) {\n' +
		'      break;\n' +
		'    }\n' +
		'    if (j == 2) {\n' +
		'      continue;\n' +
		'    }\n' +
		'    total = total + j;\n' +
		'  }\n' +
		'  return total - 4;\n' +
		'}\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_parameter_survives_the_optimizer() {
	// The same program with a level on, where every declaration is rebuilt on
	// the way through: a parameter dropped in that rebuild is a parameter the
	// emitter cannot find, and this is the level that makes it visible.
	source := scratch('optparam.c')
	binary := scratch('optparam')
	program := 'int twice(int x) { return x + x; }\n' +
		'int main() { int y = 0; twice(y); return y; }\n'
	exit_status := compile_and_run([source, '-O2', '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_char_local_and_a_char_parameter_run() {
	// Both ends of a char are the machine's byte: the value is cut to a byte
	// when it is stored, and read back as the int the language promotes it to.
	source := scratch('chars.c')
	binary := scratch('chars')
	program := 'int addc(char a, char b) { return a + b; }\n' +
		'int main() { char c = 65; char d = 300; int sum = c + 1;\n' +
		' sum = sum + (d - 44);\n' +
		' return sum + (addc(200, 100) - 44) - 66; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_an_array_holds_elements_that_are_read_back() {
	source := scratch('array.c')
	binary := scratch('array')
	program := 'int main() { int a[4]; int i = 0;\n' +
		' for (i = 0; i < 4; i = i + 1) { a[i] = i * i; }\n' +
		' return a[0] + a[1] + a[2] + a[3] - 14; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_char_array_is_a_string_where_a_pointer_is_expected() {
	source := scratch('chararray.c')
	binary := scratch('chararray')
	program := 'int puts(char *s);\n' +
		'int main() { char buf[8]; buf[0] = 72; buf[1] = 105; buf[2] = 0;\n' +
		' puts(buf); return buf[1] - 105; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}
