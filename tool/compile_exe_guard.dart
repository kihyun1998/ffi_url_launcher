// Proves that a consumer of this package can still `dart compile exe`.
//
// Run it from the repo root:
//
//     dart run tool/compile_exe_guard.dart
//
// **This is the gate no other gate can express.** The package's central promise
// is that it adds no build hooks, and a dependency that declares `hooks:` —
// `package:objective_c` is the ergonomic temptation on macOS — breaks
// `dart compile exe` outright with *"'dart compile' does not support build
// hooks, use 'dart build' instead"*. That failure appears one repo downstream,
// in a **consumer**, never in this repo's own tests, so it would pass every
// other gate (`docs/agents/lessons.md` #1).
//
// The consumer is generated into a temp directory rather than committed. A
// second `pubspec.yaml` inside the repo would create the out-of-workspace
// member that `docs/agents/theflow.md` records as *not existing here* — a real
// blind spot, since `dart test` at the root would not run it.
//
// **The generated program must answer something POSITIVELY.** An earlier
// version of this guard printed a resolved backend type, which a completely
// broken FFI load would also have printed: on macOS, messaging a class that
// never loaded returns `NO`/nil silently, so every negative answer stays
// available to a broken build (`docs/agents/lessons.md` #9). Asking whether
// `https:` has a handler and requiring `true` is what makes the compiled binary
// prove the platform libraries were actually reached.
import 'dart:io';

void main() async {
  final repoRoot = Directory.current.absolute.path;
  if (!File('$repoRoot/pubspec.yaml').existsSync()) {
    _fail('run this from the repo root; no pubspec.yaml in $repoRoot');
  }

  final consumer = Directory.systemTemp.createTempSync('ffi_url_launcher_exe_');
  stdout.writeln('consumer: ${consumer.path}');

  try {
    _write(consumer, 'pubspec.yaml', '''
name: compile_exe_guard
publish_to: none

environment:
  sdk: ^3.11.5

dependencies:
  ffi_url_launcher:
    path: ${_yamlPath(repoRoot)}
''');

    // Deliberately asks a question with a knowable, non-empty answer, and
    // deliberately does NOT launch anything — CI must not open a browser.
    _write(consumer, 'bin/main.dart', '''
import 'dart:io';

import 'package:ffi_url_launcher/ffi_url_launcher.dart';

void main() {
  final registered = canLaunchUrlSync(Uri.parse('https://dart.dev'));
  final absent = canLaunchUrlSync(
    Uri.parse('zzznotreal-ffiurllauncher://x'),
  );

  print('https registered: \$registered');
  print('unregistered scheme: \$absent');

  if (!registered) {
    print('GUARD FAILED: nothing claims https on this machine, which almost '
        'certainly means the platform libraries were never reached.');
    exit(1);
  }
  if (absent) {
    print('GUARD FAILED: a scheme nothing handles answered true.');
    exit(1);
  }
  print('GUARD OK');
}
''');

    await _run('dart', ['pub', 'get'], consumer.path);

    // The binary name carries no extension on purpose; `dart compile exe`
    // appends `.exe` on Windows and Process.run needs the real path either way.
    final output = Platform.isWindows ? 'bin/main.exe' : 'bin/main';
    await _run('dart', [
      'compile',
      'exe',
      'bin/main.dart',
      '-o',
      output,
    ], consumer.path);

    final binary =
        '${consumer.path}${Platform.pathSeparator}'
        '${output.replaceAll('/', Platform.pathSeparator)}';
    final result = await _run(binary, const [], consumer.path);

    if (!result.contains('GUARD OK')) {
      _fail('the compiled binary ran but did not report GUARD OK');
    }
    stdout.writeln('\ncompile_exe_guard: OK');
  } finally {
    try {
      consumer.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      // Windows can hold the freshly-run binary briefly. Not worth failing the
      // guard over — the temp directory is the OS's to reclaim.
      stderr.writeln(
        'note: could not remove ${consumer.path}: ${error.message}',
      );
    }
  }
}

void _write(Directory root, String relative, String contents) {
  final file = File(
    '${root.path}${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}',
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

/// Runs [executable] and fails the guard if it does not exit 0.
///
/// Output is echoed rather than swallowed: when this gate goes red the
/// subprocess message *is* the finding, and a guard that hides it would send
/// the reader looking in the wrong place.
Future<String> _run(
  String executable,
  List<String> arguments,
  String cwd,
) async {
  stdout.writeln('\n\$ $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: cwd,
    // No shell: paths with spaces are ordinary on both runners.
    runInShell: false,
  );

  final out = '${result.stdout}${result.stderr}';
  stdout.write(out);
  if (result.exitCode != 0) {
    _fail('$executable ${arguments.join(' ')} exited ${result.exitCode}');
  }
  return out;
}

Never _fail(String message) {
  stderr.writeln('\ncompile_exe_guard: $message');
  exit(1);
}

/// Quotes a filesystem path for a YAML scalar.
///
/// Windows paths contain backslashes, which YAML leaves alone in a plain
/// scalar but a reader may not; single quotes make the intent explicit, and any
/// embedded quote is doubled per the YAML spec.
String _yamlPath(String path) => "'${path.replaceAll("'", "''")}'";
