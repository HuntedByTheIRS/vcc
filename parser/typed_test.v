module parser

import ast
import tokenize
import types

// The typed tree: what the reader resolved each node to, checked one construct at
// a time. A node the model has no answer for carries the zero type and no
// diagnostic, which is what makes the difference between a construct this
// milestone has not reached and a declaration that is wrong.

fn parsed(source string) Result {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	result := parse(lexed.tokens)
	return result
}

fn checked(source string) Result {
	result := parsed(source)
	assert result.diagnostics.len == 0
	return result
}

fn first(source string) ast.FnDecl {
	result := checked(source)
	assert result.unit.decls.len == 1
	return result.unit.decls[0]
}

fn test_a_definition_carries_its_return_type_and_its_function_type() {
	decl := first('int add(int a, int b) { return a + b; }')
	assert decl.ret == 'int'
	assert decl.ret_type.same(types.int_type())
	// The name denotes the function: the return type and the parameters
	// together, which is what a declaration of the same function must agree with
	// and what a call is checked against.
	assert decl.resolved.kind == .function
	assert decl.resolved.describe() == 'int (int, int)'
	assert decl.params.len == 2
	assert decl.params[0].name == 'a'
	assert decl.params[0].resolved.same(types.int_type())
	assert decl.params[1].name == 'b'
	assert decl.params[1].resolved.same(types.int_type())
}

fn test_a_parameter_is_declared_in_the_body_it_belongs_to() {
	decl := first('int add(int a, int b) { return a + b; }')
	body := decl.body
	assert body.len == 1
	returned := body[0].expr or {
		assert false
		return
	}
	sum := returned as ast.Binary
	assert sum.op == '+'
	assert sum.typ.same(types.int_type())
	left := sum.left as ast.Ident
	assert left.name == 'a'
	assert left.typ.same(types.int_type())
	right := sum.right as ast.Ident
	assert right.name == 'b'
	assert right.typ.same(types.int_type())
}

fn test_a_local_declaration_carries_the_type_it_declared() {
	result := checked('int main() { int x = 1; char c = 97; return x + c; }')
	body := result.unit.decls[0].body
	assert body.len == 3
	assert body[0].kind == .var_decl
	assert body[0].decl_name == 'x'
	assert body[0].resolved.same(types.int_type())
	assert body[1].kind == .var_decl
	assert body[1].decl_name == 'c'
	assert body[1].resolved.same(types.char_type())
	// `x + c` converts both to int, and neither operand keeps its own type.
	returned := body[2].expr or {
		assert false
		return
	}
	sum := returned as ast.Binary
	assert sum.typ.same(types.int_type())
	assert (sum.left as ast.Ident).typ.same(types.int_type())
	assert (sum.right as ast.Ident).typ.same(types.char_type())
}

fn test_an_inner_declaration_hides_an_outer_one_and_the_outer_one_comes_back() {
	// The block is a scope: the x the second return reads is the one declared in
	// the block while the block is open, and the one outside it afterwards.
	result := checked('int main() { int x = 1; { char x = 97; } return x; }')
	body := result.unit.decls[0].body
	assert body.len == 3
	inner := body[1]
	assert inner.kind == .block
	assert inner.body.len == 1
	assert inner.body[0].decl_name == 'x'
	assert inner.body[0].resolved.same(types.char_type())
	returned := body[2].expr or {
		assert false
		return
	}
	assert (returned as ast.Ident).typ.same(types.int_type())
}

fn test_a_declaration_reads_the_names_declared_before_it() {
	// One pass: the name is typed where it is read, so a use the reader has not
	// met a declaration for is unresolved rather than guessed at. The name is
	// declared after the function that reads it, which is what keeps the file
	// compilable at all: a name nothing in the file declares is refused once the
	// unit has been read.
	result := checked('int main() { return later; }\nint later;')
	returned := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (returned as ast.Ident).typ.kind == .unknown
}

fn test_the_type_of_an_expression_is_the_type_its_operators_give_it() {
	result := checked('int main() { return -1 + 2 * 3; }')
	returned := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	sum := returned as ast.Binary
	assert sum.op == '+'
	assert sum.typ.same(types.int_type())
	negative := sum.left as ast.Unary
	assert negative.op == '-'
	assert negative.typ.same(types.int_type())
}

