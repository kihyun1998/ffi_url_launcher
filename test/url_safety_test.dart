@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/url_safety.dart';
import 'package:test/test.dart';

// A **shape** check, never a trust check. It answers one question — *does this
// denote a local path rather than a URL?* — and it exists because the answer
// depends on how `ShellExecuteW` reads a string, which a caller has no way to
// know. Everything about whether a URL is *trustworthy* stays with the caller.
//
// Pure, so every case runs on every runner; ticket #4 gets the same protection
// on macOS for free.
void main() {
  group('checkUrlShape accepts', () {
    test('ordinary web URLs', () {
      for (final url in [
        'https://example.com',
        'http://example.com/a/b?c=1#d',
        'https://例え.テスト/パス',
      ]) {
        expect(() => checkUrlShape(Uri.parse(url)), returnsNormally);
      }
    });

    test('non-web schemes, including custom ones', () {
      // Refusing these would be a trust decision, and trust is the caller's.
      for (final url in [
        'mailto:someone@example.com',
        'tel:+15551234',
        'sms:+15551234',
        'ms-settings:display',
        'myapp://token/123',
        'zoommtg://zoom.us/join?confno=1',
      ]) {
        expect(() => checkUrlShape(Uri.parse(url)), returnsNormally);
      }
    });

    test('file URLs — deliberately, and this is an execution vector', () {
      // `file:` is a supported desktop feature; the reference implementation
      // goes out of its way to make it work. `file:///C:/…/calc.exe` therefore
      // passes every check here and will execute. The README says so beside
      // what *is* blocked, because a partial guard described as "validated"
      // moves a caller's belief without moving their risk.
      for (final url in [
        'file:///C:/Users/me/report.pdf',
        'file:///C:/Windows/System32/calc.exe',
        'file://server/share/doc.txt',
      ]) {
        expect(() => checkUrlShape(Uri.parse(url)), returnsNormally);
      }
    });
  });

  group('checkUrlShape refuses', () {
    test('a Windows drive path, which parses as a one-letter scheme', () {
      // Measured: `Uri.parse(r'C:\Windows\System32\calc.exe')` yields
      // scheme='c', hasScheme=true, and `ShellExecuteW` accepts the
      // forward-slashed form and *executes* it. A `hasScheme` guard alone
      // passes this — which is why the length test exists.
      for (final path in [
        r'C:\Windows\System32\calc.exe',
        r'D:\tmp\evil.bat',
        'c:/Windows/System32/calc.exe',
      ]) {
        expect(
          () => checkUrlShape(Uri.parse(path)),
          throwsA(
            isA<UnsafeUrlError>().having(
              (e) => e.reason,
              'reason',
              UnsafeUrlReason.driveLetter,
            ),
          ),
          reason: '"$path" is a local path, not a URL',
        );
      }
    });

    test('a URL with no scheme at all', () {
      // The UNC and bare-filename cases. `hasScheme` is false for these, so
      // they need the *other* half of the check — either test alone leaves a
      // hole.
      for (final path in [
        r'\\attacker\share\evil.exe',
        'evil.bat',
        'some/relative/path',
        '',
        '   ',
      ]) {
        expect(
          () => checkUrlShape(Uri.parse(path)),
          throwsA(
            isA<UnsafeUrlError>().having(
              (e) => e.reason,
              'reason',
              UnsafeUrlReason.noScheme,
            ),
          ),
          reason: '"$path" has no scheme',
        );
      }
    });

    test(
      'the empty URL specifically — a measured defect, not a hypothesis',
      () {
        // `ShellExecuteW('')` answers 42 (success) and opens a File Explorer
        // window. An unsubstituted template value or a blank config entry
        // reaching launchUrl reproduces it exactly. See #9.
        expect(
          () => checkUrlShape(Uri.parse('')),
          throwsA(isA<UnsafeUrlError>()),
        );
      },
    );

    test('a file URL that names no file', () {
      // Found by the completeness pass on #2 and reproduced: these all
      // normalise to `file:///`, pass a scheme-only check, and `shellTargetFor`
      // turns each into a bare `\` — which `Directory(r'\').existsSync()`
      // reports as true, resolving to the current drive root. Handing that to
      // the shell opens Explorer there: the same outcome as the empty-string
      // defect (#9) by a different route, because the URL *has* a scheme.
      for (final url in ['file:', 'file://', 'file:/', 'file:///']) {
        expect(
          () => checkUrlShape(Uri.parse(url)),
          throwsA(
            isA<UnsafeUrlError>().having(
              (e) => e.reason,
              'reason',
              UnsafeUrlReason.notAFilePath,
            ),
          ),
          reason: '"$url" names no file',
        );
      }
    });

    test('a file URL carrying a query or fragment', () {
      // Not a safety case but the same class of shape judgement: such a URL
      // cannot be converted to a path at all. Catching it here is what stops
      // `Uri.toFilePath`'s `UnsupportedError` from surfacing, which the public
      // API documents as meaning "this platform has no backend" — a caller
      // would read a malformed URL as "Windows is unsupported".
      for (final url in ['file:///C:/a.txt?q=1', 'file:///C:/a.txt#frag']) {
        expect(
          () => checkUrlShape(Uri.parse(url)),
          throwsA(
            isA<UnsafeUrlError>().having(
              (e) => e.reason,
              'reason',
              UnsafeUrlReason.notAFilePath,
            ),
          ),
          reason: '"$url" cannot denote a file path',
        );
      }
    });

    test('but not a file URL that does name something', () {
      // The rule is "names no file", not "looks unusual". A path with no drive
      // resolves against the current one and a missing file fails as
      // SE_ERR_FNF, which is an ordinary answer — over-blocking here would cost
      // real callers for no measured hazard.
      for (final url in [
        'file:///C:/x.txt',
        'file:///nodrive/x',
        'file://server/share/x',
      ]) {
        expect(() => checkUrlShape(Uri.parse(url)), returnsNormally);
      }
    });

    test('naming the URL and saying which shape it was', () {
      // "Refused" with no reason sends the caller looking in the wrong place.
      Object? thrown;
      try {
        checkUrlShape(Uri.parse(r'C:\Windows\System32\calc.exe'));
      } catch (error) {
        thrown = error;
      }

      final error = thrown! as UnsafeUrlError;
      expect(error.url.toString(), contains('Windows'));
      expect(
        error.toString(),
        contains('c'),
        reason: 'names the scheme it saw',
      );
      expect(
        error.toString().toLowerCase(),
        contains('drive'),
        reason: 'says why, not just that',
      );
    });
  });

  group('the error type', () {
    test('is distinguishable from a launch failure', () {
      // A caller has to be able to tell "I passed something bad" from "the
      // system could not open it" — the two want different handling.
      expect(
        UnsafeUrlError(
          url: Uri.parse('c:/x'),
          reason: UnsafeUrlReason.driveLetter,
        ),
        isNot(isA<UrlLaunchException>()),
      );
    });

    test('is still catchable as the package-wide exception', () {
      expect(
        UnsafeUrlError(
          url: Uri.parse('c:/x'),
          reason: UnsafeUrlReason.driveLetter,
        ),
        isA<UrlLauncherException>(),
      );
    });
  });
}
