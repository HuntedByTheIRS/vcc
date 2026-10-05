# Pure-V

The compiler is written in V and nothing else. No C source among the files it
is built from, no stage handed to a C compiler, no vendored C library. The
rule is the point of the project rather than a preference about it: vcc exists
so that the C compiler in V's build is a program V can build, read and patch
in V, and a step that delegates to a C compiler removes the property the
replacement is for.

Where a piece cannot be written in V yet, the piece stays unimplemented. The
compiler refuses the construct and names it, which is a worse answer than
working code and a better one than a C shortcut. [[C-Support]] lists what is
missing today; the in-house linker is the largest of them.

## Where C is allowed

Three directories hold C, and all three hold C the compiler is handed rather
than C it is built from: `compliance/` for the C99 conformance corpus,
`regression/` for one program per bug that must not come back, and `goldens/`
for the programs whose recorded output is compared byte for byte.

Those three are the whole exception. A `.v` file inside a test directory is
still this compiler's source, so the rule reaches there too. A fourth
directory in the tree is empty on purpose: `linking/` holds nothing, because
the linker that would be written in V has not been written.

## The one exception

`-external-linker=NAME` hands the final link to a linker the system already
has. It exists for the inputs this compiler cannot consume yet, a relocatable
object or an archive, so that linking behaviour is available before an
in-house linker is written. It is off by default, and with the flag unset
every refusal stands exactly as it does without it.

`NAME` may not be a C compiler. `cc`, `gcc`, `clang`, `c++` and `tcc` are
refused by name, because a C compiler finishing C compilation is the one thing
this rule exists to prevent. A tool that is missing, or that exits non-zero,
is reported rather than quietly falling back to the in-house path.

## What the gate checks

`v run tools/gate.vsh` enforces the part of the rule that text can show:

- A file ending in one of the C source extensions fails the gate wherever it
  sits, except under `compliance/`, `regression/` and `goldens/`. No other
  directory is exempt, `tools/` included, so a fixture a test needs is
  generated into a scratch directory when the test runs instead of committed.
- Every `.v` file outside `tools/` and `.omh/` is scanned for `#include `,
  `#flag ` and a two-character pattern, the language's name followed by a full
  stop. Any line that is not a full-line comment carrying one of them fails,
  which is why a standard is written `ISO C99` or `C23` in this tree and why
  prose about interop goes inside a comment. The scan covers a test directory
  too, because a `.v` file there is still this compiler's source.

The rest of the rule is not a text pattern. Nothing in the gate stops a script
from shelling out to an external tool, so what keeps the compiler pure V is a
person reading the change and the sentence in `AGENTS.md` that states the
rule. When a change cannot be made inside it, that sentence is what gets
amended, in the open, rather than worked around.

## See also

- [[C-Support]] for what the compiler reads, and what it refuses today.
- [[Interop]] for what V asks of a C compiler.
- [[The-Gate]] for the checks a change has to pass.
