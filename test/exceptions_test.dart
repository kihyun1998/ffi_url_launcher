@TestOn('vm')
library;

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:test/test.dart';

// A failure has to name what the *user* meant, not the wire form. The reference
// implementation pins this with a regression test of its own —
// `LaunchUTF8LogsUnescapedOnFail` asserts the error message contains
// `家の管理/スキャナ` rather than `%E5%AE%B6…`. Same concern as
// flutter/flutter#159009, "URL logged on error is wrong on Windows".
void main() {
  group('UrlLaunchException', () {
    test('names the target the OS was given, not the encoded URL', () {
      final url = Uri.parse(
        'file:///G:/%E5%AE%B6%E3%81%AE%E7%AE%A1%E7%90%86/x.txt',
      );
      final error = UrlLaunchException(
        url: url,
        target: r'G:\家の管理\x.txt',
        message: 'the file was not found',
        platformCode: 2,
      );

      expect(error.toString(), contains(r'G:\家の管理\x.txt'));
      // The percent-encoded form is what a user cannot recognise as their file.
      expect(error.toString(), isNot(contains('%E5%AE%B6')));
    });

    test('keeps the original URL available for programmatic handling', () {
      // The decoded target is for reading; the Uri is what a caller compares,
      // logs structurally, or retries with. Losing it to improve the message
      // would trade one problem for another.
      final url = Uri.parse('file:///G:/%E5%AE%B6/x.txt');
      final error = UrlLaunchException(
        url: url,
        target: r'G:\家\x.txt',
        message: 'nope',
      );

      expect(error.url, url);
      expect(error.target, r'G:\家\x.txt');
    });

    test('does not print the target twice when it equals the URL', () {
      // For every scheme but file:, the target *is* the URL string. Printing
      // both would be noise on the common path.
      final url = Uri.parse('https://example.com/a');
      final error = UrlLaunchException(
        url: url,
        target: url.toString(),
        message: 'access was denied',
        platformCode: 5,
      );

      expect(
        'https://example.com/a'.allMatches(error.toString()).length,
        1,
        reason:
            'the URL should appear once, not once as url and once as target',
      );
    });

    test('carries the platform code when there is one', () {
      expect(
        UrlLaunchException(
          url: Uri.parse('https://a.test'),
          target: 'https://a.test',
          message: 'access was denied',
          platformCode: 5,
        ).toString(),
        contains('5'),
      );
    });

    test('says nothing about a code when the platform has none', () {
      // macOS answers with a bare BOOL. An invented code would be worse than
      // an absent one, and a dangling "(code null)" worse still.
      final text =
          UrlLaunchException(
            url: Uri.parse('https://a.test'),
            target: 'https://a.test',
            message: 'the open request was refused',
          ).toString();

      expect(text, isNot(contains('code')));
      expect(text, isNot(contains('null')));
    });
  });
}
