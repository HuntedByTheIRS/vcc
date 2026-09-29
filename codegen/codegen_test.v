module codegen

import ast
import os
import parser
import time
import tokenize

// The tests below run as part of module codegen, and reach into the parser to
// build input, which is the shortest path from C source to an AST that the
// compiler has. String literals and call statements cannot be parsed yet, so the
// tests that need them build the tree the parser will produce for them: the
// emitter consumes the same nodes either way.

fn translation_unit(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

// run_capturing writes an image the way main.v does and runs it, so these tests
// check the artifact and not the intent behind it. The output is what a library
// call was supposed to produce, and the exit status is what the returned
// constant became.
fn run_capturing(image []u8) os.Result {
	path := os.join_path(os.temp_dir(), 'vcc_codegen_test_${os.getpid()}_${time.now().unix()}')
	os.write_file_array(path, image) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	return result
}

fn run_image(image []u8) int {
	return run_capturing(image).exit_code
}

// The tree for a program the parser cannot write down yet: a function that calls
// other functions, with string and integer arguments, and returns a constant.
fn call_statement(name string, args []ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind: .expr_stmt
		expr: ast.Expr(ast.Call{
			name: name
			args: args
		})
	}
}

fn string_argument(value string) ast.Expr {
	return ast.Expr(ast.StrLit{
		value: value
		text:  '"${value}"'
	})
}

fn int_argument(value i64) ast.Expr {
	return ast.Expr(ast.IntLit{
		value: value
		text:  '${value}'
	})
}

fn return_statement(value i64) ast.Stmt {
	return ast.Stmt{
		kind: .return_stmt
		expr: ast.Expr(ast.IntLit{
			value: value
			text:  '${value}'
		})
	}
}

fn program(body []ast.Stmt) ast.TranslationUnit {
	return ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name: 'main'
				ret:  'int'
				body: body
			},
		]
	}
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

