module extensions

// The vendor extensions: the constructs this compiler can be asked to accept
// that the standard it was pointed at does not have, told apart from the
// standard by a flag of their own, -fvcc-exts=.
//
// A row is a name, what the extension will bring down to an earlier mode, and
// whether the compiler honors it. Nothing is honored yet, so the flag parses
// names, reports what it was given, and changes nothing about what compiles;
// the names and their rows are here so that the flag has a surface to be
// checked against before there is anything behind it.

// Row is one extension the flag can name.
pub struct Row {
pub:
	// name is what -fvcc-exts= takes.
	name string
	// brings is what the extension brings down to an earlier mode, in one
	// line, which is what a person reading -vv or the usage wants to know
	// about a name they do not recognize.
	brings string
	// honored says whether this compiler does it yet. A name that is not
	// honored is recorded and nothing else: turning it on cannot change what
	// the compiler accepts, which is the whole of what this milestone is
	// allowed to do.
	honored bool
}

// registry is the extensions this compiler has a name for: the constructs of
// C11 and C23 that the C99 work is aimed at, which are the ones a program
// written for a newer standard needs and an extension can bring down.
pub const registry = [
	Row{
		name:    'auto'
		brings:  'the auto type specifier, which C23 added'
		honored: false
	},
	Row{
		name:    'typeof'
		brings:  'the typeof specifier, which C23 added'
		honored: false
	},
	Row{
		name:    'generic'
		brings:  'the _Generic selection, which C11 added'
		honored: false
	},
	Row{
		name:    'static-assert'
		brings:  'the _Static_assert declaration, which C11 added'
		honored: false
	},
]

// known says whether the registry has a row for a name.
pub fn known(name string) bool {
	for row in registry {
		if row.name == name {
			return true
		}
	}
	return false
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
	// show what the command line asked for rather than only what was honored.
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

// enabled_names lists the extensions that are on, in the order of the registry,
// which is what a verbose mode prints and what the dialect check is handed.
pub fn (o Options) enabled_names() []string {
	mut names := []string{}
	for row in registry {
		if o.enabled(row.name) {
			names << row.name
		}
	}
	return names
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
	mut names := ''
	if arg.starts_with('-fvcc-exts=') {
		names = arg[11..]
	} else if arg.starts_with('-fno-vcc-exts=') {
		on = false
		names = arg[14..]
	} else {
		return false
	}
	if names == '' {
		return error('${arg} names no extension')
	}
	o.recorded << arg
	for name in names.split(',') {
		if name == '' {
			return error('${arg} has an empty name in its list')
		}
		if name == 'all' {
			for row in registry {
				o.mentions << Mention{
					name: row.name
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

// unknown_name is what a command line hears for a name the registry does not
// have: the name it wrote, the names the compiler does have, and the fact that
// it honors none of them yet. Naming an extension is a request, and the answer
// a request this compiler cannot grant deserves is the reason and not a silent
// build without it.
fn unknown_name(name string) string {
	mut names := []string{}
	for row in registry {
		names << row.name
	}
	if names.len == 0 {
		return "unknown extension '${name}': this compiler has none"
	}
	return "unknown extension '${name}': this compiler honors none yet, and the names it has are ${names.join(', ')}"
}
