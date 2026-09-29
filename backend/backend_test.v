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
