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
  final List<Uri> asked = [];

  @override
  bool launch(Uri url) {
    launched.add(url);
    if (throws case final error?) throw error;
    return answer;
  }

  @override
  bool canOpen(Uri url) {
    asked.add(url);
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

  group('the shape check is wired into the facade', () {
    // url_safety_test.dart proves the check decides correctly. This proves the
    // public API actually calls it — a correct check nobody invokes protects
    // nothing, and that gap would pass both suites separately.
    test('refuses a drive path before the backend is reached', () {
      final backend = _RecordingBackend();

      expect(
        () => UrlLauncher.withBackend(
          backend,
        ).launchUrlSync(Uri.parse(r'C:\Windows\System32\calc.exe')),
        throwsA(isA<UnsafeUrlError>()),
      );
      // The point of the check: the string never reaches the OS.
      expect(backend.launched, isEmpty);
    });

    test('refuses an empty URL before the backend is reached', () {
      final backend = _RecordingBackend();

      expect(
        () => UrlLauncher.withBackend(backend).launchUrlSync(Uri.parse('')),
        throwsA(isA<UnsafeUrlError>()),
      );
      expect(backend.launched, isEmpty);
    });

    test('allowUnsafe hands the same URL straight through', () {
      final backend = _RecordingBackend();
      final url = Uri.parse(r'C:\Windows\System32\calc.exe');

      expect(
        UrlLauncher.withBackend(backend).launchUrlSync(url, allowUnsafe: true),
        isTrue,
      );
      expect(backend.launched, [url]);
    });

    test('guards the asynchronous form as well', () {
      final backend = _RecordingBackend();

      expect(
        UrlLauncher.withBackend(backend).launchUrl(Uri.parse('')),
        throwsA(isA<UnsafeUrlError>()),
      );
      expect(backend.launched, isEmpty);
    });

    test('lets an ordinary URL through untouched', () {
      final backend = _RecordingBackend();
      final url = Uri.parse('https://example.com/a?b=1');

      UrlLauncher.withBackend(backend).launchUrlSync(url);

      expect(backend.launched, [url]);
    });
  });

  group('UrlLauncher.canLaunchUrl', () {
    test('answers the backend unchanged, both ways', () async {
      final url = Uri.parse('https://a.test/x');
      final yes = _RecordingBackend();
      final no = _RecordingBackend(answer: false);

      expect(UrlLauncher.withBackend(yes).canLaunchUrlSync(url), isTrue);
      expect(await UrlLauncher.withBackend(no).canLaunchUrl(url), isFalse);
      expect(yes.asked, [url]);
      expect(no.asked, [url]);
    });

    test('asks rather than launches', () {
      // The whole point of this operation: it must have no side effect. If it
      // ever reached `launch`, a caller checking before opening would open.
      final backend = _RecordingBackend();
      UrlLauncher.withBackend(
        backend,
      ).canLaunchUrlSync(Uri.parse('https://a.test'));

      expect(backend.asked, hasLength(1));
      expect(backend.launched, isEmpty);
    });

    test('applies the same shape check as launching', () {
      // Asking "can I open C:\...\calc.exe?" is the same category error as
      // trying to. One gate, both doors — ADR-0001's question (A).
      final backend = _RecordingBackend();

      expect(
        () => UrlLauncher.withBackend(
          backend,
        ).canLaunchUrlSync(Uri.parse(r'C:\Windows\System32\calc.exe')),
        throwsA(isA<UnsafeUrlError>()),
      );
      expect(backend.asked, isEmpty);
    });

    test('allowUnsafe reaches the backend here too', () {
      final backend = _RecordingBackend();
      final url = Uri.parse(r'C:\Windows\System32\calc.exe');

      expect(
        UrlLauncher.withBackend(
          backend,
        ).canLaunchUrlSync(url, allowUnsafe: true),
        isTrue,
      );
      expect(backend.asked, [url]);
    });

    test('refuses a platform with no backend rather than answering false', () {
      // A quiet `false` would be indistinguishable from "no handler here",
      // which is a different fact.
      expect(
        () => UrlLauncher.forOperatingSystem(
          'linux',
        ).canLaunchUrlSync(Uri.parse('https://a.test')),
        throwsA(isA<UnsupportedError>()),
      );
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
