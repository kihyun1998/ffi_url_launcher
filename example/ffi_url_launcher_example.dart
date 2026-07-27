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

  // The package does not check this yet (that is ticket 02), and the README
  // tells callers not to pass an unvalidated argument through until it does.
  // An example that took `arguments.first` on trust would be demonstrating the
  // practice the package documents against: `dart run example/… ""` opens a
  // File Explorer window and reports success, measured in lessons.md #4.
  if (!target.hasScheme || target.scheme.length == 1) {
    stderr.writeln(
      'Refusing "${arguments.first}": that is a local path, not a URL. '
      'Pass something like https://dart.dev.',
    );
    exitCode = 2;
    return;
  }

  try {
    if (await launchUrl(target)) {
      print('Handed $target to its registered handler.');
    } else {
      // Not a failure: the system simply has nothing registered for this URL.
      print('Nothing on this machine is registered to open $target.');
    }
  } on UrlLaunchException catch (error) {
    print('Could not open $target: ${error.message}');
    if (error.platformCode case final code?) print('Platform code: $code.');
  } on UnsupportedError catch (error) {
    print(error.message);
  }
}
