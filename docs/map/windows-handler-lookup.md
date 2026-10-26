# Windows handler lookup

## What it is
Question (C) on Windows: is anything registered to open this URL? Answered by
reading whether `HKEY_CLASSES_ROOT\<scheme>` carries a `URL Protocol` value —
a read with no side effects, safe in CI.

## Governing decisions
- [ADR-0001](../adr/0001-two-questions-about-every-url.md) › *What this does not
  cover* — (C) is a separate question from (A) and (B), per platform, and never
  refuses.
- **Switching the reader to `RegGetValueW` was measured and declined — #14,
  `wontfix`, `[product]`.** It would leave no `HKEY` in our hands at all, but
  there is no measured defect, and buying it would mean editing the most dangerous
  file and leaving the handle guard nothing to mutate (ADR-0002 question 5).
  Measured: identical answers on 11 inputs, zero handle growth over 20,000 calls,
  +1.8% / −1.7% / +4.6% interleaved medians — nothing, since in AOT what this
  package controls is 0.96 µs of a ~20 µs lookup ([lessons.md](../agents/lessons.md)
  #12; maintainer's decision recorded in the retired `theflow.md`, carried at
  2ef7cc0). **It expires on its own** if the package starts reading a registry
  *value*, a second registry path appears, or a handle leak happens once.

## Design model
- **Presence of `URL Protocol` is the whole answer**; every out-parameter is null,
  so the value's bytes are never read (`scheme_registry.dart — isSchemeRegistered`,
  `_regQueryValueExW` comment). That is what keeps `RegQueryValueExW`'s missing
  null-terminator guarantee from mattering — **the moment anything reads a value,
  the reader must become `RegGetValueW`**.
- **Every failure is `false`, never an exception** — the stated exception in
  [false-means-nothing-registered](false-means-nothing-registered.md)
  (maintainer, 2026-10-26).
- **Two guards stop `RegOpenKeyExW` succeeding on something that is not the
  scheme's key.** An empty name returns the predefined hive handle itself (which
  the code would then `RegCloseKey`); a separator reopens something real (a bare
  `\` reopens the HKCR root). Measured on Windows 11 (26200), in the function's
  own comment. Closing a predefined handle affects other threads; harmless while
  the package is single-threaded and re-derives the handle per call — a
  condition, not "it does not matter".
- **`HKEY_CLASSES_ROOT` is spelled sign-extended**, `-2147483648`, as the header
  means it and `package:win32` generates it. The unsigned literal was **measured
  to work too** on Windows 11 (26200) for `RegOpenKeyExW` on all four hives
  ([lessons.md](../agents/lessons.md) #6), so this is the correct spelling, not
  the only working one (`scheme_registry.dart — _hkeyClassesRoot` dartdoc).
- **HKCR is a merged view** of `HKLM\Software\Classes` and
  `HKCU\Software\Classes`, so per-user installs — most applications — are
  covered; `HKLM` alone would miss them.
- **The lookup is per scheme**, taken from `Uri.scheme` (already lowercased; the
  registry is case-insensitive either way) — `windows_backend.dart —
  WindowsUrlLauncherBackend.canOpen`. The reference searches the string for `:`.
- **`file:` always answers true**: `HKCR\file` carries `URL Protocol`
  unconditionally, while `ShellExecuteW` may still fail with 31 for an
  unassociated extension. Scheme registration and file-extension association are
  different layers (measured on a real machine; `CLAUDE.md` contract).
- **`false` can under-report**: `shell:` has no key under HKCR (measured) yet the
  shell handles it (`{@template can_open_contract}`).
- **A leaked `HKEY` is invisible to resident memory** — a kernel object is charged
  to paged pool, never to the address space `ProcessInfo.currentRss` measures, so
  the instrument is `GetProcessHandleCount`
  (`test/windows/handle_lifetime_test.dart`; [lessons.md](../agents/lessons.md) #12).
- Input bound: the scheme is a caller's `Uri.scheme`; nothing bounds its length.

## Code
- `lib/src/backends/windows/scheme_registry.dart — isSchemeRegistered`, `_hkeyClassesRoot`, `_keyQueryValue`, `_regOpenKeyExW`, `_regQueryValueExW`, `_regCloseKey`
- `lib/src/backends/windows/windows_backend.dart — WindowsUrlLauncherBackend.canOpen`, `WindowsUrlLauncherBackend.schemeIsRegistered`

## Reference behaviour
- `url_launcher_windows` reads the same value with three null out-parameters
  ([thegraph.md](../agents/thegraph.md)).
- Sibling `just_autostart`'s `registry.dart` for hand-written `advapi32` and the
  predefined-handle spelling — its lessons #7 (wrong handle from memory) is why
  constants are cross-checked against `package:win32` (binding).

## Cross-cutting invariants
- [false-means-nothing-registered](false-means-nothing-registered.md)
- [platform-libraries-open-lazily](platform-libraries-open-lazily.md)
- [system-libraries-load-by-absolute-path](system-libraries-load-by-absolute-path.md)

## Blast radius
- [Proving OS effects](proving-os-effects.md) — the handle-count guard covers only `isSchemeRegistered`; a second registry path needs its own guard (and expires #14's decision).
- [Windows launch](windows-shell-and-registry.md) — callers rely on this lookup because launch's `true` cannot answer it; if it stops answering honestly, the README's "ask first" advice is wrong.
- [macOS handler lookup](macos-handler-lookup.md) — the same signature answers a different question (per scheme here, per URL there); a change that "aligns" them changes what `canLaunchUrl` means on one OS.
- [Publishing](publishing.md) — the README says `canLaunchUrl` is always true for `file:`.

## Known holes / open
- **The predefined-handle thread-safety condition** holds only while the package
  is single-threaded and re-derives the handle per call (`isSchemeRegistered`
  comment).
- **Schemes the shell answers without a registry entry** (`shell:`) read as
  `false`. Documented, not closed.
