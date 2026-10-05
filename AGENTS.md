# AGENTS.md

Instructions for coding agents working in this repository. They are not
different rules from the ones a person follows, just written where a tool will
read them. `CONTRIBUTING.md` has the human-facing version.

## What this repository is

vcc is a C compiler written in V. It exists to replace the TCC binary V vendors
in `thirdparty/tcc`, on the same command line and at the same speed. Today the
tree holds a stub: a lexer, a parser for a small subset, and an ELF64 writer for
Linux x86-64.

## The two constraints

1. **Pure V.** No C source, no `#include`, no `cc` invocation, no C library
   binding added to make something work. If V cannot express a piece yet, that
   piece stays unimplemented and the failure is reported, not worked around. The
   compiler and the linker stay pure V. A test directory is the one place C
   lives, and there it is input to the compiler rather than part of it:
   `compliance/` is the C99 conformance corpus, `regression/` one program per
   bug that must not come back, `goldens/` the programs whose output is compared
   against a recording. That C is what the compiler is handed, so it does not
   break the rule, and a C source anywhere else is a failure. A `.v` file inside
   a test directory is still this compiler's source, so `#include`, `#flag` and
   `C.` stay out of it there too. One exception to the linking rule, named and
   off by default. `-external-linker=NAME` hands the link to a linker the
   system already has, for the inputs this compiler
   cannot consume yet: a relocatable object, an archive. It exists so that
   linking behaviour is available before an in-house linker is written, not so
   that a missing piece can be papered over. `NAME` must not be a C compiler:
   `cc`, `gcc`, `clang`, `c++` and `tcc` are refused by name, because a C
   compiler finishing C compilation is the one thing this rule is for. With
   the flag unset every refusal stands exactly as it does today, and the
   in-house path is unchanged when it is set. A tool that is missing or exits
   non-zero is reported rather than silently falling back to the other path.
   The paths it needs (the system's start files, its dynamic loader, its
   library directories) come from `backend/os/linux/`, so there stays one
   source for where those live.
2. **TCC-class speed, which is not open to compromise.** The workload that
   decides this is the V self-build: a few megabytes of generated C. Wall time
   and peak RSS both matter. Never claim a speed improvement from intuition;
   measure it.

## Commands

```sh
v -o vcc .                 # build
v test .                   # the suite
v run tools/gate.vsh       # format, pure-V rule, build, tests, doc links
v run tools/build.vsh      # the front door: build, gate, corpora, bench, image, version
v run tools/bench.vsh      # wall time and peak memory, tcc alongside
v fmt -w .                 # format before committing
./vcc -hh                  # the flag surface
./vcc -bench file.c -o out # per-phase timings
/usr/bin/time -v ./vcc -o /tmp/out src.c   # wall time and peak RSS
```

`tools/build.vsh` is the front door over these commands: it runs the same
checks plus the corpora, the benchmark, the image and the version report in one
run. `tools/gate.vsh` is the same set of checks a pull request has to pass, and CI
runs it too (`.github/workflows/ci.yml`), so run it before claiming a change is
done rather than after CI says otherwise. Use `-nocache`
on probe builds, and prefer the gate's build over a binary from an earlier edit.

Building with V and a source tree you did not just write: cap the compiler so a
parse loop cannot take the machine down. Use V from master or from a commit at
or after the one `ci.yml` pins; the 0.5.2 release cannot compile this tree
(README, Build).

```sh
systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0 v test .
```

An unclosed array literal still loops the V 0.5.2 parser until memory runs out,
so the cap turns a frozen desktop into a clean OOM with the peak reported.

## Where things go

| Path | Rule |
|---|---|
| `cli/` | flags, usage, version, timings. Knows nothing about C grammar. |
| `tokenize/` | source text in, tokens out. No parser knowledge. |
| `diagnostics/` | what a diagnostic is: its class, the severity the command-line flags give that class, and the one place a diagnostic becomes text. The `Diagnostic` struct itself stays in `tokenize/`, where every stage finds it. |
| `standard/` | the dialects: the `-std=` spellings, the mode each one names, and the feature table the dialect check reads. A row is a construct, the standard it is part of, and what this compiler does with it. Knows no grammar. |
| `ast/` | node types only. No printing, no emission. |
| `parser/` | tokens in, `ast` out. Never writes files. |
| `optimizer/` | `ast` in, `ast` out. `-O` levels and the builtin table. A pass is a row in a table with the level that turns it on, so adding an optimization is a function beside the table and not a branch in the emitter. `codegen/` never asks it anything. |
| `printer/` | `ast` in, text out. `-print-ast` is its only caller. `ast/` stays node types only, so nothing that renders a tree belongs in it. |
| `backend/` | target description in three dimensions. `arch/` is the machine: registers, encodings, argument positions. `os/` is the system: syscalls, their numbers, loader constants, the executable container. `abi/` is what a value travels in: whether a register carries an object or its address, and which register carries each eightbyte of it. `backend.v` composes one of each into a `Target`, which is all `codegen/` sees. A new machine, a new system or a new calling convention is a module of its own, and `codegen/` never learns about it; `backend.v` is the one place a target is composed. |
| `image/` | the emitted unit: machine code, the data it reads, and the references between them. `codegen/` builds one, and the system in `backend/os/` decides what wrapping it gets. |
| `codegen/` | `ast` in, an emitted unit out. Same input, same bytes, every run. Asks `backend/` for every machine fact. |
| `tools/` | gate and benchmark scripts. Not part of the compiler and not imported by it. |
| `compliance/`, `regression/`, `goldens/` | C the compiler is handed, not C it is built from, so these are the only directories where C source is allowed. `compliance/` is the C99 conformance corpus, `regression/` one program per bug that must not come back, `goldens/` the programs whose output is compared against a recording. Compiled by `tools/compliance.vsh` and `tools/regress.vsh`. |
| `extensions/` | the vendor extensions the `-fvcc-exts=` family names. The names are read off the rows in `standard/features.v` rather than kept in a list here, and naming one turns the construct its row describes on for the selected mode: `-fvcc-exts=typeof` under `-std=c99` stops the mode forbidding `typeof`. |

