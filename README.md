# vcc

vcc is a C compiler written in V. It has one job: replace the TCC binary that V
vendors in `thirdparty/tcc`, on the same command line, doing the same work.

Two constraints come before everything else.

**Pure V.** No C source in the compiler, no corner of the pipeline delegated to a
C compiler, no vendored C library. If a piece cannot be written in V yet, it
stays unimplemented rather than getting a C shortcut.

**Fast.** Near TCC's speed or better, with no compromise. Compiling the C that V
generates for itself is the benchmark that matters: a few megabytes of C per
build, and vcc has to get through it in the time the bundled tcc does, at
comparable peak memory. A compiler that is correct but slower is not a
replacement, and it will not be merged in that state.

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

Early, and honest about it. The tree holds a stub that lexes C, parses a very
small subset, and writes a working Linux x86-64 executable for it.

```sh
v -o vcc .
printf 'int main() { return 7; }\n' > seven.c
./vcc seven.c -o seven
./seven; echo $?
```

That prints `7`. It is close to the full extent of what the compiler does today.
Anything outside the subset listed below exits non-zero with a diagnostic that
names the construct and its source location, instead of writing an output file
that would fail later.

It accepts the flags V passes to a C compiler (`-std=`, `-w`, `-fwrapv`, `-g`,
`-B`, `-I`, `-L`, `-l`, `-Wl,` passthroughs, `-bt25`, `-x`, `@listfile`, `-`),
plus `--version`, `-v`, `-h`, `-hh`, `-run`, `-E`, `-c`, `-o`, `-bench`. See
`vcc -hh` for the annotated list.

The parser currently handles function definitions returning `int`, `return`
statements, and integer constant expressions with `+ - * / %` and parentheses.
The back end has no instruction selection yet: it emits an `exit` syscall with
the folded value of `main`'s return, so `int main() { return 7; }` works and
`int main() { return x; }` does not.

Not implemented, in rough order of how much of the tree depends on it: the
preprocessor, declarations and statements beyond a function returning a constant
int, any type other than `int`, expressions that are not constant, object files,
relocatable output, linking against libc, and a real x86-64 back end. `ROADMAP.md`
maps the order.

The speed constraint is measured, not assumed, and the current numbers are not
close. On a workload both compilers accept (`tools/bench.vsh --terms 20000`, a
constant chain and nothing else), vcc takes about 8x tcc's wall time and 4x its
peak memory; at 100000 terms it is about 18x. Most of that gap is allocation per
token and per AST node, which is a design problem rather than a constant factor.

## Build

Needs V 0.5.x on Linux x86-64.

```sh
v -o vcc .        # build the compiler
v test .          # lexer, parser, and codegen tests
v run tools/gate.vsh                          # everything a pull request has to pass
v run tools/bench.vsh                         # wall time and peak memory, tcc alongside
v -o vcc . && ./vcc -bench seven.c -o seven   # per-phase timing
```

`-bench` prints microseconds per phase. It exists from the first commit because
the speed target is a hard requirement, and a number nobody prints is a number
nobody watches. `tools/` holds the gate and the benchmark harness; `tools/README.md`
says what each one checks.


## Layout

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | the tcc-compatible command line: flags, usage, version, phase timings |
| `tokenize/` | lexer: source text to tokens |
| `ast/` | node types the parser produces and the back end consumes |
| `parser/` | recursive descent parser for the supported subset |
| `backend/` | target description as tables: registers, opcodes, syscalls, encodings |
| `codegen/` | translation unit to bytes: constant folding and the ELF64 container |
| `tools/` | gate and benchmark scripts; not part of the compiler |
| `extensions/` | reserved for compiler extensions; empty for now |

A target is data rather than a directory of hand-written emission: `backend/`
holds the shapes (`Target`, `Register`, `Syscall`, `Encoding`) and one file per
architecture supplies the tables. Adding a target means adding a file like
`backend/x86_64.v`, not editing the emitter.

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
