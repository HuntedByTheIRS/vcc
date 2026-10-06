# goldens

A case here is a small C program and the exact stdout it has to print. The
program is compiled, run, and its output compared with the recorded file. A test
that only checks the exit status cannot see the day the compiler starts printing
7 where it used to print 9; a golden can.

## One directory per standard

A case's directory is the standard it is compiled under: the leaf name is the
`-std=` spelling, so `goldens/iso/c99/` is compiled `-std=c99` and
`goldens/gnu/gnu99/` `-std=gnu99`.

    goldens/iso/c99/     ISO C99, compiled -std=c99
    goldens/iso/c11/     empty until the first ISO C11 case lands
    goldens/iso/c17/     empty
    goldens/iso/c23/     empty
    goldens/iso/c29/     empty
    goldens/gnu/gnu99/   GNU C99, compiled -std=gnu99
    goldens/gnu/gnu11/   empty
    goldens/gnu/gnu17/   empty

Every case in the corpus today compiles under strict ISO C99, so they all sit
under `iso/c99`. A case this compiler accepts only in a GNU dialect belongs
under `gnu/` beside its ISO sibling.

## Layout

`NNNN-group-individual.c` pairs with `NNNN-group-individual.expected`, in the
same dialect directory.

- `NNNN` is a four-digit serial starting at `0000`, with no gaps.
- `group` is one of the tree's own areas: `tokenize`, `preprocess`, `parser`,
  `types`, `optimizer`, `printer`, `codegen`, `backend`, `image`, `link`,
  `driver`, `cli`.
- `individual` says what the case prints.

So `iso/c99/0013-link-libc-calls.c` is compiled, run, and its stdout must equal
`iso/c99/0013-link-libc-calls.expected`.

## What a case is

A small deterministic C program. It prints to stdout and exits `0`, and it reads
nothing that varies between runs: no clock, no file, no environment, no argument
order, no uninitialised memory. Two runs of the same binary print the same bytes.

## The comparison

`tools/regress.vsh` compiles each case with the standard of its directory plus
`-w -lm -x c`, runs it, and compares its stdout with the `.expected` file byte
for byte. The trailing newline is part of the file, so output that agrees line
for line but stops before the last newline is still a failure. stdout and stderr
go to separate files and only stdout is compared.

## A missing .expected

A case without an `.expected` beside it cannot be checked. The runner treats that
as a failure ("no NNNN-....expected beside it"), not as a skip and not as a pass.
The bytes are the test, and without them there is no test.

## Where the bytes come from

The `.expected` file is the answer the C standard requires, not a transcript of
whatever vcc happened to print. Record it from a reference compile:

```sh
gcc -x c -std=c99 -w -lm 0013-link-libc-calls.c
```

then confirm the tree-built vcc prints the same bytes. A case where vcc disagrees
with gcc is a defect in the compiler: report it rather than committing vcc's
output as the expectation. A case must also stay clear of behaviour C leaves
implementation-defined or undefined, because there neither compiler is wrong and
the file records nothing worth holding.

The `.expected` files are recorded data committed beside their programs. There is
no generator script in the tree: a case is added by writing the pair and checking
both compilers print the recorded bytes.
