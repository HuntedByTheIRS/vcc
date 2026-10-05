module ast

import types

// A statement carries the part only some statements have behind a pointer, and
// the accessors are the answer for every statement that does not: a return, a
// block, a branch and a loop ask the same questions and get the zero value they
// got when the field sat in the statement. What these pin is that presence of
// the pointer and presence of a value in it are two different things.

fn test_a_statement_with_no_extra_answers_the_zero_value_of_every_field() {
	stmt := Stmt{
		kind: .return_stmt
	}
	assert stmt.resolved().kind == .unknown
	assert stmt.bytes() == 0
	assert stmt.decl_vla_size() == none
	assert stmt.decl_stride() == 0
	assert stmt.deref() == none
	assert stmt.subscript() == none
	assert stmt.case_value() == 0
	assert stmt.label() == ''
	assert stmt.asm_text() == ''
	assert stmt.asm_spelling() == ''
	assert stmt.asm_outputs() == 0
	assert stmt.asm_inputs() == 0
	assert stmt.asm_clobbers().len == 0
}

fn test_a_statement_with_an_extra_answers_what_the_extra_holds() {
	stmt := Stmt{
		kind:  .var_decl
		extra: &StmtExtra{
			resolved:    types.int_type()
			bytes:       8
			decl_stride: 4
		}
	}
	assert stmt.resolved().same(types.int_type())
	assert stmt.bytes() == 8
	assert stmt.decl_stride() == 4
	// The fields the extra did not set are still the zero value: one answer per
	// field and not one answer for the pointer.
	assert stmt.decl_vla_size() == none
	assert stmt.label() == ''
}

fn test_an_extra_that_sets_nothing_answers_the_zero_value() {
	// A case label with no value written and a label with an empty name are
	// shapes the pointer's presence must not turn into something else.
	stmt := Stmt{
		kind:  .case_stmt
		extra: &StmtExtra{}
	}
	assert stmt.case_value() == 0
	assert stmt.label() == ''
	assert stmt.resolved().kind == .unknown
	assert stmt.deref() == none
	assert stmt.asm_clobbers().len == 0
}

fn test_the_label_and_case_accessors_read_their_own_field() {
	labelled := Stmt{
		kind:  .label_stmt
		extra: &StmtExtra{
			label: 'retry'
		}
	}
	assert labelled.label() == 'retry'
	assert labelled.case_value() == 0
	labeled_case := Stmt{
		kind:  .case_stmt
		extra: &StmtExtra{
			case_value: 7
		}
	}
	assert labeled_case.case_value() == 7
	assert labeled_case.label() == ''
}

fn test_the_asm_accessors_read_the_text_the_counts_and_the_clobbers() {
	stmt := Stmt{
		kind:  .asm_stmt
		extra: &StmtExtra{
			asm_text:     'nop'
			asm_spelling: '"nop"'
			asm_outputs:  1
			asm_inputs:   2
			asm_clobbers: ['memory', 'cc']
		}
	}
	assert stmt.asm_text() == 'nop'
	assert stmt.asm_spelling() == '"nop"'
	assert stmt.asm_outputs() == 1
	assert stmt.asm_inputs() == 2
	assert stmt.asm_clobbers() == ['memory', 'cc']
	// The barrier shape: empty text and no operands, which is what the emitter
	// reads to decide the statement is a barrier rather than an instruction.
	barrier := Stmt{
		kind:  .asm_stmt
		extra: &StmtExtra{}
	}
	assert barrier.asm_text() == ''
	assert barrier.asm_spelling() == ''
	assert barrier.asm_outputs() == 0 && barrier.asm_inputs() == 0
	assert barrier.asm_clobbers().len == 0
}

fn test_the_deref_and_the_subscript_of_an_assignment_are_carried() {
	stmt := Stmt{
		kind:  .assign
		extra: &StmtExtra{
			deref: Unary{
				op:   '*'
				expr: Expr(Ident{
					name: 'p'
				})
			}
		}
	}
	deref := stmt.deref() or {
		assert false
		return
	}
	assert deref is Unary
	assert (deref as Unary).op == '*'
	assert stmt.subscript() == none
	// A statement that carries one dereference still answers zero for every
	// field it does not carry.
	assert stmt.bytes() == 0
	assert stmt.label() == ''
}

fn test_the_vla_size_and_the_stride_are_read_off_the_extra() {
	size := Expr(IntLit{
		value: 12
		text:  '12'
	})
	stmt := Stmt{
		kind:  .var_decl
		extra: &StmtExtra{
			decl_vla_size: size
			decl_stride:   4
		}
	}
	vla := stmt.decl_vla_size() or {
		assert false
		return
	}
	assert vla is IntLit
	assert (vla as IntLit).value == 12
	assert stmt.decl_stride() == 4
}

// boxed is where a statement puts a member it read while the frame was open: the
// 376-byte node is written into the heap rather than pointed at where it lies.
// The copy has to carry the option members as well as the plain ones, because a
// Field holds the base expression for a member read through a value.
fn test_a_boxed_field_is_a_copy_in_the_heap_and_not_an_alias() {
	field := Field{
		name:   'a'
		offset: 8
	}
	mut box := field.boxed()
	assert box.name == 'a'
	assert box.offset == 8
	// A second box holds the same content; the two are separate allocations,
	// which is the shape that lets each one outlive the frame the field was read
	// in rather than both pointing at where the local lies.
	other := field.boxed()
	assert other.offset == 8
	assert other.name == 'a'
	unsafe {
		assert voidptr(box) != voidptr(other)
	}
}

fn test_a_boxed_field_keeps_the_base_expression_and_the_bit_widths() {
	field := Field{
		name:            'm'
		base:            Expr(Ident{
			name: 's'
		})
		bitfield:        true
		bit_offset:      3
		bit_width:       5
		unit_width:      4
		through_pointer: true
	}
	box := field.boxed()
	assert box.bitfield && box.bit_offset == 3 && box.bit_width == 5
	assert box.unit_width == 4
	assert box.through_pointer
	base := box.base or {
		assert false
		return
	}
	assert base is Ident
	assert (base as Ident).name == 's'
}
