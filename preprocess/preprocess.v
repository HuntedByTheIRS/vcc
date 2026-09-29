module preprocess

import os
import tokenize

// The preprocessor reads a file and everything it includes and hands the parser
// one token stream: directives are consumed, macros are expanded, and text
// inside a conditional that was not taken never reaches the parser.
//
// It drives the lexer rather than the other way around, because the unit of
// work is a file. One file is lexed, an #include line opens another, and the
// tokens that come out carry the file, line and column of the text they were
// written at, which is what a diagnostic has to point at. An include is an
// insertion and not a call: the file goes on a stack and the text after the
// #include waits until the file's last token has been read.

pub struct Options {
pub mut:
	// include_dirs are the -I directories, in the order they were given.
	include_dirs []string
	// defines and undefines are the -D and -U arguments, applied to the macro
	// table before the first file is read.
	defines   []string
	undefines []string
	// standard_dirs are the system directories, searched for either spelling
	// after the -I ones. They arrive from the command line because where a
	// machine keeps its headers is the command line's business — -nostdinc is
	// the same decision — and what belongs here is only the order they are
	// searched in.
	standard_dirs []string
}

// max_include_depth is how many files may be open at once before the
// preprocessor decides the includes are not going to end. A file that includes
// itself with no guard is a loop, and the alternative to a limit is running out
// of memory instead of saying so.
const max_include_depth = 200

// max_expansion_depth is the same kind of limit for macro expansion, which is
// recursive: a replacement that keeps producing text to expand would be a
// stack overflow without it.
const max_expansion_depth = 200

// hash is the character a directive line starts with. The gate reads the bare
// spelling of the include directive in a V source as C interop — which is what
// it is when a V program asks for a C header — so the messages that have to
// show the directive build the line from parts.
const hash = '#'

// Result is a preprocess of one translation unit: the stream the parser
// consumes, plus everything that went wrong on the way.
pub struct Result {
pub:
	tokens      []tokenize.Token
	diagnostics []tokenize.Diagnostic
}

// preprocess reads one source file into the token stream the parser takes.
pub fn preprocess(source string, path string, opts Options) Result {
	mut p := Processor{
		macros:     map[string]Macro{}
		once_files: map[string]bool{}
		main_path:  path
		opts:       opts
	}
	p.define_builtins()
	p.apply_command_line_defines()
	p.push(path, source, -1)
	p.run()
	return Result{
		tokens:      p.out
		diagnostics: p.diagnostics
	}
}

// Frame is one open file: the path its tokens are reported under, the tokens
// themselves, how far the reader has walked them, and how deep the conditional
// stack was when the file opened, so a file that ends inside an #if can say so.
struct Frame {
mut:
	path            string
	tokens          []tokenize.Token
	pos             int
	condition_depth int
	// found_index is where in the search list this file was found, so that an
	// `include_next` in it knows what comes after it. A file that did not come
	// from the list — the file the compiler was handed, or one found beside its
	// includer — is -1.
	found_index int
}

// Conditional is one #if being read. A branch that is not taken still has to be
// followed, because an #else flips it and the #endif closes it, and the nested
// ones need a stack of their own state to stay straight.
struct Conditional {
mut:
	// parent is whether the text around this conditional is read at all.
	parent bool
	// taken is whether the text this branch covers is read.
	taken bool
	// any_taken is whether some branch of this conditional has been taken, so
	// an #elif or an #else knows it must not be.
	any_taken bool
	// seen_else marks the #else, after which no other branch may come.
	seen_else bool
	file      string
	line      int
	col       int
}

