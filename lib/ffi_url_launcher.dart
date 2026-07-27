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

export 'src/exceptions.dart' show UrlLaunchException, UrlLauncherException;
export 'src/url_launcher.dart' show UrlLauncher;

/// The launcher used by the top-level functions.
///
/// Lazily built, as every top-level `final` in Dart is, so
/// `Platform.operatingSystem` is not read — and no platform library is opened —
/// until something actually launches.
final UrlLauncher _default = UrlLauncher.forCurrentPlatform();

/// Opens [url] in its registered handler.
///
/// Returns `true` when the handler was started and `false` when nothing is
/// registered to open this URL. Throws [UrlLaunchException] for any other
/// failure, and [UnsupportedError] on a platform with no backend.
///
/// **`true` means the handler was started, not that the URL opened.** Neither
/// Windows nor macOS reports the latter.
Future<bool> launchUrl(Uri url) => _default.launchUrl(url);

/// Opens [url] in its registered handler, synchronously.
///
/// Identical to [launchUrl] in every respect but the return type — that call is
/// synchronous underneath as well. Reach for this one from a command-line tool
/// that has no reason to be `async`.
bool launchUrlSync(Uri url) => _default.launchUrlSync(url);
