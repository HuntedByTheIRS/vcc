# Community

Where to ask and where to report, and the rules each place carries. The
sources behind this page are `DISCUSSIONS.md`, `ISSUES.md`, `CONTRIBUTING.md`,
`SECURITY.md` and `CODE_OF_CONDUCT.md`.

## The tracker

Everything goes to <https://github.com/HuntedByTheIRS/vcc/issues>. Discussions
were turned off and folded into it: an issue carries the same conversation and
can be closed, which is what a maintainer wants out of a thread.

A question is an issue labeled `question`, and a direction for the project is
one labeled `enhancement`. `ISSUES.md` lists what a report has to include. A
report about a specific failure goes in even when it is incomplete, and a
maintainer will ask for whatever is missing.

## Where the discussion forms went

Six forms were written for the categories that wanted structure, and they are
still in the repository under `.github/DISCUSSION_TEMPLATE/`. Nothing offers
them while Discussions is off; they are the material an issue form would be
made from. `DISCUSSIONS.md` carries the table of what each one asked for.

Off-topic/Extras had no form on purpose, and Questions was the answerable
format, which is what let a reply be marked accepted and stay on top. An issue
has no such mark, and that is the one thing the move gives up.

## House rules for a proposal

vcc is written in pure V and has to stay at TCC-class speed. A proposal that
needs a C dependency, or that trades the speed target away for convenience, is
arguing against the two constraints this project exists to satisfy. Say why it
is worth it anyway if you think it is.

Bring numbers for anything about performance. Compiling the C that V generates
for its own build is the benchmark that decides. `ISSUES.md` adds that a
report which says "it feels slow" cannot be acted on, while one that names a
phase and a number usually can.

Quote the error output and the version you are on. `vcc --version` and the
commit hash answer most "which build is this" questions in one line.

## Reporting a vulnerability

Do not file a vulnerability as an issue, and do not post it anywhere public.
The private route is
<https://github.com/HuntedByTheIRS/vcc/security/advisories/new>. Private
reporting is enabled on the repository. If GitHub is not usable, email
huntedbyth3irs@gmail.com, the address the repository's commits carry.
`SECURITY.md` says what counts as a vulnerability in a compiler and what does
not. Expect an acknowledgment within a few days, an assessment of scope and
severity, and a fix on `main`.

## Response times

This is a small project with one maintainer. Questions tend to get answered in
days rather than hours, and a report with a reduced input tends to get
answered faster than one without.

## Conduct

How people are expected to treat each other is in `CODE_OF_CONDUCT.md`,
adapted from Contributor Covenant 2.1. Instances of unacceptable behavior may
be reported to the community leaders at huntedbyth3irs@gmail.com, and
complaints are reviewed promptly and fairly.
