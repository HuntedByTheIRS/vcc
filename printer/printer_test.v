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
	printed := lines(tree('int abs(int n);\nint main() { return abs(-7); }'))
	assert line_of(printed, 'call abs with 1 argument(s)') > 0
	assert line_of(printed, 'unary -') > 0
	assert line_of(printed, 'int 7') > 0
}

fn test_an_identifier_is_named() {
	printed := lines(tree('int x;\nint main() { return x; }'))
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

fn test_the_step_of_a_loop_has_its_own_heading() {
	dumped := lines(tree('int main() { int j = 0; for (j = 0; j < 3; j = j + 1) { j = j; } }'))
	assert dumped.any(it.contains('step'))
	// A while has no step, so nothing in its dump says step.
	while_dump := lines(tree('int main() { int j = 0; while (j < 3) { j = j + 1; } }'))
	assert !while_dump.any(it.contains('step'))
}

fn test_a_call_through_an_expression_prints_the_expression_it_calls() {
	// The callee of `(*fp)(1, 2)` is a value rather than a name, so the dump has
	// to print the expression: printing a name here would say the call reaches
	// something the source does not name.
	dumped := lines(tree('int h(int (*fp)(int, int)) { return (*fp)(1, 2); }'))
	assert dumped.any(it.contains('call through an expression with 2 argument(s)'))
	assert dumped.any(it.contains('unary *'))
	// A call to a function still prints the name it reaches.
	direct := lines(tree('int f(void) { return 0; } int main(void) { return f(); }'))
	assert direct.any(it.contains('call f with 0 argument(s)'))
}

// The rest of the statement and expression shapes, one dump each, so a node the
// parser can write and the printer cannot say is a failure here rather than a
// silence a reader of a dump would not notice.

fn test_a_global_is_printed_with_its_initializer_and_its_type_clause() {
	printed := lines(tree('int g = 5; int main() { return 0; }'))
	assert printed[0] == 'global g int = 5 at 1:5 : int'
}

fn test_a_global_with_no_initializer_says_it_starts_zeroed() {
	printed := lines(tree('int g; int main() { return 0; }'))
	assert printed[0].starts_with('global g int')
	assert printed[0].contains('(zeroed)')
	assert printed[0].contains(': int')
}

fn test_a_unit_with_no_declarations_says_so() {
	assert render(ast.TranslationUnit{}) == '(no declarations)'
}

fn test_a_do_while_is_named_for_the_test_that_runs_after_its_body() {
	dumped := lines(tree('int main() { int x = 0; do { x = 1; } while (x < 3); return x; }'))
	assert dumped.any(it.contains('do at'))
	// The test is the condition written after the body, and a do-while has no
	// step of its own, which is the difference the two headings read.
	assert dumped.any(it.contains('condition'))
	assert !dumped.any(it.contains('step'))
}

fn test_a_switch_prints_its_labels_in_the_order_they_were_written() {
	dumped := lines(tree('int main() { switch (1) { case 1: break; default: break; } return 0; }'))
	header := line_of(dumped, 'switch at')
	case_line := line_of(dumped, 'case 1 at')
	default_line := line_of(dumped, 'default at')
	assert header >= 0
	assert case_line > header
	assert default_line > case_line
	assert dumped.any(it.contains('break at'))
}

fn test_a_goto_and_the_label_it_reaches_are_both_named() {
	dumped := lines(tree('int main() { goto out; out: return 0; }'))
	jump := line_of(dumped, 'goto out at')
	label := line_of(dumped, 'label out at')
	assert jump >= 0
	assert label > jump
}

fn test_an_asm_statement_prints_the_spelling_the_file_wrote() {
	dumped := lines(tree('int main() { __asm__ volatile ("nop" ::: "memory"); return 0; }'))
	assert dumped.any(it.contains('asm statement "nop" at'))
}

fn test_a_member_is_printed_with_the_offset_the_layout_gave_it() {
	dumped := lines(tree('struct S { int a; }; int main() { struct S s; s.a = 1; return s.a; }'))
	assert dumped.any(it.contains('member s.a at +0 bytes, int, at'))
}

fn test_a_comma_expression_prints_both_sides() {
	dumped := lines(tree('int main() { int x = 1; int y = (x, 2); return y; }'))
	comma := line_of(dumped, 'comma at')
	assert comma >= 0
	assert dumped[comma + 1].contains('ident x')
	assert dumped[comma + 2].contains('int 2')
}

fn test_a_statement_expression_prints_its_body_before_its_value() {
	dumped := lines(tree('int main() { int y = ({ int x = 4; x; }); return y; }'))
	header := line_of(dumped, 'statement expression at')
	assert header >= 0
	declaration := line_of(dumped, 'declaration of int x')
	assert declaration > header
}

fn test_a_string_literal_prints_its_spelling_and_its_array_type() {
	dumped := lines(tree('int main() { char *s = "hi"; return 0; }'))
	assert dumped.any(it.contains('string "hi" at'))
	assert dumped.any(it.contains(': char[3]'))
}

fn test_an_array_declaration_prints_its_element_count() {
	dumped := lines(tree('int main() { int a[3]; return a[1]; }'))
	assert dumped.any(it.contains('declaration of int a[3] at'))
	assert dumped.any(it.contains('element[] at'))
}

fn test_a_cast_prints_the_type_it_converts_to() {
	dumped := lines(tree('int main() { int x = 1; int y = (char)x; return y; }'))
	assert dumped.any(it.contains('cast to char at'))
}

fn test_a_conditional_prints_its_three_operands_in_order() {
	dumped := lines(tree('int main() { int x = 1; int y = x ? 1 : 2; return y; }'))
	header := line_of(dumped, 'conditional at')
	assert header >= 0
	assert dumped[header + 1].contains('ident x')
	assert dumped[header + 2].contains('int 1')
	assert dumped[header + 3].contains('int 2')
}

fn test_an_increment_prints_its_form_beside_its_operator() {
	dumped := lines(tree('int main() { int x = 1; x++; ++x; return x; }'))
	assert dumped.any(it.contains('postfix ++ at'))
	assert dumped.any(it.contains('prefix ++ at'))
}

fn test_an_assignment_expression_prints_its_operator() {
	dumped := lines(tree('int main() { int x = 1; int y = (x = 2); return y; }'))
	assert dumped.any(it.contains('assign = at'))
}
