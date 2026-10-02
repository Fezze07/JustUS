import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shared helpers for the `lib/` source-scan tests (`import_hygiene`,
/// `logging_restrictions`, `feedback_system`, `app_palette`).
///
/// They all walk `lib/` from the working directory, which is only the Flutter
/// project root under `flutter test`. Resolving it here — once, loudly — is what
/// stops a mis-rooted scan from reporting success on zero inspected files.

/// Returns the `lib/` directory, failing the test if it is not reachable.
///
/// A previous version of `logging_restrictions_test` did
/// `if (!libDir.existsSync()) return;`, which turned the whole print/debugPrint
/// ban into a test that always passed and never checked anything.
Directory resolveLibDir() {
  final libDir = Directory('lib');
  expect(
    libDir.existsSync(),
    isTrue,
    reason: 'lib/ not found relative to the working directory. Run this test '
        'from the Flutter project root (flutter test), not from the repo root.',
  );

  return libDir;
}

/// Every `.dart` file under [dir], sorted so failure output is deterministic.
List<File> dartFilesUnder(Directory dir) {
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Dart files under [dir] excluding machine-generated localization output.
List<File> handWrittenDartFilesUnder(Directory dir) {
  return dartFilesUnder(dir)
    ..removeWhere(
      (file) => file.path.replaceAll(r'\', '/').startsWith(
            'lib/core/localization/generated/',
          ),
    );
}

/// Strips `//` and `/* */` comments so documentation mentions of a symbol do
/// not register as violations.
String stripComments(String source) => source
    .replaceAll(RegExp(r'//.*'), '')
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

/// Normalizes a path to forward slashes so assertions are OS-independent.
String normalizePath(String path) => path.replaceAll(r'\', '/');
