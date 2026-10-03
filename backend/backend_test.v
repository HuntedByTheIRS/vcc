module backend

import backend.arch.x86_64
import backend.os.linux
import os

// The machine and the system are written by hand in two files that do not know
// about each other, which is the point of the split and also its one hazard: a
// syscall that names a register the machine does not have is a typo nothing else
// would catch, because the names are strings on both sides. These tests are where
// the two descriptions are held to each other.

fn test_the_machine_and_the_system_name_the_same_registers() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	assert target.registers.len > 0
	for syscall in target.syscalls {
		for arg in syscall.args {
			if target.reg(arg) == none {
				assert false, '${syscall.name} takes ${arg}, which is not a register of ${target.arch}'
			}
		}
	}
	for arg in target.syscall_args_regs {
		if target.reg(arg) == none {
			assert false, 'the kernel takes arguments in ${arg}, which is not a register of ${target.arch}'
		}
	}
	if target.reg(target.syscall_number_reg) == none {
		assert false, 'no register named ${target.syscall_number_reg} for the syscall number'
	}
}

fn test_every_target_is_a_machine_composed_with_a_system() {
	assert targets().len > 0
	for target in targets() {
		assert target.name == '${target.arch}-${target.os}'
		assert target.word_size > 0
		assert target.elf_machine > 0
		assert target.registers.len > 0
		assert target.syscalls.len > 0
		assert target.page_size > 0
		assert target.load_base > 0
	}
}

fn test_the_exit_sequence_is_the_bytes_that_end_the_process() {
	// mov edi, 7 / mov eax, 60 / syscall, which is what the tables describe and
	// what the kernel acts on. Written out here so a change to either table has
	// to be a change to this expectation.
	code := lookup('x86_64-linux') or { panic('the target description has no such name') }.exit_sequence(7) or { panic('the target description has no such name') }
	expected := [u8(0xbf), 7, 0, 0, 0, u8(0xb8), 60, 0, 0, 0, 0x0f, 0x05]
	assert code == expected
}

fn test_the_indirect_call_is_the_bytes_that_call_the_address_in_a_register() {
	// call *%rax / call *%r8, which is what the machine's assembler produces for
	// an indirect call. Written out here so a change to the encoding has to be a
	// change to this expectation.
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	assert target.call_register(rax) or {
		panic('the target description has no such name')
	} == [u8(0xff), u8(0xd0)]
	assert target.call_register(r8) or {
		panic('the target description has no such name')
	} == [u8(0x41), u8(0xff), u8(0xd0)]
}

fn test_a_system_that_does_not_know_a_machine_answers_nothing() {
	// An empty table is how the emitter finds out that the combination is not
	// described yet. Falling back to another machine's numbers would be a wrong
	// program rather than a refusal.
	assert linux.syscalls('z80').len == 0
	assert linux.syscall_args_regs('z80').len == 0
}

// -print-file-name= has to name a file the linker would really pick, so the
// query and the link go through one search: the -L directories first, then the
// target's own, which is the order `linux.search_dirs` builds. A name the search
// does not have answers none, which is what lets the caller answer with the name
// unchanged the way gcc does.
fn test_the_library_file_query_is_the_linkers_search() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	dir := os.join_path(os.temp_dir(), 'vcc_backend_library_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	probe := os.join_path(dir, 'libprobe.so')
	os.write_file(probe, 'probe') or { panic(err) }
	found := target.library_file('libprobe.so', [dir]) or {
		panic('the -L directory was not searched')
	}
	assert found == probe
	if _ := target.library_file('nosuchfile.xyz', [dir]) {
		assert false, 'a name the search does not have has to answer none'
	}
	dirs := target.library_dirs_for([dir])
	assert dirs.len == target.library_dirs.len + 1
	assert dirs[0] == dir
	assert dirs[1..] == target.library_dirs
	assert target.base_library() == linux.base_library
	// The resolved form is the same search with the name read out of the file,
	// which is what a report of what the link would do asks for.
	system := linux.find_file('libm.so.6', target.library_dirs) or { return }
	script := os.join_path(dir, 'libscript.so')
	os.write_file(script, '/* GNU ld script\nOUTPUT_FORMAT(elf64-x86-64)\nGROUP ( ${system} ) */\n') or {
		panic(err)
	}
	resolved := target.resolve_libraries(['script'], [dir]) or { panic(err) }
	assert resolved.len == 1
	assert resolved[0].path == script
	assert resolved[0].soname == 'libm.so.6'
}

fn test_the_encoder_refuses_a_register_it_cannot_name() {
	wide := x86_64.Register{
		name:      'rax'
		wide_name: 'rax'
		code:      0
		width:     8
		call_arg:  -1
	}
	encoded := x86_64.mov_imm32(wide, 1) or { []u8{} }
	assert encoded.len == 0
}

fn test_a_target_with_no_syscalls_refuses_to_exit() {
	// A table that got emptied or renamed has to stop the emitter, not emit a
	// trap with whatever happened to be in the register.
	empty := Target{
		name:   'nothing-nothing'
		System: System{ exit_syscall: 'exit' }
	}
	code := empty.exit_sequence(1) or { []u8{} }
	assert code.len == 0
}

