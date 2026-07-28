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
  a different spelling than `Uri.toString()` produces — **on Windows**. The
  *decisions* (allow / refuse) are cross-platform; the **conversions in the
  table above are Windows-specific**, because they exist to work around how
  `ShellExecuteW` reads a string. macOS hands `NSURL` the URL untouched and it
  parses correctly, measured: `file:///tmp/%ED%95%9C%EA%B8%80%ED%8C%8C%EC%9D%BC.txt`
  resolves to a real handler, where the same string would have to become a
  native path first on Windows.
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
  every arm runs on every runner, and macOS inherited it in #4 with no new code.
- `lib/src/backends/<os>/` answers (B). `shellTargetFor` is the Windows one; on
  macOS it is the identity, since `NSURL` parses the URL itself.
- **(A) must never become platform-specific, and (B) must never refuse *on
  policy grounds*.** Both are checkable against the diff, and either would be a
  finding.
- **(B) may still fail to marshal, and reports that as `UrlLaunchException`.**
  This is not a refusal — it is "I could not build the string this OS needs",
  which is the same category as the OS itself failing, and it is why both
  platforms answer it the same way: Windows when a `file:` URL has a query or
  fragment and cannot become a path, macOS when `NSURL` will not construct.
  Neither raises `UnsafeUrlError` (that is (A)'s alone) and — measured, and
  fixed after it was found to leak — neither raises `UnsupportedError`.
- **`UnsupportedError` means "this platform has no backend" and nothing else.**
  `Uri.toFilePath` raises it natively, so `shellTargetFor` catches and
  re-raises; letting it out would tell a caller on a supported platform that
  their platform is unsupported. Asserted directly in
  `test/windows/shell_target_test.dart`.
- `allowUnsafe: true` skips (A) only, and **(B)'s failure is exactly what it
  exposes.** An earlier version of this record claimed (B) "has nothing to opt
  out of", which was wrong: with (A) skipped, a `file:` URL carrying a query
  reaches (B) and fails there. That path is the only way to reach it.

### Evidence

Tests this reproduces:

| Claim | Test |
|---|---|
| every (A) arm | `test/url_safety_test.dart`, in full |
| (A) is platform-free | the same file — it has no platform guard and runs on every runner |
| every (B) arm, Windows | `test/windows/shell_target_test.dart`, in full |
| (B) never leaks `UnsupportedError` | the same file, *"never lets UnsupportedError out"* |
| (B) is the identity on macOS | `test/macos/macos_backend_test.dart`, *"hands NSWorkspace the URL as text, unchanged"* |
| (B) marshalling failure is `UrlLaunchException` | `shell_target_test.dart` (Windows) and `macos_backend_test.dart`, *"throws for a URL NSURL could not construct"* |
| the ordering — (A) before the backend | `test/url_launcher_test.dart`, *"the shape check is wired into the facade"* |
| (C) answers without launching | `test/windows/windows_backend_test.dart` and `test/macos/macos_backend_test.dart`, *"never launches anything on the way"* |
| (C) against the real OS | `test/macos/ns_workspace_integration_test.dart`, *"the real NSWorkspace handler lookup"* |

Measured with a positive control on Windows 11 (26200) — the same input, the
same process, the only difference being whether (A) ran:

```
ShellExecuteW('')            -> 42, a File Explorer window opened   [observed]
launchUrlSync(Uri.parse('')) -> UnsafeUrlError(noScheme), no window [observed]
```

Contradicted tests: none.

### What this does not cover

- **macOS — now measured (#4).** (B) is a **no-op** there: `NSWorkspace` is
  handed `url.toString()`, `[NSURL URLWithString:]` parses it, and there is no
  per-platform rewriting the way Windows needs for `file:` URLs. (A) is inherited
  unchanged and runs on every macOS launch, exactly as the "pure and
  platform-free" consequence above promised — no new code. The one macOS-specific
  outcome is `MacOpenOutcome.invalidUrl` (an `NSURL` that would not construct),
  which throws rather than refusing, so it lives in the (B) layer, not (A).
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
  | (A) | does this denote a target? | pure, cross-platform | yes — that is its job, as `UnsafeUrlError` |
  | (B) | what string does this OS need? | per platform | never on policy — but may fail to marshal, as `UrlLaunchException` |
  | (C) | is there anything to reach it with? | per platform | never — answers `false` |

  (C) is the one an OS may be unable to answer honestly. On Windows the launch
  path cannot: an unregistered scheme comes back as success. Reading the
  handler registry is what makes (C) answerable at all there, which is why it is
  a separate operation rather than something `launch` could report.

  **(C) is now answered on macOS too (#5), and it is not the same question.**
  Windows reads a per-**scheme** registry key; macOS asks LaunchServices
  (`URLForApplicationToOpenURL:`) which application would open **this exact
  URL**. Same signature, same meaning to a caller, genuinely different lookups —
  which is why the seam was named `canOpen(Uri)` rather than
  `schemeRegistered(String)`. The visible consequence: a `file:` URL is answered
  by its *extension's* handler on macOS, while Windows answers `true`
  unconditionally because `HKCR\file` always carries `URL Protocol`. Neither is
  wrong; (C) is a question about *this system*, and the two systems have
  different registries. Callers are told (C) means "something claims this", not
  "opening will succeed" — and that phrasing already covers the divergence.
