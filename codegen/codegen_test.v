module codegen

import ast
import os
import parser
import time
import tokenize

// The tests below run as part of module codegen, and reach into the parser to
// build input, which is the shortest path from C source to an AST that the
// compiler has. String literals, call statements, variables, branches and loops
// cannot all be parsed yet, so the tests that need them build the tree the
// parser will produce for them: the emitter consumes the same nodes either way.

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

// The builders below assemble the tree for a body that keeps values in
// variables, branches on them and loops over them. They are the nodes the ast
// declares, made by hand because the parser cannot write all of them down yet.
fn name_node(name string) ast.Expr {
	return ast.Expr(ast.Ident{
		name: name
	})
}

fn binary_node(op string, left ast.Expr, right ast.Expr) ast.Expr {
	return ast.Expr(ast.Binary{
		op:    op
		left:  left
		right: right
	})
}

fn unary_node(op string, expr ast.Expr) ast.Expr {
	return ast.Expr(ast.Unary{
		op:   op
		expr: expr
	})
}

fn call_expression(name string, args []ast.Expr) ast.Expr {
	return ast.Expr(ast.Call{
		name: name
		args: args
	})
}

fn declaration(name string, typ string, init ?ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind:      .var_decl
		decl_name: name
		decl_type: typ
		init:      init
	}
}

fn assignment(target string, expr ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind:   .assign
		target: target
		expr:   expr
	}
}

fn return_expression(expr ast.Expr) ast.Stmt {
	return ast.Stmt{
		kind: .return_stmt
		expr: expr
	}
}

fn if_statement(cond ast.Expr, then_body []ast.Stmt, else_body []ast.Stmt) ast.Stmt {
	return ast.Stmt{
		kind:      .if_stmt
		cond:      cond
		then_body: then_body
		else_body: else_body
	}
}

fn while_statement(cond ast.Expr, body []ast.Stmt) ast.Stmt {
	return ast.Stmt{
		kind: .while_stmt
		cond: cond
		body: body
	}
}

fn break_statement() ast.Stmt {
	return ast.Stmt{
		kind: .break_stmt
	}
}

fn continue_statement() ast.Stmt {
	return ast.Stmt{
		kind: .continue_stmt
	}
}

fn param(name string, typ string) ast.Param {
	return ast.Param{
		name: name
		typ:  typ
	}
}

fn function_in_file(name string, params []ast.Param, body []ast.Stmt) ast.FnDecl {
	return ast.FnDecl{
		name:   name
		ret:    'int'
		params: params
		body:   body
	}
}