// The instructions a function body is made of. An encoding that is wrong is a
// wrong program rather than a wrong answer, so each one is held to the bytes the
// machine's own assembler produces for it.
fn test_the_slot_moves_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rbp := target.reg('rbp') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	edi := target.reg('edi') or { panic('the target description has no such name') }
	// load eax, [rbp-8] / load rax, [rbp-8]
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(eax), 4) or { panic('the target description has no such name') } == [
		u8(0x8b),
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(eax), 8) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x8b,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// mov [rbp-8], eax / mov [rbp-8], rax
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(eax), 4) or { panic('the target description has no such name') } == [
		u8(0x89),
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(eax), 8) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x89,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// A register the low three bits cannot name and a wide move of it, which is
	// how a pointer parameter arrives in the frame.
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(edi), 4) or { panic('the target description has no such name') } == [
		u8(0x8b),
		0xbd,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(edi), 8) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x89,
		0xbd,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// A byte: a store of the low byte, and a load that widens what it read, so
	// that a char read out of the frame is the int the language promotes it to.
	// The prefix is written even when the low three bits could name a register
	// without it, because those bits name a different register when it is
	// missing.
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(eax), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x0f,
		0xbe,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(eax), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x88,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(edi), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x88,
		0xbd,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// A two-byte value: a store with the operand-size prefix, and a load that
	// widens it with its sign kept, which is the shape a read of a short has.
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(eax), 2) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xbf,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.load_slot_unsigned(target.describe(rbp), -8, target.describe(eax), 2) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xb7,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.store_slot(target.describe(rbp), -8, target.describe(eax), 2) or { panic('the target description has no such name') } == [
		u8(0x66),
		0x89,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// A byte load of an unsigned value is the same read with zero above it
	// rather than its sign, so the widening instruction is the other one.
	assert x86_64.load_slot_unsigned(target.describe(rbp), -8, target.describe(eax), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x0f,
		0xb6,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// A width that is none of a byte, a short, an int or a pointer is refused: a
	// value of that width has no instruction, and moving it at four would read a
	// neighbour.
	assert x86_64.load_slot(target.describe(rbp), -8, target.describe(eax), 3) or { []u8{} }.len == 0
}

fn test_a_conversion_widens_a_value_with_its_sign_kept() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	// movsx eax, al is a value narrowed to a char, and movsxd rax, eax is an
	// address made out of an int: 6.3.1.3 says the sign is the one kept. movsx
	// eax, ax is the same narrowing at a short, and movzx eax, ax the same with
	// zero above it.
	assert x86_64.sign_extend_byte(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xbe,
		0xc0,
	]
	assert x86_64.sign_extend_half(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xbf,
		0xc0,
	]
	assert x86_64.zero_extend_half(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xb7,
		0xc0,
	]
	assert x86_64.sign_extend_word(target.describe(rax), target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x63,
		0xc0,
	]
	assert target.sign_extend_byte(eax) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xbe,
		0xc0,
	]
	assert target.sign_extend_word(rax, eax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x63,
		0xc0,
	]
}

fn test_the_frame_instructions_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	// sub rsp, 32, and the immediate is where the emitter will fill the size in
	assert x86_64.frame_reserve(32) == [u8(0x48), 0x81, 0xec, 0x20, 0x00, 0x00, 0x00]
	assert x86_64.frame_reserve_immediate == 3
	// mov rsp, rbp; pop rbp; ret
	assert x86_64.frame_epilogue() == [u8(0x48), 0x89, 0xec, 0x5d, 0xc3]
	assert target.frame_immediate_offset() == 3
}

// The entry point reads the kernel's argument vector off the stack before the
// stack is aligned for the call. A process starts with the stack pointer at the
// count of the arguments, the addresses of the arguments one word above it, and
// the environment after the null that ends the vector, so the count goes into
// the second argument register as the address of the count and then that
// register moves up one word. Measured with gcc 16.2.1, a program that returns
// its argument count exits 1 with no arguments and 4 with three, which is what
// the run tests in codegen check on the image this sequence is part of.
fn test_the_entry_point_reads_the_argument_vector_the_kernel_left() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	assert target.loader_arguments() or { panic('the target description has no such name') } == [
		u8(0x48),
		0x89,
		0xe6, // mov rsi, rsp
		0x8b,
		0x3e, // mov edi, [rsi]
		0x48,
		0x81,
		0xc6,
		0x08,
		0x00,
		0x00,
		0x00, // add rsi, 8
		0x48,
		0x8d,
		0x94,
		0xfe,
		0x08,
		0x00,
		0x00,
		0x00, // lea rdx, [rsi + rdi*8 + 8]
	]
}

fn test_the_arithmetic_is_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	assert x86_64.add_reg32(target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x01),
		0xc8,
	]
	assert x86_64.sub_reg32(target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x29),
		0xc8,
	]
	assert x86_64.imul_reg32(target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xaf,
		0xc1,
	]
	// cdq then idiv ecx, which is the pair a signed division is
	assert x86_64.cdq() == [u8(0x99)]
	assert x86_64.idiv_reg32(target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0xf7),
		0xf9,
	]
	assert x86_64.neg_reg32(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0xf7),
		0xd8,
	]
	assert x86_64.not_reg32(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0xf7),
		0xd0,
	]
}

fn test_a_comparison_becomes_a_zero_or_a_one_in_the_register() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	// cmp eax, ecx then setcc al then movzx eax, al, which is every comparison
	// the language has: the order is the one that changes.
	assert x86_64.test_reg32(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x85),
		0xc0,
	]
	assert x86_64.cmp_reg32(target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x39),
		0xc8,
	]
	assert x86_64.set_condition(.equal, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x94,
		0xc0,
	]
	assert x86_64.set_condition(.not_equal, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x95,
		0xc0,
	]
	assert x86_64.set_condition(.less, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x9c,
		0xc0,
	]
	assert x86_64.set_condition(.greater, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x9f,
		0xc0,
	]
	assert x86_64.set_condition(.less_or_equal, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x9e,
		0xc0,
	]
	assert x86_64.set_condition(.greater_or_equal, target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x9d,
		0xc0,
	]
	assert x86_64.movzx_byte(target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xb6,
		0xc0,
	]
	// The whole shape the emitter asks for, and the operator spelled the way the
	// language spells it.
	assert target.compare('<=', eax, ecx) or { panic('the target description has no such name') } == [
		u8(0x39),
		0xc8,
		0x0f,
		0x9e,
		0xc0,
		0x0f,
		0xb6,
		0xc0,
	]
	assert target.compare('<<', eax, ecx) or { []u8{} }.len == 0
	// Only the first four registers have a one-byte name a conditional set can
	// write, so anything else is refused rather than encoded at the wrong width.
	edi := target.reg('edi') or { panic('the target description has no such name') }
	assert x86_64.set_condition(.equal, target.describe(edi)) or { []u8{} }.len == 0
}

