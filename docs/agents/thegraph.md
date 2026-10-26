# thegraph build — ffi_url_launcher

## What this project is

A pure-Dart `dart:ffi` package that opens a URL in the OS's registered handler on
Windows and macOS; `CLAUDE.md` holds its identity and boundary.

## References

Read every source raw — the tree and the file through `gh api`, never a
summarizing fetch. The reference implementations are C++ and Swift, so their
correctness does not transfer: read them for which API to call and in what order,
and derive marshalling from the OS symbol's documentation and the siblings.

| Source | Informs | Reached by | Binding |
|---|---|---|---|
| `flutter/packages` `url_launcher_windows` `url_launcher_plugin.cpp`, `url_launcher_macos` `UrlLauncherPlugin.swift` | how it works — which OS API, in what order | its source tree — raw | example |
| `flutter/packages` `url_launcher/lib/src/url_launcher_uri.dart` | how it works — public API shape and naming | its source tree — raw | example |
| `flutter/packages` `url_launcher_web/lib/url_launcher_web.dart` (history: flutter/flutter#136657) | how it works — URL validation policy | its source tree — raw | example |
| Microsoft Learn, the symbol's own page | how it works — Win32 signature and ownership | the published docs — **summarized** | binding; a measurement outranks it |
| `package:win32` generated source | how it works — Win32 constants | its source tree — raw | binding |
| sibling `just_autostart` `lib/src/backends/windows/registry.dart` | how it works — hand-written `advapi32`, predefined handles | its source tree — raw | example |
| sibling `just_font_scan` `lib/src/macos/coretext_bindings.dart` | how it works — ObjC-runtime FFI, autorelease pool | its source tree — raw | example |
| siblings `just_autostart`, `flutter_inactive_timer` | where files go — pure-Dart package, OS-branching FFI | their source trees — raw | example |
| `https://pub.dev/api/packages/ffi_url_launcher` | published state | `curl` — raw | binding |

## Release

`pub-ready`
