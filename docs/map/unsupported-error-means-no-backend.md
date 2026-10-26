# `UnsupportedError` means "no backend for this platform"

## The fact
`UnsupportedError` leaves this package for exactly one reason: the operating
system has no backend. No other path may let one out.

## Why it is cross-cutting
The public dartdoc promises it (`ffi_url_launcher.dart — launchUrl`, "Throws …
[UnsupportedError] on a platform with no backend"), but `Uri.toFilePath` raises
the same type natively for a `file:` URL with a query or fragment. Two
independent sites keep that native one in: the shape check refuses those URLs
first, and the Windows marshalling catches and re-raises it for a caller who
passed `allowUnsafe: true`. Neither calls the other. Remove either and a caller
on a supported platform is told their platform is unsupported.

## Territories it holds in
- [Public API](public-api.md) — `ffi_url_launcher.dart — launchUrl` / `canLaunchUrl` dartdoc: the promise itself.
- [Backend selection](backend-selection.md) — `unsupported_backend.dart — UnsupportedUrlLauncherBackend.launch` / `canOpen`: the one legitimate source.
- [URL shape check](url-shape-check.md) — `url_safety.dart — _namesAFile`: a query or fragment fails (A) as `UnsafeUrlReason.notAFilePath`.
- [Windows launch](windows-shell-and-registry.md) — `shell_execute.dart — shellTargetFor`: `on UnsupportedError` → `UrlLaunchException`.
- [Error model](error-model.md) — `exceptions.dart — UnsafeUrlReason.notAFilePath`'s dartdoc names this reason.

## What a violation looks like
`launchUrl(Uri.parse('file:///C:/a.txt?q=1'), allowUnsafe: true)` on Windows
raising `UnsupportedError`. Asserted against by
`test/windows/shell_target_test.dart`, *"never lets UnsupportedError out, on any
file URL shape"*.

## Discovery history
- Found leaking and fixed; recorded in
  [ADR-0001](../adr/0001-two-questions-about-every-url.md) Consequences ("measured,
  and fixed after it was found to leak").

## Where it will recur
Any new call into `dart:core` / `dart:io` on a launch or lookup path that can
raise `UnsupportedError` (`Uri.toFilePath`, `Uri.toFilePath(windows:)`, an
unimplemented platform API) is subject to this: catch and re-raise it as a launch
failure.
