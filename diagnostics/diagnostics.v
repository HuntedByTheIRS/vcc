module diagnostics

// A diagnostic is one thing the compiler has to say about a program, and a class
// says which kind of thing it is: whether the program is wrong, whether it is
// asking for something the selected dialect does not have, or whether the
// standard requires a diagnostic for it that the flags may promote.
//
// The class is what a -W flag names, and the severity the command line gives a
// class is the whole of what those flags decide. Nothing else in the compiler
// needs to know which spelling asked for it.
pub enum Class {
	// cpp is a diagnostic a directive asked for, with #warning, and the class
	// any diagnostic the compiler raises on its own account lands in. It is
	// reported whether or not anything was asked for on the command line; the
	// name is gcc's for the same class.
	cpp
	// pedantic is a construct the selected dialect does not allow. gcc's
	// -Wpedantic asks this question under the same name, so the name matches.
	pedantic
	// required is a diagnostic the standard requires, which gcc reports
	// whether or not anything was asked for and which -pedantic-errors turns
	// into an error. gcc has no -W name for it, which is why -Wno-pedantic
	// leaves it alone, and that is measured rather than assumed: for an
	// unknown escape sequence gcc 16.2.1 prints `warning: unknown escape
	// sequence` under -std=c99, the same under -std=c99 -Wno-pedantic, and
	// `error:` with exit 1 under -std=c99 -pedantic-errors. The class is not
	// in flag_classes for that reason: there is no spelling to name it by.
	required
	// discarded_qualifiers is the constraint 6.5.16.1 puts on a pointer
	// assignment whose target points to a type missing a qualifier the source
	// points to, which 6.8.6.2 and 6.3.2.3 repeat for a return. gcc reports
	// it as a warning and still compiles the program: measured on gcc 16.2.1,
	// `const int *p; int *q = p;` is `warning: initialization discards
	// 'const' qualifier from pointer target type` and the image runs, exit 0.
	// It is the class `required` describes and unlike that one it has a
	// spelling, -Wdiscarded-qualifiers, so a caller can name it and -w or
	// -Wno-discarded-qualifiers can silence it. -pedantic-errors promotes it
	// the same way, measured: the same program is `error:` with exit 1 under
	// -std=c99 -pedantic-errors.
	discarded_qualifiers
}

// Severity is what to do with one class of diagnostic: print it as a warning,
// print it as an error, or say nothing. `.silent` is not the absence of a
// severity: it is the answer `-w` and `-Wno-name` give.
pub enum Severity {
	silent
	warning
	error
}

// flag_classes maps the name a -W flag carries to the class it names: -Wpedantic
// is the pedantic class reported as a warning and -Wno-pedantic is the same
// class silenced. A name that is not here is a flag about something this
// compiler does not classify, and the command line records it rather than
// refusing it, because a compiler V hands flags to must not fail on one it does
// not implement.
const flag_classes = {
	'cpp':                  Class.cpp
	'pedantic':             Class.pedantic
	'discarded-qualifiers': Class.discarded_qualifiers
}

// class_of answers the class a -W name names, when it names one.
pub fn class_of(name string) ?Class {
	if name in flag_classes {
		return flag_classes[name]
	}
	return none
}

// default_severity is what a class is before the command line says anything
// about it. The diagnostic the compiler has always reported stays reported; a
// pedantic message is a question about the dialect, and nobody asked until
// -Wpedantic was written.
fn default_severity(class Class) Severity {
	return match class {
		.cpp { .warning }
		// The standard requiring a diagnostic does not depend on a flag
		// having been written, so this class is reported on its own account;
		// what -pedantic-errors decides is whether it stops the compile.
		.required { .warning }
		// gcc reports a discarded qualifier without being asked, the same
		// way, and compiles the program: measured, the warning is printed
		// under -std=c99 with no warning flag written and the image runs.
		.discarded_qualifiers { .warning }
		.pedantic { .silent }
	}
}

// Mention is one -W flag as it was written: the class it names and what it asks
// for that class. Mentions are kept in order, because the last one about a class
// is the one that counts.
pub struct Mention {
pub:
	class    Class
	severity Severity
}

// Policy is the command line's answer to "what do I do with this kind of
// diagnostic", built by handing it the flags in the order they were written.
//
// Two flags are not mentions because their position does not matter, which is
// measured rather than assumed: gcc silences a pedantic diagnostic that
// -pedantic-errors promoted to an error whichever side of it -w was written on,
// so -w is a property of the policy and not a mention in the list.
pub struct Policy {
pub mut:
	// suppress is -w: every class the policy can silence is silenced,
	// including one a promotion turned into an error. A diagnostic that is an
	// error on its own is not the policy's to silence, and a caller asking
	// about one has already made a mistake.
	suppress bool
	// mentions are the -W flags in the order they were written.
	mentions []Mention
}

