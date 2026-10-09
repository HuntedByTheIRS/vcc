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
	// section_address is the address of a byte in one of the unit's own
	// sections rather than of a name: a string, a double, or a place in the
	// writable data, named by the section it lives in and the byte past its
	// start. A relocatable object states such a reference this way, as a
	// relocation against a section symbol, where this compiler's own emitter
	// names the interned entry instead. The name is the section's own key,
	// which is `.text`, `.rodata` or `.data`, and the addend is the byte
	// inside it, so the whole reference is a section key and a number.
	section_address
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

// The names a relocation uses for a unit's own sections, so that a reference to
// a place rather than to a symbol is spelled the same way in the reader and in
// the container that fills it in. A section key cannot be a C identifier, so it
// never meets the name of a symbol. It can meet the text of a string literal,
// which is keyed by its own bytes and may spell `.text`, so a key is compared
// only against a reference whose kind says it names a place: `linking/reloc/`
// keeps the two apart by kind and not by the name.
pub const section_key_text = '.text'
pub const section_key_rodata = '.rodata'
pub const section_key_data = '.data'

// Relocation is a reference inside one unit that the unit left for the link: a
// field of a known width that holds the distance from the end of the field to
// what the name stands for. A relocatable object carries one per reference it
// could not settle, because the addresses belong to whoever places it, and this
// compiler's own emitter settles its own references and carries none.
//
// The name is either a symbol the link resolves or one of the unit's own section
// keys, `.text`, `.rodata` and `.data`, which name a place in one of its blobs
// rather than in a symbol table. `addend` is the byte past the name the field
// points at: a call carries minus four, because the psABI measures the distance
// from the end of the field and the name is where the instruction began.
pub struct Relocation {
pub:
	offset int
	// place is which of the unit's blobs the field itself is in. It is `.text`
	// for a reference in the code, which is what this compiler writes, and
	// another of the three for a reference that a section of read-only or
	// writable data carries: an unwind table refers to the code from a section
	// of its own, and the field moves with its own blob when the units merge.
	place RelocationPlace = .text
	// kind is how the name is reached. A direct reference uses the address of
	// what the name stands for. A `.got` one uses the address of the global
	// offset table's slot for the name, which is what a position-independent
	// reference to an object the image may not hold a copy of goes through. An
	// `.absolute` one writes the address itself, for a field that holds an
	// address rather than a distance. A `.tpoff` one writes how far a
	// thread-local lies below the thread pointer, which measures from the end of
	// the thread-local block rather than from the end of the field.
	kind   RelocationKind = .direct
	name   string
	addend int
	// width is how many bytes the field occupies: four, which is what an
	// instruction's displacement and this compiler's own references are, or
	// eight, which is what an unwind table's entries and an eight-byte
	// address are. The bytes are already written; only the field is filled
	// in, so how wide it is has to be carried.
	width RelocationWidth = .narrow
}

// RelocationWidth is how many bytes of the field a reference occupies.
pub enum RelocationWidth {
	narrow
	wide
}

// RelocationPlace is which of a unit's blobs a relocatable field lies in. The
// four are the ones a unit is made of, and each has a base of its own in the
// merged image, which is what the merge adds to the field's offset. A field in
// the thread-local image is the one that is not storage of the program's own:
// every thread gets a copy of that image made by the loader, so a field in it
// holds an address rather than a distance.
pub enum RelocationPlace {
	text
	read_only
	tls
	data
}

