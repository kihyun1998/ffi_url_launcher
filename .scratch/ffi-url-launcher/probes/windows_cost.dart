// A probe, not a test. Measures what a repeated Windows call actually costs —
// native heap, kernel handles, paged pool, and wall time — and, crucially,
// measures the *instrument* against a deliberately broken variant, so a later
// test cannot be written to assert something it could not detect.
//
// Run one mode at a time:
//
//   dart run .scratch/ffi-url-launcher/probes/windows_cost.dart handles-clean
//   dart run .scratch/ffi-url-launcher/probes/windows_cost.dart handles-leak
//   dart run .scratch/ffi-url-launcher/probes/windows_cost.dart latency
//   dart run .scratch/ffi-url-launcher/probes/windows_cost.dart verb-cost
//
// Every launch-path input here is `missingPath`, measured UI-free (returns 2,
// SE_ERR_FNF, no window). Never give this probe the empty string or an
// unregistered scheme — both answer 42 and can put a window on screen.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ffi_url_launcher/src/backends/windows/scheme_registry.dart';
import 'package:ffi_url_launcher/src/backends/windows/shell_execute.dart';
import 'package:ffi_url_launcher/src/backends/windows/system32.dart';

const String missingPath = r'C:\zzz-ffi-url-launcher-does-not-exist\nope.zzzq';

void main(List<String> args) {
  final mode = args.isEmpty ? 'latency' : args.first;

  switch (mode) {
    case 'handles-clean':
      _handles(leak: false);
    case 'handles-leak':
      _handles(leak: true);
    case 'latency':
      _latency();
    case 'verb-cost':
      _verbCost();
    default:
      stderr.writeln('unknown mode: $mode');
      exit(2);
  }
}

// ---------------------------------------------------------------------------
// Handle / memory accumulation
// ---------------------------------------------------------------------------

/// Runs the registry lookup [iterations] times and reports every counter that
/// could plausibly show a leak — so we learn which ones actually move.
///
/// With [leak] set, the lookup is the same code with `RegCloseKey` removed.
/// That is the whole point: a counter that does not move here cannot be the
/// basis of a regression test.
void _handles({required bool leak}) {
  const warmup = 2000;
  const iterations = 50000;

  final read = leak ? _leakySchemeRead : isSchemeRegistered;

  void exercise(int times) {
    for (var i = 0; i < times; i++) {
      if (read('https') != true) throw StateError('https should be registered');
      if (read('zzznotreal') != false) throw StateError('should be absent');
    }
  }

  exercise(warmup);
  final before = _snapshot();
  exercise(iterations);
  final after = _snapshot();

  print('mode: ${leak ? 'RegCloseKey REMOVED' : 'clean'}');
  print('iterations: $iterations (x2 lookups each), after $warmup warm-up');
  print('');
  _report('handles', before.handles, after.handles, '');
  _report('paged pool', before.pagedPool, after.pagedPool, 'B');
  _report('non-paged pool', before.nonPagedPool, after.nonPagedPool, 'B');
  _report(
    'private usage',
    before.privateUsage ~/ 1024,
    after.privateUsage ~/ 1024,
    'KB',
  );
  _report(
    'working set',
    before.workingSet ~/ 1024,
    after.workingSet ~/ 1024,
    'KB',
  );
  _report('dart RSS', before.rss ~/ 1024, after.rss ~/ 1024, 'KB');
}

void _report(String name, int before, int after, String unit) {
  final delta = after - before;
  final sign = delta >= 0 ? '+' : '';
  print(
    '${name.padRight(16)} ${before.toString().padLeft(10)}$unit -> '
    '${after.toString().padLeft(10)}$unit   $sign$delta$unit',
  );
}

/// `isSchemeRegistered` with the `RegCloseKey` call deleted, and nothing else
/// changed. The regression a handle-lifetime test has to be able to see.
bool _leakySchemeRead(String scheme) {
  if (scheme.isEmpty) return false;
  if (scheme.contains(r'\') || scheme.contains('/')) return false;

  return using((arena) {
    final key = arena<Pointer<NativeType>>();
    final opened = _regOpenKeyExW(
      Pointer.fromAddress(-2147483648),
      scheme.toNativeUtf16(allocator: arena),
      0,
      0x0001,
      key,
    );
    if (opened != 0) return false;

    // No RegCloseKey. No try/finally. This is the bug, spelled out.
    return _regQueryValueExW(
          key.value,
          'URL Protocol'.toNativeUtf16(allocator: arena),
          nullptr,
          nullptr,
          nullptr,
          nullptr,
        ) ==
        0;
  });
}

// ---------------------------------------------------------------------------
// Latency
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
    print('${label.padRight(42)} ${us.toStringAsFixed(2)}us');
    return us;
  }

  print('per-call cost, $iterations iterations each (10% warm-up first)');
  print('');
  timeUs('isSchemeRegistered("https")  [present]', iterations, () {
    isSchemeRegistered('https');
  });
  timeUs('isSchemeRegistered("zzznotreal") [absent]', iterations, () {
    isSchemeRegistered('zzznotreal');
  });
  timeUs('shellTargetFor(https://dart.dev)', iterations, () {
    shellTargetFor(Uri.parse('https://dart.dev'));
  });
  // The launch path itself: a path that does not exist, measured UI-free.
  // Far fewer iterations — this one actually enters the shell.
  timeUs('shellExecuteOpen(missing path)  [SE_ERR_FNF]', 300, () {
    shellExecuteOpen(missingPath);
  });
}

