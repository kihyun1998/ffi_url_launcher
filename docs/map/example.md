# Example

## What it is
`example/ffi_url_launcher_example.dart`: the only in-repo consumer, reaching the
package through its public API alone, and the tool for the manual success-half
proof.

## Governing decisions
**None.** `CLAUDE.md` › Seams states its role.

## Design model
- **A specification, not a demo**: a new public API is proven by being used here,
  and it never models a practice the package documents against (`CLAUDE.md`).
- **It asks `canLaunchUrl` first** rather than branching on `launchUrl`'s result,
  because the latter is the pattern the package documents against (the example's
  own comment; [lessons.md](../agents/lessons.md) #4).
- **It passes its argument through untouched**, so `""` or `C:\Windows\…` shows
  the `UnsafeUrlError` branch; pre-filtering would hide the behaviour it exists to
  demonstrate.
- **It prints `error.target`**, the string the OS was handed — the decoded path for
  a `file:` URL.
- **A browser appearing is its assertion** — the one CI cannot make.

## Code
- `example/ffi_url_launcher_example.dart — main`

## Reference behaviour
**None.**

## Cross-cutting invariants
**None.**

## Blast radius
- [Public API](public-api.md) — every exported function and exception it uses; a changed signature breaks it, and `dart analyze` is the only gate that notices.
- [Error model](error-model.md) — it catches each exception type by name.
- [Proving OS effects](proving-os-effects.md) — the manual success half is run with it.

## Known holes / open
- **Executed by nothing** — `dart test` does not run it ([gates](gates.md)).
