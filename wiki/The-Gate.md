# The-Gate

The gate is the set of checks a change has to pass. It runs locally with one
command, `v run tools/gate.vsh`, and CI runs the same checks, so a pull
request does not meet an opinion the author could not have run first.

## v run tools/gate.vsh

`v run tools/gate.vsh` runs six steps, each reporting on its own line, and
exits zero only when all six pass.

The formatting step runs `v fmt -verify .`, the same formatter every
contributor runs. It refuses a file that is not formatted.

The pure V step refuses C sources in the tree, apart from the test directories
under `compliance/`, `regression/` and `goldens/`, where C is input the
compiler is handed. Everywhere else a `.c`, `.h`, `.cc`, `.cpp`, `.hpp`, `.S`
or `.s` source is a failure. The same step refuses `#include`, `#flag` and C
interop (a `C` and a dot) in the compiler's own sources, including inside a
test directory, because a `.v` file there is still this compiler's source. The
interop patterns are skipped under `tools/` and `.omh/`, where the scripts and
the agent notes name them on purpose. The step cannot prove the compiler is
written in V, only that it has not started pulling C into the compiler.

The build step runs `v -o <temp> .` into a temporary path. It refuses a tree
that does not compile.

The tests step runs `v test .`.

The documents step follows every relative link between the markdown files. It
refuses a link whose target does not exist, because a link to a file that
moved is worse than no link at all.

The workflows step reads the files under `.github/workflows` for two things
the files cannot check about themselves: every workflow pins the same V commit
(a 40-character commit hash in `V_COMMIT`), and every action is pinned to a
version rather than to a branch that moves under it. Two workflows that pin
different V commits would test two compilers and call it one CI, and the
failure would look like flakiness rather than the disagreement it is.

## The test suite

`v test .` runs the suite. A test sits beside the module it exercises as a
`*_test.v` file, and a test is a top-level `fn test_...`, which is the shape
`v test` collects. A change to a module arrives with a test that fails before
it and passes after, and a failing test is fixed in the code rather than
quieted in the test. [[Pure-V]] covers the rule the pure V step enforces.

`tools/tests.vsh` is the suite's inventory. `v run tools/tests.vsh` prints the
count in each file and then the total, and `v run tools/tests.vsh --count`
prints the total alone for the badge step. The count has one home: on a push
to main the runner writes `.github/badges/tests.json`, and the tests badge in
the README reads it, so the badge cannot disagree with the run. The walk
counts the C corpora too, by the rule `tools/regress.vsh` collects by, so the
badge and the runner do not disagree about what a case is.

## The compliance corpus

`v run tools/compliance.vsh` compiles and runs the corpus under `compliance/`.
The suite says the compiler does what its own tests say; this corpus says it
agrees with C programs nobody wrote for it, checking about nine hundred of its
answers against the standard library and asking it to refuse the programs the
standard says are invalid.

The tests live in a directory per standard, and the directory is the mode: the
leaf name is the `-std=` spelling, so `compliance/iso/c99/` is compiled
`-std=c99` and `compliance/gnu/gnu99/` `-std=gnu99`. `monolithic.c` is the file
the corpus arrived as, kept at the root, and `NNNN-name.c` inside a dialect
directory is one of its checks with the declarations and statements that check
needs. Each test is a program, so the runner is a work queue: it compiles and
runs all of them in parallel (`-j`, eight by default) and reports the suite, the
test file and the line in it that failed.

```sh
v run tools/compliance.vsh                        # build the tree, then run everything
v run tools/compliance.vsh --compiler /tmp/vcc    # a compiler you already built
v run tools/compliance.vsh --only 0017 0018       # the tests you name
v run tools/compliance.vsh --define C99_TRIGRAPHS # include the gated tests too
v run tools/compliance.vsh --list                 # print what would run
v run tools/compliance.vsh --count                # print how many tests there are
```

