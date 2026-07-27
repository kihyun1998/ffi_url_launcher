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
| `lib/src/url_launcher_backend.dart` | `UrlLauncherBackend` — the seam. Two operations, identical across platforms; the differences live in *how* the OS is asked, never in *what operations exist* |
| `lib/src/url_launcher_platform.dart` | OS name → backend, **as a pure function of the string**, so every arm is testable off-host |
| `lib/src/url_safety.dart` | the shape check — a pure function over `Uri`, no platform calls, so it is testable on any runner |
| `lib/src/exceptions.dart` | sealed exception hierarchy. Sealed on purpose: adding a failure mode makes the analyzer point at every exhaustive switch |
| `lib/src/backends/unsupported_backend.dart` | throws from both operations rather than returning a quiet `false` |
| `lib/src/backends/windows/` | hand-written `shell32` / `advapi32` bindings, the return-code decoding, and the `Run`-style scheme lookup. The marshalling **is** the dangerous part — no interface over it and no fake of it |
| `lib/src/backends/macos/` | hand-written `libobjc` / AppKit bindings, the `objc_msgSend` declarations and the autorelease-pool discipline |
| `example/` | the **only in-repo consumer seam** — reaches the package through the public API only. No separate `pubspec.yaml`, so `dart analyze` covers it but `dart test` does **not** run it (see Step 7) |

**Naming note.** The design record in `.scratch/` sketched the seam as
`NativeUrlApi`. The family's convention is `<Domain>Backend`
(`AutostartBackend`, `IdleSource`), so the seam is `UrlLauncherBackend` and its
lookup method is `canOpen(Uri)` — deliberately *not* `schemeRegistered(String)`,
which is Windows vocabulary that would misdescribe the macOS arm.

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
  Measured on Windows 11 (26200), with the window watched on screen:
  `zzznotreal://x` returns 42 and raises the *"you'll need a new app to open
  this link"* picker; the **empty string** returns 42 and opens **File
  Explorer**. What the shell "successfully launched" is something of its own, so
  `SE_ERR_NOASSOC` is **not reachable through a URL scheme** on modern Windows
  and `launch()` returning `true` does not mean anything the user wanted opened.
  The registry check (`canLaunchUrl`) is the only reliable answer, which is why
  it is a separate operation rather than a convenience. See
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
- **`HKEY_CLASSES_ROOT` is a merged view** of `HKLM\Software\Classes` and
  `HKCU\Software\Classes`. Reading it therefore covers per-user installs, which
  is most modern applications. Reading `HKLM` alone would miss them.
- **Scheme registration and file-extension association are different layers.**
  `HKCR\file` carries `URL Protocol` unconditionally, so a `file:` URL always
  answers "launchable" while `ShellExecuteW` may still fail with 31 for an
  unassociated extension. Measured on a real machine.
- **`ShellExecuteW` accepts forward slashes in a drive path.** This is what makes
  the `Uri`-scheme-of-length-1 case an execution vector rather than a curiosity.

**macOS**

- **`NSWorkspace.open` returns a bare `BOOL`** with no error code, while the
  Windows path has a rich one. The public exception therefore carries a
  **nullable** platform code, and it is always null on macOS. Do not invent a
  code to make the platforms look symmetric.
- **A Dart CLI has no Cocoa runloop, so nothing drains the autorelease pool.**
  Autoreleased objects accumulate until process exit unless the call is wrapped
  in an explicit `objc_autoreleasePoolPush` / `Pop`. Sibling `just_font_scan`
  already solved this for CoreText; the same discipline applies here.
- **`objc_msgSend` must be declared per call signature.** Reusing one declaration
  across calls with different return types breaks silently on arm64.
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

**Cross-repo rules are N/A until first publish.** Nothing is published yet, so
the SDK-floor constraint, the two-consumer signal and the report-upstream duty
all assume consumers that cannot be seen from here. The only consumer seam is
`example/`, in the same commit and the same gate, so a drift shows up
immediately. **The after-merge downstream loop is N/A on the same ground.** All
of it becomes live at the first publish.

## Step 4 — proof method per layer

| Layer | Proof |
|---|---|
| **Shape check** (`url_safety.dart`) | table-driven tests over the **exact strings that were measured to fool a naive guard** — `C:\Windows\System32\calc.exe`, `\\attacker\share\evil.exe`, `evil.bat` — alongside the ones that must pass (`file:`, `ms-settings:`, `mailto:`, a custom scheme). A test built only from obviously-bad inputs proves nothing here |
| **Return-code decoding** | a fake backend returning each documented `ShellExecuteW` code, asserting the three-way split (`> 32` → true, `31` → false, everything else → typed throw) |
| **Windows scheme lookup** | ask through our FFI, then cross-read the same key with a **different reader** — `reg query "HKCR\<scheme>" /v "URL Protocol"`. Our reader agreeing with our writer proves nothing about what Windows thinks |
| **macOS handler lookup** | ask through our FFI, then cross-read with the OS's own tool — `/usr/bin/open` on a known-absent scheme fails with a distinct error, on a known-present one succeeds |
| **Launch, failure half** | a **path that does not exist** returns 2 and opens no window — this is what proves the library loaded, the symbol resolved, UTF-16 marshalling survived, and the code→exception mapping fired. CI-safe. ⚠ **Not** "an unregistered scheme returns `false`": that was this doc's original claim and the measurement falsified it (`lessons.md` #4) |
| **Launch, success half** | manual, once per backend. A browser actually appearing is the assertion, and there is no automated substitute |
| **Consumer round-trip** | N/A until first publish. The link mechanism when it applies: `dependency_overrides: {ffi_url_launcher: {path: ../ffi_url_launcher}}` in the consumer, then the consumer's **full** suite |

**Trap — the tautological proof.** Our reader agreeing with our writer says
nothing about whether Windows or `NSWorkspace` will accept what we produced.
Every OS-facing layer above cross-reads with an OS-native tool for that reason.

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
- **Decision records** — `docs/adr/`, created lazily. **Areas that already carry a
  record: none.** That empty list is what the filing step checks before proposing
  a spine, so a cluster with a home never gets a second one — keep it current as
  records land.
- **The issue tracker** is the decision trail until `docs/adr/` exists. The
  design record for the initial slice lives in
  `.scratch/ffi-url-launcher/issues/` — seven tickets that carry the *why*, not
  only the *what*.

**What earns a record here:** two or more of theflow's promotion triggers in one
pass. Below that bar, one trigger is a decision in its issue, attached to (or
opening) a spine issue.

## Step 7 — gate matrix

Two runners, identical commands. Ubuntu is deliberately **not** in the matrix:
this package supports Windows and macOS only, and a green Linux job would prove
only that the pure logic is host-independent.

```
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Plus a guard that no other gate can express:

```
dart compile exe   # in a throwaway consumer that depends on this package
```

- **Why that guard exists.** The package's central promise is that it adds no
  build hooks. `package:objective_c` and any `hooks:`-declaring dependency would
  break `dart compile exe` outright — *"'dart compile' does not support build
  hooks, use 'dart build' instead"* — and the failure appears in a **consumer**,
  never in this repo's own tests. A dependency added for convenience would pass
  every other gate.
- **The blind spot here is per-runner, not per-member.** The Windows runner is the
  *only* one that executes a registry call or `ShellExecuteW`; the macOS runner is
  the *only* one that touches `NSWorkspace`. Never read a green matrix as "the
  backend works".
- **`dart test` does not run `example/`.** It has no separate `pubspec.yaml`, so
  `dart analyze` covers it, but nothing executes it. This gap is recorded, not
  closed.
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
