<p align="center">
  <img src="vcc.png" alt="vcc logo: a green V" width="180" style="border-radius: 15px;">
</p>

<h1 align="center">vcc</h1>

<p align="center">A C compiler written in V, built to replace the tcc that V vendors in <code>thirdparty/tcc</code>.</p>

<p align="center">
  <a href="https://github.com/HuntedByTheIRS/vcc/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/HuntedByTheIRS/vcc/ci.yml?style=flat&label=ci" alt="ci status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/HuntedByTheIRS/vcc?style=flat" alt="license"></a>
  <a href="https://github.com/HuntedByTheIRS/vcc"><img src="https://img.shields.io/github/languages/top/HuntedByTheIRS/vcc?style=flat&label=pure%20V" alt="pure V: 100%"></a>
  <a href="ROADMAP.md"><img src="https://img.shields.io/badge/platform-linux%20x86--64-2ea043?style=flat" alt="platform: Linux x86-64"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/tests-1300-2ea043?style=flat" alt="tests: 1300"></a>
  <a href="compliance/README.md"><img src="https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/compliance-tests.json&query=$.tests&label=compliance%20tests&color=2ea043&style=flat" alt="compliance tests"></a>
  <a href="https://github.com/HuntedByTheIRS/vcc/commits/main"><img src="https://img.shields.io/github/last-commit/HuntedByTheIRS/vcc?style=flat" alt="last commit"></a>
</p>

It has one job: be a drop-in for that tcc. Same command line, the same work, so
that the C compiler in V's build is a program V can build, read and patch in V.

Two rules come before everything else here.

**Pure V.** No C source in the compiler, no corner of the pipeline delegated to
a C compiler, no vendored C library. If a piece cannot be written in V yet, it
stays unimplemented rather than getting a C shortcut. There is one exception,
named and off by default: `-external-linker=NAME` hands the final link to a
linker already on the system, for the inputs this compiler cannot consume yet.
It refuses `cc`, `gcc`, `clang`, `c++` and `tcc` by name, because a C compiler
finishing C compilation is the one thing the rule exists to prevent.

**Fast.** Near tcc's speed, which is not open to compromise. The benchmark that
matters is V's self-build: a few megabytes of generated C per run, and vcc has
to get through it in the time the bundled tcc does, at comparable peak memory. A
compiler that is correct but slower is not a replacement. Speed claims here are
measurements, and the commands that produce them are printed beside the numbers.

## What it is and what it's for

The default pipeline builds an AST, because an optimizer, a type checker and a
second target are all built on one. A second path that skips the tree entirely
(`-no-ast`, planned) is where beating tcc outright is expected to come from.
`ROADMAP.md` M6a carries the rule that keeps the two honest: the same input
produces the same bytes whichever path compiles it.

The end this works toward is a compiler that builds the language it is written
in, and that V can use in place of the tcc it vendors. Four builds, each one a
check on the step before it:

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 decides everything. vcc has to compile every megabyte of C that V emits
for itself, link it, and produce a V that passes V's own test suite. Step 4 then
has to produce a vcc that behaves like the one it came from. When both hold, the
loop is closed and no C compiler other than vcc is in it.

## The case for one C compiler in V's build

V does not treat a C compiler as an opaque binary. It classifies it (by the real
path of the binary, then by `--version`), picks codegen and flags from the
answer, and caches build artifacts keyed on that identity. To do that across
GCC, Clang, MSVC and tcc, V has to carry a branch for each one: which flags to
pass, which C to emit, which quirks to route around. Every branch is a way a
build can go wrong, and none of them makes V's own generator smaller.

vcc is the bet that V needs one compiler instead of four, and that the one
should be a program V can read.

- The command line is already V's. vcc accepts the flags V passes to a C
  compiler (`-std=gnu11`, `-std=c99`, `-fwrapv`, `-fPIC`, `-g`, `-w`,
  `-Werror=implicit-function-declaration`, `-bt25`, `-B<dir>`, `-I<dir>`,
  `-L<dir>`, `-l<name>`, `-Wl,` passthroughs, `-D` defines), plus the
  preprocessor's own flags and `--version`. A flag it does not implement is
  recorded and never refused, because a compiler that errors on `-bt25` fails a
  build it was supposed to serve. `./vcc -hh` prints the annotated surface.
