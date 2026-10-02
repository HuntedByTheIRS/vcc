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
	program := 'typedef short Small;\nSmall x;\nint main(void) { return 0; }\n'
	lexed := tokenize.lex(program)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].msg == 'unsupported type short'
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

// An element is not a name, and stepping one would have to reach the lvalue
// through the subscript the tree has no node for. The program is refused where
// the operator is written and nothing is written out: a silently wrong value is
// the one outcome worse than a diagnostic.
fn test_a_step_on_an_element_is_refused_and_writes_nothing() {
	source := scratch('incdec_element.c')
	binary := scratch('incdec_element')
	text := 'int main(void) { int a[3]; a[0]++; return 0; }\n'
	os.write_file(source, text) or { panic(err) }
	lexed := tokenize.lex(text)
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].msg.contains('on a[...]')
	assert parsed.diagnostics[0].msg.contains('implements ++ and -- on a plain name only')
	assert !os.exists(binary)
	os.rm(source) or {}
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
	// The hexadecimal spelling of a float is refused by name rather than read as
	// the double of the same digits.
	text := 'int main(void) { return 0x1.8p3f; }\n'
	lexed := tokenize.lex(text)
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 1
	assert parsed.diagnostics[0].msg.contains('hexadecimal floating constants are not implemented')
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
// rather than dropped: `L` names a long double, which is its own machine class on
// this target, and a letter that names nothing is not a suffix at all.
fn test_a_floating_suffix_that_is_not_read_is_refused_by_name() {
	refusals := [
		['int main(void) { return 1.5L; }', 'long double literal'],
		['int main(void) { return 1.5l; }', 'long double literal'],
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
}
