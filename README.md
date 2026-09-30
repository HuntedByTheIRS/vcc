# vcc

vcc is a C compiler written in V. It has one job: replace the TCC binary that V
vendors in `thirdparty/tcc`, on the same command line, doing the same work.

Two constraints come before everything else.

**Pure V.** No C source in the compiler, no corner of the pipeline delegated to a
C compiler, no vendored C library. If a piece cannot be written in V yet, it
stays unimplemented rather than getting a C shortcut.

**Fast.** Near TCC's speed or better, which is not open to compromise.
Compiling the C that V generates for itself is the benchmark that matters: a
few megabytes of C per build, and vcc has to get through it in the time the
bundled tcc does, at comparable peak memory. A compiler that is correct but
slower is not a replacement, and it will not be merged in that state.

The default pipeline builds an AST, because that is what an optimizer, a type
checker and a second target are built on. A second path that skips the tree
entirely (`-no-ast`, planned) is where beating tcc outright is expected to come
from, and `ROADMAP.md` M6a carries the rule that keeps it honest: the same input
produces the same bytes whichever path compiles it.

## The bootstrap chain

The end this project works toward is a compiler that builds the language it is
written in, and that V can use in place of the tcc it vendors. Four builds, each
one a check on the step before it:

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 decides everything. vcc has to compile every megabyte of C that V emits
for itself, link it, and produce a V that passes V's own test suite. Step 4 then
has to produce a vcc that behaves like the one it was built from. When both hold,
the loop is closed and no C compiler other than vcc is in it. `ROADMAP.md` has
the milestones between here and that.


## Status

Early, and honest about it. The tree holds a compiler that reads real C (the
preprocessor walks the glibc headers on this machine with no diagnostics) and
writes a working Linux x86-64 executable that calls into libc.

```sh
v -o vcc .
printf '#include <stdio.h>\nint main(void) { puts("Hello, world!"); return 0; }\n' > hello.c
./vcc hello.c -o hello
./hello
```

That prints `Hello, world!`. `./vcc -run hello.c` does the same without leaving
an image behind, and the compiler leaves with the program's exit status.

Anything outside the subset below exits non-zero with a diagnostic that names the
construct and its source location, instead of writing an output file that would
fail later.

It accepts the flags V passes to a C compiler (`-std=`, `-w`, `-fwrapv`, `-g`,
`-B`, `-I`, `-L`, `-l`, `-Wl,` passthroughs, `-bt25`, `-x`, `@listfile`, `-`),
plus `--version`, `-v`, `-h`, `-hh`, `-run`, `-E`, `-c`, `-o`, `-bench`,
`-print-ast`, the `-O` and `-f(no-)builtin` flags below, and the preprocessor's
own: `-D`, `-U`, `-nostdinc`, `-undef`, `-include`, `-imacros`, `-M`, `-MM`,
`-MD`, `-MMD`, `-MF`, `-MT` and `-dM`. See `vcc -hh` for the annotated list.

`-std=` selects the dialect rather than only being recorded: `-std=c99` and
`-std=gnu99` are the two modes the compiler has, and every other spelling,
including the `-std=gnu11` V passes when it writes none, is recorded and never
refused. The two modes differ in one macro, defined before the first line of the
program is read: `-std=c99` defines `__STRICT_ANSI__ 1` and `-std=gnu99` does
not, which is what gcc 16.2.1 defines with the same flags. The standard headers
read that macro, and it decides which declarations they expose: as c99 the C
library shows the program the declarations C99 has and hides the POSIX ones
beside them, and as gnu99 it shows both. `-std=c99` is therefore the strict path,
and it is the one place where the two modes differ in what they accept: a
`<stdlib.h>` program that stops in the header as gnu99 compiles as c99, which is
what gcc does with the same file under the same flag.

