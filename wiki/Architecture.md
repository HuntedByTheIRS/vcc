# Architecture

vcc is a C compiler written in V, built to replace the tcc V vendors in
`thirdparty/tcc` on the same command line. It reads one source file per run
and writes one emitted image. The tree is a set of modules, each named after a
stage or a concern and each with a stated job. Two rules run through all of
them: the compiler is pure V, and the speed target is V's self-build.
[[Pure-V]] and [[Performance]] cover those two. `ARCHITECTURE.md` at the tree
root is the full statement of the design; this page is the short form and
follows its wording where the two overlap.

## The pipeline

`main.v` reads the command line and runs the stages in one order, one source
file per run. Its own comment says the file is only the wiring between the
modules named after the stages. The order is:

1. `cli.parse(os.args[1..])` produces a `cli.Options`. A flag the compiler
   does not implement is recorded on the options and carried, never refused,
   because V passes flags for work it expects done and a compiler that errors
   on `-bt25` fails a build it was meant to serve.
2. `preprocess.preprocess(source, path, opts)`. The preprocessor owns the
   lexer, because its unit of work is a file: one file is lexed, an `#include`
   pushes another, and the tokens carry the file, line and column of the text
   they came from. The result is one token stream with directives consumed and
   macros expanded.
3. `standard.pedantic_messages(processed.tokens,...)`. The dialect check reads
   the whole stream, the only point where the program is in one list. It
   reports the constructs the selected mode does not allow and refuses
   nothing; only a message the command-line flags promoted stops a compile.
4. `-M` without `-MD`, `-dM` and `-E` answer here and stop, under a policy
   with no promotion in it, because a run that only asks what the file is made
   of has no compile for a promotion to stop.
5. `parser.parse_for(processed.tokens, parser_target(opts.target))` parses
   into an `ast.TranslationUnit`. The target is a parameter and not a lookup,
   because the width of a pointer and of an int, the offset a member sits at
   and the class an object of an aggregate type travels in are all the
   target's.
6. `optimizer.optimize(parsed.unit, opts.optimization)` returns a tree.
7. `printer.render(optimized)` prints it when `-print-ast` was given, and the
   run stops there with nothing written.
8. `codegen.emit(optimized,...)` returns a `codegen.Result` that carries the
   bytes, the target it emitted for, and the back end's diagnostics.
9. `write_object` or `write_image` writes the bytes, and `-run` executes the
   file and leaves with its exit status.

`main.v` is the only place these functions are called. `-external-linker=NAME`
with a link is the one branch that leaves the pipeline early, taken before the
single-input refusals because it is the path those refusals exist to lift.
`parser.parse(tokens)` is the second parser entry point, which calls
`parser.parse_for(tokens, backend.host())`; the tests use it and the driver
does not.

## One module per job

Each stage is a module with a stated job, and the jobs are kept apart on
purpose. `ast/` is node types only and imports `types` and nothing else, so
nothing that renders a tree belongs in it. `parser/` takes tokens in and gives
an `ast` out, and never writes files. `printer/` takes an `ast` in and gives
text out, and `-print-ast` is its only caller. `optimizer/` is `ast` in and
`ast` out: a pass is a row in a table with the level that turns it on, so an
optimization is a function beside the table and not a branch in the emitter,
and `codegen/` never asks it anything. `codegen/` takes an `ast` in and gives
an emitted unit out, asks `backend/` for every machine fact, and never learns
about a target itself; the same input produces the same bytes every run.
`image/` is that emitted unit: machine code, the data it reads, and the
references between them.

Imports run one way. `parser` does not know `codegen`, `codegen` never asks
`optimizer` anything, and `ast` stays node types only. A new target, a new
optimization or a new dialect construct is a row in a table plus a function
beside it, not a branch in a caller.

## The directory map

