import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// What a `ShellExecuteW` return value means.
///
/// The decision lives here, as a pure function of an integer, so it can be
/// asserted against every documented code from any host. The FFI call site is
/// then decision-free plumbing.
enum ShellExecuteOutcome {
  /// The handler was started. **Not** "the URL opened" — no Win32 call reports
  /// that.
  launched,

  /// Nothing is registered to open this. An ordinary answer, not a fault.
  noHandler,

  /// The shell refused for some other reason.
  failed,
}

/// Classifies a raw `ShellExecuteW` return value.
///
/// `ShellExecuteW` returns an `HINSTANCE` for historical compatibility, and the
/// SDK header states the success predicate as `_Success_(return > 32)`
/// (`shellapi.h:103`). Every value at or below 32 is an error code — including
/// `SE_ERR_DLLNOTFOUND`, which is exactly 32, so a `>=` here would silently
/// convert a failure into a success.
ShellExecuteOutcome interpretShellExecuteStatus(int status) {
  if (status > 32) return ShellExecuteOutcome.launched;
  if (status == _seErrNoAssoc) return ShellExecuteOutcome.noHandler;
  return ShellExecuteOutcome.failed;
}

/// Describes a failing `ShellExecuteW` return value for a human.
///
/// Only the codes a caller can plausibly hit are named; the rest fall back to
/// the raw number rather than being hidden behind a vague sentence. The
/// reference implementation surfaces the bare integer, which is the subject of
/// flutter/flutter#138142 — "provide a better error message for
/// `SE_ERR_NOASSOC` (code 31)".
String describeShellExecuteStatus(int status) => switch (status) {
  _seErrNoAssoc => 'nothing is registered to open this URL',
  _seErrFileNotFound => 'the file was not found',
  _seErrPathNotFound => 'the path was not found',
  _seErrAccessDenied => 'access was denied',
  _seErrOutOfMemory => 'the system was out of memory',
  _seErrShare => 'a sharing violation occurred',
  _seErrAssocIncomplete => 'the file association is incomplete or invalid',
  _seErrDdeTimeout => 'the DDE transaction timed out',
  _seErrDdeFail => 'the DDE transaction failed',
  _seErrDdeBusy =>
    'the DDE transaction could not be completed; the system was busy',
  _seErrDllNotFound => 'the required library was not found',
  _ => 'ShellExecuteW returned $status',
};

/// The string `ShellExecuteW` should be handed for [url].
///
/// Every URL but one passes through as written. A **`file:`** URL does not:
/// `ShellExecuteW` decodes ASCII percent-escapes in one but leaves multi-byte
/// UTF-8 escapes alone, so `file:///C:/%ED%95%9C.txt` is looked up literally
/// and an existing file comes back as `SE_ERR_FNF`. `Uri.toString()` always
/// produces exactly that encoding, so the package would otherwise turn a
/// working input into a failing one — measured in `docs/agents/lessons.md` #5.
///
/// The reference implementation unescapes the whole URL string with
/// `UrlUnescapeA` and keeps the `file://` prefix. This converts to a native
/// path instead, which is the same fix done with a tool C++ did not have and is
/// better in two measured ways: a file genuinely named `a%20b.txt` survives
/// (unescaping the URL string turns it into `a b.txt`, opening the wrong file
/// or none), and an authority becomes a real UNC path rather than being left
/// as `file://server/share`.
///
/// Throws [UnsupportedError] for a `file:` URL carrying a query or fragment.
/// Such a URL is not addressing a file, and letting it through only buys the
/// caller a "file not found" that sends them looking in the wrong place.
String shellTargetFor(Uri url) =>
    url.scheme == 'file' ? url.toFilePath(windows: true) : url.toString();

/// Asks the shell to open [target] with its registered handler.
///
/// Returns the raw `ShellExecuteW` status; interpreting it is
/// [interpretShellExecuteStatus]'s job.
///
/// **Must run on the calling isolate's own thread.** `ShellExecuteW` depends on
/// the COM apartment that thread already has, so this may not be moved into a
/// spawned isolate.
int shellExecuteOpen(String target) {
  return using((arena) {
    return _shellExecuteW(
      nullptr,
      _verbOpen.toNativeUtf16(allocator: arena),
      target.toNativeUtf16(allocator: arena),
      nullptr,
      nullptr,
      _swShowNormal,
    );
  });
}

// Values read out of the Windows SDK headers on a real machine, with the file
// and line they came from. A constant you can recite is still a constant you
// have not checked — sibling `just_autostart` shipped the wrong predefined
// registry handle exactly that way (its lessons #7).
const int _seErrFileNotFound = 2; // shellapi.h:366  SE_ERR_FNF
const int _seErrPathNotFound = 3; // shellapi.h:367  SE_ERR_PNF
const int _seErrAccessDenied = 5; // shellapi.h:368  SE_ERR_ACCESSDENIED
const int _seErrOutOfMemory = 8; // shellapi.h:369  SE_ERR_OOM
const int _seErrShare = 26; // shellapi.h:375  SE_ERR_SHARE
const int _seErrAssocIncomplete = 27; // shellapi.h:376  SE_ERR_ASSOCINCOMPLETE
const int _seErrDdeTimeout = 28; // shellapi.h:377  SE_ERR_DDETIMEOUT
const int _seErrDdeFail = 29; // shellapi.h:378  SE_ERR_DDEFAIL
const int _seErrDdeBusy = 30; // shellapi.h:379  SE_ERR_DDEBUSY
const int _seErrNoAssoc = 31; // shellapi.h:380  SE_ERR_NOASSOC
const int _seErrDllNotFound = 32; // shellapi.h:370  SE_ERR_DLLNOTFOUND

const int _swShowNormal = 1; // winuser.h:394  SW_SHOWNORMAL

/// The `lpOperation` verb. The reference implementation uses the same one.
const String _verbOpen = 'open';

/// Opens a system DLL by absolute path.
///
/// Bare-name loading follows the search order, which begins with the directory
/// the executable was started from — so a DLL dropped next to a consumer's
/// program would be loaded in place of the system one. Siblings
/// `just_font_scan` and `just_autostart` state this as the in-family rule and
/// apply it even to DLLs the `KnownDLLs` registry list already protects,
/// precisely so that nobody has to know which ones those are.
DynamicLibrary _loadSystem32(String name) {
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  return DynamicLibrary.open('$root\\System32\\$name');
}

// Lazily initialised, as every top-level `final` in Dart is. That is what lets
// this file be part of the package on macOS and Linux — the platform dispatch
// never touches these bindings off Windows, so `shell32.dll` is never opened
// there.
final DynamicLibrary _shell32 = _loadSystem32('shell32.dll');

// HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile,
//                         LPCWSTR lpParameters, LPCWSTR lpDirectory,
//                         INT nShowCmd);                      shellapi.h:96
//
// HINSTANCE and HWND are pointer-sized, so they marshal as `IntPtr`. The
// reference truncates the result to `int` before comparing; that is safe only
// because every error code is small, and comparing the full pointer-sized value
// against 32 is equivalent without the truncation.
final _shellExecuteW = _shell32
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
