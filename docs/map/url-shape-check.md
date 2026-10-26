# The URL shape check, and the narrow "yes"

Why the check in `lib/src/url_safety.dart` exists, what it refuses, and why it stops
where it does. ADR-0001 holds the two-question structure it sits in.

## Every cheap "yes" answers a narrower question

Each surface of this package can return an affirmative that a caller will read
as an answer to a **broader** question than the one it actually answers:

| The affirmative | What it actually means | What the caller reads it as |
|---|---|---|
| `Uri.parse` succeeded, `hasScheme` is true | the string has a colon in it | "this is a URL, not a local path" |
| `canLaunchUrl` returned true | a handler is registered for the *scheme* | "`launchUrl` will succeed" |
| `ShellExecuteW` returned > 32 | the shell accepted the request — an unregistered scheme answers 42 | "the URL opened" |
| `NSWorkspace.open` returned YES | the open request was accepted | "the page loaded" |

The measured instance: `Uri.parse(r'C:\Windows\System32\calc.exe')` yields
`scheme = 'c'` and `hasScheme = true`, and `ShellExecuteW` accepts the
forward-slashed form and **executes it**. A `hasScheme` guard therefore reads as
a safety check while providing none.

**Every guard states which question it answers, in its own dartdoc.** When a
pass finds another narrow affirmative, add the row.

## Two path shapes, two checks

- **`Uri.parse` on a Windows path succeeds and produces a one-letter scheme.**
  `hasScheme` is true for `C:\...`. Any guard written as "it parsed, so it is a
  URL" is not a guard.
- **A UNC path (`\\host\share\x.exe`) parses with no scheme at all** — so the two
  hazards need two different checks, and either check alone leaves a hole.

## Why the check is the package's, and why it is partial

**The shape check is mechanism, not policy.** `[product]` — that
`Uri.parse(r'C:\...')` yields a one-letter scheme, and that `ShellExecuteW` will
execute the forward-slashed result, is **knowledge of how these specific OS calls
interpret a string**. A caller cannot be expected to know it, so leaving the
check to them is not a boundary — it is a trap with the package's name on it.
This is why the check is on by default. It is deliberately a **shape** check
(does this denote a local path?) and never a **trust** check.

**Policy — the calling application owns it by definition.** Which URL to open and
whether its source is trusted; whether to call `canLaunchUrl` first and what to
do when it says no; whether `file:` should be permitted at all; any scheme
whitelist beyond the shape check; retries; telemetry; and every piece of UI. A
scheme whitelist was weighed as a default and **declined** `[product]` — what
counts as an acceptable scheme differs per application, so owning that list would
be the package absorbing a consumer's concern.

**`allowUnsafe: true` is the concrete expression of this boundary.** The package
performs the check it alone can perform; the caller decides whether it applies.

**The check is partial by design, and says so.** `file:///C:/…/calc.exe` passes
every check and executes. `file:` is a legitimate desktop feature the reference
supports deliberately. Documenting *what is not blocked* beside what is blocked
is therefore part of the mechanism, not a README nicety — a partial guard
described as "validated" is worse than no guard, because it moves the caller's
belief without moving their risk.
