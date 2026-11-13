import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

/// Regression tests for 19.3: the cached active partnership belongs to the user
/// that started it and must never survive into another account in the same
/// process.
class _NoopAuthRepository extends AuthRepository {
  @override
  Future<void> signOut() async {}
}

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

class _MockFilter extends Mock
    implements sb.PostgrestFilterBuilder<sb.PostgrestList> {}

/// Answers handed to `await`: mocktail's canned response never resolves when
/// awaited, so `then` is implemented for real.
class _MockMaybeSingle extends Mock
    implements sb.PostgrestTransformBuilder<sb.PostgrestMap?> {
  _MockMaybeSingle(this.row);

  final sb.PostgrestMap? row;

  @override
  Future<R> then<R>(
    Function(sb.PostgrestMap? value) onValue, {
    Function? onError,
  }) async {
    try {
      return await onValue(row) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _ProbePartnershipRepository extends PartnershipRepository {
  _ProbePartnershipRepository(this.client);

  final sb.SupabaseClient client;
  int? uid;

  @override
  Future<int?> getUserId() async => uid;

  @override
  sb.SupabaseClient get sbClient => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ProbePartnershipRepository repository;
  late int queries;

  setUp(() {
    installMockSecureStorage();
    installMockPathProvider();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    PartnershipRepository.clearPartnershipCache();

    final client = _MockClient();
    final from = _MockFrom();
    final filter = _MockFilter();
    queries = 0;
    final rows = <sb.PostgrestMap?>[
      {
        'partnership_id': 9001,
        'partner_id': 7,
        'partner_display_name': 'Alex',
      },
      {
        'partnership_id': 9002,
        'partner_id': 8,
        'partner_display_name': 'Bea',
      },
    ];

    when(() => client.from('v_active_partnership')).thenAnswer((_) => from);
    when(() => from.select()).thenAnswer((_) => filter);
    when(() => filter.maybeSingle()).thenAnswer((_) {
      final row = rows[queries];
      queries += 1;
      return _MockMaybeSingle(row);
    });

    repository = _ProbePartnershipRepository(client);
  });

  test('logout drops A\'s cached partnership, so B queries the server',
      () async {
    repository.uid = 1;
    final a = await repository.getActivePartnership();

    expect(a?['partner_display_name'], 'Alex');
    expect(queries, 1);

    await AuthState(authRepo: _NoopAuthRepository()).logout();
    repository.uid = 2;

    final b = await repository.getActivePartnership();

    expect(queries, 2);
    expect(b?['partnership_id'], 9002);
    expect(b?['partner_id'], 8);
    expect(b?['partner_display_name'], 'Bea');
  });

  test('an account change without logout never returns the cached future',
      () async {
    repository.uid = 1;
    final a = await repository.getActivePartnership();

    repository.uid = 2;
    final b = await repository.getActivePartnership();

    expect(a?['partner_display_name'], 'Alex');
    expect(queries, 2);
    expect(b?['partner_display_name'], 'Bea');
  });

  test('the same user keeps reusing the cached future', () async {
    repository.uid = 1;

    final first = await repository.getActivePartnership();
    final second = await repository.getActivePartnership();

    expect(queries, 1);
    expect(second, same(first));
  });
}
