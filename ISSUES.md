# Filing an issue

The tracker is at <https://github.com/HuntedByTheIRS/vcc/issues>. Bugs and
feature requests go there. Open-ended questions belong in
[DISCUSSIONS.md](DISCUSSIONS.md) instead, where the answer can stay a
conversation.

vcc is early. Most of C is unimplemented, on purpose, and the roadmap says so.
An error telling you a construct is not implemented yet is the compiler working
as designed, not a bug. The bugs worth filing are the other ones.

## Before you file

1. Search the existing issues, open and closed. Compiler bugs cluster, and a
   duplicate costs everyone a round trip.
2. Reduce the input. The smaller the file that still shows the problem, the
   faster it gets fixed. Delete lines until removing one more makes the problem
   go away, then keep that line.
3. Try the smallest thing that could work. `int main() { return 0; }` is the
   baseline: if that fails, the report is about the build or the environment,
   not about C.

## What a report needs

- The output of `vcc --version`.
- The commit you built from, if you built from source.
- Your OS, architecture, and the V version used to build vcc.
- The exact command you ran, flags and all.
- The input, small enough to paste.
- What you expected and what happened instead, with the exit status and the full
  error output.

Three shapes of report are common enough to describe on their own.

A miscompile is the compiler accepting the input and producing an artifact that
does the wrong thing. Say what the binary does, what it should do, and how you
know (the exit status, the printed value, the signal). A reduced input that
still miscompiles is worth more than a large one that does.

A bad diagnostic is the compiler rejecting something valid, or rejecting
something invalid with a message that misdescribes it. Paste the message, the
file and line it points at, and the language rule you think it gets wrong.

A crash is a panic, a hang, or a file that got written and should not have been.
Paste the panic output and, for a hang, the input that loops. Do not send a
200 MB file that hangs the compiler; find the line that does it.

## Performance reports

Speed matters here, so reports about it are welcome, and they need numbers. Say
what you compiled, with which flags, on which machine, and what the wall time
and peak memory were. `/usr/bin/time -v` gives both. `vcc -bench` gives the
per-phase split. A report that says "it feels slow" cannot be acted on, and a
report that names a phase and a number usually can.

## Out of scope

- Bugs in upstream TCC. This project replaces it, it does not track it.
- Bugs in the V compiler, or in V's generated C being invalid C. Reduce it and
  file it against V. If vcc is the thing that refuses valid C, that is ours.
- C that uses extensions no one has implemented yet. Those are roadmap items;
  file them as feature requests if the roadmap does not already cover them.
- Support for your program. vcc compiles C or it does not; it is not a build
  system and not a linker at this point.

## Security

Do not file a vulnerability as an issue. [SECURITY.md](SECURITY.md) says what
counts and where to send it.