struct Processor {
mut:
	frames       []Frame
	macros       map[string]Macro
	conditionals []Conditional
	// once_files are the files that asked to be read at most once, which is
	// what `#pragma once` says. An include guard has no entry here: it is
	// macro state, and the macro table already keeps that.
	once_files map[string]bool
	// main_path is the file the compiler was handed, which is what
	// __BASE_FILE__ names however deep an include is being read.
	main_path string
	// expanding is the stack of macro names being expanded right now. A name
	// already on it is left alone, which is what keeps `#define A B` beside
	// `#define B A` from expanding forever.
	expanding []string
	// expansion_depth is how deep in the expansion recursion the reader is, and
	// expansion_reported says whether the depth limit has been reported once
	// already, so the report does not repeat for every token after it.
	expansion_depth    int
	expansion_reported bool
	out                []tokenize.Token
	diagnostics        []tokenize.Diagnostic
	opts               Options
}

// apply_command_line_defines puts the -D and -U arguments into the macro table
// before any file is read, which is the order C asks for: a -D is as if the
// definition had been written at the top of the translation unit. -Dname=value
// defines the name with that replacement and a bare -Dname defines it empty.
//
// The two lists are applied in the order they arrive rather than in the order
// they were written on the command line, so `-D N=1 -U N -D N=2` ends with N
// undefined here; a command line that mixes them in that way is rare enough to
// wait for the day it matters.
fn (mut p Processor) apply_command_line_defines() {
	for define in p.opts.defines {
		mut name := define
		mut body := ''
		if at := define.index('=') {
			name = define[..at]
			body = define[at + 1..]
		}
		p.macros[name] = Macro{
			name: name
			body: tokenize.lex_fragment(body)
			file: '<command line>'
			line: 1
			col:  1
		}
	}
	for name in p.opts.undefines {
		if name in p.macros {
			p.macros.delete(name)
		}
	}
}

// include is one #include line. It works out which file the line names, finds
// it, and opens it — nothing is written for the line itself, because an include
// is an insertion: the file's tokens take the line's place in the stream.
//
// `after` is the other spelling, the one that ends in _next: it is for a header
// installed in more than one place, where one copy wants the one that follows
// it in the search order rather than the one that was found.
fn (mut p Processor) include(tok tokenize.Token, args string, after bool) {
	if p.frames.len >= max_include_depth {
		p.problem(tok, 'includes are ${max_include_depth} files deep and still going; a file that includes itself with nothing to stop it is the shape of this')
		return
	}
	mut tokens := tokenize.lex_fragment(args)
	if tokens.len > 0 && tokens[0].kind == .identifier {
		// A computed include: `NAME`, where NAME is a macro that stands for the
		// name of the file. The expansion is the same one the text gets, so what
		// is read here is what would have been written.
		tokens = p.expand_all(tokens)
	}
	if tokens.len == 0 {
		p.problem(tok, '${hash}include names no file')
		return
	}
	mut name := ''
	mut angled := false
	if tokens[0].kind == .string {
		name = unquoted_name(tokens[0].text)
	} else if tokens[0].kind == .punct && tokens[0].text == '<' {
		angled = true
		// What is between the angle brackets was lexed as several tokens —
		// `bits/types.h` is a name, a slash, a name and a dot — and C says the
		// characters between the brackets are the name of the file.
		mut i := 1
		for i < tokens.len && !(tokens[i].kind == .punct && tokens[i].text == '>') {
			name += tokens[i].text
			i++
		}
		if i >= tokens.len {
			p.problem(tok, '${hash}include has a < with no >')
			return
		}
	} else {
		p.problem(tok, '${hash}include wants a "file" or a <file>, not ${tokens[0].text}')
		return
	}
	if name == '' {
		p.problem(tok, '${hash}include names no file')
		return
	}
	from := p.frames.last().path
	found := p.find_include(name, angled, from, after) or {
		looked := p.searched_dirs(angled, from, after)
		if looked.len == 0 {
			p.problem(tok, 'cannot find ${include_name(name, angled)}, and there is no directory after the one this file was found in to look in')
			return
		}
		p.problem(tok, 'cannot find ${include_name(name, angled)}; looked in ${looked.join(', ')}')
		return
	}
	if found.path in p.once_files {
		// The file asked for `#pragma once` when it was read before.
		return
	}
	source := os.read_file(found.path) or {
		p.problem(tok, 'cannot read ${found.path}')
		return
	}
	p.push(found.path, source, found.index)
}

