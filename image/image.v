module image

// The emitted unit: what one translation unit became, in the shape the emitter
// hands over and a container writes. It is not the emitter and not a fact about
// a target, so it sits in a module of its own: `codegen/` produces one,
// `backend/os/elf/` consumes one, and neither owns the shape the other needs.

// Fixup is a reference the code could not finish when it was written: a call to
// a function in the same file, a call to a function that lives in a library, the
// address of a string, or a jump to a place in the function being emitted. The
// instruction is in the text with four zero bytes where its displacement goes,
// and the layout fills them in. length is kept so that filling the reference in
// cannot quietly change the size of the code it sits in, and register is the
// register the instruction reads its answer into, for the references that have
// one.
pub struct Fixup {
pub:
	start    int
	length   int
	kind     FixupKind
	name     string
	register string
}

pub enum FixupKind {
	call_local   // a call to a function this translation unit defines
	call_import  // a call to a symbol the loader resolves out of a library
	take_address // the address of a string in the image
	// take_wide_address is the same address for a wide string literal, whose
	// characters are wider than a byte. The bytes live in the same read-only
	// data and the offset is looked up in the wide table, because the same run
	// of bytes can be a narrow literal in one program and a wide one in
	// another and the two are different objects.
	take_wide_address
	jump_local       // a jump to a label inside the function being emitted
	branch_zero      // the same jump, taken when the value last tested was zero
	branch_nonzero   // and when it was not
	global_address   // the address of an object defined at the top level
	function_address // the address of a function defined in this translation unit
	import_address   // the address of a function the loader resolves out of a library
	float_constant   // a double the instruction reads out of the read-only data
	single_constant  // the same read of a four-byte float
}

// DataFixup is a reference inside the writable data: eight bytes of a top-level
// object that hold the address of something rather than a number, which is what
// a file-scope pointer initializer is. The address is not settled while the
// bytes are laid out - the image is placed afterwards - so the bytes start at
// zero and the layout writes the address in, the way a reference in the code is
// filled in. Its kinds are the ones that name an address: `global_address` for
// an object, `function_address` for a function this unit defines,
// `import_address` for one the loader resolves, and `take_address` or
// `take_wide_address` for a string literal. `offset` is where the eight bytes
// are in globals_blob.
pub struct DataFixup {
pub:
	offset int
	kind   FixupKind
	name   string
	// addend is how many bytes past what the name is the address points: zero
	// for the address of a whole object, and the byte a part starts at for the
	// address of a part, which is what `&a[3]` and `&s.b` write. The layout
	// adds it to the address it resolves the name to.
	addend int
}

// GlobalSlot is where a top-level object lives in the image and how wide it is:
// the offset of its first element in globals_blob, the width of one element, and
// the count of elements it was defined with. floating says the object holds
// doubles, which is a different instruction for every read and write of it.
pub struct GlobalSlot {
pub:
	offset int
	width  int
	count  int
	// object says the storage is an object of an aggregate type rather than a
	// value: one object is as many bytes as the layout said and an array of them
	// is that many per element, and nothing reads one as a value.
	object   bool
	floating bool
	// single says the object holds floats rather than doubles: the same
	// register file and four bytes rather than eight, so every read and write of
	// it is a four-byte one.
	single bool
	// unsigned says the object's type is an unsigned integer one, which the
	// width does not answer: a read of an unsigned char or an unsigned short
	// takes zero above the value rather than its sign, and a read through an
	// address cannot ask the slot it came from because there is none.
	unsigned bool
}

// Program is what one translation unit became: machine code, the strings it
// reads, and the references between them.
pub struct Program {
pub mut:
	text []u8
	// fixups are the references the layout has to fill in.
	fixups []Fixup
	// data_fixups are the references the layout has to write into the storage
	// of the objects at the top level: one per address-valued initializer.
	data_fixups []DataFixup
	// labels is where each function's code begins in text, and where every jump
	// label inside one landed.
	labels map[string]int
	// defined is every function the file defines. A call is checked against it
	// before the library, so a call to a function whose body comes later in the
	// file binds to that function and not to a symbol of the same name.
	defined map[string]bool
	// imports are the library symbols the image needs, in the order they were
	// first called, so that the same input produces the same bytes every run.
	imports []string
	// libraries are the shared libraries the image names as needed, in the
	// order the -l flags named them: the loader maps these before the first
	// instruction runs, and one that is not named is one whose symbols are not
	// there. The C library is not in this list; the container adds it to every
	// image it writes.
	libraries []string
	// string_blob is the read-only data: every distinct string literal with the
	// terminator a library function reads to, and strings is where each one
	// starts in it.
	string_blob []u8
	strings     map[string]int
	// wide_strings is where each wide string literal starts in the same
	// read-only data, behind string_blob's own table. It is a second table
	// because a wide literal's bytes and a narrow one's can be the same run of
	// bytes with a different length and a different meaning, so one table
	// cannot hold both without one entry answering for the other.
	wide_strings map[string]int
	// doubles is the same storage again for the eight bytes of a floating
	// constant, keyed by the bit pattern rather than by the bytes, so that two
	// constants that are the same double are one entry the way two identical
	// strings are. A double is read out of the image and never written, which
	// is what lets it live beside the strings.
	doubles map[string]int
	// globals_blob is the storage of the objects defined at the top level, and
	// globals is where each one starts in it. It is a second blob rather than a
	// part of the strings because a global is written as well as read, and
	// because a string is interned for the bytes it holds while a global is
	// interned for the name it was defined with.
	globals_blob []u8
	globals      map[string]GlobalSlot
}

// import_data_count is how many of the references inside the writable data name
// a symbol the loader resolves rather than an address this image settles. Each
// one costs a dynamic relocation in an executable, so the container asks before
// it places its tables.
pub fn (p Program) import_data_count() int {
	mut count := 0
	for fixup in p.data_fixups {
		if fixup.kind == .import_address {
			count++
		}
	}
	return count
}
