// Probe 3 — where the ~6ms first call actually goes, and whether a compiled
// consumer pays it.
//
// Probe 2 found the cold call costs 5.5-6.5ms against 25us warm: 240x, and for
// a CLI that opens one URL and exits it is the *entire* cost. Two questions
// follow, and they have different owners:
//
//   breakdown  which step costs it — Platform.environment, DynamicLibrary.open,
//              the three lookupFunctions, or the first registry syscall. Only
//              some of those are this package's to move.
//   oneshot    what a single cold call costs, for the AOT comparison. Run this
//              under `dart run` and again from a `dart compile exe` binary: the
//              JIT has to compile the FFI trampolines on first call and an AOT
//              build does not, so the 6ms may be an artifact of how it was
//              measured rather than something a consumer pays.
//
// **Nothing here imports the package at all**, and the DLL path is spelled out
// inline rather than through `loadSystem32`. That is deliberate: the breakdown
// has to time `Platform.environment` and `DynamicLibrary.open` as *separate*
// steps, and `loadSystem32` does both in one call. The inlined path is
// byte-identical to what that function builds, so this measures the same work
// the package does — just with a stopwatch between the halves.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

void main(List<String> args) {
  final mode = args.isEmpty ? 'breakdown' : args.first;
  switch (mode) {
    case 'breakdown':
      _breakdown();
    case 'oneshot':
      _oneshot();
    default:
      stderr.writeln('unknown mode: $mode');
      exit(2);
  }
}

/// Times each step of the first call separately, in the order the real code
/// performs them, in a process that has done none of them yet.
void _breakdown() {
  final sw = Stopwatch()..start();

  void step(String label) {
    print('${label.padRight(46)} ${sw.elapsedMicroseconds}us');
    sw.reset();
  }

  // 1. `loadSystem32` reads Platform.environment['SystemRoot']. Dart builds the
  //    whole environment map on first access, so this is a candidate cost that
  //    has nothing to do with FFI.
  final root = Platform.environment['SystemRoot'];
  step('Platform.environment[SystemRoot] (first)');

  final root2 = Platform.environment['SystemRoot'];
  step('Platform.environment[SystemRoot] (cached)');
  if (root != root2) throw StateError('unreachable');

  // 2. Opening the DLL. advapi32 is almost certainly already mapped into this
  //    process, so this should be near-free — worth confirming rather than
  //    assuming.
  final advapi32 = DynamicLibrary.open('$root${r'\System32\'}advapi32.dll');
  step('DynamicLibrary.open(advapi32.dll)');

  final shell32 = DynamicLibrary.open('$root${r'\System32\'}shell32.dll');
  step('DynamicLibrary.open(shell32.dll)');

  // 3. Resolving the three symbols the registry lookup needs. Each builds an
  //    FFI trampoline, which under the JIT must be compiled.
  final regOpen = advapi32
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
  step('lookupFunction(RegOpenKeyExW)');

  final regQuery = advapi32
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
  step('lookupFunction(RegQueryValueExW)');

  final regClose = advapi32
      .lookupFunction<
        Uint32 Function(Pointer<NativeType>),
        int Function(Pointer<NativeType>)
      >('RegCloseKey');
  step('lookupFunction(RegCloseKey)');

  final shellExec = shell32
      .lookupFunction<
        IntPtr Function(
          Pointer<NativeType>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Int32,
        ),
        int Function(
          Pointer<NativeType>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
        )
      >('ShellExecuteW');
  step('lookupFunction(ShellExecuteW)');

  // 4. The first actual registry round-trip through those trampolines.
  final answer = using((arena) {
    final key = arena<Pointer<NativeType>>();
    if (regOpen(
          Pointer.fromAddress(-2147483648),
          'https'.toNativeUtf16(allocator: arena),
          0,
          0x0001,
          key,
        ) !=
        0) {
      return false;
    }
    try {
      return regQuery(
            key.value,
            'URL Protocol'.toNativeUtf16(allocator: arena),
            nullptr,
            nullptr,
            nullptr,
            nullptr,
          ) ==
          0;
    } finally {
      regClose(key.value);
    }
  });
  step('first real registry round-trip (answer=$answer)');

  // 5. And the second, through trampolines that now exist.
  using((arena) {
    final key = arena<Pointer<NativeType>>();
    if (regOpen(
          Pointer.fromAddress(-2147483648),
          'https'.toNativeUtf16(allocator: arena),
          0,
          0x0001,
          key,
        ) ==
        0) {
      regClose(key.value);
    }
  });
  step('second registry round-trip');

  // The four resolved symbols are consumed here only so nothing above is an
  // unused local. **An earlier version wrote `if (shellExec == nullptr)`, which
  // is always false** — `lookupFunction` returns a Dart function, not a pointer,
  // so that guard compared unrelated types and asserted nothing. It changed no
  // timing (the lookups above were still performed and still measured), but it
  // is exactly the shape of dead check `lessons.md` #9 removed from `lib/`.
  final resolved = <Object>[regOpen, regQuery, regClose, shellExec];
  print('resolved ${resolved.length} symbols');
}

/// One cold lookup, start to finish, as a CLI would do it. The number to compare
/// between `dart run` and a `dart compile exe` binary.
void _oneshot() {
  final sw = Stopwatch()..start();
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  final advapi32 = DynamicLibrary.open('$root${r'\System32\'}advapi32.dll');
  final regOpen = advapi32
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
  final regQuery = advapi32
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
  final regClose = advapi32
      .lookupFunction<
        Uint32 Function(Pointer<NativeType>),
        int Function(Pointer<NativeType>)
      >('RegCloseKey');

  final answer = using((arena) {
    final key = arena<Pointer<NativeType>>();
    if (regOpen(
          Pointer.fromAddress(-2147483648),
          'https'.toNativeUtf16(allocator: arena),
          0,
          0x0001,
          key,
        ) !=
        0) {
      return false;
    }
    try {
      return regQuery(
            key.value,
            'URL Protocol'.toNativeUtf16(allocator: arena),
            nullptr,
            nullptr,
            nullptr,
            nullptr,
          ) ==
          0;
    } finally {
      regClose(key.value);
    }
  });
  sw.stop();
  print('cold one-shot lookup: ${sw.elapsedMicroseconds}us (answer=$answer)');
}
