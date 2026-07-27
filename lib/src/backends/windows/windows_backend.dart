import '../../exceptions.dart';
import '../../url_launcher_backend.dart';
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
  const WindowsUrlLauncherBackend({this.shellExecute = shellExecuteOpen});

  /// Asks the shell to open a target, returning the raw `ShellExecuteW` status.
  final int Function(String target) shellExecute;

  @override
  bool launch(Uri url) {
    final status = shellExecute(url.toString());

    return switch (interpretShellExecuteStatus(status)) {
      ShellExecuteOutcome.launched => true,
      ShellExecuteOutcome.noHandler => false,
      ShellExecuteOutcome.failed => throw UrlLaunchException(
        url: url,
        message: describeShellExecuteStatus(status),
        platformCode: status,
      ),
    };
  }
}
