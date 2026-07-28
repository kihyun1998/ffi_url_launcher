import 'backends/macos/macos_backend.dart';
import 'backends/windows/windows_backend.dart';
import 'url_launcher_backend.dart';

/// How a platform this package supports is built and named.
typedef PlatformSupport = ({
  /// The name to show a human — `macOS`, not `macos`.
  String displayName,

  /// Builds the backend. A factory rather than an instance so a backend is
  /// only constructed on the platform that asked for one.
  UrlLauncherBackend Function() create,
});

/// Every operating system this package has a **wired** backend for, keyed the
/// way `Platform.operatingSystem` spells it.
///
/// One table, three jobs: it decides what
/// [resolveUrlLauncherBackend][resolve] returns, it supplies the display names
/// the refusal message lists, and its keys *are* the definition of "supported".
/// Before this existed those three lived apart, so wiring a platform meant
/// editing a set, a `switch`, and a name-formatting function that could
/// disagree with either — and the sibling package's self-contradicting refusal
/// message (`docs/agents/lessons.md`, its #5) is what that disagreement looks
/// like when it ships.
///
/// Adding a platform is adding one entry here, in the same change that writes
/// its backend. There is no way to list one without wiring it.
///
/// [resolve]: url_launcher_platform.dart
const Map<String, PlatformSupport> supportedPlatforms = {
  'windows': (displayName: 'Windows', create: _windows),
  'macos': (displayName: 'macOS', create: _macos),
};

UrlLauncherBackend _windows() => const WindowsUrlLauncherBackend();

UrlLauncherBackend _macos() => const MacosUrlLauncherBackend();