fn test_a_comparison_of_two_addresses_is_made_at_the_width_of_a_word() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	// cmp rax, rcx then setcc al then movzx eax, al. The wide compare is the same
	// comparison with REX.W in front of it, because comparing the low halves of
	// two addresses would call two different ones equal.
	assert x86_64.cmp_reg64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x39,
		0xc8,
	]
	assert target.compare_word('==', rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x39,
		0xc8,
		0x0f,
		0x94,
		0xc0,
		0x0f,
		0xb6,
		0xc0,
	]
	// The move an address makes into the scratch register is a word too, and the
	// four-byte move beside it is what would keep the low half of the address.
	assert x86_64.mov_reg64(target.describe(rcx), target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x89,
		0xc1,
	]
	assert target.move_register64(rcx, rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x89,
		0xc1,
	]
	// A register the encoder cannot name at four bytes is refused rather than
	// encoded at the wrong width.
	al := x86_64.Register{
		name:  'al'
		code:  0
		width: 1
	}
	assert x86_64.cmp_reg64(al, target.describe(rcx)) or { []u8{} }.len == 0
	assert x86_64.mov_reg64(target.describe(rcx), al) or { []u8{} }.len == 0
}

fn test_the_jumps_are_the_bytes_the_machine_reads() {
	assert x86_64.jump_rel32(16) == [u8(0xe9), 0x10, 0x00, 0x00, 0x00]
	assert x86_64.jump_zero_rel32(16) == [u8(0x0f), 0x84, 0x10, 0x00, 0x00, 0x00]
	assert x86_64.jump_nonzero_rel32(16) == [u8(0x0f), 0x85, 0x10, 0x00, 0x00, 0x00]
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	assert target.jump(-4) == [u8(0xe9), 0xfc, 0xff, 0xff, 0xff]
}

fn test_the_address_instructions_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rbp := target.reg('rbp') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	// lea rax, [rbp-8]
	assert x86_64.address_of_slot(target.describe(rbp), -8, target.describe(rax)) == [
		u8(0x48),
		0x8d,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// lea rax, [rbp + rax*4 - 8], and the same address with the scale of a char
	assert x86_64.address_of_element(target.describe(rbp), target.describe(rax), 4, -8, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x8d,
		0x84,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert x86_64.address_of_element(target.describe(rbp), target.describe(rax), 1, -8, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x8d,
		0x84,
		0x05,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// mov eax, [rax] / mov rax, [rax] / movsx eax, byte [rax]
	assert x86_64.load_indirect(target.describe(rax), target.describe(eax), 4) or { panic('the target description has no such name') } == [
		u8(0x8b),
		0x00,
	]
	assert x86_64.load_indirect(target.describe(rax), target.describe(rax), 8) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x8b,
		0x00,
	]
	assert x86_64.load_indirect(target.describe(rax), target.describe(eax), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x0f,
		0xbe,
		0x00,
	]
	// mov [rcx], eax / mov [rcx], al
	assert x86_64.store_indirect(target.describe(rcx), target.describe(eax), 4) or { panic('the target description has no such name') } == [
		u8(0x89),
		0x01,
	]
	assert x86_64.store_indirect(target.describe(rcx), target.describe(eax), 1) or { panic('the target description has no such name') } == [
		u8(0x40),
		0x88,
		0x01,
	]
	// An address the encoding cannot name without a displacement, and a scale
	// that is not a width the machine scales by.
	assert x86_64.load_indirect(target.describe(rbp), target.describe(eax), 4) or { []u8{} }.len == 0
	assert x86_64.address_of_element(target.describe(rbp), target.describe(rax), 3, -8, target.describe(rax)) or { []u8{} }.len == 0
}

// A value two words wide lives in a pair of registers, so the instructions that
// compute one are the ones that say which word they work on: the low word is in
// the result register and the high word in the register above it. Each encoding
// is held to the bytes the machine's own assembler produces for it, the way the
// instructions above are.

// The pair's multiplication needs one instruction the arithmetic beside it does
// not: a two-operand imul, which multiplies one word by another and keeps the low
// word of the answer. It is what the two cross products are made of, and the part
// of each above its low word cannot reach a 128-bit answer.
fn test_the_pairs_multiplication_is_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	rdx := target.reg('rdx') or { panic('the target description has no such name') }
	// imul rax, rcx and imul rdx, rax, as the machine's own assembler writes
	// them: the first register is the one multiplied into, and it is the one in
	// the ModRM reg field.
	assert x86_64.imul_word64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xaf,
		0xc1,
	]
	assert x86_64.imul_word64(target.describe(rdx), target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xaf,
		0xd0,
	]
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	r9 := target.reg('r9') or { panic('the target description has no such name') }
	assert x86_64.imul_word64(target.describe(r8), target.describe(r9)) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x0f,
		0xaf,
		0xc1,
	]
	assert target.multiply_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xaf,
		0xc1,
	]
	assert target.multiply_word(rdx, rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xaf,
		0xd0,
	]
}

