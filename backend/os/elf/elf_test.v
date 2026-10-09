module elf

import backend
import image
import os

// The three output kinds are checked the same way the dynamic program is: a
// Program built by hand and read back through the headers, because the questions
// worth pinning are about a header, a symbol and a relocation that the emitter's
// whole output cannot show, and about a program the kernel can actually start.
// V compiles each `_test.v` file on its own, so the byte readers here are
// defined again under names this file owns rather than shared with the others.

fn se16(bytes []u8, at int) u16 {
	return u16(bytes[at]) | (u16(bytes[at + 1]) << 8)
}

fn se32(bytes []u8, at int) u32 {
	mut value := u32(0)
	for shift in [0, 8, 16, 24] {
		value |= u32(bytes[at + shift / 8]) << shift
	}
	return value
}

fn se64(bytes []u8, at int) u64 {
	mut value := u64(0)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		value |= u64(bytes[at + shift / 8]) << shift
	}
	return value
}

fn se_target() backend.Target {
	return backend.lookup('x86_64-linux') or { panic('no x86_64-linux target') }
}

// se_phdr_at is where one program header begins: after the ELF header, with the
// entry size the header gives.
fn se_phdr_at(bytes []u8, index int) int {
	return int(se64(bytes, 32)) + index * int(se16(bytes, 54))
}

// se_dynamic_offset and se_dynamic_size reach the PT_DYNAMIC segment through the
// program header table, which is the only map a program has.
fn se_dynamic_offset(bytes []u8) int {
	for i in 0 .. int(se16(bytes, 56)) {
		at := se_phdr_at(bytes, i)
		if se32(bytes, at) == elf_ph_type_dynamic {
			return int(se64(bytes, at + 8))
		}
	}
	return 0
}

fn se_dynamic_size(bytes []u8) int {
	for i in 0 .. int(se16(bytes, 56)) {
		at := se_phdr_at(bytes, i)
		if se32(bytes, at) == elf_ph_type_dynamic {
			return int(se64(bytes, at + 32))
		}
	}
	return 0
}

fn se_has_interp(bytes []u8) bool {
	for i in 0 .. int(se16(bytes, 56)) {
		if se32(bytes, se_phdr_at(bytes, i)) == elf_ph_type_interp {
			return true
		}
	}
	return false
}

fn se_needed_count(bytes []u8) int {
	offset := se_dynamic_offset(bytes)
	mut count := 0
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		if se64(bytes, offset + i * elf_dynamic_entry_size) == dt_needed {
			count++
		}
	}
	return count
}

// SeTables is where the loader's tables are in the image, as file offsets. A
// shared object's dynamic addresses are file offsets already, so the base it is
// read with is zero.
struct SeTables {
mut:
	strtab int
	symtab int
	hash   int
	rela   int
	relasz int
}

fn se_tables(bytes []u8, base u64) SeTables {
	offset := se_dynamic_offset(bytes)
	mut tables := SeTables{}
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		tag := se64(bytes, offset + i * elf_dynamic_entry_size)
		value := se64(bytes, offset + i * elf_dynamic_entry_size + 8)
		match tag {
			dt_hash { tables.hash = int(value - base) }
			dt_strtab { tables.strtab = int(value - base) }
			dt_symtab { tables.symtab = int(value - base) }
			dt_rela { tables.rela = int(value - base) }
			dt_relasz { tables.relasz = int(value) }
			else {}
		}
	}
	return tables
}

fn se_name(bytes []u8, at int) string {
	mut end := at
	for bytes[end] != u8(0) {
		end++
	}
	return bytes[at..end].bytestr()
}

struct SeSymbol {
	index int
	info  u8
	value u64
	size  u64
	name  string
}

