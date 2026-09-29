# Discussions

Discussions are at <https://github.com/HuntedByTheIRS/vcc/discussions>. The
tracker is for work that can be closed; a discussion is for everything that is
still moving. Asking in Discussions costs nothing and often saves an issue.

## Which category

| Category | Slug | What belongs there |
|---|---|---|
| Q&A | `q-a` | How do I do this with vcc, why did it reject this, what does this diagnostic mean. Answers can be marked accepted, so the answer stays on top. |
| Ideas | `ideas` | A direction for the project, or a piece of C support worth prioritizing. |
| General | `general` | Anything that does not fit the others, including process questions. |
| Show and tell | `show-and-tell` | Something you built with vcc, or a build you moved onto it. |
| Polls | `polls` | Votes on questions with a small number of real options. Used sparingly. |
| Announcements | `announcements` | Maintainer posts about milestones and releases. |

## Issue or discussion

If the answer is "the compiler should do X and does not", it is an issue. If the
answer is a design question, a direction, or a "what would you want here", it is
a discussion. When a discussion settles into a concrete piece of work, someone
opens an issue from it and links back, so the decision is findable from both
sides.

Reports about a specific failure go to the tracker even if the report is
incomplete. [ISSUES.md](ISSUES.md) has the list for what to include, and a
maintainer will move it to Discussions if it belongs there.

## A few house rules

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
