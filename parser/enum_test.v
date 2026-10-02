module parser

import ast
import tokenize

// An enumeration is a list of names the reader turns into integer constants, and
// every number here is the one gcc 16.2.1 gives the same list: `enum { A, B, C };
// is 0, 1, 2, `= -3` is minus three, and a value computed out of `?:` and shifts
// is the computed number, which is how a library header builds the masks a
// program compares against. The values are read back the way a program reads
// them, from a use of the name, because a use of an enumerator is the number and
// not a read of an object.

// enum_read parses a unit a test writes out.
fn enum_read(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// enum_use is the number a use of `name` stands for: the unit is the definitions
// followed by a body that returns the name, and the node the reader built must be
// the literal itself, which is what makes the enumerator a constant expression.
fn enum_use(definitions string, name string) i64 {
	result := enum_read('${definitions}
int main(void) { return ${name}; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[0].expr or {
		assert false
		return 0
	}
	assert expr is ast.IntLit
	return (expr as ast.IntLit).value
}

fn test_an_enum_with_no_values_counts_from_zero() {
	definitions := 'enum { A, B, C };'
	assert enum_use(definitions, 'A') == 0
	assert enum_use(definitions, 'B') == 1
	assert enum_use(definitions, 'C') == 2
}

fn test_an_enum_value_carries_forward() {
	definitions := 'enum { A = 10, B, C = 2, D };'
	assert enum_use(definitions, 'A') == 10
	assert enum_use(definitions, 'B') == 11
	assert enum_use(definitions, 'C') == 2
	assert enum_use(definitions, 'D') == 3
}

// A trailing comma before the closing brace is the C99 licence the corpus's own
// enum exercises, so the list must read to the end and stop.
fn test_a_trailing_comma_ends_the_list() {
	definitions := 'enum c99_small { SMALL_ONE = 1, SMALL_TWO, SMALL_THREE, };'
	assert enum_use(definitions, 'SMALL_ONE') == 1
	assert enum_use(definitions, 'SMALL_TWO') == 2
	assert enum_use(definitions, 'SMALL_THREE') == 3
}

fn test_an_enum_value_is_an_integer_constant_expression() {
	definitions := 'enum c99_neg { NEG_MIN = -3, NEG_ZERO = 0, NEG_POS = 3 };
enum c99_big { BIG = 65535 };'
	assert enum_use(definitions, 'NEG_MIN') == -3
	assert enum_use(definitions, 'NEG_ZERO') == 0
	assert enum_use(definitions, 'NEG_POS') == 3
	assert enum_use(definitions, 'BIG') == 65535
}

fn test_an_enum_value_may_be_computed() {
	definitions := 'enum { SHIFT = (1 << 2) << 8, MASK = SHIFT | 1, NEG = -SHIFT };'
	assert enum_use(definitions, 'SHIFT') == 1024
	assert enum_use(definitions, 'MASK') == 1025
	assert enum_use(definitions, 'NEG') == -1024
}

// The list glibc's ctype.h writes, whose members are the masks a program tests a
// table lookup against. These are the numbers gcc 16.2.1 computes for the same
// list, so a header read here answers the same as a header read by gcc.
fn test_the_ctype_masks_are_the_masks_gcc_computes() {
	// `_ISbit(or)` is `(or) < 8 ? ((1 << (or)) << 8) : ((1 << (or)) >> 8)`, and
	// the indices are glibc's own: _ISupper is 0 and _ISblank is 8, so the two
	// arms of the conditional are both exercised.
	definitions := 'enum {
	_ISupper = (((0) < 8) ? ((1 << (0)) << 8) : ((1 << (0)) >> 8)),
	_ISlower = (((1) < 8) ? ((1 << (1)) << 8) : ((1 << (1)) >> 8)),
	_ISalpha = (((2) < 8) ? ((1 << (2)) << 8) : ((1 << (2)) >> 8)),
	_ISblank = (((8) < 8) ? ((1 << (8)) << 8) : ((1 << (8)) >> 8)),
	_ISpunct = (((10) < 8) ? ((1 << (10)) << 8) : ((1 << (10)) >> 8)),
	_ISalnum = (((11) < 8) ? ((1 << (11)) << 8) : ((1 << (11)) >> 8)),
};'
	assert enum_use(definitions, '_ISupper') == 256
	assert enum_use(definitions, '_ISlower') == 512
	assert enum_use(definitions, '_ISalpha') == 1024
	assert enum_use(definitions, '_ISblank') == 1
	assert enum_use(definitions, '_ISpunct') == 4
	assert enum_use(definitions, '_ISalnum') == 8
}

// The bound of an array is an integer constant expression, so an enumerator used
// as one is the number and not a read of an object, and the declaration is read
// with no diagnostic to answer for.
fn test_a_use_of_an_enumerator_is_a_constant() {
	result := enum_read('enum { ROWS = 2, COLS = 3 };
int main(void) { int column[COLS]; return ROWS; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	assert (expr as ast.IntLit).value == 2
}

// A name that is not an enumeration constant is left alone: an ordinary object is
// still an object, so the reader is not turning every name into a number.
fn test_an_ordinary_name_is_not_an_enumeration_constant() {
	result := enum_read('int main(void) { int x = 1; return x; }')
	assert result.diagnostics.len == 0
	expr := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	assert expr is ast.Ident
}

// A value the reader cannot compute is refused by name rather than guessed, so a
// header whose mask is built from an expression this compiler has not learned
// says so instead of answering a wrong mask.
fn test_an_uncomputable_value_is_refused() {
	result := enum_read('int s;
enum { A = s };
int main(void) { return A; }')
	assert result.diagnostics.len >= 1
	assert result.diagnostics[0].msg.contains('is not an integer constant expression')
}