// se_symbol_of finds a dynamic symbol by name. There is no section header to say
// how many entries the table has, so the count comes from the hash table's chain
// length, which is the number of symbols in the table.
fn se_symbol_of(bytes []u8, tables SeTables, name string) SeSymbol {
	count := int(se32(bytes, tables.hash + 4))
	for i in 1 .. count {
		at := tables.symtab + i * elf_symbol_size
		here := se_name(bytes, tables.strtab + int(se32(bytes, at)))
		if here == name {
			return SeSymbol{
				index: i
				info:  bytes[at + 4]
				value: se64(bytes, at + 8)
				size:  se64(bytes, at + 16)
				name:  here
			}
		}
	}
	return SeSymbol{}
}

struct SeRelocation {
	offset u64
	info   u64
	addend i64
}

fn se_relative_relocation(bytes []u8, tables SeTables) SeRelocation {
	for i in 0 .. tables.relasz / elf_relocation_size {
		at := tables.rela + i * elf_relocation_size
		info := se64(bytes, at + 8)
		if info & 0xffffffff == relocation_relative {
			return SeRelocation{
				offset: se64(bytes, at)
				info:   info
				addend: i64(se64(bytes, at + 16))
			}
		}
	}
	return SeRelocation{}
}

// A static program is one the kernel starts with no loader: no interpreter
// header, no library named, and every address settled here. The stub the import
// is reached through is laid out the same way as a dynamic program's, and the
// program has to run: the exit status is the one the code was asked for.
fn test_a_static_program_is_an_exec_with_no_interpreter_and_no_library() {
	target := se_target()
	code := target.exit_sequence(7) or { panic('the target has no exit sequence: ${err.msg()}') }
	mut program := image.Program{}
	program.text = code
	program.imports << 'entry'
	program.bound['entry'] = image.Definition{
		offset:   0
		function: true
	}
	program.plts << 'entry'
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	assert se16(bytes, 16) == elf_type_exec
	assert !se_has_interp(bytes)
	assert se_needed_count(bytes) == 0
	path := os.join_path(os.temp_dir(), 'vcc_elf_static_${os.getpid()}')
	os.write_file_array(path, bytes) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	assert result.exit_code == 7
}

// A static link resolves its libraries into the file it writes. A name still
// left to a library is one this link cannot place, and the diagnostic has to
// name it rather than write a file that would start with the name's address
// zero.
fn test_a_static_program_left_to_a_library_is_refused() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0x90)}
	program.imports << 'puts'
	write(program, target, .static_program) or {
		assert err.msg().contains('puts')
		return
	}
	assert false, 'a static program was written with puts left to a library'
}

// A shared object is a file another program loads: the header says ET_DYN, there
// is no interpreter and no entry point, and the names this image defines are
// exported in the dynamic symbol table, each at the file offset of its
// definition. An import whose definition is inside the image has its slot filled
// with the offset and an R_X86_64_RELATIVE entry beside it, because where the
// object goes is the loader's to choose. Both are pinned here: the slot holds the
// same offset the relocation's addend carries.
fn test_a_shared_object_is_dynamic_and_exports_what_it_defines() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 16, init: u8(0)}
	program.text[4] = u8(0xab)
	program.defined['exported_fn'] = true
	program.labels['exported_fn'] = 4
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['exported_obj'] = image.GlobalSlot{
		offset: 0
		width:  4
		count:  2
	}
	program.imports << 'bound_fn'
	program.bound['bound_fn'] = image.Definition{
		offset:   4
		function: true
	}
	bytes := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	assert se16(bytes, 16) == elf_type_dyn
	assert !se_has_interp(bytes)
	assert se64(bytes, 24) == 0 // no entry point
	tables := se_tables(bytes, 0)
	// The function is exported as a function, and its value is the file offset
	// the label named: the byte there is the one the text holds at offset four.
	exported := se_symbol_of(bytes, tables, 'exported_fn')
	assert exported.name == 'exported_fn'
	assert exported.info & 0xf == 0x2
	assert bytes[int(exported.value)] == u8(0xab)
	// The object is exported as an object, and its size is its whole storage:
	// two four-byte elements.
	object := se_symbol_of(bytes, tables, 'exported_obj')
	assert object.name == 'exported_obj'
	assert object.info & 0xf == 0x1
	assert object.size == 8
	// The bound import's slot is an address that points into the image, so it is
	// an offset beside a relocation that adds the load base, and the offset is
	// the definition's: the same place the exported function's label named.
	relative := se_relative_relocation(bytes, tables)
	assert relative.info & 0xffffffff == relocation_relative
	assert relative.addend == i64(exported.value)
	assert se64(bytes, int(relative.offset)) == u64(relative.addend)
}

