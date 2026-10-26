# `false` means nothing is registered

## The fact
Every public operation answers `false` only for "nothing on this system is
registered to open this URL", and raises a typed exception for every other
failure. One stated exception: the Windows registry lookup answers `false` when
the registry read itself fails, because a caller asking *can this be opened* is
not asking to be told the registry was busy (maintainer, 2026-10-26; the same
reasoning is in `scheme_registry.dart — isSchemeRegistered`'s dartdoc).

## Why it is cross-cutting
Each backend decodes its own OS answer into `bool`-or-throw, at sites that never
call each other: the Windows status classification, the macOS `BOOL` decode, the
two handler lookups, and the unsupported stand-in that must throw *rather than*
answer `false`. The facade delegates unchanged (`url_launcher.dart — UrlLauncher`),
so no shared primitive enforces the split — each site keeps it alone. Changing
one site's mapping (a fault folded into `false`, or a "no" raised as an error)
makes the same caller code mean different things per platform.

## Territories it holds in
- [Public API](public-api.md) — `url_launcher.dart — UrlLauncher.launchUrlSync` / `canLaunchUrlSync` return the backend's answer unchanged; a facade that caught and returned `false` would break every site at once.
- [Windows launch](windows-shell-and-registry.md) — `windows_backend.dart — WindowsUrlLauncherBackend.launch`: `ShellExecuteOutcome.noHandler` (31) → `false`, `failed` → `UrlLaunchException`.
- [Windows handler lookup](windows-handler-lookup.md) — `scheme_registry.dart — isSchemeRegistered`: every failure → `false` (the stated exception).
- [macOS launch](macos-launch.md) — `macos_backend.dart — MacosUrlLauncherBackend.launch`: `notOpened` → `false`, `invalidUrl` → `UrlLaunchException`.
- [macOS handler lookup](macos-handler-lookup.md) — `ns_workspace.dart — workspaceCanOpenUrl`: an `NSURL` that will not construct → `false`.
- [Backend selection](backend-selection.md) — `unsupported_backend.dart — UnsupportedUrlLauncherBackend`: throws `UnsupportedError` from both operations, never `false`.
- [Error model](error-model.md) — `exceptions.dart — UrlLaunchException` is documented as "not nothing-is-registered".

## What a violation looks like
A caller that shrugs off `false` ("no app for that") silently swallows a real
fault, or a caller that treats every exception as a bug crashes on an ordinary
"no". Reproduces whenever a backend arm maps a fault to `false` or `noHandler`
to a throw — `test/unsupported_backend_test.dart`, *"throws rather than
returning a quiet false"*, and `test/windows/windows_backend_test.dart`,
*"answers false for SE_ERR_NOASSOC rather than throwing"*, pin two sites.

## Discovery history
- The rule is stated in `CLAUDE.md` ("Nothing fails ambiguously") and in
  `url_launcher_backend.dart — UrlLauncherBackend`'s class dartdoc (reading,
  2026-10-26).
- **The rule's `false` is not reachable on every path**: on Windows an
  unregistered *scheme* launches with 42, so `launch` returns `true`
  ([`lessons.md`](../agents/lessons.md) #4). The invariant governs what `false`
  means, not that it occurs.

## Where it will recur
Any new backend, or any new outcome added to `ShellExecuteOutcome` /
`MacOpenOutcome`: ask "is this *nothing is registered*?" — only then `false`.
