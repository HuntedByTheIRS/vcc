module printer

import ast
import parser
import tokenize

// The printer reads a tree and writes text, so these tests read the text.

fn tree(source string) ast.TranslationUnit {
	lexed := tokenize.lex(source)
	assert lexed.diagnostics.len == 0
	parsed := parser.parse(lexed.tokens)
	assert parsed.diagnostics.len == 0
	return parsed.unit
}

fn lines(unit ast.TranslationUnit) []string {
	return render(unit).split_into_lines()
}

fn line_of(lines []string, needle string) int {
	for i, line in lines {
		if line.contains(needle) {
			return i
		}
	}
	return -1
}

fn test_a_function_and_its_return_are_both_named() {
	printed := lines(tree('int main() { return 42; }'))
	assert printed[0].starts_with('fn main() int at 1:')
	assert printed[1].trim_space().starts_with('return at 1:')
	assert printed[2].trim_space().starts_with('int 42 at 1:')
}

fn test_nesting_reads_as_the_tree_does() {
	// `6 * 7 + 1` is a `+` whose left side is a `*`, and the dump has to say so
	// rather than flatten it into the order the operators were written.
	printed := lines(tree('int main() { return 6 * 7 + 1; }'))
	plus := line_of(printed, 'binary +')
	times := line_of(printed, 'binary *')
	leaf := line_of(printed, 'int 6')
	if plus < 0 || times < 0 || leaf < 0 {
		assert false
		return
	}
	assert plus < times
	assert times < leaf
	// The right side of `+` belongs to the outer node, so it sits between the
	// two operators' own lines by depth, not by position in the source.
	assert printed[plus].len - printed[plus].trim_left(' ').len <
		printed[times].len - printed[times].trim_left(' ').len
}

fn test_a_call_and_its_arguments_are_printed() {
	printed := lines(tree('int main() { return abs(-7); }'))
	assert line_of(printed, 'call abs with 1 argument(s)') > 0
	assert line_of(printed, 'unary -') > 0
	assert line_of(printed, 'int 7') > 0
}

fn test_an_identifier_is_named() {
	printed := lines(tree('int main() { return x; }'))
	assert line_of(printed, 'ident x') > 0
}

fn test_a_declaration_without_a_definition_says_so() {
	printed := lines(tree('int later();'))
	assert printed[0].starts_with('fn later()')
	assert printed[1].contains('declaration without a definition')
}

fn test_several_declarations_keep_their_order() {
	printed := lines(tree('int first() { return 1; }\nint second() { return 2; }'))
	first := line_of(printed, 'fn first()')
	second := line_of(printed, 'fn second()')
	assert first == 0
	assert second > first
}

fn test_the_same_tree_prints_the_same_text() {
	source := 'int main() { return 6 * 7 + 1; }'
	assert render(tree(source)) == render(tree(source))
}

// The dump is read on files that are large, so it walks the left spine of an
// operator chain with a loop. This is the size that took the constant folder's
// stack out once already.
fn test_a_long_chain_is_printed_without_recursing() {
	mut terms := []string{}
	for _ in 0 .. 20000 {
		terms << '1'
	}
	printed := lines(tree('int main() { return ${terms.join(' + ')}; }'))
	mut operators := 0
	for line in printed {
		if line.contains('binary +') {
			operators++
		}
	}
	assert operators == 19999
	// Indentation stops growing at max_indent, so the dump of a deep chain is
	// bounded rather than quadratic in its own whitespace. The slack is for the
	// node text and the location on the line.
	for line in printed {
		assert line.len <= 2 * max_indent + 32
	}
}