// A copy relocation asks a loader to copy a library's object into this image's
// storage, which is a non-position-independent executable's shape and not a
// shared object's. The refusal names the object.
fn test_a_shared_object_that_would_copy_a_library_object_is_refused() {
	target := se_target()
	mut program := image.Program{}
	program.globals_blob = []u8{len: 8, init: u8(0)}
	program.globals['stdout'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.copy_objects << 'stdout'
	write(program, target, .shared) or {
		assert err.msg().contains('stdout')
		return
	}
	assert false, 'a shared object was written with a copy relocation'
}

// The same Program has to write the same bytes every run, and the two symbol
// sets a shared object exports are maps, whose order is not the program's. The
// exports are sorted, so the index of `a` is below the index of `b` however the
// maps were built, and the two writes are compared byte for byte.
fn test_a_shared_object_is_the_same_every_run() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0x90)}
	program.string_blob = []u8{len: 8, init: u8(0)}
	program.strings['s'] = 0
	program.globals_blob = []u8{len: 16, init: u8(0)}
	program.globals['a'] = image.GlobalSlot{
		offset: 0
		width:  8
	}
	program.globals['b'] = image.GlobalSlot{
		offset: 8
		width:  8
	}
	program.data_fixups << image.DataFixup{
		offset: 0
		kind:   .take_address
		name:   's'
	}
	first := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	second := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	assert first == second
	tables := se_tables(first, 0)
	assert se_symbol_of(first, tables, 'a').index < se_symbol_of(first, tables, 'b').index
}

// se_phdr_of is where the program header of a kind begins, or -1 when the image
// has none. A program has no section header table, so the program header table
// is the only map of its parts.
fn se_phdr_of(bytes []u8, kind u32) int {
	for i in 0 .. int(se16(bytes, 56)) {
		at := se_phdr_at(bytes, i)
		if se32(bytes, at) == kind {
			return at
		}
	}
	return -1
}

// se_dynamic_has says whether the dynamic table names a tag at all, which is
// how a test tells an entry that is absent from one whose value is zero.
fn se_dynamic_has(bytes []u8, tag u64) bool {
	offset := se_dynamic_offset(bytes)
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		if se64(bytes, offset + i * elf_dynamic_entry_size) == tag {
			return true
		}
	}
	return false
}

// se_dynamic_value is the value of the entry a tag names, and none when the
// table has no such entry.
fn se_dynamic_value(bytes []u8, tag u64) ?u64 {
	offset := se_dynamic_offset(bytes)
	for i in 0 .. se_dynamic_size(bytes) / elf_dynamic_entry_size {
		if se64(bytes, offset + i * elf_dynamic_entry_size) == tag {
			return se64(bytes, offset + i * elf_dynamic_entry_size + 8)
		}
	}
	return none
}

// se_relocation_of finds the first entry of a kind in the table the dynamic
// segment names, and se_relocation_count_of says how many there are.
fn se_relocation_of(bytes []u8, tables SeTables, kind u64) SeRelocation {
	for i in 0 .. tables.relasz / elf_relocation_size {
		at := tables.rela + i * elf_relocation_size
		info := se64(bytes, at + 8)
		if info & 0xffffffff == kind {
			return SeRelocation{
				offset: se64(bytes, at)
				info:   info
				addend: i64(se64(bytes, at + 16))
			}
		}
	}
	return SeRelocation{}
}

