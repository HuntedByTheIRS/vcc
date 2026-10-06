# compliance

A conformance corpus written against the standards rather than against this
compiler, and the reason it is here. It is the only C in this tree, and it is
input to the compiler rather than part of it: the one exception the pure-V rule
in `tools/gate.vsh` carves out.

## One directory per standard

The tests live in a directory per dialect, and the directory a test sits in is
the standard it is compiled under: the leaf name is the `-std=` spelling, so a
new standard is a new directory and not a change to the runner.

    compliance/iso/c99/     ISO C99, compiled -std=c99
    compliance/iso/c11/     empty until the first ISO C11 case lands
    compliance/iso/c17/     empty
    compliance/iso/c23/     empty
    compliance/iso/c29/     empty
    compliance/gnu/gnu99/   GNU C99, compiled -std=gnu99
    compliance/gnu/gnu11/   empty
    compliance/gnu/gnu17/   empty

A test this compiler accepts only under a GNU dialect belongs in `gnu/` beside
its ISO sibling. `NNNN-name.c` is one check with the declarations and the
statements it needs, and a program of its own: it exits non-zero when its check
fails, so a failure names a file and a line in that file. The number is four
digits, so the corpus has room for 10,000 tests; the first thousand are the
checks cut from `monolithic.c`, and the numbering went to four digits when the
three ran out.

## A test is a program the compiler accepts, or one it must refuse

Most tests are programs a conforming implementation accepts: each compiles, runs
on its own, and exits non-zero when its check fails.

68 of them are the other way round. Each is a program that breaks a Constraint
or a syntax rule of ISO/IEC 9899:1999, so a conforming implementation owes a
diagnostic for it, and the test has a line saying so:

    /* 0999: a program that breaks a constraint, so the compiler must refuse it
     *
     * ISO/IEC 9899:1999 6.5.2.1p1: one of the expressions shall have type
     * pointer to object type, the other expression shall have integer type.
     *
     * expects-refusal: this program is not valid ISO C99.
     */

The refusal is the check. A test carrying `expects-refusal:` passes when the
compiler refuses to compile it, and fails when the compiler compiles it: a
compiler that takes the program has not done what the standard asks. Such a test
is never run, because there is no binary to run.

Each of the 68 was measured under gcc 16.2.1 with `-std=c99 -pedantic-errors` as
well, and 62 of them are refused there too. The six where gcc only warns are
still what the clause says they are, so the corpus holds them to the standard
rather than to gcc: `sizeof` of a function and of void, an equality between a
pointer and an integer, a declaration that declares nothing, and the two
initializers that write past the object they initialize.

## Why 159 tests sit under gnu/gnu99 and not iso/c99

Measured on this compiler, each test compiled on its own:

- Under `-std=c99`, 159 fail. 158 of them include `<tgmath.h>` and stop at
  `/usr/include/tgmath.h:802: #error "Unsupported compiler; you cannot use
  <tgmath.h>"`, because this compiler claims `__GNUC__` only in a GNU dialect
  and glibc's `<tgmath.h>` refuses a compiler that does not claim it. The
  159th, `0941-assert-a-true-expression-does-nothing`, uses `assert()`, whose
  glibc expansion under strict ISO needs a construct this back end does not
  evaluate yet.
- Under `-std=gnu99` the 999 programs compile and run. The 68 that must be
  refused are refused under either mode.

So the 840 that hold under strict `-std=c99` are in `iso/c99`, the 159 that
need the GNU dialect are in `gnu/gnu99`, and the 68 that must be refused are in
`iso/c99` beside the accepted programs.

## Running it

    v run tools/compliance.vsh

That builds the compiler from this tree, compiles and runs every test under the
standard of the directory it sits in, runs `monolithic.c` as well, and fails
when a test exits non-zero, prints something it should not, when the compiler
refuses a test it should accept or accepts a test it should refuse, when fewer
than 1067 test files are present, or when the monolith holds fewer than 906
checks. `tools/README.md` says what the script checks in more detail.

`monolithic.c` is the file the corpus arrived as, kept whole at the root: 12,340
lines, 386,573 bytes, about nine hundred assertions, all checked at run time, and

    906 checks, 906 passed, 0 failed

is the run it is expected to produce. It stays at the root and keeps `-std=gnu99`
because it includes `<tgmath.h>` and would stop at the same `#error` under c99.

A test whose file ends in `.h` is one whose check is about what a header
declares; the compiler reads it as C because the runner passes `-x c`. A test
carrying a `requires-define: NAME` line exercises a construct this compiler
accepts only when `NAME` is defined, so it is skipped unless asked for:

    v run tools/compliance.vsh --define C99_TRIGRAPHS

The run's summary line says how many tests passed, how many were refused, how
many failed, and how many were skipped. The refused count is the constraint
tests the corpus asked about that the compiler turned down; a test the compiler
compiles instead is a failure, and the problem list names it.

`-lm` is not optional: the corpus calls `cabsl`, `csqrtl` and `cpowl`.

The corpus as it arrived: md5 `44af6e3f61210afe051472307f76b316`.

Cutting the count, or weakening an assertion, is not how a failure here gets
fixed.
