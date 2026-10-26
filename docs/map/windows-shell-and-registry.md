# Windows: ShellExecuteW and the scheme registry

These are states the OS tracks, or marshalling the reference's language hid, that a first-principles
model omits because the model "looks correct". Read this before touching `lib/src/backends/windows/`, and add an entry
when a pass finds another. Incident evidence: [`lessons.md`](../agents/lessons.md).

- **Predefined `HKEY` roots are sign-extended on 64-bit.** The Win32 header casts
  to `(LONG)` before widening to `ULONG_PTR`, so `HKEY_CLASSES_ROOT` is
  `0xFFFFFFFF80000000`, not `0x80000000`. In Dart it must be
  `Pointer.fromAddress(-2147483648)`; the unsigned literal produces a handle
  Windows does not recognise. Confirmed for `HKEY_CURRENT_USER` in sibling
  `just_autostart` (its lessons #7, against `package:win32`'s generated source).
- **`ShellExecuteW` signals success with a return value greater than 32.** The
  return type is `HINSTANCE` for historical compatibility; every value ≤ 32 is an
  error code. `SE_ERR_NOASSOC` is 31 and is the common, expected one — "nothing is
  registered to open this", not a fault.
- **`ShellExecuteW` returns once the shell has accepted the request**, not once
  the target has loaded. It cannot report whether the page opened.
- **An unregistered *scheme* answers 42 — success — not `SE_ERR_NOASSOC`.**
  Measured on Windows 11 (26200). `SE_ERR_NOASSOC` is **not reachable through a
  URL scheme** on modern Windows, so `launch()` returning `true` does not mean
  anything the user wanted opened, and the registry check (`canLaunchUrl`) is
  the only reliable answer — which is why it is a separate operation rather than
  a convenience.
- **What 42 means is "the request was accepted", not "the shell opened its own
  picker".** That second sentence was written here once and does not survive
  re-running: the identical string answered 42 with a dialog under `dart run`
  (twice) and 42 with no dialog under `dart test` (once). The empty string did
  open File Explorer. **Do not explain 42 by a window** — the window is not
  reliably there and the trigger is unidentified. See
  [`lessons.md`](../agents/lessons.md) #4.
- **Anything handed to `ShellExecuteW` can open a window, including inputs that
  look inert.** The empty string is the proof. Never call the launch path in CI
  with an input that has not been measured to be UI-free.
- **A path that does not exist answers 2 (`SE_ERR_FNF`), with no UI.** This is
  the reachable error code, and the one the real round-trip proof uses.
- **`RegQueryValueExW` does not guarantee a null terminator** on string values;
  `RegGetValueW` does. This package only tests a value's *existence* and never
  reads its bytes, so the hazard does not bite here — but any change that starts
  reading a value must switch reader.

  **Switching *now* was measured and declined — #14, `wontfix`, `[product]`.**
  `RegGetValueW` takes the subkey and the value name together and opens and closes
  internally, so it collapses three calls into one **and leaves no `HKEY` in our
  hands at all** — the leak class becomes impossible rather than guarded. Measured:
  identical answers on all 11 inputs, zero handle growth over 20,000 calls, and a
  speed difference of +1.8% / −1.7% / +4.6% (interleaved medians), i.e. nothing —
  because in AOT everything this package controls is 0.96 µs of a ~20 µs lookup.
  Declined because there is **no measured defect** (the handle discipline is
  correct and #13 now gates it), and buying the remaining argument would mean
  editing the most dangerous file in the package **and** making #13's guard
  unmutatable — permanently unanswerable on ADR-0002's question 5. **The decision
  is the maintainer's to reverse, not a derivation to re-argue** — but it expires
  on its own if any of these become true: this package starts reading a registry
  *value* (then `RegGetValueW` is mandatory anyway, per the sentence above), a
  *second* registry path appears (#13's guard covers only `isSchemeRegistered`), or
  a handle leak actually happens once. Numbers in `lessons.md` #12.
- **A leaked `HKEY` is invisible to resident memory.** The registry lookup is the
  only place this package holds a **kernel object**, and a kernel object is
  charged to the process's paged-pool quota — never to the address space
  `ProcessInfo.currentRss` measures. Measured, the leaking and the correct run
  land in the same RSS noise band. **So the macOS memory test's shape does not
  port here**: copying `ns_workspace_integration_test.dart`'s `currentRss`
  assertion to Windows produces a test named for accumulation that sits green
  with 50,000 handles leaked behind it — the exact disease #11 was opened for,
  reproduced by copying its cure. The instrument for a kernel object is
  `GetProcessHandleCount`. Numbers in `lessons.md` #12.
- **`HKEY_CLASSES_ROOT` is a merged view** of `HKLM\Software\Classes` and
  `HKCU\Software\Classes`. Reading it therefore covers per-user installs, which
  is most modern applications. Reading `HKLM` alone would miss them.
- **Scheme registration and file-extension association are different layers.**
  `HKCR\file` carries `URL Protocol` unconditionally, so a `file:` URL always
  answers "launchable" while `ShellExecuteW` may still fail with 31 for an
  unassociated extension. Measured on a real machine.
- **`ShellExecuteW` accepts forward slashes in a drive path.** This is what makes
  the `Uri`-scheme-of-length-1 case an execution vector rather than a curiosity.
- **`ShellExecuteW` decodes ASCII percent-escapes in a `file:` URL but not
  multi-byte UTF-8 ones.** `%20` becomes a space; `%ED%95%9C` is read as three
  literal characters. The reference works around it with `UrlUnescapeA`; this
  package converts to a native path with `Uri.toFilePath` instead. See
  [`lessons.md`](../agents/lessons.md) #5.
- **`Uri.toString()` is not identity.** It percent-encodes non-ASCII, spaces and
  `<>"`, and lowercases the scheme. Any reasoning about what the shell receives
  must be done on `toString()`'s output, not on the string the caller wrote —
  the package *manufactures* the encoding that breaks `file:`.
- **`Uri.toFilePath` throws for a query or fragment**, and for any scheme but
  `file`. Measured: `file:///C:/a.txt?q=1` and `#frag` both raise
  `UnsupportedError` naming the offending component. **That error type is
  already spoken for** — the public API documents `UnsupportedError` as "this
  platform has no backend" — so the shape check refuses those URLs before the
  conversion can raise it. A leaked `UnsupportedError` would read as an
  unsupported operating system.
- **Having a scheme is not the same as denoting a target.** `file:`, `file://`,
  `file:/` and `file:///` all normalise to `file:///` and convert to a bare `\`
  — an *existing* directory, the root of the current drive
  (`Directory(r'\').existsSync()` is `true`, resolving to `D:\` here). Opening
  it launches a file browser, which is the empty-string hazard arriving with a
  scheme attached. Any rule written as "does it have a scheme" misses this whole
  class.
- **KnownDLLs decides whether a bare DLL name is safe**, and the family rule is
  to not depend on knowing which. `shell32`, `advapi32`, `ole32` are on the
  list; `dwrite` is not, and a hostile `dwrite.dll` beside the executable *was*
  loaded in a probe while a hostile `shell32.dll` was ignored. Load system DLLs
  by absolute `%SystemRoot%\System32` path regardless.
