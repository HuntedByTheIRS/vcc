# goldens

A case here is a small C program and the exact stdout it has to print. The
program is compiled, run, and its output compared with the recorded file. A test
that only checks the exit status cannot see the day the compiler starts printing
7 where it used to print 9; a golden can.

## Layout

`NNNN-group-individual.c` pairs with `NNNN-group-individual.expected`.

- `NNNN` is a four-digit serial starting at `0000`, with no gaps.
- `group` is one of the tree's own areas: `tokenize`, `preprocess`, `parser`,
  `types`, `optimizer`, `printer`, `codegen`, `backend`, `image`, `link`,
  `driver`, `cli`.
- `individual` says what the case prints.

So `0013-link-libc-calls.c` is compiled, run, and its stdout must equal
`0013-link-libc-calls.expected`.

## What a case is

A small deterministic C program. It prints to stdout and exits `0`, and it reads
nothing that varies between runs: no clock, no file, no environment, no argument
order, no uninitialised memory. Two runs of the same binary print the same bytes.

## The comparison

`tools/regress.vsh` compiles each case with `-x c -std=gnu99 -w -lm`, runs it,
and compares its stdout with the `.expected` file byte for byte. The trailing
newline is part of the file, so output that agrees line for line but stops before
the last newline is still a failure. stdout and stderr go to separate files and
only stdout is compared.

## A missing .expected

A case without an `.expected` beside it cannot be checked. The runner treats that
as a failure ("no NNNN-....expected beside it"), not as a skip and not as a pass.
The bytes are the test, and without them there is no test.

## Where the bytes come from

The `.expected` file is the answer the C standard requires, not a transcript of
whatever vcc happened to print. Record it from a reference compile:

```sh
gcc -x c -std=gnu99 -w -lm 0013-link-libc-calls.c
```

then confirm the tree-built vcc prints the same bytes. A case where vcc disagrees
with gcc is a defect in the compiler: report it rather than committing vcc's
output as the expectation. A case must also stay clear of behaviour C leaves
implementation-defined or undefined, because there neither compiler is wrong and
the file records nothing worth holding.

The `.expected` files are recorded data committed beside their programs. There is
no generator script in the tree: a case is added by writing the pair and checking
both compilers print the recorded bytes.
