import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/source_scan.dart';

void main() {
  test(
      'No raw print or debugPrint calls allowed in lib/ except in ansi_logger.dart',
      () {
    final offenders = <String>[];

    for (final file in dartFilesUnder(resolveLibDir())) {
      // ansi_logger.dart is the sanctioned sink.
      if (file.path.endsWith('ansi_logger.dart')) {
        continue;
      }

      final content = stripComments(file.readAsStringSync());

      for (final match in RegExp(r'\bprint\s*\(').allMatches(content)) {
        offenders.add('${file.path}: ${match.group(0)}');
      }
      for (final match in RegExp(r'\bdebugPrint\s*\(').allMatches(content)) {
        offenders.add('${file.path}: ${match.group(0)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Raw print()/debugPrint() found (${offenders.length}). '
          'Use AnsiLogger instead:\n${offenders.join('\n')}',
    );
  });

  test('the scan actually inspected a non-trivial part of lib/', () {
    // Guards the scan itself: a scan that silently matched nothing must not be
    // able to report success.
    final files = handWrittenDartFilesUnder(resolveLibDir());

    expect(
      files.length,
      greaterThan(50),
      reason:
          'Only ${files.length} hand-written Dart files scanned under lib/ — '
          'the scan is probably pointed at the wrong directory.',
    );
  });
}
