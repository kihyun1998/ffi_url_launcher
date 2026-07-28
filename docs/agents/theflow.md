# theflow bindings (ffi_url_launcher)

Project-specific data for the `theflow` skill. The skill holds the portable
*method*; this file holds the *bindings*. Per-incident evidence lives in
[`lessons.md`](lessons.md).

Identity lives in [`../../CLAUDE.md`](../../CLAUDE.md). There is **no
`CONTEXT.md` and no `docs/adr/` yet** — until one exists, "the decision trail"
below means the issue tracker plus the design record in
`.scratch/ffi-url-launcher/issues/`.

## Reasoning bindings (project-wide)

**Prior art cross-checked throughout:** `flutter/packages` —
`url_launcher_windows` (the C++ plugin this replaces for pure-Dart consumers),
`url_launcher_macos` (its Swift counterpart), and `url_launcher_web` (the only
one of the six implementations that validates a URL, and therefore the
precedent for how this family handles a dangerous scheme). Plus the sibling
repos named in the routing table.

**Tie-breaker — behaviour follows prior art; facts follow measurement.** API
shape and naming follow `url_launcher` so a consumer arriving from it is not
surprised (`launchUrl(Uri)`, `canLaunchUrl(Uri)`, `Future<bool>`). But *how the
operating system actually behaves* is settled by our own measurement, and a
measurement outranks a sentence in anyone's README — including the reference's
own source. The two halves separate cleanly here: we adopted the reference's
signature **and** rejected its unvalidated desktop passthrough in the same
breath, because the first is a convention and the second is a hole we measured.

**The reference is C++ and Swift; we are Dart. Its correctness does not
transfer.** Both desktop implementations lean on language machinery that has no
Dart equivalent — Win32 headers that cast predefined handles before widening
them, `MultiByteToWideChar` for UTF-16, ARC for Objective-C lifetimes. A line
that is right in the reference can be wrong when transliterated. Read the
reference for **which API to call and in what order**; derive the marshalling
from the OS symbol's own documentation and from the sibling repos that already
solved it.

**Record which type each decision was.** A derivation falls to a better
derivation; a product judgement falls only to the person who made it. Decisions
here are tagged `[product]` where the maintainer chose, so a later adversarial
pass does not reopen a call that was theirs.

## The recurring failure here: every cheap "yes" answers a narrower question

Each surface of this package can return an affirmative that a caller will read
as an answer to a **broader** question than the one it actually answers:

| The affirmative | What it actually means | What the caller reads it as |
|---|---|---|
| `Uri.parse` succeeded, `hasScheme` is true | the string has a colon in it | "this is a URL, not a local path" |
| `canLaunchUrl` returned true | a handler is registered for the *scheme* | "`launchUrl` will succeed" |
| `ShellExecuteW` returned > 32 | the shell started a process | "the URL opened" |
| `NSWorkspace.open` returned YES | the open request was accepted | "the page loaded" |

The measured instance: `Uri.parse(r'C:\Windows\System32\calc.exe')` yields
`scheme = 'c'` and `hasScheme = true`, and `ShellExecuteW` accepts the
forward-slashed form and **executes it**. A `hasScheme` guard therefore reads as
a safety check while providing none.

**Every guard states which question it answers, in its own dartdoc.** When a
pass finds another narrow affirmative, add the row.

### It runs in the other direction too: a cheap "no"

A negative can be just as narrow, and it is **harder** to catch, because the
natural test for a failure path asserts exactly the value a broken call already
returns:

| The negative | What it actually means | What the reader takes it for |
|---|---|---|
| `objc_msgSend` to a nullptr class returned `nil`/`NO` | **nobody was asked** — the framework was never mapped in | "macOS said no" |
| `canOpen` returned `false` | no handler is *registered* | "launching will fail" |
| `launch` returned `false` on Windows | (effectively unreachable for a scheme) | "nothing opened it" |

The measured instance is `lessons.md` #9: a probe that never loaded AppKit read
`NO` off a class the runtime had never heard of, and an entire suite of negative
assertions agreed with it. **Every OS-facing layer therefore needs at least one
positive assertion** — a test that fails if the operating system was never
actually asked. Negative-only coverage cannot distinguish the two states.

## Crate / module map

**Pure Dart, single package.** No Flutter dependency, no native sources, no
`windows/`/`macos/` trees, no `plugin` declaration. The single runtime
dependency is `ffi`, deliberately not `package:win32` — win32 declares
`platforms: windows:`, so depending on it from a package that also supports
macOS misstates the platform support, and it would pull in thousands of
generated bindings to call four functions. No member carries its own
`pubspec.yaml`, so there is **no out-of-workspace member** — that Step 7 blind
spot does not exist here. The real blind spot is per-runner (Step 7).

