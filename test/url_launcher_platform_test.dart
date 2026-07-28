@TestOn('vm')
library;

import 'package:ffi_url_launcher/src/backends/macos/macos_backend.dart';
import 'package:ffi_url_launcher/src/backends/unsupported_backend.dart';
import 'package:ffi_url_launcher/src/backends/windows/windows_backend.dart';
import 'package:ffi_url_launcher/src/url_launcher_platform.dart';
import 'package:test/test.dart';

// Resolution is a pure function of the operating-system *name*, which is what
// lets every arm be asserted from any host. A resolver that read
// `Platform.operatingSystem` directly could only ever test one arm.
void main() {
  group('resolveUrlLauncherBackend', () {
    test('resolves Windows to the Windows backend', () {
      expect(
        resolveUrlLauncherBackend('windows'),
        isA<WindowsUrlLauncherBackend>(),
      );
    });

    test('resolves macOS to the macOS backend', () {
      // Resolution is a pure string lookup — this arm can be asserted from a
      // Windows or Linux host, and the macOS backend is only *constructed*
      // here, not called, so no dylib is opened off-platform.
      expect(
        resolveUrlLauncherBackend('macos'),
        isA<MacosUrlLauncherBackend>(),
      );
    });

    test('resolves every other platform to the unsupported backend', () {
      for (final os in ['linux', 'android', 'ios', 'fuchsia', '']) {
        expect(
          resolveUrlLauncherBackend(os),
          isA<UnsupportedUrlLauncherBackend>(),
          reason: '"$os" has no backend yet',
        );
      }
    });

    test('carries the operating-system name into the unsupported backend', () {
      // The name has to survive the resolution, or the error message cannot
      // say which platform was refused.
      final backend =
          resolveUrlLauncherBackend('linux') as UnsupportedUrlLauncherBackend;
      expect(backend.operatingSystem, 'linux');
    });
  });
}