fn test_the_wide_arithmetic_is_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	rdx := target.reg('rdx') or { panic('the target description has no such name') }
	// adc rdx, rax and sbb rdx, rax: the high words of an addition and a
	// subtraction, after the low words have gone through add and sub.
	assert x86_64.adc_reg64(target.describe(rdx), target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x11,
		0xc2,
	]
	assert x86_64.sbb_reg64(target.describe(rdx), target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x19,
		0xc2,
	]
	assert x86_64.sub_reg64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x29,
		0xc8,
	]
	// adc rdx, 0, which is the carry into the high word of a two-word negation.
	assert x86_64.adc_immediate(target.describe(rdx), 0) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x81,
		0xd2,
		0,
		0,
		0,
		0,
	]
	// The bitwise operators on one word of the pair, and the test of one word.
	assert x86_64.and_reg64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x21,
		0xc8,
	]
	assert x86_64.or_reg64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x09,
		0xc8,
	]
	assert x86_64.xor_reg64(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x31,
		0xc8,
	]
	assert x86_64.test_reg64(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x85,
		0xc0,
	]
	// The registers past the seventh need the prefix byte, and the destination
	// and the source sit in the two ModRM fields the other way round from each
	// other: the source is in the reg field and the destination in the r/m one.
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	r9 := target.reg('r9') or { panic('the target description has no such name') }
	assert x86_64.adc_reg64(target.describe(r8), target.describe(r9)) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x11,
		0xc8,
	]
	assert x86_64.sbb_reg64(target.describe(r8), target.describe(r9)) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x19,
		0xc8,
	]
	assert x86_64.and_reg64(target.describe(r8), target.describe(r9)) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x21,
		0xc8,
	]
	// The Target forwards each of them, so the emitter reaches them the way it
	// reaches every other instruction.
	assert target.subtract_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x29,
		0xc8,
	]
	assert target.add_with_carry(rdx, rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x11,
		0xc2,
	]
	assert target.add_with_carry_immediate(rdx, 0) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x81,
		0xd2,
		0,
		0,
		0,
		0,
	]
	assert target.subtract_with_borrow(rdx, rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x19,
		0xc2,
	]
	assert target.and_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x21,
		0xc8,
	]
	assert target.or_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x09,
		0xc8,
	]
	assert target.xor_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x31,
		0xc8,
	]
	assert target.test_word(rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x85,
		0xc0,
	]
	// A register that is not a word is refused rather than encoded at the wrong
	// width.
	byte := x86_64.Register{
		name:  'al'
		code:  0
		width: 1
	}
	assert x86_64.adc_reg64(byte, target.describe(rcx)) or { []u8{} }.len == 0
	assert x86_64.adc_reg64(target.describe(rax), byte) or { []u8{} }.len == 0
	assert x86_64.adc_immediate(byte, 1) or { []u8{} }.len == 0
	assert x86_64.sbb_reg64(byte, target.describe(rcx)) or { []u8{} }.len == 0
	assert x86_64.sub_reg64(target.describe(rax), byte) or { []u8{} }.len == 0
	assert x86_64.test_reg64(byte) or { []u8{} }.len == 0
}

fn test_the_wide_shifts_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	rdx := target.reg('rdx') or { panic('the target description has no such name') }
	// shl rax, 3 and shr rdx, 5, which shift one word of the pair each.
	assert x86_64.shl_reg64(target.describe(rax), 3) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xc1,
		0xe0,
		0x03,
	]
	assert x86_64.shr_reg64(target.describe(rdx), 5) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xc1,
		0xea,
		0x05,
	]
	// shld rax, rcx, 3 and shrd rax, rcx, 3: the two registers shifted as one
	// value twice as wide, so the bits that leave one word arrive in the other.
	assert x86_64.shld_immediate(target.describe(rax), target.describe(rcx), 3) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xa4,
		0xc8,
		0x03,
	]
	assert x86_64.shrd_immediate(target.describe(rax), target.describe(rcx), 3) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xac,
		0xc8,
		0x03,
	]
	// The high word of a left shift takes the low word as its source, and 63 is
	// the widest count that is not the whole register.
	assert x86_64.shld_immediate(target.describe(rdx), target.describe(rax), 63) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xa4,
		0xc2,
		0x3f,
	]
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	r9 := target.reg('r9') or { panic('the target description has no such name') }
	assert x86_64.shl_reg64(target.describe(r8), 3) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xc1,
		0xe0,
		0x03,
	]
	assert x86_64.shr_reg64(target.describe(r8), 5) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xc1,
		0xe8,
		0x05,
	]
	assert x86_64.shld_immediate(target.describe(r8), target.describe(r9), 3) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x0f,
		0xa4,
		0xc8,
		0x03,
	]
	assert x86_64.shrd_immediate(target.describe(r8), target.describe(r9), 3) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x0f,
		0xac,
		0xc8,
		0x03,
	]
	// A count as wide as the register is not a shift this machine encodes.
	assert x86_64.shl_reg64(target.describe(rax), 64) or { []u8{} }.len == 0
	assert x86_64.shrd_immediate(target.describe(rax), target.describe(rcx), 64) or { []u8{} }.len == 0
	// A register that is not a word is refused.
	byte := x86_64.Register{
		name:  'al'
		code:  0
		width: 1
	}
	assert x86_64.shl_reg64(byte, 3) or { []u8{} }.len == 0
	assert x86_64.shr_reg64(byte, 3) or { []u8{} }.len == 0
	assert x86_64.shld_immediate(byte, target.describe(rcx), 3) or { []u8{} }.len == 0
	assert x86_64.shrd_immediate(target.describe(rcx), byte, 3) or { []u8{} }.len == 0
	// The Target forwards each of them.
	assert target.shift_left_word(rax, 3) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xc1,
		0xe0,
		0x03,
	]
	assert target.shift_right_word(rdx, 5) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xc1,
		0xea,
		0x05,
	]
	assert target.shift_wide_left(rdx, rax, 63) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xa4,
		0xc2,
		0x3f,
	]
	assert target.shift_wide_right(rax, rcx, 3) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xac,
		0xc8,
		0x03,
	]
}

