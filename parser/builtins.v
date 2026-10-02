module parser

import ast
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
const builtin_expression_names = ['__builtin_types_compatible_p', '__builtin_choose_expr']

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
	value := constant_value(condition) or {
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
