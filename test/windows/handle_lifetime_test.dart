@TestOn('windows')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:ffi_url_launcher/src/backends/windows/scheme_registry.dart';
import 'package:ffi_url_launcher/src/backends/windows/system32.dart';
import 'package:test/test.dart';

// The registry lookup is the only place in this package that takes a **kernel
// object** into its own hands: `RegOpenKeyExW` hands back an `HKEY` that
// `RegCloseKey` must give back. This file is the guard on that, and the whole
// reason it exists as its own file is that **the macOS memory test's instrument
// cannot see this defect.**
//
// Measured on Windows 11 (26200), `RegCloseKey` deleted and nothing else
// changed, 100,000 lookups:
//
//   | instrument                   | shipped code        | RegCloseKey removed |
//   |------------------------------|---------------------|---------------------|
//   | GetProcessHandleCount        | 143 -> 143     (+0) | 2143 -> 52143 (+50,000) |
//   | QuotaPagedPoolUsage          | +0 B (byte-exact)   | +802,816 B          |
//   | ProcessInfo.currentRss       | +204 KB / +92 KB    | +252 KB             |
//
// **RSS cannot tell the two apart** — +252 KB leaking against +204 KB clean, the
// same noise band. A leaked `HKEY` is a kernel object charged to the process's
// paged-pool quota; it never appears in the address space RSS measures. So
// porting `test/macos/ns_workspace_integration_test.dart`'s shape here would
// produce a test named for accumulation that sits green with 50,000 handles
// leaked behind it — which is precisely the disease issue #11 was opened for,
// reproduced by copying its cure.
//
// This is not the first time the counter has been used here: the #7 completeness
// pass already cleared the handle-leak concern with it and validated it by
// leaking 500 handles on purpose (`docs/agents/lessons.md` #7). What was missing
// was not the measurement but a **standing gate** — a one-time clearance does
// not fail when someone reintroduces the defect.
void main() {
  // Deliberately far below the 50,000 the macOS test needs. That test measures
  // RSS, which is noisy, so it needs scale to lift the signal out of the noise;
  // this one counts kernel handles, where the shipped code moves the counter by
  // **exactly zero** and the regression moves it by exactly one per call. A
  // precise instrument buys back the iterations — 20,000 lookups run in well
  // under a second and still leave a 20x margin over the ceiling below.
  const iterations = 20000;

  // **Why a ceiling and not equality**, and **where the ceiling's size comes
  // from** — two separate questions, and conflating them is how a threshold gets
  // inflated without anyone noticing.
  //
  // *Why not equality:* because the counter is **shared**. `dart test` runs
  // suites as isolates in ONE process (measured: identical pid across two
  // suites, one opening handles while the other dwelt), so this is the
  // scratch-key collision of `theflow.md` Step 7 with the name requirement
  // removed — merely existing is enough to collide. A probe that opened 200
  // files took the count 169 -> 369 before closing them, which is what says a
  // concurrent suite *can* move this by hundreds. So equality is flaky by
  // construction, however reproducible 143 -> 143 looks in a probe run alone.
  //
  // *Where the size comes from:* the **measured** noise, not that 200. Sampled
  // 17M times across a full concurrent run of this repo's real suite, the band
  // is **2-3 handles**. 100 clears that by 33x, and the regression it guards
  // produces **+20,000** here — one handle per successful open, linear and
  // unbounded — so it is caught 200x over, and so is any partial leak down to
  // one handle per 200 calls.
  //
  // An earlier draft used 1,000, justified by that 200-file probe. That was the
  // wrong instinct twice over: the probe is not a suite in this repo, so the
  // number was hypothetical, and at 1,000 the guard goes blind to any leak
  // slower than one handle per 20 calls. If a future suite really does churn
  // files enough to make this flaky, the fix is to make the measurement robust —
  // **not** to raise this number, which `theflow.md` Step 7 forbids outright.
  const maxHandleGrowth = 100;

  group('the registry lookup gives every HKEY back', () {
    test('repeated real lookups do not accumulate kernel handles', () {
      // Warm up first. The lazy `advapi32` load moves the counter once — that is
      // the *one* thing lessons #7 measured 40,000 real calls to move — and
      // counting a one-time cost as growth would either mask a real leak behind
      // headroom or fail for a reason that has nothing to do with the guard.
      _exercise(200);

      final before = _handleCount();
      _exercise(iterations);
      final growth = _handleCount() - before;

      expect(
        growth,
        lessThan(maxHandleGrowth),
        reason:
            'the process gained $growth kernel handles over $iterations '
            'registry lookups, past the $maxHandleGrowth ceiling. Measured, '
            'this is what a missing RegCloseKey looks like: one leaked HKEY per '
            'lookup that succeeds, forever. Note the shipped code moves this '
            'counter by exactly 0 — any growth in the thousands is the defect, '
            'not noise.',
      );
    });

    test('the counter can actually see a leaked handle', () {
      // **The instrument's own positive control, and the reason it is a test
      // rather than a comment.** The assertion above is a *negative* — "the
      // number did not move" — and this package has already been burned once by
      // a suite of negatives that could not tell a real answer from a question
      // nobody asked (`lessons.md` #9). A counter wired to nothing, or a
      // `GetProcessHandleCount` whose marshalling silently returned a constant,
      // would satisfy the test above perfectly.
      //
      // So: leak on purpose, watch the counter move, give the handles back,
      // watch it come home. Same shape as the #7 pass's 143 -> 643 -> 143.
      const leaks = 500;

      final before = _handleCount();
      final keys = <Pointer<NativeType>>[];
      final int withLeaks;
      final int afterClosing;
      try {
        for (var i = 0; i < leaks; i++) {
          final key = _openClassesRootSubkey('https');
          if (key != nullptr) keys.add(key);
        }
        withLeaks = _handleCount();
      } finally {
        // `finally`, because the handles are opened into a process **shared with
        // every other suite** (see the ceiling's derivation above). A throw
        // between the loop and the close — a failed `_handleCount`, an
        // `expect` moved up here later — would strand 500 kernel handles in a
        // process the rest of the run still has to work in. This file exists to
        // guard against exactly that shape; leaking it itself would be absurd.
        for (final key in keys) {
          _regCloseKey(key);
        }
      }
      afterClosing = _handleCount();

      expect(
        keys.length,
        leaks,
        reason: 'the probe could not open the keys it needs to leak',
      );
      expect(
        withLeaks - before,
        greaterThanOrEqualTo(leaks),
        reason:
            'holding $leaks open HKEYs moved GetProcessHandleCount by only '
            '${withLeaks - before}. If this is ~0 the counter is not measuring '
            'what the test above relies on, and that test is worthless.',
      );
      // **Bounded by the leak, not by the other test's ceiling.** An earlier
      // draft reused `maxHandleGrowth` here — which was 1,000 against a signal of
      // 500, so a `RegCloseKey` wired to nothing would have left exactly 500
      // behind and passed. The assertion could not fail for the reason its own
      // message gave, which is `lessons.md` #6's disease in the file documenting
      // it. The bound is now the same 2-3 measured noise the ceiling above is
      // derived from, with headroom: a no-op close is 500, i.e. 10x this.
      expect(
        afterClosing - before,
        lessThan(50),
        reason:
            'closing all $leaks handles left ${afterClosing - before} behind, '
            'so the counter does not come back down — it cannot tell a leak '
            'from ordinary churn, and the negative assertion above is resting '
            'on a counter that never returns to baseline',
      );
    });
  });
}

