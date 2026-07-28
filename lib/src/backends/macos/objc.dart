// ignore_for_file: non_constant_identifier_names
// The Objective-C runtime symbols keep their C spelling — `objc_getClass`,
// `sel_registerName`, `objc_msgSend` — because that is what a reader greps for
// and what Apple's documentation names. Renaming them to satisfy the lint would
// hide the very thing this file is a binding for.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The Objective-C runtime, and just enough of it to send four messages.
///
/// This is the macOS equivalent of `system32.dart`: the raw marshalling, kept
/// on its own so the dangerous part can be read in one place. Nothing here
/// decides anything — it turns Dart strings into `objc_msgSend` calls and hands
/// the result back. The classification of what those calls mean lives in
/// `ns_workspace.dart`.
///
/// **Loaded by absolute path**, mirroring the System32 policy on Windows: a
/// bare `dlopen("libobjc.A.dylib")` follows a search order a consumer's
/// directory can sit at the front of. `/usr/lib` and `/System/Library` are not
/// writable without SIP disabled, so an absolute path removes the question.
///
/// **Every top-level `final` here is lazy**, as all Dart top-level finals are,
/// which is what lets this file be compiled into the package on Windows and
/// Linux without ever opening a dylib that is not there.

// `objc_getClass(const char*)` -> Class. A Class is an `id`, pointer-sized.
final Pointer<Void> Function(Pointer<Utf8>) objcGetClass = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('objc_getClass');

// `sel_registerName(const char*)` -> SEL. Registering a selector that already
// exists returns the existing one, so this is safe to call per message send.
final Pointer<Void> Function(Pointer<Utf8>) selRegisterName = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)
    >('sel_registerName');

// `objc_msgSend` — declared once per exact call signature.
//
// On arm64 there is a single `objc_msgSend` symbol and the compiler emits a
// call with the *callee's* prototype at each site; the runtime does not adapt.
// Reusing one Dart binding across messages with different argument or return
// types therefore marshals the wrong number or width of registers and breaks
// silently (`docs/agents/theflow.md`, macOS hidden-state list). So each of the
// four messages this package sends has its own binding below, named for its
// shape rather than for the message, because the *shape* is what makes it a
// distinct C function as far as the ABI is concerned.

/// `id objc_msgSend(id, SEL)` — a nullary message returning an object, e.g.
/// `[NSWorkspace sharedWorkspace]`.
final Pointer<Void> Function(Pointer<Void>, Pointer<Void>) msgSendReturningId =
    _objc.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
    >('objc_msgSend');

/// `id objc_msgSend(id, SEL, const char*)` — one C-string argument returning an
/// object, e.g. `[NSString stringWithUTF8String:]`.
final Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>)
msgSendCStringReturningId = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>)
    >('objc_msgSend');

/// `id objc_msgSend(id, SEL, id)` — one object argument returning an object,
/// e.g. `[NSURL URLWithString:]`.
final Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
msgSendIdReturningId = _objc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
    >('objc_msgSend');

/// `BOOL objc_msgSend(id, SEL, id)` — one object argument returning a `BOOL`,
/// e.g. `[NSWorkspace openURL:]`.
///
/// The return is read as a `Uint8`, not `Bool`, on purpose. `BOOL` is `_Bool`
/// on arm64 macOS but `signed char` on x86_64 macOS; both are one byte carrying
/// 0 or 1, and reading that byte and testing `!= 0` is correct for either,
/// whereas committing to the `_Bool` ABI would be a bet on the architecture.
final int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
msgSendIdReturningBool = _objc
    .lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
    >('objc_msgSend');

/// Looks up the class named [name], or `nullptr` if the runtime has no such
/// class. The returned `Class` is a runtime singleton and is **not owned** —
/// never released.
///
/// Call [ensureAppKitLoaded] first for any class that lives in AppKit
/// (`NSWorkspace`): the runtime only knows a class once the framework binary
/// carrying it has been mapped in, which does not happen on its own in a plain
/// Dart process.
Pointer<Void> objcClass(String name) =>
    using((arena) => objcGetClass(name.toNativeUtf8(allocator: arena)));

/// Maps AppKit (and, through it, Foundation) into the process so the runtime
/// can resolve `NSWorkspace`, `NSURL` and `NSString`.
///
/// The work is a side effect: *evaluating* the lazy `_appKit` final runs
/// `DynamicLibrary.open`, which maps the framework in. There is nothing to
/// check afterwards — `open` **throws** if the framework is absent, so a
/// missing AppKit surfaces as that throw, not as a null handle. Reading
/// `.handle` is just the touch that forces the evaluation. Idempotent and cheap
/// after the first call, since a resolved final is not re-run.
void ensureAppKitLoaded() {
  _appKit.handle;
}

/// Registers (or looks up) the selector [name]. Selectors are interned for the
/// life of the process and are **not owned**.
Pointer<Void> selector(String name) =>
    using((arena) => selRegisterName(name.toNativeUtf8(allocator: arena)));

/// Runs [body] inside an Objective-C autorelease pool.
///
/// The convenience constructors this package calls — `stringWithUTF8String:`,
/// `URLWithString:` — hand back **autoreleased** objects: alive until the
/// thread's current pool drains, owned by no one in the meantime. A Dart CLI
/// has no Cocoa runloop to drain the default pool, so without an explicit one
/// those objects accumulate until the process exits. Sibling `just_font_scan`
/// hit the same wall with CoreText; the discipline is identical. Pushing a pool
/// before the messages and popping it after is what bounds the lifetime to a
/// single launch.
///
/// `finally` guarantees the pop even if [body] throws, so an exception cannot
/// leak the pool.
T inAutoreleasePool<T>(T Function() body) {
  final pool = _objcPoolPush();
  try {
    return body();
  } finally {
    _objcPoolPop(pool);
  }
}

final DynamicLibrary _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');

// AppKit is opened only so its symbols — `NSWorkspace`, `NSURL`, `NSString` —
// are registered with the Objective-C runtime by the time `objc_getClass` is
// asked for them. The classes are reached through the runtime, not through
// these bindings, so nothing is looked up out of this handle directly; opening
// it is the whole job. `NSURL` and `NSString` live in Foundation, which AppKit
// links, so one open covers all three.
final DynamicLibrary _appKit = DynamicLibrary.open(
  '/System/Library/Frameworks/AppKit.framework/AppKit',
);

// `void* objc_autoreleasePoolPush(void)` / `void objc_autoreleasePoolPop(void*)`
final Pointer<Void> Function() _objcPoolPush = _objc
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'objc_autoreleasePoolPush',
    );
final void Function(Pointer<Void>) _objcPoolPop = _objc
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'objc_autoreleasePoolPop',
    );
