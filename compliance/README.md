# compliance

One C file, carried unaltered, and the reason it is here.

`main.c` is a C99 conformance corpus written against the standard library rather
than against this compiler. It makes about nine hundred assertions, checks each
one at run time, and prints how many held. It is the only C in this tree, and it
is input to the compiler rather than part of it: the one exception the pure-V
rule in `tools/gate.vsh` carves out.

    v run tools/compliance.vsh

That builds the compiler from this tree, compiles the corpus with it, runs the
binary, and fails when anything is printed while compiling, when the run exits
non-zero, or when fewer checks hold than the count the corpus reached when it
landed. `tools/README.md` says what the script checks.

The corpus as it arrived: md5 `44af6e3f61210afe051472307f76b316`, 12,340 lines,
386,531 bytes, and the run it is expected to produce is

    906 checks, 906 passed, 0 failed

Two of the flags are not optional. `-lm`, because the corpus calls `cabsl`,
`csqrtl` and `cpowl`. And the mode is `-std=gnu99`, not the `c99` the file
documents for gcc: the corpus includes `<tgmath.h>`, and the system header
refuses a compiler it does not recognise, so `-std=c99` stops at

    /usr/include/tgmath.h:802:1: #error "Unsupported compiler; you cannot use <tgmath.h>"

before it reaches a line of the corpus.

Cutting the count, or weakening an assertion, is not how a failure here gets
fixed.
