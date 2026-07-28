import '../../exceptions.dart';
import '../../url_launcher_backend.dart';
import 'scheme_registry.dart';
import 'shell_execute.dart';

/// Opens URLs through the Windows shell.
///
/// The whole backend is one `ShellExecuteW` call plus the classification of its
/// return value. What makes it correct is entirely in the marshalling and in
/// that classification, which is why both live in `shell_execute.dart` where
/// they can be read — and the classification tested — on their own.
final class WindowsUrlLauncherBackend implements UrlLauncherBackend {
  /// Creates the Windows backend.
  ///
  /// [shellExecute] exists so the **status → result** half of this backend can
  /// be driven from any host with any code, including the ones a real machine
  /// will not produce on demand — `ERROR_ACCESS_DENIED` is not something a test
  /// can arrange. Leave it alone outside tests; the default is the real call.
  ///
  /// The marshalling itself is deliberately *not* behind this seam. Substituting
  /// it would leave the dangerous part unproven, so it is exercised against the
  /// real `shell32.dll` instead (see `test/windows/`).
  const WindowsUrlLauncherBackend({
    this.shellExecute = shellExecuteOpen,
    this.schemeIsRegistered = isSchemeRegistered,
  });

  /// Asks the shell to open a target, returning the raw `ShellExecuteW` status.
  final int Function(String target) shellExecute;

  /// Asks whether `HKEY_CLASSES_ROOT\<scheme>` marks the scheme as a handler.
  ///
  /// Injectable for the same reason as [shellExecute] — so the *decision* can
  /// be driven from any host. The registry read itself is exercised against the
  /// real hive in `test/windows/scheme_registry_test.dart`, because a fake of
  /// the marshalling would only agree with itself.
  final bool Function(String scheme) schemeIsRegistered;

  @override
  bool canOpen(Uri url) {
    // {@macro ffi_url_launcher.can_open_contract}
    //
    // The reference implementation extracts the scheme with a string search for
    // `:`. Taking `Uri.scheme` instead means a drive path never arrives here
    // spelled as a scheme, and the value is already lowercased — the registry
    // is case-insensitive either way.
    return schemeIsRegistered(url.scheme);
  }

  @override
  bool launch(Uri url) {
    final target = shellTargetFor(url);
    final status = shellExecute(target);

    return switch (interpretShellExecuteStatus(status)) {
      ShellExecuteOutcome.launched => true,
      ShellExecuteOutcome.noHandler => false,
      // The failure names `target`, not `url`. For a `file:` URL those differ,
      // and the percent-encoded one is the form a user cannot recognise as
      // their own file.
      ShellExecuteOutcome.failed =>
        throw UrlLaunchException(
          url: url,
          target: target,
          message: describeShellExecuteStatus(status),
          platformCode: status,
        ),
    };
  }
}