// accept reads one command-line argument and reports whether it is a diagnostic
// flag, so the command line parser can hand every -W spelling to this module
// instead of keeping a list of class names of its own.
//
// The spellings are gcc's, because they are what a build writes: -W<name>,
// -Wno-<name>, -Werror=<name>, -pedantic, -pedantic-errors, and -w. A flag
// naming something this compiler does not classify is not accepted here: it
// falls through to the command line and is recorded, which keeps -Wl,... and
// -Werror=implicit-function-declaration accepted and acted on by nobody.
pub fn (mut p Policy) accept(arg string) bool {
	if arg == '-w' {
		p.suppress = true
		return true
	}
	if arg == '-pedantic' {
		p.mentions << Mention{
			class:    .pedantic
			severity: .warning
		}
		return true
	}
	if arg == '-pedantic-errors' {
		// gcc's -pedantic-errors is -pedantic and -Werror=pedantic in one
		// flag: it asks for the diagnostic and makes it an error. It is also
		// what promotes the class the standard requires a diagnostic for,
		// which is a class of its own because gcc reports that one without
		// being asked: measured on gcc 16.2.1, an unknown escape sequence is
		// a warning under -std=c99 and an error under -std=c99
		// -pedantic-errors, with -Wno-pedantic leaving it a warning.
		p.mentions << Mention{
			class:    .pedantic
			severity: .error
		}
		p.mentions << Mention{
			class:    .required
			severity: .error
		}
		// A discarded qualifier is a constraint the standard requires a
		// diagnostic for, and gcc promotes it the same way: measured, the
		// warning becomes `error:` with exit 1 under -std=c99 -pedantic-errors.
		p.mentions << Mention{
			class:    .discarded_qualifiers
			severity: .error
		}
		return true
	}
	if arg.starts_with('-Werror=') {
		class := class_of(arg[8..]) or { return false }
		p.mentions << Mention{
			class:    class
			severity: .error
		}
		return true
	}
	if arg.starts_with('-Wno-') {
		class := class_of(arg[5..]) or { return false }
		p.mentions << Mention{
			class:    class
			severity: .silent
		}
		return true
	}
	if arg.starts_with('-W') && arg.len > 2 {
		class := class_of(arg[2..]) or { return false }
		p.mentions << Mention{
			class:    class
			severity: .warning
		}
		return true
	}
	return false
}

// severity answers what to do with one class after the whole command line has
// been read. Ordered mentions are folded from the first to the last, so the last
// mention of a class wins, and -w silences every class it can silence.
pub fn (p Policy) severity(class Class) Severity {
	if p.suppress {
		return .silent
	}
	mut out := default_severity(class)
	for mention in p.mentions {
		if mention.class == class {
			out = mention.severity
		}
	}
	return out
}

// without_promotion is the policy a run that only asks the preprocessor a
// question is reported under: the same flags, the same order, the same
// silenced classes, with every promotion to an error taken back down to a
// warning. Such a run writes what it was asked for — the rule -M asked for, the
// token stream -E asked for, the macros -dM asked for — and has no compile for
// an error to stop, so a message a flag asked to be told about is still worth
// printing and nothing about the read is worth losing over it.
//
// It is measured from gcc rather than chosen: gcc's front end reports nothing
// at all in that run, `gcc -std=c99 -pedantic-errors -M` over a file its own
// `-fsyntax-only` refuses exits 0 and writes the rule, and `-E` writes the
// preprocessed text with empty stderr. vcc keeps the message and takes the
// verdict back, because a diagnostic the command line asked for should not be
// dropped for a run whose output no verdict could change.
pub fn (p Policy) without_promotion() Policy {
	mut mentions := []Mention{cap: p.mentions.len}
	for mention in p.mentions {
		mentions << Mention{
			class:    mention.class
			severity: if mention.severity == .error { .warning } else { mention.severity }
		}
	}
	return Policy{
		suppress: p.suppress
		mentions: mentions
	}
}

// render writes one diagnostic the way this compiler writes them:
//
//	file.c:12:5: warning: a variable read before it was written
//	file.c:12:5: something that stopped the compile
//
// It is the one place a diagnostic becomes text. An error is printed without a
// label because that is the shape this compiler has always printed one in, and a
// program reading the output should not have to learn a second shape because the
// class machinery arrived. Whether a diagnostic is printed at all is the
// caller's question, asked of `severity`; a silent severity renders without a
// label, which is what a caller that decided to print it anyway would get.
pub fn render(where string, line int, col int, severity Severity, msg string) string {
	label := match severity {
		.warning { 'warning: ' }
		.error, .silent { '' }
	}
	return '${where}:${line}:${col}: ${label}${msg}'
}
