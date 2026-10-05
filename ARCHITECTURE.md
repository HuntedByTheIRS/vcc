# Architecture

vcc is a C compiler written in V. It exists to replace the tcc that V vendors in
`thirdparty/tcc`, on the same command line and at the same speed, so the C
compiler in V's build is a program V can build, read and patch in V. Two
constraints run through the tree. The compiler is pure V: no C source, no
delegation to a C compiler or a C library, and a piece V cannot express yet
stays unimplemented and is refused with a diagnostic naming the construct. And
the speed target is the V self-build, a few megabytes of generated C per run, so
a change is judged by whether it moves the compiler toward compiling V's
generated C and does not make it slower.

The size of the tree is counted by `v run tools/lines.vsh`, which is what the
lines badge in README.md reads: the `.v` files the tree tracks that are not
tests, with `tools/` out and `linking/` in, so the linker counts itself the day
it is written. The total is not repeated here, because a figure copied into prose
goes stale without saying so, and the one that stood here had been counted by a
walk that reached into the agent working state and counted its copies of the
sources as the compiler. The module table below is a `wc -l` per directory, taken
when it was written.

## The pipeline

`main.v` reads the command line and runs the stages in one order, one source file
per run. Its own comment says the file is only the wiring between the modules
named after the stages. The order it runs is:

1. `cli.parse(os.args[1..])` produces a `cli.Options`. A flag the compiler does
   not implement is recorded on the options and carried, never refused, because
   V passes flags for work it expects done and a compiler that errors on `-bt25`
   fails a build it was meant to serve.
2. `preprocess.preprocess(source, path, opts)` (main.v:137). The preprocessor
   owns the lexer, because its unit of work is a file: one file is lexed, an
   `#include` pushes another, and the tokens carry the file, line and column of
   the text they came from. The result is one token stream with directives
   consumed and macros expanded.
3. `standard.pedantic_messages(processed.tokens, ...)` (main.v:185). The dialect
   check reads the whole stream, which is the only point where the program is in
   one list. It reports the constructs the selected mode does not allow and
   refuses nothing; only a message the command-line flags promoted stops a
   compile.
4. `-M` without `-MD`, `-dM` and `-E` answer here and stop. A run that only asks
   what the file is made of has no compile for a promotion to stop, so it is
   reported under a policy with no promotion in it.
5. `parser.parse_for(processed.tokens, parser_target(opts.target))` (main.v:218)
   parses into an `ast.TranslationUnit`. The target is a parameter and not a
   lookup, because the width of a pointer and of an int, the offset a member sits
   at and the class an object of an aggregate type travels in are all the
   target's.
6. `optimizer.optimize(parsed.unit, opts.optimization)` (main.v:227) returns a
   tree.
7. `printer.render(optimized)` (main.v:235) prints it when `-print-ast` was
   given, and the run stops there with nothing written.
8. `codegen.emit(optimized, ...)` (main.v:239) returns a `codegen.Result` that
   carries the bytes, the target it emitted for, and the back end's diagnostics.
9. `write_object` or `write_image` writes the bytes, and `-run` executes the file
   and leaves with its exit status.

`main.v` is the only place these functions are called. `-external-linker=NAME`
with a link is the one branch that leaves the pipeline early, taken before the
single-input refusals because it is the path those refusals exist to lift.

There are two parser entry points. `parser.parse(tokens)` parses for the host;
`parser.parse_for(tokens, target)` parses for a named target. The first calls the
second with `backend.host()`, and the tests use it; the driver uses the second.

## Modules