// Located is a header the search found: the path to read, and where in the
// search list it was found. That index is where an `include_next` in the file
// starts from. A file found beside its includer rather than in the list comes
// back as -1, which is also what the file the compiler was handed reports.
struct Located {
	path  string
	index int
}

// find_include looks for a header the way C says to: one written with quotes is
// looked for beside the file that wrote the line before it is looked for
// anywhere else, one written with angle brackets is not, and after that both
// come to the -I directories and then the standard ones.
//
// `after` leaves out both the directory beside the includer and the directories
// up to and including the one this file was found in. That is the whole of what
// the include_next spelling means, and it is what lets a header that is
// installed twice hand the rest of its contents to the copy that follows it.
fn (mut p Processor) find_include(name string, angled bool, from string, after bool) ?Located {
	if !angled && !after {
		beside := os.join_path(os.dir(from), name)
		if os.is_file(beside) {
			return Located{
				path:  beside
				index: -1
			}
		}
	}
	dirs := p.search_dirs()
	mut start := 0
	if after {
		start = p.frames.last().found_index + 1
	}
	for i := start; i < dirs.len; i++ {
		candidate := os.join_path(dirs[i], name)
		if os.is_file(candidate) {
			return Located{
				path:  candidate
				index: i
			}
		}
	}
	return none
}

// search_dirs is the list the index in a Located counts in: the -I directories
// in the order they were given, and then the standard ones.
fn (p Processor) search_dirs() []string {
	mut dirs := []string{cap: p.opts.include_dirs.len + p.opts.standard_dirs.len}
	dirs << p.opts.include_dirs
	dirs << p.opts.standard_dirs
	return dirs
}

// searched_dirs is what a diagnostic about a header that was not found has to
// say: the places that were looked in, in the order they were looked in, which
// is the search minus whatever the line left out.
fn (p Processor) searched_dirs(angled bool, from string, after bool) []string {
	mut dirs := []string{}
	if !angled && !after {
		dirs << os.dir(from)
	}
	all := p.search_dirs()
	mut start := 0
	if after {
		start = p.frames.last().found_index + 1
	}
	for i := start; i < all.len; i++ {
		dirs << all[i]
	}
	return dirs
}

// unquoted_name takes the quotes off `"file.h"`. C says the characters between
// the quotes are the name of the file, with no escape processing of the kind a
// string literal gets.
fn unquoted_name(text string) string {
	if text.len >= 2 && text[0] == `"` && text[text.len - 1] == `"` {
		return text[1..text.len - 1]
	}
	return text
}

// include_name spells a header name the way the line did, which is how a
// diagnostic about it should say it.
fn include_name(name string, angled bool) string {
	return if angled { '<${name}>' } else { '"${name}"' }
}

fn (mut p Processor) push(path string, source string, found_index int) {
	lexed := tokenize.lex(source)
	for diagnostic in lexed.diagnostics {
		p.diagnostics << tokenize.Diagnostic{
			line: diagnostic.line
			col:  diagnostic.col
			msg:  diagnostic.msg
			file: path
		}
	}
	p.frames << Frame{
		path:            path
		tokens:          lexed.tokens
		condition_depth: p.conditionals.len
		found_index:     found_index
	}
}

