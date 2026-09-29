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

Five steps, each reporting on its own line, exit status zero only when all pass:

- **formatting** — `v fmt -verify .`
- **pure V** — no C sources in the tree, and no `#include`, `#flag`, or `C.`
  interop in the compiler's own sources
- **build** — `v -o <temp> .`
- **tests** — `v test .`
- **documents** — every relative link between the markdown files resolves

The pure-V step is the machine-checked half of the first constraint. It cannot
prove the compiler is written in V, only that it has not started importing C.

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
- CI wiring. The gate is written to be CI-ready and runs locally today; the
  workflows under `.github/` do not call it yet.
