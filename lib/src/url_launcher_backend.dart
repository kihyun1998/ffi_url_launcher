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
  /// operating system reports the latter.
  ///
  /// **On Windows, `false` is effectively unreachable for a URL scheme — do not
  /// branch on it there.** `ShellExecuteW` answers *success* (42, measured) for
  /// a scheme nothing is registered to handle: it reports that the shell
  /// accepted the request, not what became of it. The documented
  /// `SE_ERR_NOASSOC` code that would produce `false` is not returned for
  /// schemes on modern Windows; it is still reachable through a file extension
  /// with no association. `docs/agents/lessons.md` #4.
  ///
  /// This is not worked around by checking first. The reference implementation
  /// does not either — `LaunchUrl` and `CanLaunchUrl` are independent there, and
  /// a pre-check would block schemes the shell handles without a registry entry
  /// (`shell:` has no key, measured). **Call [canOpen] yourself when the answer
  /// matters**; that is the question it exists to answer, and it is the only
  /// reliable one on Windows.
  /// {@endtemplate}
  bool launch(Uri url);

  /// Whether anything on this system is registered to open [url].
  ///
  /// {@template ffi_url_launcher.can_open_contract}
  /// Asks the operating system's own registry of handlers rather than asking
  /// the shell to try — which on Windows cannot answer the question at all,
  /// since an unregistered scheme is answered with *success*: the shell reports
  /// that it accepted the request and not what became of it
  /// (`docs/agents/lessons.md` #4).
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
