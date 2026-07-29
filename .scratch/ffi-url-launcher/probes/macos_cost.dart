// A probe, not a test. Measures what `URLForApplicationToOpenURL:` — the macOS
// `canLaunchUrl` path — actually costs, against the claim that a LaunchServices
// lookup is "expensive".
//
// Compile it. `dart run` measured the Windows cold path 30x too slow
// (`docs/agents/lessons.md`), and the cold path is exactly what a claim about
// LaunchServices setup lives or dies on:
//
//   dart compile exe .scratch/ffi-url-launcher/probes/macos_cost.dart -o /tmp/macos_cost
//   /tmp/macos_cost cold
//   /tmp/macos_cost latency
//   /tmp/macos_cost vary
//
// `cold` must be run in a fresh process to mean anything — it is one-shot by
// construction.
//
// **No mode here calls `openURL:`, and none may be added.** Two were, and they
// put roughly 1,900 "no application can open this URL" dialogs on the
// maintainer's screen. They were guarded by `outcome == notOpened`, which is
// not an observation of whether UI appeared — `NSWorkspace` answers `NO` and
// `CoreServicesUIAgent` shows the dialog, independently. A guard that cannot
// see the thing it exists to prevent is ADR-0002's subject exactly, and this
// probe is where it happened. Anything that measures the launch path needs an
// instrument that watches the screen, not the return value.
//
// This probe only ever *looks up*.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ffi_url_launcher/src/backends/macos/ns_workspace.dart';
import 'package:ffi_url_launcher/src/backends/macos/objc.dart';

void main(List<String> args) {
  final mode = args.isEmpty ? 'latency' : args.first;

  switch (mode) {
    case 'cold':
      _cold(args.length > 1 ? args[1] : 'https://dart.dev');
    case 'latency':
      _latency();
    case 'vary':
      _vary();
    default:
      stderr.writeln('unknown mode: $mode');
      exit(2);
  }
}

// ---------------------------------------------------------------------------
// Cold path — one shot, fresh process
// ---------------------------------------------------------------------------

/// Every first-of-its-kind cost, in the order a real consumer pays them, each
/// measured exactly once. Any second call in this mode would be warm and would
/// quietly turn a cold-path number into a warm one.
void _cold(String first) {
  final total = Stopwatch()..start();

  final t0 = Stopwatch()..start();
  final workspaceCls = nsWorkspaceClass; // opens AppKit, resolves the class
  t0.stop();

  final t1 = Stopwatch()..start();
  final stringCls = nsStringClass;
  final urlCls = nsUrlClass;
  t1.stop();

  final t2 = Stopwatch()..start();
  final selShared = selSharedWorkspace;
  final selLookup = selUrlForApplicationToOpenUrl;
  final selStr = selStringWithUtf8String;
  final selUrl = selUrlWithString;
  t2.stop();

  final t3 = Stopwatch()..start();
  final workspace = msgSendReturningId(workspaceCls, selShared);
  t3.stop();

  // Both sub-timers are stopped *before* anything prints. The first cut of this
  // probe left `t4` running through `t5` and through four `print`s, so it
  // reported 1699us for work that costs ~67us — the instrument outweighing the
  // thing measured, which is the failure ADR-0002 is about.
  final t4 = Stopwatch()..start();
  final t5 = Stopwatch();
  late bool found;
  inAutoreleasePool(() {
    final nsUrl = using((arena) {
      final s = msgSendCStringReturningId(
        stringCls,
        selStr,
        first.toNativeUtf8(allocator: arena),
      );
      return msgSendIdReturningId(urlCls, selUrl, s);
    });
    t4.stop();
    // The lookup itself, cold: the first LaunchServices round-trip of the
    // process. This is the number the "expensive" claim is about.
    t5.start();
    final app = msgSendIdReturningId(workspace, selLookup, nsUrl);
    t5.stop();
    found = app != nullptr;
  });
  total.stop();

  print('cold, one shot each, fresh process. first URL: $first');
  print('');
  _line('AppKit open + NSWorkspace class', t0);
  _line('NSString + NSURL classes', t1);
  _line('4 selectors registered', t2);
  _line('[NSWorkspace sharedWorkspace]', t3);
  _line('NSString + NSURL for the URL', t4);
  _line('URLForApplicationToOpenURL: (1st ever)', t5);
  print('');
  _line('everything above', total);
  print('');
  print('handler found: $found');

  // A second and third lookup, still in the same process, to show how much of
  // the cold number was one-time LaunchServices setup rather than the lookup.
  final t6 = Stopwatch()..start();
  workspaceCanOpenUrl('https://dart.dev');
  t6.stop();
  final t7 = Stopwatch()..start();
  workspaceCanOpenUrl('https://dart.dev');
  t7.stop();
  final t8 = Stopwatch()..start();
  workspaceCanOpenUrl('mailto:nobody@example.com');
  t8.stop();
  final t9 = Stopwatch()..start();
  workspaceCanOpenUrl('zzznotreal://x');
  t9.stop();

  print('');
  _line('2nd lookup, same URL', t6);
  _line('3rd lookup, same URL', t7);
  _line('1st lookup, mailto:', t8);
  _line('1st lookup, unregistered scheme', t9);
}

