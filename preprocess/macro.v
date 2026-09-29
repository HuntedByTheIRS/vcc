module preprocess

import tokenize

// One #define, remembered the way C remembers it: a name, the parameters it
// takes if any, and the token list its uses are replaced with.
pub struct Macro {
pub:
	name string
	// function_like says the definition had a parameter list. It is not the
	// same question as `params.len > 0`: `#define C() ...` takes no parameters
	// and is still a macro that has to be called, and `C(1)` is a mistake to
	// report rather than a name to expand with a bracket left standing after it.
	function_like bool
	// params is empty for an object-like macro. For a function-like one it is
	// the parameter names in order, and variadic is set when the list ended
	// with `...`.
	params   []string
	variadic bool
	body     []tokenize.Token
	// file, line and col are where the definition was written, which is what a
	// diagnostic about the macro has to point at.
	file string
	line int
	col  int
}

// takes_arguments is what tells the two shapes apart: a name that must be
// followed by a parenthesised argument list, and a name that expands on its
// own.
pub fn (m Macro) takes_arguments() bool {
	return m.function_like
}
