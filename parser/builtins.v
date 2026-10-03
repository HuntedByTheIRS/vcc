module parser

import ast
import math
import tokenize
import types

// The GCC builtins this reader answers while it reads, which are the ones a
// C library's headers reach for rather than the ones a program writes by hand.
// They are in the reserved namespace, so no dialect refuses them and no row in
// `standard/features.v` gates them: a name with two leading underscores carries
// nothing for the dialect check to report.
//
// Each one is folded where it is written, the way `sizeof` is: the question it
// asks is one the reader can answer from the declaration it was handed, and the
// value it is worth is an integer constant expression with no run-time part. A
// builtin whose answer would be a guess is refused by name here rather than
// filled in with a value this compiler has not computed.
const builtin_expression_names = ['__builtin_types_compatible_p', '__builtin_choose_expr',
	'__builtin_offsetof', '__builtin_va_arg', '__builtin_va_start', '__builtin_va_end',
	'__builtin_va_copy', '__builtin_huge_val', '__builtin_huge_valf', '__builtin_huge_vall',
	'__builtin_inf', '__builtin_inff', '__builtin_infl', '__builtin_nan', '__builtin_nanf',
	'__builtin_nanl', '__builtin_nans', '__builtin_nansf', '__builtin_nansl', '__builtin_classify_type',
	'__builtin_isinf_sign', '__builtin_signbit', '__builtin_signbitf', '__builtin_signbitl',
	'__builtin_signbitf128']

// parse_builtin_expression reads one of them. The name has been read and the
// cursor is at its opening parenthesis.
//
// A builtin nests through its own arguments, so the count that bounds
// parenthesised nesting and conditional chains bounds this one too: without it,
// `__builtin_choose_expr(1, __builtin_choose_expr(1, ...`, written once per
// level, follows the chain until the stack runs out.
fn (mut p Parser) parse_builtin_expression(at tokenize.Token) !ast.Expr {
	p.depth++
	if p.depth > max_expression_depth {
		p.depth--
		p.error_at(at, 'expression is nested more than ${max_expression_depth} levels deep')
		return error('expression nested too deeply')
	}
	expr := p.read_builtin_expression(at) or {
		p.depth--
		return error('the builtin ${at.text}')
	}
	p.depth--
	return expr
}

fn (mut p Parser) read_builtin_expression(at tokenize.Token) !ast.Expr {
	match at.text {
		'__builtin_types_compatible_p' {
			return p.parse_types_compatible(at)
		}
		'__builtin_choose_expr' {
			return p.parse_choose_expr(at)
		}
		'__builtin_offsetof' {
			return p.parse_offsetof(at)
		}
		'__builtin_va_arg' {
			return p.parse_va_arg(at)
		}
		'__builtin_va_start' {
			return p.parse_va_start(at)
		}
		'__builtin_va_end' {
			return p.parse_va_end(at)
		}
		'__builtin_va_copy' {
			return p.parse_va_copy(at)
		}
		'__builtin_huge_val', '__builtin_huge_valf', '__builtin_huge_vall', '__builtin_inf',
		'__builtin_inff', '__builtin_infl', '__builtin_nan', '__builtin_nanf', '__builtin_nanl',
		'__builtin_nans', '__builtin_nansf', '__builtin_nansl' {
			return p.parse_value_builtin(at)
		}
		'__builtin_signbit', '__builtin_signbitf', '__builtin_signbitl', '__builtin_signbitf128' {
			return p.parse_signbit(at)
		}
		'__builtin_isinf_sign' {
			return p.parse_isinf_sign(at)
		}
		'__builtin_classify_type' {
			return p.parse_classify_type(at)
		}
		else {
			return error('not a builtin this reader knows')
		}
	}
}

