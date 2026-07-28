import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'system32.dart';

/// Whether `HKEY_CLASSES_ROOT\<scheme>` carries a `URL Protocol` value.
///
/// That value is how Windows marks a key as a URL handler, and its *presence*
/// is the whole answer — the reference implementation reads it with three null
/// out-parameters for exactly that reason. Nothing is launched and nothing is
/// written, so this is safe to call anywhere, including CI.
///
/// Returns `false` for a scheme that is absent, for one whose key exists
/// without the marker, and for anything malformed. A registry read that fails
/// for any reason is "no", never an exception: a caller asking *can this be
/// opened* is not asking to be told the registry was busy.
bool isSchemeRegistered(String scheme) {
  // Both guards below exist because `RegOpenKeyExW` *succeeds* on these, and
  // what it hands back is not a key for the scheme. Measured on Windows 11
  // (26200), opening under `HKEY_CLASSES_ROOT`:
  //
  //   ""                          status=0  handle=0x-80000000  <- the hive itself
  //   "\"                         status=0  handle=0x232        <- a real handle, HKCR root
  //   "https\shell\open\command"  status=0  handle=0x232
  //   "https"                     status=0  handle=0x232        (control)

  // An empty subkey name returns the **predefined hive handle unchanged**, so
  // without this the code would `RegCloseKey` a predefined key. Microsoft
  // documents the consequence: "The predefined handles are not thread safe.
  // Closing a predefined handle in one thread affects any other threads that
  // are using the handle." Harmless while this package is single-threaded and
  // the handle is re-derived per call — recorded with that as the condition,
  // not as "it does not matter".
  if (scheme.isEmpty) return false;

  // A separator opens something real that is not the scheme's key — a bare `\`
  // reopens the HKCR root. The answer would come out `false` anyway (no
  // `URL Protocol` value lives at the root), so this is not a correctness fix;
  // it stops the lookup from silently meaning something else. `Uri.scheme`
  // cannot contain a separator, so this only guards a caller reaching the seam
  // directly.
  if (scheme.contains(r'\') || scheme.contains('/')) return false;

  return using((arena) {
    final key = arena<Pointer<NativeType>>();
    final opened = _regOpenKeyExW(
      Pointer.fromAddress(_hkeyClassesRoot),
      scheme.toNativeUtf16(allocator: arena),
      0,
      _keyQueryValue,
      key,
    );
    if (opened != _errorSuccess) return false;

    try {
      return _regQueryValueExW(
            key.value,
            _urlProtocolValue.toNativeUtf16(allocator: arena),
            nullptr,
            nullptr,
            nullptr,
            nullptr,
          ) ==
          _errorSuccess;
    } finally {
      _regCloseKey(key.value);
    }
  });
}

/// The value name Windows uses to mark a class key as a URL scheme handler.
const String _urlProtocolValue = 'URL Protocol';

/// `HKEY_CLASSES_ROOT`, as the address of its predefined handle.
///
/// The Win32 header defines these as `((HKEY)(ULONG_PTR)((LONG)0x80000000))`;
/// the `(LONG)` cast makes the value signed *before* it widens, so on 64-bit
/// the handle is `0xFFFFFFFF80000000`. This spelling is what the header
/// actually means and what `package:win32` generates
/// (`constants.g.dart:4609`: `HKEY(Pointer.fromAddress(-2147483648))`).
///
/// **The unsigned literal was measured to work too**, which is worth stating
/// because the in-family lesson says otherwise. On Windows 11 (26200),
/// `RegOpenKeyExW` returned `ERROR_SUCCESS` for all four predefined hives with
/// *both* spellings — see `docs/agents/lessons.md` #6. So this is the correct
/// spelling rather than the only working one, and the reason to keep it is that
/// it is what the header says; the clearance holds only for `RegOpenKeyExW` on
/// the version measured, which is why the unsigned form is still not used.
///
/// `HKEY_CLASSES_ROOT` is a **merged view** of `HKLM\Software\Classes` and
/// `HKCU\Software\Classes`, so reading it covers per-user installs — which is
/// most applications now. Reading `HKLM` alone would miss them.
const int _hkeyClassesRoot = -2147483648;

/// `KEY_QUERY_VALUE` (`winnt.h:21720`) — the least this needs, and what the
/// reference asks for. `KEY_READ` would also work and would ask for more.
const int _keyQueryValue = 0x0001;

const int _errorSuccess = 0;

// Lazily initialised, as every top-level `final` in Dart is, so this file being
// part of the package on macOS never opens a Windows DLL.
final DynamicLibrary _advapi32 = loadSystem32('advapi32.dll');

// LSTATUS RegOpenKeyExW(HKEY, LPCWSTR lpSubKey, DWORD ulOptions,
//                       REGSAM samDesired, PHKEY phkResult);
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

// LSTATUS RegQueryValueExW(HKEY, LPCWSTR lpValueName, LPDWORD lpReserved,
//                          LPDWORD lpType, LPBYTE lpData, LPDWORD lpcbData);
//
// Every out-parameter is null: this asks whether the value exists and never
// reads its bytes. That is what keeps `RegQueryValueExW`'s missing
// null-terminator guarantee from mattering here — a hazard that becomes real
// the moment anything starts reading a value, at which point the reader must
// change to `RegGetValueW`.
final _regQueryValueExW = _advapi32.lookupFunction<
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

final _regCloseKey = _advapi32.lookupFunction<
  Uint32 Function(Pointer<NativeType>),
  int Function(Pointer<NativeType>)
>('RegCloseKey');