`preprocess/` is a C preprocessor and not a macro pass bolted onto the parser:
`#include` with C's search order and `#include_next`, object-like and
function-like macros with `#`, `##` and variadic arguments, conditionals with the
full `#if` expression grammar, `#pragma once`, `#line`, `#error`, `#warning` (a
warning, so the compile goes on without it), `_Pragma`, the location and clock
macros, and `__has_include` beside the `__has_attribute`-shaped family, answered
the way a compiler that honors none of it should answer.

Its fidelity is checked against `tcc -E` on the same file, token by token, and
the differences that remain are tcc's own: it says it is `__TINYC__`, so glibc
keeps `__asm__`-shaped redirections for it, while this compiler says it is
nothing else and gets them erased. `-E` prints the stream as a table of
`file:line:col`, token kind and text, which is what that comparison reads.

The parser reads what a preprocessed header is made of (typedefs, prototypes,
structs) and the function definitions after them: parameters, local variables,
assignments, arithmetic, calls, string literals, `double` values, `if`/`else`,
`while`, and `for` with `break` and `continue`. A conversion is a type name in
parentheses and converts between the four classes the back end carries, `sizeof`
answers the size of a type name or an expression as a constant, `*` reads the
value at an address and `&` takes one, and two addresses are compared at the
width of a word. A typedef is a name for the type
it was declared as and is followed wherever a type can be written, so a
declaration written through one is the declaration of the type behind it; a name
standing for a type the back end has no form for is refused as that type and not
as the name, so `typedef long Big; Big x;` says `unsupported type long`. A
definition of a `static` function that nothing else in the file names is stepped
over before its specifiers are read, because a header's helpers are often written
in types this reader has no form for, and a program that never calls one should
not be refused over it. Anything outside the subset is diagnosed rather than
miscompiled.

`typeof` is a specifier: the operand between the parentheses is a type name or
an expression, the value written there is never evaluated, and the type of that
operand is what the declaration that follows declares. So `typeof(x) y = 4;` is
an object of the type `x` has, `typeof(int) *p` is a pointer to an int, and
`sizeof(typeof(x))` answers the size of that type. The four spellings are read:
`typeof` (C23, and a GNU word besides), `__typeof__` and `__typeof` (reserved, so
they are read in every mode including c89, which is what gcc 16.2.1 does with
them), and `typeof_unqual`, which is the same type with the qualifiers taken off
it. Measured on gcc 16.2.1, bare `typeof` is not a word under `-std=c99` and is
one under `-std=gnu99` and `-std=c23`; this compiler reads it in every mode and
reports it through the dialect table when the mode does not have it. Two operands
are refused by name: one whose type was never resolved, and one of an array type,
which would make the declaration an array the declarator never wrote.

The back end emits one RWX `PT_LOAD` at `0x400000` with a `PT_INTERP`, its own
`_start`, `DT_NEEDED libc.so.6` and no PLT: calls are resolved by the dynamic
loader, which is what makes `puts` work without a linker. `-l` adds the library
it names to that list: each `-l<name>` is resolved the way a linker would, through
the ld script in `/usr/lib` when the file it finds is one, and the SONAME of the
file at the end of that is what the image asks the loader for, which is how
`-lm` gets `sqrt` to resolve. A frame holds ints, pointers, chars and doubles. A
char is one byte in its slot and an int when it is read, which is where the
language's promotion of it happens, and a double is eight bytes in its slot and a
value in the floating-point registers while it is worked on. An array is a block
of that frame and its name is the address of its first element, so `puts(buf)`
passes the bytes themselves. An object defined at the top level is storage the
image holds instead: one blob laid out beside the code, with the constant it
starts at written into it, eight bytes of it when the object is a double, and
every function that names it reads and writes the same bytes. Taking the address
of a local with `&` is an address like any other, which is what makes
`scanf("%d", &x)` write into the local itself, and a definition that returns
`void` is a definition with nothing in the return register to read.