The runner refuses a test that does not build, a test that exits non-zero, a
test that prints something other than the two lines the corpus prints on
purpose, a test that expects a refusal the compiler does not make or an
acceptance it does not give, a test file count below 1125, and a `monolithic.c`
run that holds fewer than 906 checks. Both floors are floors and not equalities:
adding tests needs no edit here, losing them is a failure. A test carrying a
`requires-define: NAME` line is skipped unless `--define` names it, because
running it with the construct off would pass by not compiling the thing under
test. A test carrying an `expects-refusal:` line is a program that breaks a
Constraint or a syntax rule, so a conforming implementation owes a diagnostic
for it: the refusal is the check, and the test is never run. A test carrying an
`unimplemented:` line is a program the standard allows that this compiler cannot
read yet: the refusal is counted as a gap and named in the run's output, and the
program's own assertions are what run the day the compiler takes it. Each test
compiles with the standard of its directory, and
[compliance/README.md](https://github.com/HuntedByTheIRS/vcc/blob/main/compliance/README.md)
says why the corpus is split and why `-lm` is not optional.

## The regression and golden corpora

`v run tools/regress.vsh` runs two corpora with one contract each.
`regression/` is a program per bug the compiler has already fixed, and
`goldens/` is a program per behaviour whose output is recorded.

A regression case is named `NNNN-group-individual.c` and has `int main(void)`.
It prints nothing and exits zero while the compiler behaves; a line of output
or a non-zero exit is the regression the file was added for. A golden case has
the same name shape and a `.expected` file beside it: the program prints to
stdout and exits zero, and its stdout has to equal the expected bytes, line
for line and byte for byte.

```sh
v run tools/regress.vsh                        # build the tree, then run every case
v run tools/regress.vsh --compiler /tmp/vcc    # a compiler you already built
v run tools/regress.vsh --only 0001 0002       # the cases you name
v run tools/regress.vsh --define NAME          # include the gated cases
v run tools/regress.vsh --root /tmp/tree       # read the corpora from another tree
v run tools/regress.vsh --list                 # print what would run
v run tools/regress.vsh --count                # print how many cases there are
```

A case's directory is the standard it is compiled under: the leaf name is the
`-std=` spelling, so `regression/iso/c99/` is compiled `-std=c99` and
`regression/gnu/gnu99/` `-std=gnu99`. Every case in both corpora today compiles
under strict ISO C99, so they all sit under `iso/c99`; a case this compiler
accepts only in a GNU dialect goes under `gnu/`. Every case compiles with the
standard of its directory plus `-w` because a case is not required to be
warning-clean, `-lm` for the math a case may touch, and `-x c` so the compiler
reads the file as C rather than guessing from a name it did not write. Cases run
in parallel, eight at a time by default (`-j N`). Each directory has a floor on
its case count: losing a case is a failure and adding one is not. The count
`--count` prints is the number the regressions badge in the README reads.

## The benchmark harness

`v run tools/bench.vsh` measures wall time and peak memory for a compile, with
the tcc V vendors on the same input beside it, because near tcc's speed is one
of the two constraints on this project.

```sh
v run tools/bench.vsh                          # generated workload, vcc against tcc
v run tools/bench.vsh src.c                    # a file you name
v run tools/bench.vsh --terms 100000 --runs 5  # bigger, more repetitions
v run tools/bench.vsh --no-compare             # vcc alone
v run tools/bench.vsh --tcc /path/to/tcc       # a different tcc to compare against
```

It builds the tree under test first, so the numbers describe the current
source rather than whatever binary was lying around. Wall time is the best of
`--runs` attempts (three by default) and comes from the clock around the whole
call, which includes process startup; peak memory comes from `/usr/bin/time`
for the attempt that was kept. The generated workload is one function
returning a long constant expression, a file both compilers accept, and one
that grows with `--terms` (2000 by default).

The V self-build is the workload that will decide this project, and no
milestone reaches it yet, so the harness measures the gap on what the compiler
can compile. The README prints the current wall time and peak memory against
the vendored tcc. CI runs the harness and writes the numbers into the run
summary, and nothing fails on them: a shared runner's wall time is not a
budget to hold a pull request to. The speed gate appears when the self-build
number exists ([[Roadmap]] M6).

## tools/build.vsh, the front door

`v run tools/build.vsh` is the front door over the same commands: build the
compiler, run the gate, run both corpora, benchmark, build the image, and
report the version. Every step calls the runner that already owns the check,
so no count or floor is kept twice.

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

The compiler is built under the temp directory for the steps that only need
one to run cases, and no step leaves a `vcc` in the tree unless it was asked
for by name (`build -o PATH`). `all` runs every step even when one fails and
exits non-zero if any failed, so one run reports every failure. A step whose
tool is missing is skipped and named in the summary; that fails the run only
when the step was asked for by name. `version` prints what the binary reports,
what `v.mod` names, and the V commit `ci.yml` pins, because those three drift.

## What CI does with the gate

`.github/workflows/ci.yml` builds V from source at the pinned commit and runs
`gate.vsh`, so the checks a contributor runs locally are the checks CI runs.
Four jobs: the gate, the compliance corpus on a runner of its own, the
regression corpus on a runner of its own, and a run against V master that is
allowed to fail. The last three each build the pinned V, because a job is one
machine and the pin is the only thing they must share.

On a push to main the gate job counts the suite with `tests.vsh` and the
compiler's lines with `lines.vsh`, writing the files the tests and lines
badges read. The compliance and regression jobs do the same for their own
badges, each counting with its own runner.
