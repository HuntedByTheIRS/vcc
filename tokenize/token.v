module tokenize

// Kind says what a token is, not what it means. C keywords are spelled like
// identifiers, so `return` arrives as an identifier and the parser is the stage
// that knows it apart from a variable name.
pub enum Kind {
	eof
	identifier
	number
	character
	string
	punct
	directive
}

pub fn (k Kind) str() string {
	return match k {
		.eof { 'eof' }
		.identifier { 'identifier' }
		.number { 'number' }
		.character { 'character' }
		.string { 'string' }
		.punct { 'punct' }
		.directive { 'directive' }
	}
}

// Token carries its own location so every later stage can point at source text
// without keeping a second copy of the file. file names the source it came from,
// and it stays empty until a stage that follows more than one file — the
// preprocessor — fills it in.
pub struct Token {
pub:
	kind Kind
	text string
	line int
	col  int
	file string
}

// Diagnostic is one thing that went wrong, with the place it went wrong. The
// lexer defines it because the lexer is what gives a byte offset a line and a
// column; the parser and the back end report in the same terms. file is the
// source the location belongs to, empty when the caller already knows it.
pub struct Diagnostic {
pub:
	line int
	col  int
	msg  string
	file string
	// warning says the compiler noticed something and the program is still
	// allowed to be whatever it is. An error is a diagnostic that is not a
	// warning, and only errors stop a compile.
	warning bool
}

// errors are the diagnostics that stop the compiler: everything that is not a
// warning. A stage that hands back warnings has not failed, and counting the
// diagnostics instead of asking which kind they are is how that gets confused.
pub fn errors(diagnostics []Diagnostic) []Diagnostic {
	mut out := []Diagnostic{}
	for diagnostic in diagnostics {
		if !diagnostic.warning {
			out << diagnostic
		}
	}
	return out
}

pub fn (d Diagnostic) str() string {
	return '${d.line}:${d.col}: ${d.msg}'
}

// Result is a lex of one file: everything that lexed, plus everything that did
// not. The tokens are the ones read before the first lexical error.
pub struct Result {
pub:
	tokens      []Token
	diagnostics []Diagnostic
}