| Path | Lines (files) | Job |
|---|---|---|
| `main.v` | 964 | the driver: command line in, output file out |
| `cli/` | 910 (3) | flags, usage, version, input classification, the external-linker policy |
| `tokenize/` | 925 (2) | source text to tokens; defines `Token` and `Diagnostic` |
| `preprocess/` | 2,773 (5) | the C preprocessor |
| `standard/` | 881 (2) | the `-std=` modes and the dialect feature table |
| `types/` | 3,106 (7) | the type model, the object representation, the symbol table |
| `parser/` | 14,364 (7) | tokens in, `ast` out |
| `ast/` | 893 | node types only |
| `optimizer/` | 603 | `ast` in, `ast` out |
| `printer/` | 304 | `ast` in, text out |
| `codegen/` | 13,026 (3) | `ast` in, an emitted unit out |
| `image/` | 195 | the emitted unit: code, data, references |
| `backend/` | 7,238 (8) | a target in three dimensions |
| `diagnostics/` | 252 | what a diagnostic is: class, severity, one renderer |
| `extensions/` | 152 | the `-fvcc-exts=` interface |
| `linking/` | 0 | empty; the linker is not written |

`tokenize/` owns the `Diagnostic` struct (`tokenize/token.v:60`), which every
stage produces, and `errors()` beside it, which is the list of diagnostics that
stop a compile. The lexer (`lexer.v`, 824 lines) gives a byte offset a line and a
column, which is why the struct lives here and not where the classes do.

`preprocess/` is five files split by job: `preprocess.v` (1,222 lines) is the
processor and its file stack, `macro.v` is a remembered `#define`, `expand.v`
does macro expansion, `expr.v` is the `#if` expression grammar, and `builtin.v`
holds the predefined macros, including `identity_defines` and `standard_defines`.
It imports `standard`, because the mode decides whether a trigraph is replaced
before a token exists.

`types/` is the type model and the symbol table. `types.v` is the value model,
`object.v` asks a target description for sizes, alignments and member offsets,
`scope.v` is the symbol table with C's two namespaces (ordinary identifiers and
tags), and `specifiers.v`, `convert.v` and `literals.v` cover what their names
say. Nothing here holds a size or an alignment: those are machine facts, and
`from_target(target)` is how the model gets them. `measured/measured.v` is a test
fixture of measured layouts.

`parser/` is split by construct: `parser.v` (3,427 lines) is the driver of the
parse and the expression grammar, and `declarations.v` (5,928), `statements.v`
(2,310), `literals.v`, `builtins.v`, `compound.v` and `attributes.v` carry the
rest. `codegen/` is `codegen.v` (12,123 lines) plus `long_double.v` and
`complex_long_double.v` for the two float formats the general emitter does not
handle inline.

`ast/` imports `types` and nothing else. Its doc states the rule: a node carries
both the resolved type clause and the spelling the declaration was written with,
and an unresolved clause carries the zero value of `types.Type`, whose kind is
`.unknown`, which is not a claim that the type is void.

`linking/` is the in-house linker: `symbols/` resolves names across units,
`place/` lays the image out, `reloc/` fills the references in, `output/` wraps
it, and `object/` and `archive/` read a relocatable file and an `ar` archive the
command line names. `-external-linker=NAME` is the fallback for an input this
linker cannot consume, and an object carrying a section or a relocation it does
not model is refused by name rather than placed at a guessed address.

## The target description

`backend/backend.v` composes a `Machine` and a `System` into a `Target`. The
`Machine` holds the machine's own data: the general register file, the
floating-point file with its own argument positions, the word size, the ELF
machine number, the register a result is left in, and the instruction encoders.
The `System` holds the kernel entry points and the registers their arguments
arrive in, the dynamic loader, where a `-l` name is looked for, the page size and
load base, and the C library every image names.

`targets()` returns one composition, `x86_64_linux()`, and `lookup` finds it by
the name `arch-os`. `host()` answers the composition this binary was built for,
an empty `-target` resolves to the host, and an unknown name is refused with the
list of names that exist. A new machine or a new system is a module of its own
under `backend/arch` or `backend/os` plus one line in the composition, because a
V module is a directory and two machines in one module would collide on every
name they share.

The third axis, `backend/abi/`, is not a field of `Target`. `abi.class_of` takes
a `types.Representation` and a type and answers which register file carries an
object of an aggregate type, split into eightbytes. It takes the representation
as a parameter because the answer is a fact about the machine, and both the
parser and `codegen.emit` reach it through `types.from_target(target)`. So the
target value holds the machine and the system; the ABI is a function called with
the target's data, not a third field composed into it.