// RelocationKind is how a relocatable reference reaches what it names: the
// address itself, the address of the global offset table's slot for it, the
// address written down, or how far below the thread pointer a thread-local is.
pub enum RelocationKind {
	direct
	got
	absolute
	tpoff
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
	// tls says the offset counts from the start of the image's thread-local
	// block instead, which is where a local-exec reference measures from. A
	// thread-local is the one place a name lives that is neither code nor the
	// storage of an object: every thread gets its own copy of it.
	tls bool
	// image_base says the definition is the image itself: the address the first
	// byte of the file is loaded at, which is offset zero in the flat image
	// every other offset is counted in. `__ehdr_start` is the name the C
	// library's own startup gives it, and it is what a program reads to find
	// its own program headers at run time.
	image_base bool
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

// CodeRun is one section of a unit's code blob that the merge gathers with the
// same-named section of every other unit. Where it sits in the unit's blob, how
// long it is, and the alignment it asks for are all the merge needs to place it
// with the others.
pub struct CodeRun {
pub mut:
	base      int
	len       int
	alignment int
}

// Program is what one translation unit became: machine code, the strings it
// reads, and the references between them.
pub struct Program {
pub mut:
	text []u8
	// executable_stack is set when the code runs instructions it wrote into its
	// own frame, which is what taking the address of a nested function does: the
	// stub that carries the enclosing frame lives on the stack, so the container
	// has to say the stack is executable.
	executable_stack bool
	// fixups are the references the layout has to fill in.
	fixups []Fixup
	// data_fixups are the references the layout has to write into the storage
	// of the objects at the top level: one per address-valued initializer.
	data_fixups []DataFixup
	// relocations are the references inside the text that this unit left as
	// plain fields for the link rather than as fixups it could write itself.
	// This compiler's own emitter writes none, because it settles every
	// reference it makes; a unit read back from a relocatable object carries
	// one per reference that object left to a linker. They are applied by the
	// container once every address is settled, the same way a fixup is, and
	// they carry an addend rather than an instruction shape because the bytes
	// are already written and only the four-byte field is filled in.
	relocations []Relocation
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
	// read_only_globals is where an object a unit defines in read-only data
	// lives, as an offset into the merged read-only data. It is a map of its
	// own because the offset counts from that blob and not from the writable
	// one: a `const` object at file scope is ordinary C, one unit defines it
	// and another names it, and a reference to it has to land on the bytes the
	// definition wrote rather than on bytes of the same name.
	read_only_globals map[string]GlobalSlot
	// globals_alignment is the strictest alignment any top-level object asked
	// for with `__attribute__((aligned(N)))`, and zero when none did. The
	// storage of the objects has to start at it for an object whose
	// declaration asked for more than the word size to land at its alignment,
	// because every object's offset is measured from the start of the blob.
	globals_alignment int
	// init_run and fini_run are the two sections of this unit's code blob that
	// the merge gathers with the same-named section of every other unit: `.init`
	// and `.fini`, which the start files are written around. The file that opens
	// `.init` ends with a branch over a call, and the file that closes it begins
	// with the instruction that branch is meant to reach, so the two fragments
	// have to end up next to each other rather than where their units landed. A
	// unit that carries neither has a run of length zero.
	init_run CodeRun
	fini_run CodeRun
	// stub says this unit opens with the process stub the kernel jumps to. A
	// program has one, and a link carries one in a unit of its own; a unit read
	// from a relocatable object has none.
	stub bool
	// eh_frame_run is the unit's `.eh_frame` fragment: where it sits in the
	// unit's read-only data and how long it is. The merge gathers every unit's
	// fragment into one table, because the unwinder scans from one of them and
	// expects to reach the rest.
	eh_frame_run CodeRun
	// entry_place is where in the merged text the process begins, which is the
	// number the container writes into the header. It is not the start of the
	// text: the gathered `.init` and `.fini` runs are placed there.
	entry_place int
	// read_only_alignment is the strictest alignment any read-only section of
	// this unit asked for. A unit read from an object carries the alignment its
	// sections declared, and a sixteen-byte constant a compiler loads in one
	// instruction only lands at its own alignment when the merged read-only data
	// holds it there, so the merge has to know the number.
	read_only_alignment int
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
	// weak_imports is every name in `imports` the units named with a weak
	// symbol binding and none of them defines, which is what a reference to
	// `__gmon_start__` in the runtime's own startup files is. A weak import is
	// the one name a link does not have to answer: the ELF rule is that an
	// undefined weak symbol stands for zero, so no library is asked for it and
	// the image's own symbol table writes it with the weak binding, which is
	// how the loader is told to leave the slot zero rather than fail on a name
	// nothing defines.
	weak_imports map[string]bool
	// tls_slots is every name whose global offset table slot holds how far the
	// thread-local lies below the thread pointer rather than its address, which
	// is what a `R_X86_64_GOTTPOFF` reference reads: the code loads the slot and
	// reaches the variable through the thread pointer, the initial-exec model.
	// The slot's content is a number the link writes, not an address the loader
	// fills in.
	tls_slots map[string]bool
	// internal is every function and object this unit defines with internal
	// linkage, which a file-scope `static` gives a name (6.2.2p3). The object's
	// symbol table writes such a name with the local binding, so a definition
	// here cannot meet one in another translation unit the way two external
	// definitions of a name do. It is a different question from weak, which
	// still leaves the name visible to the link.
	internal map[string]bool
	// plts are the imported functions this image has to reach by a stub: a
	// unit read from a relocatable object calls a library function with a
	// direct branch, and the address that branch reaches is only known once
	// the table of slots is laid out, so the call goes to a six-byte stub that
	// jumps through the import's slot. The names are in the order the call
	// sites were first read, so the same inputs give the same stub addresses.
	// A program the emitter wrote in one piece has none, because its calls to
	// a library go through the slot directly.
	plts []string
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
	// tls_blob is the initialized image of the thread-local storage this unit
	// defines - the contents of `.tdata` - and tls_size is how much storage it
	// asks for in all, which is longer when a zero-filled part (`.tbss`)
	// follows the image. tls_alignment is the strictest alignment any member
	// asked for. A thread-local's offset in this storage is what a `tpoff`
	// reference measures from the end of the image's whole block.
	tls_blob      []u8
	tls_size      int
	tls_alignment int
	// tls_labels is where each thread-local this unit defines lies in that
	// storage, which is what a `.tpoff` reference to the name measures from
	// the end of the image's whole block. It is a map of its own rather than a
	// part of `labels`, because a label is an address in the code and this is
	// an offset in storage that every thread gets its own copy of.
	tls_labels map[string]int
	// init_array and fini_array are the two tables of function addresses the
	// container has to tell the runtime about: the entries to run before the
	// program's own code and those to run after it. They lie in the writable
	// data, which is why the offsets are into that blob; the entries
	// themselves are eight-byte addresses a relocation names.
	init_array ConstructorTable
	fini_array ConstructorTable
	// ifuncs is every name this unit defines whose definition is a function
	// that answers with the address of the function to use instead, which is
	// what `__attribute__((ifunc("resolver")))` makes a name into and what the
	// C library uses to pick a memcpy for the machine it is running on. A
	// reference to one goes through the global offset table like an import's,
	// and whoever starts the image has to ask the resolver and write the
	// answer into the slot.
	ifuncs map[string]bool
}

// ConstructorTable is where one of a unit's two constructor tables lies in its
// writable data and how many eight-byte entries it holds. A table with no
// entries is the zero value, which is what a unit with a constructor in it
// leaves behind when it has one of the other kind.
pub struct ConstructorTable {
pub:
	offset int
	count  int
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