// The shifts whose count is in CL. Every byte below was taken from `as` and
// objdump for the instruction the test names, so the encodings are held to the
// assembler's reading of them and not to mine.
fn test_a_shift_whose_count_is_in_a_register() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	// shl eax, cl and shl rax, cl: the four-byte form and the word form of one
	// operation, which are the two counts a value of each width is shifted by. The
	// four-byte form is the one whose count the machine reads as five bits.
	assert x86_64.shift_left_narrow(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0xd3),
		0xe0,
	]
	assert x86_64.shift_left_word_register(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xd3,
		0xe0,
	]
	assert x86_64.shift_right_narrow(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0xd3),
		0xe8,
	]
	assert x86_64.shift_right_word_register(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xd3,
		0xe8,
	]
	assert x86_64.shift_right_arithmetic_narrow(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0xd3),
		0xf8,
	]
	assert x86_64.shift_right_arithmetic_register(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xd3,
		0xf8,
	]
	// The register the operation is in reaches past the first eight with a REX
	// prefix, and the four-byte form needs one for that and for nothing else.
	assert x86_64.shift_left_narrow(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x41),
		0xd3,
		0xe0,
	]
	assert x86_64.shift_left_word_register(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xd3,
		0xe0,
	]
	// shld rax, rcx, cl and shrd rax, rcx, cl: the two words shifted as one, with the
	// count in the register.
	assert x86_64.shld_register(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xa5,
		0xc8,
	]
	assert x86_64.shrd_register(target.describe(rax), target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xad,
		0xc8,
	]
	// test cl, 64: the bit of the count that says the count is a word or more.
	assert x86_64.test_byte_immediate(target.describe(rcx), 64) or { panic('the target description has no such name') } == [
		u8(0xf6),
		0xc1,
		0x40,
	]
	// A register narrower than four bytes is not one of these.
	byte := x86_64.Register{
		name:  'al'
		code:  0
		width: 1
	}
	assert x86_64.shift_left_narrow(byte) or { []u8{} }.len == 0
	assert x86_64.shift_left_word_register(byte) or { []u8{} }.len == 0
	assert x86_64.test_byte_immediate(byte, 64) or { []u8{} }.len == 0
}

fn test_the_wide_multiply_and_divide_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	// mul rcx and imul rcx: the product of the result register and the source in
	// the pair, read as unsigned values and as signed ones.
	assert x86_64.mul_reg64(target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xe1,
	]
	assert x86_64.imul_reg64(target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xe9,
	]
	// div rcx and idiv rcx: the pair divided by the source, the quotient back in
	// the result register and the remainder above it.
	assert x86_64.div_reg64(target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xf1,
	]
	assert x86_64.idiv_reg64(target.describe(rcx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xf9,
	]
	// The sign change and the complement, one word of the pair each.
	assert x86_64.neg_reg64(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xd8,
	]
	assert x86_64.not_reg64(target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xd0,
	]
	r8 := target.reg('r8') or { panic('the target description has no such name') }
	assert x86_64.mul_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xe0,
	]
	assert x86_64.imul_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xe8,
	]
	assert x86_64.div_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xf0,
	]
	assert x86_64.idiv_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xf8,
	]
	assert x86_64.neg_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xd8,
	]
	assert x86_64.not_reg64(target.describe(r8)) or { panic('the target description has no such name') } == [
		u8(0x49),
		0xf7,
		0xd0,
	]
	// The Target forwards each of them.
	assert target.multiply_pair(rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xe1,
	]
	assert target.multiply_pair_signed(rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xe9,
	]
	assert target.divide_pair(rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xf1,
	]
	assert target.divide_pair_signed(rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xf9,
	]
	assert target.negate_word(rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xd8,
	]
	assert target.complement_word(rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xf7,
		0xd0,
	]
	// These take one operand, so a register that is not a word is refused.
	byte := x86_64.Register{
		name:  'al'
		code:  0
		width: 1
	}
	assert x86_64.mul_reg64(byte) or { []u8{} }.len == 0
	assert x86_64.imul_reg64(byte) or { []u8{} }.len == 0
	assert x86_64.div_reg64(byte) or { []u8{} }.len == 0
	assert x86_64.idiv_reg64(byte) or { []u8{} }.len == 0
	assert x86_64.neg_reg64(byte) or { []u8{} }.len == 0
	assert x86_64.not_reg64(byte) or { []u8{} }.len == 0
}

fn test_the_unsigned_orders_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	// The four orders that read the carry flag, which are the ones a value two
	// words wide is compared with: setb, setbe, seta and setae.
	below := x86_64.Condition.below
	assert below.code() == u8(0x92)
	assert x86_64.set_condition(.below, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x92,
		0xc0,
	]
	assert x86_64.set_condition(.below_or_equal, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x96,
		0xc0,
	]
	assert x86_64.set_condition(.above, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x97,
		0xc0,
	]
	assert x86_64.set_condition(.above_or_equal, target.describe(rax)) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x93,
		0xc0,
	]
	// setb and then movzx, which is the answer to a comparison as a value of int
	// width. gcc 16.2.1 lowered `p < q` over two unsigned 128-bit values to cmpq,
	// sbbq, setc and movzbl, which is the same reading of the carry flag: the
	// flags come from the subtraction of the pair and not from a comparison of one
	// word.
	assert target.set_condition(.below, rax) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0x92,
		0xc0,
	]
	assert target.widen_byte(rax) or { panic('the target description has no such name') } == [
		u8(0x0f),
		0xb6,
		0xc0,
	]
	// A register with no one-byte name cannot be the destination of a conditional
	// set, and the same refusal stands on the Target.
	rdi := target.reg('rdi') or { panic('the target description has no such name') }
	assert x86_64.set_condition(.below, target.describe(rdi)) or { []u8{} }.len == 0
	assert target.set_condition(.above, rdi) or { []u8{} }.len == 0
	assert target.widen_byte(rdi) or { []u8{} }.len == 0
}

