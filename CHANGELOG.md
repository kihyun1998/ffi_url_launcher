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
- A URL whose **shape** says it is a local path, or that names nothing at all,
  is refused before the operating system sees it, with `UnsafeUrlError`. Three
  shapes: no scheme (a UNC path, a bare filename, the empty string); a
  one-letter scheme, which on Windows is a drive letter; and a `file:` URL that
  names no file — `file:`/`file://`/`file:///` convert to the current drive's
  root, and one carrying a query or fragment has no path to extract. All were
  measured to reach the shell and do something the caller did not ask for.
  `allowUnsafe: true` opts out.
  **`file:` is not blocked** — it is a supported desktop feature, so
  `file:///C:/…/calc.exe` still executes. The README lists what is and is not
  blocked side by side.
- `UrlLaunchException.target` names the string the OS was actually handed, and
  the message shows it — for a `file:` URL that is the decoded path rather than
  the percent-encoded form, which is what a reader can recognise.
- The only runtime dependency is `ffi`, and there are no build hooks — a
  consumer can still `dart compile exe`.

Not yet implemented: macOS and `canLaunchUrl`. See the caveat on the return
value in the README before relying on it; on Windows 11 an unregistered scheme
currently reports success.
