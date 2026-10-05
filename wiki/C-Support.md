# C-Support

vcc reads a large subset of Linux x86-64 ISO C99 and refuses the rest with a
diagnostic. This page is what the tree reads today and what it does not, and
the claims below were checked by running the binaries the compiler produces
rather than by reading the source. The dialect table lives in
`standard/features.v`, and how the pipeline is put together is in
[[Architecture]].

## The preprocessor

The preprocessor is a real one, not a macro pass bolted onto the parser. It
reads:

- `#include` with the search order C gives it, and `#include_next`.
- object-like and function-like macros, with `#`, `##` and variadic arguments.
- conditionals with the full `#if` expression grammar.
- `#pragma once`, `#line`, `#error` and `#warning`, where a `#warning` is a
  warning and the compile continues.
- `_Pragma`, the location and clock macros, and `__has_include`.

Its fidelity is checked against `tcc -E` on the same file, token by token.

## The front end

The front end reads what a preprocessed header is made of (typedefs,
prototypes, structs, unions, enums, bitfields) and the function definitions
after them. It reads the operators, control flow (`if`/`else`, `while`, `for`,
`do`, `switch`, `goto`), `sizeof` and casts, designated initializers, compound
literals, variadic functions, function pointers, and objects of
`struct`/`union` type passed and returned by value.

An object of a struct or union is a block of storage read and written at the
offsets the layout gives it. A typedef and a `typeof` specifier are followed
to the type they name.

## The back end

The back end writes one executable `PT_LOAD` at `0x400000` with a `PT_INTERP`,
its own `_start`, `DT_NEEDED libc.so.6` and no PLT: calls resolve through the
dynamic loader, which is what makes `puts` work without a linker.

`-l<name>` resolves the library through the ld script in `/usr/lib` when the
file it finds is one, and the SONAME of the file at the end of that is what
the image asks for, which is how `-lm` gets `sqrt` to resolve. `-c` writes a
real ELF64 relocatable object. `-fPIC` reaches top-level objects through the
global offset table, so the object can go into a shared library later.

## Dialects and the -std= modes

The compiler carries a dialect table: one row per construct, holding the
standard it belongs to, whether a GNU dialect takes it, and what this compiler
does with it. The table is data and not a chain of branches, so a construct
the compiler gains is a row whose status changes.

A `-std=` spelling selects a mode. The modes are `c89`, `c99`, `c11`, `c17`,
`c23` and `c29`, and the GNU dialect of each, `gnu89` through `gnu29`. The
spellings include the ISO forms (`iso9899:1990` through `iso9899:2029`), the
`c90` and `c18` and `c2y` aliases, and `gnu2y` for the next standard. Modes
rank by the standard they name, so `gnu99` includes everything `c99` has.

Two answers sit outside that ranking. `.none` is no `-std` at all, which is
the compiler's own default and not a standard it measured anything against.
`.other` is a spelling that names a language this compiler does not implement:
it is recorded and refused nothing, because tcc accepts every spelling and a
compiler V may hand any spelling to must not fail on one.

## Pedantic messages and diagnostics

Reporting is separate from refusing, and the two are different things.

A construct the selected mode merely does not allow is a pedantic message. It
is silent until `-Wpedantic` or `-pedantic` asks for it, promoted to an error
by `-pedantic-errors` or `-Werror=pedantic`, and silenced by `-w`.

A construct the mode does not have at all is a diagnostic the compiler raises
on its own account, and no flag silences it. `typeof` is the measured example:
`-std=c99 -pedantic` on `typeof(int) x = 3;` reports
`ISO C99 forbids the typeof specifier` and exits non-zero, matching gcc's
refusal. The reserved-namespace spellings `__typeof__` and `__typeof` are
taken by every mode and reported by none. `-std=c11` takes `_Generic` silently
where `-std=c99 -pedantic` warns.

System headers are exempt from both, because nobody in the build wrote them.

Each row's phrasing was checked against gcc 16.2.1 under the relevant `-std=`,
and the comment on the row records what was measured.

## Vendor extensions and -fvcc-exts=

The spellings that follow the reserved-namespace rules (`__typeof__`,
`__asm__`) are read in every mode, the way gcc reads them. The ones a standard
introduced (`typeof`, `auto`, `_Generic`, `_Static_assert`, `_BitInt`) are
gated by the dialect table and can be brought down to an earlier mode with
`-fvcc-exts=`.

The names are the rows in `standard/features.v`, read through `extensions/`.
The table carries four: `auto`, `generic`, `static-assert` and `typeof`. `all`
turns on every extension the compiler has, and a comma-separated list names
them one by one. A name the table does not carry is an error when the flag
asks for it and a record when `-fno-vcc-exts=` turns it off.

```sh
./vcc -fvcc-exts=all prog.c -o prog                 # every extension the compiler has
./vcc -fvcc-exts=typeof,generic -std=c99 prog.c     # named ones
```

What the tree reads includes `typeof`, `__typeof__`, `__typeof` and
`typeof_unqual`; C23 `auto`; `_Generic`; `_Static_assert`; `_BitInt(128)`;
`__int128`; GNU statement expressions; `__asm__`; a postfix `__attribute__`;
the `__atomic_*` operations; and the count-leading and count-trailing
builtins.

## What is verified

Verified by running the results: a program including `stdio.h`, `stdlib.h`,
`string.h`, `stdint.h`, `stddef.h`, `limits.h`, `errno.h` and `time.h`
compiles clean with `-c`; enum/switch/shift/bitwise/unsigned code compiles and
runs; and a program with designated initializers, compound literals,
bitfields, a union and a struct returned by value compiles and runs.

The C99 conformance corpus under `compliance/` is compiled and run by
`v run tools/compliance.vsh`, which checks the compiler against the standard
rather than against its own tests. `monolithic.c` holds 906 checks and the
corpus holds 999 test files; the mode is `-std=gnu99` and `-lm` is not
optional. `regression/` holds one program per bug that must not come back, run
by `v run tools/regress.vsh`. The suite itself is counted by
`v run tools/tests.vsh`.

The recorded counts live in `.github/badges/` and are written by the runners
rather than kept by hand: 1561 tests, 999 compliance tests, 60 regression
cases with 0 failing, and 46843 lines of V. [[The-Gate]] runs the same checks
a pull request has to pass.

## What is not there yet

- Multi-unit linking. The in-house linker is not written, so linking more than
  one translation unit, archives, `-shared` and `-static` currently need
  `-external-linker=NAME`. Archive support is not optional for the V contract:
  every `-cc tcc` build links `thirdparty/tcc/lib/libgc.a`.
- V's generated C code. The compiler is not self-hosting and cannot compile it
  yet. That is bootstrap step 3, the V self-build, targeted for the end of Q4
  2026 or early Q1 2027. [[Interop]] has what V asks of a C compiler.
- Other targets. It is Linux x86-64 only. arm64, macOS and Windows are back
  ends that do not exist yet.
- `_Complex` and `_Imaginary`, which the dialect table carries as
  unimplemented. The C99 float types and `_Bool` are read, but the back end
  has no form for them yet, so a definition of one is refused by name and
  location.

## Refusals

Anything outside the subset exits non-zero with a diagnostic that names the
construct and its location, instead of writing an output file that would fail
later. A silent empty output file is treated as a bug. The full flag surface
is in `./vcc -hh`, and [[Roadmap]] has the milestones that close the gaps
above.
