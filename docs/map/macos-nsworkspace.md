# macOS: NSWorkspace through the Objective-C runtime

These are states the OS tracks, or marshalling the reference's language hid, that a first-principles
model omits because the model "looks correct". Read this before touching `lib/src/backends/macos/`, and add an entry
when a pass finds another. Incident evidence: [`lessons.md`](../agents/lessons.md).

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
- **`[NSURL URLWithString:]`'s leniency is SDK-dependent — and the leniency is
  not what the package relies on.** It returns a non-nil `NSURL` for the empty
  string, `"not a url with spaces"`, and every scheme tried **from Dart 3.10.0
  on**. On **3.9.0 and older it runs in a strict RFC 3986 mode**: non-ASCII *and
  spaces* are refused and only percent-encoded input is accepted. Boundary
  measured exactly across 3.8.0 / 3.9.0 / 3.10.0 / 3.11.5 / stable on one macOS
  image, with `NSString` fine for every input — the nil is `URLWithString:`
  alone.

  **This is unreachable through the public API**, and that is not luck: both
  backend methods hand over `url.toString()`, and `Uri.toString()`
  percent-encodes non-ASCII and spaces, which is exactly what the strict mode
  wants. Asserted on 3.9.0 — seven inputs that fail raw all construct fine once
  routed through `Uri`.

  **So the rule is about test inputs, not about the floor.** Any test driving
  `workspaceOpenUrl` / `workspaceCanOpenUrl` must pass
  `Uri.parse(…).toString()`, never a raw literal, or it measures a string the
  package cannot produce — which is how this cost a red matrix and two wrong SDK
  floors (`lessons.md` #13). The one genuinely exposed caller is someone reaching
  the seam directly through `UrlLauncher.withBackend` on an old SDK.

  `MacOpenOutcome.invalidUrl` is therefore still near-unreachable in practice,
  but for a **different reason than originally recorded**: not because `NSURL`
  is lenient, but because `Uri` normalises before it is asked.
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
