# Proving an effect on the operating system

How each layer is proved, and the traps that make a green test say nothing.
[ADR-0002](../adr/0002-every-guard-is-asked-six-questions.md) holds the six questions
every such guard is asked; incident evidence is in
[`lessons.md`](../agents/lessons.md).

## A cheap "no" is as narrow as a cheap "yes"

A negative can be just as narrow, and it is **harder** to catch, because the
natural test for a failure path asserts exactly the value a broken call already
returns:

| The negative | What it actually means | What the reader takes it for |
|---|---|---|
| `objc_msgSend` to a nullptr class returned `nil`/`NO` | **nobody was asked** — the framework was never mapped in | "macOS said no" |
| `canOpen` returned `false` | no handler is *registered* | "launching will fail" |
| `launch` returned `false` on Windows | (effectively unreachable for a scheme) | "nothing opened it" |

The measured instance is `lessons.md` #9: a probe that never loaded AppKit read
`NO` off a class the runtime had never heard of, and an entire suite of negative
assertions agreed with it. **Every OS-facing layer therefore needs at least one
positive assertion** — a test that fails if the operating system was never
actually asked. Negative-only coverage cannot distinguish the two states.

## Proof method per layer

| Layer | Proof |
|---|---|
| **Shape check** (`url_safety.dart`) | table-driven tests over the **exact strings that were measured to fool a naive guard** — `C:\Windows\System32\calc.exe`, `\\attacker\share\evil.exe`, `evil.bat` — alongside the ones that must pass (`file:`, `ms-settings:`, `mailto:`, a custom scheme). A test built only from obviously-bad inputs proves nothing here |
| **Return-code decoding** | a fake backend returning each documented `ShellExecuteW` code, asserting the three-way split (`> 32` → true, `31` → false, everything else → typed throw) |
| **Windows scheme lookup** | ask through our FFI, then cross-read the same key with a **different reader** — `reg query "HKCR\<scheme>" /v "URL Protocol"`. Our reader agreeing with our writer proves nothing about what Windows thinks |
| **macOS handler lookup** | ask through our FFI, then cross-read the **same question in Swift** — `NSWorkspace.shared.urlForApplication(toOpen:)`, run with `/usr/bin/swift`, must name the same application. This is not optional politeness: it is the reader that caught `lessons.md` #9, where our FFI and our own tests agreed with each other and were both wrong. Assert a **positive** (a scheme that resolves to a real app), never only absences |
| **Launch, failure half** | **Windows:** a **path that does not exist** returns 2 and opens no window — this proves the library loaded, the symbol resolved, UTF-16 marshalling survived, and the code→exception mapping fired. CI-safe. ⚠ **Not** "an unregistered scheme returns `false`": that was the original claim and the measurement falsified it (`lessons.md` #4). **macOS:** a **missing `file:` URL** answers `NO` with no window — the same role, and the same *shape* of input as Windows. ⚠ **Not** an unregistered scheme: it answers `NO` too, but raises a modal panel, so it is skipped exactly as its Windows twin is (`lessons.md` #8 correction, #9). ⚠ **And a negative alone proves nothing here** — a nullptr class returns `NO` as convincingly as the real one, so the load must be pinned by a **positive** assertion in the lookup group |
| **FFI object lifetime** (the second completeness trigger in `CLAUDE.md`) | **the instrument is chosen per resource kind, and proved on the resource it is watching.** A kernel object (an `HKEY`) is charged to paged pool and is invisible to RSS; an autoreleased Objective-C object is in the address space and invisible to a handle count. So: `GetProcessHandleCount` for the Windows registry handle, `ProcessInfo.currentRss` for the macOS pool. Each guard needs **three** things, not one — (i) a mutation that deletes the release and turns it red, (ii) a **positive control** proving the counter moves when the resource really leaks, since the assertion itself is a negative and `lessons.md` #9 is what a suite of negatives costs, and (iii) a ceiling **derived** from the measured signal, the measured noise, and the measured worst case, written beside the test |
| **Launch, success half** | manual, once per backend. A browser actually appearing is the assertion, and there is no automated substitute |
| **Consumer round-trip** | **Live since `0.1.0`.** Two forms, and they prove different things. *Pre-release:* `dependency_overrides: {ffi_url_launcher: {path: ../ffi_url_launcher}}` in the consumer, then the consumer's **full** suite — this is what `tool/compile_exe_guard.dart` automates. *Post-release:* a throwaway consumer depending on the **version range**, with no path override, so `pub get` fetches the real archive — the only thing that proves *what actually shipped* works rather than what is in the working directory. Run it once per release: `dart pub get` → `dart compile exe` → the binary must answer a question **positively** (`lessons.md` #9). Verified for `0.1.0`: `canLaunchUrlSync('https://dart.dev')` → `true`, an unregistered scheme → `false`, a drive path → `UnsafeUrlError(driveLetter)`, and exactly two resolved dependencies |

**Trap — the tautological proof.** Our reader agreeing with our writer says
nothing about whether Windows or `NSWorkspace` will accept what we produced.
Every OS-facing layer above cross-reads with an OS-native tool for that reason.

**Trap — a performance number measured under `dart run` is measuring the JIT.**
This package's central promise is that a consumer can `dart compile exe`, so the
consumer's cost is the **AOT** cost, and the two are not close: a cold one-shot
registry lookup measured **5,165–10,073 µs under `dart run` against 174–244 µs
from a compiled binary — 28x**. Every conclusion drawn from the JIT number is
about a cost nobody pays; `Platform.environment`'s first access looked like 25%
of the cold path at 1.5 ms and is 70 µs in AOT. **Compile the probe.** And prefer
the *cold* number to the amortised one — a CLI opens one URL and exits, so
steady-state throughput is not what its user waits for. See `lessons.md` #12.

**Trap — a single-pass memory measurement cannot tell a cache from a leak.**
Both grow on the first pass and only one keeps growing, so one pass reads the
same either way. The launch path measured **170 bytes/call** over one pass —
close enough to the 209 bytes/call of a real macOS leak (#11) to look like one —
and three passes gave 138 → 16 → **−4**, i.e. a cache being populated. **Always
run at least two passes and say which decayed**; a leak holds its rate, a cache
collapses toward zero. This is why the macOS guard warms up before it measures,
and it is the rule that both this project's memory measurements now follow.

**Trap — measuring against a shared OS resource in sequential A-then-B blocks.**
The registry has its own caches and other processes are hitting it, so
consecutive timing blocks measure drift rather than code. Two implementations
that are genuinely within 2% of each other reported +25%, +3%, −25%, −63%, +11%,
−18%, −2%, −20% across eight such runs — a swing wide enough to "prove" whichever
answer you wanted. **Interleave A/B/A/B and compare medians**, alternating which
variant leads, and report the spread beside the median so a claim that does not
clear it cannot be made. Same entry.

**Trap — CI cannot verify the thing the package is for.** A green matrix proves
"the call was shaped as intended", never "the browser opened". The success half
of launch is manual, once per backend, and its absence from CI is a **known gap,
not a covered case.** Say which of the two you have.

**Trap — the example is a proof surface and the tests are not.** Sibling
`just_autostart` shipped 31 green tests alongside a user-facing message that
contradicted itself; running the example caught it. Documentation and
user-facing strings are read, not asserted.

**Trap — a guard that is never exercised against a real launch.** The shape
check's whole purpose is to sit between a caller's string and `ShellExecuteW`.
Prove at least once, by hand, that a blocked string never reaches the shell —
not merely that the function throws.
