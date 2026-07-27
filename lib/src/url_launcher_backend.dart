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

  /// Whether anything on this system is registered to open [url].
  ///
  /// {@template ffi_url_launcher.can_open_contract}
  /// Asks the operating system's own registry of handlers rather than asking
  /// the shell to try — which on Windows cannot answer the question at all,
  /// since an unregistered scheme is answered with *success* after the shell
  /// opens its own app picker (`docs/agents/lessons.md` #4).
  ///
  /// A `true` says a handler is **registered**, not that opening will succeed:
  /// the registered application may be missing, broken, or unable to handle
  /// this particular URL.
  ///
  /// A `false` says nothing is *registered*, which is not quite "this will not
  /// open". Windows answers some schemes itself without a registry entry —
  /// `shell:` has no key under `HKEY_CLASSES_ROOT` (measured) yet the shell
  /// handles it — so a `false` can under-report. Treat it as "no application
  /// claims this", which is the question the registry can answer.
  ///
  /// It is the strongest answer the OS offers without launching anything, and
  /// it has no side effects.
  /// {@endtemplate}
  bool canOpen(Uri url);
}
