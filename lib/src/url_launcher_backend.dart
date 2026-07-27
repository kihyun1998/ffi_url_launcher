/// The operating systems this package has a working backend for, spelled the
/// way `Platform.operatingSystem` spells them.
///
/// This is the **single** source for both the resolution in
/// `url_launcher_platform.dart` and the refusal message in
/// `backends/unsupported_backend.dart`. Keeping them on one constant is what
/// makes the sibling package's mistake — a message naming the running platform
/// as unsupported while listing it as supported in the same sentence —
/// unrepresentable rather than merely unlikely.
///
/// Add a name here in the same change that wires its backend, never before.
const Set<String> supportedOperatingSystems = {'windows'};

/// How one operating system is asked to open a URL.
///
/// The operations are identical across platforms; the differences live in *how*
/// the OS is asked, never in *what operations exist*. A backend reports an
/// ordinary "nothing is registered to open this" as `false` and every other
/// failure by throwing, so the facade above it can delegate unchanged.
abstract interface class UrlLauncherBackend {
  /// Hands [url] to the operating system's registered handler.
  ///
  /// Returns `true` when the handler was started, and `false` when nothing is
  /// registered to open this URL. Throws for every other failure.
  ///
  /// **Returning `true` means the handler was started, not that the URL
  /// opened.** No operating system reports the latter.
  bool launch(Uri url);
}
