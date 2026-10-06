# regression

![regression cases failing](https://img.shields.io/badge/dynamic/json?url=https://raw.githubusercontent.com/HuntedByTheIRS/vcc/main/.github/badges/regressions.json&query=$.failed&label=regressions&color=critical&style=flat)

This corpus pins compiler behaviour that was once broken and now works. Every
file is a small C program that reproduces the shape of a defect this tree fixed,
so the same break is caught by a program rather than by a user. The source is
the tree's own history: each file's header comment names the defect it pins and
the commit that fixed it.

The badge above counts the cases that currently fail. A green badge of 0 means
every case in the directory compiles and runs.

## One directory per standard

A case's directory is the standard it is compiled under: the leaf name is the
`-std=` spelling.

    regression/iso/c99/     ISO C99, compiled -std=c99
    regression/iso/c11/     empty until the first ISO C11 case lands
    regression/iso/c17/     empty
    regression/iso/c23/     empty
    regression/iso/c29/     empty
    regression/gnu/gnu99/   GNU C99, compiled -std=gnu99
    regression/gnu/gnu11/   empty
    regression/gnu/gnu17/   empty

Most cases in the corpus compile under strict ISO C99 and sit in `iso/c99`. A
case this compiler accepts only in a GNU dialect belongs in `gnu/` beside its
ISO sibling: `gnu/gnu99/` holds the first of them, the cleanup attribute
compiled `-std=gnu99`.

## Naming

    NNNN-group-individual.c

`NNNN` is a four-digit serial from `0000` with no gaps. `group` is the area of
the tree the pinned behaviour belongs to and is one of `tokenize`, `preprocess`,
`parser`, `types`, `optimizer`, `printer`, `codegen`, `backend`, `image`,
`link`, `driver`, `cli`. `individual` names the behaviour in lowercase words
joined by hyphens. The serial counts the corpus rather than the group, so
`iso/c99/0005-parser-block-scope-extern.c` is the sixth case here whatever group
it belongs to.

## What a case is

One file is one small C program with `int main(void)`. It is self-contained and
uses no library headers beyond the C standard ones. The exit status is the
verdict.

- On the success path the program prints nothing and exits 0.
- When the compiler misbehaves the program writes one plain line to stderr
  naming what broke and exits non-zero.

The check lives inside the program, so a case fails when the compiled program
runs to the wrong result, not only when the compiler refuses the source. A
refusal and a silently wrong value are both failures here.

## How a case is compiled and run

Every case compiles and runs correctly under the tree-built vcc with exactly the
flags its directory names:

    v -o /tmp/vcc-reg .
    /tmp/vcc-reg -x c -std=c99 -w -lm regression/iso/c99/NNNN-group-individual.c -o /tmp/case
    /tmp/case ; echo $?

and under gcc with the same flags:

    gcc -x c -std=c99 -w -lm regression/iso/c99/NNNN-group-individual.c -o /tmp/case
    /tmp/case ; echo $?

`-x c` reads the file as C whatever its extension. `-std=c99` is the dialect the
directory names, so a case under `gnu/gnu99/` is measured `-std=gnu99`. `-w`
because some cases are deliberately not warning-clean under one compiler. `-lm`
for the complex and long double routines.

A non-zero exit from the run means the pinned behaviour is broken. A build
failure is also a non-zero verdict, because the compiler refusing the construct
is exactly what the case is there to catch.

## The gcc half

The pinned behaviour has to be what C says, not merely what vcc currently does
in the same run. Every case is therefore also compiled and run under gcc with
the same flags. A case where gcc disagrees with the expectation is a wrong
expectation and does not belong here; a case where vcc disagrees with gcc is a
defect, reported rather than added.
