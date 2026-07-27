import 'backends/unsupported_backend.dart';
import 'backends/windows/windows_backend.dart';
import 'url_launcher_backend.dart';

/// Chooses the backend for [operatingSystem].
///
/// A pure function of the **name**, never of `Platform.operatingSystem`
/// directly. That is what lets every arm — including the ones this host is not
/// — be asserted from any machine; a resolver that read the ambient platform
/// could only ever have one of its branches tested.
///
/// The set it switches on is [supportedOperatingSystems], shared with the
/// refusal message so the two cannot drift apart.
UrlLauncherBackend resolveUrlLauncherBackend(String operatingSystem) {
  if (!supportedOperatingSystems.contains(operatingSystem)) {
    return UnsupportedUrlLauncherBackend(operatingSystem);
  }

  return switch (operatingSystem) {
    'windows' => const WindowsUrlLauncherBackend(),
    // Unreachable while `supportedOperatingSystems` and this switch agree. The
    // guard above is what makes the message correct; this arm is what makes a
    // half-finished addition loud instead of silent.
    _ => throw StateError(
      '"$operatingSystem" is listed as supported but has no backend wired',
    ),
  };
}
