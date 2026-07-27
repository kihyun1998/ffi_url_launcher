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
  const WindowsUrlLauncherBackend();

  @override
  bool launch(Uri url) {
    final status = shellExecuteOpen(url.toString());

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
