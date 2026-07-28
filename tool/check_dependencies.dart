// Enforces the one-runtime-dependency invariant.
//
// Run it from the repo root:
//
//     dart run tool/check_dependencies.dart
//
// **Why this exists beside the compile-exe guard, rather than being covered by
// it.** `CLAUDE.md` names two ways a convenience dependency breaks this
// package, and they fail differently:
//
//   * a dependency declaring `hooks:` breaks `dart compile exe` for every
//     consumer — caught by `tool/compile_exe_guard.dart`;
//   * a **Windows-only** dependency such as `package:win32` misstates this
//     package's platform support. It resolves cleanly, analyzes cleanly, tests
//     cleanly and compiles cleanly on both runners. **Nothing else catches it.**
//
// `docs/agents/lessons.md` #1 is the first of those actually happening. The
// second is the one this file is for: an invariant no gate expressed until now,
// which is the same shape of gap that lesson is about.
//
// It reads `dart pub deps --json` rather than parsing `pubspec.yaml`, so it
// needs no YAML parser — adding a dependency to police the dependency list
// would be its own joke — and so it sees what pub actually resolved rather than
// what the file appears to say.
import 'dart:convert';
import 'dart:io';

/// The complete permitted runtime dependency set.
///
/// Adding to this is a deliberate act with a reason recorded beside it, not a
/// convenience. `ffi` is here because `dart:ffi` ships no allocator and no
/// UTF-16 marshalling; it is pure Dart, maintained by the Dart team, and
/// declares no `hooks:` and no platform restriction.
const Set<String> allowedRuntimeDependencies = {'ffi'};

void main() async {
  final result = await Process.run('dart', [
    'pub',
    'deps',
    '--json',
  ], runInShell: false);

  if (result.exitCode != 0) {
    stderr.writeln('dart pub deps failed:\n${result.stdout}${result.stderr}');
    exit(1);
  }

  final deps = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final packages = (deps['packages'] as List).cast<Map<String, dynamic>>();
  final rootName = deps['root'] as String;

  final root = packages.firstWhere((p) => p['name'] == rootName);
  // The root's `dependencies` list mixes runtime and dev entries; the dev ones
  // are exactly those pub marked `kind: dev`. Subtracting them leaves the set
  // that a consumer actually inherits, which is the thing under guard — dev
  // dependencies never reach a consumer and are not restricted.
  final devNames = packages
      .where((p) => p['kind'] == 'dev')
      .map((p) => p['name'] as String)
      .toSet();
  final runtime = (root['dependencies'] as List)
      .cast<String>()
      .where((name) => !devNames.contains(name))
      .toSet();

  if (_setEquals(runtime, allowedRuntimeDependencies)) {
    stdout.writeln(
      'check_dependencies: OK — runtime dependencies are exactly '
      '${_sorted(allowedRuntimeDependencies)}',
    );
    return;
  }

  final added = _sorted(runtime.difference(allowedRuntimeDependencies));
  final removed = _sorted(allowedRuntimeDependencies.difference(runtime));

  stderr.writeln('check_dependencies: FAILED');
  stderr.writeln('  allowed : ${_sorted(allowedRuntimeDependencies)}');
  stderr.writeln('  actual  : ${_sorted(runtime)}');
  if (added.isNotEmpty) {
    stderr.writeln('  added   : $added');
    stderr.writeln('''

A new runtime dependency is an invariant change, not a preference. Before
allowing it, check the two failure modes this guard and its sibling exist for:

  * does it declare `hooks:`?  It will break `dart compile exe` for every
    consumer of this package, and only tool/compile_exe_guard.dart will say so.
  * does it declare `platforms:`?  A Windows-only package makes this package
    claim support it does not have, and no other gate can see it.

If it is genuinely wanted, add it to `allowedRuntimeDependencies` in this file
with the reason, and say so in CHANGELOG.md.''');
  }
  if (removed.isNotEmpty) {
    stderr.writeln('  missing : $removed');
  }
  exit(1);
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

List<String> _sorted(Set<String> names) => names.toList()..sort();
