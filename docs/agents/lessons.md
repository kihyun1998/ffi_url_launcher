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

**But the window is not what 42 means — corrected after re-running.** The first
version of this entry explained 42 as *"the shell successfully launched its own
picker"*. Three runs of the identical string say otherwise:

| Run | How | Status | Dialog |
|---|---|---|---|
| 1 | `dart test`, skips removed | 42 | **no** |
| 2 | `dart run` probe (with a second, never-used scheme) | 42 | yes |
| 3 | `dart run` probe, that string alone | 42 | yes |

Same input, same machine, same return value, different screen. So 42 does not
mean a picker was launched; it means **the shell accepted the request and does
not report what it did with it**. That is the durable fact, and it is the one
the design rests on.

Run 3 also falsifies the obvious explanation for run 1 — "Windows only asks once
per scheme" — because the scheme that had already produced a dialog produced
another. What is left is that the two `dart run` invocations showed it and the
one `dart test` invocation did not, which is **n=1 on the only difference** and
is not enough to build on.

The conclusion is unchanged: an unregistered scheme answers success, so
`launch()` cannot answer "can this be opened" and reading the registry
(`canLaunchUrl`, #3) is the only reliable check.

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

## #7 — The guards were right, the reasons written beside them were not — Step 5

**Rule it proves:** a completeness pass earns its cost on the *reasons* as much
as on the gaps; and the refuting lens is what stops a plausible improvement from
shipping.

The registry binding carries two input guards. Both were documented as defence
with no measured consequence. A pass over the FFI measured what
`RegOpenKeyExW` actually does with each, opening under `HKEY_CLASSES_ROOT`:

```
""                          status=0  handle=0x-80000000   <- the hive handle itself
"\"                         status=0  handle=0x232         <- a real handle, HKCR root
"https\shell\open\command"  status=0  handle=0x232
"https"                     status=0  handle=0x232         (control)
```

Both **succeed**. The empty name returns the *predefined hive handle*, so
without that guard the code closes a predefined key — Microsoft documents the
consequence as *"The predefined handles are not thread safe. Closing a
predefined handle in one thread affects any other threads that are using the
handle."* Harmless here, with single-threadedness as the recorded condition
rather than as an assumption. The bare separator reopens the HKCR root as a real
handle; the example the comment gave, `https\shell\open\command`, was the weaker
case. The reference implementation takes the empty-name path for input `":"`.

**The refuting lens killed the pass's own proposal.** The first lens found that
138 of 280 HKCR keys carrying `URL Protocol` have no `shell\open\command` —
including `file`, `callto`, `sms`, `tel` — and read that as this package
over-answering. Adding that second test would have been a plausible fix. The
refuter checked it: `HKCR\claude` has `URL Protocol`, **zero subkeys**, and
`Get-AppxPackage` lists Claude as installed. MSIX package activation bypasses
`shell\open\command` entirely, so the "improvement" converts a documented
over-answer into **false negatives** for every packaged app.

**A scoping that was right but untested.** `canLaunchUrl(Uri.parse('https:'))`
answers `true`, and so do `mailto:` and `ms-settings:`, while `file:` is
refused. That asymmetry is correct — a scheme-only `file:` URL resolves to the
current drive's root, a target the caller did not name, while the others are
each application's own empty case — but nothing asserted it, so the next reading
of ADR-0001 could widen case 4 "for consistency". There is a test for it now,
and widening the rule takes it red.

**Also cleared, with their ground:** no handle leak (500 deliberately leaked
handles moved `GetProcessHandleCount` 143 → 643 → 143, validating the counter;
40,000 real calls moved it by the one lazy DLL load). An embedded NUL truncates
below the guard, but all five public routes — `Uri.parse`, `Uri(scheme:)`,
percent-escapes, and `allowUnsafe` — raise `FormatException` first. The macOS
per-URL / Windows per-scheme asymmetry the pass flagged as unrecorded is
recorded twice already, in `theflow.md` and in ticket 03.

---

## #8 — macOS is honest where Windows lied — Steps 1, 4

> ⚠ **Two claims in the original of this entry were wrong, and #9 is the entry
> that caught them.** Both came from one probe that never loaded AppKit. The
> corrections are inline below, struck where they stood. What survives — that
> `NSWorkspace.open` answers `NO` honestly — was re-measured with the framework
> genuinely mapped in and holds.

**Rule it proves:** to pin a runtime fact, instrument a probe rather than
assume the reference's model holds; and the CI-safe failure-half input is chosen
by measuring what is UI-free, never by what "looks inert".

Windows' launch path cannot answer "can this open" — an unregistered scheme
comes back as 42, success, sometimes with a dialog (#4). The natural assumption
was that macOS is the same and its integration test would need the same care.
It is not. A probe against the real Objective-C runtime, AppKit and
`NSWorkspace` on macOS 14.5 (arm64), each `open` re-run on its own with the
screen watched:

```
[[NSWorkspace sharedWorkspace] openURL:@"zzznotreal-ffiurllauncher://x"] -> NO,  no window   <- WRONG, see below
[[NSWorkspace sharedWorkspace] openURL:@"file:///zzz-does-not-exist.zzzq"] -> NO,  no window
```

⚠ **The first row is what #9 falsified twice over.** `NSWorkspace` was `nil` in
that probe, so nothing was ever asked and nothing could have appeared; and when
the question was genuinely put, that input **does** raise a panel. The second
row re-measured true.

**`NSWorkspace.open` returns `NO` honestly** — this half is right, and was
re-measured with AppKit actually loaded.

> ⚠ **Correction (#9).** The claim that it "opens nothing" for *both* inputs,
> and therefore that macOS "can assert both an unregistered scheme and a missing
> file directly in CI", is **false**. Re-measured with the screen watched and
> each call isolated:
>
> | input | returns | on screen |
> |---|---|---|
> | `file:///zzz-…-does-not-exist.zzzq` | `NO` | nothing |
> | `zzznotreal-ffiurllauncher://x` | `NO` | **a modal panel** — *"there is no application set to open the URL"*, with App Store / Choose Application / Cancel |
>
> So macOS is **not** the exception here: the CI-safe input is the same on both
> platforms — a target that does not exist, never a scheme nothing is registered
> for. The original probe saw no panel because `NSWorkspace` was nil and no
> shell hand-off ever happened. `ns_workspace_integration_test.dart` asserted
> the scheme input live for one commit; it is now skipped and documented, like
> its Windows twin.

What is genuinely different from Windows is only the **return value's honesty**:
there an unregistered scheme answers *success* (42), here it answers `NO`. The
UI hazard is common to both.

The asymmetry is worth stating plainly because it inverts the package's own
recurring hazard: on Windows every cheap answer over-promises, so `false` from
`launch` is effectively unreachable for a scheme; on macOS `NSWorkspace.open`'s
`false` is reachable and means what it says. `MacOpenOutcome.notOpened` carries
that.

**Two facts measured in the same probe, kept because they are not obvious:**

- **`[NSURL URLWithString:]` is lenient.** It returned a non-nil `NSURL` for the
  empty string, for `"not a url with spaces"`, and for every scheme tried. So
  the `invalidUrl` branch of `MacOpenOutcome` is nearly unreachable from real
  input, which is exactly why the backend's `openUrl` seam is injectable — the
  fake is the only way to exercise that arm, and a machine will not produce it
  on demand.
- ~~**`[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:]` returned
  `nil` for everything — including `https://dart.dev` and `mailto:`**, so #5 is
  not a quick add and needs its own measurement.~~
  > ⚠ **Withdrawn (#9). This was the probe's nil `NSWorkspace`, not the API.**
  > With AppKit actually loaded, the same call through the same FFI returns
  > `/Applications/Google Chrome.app` for `https:`, `Mail.app` for `mailto:`,
  > `TextEdit.app` for `file:`, and `nil` only for a scheme nothing handles —
  > matching Swift exactly. The API was never the problem, and #5 was
  > straightforward. The `UnimplementedError` stub #4 shipped was the right call
  > for the wrong reason: it deferred work on evidence that did not exist.

**Measurement caveat, carried from #4.** The "no window" observation was made
under `dart run`. On Windows the picker differed between `dart run` and
`dart test` for the same input, so the same caveat is written into the macOS
integration test. The mechanism differs, though: macOS returns a plain `NO` with
no shell hand-off, so a harness-dependent window is not expected the way it was
on Windows. Re-measure on a new macOS major before trusting it blindly.

**Why reading the reference could not settle it.** The Swift plugin maps
`workspace.open(nsurl)` straight to its boolean result and says nothing about
whether a `NO` is silent or pops UI — that is a platform behaviour, not a line of
code. Only running it says so, which is the same shape as #4.

---

## #9 — A probe measured a class that was never loaded, and negative-only assertions could not have told — Steps 1, 4, 5

**Rule it proves:** a cheap **`no`** is as dangerous as a cheap `yes` — this
package's recurring hazard runs in both directions. And: a test suite made
entirely of negative assertions cannot tell a real negative from a question
nobody was asked.

Setting out to build #5, the first job was to explain #8's claim that
`URLForApplicationToOpenURL:` answered `nil` even for `https:`. The cross-reader
settled it in one run — the **same question in Swift**, which is a different
reader by theflow Step 4's rule:

```
NSWorkspace.shared.urlForApplication(toOpen:)      # Swift
  https://dart.dev  -> /Applications/Google Chrome.app
  mailto:a@b.com    -> /System/Applications/Mail.app
  file:///etc/hosts -> /System/Applications/TextEdit.app
  zzznotreal://x    -> NIL
```

The API was perfect. Our FFI was not. The cause, found by measuring both ways in
one process:

```
BEFORE loading AppKit:  objc_getClass("NSWorkspace") = NULLPTR
AFTER  loading AppKit:  objc_getClass("NSWorkspace") = 0x1f4440580
```

The #4 probe declared `final appkit = DynamicLibrary.open('…/AppKit');` and
**never referenced it**. Dart top-level finals are lazy, so AppKit was never
mapped in, so the runtime had never heard of `NSWorkspace` — and **messaging
`nil` in Objective-C is not an error.** It quietly returns `nil`/`0`/`NO`. Every
question the probe asked was answered by nobody, in the negative, and every
answer looked exactly like a real object saying no.

`NSString` and `NSURL` still worked throughout, which is what made it so
convincing: they live in Foundation, which the Dart VM already links, so URL
construction succeeded while the workspace calls silently returned nothing.

**Why the test suite had no power here.** The shipped library was *not* broken —
it called `ensureAppKitLoaded()`, so the suite was exercising correct code and
was right to be green. The defect is subtler: every macOS assertion #4 shipped
was a *negative* — `notOpened`, `notOpened`, `false` — and a nullptr class
satisfies all of them perfectly. So the suite could not **distinguish** a loaded
framework from an unloaded one, and would have stayed green had the load ever
gone missing. What gave it that power was #5 adding the first **positive**
assertion — `canOpen('https://…')` must be `true` — which no amount of silence
satisfies. Mutation-checked: deleting the AppKit load turns 8 tests red now, and
would have turned **zero** red before.

**Cost, and what it did and did not reach.** The shipped library was always
correct — it called `ensureAppKitLoaded()`, and the browser really opened, which
is why the success-half manual proof passed. The damage was to the written
record and to CI safety:

- two claims in #8 stated as measured (corrected there);
- `#4` deferred `canOpen` to a later ticket on evidence that did not exist;
- `ns_workspace_integration_test.dart` asserted, live, an input that raises a
  modal panel — the exact CI trap `lessons.md` #4 exists to prevent, reproduced
  on the other platform one commit later.

**What replaced it.** `ensureAppKitLoaded()` — whose only statement was an
unused `_appKit.handle;`, flagged in review as a dead check — is gone. Classes
now resolve through `_classInAppKit`, which calls `DynamicLibrary.open`
**directly** (a real side-effecting call, not an unused read a compiler may
drop) and **throws** when the lookup comes back `nullptr`. The dead check became
the live one, in the place the bug actually was.

**Verified in a compiled binary, because `dart run` could not answer it.** The
worry that AOT might drop the load is only testable where AOT actually runs, so
the throwaway consumer now calls the real lookup rather than merely resolving a
backend:

```
$ dart compile exe bin/main.dart -o bin/main.exe && ./bin/main.exe
canLaunchUrl(https://dart.dev)  = true      <- the positive; false would mean the load was dropped
canLaunchUrl(zzznotreal://x)    = false
```

A **positive** answer out of a compiled executable is what proves the framework
was mapped in — the same asymmetry as above, now applied to the release build.
The `dart compile exe` gate had previously only printed a resolved backend type,
which this bug would have sailed through.

**The generalisable trap.** Any FFI whose failure mode is a valid-looking
falsy value: `objc_msgSend` to a nil class, a `dlsym` miss behind a null-check
that returns a default, an empty collection from an uninitialised handle. When
the "not wired up" state and the "wired up, answer is no" state produce the same
bytes, **only a positive assertion distinguishes them** — so every OS-facing
layer needs at least one test that fails if the OS was never actually asked.

---

## #10 — "Registered on every Windows install" was not, and CI said so on its first run — Steps 4, 7

**Rule it proves:** a machine you did not configure is a different reader. An
environment assumption that a developer machine silently satisfies is still an
assumption, and CI is the cheapest instrument that can falsify it.

The very first run of the new workflow (#6) came back with exactly one red, on
the Windows leg:

```
test\windows\scheme_registry_test.dart: isSchemeRegistered answers true for
schemes Windows always registers
  Expected: true
    Actual: <false>
  "mailto" is registered on every Windows install
```

The test asserted `['http', 'https', 'mailto', 'file']` were all registered,
with the reason string stating it as universal. On a `windows-latest` runner —
a headless Windows Server image with no mail client — **nothing claims
`mailto`**. `http`, `https` and `file` all answered `true`, so the FFI, the
access mask and the predefined-handle spelling were all fine; the claim about
the world was the only thing wrong.

**Why it survived review.** It was true on the developer machine, and it reads
like a fact about Windows rather than a fact about *one* Windows. The distinction
it missed is the one the fix now turns on: `http`/`https` are registered by the
bundled browser and `HKCR\file` carries `URL Protocol` unconditionally — those
are properties of the OS — whereas `mailto` is registered by *an application
someone installed*. The test was mixing the two categories under one reason
string.

**What the same run proved on purpose.** Both `dart compile exe` legs passed,
including Windows, which is what says `canLaunchUrlSync('https://…')` answered
`true` on a machine nobody had configured. That is the positive assertion #9
demanded, now running somewhere other than a laptop that already worked.

**The cost had CI not existed:** none of this was reachable by reasoning. Six
slices were built and reviewed against one Windows desktop and one macOS laptop,
and the first contact with a differently-provisioned machine found a false
assertion in under a minute. That is the whole argument for #6, and it paid on
run one.

---

## #11 — The test exercised the right code at the wrong scale, so it measured nothing — Steps 4, 5

**Rule it proves:** a test's **scale is part of its validity**. Running the
correct code path proves nothing if the effect being guarded against is smaller
than the noise at that size — and the name will still claim otherwise.

`ns_workspace_integration_test.dart` carried a test called *"autorelease
discipline — hundreds of real calls do not accumulate or crash"*. It ran 500
iterations of both macOS operations. Asked directly whether it guarded the
autorelease pool, the mutation gate said no:

```
# inAutoreleasePool reduced to `return body();` — the pool gone entirely
$ dart test test/macos/
+16 ~1: All tests passed!
```

**Measured, with `ProcessInfo.currentRss` and two passes** so one-time warm-up
could be told apart from steady state:

| 50,000 calls | pass 1 | pass 2 |
|---|---|---|
| with pool (shipped) | +16 KB | **+0 KB** |
| no pool | **+10,208 KB** | **+10,208 KB** |

The leak is real, linear and unbounded — about **209 bytes per call**. At the
500 iterations the test used, that is ~104 KB: comfortably inside RSS noise. The
test was two orders of magnitude too small to see the thing it was named for.

**What it did prove, and what that was worth.** It caught crashes, which is not
nothing — a marshalling fault that walked off a buffer would have shown. But the
name promised accumulation, and `theflow.md`'s rule that every guard states
which question it answers applies to test names as much as to dartdoc. This one
answered a narrower question than its name.

**A second reading of the same evidence, in the package's favour.** The pool
*works*. Ticket 04's criterion — "confirm autoreleased objects do not accumulate
over hundreds of calls" — had been satisfied by proxy since it shipped, and is
now satisfied by measurement.

**What replaced it.** 50,000 iterations, a warm-up pass first, and an assertion
on `ProcessInfo.currentRss` growth against a 4,000 KB ceiling. The ceiling is
derived from the table above rather than tuned to pass: correct code produced 0,
the regression produces ten to twenty megabytes, and everything between is
headroom. Mutation-checked — disabling the pop now fails loudly:

```
resident memory grew 22976KB over 50000 calls, past the 4000KB ceiling.
```

**Why it was easy to miss in review.** The test ran real FFI against the real
frameworks, looped, and asserted on every iteration. Everything about its shape
said "this is thorough". Nothing about reading it reveals that 500 was chosen
without ever measuring what 500 would show — which is the same species as
`lessons.md` #6, where a guard's *reason* was never checked, and #9, where a
suite of negative assertions could not distinguish two states. Filed as issue
#11 before fixing.

---

## #12 — The cure for #11 was about to become the disease on the other platform — Steps 4, 5, 7

**Rule it proves:** an instrument is part of a test's validity, exactly as scale
was in #11. A guard can run the right code, at the right scale, with a mutation
gate in place, and still measure nothing — because the counter it reads cannot
see the resource it is guarding.

Windows had no handle- or memory-accumulation guard; macOS got one in #11. The
obvious move was to port #11's shape — 50,000 iterations, a warm-up pass, an
assertion on `ProcessInfo.currentRss` growth. **That test would have been green
with the defect in place.**

Measured on Windows 11 (26200), `RegCloseKey` deleted from `isSchemeRegistered`
and nothing else changed, 100,000 lookups:

| instrument | shipped code | `RegCloseKey` removed |
|---|---|---|
| `GetProcessHandleCount` | 143 → 143 (**+0**) | 2143 → 52143 (**+50,000**) |
| `QuotaPagedPoolUsage` | +0 B (byte-exact) | **+802,816 B** |
| `ProcessInfo.currentRss` | +204 KB / +92 KB | **+252 KB** |

A leaked `HKEY` is a **kernel object**. It is charged to the process's paged-pool
quota and never appears in the address space RSS measures, so the leaking run and
the clean run land in the same noise band. The resource kind decides the
instrument: RSS for the macOS autorelease pool, handle count for the Windows
registry handle. Neither substitutes for the other.

**The counter had been used here before, and that is the sharper half.** The #7
completeness pass already cleared the handle-leak concern with
`GetProcessHandleCount` and validated it by leaking 500 handles on purpose. So
the missing thing was never the measurement — it was that **a one-time clearance
does not fail when someone reintroduces the defect.** Issue #13 was filed saying
Windows "has no guard", which is true, while implying the concern had never been
measured, which is false; the correction was posted to the issue on finding it.
The general form: a cleared concern recorded with its validity condition is a
*fact*, and a fact is not a *gate*.

**A second design assumption died on measurement.** #13 specified a **strict
equality** assertion, on the grounds that the handle count is noise-free — 143 →
143 reproduced exactly across every probe run. A probe of two suites says that
was unsafe:

```
PROBE-A pid=27400
PROBE-B pid=27400  handles=169          <- same process
PROBE-B after opening 200 files  =369   <- while A was still dwelling
PROBE-B after closing            =169
```

`dart test` runs suites as **isolates in one process**, so every process-wide OS
counter is shared state across test files — and unlike the scratch-key collision
in `just_autostart`'s lessons #8, this one needs no shared *name*: merely
existing is enough. Sampled 17M times during a full suite run the band is only
2–3 handles, but a suite that opens files moves it by 200. So the guard asserts a
**derived ceiling**, and iterations drop from #11's 50,000 to 20,000, because a
precise instrument buys back the scale a noisy one has to spend.

**The ceiling took two goes, and the first one is the lesson.** It was 1,000,
justified by that 200-file probe. Review found two things wrong with it at once:
the 200 is not a number any suite in *this* repo produces — it came from a probe
built to produce it — and at 1,000 the guard is blind to any leak slower than one
handle per 20 calls. **"Why a ceiling rather than equality" and "how big the
ceiling is" are different questions, and one measurement cannot answer both.**
The 200 answers the first (a concurrent suite *can* move this by hundreds, so
equality is unsafe); only the measured 2–3 may set the second. It is now **100** —
33x the measured noise, 200x under the regression.

The same confusion had already produced a worse instance one assertion away. The
positive control's closing check reused that 1,000 ceiling against a signal of
**500**, so a `RegCloseKey` wired to nothing would have left exactly 500 behind
and passed — an assertion that could not fail for the reason its own message
gave, in the file written to document that disease. Mutation-checked after the
fix: a no-op close now reports `closing all 500 handles left 500 behind` against
a bound of 50. **A borrowed threshold is not a derived one**, and this is the
cheapest way to get #11's mistake back after fixing it.

**The guard carries a positive control, for #9's reason.** The main assertion is
a *negative* — "the number did not move" — and this package has already shipped a
whole suite of negatives that could not tell a real answer from a question nobody
asked. A `GetProcessHandleCount` binding whose marshalling silently returned a
constant would satisfy it perfectly. So the file also leaks 500 handles on
purpose and asserts the counter moves and comes back, which is the #7 probe
promoted from a one-off into a standing assertion.

Mutation-checked, both directions:

```
# RegCloseKey commented out
the process gained 20000 kernel handles over 20000 registry lookups,
past the 1000 ceiling.
# restored
+2: All tests passed!
```

### The performance half of the same investigation found nothing to fix — and that took two corrections to establish

Recorded because the *negative* result is what stops the next person re-opening
these three, and because both wrong turns were mine.

- **A performance number measured under `dart run` is measuring the JIT.** Cold
  one-shot lookup: **5,165–10,073 µs under `dart run`, 174–244 µs from a compiled
  binary — 28x.** Every candidate ranked off the JIT number was ranked against a
  cost nobody pays. `Platform.environment`'s first access looked like 25% of the
  cold path at ~1.5 ms; in AOT it is 70 µs. This package's whole promise is
  `dart compile exe`, so **AOT is the only honest measurement**, and the *cold*
  number matters more than the amortised one — a CLI opens one URL and exits.
- **Sequential A-then-B blocks cannot measure a shared OS resource.** Comparing
  `RegGetValueW` (one syscall) against open+query+close (three) that way gave
  +25%, +3%, −25%, −63%, +11%, −18%, −2%, −20% over eight runs — enough spread to
  "prove" any conclusion. The first reading taken from it, *"25% faster"*, was
  noise. Interleaved A/B/A/B with medians and reported spread: **+1.8% / −1.7% /
  +4.6%**, i.e. nothing.
- **Why nothing was there to find.** In AOT, everything this package controls —
  three FFI transitions, one arena, three UTF-16 marshals — is **0.96 µs of a
  ~20 µs lookup, about 5%.** The rest is the registry. That single number kills
  all three candidates at once: the syscall collapse (measured 0), caching the
  `'URL Protocol'` / `'open'` constants (0.58 µs, under the noise floor, at the
  price of a process-lifetime `malloc`), and removing `Platform.environment` (70 µs
  of a 184 µs cold path — the only real candidate, **declined** because buying it
  means reversing the KnownDLLs absolute-path decision `system32.dart` argues for,
  against a cost no human can perceive).

**Cleared, with its validity condition:** the **launch** path accumulates
nothing. Three passes of 5,000 real `ShellExecuteW` calls gave 138 → 16 → **−4**
bytes/call and handles +5 → +5 → −1, i.e. a cache being populated, not a leak — a
single pass had read as 170 bytes/call, close to #11's 209, and could not tell the
two apart. It is not guarded by a test, deliberately: that path holds **no kernel
object of its own**, so there is no release to delete and a mutation gate has
nothing to grip. The clearance holds **as long as that stays true** — the day the
launch path takes ownership of any OS handle, it needs its own guard.