// parse_types_compatible answers `__builtin_types_compatible_p(type1, type2)`,
// which glibc's math.h uses to dispatch a type-generic macro on the type of its
// argument: `isnan(x)` becomes a chain of these asking whether the type of x is
// `float`, then `double`, then `long double`.
//
// The answer is 1 when the two types are the same type and 0 when they are not,
// and it has the type int because that is what gcc gives it. gcc ignores
// top-level qualifiers when it asks, so `__builtin_types_compatible_p(const int,
// int)` is 1 while `(__builtin_types_compatible_p(const int *, int *))` is 0;
// measured on gcc 16.2.1, along with `(char, signed char)` and `(enum E, int)`,
// which are both 0 because those are different types.
//
// The answer is a value, so neither direction may be guessed: a type this
// compiler did not resolve is refused by name rather than answered 0.
fn (mut p Parser) parse_types_compatible(at tokenize.Token) !ast.Expr {
	p.next() // (
	left := p.parse_builtin_type(at)!
	if !p.expect_punct(',') {
		return error('expected the second type')
	}
	right := p.parse_builtin_type(at)!
	if !p.expect_punct(')') {
		return error('unclosed __builtin_types_compatible_p')
	}
	same := types.unqualified(left.typ).same(types.unqualified(right.typ))
	return ast.Expr(ast.IntLit{
		value: if same { 1 } else { 0 }
		text:  '__builtin_types_compatible_p(${left.spelling}, ${right.spelling})'
		typ:   types.int_type()
		line:  at.line
		col:   at.col
	})
}

// parse_choose_expr answers `__builtin_choose_expr(cond, then, else)`, which is
// the other half of the same dispatch: the first argument is a constant, and the
// expression is worth whichever of the two others that constant selects.
//
// gcc reads both operands and only evaluates the selected one, so both are read
// here too and the second is thrown away with the tree it built. The value has
// the type of the arm chosen, which is why `sizeof(__builtin_choose_expr(1,
// (char)1, (long)1))` is 1: the selected expression is what stands in the tree.
//
// The condition has to be an integer constant expression, which is the
// constraint gcc states; one this reader cannot evaluate is refused by name.
fn (mut p Parser) parse_choose_expr(at tokenize.Token) !ast.Expr {
	p.next() // (
	condition := p.parse_expression()!
	if !p.expect_punct(',') {
		return error('expected the selected expression')
	}
	chosen := p.parse_expression()!
	if !p.expect_punct(',') {
		return error('expected the other expression')
	}
	other := p.parse_expression()!
	if !p.expect_punct(')') {
		return error('unclosed __builtin_choose_expr')
	}
	value := p.constant_value(condition) or {
		p.error_at(at, 'unsupported: __builtin_choose_expr selects on a constant, and the first argument is not one this compiler can read')
		return error('condition is not a constant')
	}
	if value != 0 {
		return chosen
	}
	return other
}

// parse_builtin_type reads one type-name argument of a builtin. The words a type
// name opens with are the words a declaration opens with, so the token has to be
// one of those: an identifier that names no type would otherwise be read as the
// name of an object and refused with a message about names rather than about the
// type that is missing.
fn (mut p Parser) parse_builtin_type(at tokenize.Token) !TypeName {
	if !p.starts_declaration(p.peek()) {
		p.error_at(p.peek(), 'unsupported: ${at.text} asks for a type name, and ${describe(p.peek())} is not a type this compiler knows')
		return error('not a type name')
	}
	name := p.parse_type_name(0)!
	if name.typ.kind == .unknown {
		p.error_at(p.peek(), 'unsupported: ${at.text} asks about ${name.spelling}, and this compiler did not resolve that type')
		return error('unresolved type')
	}
	return name
}

// parse_offsetof answers `__builtin_offsetof(type, member)`, which is what
// stddef.h's `offsetof` expands to. The answer is where the model's own layout
// puts the member and how big it is, not a number worked out from the spelling:
// the same `layout` the reader asks when it builds a `Field`, so an offsetof and
// the field it names cannot disagree.
//
// The value has the type size_t, which is what offsetof yields, so it is written
// as the constant `sizeof` writes and not as an int.
fn (mut p Parser) parse_offsetof(at tokenize.Token) !ast.Expr {
	p.next() // (
	start := p.parse_builtin_type(at)!
	if !p.expect_punct(',') {
		return error('expected the member path')
	}
	offset := p.parse_member_offset(start.typ)!
	if !p.expect_punct(')') {
		return error('unclosed __builtin_offsetof')
	}
	return ast.Expr(ast.IntLit{
		value: i64(offset)
		text:  '__builtin_offsetof(${start.spelling})'
		typ:   types.unsigned_long_type()
		line:  at.line
		col:   at.col
	})
}