- It is written in V, so it builds with V, is read in V, and a bug in it is
  debugged with the same tools as a bug in V. There is no thirdparty C program
  to trust or carry as an opaque binary.
- The extensions V's generated C actually uses are read on purpose: `typeof`,
  `__int128`, the atomic builtins, statement expressions, `__attribute__`. They
  are in the table because V emits them, not because they were easy.
- Only a compiler written in V can close the bootstrap loop above. GCC and Clang
  can build V; they cannot be built by the V that they built.
- BSD 3-Clause, and no dependency in `v.mod`.

It does not yet argue speed. vcc is behind tcc today, and the numbers are in
"What vcc does today". The claim is that the gap is measured and the design can
close it, not that it is closed.

## Benefits and downsides

**What standardizing on vcc would buy.** V supports one C compiler instead of
four, so its generator drops per-compiler branches and its release stops
depending on a thirdparty binary whose bugs live outside the tree. The compiler
itself becomes V code: a miscompile is diagnosed in the same language and the
same repository as the tool that hit it, and the bootstrap chain ends with no
foreign compiler in the loop at all. The extensions V's own generated C needs
are supported by design rather than by accident of which compiler was installed.

**What it would cost.** vcc is young and incomplete. It reads a large
subset of C and refuses the rest with a diagnostic naming the construct and its
location, which is the right failure but still a failure: a program outside the
subset does not compile, and the subset is smaller than GCC's. It is not
self-hosting yet and cannot compile V's generated C. Linking more than one
translation unit, `-shared` and `-static` currently need
`-external-linker=NAME`, because the in-house linker is not written. It targets
Linux x86-64 only; arm64, macOS and Windows are back ends that do not exist yet.
It is slower than tcc, by a margin that grows with input size. And a compiler in
the bootstrap chain is high-stakes: if vcc miscompiles a subtle thing, the V it
builds is wrong in a way that is hard to attribute, which is why the chain is
verified by V's own test suite and not by the build exiting zero.

## What vcc does today

Roughly, a usable C compiler for a large slice of Linux x86-64 C: it reads real
headers, generates code, and writes a working executable that calls into libc.
It is past the stub. The detail below is what has been verified by running the
resulting binaries, not by reading the source.

### Compatibility with C and with V

The preprocessor is a real one, not a macro pass bolted onto the parser:
`#include` with C's search order and `#include_next`, object-like and
function-like macros with `#`, `##` and variadic arguments, conditionals with the
full `#if` expression grammar, `#pragma once`, `#line`, `#error`, `#warning`
(a warning, so the compile continues), `_Pragma`, the location and clock macros,
and `__has_include`. Its fidelity is checked against `tcc -E` on the same file,
token by token.

The front end reads what a preprocessed header is made of (typedefs, prototypes,
structs, unions, enums, bitfields) and the function definitions after them, with
the operators, control flow (`if`/`else`, `while`, `for`, `do`, `switch`,
`goto`), `sizeof` and casts, designated initializers, compound literals,
variadic functions, function pointers, and objects of `struct`/`union` type
passed and returned by value. An object of a struct or union is a block of
storage read and written at the offsets the layout gives it. A typedef and a
`typeof` specifier are followed to the type they name.

The back end emits one executable `PT_LOAD` at `0x400000` with a `PT_INTERP`, its
own `_start`, `DT_NEEDED libc.so.6` and no PLT: calls resolve through the dynamic
loader, which is what makes `puts` work without a linker. `-l<name>` resolves the
library through the ld script in `/usr/lib` when the file it finds is one, and
the SONAME of the file at the end of that is what the image asks for, which is
how `-lm` gets `sqrt` to resolve. `-c` writes a real ELF64 relocatable object.
`-fPIC` reaches top-level objects through the global offset table so the object
can go into a shared library later.

Verified today on this machine: a program including `stdio.h`, `stdlib.h`,
`string.h`, `stdint.h`, `stddef.h`, `limits.h`, `errno.h` and `time.h` compiles
clean with `-c`; enum/switch/shift/bitwise/unsigned code compiles and runs; a
program with designated initializers, compound literals, bitfields, a union, and
a struct returned by value compiles and runs.

Anything outside the subset exits non-zero with a diagnostic that names the
construct and its location, instead of writing an output file that would fail
later. A silent empty output file is treated as a bug.

