@TestOn('mac-os')
library;

import 'dart:io';

import 'package:ffi_url_launcher/ffi_url_launcher.dart';
import 'package:ffi_url_launcher/src/backends/macos/macos_backend.dart';
import 'package:ffi_url_launcher/src/backends/macos/ns_workspace.dart';
import 'package:test/test.dart';

// These drive the real Objective-C runtime, AppKit, and `NSWorkspace` through
// the real FFI bindings. Faking this layer would prove nothing — the
// `objc_msgSend` marshalling *is* the dangerous part, and a green test against
// a fake would say only that the fake behaves as written.
//
// **The two operations have different CI hazards, and the split below is
// measured, not assumed.**
//
//   * `openURL:` *attempts* something, so it can put a window on screen. Only
//     one input is measured UI-free (see the launch group).
//   * `URLForApplicationToOpenURL:` only *looks up* — it starts nothing and
//     shows nothing, so it is safe against any input, including the very scheme
//     the launch path must not be given.
void main() {
  const backend = MacosUrlLauncherBackend();

  // Measured on macOS 14.5 (arm64), each call made on its own with the screen
  // watched:
  //
  //   openURL: file:///zzz-…-does-not-exist.zzzq   -> NO,  no window
  //   openURL: zzznotreal-ffiurllauncher://x       -> NO,  MODAL DIALOG
  //   URLForApplicationToOpenURL: https://dart.dev -> /Applications/Google Chrome.app
  //   URLForApplicationToOpenURL: <unregistered>   -> nil, no window
  const unregisteredScheme = 'zzznotreal-ffiurllauncher://x';
  const missingFile = 'file:///zzz-ffi-url-launcher-does-not-exist.zzzq';

  group('the real NSWorkspace launch path', () {
    test('loads AppKit, marshals a URL string, and answers a clean NO', () {
      // If libobjc/AppKit failed to load, a selector name were wrong, or an
      // objc_msgSend signature were mismatched, this would not come back as a
      // clean notOpened — it would crash or return garbage.
      //
      // Only the missing *file* is used. See the skipped test below for why the
      // unregistered scheme is not, and `docs/agents/lessons.md` #9 for what
      // makes a passing assertion here worth doubting at all.
      expect(workspaceOpenUrl(missingFile), MacOpenOutcome.notOpened);
    });

    test('survives a non-ASCII URL without crashing', () {
      // Crash detection, and labelled as such: a bad UTF-8→NSString conversion
      // that walked off the buffer would not return cleanly. It still resolves
      // to a missing file, so the answer is notOpened with no UI.
      expect(
        workspaceOpenUrl('file:///zzz-없는파일-ффи.zzzq'),
        MacOpenOutcome.notOpened,
      );
    });

    test('answers false — honestly — when nothing can open the URL', () {
      // The contrast with Windows: there this shape comes back as `true`,
      // because `ShellExecuteW` reports that the shell accepted the request and
      // not what became of it. Here `false` means what it says.
      expect(backend.launch(Uri.parse(missingFile)), isFalse);
    });

    test(
      'an unregistered scheme answers NO — and raises a modal dialog',
      // Recorded, not run. Measured on macOS 14.5 with the screen watched:
      // `openURL:` on a scheme nothing handles returns NO **and** puts up the
      // "there is no application set to open the URL" panel, with App Store /
      // Choose Application / Cancel buttons. A CI run would park on it forever.
      //
      // This is the same trap as the Windows app picker (`lessons.md` #4), and
      // it makes the CI-safe input the same on both platforms: a target that
      // does not exist, never a scheme nothing is registered for. An earlier
      // version of this file asserted this input live — the measurement that
      // caught it is `lessons.md` #9.
      //
      // Note this is the *launch* path only. Asking `canOpen` about the same
      // scheme is a lookup, shows nothing, and is asserted live below.
      () => expect(
        workspaceOpenUrl(unregisteredScheme),
        MacOpenOutcome.notOpened,
      ),
      skip:
          'raises the "no application set to open the URL" panel; '
          'measured by hand',
    );
  });

  group('the real NSWorkspace handler lookup', () {
    test('finds the application registered for a common scheme', () {
      // The positive arm, and the one that proves the lookup is wired to
      // something real rather than answering `false` from a nullptr class —
      // which is exactly how the first attempt at this failed silently
      // (`docs/agents/lessons.md` #9). Cross-read from Swift on this machine:
      // `NSWorkspace.shared.urlForApplication(toOpen:)` returns Google Chrome
      // for https and Mail for mailto, matching what this asserts.
      //
      // That the lookup **opens nothing** — the guarantee that makes asking
      // first worth doing — is a manual observation, not an assertion: these
      // two URLs would both launch a real application if this were attempting
      // the open, and none appears. There is no automated substitute, so it is
      // recorded here rather than dressed up as a test that cannot fail.
      expect(workspaceCanOpenUrl('https://dart.dev'), isTrue);
      expect(workspaceCanOpenUrl('mailto:someone@example.test'), isTrue);
    });

    test('answers false for a scheme nothing is registered to handle', () {
      // Safe to assert live, unlike the launch path above: a lookup starts
      // nothing and shows nothing.
      expect(workspaceCanOpenUrl(unregisteredScheme), isFalse);
    });

    test('answers through the backend the same way', () {
      expect(backend.canOpen(Uri.parse('https://dart.dev')), isTrue);
      expect(backend.canOpen(Uri.parse(unregisteredScheme)), isFalse);
    });

    test('answers the same through the public API', () {
      // Criterion 1 names `canLaunchUrlSync`, not the seam beneath it. Asserting
      // it here is what proves the whole public path — shape check, platform
      // resolution, backend, FFI — is wired on this machine, rather than only
      // the layer a unit test can reach.
      expect(canLaunchUrlSync(Uri.parse('https://dart.dev')), isTrue);
      expect(canLaunchUrlSync(Uri.parse(unregisteredScheme)), isFalse);
    });
  });

  group('autorelease discipline', () {
    // Each call pushes and pops its own pool, so the autoreleased
    // NSString/NSURL — and, for the lookup, the returned NSURL, which is
    // autoreleased and must not be released by us — are drained at call end
    // rather than living to process exit.
    //
    // **This used to be a 500-iteration crash check named as if it measured
    // accumulation.** It did not: disabling `inAutoreleasePool` entirely left
    // it green. Measured on macOS 14.5 (arm64) with `ProcessInfo.currentRss`,
    // two passes to separate one-time cost from steady state:
    //
    //   | 50,000 calls | pass 1     | pass 2     |
    //   |--------------|------------|------------|
    //   | with pool    |     +16 KB |      +0 KB |
    //   | no pool      | +10,208 KB | +10,208 KB |
    //
    // ~209 bytes per call, growing linearly and forever. At 500 iterations that
    // is ~104 KB — inside the noise, which is why the old test could not see
    // it. See issue #11 and `docs/agents/lessons.md` #11.
    const iterations = 50000;

    // Derived from the table above, not tuned to pass: the regression this
    // guards produces ~10 MB here, and the correct code produced 0. Anything
    // between is noise headroom. Raising this to quiet a red build would be
    // removing the guard — `docs/agents/theflow.md`, Step 7.
    const maxGrowthKb = 4000;

    int rssKb() => ProcessInfo.currentRss ~/ 1024;

    void exercise(int times) {
      for (var i = 0; i < times; i++) {
        expect(workspaceOpenUrl(missingFile), MacOpenOutcome.notOpened);
        // Driven with `https:`, not an unregistered scheme: the object whose
        // lifetime this is about is the `NSURL` that
        // `URLForApplicationToOpenURL:` *returns*, and an unregistered scheme
        // returns `nil` — iterations of which construct nothing and would prove
        // nothing about ownership.
        expect(workspaceCanOpenUrl('https://dart.dev'), isTrue);
      }
    }

    test('repeated real calls do not accumulate native memory', () {
      // A warm-up pass first. Lazy library loads, class lookups and
      // LaunchServices populating its own caches all cost memory once, and
      // counting that as growth would either mask a real leak behind headroom
      // or fail for the wrong reason.
      exercise(2000);

      final before = rssKb();
      exercise(iterations);
      final growthKb = rssKb() - before;

      expect(
        growthKb,
        lessThan(maxGrowthKb),
        reason:
            'resident memory grew ${growthKb}KB over $iterations calls, past '
            'the ${maxGrowthKb}KB ceiling. Measured, this is what a missing '
            'objc_autoreleasePoolPop looks like: the autoreleased NSString / '
            'NSURL from every call surviving to process exit, at roughly 209 '
            'bytes a call.',
      );
    });
  });
}
