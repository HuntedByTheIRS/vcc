# Home

vcc is a C compiler written in V. It exists to replace the tcc binary that V
vendors in `thirdparty/tcc`, on the same command line and in the same speed
class, so the C compiler in V's build is a program V can build, read and patch
in V. It is BSD 3-Clause and adds no dependency to `v.mod`.

## Two constraints

**Pure V.** No C source in the compiler, no part of the pipeline handed to a C
compiler, no vendored C library. If a piece cannot be written in V yet, it
stays unimplemented and the construct is refused with a diagnostic rather than
worked around. There is one exception, named and off by default:
`-external-linker=NAME` hands the final link to a linker already on the
system, for the inputs vcc cannot consume yet, such as a relocatable object or
an archive. It refuses `cc`, `gcc`, `clang`, `c++` and `tcc` by name, because
a C compiler finishing C compilation is the one thing the rule exists to
prevent.

**TCC-class speed.** The workload that decides the project is the V
self-build: a few megabytes of generated C per run, and vcc has to get through
it in the time the bundled tcc does at comparable peak memory. Speed here is a
measurement, never a claim from intuition, and the command that produced a
number is printed beside it. A compiler that is correct but slower is not a
replacement.

## Where the tree is today

Past the stub. In practice a usable C compiler for a large slice of Linux
x86-64 C: the preprocessor is real, the front end reads what a real header is
made of and the function definitions after it, and the back end writes a
dynamically linked Linux x86-64 executable that calls into libc, so
`#include <stdio.h>` and `puts` work end to end. `-c` writes a real ELF64
relocatable object.

What is not there: vcc is slower than tcc, by a ratio that grows with input
size, and it is not self-hosting, so it cannot yet compile the C that V
generates for its own build. Multi-unit linking, `-shared` and `-static`
currently need `-external-linker=NAME`, because the in-house linker is not
written. It targets Linux x86-64 only.

Anything outside the supported subset exits non-zero with a diagnostic that
names the construct and its location, instead of writing an output file that
would fail later. `README.md` carries the detail, and [[Performance]] covers
the speed side.

## The bootstrap chain

The definition of done is four builds, each one a check on the step before it.

```sh
v -cc tcc -o v-tcc cmd/v              # 1. V, built with the vendored tcc
v -cc tcc -o vcc-v1 .                 # 2. vcc, built by that V
v-tcc -cc ./vcc-v1 -o v-v2 cmd/v      # 3. V, built by vcc instead of tcc
./v-v2 -cc ./vcc-v1 -o vcc-v2 .       # 4. vcc, built by the V that vcc built
```

Step 3 is the one that decides everything. vcc has to compile the megabytes of
C V emits for itself, link them against libgc and libc, and produce a V that
builds and passes V's own test suite. Step 4 then has to produce a vcc that
behaves like the one it came from. When both hold, the loop is closed and no C
compiler other than vcc is in it.

## The wiki

- [[Building]] for the toolchain, the pinned V commit and the ways to run the
  compiler.
- [[Architecture]] for how the pipeline is put together and where a new target
  goes.
- [[The-Gate]] for the checks a change has to pass.
- [[Pure-V]] for the rule and its one exception.
- [[C-Support]] for what the compiler reads today and what it refuses.
- [[Performance]] for the benchmark, the numbers and the speed target.
- [[Roadmap]] for the milestones and what verifies each one.
- [[Community]] for where to ask, where to report and the house rules.
- [[Interop]] for what V asks of a C compiler and how vcc answers.
