import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockApi extends Mock implements ApiService {}

class _FakeRpc extends Mock implements sb.PostgrestFilterBuilder<dynamic> {
  _FakeRpc(this.result);

  final Object? result;

  @override
  Future<R> then<R>(Function(Object? value) onValue, {Function? onError}) async {
    try {
      return await onValue(result) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  test('PartnershipCancellation maps the read RPC row', () {
    final cancellation = PartnershipCancellation.fromJson({
      'partnership_id': 5,
      'partner_id': 7,
      'partner_display_name': 'Alex',
      'partner_profile_pic_url': 'profile/7/a.jpg',
      'requested_by_me': true,
    });

    expect(cancellation.partnershipId, 5);
    expect(cancellation.partnerId, 7);
    expect(cancellation.partnerDisplayName, 'Alex');
    expect(cancellation.partnerProfilePicUrl, 'profile/7/a.jpg');
    expect(cancellation.requestedByMe, isTrue);
    expect(
      PartnershipCancellation.fromJson({
        'partnership_id': 5,
        'partner_id': 7,
      }).requestedByMe,
      isFalse,
    );
  });

  test('requestCancellation calls partnership_request_cancel', () async {
    final client = _MockClient();
    when(() => client.rpc('partnership_request_cancel',
            params: {'p_partnership_id': 5}))
        .thenAnswer((_) => _FakeRpc(null));
    final repository = PartnershipRepository(sbClient: client);

    final result = await repository.requestCancellation(5);

    expect(result, isA<Success<void>>());
    verify(() => client.rpc('partnership_request_cancel',
        params: {'p_partnership_id': 5})).called(1);
  });

  test('revertCancellation calls partnership_cancel_revert', () async {
    final client = _MockClient();
    when(() => client.rpc('partnership_cancel_revert',
            params: {'p_partnership_id': 5}))
        .thenAnswer((_) => _FakeRpc(null));
    final repository = PartnershipRepository(sbClient: client);

    final result = await repository.revertCancellation(5);

    expect(result, isA<Success<void>>());
    verify(() => client.rpc('partnership_cancel_revert',
        params: {'p_partnership_id': 5})).called(1);
  });

  test('acceptCancellation uses the signed backend call', () async {
    final api = _MockApi();
    when(() => api.acceptPartnershipCancellation(partnershipId: 5))
        .thenAnswer((_) async =>
            const Success<Map<String, dynamic>>(<String, dynamic>{
              'success': true,
            }));
    final repository =
        PartnershipRepository(sbClient: _MockClient(), api: api);

    final result = await repository.acceptCancellation(5);

    expect(result, isA<Success<Map<String, dynamic>>>());
    verify(() => api.acceptPartnershipCancellation(partnershipId: 5))
        .called(1);
  });

  test('getCancellation reads the RPC row and maps a null result', () async {
    final client = _MockClient();
    when(() => client.rpc('partnership_get_cancellation')).thenAnswer(
      (_) => _FakeRpc([
        {
          'partnership_id': 5,
          'partner_id': 7,
          'partner_display_name': 'Alex',
          'partner_profile_pic_url': null,
          'requested_by_me': false,
        }
      ]),
    );
    final repository = PartnershipRepository(sbClient: client);

    final result = await repository.getCancellation();

    expect(result, isA<Success<PartnershipCancellation?>>());
    expect(result.valueOrNull?.partnershipId, 5);
    expect(result.valueOrNull?.requestedByMe, isFalse);

    when(() => client.rpc('partnership_get_cancellation'))
        .thenAnswer((_) => _FakeRpc(<dynamic>[]));
    expect((await repository.getCancellation()).valueOrNull, isNull);

    when(() => client.rpc('partnership_get_cancellation'))
        .thenAnswer((_) => _FakeRpc(null));
    expect((await repository.getCancellation()).valueOrNull, isNull);
  });
}
