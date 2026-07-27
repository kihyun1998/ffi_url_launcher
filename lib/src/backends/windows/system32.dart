import 'dart:ffi';
import 'dart:io';

/// Opens a system DLL by absolute path.
///
/// Bare-name loading follows the search order, which begins with the directory
/// the executable was started from — so a DLL dropped next to a consumer's
/// program would be loaded in place of the system one. Siblings `just_font_scan`
/// and `just_autostart` state this as the in-family rule and apply it even to
/// DLLs the `KnownDLLs` registry list already protects, precisely so that nobody
/// has to know which ones those are.
///
/// Verified once, on this machine: a hostile `shell32.dll` placed beside the
/// executable was **ignored** (SHELL32 is a KnownDLL) while a hostile
/// `dwrite.dll` **was loaded** (it is not). Loading by absolute path removes the
/// need to know which list a DLL is on.
///
/// Every caller holds the result in a top-level `final`, which Dart initialises
/// lazily — that is what lets these files be part of the package on macOS
/// without ever opening a Windows DLL there.
DynamicLibrary loadSystem32(String name) {
  final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
  return DynamicLibrary.open('$root${r'\System32\'}$name');
}
