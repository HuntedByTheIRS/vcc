module backend

import backend.arch
import backend.os

// The machine and the system are written by hand in two files that do not know
// about each other, which is the point of the split and also its one hazard: a
// syscall that names a register the machine does not have is a typo nothing else
// would catch, because the names are strings on both sides. These tests are where
// the two descriptions are held to each other.

fn test_the_machine_and_the_system_name_the_same_registers() {
	target := lookup('x86_64-linux') or { panic(err) }
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
	code := lookup('x86_64-linux') or { panic(err) }.exit_sequence(7) or { panic(err) }
	expected := [u8(0xbf), 7, 0, 0, 0, u8(0xb8), 60, 0, 0, 0, 0x0f, 0x05]
	assert code == expected
}

fn test_a_system_that_does_not_know_a_machine_answers_nothing() {
	// An empty table is how the emitter finds out that the combination is not
	// described yet. Falling back to another machine's numbers would be a wrong
	// program rather than a refusal.
	assert os.syscalls('z80').len == 0
	assert os.syscall_args_regs('z80').len == 0
}

fn test_the_encoder_refuses_a_register_it_cannot_name() {
	wide := arch.Register{
		name:      'rax'
		wide_name: 'rax'
		code:      0
		width:     8
		call_arg:  -1
	}
	encoded := arch.mov_imm32(wide, 1) or { []u8{} }
	assert encoded.len == 0
}

fn test_a_target_with_no_syscalls_refuses_to_exit() {
	// A table that got emptied or renamed has to stop the emitter, not emit a
	// trap with whatever happened to be in the register.
	empty := Target{
		name:         'nothing-nothing'
		exit_syscall: 'exit'
	}
	code := empty.exit_sequence(1) or { []u8{} }
	assert code.len == 0
}

// The instructions a function body is made of. An encoding that is wrong is a
// wrong program rather than a wrong answer, so each one is held to the bytes the
// machine's own assembler produces for it.
fn test_the_slot_moves_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic(err) }
	rbp := target.reg('rbp') or { panic(err) }
	eax := target.reg('eax') or { panic(err) }
	edi := target.reg('edi') or { panic(err) }
	// load eax, [rbp-8] / load rax, [rbp-8]
	assert arch.load_slot(rbp, -8, eax, 4) or { panic(err) } == [u8(0x8b), 0x85, 0xf8, 0xff, 0xff,
		0xff]
	assert arch.load_slot(rbp, -8, eax, 8) or { panic(err) } == [u8(0x48), 0x8b, 0x85, 0xf8, 0xff,
		0xff, 0xff]
	// mov [rbp-8], eax / mov [rbp-8], rax
	assert arch.store_slot(rbp, -8, eax, 4) or { panic(err) } == [u8(0x89), 0x85, 0xf8, 0xff, 0xff,
		0xff]
	assert arch.store_slot(rbp, -8, eax, 8) or { panic(err) } == [u8(0x48), 0x89, 0x85, 0xf8, 0xff,
		0xff, 0xff]
	// A register the low three bits cannot name and a wide move of it, which is
	// how a pointer parameter arrives in the frame.
	assert arch.load_slot(rbp, -8, edi, 4) or { panic(err) } == [u8(0x8b), 0xbd, 0xf8, 0xff, 0xff,
		0xff]
	assert arch.store_slot(rbp, -8, edi, 8) or { panic(err) } == [u8(0x48), 0x89, 0xbd, 0xf8, 0xff,
		0xff, 0xff]
	// A width that is neither an int nor a pointer is refused: a char slot moved
	// at four bytes would read a neighbour.
	assert arch.load_slot(rbp, -8, eax, 1) or { []u8{} }.len == 0
}

fn test_the_frame_instructions_are_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic(err) }
	// sub rsp, 32, and the immediate is where the emitter will fill the size in
	assert arch.frame_reserve(32) == [u8(0x48), 0x81, 0xec, 0x20, 0x00, 0x00, 0x00]
	assert arch.frame_reserve_immediate == 3
	// mov rsp, rbp; pop rbp; ret
	assert arch.frame_epilogue() == [u8(0x48), 0x89, 0xec, 0x5d, 0xc3]
	assert target.frame_immediate_offset() == 3
}

