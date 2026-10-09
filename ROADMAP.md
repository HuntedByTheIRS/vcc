# Roadmap

The order is deliberate: the front end before the back end, the back end before
linking, and the V contract before anyone swaps the binary. Each milestone names
how it is verified, and every one of them ends with the same gate: the V
self-build does not get slower.

## Where the tree is

Past the stub, at the end of M1. The preprocessor is real (it reads the glibc
headers this machine has), the front end reads the declarations such a header is
made of and the function definitions after them, and the back end writes a
dynamically linked Linux x86-64 executable that calls into libc, so `#include
<stdio.h>` and `puts` work end to end. Function bodies with parameters, local
variables and control flow (`if`/`else`, `while`, `for` with `break` and
`continue`) run as well, arrays and objects defined at the top level run with
them, the address of a local is one thing more, and so does a call whose value is
read, as in `int x = add(y, 3) + 2;`. A `double` is a value the compiler has, in
the floating-point registers and in the SysV sequence for arguments and returns,
and a typedef is followed to the type it names wherever a type can be written. A
`typeof` specifier is read the same way: the operand is a type name or an
expression, its value is never evaluated, and the declaration that follows
declares what that operand's type says. `__int128` is read where a type can be
written, and the model sizes it and lays it out, which is what makes
`sizeof(__int128)` 16 and puts a member of one on a 16-byte boundary. An object of
one is storage the back end has, as a local, a top-level object, a member of one and an array of them:
sixteen bytes, a value narrower than that widened into its two words, one object
copied into another, and a conversion of one to a narrower type reading its low
word. A value of that width is what it does not have,
so an implicit narrowing store and a parameter of the type are refused by name.
`-l` links the library it names, so `-lm` puts `libm.so.6` in the image's
`DT_NEEDED` and `sqrt` resolves. An object of a struct or union type inside a
function is a block of the frame with its members at the offsets the layout gives
them, and the arguments past the machine's registers are passed on the stack, so
both walls that were standing at the end of M1 are down. What is left is `enum`,
the shift and bitwise operators, unsigned integer types, and the rest of the list
in the README. An object of sixteen bytes or fewer is
handed over in the registers its classes name on both sides, a larger one travels
through memory, and an assignment between two objects of a type copies the bytes. The command line already
accepts the flag surface V uses, because getting that wrong later is a rewrite
rather than a fix.
Everything else exits non-zero with a diagnostic naming the construct.

The numbers, from `tools/bench.vsh` against the tcc V vendors: on a 20000-term
constant chain vcc is about 17x its wall time and 15x its peak memory, and at
100000 terms about 38x and 62x. The ratio grows with the input because tcc's
time is nearly flat while vcc's tracks the tokens and nodes it allocates. That
gap is the M6 problem, and it is measured rather than felt.

## M0: the stub

Done when `v test .` passes, the lexer covers the C preprocessing-token grammar,
the parser covers the subset the README lists, the ELF writer produces a binary
that runs, and every unsupported construct has a diagnostic with a location.

## M1: the preprocessor

A real C preprocessor, not a macro pass bolted onto the parser: `#include` with
quoted and angle search paths, object-like and function-like macros with `#` and
`##`, variadic macros, `#if` with the full constant expression grammar,
`#ifdef`, `#elif`, `#error`, `#line`, `#pragma once`, and `__LINE__`,
`__FILE__`, `__DATE__`-class predefined macros plus the `__TINYC__`-shaped ones
V's codegen may test for. `-I`, `-D`, `-U`, `-nostdinc` and `-E` become real.

Verified by preprocessing the same file with `tcc -E` and diffing the token
streams, macro definitions and include order included.

## M2: the front end

The C11 grammar as GNU C actually uses it: declarations and declarators
(including the pointer and array spellings that read backwards), structs,
unions, enums, typedefs, bitfields, `sizeof` and `alignof`, casts, compound
literals, designated initializers, `switch`, loops, `goto`, labels, variadic
functions, `_Bool` and the integer and floating types, and constant expression
folding. Diagnostics with a file, line, column, and a note saying what the
compiler expected instead.

Verified by parsing and type-checking the corpus of generated C that V emits for
itself, plus the C in V's `thirdparty/` and a few real-world projects, and
comparing acceptance against `tcc`.

## M3: the x86-64 back end

Instruction selection, register allocation, stack frames and the SysV calling
convention, global and thread-local storage, sections, relocations, `.S` input,
inline assembly, and correct integer and floating point semantics including the
signed overflow wrapping that V's generated code assumes. Symbols get emitted
with the right linkage, visibility, and alignment; `-O` levels exist and do
something.

