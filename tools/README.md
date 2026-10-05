# tools

Scripts that check the tree and measure it. They are V scripts (`v run tools/…`),
so the tooling follows the same rule as the compiler: no shell scripts that call
a C compiler, no dependency on anything but V and the system's `time`.

## gate.vsh

The checks a pull request has to pass, in one command, so CI never holds an
opinion the author did not already have a chance to see.

```sh
v run tools/gate.vsh
```

Six steps, each reporting on its own line, exit status zero only when all pass:

- **formatting** — `v fmt -verify .`
- **pure V** — no C sources in the tree, apart from the compliance corpus, and
  no `#include`, `#flag`, or `C.` interop in the compiler's own sources
- **build** — `v -o <temp> .`
- **tests** — `v test .`
- **documents** — every relative link between the markdown files resolves
- **workflows** — the files under `.github/workflows` pin the same V commit,
  and every action is pinned to a version rather than a branch that moves

The pure-V step is the machine-checked half of the first constraint. It cannot
prove the compiler is written in V, only that it has not started importing C.

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
count below 933, and a `monolithic.c` run that holds fewer than 906 checks. Both
floors are floors and not equalities: adding tests needs no edit here, losing
them is a failure.

A test carrying a `requires-define: NAME` line exercises a construct this
compiler accepts only when `NAME` is defined, and is skipped unless `--define`
names it. Running it with the construct off would pass by not compiling the
thing under test.

The mode is `-std=gnu99`; `compliance/README.md` says why, and why `-lm` is not
optional.

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
On a push to `main` the same job counts the suite with `tests.vsh` and writes
`.github/badges/tests.json`, which the tests badge in `README.md` reads; the
compliance job does the same for the compliance badge. A second job builds V
master and runs the build and the tests without calling it a failure: master is
not the version this tree promises to build with, and finding out early is
cheaper than finding out from a bump.

`.github/workflows/release.yml` runs on a `v*` tag: the gate, a check that the
version inside the compiler matches the tag, a compiled program that is run, and
only then the release with the binary and its checksum attached.
