# ADR-0002 — Every guard is asked six questions before it is trusted

**Status:** accepted
**Promoted from:** no spine — the cluster was already four issues deep before it
was recognised, which is itself the evidence (see Context)
**Conformance items:** #6, #7, #9, #11, #13 (all closed, retroactively)

## Context

This package's tests are unusually load-bearing. Almost nothing it does can be
checked by eye: the correctness lives in FFI marshalling, in OS return codes, and
in object lifetimes, and every one of those fails *quietly*. So a guard going
green is, in practice, the only thing standing between a defect and a release.

Five times now, a guard has been green while proving nothing — and each time the
diagnosis has been treated as a fresh discovery:

| | The guard | What was actually wrong | How it was found |
|---|---|---|---|
| #6 | the predefined-`HKEY` spelling | the **reason** written beside it was never measured — both spellings work | a mutation that refused to go red |
| #7 | two registry input guards | same: documented as defence with no measured consequence | a completeness pass measuring what the API does |
| #9 | eight macOS assertions | every one was a **negative**, and a nullptr class satisfies them all | cross-reading the same question in Swift |
| #11 | the autorelease-pool test | the **scale** was 100x too small to see the effect it was named for | asking directly whether it guarded the pool |
| #13 | (the guard that did not exist) | the obvious instrument, **RSS**, cannot see a leaked kernel handle | measuring both instruments against one mutation |

Read one at a time these look unrelated — a comment, a polarity, a loop count, a
counter. **They are the same defect five times.** A guard is a claim of the form
*"if X breaks, I go red"*, and that claim has preconditions. Each incident is
exactly one precondition failing, and because nothing enumerated them, each was
re-derived from scratch at a cost of a probe, a cross-reader, or a falsified doc.

The state space is combinatorial — instrument × polarity × scale × threshold ×
resource kind — so every new guard has been arriving as a fresh judgement, and
each one reinterprets the last. #13 is where that became undeniable: the fix for
#11 was **about to be copied verbatim into the exact same defect on the other
platform**, and the thing that stopped it was measuring two instruments against
one mutation rather than any rule. Worse, the review of #13 found precondition 4
broken *inside the change that was fixing precondition 2* — a threshold borrowed
from the test next door, against a signal half its size. The model is not being
learned; it is being rediscovered per encounter.

## Decision

**Before a guard is trusted, it answers all six of these. A guard that has not
answered them is a claim, not a check.**

> **1. Polarity — can it tell a failure from a question nobody asked?**
> A suite of negative assertions cannot. `nil`/`0`/`NO`/absent is what both a
> real "no" and an unwired call produce, so at least one assertion must be a
> **positive** that silence cannot satisfy.
>
> **2. Instrument — does the observable move when the guarded thing breaks?**
> Chosen by **resource kind**, not by habit. An address-space counter cannot see
> a kernel object; a handle count cannot see an autoreleased object. Prove it by
> making the resource leak on purpose and watching the number move.
>
> **3. Scale — is the effect bigger than the instrument's noise, at the size
> used?** Running the right code proves nothing if the effect is inside the noise
> at that iteration count. A precise instrument buys scale back; a noisy one
> spends it.
>
> **4. Threshold — is it derived, or borrowed?** Derived from the **measured**
> signal, the **measured** noise, and the **measured** worst case — each named
> beside the test. Never inherited from a neighbouring test, never a round
> number chosen after the fact, and never raised to clear a red build.
>
> **5. Mutation — has it been watched going red?** Break the thing it guards, see
> the failure, restore, see the green. A green from a guard nobody has seen fail
> is not evidence.
>
> **6. Stated reason — does the text beside it match what the mutation
> demonstrated?** A guard whose comment claims a consequence the mutation did not
> produce is worse than a silent one: it is a false record that the next reader
> builds on.

These are **preconditions, not a ranking** — one failing is enough, which is why
five incidents produced five different-looking symptoms.

### The five incidents fall out of it

- **#6, #7 → 6.** The guards were correct; the reasons beside them asserted
  measured facts that were never measured. Both were found by 5 (a mutation that
  would not go red), which is the pairing to expect: 6 usually fails silently
  until 5 is run.
- **#9 → 1.** Every macOS assertion was a negative, so the suite could not
  distinguish a loaded framework from an unloaded one and would have stayed green
  had the load gone missing. The fix was the first positive assertion.
