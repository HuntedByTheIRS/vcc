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

// 6.5.2.2: what a call calls has to be a function or a pointer to a function. A
// name the unit declares as something else is refused where the call is written,
// because the emitter resolves the call to whatever the name is and the image then
// dies at load: measured, `int x; int main(void) { return x(1); }` compiled, wrote
// an image, and the image died at load with `undefined symbol: x`.
fn test_a_call_to_a_name_that_is_not_a_function_is_refused() {
	refused := parsed('int x;\nint main(void) { return x(1); }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('x is declared as int')
	assert refused.diagnostics[0].msg.contains('function or a pointer to a function')
	// A call through a parameter whose type is a pointer to a function is what the
	// clause allows, and is not this refusal.
	callable := parsed('int h(int (*fp)(void)) { return fp(); }')
	assert callable.diagnostics.len == 0
	// A name nothing declares is left to the check at the end of the unit, so the
	// two refusals do not both fire on one call.
	missing := parsed('int main(void) { return missing(1); }')
	assert missing.diagnostics.len == 1
	assert missing.diagnostics[0].msg.contains('nothing in this file declares it')
}

// 6.3.2.3 asks for the value of an integer constant expression and not for the way
// it is spelled, so the question is asked of the value. Measured, gcc 16.2.1 under
// `-std=c99` accepts `h(1 - 1)` for a parameter of type `int (*)(void)`, which this
// compiler refused while the answer was the literal alone.
fn test_the_null_pointer_constant_is_the_value_of_an_expression() {
	accepted := parsed('int h(int (*fp)(void));\nint g(void) { return 0; }\nint main(void) { return h(1 - 1); }')
	assert accepted.diagnostics.len == 0
	// The other side of the same rule: the same spelling with a value that is not
	// zero is not a null pointer constant.
	refused := parsed('int main(void) { int *p = 1 - 2; return 0; }')
	assert refused.diagnostics.len == 1
	assert refused.diagnostics[0].msg.contains('only an integer constant of value zero')
	// A value that is only known at run time is not a constant expression, whatever
	// it happens to hold: the question is about the expression and not about a value.
	run_time := parsed('int main(void) { int n = 0; int *p = n - n; return 0; }')
	assert run_time.diagnostics.len == 1
	// The arithmetic of two constants folds the same way, and the initializer shape
	// emits the zero it folds to: measured, `int main(void) { int *p = 1 - 1; if (p)
	// { return 3; } return 7; }` builds a binary that returns 7, which is what gcc's
	// binary returns.
	folded := parsed('int main(void) { int *p = 3 / 4; int *q = 2 * 0; return 0; }')
	assert folded.diagnostics.len == 0
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
	// The type is spelled as the type the name stands for, because the frame the
	// emitter lays out is sized from the spelling: `count` is an int, and a
	// parameter is storage the back end has to find a width for.
	assert result.unit.decls[0].params[0].typ == 'int'
	assert result.unit.decls[0].params[0].resolved.same(types.int_type())
	assert result.unit.decls[0].resolved.describe() == 'int (int)'
}

fn test_a_definition_spelled_with_a_typedef_name_is_the_definition_it_names() {
	// A definition is storage, and storage is sized from the spelling of its
	// type. A name that stands for a type the emitter has a form for is that
	// form, so `count n = 2;` declares an int and not a type of its own.
	result := parsed('typedef int count;\nint main() { int c = 1; count n = 2; return c + n; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].body[1].decl_type == 'int'
}

// An object of an aggregate type is a block of storage, and the size of it is
// the model's layout of the members rather than anything the declaration says:
// `struct S` is a tag, and a tag has no width of its own. What the back end is
// handed is the number, because a spelling it cannot size is a spelling it would
// have to refuse.
fn test_an_object_of_an_aggregate_type_carries_the_size_of_its_layout() {
	// int at 0, char at 4, and the object rounded up to four: 8 bytes, measured
	// against gcc 16.2.1 with `sizeof`.
	decl := first('struct S { int a; char c; };\nint main() { struct S s; return 0; }')
	body := decl.body
	assert body.len == 2
	assert body[0].decl_type == 'struct S'
	assert body[0].bytes == 8
}

// A member is a value at an offset into the object, and the offset comes from the
// layout: `c` is at 4 because an int comes first, and what is read there is a
// char, which is the type the tag declared it with.
fn test_a_member_is_read_at_the_offset_the_layout_puts_it_at() {
	decl := first('struct S { int a; char c; };\nint main() { struct S s; return s.c; }')
	body := decl.body
	assert body.len == 2
	returned := body[1].expr or {
		assert false
		return
	}
	member := returned as ast.Field
	assert member.name == 's'
	assert member.member == 'c'
	assert member.offset == 4
	assert member.spelling == 'char'
	assert member.typ.same(types.char_type())
}

// A member of a union starts at the beginning of the object, whatever its type.
fn test_a_member_of_a_union_is_at_the_beginning_of_it() {
	decl := first('union U { int a; char b; };\nint main() { union U u; return u.b; }')
	body := decl.body
	returned := body[1].expr or {
		assert false
		return
	}
	member := returned as ast.Field
	assert member.offset == 0
	assert member.spelling == 'char'
}

// A member written into is the same offset read the other way, and the statement
// carries the member rather than a name: `s.c = 5` writes four bytes into the
// object at four, where a plain name would write a slot of its own.
fn test_an_assignment_to_a_member_carries_the_member() {
	decl := first('struct S { int a; char c; };\nint main() { struct S s; s.c = 5; return 0; }')
	body := decl.body
	assert body.len == 3
	assert body[1].kind == .assign
	target := body[1].field or {
		assert false
		return
	}
	assert target.offset == 4
	assert target.spelling == 'char'
}

// A tag that was declared and never defined is a type whose size nobody knows,
// so an object of it is refused by the tag as it was written and not at the use.
fn test_an_object_of_an_incomplete_tag_is_refused_by_the_tag() {
	result := parsed('struct S;\nint main() { struct S s; return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported type struct S'
	assert result.diagnostics[0].line == 2
}

// An object defined at the top level is storage in the image, which is laid out
// by a path that has no room for an aggregate yet. Refusing it where it is
// written is what keeps an object nothing uses from being dropped silently.
// An object of an aggregate type at the top level is storage in the image, and how
// much of it is the model's layout rather than a width a spelling answers. The
// declaration asks that question once and carries the answer, which is what the
// image writer reserves.
fn test_an_aggregate_at_the_top_level_carries_the_size_of_its_layout() {
	result := checked('struct S { int a; char c; };\nstruct S g;\nint main() { return 0; }')
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].bytes == 8
	assert result.unit.globals[0].count == 0
}

// An array of aggregates is a stride and a count: the stride is the layout's size
// of one element, which the index scales by, and the count is what the declarator
// wrote. Both travel with the declaration, so the image reserves the product and
// an element is read at an offset a non-power-of-two stride reaches by a multiply.
fn test_an_array_of_aggregates_carries_the_stride_and_the_count() {
	result := checked('struct S { int a; char c; };\nstruct S g[3];\nint main() { return 0; }')
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].bytes == 8
	assert result.unit.globals[0].count == 3
}

// A member of a member is inside the same object: the path is one Field naming the
// object, with the offsets added up on the way in, because a member of a member is
// a byte further into the object and not a second object. `o` is four bytes of
// struct O (`in` starts at zero and holds one int), and `in.a` sits at zero of it.
fn test_a_member_of_a_member_is_one_field_at_the_sum_of_the_offsets() {
	decl := first('struct I { int a; char c; };\nstruct O { int n; struct I in; };\nint main() { struct O o; return o.in.c; }')
	body := decl.body
	returned := body[1].expr or {
		assert false
		return
	}
	member := returned as ast.Field
	assert member.name == 'o'
	// The path is spelled the way it was written, so a diagnostic about the
	// member names `in.c` and not just `c`.
	assert member.member == 'in.c'
	assert member.offset == 8
	assert member.spelling == 'char'
	assert member.typ.same(types.char_type())
}

// Reading a member through a pointer is the arrow form: the object is the one the
// pointer names, so the Field says the address comes from the pointer's value and
// the offset is the member's place in the pointed-at type.
fn test_a_member_read_through_a_pointer_is_a_field_that_says_so() {
	decl := first('struct S { int a; int b; };\nint main() { struct S s; struct S *p = &s; return p->b; }')
	body := decl.body
	returned := body[2].expr or {
		assert false
		return
	}
	member := returned as ast.Field
	assert member.name == 'p'
	assert member.member == 'b'
	assert member.offset == 4
	assert member.through_pointer
}

// An arrow on a name that holds no pointer has no object to be read through, and
// the refusal names the name and the type it does hold.
fn test_an_arrow_on_a_name_that_is_not_a_pointer_is_refused() {
	result := parsed('struct S { int a; };\nint main() { struct S s; return s->a; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains('is read through ->')
}

// A name whose type has no members has no member, and a member a tag does not
// declare is not one either: both are refused where they are written.
fn test_a_member_of_something_without_members_is_refused() {
	plain := parsed('int main() { int n = 1; return n.a; }')
	assert plain.diagnostics.len == 1
	assert plain.diagnostics[0].msg.contains('a member is read from an object whose type has members')
	unknown := parsed('struct S { int a; };\nint main() { struct S s; return s.zz; }')
	assert unknown.diagnostics.len == 1
	assert unknown.diagnostics[0].msg.contains('has no member called zz')
}

fn test_a_typedef_of_a_type_the_emitter_has_no_form_for_is_refused_by_that_type() {
	// The name is not what is asked about, the type it names is: `Big` is a
	// `long` here, and a `long` is a type this compiler has no width for. The
	// refusal names `long` rather than `Big`, and it happens at the declaration,
	// which is where the object is defined and not only where something uses it.
	wider := parsed('typedef long Big;\nBig x;')
	assert wider.diagnostics.len == 1
	assert wider.diagnostics[0].msg == 'unsupported type long'
	assert wider.diagnostics[0].line == 2
	// A parameter is the same question, asked where the call's frame is laid out.
	parameter := parsed('typedef long Big;\nint f(Big b) { return 0; }')
	assert parameter.diagnostics.len == 1
	assert parameter.diagnostics[0].msg.contains('unsupported type long')
}

fn test_the_float_family_is_refused_by_name_and_by_location() {
	// DELIVERABLE 2's own test: a float the back end has no form for is refused
	// by name and location rather than misread as something the emitter does
	// have a form for.
	//
	// `double` is no longer in this list, and that is a change in what is true
	// rather than in what is checked: the back end has instructions for a
	// double, so a definition that returns one is a definition and not a
	// refusal. `float` is still refused, by the same reader, at the same place.
	result := parsed('float f(void) { return 0; }')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == 'unsupported type float'
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 1
	// The type is one this reader has a spelling and a width for, which is what
	// makes it the back end's to refuse and not the reader's.
	widened := parsed('double f(void) { return 0; }')
	assert widened.diagnostics.len == 0
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

fn test_a_floating_constant_is_typed_as_the_double_it_is() {
	// 6.4.4.2 makes the spelling decide the class and the class decides the type:
	// a decimal constant with a point or an exponent is a floating one, and a
	// double is the one floating type this back end has instructions for.
	decl := first('double half(void) { return 1.5; }')
	assert decl.ret_type.same(types.double_type())
	returned := decl.body[0].expr or {
		assert false
		return
	}
	half := returned as ast.FloatLit
	assert half.value == 1.5
	assert half.text == '1.5'
	assert half.typ.same(types.double_type())
	// An exponent is a floating constant with no point in it at all, and its
	// value is the one the exponent names rather than the digits before it.
	exponent := first('double big(void) { return 1e3; }')
	numeric := exponent.body[0].expr or {
		assert false
		return
	}
	assert (numeric as ast.FloatLit).value == 1000.0
}

fn test_a_floating_suffix_is_refused_by_the_type_it_names() {
	// A suffix is not dropped: `1.5f` names a float and `1.5L` a long double, and
	// reading either as a double would give the program a type it did not ask
	// for. The refusal names the type, at the constant as it was written.
	narrow := parsed('double f(void) { return 1.5f; }')
	assert narrow.diagnostics.len == 1
	assert narrow.diagnostics[0].msg.contains('float literal')
	assert narrow.diagnostics[0].col == 25
	long_double := parsed('double f(void) { return 1.5L; }')
	assert long_double.diagnostics.len == 1
	assert long_double.diagnostics[0].msg.contains('long double literal')
}

fn test_a_mixed_operation_is_a_double_on_both_sides() {
	// The usual conversions give an int and a double one common type, and the
	// node keeps it: what the emitter reads is the node's own class, which is
	// what keeps a long chain from having to be walked one term at a time.
	result := checked('double f(void) { int n = 2; return n + 1e3; }')
	returned := result.unit.decls[0].body[1].expr or {
		assert false
		return
	}
	sum := returned as ast.Binary
	assert sum.op == '+'
	assert sum.typ.same(types.double_type())
	// The int operand keeps the type it was declared with, and the conversion to
	// a double is what the emitter makes of the operation.
	assert (sum.left as ast.Ident).typ.same(types.int_type())
	assert (sum.right as ast.FloatLit).typ.same(types.double_type())
}
