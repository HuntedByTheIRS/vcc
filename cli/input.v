module cli

// What an input is, decided before any stage reads it as source.
//
// A build hands a compiler more than one kind of file and only one of them is C.
// V's own invocation is the case that matters here: it passes its generated
// source beside cached object files and the static archive it links its garbage
// collector from, so `vcc foo.o` is a command line a build reaches without
// meaning anything odd by it. Reading the object as source answers a wrong input
// kind with a wrong reading instead: the diagnostic comes from inside the ELF
// header and names a character, which sends the reader into a binary file and
// says nothing about the object being the wrong thing to hand a front end.
//
// The kind is decided by what the file is first and by its name second. The
// magic of an ELF or of an archive is the file saying what it is, and no
// extension is allowed to talk the compiler out of that. The extensions are the
// fallback for a file whose magic is not one this reader knows, where the name
// the build used is the only claim available. A -x naming a C language is the
// command line saying so, and wins over both.
pub enum InputKind {
	source
	object
	shared_object
	program
	archive
}

// The first bytes of the two containers a link input can be, and the file offset
// of an ELF header's e_type field. They are written here rather than taken from
// backend/os/elf/elf.v for the reason that module gives for keeping its own
// copy: that one writes a container of a fixed shape and this one reads files
// other tools produced, which is the opposite job.
const elf_magic = '\x7fELF'
const archive_magic = '!<arch>\n'
const elf_type_offset = 16
// The three e_type values this compiler distinguishes. The numbers are the
// container's and not the machine's, so they are the same on every target.
const elf_type_object = u16(1)
const elf_type_executable = u16(2)
const elf_type_shared = u16(3)

// classify_input answers what an input is, from the text that was read for it.
//
// The text is passed instead of the path so that the driver reads an input once:
// that read is the one a source file needs anyway, and it is the only one
// available for standard input, which cannot be read twice. What classification
// must not do is let a stage read the text as C, and it does not: the kind is
// settled here, before the preprocessor is handed a byte.
//
// path is the name the command line gave, read for the extension fallback and
// for nothing else, and declared is what -x named, or an empty string when the
// command line named nothing.
pub fn classify_input(text string, path string, declared string) InputKind {
	if declared != '' && declared != 'none' && names_c_source(declared) {
		return .source
	}
	if kind := kind_of_magic(text) {
		return kind
	}
	return kind_from_name(path)
}

// describe names an input kind the way a diagnostic should: the construct, not
// the number behind it.
pub fn (kind InputKind) describe() string {
	return match kind {
		.source { 'source' }
		.object { 'a relocatable object' }
		.shared_object { 'a shared object' }
		.program { 'a program' }
		.archive { 'an archive' }
	}
}

// input_refusal is the message for an input this run will not read, and the one
// place the wording lives. It names the construct and the path, the way the
// other refusals here do, and says what the run was doing instead: an object or
// an archive is read by a link, and the options that stop before one read a
// single source file. The file is fine; the run reached a kind of input its
// options have nothing to do with.
pub fn input_refusal(path string, kind InputKind) string {
	match kind {
		.object, .archive {
			return '${path}: ${kind.describe()} is an input to a link, and this run stops before one: -c, -E, -M and -print-ast each read source'
		}
		.shared_object {
			return '${path}: a shared object is not an input this compiler reads: -external-linker=NAME hands the link to a linker that reads one'
		}
		.program {
			return '${path}: a program is not an input this compiler reads'
		}
		.source {
			return '${path}: source is not an input to refuse'
		}
	}
}

// kind_of_magic reads the kind off the first bytes when they name a container,
// and answers none when they do not, which leaves the name to decide.
fn kind_of_magic(text string) ?InputKind {
	if text.len >= 4 && text[..4] == elf_magic {
		if text.len < elf_type_offset + 2 {
			// A truncated header is still an ELF file and not source, and the
			// kind that fits it is the one with no settled addresses.
			return .object
		}
		// e_type is a 16-bit field written low byte first on the targets this
		// compiler describes.
		kind := int(text[elf_type_offset]) | (int(text[elf_type_offset + 1]) << 8)
		return match kind {
			int(elf_type_object) { .object }
			int(elf_type_executable) { .program }
			int(elf_type_shared) { .shared_object }
			// A kind of container this reader has no name for is still a
			// container: the front end is refused it rather than fed its bytes.
			else { .object }
		}
	}
	if text.len >= 8 && text[..8] == archive_magic {
		return .archive
	}
	return none
}

// names_c_source says whether a -x value names a C language this compiler reads.
// gcc's spellings for the phases of one are all the same front end here: a
// header and an already-preprocessed file are read by the C reader like any
// other C input.
fn names_c_source(declared string) bool {
	return declared == 'c' || declared == 'c-header' || declared == 'cpp-output'
}

// kind_from_name decides an input by its extension, which is the fallback for a
// file whose magic is not one this reader knows: a truncated object, or a linker
// script carrying a library's name, where the name the build used is the only
// claim there is. A name this list does not know is source, because source is
// what a compiler reads when nothing says otherwise.
fn kind_from_name(path string) InputKind {
	name := path.to_lower()
	if name.ends_with('.o') {
		return .object
	}
	if name.ends_with('.a') {
		return .archive
	}
	if name.ends_with('.so') {
		return .shared_object
	}
	return .source
}