`optimizer/` accepts `-O0` through `-O3`, `-Os`, and the `-f(no-)builtin`
spellings. What a level turns on today is one pass: a call whose value the
compiler knows (`abs`, `labs`, `llabs`, and the reserved `__builtin_` spellings
of each) with a literal argument folds to that value. A call whose value is read
is emitted like any other expression (the result arrives in the register a value
is expected to be in), so `-O0` makes the call and `-O2` folds it to `7`: the
level decides whether a call the optimizer knows is folded, not whether it can be
made. `-fno-builtin` and `-fno-builtin-abs` take the fold back; a call written
`__builtin_abs` is an explicit request and folds at any level.

`-print-ast` parses, prints the tree the emitter would be given, and stops
without writing anything. It is how a parse or an optimization is read rather
than guessed at. `-c` is the other half of that: it is accepted and says it
cannot write an object file yet, which is M4. `-M` writes the make rule that says
what a file is made of: `-MM` leaves the system headers out of it, `-MD` and
`-MMD` write it and go on to compile, `-MF` says where the rule goes and `-MT`
names its target; `-dM` prints what is defined when the read ends, and
`-include` and `-imacros` read a file before the source does.

An object of a struct or union type is a block of storage whose members are read
and written at the offsets the layout gives them, for int, char and double members.
Inside a function that storage is in the frame and at the top level it is in the
image, and an array of them is a stride of the layout's size times an index. A
member of a member is the same object read further in, and `->` reads the member
from the object a pointer names. An object of sixteen bytes or fewer is passed to a
function and handed back from one as its bytes in the registers the classes of its
eightbytes name; a larger one is a copy on the stack going in and an address the
caller names coming back. An assignment between two objects of a type copies the
bytes, and so does writing a call's result into the object it is assigned to. The
arguments a call passes past the machine's registers go on the stack, six ints and
eight doubles being what the registers carry.

Not implemented, in rough order of how much of the tree depends on it: an element of
an array passed by value, and a call's result passed by value; `enum`; the shift
and bitwise operators (`<<`, `>>`, `&`, `|`, `^`); unsigned integer types;
`switch`; an array
with an initializer or more than one size; a pointer defined at the top level;
object files and relocatable output; and V's own generated C. `ROADMAP.md` maps the
order.

The speed constraint is measured, not assumed, and the current numbers are not
close. On a workload both compilers accept (`tools/bench.vsh --terms 20000`, a
constant chain and nothing else), vcc takes about 12x tcc's wall time and 10x its
peak memory; at 100000 terms it is about 28x the time and 35x the memory, so the
ratio still grows with the input. Most of that gap is allocation per token and per
AST node, which is a design problem rather than a constant factor.

## Build

Needs V built from source on Linux x86-64, at a commit that accepts this tree.
The 0.5.2 release does not: its checker rejects a `for {}` whose every path
returns, which `parser/parser.v` uses in `parse_parameters` and
`parse_arguments`. Everything since accepts it, and CI pins the commit it tests
with in `.github/workflows/ci.yml`.

```sh
git clone https://github.com/vlang/v && cd v && make   # once
cd /path/to/vcc
v -o vcc .        # build the compiler
v test .          # lexer, parser, optimizer, printer, pipeline, codegen tests
v run tools/gate.vsh                          # everything a pull request has to pass
v run tools/bench.vsh                         # wall time and peak memory, tcc alongside
v -o vcc . && ./vcc -bench seven.c -o seven   # per-phase timing
```

`-bench` prints microseconds per phase. It exists from the first commit because
the speed target is a hard requirement, and a number nobody prints is a number
nobody watches. `tools/` holds the gate and the benchmark harness; `tools/README.md`
says what each one checks.

CI runs the same gate against the pinned V commit, runs the build and the tests
against V master as an informational job, and writes the benchmark numbers into
the run summary. Tagging `vX.Y.Z` publishes a binary through
`.github/workflows/release.yml`, which refuses to publish if the version inside
the compiler disagrees with the tag.


