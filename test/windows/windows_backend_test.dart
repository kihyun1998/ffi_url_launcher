@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/backends/windows/windows_backend.dart';
import 'package:test/test.dart';

// The *classification* of a ShellExecuteW status is covered by
// `shell_execute_status_test.dart` as a pure function. What this file covers is
// the other half — how a classification becomes the value a caller sees — which
// is the part `launch()` actually promises.
//
// It runs on any host: the shell call is injected, so `shell32.dll` is never
// opened. That matters, because otherwise these three arms would only ever be
// checked on a Windows runner, and two of them would not be checked at all —
// no test can make a real machine return ERROR_ACCESS_DENIED on demand.
void main() {
  WindowsUrlLauncherBackend backendReturning(int status) =>
      WindowsUrlLauncherBackend(shellExecute: (_) => status);

  final url = Uri.parse('https://a.test/x');

  group('WindowsUrlLauncherBackend.launch', () {
    test('answers true when the shell reports it started a handler', () {
      expect(backendReturning(33).launch(url), isTrue);
      expect(backendReturning(42).launch(url), isTrue);
    });

    test('answers false for SE_ERR_NOASSOC rather than throwing', () {
      // 31 is "nothing is registered to open this" — an ordinary answer. A
      // caller must be able to handle it without a try/catch.
      expect(backendReturning(31).launch(url), isFalse);
    });

    test('throws for every other failing status, carrying the code', () {
      for (final status in [0, 2, 3, 5, 8, 26, 27, 28, 29, 30, 32]) {
        expect(
          () => backendReturning(status).launch(url),
          throwsA(
            isA<UrlLaunchException>()
                .having((e) => e.platformCode, 'platformCode', status)
                .having((e) => e.url, 'url', url),
          ),
          reason: 'status $status should raise, not return',
        );
      }
    });

    test('hands the shell the URL as text, unchanged', () {
      final seen = <String>[];
      WindowsUrlLauncherBackend(
        shellExecute: (target) {
          seen.add(target);
          return 42;
        },
      ).launch(Uri.parse('https://a.test/p%20q?x=1&y=2#z'));

      expect(seen, ['https://a.test/p%20q?x=1&y=2#z']);
    });

    test('describes the failure instead of printing the bare number', () {
      // flutter/flutter#138142 is exactly this complaint against the reference
      // implementation: the caller is handed an integer and has to go looking.
      expect(
        () => backendReturning(5).launch(url),
        throwsA(
          isA<UrlLaunchException>().having(
            (e) => e.message,
            'message',
            contains('denied'),
          ),
        ),
      );
    });
  });

  group('WindowsUrlLauncherBackend.canOpen', () {
    test('asks the registry about the scheme, not the whole URL', () {
      // A registry key is named for the scheme. Handing over the whole URL
      // would look up `https://a.test/x?y=1` as a key name and answer false for
      // everything — and every other test in this suite passes either way,
      // which is why this one exists.
      final asked = <String>[];
      WindowsUrlLauncherBackend(
        schemeIsRegistered: (scheme) {
          asked.add(scheme);
          return true;
        },
      ).canOpen(Uri.parse('https://a.test/x?y=1#frag'));

      expect(asked, ['https']);
    });

    test('answers the registry unchanged', () {
      expect(
        WindowsUrlLauncherBackend(schemeIsRegistered: (_) => true).canOpen(url),
        isTrue,
      );
      expect(
        WindowsUrlLauncherBackend(
          schemeIsRegistered: (_) => false,
        ).canOpen(url),
        isFalse,
      );
    });

    test('never launches anything on the way', () {
      // If canOpen ever reached ShellExecuteW, a caller checking before opening
      // would open. The injected launcher records that it was not called.
      var launches = 0;
      WindowsUrlLauncherBackend(
        shellExecute: (_) {
          launches++;
          return 42;
        },
        schemeIsRegistered: (_) => true,
      ).canOpen(url);

      expect(launches, 0);
    });

    test('does not throw when the answer is no', () {
      // "No handler" is an answer, not a failure.
      expect(
        () => WindowsUrlLauncherBackend(
          schemeIsRegistered: (_) => false,
        ).canOpen(url),
        returnsNormally,
      );
    });
  });
}
