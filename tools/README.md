# tools

Scripts that check the tree and measure it. They are V scripts (`v run tools/…`),
so the tooling follows the same rule as the compiler: no shell scripts that call
a C compiler, no dependency on anything but V and the system's `time`.

## build.vsh

The front door over the scripts below: build the compiler, run the gate, run
both corpora, benchmark, build the image, and report the version. Reach for it
when you want the checks in one command, or when you do not remember which
runner owns a check. The individual runners are still the way to pass a flag
they alone take.

```sh
v run tools/build.vsh                 # build the compiler, then the gate, then both corpora
v run tools/build.vsh build [-o PATH] # the compiler only; -o is where it lands
v run tools/build.vsh test            # `v test .`
v run tools/build.vsh gate            # gate.vsh
v run tools/build.vsh compliance      # compliance.vsh
v run tools/build.vsh regress         # regress.vsh
v run tools/build.vsh corpora         # compliance and regress together
v run tools/build.vsh bench [args]    # bench.vsh, args passed through
v run tools/build.vsh docker          # build the image, then run the binary in it
v run tools/build.vsh version         # the binary, v.mod, and the pinned V commit
v run tools/build.vsh all             # every step, then a summary
v run tools/build.vsh --list          # the steps, one line each
```

Every step calls the runner that owns the check, so no count or floor is kept
twice. The compiler is built under the temp directory for the steps that only
need one to run cases, and no step leaves a `vcc` in the tree unless it was
asked for by name (`build -o PATH`). `all` runs every step even when one fails
and exits non-zero if any failed, so one run reports every failure. A step whose
tool is missing is skipped and named in the summary; that fails the run only
when the step was asked for by name. `version` prints what the binary reports,
what `v.mod` names, and the V commit `ci.yml` pins, because those three drift.

## gate.vsh

The checks a pull request has to pass, in one command, so CI never holds an
opinion the author did not already have a chance to see.

```sh
v run tools/gate.vsh
```

Six steps, each reporting on its own line, exit status zero only when all pass:

- **formatting** — `v fmt -verify .`
- **pure V** — no C sources in the tree apart from the test directories
  (`compliance/`, `regression/`, `goldens/`), and no `#include`, `#flag`, or `C.`
  interop in the compiler's own sources, including inside a test directory
- **build** — `v -o <temp> .`
- **tests** — `v test .`
- **documents** — every relative link between the markdown files resolves
- **workflows** — the files under `.github/workflows` pin the same V commit,
  and every action is pinned to a version rather than a branch that moves

The pure-V step is the machine-checked half of the first constraint. It cannot
prove the compiler is written in V, only that it has not started importing C.
What it lets through is C the compiler is handed: the corpus directories and
nothing else. The interop patterns are skipped under `tools/` and `.omh/`, where
the scripts and the agent notes name them on purpose; a `.v` file inside a test
directory is still this compiler's source and gets no such pass.

## compliance.vsh

The corpus under `compliance/`, compiled by the tree and run. The suite says the
compiler does what its own tests say; this says it agrees with a C program nobody
wrote for it, one that checks about nine hundred of its own answers against the
standard library.

```sh
v run tools/compliance.vsh                        # build the tree, then run everything
v run tools/compliance.vsh --compiler /tmp/vcc    # a compiler you already built
v run tools/compliance.vsh --only 017 018         # the tests you name
v run tools/compliance.vsh --define C99_TRIGRAPHS # include the gated tests too
v run tools/compliance.vsh --list                 # print what would run
v run tools/compliance.vsh --count                # print how many tests there are
```

The corpus is one directory of small tests: `monolithic.c` is the file it
arrived as, and `NNN-name.c` beside it is one of its checks with the
declarations and statements that check needs. Each test is a program, so the
runner is a work queue: it compiles and runs all of them in parallel (`-j`,
eight by default) and reports the test file and the line in it that failed.

It builds the tree under test first unless `--compiler` names a binary, so the run
describes the current source rather than one from an earlier edit. It fails on a
test that does not build, a test that exits non-zero, a test that prints
something other than the two lines the corpus prints on purpose, a test file
count below 999, and a `monolithic.c` run that holds fewer than 906 checks. Both
floors are floors and not equalities: adding tests needs no edit here, losing
them is a failure.

A test carrying a `requires-define: NAME` line exercises a construct this
compiler accepts only when `NAME` is defined, and is skipped unless `--define`
names it. Running it with the construct off would pass by not compiling the
thing under test.

The mode is `-std=gnu99`; `compliance/README.md` says why, and why `-lm` is not
optional.

## regress.vsh

Two corpora with one contract each, run by one runner: `regression/` is a program
per bug the compiler has already fixed, and `goldens/` is a program per behaviour
whose output is recorded. A regression case is held to silence and an exit
status; a golden is held to the bytes in a `.expected` file.

```sh
v run tools/regress.vsh                        # build the tree, then run every case
v run tools/regress.vsh --compiler /tmp/vcc    # a compiler you already built
v run tools/regress.vsh --only 0001 0002       # the cases you name
v run tools/regress.vsh --define NAME          # include the gated cases
v run tools/regress.vsh --root /tmp/tree       # read the corpora from another tree
v run tools/regress.vsh --list                 # print what would run
v run tools/regress.vsh --count                # print how many cases there are
```

