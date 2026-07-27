import 'dart:io';

import 'package:ffi_url_launcher/ffi_url_launcher.dart';

/// Opens a URL in the system's default handler.
///
/// Run it with `dart run example/ffi_url_launcher_example.dart [url]`. A
/// browser window appearing is the point — it is the one assertion the test
/// suite cannot make, because opening a window is a side effect CI has no way
/// to observe or clean up.
Future<void> main(List<String> arguments) async {
  final target = Uri.parse(
    arguments.isEmpty ? 'https://dart.dev' : arguments.first,
  );

  // The argument is passed through untouched on purpose. The package refuses a
  // local path itself now, so an example that pre-filtered would be hiding the
  // behaviour it exists to demonstrate — try it with "" or C:\Windows\… and the
  // UnsafeUrlError branch below is what you get.
  try {
    // Ask first. Branching on what `launchUrl` returns would be demonstrating a
    // pattern the package documents against: on Windows its `false` is
    // effectively unreachable for a URL scheme, because the shell reports that
    // it accepted the request and not what became of it.
    if (!await canLaunchUrl(target)) {
      print('Nothing on this machine is registered to open $target.');
      return;
    }

    await launchUrl(target);
    print('Handed $target to its registered handler.');
  } on UnsafeUrlError catch (error) {
    stderr.writeln('Refused: $error');
    exitCode = 2;
  } on UrlLaunchException catch (error) {
    // `target` is the string the OS was handed — for a file: URL that is the
    // decoded path, which is the form a reader recognises.
    print('Could not open ${error.target}: ${error.message}');
    if (error.platformCode case final code?) print('Platform code: $code.');
  } on UnsupportedError catch (error) {
    print(error.message);
  }
}
