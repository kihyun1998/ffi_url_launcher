/// How one operating system is asked to open a URL.
///
/// The operations are identical across platforms; the differences live in *how*
/// the OS is asked, never in *what operations exist*. A backend reports an
/// ordinary "nothing is registered to open this" as `false` and every other
/// failure by throwing, so the facade above it can delegate unchanged.
abstract interface class UrlLauncherBackend {
  /// Hands [url] to the operating system's registered handler.
  ///
  /// {@template ffi_url_launcher.launch_contract}
  /// Returns `true` when the handler was started, and `false` when the
  /// operating system reported that nothing is registered to open this URL.
  /// Throws for every other failure.
  ///
  /// **`true` means the handler was started, not that the URL opened.** No
  /// operating system reports the latter, and on Windows it means less than it
  /// looks: an unregistered scheme is answered with *success* because what the
  /// shell started was its own app-picker dialog. See `docs/agents/lessons.md`
  /// #4 for the measurement.
  /// {@endtemplate}
  bool launch(Uri url);
}