fn se_relocation_count_of(bytes []u8, tables SeTables, kind u64) int {
	mut count := 0
	for i in 0 .. tables.relasz / elf_relocation_size {
		if se64(bytes, tables.rela + i * elf_relocation_size + 8) & 0xffffffff == kind {
			count++
		}
	}
	return count
}

// A wide reference is an eight-byte field and all eight bytes are written: the
// distance is a 64-bit one, so a value whose upper half is not zero reaches the
// field instead of being cut to its low thirty-two bits the way a narrow field
// is. The addend here is 2^32, which is what puts a bit in the upper half.
fn test_a_wide_direct_reference_fills_eight_bytes() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 32, init: u8(0)}
	program.labels['target'] = 24
	program.relocations << image.Relocation{
		offset: 4
		kind:   .direct
		name:   'target'
		addend: int(i64(1) << 32)
		width:  .wide
	}
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	// A static program is not shared, so its entry point is the load base plus
	// the text offset, which is all that reaches the code of a program with no
	// section headers.
	text := int(se64(bytes, 24)) - int(target.load_base)
	assert se64(bytes, text + 4) == u64(0x1_0000_0014) // (text + 24) + 2^32 - (text + 4)
	assert se32(bytes, text + 4) == u32(0x14) // the low half of the same number
	assert se32(bytes, text + 8) == u32(1) // and the high half, which a narrow field drops
}

// A tpoff reference is measured from the thread pointer, which sits at the end
// of the block rounded up to its alignment, so the value is the name's place in
// the block minus that rounded size. A block of twenty bytes aligned to sixteen
// rounds to thirty-two, and a name at four is twenty-eight below the pointer.
fn test_a_tpoff_reference_is_measured_from_the_end_of_the_rounded_block() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0)}
	program.tls_blob = []u8{len: 20, init: u8(0)}
	program.tls_size = 20
	program.tls_alignment = 16
	program.tls_labels['x'] = 4
	program.relocations << image.Relocation{
		offset: 0
		kind:   .tpoff
		name:   'x'
		width:  .narrow
	}
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	text := int(se64(bytes, 24)) - int(target.load_base)
	// roundup(20, 16) is 32, and 4 - 32 is -28.
	assert i32(se32(bytes, text)) == -28
}

// A thread-local block turns into a PT_TLS header, and it is a header of its own
// for every kind: it adds one to the four a dynamic program has, the three a
// shared object has, and the two a static program has. The header names where
// the initialization image was placed, the bytes to copy out of it, and the
// block's rounded size and alignment, which is what the runtime reads.
fn test_a_thread_local_block_writes_a_pt_tls_header() {
	target := se_target()
	mut program := image.Program{}
	program.tls_blob = []u8{len: 12, init: u8(0)}
	program.tls_size = 12
	program.tls_alignment = 8
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	assert se16(bytes, 56) == 3 // the load, the stack, and the block
	at := se_phdr_of(bytes, elf_ph_type_tls)
	assert at >= 0
	assert se32(bytes, at + 4) == elf_ph_flags_read
	// The one PT_LOAD maps the whole file at the load base, so a virtual address
	// is the base plus the file offset and p_vaddr has to agree with p_offset.
	assert se64(bytes, at + 16) == target.load_base + se64(bytes, at + 8)
	assert se64(bytes, at + 32) == 12 // p_filesz: the initialization image
	assert se64(bytes, at + 40) == 16 // p_memsz: roundup(12, 8)
	assert se64(bytes, at + 48) == 8 // p_align
	// The same block adds one to the other two kinds' header counts.
	dynamic := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	assert se16(dynamic, 56) == 5
	shared := write(program, target, .shared) or {
		panic('the shared object was not written: ${err.msg()}')
	}
	assert se16(shared, 56) == 4
}

// A program with no thread-local storage writes no PT_TLS header, and its header
// count is the one the kind always has: the block's header is not carried when
// there is no block.
fn test_a_program_without_thread_local_storage_writes_no_pt_tls_header() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0)}
	bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	assert se16(bytes, 56) == 2
	assert se_phdr_of(bytes, elf_ph_type_tls) == -1
}

