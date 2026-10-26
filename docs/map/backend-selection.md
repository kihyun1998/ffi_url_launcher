# Backend selection

## What it is
How an operating-system name becomes a backend, and what answers on a platform
with none: one table naming every supported platform, a resolver over it, and a
stand-in that refuses.

## Governing decisions
**None.** ADR-0001 governs what a backend does with a URL, not which backend
answers.

## Design model
From reading the source (no record):
- **One table, three jobs.** `supportedPlatforms` decides what the resolver
  returns, supplies the display names the refusal message lists, and *is* the
  definition of "supported". A platform cannot be listed without being wired
  (`supported_platforms.dart — supportedPlatforms` dartdoc).
- **The resolver is a pure function of the name**, never of
  `Platform.operatingSystem`, so every arm is testable from any host
  (`url_launcher_platform.dart — resolveUrlLauncherBackend`;
  `test/url_launcher_platform_test.dart`).
- **An unsupported platform throws from both operations** rather than answering
  `false` — see [false-means-nothing-registered](false-means-nothing-registered.md).
- **The refusal message reads its "supported" half out of the table.** Sibling
  `just_autostart` shipped a self-contradicting message because the two halves
  were kept apart (`unsupported_backend.dart — _message` dartdoc, citing that
  sibling's lessons #5).
- **`create` is a factory**, so a backend is built only on the platform that
  asked for it — see [platform-libraries-open-lazily](platform-libraries-open-lazily.md).

## Code
- `lib/src/supported_platforms.dart — supportedPlatforms`, `PlatformSupport`
- `lib/src/url_launcher_platform.dart — resolveUrlLauncherBackend`
- `lib/src/backends/unsupported_backend.dart — UnsupportedUrlLauncherBackend`, `_message`

## Reference behaviour
- Siblings `just_autostart` and `flutter_inactive_timer` resolve bindings the same
  way, as a pure function of the OS name — [thegraph.md](../agents/thegraph.md),
  "where files go" row.

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md)
- [platform-libraries-open-lazily](platform-libraries-open-lazily.md)

## Blast radius
- [Publishing](publishing.md) — the table is the platform claim; `pubspec.yaml`'s `platforms:` block and the README's platform table must say the same set.
- [Gates](gates.md) — CI runs only the platforms in this table; a new entry needs its runner.
- [Runtime dependencies](runtime-dependencies.md) — a new platform's binding must still come from `ffi` alone.

## Known holes / open
**None.**
