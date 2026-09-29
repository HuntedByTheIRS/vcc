module preprocess

import tokenize

// One #define, remembered the way C remembers it: a name, the parameters it
// takes if any, and the token list its uses are replaced with.
pub struct Macro {
pub:
	name string
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
	return m.params.len > 0 || m.variadic
}
