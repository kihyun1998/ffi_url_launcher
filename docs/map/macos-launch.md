# macOS launch

## What it is
How a URL reaches the macOS shell: `[[NSWorkspace sharedWorkspace]
openURL:[NSURL URLWithString:url]]`, sent through the Objective-C runtime, and
the decoding of its `BOOL` into opened / not opened / invalid URL.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) › *What this does not
  cover* — (B) is a **no-op** on macOS: `NSWorkspace` is handed `url.toString()`
  and `NSURL` parses it. `invalidUrl` lives in (B), not (A).

## Design model
- **`NSWorkspace.open` returns a bare `BOOL`** with no error code, so
  `platformCode` is always `null` here — not invented for symmetry
  (`macos_backend.dart — MacosUrlLauncherBackend.launch`; `CLAUDE.md` contract).
- **`NO` is honest and reachable**, unlike the Windows launch `false`: measured
  on macOS 14.5 (arm64), both a scheme nothing handles and a `file:` URL for a
  missing file answer `NO` ([lessons.md](../agents/lessons.md) #8). So on macOS
  `launch` returning `false` genuinely means nothing opened it.
- **But `NO` does not mean nothing appeared.** For an unregistered scheme macOS
  raises a modal panel — *"there is no application set to open the URL"* —
  while still answering `NO`; `NSWorkspace` returns the boolean and
  `CoreServicesUIAgent` draws the panel, and neither observes the other. Only
  the missing-`file:` input is silent, so it is the only launch input a test or
  probe may use (`ns_workspace.dart — MacOpenOutcome.notOpened` dartdoc;
  lessons #8's correction, #9).
- **A probe once trusted this enum's earlier wording** — it claimed both inputs
  were silent — and drove the scheme input ~1,900 times, putting that many panels
  on the maintainer's screen ([lessons.md](../agents/lessons.md) #14). The
  dartdoc now says so.
- **`invalidUrl` is a fault, not a "no"**: an `NSURL` that will not construct
  throws `UrlLaunchException` rather than reading as "no handler". Near-unreachable
  through the public API, because `Uri.toString()` percent-encodes before `NSURL`
  is asked — see [macos-nsworkspace](macos-nsworkspace.md) for the SDK-dependent
  strict mode.
- **The seam replaces the decoded call**, `openUrl:`, so the outcome → result
  mapping can be driven from any host; the marshalling is exercised against the
  real frameworks in `test/macos/` (`MacosUrlLauncherBackend` constructor dartdoc).
- **Everything transient is created inside an autorelease pool** — see
  [macos-nsworkspace](macos-nsworkspace.md).
- Input bound: none — the URL string is handed to `NSString` whole.

## Code
- `lib/src/backends/macos/ns_workspace.dart — MacOpenOutcome`, `workspaceOpenUrl`, `_sharedWorkspace`, `_nsUrlFrom`
- `lib/src/backends/macos/macos_backend.dart — MacosUrlLauncherBackend.launch`, `MacosUrlLauncherBackend.openUrl`

## Reference behaviour
- `url_launcher_macos`'s `UrlLauncherPlugin.swift` for which call to make — an
  example ([thegraph.md](../agents/thegraph.md)). Swift's ARC hides the lifetimes
  this package has to manage by hand.

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [os-calls-stay-on-the-calling-thread](os-calls-stay-on-the-calling-thread.md)

## Blast radius
- [macOS Objective-C binding](macos-nsworkspace.md) — every message here is one of its bindings; a new message needs its own `objc_msgSend` signature there.
- [Proving OS effects](proving-os-effects.md) — the CI-safe input is the missing `file:` URL; a launch test with any other input puts a panel on screen.
- [Error model](error-model.md) — `invalidUrl` becomes `UrlLaunchException` with `platformCode: null`.
- [Windows launch](windows-shell-and-registry.md) — the same caller sees honest `false` here and effectively-never `false` there; the README's return-value table states both.

## Known holes / open
- **The success half is manual** ([proving-os-effects](proving-os-effects.md)).