void _exercise(int times) {
  // A **registered** scheme on purpose. `RegOpenKeyExW` only hands back a handle
  // when it succeeds, so iterating an absent scheme would leak nothing even with
  // `RegCloseKey` gone — the mutation this file guards against would go
  // undetected. Measured: `https` is registered by the bundled browser on both
  // this machine and the CI runner (`lessons.md` #10 is why that is stated as a
  // property of Windows rather than of an installed app).
  //
  // Counted and asserted **once**, rather than an `expect` per iteration: 20,000
  // matcher invocations bury the reporter's output without adding cover, since a
  // single lookup answering `false` still fails the count. It also keeps the
  // positive assertion `lessons.md` #9 requires — if the library stopped loading
  // or the mask went wrong, every lookup would answer `false` and this trips.
  var registered = 0;
  for (var i = 0; i < times; i++) {
    if (isSchemeRegistered('https')) registered++;
  }
  expect(
    registered,
    times,
    reason:
        'only $registered of $times lookups of "https" answered true, so this '
        'run was not exercising a succeeding RegOpenKeyExW — and a lookup that '
        'fails hands back no handle, which is the one thing that would make the '
        'measurement below pass for the wrong reason',
  );
}

/// Opens `HKEY_CLASSES_ROOT\<scheme>` and returns the raw handle **without
/// closing it** — the caller owns it.
///
/// Exists only for the positive control above, which has to hold real handles
/// open to prove the counter sees them.
Pointer<NativeType> _openClassesRootSubkey(String scheme) => using((arena) {
  final key = arena<Pointer<NativeType>>();
  final opened = _regOpenKeyExW(
    Pointer.fromAddress(_hkeyClassesRoot),
    scheme.toNativeUtf16(allocator: arena),
    0,
    _keyQueryValue,
    key,
  );
  return opened == 0 ? key.value : nullptr;
});

int _handleCount() => using((arena) {
  final count = arena<Uint32>();
  if (_getProcessHandleCount(_getCurrentProcess(), count) == 0) {
    throw StateError('GetProcessHandleCount failed');
  }
  return count.value;
});

const int _hkeyClassesRoot = -2147483648;
const int _keyQueryValue = 0x0001;

// `kernel32` is bound **here and not in `lib/`** on purpose: counting handles is
// how this test measures, not something the package does. Putting it in
// `lib/src/backends/windows/` would add a shipped binding for a test's benefit.
final DynamicLibrary _kernel32 = loadSystem32('kernel32.dll');
final DynamicLibrary _advapi32 = loadSystem32('advapi32.dll');

final _getCurrentProcess = _kernel32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetCurrentProcess',
    );

// BOOL GetProcessHandleCount(HANDLE hProcess, PDWORD pdwHandleCount);
final _getProcessHandleCount = _kernel32.lookupFunction<
  Int32 Function(Pointer<Void>, Pointer<Uint32>),
  int Function(Pointer<Void>, Pointer<Uint32>)
>('GetProcessHandleCount');

final _regOpenKeyExW = _advapi32.lookupFunction<
  Uint32 Function(
    Pointer<NativeType>,
    Pointer<Utf16>,
    Uint32,
    Uint32,
    Pointer<Pointer<NativeType>>,
  ),
  int Function(
    Pointer<NativeType>,
    Pointer<Utf16>,
    int,
    int,
    Pointer<Pointer<NativeType>>,
  )
>('RegOpenKeyExW');

final _regCloseKey = _advapi32.lookupFunction<
  Uint32 Function(Pointer<NativeType>),
  int Function(Pointer<NativeType>)
>('RegCloseKey');