Verified by running the compiled programs, and by diffing behavior against tcc's
output for the same input, not by reading the assembly and approving of it.

A new architecture or a new system is a file under `backend/arch` or
`backend/os` plus a line in the composition, so this milestone grows by tables
rather than by platform branches.

## M4: objects, linking, and output formats

ELF relocatable objects, an `ar` archive reader, executable linking against
libc, static and shared output, `-L`/`-l` search order, `-shared`, `-r`,
`-nostdlib`, `-Wl,` passthroughs, and crt startup objects. This is the milestone
where the compiler stops producing standalone binaries and starts doing the job
V actually needs: linking a program against the system libraries.

Archive support is not optional for the V contract: every `-cc tcc` build links
`thirdparty/tcc/lib/libgc.a`, which V passes on the command line along with
`-DGC_THREADS=1 -DGC_BUILTIN_ATOMIC=1` and the libgc include directory. A
compiler that cannot open an archive cannot build V, whatever else it can do.

`-c` becomes real here. Until then it exits with a message rather than writing an
object file that is not one, because a file that cannot be linked is worse than a
compiler that says it cannot make it.

Verified by linking programs that use libc, libm, pthreads and dl, and running
them. Then by linking V's own objects and comparing the result with a tcc link.

## M5: the V contract

The interop work, and the milestone that decides whether "drop-in" is true.

- Version output that V classifies correctly, and stays stable enough that
  cached artifacts keyed on the old answer are not silently wrong.
- Every flag V passes, accepted and either honored or deliberately ignored with
  a note: `-std=gnu11`, `-std=c99`, `-fwrapv`, `-fPIC`, `-w`,
  `-Werror=implicit-function-declaration`, `-g`, `-bt25`, `-B`, `-I`, `-L`,
  `-Wl,`, `-D`, object files and `.a` archives mixed with sources.
- `-run`, `-M`/`-MM`/`-MD` dependency output, `-x`, `@listfile`, stdin input,
  and the `-cc tinyc` semantics V switches codegen on.
- Self-hosted use: `-cc <vcc>` for V's own build.

Verified by building the V compiler and V's own test suite with vcc, and by
comparing each build against the same build with the bundled tcc.

## M6: speed

The constraint, not a stretch goal. TCC is fast because it is a single pass
compiler with no intermediate representation to speak of, and vcc has to be
within reach of that on the workload that matters: the megabyte-scale generated
C of a V self-build.

- Phase timings from `-bench` for every stage, tracked per commit rather than
  discovered later.
- A wall-time and peak-memory budget for the V self-build, measured against the
  bundled tcc on the same machine, checked in CI once the tree builds itself.
- Design choices that follow from the target: single pass over tokens, no
  building of a full AST where a streaming decision will do, arena allocation
  rather than per-node heap traffic, and output written with buffered writes.
- Parallel compilation of translation units, the way tcc and V's `fastc` both
  do, once the single-threaded path is fast rather than instead of making it
  fast.

Verified by the numbers, in every pull request that touches a hot path.

## M6a: two pipelines behind one command line

The default builds an AST. Parse into a tree, run `optimizer/` over it, emit from
it. That is the path correctness is proven on, and it is where the diagnostics
and the tests live. An AST is what makes an optimizer, a type checker and a
second target possible later, so it stays.

`-no-ast` is the second path: skip the tree and compile while reading the tokens,
deciding as it goes. Nothing is allocated per node, nothing is walked, nothing is
freed. That is where the rest of the distance to tcc's speed sits, since tcc
does the same and allocates almost nothing on the way. The intent for this path
is to beat tcc on the V self-build rather than to match it, and the AST path is
the one that has to stay close to it.

The rule that keeps it honest: **the same input produces the same bytes on both
paths.** The AST path is the reference implementation and the streaming path is a
verified fast version of it, not a second compiler with its own opinions. Any
difference is a bug in the streaming path, and the comparison belongs in the gate
over the same corpus the tests use, not in a one-off experiment.

Sequencing: M3 first (a streaming emitter cannot exist before there is an
emitter), then the streaming path as an alternative front end feeding the same
back end, then the byte-for-byte comparison, and only then a number that claims
to beat tcc.

## M7: the swap

Point V's `-cc` at vcc for a real build, run V's test suite, and compare against
the bundled tcc. When a V build with vcc passes the same tests at the same
speed, the proposal to vendor vcc in place of tcc becomes a question about
timing rather than about readiness.

