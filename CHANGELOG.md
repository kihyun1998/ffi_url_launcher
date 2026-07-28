## 0.1.0

Initial slice — Windows and macOS launch.

- `launchUrl(Uri)` / `launchUrlSync(Uri)` open a URL in the system's registered
  handler on Windows, through hand-written `shell32` bindings.
- **macOS launch**, through hand-written Objective-C-runtime bindings
  (`libobjc` + AppKit): `[[NSWorkspace sharedWorkspace] openURL:]`, with each
  `objc_msgSend` declared per call signature and an autorelease pool around every
  launch so a runloop-less CLI does not accumulate objects. No `package:objective_c`
  and no build hooks, so `dart compile exe` still works. Unlike Windows, macOS
  reports `false` **honestly** — `NSWorkspace` returns `NO`, with no window, for a
  URL nothing can open. `UrlLaunchException.platformCode` is `null` there, since
  `NSWorkspace.open` answers a bare `BOOL`.
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
- `canLaunchUrl(Uri)` / `canLaunchUrlSync(Uri)` answer whether anything on the
  system is registered to open a URL, by reading `HKEY_CLASSES_ROOT` rather than
  asking the shell to try. On Windows the launch path cannot answer this at all
  — an unregistered scheme is reported as *success* after the shell opens its
  own app picker — so this is the only reliable check. It opens nothing, and a
  `true` means a handler is registered rather than that opening will succeed.
- `UrlLaunchException.target` names the string the OS was actually handed, and
  the message shows it — for a `file:` URL that is the decoded path rather than
  the percent-encoded form, which is what a reader can recognise.
- The only runtime dependency is `ffi`, and there are no build hooks — a
  consumer can still `dart compile exe`.

Not yet implemented: `canLaunchUrl` on macOS — it throws `UnimplementedError`
there for now (the handler lookup, `URLForApplicationToOpenURL:`, needs its own
measurement; a probe returned `nil` even for `https:`). See the caveat on
`launchUrl`'s return value in the README — on Windows 11 an unregistered scheme
reports success, which is why `canLaunchUrl` exists.
