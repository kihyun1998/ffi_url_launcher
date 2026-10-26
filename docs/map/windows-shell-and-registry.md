# Windows launch

## What it is
How a URL reaches the Windows shell: question (B) for Windows — the exact string
`ShellExecuteW` needs — then the call itself, and the decoding of its return
value into launched / no handler / failed. (The path is kept from the earlier
map, where it also held the registry lookup; that is now
[windows-handler-lookup](windows-handler-lookup.md).)

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) — `shellTargetFor` is
  (B) on Windows: it may transform freely and never refuses on policy; a
  marshalling failure is `UrlLaunchException`.

## Design model
- **Success is a return value greater than 32.** The SDK header states
  `_Success_(return > 32)` (`shellapi.h:103`); every value ≤ 32 is an error,
  including `SE_ERR_DLLNOTFOUND`, which is exactly 32, so `>=` would turn a failure
  into a success (`shell_execute.dart — interpretShellExecuteStatus`;
  `test/windows/shell_execute_status_test.dart`, *"treats 32 itself as a failure"*).
- **`SE_ERR_NOASSOC` (31) is the one ordinary "no"** → `false`; every other code ≤
  32 → `UrlLaunchException` carrying the code (`windows_backend.dart —
  WindowsUrlLauncherBackend.launch`).
- **`> 32` means the shell accepted the request**, not that the target loaded
  and not that a handler exists. **An unregistered scheme answers 42 — success**;
  `SE_ERR_NOASSOC` is not reachable through a URL scheme on modern Windows, only
  through a file extension with no association. Measured on Windows 11 (26200)
  ([lessons.md](../agents/lessons.md) #4). So `launch` returning `false` is
  effectively unreachable for a scheme, and [the handler lookup](windows-handler-lookup.md)
  is the only reliable answer — which is why it is a separate operation.
- **Do not explain 42 by a window.** The identical unregistered-scheme string
  answered 42 with a "you'll need a new app" dialog under `dart run` (twice) and
  42 with no dialog under `dart test` (once); the trigger is unidentified
  ([lessons.md](../agents/lessons.md) #4).
- **Anything handed to `ShellExecuteW` can open a window**, including inputs that
  look inert: the empty string opened File Explorer (#4). Never call the launch
  path in CI with an input not measured to be UI-free. **A path that does not
  exist answers 2 (`SE_ERR_FNF`) with no UI** — the reachable error code, and the
  one the integration test uses (`test/windows/shell_execute_integration_test.dart`).
- **A `file:` URL becomes a native path; every other URL passes as written.**
  `ShellExecuteW` decodes ASCII percent-escapes in a `file:` URL but not multi-byte
  UTF-8 ones, so `file:///C:/%ED%95%9C.txt` is looked up literally and an existing
  file comes back `SE_ERR_FNF` ([lessons.md](../agents/lessons.md) #5). And
  `Uri.toString()` *manufactures* that encoding — it percent-encodes non-ASCII,
  spaces and `<>"` and lowercases the scheme — so reasoning about what the shell
  receives must be done on its output. `Uri.toFilePath(windows: true)` fixes it,
  keeps a file genuinely named `a%20b.txt`, and turns an authority into a UNC path
  (`shell_execute.dart — shellTargetFor` dartdoc; `test/windows/shell_target_test.dart`).
- **`toFilePath` throws `UnsupportedError` for a query or fragment**; it is caught
  and re-raised as `UrlLaunchException` — see
  [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md).
  Ordinarily unreachable, since the shape check refuses those URLs first.
- **`ShellExecuteW` accepts forward slashes in a drive path** — what makes the
  one-letter-scheme case an execution vector rather than a curiosity
  ([url-shape-check](url-shape-check.md)).
- **The failure names `target`, not `url`**: for a `file:` URL the percent-encoded
  form is not one a user recognises (`WindowsUrlLauncherBackend.launch` comment).
- **The return is read pointer-sized**, as `IntPtr`; the reference truncates to
  `int` first, which is safe only because every error code is small
  (`_shellExecuteW` comment).
- **Constants are read out of the SDK headers, with file and line**, never recited
  (`shell_execute.dart` constant block). Sibling `just_autostart` shipped a wrong
  handle constant from memory (its lessons #7).
- **The seam replaces one call, never the marshalling**: `shellExecute:` lets the
  status → result arms be driven with codes a real machine will not produce; the
  marshalling is proved against the real `shell32.dll` (`CLAUDE.md` › Seams).
- Input bound: none — the target string is the caller's URL, whole.

## Code
- `lib/src/backends/windows/shell_execute.dart — ShellExecuteOutcome`, `interpretShellExecuteStatus`, `describeShellExecuteStatus`, `shellTargetFor`, `shellExecuteOpen`, `_shellExecuteW`
- `lib/src/backends/windows/windows_backend.dart — WindowsUrlLauncherBackend.launch`, `WindowsUrlLauncherBackend.shellExecute`
- `lib/src/backends/windows/system32.dart — loadSystem32`

## Reference behaviour
- `url_launcher_windows`'s `url_launcher_plugin.cpp` for which call and in what
  order — an example ([thegraph.md](../agents/thegraph.md)). It unescapes the
  whole URL with `UrlUnescapeA` and keeps `file://`; this package converts to a
  path instead, measured better on a `%` in a file name and on an authority
  (`shellTargetFor` dartdoc).
- Microsoft Learn's `ShellExecuteW` page for signature and ownership — binding,
  summarized; the measured 42 outranks it.

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [unsupported-error-means-no-backend](unsupported-error-means-no-backend.md)
- [os-calls-stay-on-the-calling-thread](os-calls-stay-on-the-calling-thread.md)
- [platform-libraries-open-lazily](platform-libraries-open-lazily.md)
- [system-libraries-load-by-absolute-path](system-libraries-load-by-absolute-path.md)

## Blast radius
- [Windows handler lookup](windows-handler-lookup.md) — the launch path's `true` cannot say whether a handler exists; any change to what `launch` reports changes whether callers still need `canOpen`.
- [URL shape check](url-shape-check.md) — `shellTargetFor` assumes the refused shapes never arrive; a change here that accepts or converts them reopens the execution vector.
- [Error model](error-model.md) — the status code becomes `platformCode` and the target becomes `target`.
- [Proving OS effects](proving-os-effects.md) — the CI-safe input (a missing path → 2) is chosen from this note's measurements; a new input must be measured UI-free first.
- [Publishing](publishing.md) — the README's return-value table and the `launch_contract` template restate the 42 finding.
- [macOS launch](macos-launch.md) — the same `file:` URL must reach the same kind of answer on both; ADR-0001 keeps the decisions cross-platform and only the conversion Windows-specific.

## Known holes / open
- **The trigger for the "new app" dialog on 42 is unidentified** (lessons #4).
- **The success half is manual**: a browser appearing is the assertion, once per
  backend ([proving-os-effects](proving-os-effects.md)).