`codegen/` imports `backend`, `backend.abi`, `backend.os.elf` and
`backend.os.linux`. Machine facts (registers, encodings, relocations, the
representation) come through the `Target`. The container is applied by
`backend/os/elf/`: `elf.object(code, target)` and `elf.executable(code, target)`
wrap the emitted unit, and `elf.v` lays the image out in one fixed pass because
every offset is the size of what came before. Library names are resolved by
`backend/os/linux/`: `linux.search_dirs`, `linux.resolve_libraries` and
`linux.unresolved_imports`. Those are the only two places codegen leaves the
`Target`.

## Diagnostics

`diagnostics/diagnostics.v` has a `Class` (cpp, pedantic, required,
discarded_qualifiers), a `Severity` (silent, warning, error), `flag_classes`,
which maps a `-W` spelling to the class it names, and `render`, the one function
that turns a diagnostic into a line of text. `main.v` has the small `report()`
that applies the command-line policy to a list of diagnostics and counts the
errors. A class the flags do not name is recorded on the command line, not
refused.

## Dialects and extensions

`standard/mode.v` defines `Mode`, one value per `-std=` language, plus `.none`
(no `-std`) and `.other` (a spelling this compiler does not implement).
`from_spelling` is total: every spelling gets a mode and none is an error.
`standard/features.v` is the dialect table in two parts: `Feature` (spellings,
`since`, `gnu`, `reserved`, `invalid`, the extension name, the pedantic phrase,
and a status) and the `features` const, one row per construct. `extension_names`
reads the extension column off the rows and `pedantic_messages` is the check.
`extensions/extensions.v` keeps no list of its own; it calls
`standard.extension_names()` and reads the same rows.

## What is verified how

Tests sit beside their module as `*_test.v`. There are 37 of them, including
three at the tree root: `pipeline_test.v`, which drives the same functions
`main()` drives, writes an image, runs it and checks the exit status;
`query_test.v` for the `-print-*` answers; and `verbose_test.v`. `v test .` runs
the suite.

`tools/gate.vsh` is the same set of checks a pull request passes, and CI runs it.
It reports six steps: formatting (`v fmt -verify .`), the pure-V rule (C only in
the test directories, no `#include`, `#flag` or `C.` interop in the compiler), a
build, the test suite, the links between root markdown files, and the workflows.

C lives in the three test directories and nowhere else, and all of it is C the
compiler is handed rather than C the compiler is built from. `compliance/` holds
one program per C99 answer, `regression/` one per behaviour that was once broken,
and `goldens/` one per program whose printed output is recorded beside it.
`tools/compliance.vsh` compiles and runs every file under `compliance/` and the
12,340-line `monolithic.c` with it, `tools/regress.vsh` does the same for the
other two directories, and `tools/bench.vsh` measures wall time and peak memory
against the vendored tcc, which is where a speed claim gets its number.

## The bootstrap chain

The definition of done is four builds, in `README.md`:

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 is the one that cannot be faked: vcc has to compile the C V emits for
itself, link it, and produce a V that passes V's own suite. Step 4 has to produce
a vcc that behaves like the one it came from. Neither passes today; the tree is
past the stub and compiles a large slice of Linux x86-64 C, but the in-house
linker and `-no-ast` do not exist and the subset is smaller than GCC's.

## Invariants to keep

One module per directory. Imports run one way: `parser` does not know `codegen`,
`codegen` never asks `optimizer` anything, and `ast` stays node types only, which
is why rendering a tree is `printer/` and not a method on a node. A new target, a
new optimization, or a new dialect construct is a row in a table plus a function
beside it, not a branch in a caller. A construct outside the subset exits
non-zero with a diagnostic that names the construct and its location; writing an
empty output file that fails later is a bug. And a speed claim is a number from
`tools/bench.vsh`, printed with the command that produced it.
