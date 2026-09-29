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
   piece stays unimplemented and the failure is reported, not worked around.
2. **TCC-class speed, no compromise.** The workload that decides this is the V
   self-build: a few megabytes of generated C. Wall time and peak RSS both
   matter. Never claim a speed improvement from intuition; measure it.

## Commands

```sh
v -o vcc .                 # build
v test .                   # the suite
v fmt -w .                 # format before committing
./vcc -hh                  # the flag surface
./vcc -bench file.c -o out # per-phase timings
/usr/bin/time -v ./vcc -o /tmp/out src.c   # wall time and peak RSS
```

Building with V 0.5.2 and a source tree you did not just write: cap the compiler
so a parse loop cannot take the machine down.

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
| `ast/` | node types only. No printing, no emission. |
| `parser/` | tokens in, `ast` out. Never writes files. |
| `codegen/` | `ast` in, bytes out. Same input, same bytes, every run. |
| `extensions/` | reserved; empty until something real lands in it. |

Tests sit beside their module as `*_test.v`.

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

Comments, commit bodies, and markdown here are read by people. Plain sentences,
specific claims, no throat-clearing. Skip the phrasing that makes text read as
machine output: "this serves as", "it's not just X, it's Y", the three-item list
that exists to sound thorough, the bolded label at the start of every bullet.
Say what the code does and why it is that way.

## Commits

`area: what changed`, lowercase, no trailing period, body explaining why. Areas
in use: `tokenize`, `parser`, `ast`, `codegen`, `cli`, `tree`, `docs`. One
logical change per commit, each one building on its own.

## Do not

- Add a dependency to `v.mod` without raising it first. Empty dependencies is a
  feature here.
- Reformat or refactor files that your change does not touch.
- Weaken a test, a diagnostic, or an assertion to make a change land.
- Write a file into the user's tree to check your own work. Scratch goes in
  `.omh/` or the session scratch directory.
