# Runtime dependencies

## What it is
The package's single runtime dependency, `ffi`, and the invariant that keeps it
single: no `hooks:`-declaring package, no platform-restricted package.

## Governing decisions
**None** as a record. The invariant is stated in `CLAUDE.md` ("The dependency list
is an invariant, not a preference") and in `tool/check_dependencies.dart —
allowedRuntimeDependencies`'s dartdoc.

## Design model
- **`ffi` only**, because `dart:ffi` ships no allocator and no UTF-16 marshalling;
  `ffi` is pure Dart, from the Dart team, with no `hooks:` and no platform
  restriction (`check_dependencies.dart — allowedRuntimeDependencies`;
  `pubspec.yaml` comment).
- **A `hooks:` dependency breaks every consumer's `dart compile exe`** — *"'dart
  compile' does not support build hooks, use 'dart build' instead"* — and the
  failure appears one repo downstream, never in this repo's tests.
  `package:objective_c` is the ergonomic temptation on macOS
  ([lessons.md](../agents/lessons.md) #1; `compile_exe_guard.dart` header).
- **A Windows-only dependency misstates platform support** and is invisible to
  every other gate. Measured: adding `win32: ^5.0.0` left `pub get`, `format`,
  `analyze`, `test` and `dart compile exe` green on both runners; only
  `check_dependencies.dart` went red (retired `theflow.md` Step 7, carried at
  2ef7cc0). `package:win32` would also pull thousands of generated bindings to
  call four functions (`pubspec.yaml` comment).
- **Injection uses public named constructors, not `@visibleForTesting`** —
  `package:meta` would be a second dependency for an advisory annotation
  (`CLAUDE.md` › Seams).
- **The checker reads `dart pub deps --json`**, not `pubspec.yaml`, so it needs no
  YAML parser and sees what pub resolved (`check_dependencies.dart` header). The
  compile-exe guard hand-parses the `sdk:` line for the same reason.
- **No lockfile is committed** (`.gitignore` excludes `pubspec.lock`, as a
  library package should), so what a consumer resolves is the declared range
  alone — every change to a range in `dependencies:` is a decision about every
  consumer, and lands as a [publishing](publishing.md) change.
- **Dev dependencies are ranged, not careted**, so the floor leg can `pub get`:
  `lints: ">=5.1.1 <7.0.0"` lets pub pick 6.x on stable and 5.1.1 on the floor.
  They constrain what this repo can verify, never what a consumer resolves
  (`pubspec.yaml` comment).

## Code
- `pubspec.yaml` — `dependencies:`, `dev_dependencies:`
- `tool/check_dependencies.dart — allowedRuntimeDependencies`, `main`
- `tool/compile_exe_guard.dart — main`

## Reference behaviour
- `package:win32`'s generated source is read for constants (binding,
  [thegraph.md](../agents/thegraph.md)) — never depended on.

## Cross-cutting invariants
**None.** One site states the set; the two guards enforce it.

## Blast radius
- [Gates](gates.md) — both guards run in CI; a new dependency is caught there or nowhere.
- [Publishing](publishing.md) — the `platforms:` block is the public claim a restricted dependency would contradict.
- [macOS Objective-C binding](macos-nsworkspace.md) and [Windows launch](windows-shell-and-registry.md) — hand-written bindings exist because no binding package may be taken.

## Known holes / open
- **No automation reports a new `ffi` major** outside the caret. Tracked: #16.
