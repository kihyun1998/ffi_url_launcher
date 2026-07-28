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
/// **Private on purpose.** A `nullptr` from here is silent rather than fatal —
/// messaging it answers `NO` to everything — so the raw lookup is not something
/// to hand out. The only caller is [_classInAppKit], which loads the framework
/// first and throws when the lookup fails; every class this package messages
/// comes from there.
Pointer<Void> _objcClass(String name) =>
    using((arena) => objcGetClass(name.toNativeUtf8(allocator: arena)));

/// The `NSWorkspace` class, looked up after AppKit has actually been mapped in.
///
/// {@template ffi_url_launcher.checked_class}
/// **A nullptr class is not an error in Objective-C — it is a silent one.**
/// Messaging `nil` returns `nil`/`0`/`NO` instead of failing, so a class that
/// never loaded answers every question in the negative and looks exactly like a
/// real object saying "no". A probe wrote AppKit as a lazy top-level `final`,
/// never referenced it, and therefore measured `NSWorkspace` saying `NO` to
/// everything — off a class the runtime had never heard of. Cross-reading the
/// same question in Swift is what exposed it (`docs/agents/lessons.md` #9).
///
/// So every class this package messages is resolved through [_classInAppKit],
/// which **checks the lookup and throws**. The load is a direct
/// `DynamicLibrary.open` call whose result feeds the lookup that follows,
/// rather than a bare read of a lazy `final` kept alive only by convention —
/// the shape the failure took the first time. Verified where it actually
/// matters: a compiled `dart compile exe` consumer answers `true` for
/// `https:`, which it could not do if the framework had not been mapped in.
/// {@endtemplate}
final Pointer<Void> nsWorkspaceClass = _classInAppKit('NSWorkspace');

/// The `NSString` class. {@macro ffi_url_launcher.checked_class}
final Pointer<Void> nsStringClass = _classInAppKit('NSString');

/// The `NSURL` class. {@macro ffi_url_launcher.checked_class}
final Pointer<Void> nsUrlClass = _classInAppKit('NSURL');

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

/// Maps AppKit in, then looks [name] up in the Objective-C runtime, throwing if
/// the runtime does not know it.
///
/// Opening AppKit is what *registers* `NSWorkspace` with the runtime; the class
/// is then reached through `objc_getClass`, never out of the returned handle,
/// so the handle itself is discarded. `NSString` and `NSURL` live in
/// Foundation, which AppKit links, so the one open covers all three — but each
/// is still checked, because "which framework provides this" is not something
/// to take on faith when getting it wrong fails silently.
///
/// `DynamicLibrary.open` is called directly rather than cached in a `final`. It
/// is idempotent and cheap — `dlopen` hands back the already-mapped handle —
/// and calling it on the path to a lookup that is then *checked* means the load
/// cannot quietly not-happen, which is the whole failure this guards.
Pointer<Void> _classInAppKit(String name) {
  DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');

  final cls = _objcClass(name);
  if (cls == nullptr) {
    throw StateError(
      'AppKit was loaded but the Objective-C runtime does not know "$name". '
      'Messaging a nullptr class would silently answer NO to everything, so '
      'this fails loudly instead.',
    );
  }
  return cls;
}

// `void* objc_autoreleasePoolPush(void)` / `void objc_autoreleasePoolPop(void*)`
final Pointer<Void> Function() _objcPoolPush = _objc
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'objc_autoreleasePoolPush',
    );
final void Function(Pointer<Void>) _objcPoolPop = _objc
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'objc_autoreleasePoolPop',
    );
