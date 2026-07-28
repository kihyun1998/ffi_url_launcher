# ffi_url_launcher

Open a URL in the system's registered handler on **Windows and macOS**, calling
the operating system directly through `dart:ffi`.

Pure Dart. No Flutter dependency, no native sources to compile, and **no build
hooks** — so a consumer can still `dart compile exe` into a single executable.

> **Status: early, and now symmetric.** `launchUrl` and `canLaunchUrl` both work
> on Windows and macOS, with the same signatures and the same meaning. Any
> platform without a backend raises `UnsupportedError` that names it.

## Usage

```dart
import 'package:ffi_url_launcher/ffi_url_launcher.dart';

Future<void> main() async {
  final url = Uri.parse('https://dart.dev');
  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  } else {
    print('nothing on this machine is registered to open that');
  }
}
```

Ask with `canLaunchUrl` rather than branching on what `launchUrl` returns — see
[What the return value means](#what-the-return-value-means) for why.

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
| `false` | the operating system reported that nothing is registered to open this. **On Windows this is effectively unreachable for a URL scheme; do not branch on it there** — use `canLaunchUrl`. **On macOS it is honest and reachable:** `NSWorkspace` returns `NO` for a URL nothing can open, with no window |
| throws `UnsafeUrlError` | the URL's shape says it is a local path — see [Security](#security) |
| throws `UrlLaunchException` | the operating system refused for some other reason; `platformCode` carries its code on Windows, and `target` names the string it was actually given |
| throws `UnsupportedError` | this platform has no backend |

**`true` does not mean the URL opened.** Neither Windows nor macOS reports that,
and on Windows it means less than it looks:

> Measured on Windows 11: `ShellExecuteW` answers **success** for a scheme
> nothing is registered to handle. It reports that the request was accepted, not
> what became of it — sometimes a "how do you want to open this?" picker, and in
> at least one measured run nothing visible at all. The documented
> `SE_ERR_NOASSOC` code is not reachable through a URL scheme, so `false` is
> effectively unreachable on Windows for schemes and a `true` can mean the user
> saw a picker, or nothing, instead of their content.

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

| | `launchUrl` | `canLaunchUrl` |
|---|---|---|
| Windows 10+ | ✅ `ShellExecuteW` | ✅ `HKEY_CLASSES_ROOT` (per **scheme**) |
| macOS 10.14+ | ✅ `NSWorkspace` | ✅ `URLForApplicationToOpenURL:` (per **URL**) |
| anything else | `UnsupportedError` | `UnsupportedError` |

**`canLaunchUrl` asks a slightly different question on each platform**, because
the two systems keep different registries. Windows asks whether the *scheme* has
a registered handler; macOS asks which application would open *that exact URL*.
For `https:` or a custom app scheme they agree. Where they visibly differ is
`file:` — Windows answers `true` for any `file:` URL (scheme registration and
file-extension association are separate layers there), while macOS answers based
on whether something handles that file's type. Both are truthfully answering
"does anything on **this** system claim this", which is all `canLaunchUrl` ever
promises.

Three more platform details worth knowing before they surprise you:

- **`UrlLaunchException.platformCode` is `null` on macOS.** `NSWorkspace.open`
  answers a bare `BOOL` with no code to carry, and a fabricated one would be
  worse than its absence. On Windows it carries the `ShellExecuteW` error code.
- **The shape check (see [Security](#security)) is cross-platform.** It runs on
  the `Uri` before either OS is touched, so a drive-letter or schemeless path is
  refused identically on macOS and Windows.
- **`canLaunchUrl` opens nothing; `launchUrl` can put a window on screen even
  when nothing opens.** On macOS, launching a scheme nothing handles returns
  `false` *and* raises the system panel "there is no application set to open the
  URL" (measured). Asking first is what keeps that away from your user, and it
  is a large part of why the two are separate calls.

## Prior art

The choice of which operating-system call to make, and the shape of the public
API, follow [`url_launcher`](https://pub.dev/packages/url_launcher) so code
moving across does not change shape. No code was copied; its Windows and macOS
implementations are C++ and Swift, and the marshalling a Dart port needs is
derived separately.
