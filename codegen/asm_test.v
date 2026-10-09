module codegen

import ast
import os
import parser
import time
import tokenize

// A statement-level GNU asm has three shapes here and they are not the same: the
// `"memory"` barrier, which does nothing the compiler can see and is emitted as
// nothing; the 128-bit divide, whose dividend is the pair rdx:rax; and the 128-bit
// multiply-add, whose three instructions are one template. Each test below reads its
// shape through the parser and then runs the emitter and the program it wrote,
// because the decision belongs to the emitter and a parse that only produced a node
// would not show which register a value was placed in.
//
// The numbers the programs answer are what gcc makes of the same sources, measured
// with `gcc -O0` on the machine this was written on. The value is the point: an
// instruction emitted with its operands in the wrong registers still compiles and
// still runs, and the number it computes is the only thing that says otherwise.
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

// test_the_divide_is_emitted_with_the_dividend_in_the_pair reads V's own
// `bits.div_64` shape. `div` divides the pair rdx:rax by its operand, so the two
// inputs whose constraints are `d` and `a` are the dividend's halves and the two
// outputs say where the quotient and the remainder are written.
//
// The program answers 67 for `divide(0, 100, 7) + divide(1, 5, 2)`. The second call
// is the one the pair is for: its quotient is past what 32 bits hold, so only a
// dividend whose high half reached rdx produces it.
fn test_the_divide_is_emitted_with_the_dividend_in_the_pair() {
	unit := asm_unit('unsigned long divide(unsigned long hi, unsigned long lo, unsigned long y) {\n\tunsigned long quo = 0;\n\tunsigned long rem = 0;\n\t__asm__ (\n\t\t"div %[y]"\n\t\t: [quo] "=a" (quo),\n\t\t  [rem] "=d" (rem)\n\t\t: [hi] "d" (hi),\n\t\t  [lo] "a" (lo),\n\t\t  [y] "r" (y)\n\t\t: "cc"\n\t);\n\treturn (quo >> 60) * 8 + rem;\n}\nint main(void) { return (int)(divide(0, 100, 7) + divide(1, 5, 2)); }')
	assert unit.decls[0].body[2].kind == .asm_stmt
	assert unit.decls[0].body[2].asm_outputs() == 2
	assert unit.decls[0].body[2].asm_inputs() == 3
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	assert asm_run(emitted.bytes) == 67
}

// test_the_multiply_is_emitted_with_the_pair_in_rdx_and_rax reads the `mulq %%rdx`
// shape: the machine multiplies rax by the register the text names and leaves the
// low half of the product in rax and the high half in rdx. The program answers 270
// for `multiply(max, max) + multiply(3, 5)`, whose first call has both halves of the
// product non-zero and whose second has all of it in rax.
fn test_the_multiply_is_emitted_with_the_pair_in_rdx_and_rax() {
	unit := asm_unit('unsigned long multiply(unsigned long x, unsigned long y) {\n\tunsigned long lo = 0;\n\tunsigned long hi = 0;\n\t__asm__ (\n\t\t"mulq %%rdx"\n\t\t: [lo] "=a" (lo),\n\t\t  [hi] "=d" (hi)\n\t\t: [x] "a" (x),\n\t\t  [y] "d" (y)\n\t\t: "cc"\n\t);\n\treturn (lo & 0xf) * 16 + (hi & 0xf);\n}\nint main(void) { return (int)(multiply(0xFFFFFFFFFFFFFFFFUL, 0xFFFFFFFFFFFFFFFFUL) + multiply(3, 5)); }')
	assert unit.decls[0].body[2].kind == .asm_stmt
	assert unit.decls[0].body[2].asm_text() == 'mulq %%rdx'
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	// 270 is what the two calls make; a process exit code is one byte, so the
	// assertion is that number modulo 256.
	assert asm_run(emitted.bytes) == 270 % 256
}

// test_the_multiply_add_is_emitted_with_its_three_instructions reads V's own
// `bits.mul_add_64`, whose instruction text is three adjacent string literals and
// therefore one template. The carry the addition leaves is added into the high half,
// which is what makes the shape more than a multiply with a store at the end.
//
// The program answers 163 for `multiply_add(max, 3, 7) + multiply_add(0, 5, 6)`. In
// the first call the addition carries out of the low half, so the high half is three
// rather than the two the product has; an emitter that dropped the carry answers 162.
fn test_the_multiply_add_is_emitted_with_its_three_instructions() {
	unit := asm_unit('unsigned long multiply_add(unsigned long x, unsigned long y, unsigned long z) {\n\tunsigned long lo = 0;\n\tunsigned long hi = 0;\n\t__asm__ (\n\t\t"mulq %%rdx\\n\\t"\n\t\t"addq %[z], %%rax\\n\\t"\n\t\t"adcq $0, %%rdx\\n\\t"\n\t\t: [lo] "=a" (lo),\n\t\t  [hi] "=d" (hi)\n\t\t: [x] "a" (x),\n\t\t  [y] "d" (y),\n\t\t  [z] "r" (z)\n\t\t: "cc"\n\t);\n\treturn (lo & 0xf) * 16 + (hi & 0xf);\n}\nint main(void) { return (int)(multiply_add(0xFFFFFFFFFFFFFFFFUL, 3, 7) + multiply_add(0, 5, 6)); }')
	assert unit.decls[0].body[2].kind == .asm_stmt
	assert unit.decls[0].body[2].asm_text() == 'mulq %%rdx\n\taddq %[z], %%rax\n\tadcq $0, %%rdx\n\t'
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 0
	assert asm_run(emitted.bytes) == 163
}

// test_an_asm_shape_this_back_end_does_not_place_is_refused_by_name reads a divide
// written with the wrong operands: `div` needs the dividend in the pair and the
// divisor in a register of the compiler's choosing, and this template asks for
// neither. It is refused with its text and its location rather than emitted with the
// registers guessed, and nothing is written.
fn test_an_asm_shape_this_back_end_does_not_place_is_refused_by_name() {
	unit := asm_unit('int main(void) {\n\tint q = 1;\n\t__asm__ ("div %[y]" : [q] "=a" (q) : [y] "r" (q));\n\treturn q;\n}')
	assert unit.decls[0].body[1].kind == .asm_stmt
	assert unit.decls[0].body[1].asm_text() == 'div %[y]'
	emitted := emit(unit, Options{})
	assert emitted.diagnostics.len == 1
	assert !emitted.diagnostics[0].warning
	assert emitted.diagnostics[0].line == 3
	assert emitted.diagnostics[0].msg.contains('div %[y]')
	assert emitted.bytes.len == 0
}