fn test_the_arithmetic_is_the_bytes_the_machine_reads() {
	target := lookup('x86_64-linux') or { panic(err) }
	eax := target.reg('eax') or { panic(err) }
	ecx := target.reg('ecx') or { panic(err) }
	assert arch.add_reg32(eax, ecx) or { panic(err) } == [u8(0x01), 0xc8]
	assert arch.sub_reg32(eax, ecx) or { panic(err) } == [u8(0x29), 0xc8]
	assert arch.imul_reg32(eax, ecx) or { panic(err) } == [u8(0x0f), 0xaf, 0xc1]
	// cdq then idiv ecx, which is the pair a signed division is
	assert arch.cdq() == [u8(0x99)]
	assert arch.idiv_reg32(ecx) or { panic(err) } == [u8(0xf7), 0xf9]
	assert arch.neg_reg32(eax) or { panic(err) } == [u8(0xf7), 0xd8]
	assert arch.not_reg32(eax) or { panic(err) } == [u8(0xf7), 0xd0]
}

fn test_a_comparison_becomes_a_zero_or_a_one_in_the_register() {
	target := lookup('x86_64-linux') or { panic(err) }
	eax := target.reg('eax') or { panic(err) }
	ecx := target.reg('ecx') or { panic(err) }
	// cmp eax, ecx then setcc al then movzx eax, al, which is every comparison
	// the language has: the order is the one that changes.
	assert arch.test_reg32(eax) or { panic(err) } == [u8(0x85), 0xc0]
	assert arch.cmp_reg32(eax, ecx) or { panic(err) } == [u8(0x39), 0xc8]
	assert arch.set_condition(.equal, eax) or { panic(err) } == [u8(0x0f), 0x94, 0xc0]
	assert arch.set_condition(.not_equal, eax) or { panic(err) } == [u8(0x0f), 0x95, 0xc0]
	assert arch.set_condition(.less, eax) or { panic(err) } == [u8(0x0f), 0x9c, 0xc0]
	assert arch.set_condition(.greater, eax) or { panic(err) } == [u8(0x0f), 0x9f, 0xc0]
	assert arch.set_condition(.less_or_equal, eax) or { panic(err) } == [u8(0x0f), 0x9e, 0xc0]
	assert arch.set_condition(.greater_or_equal, eax) or { panic(err) } == [u8(0x0f), 0x9d, 0xc0]
	assert arch.movzx_byte(eax) or { panic(err) } == [u8(0x0f), 0xb6, 0xc0]
	// The whole shape the emitter asks for, and the operator spelled the way the
	// language spells it.
	assert target.compare('<=', eax, ecx) or { panic(err) } == [u8(0x39), 0xc8, 0x0f, 0x9e, 0xc0,
		0x0f, 0xb6, 0xc0]
	assert target.compare('<<', eax, ecx) or { []u8{} }.len == 0
	// Only the first four registers have a one-byte name a conditional set can
	// write, so anything else is refused rather than encoded at the wrong width.
	edi := target.reg('edi') or { panic(err) }
	assert arch.set_condition(.equal, edi) or { []u8{} }.len == 0
}

fn test_the_jumps_are_the_bytes_the_machine_reads() {
	assert arch.jump_rel32(16) == [u8(0xe9), 0x10, 0x00, 0x00, 0x00]
	assert arch.jump_zero_rel32(16) == [u8(0x0f), 0x84, 0x10, 0x00, 0x00, 0x00]
	assert arch.jump_nonzero_rel32(16) == [u8(0x0f), 0x85, 0x10, 0x00, 0x00, 0x00]
	target := lookup('x86_64-linux') or { panic(err) }
	assert target.jump(-4) == [u8(0xe9), 0xfc, 0xff, 0xff, 0xff]
}