fn (mut p Processor) run() {
	for p.frames.len > 0 {
		i := p.frames.len - 1
		if p.frames[i].pos >= p.frames[i].tokens.len {
			p.pop(i)
			continue
		}
		// One run of text: everything up to the next directive or the end of
		// the file. It is expanded as a run rather than a token at a time,
		// because that is what lets a use reach past itself for its arguments
		// and what lets the text after a replacement finish a use that the
		// replacement started.
		mut segment := []tokenize.Token{}
		for p.frames[i].pos < p.frames[i].tokens.len {
			t := p.frames[i].tokens[p.frames[i].pos]
			if t.kind == .directive || t.kind == .eof {
				break
			}
			segment << t
			p.frames[i].pos++
		}
		if segment.len > 0 && p.reading() {
			for expanded in p.expand_all(segment) {
				p.emit(expanded)
			}
		}
		if p.frames[i].pos < p.frames[i].tokens.len {
			tok := p.frames[i].tokens[p.frames[i].pos]
			p.frames[i].pos++
			if tok.kind == .eof {
				p.pop(i)
				continue
			}
			p.directive(tok)
		}
	}
}

// pop closes the file on top of the stack. A file that ends inside an #if is a
// file the preprocessor cannot account for, so it says so instead of carrying
// the conditional into whatever is read next.
fn (mut p Processor) pop(index int) {
	frame := p.frames[index]
	if p.conditionals.len > frame.condition_depth {
		mut innermost := p.conditionals[frame.condition_depth]
		p.problem_at(frame.path, innermost.line, innermost.col,
			'unterminated #if: ${frame.path} ends inside it')
		p.conditionals = p.conditionals[..frame.condition_depth]
	}
	p.frames.delete(index)
}

// reading is true when every open conditional has taken its branch.
fn (p Processor) reading() bool {
	for conditional in p.conditionals {
		if !conditional.taken {
			return false
		}
	}
	return true
}

// directive reads one line that started with a hash. The text still holds the
// hash and the rest of the line as it was written; the name is read off the
// front and everything after it is the directive's own business.
fn (mut p Processor) directive(tok tokenize.Token) {
	trimmed := tok.text[1..].trim_left(' 	')
	// A line marker, `# 1 "file.c"`, is how a preprocessed stream says where
	// the text that follows came from. The compiler reads them and has no use
	// for them: every token it produces already carries its own file and line.
	// The check is on the first character rather than on the name, because a
	// digit is not an identifier and there is no directive that starts with one.
	if trimmed.len > 0 && is_digit(trimmed[0]) {
		return
	}
	name := directive_name(trimmed)
	args := trimmed[name.len..]
	// The conditionals decide whether the text around them is read at all, so
	// they are read whether or not anything around them is: an #if inside a
	// branch that was not taken still has to be followed to its #endif.
	match name {
		'if' { p.if_directive(tok, args) }
		'ifdef' { p.ifdef_directive(tok, args, false) }
		'ifndef' { p.ifdef_directive(tok, args, true) }
		'elif' { p.elif_directive(tok, args) }
		'else' { p.else_directive(tok) }
		'endif' { p.endif_directive(tok) }
		else {
			if !p.reading() {
				return
			}
			p.text_directive(tok, name, args)
		}
	}
}

// if_directive opens a conditional whose first branch is taken when its
// expression is not zero. The expression is only read when the text around it
// is being read: a `#if` inside a branch that was not taken must not be
// evaluated, and a name in it must not be reported as anything.
fn (mut p Processor) if_directive(tok tokenize.Token, args string) {
	parent := p.reading()
	mut taken := false
	if parent {
		value := p.if_value(tok, args) or { 0 }
		taken = value != 0
	}
	p.conditionals << Conditional{
		parent:    parent
		taken:     taken
		any_taken: taken
		file:      p.frames.last().path
		line:      tok.line
		col:       tok.col
	}
}

fn (mut p Processor) ifdef_directive(tok tokenize.Token, args string, negated bool) {
	parent := p.reading()
	mut taken := false
	if parent {
		tokens := tokenize.lex_fragment(args)
		if tokens.len == 0 || tokens[0].kind != .identifier {
			p.problem(tok, 'expected an identifier after #${if negated { 'ifndef' } else { 'ifdef' }}')
		} else {
			defined := tokens[0].text in p.macros
			taken = if negated { !defined } else { defined }
		}
	}
	p.conditionals << Conditional{
		parent:    parent
		taken:     taken
		any_taken: taken
		file:      p.frames.last().path
		line:      tok.line
		col:       tok.col
	}
}

