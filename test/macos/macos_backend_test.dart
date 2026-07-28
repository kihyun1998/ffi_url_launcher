@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/backends/macos/macos_backend.dart';
import 'package:ffi_url_launcher/src/backends/macos/ns_workspace.dart';
import 'package:test/test.dart';

// The marshalling into `NSWorkspace` is proved against the real frameworks in
// `ns_workspace_integration_test.dart` (macOS only). What this file covers is
// the other half — how a decoded `MacOpenOutcome` becomes the value a caller
// sees — and it runs on any host because the OS call is injected. That matters
// for `invalidUrl`: `NSURL` is lenient enough that a real machine will almost
// never produce it, so a fake is the only way to exercise that arm at all.
void main() {
  MacosUrlLauncherBackend backendReturning(MacOpenOutcome outcome) =>
      MacosUrlLauncherBackend(openUrl: (_) => outcome);

  final url = Uri.parse('https://a.test/x');

  group('MacosUrlLauncherBackend.launch', () {
    test('answers true when NSWorkspace reports it opened the URL', () {
      expect(backendReturning(MacOpenOutcome.opened).launch(url), isTrue);
    });

    test('answers false when nothing opened it, rather than throwing', () {
      // On macOS this is a real, reachable answer (measured), not the near-dead
      // branch it is on Windows — a caller must handle it without a try/catch.
      expect(backendReturning(MacOpenOutcome.notOpened).launch(url), isFalse);
    });

    test(
      'throws for a URL NSURL could not construct, with no platform code',
      () {
        expect(
          () => backendReturning(MacOpenOutcome.invalidUrl).launch(url),
          throwsA(
            isA<UrlLaunchException>()
                .having((e) => e.platformCode, 'platformCode', isNull)
                .having((e) => e.url, 'url', url),
          ),
        );
      },
    );

    test('hands NSWorkspace the URL as text, unchanged', () {
      // ADR-0001 (B) is a no-op on macOS: NSURL parses the string, so what the
      // OS is handed must be exactly `url.toString()` with no rewriting.
      final seen = <String>[];
      MacosUrlLauncherBackend(
        openUrl: (target) {
          seen.add(target);
          return MacOpenOutcome.opened;
        },
      ).launch(Uri.parse('https://a.test/p%20q?x=1&y=2#z'));

      expect(seen, ['https://a.test/p%20q?x=1&y=2#z']);
    });
  });

  group('MacosUrlLauncherBackend.canOpen', () {
    MacosUrlLauncherBackend backendAnswering(bool answer) =>
        MacosUrlLauncherBackend(canOpenUrl: (_) => answer);

    test('answers the lookup unchanged, both ways', () {
      expect(backendAnswering(true).canOpen(url), isTrue);
      expect(backendAnswering(false).canOpen(url), isFalse);
    });

    test('does not throw when the answer is no', () {
      // "Nothing is registered" is an answer, not a failure — a caller must be
      // able to ask without a try/catch.
      expect(backendAnswering(false).canOpen(url), isFalse);
    });

    test('asks about the whole URL, not just the scheme', () {
      // The measured Windows/macOS asymmetry, pinned. Windows reads a per-scheme
      // registry key; macOS asks LaunchServices which application would open
      // *this URL*, so the whole string must reach the lookup — a `file:` URL is
      // answered by its extension's handler, which a scheme-only question could
      // not express.
      final seen = <String>[];
      MacosUrlLauncherBackend(
        canOpenUrl: (target) {
          seen.add(target);
          return true;
        },
      ).canOpen(Uri.parse('file:///tmp/a%20b.txt'));

      expect(seen, ['file:///tmp/a%20b.txt']);
    });

    test('never launches anything on the way', () {
      // `canOpen` must not reach the launch seam at all. If it ever did, asking
      // a question would start an application.
      var launched = false;
      MacosUrlLauncherBackend(
        openUrl: (_) {
          launched = true;
          return MacOpenOutcome.opened;
        },
        canOpenUrl: (_) => true,
      ).canOpen(url);

      expect(launched, isFalse);
    });
  });
}