// parse_member_offset walks a member path in the type it was given and answers
// where the last member of it sits, in bytes. It is the walk a `Field` makes, and
// it reads the offset from the model's layout for the same reason: an offsetof
// that disagreed with the field it names would be a wrong constant in a program
// that is full of them.
//
// The path is dots, `point.y` and `inner`. An array subscript is part of the
// designator gcc allows (`chain[1].a`) and is not read here, so it is refused by
// name rather than skipped; a bitfield has no address to take and gcc refuses
// `offsetof` of one, so it is refused here too.
fn (mut p Parser) parse_member_offset(declared types.Type) !int {
	if p.peek().kind != .identifier {
		p.error_at(p.peek(), 'unsupported: __builtin_offsetof reads a member, and ${describe(p.peek())} is not a member name')
		return error('member name')
	}
	mut current := declared
	mut total := 0
	mut path := ''
	for {
		name := p.next()
		path = if path == '' { name.text } else { '${path}.${name.text}' }
		aggregate := p.tagged_type(current)
		if aggregate.kind !in [types.Kind.struct_, .union_] {
			p.error_at(name, 'unsupported: __builtin_offsetof reads ${path} from ${aggregate.describe()}, and a member is read from an object whose type has members')
			return error('not an aggregate')
		}
		mut at := -1
		for i, member in aggregate.members {
			if member.name == name.text {
				at = i
				break
			}
		}
		if at < 0 {
			p.error_at(name, 'unsupported: ${aggregate.describe()} has no member called ${name.text}')
			return error('unknown member')
		}
		member := aggregate.members[at]
		if member.bitfield {
			p.error_at(name, 'unsupported: ${path} is a bitfield, and a bitfield sits in bits inside a unit rather than at a byte offset')
			return error('bitfield')
		}
		layout := p.representation.layout(aggregate) or {
			p.error_at(name, 'unsupported: the members of ${aggregate.describe()} are not a layout this compiler knows, so the offset of ${path} cannot be read')
			return error('no layout')
		}
		total += layout.offsets[at]
		current = member.typ
		if p.at_punct('.') {
			p.next()
			continue
		}
		break
	}
	if p.at_punct('[') {
		p.error_at(p.peek(), 'unsupported: __builtin_offsetof reads ${path}[...], and this compiler answers a path of members only')
		return error('array designator')
	}
	return total
}

// The four operations over an argument list, which is one object and not four:
// `va_start` fills a list in from the save area the prologue wrote, `va_arg`
// reads one argument out of it and steps it, `va_copy` copies it, and `va_end`
// finishes with it.
//
// They are read as calls with the reserved names below, so the tree carries one
// shape for them and the back end answers each name with the sequence of
// instructions the calling convention asks for. `__builtin_va_arg` carries the
// type of the argument it reads in the node's own `typ`, which is where a
// reader of the tree expects an expression's type to be.
//
// The list an operation is given is a name in every program that uses one:
// `va_start` and `va_copy` write the list's own storage, and a spelling that is
// not a name has nowhere to be written. The last named parameter a `va_start`
// names is read for its tokens and thrown away, because where the walk starts is
// a property of the enclosing declaration and not of that expression.

// argument_list_names are the four spellings, kept in one place so the check for
// a name nothing declares skips exactly the calls this reader builds.
const argument_list_names = ['__builtin_va_start', '__builtin_va_arg', '__builtin_va_end',
	'__builtin_va_copy']

// list_argument reads the argument list one of the four is given. It has to be
// a name: it is written by `va_start` and `va_copy`, and a list the reader
// cannot find again has nowhere to put either.
fn (mut p Parser) list_argument(at tokenize.Token, spelling string) !ast.Expr {
	list := p.parse_expression()!
	if list !is ast.Ident {
		p.error_at(at, 'unsupported: ${spelling} writes the argument list it is given, and ${describe_operand(list)} is not one this compiler can write through')
		return error('not an argument list name')
	}
	return ast.Expr(list)
}

fn (mut p Parser) parse_va_start(at tokenize.Token) !ast.Expr {
	p.next() // (
	list := p.list_argument(at, '__builtin_va_start')!
	if !p.expect_punct(',') {
		p.error_at(at, 'unsupported: __builtin_va_start takes the argument list and the last named parameter')
		return error('expected the last named parameter')
	}
	// The last named parameter is read and dropped: the offsets the walk starts
	// at are the enclosing declaration's and not this expression's.
	_ := p.parse_expression()!
	if !p.expect_punct(')') {
		p.error_at(at, 'unclosed __builtin_va_start')
		return error('unclosed __builtin_va_start')
	}
	return ast.Expr(ast.Call{
		name: '__builtin_va_start'
		args: [list]
		typ:  types.void_type()
		line: at.line
		col:  at.col
	})
}

