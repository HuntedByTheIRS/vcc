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

## Build

Needs V 0.5.x on Linux x86-64.

```sh
v -o vcc .        # build the compiler
v test .          # lexer, parser, and codegen tests
v -o vcc . && ./vcc -bench seven.c -o seven   # per-phase timing
```

`-bench` prints microseconds per phase. It exists from the first commit because
the speed target is a hard requirement, and a number nobody prints is a number
nobody watches.

## Layout

| Path | Contents |
|---|---|
| `main.v` | entry point: command line in, output file out, pipeline in between |
| `cli/` | the tcc-compatible command line: flags, usage, version, phase timings |
| `tokenize/` | lexer: source text to tokens |
| `ast/` | node types the parser produces and the back end consumes |
| `parser/` | recursive descent parser for the supported subset |
| `codegen/` | ELF64 output for Linux x86-64 |
| `extensions/` | reserved for compiler extensions; empty for now |

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

## Read next

- `CONTRIBUTING.md` for the build, test, and commit workflow.
- `AGENTS.md` for coding-agent rules in this repository.
- `ROADMAP.md` for the milestones between the stub and a usable compiler.
- `ISSUES.md` and `DISCUSSIONS.md` for where reports and questions go.
- `SECURITY.md` for what counts as a vulnerability in a compiler.
- `CODE_OF_CONDUCT.md` for how people are expected to treat each other.

## License

BSD 3-Clause. See `LICENSE`.
