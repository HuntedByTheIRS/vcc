module cli

import os

// -external-linker hands the final link to a program on PATH. This file is the
// policy around that name: which names may be used at all, and how a name is
// turned into something runnable. The flag's spelling and its value live in
// cli.v beside every other flag; what a name means lives here.
//
// The one thing the flag may not name is a C compiler. The compiler exists to
// replace the C compiler V vendors, so a C compiler finishing C compilation is
// circular: it would link the objects this compiler emitted with the very front
// end this compiler is meant to make unnecessary, and a missing piece would be
// papered over rather than reported. The refusal names the flag it came from and
// points at a linker instead.

// c_compiler_drivers are the program names that must not be an external linker,
// with the versioned and target-prefixed spellings handled by is_c_compiler_driver.
const c_compiler_drivers = ['cc', 'gcc', 'clang', 'c++', 'tcc']

// external_linker_refusal is the message for a name that may not be the external
// linker, and none when the name is one this compiler will hand a link to. It is
// a refusal by name and not by what the name resolves to: `-print-prog-name=`
// has already made the point that a name is not a path here, and a name this
// compiler runs is a name the command line chose.
pub fn external_linker_refusal(name string) ?string {
	if is_c_compiler_driver(name) {
		return '-external-linker=${name}: a C compiler is not a linker here; name a linker such as ld or lld'
	}
	return none
}

// is_c_compiler_driver answers whether a name is a C compiler driver, including
// its versioned spellings (`gcc-13`, `clang-15`, `c++-13`), the same joined
// without a dash (`gcc13`), and a target-prefixed spelling
// (`x86_64-linux-gnu-gcc`). A name with anything else after the driver is a
// different program and not this one: `clangd` is a language server and
// `ccache` is a cache, and neither finishes a compilation it was given.
fn is_c_compiler_driver(name string) bool {
	lower := name.to_lower()
	for driver in c_compiler_drivers {
		if lower == driver {
			return true
		}
		if lower.starts_with('${driver}-') {
			return true
		}
		if lower.len > driver.len && lower.starts_with(driver) && is_version_suffix(lower[driver.len..]) {
			return true
		}
		// A triple-prefixed driver: `x86_64-linux-gnu-gcc`, and the same with
		// a version after it.
		if lower.ends_with('-${driver}') || lower.contains('-${driver}-') {
			return true
		}
	}
	return false
}

// is_version_suffix says whether text is a version and nothing else: digits and
// the dots between them. An empty string is not a version.
fn is_version_suffix(text string) bool {
	if text.len == 0 {
		return false
	}
	for ch in text {
		if ch != `.` && (ch < `0` || ch > `9`) {
			return false
		}
	}
	return true
}

// external_linker_path resolves a name to the program on PATH, or an error when
// the system does not have it. A name is a program name and not a path: a build
// that wanted a particular file can put it on PATH. The caller reports the miss
// rather than falling back to the in-house path, because a link handed to a tool
// that is not there must not become a link this compiler performs itself.
pub fn external_linker_path(name string) !string {
	return os.find_abs_path_of_executable(name)
}

// external_linker_prefix is the arguments a tool needs before the ones a link
// always takes, for a tool whose name alone does not tell it which linker it is.
//
// `lld` is the LLVM linkers' generic driver, a multicall binary that decides
// which linker it is from the name it was invoked under and refuses to link when
// that name is `lld`; `-flavor gnu` states what the flag already meant. Named
// `ld.lld` the same program needs nothing, and this answers nothing for every
// other tool, including the GNU ones that would reject the word. The prefix goes
// first: the generic driver reads it before it dispatches.
pub fn external_linker_prefix(name string) []string {
	if os.base(name) == 'lld' {
		return ['-flavor', 'gnu']
	}
	return []string{}
}
