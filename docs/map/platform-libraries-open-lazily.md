# Platform libraries open lazily

## The fact
No platform library is opened, and no platform symbol looked up, until an
operation on that platform actually runs. Every binding sits in a top-level
`final`, which Dart initialises on first read.

## Why it is cross-cutting
Every backend file is compiled into the package on every OS. What keeps
`shell32.dll` from being opened on macOS — and `libobjc` on Windows — is not a
guard but the laziness of each top-level `final`, kept separately in each binding
file, plus the facade's own `_default`. Turning any one into an eager read (a
`static` initialiser touched at import, a binding resolved in a constructor)
fails on the other OS at load.

## Territories it holds in
- [Public API](public-api.md) — `ffi_url_launcher.dart — _default`: `Platform.operatingSystem` is not read until something launches.
- [Backend selection](backend-selection.md) — `supported_platforms.dart — supportedPlatforms`: `create` is a factory, so a backend is built only on the platform that asked.
- [Windows launch](windows-shell-and-registry.md) — `shell_execute.dart — _shell32`, `_shellExecuteW`.
- [Windows handler lookup](windows-handler-lookup.md) — `scheme_registry.dart — _advapi32` and its three bindings.
- [macOS Objective-C binding](macos-nsworkspace.md) — `objc.dart — _objc`, the classes and selectors.

## What a violation looks like
Importing the package on the other OS throws an `ArgumentError` from
`DynamicLibrary.open`. The off-host tests (`test/url_launcher_platform_test.dart`
runs both runners) would go red on the runner that lacks the library.

## Discovery history
- Stated beside each binding (comments in `shell_execute.dart`,
  `scheme_registry.dart`, `objc.dart`, `system32.dart`; reading, 2026-10-26).
- The same laziness once hid a load: a probe held AppKit in a lazy `final` that
  nothing read, so it never loaded ([`lessons.md`](../agents/lessons.md) #9).
  That is why `objc.dart — _classInAppKit` opens AppKit directly instead.

## Where it will recur
Any new binding file, and any new platform: if it opens a library, it does so
from a top-level `final` read only on that platform's path. A lazy `final` that
must *cause* a side effect (loading a framework) is the opposite case — open it
on the path that is checked.
