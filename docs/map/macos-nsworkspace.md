# macOS Objective-C runtime binding

## What it is
The raw marshalling into the Objective-C runtime that both macOS operations rest
on: `libobjc`, AppKit, one `objc_msgSend` binding per call signature, the three
classes and five selectors the package sends, and the autorelease pool. (The
path is kept from the earlier map, where it also held launch and lookup; those
are now [macos-launch](macos-launch.md) and
[macos-handler-lookup](macos-handler-lookup.md).)

## Governing decisions
- [ADR-0002](../adr/0002-every-guard-is-asked-six-questions.md) — the
  autorelease guard is one of its exemplars, and FFI object ownership is where
  all six questions are mandatory (`CLAUDE.md`, second-pass trigger 2).

## Design model
- **A nullptr class answers every message with `nil`/`0`/`NO`, silently.** A
  probe held AppKit in a lazy `final` nothing read, so AppKit never loaded and
  `NSWorkspace` "said no" to everything; `NSString`/`NSURL` kept working because
  the Dart VM already links Foundation ([lessons.md](../agents/lessons.md) #9).
  So every class resolves through `_classInAppKit`, which calls
  `DynamicLibrary.open` on the path to a lookup it then checks, and **throws a
  `StateError` on `nullptr`** (`objc.dart — _classInAppKit`; the raw
  `_objcClass` is private for the same reason).
- **`objc_msgSend` is declared once per exact call signature.** On arm64 the
  compiler emits each call with the callee's prototype and the runtime does not
  adapt, so reusing one binding across signatures marshals the wrong registers and
  breaks silently. Four bindings, named for their shape (`objc.dart` comment
  block).
- **`BOOL` is read as `Uint8`, tested `!= 0`** — `_Bool` on arm64, `signed char`
  on x86_64, one byte either way (`objc.dart — msgSendIdReturningBool`).
- **A `SEL` is interned and safe to cache — measured.** On macOS 14.5 (arm64)
  `sel_registerName` returned an identical pointer across 10,000 registrations of
  each name, `sel_getUid` agreed, `sel_getName` round-tripped, and 5,000 unrelated
  registrations moved none of them. Caching saves ~4% on the lookup path (7.2 →
  6.9 µs, ±0.3 µs) — **not the reason**: the reason is that the whole Objective-C
  surface, three classes and five selectors, is now auditable in one place
  (`objc.dart` selector comment block).
- **A Dart CLI has no Cocoa runloop**, so nothing drains the default pool;
  `inAutoreleasePool` pushes and pops one around every operation, with the pop in
  `finally`. Sibling `just_font_scan` solved the same for CoreText.
  Guarded by `test/macos/ns_workspace_integration_test.dart`, *"repeated real
  calls do not accumulate native memory"* (50,000 iterations; ceiling derived
  beside it).
- **Ownership**: classes, selectors and `sharedWorkspace` are runtime-owned and
  never released; `NSString`/`NSURL` from convenience constructors are
  autoreleased; the UTF-8 buffer is freed with the arena once `NSString` has
  copied it (`ns_workspace.dart — _nsUrlFrom`).
- **`[NSURL URLWithString:]` is strict below Dart 3.10.0.** From 3.10.0 it
  accepts the empty string, spaces and every scheme tried; on 3.9.0 and older it
  refuses non-ASCII and spaces and accepts only percent-encoded input — boundary
  measured across 3.8.0 / 3.9.0 / 3.10.0 / 3.11.5 / stable on one macOS image,
  `NSString` fine throughout ([lessons.md](../agents/lessons.md) #13).
  Unreachable through the public API, because both backend methods hand over
  `url.toString()` — asserted on 3.9.0, seven raw-failing inputs construct once
  routed through `Uri`. **So the rule is about test inputs**: any test driving
  `workspaceOpenUrl` / `workspaceCanOpenUrl` passes `Uri.parse(…).toString()`,
  never a raw literal. The exposed caller is one reaching the seam through
  `UrlLauncher.withBackend` on an old SDK — closed by the floor
  ([sdk-floor-runs-in-ci](sdk-floor-runs-in-ci.md)).
- **No build-hook dependency writes this as Objective-C** — `package:objective_c`
  would break `dart compile exe` ([runtime-dependencies](runtime-dependencies.md)).

## Code
- `lib/src/backends/macos/objc.dart — objcGetClass`, `selRegisterName`, `msgSendReturningId`, `msgSendCStringReturningId`, `msgSendIdReturningId`, `msgSendIdReturningBool`, `_objcClass`, `nsWorkspaceClass`, `nsStringClass`, `nsUrlClass`, `selSharedWorkspace`, `selOpenUrl`, `selUrlForApplicationToOpenUrl`, `selStringWithUtf8String`, `selUrlWithString`, `_selector`, `inAutoreleasePool`, `_objc`, `_classInAppKit`, `_objcPoolPush`, `_objcPoolPop`

## Reference behaviour
- Sibling `just_font_scan`'s `coretext_bindings.dart` — `libobjc.A.dylib`, the
  pool push/pop, `CFRelease` ([thegraph.md](../agents/thegraph.md)).

## Cross-cutting invariants
- [platform-libraries-open-lazily](platform-libraries-open-lazily.md)
- [system-libraries-load-by-absolute-path](system-libraries-load-by-absolute-path.md)
- [sdk-floor-runs-in-ci](sdk-floor-runs-in-ci.md)

## Blast radius
- [macOS launch](macos-launch.md) and [macOS handler lookup](macos-handler-lookup.md) — both send their messages through these bindings and depend on the pool bounding every autoreleased object.
- [Proving OS effects](proving-os-effects.md) — a binding change is FFI ownership: all six ADR-0002 questions apply, and the memory guard must still go red when the pool is removed.
- [Runtime dependencies](runtime-dependencies.md) — this file exists because no Objective-C dependency may be taken.

## Known holes / open
**None.**