### Compiler extensions

The vendor extensions the tree carries are read because C code in the wild, and
V's generated C in particular, uses them. The spellings that follow the
reserved-namespace rules (`__typeof__`, `__asm__`) are read in every mode, the
way gcc reads them; the ones a standard introduced (`typeof`, `auto`,
`_Generic`, `_Static_assert`, `_BitInt`) are gated by the dialect table and can
be brought down to an earlier mode with `-fvcc-exts=`.

What the tree reads includes `typeof`, `__typeof__`, `__typeof` and
`typeof_unqual`; C23 `auto`; `_Generic`; `_Static_assert`; `_BitInt(128)`;
`__int128`; GNU statement expressions; `__asm__`; a postfix `__attribute__`; the
`__atomic_*` operations; and the count-leading and count-trailing builtins.

```sh
./vcc -fvcc-exts=all prog.c -o prog      # every extension the compiler has
./vcc -fvcc-exts=typeof,generic -std=c99 prog.c   # named ones
```

The names are the rows in `standard/features.v`, not a list kept apart from
them; `-fvcc-exts` reads the extension column of that table, so a construct that
gains an extension is a row that changed.

### ISO conformance

The compiler carries a dialect table: one row per construct, holding the standard
it belongs to, whether a GNU dialect takes it, and what this compiler does with
it. A `-std=` spelling selects a mode (`c89` through `c29`, and the `gnu` dialects
of each); every spelling this compiler does not implement is recorded and never
refused, because tcc accepts every spelling and a compiler V may hand any
spelling to must not fail on one. The table is data, not a chain of branches: a
construct the compiler gains is a row whose status changes.

Reporting is separate from refusing. A construct the selected mode merely does
not allow is a pedantic message, silent until `-Wpedantic` or `-pedantic` asks
for it, promoted to an error by `-pedantic-errors` or `-Werror=pedantic`, and
silenced by `-w`. A construct the mode does not have at all is a diagnostic the
compiler raises on its own account, which no flag silences. System headers are
exempt, because nobody in the build wrote them.

Each row's phrasing was checked against gcc 16.2.1 under the relevant `-std=`,
and the comment on the row records what was measured. For example, `-std=c99
-pedantic` on `typeof(int) x = 3;` reports `ISO C99 forbids the typeof specifier`
and exits non-zero, matching gcc's refusal; `-std=c11` accepts `_Generic`
silently where `-std=c99 -pedantic` warns.

The suite is 1300 tests, run with `v test .`.

## Where it's going

Targets, in order:

- Full C99 conformance in the tree by the end of October 2026.
- The V self-build, meaning vcc compiling V's generated C and the result passing
  V's test suite (bootstrap step 3), by the end of Q4 2026 or early Q1 2027.

Between here and there, the known gaps are the ones named above: the in-house
linker (multi-unit linking, archives, `-shared`, `-static`) without
`-external-linker`, V's generated C, and the streaming path that is meant to
close the speed gap. `ROADMAP.md` lays out the milestones and what verifies
each one.

Speed is the number to watch, and it is not close yet. Measured with
`v run tools/bench.vsh` against the tcc V vendors:

| terms | vcc wall | tcc wall | ratio | vcc peak | tcc peak | ratio |
|---|---|---|---|---|---|---|
| 2 000 | 30.2 ms | 5.1 ms | 6.0x | 14.4 MB | 3.4 MB | 4.2x |
| 20 000 | 196.2 ms | 7.2 ms | 27.1x | 55.4 MB | 3.4 MB | 16.4x |

The ratio grows with the input because tcc's own time barely moves, 5.1 ms to
7.2 ms across these two counts, while vcc's tracks the tokens and nodes it
allocates. That is a design problem and the M6 problem, not a constant factor to
trim.

## Extras

### Build and run it

Needs V built from source on Linux x86-64, at a commit that accepts this tree.
The 0.5.2 release does not: its checker rejects a `for {}` whose every path
returns, which `parser/parser.v` uses. Everything since accepts it, and CI pins
the commit it tests with in `.github/workflows/ci.yml`.

