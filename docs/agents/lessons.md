# lessons (ffi_url_launcher)

Per-incident evidence for the rules in [`theflow.md`](theflow.md). Each entry is
a real incident with the artifact that proves it — the rules read as
abstractions without these.

Indexed by the step whose rule it gives teeth to.

The first three were measured while designing the package, before any
implementation existed. They are the reason three of its rules are written the
way they are.

---

## #1 — A dependency chosen for ergonomics would have broken the package's whole promise — Steps 2, 7

**Rule it proves:** the `dart compile exe` gate is not ceremony; a build-hook
dependency fails only in a *consumer*, and every other gate stays green.

`package:objective_c` (dart.dev, v9.5.0) is the ergonomic way to reach
Objective-C from Dart, and its pubspec has **no `flutter` dependency** — so it
looked free. It declares `hooks:` and depends on `code_assets`, which means it
compiles native code at build time.

Measured in a throwaway pure-Dart project:

```
$ dart pub get           # succeeds, 16 packages
$ dart run bin/main.dart # succeeds — "Running build hooks..." then the objc symbol resolves
$ dart compile exe bin/main.dart
'dart compile' does not support build hooks, use 'dart build' instead.
```

The fallback, `dart build cli`, printed *"The `dart build cli` command is in
preview at the moment"* and emitted a **bundle directory**
(`build/cli/windows_x64/bundle/bin/main.exe`) rather than a single portable
executable.

**Cost had it stood:** the package targets Dart CLI authors. Taking it as a
dependency would have silently removed their ability to ship a single
executable — the ordinary way a Dart CLI is distributed — and nothing in this
repo's own tests would have failed.

**Why it was nearly missed:** the pubspec looked clean. The disqualifying
property is not a dependency edge, it is the `hooks:` key, and its consequence
appears one repo downstream.

---

## #2 — `Uri` typing reads as a safety guarantee and is not one — Steps 2, 5

**Rule it proves:** every cheap "yes" answers a narrower question; a guard states
which question it answers.

`url_launcher`'s modern API takes `Uri` rather than `String`, which reads as the
safe choice. It is not sufficient. Measured with the shipped Dart SDK:

```
C:\Windows\System32\calc.exe    scheme=c          hasScheme=true   → 'c:/Windows/System32/calc.exe'
\\attacker\share\evil.exe       scheme=           hasScheme=false  → '/attacker/share/evil.exe'
evil.bat                        scheme=           hasScheme=false  → 'evil.bat'
file:///C:/Windows/.../calc.exe scheme=file       hasScheme=true   → unchanged
```

A drive letter **parses as a URI scheme**, so `hasScheme` is `true` for a local
executable path, and `ShellExecuteW` accepts the forward-slashed form and runs
it. The two hazards also need two different checks: the drive-letter case has a
scheme, the UNC case has none, so either check alone leaves a hole.

**Cost had it stood:** a `hasScheme` guard would have shipped as "we validate
URLs" while passing `C:\Windows\System32\calc.exe` straight to the shell — a
guard that moves the caller's belief without moving their risk.

**What it did not fix:** `file:///C:/…/calc.exe` still passes. That is
deliberate — `file:` is a supported desktop feature — and it is why the README
must document what is *not* blocked beside what is.

---

## #3 — The claimed constraint was real, but not where it was claimed — Reasoning habits

**Rule it proves:** "unconfirmed ≠ absent" cuts both ways — a constraint asserted
from memory is unverified even when the conclusion turns out to be right.

While weighing whether the package could double as a `url_launcher` platform
implementation, the claim was made that *"a package depending on `flutter` cannot
be used from a pure Dart CLI, and there is no workaround."* The first half is
true; the "no workaround" half was wrong, and the boundary sits somewhere else
entirely.

Measured:

```
$ dart pub get                      # in a pure Dart project depending on url_launcher_platform_interface
Resolving dependencies... + flutter 0.0.0 from sdk flutter ... Changed 9 dependencies!   ← SUCCEEDS

$ dart run bin/main.dart            # entrypoint that does NOT import the flutter chain
hello                                                                                    ← SUCCEEDS

$ dart run bin/imp.dart             # entrypoint that DOES import it
Error: Dart library 'dart:ui' is not available on this platform.                         ← fails
```

Resolution succeeded because the `dart` on PATH was `D:\flutter\bin\dart`, a
**wrapper script that sets `FLUTTER_ROOT` itself** — so an attempt to simulate a
Flutter-less machine by overriding that variable was silently defeated. Calling
the cached SDK binary directly reproduced the real failure:

```
$ FLUTTER_ROOT=/no-flutter-here .../cache/dart-sdk/bin/dart.exe pub get
Because clitest depends on url_launcher_platform_interface >=1.0.1
which requires the Flutter SDK, version solving failed.
```

The two layers have different granularity: **`pub get` resolves per package,
compilation resolves per import graph.** The "only import the safe library"
trick works at the second layer and is powerless at the first.

**Why the first simulation lied:** `flutter/bin/dart` is a shell wrapper, not the
Dart SDK binary. Overriding an environment variable that the program under test
sets for itself measures nothing.

---

## #4 — The documented failure code is unreachable, and "success" means the shell opened its own dialog — Steps 1, 4

**Rule it proves:** to pin a runtime fact, instrument a probe; and every cheap
"yes" answers a narrower question than the caller asked.

Both the reference implementation and this repo's own bindings doc were written
around `SE_ERR_NOASSOC` (31) being the answer for "nothing is registered to open
this URL". The reference maps it to `false` specifically so that case is not an
error, and this project's Step 4 proof method was written as *"a scheme
registered to nothing returns `false` and opens no window"*.

A throwaway probe against the real `shell32.dll` on Windows 11 (26200):

```
zzznotreal-ffiurllauncher://x   -> status=42   ShellExecuteOutcome.launched
zzznotreal2://a/b?c=1           -> status=42   ShellExecuteOutcome.launched
''                              -> status=42   ShellExecuteOutcome.launched
C:\...does-not-exist\nope.zzzq  -> status=2    SE_ERR_FNF
file:///C:/zzz-nope.zzzq        -> status=2    SE_ERR_FNF
```

**42 is greater than 32, so it is success.** What the shell successfully
launched is its own "how do you want to open this?" / look-for-an-app-in-the-
Store UI. `SE_ERR_NOASSOC` is not reachable through a URL scheme at all on this
Windows version — and the **empty string** also reports success.

**Cost had it stood:**

- the `false` branch would have been believed to cover "no handler" while never
  firing for a scheme, so `launchUrl` would answer `true` for URLs nothing can
  open;
- the CI assertion planned for the launch path (ticket 06, *"a scheme registered
  to nothing returns false and opens no window"*) would have been written to
  assert a falsehood — and would have popped a dialog on every CI run trying;
- the real round-trip proof would have rested on a code the machine never
  produces, so the FFI marshalling would have gone effectively unproven.

**What replaced it:** the round-trip proof uses a **path that does not exist**
(status 2), which is reachable, UI-free, and exercises exactly the same load →
marshal → call → decode → map chain.

**Why reading the source could not have caught it:** the reference's C++ is
*correct* — it handles 31 properly. The gap is not in the code, it is that the
platform stopped producing that code. Only running it says so.

---
