import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/source_scan.dart';

/// Guardrails for how user-facing errors and statuses are raised:
/// - code throws `AppError`, never a bare `Exception`;
/// - `setMessage` only carries a localized String (`LanguageHelper.appLoc.*`),
///   never a hardcoded literal.

/// Generic `Exception(` only. Typed framework errors (`PostgrestException`,
/// `AuthException`, `SocketException`, ...) are caught, not thrown by us.
final RegExp _bareExceptionThrow = RegExp(r'throw\s+(?:new\s+)?Exception\s*\(');

/// The argument of a `setMessage(...)` call. No real call nests parentheses,
/// so `[^)]*` reads it whole.
final RegExp _setMessageCall = RegExp(r'\bsetMessage\(\s*([^)]*?)\s*\)');

/// A `LanguageHelper.appLoc.<key>` getter — the only sanctioned message source.
final RegExp _appLocMessage =
    RegExp(r'^LanguageHelper\.appLoc\.[A-Za-z_$][\w$]*$');

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

void main() {
  test('detectors match violations and ignore the sanctioned forms', () {
    expect(_bareExceptionThrow.hasMatch("throw Exception('x');"), isTrue);
    expect(_bareExceptionThrow.hasMatch('throw new Exception("x");'), isTrue);
    expect(_bareExceptionThrow.hasMatch('throw PostgrestException(x);'), isFalse);

    expect(
        _appLocMessage.hasMatch('LanguageHelper.appLoc.profile_saved'), isTrue);
    expect(_appLocMessage.hasMatch("'Nome aggiornato!'"), isFalse);
    expect(_appLocMessage.hasMatch('loc.game_answerSent'), isFalse);
  });

  test('lib/ never throws a bare Exception (use AppError)', () {
    final offenders = <String>[];

    for (final file in handWrittenDartFilesUnder(resolveLibDir())) {
      final path = normalizePath(file.path);
      final source = stripComments(file.readAsStringSync());
      for (final match in _bareExceptionThrow.allMatches(source)) {
        offenders.add('$path:${_lineOf(source, match.start)} throws Exception '
            '— use AppError(code:, message:).');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Bare Exception throws found (${offenders.length}).\n'
          '${offenders.join('\n')}',
    );
  });

  test('setMessage only receives LanguageHelper.appLoc messages', () {
    final offenders = <String>[];
    var scanned = 0;

    for (final file in handWrittenDartFilesUnder(resolveLibDir())) {
      final path = normalizePath(file.path);
      final source = stripComments(file.readAsStringSync());
      for (final match in _setMessageCall.allMatches(source)) {
        // Skip the BaseState declaration (`void setMessage(String? value)`).
        final before = source.substring(0, match.start);
        if (RegExp(r'void\s+$').hasMatch(before)) continue;

        scanned++;
        final argument = match.group(1)!.trim();
        if (!_appLocMessage.hasMatch(argument)) {
          offenders.add('$path:${_lineOf(source, match.start)} '
              'setMessage($argument) — pass a LanguageHelper.appLoc.<key> '
              'message, not hardcoded text.');
        }
      }
    }

    expect(scanned, greaterThan(5),
        reason: 'Only $scanned setMessage calls scanned — wrong directory?');
    expect(
      offenders,
      isEmpty,
      reason: 'Non-localized setMessage arguments (${offenders.length}).\n'
          '${offenders.join('\n')}',
    );
  });
}
