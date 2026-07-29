import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'objc.dart';

/// What `[[NSWorkspace sharedWorkspace] openURL:]` reported, decoded into the
/// three cases the backend above it has to tell apart.
///
/// This is the macOS counterpart of `ShellExecuteOutcome`, and it is a
/// deliberately smaller world: `NSWorkspace.open` answers a bare `BOOL`, so
/// there is no rich error code to classify and no `platformCode` to carry. The
/// only thing that turns it into three cases rather than two is that the URL
/// might not have parsed at all.
enum MacOpenOutcome {
  /// `openURL:` returned `YES`. The handler was started — **not** "the URL
  /// opened", which `NSWorkspace` does not report any more than the Windows
  /// shell does.
  opened,

  /// `openURL:` returned `NO`. Nothing opened it.
  ///
  /// Unlike the Windows launch path — where an unregistered scheme comes back
  /// as *success* (42, measured) and `false` is effectively unreachable — this
  /// `NO` is **honest and reachable**: measured against a scheme nothing
  /// handles and against a `file:` URL for a missing file, `NSWorkspace.open`
  /// returned `NO` both times (`docs/agents/lessons.md` #8). So on macOS a
  /// `false` from `launch` genuinely means "nothing opened this".
  ///
  /// ⚠ **`NO` does not mean nothing appeared on screen — and this comment used
  /// to say it did.** For an **unregistered scheme** macOS raises a modal panel
  /// — *"there is no application set to open the URL"* — while still answering
  /// `NO`. `NSWorkspace` returns the boolean and `CoreServicesUIAgent` draws
  /// the panel; neither observes the other, so no return value can be read as
  /// evidence about the screen. Only the **missing-`file:`** input is silent,
  /// which is why it is the one the integration test uses and the only launch
  /// input a probe may use (#8's correction, #9).
  ///
  /// The earlier wording here claimed *both* inputs opened no window and cited
  /// #8 for it — which #8 had already withdrawn in a box on the same page. A
  /// probe trusted this line instead of the entry it points at and drove the
  /// scheme input ~1,900 times, putting that many panels on the maintainer's
  /// screen (#14).
  notOpened,

  /// `[NSURL URLWithString:]` returned `nil` — the string is not a URL
  /// `NSURL` can construct.
  ///
  /// Rare in practice: `URLWithString:` is lenient, returning a non-nil `NSURL`
  /// even for inputs like an empty string or one containing spaces (measured).
  /// It is kept as its own case because when it *does* happen it is a genuine
  /// fault, not the ordinary "nothing is registered" — and conflating the two
  /// would let a malformed URL read as "no handler".
  invalidUrl,
}

/// Hands [url] to the macOS shell through `NSWorkspace`, returning what it
/// reported.
///
/// The call path is one line of Objective-C —
/// `[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]]` — sent
/// through the runtime because the package takes no build-hook dependency that
/// would let it be written as Objective-C (`docs/agents/theflow.md`, lessons
/// #1). `url` is passed as text and `NSURL` parses it; there is no per-platform
/// string rewriting the way Windows needs for `file:` URLs, so the (B)-question
/// marshalling of ADR-0001 is a no-op here.
///
/// **Runs on the calling isolate's thread, synchronously.** `NSWorkspace` wants
/// the main thread, so this must not be moved into a spawned isolate — the
/// reason the package's `Future` API wraps a synchronous call rather than
/// offloading one.
///
/// Everything transient is created inside an autorelease pool ([inAutoreleasePool])
/// so repeated launches do not accumulate objects a CLI has no runloop to drain.
MacOpenOutcome workspaceOpenUrl(String url) {
  return inAutoreleasePool(() {
    final nsUrl = _nsUrlFrom(url);
    if (nsUrl == nullptr) return MacOpenOutcome.invalidUrl;

    final workspace = _sharedWorkspace();
    final opened = msgSendIdReturningBool(workspace, selOpenUrl, nsUrl) != 0;

    return opened ? MacOpenOutcome.opened : MacOpenOutcome.notOpened;
  });
}

/// Whether macOS has an application registered to open [url].
///
/// Asks `[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:]`, which
/// answers the URL of the application that *would* be used, or `nil` when
/// nothing would. The reference implementation asks exactly this
/// (`workspace.urlForApplication(toOpen:) != nil`), and it is the current API —
/// the pure-C `LSCopyDefaultApplicationURLForURL` was deprecated in macOS 12.
///
/// **This is a lookup, not an attempt.** It starts nothing and opens no window,
/// which is what makes it safe to call before launching — and, unlike the
/// launch path, safe to exercise in CI against a scheme nothing handles.
///
/// Measured on macOS 14.5, agreeing exactly with the same question asked from
/// Swift: `https:` → Google Chrome, `mailto:` → Mail, `file:` → TextEdit, an
/// unregistered scheme → `nil`.
///
/// A `false` for a URL string `NSURL` cannot construct at all: nothing can open
/// what does not parse, and unlike [workspaceOpenUrl] there is no faulted
/// operation to report — the question "is there a handler" has a truthful
/// negative answer here.
///
/// **Ownership:** the returned `NSURL` comes from a `URLFor…` accessor, not a
/// `copy`/`create`, so it is **autoreleased and not owned** — it must not be
/// released, and the surrounding pool bounds its lifetime. Same discipline as
/// [workspaceOpenUrl].
bool workspaceCanOpenUrl(String url) {
  return inAutoreleasePool(() {
    final nsUrl = _nsUrlFrom(url);
    if (nsUrl == nullptr) return false;

    final workspace = _sharedWorkspace();
    final application = msgSendIdReturningId(
      workspace,
      selUrlForApplicationToOpenUrl,
      nsUrl,
    );

    return application != nullptr;
  });
}

/// `[NSWorkspace sharedWorkspace]` — the process-wide singleton.
///
/// Not owned and never released: it is a shared instance the framework keeps
/// for the life of the process, not something this call created.
Pointer<Void> _sharedWorkspace() =>
    msgSendReturningId(nsWorkspaceClass, selSharedWorkspace);

/// Builds an autoreleased `NSURL` from [url], or `nullptr` if `NSURL` refuses
/// the string.
///
/// Must be called inside an [inAutoreleasePool]: both the intermediate
/// `NSString` and the `NSURL` are autoreleased, so their lifetime is the pool's.
/// The native UTF-8 buffer is freed with the arena as soon as `NSString` has
/// copied it.
Pointer<Void> _nsUrlFrom(String url) {
  return using((arena) {
    final nsString = msgSendCStringReturningId(
      nsStringClass,
      selStringWithUtf8String,
      url.toNativeUtf8(allocator: arena),
    );
    return msgSendIdReturningId(nsUrlClass, selUrlWithString, nsString);
  });
}
