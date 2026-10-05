# Roadmap

The order is deliberate: the front end before the back end, the back end
before linking, and the V contract before anyone swaps the binary. Each
milestone names how it is verified, and each one ends at the same gate: the V
self-build does not get slower. This page follows `ROADMAP.md`, the file of
record.

## Where the tree is

The tree records one status line: past the stub, at the end of M1. The
preprocessor is real, the front end reads the declarations a header is made of
and the function definitions after them, and the back end writes a dynamically
linked Linux x86-64 executable that calls into libc. Function bodies with
parameters, locals and control flow run, as do top-level objects, arrays, a
`double`, typedefs, `typeof` and `__int128` as storage. `enum`, the shift and
bitwise operators and the unsigned integer types are still on the list.

No other milestone carries a status in the tree. Where nothing is recorded,
this page says so rather than guessing.

The two dated targets come from `README.md`:

- Full C99 conformance in the tree by the end of October 2026.
- The V self-build, meaning bootstrap step 3, by the end of Q4 2026 or early
  Q1 2027.

Speed is measured, not felt. Against the tcc V vendors, `tools/bench.vsh`
records vcc at about 27x tcc's wall time and 16x its peak memory on a
20000-term constant chain, and about 69x and 57x at 100000 terms. The ratio
grows with the input because tcc's time is nearly flat while vcc's tracks the
tokens and nodes it allocates. That gap is the M6 problem, and it is measured
rather than guessed.

## M0: the stub

Done when `v test .` passes, the lexer covers the C preprocessing-token
grammar, the parser covers the subset the README lists, the ELF writer
produces a binary that runs, and every unsupported construct has a diagnostic
with a location.

## M1: the preprocessor

A real C preprocessor rather than a macro pass bolted onto the parser:
`#include` with quoted and angle search paths, object-like and function-like
macros with `#` and `##`, variadic macros, `#if` with the full constant
expression grammar, `#ifdef`, `#elif`, `#error`, `#line`, `#pragma once`, and
the `__LINE__`, `__FILE__` and `__DATE__`-class predefined macros plus the
`__TINYC__`-shaped ones V's codegen may test for. `-I`, `-D`, `-U`,
`-nostdinc` and `-E` become real.

Verified by preprocessing the same file with `tcc -E` and diffing the token
streams, macro definitions and include order included.

## M2: the front end

The C11 grammar as GNU C actually uses it: declarations and declarators
including the pointer and array spellings that read backwards, structs,
unions, enums, typedefs, bitfields, `sizeof` and `alignof`, casts, compound
literals, designated initializers, `switch`, loops, `goto`, labels, variadic
functions, `_Bool` and the integer and floating types, and constant expression
folding. Diagnostics carry a file, line, column and a note saying what the
compiler expected instead.

Verified by parsing and type-checking the corpus of generated C V emits for
itself, plus the C in V's `thirdparty/` and a few real-world projects, and
comparing acceptance against tcc.

## M3: the x86-64 back end

Instruction selection, register allocation, stack frames and the SysV calling
convention, global and thread-local storage, sections, relocations, `.S`
input, inline assembly, and correct integer and floating point semantics
including the signed overflow wrapping V's generated code assumes. Symbols get
the right linkage, visibility and alignment, and `-O` levels exist and do
something.

Verified by running the compiled programs and diffing behavior against tcc's
output for the same input, not by reading the assembly. A new architecture or
system is a file under `backend/arch` or `backend/os` plus a line in the
composition, so the milestone grows by tables rather than by platform
branches.

## M4: objects, linking and output formats

ELF relocatable objects, an `ar` archive reader, executable linking against
libc, static and shared output, `-L`/`-l` search order, `-shared`, `-r`,
`-nostdlib`, `-Wl,` passthroughs and crt startup objects. This is where the
compiler stops producing standalone binaries and starts doing the job V needs:
linking a program against the system libraries. Archive support is not
optional for the V contract, because every `-cc tcc` build links
`thirdparty/tcc/lib/libgc.a`. `-c` becomes real here; until then it exits with
a message rather than writing an object file that is not one.

Verified by linking programs that use libc, libm, pthreads and dl and running
them, then by linking V's own objects and comparing the result with a tcc
link.

## M5: the V contract

The interop work, and the milestone that decides whether "drop-in" is true. It
covers version output that V classifies correctly and stays stable, every flag
V passes accepted and either honored or deliberately ignored with a note, the
`-run`, `-M`-family, `-x`, `@listfile` and stdin surfaces, and self-hosted use
as `-cc <vcc>` for V's own build.

Verified by building the V compiler and V's own test suite with vcc, and by
comparing each build against the same build with the bundled tcc.

## M6: speed

The constraint rather than a stretch goal. TCC is fast because it is a
single-pass compiler with almost no intermediate representation, and vcc has
to be within reach of that on the workload that matters: the megabyte-scale
generated C of a V self-build. The milestone carries phase timings from
`-bench` tracked per commit, a wall-time and peak-memory budget for the V
self-build checked in CI once the tree builds itself, design choices that
follow from the target, and parallel compilation of translation units once the
single-threaded path is fast.

Verified by the numbers, in every pull request that touches a hot path.

## M6a: two pipelines behind one command line

The default builds an AST and runs `optimizer/` over it; that path is where
correctness, the diagnostics and the tests live. `-no-ast` is the second path:
skip the tree and compile while reading the tokens, allocating nothing per
node. That is where the rest of the distance to tcc's speed sits, and the
intent is to beat tcc on the V self-build rather than to match it. The rule
that keeps it honest: the same input produces the same bytes on both paths, so
the AST path stays the reference and the streaming path is a verified fast
version of it. Sequencing: M3 first, then the streaming path as an alternative
front end feeding the same back end, then the byte-for-byte comparison over
the same corpus the tests use, and only then a number that claims to beat tcc.

## M7: the swap

Point V's `-cc` at vcc for a real build, run V's test suite, and compare
against the bundled tcc. When a V build with vcc passes the same tests at the
same speed, the proposal to vendor vcc in place of tcc becomes a question
about timing rather than about readiness.

## M8: the bootstrap chain

The end of the road and the definition of done: four builds where the last one
closes the loop.

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 is the one that cannot be faked: vcc has to compile the megabytes of C
V emits for itself, link them against libgc and libc, and produce a V that
builds and passes V's own suite. Step 4 has to produce a vcc that behaves like
the one it came from, which is where fixed-point bugs show up.

Verified by running the chain on a clean checkout, running `v test` on the V
that step 3 produced, and comparing the behavior of `vcc-v2` with `vcc-v1` on
the same inputs. The chain is then part of CI, because a fixed point that is
not continuously checked is a fixed point nobody has.

## Later, and not yet planned

- Other targets. Linux x86-64 first, then arm64, then macOS and Windows. Each
  is a back end and a linking story, not a flag.
- GCC extensions that real code needs: `__attribute__`, statement expressions,
  `__builtin_*`, computed gotos. `extensions/` is reserved for this and stays
  empty until something real lands there.
- Debug info. `-g` producing usable DWARF rather than being accepted and
  ignored.

## Not on the roadmap

- C++ beyond what C already provides.
- A second command line that differs from tcc's. The point is to be a drop-in.
- Written in anything but pure V.
