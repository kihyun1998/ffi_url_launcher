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

/// Why a URL was refused before it reached the operating system.
///
/// Lives here rather than beside the check so the dependency runs one way:
/// `url_safety.dart` needs the exception, and the exception needs the reason.
enum UnsafeUrlReason {
  /// The URL has no scheme, so it denotes a relative path, a UNC path, or
  /// nothing at all — never a URL.
  ///
  /// The empty string lands here, and it is not a theoretical case:
  /// `ShellExecuteW('')` answers *success* and opens a File Explorer window.
  noScheme,

  /// The scheme is a single letter, which on Windows is a drive letter.
  ///
  /// `Uri.parse(r'C:\Windows\System32\calc.exe')` yields `scheme == 'c'` and
  /// `hasScheme == true`, and `ShellExecuteW` accepts the forward-slashed form
  /// and **executes it**. RFC 3986 permits a one-character scheme, but none is
  /// registered or in real use, so on this platform pair it is a drive letter.
  driveLetter,

  /// The URL's scheme is `file:` but it does not denote a file.
  ///
  /// Two spellings reach this. **A `file:` URL with nothing after the scheme**
  /// — `file:`, `file://`, `file:/`, `file:///` all normalise to the same thing
  /// — converts to a bare `\`, which is an existing directory: the root of the
  /// current drive. Opening it launches a file browser there, which is the
  /// empty-string hazard ([noScheme]) arriving by a route that *has* a scheme.
  ///
  /// **A `file:` URL carrying a query or fragment** cannot be converted to a
  /// path at all. Refusing it here is what keeps `Uri.toFilePath`'s
  /// `UnsupportedError` from surfacing, since this package documents that error
  /// as meaning "this platform has no backend" — a caller would otherwise read
  /// a malformed URL as an unsupported operating system.
  ///
  /// A `file:` URL that *does* name something is left alone, including one with
  /// no drive letter: it resolves against the current drive, and a file that is
  /// not there fails as an ordinary "not found".
  notAFilePath,
}

/// A URL was refused before the operating system saw it, because its shape says
/// it is a local path rather than a URL.
///
/// Distinct from [UrlLaunchException] on purpose: "you handed me something that
/// is not a URL" and "the system could not open this URL" want different
/// handling, and a caller that cannot tell them apart will treat a programming
/// mistake as an environment problem.
///
/// Pass `allowUnsafe: true` to skip the check when the caller has already
/// decided the input is fine.
final class UnsafeUrlError extends UrlLauncherException {
  /// Creates a refusal for [url].
  const UnsafeUrlError({required super.url, required this.reason});

  /// Which shape the URL had.
  final UnsafeUrlReason reason;

  @override
  String toString() => switch (reason) {
    UnsafeUrlReason.noScheme =>
      'UnsafeUrlError: "$url" has no scheme, so it is a local path rather than '
          'a URL. Pass allowUnsafe: true to hand it over anyway.',
    UnsafeUrlReason.driveLetter =>
      'UnsafeUrlError: "$url" parses with the one-letter scheme "${url.scheme}", '
          'which on Windows is a drive letter — this is a local path, not a URL. '
          'Pass allowUnsafe: true to hand it over anyway.',
    UnsafeUrlReason.notAFilePath =>
      'UnsafeUrlError: "$url" is a file: URL that does not name a file — it has '
          'no path, or it carries a query or fragment. Pass allowUnsafe: true to '
          'hand it over anyway.',
  };
}

/// The operating system refused to open a URL for a reason that is not
/// "nothing is registered to handle it".
///
/// That ordinary case is reported as `false`, never as this exception. What
/// reaches here is a genuine fault: access denied, a path that does not exist,
/// an out-of-memory shell.
final class UrlLaunchException extends UrlLauncherException {
  /// Creates a launch failure for [url].
  const UrlLaunchException({
    required super.url,
    required this.target,
    required this.message,
    this.platformCode,
  });

  /// The string the operating system was actually handed.
  ///
  /// The same as `url.toString()` for every scheme but `file:`, where the URL
  /// is converted to a native path first. **This is the form a message shows**,
  /// because a percent-encoded URL is not something a user recognises as their
  /// own file: `file:///G:/%E5%AE%B6%E3%81%AE…` names nothing they can act on,
  /// while `G:\家の管理\…` does. The reference implementation pins the same
  /// behaviour with a regression test of its own.
  final String target;

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
    return 'UrlLaunchException: failed to open $target — $message$code';
  }
}
