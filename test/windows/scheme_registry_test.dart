@TestOn('windows')
library;

import 'package:ffi_url_launcher/src/backends/windows/scheme_registry.dart';
import 'package:test/test.dart';

// Drives the real `advapi32.dll` against the real registry. Faking it would
// prove nothing: the marshalling *is* the dangerous part here, and the sibling
// package shipped the wrong predefined `HKEY` spelling — a mistake a fake would
// have happily agreed with (`just_autostart`, its lessons #7).
//
// Reading is side-effect free, so unlike the launch path this can run in CI.
void main() {
  group('isSchemeRegistered', () {
    test('answers true for schemes Windows always registers', () {
      // A positive case, not only a negative one: a wrong access mask or a
      // failed library load would make every answer `false`, which a
      // negative-only suite would read as success.
      //
      // It does **not** discriminate the predefined-handle spelling. Measured:
      // `RegOpenKeyExW` succeeds with both the signed and the unsigned literal
      // for all four hives on Windows 11 (26200) — `lessons.md` #6 — so no test
      // here can go red on that, and one written as if it could would be
      // claiming cover it does not have.
      // **`mailto` used to be in this list** — asserted with the reason
      // *"registered on every Windows install"* — and the first CI run on a
      // `windows-latest` runner falsified it: a headless Server image ships no
      // mail client, so nothing claims `mailto` there (`lessons.md` #10). It
      // was true on the developer machine, which is exactly why it survived
      // review.
      //
      // What is left is what Windows itself provides rather than what an
      // installed application registers: `http`/`https` come with the bundled
      // browser, and `HKCR\file` carries `URL Protocol` unconditionally — a
      // registry-layer fact, not an app-presence one. Measured on both Windows
      // 11 (26200) and the CI runner.
      for (final scheme in ['http', 'https', 'file']) {
        expect(
          isSchemeRegistered(scheme),
          isTrue,
          reason: '"$scheme" is registered by Windows itself, not by an app',
        );
      }
    });

    test('answers false for a scheme nothing has ever registered', () {
      for (final scheme in ['zzznotreal', 'zzz-ffi-url-launcher-absent']) {
        expect(isSchemeRegistered(scheme), isFalse);
      }
    });

    test('is case-insensitive, as the registry is', () {
      // `Uri.scheme` arrives lowercased, so this is defence rather than a
      // requirement — but a caller reaching the seam directly should not get a
      // different answer for HTTPS than for https.
      expect(isSchemeRegistered('HTTPS'), isSchemeRegistered('https'));
    });

    test('answers false rather than throwing for a malformed scheme', () {
      // A registry path is not a scheme. What this pins is the *answer* and the
      // absence of a throw — not the separator guard, which was measured to
      // change no answer here (`https\shell\open\command` opens, carries no
      // `URL Protocol` value, and is `false` either way). The guard stays as
      // defence for a direct seam caller, and this test does not pretend to
      // cover it.
      for (final scheme in [r'https\shell\open\command', '..', '']) {
        expect(
          () => isSchemeRegistered(scheme),
          returnsNormally,
          reason: '"$scheme" should be answered, not thrown on',
        );
        expect(isSchemeRegistered(scheme), isFalse);
      }
    });

    test('discriminates between installed and absent applications', () {
      // The measurement this whole approach rests on: the check has to tell
      // apart apps that are here from apps that are not. Asserted as a relation
      // rather than a fixed expectation, since which apps exist varies by
      // machine — `http` is always present and this random scheme never is.
      expect(
        isSchemeRegistered('http'),
        isNot(isSchemeRegistered('zzz-definitely-not-installed')),
      );
    });
  });
}
