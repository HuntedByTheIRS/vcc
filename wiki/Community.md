# Community

Where to ask and where to report, and the rules each place carries. The
sources behind this page are `DISCUSSIONS.md`, `ISSUES.md`, `CONTRIBUTING.md`,
`SECURITY.md` and `CODE_OF_CONDUCT.md`.

## Discussions or the tracker

Discussions are at <https://github.com/HuntedByTheIRS/vcc/discussions>. The
tracker is at <https://github.com/HuntedByTheIRS/vcc/issues>.

The line between them: the tracker is for work that can be closed, and a
discussion is for everything that is still moving. If the answer is "the
compiler should do X and does not", it is an issue. If the answer is a design
question, a direction, or a "what would you want here", it is a discussion.
When a discussion settles into a concrete piece of work, someone opens an
issue from it and links back, so the decision is findable from both sides.

A report about a specific failure goes to the tracker even if the report is
incomplete. `ISSUES.md` lists what to include, and a maintainer will move it
to Discussions if it belongs there. Bugs and feature requests go to the
tracker; open-ended questions belong in Discussions, where the answer can stay
a conversation.

## Discussion categories

| Category | What belongs there | Form |
|---|---|---|
| Announcements | Maintainer posts about a milestone, a release, an interface change, or a direction that moved. | `announcements.yml` |
| Design Proposals | A change to how the compiler is put together, argued while the shape is still moving. | `design-proposals.yml` |
| RFCs | The same change carried to a document: the command line, the C that is accepted, the diagnostics, the bytes written. Settled before the work lands. | `rfcs.yml` |
| Questions | How do I do this with vcc, why did it refuse this, what does this diagnostic mean. | `questions.yml` |
| Roadmap Discussion | The order of the milestones, and what a milestone should cover. | `roadmap-discussion.yml` |
| Compatibility | Where this compiler's answer differs from tcc's, gcc's, clang's, the standard's, or V's build's. | `compatibility.yml` |
| Off-topic/Extras | Anything that does not fit the others, including process questions and something built with vcc. | none, deliberately |

A form is offered when its file name matches the live slug of the category, so
`questions.yml` is the form for the Questions category; the slugs are read
back with the command in `DISCUSSIONS.md`. Questions is the question and
answer format, which is what lets an answer be marked accepted, and
Announcements is the announcement format, where only a maintainer can start a
discussion and anyone can comment. Off-topic/Extras has no form because a post
that fits nowhere in particular does not benefit from being asked for fields.

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

Do not file a vulnerability as an issue, and do not raise it in a public
discussion. The private route is
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