// ---------------------------------------------------------------------------
// The cost of marshalling a constant string per call
// ---------------------------------------------------------------------------

/// Both hot paths encode a compile-time-constant wide string on every call:
/// `'open'` for the `ShellExecuteW` verb and `'URL Protocol'` for the registry
/// value name. This is the Windows shape of the macOS selector question (#12) —
/// so measure it rather than asserting it matters.
void _verbCost() {
  const iterations = 200000;

  final cached = 'URL Protocol'.toNativeUtf16();

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

  print('marshalling a constant, $iterations iterations each');
  print('');
  final perCall = timeUs('arena-allocate "URL Protocol" per call', () {
    using((arena) => 'URL Protocol'.toNativeUtf16(allocator: arena));
  });
  // The comparison **is** the measurement here — reading a pointer allocated
  // once is what the cached variant would do per call — so it is spelled as a
  // read into a sink rather than as `if (cached == nullptr) throw`. That earlier
  // spelling was always false and read as a guard, which is the dead-check shape
  // `lessons.md` #9 had removed from `lib/`; it belongs in a probe no more than
  // it belonged there.
  var sink = 0;
  final reuse = timeUs('read a pointer allocated once', () {
    sink += cached.address;
  });
  if (sink == 0) throw StateError('the cached pointer was null');
  print('');
  print('difference: ${(perCall - reuse).toStringAsFixed(3)}us per constant');
  print('the registry lookup marshals 2 constants+scheme, launch marshals 2');

  calloc.free(cached);
}

// ---------------------------------------------------------------------------
// Counters
// ---------------------------------------------------------------------------

class _Snapshot {
  const _Snapshot({
    required this.handles,
    required this.pagedPool,
    required this.nonPagedPool,
    required this.privateUsage,
    required this.workingSet,
    required this.rss,
  });

  final int handles;
  final int pagedPool;
  final int nonPagedPool;
  final int privateUsage;
  final int workingSet;
  final int rss;
}

_Snapshot _snapshot() {
  return using((arena) {
    final count = arena<Uint32>();
    if (_getProcessHandleCount(_getCurrentProcess(), count) == 0) {
      throw StateError('GetProcessHandleCount failed');
    }

    // PROCESS_MEMORY_COUNTERS_EX: DWORD cb, DWORD PageFaultCount, then nine
    // SIZE_T fields. 4 + 4 + 9*8 = 80 bytes on 64-bit.
    const size = 80;
    final counters = arena<Uint8>(size);
    counters.cast<Uint32>().value = size;
    if (_getProcessMemoryInfo(_getCurrentProcess(), counters, size) == 0) {
      throw StateError('GetProcessMemoryInfo failed');
    }
    // Field i (0-based among the SIZE_T block) sits at byte 8 + i*8.
    int sizeT(int i) => (counters + (8 + i * 8)).cast<Uint64>().value;

    return _Snapshot(
      handles: count.value,
      workingSet: sizeT(1), // WorkingSetSize
      pagedPool: sizeT(3), // QuotaPagedPoolUsage
      nonPagedPool: sizeT(5), // QuotaNonPagedPoolUsage
      privateUsage: sizeT(8), // PrivateUsage
      rss: ProcessInfo.currentRss,
    );
  });
}

final DynamicLibrary _kernel32 = loadSystem32('kernel32.dll');
final DynamicLibrary _psapi = loadSystem32('psapi.dll');
final DynamicLibrary _advapi32 = loadSystem32('advapi32.dll');

final _getCurrentProcess = _kernel32
    .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetCurrentProcess',
    );

// BOOL GetProcessHandleCount(HANDLE, PDWORD);
final _getProcessHandleCount = _kernel32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint32>)
    >('GetProcessHandleCount');

// BOOL GetProcessMemoryInfo(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD cb);
final _getProcessMemoryInfo = _psapi
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)
    >('GetProcessMemoryInfo');

final _regOpenKeyExW = _advapi32
    .lookupFunction<
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

final _regQueryValueExW = _advapi32
    .lookupFunction<
      Uint32 Function(
        Pointer<NativeType>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint8>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<NativeType>,
        Pointer<Utf16>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint8>,
        Pointer<Uint32>,
      )
    >('RegQueryValueExW');
