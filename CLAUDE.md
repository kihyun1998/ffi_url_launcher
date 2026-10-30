# CLAUDE.md

## Working discipline — thegraph

Substantive changes (a feature slice, a bug fix, a refactor touching the public
surface) run through **`/thegraph`**; its build is `docs/agents/thegraph.md`.
Per-incident evidence is in **`docs/agents/lessons.md`** — add each new incident
there.

- **Convention:** ticket → implement → `/code-review` → commit referencing the
  issue (`Closes #n`) → fast-forward merge to `main` → push → confirm CI green.
  No PR flow; this is a solo repo, matching the family.
- **Release:** before a release, run `pub-ready`. The `sdk:` floor rises only
  in a minor or major bump with its reason recorded, never as a side effect of a
  newer language feature.
- **Always a refuting second pass** (`lens`), whatever the enumeration risk
  `[product]`: (1) anything that decides whether a string reaches `ShellExecuteW`,
  or builds that string — a miss is arbitrary code execution on data the caller
  may have from a network; (2) FFI memory, buffer-size negotiation and object
  ownership — a mistake is process corruption, not a failing test. ADR-0002's six
  questions are mandatory on (2).
- **`[product]` marks the maintainer's call.** A derivation falls to a better
  derivation; a product judgement falls only to the person who made it.

## Identity & invariants (the boundary)

`ffi_url_launcher` opens a URL in the system's registered handler on **Windows
and macOS**, calling the OS directly through `dart:ffi`. It is pure Dart: no
Flutter dependency, no native sources to compile, no build hooks, and no step
where a consumer opens Visual Studio or Xcode.

Its identity is a **boundary**: the package owns the **mechanism** — how a URL
reaches the OS handler, how "is there a handler" is answered, and the platform
code → typed exception mapping. The calling application owns the **policy** —
which URL, whether its source is trusted, whether `file:` is allowed, any scheme
whitelist, and all UI. Before deciding where something lives, or "fixing" one of
the contracts below, read the note under `docs/map/` for that area —
`url-shape-check.md` for the boundary itself; each contract's measured reason is
recorded there.

- **Contract, not a defect — the shape check is on by default.** A caller cannot
  know that `Uri.parse(r'C:\...')` yields a one-letter scheme `ShellExecuteW`
  executes. It is a **shape** check, never a **trust** check; `allowUnsafe: true`
  is the caller's to set.
- **Contract, not a defect — the check is partial, and the README says what it
  does not block.** `file:///C:/…/calc.exe` passes and executes; a partial guard
  described as "validated" moves the caller's belief without moving their risk.
- **Contract, not a defect — a scheme whitelist is refused.** A **product
  decision**, the maintainer's to reverse, not a derivation to re-argue.
- **Contract, not a defect — `canLaunchUrl` is always true for `file:`.** Scheme
  registration and file-extension association are different registry layers.
- **Contract, not a defect — the platform error code is null on macOS.**
  `NSWorkspace.open` returns a bare `BOOL`; leave the code null rather than
  invent one for symmetry.
- **Contract, not a defect — the `Future` API wraps a synchronous call.**
  `NSWorkspace` wants the main thread and `ShellExecuteW` the caller's COM
  apartment, so the call stays on the calling isolate.

- **Nothing fails ambiguously.** An expected failure — nothing is registered to
  open this URL — returns `false`. Everything else raises a typed exception
  carrying the platform code where one exists.
- **The dependency list is an invariant, not a preference.** `ffi` only. A
  dependency that declares `hooks:` breaks `dart compile exe` for every consumer,
  and a Windows-only dependency misstates this package's platform support. Both
  pass every gate except the one that exists to catch them (`lessons.md` #1).

- **Recurring hazard — every cheap "yes" answers a narrower question than the
  caller asked.** `ShellExecuteW > 32` means **the shell accepted the request**,
  not that the URL opened — **measured: an unregistered scheme returns 42, i.e.
  success** (`lessons.md` #4). Every guard states which question it answers, in
  its own dartdoc; add each new narrow affirmative to the table in
  `docs/map/url-shape-check.md`.

## Seams

- **`UrlLauncherBackend` is the one seam.** Operations are identical across
  platforms; the differences live in *how* the OS is asked. It is not exported
  from `lib/ffi_url_launcher.dart`, so outside code cannot name the argument
  type without reaching into `src/` — that, not an annotation, keeps the seam
  from becoming load-bearing API.
- **Injection is public named constructors and parameters, not
  `@visibleForTesting`.** That annotation lives in `package:meta`, which would
  break the `ffi`-only invariant.
- **Two seams of different kinds.** `UrlLauncher.withBackend` replaces a whole
  platform; `WindowsUrlLauncherBackend(shellExecute:)` replaces one call, so the
  status→result arms can be driven with codes a real machine will not produce on
  demand. Neither substitutes the **marshalling**, which is proved against the
  real DLL — a fake `ShellExecuteW` proves only that the fake behaves as written.
- **`example/` is the only in-repo consumer seam, and a specification.** It
  reaches the package through the public API only; a new public API is proven by
  being used there, and it never models a practice the package documents
  against.
- **The README carries**, because each is discovered painfully otherwise: the
  blocked / not-blocked table with `file:` named as an execution vector; that
  `canLaunchUrl` is always true for `file:`; that the platform code is null on
  macOS; and the two reasons to choose this package — no Flutter dependency, and
  `dart compile exe` works.

## Territory map

The map's hub is [`docs/map/README.md`](docs/map/README.md). **Before designing a
change** (thegraph's `read-it`), open the territory it touches and follow its
`## Blast radius` and `## Cross-cutting invariants`. **After it lands**
(`check-it`), correct every note the change made false. When a fix reveals a
fact, ask whether it holds at every site that shares the same assumption — if
yes, the fix lands with an invariant note.

## Comments

A comment says what the code is. Why it is this way, what it deliberately leaves
out, the trap and the measured value go to the territory note under `docs/map/`.
Where none seems to hold it, search the folder and the code symbol first; only
then start a new note, named for what the system does there, not for the file.
History goes to the commit message. Comments written before this rule still carry
the rest: never delete one whose content the map does not yet hold — move it
there first.

## Agent skills

### Domain docs

**Single-context** — `GLOSSARY.md` plus `docs/adr/` at the repo root. See
`docs/agents/domain.md` for how skills consume them.

- **ADR-0001, "Every URL is asked two independent questions, in order"** — read it
  before changing anything between a caller's `Uri` and the OS call.
- **ADR-0002, "Every guard is asked six questions before it is trusted"** — read
  it before writing or changing any test that asserts an effect on the operating
  system.

### Issue tracker

GitHub Issues for `kihyun1998/ffi_url_launcher`, driven by the `gh` CLI. See
`docs/agents/issue-tracker.md` for the conventions and how blocking edges are
represented.

The long-form design records live in `.scratch/ffi-url-launcher/issues/`; each
names the GitHub issue that carries its state.

### Triage labels

The five canonical roles, separated by **evidence**, not urgency. See
`docs/agents/triage-labels.md`.
