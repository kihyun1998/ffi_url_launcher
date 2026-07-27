@TestOn('windows')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/backends/windows/shell_execute.dart';
import 'package:ffi_url_launcher/src/backends/windows/windows_backend.dart';
import 'package:test/test.dart';

// These drive the real `shell32.dll` through the real FFI bindings. Nothing
// here opens a window: every target is a path that does not exist, which the
// shell rejects outright.
//
// Faking this layer would prove nothing — the marshalling *is* the dangerous
// part, so a green test against a fake would say only that the fake behaves as
// written.
void main() {
  const backend = WindowsUrlLauncherBackend();

  // Measured on Windows 11 (26200). Recorded because the *reachability* of
  // these codes is not obvious from the documentation:
  //
  //   C:\...\does-not-exist\nope.zzzq  -> 2   SE_ERR_FNF
  //   file:///C:/zzz-nope.zzzq         -> 2   SE_ERR_FNF
  //   zzznotreal://x                   -> 42  (success!)  see the group below
  //   ''                               -> 42  (success!)
  const missingPath = r'C:\zzz-ffi-url-launcher-does-not-exist\nope.zzzq';

  group('the real ShellExecuteW', () {
    test('loads, marshals a UTF-16 target, and reports a documented code', () {
      // If the library failed to load, the symbol name were wrong, or the
      // string marshalling were broken, this would not come back as a clean
      // SE_ERR_FNF.
      expect(shellExecuteOpen(missingPath), 2);
    });

    test('survives a non-ASCII target without crashing', () {
      // Deliberately weak, and labelled so.
      //
      // An earlier version of this test claimed the assertion proved the UTF-16
      // marshalling was correct, on the reasoning that a mangled conversion
      // "would change which error the shell reports". That was measured and is
      // false: correct UTF-16, UTF-8 bytes cast to Utf16, and low-byte
      // truncation all return 2 for a path that does not exist. The assertion
      // could not fail for the reason it named — theflow Step 4's tautological
      // proof, in the file that exists to avoid it.
      //
      // What it still buys is crash detection: a marshalling bug that walked
      // off the end of the buffer would not return cleanly at all.
      //
      // A discriminating form needs an existing non-ASCII path, which under the
      // "open" verb means a window. It becomes available for free once the
      // `file:` percent-decoding gap is closed, because then an existing
      // non-ASCII `file:` URL must stop answering 2.
      expect(shellExecuteOpen(r'C:\zzz-없는경로-ффи\nope.zzzq'), 2);
    });
  });

  group('WindowsUrlLauncherBackend against the real shell', () {
    test('raises a launch failure carrying the platform code', () {
      final url = Uri.file(missingPath, windows: true);

      expect(
        () => backend.launch(url),
        throwsA(
          isA<UrlLaunchException>()
              .having((e) => e.platformCode, 'platformCode', 2)
              .having((e) => e.url, 'url', url)
              .having((e) => e.message, 'message', contains('not found')),
        ),
      );
    });
  });

  group('inputs that report success while opening something else', () {
    // Recorded, not asserted as desirable. Measured on Windows 11 (26200) with
    // the window watched on screen, each call run on its own so the window
    // could be attributed:
    //
    //   'zzznotreal-ffiurllauncher://x' -> 42, raises the "you'll need a new
    //                                      app to open this link" picker
    //   ''                              -> 42, opens File Explorer
    //
    // 42 is greater than 32, so both are "success". What the shell successfully
    // launched is something of its own. SE_ERR_NOASSOC is not reachable through
    // a URL scheme at all here, so `launch()` returning `true` does not mean
    // anything the caller wanted opened it — `canLaunchUrl`, which reads the
    // registry instead of asking the shell, is the only reliable answer.
    //
    // Both are skipped: confirming either costs a window on the developer's
    // desktop, which is also why neither may ever run in CI. Unskip
    // deliberately when re-measuring on a new Windows build.
    test(
      'an unregistered scheme reports success and raises the app picker',
      () => expect(shellExecuteOpen('zzznotreal-ffiurllauncher://x'), 42),
      skip: 'opens the "new app needed" dialog; measured by hand',
    );

    test(
      'the empty string reports success and opens File Explorer',
      // The worse of the two: a dialog at least tells the user something went
      // wrong, while Explorer appearing looks like an unrelated accident and
      // the call still answers `true`. An empty or unsubstituted config value
      // reaching launchUrl reproduces this exactly — and ticket 02's shape
      // check, which requires a scheme, is what blocks it.
      () => expect(shellExecuteOpen(''), 42),
      skip: 'opens a File Explorer window; measured by hand',
    );
  });
}
