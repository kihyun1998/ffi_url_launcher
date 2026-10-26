# Proving an effect on the operating system

## What it is
How each layer that touches an OS is proved, and the traps that make a green
test say nothing. Its subject is the test suite under `test/windows/` and
`test/macos/`, and the probes under `.scratch/`.

## Governing decisions
- [ADR-0002](../adr/0002-every-guard-is-asked-six-questions.md) — every guard
  answers polarity, instrument, scale, threshold, mutation and stated reason
  before it is trusted; all six are mandatory on FFI memory and ownership.

## Design model
### A cheap "no" is as narrow as a cheap "yes"
A negative is harder to catch than a positive, because the natural failure-path
test asserts exactly what a broken call already returns. The cheap "yes" table
is in [url-shape-check](url-shape-check.md).

| The negative | What it actually means | What the reader takes it for |
|---|---|---|
| `objc_msgSend` to a nullptr class returned `nil`/`NO` | **nobody was asked** — the framework was never mapped in | "macOS said no" |
| `canOpen` returned `false` | no handler is *registered* | "launching will fail" |
| `launch` returned `false` on Windows | effectively unreachable for a scheme | "nothing opened it" |

**Every OS-facing layer needs at least one positive assertion** — a test that
fails if the OS was never asked. Negative-only coverage cannot tell the two
apart ([lessons.md](../agents/lessons.md) #9; ADR-0002 question 1).

### Proof method per layer
(Carried from the retired `theflow.md` Step 4 at 2ef7cc0; each row re-read
against the named test, 2026-10-26.)

| Layer | Proof |
|---|---|
| Shape check | table-driven tests over the **exact strings measured to fool a naive guard** — `C:\Windows\System32\calc.exe`, `\\attacker\share\evil.exe`, `evil.bat` — beside the ones that must pass (`file:`, `ms-settings:`, `mailto:`, a custom scheme). `test/url_safety_test.dart` |
| Return-code decoding | a fake status per documented `ShellExecuteW` code, asserting the three-way split. `test/windows/shell_execute_status_test.dart`, `windows_backend_test.dart` |
| Windows scheme lookup | our FFI, cross-read with a **different reader** — `reg query "HKCR\<scheme>" /v "URL Protocol"`. Our reader agreeing with our writer proves nothing. `test/windows/scheme_registry_test.dart` |
| macOS handler lookup | our FFI, cross-read in Swift — `NSWorkspace.shared.urlForApplication(toOpen:)` via `/usr/bin/swift` must name the same app. Assert a **positive**. `test/macos/ns_workspace_integration_test.dart`, *"finds the application registered for a common scheme"* |
| Launch, failure half | **Windows:** a path that does not exist → 2, no window — proves the DLL loaded, the symbol resolved, UTF-16 survived and code → exception fired. **macOS:** a missing `file:` URL → `NO`, no window. **Never an unregistered scheme on either** — Windows answers 42 ([lessons.md](../agents/lessons.md) #4), macOS raises a panel (#8, #9). A negative alone proves nothing here; the load is pinned by the lookup's positive |
| FFI object lifetime | the instrument is chosen **per resource kind** and proved on the resource it watches: `GetProcessHandleCount` for the Windows `HKEY` (a kernel object, invisible to RSS), `ProcessInfo.currentRss` for the macOS pool (in the address space, invisible to a handle count). Each guard needs (i) a mutation that deletes the release and turns it red, (ii) a positive control proving the counter moves on a real leak, and (iii) a ceiling derived from measured signal, noise and worst case, written beside the test. `test/windows/handle_lifetime_test.dart`, `ns_workspace_integration_test.dart` |
| Launch, success half | manual, once per backend — a browser appearing is the assertion; `example/` is the tool |
| Consumer round-trip | pre-release: `tool/compile_exe_guard.dart` (see [gates](gates.md)). Post-release: a throwaway consumer on the **version range**, no path override, so `pub get` fetches the real archive; `dart compile exe`, and the binary answers a question **positively**. Verified for `0.1.0`: `https:` → `true`, an unregistered scheme → `false`, a drive path → `UnsafeUrlError(driveLetter)`, two resolved dependencies |

### Traps
- **The tautological proof.** Our reader agreeing with our writer says nothing
  about whether the OS accepts what we produced; every OS-facing layer cross-reads
  with an OS-native tool. `shell_execute_integration_test.dart`'s non-ASCII case
  once asserted a reason it could not fail for — correct UTF-16, UTF-8 bytes cast
  to `Utf16` and low-byte truncation all return 2 — and is now labelled crash
  detection (its own comment; ADR-0002 Consequences).
- **A performance number under `dart run` measures the JIT.** A consumer's cost is
  AOT: a cold one-shot registry lookup measured 5,165–10,073 µs under `dart run`
  against 174–244 µs compiled — 28×. Compile the probe, and prefer the cold number
  ([lessons.md](../agents/lessons.md) #12).
- **One pass cannot tell a cache from a leak.** The launch path measured 170
  bytes/call over one pass — close to the 209 bytes/call of a real macOS leak
  (#11) — and 138 → 16 → −4 over three: a cache. Run at least two passes and say
  which decayed; it is why the macOS guard warms up first (#12).
- **Sequential A-then-B blocks against a shared OS resource measure drift.** Two
  implementations within 2% reported +25%, +3%, −25%, −63%, +11%, −18%, −2%, −20%
  across eight runs. Interleave A/B/A/B, alternate the leader, report spread beside
  the median (#12).
- **CI cannot verify what the package is for.** A green matrix proves "the call was
  shaped as intended", never "the browser opened"; the success half's absence is a
  **known gap, not a covered case**.
- **The example is a proof surface and the tests are not.** Sibling
  `just_autostart` shipped 31 green tests beside a self-contradicting user-facing
  message; running the example caught it.
- **Probe inputs must be ones the package can produce**: drive `workspaceOpenUrl`
  / `workspaceCanOpenUrl` with `Uri.parse(…).toString()`, never a raw literal
  ([lessons.md](../agents/lessons.md) #13).
- **Open a cited entry before trusting a line that cites it** — a dartdoc citing
  #8 had outlived #8's own correction (#14).

## Code
- `test/` — `git ls-files test` lists it; the integration tests are
  `test/windows/shell_execute_integration_test.dart`,
  `test/windows/scheme_registry_test.dart`,
  `test/windows/handle_lifetime_test.dart`,
  `test/macos/ns_workspace_integration_test.dart`.
- `.scratch/ffi-url-launcher/probes/` — committed measurement probes, valid as of
  their commit; the numbers live in `lessons.md`.

## Reference behaviour
- ADR-0002's evidence table maps each question to the test that answers it.

## Cross-cutting invariants
**None.** It proves the invariants; it does not hold one.

## Blast radius
- [Gates](gates.md) — the derived thresholds and the per-runner split are this note's rules enforced; moving a threshold in CI removes a guard.
- [Windows launch](windows-shell-and-registry.md) and [macOS launch](macos-launch.md) — the CI-safe inputs come from their measurements; a new launch test needs an input measured UI-free.
- [Windows handler lookup](windows-handler-lookup.md) — the handle guard covers only `isSchemeRegistered`.
- [macOS Objective-C binding](macos-nsworkspace.md) — the memory guard depends on the pool being where the binding puts it.

## Known holes / open
- **The launch success half is manual**, once per backend, and not recorded per
  release anywhere in the repo.
- **Performance preconditions are not a record**: ADR-0002 leaves them as traps
  until a third performance incident lands.
- **ADR-0002's Consequences still cite `theflow.md` Step 4** for the FFI-lifetime
  row and the success-half gap; that content is now in this note. Records are not
  edited by the map.
