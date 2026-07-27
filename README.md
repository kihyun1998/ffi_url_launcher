# ffi_url_launcher

Open a URL in the system's registered handler on **Windows and macOS**, calling
the operating system directly through `dart:ffi`.

Pure Dart. No Flutter dependency, no native sources to compile, and **no build
hooks** — so a consumer can still `dart compile exe` into a single executable.

> **Status: early. Windows only so far.** macOS is designed but not yet wired;
> calling this on any platform without a backend raises `UnsupportedError` that
> names the platform. `canLaunchUrl` and URL validation are not implemented yet
> — read the caveats below before relying on the return value.

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
| throws `UrlLaunchException` | the operating system refused for some other reason; `platformCode` carries its code on Windows |
| throws `UnsupportedError` | this platform has no backend |

**`true` does not mean the URL opened.** Neither Windows nor macOS reports that,
and on Windows it means less than it looks:

> Measured on Windows 11: `ShellExecuteW` answers **success** for a scheme
> nothing is registered to handle, because what it successfully launched is its
> own "how do you want to open this?" dialog. The documented `SE_ERR_NOASSOC`
> code is not reachable through a URL scheme. So `false` is **currently
> unreachable on Windows for schemes**, and a `true` can mean the user was shown
> a Store lookup instead of their content.

Reading the registry — the forthcoming `canLaunchUrl` — is the only reliable way
to know beforehand. Until it lands, treat `true` as "the request was accepted",
not as "it worked".

## Security

This version performs **no URL validation**. A string that `Uri` parses is
handed to the shell as-is, and on Windows a drive-letter path parses as a URI:

```dart
Uri.parse(r'C:\Windows\System32\calc.exe').scheme;      // 'c'
Uri.parse(r'C:\Windows\System32\calc.exe').hasScheme;   // true
```

`ShellExecuteW` accepts the forward-slashed form of that and **executes it**.
Until the shape check lands, do not pass URLs from an untrusted source — a
network response, a config file, standard input — without checking them
yourself.

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
