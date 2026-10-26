# CLAUDE.md

## Working discipline — theflow

Substantive changes (a feature slice, a bug fix, a refactor touching the public
surface) follow the **`theflow`** skill — run `/theflow` at the start. Before
starting, read this repo's bindings in **`docs/agents/theflow.md`**
(`grep '^## ' docs/agents/theflow.md` lists them) and the per-incident evidence
in **`docs/agents/lessons.md`**. Add each new war-story to lessons with the step
number it gives teeth to.

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
the contracts below, read `docs/agents/theflow.md` Step 2 and its hidden-state
list; each contract's reason is recorded there.

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
  its own dartdoc; add each new narrow affirmative to the cheap-"yes" table in
  `theflow.md`.

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
