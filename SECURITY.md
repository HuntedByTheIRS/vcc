# Security policy

## Supported versions

Nothing has been released. `main` is the only build that exists, and it is a
stub, so there is no version of vcc anyone should be running in a situation
where security matters.

| Version | Supported |
|---|---|
| `main` (unreleased) | Development only. Fixes land here; nothing is backported because there is nothing to backport to. |
| Tagged releases | None yet. |

That table will get more interesting when the first release exists. Until then,
treat every report as a development-tree bug and expect a fix on `main` rather
than a patch release.

## What counts as a vulnerability here

vcc is a compiler: it reads untrusted text and writes a binary. That gives it a
different threat surface from an application, and a shorter one.

- A silent miscompilation is input that is valid C, accepted without a
  diagnostic, producing an artifact that behaves differently from what the
  source says. This is the worst thing a compiler can do, and a way to get a
  vulnerable program from a source file that a reviewer read and approved. A
  miscompile that only shows up under unusual input is still this.
- Code execution or file access driven by the compiler is a crafted C input, or a
  crafted command line, that makes vcc execute a program, read a file it was
  never asked to read, or write outside the output path. Include the preprocessor
  once it exists: includes, macro expansion, and pragma handling are where a
  compiler starts touching files the input names.
- Memory unsafety in the compiler itself: vcc is written in V with bounds
  checking, but the back end does raw pointer arithmetic and offset math, and a
  hand-written ELF writer is exactly where an integer overflow turns into a bad
  write. A crash on well-formed input is a bug to file as an issue; a crash from
  input that reaches outside the compiler's own memory is this category.
- Input parsing with a bad trust boundary, once linking exists. Object files and
  archives are attacker-shaped data, and parsing ELF or `ar` containers is the
  classic route from "compile this" to "run this".
- Reproducibility failures with a security consequence: output that changes
  between runs of the same input and flags, in a way that lets one build differ
  from the build someone verified.

## What does not count

- Bugs in upstream TCC, in the V compiler, or in the Linux kernel.
- Anything about the program vcc produces. A compiler is not a sandbox: it
  compiles whatever you point it at, and a program with a vulnerability written
  in C has that vulnerability after vcc compiles it.
- Resource exhaustion from input you chose to hand a compiler that does not
  claim to be hardened. A 2 GB translation unit is your problem.
- Unimplemented C, however surprising the diagnostic is. That is a feature
  request or an issue, not a vulnerability.
- Missing hardening flags, or a refusal to compile code that would need them.

## Reporting

Privately, through GitHub's private vulnerability reporting:

<https://github.com/HuntedByTheIRS/vcc/security/advisories/new>

Private reporting is enabled on this repository. Use it rather than a public
issue, and rather than a public discussion, for anything in the list above. If
you cannot use GitHub, email huntedbyth3irs@gmail.com, which is the address this
repository's commits carry.

A useful report has the same shape as a good bug report
([ISSUES.md](ISSUES.md)) with one addition: say what an attacker gets out of it.
An input plus the artifact it produced, and a sentence about what that artifact
does differently from what the source says, is the whole report.

What to expect: an acknowledgment within a few days, an assessment of whether it
is in scope and how severe it looks, and a fix on `main` with the advisory
published once it is out. Credit in the advisory unless you would rather not be
named.

## This policy is about a stub

Most of what is listed above cannot happen yet, because the compiler does not do
enough for it to happen. The list is one thing that grows with the compiler, and
it is worth writing down before the code that makes it true exists.
