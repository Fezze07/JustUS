import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

import 'test_helpers/mock_secure_storage.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

class _FakeRpc extends Mock implements sb.PostgrestFilterBuilder<dynamic> {
  _FakeRpc(this.result);

  final Object? result;

  @override
  Future<R> then<R>(Function(Object? value) onValue,
      {Function? onError}) async {
    try {
      return await onValue(result) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _FakeUpsert extends Mock
    implements sb.PostgrestFilterBuilder<sb.PostgrestList> {
  @override
  Future<R> then<R>(Function(sb.PostgrestList value) onValue,
      {Function? onError}) async {
    try {
      return await onValue(<Map<String, dynamic>>[]) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _TestDriveRepository extends DriveRepository {
  _TestDriveRepository({required super.sbClient});

  @override
  Future<void> notifyPartnerOnce({
    required String notificationKey,
    Map<String, String> params = const {},
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('20.2: a changed reaction upserts on (user_id, item_id)', () async {
    await StorageService.saveUserId(7);

    final client = _MockClient();
    final from = _MockFrom();
    final upsert = _FakeUpsert();

    when(() => client.rpc('emoji_get_or_create',
            params: {'p_emoji_char': '😂'}))
        .thenAnswer((_) => _FakeRpc(5));
    when(() => client.from('drive_item_reactions')).thenAnswer((_) => from);
    when(() => from.upsert(
          {'item_id': 3, 'user_id': 7, 'emoji_id': 5},
          onConflict: 'user_id,item_id',
        )).thenAnswer((_) => upsert);

    final result =
        await _TestDriveRepository(sbClient: client).addReaction(3, '😂');

    expect(result.isSuccess, isTrue);
    verify(() => from.upsert(
          {'item_id': 3, 'user_id': 7, 'emoji_id': 5},
          onConflict: 'user_id,item_id',
        )).called(1);
  });
}
