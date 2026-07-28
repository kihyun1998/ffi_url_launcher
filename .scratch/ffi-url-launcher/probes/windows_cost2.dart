// Probe 2 — the questions probe 1 did not ask.
//
// Probe 1 measured steady-state throughput of the registry lookup and answered
// "is there a leak". Neither is the number a consumer feels, and neither looks
// for a structural improvement. This one covers:
//
//   cold        the FIRST call, including DynamicLibrary.open and every
//               lookupFunction. A CLI opens one URL and exits, so this — not the
//               amortised cost — is what a user waits for.
//   reggetvalue RegGetValueW collapses open+query+close into ONE call, and holds
//               no handle for us to leak. Correctness cross-check, then speed.
//   floor       how much of the per-call cost is FFI overhead we could never
//               remove, so an "improvement" can be judged against a real floor.
//   api         the public path (canLaunchUrlSync) against the bare seam — what
//               the shape check and platform dispatch add.
//   launch-mem  accumulation on the LAUNCH path. Probe 1 only exercised the
//               registry path; the two arenas are different code.
//
// Every launch input is `missingPath`, measured UI-free (returns 2, no window).

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ffi_url_launcher/ffi_url_launcher.dart' as api;
import 'package:ffi_url_launcher/src/backends/windows/scheme_registry.dart';
import 'package:ffi_url_launcher/src/backends/windows/shell_execute.dart';
import 'package:ffi_url_launcher/src/backends/windows/system32.dart';
import 'package:ffi_url_launcher/src/url_safety.dart';

const String missingPath = r'C:\zzz-ffi-url-launcher-does-not-exist\nope.zzzq';

void main(List<String> args) {
  final mode = args.isEmpty ? 'cold' : args.first;
  switch (mode) {
    case 'cold':
      _cold();
    case 'reggetvalue':
      _regGetValue();
    case 'floor':
      _floor();
    case 'api':
      _api();
    case 'launch-mem':
      _launchMem();
    default:
      stderr.writeln('unknown mode: $mode');
      exit(2);
  }
}

// ---------------------------------------------------------------------------
// Cold cost — the only latency number a CLI consumer actually experiences
// ---------------------------------------------------------------------------

void _cold() {
  // Nothing has touched advapi32 yet. This first call pays for
  // DynamicLibrary.open plus three lookupFunction resolutions, on top of the
  // three registry syscalls.
  final sw = Stopwatch()..start();
  isSchemeRegistered('https');
  final first = sw.elapsedMicroseconds;

  sw.reset();
  isSchemeRegistered('https');
  final second = sw.elapsedMicroseconds;

  sw.reset();
  for (var i = 0; i < 100; i++) {
    isSchemeRegistered('https');
  }
  final warmAvg = sw.elapsedMicroseconds / 100;

  // Same question for the launch path's library (shell32), which is a separate
  // DLL and a separate lazy final.
  sw.reset();
  shellExecuteOpen(missingPath);
  final firstLaunch = sw.elapsedMicroseconds;

  print('registry  first call: ${first}us');
  print('registry second call: ${second}us');
  print('registry  warm (x100 avg): ${warmAvg.toStringAsFixed(1)}us');
  print('launch    first call: ${firstLaunch}us');
  print('cold penalty (registry): ${first - second}us');
}

// ---------------------------------------------------------------------------
// RegGetValueW — three syscalls collapsed into one, and no handle to leak
// ---------------------------------------------------------------------------

