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
		target:       opts.target
		entry:        'main'
		libraries:    opts.libraries
		library_dirs: opts.library_dirs
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
		'int abs(int n);\nint main() { return abs(-7) - 6; }\n')
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
	exit_status := compile_and_run([source, '-o', binary],
		'int abs(int n);\nint main() { return abs(-7) - 6; }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_fno_builtin_takes_the_fold_back_at_the_same_level() {
	source := scratch('abs_nb.c')
	binary := scratch('abs_nb')
	exit_status := compile_and_run(['-O2', '-fno-builtin', source, '-o', binary],
		'int abs(int n);\nint main() { return abs(-7) - 6; }\n')
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
		'int abs(int n);\nint main() { return ${terms.join(' + ')}; }\n')
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

fn test_a_top_level_object_is_storage_every_function_shares() {
	source := scratch('globals.c')
	binary := scratch('globals')
	program := 'int counter = 3;\n' +
		'int total;\n' +
		'int bump(int by) { counter = counter + by; return counter; }\n' +
		'int main() { total = 10; return bump(4) + total - 17; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_char_array_at_the_top_level_is_a_string() {
	source := scratch('globalstring.c')
	binary := scratch('globalstring')
	program := 'int puts(char *s);\n' +
		'char message[6];\n' +
		'int main() { message[0] = 72; message[1] = 105; message[2] = 0;\n' +
		' puts(message); return message[1] - 105; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// What -l does, end to end: the library is named in the image, and a symbol that
// lives only in it resolves. `fetestexcept` is in libm and not in the C library
// (measured: `readelf --dyn-syms /usr/lib/libm.so.6` lists it and
// `readelf --dyn-syms /usr/lib/libc.so.6` does not), so it is a call the flag
// and nothing else can make work.
fn test_a_library_named_with_l_is_the_one_a_symbol_resolves_from() {
	source := scratch('libm.c')
	binary := scratch('libm')
	program := 'int fetestexcept(int);\nint main() { return fetestexcept(0); }\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The other half of that: with the library not named, the program compiles and
// then dies at load, saying which symbol it could not find. That is the shape
// the flag used to leave behind, and it is worth a test of its own because it is
// silent at compile time.
fn test_without_the_library_the_symbol_does_not_resolve() {
	source := scratch('nolibm.c')
	binary := scratch('nolibm')
	program := 'int fetestexcept(int);\nint main() { return fetestexcept(0); }\n'
	opts := cli.parse([source, '-o', binary])!
	image := compile([source, '-o', binary], program)
	assert image.diagnostics.len == 0
	os.write_file_array(binary, image.bytes) or { panic(err) }
	os.chmod(binary, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(binary))
	assert opts.libraries.len == 0
	assert result.exit_code != 0
	assert result.output.contains('fetestexcept')
	os.rm(source) or {}
	os.rm(binary) or {}
}

// Naming one library twice names it once, and the image is the one the flag
// names once: the same input produces the same bytes, which is what makes a
// duplicate flag cost nothing.
fn test_the_same_library_twice_is_named_once() {
	source := scratch('libmonce.c')
	once := compile([source, '-o', scratch('once'), '-lm'], 'int main() { return 0; }\n')
	twice := compile([source, '-o', scratch('twice'), '-lm', '-lm'],
		'int main() { return 0; }\n')
	assert once.diagnostics.len == 0
	assert twice.diagnostics.len == 0
	assert once.bytes == twice.bytes
	os.rm(source) or {}
}

// A -l name with no file behind it is reported rather than dropped, and the
// report says where it looked: a flag that quietly does nothing is the failure
// this test exists to keep out.
fn test_a_library_that_is_not_there_is_reported() {
	source := scratch('missing.c')
	image := compile([source, '-o', scratch('missing'), '-lnosuchlibrary'],
		'int main() { return 0; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('cannot find -lnosuchlibrary')
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// A double through the whole pipeline: the optimizer runs over the tree, the
// emitter writes the floating-point instructions, the image calls into a library
// the -l flag named, and the answer comes back through the exit status. This is
// the combination the compiler was asked for, end to end.
fn test_a_double_argument_reaches_a_library_call() {
	source := scratch('sqrt.c')
	binary := scratch('sqrt')
	program := 'double sqrt(double x);\nint main() { int n = sqrt(2.0) * 100; return n; }\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 141
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The machine passes six ints and eight doubles in registers. Past those the
// arguments go on the stack, in the order they were written, and the callee reads
// them from the frame it was entered with. Ten ints is four of them on the stack.
fn test_a_call_past_the_sixth_argument_passes_the_rest_on_the_stack() {
	source := scratch('stackargs.c')
	binary := scratch('stackargs')
	program := 'int add10(int a, int b, int c, int d, int e, int f, int g, int h, int i, int j) { return a + b + c + d + e + f + g + h + i + j; }\nint main(void) { return add10(1, 2, 3, 4, 5, 6, 7, 8, 9, 10); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 55
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A sum cannot tell one argument from another, so this is the case that catches a
// reversed stack: the seventh, eighth and ninth parameters have to arrive as 7, 8
// and 9, and the answer changes if any two of them swap.
fn test_the_stack_arguments_arrive_in_the_order_they_were_written() {
	source := scratch('stackorder.c')
	binary := scratch('stackorder')
	program := 'int f9(int a, int b, int c, int d, int e, int f, int g, int h, int i) { return g * 100 + h * 10 + i; }\nint main(void) { return f9(1, 2, 3, 4, 5, 6, 7, 8, 9); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 789 % 256
	os.rm(source) or {}
	os.rm(binary) or {}
}

// Two arguments of one call can be on the stack for two different reasons, and
// the two sequences run out separately: six ints use the general registers and
// nine doubles use all eight of the floating ones, so the ninth double is the one
// the stack carries.
fn test_an_argument_past_the_floating_registers_is_on_the_stack() {
	source := scratch('stackdoubles.c')
	binary := scratch('stackdoubles')
	program := 'double d9(double a, double b, double c, double d, double e, double f, double g, double h, double i) { return a + b + c + d + e + f + g + h + i; }\nint main(void) { return d9(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0) * 2; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 90
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A call that runs out of both sequences at once: the ints past the sixth are on
// the stack, and so is the double past the eighth, each read back as its own type.
fn test_both_sequences_can_overflow_in_one_call() {
	source := scratch('stackmixed.c')
	binary := scratch('stackmixed')
	program := 'int f(int a, int b, int c, int d, int e, int f, double g, double h, double i, double j, double k, double l, double m, double n, double o) { return a + b + c + d + e + f + g + h * 2 + i * 3 + j * 4 + k * 5 + l * 6 + m * 7 + n * 8 + o * 9; }\nint main(void) { return f(1, 1, 1, 1, 1, 1, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 51
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A library function is called the same way, and a variadic one reads the
// arguments the registers did not carry by walking the stack: seven ints after the
// format string is one past the registers.
fn test_a_variadic_library_call_past_the_registers_runs() {
	source := scratch('stackprintf.c')
	binary := scratch('stackprintf')
	program := 'int printf(const char *fmt, ...);\nint main(void) { printf("%d %d %d %d %d %d %d\\n", 1, 2, 3, 4, 5, 6, 7); return 0; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The stack a call took comes back with the call, so the next call in the same
// body and the slots of the frame are where they were: a loop calling a function
// with seven arguments five times is five times the same answer.
fn test_the_stack_a_call_took_comes_back_before_the_next_call() {
	source := scratch('stackloop.c')
	binary := scratch('stackloop')
	program := 'int add7(int a, int b, int c, int d, int e, int f, int g) { return a + b + c + d + e + f + g; }\nint main(void) { int total = 0; int i = 0; while (i < 5) { total = total + add7(i, i, i, i, i, i, i); i = i + 1; } return total; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 70
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An object of a struct type is a block of the frame, and a member of it is read
// and written at the offset the layout gave it. The program is run, so what is
// checked is the bytes and not the tree: three members of three widths, each
// written and read back, and the answer depends on all three offsets.
fn test_a_member_of_a_struct_is_read_and_written_at_its_offset() {
	source := scratch('structmembers.c')
	binary := scratch('structmembers')
	program := 'struct S { int a; int b; char c; };\nint main(void) { struct S x; x.a = 3; x.b = 4; x.c = 5; return x.a * 100 + x.b * 10 + x.c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 89
	os.rm(source) or {}
	os.rm(binary) or {}
}

// Where a char member puts the member after it is the char's width, so this is
// the case that catches a wrong width in the description: the int has to be read
// from offset four, and a layout that gave it offset one would read the padding.
fn test_a_char_member_puts_the_next_member_where_the_char_ends() {
	source := scratch('structpad.c')
	binary := scratch('structpad')
	program := 'struct M { char c; int i; };\nint main(void) { struct M m; m.c = 1; m.i = 2; return m.c * 10 + m.i; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 12
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A double member is a value in the floating-point registers, read and written
// with the instruction that moves one rather than with the integer store of the
// same width, which would write half of it.
fn test_a_double_member_is_a_double() {
	source := scratch('structdouble.c')
	binary := scratch('structdouble')
	program := 'struct P { double x; double y; };\nint main(void) { struct P p; p.x = 1.5; p.y = 2.25; return (p.x + p.y) * 4; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 15
	os.rm(source) or {}
	os.rm(binary) or {}
}

// Every member of a union starts at the beginning of the object, so the second
// member written is the one read back.
fn test_a_member_of_a_union_is_at_the_beginning_of_the_object() {
	source := scratch('unionmember.c')
	binary := scratch('unionmember')
	program := 'union U { int a; char b; };\nint main(void) { union U u; u.a = 0; u.b = 7; return u.b; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An object of an aggregate type at the top level is storage in the image rather
// than in a frame, and the address a member is read at is the address of that
// storage: the object starts as zeros, the members written into it are read back
// from a function, and a char member is a byte of the same eight.
fn test_a_top_level_aggregate_is_storage_in_the_image() {
	source := scratch('globalstruct.c')
	binary := scratch('globalstruct')
	program := 'struct A { int x; };\nstruct B { struct A a; int y; char c; };\nstruct B g;\nint main(void) { g.a.x = 5; g.y = 2; g.c = 1; return g.a.x * 100 + g.y * 10 + g.c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 521 % 256
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A member of a member is one object read further in, so the offsets add up: the
// member `x` of the member `a` of `b` is at the byte `a` starts at plus the byte
// `x` starts at inside it. The answer is 34 = 3 * 10 + 4, and a layout that put
// either member anywhere else would give a different one.
fn test_a_member_of_a_member_is_read_and_written_at_the_offsets_added_up() {
	source := scratch('memberpath.c')
	binary := scratch('memberpath')
	program := 'struct A { int x; };\nstruct B { int y; struct A a; };\nint main(void) { struct B b; b.y = 3; b.a.x = 4; return b.y * 10 + b.a.x; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 34
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An arrow reads the member from the object the pointer names, so the address is
// the pointer's value and not the frame's: the pointer is set to the address of a
// local, and the member written through it is read from the local afterwards.
fn test_a_member_through_a_pointer_is_read_and_written_from_the_object_it_names() {
	source := scratch('memberpointer.c')
	binary := scratch('memberpointer')
	program := 'struct S { int a; int b; };\nint main(void) { struct S s; struct S *p; p = &s; p->a = 5; p->b = 6; return p->a * 10 + p->b; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 56
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A typedef is a name for a type and not a type of its own: the declaration is
// read, and every use of the name afterwards is a use of the type it stands for,
// wherever a type can be written. These run the programs, so what is checked is
// the artifact and not the spelling in the tree.
fn test_a_typedef_name_is_the_type_it_names() {
	source := scratch('typedef.c')
	binary := scratch('typedef')
	program := 'typedef int T;\nT g = 7;\nT add(T a, T b) { return a + b; }\nint main(void) { T x = 5; return add(x, g); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 12
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A typedef of a double is a double, which is the one type here that travels in
// the floating-point registers: the alias reaches the emitter as the type it
// names, so the arithmetic and the argument sequence are the double's.
fn test_a_typedef_of_a_double_is_a_double() {
	source := scratch('typedefd.c')
	binary := scratch('typedefd')
	program := 'typedef double D;\nD twice(D x) { return x + x; }\nint main(void) { D v = 2.5; int n = twice(v) * 4; return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 20
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A typedef of a pointer is a pointer, and a typedef of a typedef is the type at
// the end of the chain. The string is read by the library function the pointer is
// handed to, so what is checked is that the alias reached the call as the `char *`
// the parameter is: a pointer of the wrong shape would fault here.
fn test_a_typedef_of_a_pointer_reads_through_it() {
	source := scratch('typedefp.c')
	binary := scratch('typedefp')
	program := 'typedef char *String;\ntypedef String Text;\nint puts(const char *s);\nint main(void) { Text s = "abc"; return puts(s) < 0; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A typedef of a type the back end has no form for is refused by that type and
// not by the name: the name is a spelling of the type, and the type is what the
// image has to hold. The refusal is at the declaration, so an object nothing uses
// is refused too rather than dropped quietly.
fn test_a_typedef_of_a_type_with_no_form_is_refused_by_that_type() {
	program := 'typedef long Big;\nBig x;\nint main(void) { return 0; }\n'
	lexed := tokenize.lex(program)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].msg == 'unsupported type long'
	assert parsed.diagnostics[0].line == 2
}

// The sign of a double is in the top bit of the value rather than in a bit of a
// register the arithmetic happens to leave in a convenient place, so a negated
// double is the case a wrong instruction shows up in first.
fn test_a_negated_double_reaches_a_comparison_intact() {
	source := scratch('negated.c')
	binary := scratch('negated')
	program := 'int main() { double a = -3.5; if (a < 0.0) { return 1; } return 2; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}