// The single-precision instructions, held to the bytes gas produces for them the
// same way the slot moves are. Each one is its double-precision counterpart with
// the F3 prefix instead of F2, except the comparison, which is Comiss: the same
// instruction as Comisd without the 66 prefix. Measured with
//
//   gcc -c enc.s -o enc.o && objdump -d -M intel enc.o
//
// over `movss`, `addss`, `comiss`, `cvtsi2ss`, `cvttss2si`, `cvtss2sd` and
// `cvtsd2ss`.
fn test_the_float_instructions_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rbp := target.reg('rbp') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	xmm0 := target.float_reg('xmm0') or { panic('the target description has no such name') }
	xmm1 := target.float_reg('xmm1') or { panic('the target description has no such name') }
	// movss xmm0, xmm1
	assert target.move_float(xmm0, xmm1) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x10,
		0xc1,
	]
	// addss xmm0, xmm1
	assert target.float_arithmetic('+', xmm0, xmm1) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x58,
		0xc1,
	]
	// comiss xmm0, xmm1
	assert x86_64.compare_float(target.describe(xmm0), target.describe(xmm1)) or {
		panic('the target description has no such name')
	} == [u8(0x0f), 0x2f, 0xc1]
	// cvtsi2ss xmm0, eax
	assert target.int_to_float(xmm0, eax) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x2a,
		0xc0,
	]
	// cvttss2si eax, xmm0
	assert target.float_to_int(eax, xmm0) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x2c,
		0xc0,
	]
	// cvtss2sd xmm0, xmm1 / cvtsd2ss xmm0, xmm1
	assert target.float_to_double(xmm0, xmm1) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x5a,
		0xc1,
	]
	assert target.double_to_float(xmm0, xmm1) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x0f,
		0x5a,
		0xc1,
	]
	// movss xmm0, [rbp-8] / movss [rbp-8], xmm0
	assert target.load_float_slot(rbp, -8, xmm0) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x10,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	assert target.store_float_slot(rbp, -8, xmm0) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x11,
		0x85,
		0xf8,
		0xff,
		0xff,
		0xff,
	]
	// movss xmm0, [rip+0]
	assert target.load_float_constant(xmm0, 0) or { panic('the target description has no such name') } == [
		u8(0xf3),
		0x0f,
		0x10,
		0x05,
		0x00,
		0x00,
		0x00,
		0x00,
	]
	// negating a float: movq rax, xmm0 / btc eax, 31 / movq xmm0, rax. The middle
	// instruction is the one that says which bit the sign is: the double's form of
	// it is the same two bytes with a REX.W in front and 63 for the bit, and that
	// one flips bit 63 of the register, which a float does not have a sign at.
	assert target.negate_single(xmm0, eax) or { panic('the target description has no such name') } == [
		u8(0x66),
		0x48,
		0x0f,
		0x7e,
		0xc0,
		0x0f,
		0xba,
		0xf8,
		0x1f,
		0x66,
		0x48,
		0x0f,
		0x6e,
		0xc0,
	]
	assert target.negate_double(xmm0, rax) or { panic('the target description has no such name') } == [
		u8(0x66),
		0x48,
		0x0f,
		0x7e,
		0xc0,
		0x48,
		0x0f,
		0xba,
		0xf8,
		0x3f,
		0x66,
		0x48,
		0x0f,
		0x6e,
		0xc0,
	]
}

// The conversion of an unsigned four-byte integer to a double. The signed
// instruction reads the top bit of the integer as a sign and sign-extends, so
// 3000000000u reaches it as -1294967296. The unsigned form clears the upper half
// with a four-byte move and takes the same conversion at eight bytes. The bytes
// are what the machine's own assembler produces for `mov eax, eax / cvtsi2sdq
// %rax, %xmm0`; REX.W comes after the F2 prefix and before the escape.
fn test_an_unsigned_integer_reaches_the_conversion_zero_extended() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	xmm0 := target.float_reg('xmm0') or { panic('the target description has no such name') }
	xmm1 := target.float_reg('xmm1') or { panic('the target description has no such name') }
	// The signed conversion, for contrast: no REX, so the source is four bytes and
	// the top bit is a sign.
	assert x86_64.int_to_double(target.describe(xmm0), target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x0f,
		0x2a,
		0xc0,
	]
	assert x86_64.unsigned_int_to_double(target.describe(xmm0), target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0x89),
		0xc0,
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xc0,
	]
	// A second register pair pins the ModRM fields: ecx is code 1 and xmm1 is 1.
	assert x86_64.unsigned_int_to_double(target.describe(xmm1), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x89),
		0xc9,
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xc9,
	]
	// The same goes through the target, which is the seam the emitter sees.
	assert target.unsigned_int_to_double(xmm0, eax) or { panic('the target description has no such name') } == [
		u8(0x89),
		0xc0,
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xc0,
	]
}

