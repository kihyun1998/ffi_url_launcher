@TestOn('mac-os')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:ffi_url_launcher/src/backends/macos/objc.dart';
import 'package:test/test.dart';

// THROWAWAY DIAGNOSTIC — delete once `lessons.md` #13 has its answer.
//
// Dart 3.7.0 and 3.8.0 answer `MacOpenOutcome.invalidUrl` for
// `file:///zzz-없는파일-ффи.zzzq` on macOS where 3.12.2 answers `notOpened`,
// deterministically, with the macOS image, `ffi` version and UTF-8 bytes all
// verified identical. Every observation so far has been of the *final* value,
// which cannot say which of the two Objective-C calls produced the nil:
//
//     [NSString stringWithUTF8String:]   <- could return nil for bad UTF-8
//     [NSURL URLWithString:]             <- could return nil for a non-URL
//
// This prints the intermediates on whichever SDK runs it. It asserts almost
// nothing on purpose: it is here to be read in the CI log, not to gate.
void main() {
  group('diagnose: where the nil comes from', () {
    const inputs = <String, String>{
      'ascii control': 'file:///zzz-plain.zzzq',
      'the failing one': 'file:///zzz-없는파일-ффи.zzzq',
      'korean only': 'file:///zzz-한글.zzzq',
      'cyrillic only': 'file:///zzz-ффи.zzzq',
      'percent-encoded': 'file:///zzz-%ED%95%9C%EA%B8%80.zzzq',
      'space': 'file:///zzz plain.zzzq',
      'https non-ascii': 'https://example.test/한글',
    };

    test('reports NSString and NSURL separately for each input', () {
      // ignore: avoid_print
      print('--- DIAGNOSE START ---');
      inputs.forEach((label, url) {
        using((arena) {
          final utf8 = url.toNativeUtf8(allocator: arena);

          // Byte-level view of exactly what Objective-C is handed, so this can
          // be compared across SDKs without trusting that the encoder matched.
          final bytes = <int>[];
          var i = 0;
          while (utf8.cast<Uint8>()[i] != 0) {
            bytes.add(utf8.cast<Uint8>()[i]);
            i++;
          }

          final nsString = msgSendCStringReturningId(
            nsStringClass,
            selStringWithUtf8String,
            utf8,
          );
          final nsUrl = nsString == nullptr
              ? nullptr
              : msgSendIdReturningId(nsUrlClass, selUrlWithString, nsString);

          // ignore: avoid_print
          print(
            'DIAGNOSE | ${label.padRight(16)} '
            '| utf8Bytes=${bytes.length} '
            '| nsString=${nsString == nullptr ? "NIL" : "ok"} '
            '| nsUrl=${nsUrl == nullptr ? "NIL" : "ok"} '
            '| bytes=${bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}',
          );
        });
      });
      // ignore: avoid_print
      print('--- DIAGNOSE END ---');

      // The ASCII control must work, or the runtime was never reached at all
      // and every NIL above is meaningless — `lessons.md` #9's rule, applied to
      // a diagnostic.
      using((arena) {
        final s = msgSendCStringReturningId(
          nsStringClass,
          selStringWithUtf8String,
          'file:///zzz-plain.zzzq'.toNativeUtf8(allocator: arena),
        );
        expect(s, isNot(nullptr), reason: 'NSString itself is not reachable');
        final u = msgSendIdReturningId(nsUrlClass, selUrlWithString, s);
        expect(u, isNot(nullptr), reason: 'NSURL itself is not reachable');
      });
    });
  });
}
