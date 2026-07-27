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
- The only runtime dependency is `ffi`, and there are no build hooks — a
  consumer can still `dart compile exe`.

Not yet implemented: macOS, `canLaunchUrl`, and URL validation. See the caveats
in the README before using the return value; on Windows 11 an unregistered
scheme currently reports success.