fn (mut p Processor) elif_directive(tok tokenize.Token, args string) {
	if p.conditionals.len == 0 {
		p.problem(tok, '#elif with no #if to belong to')
		return
	}
	i := p.conditionals.len - 1
	if p.conditionals[i].seen_else {
		p.problem(tok, '#elif after #else')
		return
	}
	mut taken := false
	if p.conditionals[i].parent && !p.conditionals[i].any_taken {
		value := p.if_value(tok, args) or { 0 }
		taken = value != 0
	}
	p.conditionals[i].taken = taken
	if taken {
		p.conditionals[i].any_taken = true
	}
}

fn (mut p Processor) else_directive(tok tokenize.Token) {
	if p.conditionals.len == 0 {
		p.problem(tok, '#else with no #if to belong to')
		return
	}
	i := p.conditionals.len - 1
	if p.conditionals[i].seen_else {
		p.problem(tok, '#else after #else')
		return
	}
	p.conditionals[i].seen_else = true
	taken := p.conditionals[i].parent && !p.conditionals[i].any_taken
	p.conditionals[i].taken = taken
	if taken {
		p.conditionals[i].any_taken = true
	}
}

fn (mut p Processor) endif_directive(tok tokenize.Token) {
	if p.conditionals.len == 0 {
		p.problem(tok, '#endif with no #if to close')
		return
	}
	p.conditionals.delete(p.conditionals.len - 1)
}

// if_value evaluates the controlling expression of one #if or #elif. `defined`
// is answered before the macros around it are expanded, because what it takes
// is the name of a macro and not a use of one, and every name left after the
// expansion is a name that is not defined, which C says is zero.
fn (mut p Processor) if_value(tok tokenize.Token, args string) ?i64 {
	raw := tokenize.lex_fragment(args)
	// `defined` is answered before anything is expanded, because what it takes
	// is the name of a macro and not a use of one: it is rewritten to 1 or 0
	// here, and the expansion that follows is the ordinary one — which is what
	// lets an #if call a macro that takes arguments.
	mut answered := []tokenize.Token{}
	mut i := 0
	for i < raw.len {
		t := raw[i]
		if t.kind == .identifier && t.text == 'defined' {
			i++
			mut name := ''
			if i < raw.len && raw[i].kind == .punct && raw[i].text == '(' {
				i++
				if i < raw.len && raw[i].kind == .identifier {
					name = raw[i].text
					i++
				}
				if i < raw.len && raw[i].kind == .punct && raw[i].text == ')' {
					i++
				} else {
					p.problem(t, 'defined( has no closing )')
					return none
				}
			} else if i < raw.len && raw[i].kind == .identifier {
				name = raw[i].text
				i++
			} else {
				p.problem(t, 'defined wants the name of a macro')
				return none
			}
			answered << tokenize.Token{
				kind: .number
				text: if name in p.macros { '1' } else { '0' }
				line: t.line
				col:  t.col
				file: t.file
			}
			continue
		}
		answered << t
		i++
	}
	mut condition := Condition{
		tokens: p.expand_all(answered)
		file:   p.frames.last().path
		line:   tok.line
		col:    tok.col
	}
	value := condition.parse()
	p.diagnostics << condition.diagnostics
	return value
}

