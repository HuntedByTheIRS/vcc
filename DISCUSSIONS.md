# Discussions

Discussions are at <https://github.com/HuntedByTheIRS/vcc/discussions>. The
tracker is for work that can be closed; a discussion is for everything that is
still moving. Asking in Discussions costs nothing and often saves an issue.

## Which category

| Category | What belongs there | Form |
|---|---|---|
| Announcements | Maintainer posts about a milestone, a release, an interface change, or a direction that moved. | `announcements.yml` |
| Design Proposals | A change to how the compiler is put together, argued while the shape is still moving. | `design-proposals.yml` |
| RFCs | The same change carried to a document: the command line, the C that is accepted, the diagnostics, the bytes written. Settled before the work lands. | `rfcs.yml` |
| Questions | How do I do this with vcc, why did it refuse this, what does this diagnostic mean. | `questions.yml` |
| Roadmap Discussion | The order of the milestones, and what a milestone should cover. | `roadmap-discussion.yml` |
| Compatibility | Where this compiler's answer differs from tcc's, gcc's, clang's, the standard's, or V's build's. | `compatibility.yml` |
| Off-topic/Extras | Anything that does not fit the others, including process questions and something you built with vcc. | none, deliberately |

The forms are in `.github/DISCUSSION_TEMPLATE/`, and a form's file name is the
live slug of its category, so `questions.yml` is the form for
`/discussions/categories/questions`. A category whose name is changed in the
repository's discussion settings needs the file renamed to match, or the form
quietly stops being offered. The slugs in use:

```sh
gh api graphql \
  -f query='query{repository(owner:"HuntedByTheIRS",name:"vcc"){discussionCategories(first:50){nodes{name slug isAnswerable}}}}'
```

Two of the categories are a format rather than only a topic. Questions is the
question and answer format, which is what lets an answer be marked accepted and
stay on top. Announcements is the announcement format, where only a maintainer
can start a discussion and anyone can comment on one, which is what keeps the
category to news from the project itself.

Off-topic/Extras has no form on purpose. A post that fits nowhere in particular
does not benefit from being asked for fields, and the category is the one place
here where a blank box is the right box.

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