// parse_va_arg reads `__builtin_va_arg(ap, type)`, which is what stdarg.h's
// `va_arg` expands to. The type is the type of the argument being read, and the
// node carries it: a walk through a list holds no type, so this is the only
// place that says whether the next argument is an int, a long long or a double,
// and the back end reads it from here.
fn (mut p Parser) parse_va_arg(at tokenize.Token) !ast.Expr {
	p.next() // (
	list := p.list_argument(at, '__builtin_va_arg')!
	if !p.expect_punct(',') {
		p.error_at(at, 'unsupported: __builtin_va_arg takes the argument list and the type of the argument')
		return error('expected the type of the argument')
	}
	read := p.parse_builtin_type(at)!
	if !p.expect_punct(')') {
		p.error_at(at, 'unclosed __builtin_va_arg')
		return error('unclosed __builtin_va_arg')
	}
	return ast.Expr(ast.Call{
		name: '__builtin_va_arg'
		args: [list]
		typ:  read.typ
		line: at.line
		col:  at.col
	})
}

fn (mut p Parser) parse_va_end(at tokenize.Token) !ast.Expr {
	p.next() // (
	list := p.list_argument(at, '__builtin_va_end')!
	if !p.expect_punct(')') {
		p.error_at(at, 'unclosed __builtin_va_end')
		return error('unclosed __builtin_va_end')
	}
	return ast.Expr(ast.Call{
		name: '__builtin_va_end'
		args: [list]
		typ:  types.void_type()
		line: at.line
		col:  at.col
	})
}

fn (mut p Parser) parse_va_copy(at tokenize.Token) !ast.Expr {
	p.next() // (
	destination := p.list_argument(at, '__builtin_va_copy')!
	if !p.expect_punct(',') {
		p.error_at(at, 'unsupported: __builtin_va_copy takes the list being written and the one being read')
		return error('expected the source list')
	}
	source := p.parse_expression()!
	if !p.expect_punct(')') {
		p.error_at(at, 'unclosed __builtin_va_copy')
		return error('unclosed __builtin_va_copy')
	}
	return ast.Expr(ast.Call{
		name: '__builtin_va_copy'
		args: [destination, source]
		typ:  types.void_type()
		line: at.line
		col:  at.col
	})
}

// The builtins that are a value rather than a question about a declaration: the
// infinities and NaNs a math header builds HUGE_VAL, INFINITY and NAN from, and
// the three that classify an argument. gcc gives each constant a type of its own
// width, and the type here is the one the answer carries, which is the whole
// reason the reader has to know: `isinf(HUGE_VALL)` asks the type of
// `__builtin_huge_vall()` through `__typeof`, and only `long double` answers it
// the way gcc does.

// parse_value_builtin reads an infinity. It takes no argument; the spelling's
// last letter picks the width, and `__builtin_nanf("")` and its siblings read a
// string that names the payload of the NaN. gcc ignores the payload for the value
// this compiler builds, which is the quiet NaN its own `nan` is.
fn (mut p Parser) parse_value_builtin(at tokenize.Token) !ast.Expr {
	if at.text in ['__builtin_nan', '__builtin_nanf', '__builtin_nanl', '__builtin_nans',
		'__builtin_nansf', '__builtin_nansl'] {
		p.next() // (
		if p.peek().kind != .string {
			p.error_at(p.peek(), 'unsupported: ${at.text} reads the payload of a NaN from a string literal, and ${describe(p.peek())} is not one')
			return error('the payload of a NaN')
		}
		_ := p.next()
		if !p.expect_punct(')') {
			return error('a NaN call')
		}
		return float_constant(math.nan(), builtin_width(at.text), '${at.text}("")', at)
	}
	p.next() // (
	if !p.expect_punct(')') {
		return error('a call with no argument')
	}
	return float_constant(math.inf(1), builtin_width(at.text), '${at.text}()', at)
}