## M8: the bootstrap chain

The end of the road, and the definition of done: four builds where the last one
closes the loop.

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 is the one that cannot be faked. vcc has to compile the megabytes of C V
emits for itself, link them against libgc and libc, and produce a V that builds
and passes V's own suite. Step 4 has to produce a vcc that behaves like the one
it came from, which is where fixed-point bugs show up: a compiler that
miscompiles itself once is usually miscompiling something subtle every time.

Verified by running the chain on a clean checkout, running `v test` on the V that
step 3 produced, and comparing the behavior of `vcc-v2` with `vcc-v1` on the same
inputs. The chain is then part of CI, because a fixed point that is not
continuously checked is a fixed point nobody has.

Measured on this tree, in the in-house form of steps 2 and 4 rather than planned:
with `-std=gnu11`, which is what V passes by default, `v -nocache -cc ./vcc
-showcc -o vcc-v1 .` exits 0, and `v -cc vcc-v1 -o vcc-v2 .` exits 0 as well.
vcc-v1 compiles the C V emits for this tree: `vcc-v1 -c -std=gnu11 -w -o src.o
src.c` exits 0 and writes 46,067,936 bytes, the size of the object the host
writes for the same file, and gcc links that object into a compiler that runs
and reports its version.

The output was not clean for a while, and that was this milestone's business
rather than a neighbour's. A compiler built this way wrote the wrong bytes where
the section names belong in the objects it writes: `.text`, `.rodata` and
`.data` came out as the bytes of the section contents, so its string table held
`55 48 89 e5 48` where `.text` belongs. The cause sat in the link rather than in
the writer. The image keys a string by the literal's own bytes, this tree's
object writer builds its name table from literals that spell the three section
keys, and the writable-data rewrite compared every reference's name against
those keys, so a reference to the literal `.text` was rewritten into a reference
to the code section and the field came back holding the section's start.

The comparison is by kind now (`b710ccb`): a key is compared only against a
reference whose kind names a place, which is what a relocatable object states,
and a `take_address` names an interned entry whatever it spells. `v test .` is
51/51, the corpus is 118 passed and 0 failed, the gate passes, and a compiler
built by this one writes `\0.text\0.rela.text\0.rodata\0.data\0` into
`.shstrtab` where it wrote code bytes. The two-to-three-byte difference between
two runs of one binary did not reproduce once the names were right, and the
twenty-six bytes between two builds of vcc is two builds rather than one input
compiled twice.

Step 4 was blocked by a compiler this one built segfaulting on inputs that make
the collector run while the front end is working. The witnesses were
`compliance/gnu/gnu99/0013-hosted-known-1.c` under `-std=gnu99` and
`compliance/iso/c99/1123-vprintf-formats-through-a-va-list.c` under `-std=c99`,
both exiting 139 with `-c`, with `-E` and with `-o`, and the smallest input that
still crashed was three includes, `<stdio.h>`, `<math.h>` and `<tgmath.h>`, under
`-std=gnu99`. `-E` alone reproduced it, so the crash was in the compiler rather
than in the link, and it was not in this tree's source, since `v -o vcc .` from
the same commit compiled both files and the gate passed.

The fault was in libgcc's unwinder rather than in this tree. `uw_update_context_1`
took a general protection fault on a `movaps` to its own frame, because the
sixteen-byte stack alignment the ABI requires across a call was not there, and the
chain that reached it is glibc's `backtrace()` called from libgc's
`GC_save_callers` on a collection, which that collector performs every time
(`SAVE_CALL_CHAIN` is on by default for Linux/x86, `thirdparty/libgc/gc.c:4059`).
The alignment was lost in a call this compiler generated. The class read as
floating point and variadic only because those cases are the ones that allocate
enough to collect: compiling the same generated C with gcc and linking it against
the same vendored `libgc.a` ran and exited 0 three times, so the defect was in the
object this compiler emits rather than in the linker or in libgc, and the first
generation compiled both witnesses and exited 0.

It was one rule in `codegen/`, fixed in 615aed0. A call whose arguments do not all
fit in registers takes one more word than it needs when the count of them is odd,
so that the call itself is aligned, which is right. That word was taken before the
stacked arguments were evaluated, and an object or a long double is evaluated in
that same loop. An argument that is itself a call therefore ran with the
reservation standing, eight bytes off, and a frame pointer that is not where
sixteen-byte stores to a frame expect it takes a general protection fault. A
`string` is three eightbytes, so a call returning one, written inside another
call's argument, is the smallest shape that shows it, and that shape is most of
V's generated C.

