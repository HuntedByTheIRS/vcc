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
	jump_local     // a jump to a label inside the function being emitted
	branch_zero    // the same jump, taken when the value last tested was zero
	branch_nonzero // and when it was not
	global_address // the address of an object defined at the top level
	// got_address is the same address reached the other way: the instruction
	// loads the object's address out of the global offset table entry the
	// linker builds for it, rather than computing a direct distance to the
	// object. It is the reference a position-independent object writes for an
	// object another object may define, because a direct distance to such a
	// symbol is one a shared link refuses. A static object, whose name another
	// object cannot define, keeps global_address.
	got_address      // the address of an object, out of the global offset table
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

// Definition is where a name that another translation unit of the same link
// defines lives in the image being built: a function's offset in the code, or a
// top-level object's offset in the writable data. The emitter cannot know it,
// because one translation unit does not see another; a link knows it, and this
// is the answer it hands back.
pub struct Definition {
pub:
	offset int
	// function says which of the two places the offset counts from: true for an
	// offset into the code, false for an offset into the writable data of the
	// top-level objects.
	function bool
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
	// object_imports are the names in `imports` that name an object rather than
	// a function: an `extern` object another translation unit defines. The
	// symbol is undefined either way, and the type it is given says what a
	// reader of the table is looking at.
	object_imports map[string]bool
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
	// globals_alignment is the strictest alignment any top-level object asked
	// for with `__attribute__((aligned(N)))`, and zero when none did. The
	// storage of the objects has to start at it for an object whose
	// declaration asked for more than the word size to land at its alignment,
	// because every object's offset is measured from the start of the blob.
	globals_alignment int
	// copy_objects is every name in `globals` that stands for an object another
	// object defines: the storage is here, the definition is in a shared
	// library, and the loader copies the library's object into this storage
	// when the program starts. It is the shape a non-position-independent
	// executable uses for a variable it names out of a library, and a copy
	// relocation is what asks for it. The names are in the order they were
	// first reached so that the same input writes the same bytes, and the size
	// the relocation carries is read from the name's slot.
	copy_objects []string
	// weak is every function and object this unit defines with a weak symbol
	// binding, which `__attribute__((weak))` asks for. The object's symbol
	// table says WEAK rather than GLOBAL for a name in it.
	weak map[string]bool
	// internal is every function and object this unit defines with internal
	// linkage, which a file-scope `static` gives a name (6.2.2p3). The object's
	// symbol table writes such a name with the local binding, so a definition
	// here cannot meet one in another translation unit the way two external
	// definitions of a name do. It is a different question from weak, which
	// still leaves the name visible to the link.
	internal map[string]bool
	// bound is the imports whose definition is inside this image: names the
	// emitter wrote as a reference to another translation unit, which a link
	// resolved to a definition one of its own units provides. Such a name stays
	// in `imports`, because a call to it still reaches it through a slot the way
	// a call to a library function does, and the layout writes the definition's
	// own address into that slot instead of leaving it to the loader. A name in
	// here gets no dynamic symbol and no relocation, because nothing outside
	// this image has to answer for it. A name not in here is what `imports`
	// meant before a link existed: a symbol some library the image names has to
	// provide. The map is empty for a program the emitter wrote in one piece,
	// where every import is a library's.
	bound map[string]Definition
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
