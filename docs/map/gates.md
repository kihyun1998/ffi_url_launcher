# Gates

## What it is
What CI runs, on which runners, and why each gate is shaped the way it is. The
commands are in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml); the
two guards no other gate can express are `tool/compile_exe_guard.dart` and
`tool/check_dependencies.dart`.

## Governing decisions
- [ADR-0002](../adr/0002-every-guard-is-asked-six-questions.md) question 4 — a
  threshold is derived, never raised to clear a red build.

## Design model
- **Two runners, Windows and macOS; Ubuntu is deliberately not in the matrix** —
  the package supports neither Linux nor anything else, and a green Linux job
  would prove only that the pure logic is host-independent. `fail-fast: false`,
  because the legs exercise different backends (retired `theflow.md` Step 7,
  carried at 2ef7cc0; matrix re-read in `ci.yml`).
- **Each runner is the only one that executes its backend.** Windows alone makes a
  registry call or `ShellExecuteW`; macOS alone touches `NSWorkspace`. Never read
  a green matrix as "the backend works" — see [proving-os-effects](proving-os-effects.md).
- **Two SDK legs per runner, `stable` and the declared floor** —
  [sdk-floor-runs-in-ci](sdk-floor-runs-in-ci.md).
- **Two guards, one per failure mode a convenience dependency has**: a `hooks:`
  dependency breaks `dart compile exe` (the compile-exe guard), and a
  `platforms:`-restricted one misstates support (the dependency guard). Neither
  covers the other — see [runtime-dependencies](runtime-dependencies.md).
- **The compile-exe consumer must answer something positively** — it asks whether
  `https:` has a handler and requires `true`. An earlier version printed a resolved
  backend type, which a broken FFI load also prints
  (`compile_exe_guard.dart` header; [lessons.md](../agents/lessons.md) #9).
- **The consumer inherits the package's own SDK constraint**, read out of
  `pubspec.yaml` (`compile_exe_guard.dart — _packageSdkConstraint`).
- **The generated consumer lives in a temp directory.** No member carries its own
  `pubspec.yaml`, so there is no out-of-workspace member; committing the consumer
  would create one, and `dart test` at the root would not run it.
- **`dart test` does not run `example/`** — it has no `pubspec.yaml` of its own, so
  `dart analyze` covers it and nothing executes it. Recorded, not closed.
- **Neither `dart format .` nor `dart analyze` reaches `.scratch/`** — both skip
  dot-directories. Measured: invalid Dart there leaves `dart analyze --fatal-infos`
  at *"No issues found!"*, exit 0, while `dart analyze --fatal-infos .scratch/`
  catches it (exit 3). Deliberately left open: a half-finished probe must not break
  `main`. Probes are still expected to pass `dart analyze .scratch/` when committed
  — a hand-run check.
- **Run each gate bare, never piped**: `dart test | tail -1 && commit` always
  commits, since the pipeline's status is `tail`'s.
- **Format runs after `pub get`** — `dart format` reads the language version from
  `package_config`; the failure reproduces only in a clean `git worktree`.
- **Never move a threshold to turn a build green.** `--fatal-infos` and
  `--set-exit-if-changed` are the floor; the memory and handle ceilings are derived
  beside their tests.
- **Test files share one process.** `dart test` runs files concurrently, as
  isolates in **one process** — measured, an identical `pid` across two suites, one
  opening handles while the other dwelt. So shared OS state needs a key unique to
  its file (sibling `just_autostart`'s lessons #8: two files sharing one scratch
  registry key destroyed each other), and every **process-wide** counter — handle
  count, pool quota, RSS — is shared with no name needed. A strict-equality
  assertion on one is flaky by construction; `handle_lifetime_test.dart` asserts a
  derived ceiling — measured noise 2–3 handles, a 200-file suite moves it by 200,
  the regression by 20,000 (the test's own comment).

## Code
- `.github/workflows/ci.yml` — jobs `gates`, `compile-exe`
- `tool/compile_exe_guard.dart — main`, `_packageSdkConstraint`
- `tool/check_dependencies.dart — allowedRuntimeDependencies`, `main`

## Reference behaviour
**None.**

## Cross-cutting invariants
- [sdk-floor-runs-in-ci](sdk-floor-runs-in-ci.md)

## Blast radius
- [Runtime dependencies](runtime-dependencies.md) — the two guards are that invariant's only enforcement.
- [Proving OS effects](proving-os-effects.md) — CI runs the integration tests; a gate change can silently drop one leg's only proof.
- [Publishing](publishing.md) — the floor leg proves the `sdk:` constraint consumers inherit; `dart pub publish --dry-run` is not in CI.
- [Backend selection](backend-selection.md) — a new platform needs its runner here.

## Known holes / open
- **Nothing reports a new `ffi` major or drift in the pinned actions** — no
  Dependabot. Tracked: #16.
- `example/` is analyzed, never executed; `.scratch/` is neither.