// builtin_width is the type a floating builtin answers with, read off the
// spelling. The width is a `f` or `l` on the end of the *name*, and not the
// letter before it: `__builtin_huge_val` ends in `l` and is the double one, while
// `__builtin_huge_vall` is the long double one.
fn builtin_width(name string) types.Type {
	if name in ['__builtin_huge_valf', '__builtin_inff', '__builtin_nanf', '__builtin_nansf'] {
		return types.float_type()
	}
	if name in ['__builtin_huge_vall', '__builtin_infl', '__builtin_nanl', '__builtin_nansl'] {
		return types.long_double_type()
	}
	return types.double_type()
}

// parse_signbit reads `__builtin_signbit(x)`, and the `f`, `l` and `f128`
// spellings a type-generic macro picks between. The answer is nonzero when the
// sign bit of x is set, which is what makes it different from `x < 0`: -0.0 has
// the sign bit set and compares equal to zero. Measured on gcc 16.2.1,
// `__builtin_signbit(-0.0)` is 1 and `__builtin_signbit(0.0)` is 0.
//
// A constant operand is folded exactly, by the sign bit of the value, so -0.0
// and a NaN keep the answer gcc gives them. Anything else is written as
// `(x) < 0.0 || (1.0 / (x) < 0.0)`, whose first term is the negative numbers and
// the infinities and whose second is -0.0 and the negative subnormals, where
// 1.0 / (x) overflows to -infinity. A NaN whose sign bit is set is the one
// operand this misses: the arithmetic form has no bit to read and answers 0.
fn (mut p Parser) parse_signbit(at tokenize.Token) !ast.Expr {
	p.next() // (
	operand := p.parse_expression()!
	if !p.expect_punct(')') {
		return error('a value')
	}
	if value := constant_double(operand) {
		return integer_constant(if math.signbit(value) { 1 } else { 0 },
			'${at.text}(${describe_operand(operand)})', at, types.Kind.int_)
	}
	zero := float_constant(0.0, types.double_type(), '0.0', at)
	one := float_constant(1.0, types.double_type(), '1.0', at)
	negative := p.builtin_binary('<', operand, zero, at)
	reciprocal := p.builtin_binary('/', one, operand, at)
	underflow := p.builtin_binary('<', reciprocal, zero, at)
	return p.builtin_binary('||', negative, underflow, at)
}

// parse_isinf_sign reads `__builtin_isinf_sign(x)`, which gcc's `<math.h>`
// writes for `isinf(x)` under a GNU dialect. The answer is 1 for positive
// infinity, -1 for negative infinity and 0 for everything else, and a NaN is
// 0 because it is not equal to either infinity.
//
// A constant operand is folded, so `__builtin_isinf_sign(__builtin_huge_vall())`
// answers without a long double ever reaching the emitter: the infinity the
// header wrote is a constant, and the question has an answer at the call. A
// value that is not constant is compared with the two infinities.
fn (mut p Parser) parse_isinf_sign(at tokenize.Token) !ast.Expr {
	p.next() // (
	operand := p.parse_expression()!
	if !p.expect_punct(')') {
		return error('a value')
	}
	if value := constant_double(operand) {
		return integer_constant(isinf_sign_of(value), '${at.text}(${describe_operand(operand)})', at, types.Kind.int_)
	}
	positive := float_constant(math.inf(1), types.double_type(), '__builtin_huge_val()', at)
	negative := float_constant(-math.inf(1), types.double_type(), '-__builtin_huge_val()', at)
	positive_answer := p.builtin_conditional(p.builtin_binary('==', operand, positive, at),
		integer_constant(1, '1', at, types.Kind.int_), integer_constant(0, '0', at, types.Kind.int_), at)
	return p.builtin_conditional(p.builtin_binary('==', operand, negative, at),
		integer_constant(-1, '-1', at, types.Kind.int_), positive_answer, at)
}

// isinf_sign_of is gcc's answer for a constant: 1 at positive infinity, -1 at
// negative infinity, 0 anywhere else.
fn isinf_sign_of(value f64) i64 {
	if math.is_inf(value, 1) {
		return 1
	}
	if math.is_inf(value, -1) {
		return -1
	}
	return 0
}

