# ffi_url_launcher

Open a URL in the system's registered handler on **Windows and macOS**, calling
the operating system directly through `dart:ffi`.

Pure Dart. No Flutter dependency, no native sources to compile, and **no build
hooks** — so a consumer can still `dart compile exe` into a single executable.

> **Status: early. Windows only so far.** macOS is designed but not yet wired;
> calling this on any platform without a backend raises `UnsupportedError` that
> names the platform.

## Usage

```dart
import 'package:ffi_url_launcher/ffi_url_launcher.dart';

Future<void> main() async {
  if (!await launchUrl(Uri.parse('https://dart.dev'))) {
    print('nothing is registered to open that');
  }
}
```

From a command-line tool with no reason to be `async`:

```dart
launchUrlSync(Uri.parse('https://dart.dev'));
```

To ask what the package would do on a platform you are not running on — useful
in tests:

```dart
UrlLauncher.forOperatingSystem('linux').launchUrlSync(url);  // throws, naming linux
```

## What the return value means

| Result | Meaning |
|---|---|
| `true` | the handler was **started** |
| `false` | the operating system reported that nothing is registered to open this |
| throws `UnsafeUrlError` | the URL's shape says it is a local path — see [Security](#security) |
| throws `UrlLaunchException` | the operating system refused for some other reason; `platformCode` carries its code on Windows, and `target` names the string it was actually given |
| throws `UnsupportedError` | this platform has no backend |

**`true` does not mean the URL opened.** Neither Windows nor macOS reports that,
and on Windows it means less than it looks:

> Measured on Windows 11: `ShellExecuteW` answers **success** for a scheme
> nothing is registered to handle, because what it successfully launched is its
> own "how do you want to open this?" dialog. The documented `SE_ERR_NOASSOC`
> code is not reachable through a URL scheme, so `false` is effectively
> unreachable on Windows for schemes and a `true` can mean the user was shown an
> app picker instead of their content.

**Ask first** — that is what `canLaunchUrl` is for. It reads the system's
registry of handlers rather than asking the shell to try, so it can answer the
question the launch path cannot, and it opens nothing:

```dart
final url = Uri.parse('obsidian://open?vault=notes');
if (await canLaunchUrl(url)) {
  await launchUrl(url);
} else {
  print('nothing on this machine handles obsidian: URLs');
}
```

A `true` there says a handler is **registered**, not that opening will succeed —
the registered application can still be missing or broken. It is the strongest
answer the OS gives without launching anything.

## Security

A URL whose **shape** says it is a local path is refused before the operating
system sees it. The check is on by default and throws `UnsafeUrlError`.

| Input | Result |
|---|---|
| `C:\Windows\System32\calc.exe` | **refused** — parses with the one-letter scheme `c`, a drive letter |
| `\\attacker\share\evil.exe` | **refused** — no scheme |
| `evil.bat`, `some/path` | **refused** — no scheme |
| `''` (empty or blank) | **refused** — no scheme |
| `file:`, `file://`, `file:///` | **refused** — names no file; converts to the current drive's root |
| `file:///C:/a.txt?q=1`, `…#frag` | **refused** — a query or fragment means it is not a file path |
| `https://…`, `mailto:…`, `myapp://…` | allowed |
| `file:///C:/x.txt`, `file://server/share/x` | allowed |
| `file:///C:/Windows/System32/calc.exe` | **allowed — and it will execute** |

**Read that last row.** `file:` is a supported desktop feature, so this check
does not block it. It blocks two specific shapes; it is not a judgement about
whether a URL is safe to open, and describing it as "validated" would move your
belief without moving your risk. If your URLs come from a network response, a
config file, or standard input, you still need your own policy on top — a scheme
whitelist is yours to decide, deliberately not this package's.

Why these two shapes and not a whitelist: `Uri` typing alone does not protect
you. Measured on Windows 11 —

```dart
Uri.parse(r'C:\Windows\System32\calc.exe').scheme;      // 'c'   — not what you expect
Uri.parse(r'C:\Windows\System32\calc.exe').hasScheme;   // true  — a `hasScheme` guard passes it
```

`ShellExecuteW` accepts the forward-slashed form and **executes it**. An empty
URL is not inert either: `ShellExecuteW('')` answers *success* and opens a File
Explorer window. Both are now refused.

To opt out for an input you have already decided is fine:

```dart
await launchUrl(uri, allowUnsafe: true);
```

## Platform support

| | Status |
|---|---|
| Windows 10+ | implemented (`ShellExecuteW`) |
| macOS 10.14+ | designed, not yet wired (`NSWorkspace`) |
| anything else | `UnsupportedError` |

## Prior art

The choice of which operating-system call to make, and the shape of the public
API, follow [`url_launcher`](https://pub.dev/packages/url_launcher) so code
moving across does not change shape. No code was copied; its Windows and macOS
implementations are C++ and Swift, and the marshalling a Dart port needs is
derived separately.
