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
  const MacosUrlLauncherBackend({this.openUrl = workspaceOpenUrl});

  /// Asks `NSWorkspace` to open a URL, returning the decoded outcome.
  final MacOpenOutcome Function(String url) openUrl;

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
      MacOpenOutcome.invalidUrl => throw UrlLaunchException(
        url: url,
        target: target,
        message: 'NSURL could not construct a URL from this string',
        platformCode: null,
      ),
    };
  }

  @override
  bool canOpen(Uri url) {
    // Deferred to #5. macOS answers this through
    // `[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:]`, which is a
    // different call from `openURL:` and a slice of its own — and a probe found
    // it returning `nil` even for `https:` on this host, so it needs its own
    // measurement rather than a quick add here. Throwing `UnimplementedError`
    // (not `UnsupportedError`, which is reserved for "no backend for this
    // platform") says plainly that the operation exists but is not built yet,
    // rather than answering a launch question with a quiet wrong `false`.
    throw UnimplementedError(
      'canLaunchUrl is not yet implemented on macOS (issue #5). launchUrl '
      'works; asking whether a handler exists does not, yet.',
    );
  }
}
