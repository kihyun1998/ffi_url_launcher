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
  /// returned `NO` and opened no window (`docs/agents/lessons.md` #8). So on
  /// macOS a `false` from `launch` genuinely means "nothing opened this".
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
  ensureAppKitLoaded();

  return inAutoreleasePool(() {
    return using((arena) {
      final nsString = msgSendCStringReturningId(
        objcClass('NSString'),
        selector('stringWithUTF8String:'),
        url.toNativeUtf8(allocator: arena),
      );
      final nsUrl = msgSendIdReturningId(
        objcClass('NSURL'),
        selector('URLWithString:'),
        nsString,
      );
      if (nsUrl == nullptr) return MacOpenOutcome.invalidUrl;

      final workspace = msgSendReturningId(
        objcClass('NSWorkspace'),
        selector('sharedWorkspace'),
      );
      final opened =
          msgSendIdReturningBool(workspace, selector('openURL:'), nsUrl) != 0;

      return opened ? MacOpenOutcome.opened : MacOpenOutcome.notOpened;
    });
  });
}
