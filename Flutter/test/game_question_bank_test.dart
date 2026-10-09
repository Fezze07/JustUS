import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

void main() {
  group('GameQuestionBankItem Model Tests', () {
    test('fromJson and toJson correctly process game question bank data', () {
      final json = {
        'question_code': 'game_q_000001',
        'locale': 'it',
        'text': 'Qual è il mio piatto preferito?',
      };

      final item = GameQuestionBankItem.fromJson(json);

      expect(item.questionCode, 'game_q_000001');
      expect(item.locale, 'it');
      expect(item.text, 'Qual è il mio piatto preferito?');
    });
  });

  group('GameNewQuestionResponse with questionCode', () {
    test('handles questionCode field correctly', () {
      final json = {
        'success': true,
        'id': 12,
        'question': 'Who is more romantic?',
        'question_code': 'game_q_000002',
        'optionA': 'User A',
        'optionB': 'User B',
        'userIdA': 10,
        'userIdB': 20,
        'status': 'pending',
      };

      final response = GameNewQuestionResponse.fromJson(json);

      expect(response.id, 12);
      expect(response.questionCode, 'game_q_000002');
      expect(response.question, 'Who is more romantic?');

      final updated = response.copyWith(status: 'waiting');
      expect(updated.questionCode, 'game_q_000002');
      expect(updated.status, 'waiting');
    });
  });
}
