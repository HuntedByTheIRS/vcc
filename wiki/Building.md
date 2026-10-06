# Building

vcc is a compiler written in V, and V builds it. On Linux x86-64 the build is
a short list of commands: build V once, build the compiler, run the suite, and
run the gate.

## Which V builds the tree

The tree needs V built from source on Linux x86-64, at a commit that accepts
it.

The 0.5.2 release cannot build this tree. Its checker rejects a `for {}` whose
every path returns, which `parser/parser.v` uses, so the build stops in the
parser. Every commit after 0.5.2 accepts the shape. CI pins the commit it
builds and tests with in a `V_COMMIT` variable in
[.github/workflows/ci.yml](https://github.com/HuntedByTheIRS/vcc/blob/main/.github/workflows/ci.yml),
and the pin moves only after the tree is re-verified against the commit it
moves to.

The pin also has a floor. `parser/literals.v` reads a long double's literal
through a u128, and upstream V gained u128 and i128 on 2026-10-01. A V older
than that fails the build with `error: unknown function: u128`, and every test
file fails behind it. The comment on `V_COMMIT` records both facts.

## Building and running

```sh
git clone https://github.com/vlang/v && cd v && make   # once
cd /path/to/vcc
v -o vcc .                 # build the compiler
v test .                   # the suite
v run tools/gate.vsh       # format, pure-V rule, build, tests, doc links, workflows
v run tools/bench.vsh      # wall time and peak memory, tcc alongside
./vcc -bench file.c -o out # per-phase timings
```

`v -o vcc .` writes the compiler to `./vcc`. `v test .` runs the suite.
[[The-Gate]] describes the gate, the suite and the corpora.
`v run tools/build.vsh` is the front door over the same commands when one run
is wanted.

## A first program

```sh
printf '#include <stdio.h>\nint main(void) { puts("Hello, world!"); return 0; }\n' > hello.c
./vcc hello.c -o hello && ./hello
./vcc -run hello.c        # same, without leaving an image behind
```

`-run` compiles the program, runs it, and exits with the program's own exit
status. It writes no image, so the tree keeps no file behind.

## Reading a parse with -print-ast

`-print-ast` parses the input, prints the tree the emitter would be given, and
stops without writing anything. A parse or an optimization is read from that
output rather than guessed at.

## Flags beyond the V contract

V passes a C compiler a fixed flag set, and vcc accepts it; [[Interop]] covers
that contract. Beyond the set, vcc accepts its own flags:

`--version`, `-v`, `-vv`, `-h`, `-hh`, `-E`, `-c`, `-o`, `-run`, `-bench`,
`-print-ast`, the `-O0` through `-O3` and `-Os` levels, `-fno-builtin` and
`-fno-builtin-NAME`, `-fPIC`/`-fpic`, `-nostdinc`, `-undef`, `-include`,
`-imacros`, the dependency flags `-M`/`-MM`/`-MD`/`-MMD`/`-MF`/`-MT`/`-MQ`,
`-dM`, `-Wclass`/`-Wno-class`, `-femulation=NAME` (define the identity macros
of gcc, clang or tcc instead of vcc's own), `-external-linker=NAME`,
`-shared`, `-static`, and the gcc `-print-` family. `./vcc -hh` prints the
annotated surface.

`-O` today turns on one optimizer pass: a call whose value the compiler knows
(`abs`, `labs`, `llabs`) with a literal argument folds to that value. `-O0`
makes the call and `-O2` folds it. `-fno-builtin` takes the fold back.

`-external-linker=NAME` hands the final link to a linker already on the
system, for the inputs this compiler cannot consume yet. It refuses `cc`,
`gcc`, `clang`, `c++` and `tcc` by name, because a C compiler finishing C
compilation is the one thing the pure-V rule exists to prevent. It is the
single exception to that rule, and it is off by default. [[Pure-V]] covers the
rule.

A flag the compiler does not implement is recorded and never refused, because
a compiler that errors on `-bt25` fails a build it was supposed to serve.

## Directory layout

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
| `extensions/` | the `-fvcc-exts=` interface, built on the extension rows in `standard/` |
| `tools/` | gate, benchmark and corpus scripts; not part of the compiler |
| `compliance/` | the conformance corpus, one directory per standard: one C program per standard-library check, run by `tools/compliance.vsh` |
| `regression/` | one C program per bug that must not come back, run by `tools/regress.vsh` |
| `goldens/` | C programs whose recorded output is compared byte for byte, so a change in behavior shows as a diff |

The C in `compliance/`, `regression/` and `goldens/` is the only C in the
tree, and it is input the compiler is handed rather than part of the compiler
itself.

A new machine, a new system, or a new calling convention is a module of its
own under `backend/`, and `codegen/` never learns about it. [[Architecture]]
describes the pipeline these modules form.

## See also

- [[The-Gate]], for the checks a change has to pass.
- [[Pure-V]], for the rule and where C may appear.
- [[Interop]], for what V asks of a C compiler.
