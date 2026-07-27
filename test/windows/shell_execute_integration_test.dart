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

    test('marshals non-ASCII targets without corrupting them', () {
      // A UTF-16 conversion that truncated or mis-encoded would change which
      // error the shell reports, or crash. Getting "file not found" back for a
      // path that genuinely does not exist is the assertion.
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

  group('what an unregistered scheme actually does', () {
    // Recorded, not asserted as desirable. On Windows 11 the shell answers 42
    // — success — for a scheme nothing is registered to handle, because what it
    // "successfully launched" is its own look-for-an-app UI. It does *not*
    // answer SE_ERR_NOASSOC.
    //
    // The consequence: `launch()` reporting `true` does not mean the URL was
    // opened by anything the user wanted. `canLaunchUrl` — which reads the
    // registry rather than asking the shell — is the only reliable answer, and
    // that is why it is a separate operation rather than a convenience.
    //
    // This test is skipped because confirming it costs a UI popup on the
    // developer's desktop. Unskip it deliberately when re-measuring.
    test(
      'reports success even though nothing handles it',
      () => expect(shellExecuteOpen('zzznotreal-ffiurllauncher://x'), 42),
      skip: 'opens a "how do you want to open this" UI; measured by hand',
    );
  });
}