A regression case is named `NNNN-group-individual.c` and has `int main(void)`. It
prints nothing and exits zero while the compiler behaves; a line of output or a
non-zero exit is the regression the file was added for. A golden case has the
same name shape and a `.expected` file beside it: the program prints to stdout
and exits zero, and its stdout has to equal the expected bytes, line for line and
byte for byte.

Both corpora compile with the flags `compliance.vsh` uses, for the same reasons:
`-std=gnu99` because a case may reach a system header that refuses the `c99`
spelling, `-w` because a case is not required to be warning-clean, `-lm` for the
math a case may touch, and `-x c` so the compiler reads the file as C rather than
guessing from a name it did not write. Cases run in parallel, eight at a time by
default (`-j N`).

Each directory has a floor on its case count: losing a case is a failure and
adding one is not, so the floor is a floor and not an equality, the same
arrangement `compliance.vsh` uses. `--root` points the runner at corpora in
another tree, which is how it was exercised before its corpus landed here.
`--count` prints the case count, and that number is what the regressions badge in
`README.md` reads.

## tests.vsh

The suite's inventory. `v test .` runs the tests; this says how many there are,
which is the number the tests badge in `README.md` reads.

```sh
v run tools/tests.vsh            # the count in each file, then the total
v run tools/tests.vsh --count    # the total alone, for the badge step
```

A test is a top-level `fn test_...`, which is the shape `v test` collects, so
the badge cannot disagree with the run. The count has one home: the runner
writes `.github/badges/tests.json` on a push to `main` and the badge reads it,
the same arrangement `compliance.vsh` and the compliance badge use.

## lines.vsh

The compiler's size in lines: the `.v` files the tree tracks that are not tests,
`tools/` out and `linking/` in, so the linker counts itself the day it is
written. Lines are physical, the way `wc -l` counts them. The files come from
`git ls-files` rather than a walk of the tree, because a walk reaches into
`.omh/` and counts the agent working state's copies of the sources as compiler;
that leak is where ARCHITECTURE.md's old total of 72,068 came from.

```sh
v run tools/lines.vsh            # the lines in each module, then the total
v run tools/lines.vsh --count    # the total alone, for the badge step
```

The count has one home: the gate job writes `.github/badges/lines.json` on a push
to `main` and the lines badge reads it, the same arrangement the tests badge uses.

## bench.vsh

Wall time and peak memory for a compile, with tcc on the same input as the
comparison, because "near TCC's speed" is the requirement and a number nobody
prints is a number nobody watches.

```sh
v run tools/bench.vsh                          # generated workload, vcc against tcc
v run tools/bench.vsh src.c                    # a file you name
v run tools/bench.vsh --terms 100000 --runs 5  # bigger, more repetitions
v run tools/bench.vsh --no-compare             # vcc alone
v run tools/bench.vsh --tcc /path/to/tcc       # a different tcc to compare against
```

It builds the tree under test first, so the numbers describe the current source
rather than whatever binary was lying around. Wall time is the best of `--runs`
attempts and comes from the clock around the whole call, which includes process
startup; peak memory comes from `/usr/bin/time` for the attempt that was kept.
Generated workloads are one function returning a long constant expression, which
is a workload both compilers accept and one that grows with `--terms`.

The V self-build is the workload that will decide this project, and it is not
here yet: the stub cannot compile real C. Until then this harness measures the
gap on what it can compile, so the numbers move as the compiler grows into the
workload that matters.

## What is not here yet

- A self-build benchmark, for the reason above: it needs a compiler that can
  compile V's output, which is M3's problem and not a tooling problem.
- A phase-by-phase profile. `./vcc -bench` reports microseconds per phase and the
  harness prints them, but there is no history of those numbers across commits.
- A speed gate. `.github/workflows/ci.yml` runs the harness and writes the
  numbers into the run summary,
  but nothing fails on them yet: a shared runner's wall time is not a budget to
  hold a pull request to, and the workload that decides this project is the V
  self-build, which no milestone can run yet. The gate appears when that number
  exists (ROADMAP M6).

## What CI does with them

`.github/workflows/ci.yml` builds V from source at a pinned commit, runs
`gate.vsh`, then runs the benchmark and writes the numbers into the run summary.
On a push to `main` the same job counts the suite with `tests.vsh`, and the
compiler's lines with `lines.vsh`, writing `.github/badges/tests.json` and
`.github/badges/lines.json` for the badges in `README.md`; the
compliance job and the regression job do the same for the compliance and
regressions badges, each counting with its own runner. A second job builds V
master and runs the build and the tests without calling it a failure: master is
not the version this tree promises to build with, and finding out early is
cheaper than finding out from a bump.

`.github/workflows/release.yml` runs on a `v*` tag: the gate, a check that the
version inside the compiler matches the tag, a compiled program that is run, and
only then the release with the binary and its checksum attached.