| Module | Role |
|---|---|
| `lib/ffi_url_launcher.dart` | the public surface; the export list *is* the API contract |
| `lib/src/url_launcher.dart` | the facade. Selects a backend once and delegates unchanged, so a backend's failures reach the caller as thrown |
| `lib/src/url_launcher_backend.dart` | `UrlLauncherBackend` — the seam, and nothing else. Operations are identical across platforms; the differences live in *how* the OS is asked, never in *what operations exist*. Also holds the `{@template}` for the launch contract, so the sentence most likely to go stale exists once |
| `lib/src/supported_platforms.dart` | `supportedPlatforms` — the one table naming a platform, formatting its name, and building its backend. Three separate declarations before, which is one disagreement away from the sibling package's self-contradicting refusal message; a platform cannot now be listed without being wired |
| `lib/src/url_launcher_platform.dart` | OS name → backend, **as a pure function of the string**, so every arm is testable off-host. A lookup in `supportedPlatforms`, not a `switch` |
| `lib/src/url_safety.dart` | **planned (ticket 02)** — the shape check: a pure function over `Uri`, no platform calls, so it is testable on any runner |
| `lib/src/exceptions.dart` | sealed exception hierarchy. Sealed on purpose: adding a failure mode makes the analyzer point at every exhaustive switch |
| `lib/src/backends/unsupported_backend.dart` | throws from both operations rather than returning a quiet `false` |
| `lib/src/backends/windows/` | hand-written `shell32` / `advapi32` bindings, the return-code decoding, and the `Run`-style scheme lookup. The marshalling **is** the dangerous part — no interface over it and no fake of it |
| `lib/src/backends/macos/` | hand-written `libobjc` / AppKit bindings (`objc.dart`), the per-signature `objc_msgSend` declarations and the autorelease-pool discipline; `ns_workspace.dart` sends `[[NSWorkspace sharedWorkspace] openURL:]` and decodes the `BOOL` into `MacOpenOutcome`, and asks `URLForApplicationToOpenURL:` for the handler lookup; `macos_backend.dart` maps both to the caller's values. Classes resolve through `_classInAppKit`, which loads AppKit and **throws on a nullptr lookup** — a silent nil class is what `lessons.md` #9 cost |

Rows marked **planned** do not exist yet. The table is a map of where things go,
not an inventory of what is there; without the marker it reads as the latter and
an agent goes looking for a file that was never written.
| `example/` | the **only in-repo consumer seam** — reaches the package through the public API only. No separate `pubspec.yaml`, so `dart analyze` covers it but `dart test` does **not** run it (see Step 7) |
| `tool/` | the two gates no other gate expresses, as scripts so they run identically in CI and by hand: `compile_exe_guard.dart` (generates a throwaway consumer and compiles it) and `check_dependencies.dart` (the `ffi`-only invariant). Part of the package, so they need no dependency of their own |

**Naming note.** The design record in `.scratch/` sketched the seam as
`NativeUrlApi`. The family's convention is `<Domain>Backend`
(`AutostartBackend`, `IdleSource`), so the seam is `UrlLauncherBackend` and its
lookup method is `canOpen(Uri)` — deliberately *not* `schemeRegistered(String)`,
which is Windows vocabulary that would misdescribe the macOS arm.

**Injection seams are public named constructors and parameters, not
`@visibleForTesting`.** That annotation lives in `package:meta`, and taking it
would break the one-runtime-dependency invariant for an annotation the analyzer
only advises on. Ticket 01 asked for both and the two cannot hold together; the
dependency invariant wins, matching sibling `just_autostart`, which reaches the
same shape with a documented `Autostart.withBackend`. What keeps the seam from
becoming load-bearing public API is that **the types it accepts are not
exported** — `UrlLauncherBackend` is not in `lib/ffi_url_launcher.dart`, so
outside code cannot name the argument without reaching into `src/`.

**Two seams, and they are not the same kind.** `UrlLauncher.withBackend`
replaces a whole platform, and `WindowsUrlLauncherBackend(shellExecute:)`
replaces one call so the status→result arms can be driven with codes a real
machine will not produce on demand. Neither substitutes the **marshalling**,
which is proved against the real DLL instead — a green test against a faked
`ShellExecuteW` would say only that the fake behaves as written.

## Hidden-state list

Read this **before** touching domain semantics. These are the states the OS
tracks, or the marshalling the reference's language hid, that a first-principles
model omits because the model "looks correct". Add to this list when a pass
finds another.

**Windows**

