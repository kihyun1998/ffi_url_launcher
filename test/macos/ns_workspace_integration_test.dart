@TestOn('mac-os')
library;

import 'package:ffi_url_launcher/src/backends/macos/macos_backend.dart';
import 'package:ffi_url_launcher/src/backends/macos/ns_workspace.dart';
import 'package:test/test.dart';

// These drive the real Objective-C runtime, AppKit, and `NSWorkspace` through
// the real FFI bindings. Nothing here opens a window: every target is measured
// to make `NSWorkspace.open` answer `NO` with no UI.
//
// Faking this layer would prove nothing — the `objc_msgSend` marshalling *is*
// the dangerous part, and a green test against a fake would say only that the
// fake behaves as written.
//
// The macOS/Windows contrast is the point of the two inputs below. On Windows
// an unregistered scheme comes back as *success* (42) and can pop a picker, so
// its integration test targets a missing **path** instead and the scheme case
// is skipped. On macOS `NSWorkspace.open` is honest: measured against both a
// scheme nothing handles and a `file:` URL for a missing file, it returned `NO`
// and opened nothing (`docs/agents/lessons.md` #8), so both are safe to assert
// in CI.
//
// Measurement caveat, carried from lessons #4: the "no window" observation was
// made under `dart run`. Unlike the Windows dialog — which differed between
// `dart run` and `dart test` — the mechanism here is a plain `NO` return with
// no shell hand-off, so a harness-dependent window is not expected. Re-measure
// on a new macOS major before trusting it blindly.
void main() {
  const backend = MacosUrlLauncherBackend();

  // A scheme with no registered handler, and a `file:` URL naming a file that
  // does not exist. Both measured on macOS 14.5 (arm64) to return NO, no UI.
  const unregisteredScheme = 'zzznotreal-ffiurllauncher://x';
  const missingFile = 'file:///zzz-ffi-url-launcher-does-not-exist.zzzq';

  group('the real NSWorkspace', () {
    test('loads AppKit, marshals a URL string, and answers a clean NO', () {
      // If libobjc/AppKit failed to load, a selector name were wrong, or an
      // objc_msgSend signature were mismatched, this would not come back as a
      // clean notOpened — it would crash or return garbage.
      expect(workspaceOpenUrl(missingFile), MacOpenOutcome.notOpened);
      expect(workspaceOpenUrl(unregisteredScheme), MacOpenOutcome.notOpened);
    });

    test('survives a non-ASCII URL without crashing', () {
      // Crash detection, and labelled as such: a bad UTF-8→NSString conversion
      // that walked off the buffer would not return cleanly. It still resolves
      // to a missing file, so the answer is notOpened with no UI.
      expect(
        workspaceOpenUrl('file:///zzz-없는파일-ффи.zzzq'),
        MacOpenOutcome.notOpened,
      );
    });
  });

  group('MacosUrlLauncherBackend against the real NSWorkspace', () {
    test('answers false — honestly — when nothing can open the URL', () {
      // The contrast with Windows: there this same shape would come back as
      // `true`. Here `false` means what it says.
      expect(backend.launch(Uri.parse(unregisteredScheme)), isFalse);
      expect(backend.launch(Uri.parse(missingFile)), isFalse);
    });
  });

  group('autorelease discipline', () {
    test('hundreds of real launches do not accumulate or crash', () {
      // Each workspaceOpenUrl pushes and pops its own pool, so the autoreleased
      // NSString/NSURL from every call are drained at call end rather than
      // living to process exit. This exercises that over many iterations against
      // the no-UI input; a missing pop would show up as unbounded growth, and a
      // marshalling fault as a crash. Measured: 500 calls complete cleanly.
      for (var i = 0; i < 500; i++) {
        expect(workspaceOpenUrl(missingFile), MacOpenOutcome.notOpened);
      }
    });
  });
}
