# Performance

## The target

Near tcc's speed, which is not open to compromise. The benchmark that decides
this is the V self-build: a few megabytes of generated C per run, and vcc has
to get through it in the time the bundled tcc does, at comparable peak memory.
A compiler that is correct but slower is not a replacement.

`AGENTS.md` puts the same constraint in the tree: TCC-class speed, wall time
and peak RSS both, and never a speed improvement claimed from intuition. Speed
claims here are measurements, and the commands that produce them are printed
beside the numbers.

## How it is measured

`v run tools/bench.vsh` builds the tree under test rather than trusting a
binary lying around, generates a workload, and runs vcc and the tcc V vendors
on the same input. Wall time is the best of a few attempts and comes from the
clock around the whole call, which includes process startup. Peak memory comes
from `/usr/bin/time` for the attempt that was kept, since a peak from a slower
run belongs to a different measurement. Generated workloads are one function
returning a long constant expression, which is a workload both compilers
accept and one that grows with `--terms`.

The comparison tcc is found next to the `v` binary at
`thirdparty/tcc/tcc.exe`, or named with `--tcc PATH`. `--no-compare` runs vcc
alone. `tools/README.md` has the rest of the harness.

## The numbers

The numbers the repository records, from `README.md`, measured with
`v run tools/bench.vsh` against the tcc V vendors:

| terms | vcc wall | tcc wall | ratio | vcc peak | tcc peak | ratio |
|---|---|---|---|---|---|---|
| 2 000 | 30.2 ms | 5.1 ms | 6.0x | 14.4 MB | 3.4 MB | 4.2x |
| 20 000 | 196.2 ms | 7.2 ms | 27.1x | 55.4 MB | 3.4 MB | 16.4x |

The ratio grows with the input because tcc's own time barely moves, 5.1 ms to
7.2 ms across these two counts, while vcc's tracks the tokens and nodes it
allocates. That is a design problem and the M6 problem, not a constant factor
to trim.

`ROADMAP.md` records the same measurement at a larger count: on a 100000-term
constant chain vcc is about 69x the wall time and 57x the peak memory of tcc,
from `v run tools/bench.vsh --terms 100000`. The gap is measured rather than
felt.

## The commands

```sh
v run tools/bench.vsh                       # generated workload, vcc against tcc
v run tools/bench.vsh --terms 20000         # a bigger generated workload
v run tools/bench.vsh --terms 100000 --runs 5
./vcc -bench file.c -o out                  # per-phase timings
/usr/bin/time -v ./vcc -o /tmp/out src.c    # wall time and peak RSS
```

`--terms N` sets the length of the generated constant chain and `--runs N` the
number of attempts. `./vcc -bench` reports microseconds per phase, which
`tools/README.md` notes are printed but not kept as a history across commits.
`.github/workflows/ci.yml` runs the harness and writes the numbers into the
run summary, and nothing fails on them yet: a shared runner's wall time is not
a budget to hold a pull request to, and the workload that decides this
project, the V self-build, no milestone can run yet.

## What counts as a speed claim

A correctness-preserving change measured here is the only kind of speed claim
the tree accepts. The gate enforces the correctness half ([[The-Gate]]), and
ROADMAP M6 sets the budget: phase timings from `-bench` tracked per commit, a
wall-time and peak-memory budget for the V self-build measured against the
bundled tcc on the same machine, and design choices that follow from the
target, meaning a single pass over tokens, no full tree where a streaming
decision will do, arena allocation rather than per-node heap traffic, and
buffered output.

## The streaming path

The default pipeline builds an AST, because an optimizer, a type checker and a
second target are all built on one. `-no-ast` is the second path, planned:
skip the tree and compile while reading the tokens, deciding as it goes, with
nothing allocated per node, nothing walked and nothing freed. That is where
the rest of the distance to tcc's speed sits, since tcc does the same and
allocates almost nothing on the way. [[Architecture]] has the pipeline.

The rule that keeps the two honest is in ROADMAP M6a: the same input produces
the same bytes on both paths. The AST path is the reference implementation and
the streaming path is a verified fast version of it, not a second compiler
with its own opinions. Any difference is a bug in the streaming path, and the
comparison belongs in the gate over the same corpus the tests use. The
sequencing is M3 first, then the streaming path as an alternative front end
feeding the same back end, then the byte-for-byte comparison, and only then a
number that claims to beat tcc. [[Roadmap]] has the milestones.

## The long-input case

Long input is a test case. The one crash this tree has had was a fold that
recursed once per term in an operator chain and took the stack out at about
three thousand terms; `v run tools/bench.vsh --terms 20000` is what found it.
A phase is run on input that is large rather than only on input that is
interesting, and a deep structure counts against a limit the author chose
rather than against the stack.
