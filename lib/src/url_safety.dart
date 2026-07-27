import 'exceptions.dart';

/// Refuses a URL whose *shape* says it is a local path rather than a URL.
///
/// This is a **shape** check and never a **trust** check. It answers one
/// question — *does this denote a local path?* — and it lives in this package
/// because the answer depends on how `ShellExecuteW` reads a string, which a
/// caller has no way to know. Whether a URL is *trustworthy*, whether `file:`
/// should be allowed at all, and any scheme whitelist stay with the caller;
/// owning those would be this package absorbing a consumer's concern.
///
/// **It is partial, deliberately.** `file:///C:/Windows/System32/calc.exe`
/// passes and will execute — `file:` is a supported desktop feature. What is
/// *not* blocked is documented beside what is, because a partial guard
/// described as "validated" moves a caller's belief without moving their risk.
///
/// Throws [UnsafeUrlError] naming which shape it saw.
void checkUrlShape(Uri url) {
  if (!url.hasScheme || url.scheme.isEmpty) {
    throw UnsafeUrlError(url: url, reason: UnsafeUrlReason.noScheme);
  }
  if (url.scheme.length == 1) {
    throw UnsafeUrlError(url: url, reason: UnsafeUrlReason.driveLetter);
  }
  if (url.isScheme('file') && !_namesAFile(url)) {
    throw UnsafeUrlError(url: url, reason: UnsafeUrlReason.notAFilePath);
  }
}

/// Whether a `file:` URL points at something rather than at nothing.
///
/// Having a scheme is not the same as denoting a target — `file:`, `file://`,
/// `file:/` and `file:///` all normalise to `file:///`, which converts to a bare
/// `\`: an existing directory, the root of the current drive. That is the
/// [UnsafeUrlReason.noScheme] hazard arriving with a scheme attached, which is
/// exactly why the first two rules do not catch it.
///
/// A query or fragment disqualifies it for a different reason: such a URL has
/// no file path to extract at all.
bool _namesAFile(Uri url) {
  if (url.hasQuery || url.hasFragment) return false;
  // An authority is a UNC host, which names a target on its own.
  if (url.host.isNotEmpty) return true;
  return url.path.isNotEmpty && url.path != '/';
}
