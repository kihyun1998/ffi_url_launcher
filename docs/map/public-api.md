# Public API

## What it is
The four top-level functions and the `UrlLauncher` facade a consumer calls:
`launchUrl`, `launchUrlSync`, `canLaunchUrl`, `canLaunchUrlSync`, each with
`allowUnsafe`. It runs the shape check, then delegates to one backend unchanged.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) — the facade is where
  (A) runs before the backend, for both operations ("one gate, both doors").

## Design model
- **The export list is the API contract.** `lib/ffi_url_launcher.dart` exports
  four exception types and `UrlLauncher`; `UrlLauncherBackend` is not exported, so
  `UrlLauncher.withBackend` takes a type outside code cannot name without reaching
  into `src/` (`CLAUDE.md` › Seams; reading of the export list, 2026-10-26).
- **Shape and naming follow `package:url_launcher`** — `launchUrl(Uri)`,
  `canLaunchUrl(Uri)`, `Future<bool>` — so code moving across keeps its shape
  (`url_launcher.dart — UrlLauncher.launchUrl` dartdoc). The upstream is an
  *example*, not a spec ([thegraph.md](../agents/thegraph.md)).
- **The facade delegates unchanged.** A backend's `false` and its exceptions
  reach the caller as thrown (`url_launcher.dart — UrlLauncher` class dartdoc;
  `test/url_launcher_test.dart`, *"lets a backend failure through instead of
  turning it into false"*).
- **The shape check runs unless `allowUnsafe: true`**, before the backend, on
  launch and lookup alike (`UrlLauncher.launchUrlSync`, `canLaunchUrlSync`;
  `test/url_launcher_test.dart` group *"the shape check is wired into the
  facade"*). `allowUnsafe` is the caller's policy, never the package's.
- **The `Sync` forms are the real ones**; the `Future` forms wrap them — see
  [os-calls-stay-on-the-calling-thread](os-calls-stay-on-the-calling-thread.md).
- **The shared contracts are `{@template}`s** in `url_launcher_backend.dart`
  (`launch_contract`, `can_open_contract`, `platform_fault`) and
  `url_launcher.dart` (`allow_unsafe`), so the sentence most likely to go stale
  exists once. The public dartdoc ships verbatim as the API reference.
- **Ask with `canLaunchUrl`, not by branching on `launchUrl`'s result** — the
  library dartdoc says so, because Windows' launch `false` is effectively
  unreachable for a scheme ([lessons.md](../agents/lessons.md) #4).
- Input bound: the URL is a caller's `Uri`; nothing bounds its length here. Each
  OS call receives it whole.

## Code
- `lib/ffi_url_launcher.dart — launchUrl`, `launchUrlSync`, `canLaunchUrl`, `canLaunchUrlSync`, `_default`
- `lib/src/url_launcher.dart — UrlLauncher.withBackend`, `UrlLauncher.forCurrentPlatform`, `UrlLauncher.forOperatingSystem`, `UrlLauncher.launchUrlSync`, `UrlLauncher.launchUrl`, `UrlLauncher.canLaunchUrlSync`, `UrlLauncher.canLaunchUrl`
- `lib/src/url_launcher_backend.dart — UrlLauncherBackend` (the seam and the contract templates)

## Reference behaviour
- `package:url_launcher`'s `url_launcher_uri.dart` for shape and naming —
  [thegraph.md](../agents/thegraph.md), row "public API shape and naming".

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md)
- [os-calls-stay-on-the-calling-thread](os-calls-stay-on-the-calling-thread.md)
- [platform-libraries-open-lazily](platform-libraries-open-lazily.md)

## Blast radius
- [Error model](error-model.md) — the exported exception set is the caller's whole `switch`; adding or removing one changes what "handled everything" means.
- [Example](example.md) — the example is the specification of how this surface is meant to be used; a new or changed function must be used there.
- [Publishing](publishing.md) — the README's usage and return-value tables restate this surface; the CHANGELOG records any change to it, and pub.dev renders the dartdoc.
- [URL shape check](url-shape-check.md) — the facade decides *when* the check runs; moving that call changes which door is guarded.
- [Backend selection](backend-selection.md) — `forOperatingSystem` is the only route from a platform name to a backend.

## Known holes / open
- **The success half is unproven by automation**: `true` means the handler was
  started, and no OS reports whether the URL opened — see
  [proving-os-effects](proving-os-effects.md).
