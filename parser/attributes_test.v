module parser

import tokenize

// attributes_of parses a stream for one of these cases, the same way the
// declaration tests parse theirs: a source string in, the declarations and the
// diagnostics out.
fn attributes_of(source string) Result {
	return parse(tokenize.lex(source).tokens)
}

// These tests are the GNU attributes as V's generated C writes them: in front of
// a declaration's specifiers. The two that change the object this compiler emits
// are read wherever a declaration carries them, and every other name is refused
// by name at the place it was written, because an attribute this compiler does
// not implement is a claim about the object it cannot keep.

// `__attribute__((weak))` on a definition is the shape at line 2399 of V's
// generated C. It asks for a weak symbol binding, and the declaration records it
// so the object can say so; nothing is refused, because the binding is one this
// compiler can emit.
fn test_a_weak_attribute_in_front_of_a_definition_is_recorded() {
	result := attributes_of('__attribute__((weak)) void vheap_alloc(void* p, unsigned long long n) {\n\t(void)p;\n\t(void)n;\n}\n')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].name == 'vheap_alloc'
	assert result.unit.decls[0].weak
}

// The same attribute on a prototype, which is a declaration rather than a
// definition: it is still what the declaration asked for.
fn test_a_weak_attribute_on_a_prototype_is_recorded() {
	result := attributes_of('__attribute__((weak)) int f(void);')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 1
	assert result.unit.decls[0].weak
	assert !result.unit.decls[0].defined
}

// GNU writes the name with double underscores around it as freely as without, and
// the two are one attribute. gcc 16.2.1 reads `__weak__` the same way.
fn test_the_underscored_spelling_of_weak_is_the_same_attribute() {
	result := attributes_of('__attribute__((__weak__)) int f(void) { return 1; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].weak
}

// `noreturn`, `noinline` and `dllimport` say nothing this target's object shows:
// gcc 16.2.1 on Linux accepts all three and emits the same object without them.
// This compiler accepts them the same way, and they leave the declaration alone.
fn test_the_attributes_that_change_nothing_are_accepted() {
	result := attributes_of('__attribute__((noreturn)) void die(void) {}\n__attribute__((noinline)) int g(void) { return 2; }\n__attribute__((dllimport)) int h(void) { return 3; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls.len == 3
	assert !result.unit.decls[0].weak
	assert !result.unit.decls[1].weak
}

// A list may carry more than one attribute, separated by commas.
fn test_a_list_of_attributes_is_read_together() {
	result := attributes_of('__attribute__((weak, noinline)) int f(void) { return 0; }')
	assert result.diagnostics.len == 0
	assert result.unit.decls[0].weak
}

// `aligned(N)` on an object at file scope is a layout request the object keeps:
// the alignment travels on the object so the image can place it there.
fn test_aligned_on_a_top_level_object_is_recorded() {
	result := attributes_of('__attribute__((aligned(16))) int g = 3;')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].name == 'g'
	assert result.unit.globals[0].alignment == 16
}

// An attribute after the declarator belongs to the same declaration, and the two
// that change the object are read there too: `int g __attribute__((aligned(32)));`
// asks for the same alignment as the spelling in front of the specifiers.
fn test_an_attribute_after_the_declarator_is_read() {
	result := attributes_of('int g __attribute__((aligned(32))) = 1;')
	assert result.diagnostics.len == 0
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].alignment == 32
}

// An attribute this compiler does not implement is refused by name with its
// location. `packed` asks for a layout this compiler does not write, so reading
// past it would emit an object the program's author asked to be something else.
fn test_an_unimplemented_attribute_is_refused_by_name_with_its_location() {
	result := attributes_of('__attribute__((packed)) int x = 1;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == "unsupported: the attribute 'packed' is not implemented"
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 16
}

// `section` names a part of the object this compiler does not place objects in,
// and it is refused the same way rather than silently dropped.
fn test_an_attribute_that_asks_for_a_section_is_refused_by_name() {
	result := attributes_of('__attribute__((section("x"))) int sec = 1;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg == "unsupported: the attribute 'section' is not implemented"
	assert result.diagnostics[0].line == 1
	assert result.diagnostics[0].col == 16
}

// `aligned` with no argument asks for the strictest alignment the target has,
// which the declaration does not write a number for. It is refused rather than
// guessed at, and the refusal names what it could not read.
fn test_aligned_with_no_argument_is_refused() {
	result := attributes_of('__attribute__((aligned)) int x = 1;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains("the attribute 'aligned'")
	assert result.diagnostics[0].line == 1
}

// A written alignment that is not an integer this compiler can read is refused
// rather than rounded to one. gcc 16.2.1 refuses `aligned(3)` as `requested
// alignment is not a power of 2`.
fn test_an_alignment_that_is_not_a_power_of_two_is_refused() {
	result := attributes_of('__attribute__((aligned(3))) int x = 1;')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains("the attribute 'aligned'")
}

// A refusal is a diagnostic, not a silent skip: the declaration is still read to
// its end so the reader does not lose its place, and it is the diagnostic that
// keeps the image from being written. The object is in the tree and nothing is
// emitted for it.
fn test_an_unimplemented_attribute_is_a_diagnostic_not_a_skip() {
	result := attributes_of('__attribute__((packed)) int x = 1;')
	assert result.diagnostics.len == 1
	assert result.unit.globals.len == 1
	assert result.unit.globals[0].name == 'x'
	assert result.unit.globals[0].alignment == 0
}

// `__attribute__((cleanup(name)))` on a declaration inside a function records
// the function to run on the object when the block the object was declared in
// ends. The name is read at the attribute and the statement it sits on carries
// it, which is what the back end places the call from.
fn test_a_cleanup_attribute_names_the_function_the_block_runs() {
	result := attributes_of('void mark(int *p) {\n\t(void)p;\n}\nvoid f(void) {\n\t__attribute__((cleanup(mark))) int x = 1;\n\t(void)x;\n}\n')
	assert result.diagnostics.len == 0
	body := result.unit.decls[1].body
	assert body[0].kind == .var_decl
	assert body[0].decl_name == 'x'
	assert body[0].cleanup() == 'mark'
}

// The attribute names one function and nothing else. An argument that is not a
// single name is refused by name rather than read as some other function.
fn test_a_cleanup_attribute_that_names_no_function_is_refused() {
	result := attributes_of('void f(void) {\n\t__attribute__((cleanup(1 + 2))) int x = 1;\n\t(void)x;\n}\n')
	assert result.diagnostics.len == 1
	assert result.diagnostics[0].msg.contains("the attribute 'cleanup'")
}

// The call runs where the block ends, so the object has to have automatic
// storage duration: a static object outlives the block and an extern one has no
// block here at all. Both are refused rather than given a call at a scope the
// object does not leave.
fn test_a_cleanup_attribute_on_an_object_that_is_not_automatic_is_refused() {
	held := attributes_of('void mark(int *p) {\n\t(void)p;\n}\nvoid f(void) {\n\tstatic __attribute__((cleanup(mark))) int x = 1;\n\t(void)x;\n}\n')
	assert held.diagnostics.len == 1
	assert held.diagnostics[0].msg.contains('automatic storage duration')
	external := attributes_of('void mark(int *p) {\n\t(void)p;\n}\nvoid f(void) {\n\textern __attribute__((cleanup(mark))) int x;\n\t(void)x;\n}\n')
	assert external.diagnostics.len == 1
	assert external.diagnostics[0].msg.contains('automatic storage duration')
}
