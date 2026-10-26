# macOS handler lookup

## What it is
Question (C) on macOS: is anything registered to open this URL? Answered by
`[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:]`, which names the
application that would open this exact URL, or `nil`.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) › *What this does not
  cover* — (C) on macOS is asked per URL, not per scheme; same signature, same
  meaning to a caller, a different lookup.

## Design model
- **Per URL, where Windows answers per scheme.** Measured on macOS 14.5, agreeing
  with the same question asked from Swift: `https:` → Google Chrome, `mailto:` →
  Mail, `file:` → TextEdit, an unregistered scheme → `nil`
  (`ns_workspace.dart — workspaceCanOpenUrl` dartdoc). So a `file:` URL is
  answered by its *extension's* handler here, while Windows always answers
  `true`. This is why the seam is `canOpen(Uri)` and not
  `schemeRegistered(String)` (`macos_backend.dart — MacosUrlLauncherBackend.canOpen`).
- **A lookup, not an attempt**: it starts nothing and shows nothing for any input,
  including the scheme that raises a panel on launch — so its integration test may
  assert live what the launch test must skip. The CI hazard belongs to the
  operation, not the URL (`workspaceCanOpenUrl` dartdoc).
- **An `NSURL` that will not construct answers `false`**: nothing can open what
  does not parse, and there is no faulted operation to report
  ([false-means-nothing-registered](false-means-nothing-registered.md)).
- **The returned `NSURL` is autoreleased and not owned** — it comes from a
  `URLFor…` accessor, not `copy`/`create`, so it must not be released; the pool
  bounds it ([macos-nsworkspace](macos-nsworkspace.md)).
- **It is the current API**: the pure-C `LSCopyDefaultApplicationURLForURL` was
  deprecated in macOS 12, and the reference asks exactly this
  (`workspaceCanOpenUrl` dartdoc).
- Input bound: none.

## Code
- `lib/src/backends/macos/ns_workspace.dart — workspaceCanOpenUrl`
- `lib/src/backends/macos/macos_backend.dart — MacosUrlLauncherBackend.canOpen`, `MacosUrlLauncherBackend.canOpenUrl`

## Reference behaviour
- `url_launcher_macos` asks `workspace.urlForApplication(toOpen:) != nil`
  ([thegraph.md](../agents/thegraph.md)). The Swift cross-read is the reader
  that caught [lessons.md](../agents/lessons.md) #9.

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [os-calls-stay-on-the-calling-thread](os-calls-stay-on-the-calling-thread.md)

## Blast radius
- [macOS Objective-C binding](macos-nsworkspace.md) — the lookup's positive answer is what proves AppKit was really loaded; without it every negative is indistinguishable from a class that never resolved.
- [Proving OS effects](proving-os-effects.md) — *"finds the application registered for a common scheme"* is the positive the macOS suite relies on (ADR-0002 question 1).
- [Gates](gates.md) — the compile-exe consumer's `true` for `https:` rests on this lookup working under AOT.
- [Windows handler lookup](windows-handler-lookup.md) — per URL here, per scheme there; "aligning" them changes what `canLaunchUrl` means on one OS.

## Known holes / open
**None.**
