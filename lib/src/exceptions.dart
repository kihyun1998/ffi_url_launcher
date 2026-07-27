/// Everything this package throws.
///
/// Sealed on purpose: adding a failure mode makes the analyzer point at every
/// exhaustive `switch` over it, so a caller that handled all of them keeps
/// being told when "all of them" changes.
sealed class UrlLauncherException implements Exception {
  /// Creates an exception about [url].
  const UrlLauncherException({required this.url});

  /// The URL the failed operation was about.
  final Uri url;
}

/// The operating system refused to open a URL for a reason that is not
/// "nothing is registered to handle it".
///
/// That ordinary case is reported as `false`, never as this exception — see
/// [UrlLauncherBackend.launch]. What reaches here is a genuine fault: access
/// denied, a path that does not exist, an out-of-memory shell.
final class UrlLaunchException extends UrlLauncherException {
  /// Creates a launch failure for [url].
  const UrlLaunchException({
    required super.url,
    required this.message,
    this.platformCode,
  });

  /// A human-readable account of what the operating system reported.
  final String message;

  /// The raw code the platform returned, when the platform returns one.
  ///
  /// **Windows only.** `NSWorkspace` answers with a bare `BOOL` and has no code
  /// to carry, so this is always `null` on macOS. It is deliberately not
  /// invented there — a fabricated code would be worse than an absent one.
  final int? platformCode;

  @override
  String toString() {
    final code = platformCode == null ? '' : ' (code $platformCode)';
    return 'UrlLaunchException: failed to open $url — $message$code';
  }
}
