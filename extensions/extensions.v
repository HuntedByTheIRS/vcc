module extensions

import standard

// The vendor extensions: the constructs this compiler can be asked to accept
// that the standard it was pointed at does not have, told apart from the
// standard by a flag of their own, -fvcc-exts=.
//
// No list of names is kept here. A name is the extension column of a feature
// row in `standard/`, read through the functions below, so a construct that
// gains an extension gains it in the table and nowhere else.

// names lists the extensions the flag can name: the names the standard table's
// rows carry, in one order that does not depend on where in the table a row
// sits, with no name twice.
pub fn names() []string {
	return standard.extension_names()
}

// known says whether the flag can name an extension.
//
// A name the table does not carry is answered here rather than collected from
// rows: false is the answer, and it is a miss the caller can report against the
// list names() hands out beside it.
pub fn known(name string) bool {
	return standard.extension_names().contains(name)
}

// brings is what an extension brings down to an earlier mode, in one line, for
// -vv and the usage text. It is the rows that name the extension read back:
// each construct's phrase and the standard that made it standard, so a row that
// changes its standard changes this line with it.
pub fn brings(name string) string {
	mut clauses := []string{}
	for feature in standard.features {
		if feature.extension != name || feature.pedantic == '' {
			continue
		}
		if feature.since == .none {
			clauses << feature.pedantic
			continue
		}
		clauses << '${feature.pedantic}, which ${feature.since.standard_name()} added'
	}
	return clauses.join('; ')
}

// Mention is one name the command line named and the state it asked for. The
// mentions are kept in order, because the last mention of a name is the one
// that counts.
struct Mention {
	name string
	on   bool
}

// Options is the extension state of one compile, built by handing it the flags
// in the order they were written.
pub struct Options {
pub mut:
	mentions []Mention
	// recorded keeps the flags as they were written, so a verbose mode can
	// show what the command line asked for rather than only what the compiler
	// acts on.
	recorded []string
}

// enabled answers whether a name is on after the whole command line has been
// read. Every extension is off unless it was named, and the last mention of a
// name wins over the ones before it.
pub fn (o Options) enabled(name string) bool {
	mut on := false
	for mention in o.mentions {
		if mention.name == name {
			on = mention.on
		}
	}
	return on
}

// enabled_names lists the extensions that are on, in the order names() gives
// them, which is what a verbose mode prints and what the dialect check is
// handed.
pub fn (o Options) enabled_names() []string {
	mut out := []string{}
	for name in names() {
		if o.enabled(name) {
			out << name
		}
	}
	return out
}

// accept reads one command-line argument and reports whether it is one of the
// extension flags: -fvcc-exts=<name>[,<name>...], -fno-vcc-exts=<name>, and
// either of them with `all` in place of the names.
//
// A name this compiler does not have is an error when the flag asks for it and
// a record when the flag turns it off. That half measures gcc, which accepts
// -Wno-<anything> and refuses -W<anything>: a build that says -fno-name about a
// compiler without that name gets what it asked for, while -fname is a request
// this compiler cannot answer, and a build that is quietly missing something it
// asked for is worse than one that is told.
pub fn (mut o Options) accept(arg string) !bool {
	mut on := true
	mut listed := ''
	if arg.starts_with('-fvcc-exts=') {
		listed = arg[11..]
	} else if arg.starts_with('-fno-vcc-exts=') {
		on = false
		listed = arg[14..]
	} else {
		return false
	}
	if listed == '' {
		return error('${arg} names no extension')
	}
	o.recorded << arg
	for name in listed.split(',') {
		if name == '' {
			return error('${arg} has an empty name in its list')
		}
		if name == 'all' {
			for every in names() {
				o.mentions << Mention{
					name: every
					on:   on
				}
			}
			continue
		}
		if !known(name) && on {
			return error(unknown_name(name))
		}
		o.mentions << Mention{
			name: name
			on:   on
		}
	}
	return true
}

// unknown_name is what a command line hears for a name this compiler does not
// have: the name it wrote and the names it does have. Naming an extension is a
// request, and the answer a request this compiler cannot grant deserves is the
// reason and not a silent build without it.
fn unknown_name(name string) string {
	offered := names()
	if offered.len == 0 {
		return "unknown extension '${name}': this compiler has none"
	}
	return "unknown extension '${name}': it is none of the names this compiler has, which are ${offered.join(', ')}"
}
