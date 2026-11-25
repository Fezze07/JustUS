import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

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

class _TestGameRepository extends GameRepository {
  _TestGameRepository(this.client) : super(sbClient: client);

  final _MockClient client;
  final List<String> notifications = [];

  @override
  Future<int?> getUserId() async => 42;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async => {
        'partnership_id': 9001,
        'partner_id': 77,
        'partner_display_name': 'Claretta',
      };

  @override
  Future<void> notifyPartnerOnce({
    required String notificationKey,
    Map<String, String> params = const {},
  }) async {
    notifications.add(notificationKey);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'app_locale': 'en',
      'username': 'Fede',
    });
  });

  group('GameRepository.fetchNewGameQuestion', () {
    test('notifies partner when RPC creates a new question', () async {
      final client = _MockClient();
      when(() => client.rpc('game_get_or_create_question', params: {
            'p_partnership_id': 9001,
            'p_locales': ['en', 'it'],
          })).thenAnswer((_) => _FakeRpc({
            'id': 501,
            'question_code': 'q_001',
            'question': 'Who cooks better?',
            'status': 'pending',
            'user_id_a': 42,
            'user_id_b': 77,
            'created': true,
            'has_answered': false,
            'partner_answered': false,
          }));

      final repo = _TestGameRepository(client);
      final result = await repo.fetchNewGameQuestion();

      final q = result.valueOrNull;
      expect(q, isNotNull);
      expect(q!.id, 501);
      expect(q.questionCode, 'q_001');
      expect(q.question, 'Who cooks better?');
      expect(q.optionA, 'Fede');
      expect(q.optionB, 'Claretta');
      expect(q.hasAnswered, isFalse);
      expect(q.partnerAnswered, isFalse);
      expect(repo.notifications, ['newQuestion']);
    });

    test('returns existing active question without notifying when created=false',
        () async {
      final client = _MockClient();
      when(() => client.rpc('game_get_or_create_question', params: {
            'p_partnership_id': 9001,
            'p_locales': ['en', 'it'],
          })).thenAnswer((_) => _FakeRpc({
            'id': 501,
            'question_code': 'q_001',
            'question': 'Who cooks better?',
            'status': 'pending',
            'user_id_a': 77,
            'user_id_b': 42,
            'created': false,
            'has_answered': false,
            'partner_answered': true,
          }));

      final repo = _TestGameRepository(client);
      final result = await repo.fetchNewGameQuestion();

      final q = result.valueOrNull;
      expect(q, isNotNull);
      expect(q!.id, 501);
      expect(q.optionA, 'Claretta');
      expect(q.optionB, 'Fede');
      expect(q.partnerAnswered, isTrue);
      expect(repo.notifications, isEmpty);
    });

    test('returns Success(null) when RPC returns null (empty catalog)',
        () async {
      final client = _MockClient();
      when(() => client.rpc('game_get_or_create_question', params: {
            'p_partnership_id': 9001,
            'p_locales': ['en', 'it'],
          })).thenAnswer((_) => _FakeRpc(null));

      final repo = _TestGameRepository(client);
      final result = await repo.fetchNewGameQuestion();

      expect(result, isA<Success<GameNewQuestionResponse?>>());
      expect(result.valueOrNull, isNull);
      expect(repo.notifications, isEmpty);
    });
  });
}
