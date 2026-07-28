@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/backends/windows/shell_execute.dart';
import 'package:test/test.dart';

// `ShellExecuteW` does not decode multi-byte UTF-8 percent-escapes in `file:`
// URLs — measured, `docs/agents/lessons.md` #5 — and `Uri.toString()` always
// produces them. Converting the URL to a native path is what closes that, and
// it is pure, so it is asserted here rather than on a Windows runner.
void main() {
  group('shellTargetFor', () {
    test('leaves a non-file URL exactly as the caller wrote it', () {
      for (final url in [
        'https://example.com/a%20b?q=1#frag',
        'mailto:someone@example.com?subject=hi',
        'ms-settings:display',
        'myapp://token/123',
      ]) {
        expect(shellTargetFor(Uri.parse(url)), Uri.parse(url).toString());
      }
    });

    test('decodes a percent-encoded non-ASCII file URL to a native path', () {
      // The exact failure this exists for: an existing file reported as "not
      // found" because the shell was handed %E5%AE%B6… instead of 家.
      expect(
        shellTargetFor(
          Uri.parse('file:///G:/%E5%AE%B6%E3%81%AE%E7%AE%A1%E7%90%86/x.txt'),
        ),
        r'G:\家の管理\x.txt',
      );
    });

    test('decodes percent-encoded spaces', () {
      expect(
        shellTargetFor(Uri.parse('file:///C:/My%20Docs/a.txt')),
        r'C:\My Docs\a.txt',
      );
    });

    test('keeps a percent sign that is part of the file name', () {
      // The reference implementation unescapes the whole URL string, so a file
      // genuinely named `a%20b.txt` becomes `a b.txt` and opens the wrong file
      // — or none. Going through the URI parser instead round-trips it.
      final url = Uri.file(r'C:\tmp\a%20b.txt', windows: true);
      expect(url.toString(), 'file:///C:/tmp/a%2520b.txt');
      expect(shellTargetFor(url), r'C:\tmp\a%20b.txt');
    });

    test('turns a file URL with an authority into a UNC path', () {
      expect(
        shellTargetFor(Uri.parse('file://server/share/%ED%8C%8C%EC%9D%BC.txt')),
        r'\\server\share\파일.txt',
      );
    });

    test('round-trips a path through Uri.file and back', () {
      for (final path in [
        r'C:\Users\User\한글파일.txt',
        r'C:\Program Files\App\thing.exe',
        r'D:\ффи\файл.txt',
      ]) {
        expect(shellTargetFor(Uri.file(path, windows: true)), path);
      }
    });

    test('refuses a file URL that is not a path, saying which part', () {
      // A query or fragment means this is not addressing a file. Handing it to
      // the shell anyway produces "the file was not found", which sends the
      // caller looking in the wrong place.
      //
      // **The exception type is the assertion here**, not just the fact of
      // throwing. `Uri.toFilePath` raises `UnsupportedError`, which this package
      // reserves for "there is no backend for this operating system" — so
      // letting it through would tell a caller on Windows that Windows is
      // unsupported. Reachable only with `allowUnsafe: true`, since the shape
      // check refuses these URLs first; ADR-0001 records why (B) reports a
      // marshalling failure this way rather than raising a shape refusal.
      expect(
        () => shellTargetFor(Uri.parse('file:///C:/a.txt?q=1')),
        throwsA(
          isA<UrlLaunchException>()
              .having((e) => e.message, 'message', contains('query'))
              .having((e) => e.platformCode, 'platformCode', isNull),
        ),
      );
      expect(
        () => shellTargetFor(Uri.parse('file:///C:/a.txt#frag')),
        throwsA(
          isA<UrlLaunchException>().having(
            (e) => e.message,
            'message',
            contains('fragment'),
          ),
        ),
      );
    });

    test('never lets UnsupportedError out, on any file URL shape', () {
      // The type reservation, asserted directly. ADR-0001: `UnsupportedError`
      // means "this platform has no backend" and nothing else, so no (B)-layer
      // input may produce one.
      for (final s in [
        'file:///C:/a.txt?q=1',
        'file:///C:/a.txt#frag',
        'file:///C:/a.txt?q=1#frag',
        'file:',
        'file:///',
      ]) {
        try {
          shellTargetFor(Uri.parse(s));
        } on UnsupportedError {
          fail('shellTargetFor("$s") leaked UnsupportedError');
        } on UrlLaunchException {
          // The permitted failure.
        }
      }
    });
  });
}
