## 0.1.0

Initial slice — Windows launch.

- `launchUrl(Uri)` / `launchUrlSync(Uri)` open a URL in the system's registered
  handler on Windows, through hand-written `shell32` bindings.
- `UrlLauncher.forOperatingSystem(String)` resolves a backend as a pure function
  of the platform name, so behaviour on a platform you are not running on can be
  asserted from any host.
- Failures are typed: an ordinary "nothing is registered to open this" is
  `false`, and every other shell failure raises `UrlLaunchException` carrying the
  Windows error code. A platform with no backend raises `UnsupportedError`
  naming it.
- `file:` URLs work for non-ASCII paths. `Uri.toString()` percent-encodes them
  and `ShellExecuteW` does not decode multi-byte UTF-8 escapes, so they are
  converted to a native path first — which also keeps a percent sign that is
  genuinely part of a file name, and turns `file://server/share` into a real UNC
  path.
- The only runtime dependency is `ffi`, and there are no build hooks — a
  consumer can still `dart compile exe`.

Not yet implemented: macOS, `canLaunchUrl`, and URL validation. See the caveats
in the README before using the return value; on Windows 11 an unregistered
scheme currently reports success.
