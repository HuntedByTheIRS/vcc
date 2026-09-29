module codegen

import ast
import os
import parser
import time
import tokenize

// The tests below run as part of module codegen, and reach into the parser to
// build input. That is the shortest path from C source to an AST that the
// compiler has, and it means a codegen test fails for the right reason when the
// front end changes.

fn translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

// run_image writes an image the way main.v does and runs it, so these tests
// check the artifact and not the intent behind it.
fn run_image(image []u8) int {
	path := os.join_path(os.temp_dir(), 'vcc_codegen_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result.exit_code
}

fn test_the_exit_status_is_the_returned_constant() {
	emitted := emit(translation_unit('int main() { return 7; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 7
}

fn test_a_constant_expression_is_folded() {
	emitted := emit(translation_unit('int main() { return 6 * 7; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

fn test_a_negative_return_wraps_into_the_status_byte() {
	emitted := emit(translation_unit('int main() { return -1; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 255
}

fn test_a_status_wider_than_a_byte_keeps_its_low_bits() {
	emitted := emit(translation_unit('int main() { return 300; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 44
}

fn test_the_image_is_an_elf_executable_with_the_code_after_the_headers() {
	emitted := emit(translation_unit('int main() { return 3; }'), Options{})
	assert emitted.bytes[0..4] == [u8(0x7f), `E`, `L`, `F`]
	assert emitted.bytes.len == 4096 + 12 // one page of headers, then the code
	assert emitted.target.name == 'x86_64-linux'
	// mov edi, 3
	assert emitted.bytes[4096] == 0xbf
	assert emitted.bytes[4097] == 3
	// mov eax, 60 (exit)
	assert emitted.bytes[4101] == 0xb8
	assert emitted.bytes[4102] == 60
	// syscall
	assert emitted.bytes[4106..] == [u8(0x0f), 0x05]
}

fn test_division_by_zero_is_a_diagnostic_and_not_a_crash() {
	emitted := emit(translation_unit('int main() { return 1 / 0; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('division by zero')
	assert emitted.bytes.len == 0
}

fn test_a_non_constant_return_is_reported_with_the_name() {
	emitted := emit(translation_unit('int main() { return x; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('x is not a constant')
}

fn test_a_call_in_a_constant_expression_is_reported() {
	emitted := emit(translation_unit('int main() { return f(1); }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('f')
}

// A long constant chain used to take the stack out: the fold recursed once per
// term, and about three thousand terms is a size generated code reaches without
// trying. The benchmark harness found it; this keeps it found.
fn test_a_long_constant_chain_folds() {
	mut terms := []string{}
	mut expected := i64(0)
	for i in 0 .. 20000 {
		value := (i % 97) + 1
		terms << '${value}'
		expected = (expected + value) & 0xff
	}
	source := 'int main() { return ${terms.join(' + ')}; }'
	emitted := emit(translation_unit(source), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(expected)
}

fn test_a_body_with_work_in_it_is_reported() {
	emitted := emit(translation_unit('int main() { return 1; return 2; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('single return')
}

fn test_a_file_without_main_says_so() {
	emitted := emit(translation_unit('int other() { return 1; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('no definition of main')
}

fn test_a_return_type_other_than_int_is_reported() {
	emitted := emit(translation_unit('char main() { return 1; }'), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('only int')
}

fn test_the_entry_point_can_be_named() {
	emitted := emit(translation_unit('int other() { return 9; }'), Options{
		entry: 'other'
	})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 9
}

fn test_an_unknown_target_names_the_targets_that_exist() {
	emitted := emit(translation_unit('int main() { return 1; }'), Options{
		target: 'riscv64-linux'
	})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('unknown target riscv64-linux')
	assert emitted.diagnostics[0].msg.contains('x86_64-linux')
}