/// Whether `HKCR\<scheme>` carries `URL Protocol`, asked with a single
/// `RegGetValueW` instead of open + query + close.
///
/// `RegGetValueW` takes the subkey **and** the value name, opening and closing
/// the subkey internally. Two consequences worth separating: it is one
/// transition instead of three, and **there is no `HKEY` in our hands at all**,
/// so the handle-lifetime hazard probe 1 measured cannot exist on this path.
bool _schemeRegisteredViaGetValue(String scheme) {
  if (scheme.isEmpty) return false;
  if (scheme.contains(r'\') || scheme.contains('/')) return false;

  return using((arena) {
    return _regGetValueW(
          Pointer.fromAddress(-2147483648),
          scheme.toNativeUtf16(allocator: arena),
          'URL Protocol'.toNativeUtf16(allocator: arena),
          _rrfRtAny,
          nullptr,
          nullptr,
          nullptr,
        ) ==
        0;
  });
}

void _regGetValue() {
  // Correctness first, and against every input the existing test asserts. A
  // faster call that answers differently is not an improvement, and speed is
  // not worth measuring until the answers match.
  const inputs = [
    'https',
    'http',
    'file',
    'HTTPS',
    'zzznotreal',
    'zzz-ffi-url-launcher-absent',
    '',
    '..',
    r'https\shell\open\command',
    'mailto',
    'ms-settings',
  ];

  print('correctness cross-check (open+query+close  vs  RegGetValueW)');
  var disagreements = 0;
  for (final scheme in inputs) {
    final current = isSchemeRegistered(scheme);
    final candidate = _schemeRegisteredViaGetValue(scheme);
    final mark = current == candidate ? '  ' : '<-- DISAGREES';
    if (current != candidate) disagreements++;
    print(
      '  ${'"$scheme"'.padRight(30)} current=$current '
      'candidate=$candidate $mark',
    );
  }
  print('disagreements: $disagreements');
  print('');

  if (disagreements > 0) {
    print('speed not measured: the answers differ, so there is nothing to buy');
    return;
  }

  // **Sequential A-then-B blocks could not resolve this.** Eight runs of that
  // shape gave +25%, +3%, -25%, -63%, +11%, -18%, -2%, -20% — the registry is a
  // shared OS resource with its own caching and other processes hitting it, so
  // consecutive blocks measure drift, not code. Interleaving A/B/A/B and taking
  // a median per variant is what makes the two see the same conditions.
  _abCompare(
    label: 'present  "https"',
    a: () => isSchemeRegistered('https'),
    b: () => _schemeRegisteredViaGetValue('https'),
  );
  _abCompare(
    label: 'absent   "zzznotreal"',
    a: () => isSchemeRegistered('zzznotreal'),
    b: () => _schemeRegisteredViaGetValue('zzznotreal'),
  );

  // And the cold number, which is the one a CLI pays. Measured in a child
  // process below; here just confirm the handle count stays flat with no
  // RegCloseKey of our own anywhere in the path.
  final before = _handleCount();
  for (var i = 0; i < 20000; i++) {
    _schemeRegisteredViaGetValue('https');
  }
  print('');
  print('handles over 20000 RegGetValueW calls: ${_handleCount() - before}');
}

/// Times [a] and [b] in alternating blocks and reports the median of each,
/// plus the spread — so a difference is only claimed when it clears the spread.
///
/// The spread is the honest part. Reporting a single ratio off one A-then-B pair
/// here produced swings from +25% to -63% on identical code.
void _abCompare({
  required String label,
  required bool Function() a,
  required bool Function() b,
}) {
  const blocks = 21;
  const perBlock = 3000;

  double timeBlock(bool Function() body) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < perBlock; i++) {
      body();
    }
    sw.stop();
    return sw.elapsedMicroseconds / perBlock;
  }

  // Warm both before either is timed.
  for (var i = 0; i < perBlock; i++) {
    a();
    b();
  }

  final aTimes = <double>[];
  final bTimes = <double>[];
  for (var block = 0; block < blocks; block++) {
    // Alternate which variant goes first, so neither systematically inherits
    // the other's cache state.
    if (block.isEven) {
      aTimes.add(timeBlock(a));
      bTimes.add(timeBlock(b));
    } else {
      bTimes.add(timeBlock(b));
      aTimes.add(timeBlock(a));
    }
  }

  aTimes.sort();
  bTimes.sort();
  final aMed = aTimes[aTimes.length ~/ 2];
  final bMed = bTimes[bTimes.length ~/ 2];

  String spread(List<double> t) =>
      '${t.first.toStringAsFixed(1)}-${t.last.toStringAsFixed(1)}';

  print('$label   ($blocks interleaved blocks of $perBlock)');
  print(
    '  open+query+close  median ${aMed.toStringAsFixed(2)}us  '
    '(spread ${spread(aTimes)})',
  );
  print(
    '  RegGetValueW      median ${bMed.toStringAsFixed(2)}us  '
    '(spread ${spread(bTimes)})',
  );
  final delta = 100 * (aMed - bMed) / aMed;
  print('  median difference: ${delta.toStringAsFixed(1)}%');
  print('');
}

// ---------------------------------------------------------------------------
// The floor — what fraction of the cost is ours to improve at all
// ---------------------------------------------------------------------------

void _floor() {
  const iterations = 200000;
  double timeUs(String label, void Function() body) {
    for (var i = 0; i < iterations ~/ 10; i++) {
      body();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body();
    }
    sw.stop();
    final us = sw.elapsedMicroseconds / iterations;
    print('${label.padRight(46)} ${us.toStringAsFixed(3)}us');
    return us;
  }

  print('cost floor, $iterations iterations each');
  print('');
  final ffiCall = timeUs('bare FFI call (GetCurrentProcess)', () {
    _getCurrentProcess();
  });
  final arena = timeUs('using((arena) {}) with nothing in it', () {
    using((arena) => 0);
  });
  final marshal = timeUs('arena + marshal one scheme string', () {
    using((a) => 'https'.toNativeUtf16(allocator: a));
  });
  print('');
  print('FFI transition:      ${ffiCall.toStringAsFixed(3)}us');
  print('arena setup/teardown: ${arena.toStringAsFixed(3)}us');
  print('one UTF-16 marshal:  ${(marshal - arena).toStringAsFixed(3)}us');
  print('');
  print('a 3-syscall lookup therefore floors at roughly');
  print('  3 FFI transitions + arena + 3 marshals =');
  print(
    '  ${(3 * ffiCall + arena + 3 * (marshal - arena)).toStringAsFixed(2)}us '
    'of the ~17-20us measured — the rest is the registry itself',
  );
}

// ---------------------------------------------------------------------------
// The public path against the bare seam
// ---------------------------------------------------------------------------

