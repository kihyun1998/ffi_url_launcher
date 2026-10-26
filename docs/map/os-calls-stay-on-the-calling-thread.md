# OS calls stay on the calling thread

## The fact
Both OS calls run synchronously on the caller's own isolate thread: the `Future`
API wraps a synchronous call and offloads nothing.

## Why it is cross-cutting
The constraint comes from two unrelated OSes — `NSWorkspace` wants the main
thread, and `ShellExecuteW` depends on the COM apartment the calling thread
already has (`url_launcher.dart — UrlLauncher.launchUrl` dartdoc;
`shell_execute.dart — shellExecuteOpen`; `ns_workspace.dart — workspaceOpenUrl`).
The facade's `async` wrappers and each backend's call site keep it
independently; an `Isolate.run` added at either level breaks it.

## Territories it holds in
- [Public API](public-api.md) — `url_launcher.dart — UrlLauncher.launchUrl` / `canLaunchUrl`: `async =>` over the `Sync` form.
- [Windows launch](windows-shell-and-registry.md) — `shell_execute.dart — shellExecuteOpen`.
- [macOS launch](macos-launch.md) — `ns_workspace.dart — workspaceOpenUrl`.
- [macOS handler lookup](macos-handler-lookup.md) — `ns_workspace.dart — workspaceCanOpenUrl`.

## What a violation looks like
Not reproduced in this repo — no test can observe the COM apartment or the
main-thread requirement directly. Stated as a contract in `CLAUDE.md` and in
the dartdoc above; treat it as unverified by measurement.

## Discovery history
- Recorded in the retired `theflow.md` macOS hidden-state list and carried into
  `CLAUDE.md` (commit 2ef7cc0, 2026-10-26).

## Where it will recur
Any proposal to make the async API "really async" — `Isolate.run`, `compute`, a
worker isolate — is subject to this.
