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
