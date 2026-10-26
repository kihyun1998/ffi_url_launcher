# Gates: what CI proves, and what it cannot

The commands are in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml);
this note is why they are shaped the way they are.

Ubuntu is deliberately **not** in the matrix: this package supports Windows and
macOS only, and a green Linux job would prove only that the pure logic is
host-independent. `fail-fast: false`, because the two legs exercise entirely
different backends and one failing says nothing about the other.

Beside format, analyze and test, **two** guards that no other gate can express, one per failure mode a
convenience dependency has:

```
dart run tool/compile_exe_guard.dart    # a hooks: dependency breaks consumers
dart run tool/check_dependencies.dart   # a platforms: dependency misstates support
```

**The consumer must call something that answers positively**, not merely import
the package or resolve a backend. A compiled binary printing a backend type
proves the build worked; it does not prove the platform libraries load under
AOT. Have it call `canLaunchUrlSync(Uri.parse('https://…'))` and expect `true` —
`lessons.md` #9 is a bug that a type-printing consumer would have passed.

- **Why the compile-exe guard exists.** The package's central promise is that it
  adds no build hooks. `package:objective_c` and any `hooks:`-declaring
  dependency would break `dart compile exe` outright — *"'dart compile' does not
  support build hooks, use 'dart build' instead"* — and the failure appears in a
  **consumer**, never in this repo's own tests. A dependency added for
  convenience would pass every other gate.
- **Why the dependency guard exists too, and is not redundant.** The other
  failure mode `CLAUDE.md` names — a Windows-only dependency such as
  `package:win32`, which makes this package claim platform support it does not
  have — is **invisible to every gate including the compile one**. Measured:
  adding `win32: ^5.0.0` leaves `pub get`, `format`, `analyze`, `test` and
  `dart compile exe` all green on both runners, and only
  `check_dependencies.dart` goes red. Two failure modes, two guards; neither
  covers the other.
- **The generated consumer lives in a temp directory, not in the repo.**
  No member carries its own `pubspec.yaml`, so there is no out-of-workspace
  member. Committing the consumer would add a second `pubspec.yaml` and create
  exactly that member — `dart test` at
  the root would not run it.
- **The blind spot here is per-runner, not per-member.** The Windows runner is the
  *only* one that executes a registry call or `ShellExecuteW`; the macOS runner is
  the *only* one that touches `NSWorkspace`. Never read a green matrix as "the
  backend works".
- **`dart test` does not run `example/`.** It has no separate `pubspec.yaml`, so
  `dart analyze` covers it, but nothing executes it. This gap is recorded, not
  closed.
- **Neither `dart format .` nor `dart analyze` reaches `.scratch/`** — both skip
  dot-directories. Measured: a file of outright invalid Dart placed there leaves
  `dart analyze --fatal-infos` reporting *"No issues found!"* and exiting 0, while
  `dart analyze --fatal-infos .scratch/` catches it (exit 3). So the committed
  measurement probes there **can rot silently** as the package's internals move.
  **The gap is closeable in one gate line and is deliberately left open**:
  `.scratch/` is where a throwaway belongs, and gating it would make a
  half-finished probe break `main`. What carries the durability instead is that
  the *numbers* live in `lessons.md`, not in the probes — a probe is a
  convenience for re-measuring, valid as of its commit. Probes are still expected
  to pass `dart analyze .scratch/` when committed; that is a hand-run check, not a
  gate.
- **Run each gate bare, never piped.** `dart test | tail -1 && commit` always
  commits: a pipeline's exit status is `tail`'s, and `tail` always succeeds.
- **Format runs after `pub get`** — `dart format` reads the language version from
  `package_config`; the failure only reproduces in a clean `git worktree`.
- **Never move a threshold to turn a build green.** `--fatal-infos` and
  `--set-exit-if-changed` are the floor; raise them when the real number rises.
- **Scratch-state collisions across test files.** Sibling `just_autostart`'s
  lessons #8: two files sharing one scratch registry key destroyed each other
  because `dart test` runs files concurrently. Any test that touches shared OS
  state uses a key unique to its file.
- **And it runs those files as isolates in *one process*** — measured, identical
  `pid` across two suites, one provably opening handles while the other dwelt. So
  every **process-wide** OS counter (handle count, pool quota, RSS) is shared
  state across test files, and this collision needs no shared *name* to happen:
  merely existing is enough. A strict-equality assertion on such a counter is
  flaky by construction. `test/windows/handle_lifetime_test.dart` therefore
  asserts a **derived ceiling** rather than equality — measured noise from a full
  concurrent suite run is 2–3 handles, a suite opening 200 files moves it by 200,
  and the regression it guards moves it by 20,000.
- **`.pubignore` is load-bearing.** A top-level `docs/`
  collides with pub's reserved singular `doc/` layout name and makes
  `dart pub publish` refuse outright (sibling `just_autostart`, lessons #4). This
  repo now has `docs/agents/`, so `.pubignore` must exclude `docs/` **and**
  repeat the `.gitignore` entries, because a present `.pubignore` replaces
  `.gitignore` for archive purposes.
