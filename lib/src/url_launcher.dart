import 'dart:io';

import 'url_launcher_backend.dart';
import 'url_launcher_platform.dart';
import 'url_safety.dart';

/// Opens URLs in the operating system's registered handler.
///
/// The platform backend is chosen once, when the instance is built. Operations
/// are delegated to it unchanged, so a backend's failures reach the caller
/// exactly as thrown.
class UrlLauncher {
  /// Wraps a backend directly.
  ///
  /// Useful for tests, and for a caller who has constructed a platform backend
  /// with options the cross-platform surface does not expose.
  const UrlLauncher.withBackend(this._backend);

  /// Builds the instance for the platform this program is running on.
  factory UrlLauncher.forCurrentPlatform() =>
      UrlLauncher.forOperatingSystem(Platform.operatingSystem);

  /// Builds the instance for a named [operatingSystem].
  ///
  /// Takes the name rather than reading it, so a caller — or a test — can ask
  /// what this package would do on a platform it is not running on.
  factory UrlLauncher.forOperatingSystem(String operatingSystem) =>
      UrlLauncher.withBackend(resolveUrlLauncherBackend(operatingSystem));

  final UrlLauncherBackend _backend;

  /// Opens [url] in its registered handler.
  ///
  /// {@macro ffi_url_launcher.launch_contract}
  ///
  /// {@template ffi_url_launcher.allow_unsafe}
  /// Refuses a URL whose *shape* says it is a local path rather than a URL — no
  /// scheme at all, or a one-letter scheme, which on Windows is a drive letter.
  /// Both were measured to reach the shell and do something the caller did not
  /// ask for. Set [allowUnsafe] to skip that check when the input has already
  /// been decided elsewhere.
  ///
  /// The check is a **shape** check, never a trust check, and it is partial by
  /// design: `file:///C:/Windows/System32/calc.exe` passes it and will execute.
  /// See the README for what is and is not blocked.
  /// {@endtemplate}
  ///
  /// Throws `UnsafeUrlError` for a refused shape, `UrlLaunchException` for a
  /// genuine failure, and [UnsupportedError] on a platform with no backend.
  bool launchUrlSync(Uri url, {bool allowUnsafe = false}) {
    if (!allowUnsafe) checkUrlShape(url);
    return _backend.launch(url);
  }

  /// Opens [url] in its registered handler.
  ///
  /// The asynchronous form of [launchUrlSync], and the one to reach for by
  /// default — it matches `package:url_launcher`, so code moving across does
  /// not change shape.
  ///
  /// {@macro ffi_url_launcher.allow_unsafe}
  ///
  /// **No work is offloaded.** The underlying call is synchronous and must stay
  /// on the calling isolate's thread: `NSWorkspace` wants the main thread and
  /// `ShellExecuteW` depends on that thread's COM apartment. The `Future` is
  /// here so the signature can survive a future implementation that genuinely
  /// is asynchronous, not because this one is.
  Future<bool> launchUrl(Uri url, {bool allowUnsafe = false}) async =>
      launchUrlSync(url, allowUnsafe: allowUnsafe);
}
