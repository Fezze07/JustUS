import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/source_scan.dart';

/// Guardrails for how user-facing errors and statuses are raised:
/// - code throws `AppError`, never a bare `Exception`;
/// - `setMessage` only carries a localized String (`LanguageHelper.appLoc.*`),
///   never a hardcoded literal;
/// - a message that travels through `setMessage` is never ALSO shown by a
///   direct `ErrorHandler.showSnackBar` (that would double the snackbar);
/// - the ARB catalogs and the generated `AppLocalizations` stay in sync.

/// Generic `Exception(` only. Typed framework errors (`PostgrestException`,
/// `AuthException`, `SocketException`, ...) are caught, not thrown by us.
final RegExp _bareExceptionThrow = RegExp(r'throw\s+(?:new\s+)?Exception\s*\(');

/// The argument of a `setMessage(...)` call. No real call nests parentheses,
/// so `[^)]*` reads it whole.
final RegExp _setMessageCall = RegExp(r'\bsetMessage\(\s*([^)]*?)\s*\)');

/// A `LanguageHelper.appLoc.<key>` getter — the only sanctioned message source.
final RegExp _appLocMessage =
    RegExp(r'^LanguageHelper\.appLoc\.[A-Za-z_$][\w$]*$');

/// Any `appLoc.<key>` / `.loc.<key>` reference.
final RegExp _locKey = RegExp(r'(?:appLoc|\.loc)\.([A-Za-z_$][\w$]*)');

/// A direct, screen-owned snackbar call.
final RegExp _showSnackBarCall = RegExp(r'ErrorHandler\.showSnackBar\s*\(');

/// A key declared in the generated `AppLocalizations` base class.
final RegExp _generatedGetter =
    RegExp(r'^  String (?:get )?([A-Za-z_$][\w$]*)[;(]');

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// The argument text of the call whose `(` sits at [openParen], matched to its
/// closing `)` so keys inside nested calls are read, not the whole file.
String _argumentsOf(String source, int openParen) {
  var depth = 0;
  for (var i = openParen; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen + 1, i);
    }
  }
  return source.substring(openParen + 1);
}

Set<String> _arbKeys(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return json.keys.where((key) => !key.startsWith('@')).toSet();
}

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

  test('a message key is never also shown by a direct showSnackBar', () {
    final stateKeys = <String, String>{};
    final directKeys = <String, String>{};

    for (final file in handWrittenDartFilesUnder(resolveLibDir())) {
      final path = normalizePath(file.path);
      final source = stripComments(file.readAsStringSync());

      for (final match in _setMessageCall.allMatches(source)) {
        final before = source.substring(0, match.start);
        if (RegExp(r'void\s+$').hasMatch(before)) continue;
        final key = _locKey.firstMatch(match.group(1)!.trim())?.group(1);
        if (key != null) {
          stateKeys.putIfAbsent(
              key, () => '$path:${_lineOf(source, match.start)}');
        }
      }

      for (final match in _showSnackBarCall.allMatches(source)) {
        final args = _argumentsOf(source, match.end - 1);
        for (final key in _locKey.allMatches(args)) {
          directKeys.putIfAbsent(
              key.group(1)!, () => '$path:${_lineOf(source, match.start)}');
        }
      }
    }

    expect(stateKeys, isNotEmpty, reason: 'no setMessage keys scanned');
    expect(directKeys, isNotEmpty, reason: 'no direct snackbar keys scanned');

    final overlap = stateKeys.keys
        .where(directKeys.containsKey)
        .map((key) => '$key — state: ${stateKeys[key]}, '
            'snackbar: ${directKeys[key]}')
        .toList();
    expect(
      overlap,
      isEmpty,
      reason: 'These keys are raised through the state message AND shown '
          'directly, so the user sees them twice. Keep one path: a state '
          'message for action feedback, a direct snackbar for UI-local '
          'validation only.\n${overlap.join('\n')}',
    );
  });

  test('ARB catalogs and generated localizations agree', () {
    final en = _arbKeys('lib/core/localization/intl_en.arb');
    final it = _arbKeys('lib/core/localization/intl_it.arb');

    expect(en, isNotEmpty);
    expect(
      en,
      unorderedEquals(it),
      reason: 'intl_en.arb and intl_it.arb must declare the same keys, or one '
          'locale silently falls back to empty text.',
    );

    final generated = File(
            'lib/core/localization/generated/app_localizations.dart')
        .readAsStringSync()
        .split('\n')
        .map((line) => _generatedGetter.firstMatch(line)?.group(1))
        .whereType<String>()
        .toSet();

    expect(
      generated,
      unorderedEquals(en),
      reason: 'The generated AppLocalizations is stale — a key was added to '
          'or removed from the ARB without re-running `flutter gen-l10n`.',
    );
  });
}
