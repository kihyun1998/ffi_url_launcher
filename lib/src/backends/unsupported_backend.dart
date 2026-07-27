import '../supported_platforms.dart';
import '../url_launcher_backend.dart';

/// Stands in on an operating system this package has no backend for.
///
/// Every operation throws. Returning `false` would be indistinguishable from
/// "no application is registered to open this", which is a completely different
/// situation and one a caller may reasonably shrug off.
final class UnsupportedUrlLauncherBackend implements UrlLauncherBackend {
  /// Creates the stand-in for [operatingSystem].
  const UnsupportedUrlLauncherBackend(this.operatingSystem);

  /// The operating-system name that had no backend, as
  /// `Platform.operatingSystem` spells it.
  final String operatingSystem;

  @override
  Never launch(Uri url) => throw UnsupportedError(_message);

  @override
  Never canOpen(Uri url) => throw UnsupportedError(_message);

  /// The refusal message.
  ///
  /// The supported half is **read out of [supportedPlatforms]** rather than
  /// written down, so it cannot come to disagree with what the resolver
  /// actually wires. Sibling `just_autostart` shipped *"has no backend for
  /// "windows". Supported platforms are Windows and macOS."* — a sentence that
  /// contradicts itself — because those two halves were maintained separately
  /// (its lessons #5).
  String get _message {
    final supported = supportedPlatforms.values
        .map((platform) => platform.displayName)
        .join(' and ');
    return 'ffi_url_launcher has no backend for "$operatingSystem". '
        'Supported: $supported.';
  }
}
