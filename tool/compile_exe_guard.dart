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
    // **The consumer inherits this package's own SDK constraint** rather than
    // naming one. Hardcoding it is how the guard ends up testing a floor the
    // package does not declare: this line read `^3.11.5` while the package was
    // being lowered to `>=3.7.0`, so the guard refused to run on the very SDK
    // the change existed to support, and a green guard would have said nothing
    // about the floor consumers were being promised.
    final sdkConstraint = _packageSdkConstraint(repoRoot);
    stdout.writeln('consumer sdk constraint (from pubspec): $sdkConstraint');

    _write(consumer, 'pubspec.yaml', '''
name: compile_exe_guard
publish_to: none

environment:
  sdk: $sdkConstraint

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

/// Reads `environment.sdk` out of this package's own `pubspec.yaml`.
///
/// Hand-parsed rather than pulled from a YAML package: `tool/` ships inside the
/// published archive, and taking a dependency for it would put a second entry
/// beside `ffi` in the very list `check_dependencies.dart` exists to keep at one
/// (`docs/agents/theflow.md`, the dependency invariant).
///
/// Anchored on the `environment:` block rather than on the first `sdk:` in the
/// file, because `sdk:` is also how a Flutter dependency is spelled — this
/// package has none today, and a parser that would break when it does is not
/// worth the two lines saved.
String _packageSdkConstraint(String repoRoot) {
  final pubspec = File('$repoRoot/pubspec.yaml').readAsLinesSync();

  var inEnvironment = false;
  for (final line in pubspec) {
    if (line.startsWith('environment:')) {
      inEnvironment = true;
      continue;
    }
    // Any other column-0 key ends the block.
    if (inEnvironment && line.isNotEmpty && !line.startsWith(' ')) break;

    if (inEnvironment) {
      final match = RegExp(r'^\s+sdk:\s*(.+?)\s*$').firstMatch(line);
      if (match != null) return match.group(1)!;
    }
  }

  _fail(
    'could not read environment.sdk from pubspec.yaml. The guard will not '
    'invent a constraint: doing so is what let it test a floor the package '
    'never declared.',
  );
}

/// Quotes a filesystem path for a YAML scalar.
///
/// Windows paths contain backslashes, which YAML leaves alone in a plain
/// scalar but a reader may not; single quotes make the intent explicit, and any
/// embedded quote is doubled per the YAML spec.
String _yamlPath(String path) => "'${path.replaceAll("'", "''")}'";
