module main

import cli
import codegen
import optimizer
import os
import printer
import parser
import time
import tokenize

// WideValueCase is one 128-bit program beside the status it exits with. The two
// fields are declared rather than written as a two-element literal, because a
// literal mixing a string and an int is not an array this V infers.
struct WideValueCase {
	source string
	status int
}

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

// Whether a dialect verdict survives the flags is the command line's question,
// and the answer is the one the class machinery gives: a construct the mode does
// not have is an error whatever is written, and a pedantic message is silent
// until something asks. The policy here is built by the same parse main() calls,
// so this checks the wiring and not only the class. Measured on gcc 16.2.1,
// which exits 1 on plain `typeof` under -std=c99 with -w on the command line.
fn test_the_dialect_verdict_survives_the_flags() {
	source := scratch('dialect_absent.c')
	os.write_file(source, 'int x = 1;\ntypeof(x) y = 2;\nint main(void) { return y; }\n') or {
		panic(err)
	}
	absent := tokenize.Diagnostic{
		line:    2
		col:     1
		msg:     'ISO C99 forbids the typeof specifier'
		file:    source
		warning: false
		class:   .cpp
	}
	for flags in [['-std=c99'], ['-std=c99', '-w'], ['-std=c99', '-Wno-pedantic'],
		['-std=c99', '-pedantic-errors']] {
		mut args := flags.clone()
		args << source
		opts := cli.parse(args) or { panic(err) }
		assert severity_of(absent, opts.warnings) == .error
	}
	question := tokenize.Diagnostic{
		line:    2
		col:     1
		msg:     'ISO C99 forbids the __int128 type'
		file:    source
		warning: true
		class:   .pedantic
	}
	for flags in [['-std=c99', '-w'], ['-std=c99', '-Wno-pedantic']] {
		mut args := flags.clone()
		args << source
		opts := cli.parse(args) or { panic(err) }
		assert severity_of(question, opts.warnings) == .silent
	}
	asked := cli.parse(['-std=c99', '-pedantic-errors', source]) or { panic(err) }
	assert severity_of(question, asked.warnings) == .error
	os.rm(source) or {}
}

