## 0.1.1

**Lowers the SDK floor from `^3.11.5` to `>=3.8.0` — Flutter 3.32.0 and newer.**
No API change.

- **The old floor was never a requirement.** `dart create` wrote whatever SDK was
  installed at the time, and it stayed untouched through 0.1.0 — four minor
  versions above anything this package uses. Because an `environment` constraint
  is carried down to every consumer, 0.1.0 was silently demanding an SDK upgrade
  of anyone adopting it: a Flutter 3.32 app, for instance, would have had to move
  to Flutter 3.41 to add a package that needed nothing from it.
- **The floor stops one above what resolution allows, and CI is why.**
  `package:ffi` would permit 3.7.0, and the first CI run at that floor went red
  on macOS — deterministically, reproduced on a re-run. There,
  `[NSURL URLWithString:]` refuses a non-ASCII `file:` URL, so `launchUrl`
  **throws** where every later SDK returns `false`. Same macOS image, same
  `ffi 2.2.0`, byte-identical UTF-8 reaching the runtime — all three checked —
  and the mechanism is not yet explained. A floor is a promise about behaviour,
  not only about resolution, so 3.8.0 it is.
- **Verified on real SDKs**, not by lowering the constraint on a newer toolchain
  — that only proves the language version, and resolution happens against
  whatever is installed. Dart 3.7.0 and 3.8.0 were downloaded and run: `pub get`,
  `analyze --fatal-infos`, all 84 tests, and a consumer compiled with
  `dart compile exe` answering `canLaunchUrlSync('https://dart.dev')` → `true`.
  Both are now CI legs, so the floor stays honest rather than decaying the first
  time someone uses a newer language feature.
- Formatting is unchanged in meaning but differs on disk: `dart format` derives
  its style from the declared language version, so lowering the floor reformats
  the package. Verified byte-identical output across 3.7.0, 3.8.0 and current.

## 0.1.0

Initial slice — Windows and macOS launch.

- `launchUrl(Uri)` / `launchUrlSync(Uri)` open a URL in the system's registered
  handler on Windows, through hand-written `shell32` bindings.
- **macOS launch**, through hand-written Objective-C-runtime bindings
  (`libobjc` + AppKit): `[[NSWorkspace sharedWorkspace] openURL:]`, with each
  `objc_msgSend` declared per call signature and an autorelease pool around every
  launch so a runloop-less CLI does not accumulate objects. No `package:objective_c`
  and no build hooks, so `dart compile exe` still works. Unlike Windows, macOS
  reports `false` **honestly** — `NSWorkspace` returns `NO` for a URL nothing can
  open, where `ShellExecuteW` reports success. It can still put the system's
  "there is no application set to open the URL" panel on screen while doing so,
  which is what `canLaunchUrl` is for. `UrlLaunchException.platformCode` is
  `null` there, since `NSWorkspace.open` answers a bare `BOOL`.
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
- **`canLaunchUrl` on macOS**, through
  `[[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:]` — the current
  API, not the `LSCopyDefaultApplicationURLForURL` deprecated in macOS 12. It
  looks up and opens nothing. Note the platforms ask genuinely different
  questions under one signature: Windows asks whether the *scheme* is
  registered, macOS which application would open *that exact URL*. They agree
  for `https:` and custom app schemes, and visibly differ for `file:`.
- `canLaunchUrl(Uri)` / `canLaunchUrlSync(Uri)` answer whether anything on the
  system is registered to open a URL, by reading `HKEY_CLASSES_ROOT` rather than
  asking the shell to try. On Windows the launch path cannot answer this at all
  — an unregistered scheme is reported as *success* after the shell opens its
  own app picker — so this is the only reliable check. It opens nothing, and a
  `true` means a handler is registered rather than that opening will succeed.
- `UnsupportedError` means **"this platform has no backend"** and nothing else.
  A `file:` URL carrying a query or fragment cannot be converted to a Windows
  path, and `Uri.toFilePath` reports that with `UnsupportedError` — which would
  have told a caller on Windows that Windows was unsupported. It is re-raised as
  `UrlLaunchException` instead, matching how macOS reports an `NSURL` that will
  not construct. Reachable only with `allowUnsafe: true`, since the shape check
  refuses these URLs first.
- `UrlLaunchException.target` names the string the OS was actually handed, and
  the message shows it — for a `file:` URL that is the decoded path rather than
  the percent-encoded form, which is what a reader can recognise.
- **Repeated calls do not accumulate operating-system resources**, which matters
  for a long-running app that asks `canLaunchUrl` often. Each registry read hands
  its `HKEY` back and each macOS call drains its own autorelease pool, and both
  are now held by tests that were watched failing when the release was removed —
  20,000 lookups move the Windows process handle count by zero, and 50,000 macOS
  calls move resident memory by zero.
- The only runtime dependency is `ffi`, and there are no build hooks — a
  consumer can still `dart compile exe`. Both halves of that are now enforced by
  CI on real Windows and real macOS runners, with no Flutter installed: one
  guard compiles a generated consumer to a single executable and requires it to
  answer a question *positively*, and another fails the build if the runtime
  dependency list is anything but `ffi`. Neither guard catches the other's
  failure mode.

See the caveat on `launchUrl`'s return value in the README — on Windows 11 an
unregistered scheme reports success, which is why `canLaunchUrl` exists.
