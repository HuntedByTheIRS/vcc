module codegen

import ast
import os
import parser
import time
import tokenize

// A statement-level GNU asm has two shapes here that are not the same: the
// `"memory"` barrier, which does nothing the compiler can see and is emitted as
// nothing, and an instruction body, which is refused by name with its text.
// Each test below reads its shape through the parser and then runs the emitter,
// because the decision belongs to the emitter and a parse that only produced a
// node would not show it.
//
// These helpers are the two codegen_test.v has, defined again because V compiles
// each `_test.v` file on its own.

fn asm_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

fn asm_run(image []u8) int {
	path := os.join_path(os.temp_dir(), 'vcc_asm_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result.exit_code
}

// test_the_memory_barrier_is_read_and_emitted_as_nothing reads the barrier V's
// generated C writes for `cpu_relax`. The tree carries a statement with no text
// and the memory clobber, and the program around it runs to the value it
// computed.
fn test_the_memory_barrier_is_read_and_emitted_as_nothing() {
	unit := asm_unit('int f(void) {\n\t__asm__ __volatile__("" ::: "memory");\n\treturn 41;\n}\nint main(void) { return f() + 1; }')
	assert unit.decls[0].body[0].kind == .asm_stmt
	assert unit.decls[0].body[0].asm_text() == ''
	assert unit.decls[0].body[0].asm_spelling() == '""'
	assert unit.decls[0].body[0].asm_clobbers() == ['memory']
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	assert asm_run(emitted.bytes) == 42
}

// test_an_asm_instruction_body_is_refused_by_name_with_its_text reads the `div`
// shape out of V's generated C, one output and one input, and checks that the
// emitter refuses it with the instruction text and its location rather than
// emitting nothing for it. Emitting nothing would be a quotient the program
// asked for and did not get.
fn test_an_asm_instruction_body_is_refused_by_name_with_its_text() {
	unit := asm_unit('int main(void) {\n\tint q = 1;\n\t__asm__ ("div %[y]" : [q] "=a" (q) : [y] "r" (q));\n\treturn q;\n}')
	assert unit.decls[0].body[1].kind == .asm_stmt
	assert unit.decls[0].body[1].asm_text() == 'div %[y]'
	assert unit.decls[0].body[1].asm_outputs() == 1
	assert unit.decls[0].body[1].asm_inputs() == 1
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 1
	assert !emitted.diagnostics[0].warning
	assert emitted.diagnostics[0].line == 3
	assert emitted.diagnostics[0].msg.contains('div %[y]')
	assert emitted.bytes.len == 0
}

// test_adjacent_string_literals_join_into_one_instruction_text reads the
// `mul_add` shape, whose instruction is written as adjacent literals, and checks
// that they are one text. The refusal names the whole of it, which is what tells
// a reader what the statement asked for.
fn test_adjacent_string_literals_join_into_one_instruction_text() {
	unit := asm_unit('int main(void) {\n\tint lo = 1;\n\t__asm__ ("mulq %%rdx\\n\\t" "addq %[z], %%rax\\n\\t" : [lo] "=a" (lo) : [z] "r" (lo));\n\treturn lo;\n}')
	assert unit.decls[0].body[1].kind == .asm_stmt
	assert unit.decls[0].body[1].asm_text() == 'mulq %%rdx\n\taddq %[z], %%rax\n\t'
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('mulq %%rdx')
}
