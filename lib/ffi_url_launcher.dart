/// Opens a URL in the system's registered handler on Windows and macOS,
/// calling the operating system directly through `dart:ffi`.
///
/// Pure Dart: no Flutter dependency, no native sources to compile, and no build
/// hooks — so a consumer can still `dart compile exe`.
///
/// ```dart
/// final url = Uri.parse('https://dart.dev');
/// if (await canLaunchUrl(url)) {
///   await launchUrl(url);
/// } else {
///   print('nothing on this machine is registered to open that');
/// }
/// ```
///
/// Ask with [canLaunchUrl] rather than branching on what [launchUrl] returns:
/// on Windows its `false` is effectively unreachable for a URL scheme, because
/// the shell reports that it accepted the request and not what became of it.
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

/// Whether anything on this system is registered to open [url].
///
/// {@macro ffi_url_launcher.can_open_contract}
///
/// {@macro ffi_url_launcher.allow_unsafe}
///
/// Throws [UnsafeUrlError] for a refused shape and [UnsupportedError] on a
/// platform with no backend. It never throws for "no" — that is an answer.
Future<bool> canLaunchUrl(Uri url, {bool allowUnsafe = false}) =>
    _default.canLaunchUrl(url, allowUnsafe: allowUnsafe);

/// Whether anything on this system is registered to open [url],
/// synchronously.
///
/// Identical to [canLaunchUrl] but for the return type.
///
/// {@macro ffi_url_launcher.can_open_contract}
bool canLaunchUrlSync(Uri url, {bool allowUnsafe = false}) =>
    _default.canLaunchUrlSync(url, allowUnsafe: allowUnsafe);