- **#11 → 3.** 500 iterations against ~209 bytes/call is ~104 KB, inside RSS
  noise. Correct code, correct instrument, wrong scale.
- **#13 → 2**, with **4** broken inside the same change. RSS cannot see a leaked
  `HKEY`; and the positive control's bound was borrowed from its neighbour
  (1,000) against a signal of 500, so it could not fail.

### It resolves cases nobody has decided yet

A guard on a future subprocess, a file descriptor, a COM reference, a timing
budget: each has a *different* instrument (2) and therefore a different noise
floor (3) and threshold (4), but the six questions are the same and the answers
are all measurable. **No new resource needs a new decision; it needs the six
asked.** That is the test of whether this record derives rather than lists — and
it is why the count is preconditions rather than a checklist of past bugs.

## Consequences

Currently-true statements. Flip them if the decision flips.

- **`theflow.md` Step 4 carries the FFI-lifetime row** naming the instrument per
  resource kind, and Step 5's second unconditional trigger (FFI memory and object
  ownership) is the surface where all six are mandatory rather than advisory.
- **A threshold's derivation is written beside it, in the test.** Not in a commit
  message and not in an issue — both are read once. `handle_lifetime_test.dart`
  and `ns_workspace_integration_test.dart` both do this now.
- **Question 4 has a corollary that cost a review round:** *why* a threshold
  exists and *how big* it is are different questions, and one measurement cannot
  answer both. A concurrent suite being able to move a counter by hundreds is why
  the assertion is a ceiling rather than an equality; only the measured 2–3 may
  set the ceiling's size.
- **This record does not lower the bar for the success half.** Whether a browser
  actually opens is still manual, once per backend, and still a **known gap, not
  a covered case** (`theflow.md` Step 4). The six questions make a guard
  trustworthy; they do not make an unautomatable proof automatable.
- **A guard that cannot answer 5 is not thereby forbidden** — it is labelled. The
  launch path holds no kernel object of its own, so there is no release to delete
  and no mutation to run; the honest outcome was a measurement recorded with its
  validity condition and **no test**, rather than a test that cannot fail. Same
  for `shell_execute_integration_test.dart`'s non-ASCII case, which says in its
  own comment that it is crash detection and not a marshalling proof.

### Evidence

Tests this record reproduces — each already conforms, which is what makes them
evidence rather than work:

| Question | Test |
|---|---|
| 1 (polarity) | `test/macos/ns_workspace_integration_test.dart`, *"finds the application registered for a common scheme"* — the positive that #9 added |
| 1 (polarity) | `tool/compile_exe_guard.dart` — the consumer must answer `true`, not merely resolve a backend |
| 2 (instrument) | `test/windows/handle_lifetime_test.dart`, *"the counter can actually see a leaked handle"* |
| 3 (scale) | `ns_workspace_integration_test.dart`, *"repeated real calls do not accumulate native memory"* — 50,000 iterations, derived from the table beside it |
| 4 (threshold) | both memory guards — each states signal, noise and worst case in-file |
| 6 (stated reason) | `test/windows/scheme_registry_test.dart`, *"answers false rather than throwing for a malformed scheme"* — which says outright that it does not cover the separator guard |
| 6 (stated reason) | `test/windows/shell_execute_integration_test.dart`, *"survives a non-ASCII target"* — labelled deliberately weak after its original claim was falsified |

Contradicted tests: none. Every guard in the suite either conforms or says in its
own text which question it fails to answer, which is question 6 doing its job.

### What this does not cover

- **Whether a guard should exist at all.** That is enumeration risk and the
  Step 5 trigger list, not this record. These six apply once you have decided to
  write one.
- **Non-guard tests.** A pure-logic table test over `checkUrlShape` has no
  instrument and no threshold; questions 2, 3 and 4 are N/A and saying so is the
  conformance.
- **Performance measurement**, which turned out to need its own preconditions —
  AOT rather than JIT, interleaved rather than sequential blocks, cold rather
  than amortised. Those are recorded as Step 4 traps and `lessons.md` #12 rather
  than promoted here, because they answer *"is this number real"* and not *"does
  this guard hold"*. If a third performance incident lands, they earn their own
  record.
