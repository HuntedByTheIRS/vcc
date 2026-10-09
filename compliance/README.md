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

## A test is a program the compiler accepts, one it must refuse, or one it cannot read yet

Most tests are programs a conforming implementation accepts: each compiles, runs
on its own, and exits non-zero when its check fails.

68 of them are the other way round. Each is a program that breaks a Constraint or
a syntax rule of ISO/IEC 9899:1999, so a conforming implementation owes a
diagnostic for it, and the test has a line saying so:

    /* 0999: a-subscript-on-a-scalar
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

The third kind of test is a program the standard allows and this compiler
cannot read yet. It carries an `unimplemented: X` line instead of
`expects-refusal:`, and the runner counts the build's refusal as a gap rather
than a failure and names the construct in the run:

    /* 1099: a-construct-this-compiler-does-not-read-yet
     *
     * ISO/IEC 9899:1999 <clause>: <the rule the program follows>.
     *
     * unimplemented: <the construct this compiler does not read>.
     */

Such a test is measured twice over: gcc compiles it, runs it and it exits 0, so
the program is right, and this compiler's refusal is the gap. The program is a
check with its own assertions, so the day this compiler takes it the test runs,
and a gap that compiles is reported by name as a line that can go: the corpus
does not keep a gap that has closed. One test carries the line, under
`iso/c99`: a structure a function type names before its own definition, which is
a shape V's generated C writes. Every gap the corpus carried before it has
closed, HUGE_VALL and the division of a `long double _Complex` and its negation
among them.

## The GNU extensions nothing reads yet

A GNU extension has no ISO clause to cite. The document that defines the dialect
is GCC's manual, section 6 (Extensions to the C Language Family) and the built-in
function chapters under section 7, so a test cites the node it comes from by
number and title:

    /* 1125: case-ranges-in-a-switch
     *
     * GCC 6.12.14 Case Ranges: "You can specify a range of consecutive values
     * in a single case label, like this: case low ... high :"
     *
     * unimplemented: a case label holding a range of values.
     */

26 tests, numbered 1125 to 1150, name a GNU construct this compiler did not read
when they were written: case ranges, a label declared with `__label__`, the
address of a label and a computed goto, nested functions, `__auto_type`,
`_Countof`, `__alignof__`, a variadic macro that names its arguments, the `?:`
with its middle operand omitted, `__FUNCTION__` and `__PRETTY_FUNCTION__`, a
structure with no members, a cast to a union type, the `[first ... last]`
designated initializer, `_Float128`, the decimal floating types, the `cleanup`
attribute, the built-ins `__builtin_add_overflow` and `__builtin_mul_overflow`, a
vector type declared with `__attribute__((vector_size(N)))`,
`__builtin_constant_p`, the bit-operation and byte-swapping built-ins,
`__builtin_unreachable` and `__builtin_trap`, `__builtin_alloca`,
`__builtin_object_size`, `__builtin_return_address`, and `asm goto`.

All 26 compile and run now. 1139, the decimal floating types, was the last and the
largest: `_Decimal32`, `_Decimal64` and `_Decimal128` needed a literal suffix and
three type kinds, the BID encoding gcc stores them in, and a conversion to
`double` that rounds the way gcc's does, which is code the program carries rather
than something the compiler can fold. A number that is not the one the source
wrote is worse than a refusal, so the refusal stood until the encoding and the
conversion were measured against gcc rather than guessed. Nothing in the range
carries an `unimplemented:` line any more.

Each was compiled and run under `gcc -std=gnu99` first: it exits 0 and prints
nothing. That is what makes "the program is right and only this compiler is
behind" a measurement rather than a claim.

## Why 159 of the tests sit under gnu/gnu99 and not iso/c99

Measured on this compiler, each test compiled on its own:

- Under `-std=c99`, 159 of the tests that predate the GNU gap tests fail. 158 of
  them include `<tgmath.h>` and stop at `/usr/include/tgmath.h:802: #error
  "Unsupported compiler; you cannot use <tgmath.h>"`, because this compiler
  claims `__GNUC__` only in a GNU dialect and glibc's `<tgmath.h>` refuses a
  compiler that does not claim it. The 159th,
  `0941-assert-a-true-expression-does-nothing`, uses `assert()`, whose glibc
  expansion under strict ISO needs a construct this back end does not evaluate
  yet.
- Under `-std=gnu99` the 1057 accepted programs compile and run. The 68 that must
  be refused are refused under either mode.

So `iso/c99` holds the 898 programs that hold under strict `-std=c99` and the 68
that must be refused, and `gnu/gnu99` holds those 159 plus the 26 GNU extensions
nothing reads yet: 1151 test files.

## Running it

    v run tools/compliance.vsh

That builds the compiler from this tree, compiles and runs every test under the
standard of the directory it sits in, runs `monolithic.c` as well, and fails
when a test exits non-zero, prints something it should not, when the compiler
refuses a test it should accept or accepts a test it should refuse, when fewer
than 1151 test files are present, or when the monolith holds fewer than 906
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
many are not implemented yet, how many failed, and how many were skipped, and it
names the construct behind each gap. The refused count is the constraint tests
the corpus asked about that the compiler turned down; a test the compiler
compiles instead is a failure, and the problem list names it.

`-lm` is not optional: the corpus calls `cabsl`, `csqrtl` and `cpowl`.

The corpus as it arrived: md5 `44af6e3f61210afe051472307f76b316`.

Cutting the count, or weakening an assertion, is not how a failure here gets
fixed.
