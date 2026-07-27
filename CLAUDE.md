# CLAUDE.md

## Working discipline — theflow

Substantive changes (a feature slice, a bug fix, a refactor touching the public
surface) follow the **`theflow`** skill — run `/theflow` at the start. This
repo's bindings (module map, hidden-state list, reference routing, boundary rule,
proof methods, sacred paths, surfaces, gate matrix) live in
**`docs/agents/theflow.md`**; the per-incident evidence in
**`docs/agents/lessons.md`**. Read both before starting, and add new war-stories
to lessons with the step number they give teeth to.

The design record for the initial slice — seven tickets carrying the *why*, not
only the *what* — lives in `.scratch/ffi-url-launcher/issues/`.

## Identity & invariants (the boundary)

`ffi_url_launcher` opens a URL in the system's registered handler on **Windows
and macOS**, calling the OS directly through `dart:ffi`. It is pure Dart: no
Flutter dependency, no native sources to compile, no build hooks, and no step
where a consumer opens Visual Studio or Xcode.

Its identity is a **boundary** — it stays correct by *not* absorbing the concerns
of the application that calls it. theflow Step 2 grounds its judgement here.

- **The core owns the mechanism:** how a URL is handed to the OS handler and how
  "is there a handler" is answered on each OS — the `ShellExecuteW` call and its
  32-boundary return decoding, the `HKEY_CLASSES_ROOT` scheme lookup and its
  sign-extended handle, the `objc_msgSend` sequence into `NSWorkspace`, the
  `NSString`/`NSURL` lifetimes and autorelease discipline, and the platform error
  code → typed exception mapping.
- **The calling application owns the policy:** which URL to open and whether its
  source is trusted; whether to check `canLaunchUrl` first and what to do when it
  says no; whether `file:` should be permitted at all; any scheme whitelist; and
  every piece of UI. That is the boundary, not a workaround.

- **Contract, not a defect — the shape check is on by default.** That
  `Uri.parse(r'C:\...')` yields a one-letter scheme, and that `ShellExecuteW`
  will execute the forward-slashed result, is knowledge of how *these specific OS
  calls* read a string. A caller cannot be expected to know it, so leaving the
  check to them would be a trap with this package's name on it. It is a **shape**
  check (does this denote a local path?), never a **trust** check —
  `allowUnsafe: true` is the caller's to set.
- **Contract, not a defect — the check is partial, and the README says what it
  does not block.** `file:///C:/…/calc.exe` passes and executes; `file:` is a
  legitimate desktop feature. A partial guard described as "validated" is worse
  than no guard, because it moves the caller's belief without moving their risk.
- **Contract, not a defect — a scheme whitelist is refused.** What counts as an
  acceptable scheme differs per application. Owning that list would be this
  package absorbing a consumer's concern. **Product decision** recorded in
  `docs/agents/theflow.md` — the maintainer's to reverse, not a derivation to
  re-argue.
- **Contract, not a defect — `canLaunchUrl` is always true for `file:`.** Scheme
  registration and file-extension association are different registry layers.
- **Contract, not a defect — the platform error code is null on macOS.**
  `NSWorkspace.open` returns a bare `BOOL`. Do not invent a code to make the
  platforms look symmetric.
- **Contract, not a defect — the `Future` API wraps a synchronous call.**
  `NSWorkspace` wants the main thread and `ShellExecuteW` depends on the calling
  thread's COM apartment, so neither may move into a spawned isolate. The async
  signature exists to keep the option open, not because work is offloaded.

- **Nothing fails ambiguously.** An expected failure — nothing is registered to
  open this URL — returns `false`. Everything else raises a typed exception
  carrying the platform code where one exists.
- **The dependency list is an invariant, not a preference.** `ffi` only. A
  dependency that declares `hooks:` breaks `dart compile exe` for every consumer,
  and a Windows-only dependency misstates this package's platform support. Both
  pass every gate except the one that exists to catch them (`lessons.md` #1).

- **Recurring hazard — every cheap "yes" answers a narrower question than the
  caller asked.** `hasScheme` true means the string has a colon, not that it is a
  URL. `canLaunchUrl` true means the *scheme* is registered, not that the launch
  will succeed. `ShellExecuteW > 32` means a process started, not that the URL
  opened — **measured: an unregistered scheme returns 42, i.e. success, because
  the shell launched its own look-for-an-app dialog** (`lessons.md` #4). Every
  guard states which question it answers, in its own dartdoc.

## Agent skills

### Domain docs

**Single-context** — `CONTEXT.md` plus `docs/adr/` at the repo root. Neither
exists yet; `/domain-modeling` creates them lazily. Until one does, the decision
trail is the issue tracker plus `.scratch/ffi-url-launcher/issues/`.

### Issue tracker

GitHub Issues for `kihyun1998/ffi_url_launcher`, driven by the `gh` CLI. See
`docs/agents/issue-tracker.md` for the conventions and how blocking edges are
represented, and `docs/agents/triage-labels.md` for the label vocabulary — where
`ready-for-agent` and `needs-triage` are separated by **evidence**, not urgency.

The long-form design records live in `.scratch/ffi-url-launcher/issues/`; each
names the GitHub issue that carries its state.