// parse_classify_type reads `__builtin_classify_type(expr)`, which is a number
// for the type of the operand and not for its value. The operand is read and
// thrown away once its type is known, the way `sizeof` and `typeof` read theirs.
//
// The numbers are gcc 16.2.1's, measured by printing one for a value of each
// kind: every integer type including char, _Bool and an enum answers 1, float and
// double and long double answer 8, a complex type 9, a pointer 5, a struct 12 and
// a union 13. gcc has no answer for a void operand and refuses one; so does this
// reader, by name.
fn (mut p Parser) parse_classify_type(at tokenize.Token) !ast.Expr {
	p.next() // (
	operand := p.parse_expression()!
	if !p.expect_punct(')') {
		return error('a value')
	}
	typ := p.value_type(operand)
	if p.is_unresolved(operand) || typ.kind == .unknown {
		p.error_at(at, 'unsupported: ${at.text} asks about ${describe_operand(operand)}, and this compiler did not resolve its type')
		return error('no type for the operand')
	}
	number := type_class(typ) or {
		p.error_at(at, 'unsupported: ${at.text} has no number for ${typ.describe()}, and gcc has none either')
		return error('no class for the type')
	}
	return integer_constant(number, '${at.text}(${describe_operand(operand)})', at, types.Kind.int_)
}

// type_class is the number gcc's `__builtin_classify_type` gives a type, or none
// for a type gcc has no number for. A void operand is the one gcc refuses, and
// an unresolved type is one this reader has nothing to answer with.
fn type_class(typ types.Type) ?i64 {
	if typ.is_integer() {
		return 1
	}
	if typ.is_floating() {
		return 8
	}
	if typ.is_complex() {
		return 9
	}
	if typ.is_pointer() {
		return 5
	}
	if typ.kind == .struct_ {
		return 12
	}
	if typ.kind == .union_ {
		return 13
	}
	return none
}

// constant_double is the value of an expression that is a floating constant, or
// none. A constant written with a leading minus is a unary minus over the
// literal, and gcc folds it before it is asked for its sign, so the sign is taken
// off the value here too. That is what makes `__builtin_signbit(-0.0)` the -0.0
// gcc answers 1 for.
fn constant_double(expr ast.Expr) ?f64 {
	match expr {
		ast.FloatLit {
			return expr.value
		}
		ast.Unary {
			if expr.op == '-' {
				if inner := constant_double(expr.expr) {
					return -inner
				}
			}
		}
		else {}
	}
	return none
}

// float_constant and integer_constant are the two nodes the builtins above build
// in place of a call. They are written where the call was written, so a
// diagnostic about one points at the line that asked for it.
fn float_constant(value f64, typ types.Type, text string, at tokenize.Token) ast.Expr {
	return ast.Expr(ast.FloatLit{
		value: value
		text:  text
		typ:   typ
		line:  at.line
		col:   at.col
	})
}

// integer_constant is a use of an integer constant this reader computed: the
// value and the kind a use of it has. An enumeration constant's kind is the one
// its enum settled (see types.enum_constant_kind), and every other caller here
// names an int, which is what a classifying builtin answers.
fn integer_constant(value i64, text string, at tokenize.Token, kind types.Kind) ast.Expr {
	return ast.Expr(ast.IntLit{
		value: value
		text:  text
		typ:   types.scalar(kind) or { types.int_type() }
		line:  at.line
		col:   at.col
	})
}

// builtin_binary and builtin_conditional build the operator nodes a classifying
// builtin stands for, with the type the reader's own operators would give them.
// The operator token carries where the call was written so that a refusal inside
// one of them points at the call rather than at a file position that does not
// exist.
fn (mut p Parser) builtin_binary(op string, left ast.Expr, right ast.Expr, at tokenize.Token) ast.Expr {
	operator := tokenize.Token{
		...at
		text: op
	}
	return ast.Expr(ast.Binary{
		op:    op
		left:  left
		right: right
		typ:   p.binary_type(operator, left, right)
		line:  at.line
		col:   at.col
	})
}

fn (mut p Parser) builtin_conditional(condition ast.Expr, then_expr ast.Expr, else_expr ast.Expr, at tokenize.Token) ast.Expr {
	question := tokenize.Token{
		...at
		text: '?'
	}
	return ast.Expr(ast.Conditional{
		cond:      condition
		then_expr: then_expr
		else_expr: else_expr
		typ:       p.conditional_type(question, then_expr, else_expr)
		line:      at.line
		col:       at.col
	})
}