| Path | Job |
|---|---|
| `main.v` | the driver: command line in, output file out, the pipeline in between |
| `cli/` | flags, usage, version, input classification, the external-linker policy. Knows nothing about C grammar. |
| `tokenize/` | source text to tokens; defines `Token` and the `Diagnostic` struct every stage produces |
| `diagnostics/` | what a diagnostic is: class, severity, `flag_classes`, and `render`, the one place a diagnostic becomes text |
| `standard/` | the `-std=` modes and the dialect feature table |
| `preprocess/` | the C preprocessor: its file stack, `macro.v`, `expand.v`, `expr.v` the `#if` grammar, `builtin.v` the predefined macros |
| `types/` | the type model, the object representation, the symbol table |
| `ast/` | node types only |
| `parser/` | tokens in, `ast` out |
| `optimizer/` | `ast` in, `ast` out: the `-O` levels and the builtin table |
| `printer/` | `ast` in, text out: what `-print-ast` prints |
| `backend/` | target description: `arch/` the machine, `os/` the system, `abi/` the calling convention, `backend.v` composes them |
| `codegen/` | `ast` in, an emitted unit out |
| `image/` | the emitted unit: machine code, the data it reads, the references between them |
| `extensions/` | the `-fvcc-exts=` interface, built on the rows in `standard/features.v` |
| `linking/` | empty; the in-house linker is not written |
| `tools/` | gate, benchmark and corpus scripts; not part of the compiler |
| `compliance/`, `regression/`, `goldens/` | C the compiler is handed, not C it is built from |

## The target description

`backend/backend.v` composes a `Machine` and a `System` into a `Target`. The
`Machine` holds the machine's own data: the general register file, the
floating-point file with its own argument positions, the word size, the ELF
machine number, the register a result is left in, and the instruction
encoders. The `System` holds the kernel entry points and the registers their
arguments arrive in, the dynamic loader, where a `-l` name is looked for, the
page size and load base, and the C library every image names. `targets()`
returns one composition, `x86_64_linux()`, and `lookup` finds it by the name
`arch-os`. `host()` answers the composition this binary was built for, an
empty `-target` resolves to the host, and an unknown name is refused with the
list of names that exist.

The third axis, `backend/abi/`, is not a field of `Target`. `abi.class_of`
takes a `types.Representation` and a type and answers which register file
carries an object of an aggregate type, split into eightbytes. It takes the
representation as a parameter because the answer is a fact about the machine,
and both the parser and `codegen.emit` reach it through
`types.from_target(target)`. So the target value holds the machine and the
system; the ABI is a function called with the target's data, not a third field
composed into it.

`codegen/` imports `backend`, `backend.abi`, `backend.os.elf` and
`backend.os.linux`. Machine facts come through the `Target`. The container is
applied by `backend/os/elf/`: `elf.object(code, target)` and
`elf.executable(code, target)` wrap the emitted unit. Library names are
resolved by `backend/os/linux/`: `linux.search_dirs`,
`linux.resolve_libraries` and `linux.unresolved_imports`. Those are the only
two places codegen leaves the `Target`. A new machine or a new system is a
module of its own under `backend/arch` or `backend/os` plus one line in the
composition, because a V module is a directory and two machines in one module
would collide on every name they share. A new calling convention is a module
under `backend/abi/`, and `codegen/` never learns about any of it.

## Diagnostics and dialects

`diagnostics/diagnostics.v` has a `Class` (cpp, pedantic, required,
discarded_qualifiers), a `Severity` (silent, warning, error), `flag_classes`,
which maps a `-W` spelling to the class it names, and `render`, the one
function that turns a diagnostic into a line of text. The `Diagnostic` struct
itself stays in `tokenize/`, where every stage finds it, because the lexer is
what gives a byte offset a line and a column. `main.v` has the small
`report()` that applies the command-line policy to a list of diagnostics and
counts the errors.

`standard/mode.v` defines `Mode`, one value per `-std=` language, plus `.none`
(no `-std`) and `.other` (a spelling this compiler does not implement).
`from_spelling` is total: every spelling gets a mode and none is an error.
`standard/features.v` is the dialect table in two parts: `Feature` and the
`features` const, one row per construct. `extension_names` reads the extension
column off the rows and `pedantic_messages` is the check.
`extensions/extensions.v` keeps no list of its own; it calls
`standard.extension_names()` and reads the same rows. [[C-Support]] has the
conformance side.

## Invariants to keep

One module per directory. Imports run one way. A new target, a new
optimization or a new dialect construct is a row in a table plus a function
beside it, not a branch in a caller. A construct outside the subset exits
non-zero with a diagnostic that names the construct and its location; writing
an empty output file that fails later is a bug. A speed claim is a number from
`tools/bench.vsh`, printed with the command that produced it. Tests sit beside
their module as `*_test.v`, `v test .` runs the suite, and `tools/gate.vsh` is
the same set of checks a pull request passes, which [[The-Gate]] describes.
The definition of done is the four-build bootstrap chain, which [[Interop]]
has.
