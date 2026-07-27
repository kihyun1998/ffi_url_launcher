# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those
roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the
corresponding label string from this table.

## What separates `ready-for-agent` from `needs-triage` here

Not urgency — **evidence**. `ready-for-agent` means the finding was reproduced
by whoever filed it and the fix is specified. `needs-triage` means it came from
a report (a completeness pass, a subagent, a user) and has **not** been
reproduced, so the first job is confirming it exists. theflow's rule that a
subagent's probe is a candidate rather than a finding is what this distinction
encodes: dropping such a candidate silently loses real defects, and promoting it
silently files unverified claims.

## Label availability

`wontfix` already exists in this repo (a GitHub default label). The other four
were created with `gh label create <name> --description "..."`.