// text_directive handles the directives that do something to the text being
// read, as opposed to the ones that decide whether it is read at all.
fn (mut p Processor) text_directive(tok tokenize.Token, name string, args string) {
	match name {
		'define' { p.define(tok, args) }
		'undef' { p.undef(tok, args) }
		'error' { p.problem(tok, '#error ${args.trim_space()}') }
		'warning' { p.problem(tok, '#warning ${args.trim_space()}') }
		'include' { p.include(tok, args, false) }
		'include_next' { p.include(tok, args, true) }
		'line' { p.problem(tok, 'unsupported: #line is not implemented yet') }
		'pragma' {
			// `#pragma once` is a file saying it may be read at most once, which
			// is one of the two ways a header does that; the other is the
			// include guard, which needs no code at all because it is macro
			// state and the macro table already keeps it. Every other pragma is
			// something this compiler has nothing to say about yet.
			if args.trim_space() == 'once' {
				p.once_files[p.frames.last().path] = true
			}
		}
		else {
			if name == '' {
				// A null directive, `#` alone: nothing to do.
				return
			}
			p.problem(tok, 'unsupported: #${name} is not a directive this compiler knows')
		}
	}
}

// define reads `#define name replacement` and `#define name(params) replacement`.
// The two shapes are told apart by position, not by the tokens: a function-like
// macro is one where the `(` follows the name with nothing between them, so
// `#define F (x)` is an object-like macro whose replacement is `(x)`.
fn (mut p Processor) define(tok tokenize.Token, args string) {
	text := args.trim_left(' \t')
	tokens := tokenize.lex_fragment(text)
	if tokens.len == 0 || tokens[0].kind != .identifier {
		p.problem(tok, 'expected a macro name after #define')
		return
	}
	name := tokens[0].text
	mut params := []string{}
	mut variadic := false
	mut body_text := text[name.len..]
	if text.len > name.len && text[name.len] == `(` {
		close := text.index(')') or {
			p.problem(tok, '#define ${name}: the parameter list has no closing )')
			return
		}
		for part in text[name.len + 1..close].split(',') {
			param := part.trim_space()
			if param == '' {
				continue
			}
			if param == '...' {
				variadic = true
				continue
			}
			params << param
		}
		body_text = text[close + 1..]
	}
	p.macros[name] = Macro{
		name:     name
		params:   params
		variadic: variadic
		body:     tokenize.lex_fragment(body_text)
		file:     p.frames.last().path
		line:     tok.line
		col:      tok.col
	}
}

fn (mut p Processor) undef(tok tokenize.Token, args string) {
	tokens := tokenize.lex_fragment(args)
	if tokens.len == 0 || tokens[0].kind != .identifier {
		p.problem(tok, 'expected a macro name after #undef')
		return
	}
	if tokens[0].text in p.macros {
		p.macros.delete(tokens[0].text)
	}
}

// emit is where every token that reaches the parser goes: the file it came
// from is the file being read when it was written out, which is the frame on
// top of the stack.
fn (mut p Processor) emit(tok tokenize.Token) {
	where := if p.frames.len > 0 { p.frames.last().path } else { tok.file }
	p.out << tokenize.Token{
		kind: tok.kind
		text: tok.text
		line: tok.line
		col:  tok.col
		file: where
	}
}

fn (mut p Processor) problem(tok tokenize.Token, msg string) {
	where := if p.frames.len > 0 { p.frames.last().path } else { tok.file }
	p.problem_at(where, tok.line, tok.col, msg)
}

fn (mut p Processor) problem_at(file string, line int, col int, msg string) {
	p.diagnostics << tokenize.Diagnostic{
		line: line
		col:  col
		msg:  msg
		file: file
	}
}

// directive_name reads the identifier a directive starts with. A directive line
// that starts with anything else — a digit, as in a line marker — has no name,
// and the caller decides what to make of it.
fn directive_name(text string) string {
	mut out := ''
	for i in 0 .. text.len {
		c := text[i]
		if !is_ident_char(c) {
			break
		}
		out += c.ascii_str()
	}
	return out
}

fn is_digit(c u8) bool {
	return c >= `0` && c <= `9`
}

fn is_ident_char(c u8) bool {
	return c == `_` || (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c >= 0x80
}
