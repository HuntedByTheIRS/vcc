module parser

import ast
import decimal
import tokenize

// The rows below are measured on gcc 16.2.1, by writing the operation on the
// literals themselves and printing the bytes of the object gcc compiled, most
// significant byte first, the order the reader's own rows are written in. gcc's
// front end evaluates such an expression while it compiles, so the program
// stores the result rather than the expression, and the result's exponent is not
// always the one a run-time routine would leave: `1.0dd / 2.0dd` is the
// coefficient 5 at a power of minus one rather than the wide coefficient the
// division scales to, and a zero from a cancellation carries the smaller of the
// two powers, so `1e7df - 1e7df` is a zero at a power of seven and not the plain
// zero. The bytes are what accepts the fold, because a value one exponent off
// prints the same number at a different encoding.

// folded_parse reads a source string to a unit, the parser's own entry over the
// lexer, without a preprocessor in front of it.
fn folded_parse(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// folded_decimal parses a declaration whose initializer is a decimal expression
// and reports the bytes of the value the folder left there, most significant
// byte first. It fails the test when the parser refuses the program or the
// initializer is not the folded constant, which is what an unfolded operation
// leaves behind.
fn folded_decimal(type_name string, expr string) string {
	source := 'int main(void) { ${type_name} r = ${expr}; }'
	result := folded_parse(source)
	assert result.diagnostics.len == 0, '${source} was refused'
	stmt := result.unit.decls[0].body[0]
	init := stmt.init or {
		assert false, '${source} has no initializer'
		return ''
	}
	if init is ast.Binary {
		assert false, '${expr} was not folded: it is still the operation'
	}
	lit := init as ast.FloatLit
	value := lit.decimal_value
	bytes := decimal.encode(value.value(), value.decimal_format())
	mut out := ''
	for i := bytes.len - 1; i >= 0; i-- {
		out += '${bytes[i]:02x}'
	}
	return out
}

struct FoldedRow {
	kind string
	expr string
	word string
}

fn test_a_folded_decimal_operation_keeps_the_bytes_gcc_writes() {
	rows := [
		// _Decimal32.
		FoldedRow{'df', '1.0df + 2.0df', '3200001e'},
		FoldedRow{'df', '1.0df - 2.0df', 'b200000a'},
		FoldedRow{'df', '1.0df * 2.0df', '318000c8'},
		FoldedRow{'df', '1.0df / 2.0df', '32000005'},
		FoldedRow{'df', '100.0df / 2.0df', '32800032'},
		// The operand is the value as it is stored, so 1e96df is the padded
		// coefficient 1000000 at a power of 90 and the product keeps that shape.
		FoldedRow{'df', '1e96df * 1e-7df', '5c0f4240'},
		// A zero from a cancellation carries the smaller power of ten.
		FoldedRow{'df', '1e7df - 1e7df', '36000000'},
		// Underflow, overflow and the two specials.
		FoldedRow{'df', '1e-101df * 1e-7df', '00000000'},
		FoldedRow{'df', '1e96df * 1e96df', '78000000'},
		FoldedRow{'df', '0.0df / 0.0df', '7c000000'},
		FoldedRow{'df', '1.0df / 0.0df', '78000000'},
		// _Decimal64.
		FoldedRow{'dd', '1.0dd + 2.0dd', '31a000000000001e'},
		FoldedRow{'dd', '1.0dd / 2.0dd', '31a0000000000005'},
		FoldedRow{'dd', '100.0dd / 2.0dd', '31c0000000000032'},
		FoldedRow{'dd', '1e10dd / 2e0dd', '32e0000000000005'},
		// A repeating quotient is rounded to the format's digits, and its
		// exponent follows the magnitude, not the division's preference.
		FoldedRow{'dd', '1.0dd / 3.0dd', '2fcbd7a625405555'},
		FoldedRow{'dd', '1e-398dd - 1e-398dd', '0000000000000000'},
		FoldedRow{'dd', '1e-398dd * 1e-398dd', '0000000000000000'},
		FoldedRow{'dd', '1e384dd * 1e384dd', '7800000000000000'},
		FoldedRow{'dd', '1e384dd * 1e-320dd', '37e38d7ea4c68000'},
		// _Decimal128.
		FoldedRow{'dl', '1.0dl + 2.0dl', '303e000000000000000000000000001e'},
		FoldedRow{'dl', '1.0dl / 2.0dl', '303e0000000000000000000000000005'},
		FoldedRow{'dl', '1e30dl * 1e30dl', '30b80000000000000000000000000001'},
		FoldedRow{'dl', '1e6144dl * 1e6144dl', '78000000000000000000000000000000'},
		FoldedRow{'dl', '1e-6176dl * 1e-6176dl', '00000000000000000000000000000000'},
		FoldedRow{'dl', '1e-6176dl - 1e-6176dl', '00000000000000000000000000000000'},
	]
	for row in rows {
		type_name := match row.kind {
			'df' { '_Decimal32' }
			'dd' { '_Decimal64' }
			else { '_Decimal128' }
		}
		got := folded_decimal(type_name, row.expr)
		assert got == row.word, '${row.expr} folded to ${got}, gcc writes ${row.word}'
	}
}

// folded_comparison parses a declaration whose initializer is a comparison of two
// decimal constants and reports the int the folder left there, which is the
// answer gcc's front end gives.
fn folded_comparison(expr string) i64 {
	source := 'int main(void) { int r = ${expr}; }'
	result := folded_parse(source)
	assert result.diagnostics.len == 0, '${source} was refused'
	stmt := result.unit.decls[0].body[0]
	init := stmt.init or {
		assert false, '${source} has no initializer'
		return 0
	}
	if init is ast.Binary {
		assert false, '${expr} was not folded: it is still the comparison'
	}
	return (init as ast.IntLit).value
}

fn test_a_folded_decimal_comparison_is_the_answer_gcc_gives() {
	rows := [
		// The six comparisons over ordered constants.
		'1.0dd == 1.0dd 1',
		'1.0dd != 1.0dd 0',
		'1.0dd < 2.0dd 1',
		'2.0dd <= 2.0dd 1',
		'3.0dd > 2.0dd 1',
		'2.0dd >= 2.0dd 1',
		'1.0dd == 2.0dd 0',
		'1.0dd != 2.0dd 1',
		'2.0dd < 1.0dd 0',
		'1.0dd <= 0.5dd 0',
		'1.0dd > 2.0dd 0',
		'1.0dd >= 2.0dd 0',
		// A zero is ordered against the other value's sign, so a zero is greater
		// than a negative and less than a positive whichever sign it carries.
		'0.0dd < -1.0dd 0',
		'-1.0dd < 0.0dd 1',
		'0.0dd > -1.0dd 1',
		'-1.0dd >= 0.0dd 0',
		'0.0df < -1.0df 0',
		'-1.0df < 0.0df 1',
		'0.0dl < -1.0dl 0',
		'-1.0dl < 0.0dl 1',
		// A decimal constant compares by value, not by its stored form.
		'1.5dd == 15e-1dd 1',
		'1.5dd < 1.6dd 1',
	]
	for row in rows {
		expr := row.all_before_last(' ')
		want := row.all_after_last(' ').i64()
		got := folded_comparison(expr)
		assert got == want, '${expr} folded to ${got}, gcc gives ${want}'
	}
}

// An operation the folder cannot evaluate keeps its operation in the tree, where
// the back end refuses a decimal value it has no form for by name rather than
// emitting a call to a routine that does not exist. A mix of two widths is one
// such operation: the folder evaluates only an operation whose operands are
// constants of one format, so this is still a binary expression.
fn test_an_operation_without_one_decimal_format_is_not_folded() {
	source := 'int main(void) { _Decimal64 r = 1.0df + 1.0dd; }'
	result := folded_parse(source)
	if result.diagnostics.len > 0 {
		return
	}
	init := result.unit.decls[0].body[0].init or {
		assert false, '${source} has no initializer'
		return
	}
	assert init is ast.Binary, '${source} folded an operation of two formats'
}
