/// Opens a URL in the system's registered handler on Windows and macOS,
/// calling the operating system directly through `dart:ffi`.
///
/// Pure Dart: no Flutter dependency, no native sources to compile, and no build
/// hooks — so a consumer can still `dart compile exe`.
///
/// ```dart
/// if (!await launchUrl(Uri.parse('https://dart.dev'))) {
///   print('nothing is registered to open that');
/// }
/// ```
library;

import 'src/url_launcher.dart';

export 'src/exceptions.dart'
    show
        UnsafeUrlError,
        UnsafeUrlReason,
        UrlLaunchException,
        UrlLauncherException;
export 'src/url_launcher.dart' show UrlLauncher;

/// The launcher used by the top-level functions.
///
/// Lazily built, as every top-level `final` in Dart is, so
/// `Platform.operatingSystem` is not read — and no platform library is opened —
/// until something actually launches.
final UrlLauncher _default = UrlLauncher.forCurrentPlatform();

/// Opens [url] in its registered handler.
///
/// {@macro ffi_url_launcher.launch_contract}
///
/// {@macro ffi_url_launcher.allow_unsafe}
///
/// Throws [UnsafeUrlError] for a refused shape, [UrlLaunchException] for a
/// genuine failure, and [UnsupportedError] on a platform with no backend.
Future<bool> launchUrl(Uri url, {bool allowUnsafe = false}) =>
    _default.launchUrl(url, allowUnsafe: allowUnsafe);

/// Opens [url] in its registered handler, synchronously.
///
/// Identical to [launchUrl] in every respect but the return type — that call is
/// synchronous underneath as well. Reach for this one from a command-line tool
/// that has no reason to be `async`.
///
/// {@macro ffi_url_launcher.allow_unsafe}
bool launchUrlSync(Uri url, {bool allowUnsafe = false}) =>
    _default.launchUrlSync(url, allowUnsafe: allowUnsafe);
