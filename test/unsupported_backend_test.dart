@TestOn('vm')
library;

import 'package:ffi_url_launcher/src/backends/unsupported_backend.dart';
import 'package:test/test.dart';

void main() {
  group('UnsupportedUrlLauncherBackend', () {
    test('throws rather than returning a quiet false', () {
      // Returning `false` here would be indistinguishable from "no application
      // is registered", which is a completely different situation.
      expect(
        () => const UnsupportedUrlLauncherBackend(
          'linux',
        ).launch(Uri.parse('https://a.test')),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('names the refused platform and the supported ones', () {
      // Sibling `just_autostart` shipped a message that named the *running*
      // platform as unsupported while listing it as supported in the same
      // sentence (its lessons #5). The two halves are asserted together here so
      // the message cannot contradict itself unnoticed.
      Object? thrown;
      try {
        const UnsupportedUrlLauncherBackend(
          'linux',
        ).launch(Uri.parse('https://a.test'));
      } catch (error) {
        thrown = error;
      }

      final message = (thrown as UnsupportedError).message as String;
      expect(message, contains('linux'));
      expect(message, contains('Windows'));
    });

    test('does not list the refused platform as supported', () {
      // The self-contradiction guard: whatever platform was refused must not
      // also appear in the "supported" half of the sentence.
      // `macos` is the case that matters, and the one a hand-written list gets
      // wrong: the package is *for* macOS, so a message that names its
      // supported platforms from intent rather than from what is actually
      // wired will refuse "macos" and list macOS as supported in the same
      // breath. The other three can never expose that, which is why a version
      // of this test without `macos` passed against a hardcoded list.
      for (final os in ['macos', 'linux', 'android', 'ios']) {
        Object? thrown;
        try {
          UnsupportedUrlLauncherBackend(os).launch(Uri.parse('https://a.test'));
        } catch (error) {
          thrown = error;
        }
        final message = ((thrown as UnsupportedError).message as String)
            .toLowerCase();
        final supportedHalf = message.split('supported').last;
        expect(
          supportedHalf,
          isNot(contains(os)),
          reason: '"$os" was refused but appears in the supported list',
        );
      }
    });
  });
}