The measurement is a scanner that walks a function's control flow tracking `rsp`
modulo sixteen. This compiler's object for V's generated C had 2,337 call sites
where `rsp` was not sixteen-byte aligned, against 35 in gcc's object for the same
file, every one of them a cold-split part of a function no caller reaches. It
reports 0 now. `regression/iso/c99/0066-codegen-call-inside-a-stacked-argument.c`
holds the shape, and it is the one case here that needs no fault to observe the
defect: the callee reports the alignment of a local of its own frame, and the
compiler before 615aed0 answers "0 against 8" for one function called from a
statement and from inside a stacked argument.

In-house steps 2 and 4 produce a compiler that behaves like the one it came from.
`v -nocache -cc ./vcc -showcc -o /tmp/self .` exits 0 and writes 46,067,712
bytes, and that compiler runs both witnesses, three runs of the first and two of
the second, all exit 0. The corpora under it are clean: compliance 1066 passed, 68
refused, 0 failed and 17 skipped, with 906 of 906 monolithic checks passing, and
the regression corpus 119 passed and 0 failed, where the compiler built before the
fix reported 170 problems on the first and 5 on the second. What the chain still
owes is its own second half, V built by vcc and then V's suite under it, which is
step 3's bar rather than a behaviour of this compiler.

A compiler built this way is 46,067,712 bytes and statically linked, and it
carries the unwind table and its index the way any other program this compiler
links now does; `v -o vcc .` writes about 7.1 MB. Check which one is in the tree
before trusting it.

Relocatable objects now carry an unwind table, in 2aa2e40, where before they
carried none and gcc's carried a CIE and an FDE for every function. Every
function this compiler emits opens with the same prologue, so one CIE serves them
all: the canonical frame address is rbp plus sixteen, the caller's return address
at CFA minus eight, the saved frame pointer at CFA minus sixteen, and the return
address needs a rule of its own, `DW_CFA_offset rip,-8`, or a walker cannot find
the caller's program counter. The object holds one FDE per function body carrying
the body's place and length and no instructions of its own, and `.rela.eh_frame`
fills in each initial location with an `R_X86_64_PC32` against the `.text`
section symbol. A body's extent is not the distance to the next label, because
the routines an image writes behind the functions are code in the same section,
so the emitter records each body's run in `image.Program` and the writer reads
the ranges from there.

The measurement is a chain of three calls that prints the count `backtrace()`
returns: gcc answers 7, and the same source compiled by this compiler and linked
with gcc answers 7, where a compiler built before the change answered 1.

The in-house link carries it too, in 9b027dc and 0d2010b. The merge rebases each
body's run into the merged program, and the container places the table, writes
`.eh_frame_hdr` (version 1, the frame pointer as `DW_EH_PE_pcrel|DW_EH_PE_sdata4`,
the count as `udata4`, and a table of `DW_EH_PE_datarel|DW_EH_PE_sdata4` pairs
sorted by initial location), and advertises it with a `PT_GNU_EH_FRAME` program
header. The program that answered 1 above answers 5 now, and those five are the
chain: `leaf`, `middle`, `top`, `main` and the startup stub. gcc's seven counts
three frames this compiler never links, because a program starts from codegen's
own stub and leaves `crt1.o` out on purpose (`main.v:708`), so `_start`,
`__libc_start_main` and `__libc_start_call_main` are not in the chain to be
unwound. Nothing is truncated; the count differs because the startup does.

Two limits on the table. An object or archive unit exposes its `.eh_frame` bytes
rather than the runs the container builds from, so no frame inside `crt1.o` or
`libgc.a` is described in a link that includes one, and the self-build is such a
link. And a statically linked program that calls `backtrace()` aborts with exit
134; the same abort is there at 4de67f2, built in a worktree of that commit and
run with `-static` while the dynamic build of the same source answered 1, so the
static path never printed a count and this work did not break it.


## Later, and not yet planned

- **Other targets.** Linux x86-64 first, then arm64, then macOS and Windows.
  Each is a back end and a linking story, not a flag.
- **GCC extensions** that real code needs: `__attribute__`, statement
  expressions, `__builtin_*`, computed gotos. `extensions/` is reserved for
  this, and it stays empty until something real lands there.
- **Debug info.** `-g` producing usable DWARF rather than being accepted and
  ignored.

## Not on the roadmap

- C++ beyond what C already provides.
- A second command line that differs from tcc's. The point is to be a drop-in.
- Written in anything but pure V.