// A body is statements now, not one folded return: the first return is what the
// function finishes with, and the second is emitted behind it and never reached.
fn test_a_body_with_more_than_one_return_compiles_and_the_first_wins() {
	emitted := emit(translation_unit('int main() { return 1; return 2; }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

fn test_a_return_inside_a_nested_block_is_emitted() {
	emitted := emit(translation_unit('int main() { { return 5; } }'), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 5
}

// A program whose body runs to the end without returning still has a status:
// zero, which is what C says the entry function does.
fn test_a_body_that_never_returns_finishes_with_zero() {
	body := [
		call_statement('puts', [string_argument('no return statement')]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('no return statement')
}

// The point of the whole container: the code calls a function that is not in the
// image, the loader resolves it out of libc, and the process prints. A file with
// no string in it would pass without any of that working.
fn test_a_call_to_a_library_function_prints_and_the_return_becomes_the_status() {
	body := [
		call_statement('puts', [string_argument('vcc speaks to libc')])
		return_statement(3),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 3
	assert result.output.contains('vcc speaks to libc')
}

// printf is variadic, which is the one call shape where the machine wants more
// than the arguments themselves: the number of vector arguments goes in the low
// byte of the result register before the call.
fn test_a_variadic_library_call_prints_its_formatted_argument() {
	body := [
		call_statement('printf', [string_argument('value: %d\n'), int_argument(42)])
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('value: 42')
}

// A call to a name the file defines is a call into the image, wherever in the
// file the definition is written. Treating it as a library symbol would fail at
// load time with the name of a function the file supplies itself.
fn test_a_call_to_a_function_in_the_file_binds_to_the_definition() {
	unit := ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name: 'main'
				ret:  'int'
				body: [call_statement('helper', []ast.Expr{}), return_statement(5)]
			},
			ast.FnDecl{
				name: 'helper'
				ret:  'int'
				body: [
					call_statement('puts', [string_argument('from the helper')])
					return_statement(0),
				]
			},
		]
	}
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 5
	assert result.output.contains('from the helper')
}

// The same tree has to produce the same bytes every run: the layout is a
// sequence and the imports are in the order they were first called.
fn test_the_same_tree_produces_the_same_bytes() {
	body := [
		call_statement('puts', [string_argument('deterministic')])
		return_statement(0),
	]
	first := emit(program(body), Options{})
	second := emit(program(body), Options{})
	assert first.diagnostics.len == 0
	assert second.diagnostics.len == 0
	assert first.bytes == second.bytes
}

// The facts that make this a dynamically linked executable: what the file is,
// which machine it is for, the loader it names, and the library it runs
// against. The entry point has to land inside the segment the loader maps,
// otherwise the kernel has nowhere to start.
fn test_the_image_is_a_dynamic_elf_the_kernel_can_start() {
	emitted := emit(translation_unit('int main() { return 3; }'), Options{})
	assert emitted.diagnostics.len == 0
	bytes := emitted.bytes
	base := emitted.target.load_base
	assert bytes[0..4] == [u8(0x7f), `E`, `L`, `F`]
	assert bytes[4] == 2 // 64-bit
	assert bytes[5] == 1 // little endian
	assert u16_at(bytes, 16) == 2 // ET_EXEC
	assert u16_at(bytes, 18) == 62 // EM_X86_64
	headers := segments(bytes)
	assert headers.len == 4
	interp := only_segment(headers, elf_ph_type_interp)
	assert read_string(bytes, int(interp.offset)) == emitted.target.interpreter
	load := only_segment(headers, elf_ph_type_load)
	entry := u64_at(bytes, 24)
	assert entry >= load.vaddr
	assert entry < load.vaddr + load.filesz
	assert load.filesz == u64(bytes.len)
	needed := dynamic_value(bytes, dt_needed) or { panic('the image has no DT_NEEDED') }
	strtab := dynamic_value(bytes, dt_strtab) or { panic('the image has no DT_STRTAB') }
	assert read_string(bytes, int(strtab - base) + int(needed)) == 'libc.so.6'
}

// Dynamic linking is also a symbol table and a relocation per imported function:
// the loader has to find each name and write its address where the calls read
// it, so a test looks at both rather than trusting that the calls work by luck.
fn test_an_imported_function_is_an_undefined_symbol_with_a_relocation() {
	body := [
		call_statement('puts', [string_argument('relocated')])
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	bytes := emitted.bytes
	base := emitted.target.load_base
	dynsym := dynamic_value(bytes, dt_symtab) or { panic('the image has no DT_SYMTAB') }
	dynstr := dynamic_value(bytes, dt_strtab) or { panic('the image has no DT_STRTAB') }
	hash := dynamic_value(bytes, dt_hash) or { panic('the image has no DT_HASH') }
	rela := dynamic_value(bytes, dt_rela) or { panic('the image has no DT_RELA') }
	relasz := dynamic_value(bytes, dt_relasz) or { panic('the image has no DT_RELASZ') }
	// The hash table's chain count is how many symbols there are, which is what
	// walks the table: the null entry, the called function, and the exit the
	// entry point leaves through.
	count := int(u32_at(bytes, int(hash - base) + 4))
	assert count == 3
	mut names := []string{}
	for i in 1 .. count {
		at := int(dynsym - base) + i * elf_symbol_size
		assert bytes[at + 4] == symbol_global_function
		assert u16_at(bytes, at + 6) == 0 // undefined: the definition is elsewhere
		names << read_string(bytes, int(dynstr - base) + int(u32_at(bytes, at)))
	}
	assert 'puts' in names
	assert 'exit' in names
	// One relocation per imported function, each one a global data relocation
	// naming a symbol and pointing at a slot the code reads.
	assert relasz == u64(2 * elf_relocation_size)
	mut slots := []u64{}
	for i in 0 .. 2 {
		at := int(rela - base) + i * elf_relocation_size
		slots << u64_at(bytes, at)
		info := u64_at(bytes, at + 8)
		assert (info & 0xffffffff) == relocation_glob_dat
		assert (info >> 32) >= 1 // the null symbol is never referenced
	}
	assert slots[0] != slots[1]
	for slot in slots {
		assert slot >= base && slot < base + u64(bytes.len)
	}
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
	assert emitted.bytes.len == 0
}

fn test_a_call_argument_that_is_not_a_constant_is_reported() {
	body := [
		call_statement('puts', [ast.Expr(ast.Ident{ name: 'message' })]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('message')
	assert emitted.bytes.len == 0
}

fn test_a_call_as_an_argument_of_another_call_is_reported() {
	body := [
		call_statement('puts', [ast.Expr(ast.Call{ name: 'name_of', args: []ast.Expr{} })]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('name_of')
	assert emitted.bytes.len == 0
}

fn test_more_arguments_than_the_machine_has_registers_is_reported() {
	mut args := []ast.Expr{}
	for i in 0 .. 7 {
		args << int_argument(i64(i))
	}
	emitted := emit(program([call_statement('puts', args)]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('more than 6')
	assert emitted.bytes.len == 0
}

fn test_an_expression_statement_that_is_not_a_call_is_reported() {
	body := [
		ast.Stmt{
			kind: .expr_stmt
			expr: ast.Expr(ast.IntLit{ value: 1, text: '1' })
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('call')
	assert emitted.bytes.len == 0
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

// The check is on every function the image holds, not only on the entry point:
// a helper the entry point calls is emitted too.
fn test_a_helper_with_another_return_type_is_reported() {
	unit := ast.TranslationUnit{
		decls: [
			ast.FnDecl{
				name: 'main'
				ret:  'int'
				body: [call_statement('helper', []ast.Expr{}), return_statement(0)]
			},
			ast.FnDecl{
				name: 'helper'
				ret:  'char'
				body: [return_statement(0)]
			},
		]
	}
	emitted := emit(unit, Options{})
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

// A program header the way the kernel reads it, so a test can say what the image
// claims rather than what the emitter meant.
struct Segment {
	kind   u32
	offset u64
	vaddr  u64
	filesz u64
}

fn u16_at(bytes []u8, offset int) u16 {
	return u16(bytes[offset]) | (u16(bytes[offset + 1]) << 8)
}

fn u32_at(bytes []u8, offset int) u32 {
	return u32(bytes[offset]) | (u32(bytes[offset + 1]) << 8) | (u32(bytes[offset + 2]) << 16) | (u32(bytes[offset + 3]) << 24)
}

fn u64_at(bytes []u8, offset int) u64 {
	mut value := u64(0)
	for i in 0 .. 8 {
		value |= u64(bytes[offset + i]) << u64(8 * i)
	}
	return value
}

fn segments(bytes []u8) []Segment {
	start := int(u64_at(bytes, 32))
	size := int(u16_at(bytes, 54))
	count := int(u16_at(bytes, 56))
	mut out := []Segment{}
	for i in 0 .. count {
		at := start + i * size
		out << Segment{
			kind:   u32_at(bytes, at)
			offset: u64_at(bytes, at + 8)
			vaddr:  u64_at(bytes, at + 16)
			filesz: u64_at(bytes, at + 32)
		}
	}
	return out
}

fn only_segment(headers []Segment, kind u32) Segment {
	matching := headers.filter(it.kind == kind)
	assert matching.len == 1
	return matching[0]
}

// dynamic_value looks a tag up in the dynamic table the loader reads.
fn dynamic_value(bytes []u8, tag u64) ?u64 {
	dynamic := only_segment(segments(bytes), elf_ph_type_dynamic)
	for i in 0 .. int(dynamic.filesz) / elf_dynamic_entry_size {
		at := int(dynamic.offset) + i * elf_dynamic_entry_size
		if u64_at(bytes, at) == dt_null {
			break
		}
		if u64_at(bytes, at) == tag {
			return u64_at(bytes, at + 8)
		}
	}
	return none
}

fn read_string(bytes []u8, offset int) string {
	mut end := offset
	for end < bytes.len && bytes[end] != 0 {
		end++
	}
	return bytes[offset..end].bytestr()
}