// A constructor table is named in the dynamic table by its address and its size,
// eight bytes per entry. The two tables lie in the writable data at the offsets
// the program gave, so their addresses differ by sixteen when the init table is
// at eight and the fini table at twenty-four. A program with no table names
// neither, and a static program writes no dynamic table to name one in.
fn test_a_constructor_table_is_named_in_the_dynamic_table() {
	target := se_target()
	mut program := image.Program{}
	program.globals_blob = []u8{len: 32, init: u8(0)}
	program.init_array = image.ConstructorTable{
		offset: 8
		count:  2
	}
	program.fini_array = image.ConstructorTable{
		offset: 24
		count:  1
	}
	bytes := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	init := se_dynamic_value(bytes, dt_init_array) or { panic('no DT_INIT_ARRAY') }
	fini := se_dynamic_value(bytes, dt_fini_array) or { panic('no DT_FINI_ARRAY') }
	assert se_dynamic_value(bytes, dt_init_arraysz) or { panic('no DT_INIT_ARRAYSZ') } == 16
	assert se_dynamic_value(bytes, dt_fini_arraysz) or { panic('no DT_FINI_ARRAYSZ') } == 8
	assert fini - init == 16
	// The address is one the loader maps, inside the image the file became.
	assert init >= target.load_base
	assert init < target.load_base + u64(bytes.len)
	// A program with no constructor table names none of the four entries.
	plain := write(image.Program{}, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	assert !se_dynamic_has(plain, dt_init_array)
	assert !se_dynamic_has(plain, dt_fini_array)
	// And a static program writes no dynamic table at all for them to live in.
	static_bytes := write(program, target, .static_program) or {
		panic('the static program was not written: ${err.msg()}')
	}
	assert se_dynamic_offset(static_bytes) == 0
}

// A name whose definition is a resolver has its slot filled by asking the
// resolver, not by the loader copying an address, so the slot gets an
// R_X86_64_IRELATIVE entry: the entry names the slot, names no symbol, and its
// addend is the resolver's own address, which the loader calls. The slot holds
// that address too, which is what a bound name's slot always holds, and a bound
// name that is not an ifunc gets no such entry.
fn test_an_ifunc_name_gets_an_irelative_entry_for_its_slot() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 16, init: u8(0x90)}
	program.imports << 'memcpy'
	program.bound['memcpy'] = image.Definition{
		offset:   4
		function: true
	}
	program.ifuncs['memcpy'] = true
	program.imports << 'plain'
	program.bound['plain'] = image.Definition{
		offset:   0
		function: true
	}
	bytes := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	tables := se_tables(bytes, target.load_base)
	assert se_relocation_count_of(bytes, tables, relocation_irelative) == 1
	entry := se_relocation_of(bytes, tables, relocation_irelative)
	// The resolver is the definition: the code's start, which the entry point
	// names, plus the definition's offset.
	resolver := se64(bytes, 24) + 4
	assert entry.addend == i64(resolver)
	// The entry names the slot, and the slot already holds the resolver so the
	// loader has an address to call before it writes the answer over it.
	assert se64(bytes, int(entry.offset - target.load_base)) == resolver
}

// The tpoff the container writes has to agree with the runtime that places the
// thread pointer, and the way to know it does is to run a program that reads a
// thread-local and stops with what it read. The code moves one byte out of
// fs:[tpoff] and exits with it; the value comes out of the block the runtime
// copied from the image, so a wrong offset reads a byte of something else.
fn test_a_thread_local_reads_its_initial_value_through_the_pointer() {
	target := se_target()
	held := target.reg('eax') or { panic('no eax register') }
	mut program := image.Program{}
	// movzx eax, byte ptr fs:[disp32]: the fs prefix and the instruction, then
	// the four bytes of the field a tpoff reference fills in at offset five.
	program.text = [u8(0x64), 0x0f, 0xb6, 0x04, 0x25, 0, 0, 0, 0]
	exit := target.exit_sequence_from(held) or { panic('no exit sequence: ${err.msg()}') }
	program.text << exit
	program.tls_blob = [u8(42)]
	program.tls_size = 1
	program.tls_alignment = 1
	program.tls_labels['x'] = 0
	program.relocations << image.Relocation{
		offset: 5
		kind:   .tpoff
		name:   'x'
		width:  .narrow
	}
	bytes := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	path := os.join_path(os.temp_dir(), 'vcc_elf_tls_${os.getpid()}')
	os.write_file_array(path, bytes) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
	result := os.execute(os.quoted_path(path))
	os.rm(path) or {}
	assert result.exit_code == 42
}

