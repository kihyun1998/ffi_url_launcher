import '../../exceptions.dart';
import '../../url_launcher_backend.dart';
import 'ns_workspace.dart';

/// Opens URLs through `NSWorkspace` on macOS.
///
/// Like the Windows backend, the whole thing is one OS call plus the
/// classification of what it returned. The call and its Objective-C-runtime
/// marshalling live in `ns_workspace.dart` / `objc.dart`, where the dangerous
/// part can be read on its own; this class is the decision-free mapping from a
/// [MacOpenOutcome] to the value a caller sees.
final class MacosUrlLauncherBackend implements UrlLauncherBackend {
  /// Creates the macOS backend.
  ///
  /// [openUrl] exists for the same reason as the Windows backend's
  /// `shellExecute` seam: it lets the **outcome → result** mapping be driven
  /// from any host, including the `invalidUrl` case a real machine will almost
  /// never produce (`NSURL` is lenient — measured). The marshalling itself is
  /// deliberately not behind this seam; substituting it would leave the
  /// dangerous part unproven, so it is exercised against the real frameworks in
  /// `test/macos/`.
  const MacosUrlLauncherBackend({
    this.openUrl = workspaceOpenUrl,
    this.canOpenUrl = workspaceCanOpenUrl,
  });

  /// Asks `NSWorkspace` to open a URL, returning the decoded outcome.
  final MacOpenOutcome Function(String url) openUrl;

  /// Asks `NSWorkspace` whether an application is registered to open a URL.
  ///
  /// Injectable for the same reason as [openUrl] — so the *decision* can be
  /// driven from any host. The lookup itself is exercised against the real
  /// `NSWorkspace` in `test/macos/`, because a fake of the marshalling would
  /// only agree with itself.
  final bool Function(String url) canOpenUrl;

  @override
  bool launch(Uri url) {
    // ADR-0001's (B) question is a no-op on macOS: `NSURL` parses the URL
    // string itself, so — unlike Windows `file:` URLs — there is nothing to
    // rewrite. The string handed over is exactly `url.toString()`.
    final target = url.toString();

    return switch (openUrl(target)) {
      MacOpenOutcome.opened => true,
      MacOpenOutcome.notOpened => false,
      // A URL that passed the shape check but that `NSURL` could not construct
      // is a genuine fault, not the ordinary "nothing is registered" — so it
      // throws rather than returning `false`. There is no platform code:
      // `NSWorkspace` deals in `BOOL`, and inventing one would be worse than
      // its absence (`docs/agents/theflow.md`, macOS hidden-state list).
      MacOpenOutcome.invalidUrl =>
        throw UrlLaunchException(
          url: url,
          target: target,
          message: 'NSURL could not construct a URL from this string',
          platformCode: null,
        ),
    };
  }

  @override
  bool canOpen(Uri url) {
    // {@macro ffi_url_launcher.can_open_contract}
    //
    // The whole URL is handed over, not just the scheme. That asymmetry with
    // Windows — which reads a per-*scheme* registry key — is why the seam is
    // named `canOpen(Uri)` rather than `schemeRegistered(String)`: macOS asks
    // LaunchServices which application would open *this URL*, so a `file:` URL
    // is answered by the extension's handler, not by whether `file` is a
    // registered scheme.
    return canOpenUrl(url.toString());
  }
}
