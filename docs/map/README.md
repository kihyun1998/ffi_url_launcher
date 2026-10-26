# Territory map

<!-- grill-map build stamp: none (the skills checkout is not a git repository) -->
<!-- grill-map synced at: 2ef7cc0 (2026-10-26) -->

The territory map of `ffi_url_launcher`. It answers the two questions that gate a
change:

- **If I touch this, what else moves?** Open the territory, read its
  `## Blast radius`, and follow each edge whose reason matches your change. Then
  read every note under its `## Cross-cutting invariants`.
- **What decision is this shape derived from?** Read the territory's
  `## Governing decisions`. A **None.** there is itself the answer: the shape
  comes from reading the source, not from a record.

A comment's why, trap and measured value go to a note here (`CLAUDE.md` ›
Comments).

## How to read it
- `## Blast radius` is a checklist. An edge with nothing to do for your change is
  a correct outcome.
- Every claim carries its evidence (a symbol, a test, a record, a `lessons.md`
  entry) or its source and date — `(maintainer, 2026-10-26)`, or a retired
  document at the commit it was carried from.
- Symbols, never line numbers. Plain relative links. A fact another artifact owns
  is linked, not restated. Empty sections stay, marked **None.**
- Source files, tests and issues are text inside notes, not nodes: the map cannot
  answer "what calls this symbol" — grep can.

## What the system does
A pure-Dart package that hands a URL to the OS's registered handler and answers
whether a handler exists, on Windows (`ShellExecuteW`, `HKEY_CLASSES_ROOT`) and
macOS (`NSWorkspace` through the Objective-C runtime). Every URL first passes a
cross-platform shape check (ADR-0001's (A)), then each OS gets the string it needs
(B), and the lookup (C) is a separate operation because Windows' launch path
cannot say "no handler". Around that sit the error model, the backend table, and
the quiet territories that rarely change and break silently: the dependency
invariant, the gates, publishing. The largest gap is the success half — no
automated test can see a browser open.

## Territories
- [Public API](public-api.md)
- [Backend selection](backend-selection.md)
- [URL shape check](url-shape-check.md)
- [Error model](error-model.md)
- [Windows launch](windows-shell-and-registry.md)
- [Windows handler lookup](windows-handler-lookup.md)
- [macOS launch](macos-launch.md)
- [macOS handler lookup](macos-handler-lookup.md)
- [macOS Objective-C runtime binding](macos-nsworkspace.md)
- [Proving an effect on the operating system](proving-os-effects.md)
- [Gates](gates.md)
- [Runtime dependencies](runtime-dependencies.md)
- [Publishing](publishing.md)
- [Example](example.md)

## Cross-cutting invariants
- [`false` means nothing is registered](false-means-nothing-registered.md)
- [`UnsupportedError` means no backend](unsupported-error-means-no-backend.md)
- [OS calls stay on the calling thread](os-calls-stay-on-the-calling-thread.md)
- [Platform libraries open lazily](platform-libraries-open-lazily.md)
- [System libraries load by absolute path](system-libraries-load-by-absolute-path.md)
- [The SDK floor is the one CI runs](sdk-floor-runs-in-ci.md)

## Scope
Everything under `lib/`, `example/`, `tool/` and `test/`, CI, and the published
surfaces. **Out of scope**: `docs/agents/` (agent configuration, not the system),
`.scratch/` design tickets (the decision trail — notes cite them), and Linux or
any other OS (no backend, by design; [backend selection](backend-selection.md)).

**An absent note means nothing in the repo commits to that area yet.** A
territory is owed a note when a decision record, a spec, or an open issue with a
design commits to it — a new platform, a new operation.
