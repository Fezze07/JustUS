// An RPC raise carries an app error code in its message
// ('API-VALIDATION-00x: <developer text>'). The code resolves to a localized
// user message; the raw Postgres text never reaches the UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _FakeRepo extends BaseRepository {
  _FakeRepo(sb.SupabaseClient client) : super(sbClient: client);

  Future<ResultWrapper<void>> boom(Object error) =>
      tryCall<void>(() async => throw error);
}

void main() {
  final en = AppLocalizationsEn();
  final it = AppLocalizationsIt();

  group('ErrorCodes.resolveServerCode', () {
    test('reads the code prefix and ignores the developer text', () {
      expect(
        ErrorCodes.resolveServerCode(
            'API-VALIDATION-006: Cannot invite yourself'),
        ErrorCodes.apiValidation006,
      );
    });

    test('accepts a bare code', () {
      expect(
        ErrorCodes.resolveServerCode('API-VALIDATION-007'),
        ErrorCodes.apiValidation007,
      );
    });

    test('rejects an unknown code and a plain message', () {
      expect(ErrorCodes.resolveServerCode('API-VALIDATION-999: nope'), isNull);
      expect(ErrorCodes.resolveServerCode('division by zero'), isNull);
      expect(ErrorCodes.resolveServerCode(null), isNull);
    });
  });

  group('userMessage', () {
    test('localizes each RPC code in both locales', () {
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation003, en),
          'User not authenticated or invalid ID.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation004, it),
          'Hai già una partnership o una richiesta attiva.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation005, en),
          'Invalid partner email or code.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation006, it),
          'Non puoi invitare te stesso.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation007, en),
          'No active partnership found.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation010, en),
          "You can't request cancellation for this partnership.");
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation011, it),
          "Non c'è alcuna richiesta di cancellazione da annullare.");
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation012, en),
          "You can't perform this cancellation action.");
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation013, it),
          'Non puoi richiedere la cancellazione di nuovo. Riprova più tardi.');
      expect(ErrorCodes.userMessage(ErrorCodes.apiValidation014, en),
          'This cancellation request has expired.');
    });

    test('accepts the cancellation codes from an RPC message', () {
      for (final code in const [
        ErrorCodes.apiValidation010,
        ErrorCodes.apiValidation011,
        ErrorCodes.apiValidation012,
        ErrorCodes.apiValidation013,
        ErrorCodes.apiValidation014,
      ]) {
        expect(ErrorCodes.serverCodes, contains(code));
        expect(ErrorCodes.resolveServerCode('$code: detail'), code);
      }
    });
  });

  group('tryCall', () {
    test('keeps the RPC code of a PostgrestException in details', () async {
      final result = await _FakeRepo(_MockClient()).boom(
        const sb.PostgrestException(
          message: 'API-VALIDATION-007: No active partnership found',
        ),
      );

      expect(result, isA<GenericError<void>>());
      final details = (result as GenericError<void>).details;
      expect(details, isA<AppError>());
      expect((details as AppError).code, ErrorCodes.apiValidation007);
      expect(ErrorHandler.toAppError(result).userMessage(en),
          'No active partnership found.');
    });

    test('keeps a non-RPC failure on the generic path', () async {
      final result = await _FakeRepo(_MockClient())
          .boom(Exception('socket hang up'));

      expect(result, isA<GenericError<void>>());
      expect((result as GenericError<void>).details, isNull);
    });
  });
}