- **Predefined `HKEY` roots are sign-extended on 64-bit.** The Win32 header casts
  to `(LONG)` before widening to `ULONG_PTR`, so `HKEY_CLASSES_ROOT` is
  `0xFFFFFFFF80000000`, not `0x80000000`. In Dart it must be
  `Pointer.fromAddress(-2147483648)`; the unsigned literal produces a handle
  Windows does not recognise. Confirmed for `HKEY_CURRENT_USER` in sibling
  `just_autostart` (its lessons #7, against `package:win32`'s generated source).
- **`ShellExecuteW` signals success with a return value greater than 32.** The
  return type is `HINSTANCE` for historical compatibility; every value ≤ 32 is an
  error code. `SE_ERR_NOASSOC` is 31 and is the common, expected one — "nothing is
  registered to open this", not a fault.
- **`ShellExecuteW` returns once the shell has started a process**, not once the
  target has loaded. It cannot report whether the page opened.
- **An unregistered *scheme* answers 42 — success — not `SE_ERR_NOASSOC`.**
  Measured on Windows 11 (26200). `SE_ERR_NOASSOC` is **not reachable through a
  URL scheme** on modern Windows, so `launch()` returning `true` does not mean
  anything the user wanted opened, and the registry check (`canLaunchUrl`) is
  the only reliable answer — which is why it is a separate operation rather than
  a convenience.
- **What 42 means is "the request was accepted", not "the shell opened its own
  picker".** That second sentence was written here once and does not survive
  re-running: the identical string answered 42 with a dialog under `dart run`
  (twice) and 42 with no dialog under `dart test` (once). The empty string did
  open File Explorer. **Do not explain 42 by a window** — the window is not
  reliably there and the trigger is unidentified. See
  [`lessons.md`](lessons.md) #4.
- **Anything handed to `ShellExecuteW` can open a window, including inputs that
  look inert.** The empty string is the proof. Never call the launch path in CI
  with an input that has not been measured to be UI-free.
- **A path that does not exist answers 2 (`SE_ERR_FNF`), with no UI.** This is
  the reachable error code, and the one the real round-trip proof uses.
- **`RegQueryValueExW` does not guarantee a null terminator** on string values;
  `RegGetValueW` does. This package only tests a value's *existence* and never
  reads its bytes, so the hazard does not bite here — but any change that starts
  reading a value must switch reader.

  **Switching *now* was measured and declined — #14, `wontfix`, `[product]`.**
  `RegGetValueW` takes the subkey and the value name together and opens and closes
  internally, so it collapses three calls into one **and leaves no `HKEY` in our
  hands at all** — the leak class becomes impossible rather than guarded. Measured:
  identical answers on all 11 inputs, zero handle growth over 20,000 calls, and a
  speed difference of +1.8% / −1.7% / +4.6% (interleaved medians), i.e. nothing —
  because in AOT everything this package controls is 0.96 µs of a ~20 µs lookup.
  Declined because there is **no measured defect** (the handle discipline is
  correct and #13 now gates it), and buying the remaining argument would mean
  editing the most dangerous file in the package **and** making #13's guard
  unmutatable — permanently unanswerable on ADR-0002's question 5. **The decision
  is the maintainer's to reverse, not a derivation to re-argue** — but it expires
  on its own if any of these become true: this package starts reading a registry
  *value* (then `RegGetValueW` is mandatory anyway, per the sentence above), a
  *second* registry path appears (#13's guard covers only `isSchemeRegistered`), or
  a handle leak actually happens once. Numbers in `lessons.md` #12.
- **A leaked `HKEY` is invisible to resident memory.** The registry lookup is the
  only place this package holds a **kernel object**, and a kernel object is
  charged to the process's paged-pool quota — never to the address space
  `ProcessInfo.currentRss` measures. Measured, the leaking and the correct run
  land in the same RSS noise band. **So the macOS memory test's shape does not
  port here**: copying `ns_workspace_integration_test.dart`'s `currentRss`
  assertion to Windows produces a test named for accumulation that sits green
  with 50,000 handles leaked behind it — the exact disease #11 was opened for,
  reproduced by copying its cure. The instrument for a kernel object is
  `GetProcessHandleCount`. Numbers in `lessons.md` #12.
- **`HKEY_CLASSES_ROOT` is a merged view** of `HKLM\Software\Classes` and
  `HKCU\Software\Classes`. Reading it therefore covers per-user installs, which
  is most modern applications. Reading `HKLM` alone would miss them.
- **Scheme registration and file-extension association are different layers.**
  `HKCR\file` carries `URL Protocol` unconditionally, so a `file:` URL always
  answers "launchable" while `ShellExecuteW` may still fail with 31 for an
  unassociated extension. Measured on a real machine.
- **`ShellExecuteW` accepts forward slashes in a drive path.** This is what makes
  the `Uri`-scheme-of-length-1 case an execution vector rather than a curiosity.
- **`ShellExecuteW` decodes ASCII percent-escapes in a `file:` URL but not
  multi-byte UTF-8 ones.** `%20` becomes a space; `%ED%95%9C` is read as three
  literal characters. The reference works around it with `UrlUnescapeA`; this
  package converts to a native path with `Uri.toFilePath` instead. See
  [`lessons.md`](lessons.md) #5.
- **`Uri.toString()` is not identity.** It percent-encodes non-ASCII, spaces and
  `<>"`, and lowercases the scheme. Any reasoning about what the shell receives
  must be done on `toString()`'s output, not on the string the caller wrote —
  the package *manufactures* the encoding that breaks `file:`.
- **`Uri.toFilePath` throws for a query or fragment**, and for any scheme but
  `file`. Measured: `file:///C:/a.txt?q=1` and `#frag` both raise
  `UnsupportedError` naming the offending component. **That error type is
  already spoken for** — the public API documents `UnsupportedError` as "this
  platform has no backend" — so the shape check refuses those URLs before the
  conversion can raise it. A leaked `UnsupportedError` would read as an
  unsupported operating system.
- **Having a scheme is not the same as denoting a target.** `file:`, `file://`,
  `file:/` and `file:///` all normalise to `file:///` and convert to a bare `\`
  — an *existing* directory, the root of the current drive
  (`Directory(r'\').existsSync()` is `true`, resolving to `D:\` here). Opening
  it launches a file browser, which is the empty-string hazard arriving with a
  scheme attached. Any rule written as "does it have a scheme" misses this whole
  class.
- **KnownDLLs decides whether a bare DLL name is safe**, and the family rule is
  to not depend on knowing which. `shell32`, `advapi32`, `ole32` are on the
  list; `dwrite` is not, and a hostile `dwrite.dll` beside the executable *was*
  loaded in a probe while a hostile `shell32.dll` was ignored. Load system DLLs
  by absolute `%SystemRoot%\System32` path regardless.

**macOS**

- **`NSWorkspace.open` returns a bare `BOOL`** with no error code, while the
  Windows path has a rich one. The public exception therefore carries a
  **nullable** platform code, and it is always null on macOS. Do not invent a
  code to make the platforms look symmetric.
- **`NSWorkspace.open`'s `NO` is honest and reachable, unlike the Windows `false`.**
  Measured on macOS 14.5 (arm64): both a scheme nothing handles and a `file:`
  URL for a missing file answer `NO`. This is the inverse of the Windows hazard
  where 42 = success for an unregistered scheme, so on macOS `launch` returning
  `false` genuinely means "nothing opened this". `MacOpenOutcome.notOpened` is
  the decode.
- **But an unregistered scheme still raises a modal panel** — *"there is no
  application set to open the URL"*, with App Store / Choose Application /
  Cancel. `NO` **and** a window; the two are independent. So the CI-safe launch
  input is the same on both platforms — **a target that does not exist**, never
  a scheme nothing is registered for (`lessons.md` #8 correction, #9). A missing
  `file:` URL is measured UI-free and is the one the integration test uses.
- **`URLForApplicationToOpenURL:` is a lookup and shows nothing**, for any input
  including that same scheme. So `canOpen`'s integration test may assert live
  what `launch`'s must skip — the CI hazard belongs to the *operation*, not to
  the URL.
- **A nullptr Objective-C class answers every message with `nil`/`0`/`NO`,
  silently.** AppKit must be mapped in before `objc_getClass('NSWorkspace')`, and
  a lazy `final` holding the `DynamicLibrary` that nothing reads is never
  evaluated — which cost this package a whole false measurement (`lessons.md`
  #9). `NSString`/`NSURL` keep working throughout, because the Dart VM already
  links Foundation, so URL construction succeeds while every workspace call
  quietly says no. Classes therefore resolve through `_classInAppKit`, which
  calls `DynamicLibrary.open` directly and **throws** on a `nullptr` lookup.
- **`[NSURL URLWithString:]` is lenient — nil is nearly unreachable.** It returned
  a non-nil `NSURL` for the empty string, `"not a url with spaces"`, and every
  scheme tried (measured). So `MacOpenOutcome.invalidUrl` almost never fires from
  real input; it exists so a genuine parse failure does not masquerade as "no
  handler", and it is exercised only through the injected `openUrl` seam.
- **`URLForApplicationToOpenURL:` answers per-URL, where Windows answers
  per-scheme.** It returns the application that *would* open this exact URL, or
  `nil`. Measured, agreeing with Swift: `https:` → Google Chrome, `mailto:` →
  Mail, `file:` → TextEdit, unregistered scheme → `nil`. This is why the seam is
  `canOpen(Uri)` and not `schemeRegistered(String)` — and why a `file:` URL is
  answered by its *extension's* handler on macOS, while on Windows `HKCR\file`
  carries `URL Protocol` unconditionally and always answers `true`. **The same
  call, asked about the same URL, can legitimately differ between the two.**
- **The returned `NSURL` is autoreleased, not owned.** It comes from a `URLFor…`
  accessor rather than a `copy`/`create`, so it must not be released; the pool
  around the call bounds it.
- **A Dart CLI has no Cocoa runloop, so nothing drains the autorelease pool.**
  Autoreleased objects accumulate until process exit unless the call is wrapped
  in an explicit `objc_autoreleasePoolPush` / `Pop`. Sibling `just_font_scan`
  already solved this for CoreText; the same discipline applies here.
- **`objc_msgSend` must be declared per call signature.** Reusing one declaration
  across calls with different return types breaks silently on arm64.
- **A `SEL` is interned and safe to cache — measured, not recited.** On macOS
  14.5 (arm64): `sel_registerName` returned an identical pointer across 10,000
  registrations of each name, `sel_getUid` agreed with it, `sel_getName`
  round-tripped the exact string, and registering 5,000 unrelated selectors
  afterwards moved none of them — so no rehash can leave a cached `SEL` stale.
  Owned by the runtime for the life of the process; never released. The five
  this package sends are resolved once in `objc.dart`, beside the three classes,
  so **the complete Objective-C surface it touches is auditable in one place.**
- **`NSWorkspace` wants the main thread**, and `ShellExecuteW` depends on the COM
  apartment the calling thread already has. Neither call may be moved into a
  spawned isolate. **This is why the package's `Future` API is a wrapper over a
  synchronous call and not a real one** — the async signature exists to keep the
  option open, not because work is offloaded.

**Both**

- **`Uri.parse` on a Windows path succeeds and produces a one-letter scheme.**
  `hasScheme` is true for `C:\...`. Any guard written as "it parsed, so it is a
  URL" is not a guard.
- **A UNC path (`\\host\share\x.exe`) parses with no scheme at all** — so the two
  hazards need two different checks, and either check alone leaves a hole.

## Step 1 — reference routing table

The reference implementation is federated across two languages, and **neither is
Dart**; see the reasoning binding above for why its correctness does not
transfer line-for-line.

| Change type | Real source to read |
|---|---|
| **Which OS API to call, and in what order** | `flutter/packages` — `packages/url_launcher/url_launcher_windows/windows/url_launcher_plugin.cpp` and `packages/url_launcher/url_launcher_macos/macos/url_launcher_macos/Sources/url_launcher_macos/UrlLauncherPlugin.swift`, fetched raw |
| **Public API shape and naming** | `packages/url_launcher/url_launcher/lib/src/url_launcher_uri.dart` — the modern `Uri`-taking surface |
| **URL validation policy in this family** | `packages/url_launcher/url_launcher_web/lib/url_launcher_web.dart` — the only implementation that blocks a scheme, and the shape it chose (blocklist, `false` + warning, not a whitelist and not a throw). Its history is flutter/flutter#136657 |
| **Win32 marshalling from Dart** | the symbol's own Microsoft Learn page for signature and ownership; then sibling **`just_autostart`** (`lib/src/backends/windows/registry.dart`) for hand-written `advapi32` bindings and predefined-handle spelling. Cross-check constants against `package:win32`'s generated source — **never against memory** |
| **macOS ObjC-runtime FFI** | sibling **`just_font_scan`** (`lib/src/macos/coretext_bindings.dart`) — `libobjc.A.dylib`, `objc_autoreleasePoolPush`/`Pop`, `CFRelease`, and the graceful-degrade pattern when a symbol fails to resolve |
| **Pure-Dart package structure, OS-branching FFI** | siblings **`just_autostart`** and **`flutter_inactive_timer`** — both resolve bindings as a pure function of the OS name so every arm is testable off-host |
| **Published state** | `curl -s https://pub.dev/api/packages/ffi_url_launcher` |
| **Hidden state** | the list above, in this file |

**Never use a summarizing fetch on a reference repo.** Fetch the raw tree and the
raw file (`gh api repos/<o>/<r>/git/trees/main?recursive=1`,
`gh api …/contents/<path> --jq .content | base64 -d`) and grep the real lines.
Sibling `just_autostart`'s lessons #1 records a summarizing fetch inventing
native `windows/`/`macos/` directories that did not exist — the premise of that
project would have been answered wrong.

## Step 2 — boundary rule (package = mechanism, calling app = policy)

**Mechanism — this package owns it.** How a URL is handed to the OS handler and
how "is there a handler" is answered on each OS: the `ShellExecuteW` call and its
32-boundary return decoding, the `HKCR` scheme lookup and its sign-extended
handle, the `objc_msgSend` sequence into `NSWorkspace`, `NSString`/`NSURL`
construction and their lifetimes, the autorelease discipline, and the platform
error code → typed exception mapping. All of it is only correct with the OS's own
behaviour in hand.

**The shape check is mechanism, not policy.** `[product]` — that
`Uri.parse(r'C:\...')` yields a one-letter scheme, and that `ShellExecuteW` will
execute the forward-slashed result, is **knowledge of how these specific OS calls
interpret a string**. A caller cannot be expected to know it, so leaving the
check to them is not a boundary — it is a trap with the package's name on it.
This is why the check is on by default. It is deliberately a **shape** check
(does this denote a local path?) and never a **trust** check.

**Policy — the calling application owns it by definition.** Which URL to open and
whether its source is trusted; whether to call `canLaunchUrl` first and what to
do when it says no; whether `file:` should be permitted at all; any scheme
whitelist beyond the shape check; retries; telemetry; and every piece of UI. A
scheme whitelist was weighed as a default and **declined** `[product]` — what
counts as an acceptable scheme differs per application, so owning that list would
be the package absorbing a consumer's concern.

**`allowUnsafe: true` is the concrete expression of this boundary.** The package
performs the check it alone can perform; the caller decides whether it applies.

**The check is partial by design, and says so.** `file:///C:/…/calc.exe` passes
every check and executes. `file:` is a legitimate desktop feature the reference
supports deliberately. Documenting *what is not blocked* beside what is blocked
is therefore part of the mechanism, not a README nicety — a partial guard
described as "validated" is worse than no guard, because it moves the caller's
belief without moving their risk.

**Cross-repo rules are now LIVE — `0.1.0` was published to pub.dev on
2026-07-28.** This paragraph previously read *"N/A until first publish"*, and that
was a clearance whose validity condition has now expired. What changes:

- **The SDK-floor constraint binds.** `environment: sdk: ^3.11.5` is carried down
  to every consumer by a caret range. Raising it is a breaking change for anyone
  on an older SDK, so it moves in a major/minor bump with the reason recorded —
  never as a side effect of using a newer language feature.
- **The `platforms:` block is a public claim, not documentation.** pub.dev renders
  it, so a dependency declaring `platforms: windows:` now contradicts a statement
  consumers can see. `tool/check_dependencies.dart` is the only gate that catches
  it (`lessons.md` #1).
- **The two-consumer signal and the report-upstream duty apply** — and both are
  unobservable from inside this repo, which is the point: report a local guard
  upstream even when the fix here was correct, because that report is what lets
  upstream see a pattern one consumer never can.
- **The after-merge downstream loop is live.** Derive the consumer list at that
  moment by grepping sibling manifests for this package's name; never store it.
- **The `CHANGELOG` is now snapshotted per version.** Never rewrite the `0.1.0`
  entry — pub.dev has it. Open a new version instead.

`example/` remains the only *in-repo* consumer seam, in the same commit and the
same gate, so drift there still shows up immediately.

## Step 4 — proof method per layer

| Layer | Proof |
|---|---|
| **Shape check** (`url_safety.dart`) | table-driven tests over the **exact strings that were measured to fool a naive guard** — `C:\Windows\System32\calc.exe`, `\\attacker\share\evil.exe`, `evil.bat` — alongside the ones that must pass (`file:`, `ms-settings:`, `mailto:`, a custom scheme). A test built only from obviously-bad inputs proves nothing here |
| **Return-code decoding** | a fake backend returning each documented `ShellExecuteW` code, asserting the three-way split (`> 32` → true, `31` → false, everything else → typed throw) |
| **Windows scheme lookup** | ask through our FFI, then cross-read the same key with a **different reader** — `reg query "HKCR\<scheme>" /v "URL Protocol"`. Our reader agreeing with our writer proves nothing about what Windows thinks |
| **macOS handler lookup** | ask through our FFI, then cross-read the **same question in Swift** — `NSWorkspace.shared.urlForApplication(toOpen:)`, run with `/usr/bin/swift`, must name the same application. This is not optional politeness: it is the reader that caught `lessons.md` #9, where our FFI and our own tests agreed with each other and were both wrong. Assert a **positive** (a scheme that resolves to a real app), never only absences |
| **Launch, failure half** | **Windows:** a **path that does not exist** returns 2 and opens no window — this proves the library loaded, the symbol resolved, UTF-16 marshalling survived, and the code→exception mapping fired. CI-safe. ⚠ **Not** "an unregistered scheme returns `false`": that was this doc's original claim and the measurement falsified it (`lessons.md` #4). **macOS:** a **missing `file:` URL** answers `NO` with no window — the same role, and the same *shape* of input as Windows. ⚠ **Not** an unregistered scheme: it answers `NO` too, but raises a modal panel, so it is skipped exactly as its Windows twin is (`lessons.md` #8 correction, #9). ⚠ **And a negative alone proves nothing here** — a nullptr class returns `NO` as convincingly as the real one, so the load must be pinned by a **positive** assertion in the lookup group |
| **FFI object lifetime** (Step 5's second unconditional trigger) | **the instrument is chosen per resource kind, and proved on the resource it is watching.** A kernel object (an `HKEY`) is charged to paged pool and is invisible to RSS; an autoreleased Objective-C object is in the address space and invisible to a handle count. So: `GetProcessHandleCount` for the Windows registry handle, `ProcessInfo.currentRss` for the macOS pool. Each guard needs **three** things, not one — (i) a mutation that deletes the release and turns it red, (ii) a **positive control** proving the counter moves when the resource really leaks, since the assertion itself is a negative and `lessons.md` #9 is what a suite of negatives costs, and (iii) a ceiling **derived** from the measured signal, the measured noise, and the measured worst case, written beside the test |
| **Launch, success half** | manual, once per backend. A browser actually appearing is the assertion, and there is no automated substitute |
| **Consumer round-trip** | **Live since `0.1.0`.** Two forms, and they prove different things. *Pre-release:* `dependency_overrides: {ffi_url_launcher: {path: ../ffi_url_launcher}}` in the consumer, then the consumer's **full** suite — this is what `tool/compile_exe_guard.dart` automates. *Post-release:* a throwaway consumer depending on the **version range**, with no path override, so `pub get` fetches the real archive — the only thing that proves *what actually shipped* works rather than what is in the working directory. Run it once per release: `dart pub get` → `dart compile exe` → the binary must answer a question **positively** (`lessons.md` #9). Verified for `0.1.0`: `canLaunchUrlSync('https://dart.dev')` → `true`, an unregistered scheme → `false`, a drive path → `UnsafeUrlError(driveLetter)`, and exactly two resolved dependencies |

**Trap — the tautological proof.** Our reader agreeing with our writer says
nothing about whether Windows or `NSWorkspace` will accept what we produced.
Every OS-facing layer above cross-reads with an OS-native tool for that reason.

**Trap — a performance number measured under `dart run` is measuring the JIT.**
This package's central promise is that a consumer can `dart compile exe`, so the
consumer's cost is the **AOT** cost, and the two are not close: a cold one-shot
registry lookup measured **5,165–10,073 µs under `dart run` against 174–244 µs
from a compiled binary — 28x**. Every conclusion drawn from the JIT number is
about a cost nobody pays; `Platform.environment`'s first access looked like 25%
of the cold path at 1.5 ms and is 70 µs in AOT. **Compile the probe.** And prefer
the *cold* number to the amortised one — a CLI opens one URL and exits, so
steady-state throughput is not what its user waits for. See `lessons.md` #12.

**Trap — a single-pass memory measurement cannot tell a cache from a leak.**
Both grow on the first pass and only one keeps growing, so one pass reads the
same either way. The launch path measured **170 bytes/call** over one pass —
close enough to the 209 bytes/call of a real macOS leak (#11) to look like one —
and three passes gave 138 → 16 → **−4**, i.e. a cache being populated. **Always
run at least two passes and say which decayed**; a leak holds its rate, a cache
collapses toward zero. This is why the macOS guard warms up before it measures,
and it is the rule that both this project's memory measurements now follow.

**Trap — measuring against a shared OS resource in sequential A-then-B blocks.**
The registry has its own caches and other processes are hitting it, so
consecutive timing blocks measure drift rather than code. Two implementations
that are genuinely within 2% of each other reported +25%, +3%, −25%, −63%, +11%,
−18%, −2%, −20% across eight such runs — a swing wide enough to "prove" whichever
answer you wanted. **Interleave A/B/A/B and compare medians**, alternating which
variant leads, and report the spread beside the median so a claim that does not
clear it cannot be made. Same entry.

**Trap — CI cannot verify the thing the package is for.** A green matrix proves
"the call was shaped as intended", never "the browser opened". The success half
of launch is manual, once per backend, and its absence from CI is a **known gap,
not a covered case.** Say which of the two you have.

**Trap — the example is a proof surface and the tests are not.** Sibling
`just_autostart` shipped 31 green tests alongside a user-facing message that
contradicted itself; running the example caught it. Documentation and
user-facing strings are read, not asserted.

**Trap — a guard that is never exercised against a real launch.** The shape
check's whole purpose is to sit between a caller's string and `ShellExecuteW`.
Prove at least once, by hand, that a blocked string never reaches the shell —
not merely that the function throws.

## Step 5 — unconditional completeness triggers

The completeness pass runs on these **regardless** of the enumeration-risk
judgement, and these are the only paths where a second, *refuting* lens is worth
its cost. `[product]` — chosen by the maintainer.

1. **Anything that decides whether a string reaches `ShellExecuteW`, or that
   builds that string.** The shape check, the `allowUnsafe` path, and any future
   normalisation. A miss here is arbitrary code execution on the user's machine,
   triggered by data the calling application may have received from a network. It
   cannot be undone and it will not look like a failing test.
2. **FFI memory, buffer-size negotiation and object ownership.** UTF-16 length
   arithmetic, registry handle lifetime, `NSString`/`NSURL` lifetimes and the
   autorelease pool. A mistake is not a failing test — it is process corruption,
   or silent corruption that passes.

Everything else is gated on enumeration risk as usual.

## Step 6 — behaviour-describing surfaces

- **`README.md`** — the landing page. It must carry, because each is discovered
  painfully otherwise: the **blocked / not-blocked table** with `file:` named
  explicitly as an execution vector; that `canLaunchUrl` is always true for
  `file:`; that the platform code is null on macOS; and the two claims that are
  the reason to choose this package at all — no Flutter dependency, and
  `dart compile exe` works.
- **`CHANGELOG.md`** — pub.dev **snapshots at publish**. Never rewrite a
  published entry; open a new version.
- **Public dartdoc** — ships verbatim as the API reference. It is the surface most
  likely to still describe the old behaviour, and it lies in a way tests cannot
  catch. Every guard's dartdoc states **which question it answers**, per the
  recurring-failure section.
- **`example/`** — a specification. A new public API is proven by being *used*
  here, and the example must not model a practice the package documents against.
- **`.pubignore`** — **load-bearing, and already relevant.** A top-level `docs/`
  collides with pub's reserved singular `doc/` layout name and makes
  `dart pub publish` refuse outright (sibling `just_autostart`, lessons #4). This
  repo now has `docs/agents/`, so `.pubignore` must exclude `docs/` **and**
  repeat the `.gitignore` entries, because a present `.pubignore` replaces
  `.gitignore` for archive purposes.
- **Decision records** — `docs/adr/`. **Areas that already carry a record:**

  | Record | Status | Area it governs |
  |---|---|---|
  | [ADR-0001](../adr/0001-two-questions-about-every-url.md) | accepted | everything between a caller's `Uri` and the OS call — shape (A) and marshalling (B). Promoted from spine #8 |
  | [ADR-0002](../adr/0002-every-guard-is-asked-six-questions.md) | accepted | **whether a guard can be trusted** — polarity, instrument, scale, threshold, mutation, stated reason. Governs every test asserting an OS-observable effect, and all six are mandatory on Step 5's second unconditional trigger. Promoted after five incidents (#6, #7, #9, #11, #13) each turned out to be one precondition failing |

  This list is what the filing step checks **before** proposing a spine. An
  issue in an area that already has a record is a **conformance item under that
  record**, never a sibling under a new anchor — two homes for one throughline
  is the failure the rung exists to prevent. Keep it current as records land.
- **The issue tracker** — GitHub Issues, per `issue-tracker.md`. **Open spines:
  none** (#8 promoted to ADR-0001 and closed). The long-form design records live
  in `.scratch/ffi-url-launcher/issues/`; each names the issue that carries its
  state, and the issue carries the labels and the blocking edges.

**What earns a record here:** two or more of theflow's promotion triggers in one
pass. Below that bar, one trigger is a decision in its issue, attached to (or
opening) a spine issue.

## Step 7 — gate matrix

**Automated in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)**,
on pull requests and on pushes to `main`. Two runners, identical commands.
Ubuntu is deliberately **not** in the matrix: this package supports Windows and
macOS only, and a green Linux job would prove only that the pure logic is
host-independent. `fail-fast: false`, because the two legs exercise entirely
different backends and one failing says nothing about the other.

```
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Plus **two** guards no other gate can express, one per failure mode a
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
  Committing it would add a second `pubspec.yaml` and create exactly the
  out-of-workspace member this section says does not exist here — `dart test` at
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
- **Convention:** ticket → implement → `/code-review` → commit referencing the
  issue (`Closes #n`) → fast-forward merge to `main` → push → confirm CI green.
  No PR flow; this is a solo repo, matching the family.
- **Release:** `dart pub publish --dry-run` must be **0 warnings**.
  `dart pub publish` is irreversible — **the agent does not run it; the user
  does.**

## War-story index

Per-incident evidence lives in [`lessons.md`](lessons.md), indexed by step. It
starts seeded with the measurements taken while designing this package, since
they are the reason several rules above exist.
