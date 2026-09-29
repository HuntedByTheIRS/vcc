# Contributing to vcc

Thanks for wanting to help. This file covers how to build the tree, what a
change has to bring with it, and how the project writes things down. Two rules
sit above everything else here:

- The compiler is written in pure V. No C is added to the pipeline, and no piece
  of the compiler delegates work to a C compiler or a C library.
- It is fast, and the speed does not regress. The measurement that counts is
  compiling the C that V generates for its own build, because that is the load a
  replacement for the vendored tcc has to carry.

## Getting set up

You need V 0.5.x and a Linux x86-64 machine.

```sh
git clone https://github.com/HuntedByTheIRS/vcc
cd vcc
v -o vcc .            # build the compiler
v test .              # the test suite
v run tools/gate.vsh  # format, the pure-V rule, the build, the tests, doc links
./vcc -hh             # the flag surface, annotated
```

The gate is the same set of checks CI runs, so it is worth running before you
push rather than waiting for a machine to tell you. `tools/README.md` describes
it and the benchmark harness next to it.

Nothing in this tree needs a C compiler of its own beyond the one V itself uses
to build it. If you find yourself adding a `cc` invocation, that is the rule
above being broken, not a build problem to solve.

## Preprocessor, flags, and the V contract

V does not treat a C compiler as an opaque binary. It classifies it by name and
by its `--version` output, caches artifacts against that identity, and passes a
specific flag set. The list and the classification rules are in the README under
"What a drop-in has to satisfy", read off `vlib/v/driver/driver.v` and
`vlib/v/pref/pref.v`.

Three consequences for changes that touch the command line:

- A flag you do not implement gets accepted and recorded, never rejected. V
  passes `-bt25` and `-Wl,...` passthroughs, and a compiler that errors on them
  fails a build it was supposed to serve.
- `--version` stays stable and machine-parseable. Changing its shape changes
  what V thinks this compiler is and invalidates every cached artifact keyed on
  the old answer.
- Anything that reasons about "what V wants here" is a change to interop, and
  the pull request should say which V source line it comes from.

## Measuring speed

A performance claim needs a number, and the number needs to come from the same
workload every time. `tools/bench.vsh` runs vcc and the vendored tcc on the same
input and prints wall time and peak memory for both.

```sh
v run tools/bench.vsh                 # generated workload, vcc beside tcc
v run tools/bench.vsh src.c --runs 5  # a file you name, more repetitions
v -showcc -cc tcc -o /tmp/probe probe.v   # what V actually asks a compiler to do
```

The workload that decides this project is the V self-build, and no milestone
before M3 can run it, so the harness measures what it can compile and the number
is reported with the file it came from. Quote the command when you quote the
number.

`./vcc -bench` prints per-phase timings, which is where you find out whether a
slow build is the lexer, the parser, or the back end. A change that makes the
self-build slower is not landed with an apology; either the constant factor
comes out of the same change or it stays open. When you compare, compare peak
memory as well as wall time. A compiler that is quick and eats four gigabytes is
not usable on the machines this has to run on.

## Tests

`v test .` runs everything: the suite lives in `*_test.v` files beside the code
it exercises. A change to the lexer, the parser, or the back end arrives with a
test that fails before it and passes after. When a test fails, fix the code or,
if the expected behavior genuinely changed, say so in the pull request and
change the expectation there. Never edit a test to quiet a failure.

Back-end changes want a runnable artifact, not just a unit assertion. The
pattern the tree already uses compiles a small program, writes it to a scratch
directory, runs it, and checks the exit status or the output.

Big input is a test case in its own right. The one crash this tree has had was a
fold that recursed once per term in an operator chain, which took the stack out
at a few thousand terms; `v run tools/bench.vsh --terms 20000` is what found it.
A new phase wants a test on input that is large and badly shaped (deep nesting,
long chains) and not only on input that is interesting.

## Code and prose

- `v fmt -w` before every commit. Tabs for indentation, per `.editorconfig`.
- One module per directory. `parser` does not know about `codegen`, and neither
  of them reaches into `cli`.
- Doc comments explain why a thing exists and what would break without it. They
  read as plain sentences, not as a summary of the function name.
- The same goes for the markdown here. Write it the way you would say it out
  loud; cut the padding and the "this serves as a reminder that" phrasing.

## Commits

Subjects are `area: the thing that changed`, lowercase, no trailing period. The
body says why the change happened, what the old behavior was, and what the
measurement showed if speed was involved. One logical change per commit, each
one building and passing `v test .` on its own.

Areas in use: `tokenize`, `parser`, `ast`, `backend`, `codegen`, `cli`, `tools`,
`tree`, `docs`.

## Review

A reviewer reads for the failure first: what happens on malformed input, what
happens when the output file cannot be written, what a diagnostic carries. Then
the numbers, if the change is on a hot path. Then the flag contract, if the
change touches the command line. Say which of those your change affects when you
open the pull request, so the review goes where the risk is.

## Where to ask

- Questions, design discussion, and half-formed ideas: `DISCUSSIONS.md`.
- Bugs and feature requests: `ISSUES.md`.
- Vulnerabilities: `SECURITY.md`, privately, not in a public issue.
- How people are expected to behave here: `CODE_OF_CONDUCT.md`.
