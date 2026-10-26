# Publishing

## What it is
How the package reaches pub.dev and what it promises there: `pubspec.yaml`'s
metadata, platform claim and SDK floor, the archive's contents, the README and
CHANGELOG as published surfaces, and the release procedure.

## Governing decisions
**None** as a record. The release bar is `pub-ready`'s; the SDK-floor rule is
`CLAUDE.md` › Working discipline.

## Design model
- **The release bar — who publishes, the dry-run, frozen CHANGELOG entries —
  is `pub-ready`'s** ([thegraph.md](../agents/thegraph.md) › Release).
- **The `platforms:` block is a public claim**, rendered by pub.dev — Windows and
  macOS only, matching `supportedPlatforms` (`pubspec.yaml` comment).
- **The `sdk:` floor is measured, not scaffolded**: `>=3.10.0 <4.0.0`, the
  boundary where `[NSURL URLWithString:]` leaves strict mode. It rises only in a
  minor or major bump with its reason recorded (`pubspec.yaml` comment;
  `CLAUDE.md`). `dart create` wrote `^3.11.5` and it stayed untouched to 0.1.0,
  silently demanding an SDK upgrade of every adopter (`pubspec.yaml` comment).
- **`.pubignore` is load-bearing.** A top-level `docs/` collides with pub's
  reserved `doc/` layout name and makes `dart pub publish` refuse (sibling
  `just_autostart`, its lessons #4), so `.pubignore` excludes `docs/`, `.scratch/`
  and `.github/` — and repeats the `.gitignore` entries, because a present
  `.pubignore` replaces `.gitignore` for the archive (`.pubignore` header).
- **The README carries what is discovered painfully otherwise**: the blocked /
  not-blocked table with `file:` named as an execution vector; `canLaunchUrl`
  always true for `file:`; the platform code null on macOS; no Flutter
  dependency, and `dart compile exe` works (`CLAUDE.md` › Seams).
- **Published state is read from the pub.dev API**, not remembered —
  [thegraph.md](../agents/thegraph.md).

## Code
- `pubspec.yaml` — `version`, `platforms:`, `environment:`, `topics:`
- `.pubignore`
- `README.md`, `CHANGELOG.md`, `LICENSE`

## Reference behaviour
- `curl -s https://pub.dev/api/packages/ffi_url_launcher` — published state,
  binding.

## Cross-cutting invariants
- [sdk-floor-runs-in-ci](sdk-floor-runs-in-ci.md)

## Blast radius
- [Gates](gates.md) — the floor leg must name the same SDK; the dry run is not in CI.
- [Public API](public-api.md) — the README and the dartdoc on pub.dev describe this surface; a change to it is a CHANGELOG entry.
- [URL shape check](url-shape-check.md) — the README's Security table is the caller's account of what is refused.
- [Backend selection](backend-selection.md) — `platforms:` and the README's platform table must match the wired set.

## Known holes / open
- **The post-release consumer round-trip is a hand procedure** with no record per
  release beyond 0.1.0's ([proving-os-effects](proving-os-effects.md)).