void _api() {
  const iterations = 20000;
  double timeUs(String label, void Function() body) {
    for (var i = 0; i < iterations ~/ 10; i++) {
      body();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body();
    }
    sw.stop();
    final us = sw.elapsedMicroseconds / iterations;
    print('${label.padRight(52)} ${us.toStringAsFixed(2)}us');
    return us;
  }

  final parsed = Uri.parse('https://dart.dev/guides?a=1#x');

  print('the public path, $iterations iterations each');
  print('');
  timeUs('Uri.parse("https://dart.dev/guides?a=1#x")', () {
    Uri.parse('https://dart.dev/guides?a=1#x');
  });
  timeUs('checkUrlShape(parsed)  [shape check alone]', () {
    checkUrlShape(parsed);
  });
  timeUs('isSchemeRegistered("https")  [bare seam]', () {
    isSchemeRegistered('https');
  });
  timeUs('canLaunchUrlSync(parsed)  [full public path]', () {
    api.canLaunchUrlSync(parsed);
  });
  print('');
  // Does the top-level helper rebuild the launcher — and therefore re-resolve
  // the backend — on every call? That is a per-call allocation a consumer pays
  // for and cannot see.
  timeUs('UrlLauncher.forCurrentPlatform()  [construction only]', () {
    api.UrlLauncher.forCurrentPlatform();
  });
}

// ---------------------------------------------------------------------------
// Accumulation on the launch path, which probe 1 never exercised
// ---------------------------------------------------------------------------

void _launchMem() {
  // ~1ms per call, so far fewer iterations than the registry path allows.
  //
  // **Three passes, not one.** A single pass measured +852KB over 5000 calls —
  // 170 bytes each, close to the 209 bytes/call the macOS leak produced — and a
  // single pass cannot tell that apart from the shell populating a cache once.
  // Consecutive equal passes mean linear growth; a first pass alone means
  // nothing. This is the shape `test/macos/ns_workspace_integration_test.dart`
  // uses, and the reason it uses it.
  const warmup = 200;
  const perPass = 5000;
  const passes = 3;

  void exercise(int times) {
    for (var i = 0; i < times; i++) {
      final status = shellExecuteOpen(missingPath);
      if (status != 2) throw StateError('expected SE_ERR_FNF, got $status');
    }
  }

  exercise(warmup);

  print('launch path: $passes passes of $perPass calls, after $warmup warm-up');
  print('a leak shows as passes that stay equal; a cache shows as a decay');
  print('');
  print('pass    handles      RSS delta    bytes/call');
  for (var pass = 1; pass <= passes; pass++) {
    final h0 = _handleCount();
    final r0 = ProcessInfo.currentRss;
    exercise(perPass);
    final dh = _handleCount() - h0;
    final dr = ProcessInfo.currentRss - r0;
    print(
      '  $pass   ${(dh >= 0 ? '+$dh' : '$dh').padLeft(7)}   '
      '${'${dr >= 0 ? '+' : ''}${dr ~/ 1024}KB'.padLeft(9)}   '
      '${(dr / perPass).toStringAsFixed(0).padLeft(6)}',
    );
  }

  // The Dart heap is a confound the macOS test did not have to think about,
  // because that probe allocated no Dart objects per call either. Here
  // `shellExecuteOpen` builds no Dart garbage per call, so if RSS growth is
  // Dart-side it must be the GC's own growth rather than ours — separate the two
  // by asking for the same measurement with the native call removed entirely.
  print('');
  print('control: the same loop with no FFI call at all');
  final c0 = ProcessInfo.currentRss;
  var sink = 0;
  for (var i = 0; i < perPass; i++) {
    sink += missingPath.length;
  }
  final c1 = ProcessInfo.currentRss;
  print(
    '  RSS delta ${(c1 - c0) ~/ 1024}KB over $perPass no-op iterations '
    '(sink=$sink)',
  );
}

// ---------------------------------------------------------------------------

int _handleCount() => using((arena) {
  final count = arena<Uint32>();
  if (_getProcessHandleCount(_getCurrentProcess(), count) == 0) {
    throw StateError('GetProcessHandleCount failed');
  }
  return count.value;
});

const int _rrfRtAny = 0x0000ffff; // winreg.h  RRF_RT_ANY

final DynamicLibrary _kernel32 = loadSystem32('kernel32.dll');
final DynamicLibrary _advapi32 = loadSystem32('advapi32.dll');

final _getCurrentProcess = _kernel32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetCurrentProcess',
    );

final _getProcessHandleCount = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetProcessHandleCount');

// LSTATUS RegGetValueW(HKEY hkey, LPCWSTR lpSubKey, LPCWSTR lpValue,
//                      DWORD dwFlags, LPDWORD pdwType, PVOID pvData,
//                      LPDWORD pcbData);
final _regGetValueW = _advapi32
    .lookupFunction<
      Uint32 Function(
        Pointer<NativeType>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<NativeType>,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
        Pointer<Uint32>,
        Pointer<Void>,
        Pointer<Uint32>,
      )
    >('RegGetValueW');