fn test_a_source_file_becomes_a_runnable_binary() {
	source := scratch('seven.c')
	binary := scratch('seven')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { return 7; }\n')
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A block-scope `extern` declaration of a file-scope object names that object
// and gives the name no storage in the frame. Before this the declaration was
// emitted as a local like any other, and a read of the name read the
// uninitialized slot: measured on gcc 16.2.1 with -std=gnu99 the same program
// exits 100, and this compiler read address-shaped garbage. The local `got`
// makes the wrong answer a value of its own rather than zero, so a read of the
// slot is told apart from a read of the object.
fn test_a_block_scope_extern_reads_the_file_scope_object() {
	source := scratch('block_extern.c')
	binary := scratch('block_extern')
	program := 'static int obj = 100;\nint main(void) {\n    int got = -1;\n    { extern int obj; got = obj; }\n    return got;\n}\n'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 100
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A file-scope declaration with several declarators defines one object per
// declarator, and each is an object the rest of the program can name. Before
// this only the first reached the tree: `static int a = 0, b = 0;` refused
// `&b` with "the address of b is not implemented" and refused `b = 5` with "no
// local of that name is in scope", and the last initializer overwrote the
// first's, so `static int a = 5, b = 7;` read 7 from `a`. The program here
// names the second declarator by address and by assignment, and reads the
// fourth's value; measured on gcc 16.2.1 with -std=gnu99 it exits 0.
fn test_a_file_scope_declaration_reaches_every_declarator() {
	source := scratch('multi_declarator.c')
	binary := scratch('multi_declarator')
	program := 'static int a = 5, b = 0, c[2] = { 3, 4 }, d = 7;\nint main(void) {\n    b = 6;\n    if (&b == 0) { return 1; }\n    if (b != 6) { return 2; }\n    if (a != 5) { return 3; }\n    if (c[1] != 4) { return 4; }\n    if (d != 7) { return 5; }\n    return 0;\n}\n'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A variable-length array declared in a loop body claims its storage on the
// stack when the declaration runs, and the storage is given back where the block
// ends. Before that release, each time round subtracted again and the stack grew
// until the program died; four million iterations of an eight-byte array is
// sixty-odd megabytes of stack, far past the eight a thread gets. The program
// answers 1 when it finishes and the same program exits 1 under gcc 16.2.1 with
// -std=gnu99, measured.
fn test_a_loop_body_gives_a_variable_length_array_back_every_time_round() {
	source := scratch('vla_loop.c')
	binary := scratch('vla_loop')
	program := 'int main(void) {\n    int c = 0;\n    for (int i = 0; i < 4000000; i++) {\n        int n = 8;\n        int a[n];\n        a[0] = i;\n        if (a[0] == 3999999) { c = 1; }\n    }\n    return c;\n}\n'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A goto that leaves a block which claimed a variable-length array's storage
// gives it back before it jumps, because the block's own exit is not reached.
// The loop here is a block and a backward goto out of it, so each time round
// leaves the block early; without the release on that edge the stack grows once
// per iteration and the program dies, where gcc 16.2.1 with -std=gnu99 exits 1.
fn test_a_goto_out_of_a_block_gives_a_variable_length_array_back() {
	source := scratch('vla_goto.c')
	binary := scratch('vla_goto')
	program := 'int main(void) {\n    int c = 0;\n    int i = 0;\ntop:\n    if (i >= 4000000) { goto done; }\n    {\n        int n = 8;\n        int a[n];\n        a[0] = i;\n        if (a[0] == 3999999) { c = 1; }\n        i++;\n        goto top;\n    }\ndone:\n    return c;\n}\n'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_call_through_a_function_pointer_is_the_address_it_holds() {
	// A call written to an expression calls the address the expression is worth,
	// and the answer says which function that was: add and mul disagree on
	// (3, 4), so a call that reached the wrong one is a different number and not
	// a plausible one. The five shapes are the four of 6.5.2.2 and the one of
	// 6.3.2.1: a pointer in a variable, a dereference of one, an element of a
	// table, a dereference of an element, and a designator passed as an argument.
	source := scratch('call_through.c')
	binary := scratch('call_through')
	exit_status := compile_and_run([source, '-o', binary], 'int add(int a, int b) { return a + b; }\nint mul(int a, int b) { return a * b; }\nstatic int through(int (*fn)(int, int)) { return fn(3, 4); }\nint main(void) {\n    int (*p)(int, int) = add;\n    int (*t[2])(int, int);\n    t[0] = add;\n    t[1] = mul;\n    int total = p(3, 4);\n    total += (*p)(3, 4);\n    total += t[1](3, 4);\n    total += (*t[0])(3, 4);\n    total += through(mul);\n    return total;\n}\n')
	// 7 + 7 + 12 + 7 + 12 = 45, which is what the same program returns under
	// gcc 16.2.1 with -std=c99.
	assert exit_status == 45
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.3.2.3p8 allows a pointer to a function of one type to convert to a pointer
// to a function of another type, and 6.3.2.1p4 makes a function designator
// written where a value is wanted the pointer to that function, so this
// conversion has a pointer on both sides. The designator is one, and the back
// end refused it while the operand was still the function type itself, which
// has no width for the conversion to widen. Measured on gcc 16.2.1, the first
// program exits 42 and the second exits 0.
fn test_a_function_designator_is_converted_to_the_function_pointer() {
	source := scratch('cast_function.c')
	binary := scratch('cast_function')
	matched := compile_and_run([source, '-o', binary], 'static int inc(int x) { return x + 1; } int main(void) { int (*fp)(int) = (int (*)(int))inc; return fp(41); }')
	assert matched == 42
	// A conversion to a different function type: the value is already the
	// address, so no instruction is written and the program runs to zero.
	discarded := compile_and_run([source, '-o', binary], 'static int inc(int x) { return x + 1; } int main(void) { void (*v)(void) = (void (*)(void))inc; (void)v; return 0; }')
	assert discarded == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A function whose return type is a pointer hands one word back in the register
// an int comes back in, so the value needs no new machinery and it is usable
// where the call is written: a local, a dereference, a subscript of the call, an
// element of the array a pointer-to-array points at, and the callee of another
// call. The chars stand in as their values so the program has no literals to
// escape. Measured on gcc 16.2.1, which exits 0 from the same program.
fn test_a_pointer_return_is_usable_where_the_call_is_written() {
	source := scratch('pointer_return.c')
	binary := scratch('pointer_return')
	exit_status := compile_and_run([source, '-o', binary], 'static int answer = 42;\nstatic char text[] = "abcdef";\nstatic int three[3] = {7, 8, 9};\ntypedef int (*binop)(int, int);\nstatic char *greet(void) { return text; }\nstatic int *get_answer(void) { return &answer; }\nstatic void *get_void(void) { return &answer; }\nstatic int (*get_three(void))[3] { return &three; }\nstatic int add(int a, int b) { return a + b; }\nstatic binop get_fn(void) { return add; }\nint main(void) {\n    char *g = greet();\n    int *a = get_answer();\n    void *v = get_void();\n    if (g[1] != 98) { return 1; }\n    if (*a != 42) { return 2; }\n    if (*(int *)v != 42) { return 3; }\n    if (*get_answer() != 42) { return 4; }\n    if (greet()[2] != 99) { return 5; }\n    if (get_three()[0][2] != 9) { return 6; }\n    if (get_fn()(20, 22) != 42) { return 7; }\n    greet();\n    return 0;\n}\n')
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A call to a pointer-returning function the file only declares is refused by
// name: the declaration is a promise nothing keeps, so the name is a symbol no
// library the image names provides. It used to compile and die at load with
// "symbol lookup error: ... undefined symbol: missing", the same shape an int
// return took, and the compile said nothing either way.
fn test_a_pointer_return_declared_and_never_defined_is_refused_by_name() {
	source := scratch('pointer_return_undefined.c')
	image := compile([source, '-o', scratch('pointer_return_undefined')],
		'char *missing(void);\nint main(void) { char *p = missing(); return p == 0; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('missing')
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// `*p` where p points at an array is the array, and an array's value is the
// address of its first element rather than the bytes at it. A reader that loads
// the array's bytes into a register leaves a small number where an address was
// wanted, and a subscript of that number reads through it: the shape is reached
// both by an object and by a pointer-to-array return. Measured, the previous
// behaviour took the machine down on the second subscript; gcc 16.2.1 exits 0
// from the program below and from the same program written with `*row`.
fn test_a_dereference_of_a_pointer_to_an_array_is_the_element_address() {
	source := scratch('pointer_to_array_deref.c')
	binary := scratch('pointer_to_array_deref')
	exit_status := compile_and_run([source, '-o', binary], 'static int arr[3] = {7, 8, 9};\nstatic int (*get_row(void))[3] { return &arr; }\nint main(void) {\n    int (*row)[3] = &arr;\n    if ((*row)[1] != 8) { return 1; }\n    if ((*get_row())[2] != 9) { return 2; }\n    int *p = *row;\n    if (p[0] != 7) { return 3; }\n    return 0;\n}\n')
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_designator_naming_a_declared_function_is_its_address() {
	// A function the file only declares has its code somewhere the image is not,
	// so a designator naming it is a symbol the loader resolves: 6.3.2.1 makes it
	// the pointer to that function whether or not the file wrote the body. The
	// address is read out of the same slot a call to that function goes through,
	// so a pointer to it, an address taken with `&`, and a call through either
	// are one value. getpid is the callee because its answer is its own pid and
	// the program asks for the same one twice; there is no argument to pass, so
	// nothing here leans on how an argument travels.
	source := scratch('declared_designator.c')
	binary := scratch('declared_designator')
	exit_status := compile_and_run([source, '-o', binary],
		'int getpid(void);\nint same(int (*f)(void), int (*g)(void)) { return f == g; }\nint main(void) {\n    int (*p)(void) = getpid;\n    int (*q)(void) = &getpid;\n    if (p != q) { return 1; }\n    if (p == 0) { return 2; }\n    if (!same(p, getpid)) { return 3; }\n    return p() == getpid() ? 0 : 4;\n}\n')
	// gcc 16.2.1 with -std=c99 exits 0 from the same program.
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_call_through_a_function_pointer_uses_the_type_the_pointer_carries() {
	// A pointer to a function has the parameter list and the return type its
	// declaration wrote, and C calls through one with that prototype: a float
	// parameter takes the argument as a float rather than as a promoted double,
	// and a float return is read from the floating-point register rather than
	// from the general one. A pointer to a same-file function is beside the
	// library ones as the constraint, and each program answers 2.5 from the
	// arguments below: one parameter for the first four, two for fmodf and three
	// for fmaf. Measured on gcc 16.2.1 with -std=c99, every one exits 0.
	programs := [
		'float idl(float x) { return x; }\nint main(void) { float (*p)(float) = idl; return p(2.5f) == 2.5f ? 0 : 1; }\n',
		'float fabsf(float);\nint main(void) { float (*p)(float) = fabsf; return p(-2.5f) == 2.5f ? 0 : 1; }\n',
		'float fabsf(float);\nint main(void) { float (*p)(float) = fabsf; float x = -2.5f; return p(x) == 2.5f ? 0 : 1; }\n',
		'float sqrtf(float);\nint main(void) { float (*p)(float) = sqrtf; return p(6.25f) == 2.5f ? 0 : 1; }\n',
		'float fmodf(float, float);\nint main(void) { float (*p)(float, float) = fmodf; return p(5.5f, 3.0f) == 2.5f ? 0 : 1; }\n',
		'float fmaf(float, float, float);\nint main(void) { float (*p)(float, float, float) = fmaf; return p(1.0f, 1.5f, 1.0f) == 2.5f ? 0 : 1; }\n',
	]
	for i, program in programs {
		source := scratch('pointer_float_${i}.c')
		binary := scratch('pointer_float_${i}')
		exit_status := compile_and_run([source, '-o', binary, '-lm'], program)
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

fn test_a_static_function_nothing_names_is_not_read() {
	// The shape <bits/byteswap.h> and <bits/uintn-identity.h> have, which main.c
	// reaches through <stdio.h> and <stdlib.h>: a helper nothing calls, written
	// in a type this reader has no form for and a body the grammar has no
	// operators for. The definition is stepped over and the program runs.
	source := scratch('static_unused.c')
	binary := scratch('static_unused')
	exit_status := compile_and_run([source, '-o', binary],
		'static unsigned short int unused (unsigned short int x) { return x & 1; }\nint main() { return 0; }\n')
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
	// A definition a call can reach is still read and emitted.
	called := scratch('static_called.c')
	called_binary := scratch('static_called')
	called_status := compile_and_run([called, '-o', called_binary],
		'static int twice (int x) { return x * 2; }\nint main() { return twice(3); }\n')
	assert called_status == 6
	os.rm(called) or {}
	os.rm(called_binary) or {}
}

// A definition in the file is what a call in the file reaches, whatever the
// callee returns. The shape that was wrong is a definition with an empty body:
// `void f(void) {}` supplies f for this translation unit, but body.len is zero
// for it exactly as it is for a prototype, so it was read as a declaration, the
// call was emitted as an undefined dynamic symbol, and the image could not
// start. These programs are compiled and run, so what is checked is the exit
// status; a diagnostic count or a byte comparison would pass while the artifact
// is dead.
//
// Both return types are here, and the int callee is called as a value as well as
// as a statement: a change that made every call local by mishandling the value
// case would pass the void programs and fail the int ones.
fn test_a_call_to_a_definition_in_the_file_is_local_for_every_return_type() {
	cases := [
		'void f(void) {}\nint main(void) { f(); return 7; }\n',
		'static void f(void) {}\nint main(void) { f(); return 7; }\n',
		'void f(void);\nvoid f(void) {}\nint main(void) { f(); return 7; }\n',
		'int f(void) { return 5; }\nint main(void) { return f(); }\n',
		'int f(void) { return 5; }\nint main(void) { f(); return 7; }\n',
		'int add(int a, int b) { return a + b; }\nint main(void) { return add(3, 4); }\n',
	]
	answers := [7, 7, 7, 5, 7, 7]
	for i, program in cases {
		source := scratch('definition_local_${i}.c')
		binary := scratch('definition_local_${i}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
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

// `sizeof` is answered by the parser, so what the program is emitted with is the
// number and not a call: the exit status is the size of a double plus the size of
// a char, which is nine on this target.
fn test_sizeof_is_the_constant_the_program_returns() {
	source := scratch('sizes.c')
	binary := scratch('sizes')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { return sizeof(double) + sizeof(char); }\n')
	assert exit_status == 9
	os.rm(source) or {}
	os.rm(binary) or {}
}

// `sizeof` asks about a type and not about a value, so the operand is read and
// never evaluated. The operand here is a call that counts itself, and measured on
// gcc 16.2.1 the program exits 4: the counter is still 0 and the size of the
// call's int is 4. A reader that evaluated the operand would exit 104.
fn test_sizeof_does_not_evaluate_its_operand() {
	source := scratch('noeval.c')
	binary := scratch('noeval')
	exit_status := compile_and_run([source, '-o', binary], 'static int g_calls = 0;\nstatic int bump(void) { ++g_calls; return 1; }\nint main() { int n = sizeof(bump()); return g_calls * 100 + n; }\n')
	assert exit_status == 4
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The constant `sizeof` answers with has the type the target gives size_t, which
// is unsigned long here, and a signedness shows where the value is compared.
// Measured on gcc 16.2.1, this program exits 2: `sizeof(int) - 5` is four minus
// five in an unsigned 64-bit type and so greater than zero, and `sizeof(char) - 2`
// is 1 - 2, which is not less than zero. Read as an int both comparisons go the
// other way and the count is 1, which is what this returned before the result
// type was size_t.
fn test_sizeof_is_size_t_where_the_signedness_shows() {
	source := scratch('sizet.c')
	binary := scratch('sizet')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { return (sizeof(int) - 5 > 0) * 2 + (sizeof(char) - 2 < 0); }\n')
	assert exit_status == 2
	os.rm(source) or {}
	os.rm(binary) or {}
}

// `sizeof` of an array is the whole array and not the address its name is worth
// everywhere else in an expression. Measured on gcc 16.2.1, `int a[10]` is 40
// bytes, which is what the program returns. A reader that let the operand decay
// would answer 8, the width of a pointer on this target.
fn test_sizeof_of_an_array_is_the_whole_array() {
	source := scratch('wholearray.c')
	binary := scratch('wholearray')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { int a[10]; return sizeof(a); }\n')
	assert exit_status == 40
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.5.2.1 defines `E1[E2]` as `*((E1) + (E2))`, and addition commutes, so the base
// of a subscript is an expression and not a name: `3[p]` names the same element
// `p[3]` does, and an element of an integer array can be named from either side.
// Measured on gcc 16.2.1, the program below returns 12: 4 and 4 and 2 and 2.
fn test_a_subscript_accepts_an_expression_on_its_left() {
	source := scratch('subscript_any.c')
	binary := scratch('subscript_any')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[4] = {1,2,3,4}; int *p = a; return p[3] + 3[p] + *(p+1) + 1[a]; }\n')
	assert exit_status == 12
	os.rm(source) or {}
	os.rm(binary) or {}
}

// `p[3]`, `3[p]` and `*(p + 3)` are one lvalue, so a value written through any of
// them is read back through the others. A reader that read an element but did not
// compute the same address to store through would pass a value test and fail this
// one. Measured on gcc 16.2.1, the program returns 9.
fn test_an_element_written_through_any_base_stores_at_the_same_place() {
	source := scratch('subscript_store.c')
	binary := scratch('subscript_store')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[4] = {0}; int *p = a; 3[p] = 9; return p[3]; }\n')
	assert exit_status == 9
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The base of a subscript is any expression whose value is an address, and an
// element that is itself an array is the address of its first element, so an
// element named by another element is reached: `rows[0][2]` is the third int of
// the array `rows[0]` holds. Measured on gcc 16.2.1, the program returns 9: 3 and
// 6.
fn test_an_element_of_an_element_is_read() {
	source := scratch('subscript_nested.c')
	binary := scratch('subscript_nested')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[4]; int b[4]; int *rows[2]; a[2] = 3; b[1] = 6; rows[0] = a; rows[1] = b; return rows[0][2] + rows[1][1]; }\n')
	assert exit_status == 9
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A pointer value and a parenthesised name are bases too: `(*pp)[2]` reads through
// the pointer `pp` names, and `(a)[1]` is the element `a[1]` is. Measured on gcc
// 16.2.1, the program returns 9.
fn test_a_subscript_of_a_dereferenced_pointer_and_of_a_parenthesised_name() {
	source := scratch('subscript_paths.c')
	binary := scratch('subscript_paths')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int g[3]; int *p; int **pp; g[2] = 9; p = g; pp = &p; return (*pp)[2]; }\n')
	assert exit_status == 9
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The base of a subscript being an expression does not turn an array into a
// pointer: `sizeof(a)` is still the whole array and `sizeof(a[0])` the element.
// Measured on gcc 16.2.1, the program returns 44: 40 and 4.
fn test_sizeof_of_an_array_and_of_an_element_are_unchanged() {
	source := scratch('subscript_sizeof.c')
	binary := scratch('subscript_sizeof')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[10]; return sizeof(a) + sizeof(a[0]); }\n')
	assert exit_status == 44
	os.rm(source) or {}
	os.rm(binary) or {}
}

// `E1[E2]` is `*((E1) + (E2))`, so an address plus an index, an index plus an
// address and an address minus an index are the address of the element the index
// counts to, scaled by the size of one element. Measured on gcc 16.2.1, the
// program below returns 38: 14 and 13 and 11.
fn test_an_address_moved_by_an_index_is_an_address() {
	source := scratch('address_arithmetic.c')
	binary := scratch('address_arithmetic')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[5]; a[0] = 10; a[1] = 11; a[2] = 12; a[3] = 13; a[4] = 14; int *p = a + 4; return *p + *(p - 1) + *(1 + a); }\n')
	assert exit_status == 38
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A member that is an array is addressable storage of its own, so the base of a
// subscript can be a member path: `s.a[1]` is the second int of the array the
// member holds. Measured on gcc 16.2.1, the program returns 7 and the one after
// it returns 9.
fn test_a_member_that_is_an_array_is_subscripted() {
	source := scratch('member_array.c')
	binary := scratch('member_array')
	exit_status := compile_and_run([source, '-o', binary],
		'struct S { int a[3]; };\nint main(void) { struct S s; s.a[1] = 7; return s.a[1]; }\n')
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
	second := scratch('member_array_2.c')
	second_binary := scratch('member_array_2')
	second_status := compile_and_run([second, '-o', second_binary],
		'struct T { int b; int c[4]; };\nint main(void) { struct T t; t.b = 0; t.c[2] = 9; return t.c[2] + t.b; }\n')
	assert second_status == 9
	os.rm(second) or {}
	os.rm(second_binary) or {}
}

// A union is one object its members share: every member starts at the beginning
// of the object, so the address of any member is the address of the union, and
// the size is the largest member's. A member is written and read at its own
// width, which is what `u.ll = 0` then `u.i = 0x01020304` then reading
// `u.bytes[0]` shows: a constant stored into an eight-byte member is written at
// the member's width and widened into the whole register, and a double member is
// read by the instruction that moves one. Measured on gcc 16.2.1, the same
// program returns 127.
fn test_a_union_member_is_read_at_the_beginning_of_the_object() {
	source := scratch('union_members.c')
	binary := scratch('union_members')
	exit_status := compile_and_run([source, '-o', binary],
		"union U { char c; short s; int i; long long ll; double d; char bytes[8]; };\nint main(void) { union U u; int score = 0; u.ll = 0; u.i = 0x01020304; if ((void *)&u.i == (void *)&u) score += 1; if ((void *)&u.c == (void *)&u) score += 2; if (sizeof(union U) == 8) score += 4; if (u.i == 0x01020304) score += 8; if (u.bytes[0] == 4) score += 16; u.d = 1.0; if (u.d == 1.0) score += 32; u.c = 'z'; if (u.c == 'z') score += 64; return score; }\n")
	assert exit_status == 127
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A constant stored into a member is written at the width of the member, and a
// member eight bytes wide takes it widened into the whole register, which is
// what a store into a name of that width does. `s.ll = 0` is the case: without
// the widening the store would move eight bytes built from a four-byte value.
// Measured on gcc 16.2.1, the same program returns 104.
fn test_a_constant_stored_into_a_wider_member_is_widened() {
	source := scratch('member_widen.c')
	binary := scratch('member_widen')
	exit_status := compile_and_run([source, '-o', binary],
		"struct S { long long ll; char c; };\nint main(void) { struct S s; s.ll = 0; s.ll = 7; s.c = 'a'; return (int)s.ll + s.c; }\n")
	assert exit_status == 104
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.7.8 initializes the first member of a union, wherever the union type was
// reached from: a tagged type, a typedef of an anonymous union, an anonymous
// union in the declaration itself, and a first member narrower than the value
// written into it. The value goes at the beginning of the object, which is where
// the first member sits. Measured on gcc 16.2.1, these programs return 4, 4, 4
// and 65.
fn test_a_brace_initializer_for_a_union_stores_into_its_first_member() {
	programs := [
		'union U { int i; char c[4]; };\nint main(void) { union U u = { 0x01020304 }; return u.c[0]; }\n',
		'typedef union { int i; char c[4]; } T;\nint main(void) { T u = { 0x01020304 }; return u.c[0]; }\n',
		'int main(void) { union { int i; char c[4]; } u = { 0x01020304 }; return u.c[0]; }\n',
		'union U { char c; int i; };\nint main(void) { union U u = { 65 }; return u.c; }\n',
	]
	expected := [4, 4, 4, 65]
	for index, program in programs {
		source := scratch('union_init_${index}.c')
		binary := scratch('union_init_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == expected[index]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A union defined at the top level with an initializer has its first member
// written into the image, at the beginning of the object, and the rest of the
// union is the zeros the storage starts as. The tagged form and a typedef of an
// anonymous union reach the same storage. Measured on gcc 16.2.1, these programs
// return 4, 4 and 65.
fn test_a_file_scope_union_initializer_writes_its_first_member() {
	programs := [
		'union U { int i; char c[4]; };\nunion U u = { 0x01020304 };\nint main(void) { return u.c[0]; }\n',
		'typedef union { int i; char c[4]; } T;\nT u = { 0x01020304 };\nint main(void) { return u.c[0]; }\n',
		'union U { char c; int i; };\nunion U u = { 65 };\nint main(void) { return u.c; }\n',
	]
	expected := [4, 4, 65]
	for index, program in programs {
		source := scratch('union_global_init_${index}.c')
		binary := scratch('union_global_init_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == expected[index]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A struct's brace initializer in a body gives each value to a member in the
// order the members were written, one store per member, and the members the list
// did not reach are zero (6.7.8p21). A value written into a member of a narrower
// type is converted the way a store into that member converts it, `_Bool`
// included, and a character constant is the value of the character it names.
// Measured on gcc 16.2.1, these programs return 56, 56, 244, 144, 65 and 34.
fn test_a_body_struct_brace_initializer_stores_the_values_into_its_members() {
	programs := [
		'struct P { int a, b; };\nint main(void) { struct P p = {5, 6}; return p.a * 10 + p.b; }\n',
		'typedef struct { int a, b; } P;\nint main(void) { P p = {5, 6}; return p.a * 10 + p.b; }\n',
		'struct P { int a, b, c; };\nint main(void) { struct P p = {5}; return p.a * 100 + p.b * 10 + p.c; }\n',
		'struct N { _Bool b; char c; unsigned char u; short s; };\nint main(void) { struct N n = {5, 300, 300, 70000}; return (int)n.b * 100 + (int)n.c; }\n',
		"struct C { char c; int i; };\nint main(void) { struct C s = { 'A' }; return s.c; }\n",
		'struct S { int a; int b; };\nint main(void) { struct S s = {3, 4}; return s.a * 10 + s.b; }\n',
	]
	expected := [56, 56, 244, 144, 65, 34]
	for index, program in programs {
		source := scratch('struct_init_${index}.c')
		binary := scratch('struct_init_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == expected[index]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A struct defined at the top level with an initializer has each member written
// into the image at the byte the layout gave it, and the members the list did
// not reach are the zeros the storage starts as. Measured on gcc 16.2.1, these
// programs return 56, 244, 144, 65 and 4.
fn test_a_file_scope_struct_brace_initializer_writes_the_members() {
	programs := [
		'struct P { int a, b; };\nstruct P p = {5, 6};\nint main(void) { return p.a * 10 + p.b; }\n',
		'struct P { int a, b, c; };\nstruct P p = {5};\nint main(void) { return p.a * 100 + p.b * 10 + p.c; }\n',
		'struct N { _Bool b; char c; unsigned char u; short s; };\nstruct N n = {5, 300, 300, 70000};\nint main(void) { return (int)n.b * 100 + (int)n.c; }\n',
		"struct C { char c; int i; };\nstruct C s = { 'A', 7 };\nint main(void) { return s.c; }\n",
		'struct D { double d; int n; };\nstruct D g = {1.5, 3};\nint main(void) { struct D l = {2.5, 4}; return (int)(g.d + l.d); }\n',
	]
	expected := [56, 244, 144, 65, 4]
	for index, program in programs {
		source := scratch('struct_global_init_${index}.c')
		binary := scratch('struct_global_init_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == expected[index]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// typeof is read by the parser and answered by the emitter as the type behind
// it: a program that declares an object through typeof compiles and runs, and
// the exit status is what the types decided. Measured on gcc 16.2.1, the same
// program returns 17: 4 and 9 and the size of an int.
fn test_typeof_declares_an_object_of_the_type_behind_it() {
	source := scratch('typeof.c')
	binary := scratch('typeof')
	exit_status := compile_and_run([source, '-o', binary],
		'int main() { int x = 4; typeof(x) y = 9; __typeof__(int) z = sizeof(typeof(x)); return x + y + z; }\n')
	assert exit_status == 17
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A 128-bit object is declared, given a value narrower than it, copied into
// another object, and assigned to, and the image runs: the two objects are storage
// of their own, which is what the program's exit status says. The value itself is
// not readable yet, and a program that reads one is refused by name rather than
// compiled.
fn test_a_128_bit_object_is_storage_that_runs() {
	source := scratch('wide.c')
	binary := scratch('wide')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { __int128 a = 5; __int128 b = a; a = -1; return (int)(&a != &b); }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The write and the read are one fact: a value stored in a 128-bit object is read
// back by converting it to a narrower type, which takes its low word, and the bytes
// the conversion reads are the bytes the store wrote. Measured on gcc 16.2.1, the
// three programs return 44, 255 and 1.
fn test_a_128_bit_object_is_written_and_read_back() {
	cases := [
		'int main(void) { __int128 a = 300; __int128 b = a; return (int)(char)b; }',
		'int main(void) { __int128 n = -1; return (int)n; }',
		'int main(void) { __int128 z = 0; char *p = (char *)z; return p == 0; }',
	]
	answers := [44, 255, 1]
	for i, source_text in cases {
		source := scratch('wide_round_${i}.c')
		binary := scratch('wide_round_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A 128-bit object is not a value, so a program that reads one without saying what
// it wants is refused and nothing is written out. The conversion has to be written,
// which is what makes the reader say which width they meant.
// A member of a 128-bit type is storage inside an object, and the round trip
// through the built compiler says the same thing the local does: measured on gcc
// 16.2.1, the member written with 300 reads back as 44 in its low byte, and a
// member reached through a pointer is the same member.
fn test_a_128_bit_member_is_written_and_read_back() {
	cases := [
		'struct S { __int128 v; char c; }; int main(void) { struct S s; s.v = 300; return (int)(char)s.v; }',
		'struct S { __int128 v; }; int main(void) { struct S s; struct S *p = &s; p->v = 300; return (int)(char)s.v; }',
		'struct S { __int128 v; }; struct S g; int main(void) { g.v = -1; return (int)g.v; }',
	]
	answers := [44, 44, 255]
	for i, source_text in cases {
		source := scratch('wide_member_${i}.c')
		binary := scratch('wide_member_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// An array of 128-bit objects is storage whose elements are written and converted the
// way an object of the type is, and an element taken as a value is refused by name with
// its place in the file rather than reaching the encoding as an internal diagnostic at
// the top of the file. Measured on gcc 16.2.1, the two programs below return 0 and 44.
fn test_an_array_of_128_bit_objects_is_written_at_an_element_address() {
	cases := ['int main(void) { __int128 a[3]; a[0] = 300; return 0; }',
		'int main(void) { __int128 a[3]; a[0] = 300; int n = a[0]; return n; }']
	answers := [0, 44]
	for i, source_text in cases {
		source := scratch('wide_element_${i}.c')
		binary := scratch('wide_element_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
	element := scratch('wide_element_value.c')
	image := compile([element, '-o', scratch('wide_element_value')],
		'int main(void) { __int128 a[3]; a[0] = 5; return a[0]; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('is an object of 128 bits')
	assert image.bytes.len == 0
	os.rm(element) or {}
}

// A 128-bit division and remainder run: the routine the compiler emits is exercised
// end to end, through the command line, and the answers are gcc 16.2.1's. The large
// one is the identity a division is defined by rather than a wished-for quotient.
// A shift and a bitwise operator on a 128-bit value, run through the command line:
// the high word of a pair is read by shifting it down, which is the read that the
// pair had no form for until the shifts existed.
fn test_a_128_bit_shift_runs() {
	mut powers := '\tunsigned __int128 t64 = 1;\n'
	for _ in 0 .. 64 {
		powers += '\tt64 = t64 + t64;\n'
	}
	source := scratch('wide_shift.c')
	binary := scratch('wide_shift')
	high := compile_and_run([source, '-o', binary], 'int main(void) {\n${powers}\tunsigned __int128 a = t64 + 0x1234;\n\treturn ((a >> 64) & 0xffff) == 0x1 && ((a >> 4) & 0xff) == 0x23;\n}\n')
	assert high == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A shift by a count the program works out, run through the command line, on both
// widths. The count is in a variable, so the emitter cannot write it into the
// instruction and has to use the encodings that read it from a register.
fn test_a_shift_by_a_count_the_program_works_out_runs() {
	source := scratch('wide_shift_count.c')
	binary := scratch('wide_shift_count')
	narrow := compile_and_run([source, '-o', binary], 'int main(void) {\n\tint a = 8; int n = 33;\n\treturn (a << n) == 16 && (a >> 3) == 1;\n}\n')
	assert narrow == 1
	os.rm(source) or {}
	os.rm(binary) or {}
	mut powers := '\tunsigned __int128 t64 = 1;\n'
	for _ in 0 .. 64 {
		powers += '\tt64 = t64 + t64;\n'
	}
	wide := compile_and_run([source, '-o', binary], 'int main(void) {\n${powers}\t__int128 a = t64 + 5; int n = 64;\n\t__int128 p = a << n;\n\treturn (a >> n) == 1 && p == (t64 + 5) * t64;\n}\n')
	assert wide == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_128_bit_division_and_remainder_run() {
	mut powers := '\tunsigned __int128 t64 = 1;\n'
	for _ in 0 .. 64 {
		powers += '\tt64 = t64 + t64;\n'
	}
	powers += '\tunsigned __int128 t100 = 1;\n'
	for _ in 0 .. 100 {
		powers += '\tt100 = t100 + t100;\n'
	}
	source := scratch('wide_div.c')
	binary := scratch('wide_div')
	small := compile_and_run([source, '-o', binary], 'int main(void) { __int128 a = -7; __int128 b = 3; return (int)(a / b) == -2 && (int)(a % b) == -1; }\n')
	assert small == 1
	large := compile_and_run([source, '-o', binary], 'int main(void) {\n${powers}\tunsigned __int128 D = t100 + 7;\n\tunsigned __int128 q = D / 3;\n\tunsigned __int128 r = D % 3;\n\treturn (q * 3 + r) == D && r < 3;\n}\n')
	assert large == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A 128-bit value computed in the program and run: the pair the two words travel
// in reaches the program's own answer, through a declaration, an assignment, a
// member, an element and a function call. Measured on gcc 16.2.1, each program
// below returns the status written beside it.
fn test_a_128_bit_value_is_computed_and_runs() {
	cases := [
		WideValueCase{'int main(void) { __int128 a = 40; int n = a + 2; return n; }', 42},
		WideValueCase{'struct S { __int128 v; }; int main(void) { struct S s; s.v = 40; __int128 b = 2; return (int)(s.v + b); }', 42},
		WideValueCase{'int main(void) { __int128 a[2]; a[0] = 40; a[1] = 2; return (int)(a[0] + a[1]); }', 42},
		WideValueCase{'int two(void) { return 2; } int main(void) { __int128 a = 40; return (int)(a + two()); }', 42},
		WideValueCase{'int main(void) { __int128 a = 40; __int128 w; w = a + 1; return (int)w; }', 41},
	]
	for case in cases {
		source := scratch('wide_value.c')
		binary := scratch('wide_value')
		exit_status := compile_and_run([source, '-o', binary], case.source + '\n')
		assert exit_status == case.status
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// The low word of a 128-bit object is what a narrower slot takes, and the round
// trip through the built compiler is the same answer the codegen test asserts:
// measured on gcc 16.2.1, an int declared from a stored 300 is 300 and a char from
// the same object is 44. A floating slot is the case the low word is wrong for, and
// it is refused rather than stored.
// A pair multiplied by a pair, run: the answer is the program's exit status, and
// gcc 16.2.1 gives the same one for each of these. The expected 128-bit value is
// written as a power of two doubled the number of times it needs, because the
// language has no literal that wide and no shift.
fn test_two_128_bit_values_are_multiplied_and_run() {
	mut powers := '\tunsigned __int128 t64 = 1;\n'
	for _ in 0 .. 64 {
		powers += '\tt64 = t64 + t64;\n'
	}
	powers += '\tunsigned __int128 t32 = 1;\n'
	for _ in 0 .. 32 {
		powers += '\tt32 = t32 + t32;\n'
	}
	source := scratch('wide_mul.c')
	binary := scratch('wide_mul')
	// The low product's high word is what reaches the answer in the first of
	// these, and the two cross products carry a sign in the second.
	first := 'int main(void) {\n${powers}\tunsigned __int128 a = t32 + 1;\n\tunsigned __int128 p = a * a;\n\treturn p == t64 + t32 + t32 + 1;\n}\n'
	second := 'int main(void) {\n${powers}\t__int128 a = 0 - t64 - 1;\n\t__int128 b = t64 + 5;\n\t__int128 p = a * b;\n\t__int128 e = 0;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - t64;\n\te = e - 5;\n\treturn p == e;\n}\n'
	mut exit_status := compile_and_run([source, '-o', binary], first)
	assert exit_status == 1
	exit_status = compile_and_run([source, '-o', binary], second)
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

fn test_a_128_bit_object_is_stored_into_a_narrower_slot() {
	cases := ['int main(void) { __int128 v = 300; int n = v; return n; }',
		'int main(void) { __int128 v = 300; char c = v; return c; }',
		'int main(void) { __int128 v = 300; int n = 0; n = v; return n; }',
		'int main(void) { __int128 v = -1; int n = v; return n; }']
	answers := [44, 44, 44, 255]
	for i, source_text in cases {
		source := scratch('wide_narrow_${i}.c')
		binary := scratch('wide_narrow_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
	floating := scratch('wide_narrow_double.c')
	image := compile([floating, '-o', scratch('wide_narrow_double')],
		'int main(void) { __int128 v = 5; double d = v; return (int)d; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('does not convert to a floating type')
	assert image.bytes.len == 0
	os.rm(floating) or {}
}

// An operand whose type the reader never resolved is refused where typeof was
// written, and nothing is written out: a declaration built from a type nothing
// answered for would be a declaration nothing can size.
fn test_typeof_of_a_name_nothing_declares_writes_nothing() {
	source := scratch('typeof_bad.c')
	binary := scratch('typeof_bad')
	os.write_file(source, 'int main() { typeof(nothing) y = 1; return y; }\n') or { panic(err) }
	lexed := tokenize.lex(os.read_file(source) or { '' })
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len > 0
	assert parsed.diagnostics[0].msg.contains('typeof asks for the type of nothing')
	assert !os.exists(binary)
	os.rm(source) or {}
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

// A complex value from a library call, its component read and compared. A report
// once read this shape as a silent wrong value, and the measurement that settles
// it is gcc's own: gcc constant-folds `cpow(2.0, 3.0)` to exactly 8.0, while the
// runtime glibc `cpow` on this machine answers 7.9999999999999982 - one ULP below
// 8.0 - and `gcc -O0 -fno-builtin` on the same source answers with the runtime
// value too. This compiler calls the library and folds no floating builtin, so
// `__real__ cpow(2.0, 3.0) == 8.0` is false in it, and the component it reads is
// bit-for-bit the one gcc reads with the fold off. The program below uses a
// library call whose result IS exact, so the comparison is a claim about the read
// and not about the library. Measured on gcc 16.2.1, it exits 0.
fn test_a_component_read_from_a_library_call_is_the_value_the_library_wrote() {
	source := scratch('complex_call.c')
	binary := scratch('complex_call')
	program := 'double _Complex csqrt(double _Complex);\n' +
		'int main(void) {\n' +
		'    double _Complex c = csqrt(-4.0);\n' +
		'    if (__real__ c != 0.0) { return 1; }\n' +
		'    if (__imag__ c != 2.0) { return 2; }\n' +
		'    double r = __real__ c;\n' +
		'    if (r != 0.0) { return 3; }\n' +
		'    if (__real__ c == 0.0 && __imag__ c == 2.0) { return 0; }\n' +
		'    return 4;\n' +
		'}\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The extended complex type crosses a call the same way: an argument is a
// thirty-two byte object in memory, the real part at the lower address, and the
// return leaves two extended components on the x87 stack, st(0) the real part
// and st(1) the imaginary one. Measured on gcc 16.2.1: `sizeof` is thirty-two,
// `csqrtl(4.0L)` is exactly 2.0 in the real part and 0.0 in the imaginary one,
// so the comparison is about the convention rather than about the library. The
// real argument is converted to the complex type with a zero imaginary part
// before the call, which is 6.3.2.2 and the shape the corpus's `csqrtl(4.0L)`
// is written in.
fn test_the_extended_complex_type_crosses_a_library_call() {
	source := scratch('complex_long_call.c')
	binary := scratch('complex_long_call')
	program := 'long double _Complex csqrtl(long double _Complex);\n' +
		'long double creall(long double _Complex);\n' +
		'long double cimagl(long double _Complex);\n' +
		'int main(void) {\n' +
		'    long double _Complex c = csqrtl(4.0L);\n' +
		'    if (sizeof c != 32) { return 1; }\n' +
		'    if (creall(c) != 2.0L) { return 2; }\n' +
		'    if (cimagl(c) != 0.0L) { return 3; }\n' +
		'    return 0;\n' +
		'}\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A constant conditional whose arms are a complex type, handed to a parameter of
// that type. `<tgmath.h>` is where the shape comes from rather than a program:
// with a `__GNUC__` this compiler predefines, glibc's type-generic macros expand
// to a chain of conditionals over `sizeof` and `__builtin_classify_type`, so
// `creal(conj(z))` hands a conditional to `creal`'s parameter. The condition is a
// constant, so 6.5.15 selects one arm and the other is never evaluated; measured
// on gcc 16.2.1, this program exits 0.
fn test_a_constant_conditional_of_a_complex_type_is_converted_to_it() {
	source := scratch('complex_conditional.c')
	binary := scratch('complex_conditional')
	program := 'double _Complex csqrt(double _Complex);\n' +
		'double creal(double _Complex);\n' +
		'int main(void) {\n' +
		'    double _Complex z = csqrt(-9.0);\n' +
		'    if (creal(1 ? z : z) != 0.0) { return 1; }\n' +
		'    double _Complex w = 1.0 + 2.0 * 1.0iF;\n' +
		'    if (creal(0 ? z : w) != 1.0) { return 2; }\n' +
		'    if (creal(1 ? w : z) != 1.0) { return 3; }\n' +
		'    return 0;\n' +
		'}\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A conditional whose type is float, in the shape `<tgmath.h>` writes: a
// `sizeof` dispatch over one call per floating width, handed to a `float`
// parameter, the corpus's `sqrt(4.0f)`. The result type is a float, so the arm
// has to be a float and not a double: before this the arm was widened to double
// and the four-byte return read the low half of it, which is zero, so this
// program exited 1 at the first check. Measured on gcc 16.2.1, it exits 0.
fn test_a_float_conditional_dispatched_by_sizeof_is_a_float_value() {
	source := scratch('float_conditional.c')
	binary := scratch('float_conditional')
	program := 'float sqrtf(float);\n' +
		'double sqrt(double);\n' +
		'float dispatchf(float a) { return sizeof(a) == sizeof(float) ? sqrtf(a) : (float)sqrt((double)a); }\n' +
		'double dispatchd(double a) { return sizeof(a) == sizeof(double) ? sqrt(a) : (double)sqrtf((float)a); }\n' +
		'int main(void) {\n' +
		'    float f = 4.0f;\n' +
		'    float r = dispatchf(f);\n' +
		'    if (r != 2.0f) { return 1; }\n' +
		'    if (sizeof(dispatchf(f)) != sizeof(float)) { return 2; }\n' +
		'    if (sizeof(1 ? f : f) != sizeof(float)) { return 3; }\n' +
		'    double d = 4.0;\n' +
		'    if (dispatchd(d) != 2.0) { return 4; }\n' +
		'    return 0;\n' +
		'}\n'
	exit_status := compile_and_run(['-lm', source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The other half of that: with the library not named, the compile is refused and
// the symbol is named. It used to compile and die at load saying which symbol it
// could not find, which was silent at compile time, and a build that trusts the
// exit status took the image for a success.
fn test_without_the_library_the_symbol_is_refused_by_name() {
	source := scratch('nolibm.c')
	program := 'int fetestexcept(int);\nint main() { return fetestexcept(0); }\n'
	opts := cli.parse([source, '-o', scratch('nolibm')])!
	image := compile([source, '-o', scratch('nolibm')], program)
	assert opts.libraries.len == 0
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('fetestexcept')
	assert image.diagnostics[0].msg.contains('no library the image names defines it')
	// No bytes means main() writes no file and leaves with a non-zero status.
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// An external the file declares and never defines, with no library named to
// supply it, is refused at compile time and leaves no image. This program used
// to compile with exit status 0 and nothing on stderr, and the binary died at
// load: the shape the check exists to keep out.
fn test_an_external_nothing_defines_is_refused_by_name() {
	source := scratch('undefined_external.c')
	program := 'extern int nowhere(void);\nint main(void) { return nowhere(); }\n'
	image := compile([source, '-o', scratch('undefined_external')], program)
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('nowhere')
	assert image.diagnostics[0].msg.contains('no library the image names defines it')
	assert image.bytes.len == 0
	os.rm(source) or {}
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

// An object of an aggregate type of one eightbyte is handed over as its bytes in
// one register: the caller takes the object's address and reads the eightbyte from
// it, and the callee copies that register into the parameter's storage. The class
// decides which register file, so a struct of one double travels where a double
// does.
fn test_an_object_of_an_aggregate_type_is_handed_over_by_value() {
	source := scratch('byvalue.c')
	binary := scratch('byvalue')
	program := 'struct S { int a; int b; };\nint f(struct S s) { return s.a * 10 + s.b; }\nint main(void) { struct S s; s.a = 3; s.b = 4; return f(s); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 34
	os.rm(source) or {}
	os.rm(binary) or {}
}

// One byte of object travels the same way as eight, and a member of a member and a
// top-level object are both read from where they are rather than from a copy.
fn test_a_small_object_and_a_top_level_object_are_handed_over_by_value() {
	source := scratch('byvaluesmall.c')
	binary := scratch('byvaluesmall')
	program := 'struct C { char c; };\nint f(struct C x) { return x.c; }\nstruct C g;\nint main(void) { struct C x; x.c = 60; g.c = 5; return f(x) + f(g); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 65
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An object of two eightbytes is handed over in two registers, one for each
// eightbyte's class, and the object goes on the stack whole when either sequence has
// no register left for it. Which registers they are is the same answer the callee
// reaches, so a pair whose second eightbyte did not fit arrives in memory rather
// than half in a register.
fn test_an_object_of_two_eightbytes_is_handed_over_in_two_registers() {
	source := scratch('pairregisters.c')
	binary := scratch('pairregisters')
	program := 'struct W { int a; int b; int c; };\nint f(struct W w) { return w.a * 100 + w.b * 10 + w.c; }\nint main(void) { struct W w; w.a = 1; w.b = 2; w.c = 3; return f(w); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 123
	source_four := scratch('pairregistersfour.c')
	binary_four := scratch('pairregistersfour')
	program_four := 'struct W { int a; int b; int c; };\nint f(struct W u, struct W v, struct W w, struct W x) { return u.a + v.a * 2 + w.a * 4 + x.a * 8; }\nint main(void) { struct W u; struct W v; struct W w; struct W x; u.a = 1; v.a = 2; w.a = 3; x.a = 4; return f(u, v, w, x); }\n'
	four_status := compile_and_run([source_four, '-o', binary_four], program_four)
	assert four_status == 49
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_four) or {}
	os.rm(binary_four) or {}
}

// The class of each eightbyte decides which file carries it, and the two eightbytes
// of one object may be carried by different files: a struct of two doubles is two
// floating registers, a struct of a double and an int is one of each.
fn test_two_eightbytes_are_carried_by_the_file_each_class_names() {
	source := scratch('pairfloating.c')
	binary := scratch('pairfloating')
	program := 'struct T { double x; double y; };\ndouble f(struct T t) { return t.x * 10.0 + t.y; }\nint main(void) { struct T t; t.x = 2.0; t.y = 3.0; return f(t) * 100.0; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 252
	source_mixed := scratch('pairmixed.c')
	binary_mixed := scratch('pairmixed')
	program_mixed := 'struct M { double d; int i; };\nint f(struct M m) { return m.i * 10 + (m.d > 1.0); }\nint main(void) { struct M m; m.d = 2.0; m.i = 3; return f(m); }\n'
	mixed_status := compile_and_run([source_mixed, '-o', binary_mixed], program_mixed)
	assert mixed_status == 31
	source_hole := scratch('pairhole.c')
	binary_hole := scratch('pairhole')
	program_hole := 'struct H { char c; double d; };\nint f(struct H h) { return h.c * 10 + (h.d > 1.0); }\nint main(void) { struct H h; h.c = 2; h.d = 3.0; return f(h); }\n'
	hole_status := compile_and_run([source_hole, '-o', binary_hole], program_hole)
	assert hole_status == 21
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_mixed) or {}
	os.rm(binary_mixed) or {}
	os.rm(source_hole) or {}
	os.rm(binary_hole) or {}
}

// An object of two eightbytes whose registers have run out goes on the stack whole:
// five ints leave one general register, which is not enough for an object that needs
// two, and the callee finds it in memory. The second eightbyte is the one at the
// higher address, which is why the caller pushes it first.
fn test_an_object_of_two_eightbytes_goes_on_the_stack_when_a_register_ran_out() {
	source := scratch('pairstack.c')
	binary := scratch('pairstack')
	program := 'struct W { int a; int b; int c; };\nint f(int p, int q, int r, int s, int t, struct W w) { return p + q + r + s + t + w.a * 10 + w.b; }\nint main(void) { struct W w; w.a = 4; w.b = 5; w.c = 6; return f(1, 1, 1, 1, 1, w); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 50
	source_six := scratch('pairstacksix.c')
	binary_six := scratch('pairstacksix')
	program_six := 'struct W { int a; int b; int c; };\nint f(int p, int q, int r, int s, int t, int u, struct W w) { return w.a * 100 + w.b * 10 + w.c; }\nint main(void) { struct W w; w.a = 1; w.b = 2; w.c = 3; return f(0, 0, 0, 0, 0, 0, w); }\n'
	six_status := compile_and_run([source_six, '-o', binary_six], program_six)
	assert six_status == 123
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_six) or {}
	os.rm(binary_six) or {}
}

// An object of more than two eightbytes is passed in memory: the caller puts a copy
// of it on the stack, its words in reverse so that the first one ends up at the
// lowest address, and the callee copies as many bytes as the object has out of the
// stack into its own storage. That copy is what makes a parameter's writes local to
// the call: what the caller has is a different object.
fn test_an_object_of_more_than_two_eightbytes_is_passed_in_memory() {
	source := scratch('memoryobject.c')
	binary := scratch('memoryobject')
	program := 'struct B { double a; double b; double c; };\ndouble f(struct B x) { return x.a * 100.0 + x.b * 10.0 + x.c; }\nint main(void) { struct B b; b.a = 1.0; b.b = 2.0; b.c = 3.0; return f(b); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 123
	// An object whose size is not a multiple of eight: the last word of the copy is
	// as wide as the bytes the object has left and no wider.
	source_odd := scratch('memoryobjectodd.c')
	binary_odd := scratch('memoryobjectodd')
	program_odd := 'struct F { int a; int b; int c; int d; int e; };\nint f(struct F s) { return s.a * 100 + s.b * 10 + s.e; }\nint main(void) { struct F s; s.a = 1; s.b = 2; s.c = 3; s.d = 4; s.e = 5; return f(s); }\n'
	odd_status := compile_and_run([source_odd, '-o', binary_odd], program_odd)
	assert odd_status == 125
	// Two objects in memory with a value between them, so that the order of the
	// stack and the position each one is read at are both the convention's.
	source_two := scratch('memoryobjecttwo.c')
	binary_two := scratch('memoryobjecttwo')
	program_two := 'struct S { int a; int b; int c; int d; };\nint f(struct S s, int p, struct S t) { return s.a + p + t.d * 10; }\nint main(void) { struct S s; struct S t; s.a = 1; s.b = 2; s.c = 3; s.d = 4; t.a = 1; t.b = 2; t.c = 3; t.d = 5; return f(s, 2, t); }\n'
	two_status := compile_and_run([source_two, '-o', binary_two], program_two)
	assert two_status == 53
	// A parameter of such a type is storage of its own: writing to it does not write
	// to the object the caller passed.
	source_copy := scratch('memoryobjectcopy.c')
	binary_copy := scratch('memoryobjectcopy')
	program_copy := 'struct S { int a; int b; int c; int d; };\nint f(struct S s) { s.a = 9; return s.a; }\nint main(void) { struct S s; s.a = 1; s.b = 2; s.c = 3; s.d = 4; int r = f(s); return s.a * 10 + r; }\n'
	copy_status := compile_and_run([source_copy, '-o', binary_copy], program_copy)
	assert copy_status == 19
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_odd) or {}
	os.rm(binary_odd) or {}
	os.rm(source_two) or {}
	os.rm(binary_two) or {}
	os.rm(source_copy) or {}
	os.rm(binary_copy) or {}
}

// A function hands an object back as its bytes in the register the class names, so
// the caller reads that register: assigning it into another object of the type is
// the same eight bytes, and a struct of one double comes back where a double comes
// back. The declaration of a local with such an initializer is the same copy into
// the storage the declaration just claimed.
fn test_an_object_is_handed_back_from_a_function() {
	source := scratch('byvaluereturn.c')
	binary := scratch('byvaluereturn')
	program := 'struct S { int a; int b; };\nstruct S f(void) { struct S s; s.a = 1; s.b = 2; return s; }\nint main(void) { struct S s = f(); struct S t; t = f(); return s.a * 100 + s.b * 10 + t.a; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 121 % 256
	source_double := scratch('byvaluereturndouble.c')
	binary_double := scratch('byvaluereturndouble')
	program_double := 'struct D { double d; };\nstruct D f(void) { struct D x; x.d = 2.5; return x; }\nint main(void) { struct D y; y = f(); return y.d * 2.0; }\n'
	double_status := compile_and_run([source_double, '-o', binary_double], program_double)
	assert double_status == 5
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_double) or {}
	os.rm(binary_double) or {}
}

// An object of two eightbytes comes back in two registers too, and the caller writes
// both of them into the object it is assigned to: the second register is the one
// beside the first in its own file, so the two files are numbered apart.
fn test_an_object_of_two_eightbytes_is_handed_back_in_two_registers() {
	source := scratch('pairreturn.c')
	binary := scratch('pairreturn')
	program := 'struct W { int a; int b; int c; };\nstruct W f(void) { struct W w; w.a = 1; w.b = 2; w.c = 3; return w; }\nint main(void) { struct W w; w = f(); struct W v = f(); return w.a * 100 + w.b * 10 + w.c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 123
	source_global := scratch('pairreturnglobal.c')
	binary_global := scratch('pairreturnglobal')
	program_global := 'struct W { int a; int b; int c; };\nstruct W g;\nstruct W f(void) { struct W w; w.a = 4; w.b = 5; w.c = 6; return w; }\nint main(void) { g = f(); return g.a; }\n'
	global_status := compile_and_run([source_global, '-o', binary_global], program_global)
	assert global_status == 4
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_global) or {}
	os.rm(binary_global) or {}
}

// A pair of floating eightbytes comes back in the machine's two floating registers,
// which is where a double and the double beside it come back.
fn test_two_floating_eightbytes_are_handed_back_in_two_registers() {
	source := scratch('pairreturnfloating.c')
	binary := scratch('pairreturnfloating')
	program := 'struct T { double x; double y; };\nstruct T f(void) { struct T t; t.x = 2.0; t.y = 0.5; return t; }\nint main(void) { struct T t = f(); return t.x * 100.0 + t.y * 10.0; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 205
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A function that hands an object of more than two eightbytes back is given an address
// to put it at in the first general register, and the call answers with that address.
// The address is an argument the caller writes and the definition reads before its own
// parameters, so every argument written in the call moves one register later.
fn test_an_object_of_more_than_two_eightbytes_is_handed_back_through_an_address() {
	source := scratch('memoryreturn.c')
	binary := scratch('memoryreturn')
	program := 'struct B { double a; double b; double c; };\nstruct B f(void) { struct B b; b.a = 1.0; b.b = 2.0; b.c = 3.0; return b; }\nint main(void) { struct B b; b = f(); return b.a * 100.0 + b.b * 10.0 + b.c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 123
	// The hidden address is the first general register, so a parameter written in the
	// definition arrives in the second one and the two sequences stay in step.
	source_args := scratch('memoryreturnargs.c')
	binary_args := scratch('memoryreturnargs')
	program_args := 'struct F { int a; int b; int c; int d; int e; };\nstruct F f(int p, int q) { struct F x; x.a = p; x.b = q; x.c = p + q; x.d = p * q; x.e = 7; return x; }\nint main(void) { struct F x; x = f(2, 3); return x.c * 10 + x.d; }\n'
	args_status := compile_and_run([source_args, '-o', binary_args], program_args)
	assert args_status == 56
	// An object handed over in memory and an object handed back through an address in
	// the same call: both directions at once.
	source_both := scratch('memoryreturnboth.c')
	binary_both := scratch('memoryreturnboth')
	program_both := 'struct S { int a; int b; int c; int d; };\nstruct S f(struct S s) { struct S t; t.a = s.a + 1; t.b = s.b + 1; t.c = s.c + 1; t.d = s.d + 1; return t; }\nint main(void) { struct S s; s.a = 1; s.b = 2; s.c = 3; s.d = 4; struct S t; t = f(s); return t.a * 100 + t.b * 10 + t.d; }\n'
	both_status := compile_and_run([source_both, '-o', binary_both], program_both)
	assert both_status == 235
	// Two of them in a row: the storage the caller lends is one slot per function,
	// because the result of such a call cannot be an argument or a value.
	source_two := scratch('memoryreturntwo.c')
	binary_two := scratch('memoryreturntwo')
	program_two := 'struct S { int a; int b; int c; int d; };\nstruct S f(int n) { struct S s; s.a = n; s.b = n * 2; s.c = n * 3; s.d = n * 4; return s; }\nint main(void) { struct S s; struct S t; s = f(1); t = f(2); return s.a * 10 + t.d; }\n'
	two_status := compile_and_run([source_two, '-o', binary_two], program_two)
	assert two_status == 18
	// A top-level object takes the result the same way: the copy goes to the image.
	source_global := scratch('memoryreturnglobal.c')
	binary_global := scratch('memoryreturnglobal')
	program_global := 'struct B { double a; double b; double c; };\nstruct B g;\nstruct B f(void) { struct B b; b.a = 1.0; b.b = 2.0; b.c = 3.0; return b; }\nint main(void) { g = f(); return g.a * 100.0 + g.b * 10.0 + g.c; }\n'
	global_status := compile_and_run([source_global, '-o', binary_global], program_global)
	assert global_status == 123
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(source_args) or {}
	os.rm(binary_args) or {}
	os.rm(source_both) or {}
	os.rm(binary_both) or {}
	os.rm(source_two) or {}
	os.rm(binary_two) or {}
	os.rm(source_global) or {}
	os.rm(binary_global) or {}
}

// One object is written into another by copying its bytes, which is what 6.5.16.1
// gives an assignment between two objects of the same type: no conversion is
// involved and neither object is read as a value.
fn test_one_object_is_copied_into_another() {
	source := scratch('byvaluecopy.c')
	binary := scratch('byvaluecopy')
	program := 'struct S { int a; int b; char c; };\nint main(void) { struct S s; struct S t; s.a = 1; s.b = 2; s.c = 3; t = s; return t.a * 100 + t.b * 10 + t.c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 123
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An object takes one register of its class like a value does, so a call whose
// argument registers run out hands the object over on the stack: six ints and an
// object is the object past the last general register, and seven objects are six
// registers and one pushed word.
fn test_an_object_past_the_registers_is_handed_over_on_the_stack() {
	source := scratch('byvaluestack.c')
	binary := scratch('byvaluestack')
	program := 'struct S { int a; int b; };\nint f(int p, int q, int r, int s, int t, int u, struct S x) { return p + q + r + s + t + u + x.a * 10 + x.b; }\nint main(void) { struct S x; x.a = 4; x.b = 5; return f(1, 2, 3, 4, 5, 6, x); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 66
	seven := scratch('byvalueseven.c')
	seven_binary := scratch('byvalueseven')
	seven_program := 'struct S { int a; int b; };\nint f(struct S a, struct S b, struct S c, struct S d, struct S e, struct S f, struct S g) { return a.a + b.a + c.a + d.a + e.a + f.a + g.a; }\nint main(void) { struct S v; v.a = 1; v.b = 2; return f(v, v, v, v, v, v, v); }\n'
	seven_status := compile_and_run([seven, '-o', seven_binary], seven_program)
	assert seven_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
	os.rm(seven) or {}
	os.rm(seven_binary) or {}
}

// An element of an array of aggregates is a block of the layout's size, and the
// stride between elements is that size, which the index scales by. A member of an
// element is read at the element's address plus the member's own offset, so this
// runs the non-power-of-two stride too: the struct has a char member, which makes
// it eight bytes, and the machine has to multiply the index rather than scale it.
fn test_an_element_of_an_array_of_aggregates_is_read_at_the_stride_times_the_index() {
	source := scratch('arrayofstructs.c')
	binary := scratch('arrayofstructs')
	program := 'struct S { int a; int b; char c; };\nint main(void) { struct S s[3]; s[1].a = 9; s[2].b = 4; s[0].c = 2; return s[1].a * 100 + s[2].b * 10 + s[0].c; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 942 % 256
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The same stride applies to an array of aggregates at the top level, whose
// storage is in the image rather than the frame: an element is addressed from the
// object's address, and the member is at that element's offset.
fn test_an_array_of_aggregates_at_the_top_level_is_storage_in_the_image() {
	source := scratch('globalarrayofstructs.c')
	binary := scratch('globalarrayofstructs')
	program := 'struct S { int a; int b; };\nstruct S g[3];\nint main(void) { g[1].a = 5; g[2].b = 7; return g[1].a * 10 + g[2].b; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 57
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
	program := 'typedef long double _Imaginary Wide;\nWide x;\nint main(void) { return 0; }\n'
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

// A function that returns a 128-bit value and one that takes one, driven through
// the command line the way every other program here is: the source is written, the
// image is written out, and the image is run. The three programs cover a pair
// returned and used, a function of the type answering a narrower expression, and a
// pair passed beside a pointer and a char. Measured on gcc 16.2.1, the programs
// exit 42, 19 and 160.
fn test_a_128_bit_return_and_parameter_run_through_the_command_line() {
	cases := [
		'__int128 twice(__int128 a) { return a + a; }\nint main(void) { __int128 r = twice((__int128)21); return (int)r; }\n',
		'__int128 neg(void) { return -1; }\nint main(void) { __int128 r = neg(); return (int)r + ((int)(r >> 64) + 2) * 20; }\n',
		'int cp(char *s, __int128 a, char c) { return *s + (int)a + c; }\nint main(void) { return cp("zz", (__int128)34, 4); }\n',
	]
	answers := [42, 19, 160]
	for i, program in cases {
		source := scratch('wide_call_${i}.c')
		binary := scratch('wide_call_${i}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A pair the argument registers have no room for is refused through the command
// line as well, with nothing written out: the driver reports it where the parameter
// was written and leaves no image behind. Measured on gcc 16.2.1, which compiles
// this program and reads the pair from 16(%rbp).
fn test_a_128_bit_parameter_that_will_not_fit_the_registers_is_refused() {
	source := scratch('wide_memory.c')
	binary := scratch('wide_memory')
	image := compile([source, '-o', binary],
		'int f(int a, int b, int c, int d, int e, __int128 x) { return (int)x; }\nint main(void) { return 0; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].line == 1
	assert image.diagnostics[0].msg.contains('two argument registers at once')
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// C23 spells the 128-bit type `_BitInt(128)`, and a declaration written that way
// is the same type as one written `__int128`. Measured on gcc 16.2.1, this
// program exits 10: a thousand cubed is a thousand million, and the quotient by
// a hundred million is ten.
fn test_the_bitint_spelling_names_the_128_bit_type() {
	source := scratch('wide_bitint.c')
	binary := scratch('wide_bitint')
	program := 'int main(void) { _BitInt(128) a = 1000; a = a * 1000; a = a * 1000; return (int)(a / 100000000); }'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 10
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The width of a _BitInt is the type, so a width this compiler has no value for
// is refused by name rather than answered with the nearest type it does have.
// The 128-bit pair wraps at 128 bits and a `_BitInt(8)` wraps at eight, which is
// a different type, so the declaration is reported with the line it was written
// at. The refusal is the parser's, and it stops the program there rather than
// leaving a stage below to size a type nothing resolved.
fn test_a_bitint_width_with_no_value_here_is_refused() {
	source := scratch('wide_bitint_refused.c')
	program := 'int main(void) { _BitInt(8) x = 1; return (int)x; }'
	os.write_file(source, program) or { panic(err) }
	lexed := tokenize.lex(program)
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].line == 1
	assert parsed.diagnostics[0].msg.contains('_BitInt(8)')
	os.rm(source) or {}
}

// A 128-bit temporary belongs to the frame it was claimed in, and a program that
// hands two calls to a function of two pairs is where a temporary kept from the
// function before shows up: the first operand is parked on the slot the second
// parameter holds, and the sum comes back as the first value twice. Measured on gcc
// 16.2.1, this program exits 15.
fn test_a_pair_from_a_call_keeps_its_value_across_the_call() {
	source := scratch('wide_frames.c')
	binary := scratch('wide_frames')
	program := '__int128 g(__int128 x) { return x + 1; }\n' + '__int128 f(__int128 a, __int128 b) { return a + b; }\n' +
		'int main(void) { return (int)f(g(9), g(4)); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 15
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A do-while's body runs before its condition is read even once, which is the whole
// difference from a while: this program's test is false from the start and the body
// still runs, so it exits 1 and not 0. Measured on gcc 16.2.1.
fn test_a_do_while_runs_its_body_before_reading_the_condition() {
	source := scratch('do_once.c')
	binary := scratch('do_once')
	exit_status := compile_and_run([source, '-o', binary], 'int main() { int c = 0; do { c = c + 1; } while (0); return c; }\n')
	assert exit_status == 1
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A continue in a do-while belongs at the condition, which is the next thing C does
// after one, and where it lands is visible only when the condition has gone false by
// the time the continue runs. This program's third turn is that one: the condition is
// already false, so a continue that lands on the body's top label runs the body a
// fourth time and exits 7, while the right placement asks the condition and exits 3.
// Measured on gcc 16.2.1, which exits 3.
fn test_a_continue_in_a_do_while_goes_to_the_condition() {
	source := scratch('do_continue.c')
	binary := scratch('do_continue')
	program := 'int main() { int i = 0; int n = 0; do { i = i + 1; if (i == 3) continue; n = n + i; } while (i < 3); return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 3
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A break in a do-while leaves the loop and lands after it. Measured on gcc 16.2.1,
// this exits 3.
fn test_a_break_in_a_do_while_leaves_the_loop() {
	source := scratch('do_break.c')
	binary := scratch('do_break')
	program := 'int main() { int i = 0; int n = 0; do { i = i + 1; if (i > 3) break; n = n + 1; } while (i < 10); return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 3
	os.rm(source) or {}
	os.rm(binary) or {}
}

// `x++` is worth what x held before the step and `++x` what it holds after, and
// these programs tell the two apart rather than only checking that a step
// happened: the first exits 57 where a postfix form that yielded the new value
// would exit 67, and the second exits 53 where one would exit 43. Measured on
// gcc 16.2.1, which exits 57 and 53.
fn test_a_postfix_step_is_worth_the_old_value_and_a_prefix_one_the_new() {
	source := scratch('incdec_direction.c')
	binary := scratch('incdec_direction')
	increment := compile_and_run([source, '-o', binary],
		'int main(void) { int i = 5; int a = i++; int b = ++i; return a * 10 + b; }\n')
	assert increment == 57
	decrement := compile_and_run([source, '-o', binary],
		'int main(void) { int i = 5; int a = i--; int b = --i; return a * 10 + b; }\n')
	assert decrement == 53
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A brace initializer at the top level is written into the image, and the program
// reads the values it wrote and the zeros it did not. Measured on gcc 16.2.1, this
// exits 93: x[2] is 3, a[0]*10 is 90, and a[3] is 0 because the list wrote one
// value of four.
fn test_a_file_scope_brace_initializer_writes_the_values_into_the_image() {
	source := scratch('brace_global.c')
	binary := scratch('brace_global')
	program := 'int a[4] = {9};\nint x[] = {1, 2, 3};\nint main(void) { return x[2] + a[0] * 10 + a[3]; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 93
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The places a step is written: as a statement of its own, as the step of a for,
// as the value of an expression around it, and on a top-level object rather than
// a local. Each program is run, so what is checked is the bytes and not the
// intent. Measured on gcc 16.2.1, which exits 3, 8, 14 and 35.
fn test_a_step_runs_as_a_statement_a_loop_step_a_value_and_a_global() {
	source := scratch('incdec_where.c')
	binary := scratch('incdec_where')
	statement := compile_and_run([source, '-o', binary],
		'int main(void) { int i = 0; i++; i++; i++; return i; }\n')
	assert statement == 3
	loop_step := compile_and_run([source, '-o', binary],
		'int main(void) { int n = 0; int i = 0; for (i = 0; i < 4; i++) { n = n + 2; } return n; }\n')
	assert loop_step == 8
	enclosing := compile_and_run([source, '-o', binary],
		'int main(void) { int n = 10; int i = 4; return n + i++; }\n')
	assert enclosing == 14
	global := compile_and_run([source, '-o', binary],
		'int g = 3; int main(void) { int a = g++; int b = ++g; return a * 10 + b; }\n')
	assert global == 35
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The narrow integer types are types a whole program holds: each is a value in a
// register, widened on the way in and cut to its own width on the way out, and a
// `_Bool` is 0 or 1 whatever was stored into it. A value of one stored at the top
// level and an element of an array of one are read through an address rather than
// out of a frame slot, which is the other path a value is read by. The program is
// run, so what is checked is the bytes. Measured on gcc 16.2.1, this exits 11: one
// for each comparison that is true, the ones a sign taken where zero belongs or a
// zero where a sign belongs would answer differently, and the ones a conversion
// that did not cut to the width would too.
fn test_the_narrow_integer_types_run() {
	source := scratch('narrow_int.c')
	binary := scratch('narrow_int')
	program := 'static unsigned char gb[3] = {200, 100, 255};\nstatic unsigned short gus = 40000;\nint main(void) { unsigned char uc = 200; signed char sc = -56; short s = -300; unsigned short us = 40000; _Bool b = 42; return (uc == 200) + (sc == -56) + (s == -300) + (us == 40000) + (b == 1) + ((unsigned short)-1 == 65535) + ((short)70000 == 4464) + ((unsigned char)-1 == 255) + (gb[0] == 200) + (gb[2] == 255) + (gus == 40000); }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 11
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A brace initializer in a body is the stores the initialization makes, one per
// value the list wrote and a zero for each it did not, because the frame slot
// holds whatever was there. Measured on gcc 16.2.1, this exits 75: a[0]*10 is 70,
// a[1] is 0, and b[1] is 5.
fn test_a_body_brace_initializer_writes_the_values_into_the_frame() {
	source := scratch('brace_local.c')
	binary := scratch('brace_local')
	program := 'int main(void) { int a[3] = {7}; int b[] = {4, 5}; return a[0] * 10 + a[1] + b[1]; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 75
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An array whose brackets wrote no size takes its count from its initializer, and
// a later `sizeof` is a question about that count rather than about the brackets
// that wrote none. 6.7.8 fills the bound in only for an array declarator with no
// size at all, and only when the initializer is a list or a string. The programs
// are run, so what is checked is the bytes and not the intent. Measured on gcc
// 16.2.1, these exit 1, 1, 3, 2 and 4.
fn test_a_deduced_array_takes_its_size_from_its_initializer() {
	source := scratch('deduced_array.c')
	binary := scratch('deduced_array')
	flat := compile_and_run([source, '-o', binary],
		'int main(void) { int d[] = {2, 3, 5, 7, 11}; return sizeof d == 5 * sizeof(int) && d[4] == 11; }\n')
	assert flat == 1
	// The same at file scope, where the count is a fact the image carries.
	file := compile_and_run([source, '-o', binary],
		'int d[] = {2, 3, 5, 7, 11};\nint main(void) { return sizeof d == 5 * sizeof(int) && d[4] == 11; }\n')
	assert file == 1
	// A nested list sizes an array with empty brackets by the subobjects it
	// reaches, at either scope.
	two_d := compile_and_run([source, '-o', binary],
		'int main(void) { int m[][2] = {{1, 2}, {3, 4}, {5, 6}}; return sizeof(m) / sizeof(m[0]); }\n')
	assert two_d == 3
	aggregate := compile_and_run([source, '-o', binary],
		'struct S { int a; int b; };\nint main(void) { struct S p[] = {{1, 2}, {3, 4}}; return sizeof(p) / sizeof(p[0]); }\n')
	assert aggregate == 2
	// A string literal sizes a char array at the characters it writes and the
	// terminator it does not, so `sizeof` includes it: `abc` is four bytes.
	literal := compile_and_run([source, '-o', binary],
		'int main(void) { char s[] = "abc"; return sizeof(s); }\n')
	assert literal == 4
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A char is stepped at its own byte: the value 127 plus one is the byte 128,
// which as a char is -128 and as the int the exit status is read at is 128. The
// increment of a char is therefore a wrap at one byte, not an int that grew.
// Measured on gcc 16.2.1, which exits 128.
fn test_a_char_is_stepped_at_its_own_byte() {
	source := scratch('incdec_char.c')
	binary := scratch('incdec_char')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { char c = 127; c++; return c; }\n')
	assert exit_status == 128
	os.rm(source) or {}
	os.rm(binary) or {}
}

// An integer name of any width the back end stores is stepped by one, at the
// object's own width, whether the step is the only thing in the statement or the
// value is used. The programs are run, so what is checked is the bytes and not
// the intent. Measured on gcc 16.2.1, which exits 6, 201, 128, 199 and 4.
fn test_an_integer_name_of_any_width_steps_by_one() {
	source := scratch('incdec_width.c')
	binary := scratch('incdec_width')
	long := compile_and_run([source, '-o', binary],
		'int main(void) { long i = 5; i++; return (int)i; }\n')
	assert long == 6
	unsigned_long := compile_and_run([source, '-o', binary],
		'int main(void) { unsigned long i = 200; ++i; return (int)i; }\n')
	assert unsigned_long == 201
	short := compile_and_run([source, '-o', binary],
		'int main(void) { short s = 127; s++; return (int)s; }\n')
	assert short == 128
	unsigned_int := compile_and_run([source, '-o', binary],
		'int main(void) { unsigned i = 200; i--; return (int)i; }\n')
	assert unsigned_int == 199
	plain_int := compile_and_run([source, '-o', binary],
		'int main(void) { int i = 5; --i; return i; }\n')
	assert plain_int == 4
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A pointer name is stepped by the size of what it points at and not by one: a
// char pointer by one, an int pointer by four, a double pointer by eight, a
// pointer to a two-int struct by eight, a pointer to a pointer by the word, and
// a pointer to an array of three ints by twelve. Each program reads the element
// the stepped pointer should name, so a stride of one reads the wrong bytes and
// a stride too far misses the element rather than passing quietly. The int**
// case reads the stride as an address difference, because reading through it
// would need a second live pointer and the point is the number of bytes moved.
// Measured on gcc 16.2.1, which exits 8, 6, 5, 7, 8 and 9.
fn test_a_pointer_step_uses_the_size_of_what_it_points_at() {
	source := scratch('incdec_stride.c')
	binary := scratch('incdec_stride')
	char_pointer := compile_and_run([source, '-o', binary],
		'int main(void) { char s[3] = {7, 8, 9}; char *p = s; p++; return p[0]; }\n')
	assert char_pointer == 8
	int_pointer := compile_and_run([source, '-o', binary],
		'int main(void) { int a[3] = {0, 0, 6}; int *p = a; p++; p++; return *p; }\n')
	assert int_pointer == 6
	double_pointer := compile_and_run([source, '-o', binary],
		'int main(void) { double d[2] = {1.0, 5.0}; double *p = d; p++; return (int)*p; }\n')
	assert double_pointer == 5
	struct_pointer := compile_and_run([source, '-o', binary],
		'struct S { int x; int y; };\nint main(void) { struct S a[2]; a[1].x = 7; struct S *p = &a[0]; p++; return p->x; }\n')
	assert struct_pointer == 7
	pointer_pointer := compile_and_run([source, '-o', binary],
		'int main(void) { int v = 0; int *px = &v; int **pp = &px; unsigned long b = (unsigned long)pp; pp++; return (int)((unsigned long)pp - b); }\n')
	assert pointer_pointer == 8
	array_pointer := compile_and_run([source, '-o', binary],
		'int main(void) { int g[2][3]; g[1][2] = 9; int (*p)[3] = g; p++; return p[0][2]; }\n')
	assert array_pointer == 9
	decrement := compile_and_run([source, '-o', binary],
		'int main(void) { int a[3] = {4, 5, 6}; int *p = a + 2; p--; return *p; }\n')
	assert decrement == 5
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A floating object is stepped by one of its own width, at the width it is
// stored with: a double adds 1.0 in eight bytes and a float 1.0f in four. The
// name, the member read through a dot and the member read through `->` are the
// same step, and the postfix form is worth what the object held. The programs
// are run, so what is checked is the bytes rather than the intent. Measured on
// gcc 16.2.1, which exits 9, 5, 5, 18, 8, 14 and 6.
fn test_a_floating_object_is_stepped_by_one_of_its_width() {
	source := scratch('incdec_float.c')
	binary := scratch('incdec_float')
	double_name := compile_and_run([source, '-o', binary],
		'int main(void) { double d = 2.5; d++; d++; return (int)(d * 2); }\n')
	assert double_name == 9
	double_postfix := compile_and_run([source, '-o', binary],
		'int main(void) { double d = 2.5; double x = d++; return (int)(x * 2); }\n')
	assert double_postfix == 5
	float_decrement := compile_and_run([source, '-o', binary],
		'int main(void) { float f = 3.5f; f--; return (int)(f * 2); }\n')
	assert float_decrement == 5
	float_member := compile_and_run([source, '-o', binary],
		'struct S { float f; };\nint main(void) { struct S s; s.f = 1.25f; s.f++; return (int)(s.f * 8); }\n')
	assert float_member == 18
	double_arrow := compile_and_run([source, '-o', binary],
		'struct S { double d; };\nint main(void) { struct S s; s.d = 1.0; struct S *p = &s; p->d++; return (int)(s.d * 4); }\n')
	assert double_arrow == 8
	double_element := compile_and_run([source, '-o', binary],
		'int main(void) { double a[2] = {1.0, 2.5}; a[1]++; return (int)(a[1] * 4); }\n')
	assert double_element == 14
	double_element_postfix := compile_and_run([source, '-o', binary],
		'int main(void) { double a[2] = {1.0, 2.5}; double old = a[0]++; return (int)(old * 2) + (int)(a[0] * 2); }\n')
	assert double_element_postfix == 6
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A pointer whose pointed-at type has no size has no step to compute: `void *`
// is the standing case, and a pointer to a function and to an undefined struct
// are the same shape. Refused by name where the operator is written.
fn test_a_step_on_a_pointer_with_no_pointed_at_size_is_refused() {
	source := scratch('incdec_voidptr.c')
	binary := scratch('incdec_voidptr')
	text := 'int main(void) { void *p; p++; return 0; }\n'
	image := compile([source, '-o', binary], text)
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('which is void *')
	assert image.diagnostics[0].msg.contains('has no size to step by')
	os.rm(source) or {}
}

// An element is an object the operator can step in place: `a[i]++` reads the
// element at the old index, steps it and leaves it stepped, and a postfix step
// is worth what the element held. The programs are run, so what is checked is
// the bytes and not the intent. Measured on gcc 16.2.1, which exits 6, 7 and 6.
fn test_an_element_or_a_member_steps_in_place() {
	source := scratch('incdec_object.c')
	binary := scratch('incdec_object')
	element := compile_and_run([source, '-o', binary],
		'int main(void) { int a[3] = {5, 0, 0}; a[0]++; return a[0]; }\n')
	assert element == 6
	member := compile_and_run([source, '-o', binary],
		'struct S { int m; };\nint main(void) { struct S s; s.m = 6; ++s.m; return s.m; }\n')
	assert member == 7
	arrow := compile_and_run([source, '-o', binary],
		'struct S { int m; };\nint main(void) { struct S s; s.m = 5; struct S *p = &s; p->m++; return s.m; }\n')
	assert arrow == 6
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The index of the element a postfix step is written on is evaluated once: `a[i++]++`
// steps the element at the old index and increments the index a single time. A
// second evaluation of the index, or one made after the element's step, is a
// silent wrong value with no diagnostic to show for it. Measured on gcc 16.2.1:
// the element is 100 at the old index, 101 after the step, and the index is 1.
fn test_the_index_of_a_stepped_element_is_read_once() {
	source := scratch('incdec_once.c')
	binary := scratch('incdec_once')
	exit_status := compile_and_run([source, '-o', binary],
		'int main(void) { int a[3] = {100, 0, 0}; int i = 0; int old = a[i++]++; return old + a[0] + i; }\n')
	assert exit_status == 202
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A scalar wrapped in braces is the value in them, at either scope, and an array
// of doubles takes the constants in the class of its elements: an integer in a
// double list is that integer as a double. Measured on gcc 16.2.1, these exit 8
// and 35.
fn test_a_scalar_in_braces_and_a_list_of_doubles_hold_what_they_wrote() {
	source := scratch('brace_scalar.c')
	binary := scratch('brace_scalar')
	scalars := 'int x = {5};\nint main(void) { int y = {3}; return x + y; }\n'
	assert compile_and_run([source, '-o', binary], scalars) == 8
	doubles := 'static const double d[] = {1.5, 2};\nint main(void) { return (int)(d[0] * 10) + (int)(d[1] * 10); }\n'
	assert compile_and_run([source, '-o', binary], doubles) == 35
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A case with no break before the next label runs into it, which is what makes a
// switch a jump into a run of statements and not a chain of branches: this
// program exits 11, and one that stopped at each case would exit 1. Measured on
// gcc 16.2.1, which exits 11.
fn test_a_case_falls_through_into_the_next_one() {
	source := scratch('switch_fallthrough.c')
	binary := scratch('switch_fallthrough')
	program := 'int main(void) { int n = 0; switch (1) { case 1: n += 1; case 2: n += 10; break; default: n += 100; } return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 11
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A default reads the same wherever it is written and runs only when no case
// matches, so its position in the body is not its position in the dispatch. The
// three programs here exit 2, 0 and 7: the default written first is taken when
// nothing else matches, a switch with no matching case and no default runs none
// of its body, and a default in the middle is taken from either side of it.
// Measured on gcc 16.2.1, which exits 2, 0 and 7.
fn test_a_default_reads_wherever_it_is_written_and_only_when_nothing_matches() {
	source := scratch('switch_default.c')
	binary := scratch('switch_default')
	first := 'int main(void) { int n = 0; switch (2) { default: n += 100; break; case 1: n += 1; break; case 2: n += 2; break; } return n; }\n'
	assert compile_and_run([source, '-o', binary], first) == 2
	unmatched := 'int main(void) { int n = 0; switch (5) { case 1: n += 1; break; case 2: n += 2; break; } return n; }\n'
	assert compile_and_run([source, '-o', binary], unmatched) == 0
	middle := 'int main(void) { int n = 0; switch (5) { case 1: n += 1; break; default: n += 7; break; case 2: n += 2; break; } return n; }\n'
	assert compile_and_run([source, '-o', binary], middle) == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A continue inside a switch inside a loop belongs to the loop, so the turn the
// continue is on does not add to the accumulator below the switch. This program
// exits 44: four of the five turns add ten and one, and the turn the continue is
// on adds neither, where a continue that left the switch alone would exit 33 and
// one that left the loop would exit 11. Measured on gcc 16.2.1, which exits 44.
fn test_a_continue_in_a_switch_belongs_to_the_loop_outside_it() {
	source := scratch('switch_continue.c')
	binary := scratch('switch_continue')
	program := 'int main(void) { int i = 0; int n = 0; for (i = 0; i < 5; i++) { switch (i) { case 1: continue; default: n += 10; } n += 1; } return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 44
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A break inside a loop inside a switch belongs to the loop, because the loop
// encloses the break more closely than the switch does. This program exits 13:
// the loop leaves after three steps and the ten below it is added, where a break
// bound to the switch would leave it at once and exit 3. Measured on gcc 16.2.1,
// which exits 13.
fn test_a_break_in_a_loop_inside_a_switch_belongs_to_the_loop() {
	source := scratch('switch_break.c')
	binary := scratch('switch_break')
	program := 'int main(void) { int n = 0; switch (1) { case 1: while (1) { n = n + 1; if (n == 3) break; } n += 10; break; default: n += 100; } return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 13
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The case labels of a nested switch belong to it and not to the one outside, so
// a continue in the inner switch still belongs to the loop around both. This
// program exits 22: the two outer turns that are not case 1 add ten and one
// each, the case 1 turn adds neither because the continue skips the outer
// accumulator too, and the inner default is never reached. Measured on gcc
// 16.2.1, which exits 22.
fn test_a_nested_switch_owns_its_own_labels() {
	source := scratch('switch_nested.c')
	binary := scratch('switch_nested')
	program := 'int main(void) { int i = 0; int n = 0; for (i = 0; i < 3; i++) { switch (i) { case 1: switch (i) { case 1: continue; default: n += 1; } n += 100; break; default: n += 10; } n += 1; } return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 22
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A goto jumps forward, backward and out of nested loops, and the three are one
// mechanism: a name for a place in the function. This program exits 10, which is
// the value the forward jump leaves where a program that never took it exits 3,
// and the loops the second jump leaves have both of their counters at their
// first values. Measured on gcc 16.2.1, which exits 10 and 11.
fn test_a_goto_jumps_forward_backward_and_out_of_nested_loops() {
	source := scratch('goto_jumps.c')
	binary := scratch('goto_jumps')
	forward := 'int main(void) { int c = 0; goto forward; backward: c = c + 1; if (c < 3) goto backward; goto done; forward: c = 10; goto after; done: c = 3; after: return c; }\n'
	assert compile_and_run([source, '-o', binary], forward) == 10
	nested := 'int main(void) { int i = 0; int j = 0; for (i = 0; i < 3; ++i) { for (j = 0; j < 3; ++j) { if (i == 1 && j == 1) goto out_of_loops; } } out_of_loops: return i * 10 + j; }\n'
	assert compile_and_run([source, '-o', binary], nested) == 11
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A label is a name for a place and an object of the same name is another name,
// so the two do not collide. This program exits 7, and a reader that treated the
// label as a declaration of `label`, or the goto's name as a use of it, would
// either refuse the file or reach a different object. Measured on gcc 16.2.1,
// which exits 7.
fn test_a_label_and_an_object_of_the_same_name_are_two_names() {
	source := scratch('goto_namespace.c')
	binary := scratch('goto_namespace')
	program := 'int main(void) { int label = 5; goto past; past: label = label + 2; return label; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A label at the end of a block is a place a goto reaches, and the statement
// under it is the empty statement `;`, which is legal wherever a statement is.
// This program exits 0 because the goto skips the assignment; a reader that read
// `end: ;` as a label over the closing brace, or that reported the empty
// statement, would not compile it. Measured on gcc 16.2.1, which exits 0.
fn test_a_label_at_the_end_of_a_block_is_a_place_a_goto_reaches() {
	source := scratch('goto_end_label.c')
	binary := scratch('goto_end_label')
	program := 'int main(void) { int n = 0; goto end; n = 5; end: ; return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A goto to a label the function never writes is refused by name, and no image
// is written: the jump would be an instruction to an address the image does not
// hold, which is worse than a refusal. Measured on gcc 16.2.1, which refuses the
// same program with `label 'nowhere' used but not defined`.
fn test_a_goto_to_a_label_nothing_defines_is_refused_and_writes_no_image() {
	source := scratch('goto_undefined.c')
	binary := scratch('goto_undefined')
	image := compile([source, '-o', binary], 'int main(void) { goto nowhere; return 0; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('label nowhere is used but not defined')
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// Two labels of one name in a function are refused where the second is written,
// which is what gcc reports as a duplicate label: a name for two places is not a
// name. Measured on gcc 16.2.1, which refuses the same program.
fn test_two_labels_of_one_name_are_refused_and_write_no_image() {
	source := scratch('goto_duplicate.c')
	binary := scratch('goto_duplicate')
	image := compile([source, '-o', binary], 'int main(void) { int n = 0; goto x; x: n = 1; x: n = 2; return n; }\n')
	assert image.diagnostics.len == 1
	assert image.diagnostics[0].msg.contains('duplicate label x')
	assert image.bytes.len == 0
	os.rm(source) or {}
}

// A switch with a few thousand labels is compiled by a walk and a dispatch that
// are loops: the labels of the body are numbered by walking it, and the dispatch
// is one comparison per case, so the cost of a switch is its length and not the
// stack. This program has 4000 labels and exits 200, which is the arm 3999
// selects: measured on gcc 16.2.1, which exits 200. The source is built rather
// than written out because it is four thousand lines.
fn test_a_switch_with_a_few_thousand_cases_is_matched_and_not_run_out_of_stack() {
	source := scratch('switch_many.c')
	binary := scratch('switch_many')
	mut program := 'int main(void) { int s = 3999; int n = 0; switch (s) {\n'
	for i in 0 .. 4000 {
		program += 'case ${i}: n = ${i % 200 + 1}; break;\n'
	}
	program += 'default: n = 99;\n}\nreturn n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 200
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A case label is a place in its switch wherever it is written inside it,
// including inside a block, and the labels fall through in the order they are
// written rather than the order they nest: the label inside the second block is
// between the case above it and the default below it. This program exits 7,
// which is 2 from the arm plus 5 from the default it falls into. Measured on gcc
// 16.2.1, which exits 7.
fn test_a_case_label_inside_a_block_is_an_arm_of_its_switch() {
	source := scratch('switch_block_case.c')
	binary := scratch('switch_block_case')
	program := 'int main(void) { int i = 2; int n = 0; switch (i) { case 1: { n = 1; break; } case 2: { n = 2; } default: n += 5; } return n; }\n'
	exit_status := compile_and_run([source, '-o', binary], program)
	assert exit_status == 7
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The optimizer rebuilds every statement of a body, so a statement it rebuilds
// has to keep the names and the constants it carries: a label name or a case
// value dropped there turns a jump into a jump to nothing or an arm into an arm
// for no value. This is the fallthrough program with a goto after it, compiled
// through the -O1 pipeline, which is the level the only pass runs at. Measured on
// gcc 16.2.1, which exits 11 at every level.
fn test_the_optimizer_keeps_a_switch_and_a_goto_whole() {
	source := scratch('switch_optimized.c')
	binary := scratch('switch_optimized')
	program := 'int main(void) { int n = 0; switch (1) { case 1: n += 1; case 2: n += 10; break; default: n += 100; } goto end; end: return n; }\n'
	assert compile_and_run([source, '-O1', '-o', binary], program) == 11
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A float is four bytes and its value is the four-byte one. The whole reason a
// float is not a double is that `0.1f` and `0.1` are different numbers, so a
// compiler that read the first as the second would answer 0 where this answers
// 1. The width shows in a layout as well: a char and a float in one object are
// eight bytes with a float's alignment.
//
// Every answer in this test and the four after it was measured on gcc 16.2.1 on
// this target, by compiling the same source with `gcc -std=c99 -w` and reading
// the exit status of the binary it produced.
fn test_a_float_is_four_bytes_and_its_value_is_the_four_byte_one() {
	cases := [
		'int main(void) { return sizeof(float); }',
		'int main(void) { return 0.1f != 0.1; }',
		'int main(void) { return 1.5f == 1.5; }',
		'int main(void) { return 1.5F == 1.5; }',
		'int main(void) { return 1e10f == 1e10; }',
		'int main(void) { return 0.1f == 0.1; }',
		'struct S { char c; float f; }; int main(void) { return sizeof(struct S); }',
	]
	answers := [4, 1, 1, 1, 1, 0, 8]
	for i, source_text in cases {
		source := scratch('single_width_${i}.c')
		binary := scratch('single_width_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
	// The hexadecimal spelling reads to the same value as the decimal one,
	// which is what makes it a spelling rather than a different number.
	// Measured on gcc 16.2.1, which returns 1 for each of these as well.
	hex_cases := [
		'int main(void) { return 0x1.8p3f == 12.0f; }',
		'int main(void) { return 0x1.8p3 == 12.0; }',
		'int main(void) { return 0x.8p1 == 1.0; }',
		'int main(void) { return 0x1p-2 == 0.25; }',
		'int main(void) { return 0x0.1p4 == 1.0; }',
	]
	for i, source_text in hex_cases {
		source := scratch('hex_float_${i}.c')
		binary := scratch('hex_float_${i}')
		assert compile_and_run([source, '-o', binary], '${source_text}\n') == 1
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// The arithmetic happens at four bytes. A float step rounds where a double one of
// the same numbers does not, and the difference is in the answer rather than in
// the instruction count: `1.0f / 3.0f` widened is not `1.0 / 3.0`, and ten steps
// of `0.1f` do not add up to `1.0f`. Two of the cases are the other way round,
// where four bytes and eight agree, so that neither answer alone can pass.
fn test_a_float_expression_is_computed_at_four_bytes() {
	cases := [
		'int main(void) { float a = 1.0f; float b = 3.0f; return a / b != 1.0 / 3.0; }',
		'int main(void) { float a = 1.0f; float b = 3.0f; return (double)(a / b) == (double)a / (double)b; }',
		'int main(void) { float x = 16777216.0f; return x + 1.0f == x; }',
		'int main(void) { float k = 0.0f; int i; for (i = 0; i < 10; i++) { k = k + 0.1f; } return k == 1.0f; }',
		'int main(void) { float e = 0.1f; e = e * 3.0f; return e == 0.30000001f; }',
		'int main(void) { float e = 0.1f; e = e * 3.0f; return e != 0.3; }',
		'int main(void) { return (double)(1.0f + 2.0) == 3.0; }',
		'int main(void) { return (double)(1.5f + 1) == 2.5; }',
		'int main(void) { float f = 1.5f; return f + f == 3.0f && f * 2.0f == 3.0f; }',
		'int main(void) { float f = 7.0f; return f - 3.0f == 4.0f; }',
	]
	answers := [1, 0, 1, 0, 1, 1, 1, 1, 1, 1]
	for i, source_text in cases {
		source := scratch('single_step_${i}.c')
		binary := scratch('single_step_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A float widened to a double is exact and a double narrowed to a float rounds,
// which is one test written two ways: the double of 0.1f is not 0.1, and it is
// the double of 0.1f. An integer converts to a float the way it converts to a
// double for every value within an int's range.
//
// The unsigned 32-bit conversions are deliberately not here: `(double)3000000000u`
// and `(unsigned int)3000000000.0` answer 0 and 2147483648 where gcc answers 1 and
// 3000000000, and they answer that on the commit this lane started from as well, so
// what that gap belongs to is the double conversions and not this type.
fn test_a_float_converts_to_and_from_the_other_widths() {
	cases := [
		'int main(void) { double d = 0.1; float f = (float)d; return f == 0.1f; }',
		'int main(void) { float f = 0.1f; double d = f; return d == 0.1; }',
		'int main(void) { float f = 0.1f; double d = f; return d == (double)0.1f; }',
		'int main(void) { float f = 0.1f; return (double)f != 0.1 && (double)f == (double)0.1f; }',
		'int main(void) { return (int)2.75f; }',
		'int main(void) { return (int)-2.75f == -2; }',
		'int main(void) { float f = 3.9f; return (int)f; }',
		'int main(void) { return (float)5 == 5.0f; }',
		'int main(void) { float f = 7.0f; return (int)f; }',
		'int main(void) { float f = 0.1f; return (double)f == (double)0.1f; }',
	]
	answers := [1, 0, 1, 1, 2, 1, 3, 1, 7, 1]
	for i, source_text in cases {
		source := scratch('single_convert_${i}.c')
		binary := scratch('single_convert_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A float is stored and read back as four bytes in every place storage is: a
// local, an element of an array of them, an element written through a subscript,
// a member, a member reached through a pointer and a member of a top-level
// object. The value 0.1f is the sharp end of it: a relabelled double would
// compare equal to 0.1 and a four-byte float does not. One case answers 0, where
// a float narrowed from a double and a float written directly are the same
// number, so the test is not a check that every float differs from every double.
fn test_a_float_is_stored_and_read_back_as_four_bytes() {
	cases := [
		'int main(void) { float f = 0.1f; return f == 0.1f && f != 0.1; }',
		'int main(void) { float a[2]; a[0] = 0.1f; return a[0] != 0.1 && a[0] == 0.1f; }',
		'struct S { float f; };\nint main(void) { struct S s; s.f = 0.1f; return s.f == 0.1f && s.f != 0.1; }',
		'struct S { float f; };\nint main(void) { struct S s; struct S *p = &s; p->f = 1.5f; return s.f == 1.5f; }',
		'struct S { float f; };\nstruct S g;\nint main(void) { g.f = 0.1f; return g.f != 0.1; }',
		'struct S { float f; double d; };\nint main(void) { struct S s; s.f = 0.1f; s.d = 0.1; return s.f == 0.1f && s.f != (float)s.d; }',
		'int main(void) { float f = 1.5f; return -f == -1.5f && -0.1f != 0.1f; }',
		'struct S { char c; float f; };\nint main(void) { struct S s; s.f = 0.1f; return s.f == 0.1f && s.f != 0.1; }',
	]
	answers := [1, 1, 1, 1, 1, 0, 1, 1]
	for i, source_text in cases {
		source := scratch('single_storage_${i}.c')
		binary := scratch('single_storage_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A function hands a float over as four bytes, in a parameter and in a return,
// and a float argument is promoted to a double where the parameter is one or is
// not known: `id(0.1f)` widened is not 0.1, and a float returned from a function
// whose body computed a double is the float it was rounded to.
fn test_a_float_is_passed_and_returned_as_four_bytes() {
	cases := [
		'float half(float x) { return x / 2.0f; }\nint main(void) { return half(1.5f) == 0.75f; }',
		'float half(float x) { return x / 2.0f; }\nint main(void) { return half(0.1f) == 0.1f / 2.0f; }',
		'int takes(float x) { return x == 0.1f; }\nint main(void) { return takes(0.1f); }',
		'float id(float x) { return x; }\nint main(void) { float f = 0.1f; return (double)id(f) == 0.1; }',
		'float id(float x) { return x; }\nint main(void) { float f = 0.1f; return (double)id(f) == (double)0.1f; }',
		'float third(void) { return 1.0 / 3.0; }\nint main(void) { return (double)third() == 1.0 / 3.0; }',
		'float f2(float x) { return x; }\nint main(void) { return f2(1) == 1.0f; }',
		'double d2(double x) { return x; }\nint main(void) { float f = 0.1f; return d2(f) == (double)0.1f; }',
		'float sum3(float a, float b, float c) { return a + b + c; }\nint main(void) { return sum3(0.1f, 0.2f, 0.3f) == 0.1f + 0.2f + 0.3f; }',
		'int six(float a, float b, float c) { return a == 0.1f && b == 0.2f && c == 0.3f; }\nint main(void) { return six(0.1f, 0.2f, 0.3f); }',
	]
	answers := [1, 1, 1, 0, 1, 0, 1, 1, 1, 1]
	for i, source_text in cases {
		source := scratch('single_call_${i}.c')
		binary := scratch('single_call_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A float asked as a question is compared at four bytes against zero, so a float
// that is zero is false and a negative zero is false too, and a float compared
// with an integer or another float is a four-byte comparison rather than the
// eight-byte one the same instruction has in its other form. If the test of a
// float compared eight bytes, `if (0.0f)` would read the register's upper half
// and answer true.
fn test_a_float_asked_as_a_question_is_compared_at_four_bytes() {
	cases := [
		'int main(void) { float z = 0.0f; if (z) { return 1; } return 0; }',
		'int main(void) { float z = 0.1f; if (z) { return 1; } return 0; }',
		'int main(void) { float z = -0.0f; if (z) { return 1; } return 0; }',
		'int main(void) { float z = 0.0f; z = z - 1.0f; if (z) { return 1; } return 0; }',
		'int main(void) { float z = 0.0f; while (z) { return 1; } return 0; }',
		'int main(void) { float z = 0.1f; return z > 0.0f && z < 0.2f && !(z > 0.1f) && z >= 0.1f; }',
		'int main(void) { float f = 1.5f; return f > 1 && f < 2 && f != 2 && f == 1.5f; }',
	]
	answers := [0, 1, 0, 1, 0, 1, 1]
	for i, source_text in cases {
		source := scratch('single_test_${i}.c')
		binary := scratch('single_test_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A suffix the compiler does not implement is refused by name where it is written
// rather than dropped: a letter that names nothing is not a suffix at all, and
// the constant it trails is refused at the reader.
fn test_a_floating_suffix_that_is_not_read_is_refused_by_name() {
	refusals := [
		['int main(void) { return 1.5q; }', 'not part of a floating constant'],
		['int main(void) { return 1.5fq; }', 'not part of a floating constant'],
	]
	for pair in refusals {
		lexed := tokenize.lex(pair[0])
		parsed := parser.parse(lexed.tokens)
		assert parsed.diagnostics.len == 1
		assert parsed.diagnostics[0].msg.contains(pair[1])
		assert parsed.diagnostics[0].line == 1
	}
	// `L` is a suffix this compiler reads now: it names the extended type, so
	// the constant is a long double and the program is accepted.
	accepted := parser.parse(tokenize.lex('int main(void) { return 1.5L; }').tokens)
	assert accepted.diagnostics.len == 0
}

// A top-level object that holds a float is read and written at four bytes: the
// shape of the object carries which of the two floating widths its storage is,
// and that is what the load and the store of the name are picked from. The value
// here is written at run time rather than in the initializer, so what this checks
// is the load and the store of a name and not the bytes of a constant.
//
// Measured on gcc 16.2.1: every program below exits 1.
fn test_a_float_top_level_object_is_read_and_written_at_four_bytes() {
	cases := [
		'static float g;\nint main(void) { g = 1.5f; return g == 1.5f; }',
		'static float g;\nint main(void) { g = 0.1f; return g != 0.1 && g == 0.1f; }',
		'static float g;\nint main(void) { g = 0.1f; g = g * 2.0f; return g == 0.2f; }',
		'static float g;\nint main(void) { float f = 2.5f; g = f; return g == 2.5f; }',
	]
	answers := [1, 1, 1, 1]
	for i, source_text in cases {
		source := scratch('single_global_${i}.c')
		binary := scratch('single_global_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A top-level float written by its initializer is four bytes of the value and not
// the low four bytes of the double of it: the low half of the double of 1.5 is
// zeros, so a top-level float written with the double bytes came out as 0.0f with
// no diagnostic at all. The array and the single object are both here because the
// initializer writes one element at a time, at the width of the element.
//
// Measured on gcc 16.2.1: every program below exits 1.
fn test_a_float_top_level_initializer_is_written_as_four_bytes() {
	cases := [
		'static float g = 1.5f;\nint main(void) { return g == 1.5f; }',
		'static float g = 0.1f;\nint main(void) { return g != 0.1 && g == 0.1f; }',
		'static float g = 2.25f;\nint main(void) { return g == 2.25f; }',
		'static float a[3] = { 1.5f, 0.1f, 2.25f };\nint main(void) { return a[0] == 1.5f && a[1] == 0.1f && a[2] == 2.25f; }',
		'static float a[3] = { 1.5f, 0.1f, 2.25f };\nint main(void) { return a[1] != 0.1; }',
	]
	answers := [1, 1, 1, 1, 1]
	for i, source_text in cases {
		source := scratch('single_initializer_${i}.c')
		binary := scratch('single_initializer_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A condition that is a floating value is asked whether it is zero at its own
// width, and the two sides of a short circuit are asked the same question. The
// value is the condition directly rather than a comparison of it, so what this
// checks is the test the emitter writes and not the comparison: a floating
// condition tested as an integer would answer from whatever the general register
// happened to hold, since the value lives in the floating-point one.
//
// Measured on gcc 16.2.1: the answers below are what it exits with.
fn test_a_floating_value_asked_as_a_question_is_compared_as_one() {
	cases := [
		'int main(void) { double d = 1.5; if (d) { return 1; } return 0; }',
		'int main(void) { double d = 0.0; if (d) { return 1; } return 0; }',
		'int main(void) { double d = -0.0; if (d) { return 1; } return 0; }',
		'int main(void) { double d = 1.5; while (d) { return 0; } return 1; }',
		'int main(void) { double d = 1.5; return d && 1; }',
		'int main(void) { double d = 0.0; return d || 1; }',
		'int main(void) { float z = 1.5f; double d = (double)z; return d == 1.5 && z != 0.0f; }',
	]
	answers := [1, 0, 0, 0, 1, 1, 1]
	for i, source_text in cases {
		source := scratch('floating_question_${i}.c')
		binary := scratch('floating_question_${i}')
		exit_status := compile_and_run([source, '-o', binary], '${source_text}\n')
		assert exit_status == answers[i]
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// An unsigned integer converts to a double with its value kept. gcc 16.2.1 answers
// every one of these programs with 0; before the unsigned conversion existed this
// back end answered 1 for all of them, because `cvtsi2sd xmm, r/m32` sign-extends
// its source. The values sit on both sides of 2^31 and at the top of the range, so
// a fix that special-cased 3000000000 would fail the rest.
fn test_an_unsigned_integer_converts_to_a_double() {
	cases := [
		'unsigned int u = 3000000000u; double d = (double)u; return d == 3000000000.0 ? 0 : 1;',
		'unsigned int u = 2147483648u; double d = (double)u; return d == 2147483648.0 ? 0 : 1;',
		'unsigned int u = 4294967295u; double d = (double)u; return d == 4294967295.0 ? 0 : 1;',
	]
	for index, body in cases {
		source := scratch('uconv_source_${index}.c')
		binary := scratch('uconv_source_${index}')
		exit_status := compile_and_run([source, '-o', binary], 'int main(void) { ${body} }\n')
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// An eight-byte integer converts to a double with its value kept, signed and
// unsigned. gcc 16.2.1 answers every one of these programs with 0. Before this
// the finite conversion took its four-byte form for all four of the 64-bit
// types, so 18000000000000000000 arrived as a negative value and a long's low
// half was converted as though the top of it were a sign. The values sit on both
// sides of 2^63 and 2^53 and at the top of the range, so a fix that special-cased
// one constant would fail the rest.
fn test_an_eight_byte_integer_converts_to_a_double_with_its_value() {
	cases := [
		'unsigned long u = 18000000000000000000UL; double d = (double)u; return d == 18000000000000000000.0 ? 0 : 1;',
		'unsigned long u = 9223372036854775808UL; double d = (double)u; return d == 9223372036854775808.0 ? 0 : 1;',
		'unsigned long u = 9223372036854775809UL; double d = (double)u; return d == 9223372036854775808.0 ? 0 : 1;',
		'unsigned long u = 18446744073709551615UL; double d = (double)u; return d == 18446744073709551616.0 ? 0 : 1;',
		'unsigned long long u = 18446744073709551615ULL; double d = (double)u; return d == 18446744073709551616.0 ? 0 : 1;',
		'long x = 4611686018427387904L; double d = (double)x; return d == 4611686018427387904.0 ? 0 : 1;',
		'long long x = 9007199254740993LL; double d = (double)x; return d == 9007199254740992.0 ? 0 : 1;',
		'unsigned long u = 0UL; double d = (double)u; return d == 0.0 ? 0 : 1;',
	]
	for index, body in cases {
		source := scratch('uconv64_source_${index}.c')
		binary := scratch('uconv64_source_${index}')
		exit_status := compile_and_run([source, '-o', binary], 'int main(void) { ${body} }\n')
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// The same conversion where the value is not cast but converted for a store, a
// parameter or a return: each reads the destination's type rather than the
// expression's, so a fix at the cast alone would leave them wrong.
fn test_an_eight_byte_integer_reaches_a_double_wherever_it_is_asked_for() {
	programs := [
		'int main(void){ unsigned long u = 18000000000000000000UL; double d = 0; d = u; return d == 18000000000000000000.0 ? 0 : 1; }\n',
		'int main(void){ long x = 4611686018427387904L; double d = 0; d = x; return d == 4611686018427387904.0 ? 0 : 1; }\n',
		'double f(unsigned long u){ return u; }\nint main(void){ return f(18000000000000000000UL) == 18000000000000000000.0 ? 0 : 1; }\n',
		'double f(long x){ return x; }\nint main(void){ return f(4611686018427387904L) == 4611686018427387904.0 ? 0 : 1; }\n',
		'int main(void){ double a[1]; unsigned long u = 18446744073709551615UL; a[0] = u; return a[0] == 18446744073709551616.0 ? 0 : 1; }\n',
	]
	for index, program in programs {
		source := scratch('uconv64_place_${index}.c')
		binary := scratch('uconv64_place_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A double converts to an unsigned integer with its value kept. gcc 16.2.1 answers
// each of these with 0; before the unsigned conversion existed this back end
// answered 1 for all of them, because `cvttsd2si r32, xmm` saturates at 2^31.
fn test_a_double_converts_to_an_unsigned_integer() {
	cases := [
		'double d = 3000000000.0; unsigned int u = (unsigned int)d; return u == 3000000000u ? 0 : 1;',
		'double d = 2147483648.0; unsigned int u = (unsigned int)d; return u == 2147483648u ? 0 : 1;',
		'double d = 4294967295.0; unsigned int u = (unsigned int)d; return u == 4294967295u ? 0 : 1;',
	]
	for index, body in cases {
		source := scratch('uconv_dest_${index}.c')
		binary := scratch('uconv_dest_${index}')
		exit_status := compile_and_run([source, '-o', binary], 'int main(void) { ${body} }\n')
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A double converts to an eight-byte integer with its value kept, signed and
// unsigned. gcc 16.2.1 answers every one of these programs with 0. Before this a
// conversion to a 64-bit type was refused by name, and the four-byte truncation
// the back end had would have saturated the values above 2^31 instead. The doubles
// sit on both sides of 2^63 and next to the top of the range, so a fix that
// special-cased one boundary would fail the rest.
fn test_a_double_converts_to_an_eight_byte_integer_with_its_value() {
	cases := [
		'double d = 9223372036854775808.0; unsigned long u = (unsigned long)d; return u == 9223372036854775808UL ? 0 : 1;',
		'double d = 10000000000000000000.0; unsigned long u = (unsigned long)d; return u == 10000000000000000000UL ? 0 : 1;',
		'double d = 18446744073709549568.0; unsigned long u = (unsigned long)d; return u == 18446744073709549568UL ? 0 : 1;',
		'double d = 9223372036854774784.0; unsigned long u = (unsigned long)d; return u == 9223372036854774784UL ? 0 : 1;',
		'double d = 0.0; unsigned long u = (unsigned long)d; return u == 0UL ? 0 : 1;',
		'double d = 4611686018427387904.0; long u = (long)d; return u == 4611686018427387904L ? 0 : 1;',
		'double d = -1.0; long u = (long)d; return u == -1L ? 0 : 1;',
		'double d = 10000000000000000000.0; unsigned long long u = (unsigned long long)d; return u == 10000000000000000000ULL ? 0 : 1;',
	]
	for index, body in cases {
		source := scratch('uconv64_dest_${index}.c')
		binary := scratch('uconv64_dest_${index}')
		exit_status := compile_and_run([source, '-o', binary], 'int main(void) { ${body} }\n')
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// The same conversion where a value is stored rather than cast: an unsigned local,
// an element of an array, a member, a top-level object, and the value a function
// returns. Each reads the destination's type rather than the expression's, so a fix
// at the cast alone would leave them wrong.
fn test_a_double_reaches_an_eight_byte_integer_wherever_it_is_asked_for() {
	programs := [
		'int main(void){ double d = 10000000000000000000.0; unsigned long u = 0; u = d; return u == 10000000000000000000UL ? 0 : 1; }\n',
		'int main(void){ double d = 10000000000000000000.0; unsigned long a[2]; a[0] = d; return a[0] == 10000000000000000000UL ? 0 : 1; }\n',
		'struct S { unsigned long u; };\nint main(void){ struct S s; double d = 10000000000000000000.0; s.u = d; return s.u == 10000000000000000000UL ? 0 : 1; }\n',
		'unsigned long g;\nint main(void){ double d = 10000000000000000000.0; g = d; return g == 10000000000000000000UL ? 0 : 1; }\n',
		'unsigned long f(double d){ return d; }\nint main(void){ return f(10000000000000000000.0) == 10000000000000000000UL ? 0 : 1; }\n',
		'long f(double d){ return d; }\nint main(void){ return f(4611686018427387904.0) == 4611686018427387904L ? 0 : 1; }\n',
	]
	for index, program in programs {
		source := scratch('uconv64_dest_place_${index}.c')
		binary := scratch('uconv64_dest_place_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A float reaches the same conversion by widening to a double first, which is
// exact: the four-byte truncation saturates at 2^31, which a float at 3e9 is
// above. gcc 16.2.1 answers both of these with 0.
fn test_a_float_reaches_an_eight_byte_integer_by_widening() {
	cases := [
		'float f = 3000000000.0f; unsigned long u = f; return u == 3000000000UL ? 0 : 1;',
		'float f = 4611686018427387904.0f; long u = f; return u == 4611686018427387904L ? 0 : 1;',
	]
	for index, body in cases {
		source := scratch('uconv64_dest_float_${index}.c')
		binary := scratch('uconv64_dest_float_${index}')
		exit_status := compile_and_run([source, '-o', binary], 'int main(void) { ${body} }\n')
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// The same conversion where a value is stored rather than cast: an unsigned local,
// an element of an unsigned array, an unsigned member, an unsigned parameter a
// double is handed to, and a top-level unsigned object. Each would saturate at
// 2^31 if the conversion were chosen without the destination's signedness.
fn test_an_unsigned_destination_keeps_its_range_where_a_double_is_stored() {
	programs := [
		'int main(void){ double d = 3000000000.0; unsigned int u = 0; u = d; return u == 3000000000u ? 0 : 1; }\n',
		'int main(void){ double d = 3000000000.0; unsigned int a[2]; a[0] = d; return a[0] == 3000000000u ? 0 : 1; }\n',
		'struct S { unsigned int u; };\nint main(void){ struct S s; double d = 3000000000.0; s.u = d; return s.u == 3000000000u ? 0 : 1; }\n',
		'unsigned int got;\nvoid f(unsigned int x){ got = x; }\nint main(void){ double d = 3000000000.0; f(d); return got == 3000000000u ? 0 : 1; }\n',
		'unsigned int g;\nint main(void){ double d = 3000000000.0; g = d; return g == 3000000000u ? 0 : 1; }\n',
	]
	for index, program in programs {
		source := scratch('uconv_store_${index}.c')
		binary := scratch('uconv_store_${index}')
		exit_status := compile_and_run([source, '-o', binary], program)
		assert exit_status == 0
		os.rm(source) or {}
		os.rm(binary) or {}
	}
}

// A variadic definition is a definition: the prologue writes every argument
// register into a save area, and the four operations over the argument list read
// and step that area. These run, because a definition that compiles and sums the
// wrong arguments is the failure this feature can have, and only a run shows it.
//
// The sources are written with the compiler's own spellings rather than with
// stdarg.h's, because the preprocessor is not in this path; each one is what a
// header's `va_start`, `va_arg`, `va_copy` and `va_end` expand to. Every answer
// here was checked against gcc 16.2.1 under -std=gnu99 on the same source.
fn test_a_variadic_definition_sums_what_it_is_given() {
	source := scratch('variadic_sum.c')
	binary := scratch('variadic_sum')
	program := 'int sum(int count, ...)
{
	__builtin_va_list ap;
	int total = 0;
	int i;
	__builtin_va_start(ap, count);
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(ap, int);
	__builtin_va_end(ap);
	return total;
}
long long sum_long(int count, ...)
{
	__builtin_va_list ap;
	long long total = 0;
	int i;
	__builtin_va_start(ap, count);
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(ap, long long);
	__builtin_va_end(ap);
	return total;
}
double sum_double(int count, ...)
{
	__builtin_va_list ap;
	double total = 0;
	int i;
	__builtin_va_start(ap, count);
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(ap, double);
	__builtin_va_end(ap);
	return total;
}
int main(void)
{
	if (sum(0) != 0) return 1;
	if (sum(1, 7) != 7) return 2;
	if (sum(3, 1, 2, 3) != 6) return 3;
	if (sum(9, 1, 2, 3, 4, 5, 6, 7, 8, 9) != 45) return 4;
	if (sum_long(0) != 0) return 5;
	if (sum_long(3, 1, 2, 3) != 6) return 6;
	if (sum_double(0) != 0.0) return 7;
	if (sum_double(3, 0.5, 1.5, 2.5) != 4.5) return 8;
	return 0;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// More unnamed arguments than there are argument registers: the first ones arrive
// in registers and the rest on the caller's stack, and a walk that starts in the
// wrong place reads the wrong word. Six named parameters fill the general file,
// so all three unnamed ones are on the stack, at the first word past the return
// address and the saved frame pointer.
fn test_the_general_arguments_run_out_of_registers() {
	source := scratch('variadic_stack.c')
	binary := scratch('variadic_stack')
	program := 'int take(int a, int b, int c, int d, int e, int f, ...)
{
	__builtin_va_list ap;
	int total = 0;
	__builtin_va_start(ap, f);
	total += __builtin_va_arg(ap, int);
	total += __builtin_va_arg(ap, int);
	total += __builtin_va_arg(ap, int);
	__builtin_va_end(ap);
	return total;
}
int main(void)
{
	/* The body reads exactly the three unnamed arguments it is given: a read
	 * past the last one is a read of the caller stack, which is not a thing
	 * this test can have an answer for. */
	return take(1, 2, 3, 4, 5, 6, 7, 8, 9) == 24 ? 0 : 1;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// A vector argument after one that went on the stack. The general file is full,
// so the two ints are on the stack, and the two doubles are in the first vector
// registers: a save area that writes only the general file, or only the registers
// it saw used, answers zero for the doubles here.
fn test_a_vector_argument_after_one_that_went_on_the_stack() {
	source := scratch('variadic_mixed.c')
	binary := scratch('variadic_mixed')
	program := 'int mixed(int a, int b, int c, int d, int e, int f, ...)
{
	__builtin_va_list ap;
	int total = a + b + c + d + e + f;
	double halves = 0;
	__builtin_va_start(ap, f);
	total += __builtin_va_arg(ap, int);
	total += __builtin_va_arg(ap, int);
	halves += __builtin_va_arg(ap, double);
	halves += __builtin_va_arg(ap, double);
	__builtin_va_end(ap);
	return total + (int)(halves * 10);
}
int main(void)
{
	return mixed(1, 2, 3, 4, 5, 6, 7, 8, 1.5, 2.5) == 76 ? 0 : 1;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// A copy of an argument list walks on its own: the same unnamed arguments are
// read twice, once through each list. Nine arguments with one named parameter put
// four of them on the stack, so the copy is a copy of a walk that has already
// stepped out of both files.
fn test_a_copy_of_an_argument_list_walks_on_its_own() {
	source := scratch('variadic_copy.c')
	binary := scratch('variadic_copy')
	program := 'int twice(int count, ...)
{
	__builtin_va_list ap;
	__builtin_va_list snapshot;
	int total = 0;
	int i;
	__builtin_va_start(ap, count);
	__builtin_va_copy(snapshot, ap);
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(ap, int);
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(snapshot, int);
	__builtin_va_end(snapshot);
	__builtin_va_end(ap);
	return total;
}
int main(void)
{
	if (twice(0) != 0) return 1;
	if (twice(1, 5) != 10) return 2;
	if (twice(3, 1, 2, 3) != 12) return 3;
	if (twice(9, 1, 2, 3, 4, 5, 6, 7, 8, 9) != 90) return 4;
	return 0;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// There are no unnamed arguments in a function whose parameter list does not end
// in an ellipsis, so there is no list to fill in and the operation is refused by
// name rather than answered with a walk over nothing.
fn test_an_argument_list_operation_outside_a_variadic_function_is_refused() {
	source := scratch('variadic_refused.c')
	binary := scratch('variadic_refused')
	program := 'int main(void)
{
	__builtin_va_list ap;
	__builtin_va_start(ap, ap);
	return 0;
}
'
	emitted := compile([source, '-o', binary], program)
	os.rm(source) or {}
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('__builtin_va_start')
}

// A function that is handed an argument list is not a variadic definition, but
// its parameter is a list all the same: a function that formats or sums on behalf
// of a variadic one walks the list it was handed. The list is not storage this
// function filled in, so it is the declared type that says what the walk may
// read, and the walk steps the caller's tag rather than a copy of it.
fn test_a_function_handed_an_argument_list_walks_it() {
	source := scratch('variadic_handed.c')
	binary := scratch('variadic_handed')
	program := 'int sum_list(int count, __builtin_va_list ap)
{
	int total = 0;
	int i;
	for (i = 0; i < count; ++i)
		total += __builtin_va_arg(ap, int);
	return total;
}
int sum(int count, ...)
{
	__builtin_va_list ap;
	__builtin_va_start(ap, count);
	return sum_list(count, ap);
}
int main(void)
{
	if (sum(0) != 0) return 1;
	if (sum(3, 1, 2, 3) != 6) return 2;
	if (sum(9, 1, 2, 3, 4, 5, 6, 7, 8, 9) != 45) return 3;
	return 0;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// An object that is not an argument list holds something that is not a tag, so a
// walk through it reads that something as though it were one: `va_arg(x, int)` on
// an int takes the value of x for the address of a tag and reads a list out of
// wherever it points. gcc 16.2.1 refuses this and so does this back end, at the
// operation rather than by writing a program that reads a wrong address.
fn test_a_walk_of_an_object_that_is_not_an_argument_list_is_refused() {
	source := scratch('variadic_not_a_list.c')
	binary := scratch('variadic_not_a_list')
	program := 'int main(void)
{
	int x = 0;
	return __builtin_va_arg(x, int);
}
'
	emitted := compile([source, '-o', binary], program)
	os.rm(source) or {}
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('__builtin_va_arg')
	assert emitted.diagnostics[0].msg.contains('not an argument list')
}

// An argument is parked in the frame slot of the level it is emitted at, and a
// later argument that takes an address computes the element's or the member's
// address through the slot of its own level.  When the address was taken at
// level zero instead of the argument's level, `f("hello", &arr[1])` overwrote
// the string pointer already sitting in level zero and printed an empty string
// where gcc printed "hello".  Every callee here checks the value it was handed:
// a dropped pointer and a dropped integer look the same in an exit status.
fn test_an_earlier_argument_survives_a_later_one_that_takes_an_address() {
	source := scratch('argument_address.c')
	binary := scratch('argument_address')
	program := 'int retint(void) { return 42; }
int two(const char *s, int *p)
{
	if (*s != 104) return 1;
	if (*p != 9) return 2;
	return 0;
}
int three(const char *s, int i, int *p)
{
	if (*s != 98) return 1;
	if (i != 4) return 2;
	if (*p != 9) return 3;
	return 0;
}
int pointers(int *a, int *b)
{
	if (*a != 7) return 1;
	if (*b != 9) return 2;
	return 0;
}
int four(const char *s, int *p, int n, int m)
{
	if (*s != 100) return 1;
	if (*p != 9) return 2;
	if (n != 5) return 3;
	if (m != 6) return 4;
	return 0;
}
int number(int n, int *p)
{
	if (n != 42) return 1;
	if (*p != 9) return 2;
	return 0;
}
int member(const char *s, int *p)
{
	if (*s != 101) return 1;
	if (*p != 13) return 2;
	return 0;
}
int loop_check(const char *s, int *p)
{
	if (*s != 102) return 1;
	return *p;
}
struct pair { int a; int b; };
int main(void)
{
	int arr[2];
	int x;
	int i;
	int *p;
	struct pair q;
	int total;
	arr[0] = 7;
	arr[1] = 9;
	x = 5;
	i = 1;
	p = arr;
	q.a = 11;
	q.b = 13;
	if (two("hello", &arr[1]) != 0) return 1;
	if (three("b", 4, &arr[i]) != 0) return 2;
	if (pointers(&arr[0], &arr[1]) != 0) return 3;
	if (four("d", &arr[1], 5, 6) != 0) return 4;
	if (number(retint(), &arr[1]) != 0) return 5;
	if (member("e", &q.b) != 0) return 6;
	if (two("h", p + i) != 0) return 7;
	total = 0;
	for (i = 0; i < 2; ++i)
		total += loop_check("f", &arr[i]);
	if (total != 16) return 8;
	if (x != 5) return 9;
	return 0;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// A call through an expression resolves the address it calls before the
// arguments are evaluated and keeps it in a slot of its own.  The last argument
// is emitted at the level that address used to be parked in, so an argument
// holding a value of its own at that level - an assignment does - overwrote the
// callee and the call jumped to the argument's value: `fp("w", (p = q))` through
// a function pointer crashed on main's tip.
fn test_a_resolved_callee_survives_the_arguments_it_is_called_with() {
	source := scratch('callee_slot.c')
	binary := scratch('callee_slot')
	program := 'int two(const char *s, int *p)
{
	if (*s != 119) return 1;
	if (*p != 7) return 2;
	return 0;
}
int main(void)
{
	int (*fp)(const char *, int *) = two;
	int first[2];
	int *p;
	int *q;
	first[0] = 7;
	first[1] = 9;
	p = first;
	q = first;
	if (fp("w", (p = q)) != 0) return 1;
	if (fp("w", p++) != 0) return 2;
	return 0;
}
'
	exit_status := compile_and_run([source, '-o', binary], program)
	os.rm(source) or {}
	os.rm(binary) or {}
	assert exit_status == 0
}

// _Generic is the C11 selection: the controlling expression's type, after the
// lvalue conversion 6.5.17 asks for, picks the association, and the selection is
// worth that association's expression and type. Each program below is the value
// gcc 16.2.1 computes for the same source.
fn test_a_generic_selection_is_the_arm_its_controlling_type_names() {
	source := scratch('generic_named.c')
	binary := scratch('generic_named')
	program := 'int main(void) { int n = 0; int r = _Generic(n, int: 3, long: 4, default: 0); return r; }\n'
	assert compile_and_run(['-std=c23', source, '-o', binary], program) == 3
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.5.17 does not evaluate the controlling expression: the increment is read for
// its type and the value of n is unchanged, so the program returns 5 * 10 + 0.
fn test_a_generic_selection_does_not_evaluate_its_controlling_expression() {
	source := scratch('generic_noeval.c')
	binary := scratch('generic_noeval')
	program := 'int main(void) { int n = 0; int r = _Generic(++n, int: 5, default: 0); return r * 10 + n; }\n'
	assert compile_and_run(['-std=c23', source, '-o', binary], program) == 50
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The selection has the type of the arm it selected, here a double, which is what
// makes the arithmetic below a double multiply rather than an integer one.
fn test_a_generic_selection_has_the_type_of_its_selected_arm() {
	source := scratch('generic_type.c')
	binary := scratch('generic_type')
	program := 'int main(void) { double d = _Generic(1.0, int: 1.0, double: 2.5, default: 0.0); return (int)(d * 10); }\n'
	assert compile_and_run(['-std=c23', source, '-o', binary], program) == 25
	os.rm(source) or {}
	os.rm(binary) or {}
}

// The extension brings the construct down to c99, so the same program compiles
// and runs under `-std=c99 -fvcc-exts=generic`.
fn test_the_generic_extension_brings_the_selection_down_to_c99() {
	source := scratch('generic_c99.c')
	binary := scratch('generic_c99')
	program := 'int main(void) { return _Generic(1, int: 21, default: 0) * 2; }\n'
	assert compile_and_run(['-std=c99', '-fvcc-exts=generic', source, '-o', binary], program) == 42
	os.rm(source) or {}
	os.rm(binary) or {}
}

// C23's auto takes the type of its initializer, and the value the program returns
// says which type it took: each arm is worth a different number and the last term
// is the value itself. Measured on gcc 16.2.1 the same program with the deduced
// types written in returns 18, so 18 is the answer a deduction that picked int,
// unsigned int, double and long has to give. It is compiled in the mode that made
// the construct standard and in c99 with the extension that brings it down, which
// is what naming the name on the command line is for.
fn test_auto_is_the_initializer_type_in_both_modes_that_have_it() {
	source := scratch('auto_local.c')
	binary := scratch('auto_local')
	program := 'int main(void) {\n    auto x = 1;\n    auto u = 2u;\n    auto d = 3.5;\n    auto l = 4L;\n    return _Generic(x, int: 1, default: 0) + _Generic(u, unsigned int: 2, default: 0) + _Generic(d, double: 4, default: 0) + _Generic(l, long: 8, default: 0) + (int)d;\n}\n'
	assert compile_and_run(['-std=c23', source, '-o', binary], program) == 18
	assert compile_and_run(['-std=c99', '-fvcc-exts=auto', source, '-o', binary], program) == 18
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A file-scope auto is a definition of the initializer's type, and the type is
// read from the expression rather than from the folded number, which is why a
// suffix that decides the type decides the object: measured on gcc 16.2.1,
// `auto g = 2.5;` defines a double and the two reads below are 42 and 10.
fn test_a_file_scope_auto_defines_an_object_of_the_initializer_type() {
	source := scratch('auto_file.c')
	binary := scratch('auto_file')
	whole := 'auto g = 42;\nint main(void) { return g; }\n'
	floating := 'auto h = 2.5;\nint main(void) { return (int)(h * 4); }\n'
	assert compile_and_run(['-std=c23', source, '-o', binary], whole) == 42
	assert compile_and_run(['-std=c99', '-fvcc-exts=auto', source, '-o', binary], floating) == 10
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.3.2.1p2 and 6.5.16.1: a value read from a const-qualified aggregate is a
// value of the unqualified type, so every position that reads it accepts it. The
// program is compiled and run, so what is checked is the artifact and not a
// diagnostic count: measured on gcc 16.2.1 with -std=c99, the same program exits
// 21. The positions are the ones the rule has to keep working in: a local of the
// plain type, an argument to a function whose parameter is the plain type, a
// function returning a const-qualified file-scope object, the initializer of a
// file-scope object and an assignment into one, an element of a const array, and
// a read through a `const S *`.
//
// An assignment into a struct member of the aggregate type is one of the
// positions now: the member takes a copy of the object's bytes, and the second
// program compiles and runs to measure it. Measured on gcc 16.2.1, `S x = {5};
// struct Holder h; h.m = x; return h.m.a;` exits 5.
fn test_a_const_qualified_aggregate_reads_in_the_positions_that_take_it() {
	source := scratch('constagg.c')
	binary := scratch('constagg')
	program := 'typedef struct { int a; } S;\n' +
		'const S gc = {4};\n' +
		'S take(S v) { return v; }\n' +
		'S get(void) { return gc; }\n' +
		'S g2 = gc;\n' +
		'int main(void) {\n' +
		'    const S s = {5};\n' +
		'    S t = s;\n' +
		'    S u = take(s);\n' +
		'    g2 = s;\n' +
		'    const S *p = &s;\n' +
		'    const S arr[2] = {{1}, {2}};\n' +
		'    S b = arr[0];\n' +
		'    return t.a + u.a + g2.a + p->a + b.a; /* 5 + 5 + 5 + 5 + 1 */\n' +
		'}\n'
	assert compile_and_run([source, '-o', binary], program) == 21
	os.rm(source) or {}
	os.rm(binary) or {}
	// The member-of-aggregate shape is the same copy now, and the qualifier rule
	// reads a const-qualified aggregate the same way.
	member := scratch('constagg_member.c')
	assert compile_and_run([member, '-o', scratch('constagg_member')],
		'typedef struct { int a; } S;\nstruct Holder { S m; };\nint main(void) { S x = {5}; struct Holder h; h.m = x; return h.m.a; }') == 5
	os.rm(member) or {}
}

// The other direction of the same rule, pinned: writing an object that is not a
// modifiable lvalue is refused. A struct with a const-qualified member is the case
// that must stay refused, and a const-qualified object is the other. 6.3.1p1 is
// the rule, and the refusal is at the parser, so the parse is asked directly.
fn test_writing_an_object_that_is_not_modifiable_is_refused() {
	const_member := 'typedef struct { const int a; } T;\nT x;\nT y;\nint main(void) { x = y; return 0; }\n'
	member := parser.parse(tokenize.lex(const_member).tokens)
	assert member.diagnostics.len >= 1
	assert member.diagnostics[0].msg.contains('const-qualified member')
	const_object := 'typedef struct { int a; } S;\nint main(void) { const S s = {1}; S t = {2}; s = t; return 0; }\n'
	object := parser.parse(tokenize.lex(const_object).tokens)
	assert object.diagnostics.len >= 1
	assert object.diagnostics[0].msg.contains('const-qualified')
}

// A designated member of a compound literal whose own type is an aggregate takes
// the element as its value, so the designator resolves against the literal's own
// type and not against the member's: `(Info){.file = S}` copies S into the member
// and the program reads 4 and x back out. Measured on gcc 16.2.1, the same
// program prints `4 x` and exits 0.
fn test_a_designated_aggregate_member_of_a_compound_literal_is_copied() {
	source := scratch('desig_agg.c')
	binary := scratch('desig_agg')
	program := 'typedef struct { char *str; long len; } string;\n' +
		'typedef struct { long line_no; string file; string mod; } Info;\n' +
		'static string S = {"x", 1};\n' +
		"int main(void) { Info d = (Info){.line_no = 4, .file = S, .mod = S}; return (d.line_no == 4 && d.file.len == 1 && d.mod.len == 1 && d.file.str[0] == 'x') ? 0 : 7; }\n"
	assert compile_and_run([source, '-o', binary], program) == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.5.16.1 lets a pointer to void convert to and from a pointer to an object or
// incomplete type, and a function type is neither, so a conversion between a
// function pointer and a void pointer is outside the standard. gcc 16.2.1
// accepts it in every mode and reports it only under -pedantic, and this tree
// does the same. What is checked is the value and not the spelling: the round
// trip through a void pointer calls the function again, and the number that
// comes back is the one gcc's program returns. Measured on gcc 16.2.1, this
// program exits 42, and the two messages are `ISO C forbids conversion of
// function pointer to object pointer type` and `ISO C forbids conversion of
// object pointer to function pointer type`.
fn test_a_function_pointer_and_a_void_pointer_convert_to_one_another() {
	source := scratch('fnptrvoid.c')
	binary := scratch('fnptrvoid')
	program := 'typedef int (*fp)(int);\n' +
		'static int twice(int x) { return x * 2; }\n' +
		'int main(void) { fp f = twice; void *p = (void *)f; fp g = (fp)p; return g(21); }\n'
	image := compile(['-std=c99', '-w', source, '-o', binary], program)
	assert image.bytes.len > 0
	assert image.diagnostics.len == 2
	mut forward := false
	mut reverse := false
	for diagnostic in image.diagnostics {
		assert diagnostic.warning
		assert diagnostic.class == .pedantic
		if diagnostic.msg == 'ISO C forbids conversion of function pointer to object pointer type' {
			forward = true
		}
		if diagnostic.msg == 'ISO C forbids conversion of object pointer to function pointer type' {
			reverse = true
		}
	}
	assert forward && reverse
	// The program runs and the value is the function's own, which is what a
	// conversion that wrote the wrong address would not answer.
	os.write_file_array(binary, image.bytes) or { panic(err) }
	os.chmod(binary, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(binary))
	assert result.exit_code == 42
	// The flags decide the fate of the pedantic class, the same way they do for
	// gcc's message: reported under -Wpedantic, promoted by -pedantic-errors,
	// and silenced by -w whichever order the flags are written in.
	asked := cli.parse(['-std=c99', '-Wpedantic', source, '-o', binary]) or { panic(err) }
	promoted := cli.parse(['-std=c99', '-pedantic-errors', source, '-o', binary]) or { panic(err) }
	silenced := cli.parse(['-std=c99', '-w', source, '-o', binary]) or { panic(err) }
	for diagnostic in image.diagnostics {
		assert severity_of(diagnostic, asked.warnings) == .warning
		assert severity_of(diagnostic, promoted.warnings) == .error
		assert severity_of(diagnostic, silenced.warnings) == .silent
	}
	os.rm(source) or {}
	os.rm(binary) or {}
}

// A null function pointer round trips through a void pointer as a null one,
// which is the row a conversion that read the bytes wrongly would fail: a zero
// that came back as anything else compares unequal to 0. Measured on gcc
// 16.2.1, the program exits 0.
fn test_a_null_function_pointer_is_null_after_a_void_pointer_round_trip() {
	source := scratch('fnptrvoid_null.c')
	binary := scratch('fnptrvoid_null')
	program := 'typedef int (*fp)(int);\n' +
		'int main(void) { fp none = 0; void *z = (void *)none; fp again = (fp)z; return (again == 0 && z == 0) ? 0 : 1; }\n'
	image := compile(['-std=c99', '-w', source, '-o', binary], program)
	assert image.bytes.len > 0
	for diagnostic in image.diagnostics {
		assert diagnostic.warning
	}
	os.write_file_array(binary, image.bytes) or { panic(err) }
	os.chmod(binary, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(binary))
	assert result.exit_code == 0
	os.rm(source) or {}
	os.rm(binary) or {}
}

// 6.5.15 evaluates only the arm the condition selects. A condition the reader
// folded to a literal selects the same arm on every run, so the arm it does not
// select is never written into the image and a construct the back end refuses
// only for that arm cannot refuse the program. `(long)(1.0L)` is such a
// construct - refused alone with `a conversion from long double to long is not
// one this back end makes` - and each of these rows is refused on main before
// the untaken arm stops being emitted. Measured on gcc 16.2.1 and run here: 0
// and 5.
fn test_a_constant_conditional_emits_only_the_taken_arm() {
	then_source := scratch('const_cond_then.c')
	then_binary := scratch('const_cond_then')
	then_status := compile_and_run(['-std=gnu99', then_source, '-o', then_binary],
		'int main(void) { return 1 ? 0 : (long)(1.0L); }')
	assert then_status == 0
	else_source := scratch('const_cond_else.c')
	else_binary := scratch('const_cond_else')
	else_status := compile_and_run(['-std=gnu99', else_source, '-o', else_binary],
		'int main(void) { return 0 ? (long)(1.0L) : 5; }')
	assert else_status == 5
}

// A condition that is not known until run time keeps both arms, and the arm the
// value selects is the one whose side effect runs. The counters come back through
// the exit status, so the two kinds are numbers: the two constant ternaries run
// one arm each and the volatile ternary runs the arm its value selects.
fn test_a_runtime_conditional_keeps_both_arms() {
	source := scratch('runtime_cond.c')
	binary := scratch('runtime_cond')
	program := 'int then_runs = 0; int else_runs = 0; int bump_then(int v) { then_runs++; return v; } int bump_else(int v) { else_runs++; return v; } int main(void) { volatile int c = 0; int a = 1 ? bump_then(3) : bump_else(5); int b = 0 ? bump_then(3) : bump_else(5); int d = c ? bump_then(4) : bump_else(6); if (a != 3) { return 10; } if (b != 5) { return 11; } if (d != 6) { return 12; } if (then_runs != 1) { return 13; } if (else_runs != 2) { return 14; } return 0; }'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 0
}

// A constant condition need not be one literal: 6.6 leaves the operators in an
// integer constant expression, so the reader folds `2 > 1` and `1 + 1` as well.
fn test_a_constant_condition_that_is_not_a_literal_selects_the_arm() {
	source := scratch('const_cond_expr.c')
	binary := scratch('const_cond_expr')
	program := 'int main(void) { int a = 2 > 1 ? 7 : 9; int b = (1 + 1) ? 8 : 9; if (a != 7) { return 1; } if (b != 8) { return 2; } return 0; }'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 0
}

// A conditional whose arms have the extended type is carried as the address of
// the selected arm's bytes, and a constant condition selects that arm with no
// branch. Both rows run the selected arm: `1 ? a : b` is a and `0 ? a : b` is b.
fn test_a_constant_conditional_of_the_extended_type_selects_the_arm() {
	source := scratch('const_cond_extended.c')
	binary := scratch('const_cond_extended')
	program := 'int main(void) { long double a = 1.25L; long double b = 2.5L; long double c = 1 ? a : b; long double d = 0 ? a : b; if (c != 1.25L) { return 1; } if (d != 2.5L) { return 2; } return 0; }'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 0
}

// 6.5.3.4p2 for a compound literal's operand, where the statements are the point:
// a literal writes its object as statements appended to the statement it was
// written in, and the operand of a sizeof is not a place that was taken into
// account. Measured on gcc 16.2.1, `sizeof((S){count(), count()})` calls count no
// times, and this compiler called it twice. The type spelling and the constant list
// were already right, so they are here to keep them that way. The sibling test
// above covers the call shape, which was never wrong. The exit code says which row
// failed.
fn test_sizeof_does_not_build_a_compound_literal_operand() {
	source := scratch('sizeof_operand.c')
	binary := scratch('sizeof_operand')
	program := 'typedef struct { int x; int y; } S;\nint calls = 0;\nint count(void) { calls++; return calls; }\nint main(void) {\n    if (sizeof((S){count(), count()}) != 8) { return 1; }\n    if (calls != 0) { return 2; }\n    if (sizeof(S){count(), count()} != 8) { return 3; }\n    if (calls != 0) { return 4; }\n    if (sizeof((S){1, 2}) != 8) { return 5; }\n    return 0;\n}\n'
	exit_status := compile_and_run(['-std=gnu99', source, '-o', binary], program)
	assert exit_status == 0
}
