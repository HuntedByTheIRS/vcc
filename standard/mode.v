module standard

// Mode is the language a -std= spelling names, and the language is a question
// the rest of the compiler asks of it: which constructs are standard, which
// macros describe it, which pedantic messages a program can hear.
//
// Two answers have to be kept apart. `.none` is no -std at all, which is the
// compiler's own default and not a standard it measured anything against.
// `.other` is a spelling that names a language this compiler does not
// implement. Everything it does implement is a mode here.
pub enum Mode {
	// none: no -std was given.
	none
	c89
	c99
	c11
	c17
	c23
	c29
	gnu89
	gnu99
	gnu11
	gnu17
	gnu23
	gnu29
	// other: a spelling that names a language this compiler does not
	// implement. It is recorded and nothing else. tcc accepts every spelling
	// there is, including nonsense, and a compiler V may hand any spelling to
	// must not fail on one, so a spelling nobody here recognizes is an answer
	// like any other.
	other
}

// from_spelling answers the mode a -std= spelling names. The map is total: every
// string has an answer and no spelling is an error, which is the contract the
// flag is under and the reason this returns a mode rather than an error.
//
// What the next standard is called is not settled, and the map carries both
// names for it rather than choosing: measured on gcc 16.2.1, which takes
// `-std=c2y` and `-std=gnu2y` and reports `__STDC_VERSION__ 202500L`, and
// refuses `-std=c29` and `-std=gnu29` as unrecognized options. The working name
// is the one a compiler answers to today and the year is the one the standard
// will be published under, so a program may write either.
pub fn from_spelling(spelling string) Mode {
	return match spelling {
		'c89', 'c90', 'iso9899:1990' {
			.c89
		}
		'c99', 'iso9899:1999' {
			.c99
		}
		'c11', 'iso9899:2011' {
			.c11
		}
		'c17', 'c18', 'iso9899:2017' {
			.c17
		}
		'c23', 'iso9899:2024' {
			.c23
		}
		'c29', 'c2y', 'iso9899:2029' {
			.c29
		}
		'gnu89', 'gnu90' {
			.gnu89
		}
		'gnu99' {
			.gnu99
		}
		'gnu11' {
			.gnu11
		}
		'gnu17', 'gnu18' {
			.gnu17
		}
		'gnu23' {
			.gnu23
		}
		'gnu29', 'gnu2y' {
			.gnu29
		}
		else {
			.other
		}
	}
}

// spelling is the spelling a mode is normally written as, so that a mode can be
// reported the way a command line writes it. `.none` and `.other` are not
// spellings of anything; the caller keeps the spelling the command line used.
//
// A mode with two spellings keeps the one that names the standard rather than
// the year it was published in, which is what c17 does with c18: reporting
// `.c29` as `c2y` would name the draft, and reporting `.c17` as `c18` would name
// the editorial year rather than the standard.
pub fn (m Mode) spelling() string {
	return match m {
		.c89 { 'c89' }
		.c99 { 'c99' }
		.c11 { 'c11' }
		.c17 { 'c17' }
		.c23 { 'c23' }
		.c29 { 'c29' }
		.gnu89 { 'gnu89' }
		.gnu99 { 'gnu99' }
		.gnu11 { 'gnu11' }
		.gnu17 { 'gnu17' }
		.gnu23 { 'gnu23' }
		.gnu29 { 'gnu29' }
		.none, .other { '' }
	}
}

// is_gnu says whether the mode is a GNU dialect: one of the standards above plus
// the extensions GNU C has always had, which such a dialect takes without a word
// from the command line.
pub fn (m Mode) is_gnu() bool {
	return match m {
		.gnu89, .gnu99, .gnu11, .gnu17, .gnu23, .gnu29 { true }
		else { false }
	}
}

// rank orders the modes by how much of the language they take in, which is the
// order the standards were published in. A GNU dialect ranks with the standard
// it extends: gnu11 includes everything C99 ever did.
//
// A mode missing from this match ranks below every standard, because the
// fall-through answer is -1 and `includes` reads a negative rank as a mode that
// includes nothing. That is the answer `.none` and `.other` want, and it is the
// wrong answer for a standard: a mode that is missing here refuses every
// construct the table gives a later standard, so the arm has to be written when
// the mode is.
fn (m Mode) rank() int {
	return match m {
		.c89, .gnu89 { 0 }
		.c99, .gnu99 { 1 }
		.c11, .gnu11 { 2 }
		.c17, .gnu17 { 3 }
		.c23, .gnu23 { 4 }
		.c29, .gnu29 { 5 }
		else { -1 }
	}
}

// includes says whether the mode takes in everything a construct that first
// became standard in another mode has. A mode nobody ranked, which is no -std at
// all or a spelling this compiler does not implement, includes nothing: it is
// not a standard and it asks no question of a program.
pub fn (m Mode) includes(since Mode) bool {
	if m.rank() < 0 || since.rank() < 0 {
		return false
	}
	return m.rank() >= since.rank()
}

// standard_name is what a message about this mode calls the standard the mode
// asks about: `ISO C99 forbids braced-groups within expressions`. gcc says `ISO
// C` and leaves the year out; a vcc message names it, because the year is the
// question the -std spelling asked.
pub fn (m Mode) standard_name() string {
	return match m {
		.c89, .gnu89 { 'ISO C90' }
		.c99, .gnu99 { 'ISO C99' }
		.c11, .gnu11 { 'ISO C11' }
		.c17, .gnu17 { 'ISO C17' }
		.c23, .gnu23 { 'ISO C23' }
		.c29, .gnu29 { 'ISO C29' }
		.none, .other { '' }
	}
}
