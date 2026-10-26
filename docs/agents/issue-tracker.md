# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues in
`kihyun1998/ffi_url_launcher`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Make an issue a sub-issue of a parent**: `gh issue create --parent <parent> ...`, or `gh issue edit <parent> --add-sub-issue <child>` afterwards (`gh` 2.94+). Older `gh`: `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>` (database id, as in **Blocking edges** below). Without sub-issues, put `Part of #<parent>` at the top of the child body.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run
inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be
either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

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

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (see **Make an issue a sub-issue of a parent**). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: as in **Blocking edges** above.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.

## Spine issues

A **spine** is a cluster anchor: one issue per artifact family, holding a
*hypothesis* rather than a decision — the suspected shared root, the sibling
roster, and what is explicitly not yet decided. Siblings link to it at filing
time. It promises nothing, so it is free to close as "one decision after all".
An issue in an area that already carries a decision record (`ls docs/adr/`) is a
**conformance item under that record**, never a sibling under a new spine — two
homes for one throughline is the failure a spine exists to prevent. A spine whose
siblings turn out to be one decision promotes to a record, as #8 became ADR-0001.

## History note

Tickets 01–07 were authored as files under `.scratch/ffi-url-launcher/issues/`
before this tracker was configured, and ticket 01 was implemented against the
files rather than against issue numbers — which is why its six commits reference
ticket paths instead of `Closes #n`. The files remain as the long-form design
record; the issues are the working surface. Later slices use `Closes #n`.