```sh
git clone https://github.com/vlang/v && cd v && make   # once
cd /path/to/vcc
v -o vcc .                 # build the compiler
v test .                   # the suite
v run tools/gate.vsh       # format, pure-V rule, build, tests, doc links, workflows
v run tools/bench.vsh      # wall time and peak memory, tcc alongside
./vcc -bench file.c -o out # per-phase timings
```

```sh
printf '#include <stdio.h>\nint main(void) { puts("Hello, world!"); return 0; }\n' > hello.c
./vcc hello.c -o hello && ./hello
./vcc -run hello.c        # same, without leaving an image behind
```

`-run` leaves with the program's exit status. `-print-ast` parses, prints the
tree the emitter would be given, and stops without writing anything, which is
how a parse or an optimization is read rather than guessed at.

### Flags beyond the V contract

Also accepted: `--version`, `-v`, `-vv`, `-h`, `-hh`, `-E`, `-c`, `-o`, `-run`,
`-bench`, `-print-ast`, the `-O0` through `-O3` and `-Os` levels, `-fno-builtin`
and `-fno-builtin-NAME`, `-fPIC`/`-fpic`, `-nostdinc`, `-undef`, `-include`,
`-imacros`, the dependency flags `-M`/`-MM`/`-MD`/`-MMD`/`-MF`/`-MT`/`-MQ`,
`-dM`, `-Wclass`/`-Wno-class`, `-femulation=NAME` (define the identity macros of
gcc, clang or tcc instead of vcc's own), `-external-linker=NAME`, `-shared`,
`-static`, and the gcc `-print-` family. See `./vcc -hh` for the annotated list.

`-O` today turns on one optimizer pass: a call whose value the compiler knows
(`abs`, `labs`, `llabs`) with a literal argument folds to that value, `-O0` makes
the call and `-O2` folds it. `-fno-builtin` takes the fold back.

### Layout

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | the tcc-compatible command line: flags, usage, version, phase timings |
| `tokenize/` | lexer: source text to tokens |
| `diagnostics/` | what a diagnostic is: class, severity, and the one place it becomes text |
| `standard/` | the dialects: `-std=` spellings, the modes, and the feature table |
| `preprocess/` | the C preprocessor |
| `ast/` | node types only |
| `parser/` | tokens in, `ast` out |
| `optimizer/` | `ast` in, `ast` out: `-O` levels and the builtin table |
| `printer/` | `ast` in, text out: what `-print-ast` prints |
| `backend/` | target description: `arch/` the machine, `os/` the system, `abi/` the calling convention, `backend.v` composes them |
| `codegen/` | `ast` in, an emitted unit out |
| `image/` | the emitted unit: machine code, the data it reads, the references between them |
| `extensions/` | the `-fvcc-exts=` interface, built on the rows in `standard/features.v` |
| `tools/` | gate and benchmark scripts; not part of the compiler |

A new machine, a new system, or a new calling convention is a module of its own
under `backend/`, and `codegen/` never learns about it.

### What V asks of a C compiler

Notes for whoever touches interoperability, all read off the V tree:

- V resolves the compiler name from the real path of the binary. A name holding
  `tcc` or `tinyc` is classified as `tinyc` immediately; otherwise V runs
  `--version` and looks for `tiny c compiler` or `tcc version`. This is why
  vcc's version line matters beyond cosmetics: it decides whether V passes
  tcc-only flags and emits tcc-shaped C.
- V caches artifacts keyed on that identity and compares it against the default
  `cc`, so `--version` has to be stable and machine-parseable, and integration
  tests run from a clean cache.
- The vendored tcc carries a garbage collector that V links into every tcc
  build (`.../thirdparty/tcc/lib/libgc.a`), so a replacement has to be able to
  link an archive against the program it just compiled. `v -showcc -cc tcc
  probe.v` prints the whole list.

### Docs

- `CONTRIBUTING.md` for the build, test and commit workflow.
- `AGENTS.md` for coding-agent rules in this repository.
- `ROADMAP.md` for the milestones between the stub and a usable compiler.
- `tools/README.md` for the gate and the benchmark harness.
- `ISSUES.md` and `DISCUSSIONS.md` for where reports and questions go.
- `SECURITY.md` for what counts as a vulnerability in a compiler.
- `CODE_OF_CONDUCT.md` for how people are expected to treat each other.

## License

BSD 3-Clause. See `LICENSE`.
