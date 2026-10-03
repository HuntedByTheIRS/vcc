module cli

import os

// What an input on the command line is, decided before anything reads it as
// source.
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
const elf_magic = [u8(0x7f), `E`, `L`, `F`]
const archive_magic = [u8(0x21), u8(0x3c), u8(0x61), u8(0x72), u8(0x63), u8(0x68), u8(0x3e), u8(0x0a)]
// A prefix this long holds the magic and, for an ELF, the two bytes of e_type at
// offset 16. Only a prefix is read: classifying must not cost a full pass over
// the source file the driver is about to read whole.
const input_prefix = 18
const elf_type_offset = 16
// The three e_type values this compiler distinguishes. The numbers are the
// container's and not the machine's, so they are the same on every target.
const elf_type_object = u16(1)
const elf_type_executable = u16(2)
const elf_type_shared = u16(3)

// classify_input answers what a path is without reading it as source: the first
// bytes of the file when they name a container, the name when they do not, and
// source for everything left.
//
// declared is what -x named, or an empty string when the command line named
// nothing.
pub fn classify_input(path string, declared string) InputKind {
	if declared != '' && declared != 'none' && names_c_source(declared) {
		return .source
	}
	// A path that cannot be opened is left to the reader that reports it: the
	// driver's own message about the file it could not read is the honest one,
	// and an unreadable file is not a claim about its kind. Standard input
	// arrives here too, because there is no file named '-' to open.
	head := head_of_file(path, input_prefix) or { return .source }
	if head.len >= 4 && head[..4] == elf_magic {
		if head.len < elf_type_offset + 2 {
			// A truncated header is still an ELF file and not source, and the
			// kind that fits best is the one with no settled addresses.
			return .object
		}
		return match int(head[elf_type_offset]) | (int(head[elf_type_offset + 1]) << 8) {
			int(elf_type_object) { .object }
			int(elf_type_executable) { .program }
			int(elf_type_shared) { .shared_object }
			// A kind of container this reader does not have a name for is
			// still a container: the front end is refused it by name rather
			// than fed its bytes.
			else { .object }
		}
	}
	if head.len >= 8 && head[..8] == archive_magic {
		return .archive
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

// input_refusal is the message for an input this compiler will not read, and the
// one place the wording lives. It names the construct and the path, the way the
// other refusals here do, and says what is missing rather than blaming the file:
// the file is fine and the linker is not written.
pub fn input_refusal(path string, kind InputKind) string {
	match kind {
		.object, .shared_object, .archive {
			return '${path}: ${kind.describe()} is an input to a link, and linking is not implemented yet'
		}
		.program {
			return '${path}: a program is not an input this compiler reads'
		}
		.source {
			return '${path}: source is not an input to refuse'
		}
	}
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
// claim there is. A name this list does not know is source, because that is what
// a compiler reads when nothing says otherwise.
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

// head_of_file is the first want bytes of a file, or none when it cannot be
// opened. The buffer comes back short when the file is shorter than that, and
// empty when there was nothing to read at all.
fn head_of_file(path string, want int) ?[]u8 {
	mut file := os.open(path) or { return none }
	mut buffer := []u8{len: want}
	read := file.read(mut buffer) or { 0 }
	file.close()
	if read <= 0 {
		return []u8{}
	}
	return buffer[..read]
}
