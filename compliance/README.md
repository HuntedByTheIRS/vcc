# compliance

A C99 conformance corpus written against the standard library rather than
against this compiler, and the reason it is here. It is the only C in this tree,
and it is input to the compiler rather than part of it: the one exception the
pure-V rule in `tools/gate.vsh` carves out.

The corpus is one directory of small tests. `monolithic.c` is the file it
arrived as, kept whole: 12,340 lines, 386,531 bytes, about nine hundred
assertions, all checked at run time, and

    906 checks, 906 passed, 0 failed

is the run it is expected to produce. Beside it, `NNN-name.c` is one of those
checks with the declarations and the statements it needs, and a program of its
own: it exits non-zero when its check fails, so a failure names a file and a
line in that file instead of a line in a twelve thousand line unit.

    v run tools/compliance.vsh

That builds the compiler from this tree, compiles and runs every test with it,
runs `monolithic.c` as well, and fails when a test exits non-zero, prints
something it should not, when the compiler refuses a test, when fewer than 933
test files are present, or when the monolith holds fewer than 906 checks.
`tools/README.md` says what the script checks in more detail.

A test whose file ends in `.h` is one whose check is about what a header
declares; the compiler reads it as C because the runner passes `-x c`. A test
carrying a `requires-define: NAME` line exercises a construct this compiler
accepts only when `NAME` is defined, so it is skipped unless asked for:

    v run tools/compliance.vsh --define C99_TRIGRAPHS

Two of the compiler flags are not optional. `-lm`, because the corpus calls
`cabsl`, `csqrtl` and `cpowl`. And the mode is `-std=gnu99`, not the `c99` the
monolith documents for gcc: the corpus includes `<tgmath.h>`, and the system
header refuses a compiler it does not recognise, so `-std=c99` stops at

    /usr/include/tgmath.h:802:1: #error "Unsupported compiler; you cannot use <tgmath.h>"

before it reaches a line of the corpus.

The corpus as it arrived: md5 `44af6e3f61210afe051472307f76b316`.

Cutting the count, or weakening an assertion, is not how a failure here gets
fixed.