## Layout

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | the tcc-compatible command line: flags, usage, version, phase timings |
| `tokenize/` | lexer: source text to tokens |
| `ast/` | node types the parser produces and the back end consumes |
| `parser/` | recursive descent parser for the supported subset |
| `optimizer/` | `ast` in, `ast` out: `-O` levels and the builtin table |
| `printer/` | `ast` in, text out: what `-print-ast` prints |
| `backend/` | target description: `arch/` is the machine, `os/` is the system, `backend.v` composes them |
| `codegen/` | translation unit to bytes: constant folding and the ELF64 container |
| `tools/` | gate and benchmark scripts; not part of the compiler |
| `extensions/` | the vendor extensions `-fvcc-exts=` names. Nothing is honored yet, so the flag changes nothing about what compiles |

A target is data rather than a directory of hand-written emission, and it has
two dimensions. `backend/arch/` describes a machine: its register file, how a
register is numbered in an instruction, where a function's arguments arrive.
`backend/os/` describes a system: the kernel entry points a program can call, the
numbers they take, and the loader constants a container is built from. Neither
knows the other exists, and every arch-dependent answer the system gives is asked
for by machine name, which is what lets a second system be written without
touching the first one's file.

`backend/backend.v` is where the two meet, in a `Target` composed from one of
each. The emitter asks that, so a new architecture, a new system, or a new fact
about either is a table that changed and not a branch in `codegen/`.

Tests live next to the code as `*_test.v` files and run with `v test .`.

## What a drop-in has to satisfy

V does not just hand its generated C to whatever binary is on `PATH`. It looks
the compiler up, asks it for a version, and picks codegen and flags from the
answer. Notes for whoever works on interoperability, all read off the V tree:

- V resolves the compiler name from the real path of the binary. A name holding
  `tcc` or `tinyc` is classified as `tinyc` immediately; otherwise V runs
  `--version` and looks for `tiny c compiler` or `tcc version` in the output.
  This is why vcc's version line matters beyond cosmetics: it decides whether V
  passes tcc-only flags and emits tcc-shaped C.
- `ccompiler_can_assemble` treats anything that answers like tcc as unable to
  assemble a `.S` file. A replacement that does assemble asm has to be
  recognized as gcc-like instead, which is a decision about identity and not a
  flag.
- V caches build artifacts keyed on the identity of the C compiler, and compares
  that identity against the default `cc`. `--version` has to be stable and
  machine-parseable, and every integration test has to run from a clean cache.
- Flags V passes and a replacement must accept: `-std=gnu11`, `-std=c99`,
  `-fwrapv`, `-fPIC`, `-w`, `-Werror=implicit-function-declaration`, `-g`,
  `-bt25`, `-B<dir>`, `-I<dir>`, `-L<dir>`, `-Wl,` passthroughs, `-lc -lm -ldl
  -lpthread` in that order, `-D` defines, and object files and `.a` archives
  mixed in with sources. Never error on a flag you do not implement.
- The vendored tcc also carries a garbage collector, and V links it into every
  tcc build. `v -showcc -cc tcc probe.v` prints the whole list:
  `-DGC_THREADS=1 -DGC_BUILTIN_ATOMIC=1 -I<v>/thirdparty/libgc/include
  <v>/thirdparty/tcc/lib/libgc.a -ldl -lpthread -lm`. So a replacement has to
  link an archive of prebuilt objects against the program it just compiled, which
  makes the `libgc.a` path part of the drop-in contract rather than an optional
  library it could decline.

## Read next

- `CONTRIBUTING.md` for the build, test, and commit workflow.
- `AGENTS.md` for coding-agent rules in this repository.
- `ROADMAP.md` for the milestones between the stub and a usable compiler.
- `ISSUES.md` and `DISCUSSIONS.md` for where reports and questions go.
- `SECURITY.md` for what counts as a vulnerability in a compiler.
- `CODE_OF_CONDUCT.md` for how people are expected to treat each other.

## License

BSD 3-Clause. See `LICENSE`.
