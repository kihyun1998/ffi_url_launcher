# URL shape check

## What it is
Question (A): does this URL denote a target, or is it a local path wearing a
URL's clothes? A pure, platform-free function that refuses a URL with no scheme,
a one-letter scheme, or a `file:` URL that names no file, before any OS is asked.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) — this is (A); it must
  never become platform-specific.
- **A scheme whitelist was weighed as a default and declined `[product]`** — what
  counts as acceptable differs per application, so owning that list would be the
  package absorbing a consumer's concern (maintainer; recorded in `CLAUDE.md` and
  in the retired `theflow.md` Step 2, carried at 2ef7cc0, 2026-10-26).
- **The check is on by default `[product]`** — that `Uri.parse(r'C:\...')` yields
  a one-letter scheme `ShellExecuteW` executes is knowledge of how these OS calls
  read a string, which a caller cannot be expected to have; leaving it to them is
  a trap with the package's name on it (same sources).

## Design model
- **A shape check, never a trust check.** It answers *does this denote a local
  path?* Trust, whether `file:` is allowed, and any whitelist are the caller's
  (`url_safety.dart — checkUrlShape` dartdoc). `allowUnsafe: true` is where the
  caller decides whether it applies.
- **Partial by design, and says so.** `file:///C:/Windows/System32/calc.exe`
  passes and executes — `file:` is a legitimate desktop feature the reference
  supports. What is not blocked is documented beside what is, because a partial
  guard described as "validated" moves the caller's belief without moving their
  risk (`checkUrlShape` dartdoc; README › Security table;
  `test/url_safety_test.dart`, *"file URLs — deliberately, and this is an
  execution vector"*).
- **Three refusals** (`exceptions.dart — UnsafeUrlReason`):
  - `noScheme` — no scheme at all. A UNC path (`\\host\share\x.exe`), a bare
    filename and the empty string all land here. The empty string is not
    theoretical: `ShellExecuteW('')` answers success and opens File Explorer.
  - `driveLetter` — a one-letter scheme. `Uri.parse(r'C:\Windows\System32\calc.exe')`
    yields `scheme == 'c'`, `hasScheme == true`, and `ShellExecuteW` accepts the
    forward-slashed form and executes it.
  - `notAFilePath` — `file:`, `file://`, `file:/`, `file:///` normalise to
    `file:///`, which converts to a bare `\`: an existing directory, the root of
    the current drive. A query or fragment means there is no path to extract.
- **The two path hazards need two checks.** A drive path parses *with* a scheme
  and a UNC path *without* one, so either check alone leaves a hole (re-verified:
  `checkUrlShape`'s first two rules).
- **A `file:` URL with an authority is allowed**: the host names a target
  (`url_safety.dart — _namesAFile`).

### Every cheap "yes" answers a narrower question

Each surface returns an affirmative a caller will read as an answer to a broader
question. Every guard states which question it answers, in its own dartdoc;
when a pass finds another, add the row.

| The affirmative | What it actually means | What the caller reads it as | Evidence |
|---|---|---|---|
| `Uri.parse` succeeded, `hasScheme` is true | the string has a colon in it | "this is a URL, not a local path" | `UnsafeUrlReason.driveLetter` dartdoc |
| `canLaunchUrl` returned true | a handler is registered for the scheme (Windows) or this URL (macOS) | "`launchUrl` will succeed" | `{@template can_open_contract}` |
| `ShellExecuteW` returned > 32 | the shell accepted the request — an unregistered scheme answers 42 | "the URL opened" | [lessons.md](../agents/lessons.md) #4 |
| `NSWorkspace.open` returned YES | the handler was started | "the page loaded" | `MacOpenOutcome.opened` dartdoc |

The cheap "no" runs the other way — see [proving-os-effects](proving-os-effects.md).

## Code
- `lib/src/url_safety.dart — checkUrlShape`, `_namesAFile`
- `lib/src/exceptions.dart — UnsafeUrlReason`
- `lib/src/url_launcher.dart — UrlLauncher.launchUrlSync`, `UrlLauncher.canLaunchUrlSync` (the call sites)

## Reference behaviour
- `url_launcher_web` is the only implementation in the family that blocks a
  scheme, and it chose a blocklist returning `false` with a warning — not a
  whitelist, not a throw ([thegraph.md](../agents/thegraph.md), "URL validation
  policy" row; flutter/flutter#136657). The desktop references pass the string
  through unvalidated; this package rejected that passthrough because the hole
  was measured.

## Cross-cutting invariants
- [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md)

## Blast radius
- [Windows launch](windows-shell-and-registry.md) — `shellTargetFor` assumes a `file:` URL that reaches it names a file; a refusal dropped here reaches the shell, or reaches `toFilePath`'s `UnsupportedError`.
- [Error model](error-model.md) — each refusal is an `UnsafeUrlReason`; a new arm needs its reason and its message.
- [Publishing](publishing.md) — the README's blocked / not-blocked table must match the arms exactly; it is the caller's only account of the partial guard.
- [Public API](public-api.md) — the `allow_unsafe` template restates what is refused.
- [macOS handler lookup](macos-handler-lookup.md) and [Windows handler lookup](windows-handler-lookup.md) — the check runs before the lookup too, so a refusal changes what `canLaunchUrl` can answer.

## Known holes / open
- **The `allow_unsafe` template under-describes the check.** It says the check
  refuses "no scheme at all, or a one-letter scheme"
  (`url_launcher.dart — {@template ffi_url_launcher.allow_unsafe}`), but
  `checkUrlShape` also refuses a `file:` URL that names no file
  (`UnsafeUrlReason.notAFilePath`). The README table is complete; the dartdoc,
  which ships as the API reference, is not (reading, 2026-10-26).
- `file:///…/calc.exe` executes, by design. Whether a caller should allow `file:`
  is theirs; the package states it and stops.
- A blocked string never reaching the shell is proven by the facade tests with a
  fake backend; the retired `theflow.md` asked for it to be proven once by hand
  against a real launch. Whether that was done is not recorded.
