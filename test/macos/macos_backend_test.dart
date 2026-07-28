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
    test('throws UnimplementedError until #5, not UnsupportedError', () {
      // The distinction is load-bearing: UnsupportedError means "no backend for
      // this platform" and would misreport macOS as unsupported. This says the
      // operation exists but is not built yet — and it must not answer a
      // launchability question with a quiet, wrong `false`.
      expect(
        () => const MacosUrlLauncherBackend().canOpen(url),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