// The conversion of an eight-byte unsigned integer to a double. The signed
// conversion reads the top bit of the whole register as a sign, so a value at or
// above 2^63 reaches it as a negative one. The value is split at that boundary:
// the low bit is folded into the word above it, which brings the magnitude below
// 2^63, and the conversion's result is doubled. The bytes are what the machine
// disassembles to for `test rax,rax / js / cvtsi2sd xmm0,rax / jmp / mov
// rcx,rax / shr rcx,1 / and rax,1 / or rax,rcx / cvtsi2sd xmm0,rax / addsd
// xmm0,xmm0`, with the two jumps as the distances between the three parts. gcc
// 16.2.1 emits the same shape at -O0.
fn test_an_unsigned_word_reaches_the_conversion_by_its_range() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	edx := target.reg('edx') or { panic('the target description has no such name') }
	xmm0 := target.float_reg('xmm0') or { panic('the target description has no such name') }
	xmm1 := target.float_reg('xmm1') or { panic('the target description has no such name') }
	// The signed conversion at eight bytes, for contrast: REX.W is the whole of
	// the difference from the four-byte one.
	assert x86_64.signed_word_to_double(target.describe(xmm0), target.describe(eax)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x48,
		0x0f,
		0x2a,
		0xc0,
	]
	assert x86_64.unsigned_word_to_double(target.describe(xmm0), target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x85,
		0xc0, // test rax,rax
		0x0f,
		0x88,
		0x0a,
		0x00,
		0x00,
		0x00, // js .high, over the five-byte conversion and the five-byte jump
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xc0, // cvtsi2sd xmm0,rax below the boundary
		0xe9,
		0x1a,
		0x00,
		0x00,
		0x00, // jmp .done, over the twenty-six bytes above the boundary
		0x48,
		0x89,
		0xc1, // mov rcx,rax
		0x48,
		0xc1,
		0xe9,
		0x01, // shr rcx,1
		0x48,
		0x81,
		0xe0,
		0x01,
		0x00,
		0x00,
		0x00, // and rax,1
		0x48,
		0x09,
		0xc8, // or rax,rcx
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xc0, // cvtsi2sd xmm0,rax
		0xf2,
		0x0f,
		0x58,
		0xc0, // addsd xmm0,xmm0
	]
	// A second register pair pins the ModRM fields: edx is code 2 and xmm1 is 1.
	assert x86_64.unsigned_word_to_double(target.describe(xmm1), target.describe(edx), target.describe(ecx)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x85,
		0xd2, // test rdx,rdx
		0x0f,
		0x88,
		0x0a,
		0x00,
		0x00,
		0x00,
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xca, // cvtsi2sd xmm1,rdx
		0xe9,
		0x1a,
		0x00,
		0x00,
		0x00,
		0x48,
		0x89,
		0xd1, // mov rcx,rdx
		0x48,
		0xc1,
		0xe9,
		0x01,
		0x48,
		0x81,
		0xe2,
		0x01,
		0x00,
		0x00,
		0x00, // and rdx,1
		0x48,
		0x09,
		0xca, // or rdx,rcx
		0xf2,
		0x48,
		0x0f,
		0x2a,
		0xca, // cvtsi2sd xmm1,rdx
		0xf2,
		0x0f,
		0x58,
		0xc9, // addsd xmm1,xmm1
	]
	// The same goes through the target, which is the seam the emitter sees.
	assert target.unsigned_word_to_double(xmm0, eax, ecx) or { panic('the target description has no such name') } ==
		x86_64.unsigned_word_to_double(target.describe(xmm0), target.describe(eax), target.describe(ecx)) or { panic('the target description has no such name') }
}

// The conversion of a double to an unsigned four-byte integer. The signed
// instruction saturates at 2^31, so 3000000000.0 reaches a four-byte result as
// 2147483648. The unsigned form takes the eight-byte truncation, which holds every
// value a four-byte unsigned type has. The bytes are what the machine's own
// assembler produces for `cvttsd2siq %xmm0, %rax`.
fn test_a_double_converts_to_an_unsigned_integer_at_the_width_it_needs() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	xmm0 := target.float_reg('xmm0') or { panic('the target description has no such name') }
	xmm1 := target.float_reg('xmm1') or { panic('the target description has no such name') }
	// The signed conversion, for contrast.
	assert x86_64.double_to_int(target.describe(eax), target.describe(xmm0)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x0f,
		0x2c,
		0xc0,
	]
	assert x86_64.double_to_unsigned_int(target.describe(eax), target.describe(xmm0)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x48,
		0x0f,
		0x2c,
		0xc0,
	]
	// A second register pair pins the ModRM fields: ecx is code 1 and xmm1 is 1.
	assert x86_64.double_to_unsigned_int(target.describe(ecx), target.describe(xmm1)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x48,
		0x0f,
		0x2c,
		0xc9,
	]
	// The same goes through the target, which is the seam the emitter sees.
	assert target.double_to_unsigned_int(eax, xmm0) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x48,
		0x0f,
		0x2c,
		0xc0,
	]
}