void _line(String label, Stopwatch sw) {
  final us = sw.elapsedMicroseconds;
  print('${label.padRight(40)} ${us.toString().padLeft(8)}us');
}

// ---------------------------------------------------------------------------
// Warm per-call cost
// ---------------------------------------------------------------------------

void _latency() {
  const iterations = 20000;

  double timeUs(String label, int times, void Function() body) {
    for (var i = 0; i < times ~/ 10; i++) {
      body();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < times; i++) {
      body();
    }
    sw.stop();
    final us = sw.elapsedMicroseconds / times;
    print('${label.padRight(44)} ${us.toStringAsFixed(2)}us');
    return us;
  }

  print('warm per-call cost, $iterations iterations each (10% warm-up first)');
  print('');

  // Baseline 1: the FFI + arena + NSString/NSURL work the lookup does *around*
  // the LaunchServices call. Whatever the lookup costs above this is the part
  // LaunchServices is responsible for.
  final nsurl = timeUs('NSString+NSURL only (no lookup)', iterations, () {
    inAutoreleasePool(() {
      using((arena) {
        final s = msgSendCStringReturningId(
          nsStringClass,
          selStringWithUtf8String,
          'https://dart.dev'.toNativeUtf8(allocator: arena),
        );
        msgSendIdReturningId(nsUrlClass, selUrlWithString, s);
      });
    });
  });

  // Baseline 2: a bare objc_msgSend, to size the FFI transition itself.
  timeUs('[NSWorkspace sharedWorkspace] alone', iterations, () {
    msgSendReturningId(nsWorkspaceClass, selSharedWorkspace);
  });

  final https = timeUs('canOpen https://dart.dev', iterations, () {
    workspaceCanOpenUrl('https://dart.dev');
  });
  timeUs('canOpen mailto:', iterations, () {
    workspaceCanOpenUrl('mailto:nobody@example.com');
  });
  timeUs('canOpen file:///etc/hosts', iterations, () {
    workspaceCanOpenUrl('file:///etc/hosts');
  });
  final absent = timeUs('canOpen zzznotreal:// (unregistered)', iterations, () {
    workspaceCanOpenUrl('zzznotreal://x');
  });

  print('');
  print(
    'LaunchServices share, https: ${(https - nsurl).toStringAsFixed(2)}us '
    'of ${https.toStringAsFixed(2)}us',
  );
  print(
    'LaunchServices share, absent: ${(absent - nsurl).toStringAsFixed(2)}us '
    'of ${absent.toStringAsFixed(2)}us',
  );
}

// ---------------------------------------------------------------------------
// Is the warm number a cache? Ask a different URL every time.
// ---------------------------------------------------------------------------

/// The warm loop above asks the *same* URL 20,000 times. If LaunchServices
/// memoises per URL, that measures a cache hit and says nothing about what a
/// consumer's first lookup of a given URL costs. So: same URL vs. a distinct
/// URL per iteration, same host and same scheme, differing only in path.
void _vary() {
  const iterations = 5000;

  double timeUs(String label, void Function(int) body) {
    for (var i = 0; i < iterations ~/ 10; i++) {
      body(-i - 1);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body(i);
    }
    sw.stop();
    final us = sw.elapsedMicroseconds / iterations;
    print('${label.padRight(44)} ${us.toStringAsFixed(2)}us');
    return us;
  }

  print('same URL vs distinct URL per call, $iterations iterations each');
  print('');
  timeUs('same https URL every call', (_) {
    workspaceCanOpenUrl('https://dart.dev/a');
  });
  timeUs('distinct https path per call', (i) {
    workspaceCanOpenUrl('https://dart.dev/$i');
  });
  timeUs('distinct https host per call', (i) {
    workspaceCanOpenUrl('https://h$i.example.com/');
  });
  timeUs('distinct unregistered scheme per call', (i) {
    workspaceCanOpenUrl('zzznotreal$i://x');
  });
  timeUs('distinct file: path per call', (i) {
    workspaceCanOpenUrl('file:///tmp/zzz-no-such-$i.txt');
  });
}
