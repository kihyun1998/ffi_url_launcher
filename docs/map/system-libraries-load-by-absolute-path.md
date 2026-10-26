# System libraries load by absolute path

## The fact
Every system library is opened by absolute path, never by bare name.

## Why it is cross-cutting
Bare-name loading follows a search order a consumer's directory can sit at the
front of. Windows and macOS keep this in separate code — `system32.dart —
loadSystem32` for the DLLs, literal paths in `objc.dart` for the dylib and the
framework — so neither shares a primitive with the other.

## Territories it holds in
- [Windows launch](windows-shell-and-registry.md) — `shell32.dll` via `loadSystem32`.
- [Windows handler lookup](windows-handler-lookup.md) — `advapi32.dll` via `loadSystem32`.
- [macOS Objective-C binding](macos-nsworkspace.md) — `objc.dart — _objc` (`/usr/lib/libobjc.A.dylib`) and `_classInAppKit` (`/System/Library/Frameworks/AppKit.framework/AppKit`).

## What a violation looks like
A hostile DLL beside the consumer's executable is loaded instead of the system
one. Measured once: a hostile `shell32.dll` was **ignored** (it is a KnownDLL)
while a hostile `dwrite.dll` **was loaded** (`system32.dart — loadSystem32`
dartdoc). The rule exists so nobody has to know which list a DLL is on.

## Discovery history
- In-family rule from siblings `just_font_scan` and `just_autostart`
  (`system32.dart` dartdoc).

## Where it will recur
Any new `DynamicLibrary.open`.
