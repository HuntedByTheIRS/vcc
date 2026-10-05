# Discussions

Discussions are off on this repository. The space is folded into the tracker,
where a thread can be closed and where the work it settles into already lives.

Questions, design arguments and half-formed ideas go to
<https://github.com/HuntedByTheIRS/vcc/issues>, labeled `question` for a question
and `enhancement` for a direction. [ISSUES.md](ISSUES.md) says what a report has
to carry. A vulnerability does not go in the tracker at all;
[SECURITY.md](SECURITY.md) says where it goes.

## The six forms, kept for the move

They are still in `.github/DISCUSSION_TEMPLATE/` and nothing offers them while
Discussions is off. Each row is a category that wanted structure, and the shape
its issue form should take when the move happens.

| Was | What belonged there | File |
|---|---|---|
| Announcements | Maintainer posts about a milestone, a release, an interface change, or a direction that moved. | `announcements.yml` |
| Design Proposals | A change to how the compiler is put together, argued while the shape is still moving. | `design-proposals.yml` |
| RFCs | The same change carried to a document: the command line, the C that is accepted, the diagnostics, the bytes written. Settled before the work lands. | `rfcs.yml` |
| Questions | How do I do this with vcc, why did it refuse this, what does this diagnostic mean. | `questions.yml` |
| Roadmap Discussion | The order of the milestones, and what a milestone should cover. | `roadmap-discussion.yml` |
| Compatibility | Where this compiler's answer differs from tcc's, gcc's, clang's, the standard's, or V's build's. | `compatibility.yml` |

Off-topic/Extras never had a form on purpose: a post that fits nowhere in
particular does not benefit from being asked for fields, and nothing written for
it is lost by the space closing.

Questions was the answerable format, so a reply could be marked accepted and
stay on top of the thread. An issue has no such mark, and that is the one thing
the move gives up.

## House rules

- vcc is written in pure V and has to stay at TCC-class speed. A proposal that
  needs a C dependency, or that trades the speed target away for convenience,
  is arguing against the two constraints this project exists to satisfy. Say why
  it is worth it anyway if you think it is.
- Bring numbers for anything about performance. Compiling the C that V generates
  for its own build is the benchmark that decides.
- Quote the error output and the version you are on. `vcc --version` and the
  commit hash answer most "which build is this" questions in one line.

## Response times

This is a small project with one maintainer. Questions tend to get answered in
days rather than hours, and a report with a reduced input tends to get answered
faster than one without.
