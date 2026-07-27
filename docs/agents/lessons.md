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

**42 is greater than 32, so it is success.** `SE_ERR_NOASSOC` is not reachable
through a URL scheme at all on this Windows version.

**What the shell actually did — watched on screen, not inferred.** Each call was
re-run on its own so the window could be attributed to one input:

| Input | Status | What appeared |
|---|---|---|
| `zzznotreal-ffiurllauncher://x` | 42 | the **"이 링크를 열려면 새 앱이 필요합니다"** dialog (Windows' "you'll need a new app to open this link" handler picker) |
| `''` (empty string) | 42 | a **File Explorer window** |

So "success" means *the shell successfully launched something of its own* — a
picker dialog, or Explorer. Neither is what the caller asked for, and both are
reported identically to a real launch.

The empty-string row is the worse of the two. A dialog at least tells the user
something went wrong; Explorer opening looks like an unrelated accident while
the function returns `true`. An empty or unsubstituted value reaching
`launchUrl` from a config file reproduces it exactly. **Ticket 02's shape check
blocks it** — the empty string has no scheme — which turns that ticket from a
guard against a hypothetical into a fix for a measured case.

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

## #5 — A summarizing fetch dropped a branch, and seven tickets were written on top of it — Steps 1, 6

**Rule it proves:** never use a summarizing fetch on a reference file; and an
error's cost scales with how early it sits, not with its size.

`url_launcher_plugin.cpp` was first read through a summarizing fetch. The
summary correctly listed *which* Win32 functions the file calls. It silently
dropped what happens **inside** them:

- `RegOpenKeyExW` is called with `KEY_QUERY_VALUE`, not `KEY_READ` — the
  argument was gone, and the ticket was written with the wrong one.
- `LaunchUrl` has a **branch**: when the URL starts with `file:` it runs
  `UrlUnescapeA(..., URL_UNESCAPE_INPLACE)` first, under the comment
  *"ShellExecuteW does not process %-encoded UTF8 strings in file URLs."* The
  branch was absent from the summary entirely, so it was absent from all seven
  tickets.

**The defect it caused.** `Uri.toString()` always percent-encodes non-ASCII, and
`ShellExecuteW` decodes ASCII `%20` in a `file:` URL but **not** multi-byte
UTF-8 escapes. Measured end to end against a file that exists:

```
file exists      : true
Uri.toString()   : file:///C:/…/%ED%95%9C%EA%B8%80%ED%8C%8C%EC%9D%BC.txt
launchUrlSync    : UrlLaunchException — the file was not found (code 2)
```

Confirmed independently with `PathCreateFromUrlW`, the shell's own URL→path
converter: `%20` decodes, `%ED%95%9C` is read as one wide character each.

This package was **more exposed than the reference**, not less: the C++ receives
whatever string its Dart caller passed, while this API takes a `Uri` and
therefore *manufactures* the broken encoding. A user with a Korean, Japanese or
Cyrillic path had no working `file:` support at all.

**Cost of where the error sat.** The bad read happened before any code existed,
so it propagated into the design record, the `theflow.md` Step 4 proof method,
and ticket 06's CI assertion. Closing it meant amending four documents, not
editing one line. Had the same mistake been made during implementation it would
have cost minutes.

**What replaced it, and why it is not the reference's fix.** `Uri.toFilePath`
rather than unescaping the URL string. Measured, it is better in two ways the
reference cannot be, because C++ had no URI parser:

| Input | reference's unescape | `toFilePath` |
|---|---|---|
| file genuinely named `a%20b.txt` | `a b.txt` — wrong file, or none | `a%20b.txt` |
| `file://server/share/x` | left as a URL | `\\server\share\x` |

This is the bindings' tie-breaker in action: the reference decides *which* call
to make and in what order; the marshalling is derived for the language actually
being written.

---

## #6 — A sibling's lesson was copied without measuring it, and it did not reproduce — Step 1

**Rule it proves:** secondhand statements are verification targets *including*
one written by this family; and the mutation gate is what exposes a doc-comment
asserting a consequence nothing tests.

Sibling `just_autostart`'s lessons #7 says the unsigned spelling of a predefined
registry handle "produces a handle Windows does not recognise", and its
`registry.dart` carries that reasoning in a dartdoc. Writing this package's
registry binding, that paragraph was copied across and adapted for
`HKEY_CLASSES_ROOT`.

The mutation gate then refused to go red: swapping `-2147483648` for
`0x80000000` changed no test result. A direct probe of all four predefined
hives, both spellings, `RegOpenKeyExW`, Windows 11 (26200):

```
HKEY_CLASSES_ROOT    key=https      signed=0  unsigned=0
HKEY_CURRENT_USER    key=Software   signed=0  unsigned=0
HKEY_LOCAL_MACHINE   key=Software   signed=0  unsigned=0
HKEY_USERS           key=.DEFAULT   signed=0  unsigned=0
                                    (0 = ERROR_SUCCESS)
```

Both work. Re-reading the sibling's entry, its evidence is that
`package:win32`'s generated source *spells it* signed — an argument from
spelling, not a measured failure. Its own stated rule is *"a value you can
recite is still a value you have not checked"*, and the consequence went
unchecked; this package then propagated the claim a second time.

**What changed:** the signed spelling stays — it is what the header means
(`(LONG)` casts before widening, so the handle really is `0xFFFFFFFF80000000`)
and it matches `package:win32`. What changed is the *reason* recorded beside it,
from "the other one breaks" to "the other one is not what the header says, and
only `RegOpenKeyExW` on this version has been measured". The clearance carries
its validity condition rather than a claim the code cannot support.

**Second finding, from the same gate.** The separator guard in
`isSchemeRegistered` also survived mutation: without it,
`https\shell\open\command` opens that key and still answers `false`, because no
`URL Protocol` value lives there. It is defence for a caller reaching the seam
directly — `Uri.scheme` cannot contain a separator — and both the code comment
and the test now say that instead of implying a fix.

**Cost had the gate not run:** two dartdoc paragraphs asserting measured facts
that were not measured, in a file whose entire purpose is marshalling nobody can
check by eye.

---
