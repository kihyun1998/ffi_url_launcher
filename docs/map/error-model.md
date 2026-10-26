# Error model

## What it is
Everything the package throws: a sealed `UrlLauncherException` with two members,
`UnsafeUrlError` (the shape check refused) and `UrlLaunchException` (the OS
failed for a reason other than "nothing is registered"), plus the platform's
`UnsupportedError` and the `StateError` for an unreachable system library.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) — `UnsafeUrlError` is
  (A)'s alone; a (B) marshalling failure is `UrlLaunchException`; `UnsupportedError`
  means no backend.

## Design model
- **Sealed on purpose**: adding a failure mode makes the analyzer point at every
  exhaustive `switch` (`exceptions.dart — UrlLauncherException` dartdoc).
- **Refusal and failure are distinct types**, because "you handed me something
  that is not a URL" and "the system could not open this URL" want different
  handling (`UnsafeUrlError` dartdoc; `test/url_safety_test.dart`, *"is
  distinguishable from a launch failure"*).
- **`UrlLaunchException.target` is the string the OS was handed**, and it is the
  form a message shows — for a `file:` URL the native path, not the
  percent-encoded URL (`exceptions.dart — UrlLaunchException.target`;
  `test/exceptions_test.dart`, *"names the target the OS was given, not the
  encoded URL"*).
- **`platformCode` is nullable and always `null` on macOS**: `NSWorkspace`
  answers a bare `BOOL`, and a fabricated code would be worse than an absent one
  (`UrlLaunchException.platformCode` dartdoc; `CLAUDE.md` contract).
- **An unreachable system library is a `StateError`** — an environment fault,
  loud on purpose, because a class that did not resolve answers `NO` silently
  (`url_launcher_backend.dart — {@template platform_fault}`;
  [lessons.md](../agents/lessons.md) #9).
- `UnsafeUrlReason` lives here, not beside the check, so the dependency runs one
  way (`exceptions.dart — UnsafeUrlReason` dartdoc).

## Code
- `lib/src/exceptions.dart — UrlLauncherException`, `UnsafeUrlReason`, `UnsafeUrlError`, `UnsafeUrlError.toString`, `UrlLaunchException`

## Reference behaviour
- The reference surfaces the bare integer for a failure; flutter/flutter#138142
  asks for better messages — the reason `describeShellExecuteStatus` names codes
  (`shell_execute.dart` dartdoc). See [windows launch](windows-shell-and-registry.md).

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md)

## Blast radius
- [Public API](public-api.md) — the export list names these types; the dartdoc "Throws" lines list them.
- [URL shape check](url-shape-check.md) — each `UnsafeUrlReason` is one refusal arm; a reason added here needs its arm and its README row.
- [Windows launch](windows-shell-and-registry.md) — builds `UrlLaunchException` with a `platformCode` and a `target`.
- [macOS launch](macos-launch.md) — builds it with `platformCode: null`.
- [Publishing](publishing.md) — a new exception type is a public API change for the CHANGELOG.
- [Example](example.md) — it catches each type by name.

## Known holes / open
**None.**
