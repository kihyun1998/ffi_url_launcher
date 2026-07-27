# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues in
`kihyun1998/ffi_url_launcher`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run
inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

GitHub shares one number space across issues and PRs, so a bare `#42` may be
either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Blocking edges

GitHub's **native issue dependencies** — the canonical, UI-visible
representation. Add an edge with:

```
gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by \
  -F issue_id=<blocker-db-id>
```

where `<blocker-db-id>` is the blocker's numeric **database id**
(`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, *not* the `#number` or the
`node_id`). GitHub reports `issue_dependencies_summary.blocked_by`, counting
open blockers only — that is the live gate. Where dependencies are unavailable,
fall back to a `Blocked by: #<n>, #<n>` line at the top of the body. A ticket is
unblocked when every blocker is closed.

## Spine issues

A **spine** is a cluster anchor: one issue per artifact family, holding a
*hypothesis* rather than a decision — the suspected shared root, the sibling
roster, and what is explicitly not yet decided. Siblings link to it at filing
time. It promises nothing, so it is free to close as "one decision after all".
See `theflow.md` for when one is opened and when it promotes to a decision
record.

## History note

Tickets 01–07 were authored as files under `.scratch/ffi-url-launcher/issues/`
before this tracker was configured, and ticket 01 was implemented against the
files rather than against issue numbers — which is why its six commits reference
ticket paths instead of `Closes #n`. The files remain as the long-form design
record; the issues are the working surface. Later slices use `Closes #n`.
