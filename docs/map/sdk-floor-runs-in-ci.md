# The SDK floor is the one CI runs

## The fact
The lower bound of `environment: sdk:` in `pubspec.yaml` and the pinned SDK leg
of the CI matrix (`ci.yml`, `matrix.sdk`) name the same version.

## Why it is cross-cutting
`pubspec.yaml` declares the floor a consumer inherits; `.github/workflows/ci.yml`
pins a leg to it by literal (`sdk: [stable, "3.10.0"]` in both jobs). Neither
reads the other — only `tool/compile_exe_guard.dart — _packageSdkConstraint`
reads the pubspec, and it does not pin the SDK it runs on. Move the floor without
the matrix and the floor is a claim no gate executes.

## Territories it holds in
- [Publishing](publishing.md) — `pubspec.yaml`, `environment: sdk:`.
- [Gates](gates.md) — `ci.yml`, both jobs' `matrix.sdk`.
- [macOS Objective-C binding](macos-nsworkspace.md) — the floor is where `[NSURL URLWithString:]` leaves its strict mode, so it is a behavioural boundary, not a scaffold value.

## What a violation looks like
The floor lowered in `pubspec.yaml` while CI still runs the old one: green, and
the new floor unproven. Or the reverse: a red leg that is not the code's fault.

## Discovery history
- 3.10.0 is measured, across 3.8.0 / 3.9.0 / 3.10.0 / 3.11.5 / stable on one
  macOS image ([`lessons.md`](../agents/lessons.md) #13; `pubspec.yaml` comment).
- `compile_exe_guard.dart` once hardcoded `^3.11.5` while the floor was being
  lowered, and refused to run on the SDK the change was for (its own comment).

## Where it will recur
Every change to `environment: sdk:`. The release rule in `CLAUDE.md` (the floor
rises only in a minor or major bump) applies on top.