// unit_of is a translation unit whose entry function is main, with the other
// functions after it: a call written before a definition still binds to it, and
// this is the order that says so.
fn unit_of(main_body []ast.Stmt, helpers []ast.FnDecl) ast.TranslationUnit {
	mut decls := [function_in_file('main', []ast.Param{}, main_body)]
	decls << helpers
	return ast.TranslationUnit{
		decls: decls
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

// A constant the type model did not resolve is refused before the layout runs.
// The emitter writes a constant as a four-byte int, so a value that int cannot
// hold would be written as a different number than the program asked for:
// measured, `int main(void) { return 4294967295 > 2147483647; }` was emitted as
// an int comparison and returned 0 where ISO C and gcc return 1.
fn test_a_constant_the_model_did_not_type_is_refused_before_anything_is_written() {
	emitted := emit(program([return_expression(int_argument(4294967295))]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('4294967295')
	assert emitted.bytes.len == 0
	// The same node with a value an int holds is written as the int it is, which
	// is what keeps a tree assembled by hand emittable.
	small := emit(program([return_expression(int_argument(7))]), Options{})
	assert small.diagnostics.len == 0
	assert run_image(small.bytes) == 7
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
	// The tree is assembled by hand rather than parsed: a name nothing in the
	// unit declares is refused by the parser once the whole unit has been read,
	// and what this checks is the message the emitter gives for a name it cannot
	// place.
	emitted := emit(program([ast.Stmt{
		kind: .return_stmt
		expr: name_node('x')
	}]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('x is not a constant')
}

// A call whose result is read is emitted: the value arrives in the register a
// value is expected to be in, so a call can stand where a name would. What the
// -O levels decide is whether a call the optimizer knows is folded, not whether
// a call can be made at all.
fn test_a_call_can_be_the_value_of_an_expression() {
	helper := ast.FnDecl{
		name:   'twice'
		ret:    'int'
		params: [ast.Param{
			name: 'x'
			typ:  'int'
		}]
		body:   [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('x'), name_node('x'))
		}]
	}
	body := [
		declaration('v', 'int', ast.Expr(ast.Call{
			name: 'twice'
			args: [int_argument(21)]
		})),
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', name_node('v'), int_argument(42))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// Two calls in one expression each want somewhere to park their arguments, and
// the inner one has to park them above the outer one's: a shared slot would have
// the outer call hand over a value the inner one overwrote.
fn test_a_call_can_be_the_argument_of_another_call() {
	helper := ast.FnDecl{
		name:   'twice'
		ret:    'int'
		params: [ast.Param{
			name: 'x'
			typ:  'int'
		}]
		body:   [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('x'), name_node('x'))
		}]
	}
	body := [
		declaration('v', 'int', ast.Expr(ast.Call{
			name: 'twice'
			args: [ast.Expr(ast.Call{
				name: 'twice'
				args: [int_argument(21)]
			})]
		})),
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', name_node('v'), int_argument(84))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// A function that returns nothing has no value to read: the file says what each
// function it declares returns, and a call to one that returns void, read as a
// value, is reported rather than read from whatever the call left in the
// register.
fn test_a_call_to_a_void_function_used_as_a_value_is_reported() {
	declared := ast.FnDecl{
		name:   'nothing'
		ret:    'void'
		params: [ast.Param{
			name: 'v'
			typ:  'int'
		}]
	}
	body := [
		declaration('x', 'int', ast.Expr(ast.Call{
			name: 'nothing'
			args: [int_argument(1)]
		})),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [declared]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('returns void')
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

// A frame with two locals in it: each declaration takes a slot, each initializer
// writes it, and the return reads both back out.
fn test_two_locals_are_summed() {
	body := [
		declaration('a', 'int', int_argument(40)),
		declaration('b', 'int', int_argument(2)),
		return_expression(binary_node('+', name_node('a'), name_node('b'))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

// A declaration without an initializer is storage: the value is whatever the
// function writes into it before it reads it.
fn test_a_declaration_without_an_initializer_is_storage() {
	body := [
		declaration('n', 'int', none),
		assignment('n', int_argument(42)),
		return_expression(name_node('n')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 42
}

// A parameter arrives in a register, is stored where a local lives, and is read
// from there as many times as the expression asks for it.
fn test_a_parameter_is_used_in_an_expression() {
	helper := function_in_file('twice', [param('x', 'int')], [
		call_statement('printf', [string_argument('twice %d\n'), binary_node('+', name_node('x'),
			name_node('x'))]),
		return_statement(0),
	])
	body := [
		call_statement('twice', [int_argument(21)]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('twice 42')
}

// An arithmetic answer that is not a constant: the two values are in the frame
// and the operation happens at run time, where a wrong width or a wrong operand
// order would show up in the status.
fn test_arithmetic_on_locals_is_computed() {
	body := [
		declaration('a', 'int', int_argument(47)),
		declaration('b', 'int', int_argument(5)),
		declaration('sum', 'int', binary_node('+', name_node('a'), name_node('b'))),
		declaration('product', 'int', binary_node('*', binary_node('-', name_node('a'), name_node('b')),
			int_argument(2))),
		return_expression(binary_node('+', binary_node('+', name_node('sum'),
			name_node('product')), int_argument(0))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	// 52 + 84, and the low eight bits of 136 are the status.
	assert run_image(emitted.bytes) == 136
}

// The two division operators read the quotient and the remainder from the two
// registers a signed division leaves them in: 47 / 5 is 9 and 47 % 5 is 2.
fn test_division_and_remainder_on_locals() {
	body := [
		declaration('a', 'int', int_argument(47)),
		declaration('b', 'int', int_argument(5)),
		return_expression(binary_node('+', binary_node('/', name_node('a'), name_node('b')),
			binary_node('*', binary_node('%', name_node('a'), name_node('b')), int_argument(10)))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 29
}

// Each side of an if returns a value of its own, so the status says which branch
// ran. The condition is a constant here and a value read from the frame in the
// test after it, which is the case the branch is for.
fn test_each_side_of_an_if_returns_its_own_value() {
	taken := emit(program([
		if_statement(int_argument(1), [return_statement(3)], [return_statement(4)]),
	]), Options{})
	assert taken.diagnostics.len == 0
	assert run_image(taken.bytes) == 3
	not_taken := emit(program([
		if_statement(int_argument(0), [return_statement(3)], [return_statement(4)]),
	]), Options{})
	assert not_taken.diagnostics.len == 0
	assert run_image(not_taken.bytes) == 4
}

fn test_a_condition_on_a_local_picks_the_branch() {
	body := [
		declaration('n', 'int', int_argument(7)),
		if_statement(binary_node('<', name_node('n'), int_argument(10)), [return_statement(1)],
			[return_statement(2)]),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A body whose if can fall through has a way out that returns nothing, so the
// function still finishes with the zero a caller is owed.
fn test_a_body_that_falls_off_the_end_after_an_if_returns_zero() {
	body := [
		if_statement(int_argument(0), [return_statement(7)], []ast.Stmt{}),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 0
}

// A loop that counts to five: the variable is what the condition reads and the
// body writes, and the status is what it holds when the loop stops.
fn test_a_while_loop_counts_to_five() {
	body := [
		declaration('i', 'int', int_argument(0)),
		while_statement(binary_node('<', name_node('i'), int_argument(5)), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
		]),
		return_expression(name_node('i')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 5
}

// break leaves the loop where it stands.
fn test_break_leaves_a_loop() {
	body := [
		declaration('i', 'int', int_argument(0)),
		while_statement(int_argument(1), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			if_statement(binary_node('==', name_node('i'), int_argument(3)), [break_statement()],
				[]ast.Stmt{}),
		]),
		return_expression(name_node('i')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 3
}

// continue goes back to the test, so the statement after it is skipped and the
// loop still runs to its end: four rounds, one of them cut short.
fn test_continue_goes_round_the_loop_again() {
	body := [
		declaration('i', 'int', int_argument(0)),
		declaration('counted', 'int', int_argument(0)),
		while_statement(binary_node('<', name_node('i'), int_argument(4)), [
			assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			if_statement(binary_node('==', name_node('i'), int_argument(2)), [continue_statement()],
				[]ast.Stmt{}),
			assignment('counted', binary_node('+', name_node('counted'), int_argument(1))),
		]),
		return_expression(name_node('counted')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 3
}

// The shape a for is turned into before the back end sees it: a block that holds
// the declaration, a while whose condition is the test, and the increment as the
// last statement of the body. Nothing in the emitter knows about for; this test
// pins the desugaring both lanes write against, and the parser's own for is what
// produced the binary this shape came from.
fn test_the_shape_a_for_is_desugared_into_counts() {
	counting := ast.Stmt{
		kind: .block
		body: [
			declaration('i', 'int', int_argument(0)),
			while_statement(binary_node('<', name_node('i'), int_argument(5)), [
				assignment('total', binary_node('+', name_node('total'), binary_node('*',
					name_node('i'), int_argument(2)))),
				assignment('i', binary_node('+', name_node('i'), int_argument(1))),
			]),
		]
	}
	body := [
		declaration('total', 'int', int_argument(0)),
		counting,
		return_expression(name_node('total')),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 20
}

// A call whose arguments are computed: two locals are read out of the frame and
// handed over in the registers the definition reads its parameters from, and the
// definition reads them in a frame of its own. The library call inside the
// definition prints what arrived, which is what makes the arguments visible.
fn test_a_call_whose_arguments_are_locals() {
	helper := function_in_file('show', [param('x', 'int'), param('y', 'int')], [
		call_statement('printf', [string_argument('sum %d\n'), binary_node('+', name_node('x'),
			name_node('y'))]),
		return_statement(0),
	])
	body := [
		declaration('a', 'int', int_argument(40)),
		declaration('b', 'int', int_argument(2)),
		call_statement('show', [name_node('a'), name_node('b')]),
		call_statement('printf', [string_argument('difference %d\n'), binary_node('-', name_node('a'),
			name_node('b'))]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('sum 42')
	assert result.output.contains('difference 38')
}

// A pointer local is eight bytes wide and holds the address of a string literal.
// The library call reads the variable, not a literal written where the call is,
// and the program prints what the local points at.
fn test_a_library_call_reads_a_pointer_local() {
	body := [
		declaration('message', 'char *', string_argument('a variable says hello')),
		call_statement('puts', [name_node('message')]),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('a variable says hello')
}

// An int is four bytes and a pointer is eight, and the difference is visible: a
// pointer local and an int local sit in the same frame, each written and read at
// its own width. The call says the pointer kept its value and the status says the
// int kept its.
fn test_an_int_local_and_a_pointer_local_keep_their_widths() {
	body := [
		declaration('message', 'char *', string_argument('widths')),
		declaration('n', 'int', int_argument(6)),
		call_statement('puts', [name_node('message')]),
		return_expression(binary_node('*', name_node('n'), int_argument(7))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 42
	assert result.output.contains('widths')
}

// A function that takes both a pointer and an int and calls the library itself.
// The call to it is written before its definition, which is where a call has to
// bind forward, and the variadic call inside it formats a value computed from
// its parameters.
fn test_a_helper_takes_a_pointer_and_an_int() {
	helper := function_in_file('report', [param('message', 'char *'), param('n', 'int')], [
		call_statement('printf', [string_argument('%s %d\n'), name_node('message'),
			binary_node('*', name_node('n'), int_argument(2))]),
		return_statement(0),
	])
	body := [
		declaration('text', 'char *', string_argument('from a helper')),
		call_statement('report', [name_node('text'), int_argument(21)]),
		return_statement(0),
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('from a helper 42')
}

// Every comparison is a value of int width, zero or one, and the bits of the
// status are where the six of them are read back.
fn test_comparisons_produce_zero_or_one() {
	operators := ['<', '>', '==', '!=', '<=', '>=']
	// 3 against 5, 3 against 5, then 3 against 3: true, false, true, false,
	// true, true. Each answer goes into a bit of the status, so one run reads
	// back all six.
	truths := [i64(1), i64(0), i64(1), i64(0), i64(1), i64(1)]
	mut body := [declaration('a', 'int', int_argument(3))]
	mut total := i64(0)
	mut sum := ast.Expr(int_argument(0))
	for i, op in operators {
		right := if op in ['<', '>'] { int_argument(5) } else { int_argument(3) }
		weight := i64(1) << i
		body << declaration('c${i}', 'int', binary_node(op, name_node('a'), right))
		total += truths[i] * weight
		sum = binary_node('+', sum, binary_node('*', name_node('c${i}'), int_argument(weight)))
	}
	body << return_expression(sum)
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == int(total)
}

// The unary operators take one computed value: the sign change negates what is in
// the frame, and the logical not answers whether it is zero.
fn test_unary_operators_compute_on_a_local() {
	negated := emit(program([
		declaration('minus', 'int', int_argument(-42)),
		return_expression(unary_node('-', name_node('minus'))),
	]), Options{})
	assert negated.diagnostics.len == 0
	assert run_image(negated.bytes) == 42
	notted := emit(program([
		declaration('zero', 'int', int_argument(0)),
		declaration('five', 'int', int_argument(5)),
		return_expression(binary_node('+', binary_node('*', unary_node('!', name_node('zero')),
			int_argument(40)), binary_node('*', unary_node('!', name_node('five')), int_argument(2)))),
	]), Options{})
	assert notted.diagnostics.len == 0
	assert run_image(notted.bytes) == 40
}

// The short-circuit operators: the left side settles the answer, so the right
// side is not evaluated at all. The right side here divides by a variable that
// holds zero, which would stop the process if it were evaluated.
fn test_and_and_or_do_not_evaluate_the_side_they_do_not_need() {
	body := [
		declaration('zero', 'int', int_argument(0)),
		declaration('one', 'int', int_argument(1)),
		declaration('conjunction', 'int', binary_node('&&', name_node('zero'),
			binary_node('/', name_node('one'), name_node('zero')))),
		declaration('disjunction', 'int', binary_node('||', name_node('one'),
			binary_node('/', name_node('one'), name_node('zero')))),
		return_expression(binary_node('+', binary_node('*', name_node('conjunction'), int_argument(2)),
			name_node('disjunction'))),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	assert run_image(emitted.bytes) == 1
}

// A tree with a frame produces the same bytes every time it is emitted, which is
// what the layout being a sequence is for.
fn test_a_tree_with_a_frame_produces_the_same_bytes() {
	body := [
		declaration('a', 'int', int_argument(1)),
		if_statement(name_node('a'), [
			assignment('a', binary_node('+', name_node('a'), int_argument(1))),
		], []ast.Stmt{}),
		while_statement(binary_node('<', name_node('a'), int_argument(4)), [
			assignment('a', binary_node('+', name_node('a'), int_argument(1))),
		]),
		return_expression(name_node('a')),
	]
	unit := program(body)
	first := emit(unit, Options{})
	second := emit(unit, Options{})
	assert first.diagnostics.len == 0
	assert second.diagnostics.len == 0
	assert first.bytes == second.bytes
}

// What the back end cannot emit it reports, once, with the place it was written,
// and writes no image at all. These are the three shapes a body can reach: a
// statement with no loop to leave, a local of a type that has no instruction,
// and an operation on a pointer that would compute at the wrong width.
fn test_break_outside_a_loop_is_one_located_diagnostic_and_no_bytes() {
	emitted := emit(program([break_statement()]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('break outside a loop')
	assert emitted.bytes.len == 0
}

fn test_a_local_of_a_type_with_no_instruction_is_reported() {
	body := [
		declaration('f', 'double', int_argument(1)),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('double')
	assert emitted.bytes.len == 0
}

fn test_an_operation_on_a_pointer_is_reported() {
	body := [
		declaration('s', 'char *', string_argument('x')),
		declaration('t', 'char *', binary_node('+', name_node('s'), int_argument(1))),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('pointer')
	assert emitted.bytes.len == 0
}

// More parameters than the machine passes in registers: the rest would have to
// be read off the stack, and that is said rather than emitted.
fn test_more_parameters_than_the_machine_has_registers_is_reported() {
	mut params := []ast.Param{}
	for i in 0 .. 7 {
		params << param('p${i}', 'int')
	}
	helper := function_in_file('many', params, [return_statement(0)])
	emitted := emit(unit_of([return_statement(0)], [helper]), Options{})
	assert emitted.diagnostics.len == 1
	assert emitted.diagnostics[0].msg.contains('more than 6')
	assert emitted.bytes.len == 0
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

// A char is one byte in the frame and an int in an expression: the load widens
// what it read, so adding one to a number needs nothing else, and a value too
// large for the byte is stored as its low byte, which is what the language's
// assignment to a char does.
fn test_a_char_local_is_a_byte_that_widens_when_it_is_read() {
	body := [
		declaration('c', 'char', int_argument(65)),
		declaration('sum', 'int', int_argument(0)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('-', name_node('c'), int_argument(65)))),
		declaration('d', 'char', int_argument(300)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('-', name_node('d'), int_argument(44)))),
		declaration('e', 'char', int_argument(-1)),
		assignment('sum', binary_node('+', name_node('sum'), binary_node('+', name_node('e'), int_argument(1)))),
		ast.Stmt{
			kind: .return_stmt
			expr: name_node('sum')
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// A char parameter arrives in a register that carries a machine word: the frame
// keeps the low byte of it, and the argument side reads the byte and widens it,
// so a char whose value is negative is handed over as the number it is.
fn test_a_char_parameter_keeps_its_value_and_its_sign() {
	helper := ast.FnDecl{
		name:   'addc'
		ret:    'int'
		params: [
			ast.Param{
				name: 'a'
				typ:  'char'
			},
			ast.Param{
				name: 'b'
				typ:  'char'
			},
		]
		body:   [ast.Stmt{
			kind: .return_stmt
			expr: binary_node('+', name_node('a'), name_node('b'))
		}]
	}
	body := [
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', ast.Expr(ast.Call{
				name: 'addc'
				args: [int_argument(200), int_argument(100)]
			}), int_argument(44))
		},
	]
	emitted := emit(unit_of(body, [helper]), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}

// An array is a block of storage and its name is the address of the first
// element, which is what a library function that takes a pointer reads: the bytes
// written one at a time are the string that comes out of it.
fn test_a_char_array_written_one_byte_at_a_time_is_a_string() {
	body := [
		ast.Stmt{
			kind:       .var_decl
			decl_name:  'buf'
			decl_type:  'char'
			decl_count: 8
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(0)
			expr:   int_argument(72)
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(1)
			expr:   int_argument(105)
		},
		ast.Stmt{
			kind:   .assign
			target: 'buf'
			index:  int_argument(2)
			expr:   int_argument(0)
		},
		call_statement('puts', [name_node('buf')]),
		return_statement(0),
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
	assert result.output.contains('Hi')
}

// An element is addressed as the frame plus the index scaled by the width of an
// element, so an index that is not a constant is the same instruction: what one
// element was written through, the other is read through.
fn test_an_element_with_a_variable_index_is_the_element_it_reads() {
	body := [
		ast.Stmt{
			kind:       .var_decl
			decl_name:  'a'
			decl_type:  'int'
			decl_count: 4
		},
		declaration('i', 'int', int_argument(2)),
		ast.Stmt{
			kind:   .assign
			target: 'a'
			index:  name_node('i')
			expr:   int_argument(30)
		},
		ast.Stmt{
			kind: .return_stmt
			expr: binary_node('-', ast.Expr(ast.Index{
				name:  'a'
				index: int_argument(2)
			}), int_argument(30))
		},
	]
	emitted := emit(program(body), Options{})
	assert emitted.diagnostics.len == 0
	result := run_capturing(emitted.bytes)
	assert result.exit_code == 0
}