// An image with function bodies carries the unwind table and the header that
// indexes it, and PT_GNU_EH_FRAME names the header so an unwinder reaches the
// table without scanning. Two bodies make the shape visible: the table is one
// CIE, one FDE per body and a zero record that ends it, and the header's search
// table is sorted by the address each body covers and points at the FDE that
// describes it. The bodies are handed out of address order so the sort is
// exercised, and the FDE measures to its body from its own field while the
// search table measures from the header's start, which is the datarel encoding
// gcc writes.
fn test_function_bodies_write_an_unwind_table_the_header_indexes() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 64, init: u8(0x90)}
	program.function_runs << image.CodeRun{
		base: 32
		len:  16
	}
	program.function_runs << image.CodeRun{
		base: 0
		len:  8
	}
	bytes := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	at := se_phdr_of(bytes, elf_ph_type_gnu_eh_frame)
	assert at >= 0
	assert se32(bytes, at + 4) == elf_ph_flags_read
	// The one segment maps the whole file, so a virtual address is the base
	// plus the file offset, and the block is the fixed header and two entries.
	assert se64(bytes, at + 16) == target.load_base + se64(bytes, at + 8)
	assert se64(bytes, at + 32) == 12 + 2 * 8
	assert se64(bytes, at + 48) == 4
	hdr := int(se64(bytes, at + 8))
	// The version and the three encodings are gcc's, and the table address is
	// a distance from the field itself to `.eh_frame`.
	assert bytes[hdr] == u8(1)
	assert bytes[hdr + 1] == u8(0x1b)
	assert bytes[hdr + 2] == u8(0x03)
	assert bytes[hdr + 3] == u8(0x3b)
	assert se32(bytes, hdr + 8) == 2
	eh_frame := hdr + 4 + int(i32(se32(bytes, hdr + 4)))
	text := int(se64(bytes, 24)) - int(target.load_base)
	// The CIE is the table's first entry; the two FDEs follow it in address
	// order, the body at zero before the one at thirty-two.
	assert se32(bytes, eh_frame) == 20
	first_fde := eh_frame + 24
	second_fde := first_fde + 20
	assert se32(bytes, first_fde) == 16
	// The search table's first entry is the body that begins lowest, and it
	// names the FDE that describes it.
	assert hdr + int(i32(se32(bytes, hdr + 12))) == text
	assert hdr + int(i32(se32(bytes, hdr + 16))) == first_fde
	assert first_fde + 8 + int(i32(se32(bytes, first_fde + 8))) == text
	assert se32(bytes, first_fde + 12) == 8
	assert hdr + int(i32(se32(bytes, hdr + 20))) == text + 32
	assert second_fde + 8 + int(i32(se32(bytes, second_fde + 8))) == text + 32
	assert se32(bytes, second_fde + 12) == 16
}

// An image with no function body writes no table and no header, and its header
// count is the one the kind always had: the unwind table's header is not carried
// when there is nothing to index.
fn test_an_image_with_no_function_body_writes_no_unwind_header() {
	target := se_target()
	mut program := image.Program{}
	program.text = []u8{len: 8, init: u8(0x90)}
	bytes := write(program, target, .program) or {
		panic('the dynamic program was not written: ${err.msg()}')
	}
	assert se16(bytes, 56) == 4
	assert se_phdr_of(bytes, elf_ph_type_gnu_eh_frame) == -1
}
