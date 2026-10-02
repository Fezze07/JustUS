import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/source_scan.dart';

/// Regression tests for 6.4 / F-DS8: the app has exactly one snackbar/toast
/// mechanism (`ErrorHandler.showSnackBar`, root-overlay based) and exactly one
/// dialog component (`VPDialog`). Both used to have a second implementation,
/// which let copy, timing and styling drift per call site.
const String _vpWidgetsPath = 'lib/shared/design_system/vp_widgets.dart';

void main() {
  test('no second snackbar helper exists alongside ErrorHandler', () {
    final offenders = <String>[];

    for (final file in handWrittenDartFilesUnder(resolveLibDir())) {
      final path = normalizePath(file.path);
      final source = file.readAsStringSync();
      if (RegExp(r'\bUIUtils\b').hasMatch(source)) {
        offenders.add('$path references UIUtils');
      }
      if (RegExp(r'ScaffoldMessenger\.of\(').hasMatch(source)) {
        offenders.add('$path uses ScaffoldMessenger.of — feedback must go '
            'through ErrorHandler.showSnackBar');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'A second feedback path crept back in (${offenders.length}).\n'
          '${offenders.join('\n')}',
    );
  });

  test('ErrorHandler exposes the single snackbar entry point', () {
    final file = File('lib/core/error_handling/error_handler.dart');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'error_handler.dart moved — update this test and the snackbar '
          'call sites that depend on its public API.',
    );

    final source = file.readAsStringSync();

    expect(RegExp(r'static void showSnackBar\(').hasMatch(source), isTrue,
        reason: 'ErrorHandler.showSnackBar must stay public for call sites.');
  });

  test('AlertDialog is only constructed by VPDialog', () {
    final offenders = <String>[];

    for (final file in handWrittenDartFilesUnder(resolveLibDir())) {
      final path = normalizePath(file.path);
      if (path == _vpWidgetsPath) continue;

      if (RegExp(r'\bAlertDialog\s*\(').hasMatch(file.readAsStringSync())) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Raw AlertDialog(s) outside $_vpWidgetsPath — use VPDialog so '
          'title/content/actions styling cannot diverge per screen '
          '(${offenders.length}).\n${offenders.join('\n')}',
    );
  });
}
