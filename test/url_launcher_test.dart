@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/url_launcher_backend.dart';
import 'package:test/test.dart';

/// Records what the facade handed down, and answers however the test wants.
///
/// The facade's whole job is to delegate unchanged, so what this asserts is
/// that nothing is rewritten, swallowed, or re-ordered on the way through.
final class _RecordingBackend implements UrlLauncherBackend {
  _RecordingBackend({this.answer = true, this.throws});

  final bool answer;
  final Object? throws;
  final List<Uri> launched = [];

  @override
  bool launch(Uri url) {
    launched.add(url);
    if (throws case final error?) throw error;
    return answer;
  }
}

void main() {
  group('UrlLauncher.launchUrlSync', () {
    test('hands the backend exactly the URL it was given', () {
      final backend = _RecordingBackend();
      UrlLauncher.withBackend(
        backend,
      ).launchUrlSync(Uri.parse('https://a.test/x?y=1'));

      expect(backend.launched, [Uri.parse('https://a.test/x?y=1')]);
    });

    test('returns the backend answer unchanged', () {
      expect(
        UrlLauncher.withBackend(
          _RecordingBackend(answer: true),
        ).launchUrlSync(Uri.parse('https://a.test')),
        isTrue,
      );
      expect(
        UrlLauncher.withBackend(
          _RecordingBackend(answer: false),
        ).launchUrlSync(Uri.parse('https://a.test')),
        isFalse,
      );
    });

    test('lets a backend failure through instead of turning it into false', () {
      final url = Uri.parse('https://a.test');
      final backend = _RecordingBackend(
        throws: UrlLaunchException(
          url: url,
          target: url.toString(),
          message: 'boom',
          platformCode: 5,
        ),
      );

      expect(
        () => UrlLauncher.withBackend(backend).launchUrlSync(url),
        throwsA(
          isA<UrlLaunchException>()
              .having((e) => e.platformCode, 'platformCode', 5)
              .having((e) => e.url, 'url', url),
        ),
      );
      // The call still reached the backend — the exception is not the facade
      // refusing to delegate.
      expect(backend.launched, [url]);
    });
  });

  group('UrlLauncher.launchUrl', () {
    test('answers the same as the synchronous form', () async {
      expect(
        await UrlLauncher.withBackend(
          _RecordingBackend(answer: false),
        ).launchUrl(Uri.parse('https://a.test')),
        isFalse,
      );
    });

    test('surfaces a backend failure as a rejected future, not a throw', () {
      final url = Uri.parse('https://a.test');
      final launcher = UrlLauncher.withBackend(
        _RecordingBackend(
          throws: UrlLaunchException(
            url: url,
            target: url.toString(),
            message: 'boom',
          ),
        ),
      );

      // Calling it must not throw synchronously — an `await`ing caller has to
      // be able to catch this with try/catch around the await.
      late final Future<bool> pending;
      expect(() => pending = launcher.launchUrl(url), returnsNormally);
      expect(pending, throwsA(isA<UrlLaunchException>()));
    });
  });

  group('UrlLauncher.forOperatingSystem', () {
    test('refuses a platform with no backend, naming it', () {
      final launcher = UrlLauncher.forOperatingSystem('linux');

      expect(
        () => launcher.launchUrlSync(Uri.parse('https://a.test')),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(contains('linux'), contains('ffi_url_launcher')),
          ),
        ),
      );
    });
  });
}