Tests sit beside their module as `*_test.v`.

## What this is working toward

The bootstrap chain, which is the definition of done: V built by the vendored
tcc builds vcc, vcc builds V, and the V that vcc built builds vcc again. Steps 3
and 4 are in the README with the commands. Nothing in this tree is finished until
step 3 passes V's own test suite, so a change is judged by whether it moves the
compiler toward compiling V's generated C.

## Interop, which is easy to get wrong

V classifies a C compiler by the real path of the binary (`tcc`/`tinyc` in the
name wins immediately) and otherwise by its `--version` output, then caches
artifacts against that identity. Read the authority rather than this file:

```sh
cd /path/to/v
grep -n "effective_c_compiler_name" -A 45 vlib/v/driver/driver.v
grep -n "ccompiler_can_assemble" -A 25 vlib/v/pref/pref.v
grep -n "ccompiler\b" vlib/v/driver/driver.v | head
```

A change to `--version`, or to how a flag is accepted, changes what V thinks
this binary is. Say which V source line justifies the change in the commit body.

## Verification

- Run the artifact, do not infer it. A codegen change is verified by running the
  binary it produced and reading the exit status or output.
- Read the output file back when the write left the process: check the file
  exists, is executable when it should be, and starts with the bytes you meant.
- Keep a diagnostic honest. An unimplemented construct exits non-zero with the
  construct and its location; a silent empty output file is the worst outcome
  available and is treated as a bug.
- Before saying a test failed, check whether it failed before your change. The
  V toolchain caches aggressively: `-nocache` on probe runs, and a binary built
  before your edit reports the previous source's problems.
- Read the tree instead of guessing at it: `./vcc -print-ast file.c` prints what
  the emitter would be handed, which is faster than adding a print statement to
  a walk and taking it out again.
- Long input is a test case. The one crash this tree has had was a fold that
  recursed once per term in an operator chain, which took the stack out at about
  three thousand terms; `tools/bench.vsh --terms 20000` is what found it. When
  you add a phase, run it on input that is large rather than only on input that
  is interesting, and let a deep structure count against a limit you chose
  instead of against the stack.

## Agent working state

Anything written for one agent run lives in `.omh/`, which is git-ignored: plans,
probe scripts, capture generators, golden files on the agent side, and scratch
notes. None of it is committed, and no harness, lane checklist, or golden
generator written to check a single change belongs in this tree. A repository
keeps the tests its maintainers will run.

`.gitignore` carries the same rule for the coding tools that drop a directory in
a working tree: `.claude/`, `.codex/`, `.opencode/`, `.omo/`, `.cursor/`,
`.gemini/`, `.continue/`, `.aider*` and the rest, one line each. None of them is
project content. A new tool gets a line in that list, not a commit.

## Prose

Comments, commit bodies, pull request text, and the markdown here are read by
people. Write them the way you would say them out loud: plain sentences, specific
claims. This binds text an agent writes as much as text a person writes, because
these shapes are recognisable and every one of them costs the reader time before
it costs anything else.

- "Serves as", "stands as", "marks a pivotal moment", and the rest of the
  vocabulary that inflates what the code does into what it means.
- "It's not just X, it's Y", and the clipped negation hung off the end of a
  sentence ("no guessing"). Write the clause.
- The three-item list assembled to sound thorough, and the synonym carousel where
  one thing is first a catalyst, then a partner, then a foundation.
- A bolded label at the start of every bullet. That is a table pretending to be
  prose.
- Signposting before the point: "let's look at", "here's what you need to know",
  "in this section we will".
- Em dashes for punch. A comma, a colon, or a full stop is usually what was meant.
- Upbeat closes and unasked-for reassurance: "the future looks bright", "and
  that's okay". Stop when the point is made.
- Hedging that hides a decision. If something is uncertain, name what would settle
  it rather than stacking qualifiers.

Prefer `is`, `has`, and `does` to "serves as", "features", and "stands as". And
when the claim is a measurement, print the number and the command that produced
it, because an adjective is not evidence.

## Commits

`area: what changed`, lowercase, no trailing period, body explaining why. Areas
in use: `tokenize`, `parser`, `ast`, `optimizer`, `printer`, `backend`,
`image`, `codegen`, `cli`, `tools`, `github`, `tree`, `docs`. One logical change
per commit, each one building on its own.

## Do not

- Add a dependency to `v.mod` without raising it first. Empty dependencies is a
  feature here.
- Reformat or refactor files that your change does not touch.
- Weaken a test, a diagnostic, or an assertion to make a change land.
- Write a file into the user's tree to check your own work. Scratch goes in
  `.omh/` or the session scratch directory.