// The conversion of a double to an eight-byte unsigned integer. The signed
// truncation saturates at 2^63, so a double at or above the boundary is split
// there: 2^63 is taken off the double, the difference truncates as a signed value,
// and the bit that was taken off is set again in the integer. 2^63 is a double no
// instruction here carries as an immediate for the floating-point file, so its
// eight bytes are moved in from a general register. The bytes are what the machine
// disassembles to for `movabs rcx,0x43e0000000000000 / movq xmm1,rcx / comisd
// xmm0,xmm1 / jb / subsd xmm0,xmm1 / cvttsd2si rax,xmm0 / bts rax,63 / jmp /
// cvttsd2si rax,xmm0`, with each jump the distance to the next part. gcc 16.2.1
// emits the same shape at -O0.
fn test_a_double_reaches_an_unsigned_word_by_its_range() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	eax := target.reg('eax') or { panic('the target description has no such name') }
	ecx := target.reg('ecx') or { panic('the target description has no such name') }
	edx := target.reg('edx') or { panic('the target description has no such name') }
	xmm0 := target.float_reg('xmm0') or { panic('the target description has no such name') }
	xmm1 := target.float_reg('xmm1') or { panic('the target description has no such name') }
	xmm2 := target.float_reg('xmm2') or { panic('the target description has no such name') }
	// The signed truncation at eight bytes, for contrast: REX.W is the whole of
	// the difference from the four-byte one.
	assert x86_64.double_to_signed_word(target.describe(eax), target.describe(xmm0)) or { panic('the target description has no such name') } == [
		u8(0xf2),
		0x48,
		0x0f,
		0x2c,
		0xc0,
	]
	assert x86_64.double_to_unsigned_word(target.describe(eax), target.describe(xmm0), target.describe(ecx), target.describe(xmm1)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xb9,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0xe0,
		0x43, // movabs rcx,0x43e0000000000000
		0x66,
		0x48,
		0x0f,
		0x6e,
		0xc9, // movq xmm1,rcx
		0x66,
		0x0f,
		0x2f,
		0xc1, // comisd xmm0,xmm1
		0x0f,
		0x82,
		0x13,
		0x00,
		0x00,
		0x00, // jb .low, over the fourteen bytes above the boundary and the jump
		0xf2,
		0x0f,
		0x5c,
		0xc1, // subsd xmm0,xmm1
		0xf2,
		0x48,
		0x0f,
		0x2c,
		0xc0, // cvttsd2si rax,xmm0
		0x48,
		0x0f,
		0xba,
		0xe8,
		0x3f, // bts rax,63
		0xe9,
		0x05,
		0x00,
		0x00,
		0x00, // jmp .done, over the five-byte truncation below the boundary
		0xf2,
		0x48,
		0x0f,
		0x2c,
		0xc0, // cvttsd2si rax,xmm0
	]
	// A second register set pins the ModRM fields and the two jump distances:
	// ecx is 1, edx is 2, xmm1 is 1 and xmm2 is 2.
	assert x86_64.double_to_unsigned_word(target.describe(ecx), target.describe(xmm1), target.describe(edx), target.describe(xmm2)) or { panic('the target description has no such name') } == [
		u8(0x48),
		0xba,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0x00,
		0xe0,
		0x43, // movabs rdx,0x43e0000000000000
		0x66,
		0x48,
		0x0f,
		0x6e,
		0xd2, // movq xmm2,rdx
		0x66,
		0x0f,
		0x2f,
		0xca, // comisd xmm1,xmm2
		0x0f,
		0x82,
		0x13,
		0x00,
		0x00,
		0x00,
		0xf2,
		0x0f,
		0x5c,
		0xca, // subsd xmm1,xmm2
		0xf2,
		0x48,
		0x0f,
		0x2c,
		0xc9, // cvttsd2si rcx,xmm1
		0x48,
		0x0f,
		0xba,
		0xe9,
		0x3f, // bts rcx,63
		0xe9,
		0x05,
		0x00,
		0x00,
		0x00,
		0xf2,
		0x48,
		0x0f,
		0x2c,
		0xc9, // cvttsd2si rcx,xmm1
	]
	// The same goes through the target, which is the seam the emitter sees.
	assert target.double_to_unsigned_word(eax, xmm0, ecx, xmm1) or { panic('the target description has no such name') } ==
		x86_64.double_to_unsigned_word(target.describe(eax), target.describe(xmm0), target.describe(ecx), target.describe(xmm1)) or { panic('the target description has no such name') }
}

fn test_the_dynamic_frame_subtraction_is_the_bytes_that_lower_the_stack() {
	// sub rsp, rax and sub rsp, r11: the stack pointer is the destination and the
	// register holding the size is the source, which is the r/m form of the group
	// opcode. Written out here so a change to the encoding has to be a change to
	// this expectation.
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	r11 := target.reg('r11') or { panic('the target description has no such name') }
	assert target.sub_rsp_register(rax) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x29,
		0xc4,
	]
	assert target.sub_rsp_register(r11) or { panic('the target description has no such name') } == [
		u8(0x4c),
		0x29,
		0xdc,
	]
}

fn test_the_dynamic_stride_multiply_is_the_bytes_that_scale_an_index() {
	// imul rax, rcx / imul r11, r12: the destination is in the reg field and the
	// source in the r/m field, which is the way this two-operand form runs. The
	// multiply a variable-length array's row stride needs is the same one a wide
	// pair's cross products use, so it is the machine's existing encoder.
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	rax := target.reg('rax') or { panic('the target description has no such name') }
	rcx := target.reg('rcx') or { panic('the target description has no such name') }
	r11 := target.reg('r11') or { panic('the target description has no such name') }
	r12 := target.reg('r12') or { panic('the target description has no such name') }
	assert target.multiply_word(rax, rcx) or { panic('the target description has no such name') } == [
		u8(0x48),
		0x0f,
		0xaf,
		0xc1,
	]
	assert target.multiply_word(r11, r12) or { panic('the target description has no such name') } == [
		u8(0x4d),
		0x0f,
		0xaf,
		0xdc,
	]
}

// The external link's command line reaches the driver as the target's own, so
// the loader, the start files and the library directories cannot be one set in
// the in-house image and another in the external link. The system description is
// the source both read: this is that seam, and the linux module's own test is
// where the argument list itself is held to its shape.
fn test_the_external_link_arguments_come_from_the_target() {
	target := lookup('x86_64-linux') or { panic('the target description has no such name') }
	args := target.external_link_arguments(['x.o'], ['/opt/lib'], ['m'], 'out') or {
		panic(err)
	}
	assert args[0] == '-dynamic-linker'
	assert args[1] == target.interpreter
	assert '-L/opt/lib' in args
	assert '-lm' in args
	assert '-lc' in args
	assert 'out' in args
}