fn test_a_constant_whose_type_needs_a_width_the_description_lacks_is_refused() {
	// 42 fits in the range every int has, so the type is settled without asking
	// the target description for a width. 100000 and 0xffffffff are past that
	// range and are still values the four-byte integer the back end writes a
	// constant at holds, so the description answers int and unsigned int for
	// them. 4294967296 needs a long, whose width the description does not
	// carry, so the model refuses, and the refusal is reported where the
	// constant is written rather than discarded: a node left unresolved is one
	// the emitter would have to guess a width for, which is how
	// `return 4294967295 > 2147483647;` was emitted as an int comparison and
	// returned 0 where ISO C and gcc return 1.
	small := checked('int main() { return 42; }')
	small_lit := small.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (small_lit as ast.IntLit).typ.same(types.int_type())
	wide := checked('int main() { return 0xffffffff; }')
	wide_lit := wide.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (wide_lit as ast.IntLit).typ.same(types.unsigned_int_type())
	big := checked('int main() { return 100000; }')
	big_lit := big.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (big_lit as ast.IntLit).typ.same(types.int_type())
	// Past the width the back end writes, the refusal stands.
	refused := parsed('int main() { return 4294967296; }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('4294967296')
	assert refused.diagnostics[0].line == 1
	assert refused.diagnostics[0].col == 21
	// The clause is the zero type: the constant is still a constant, and the
	// diagnostic is what keeps it from being compiled at a width nothing
	// decided.
	refused_lit := refused.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	assert (refused_lit as ast.IntLit).typ.kind == .unknown
}

fn test_sizeof_is_refused_by_name_and_by_location() {
	// `sizeof` is an operator, and reading the spelling as a call produced a
	// reference to a symbol nothing defines: `int main(void) { int a[4]; return
	// sizeof(a); }` compiled into a binary that died at load with `undefined
	// symbol: sizeof`. It is refused by name at its own token instead, both
	// spellings, and what it is written with is not read as an argument list.
	for source in [
		'int main() { int a[4]; return sizeof(a); }',
		'int main() { int a[4]; return sizeof a; }',
	] {
		result := parsed(source)
		assert result.diagnostics.len == 1
		assert result.diagnostics[0].msg.contains('sizeof')
		assert result.diagnostics[0].line == 1
		assert result.diagnostics[0].col == 31
	}
	// The refusal does not swallow the rest of the file: the next declaration is
	// read and carries its own clause.
	after := parsed('int main() { int x = sizeof(int); return x; }')
	assert after.diagnostics.len == 1
	assert after.diagnostics[0].col == 22
	assert after.unit.decls.len == 1
}

fn test_a_string_literal_is_an_array_of_char_with_room_for_the_terminator() {
	// Three characters and the terminator the literal does not write. The
	// argument is checked against `char *`, which it matches because a value of
	// an array type decays to a pointer to its first element where a value is
	// needed.
	result := checked('int wants(char *s);\nint main() { wants("abc"); return 0; }')
	statement := result.unit.decls[1].body[0]
	assert statement.kind == .expr_stmt
	call_expr := statement.expr or {
		assert false
		return
	}
	call := call_expr as ast.Call
	argument := call.args[0] as ast.StrLit
	assert argument.typ.kind == .array
	assert argument.typ.describe() == 'char[4]'
}

fn test_an_element_of_an_array_carries_the_element_type() {
	result := checked('char name[8];\nint main() { return name[1]; }')
	returned := result.unit.decls[0].body[0].expr or {
		assert false
		return
	}
	element := returned as ast.Index
	assert element.name == 'name'
	assert element.typ.same(types.char_type())
	assert (element.index as ast.IntLit).typ.same(types.int_type())
}

fn test_the_arguments_of_a_call_are_read_against_its_declaration() {
	// `int *p` and a char * argument: the two point at different types, which is
	// the constraint 6.5.16.1 names for an assignment and 6.5.2.2 for an
	// argument, since an argument converts to its parameter as if by assignment.
	result := parsed('int wants(int *p);\nint main() { char *s = 0; wants(s); return 0; }')
	assert result.diagnostics.len == 1
	message := result.diagnostics[0].msg
	assert message.contains('int *')
	assert message.contains('char *')
	assert message.contains('compatible')
	// The argument is where the diagnostic points, not the call.
	assert result.diagnostics[0].line == 2
	assert result.diagnostics[0].col == 33
}

// The constraint on assignment, 6.5.16.1, is asked wherever an assignment is
// written, which is three places and not one: an argument, which 6.5.2.2 says
// converts as if by assignment, an assignment statement, and the initializer of a
// declaration. Measured, gcc 16.2.1 under `-std=c99` refuses both pairs below,
// where this compiler accepted them: `void f(int *p, char *q) { q = p; }` is
// `assignment to 'char *' from incompatible pointer type 'int *'`, and
// `int main(void) { int *p = 7; return 0; }` is `initialization of 'int *' from
// 'int' makes pointer from integer without a cast`.
fn test_an_assignment_statement_is_checked_like_an_argument() {
	result := parsed('void f(int *p, char *q) { q = p; }\nint main(void) { return 0; }')
	assert result.diagnostics.len == 1
	message := result.diagnostics[0].msg
	assert message.contains('int *')
	assert message.contains('char *')
	assert message.contains('compatible')
	// The operator that writes is where the diagnostic points.
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 29
	// Writing a value whose type the object has is not a violation, and neither is
	// the null pointer constant, which converts to any pointer.
	clean := checked('int main(void) { int *p = 0; int *q = 0; q = p; q = 0; return 0; }')
	assert clean.unit.decls.len == 1
}

fn test_a_declaration_initializer_is_checked_like_an_assignment() {
	refused := parsed('int main(void) { int *p = 7; return 0; }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('only an integer constant of value zero')
	// The initializer is where it points, which is where gcc points at it.
	assert refused.diagnostics[0].line == 1
	assert refused.diagnostics[0].col == 27
	// The other side of the same rule: the same integer written into an int is
	// accepted, and so is the null pointer constant written into the pointer.
	accepted := checked('int main(void) { int n = 7; int *p = 0; return n; }')
	assert accepted.unit.decls.len == 1
	// An array of characters initialized by a string literal is 6.7.8 and not an
	// assignment, so this constraint has nothing to say about it.
	literal := checked('int main(void) { char s[4] = "abc"; return s[0]; }')
	assert literal.unit.decls.len == 1
}

fn test_the_null_pointer_constant_is_the_one_integer_a_pointer_takes() {
	// Zero is a null pointer constant and converts to any pointer; one is not,
	// and an argument that is a plain integer is a constraint violation.
	null_ok := checked('int wants(int *p);\nint main() { wants(0); return 0; }')
	assert null_ok.unit.decls.len == 2
	not_null := parsed('int wants(int *p);\nint main() { wants(1); return 0; }')
	assert not_null.diagnostics.len == 1
	assert not_null.diagnostics[0].msg.contains('integer')
}

fn test_a_call_reads_the_type_its_declaration_returns() {
	result := checked('int twice(int n);\nint main() { return twice(3) + 1; }')
	call := result.unit.decls[1].body[0].expr or {
		assert false
		return
	}
	sum := call as ast.Binary
	assert sum.typ.same(types.int_type())
	inner := sum.left as ast.Call
	assert inner.name == 'twice'
	assert inner.typ.same(types.int_type())
	assert inner.args.len == 1
	assert (inner.args[0] as ast.IntLit).typ.same(types.int_type())
}

fn test_the_return_type_of_a_pointer_is_a_pointer() {
	result := checked('char *pick(char *s, int n);')
	decl := result.unit.decls[0]
	assert decl.ret == 'char *'
	assert decl.ret_type.is_pointer()
	assert decl.ret_type.describe() == 'char *'
	assert decl.resolved.describe() == 'char * (char *, int)'
	assert decl.params.len == 2
	assert decl.params[0].resolved.describe() == 'char *'
	assert decl.params[1].resolved.same(types.int_type())
}

fn test_an_array_declared_at_the_top_level_carries_its_element_type_and_count() {
	result := checked('int table[4];\nchar name[8];')
	table := result.unit.globals[0]
	assert table.resolved.kind == .array
	assert table.resolved.describe() == 'int[4]'
	assert table.resolved.count == 4
	element := table.resolved.element() or {
		assert false
		return
	}
	assert element.same(types.int_type())
	assert result.unit.globals[1].resolved.describe() == 'char[8]'
}

fn test_a_tag_is_a_type_of_its_own_namespace() {
	// The tag is recorded while its body is read, so an object declared with it
	// afterwards has the aggregate type the body defined. A tag with no body is
	// declared and not complete, which is what a pointer to it may name.
	result := checked('struct point { int x; int y; };\nstruct later;\nint f(void) { return 1; }')
	assert result.diagnostics.len == 0
	tag := types.incomplete_tag(types.Kind.struct_, 'later')
	assert !tag.is_complete()
	assert tag.describe() == 'struct later'
}

fn test_a_typedef_makes_a_name_a_type_for_the_rest_of_the_file() {
	// The name resolves to what it was declared as, wherever it is read: here a
	// parameter of `count` is an int.
	result := checked('typedef int count;\nint take(count n);')
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].params[0].typ == 'count'
	assert result.unit.decls[0].params[0].resolved.same(types.int_type())
	assert result.unit.decls[0].resolved.describe() == 'int (int)'
}

fn test_a_definition_spelled_with_a_typedef_name_is_refused_where_it_is_written() {
	// The model resolves the name; the emitter reads the spelling, and a spelling
	// it has no width for is refused rather than emitted as something else. A
	// definition is storage, so this is a refusal and not a promise.
	result := parsed('typedef int count;\nint main() { int c = 1; count n = 2; return c; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported type count'
	assert result.diagnostics[0].line == 2
}

fn test_the_float_family_is_refused_by_name_and_by_location() {
	// DELIVERABLE 2's own test: a float the back end has no form for is refused
	// by name and location rather than misread as something the emitter does
	// have a form for.
	for spelled in ['float', 'double'] {
		result := parsed('${spelled} f(void) { return 0; }')
		assert result.diagnostics.len == 1
		assert result.diagnostics[0].msg == 'unsupported type ${spelled}'
		assert result.diagnostics[0].line == 1
		assert result.diagnostics[0].col == 1
	}
	// `long double` is one type written as two words, so the refusal names it
	// rather than the first word of it.
	wide := parsed('long double f(void) { return 0; }')
	assert wide.diagnostics.len == 1
	assert wide.diagnostics[0].msg == 'unsupported: long double is a type this compiler does not emit yet, so a function cannot return it'
	assert wide.diagnostics[0].line == 1
	// The model answers for the type all the same, which is what makes the
	// refusal the back end's and not the reader's.
	prototype := checked('long double f(void);')
	assert prototype.unit.decls[0].ret_type.same(types.long_double_type())
}

fn test_a_complex_type_is_refused_by_name() {
	// The model has the complex types and the emitter has no arithmetic for
	// them, so a definition of one is refused by name and location. The refusal
	// says which type it was, not the first word of its spelling.
	complex := parsed('double _Complex f(void) { return 0; }')
	assert complex.diagnostics.len == 1
	assert complex.diagnostics[0].msg == 'unsupported: double _Complex is a type this compiler does not emit yet, so a function cannot return it'
	assert complex.diagnostics[0].line == 1
	imaginary := parsed('_Imaginary g(void) { return 0; }')
	assert imaginary.diagnostics.len == 1
	assert imaginary.diagnostics[0].msg == 'unsupported type _Imaginary'
	// The parameter list names what a parameter was declared with, which is the
	// one place a type written as two words is spelled in full.
	parameter := parsed('int h(double _Complex z) { return 0; }')
	assert parameter.diagnostics.len == 1
	assert parameter.diagnostics[0].msg == 'unsupported type double _Complex'
}

fn test_a_type_the_emitter_has_no_form_for_is_refused_by_its_first_word() {
	// The wording for a definition of an object: the emitter stops at the first
	// word of the type, and that is the message the compiler has published.
	wider := parsed('unsigned long long h(void) { return 0; }')
	assert wider.diagnostics.len == 1
	assert wider.diagnostics[0].msg == 'unsupported type unsigned'
	assert wider.diagnostics[0].line == 1
}
