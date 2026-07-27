# ADR-0001 — Every URL is asked two independent questions, in order

**Status:** accepted
**Promoted from:** spine #8, *nothing normalises a URL before it reaches the shell*
**Conformance items:** #2 (the shape check), #9 (empty URL), #1 (`file:` decoding, closed)

## Context

This package hands a string to an operating-system call. Between a caller's
`Uri` and that call, eight separate decisions have been made, each arriving as
fresh work:

| | Case | Decision taken |
|---|---|---|
| 1 | `file:` URL with percent-encoded non-ASCII | convert to a native path (#1) |
| 2 | empty or blank URL | refuse (#2, #9) |
| 3 | `C:\…` — a drive letter parses as a one-letter scheme | refuse (#2) |
| 4 | `file:`, `file://`, `file:///` — names nothing | refuse (#2) |
| 5 | `file:///C:/a.txt?q=1` — query or fragment | refuse (#2) |
| 6 | `file://server/share/x` — an authority | allow, convert to `\\server\share\x` (#1) |
| 7 | `file:///nodrive/x` — rooted, no drive | allow |
| 8 | `shell:`, `search-ms:`, and any scheme that executes | allow — a whitelist was refused `[product]` |

Two of theflow's promotion triggers fired on the completeness pass for #2: an
earlier issue's stated premise measured false (twice — #6's planned CI assertion,
and #1's documentation of `UnsupportedError` as meaning "no backend for this
platform" while a malformed `file:` URL raised the same type). Eight decisions
and no written model is what that count means: the state space is combinatorial
and every new combination has been arriving as its own judgement.

## Decision

**Every URL is asked two questions, in this order, and they are never mixed.**

> **(A) Does this URL denote a target?**
> A question about *shape*. Asked on the `Uri`, cross-platform, before anything
> else. Failing it means refusing — the caller handed over something that names
> nothing, or that names a local file while claiming to be a URL.
>
> **(B) What exact string does *this* operating system need in order to reach
> that target?**
> A question about *marshalling*. Asked per platform, only after (A) passes.
> It may transform the string freely. It never refuses.

Neither question asks whether a URL is **trustworthy**. That is the caller's,
by the boundary rule in `CLAUDE.md`, and it is why (A) admits
`file:///C:/Windows/System32/calc.exe`.

### The eight decisions fall out of it

- **(A) fails → refuse:** 2, 3, 4, 5. None of them denotes a target: the empty
  string and a bare filename name nothing; `C:\…` names a local file; `file:`
  normalises to the current drive's root, which is *a* place but not one the
  caller asked for; a `file:` URL with a query has no path to extract.
- **(A) passes, (B) transforms:** 1, 6, 7. Each denotes a target and each needs
  a different spelling than `Uri.toString()` produces.
- **(A) passes, trust is not our question → allow:** 8, and
  `file:///…/calc.exe`.

### It resolves cases nobody has decided yet

A desktop analogue of the web implementation's `javascript:` block: (A) passes —
it denotes a target — and refusing it would be a trust judgement, so it is
allowed and the caller's whitelist is where it belongs. A new OS with a
different path spelling: (B) only. A URL form that resolves to somewhere the
caller did not name: (A). **No new case needs a new decision; it needs the two
questions asked.**

## Consequences

These are currently-true statements, not predictions. Flip them if the decision
flips.

- `lib/src/url_safety.dart` answers (A). It is **pure and platform-free**, so
  every arm runs on every runner and #4 inherits it on macOS without new work.
- `lib/src/backends/<os>/` answers (B). `shellTargetFor` is the Windows one.
- **(A) must never become platform-specific, and (B) must never refuse.** Both
  are checkable against the diff, and either would be a finding.
- Because (A) runs first, `Uri.toFilePath`'s `UnsupportedError` cannot escape
  the public API — the type is reserved for "this platform has no backend".
- `allowUnsafe: true` skips (A) only. (B) still runs; it has nothing to opt out
  of.

### Evidence

Tests this reproduces: `test/url_safety_test.dart` in full (every (A) arm),
`test/windows/shell_target_test.dart` in full (every (B) arm), and
`test/url_launcher_test.dart`'s *"the shape check is wired into the facade"*
group (the ordering).

Measured with a positive control on Windows 11 (26200) — the same input, the
same process, the only difference being whether (A) ran:

```
ShellExecuteW('')            -> 42, a File Explorer window opened   [observed]
launchUrlSync(Uri.parse('')) -> UnsafeUrlError(noScheme), no window [observed]
```

Contradicted tests: none.

### What this does not cover

- **macOS.** `NSWorkspace` takes an `NSURL`, not a string, so (B) may be a
  no-op there or may not exist. (A) is unchanged either way. Unmeasured until #4.
- **Trust policy.** Deliberately outside both questions.
- **`canLaunchUrl` — a third question, and #3 has now answered it.** *Is there
  anything to reach the target with?* It is genuinely separate from (A) and (B),
  and shipping it did not disturb either: the shape check runs first for both
  operations (one gate, both doors), and the registry read is a (B)-layer
  platform mechanism that, like `shellTargetFor`, never refuses — "no handler"
  is an answer it returns, not a refusal it raises.

  So the record's shape survived contact with the third question rather than
  needing to absorb it. What is worth stating is where the three sit:

  | | Question | Layer | Refuses? |
  |---|---|---|---|
  | (A) | does this denote a target? | pure, cross-platform | yes — that is its job |
  | (B) | what string does this OS need? | per platform | never |
  | (C) | is there anything to reach it with? | per platform | never — answers `false` |

  (C) is the one an OS may be unable to answer honestly. On Windows the launch
  path cannot: an unregistered scheme comes back as success. Reading the
  handler registry is what makes (C) answerable at all there, which is why it is
  a separate operation rather than something `launch` could report.
