import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

/// Answers handed to `await`: the builders are `@immutable`, so the mocks keep
/// them in a holder instead of a field of their own.
class _CannedAnswer {
  sb.PostgrestList Function()? rows;
}

/// `then` is implemented for real (mocktail's canned response never resolves
/// under `await`), so awaiting the builder yields whatever the chain has read.
class _MockFilter extends Mock
    implements sb.PostgrestFilterBuilder<sb.PostgrestList> {
  _MockFilter(this.answer);

  final _CannedAnswer answer;

  @override
  Future<R> then<R>(
    Function(sb.PostgrestList value) onValue, {
    Function? onError,
  }) async {
    try {
      return await onValue(answer.rows?.call() ?? const []) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

class _MockSingle extends Mock
    implements sb.PostgrestTransformBuilder<sb.PostgrestMap?> {}

/// Real `GameRepository` body for `fetchGameHistory`, minus the plumbing that
/// unit tests cannot reach: uid and partnership are canned, so the only real
/// DB queries are `game_answers` + `game_question_bank`.
class _HistoryEngine extends GameRepository {
  _HistoryEngine(this.client) : super(sbClient: client);

  final _MockClient client;

  @override
  Future<int?> getUserId() async => 42;

  @override
  Future<Map<String, dynamic>?> getActivePartnership() async => {
        'partnership_id': 9001,
        'partner_id': 77,
        'partner_display_name': 'Claretta',
      };
}

const _absentCodes = [
  'q_abs_1',
  'q_abs_2',
  'q_abs_3',
  'q_abs_4',
  'q_abs_5',
];

sb.PostgrestList _historyRows() => [
      for (final (index, code) in _absentCodes.indexed)
        {
          'game_id': index + 1,
          'user_id': index.isEven ? 42 : 77,
          'selected_option': (index % 3) + 1,
          'game_questions': {
            'id': index + 1,
            'question_code': code,
            'created_at': '2026-01-0${index + 1}T00:00:00Z',
          },
        },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language_code': 'en'});
    PartnershipRepository.clearPartnershipCache();
  });

  test('with 5 codes absent from the bank only the chain-locale queries run '
      '(G4)', () async {
    final client = _MockClient();
    final answersFrom = _MockFrom();
    final bankFrom = _MockFrom();

    when(() => client.from('game_answers')).thenAnswer((_) => answersFrom);
    when(() => client.from('game_question_bank')).thenAnswer((_) => bankFrom);

    final answersAnswer = _CannedAnswer()..rows = _historyRows;
    final answersFilter = _MockFilter(answersAnswer);
    when(() => answersFrom.select(any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.inFilter(any(), any()))
        .thenAnswer((_) => answersFilter);
    when(() => answersFilter.eq(any(), any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.order(any(), ascending: any(named: 'ascending')))
        .thenAnswer((_) => answersFilter);

    final bankAnswer = _CannedAnswer()..rows = () => const [];
    final bankFilter = _MockFilter(bankAnswer);
    final bankLocales = <String>[];
    final bankCodeFilters = <List<String>>[];
    var perCodeEqCalls = 0;
    var perCodeMaybeSingleCalls = 0;
    when(() => bankFrom.select(any())).thenAnswer((_) => bankFilter);
    when(() => bankFilter.inFilter('question_code', any()))
        .thenAnswer((invocation) {
      bankCodeFilters.add(invocation.positionalArguments[1] as List<String>);
      return bankFilter;
    });
    when(() => bankFilter.eq('locale', any())).thenAnswer((invocation) {
      bankLocales.add(invocation.positionalArguments[1] as String);
      return bankFilter;
    });
    when(() => bankFilter.eq('question_code', any())).thenAnswer((_) {
      perCodeEqCalls++;
      return bankFilter;
    });
    when(() => bankFilter.maybeSingle()).thenAnswer((_) {
      perCodeMaybeSingleCalls++;
      return _MockSingle();
    });

    final result = await _HistoryEngine(client).fetchGameHistory();

    final history = result.valueOrNull!;
    expect(history, hasLength(_absentCodes.length));
    expect(
      history.map((h) => h.questionId).toSet(),
      Iterable.generate(_absentCodes.length, (i) => i + 1).toSet(),
    );
    // Absent codes resolve to the empty string, never to a thrown error.
    expect(history.map((h) => h.question), everyElement(isEmpty));
    // One `inFilter` column filter per chain-locale query — nothing more.
    expect(bankCodeFilters, hasLength(2));
    // Only the requested codes are filtered — no full-catalog downloads.
    expect(bankCodeFilters[0].toSet(), _absentCodes.toSet());
    expect(bankCodeFilters[1].toSet(), _absentCodes.toSet());
    // No per-code resolution: the legacy `(question_code, locale)` + retry
    // exhausts, which the G4 fix removed.
    expect(perCodeEqCalls, 0);
    expect(perCodeMaybeSingleCalls, 0);
    expect(bankLocales, ['en', 'it']);
  });

  test('a fallback-only translation resolves texts from the chain without '
      'per-code queries (G4)', () async {
    final client = _MockClient();
    final answersFrom = _MockFrom();
    final bankFrom = _MockFrom();

    when(() => client.from('game_answers')).thenAnswer((_) => answersFrom);
    when(() => client.from('game_question_bank')).thenAnswer((_) => bankFrom);

    final answersAnswer = _CannedAnswer()..rows = _historyRows;
    final answersFilter = _MockFilter(answersAnswer);
    when(() => answersFrom.select(any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.inFilter(any(), any()))
        .thenAnswer((_) => answersFilter);
    when(() => answersFilter.eq(any(), any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.order(any(), ascending: any(named: 'ascending')))
        .thenAnswer((_) => answersFilter);

    final bankLocales = <String>[];
    final bankAnswer = _CannedAnswer()
      ..rows = () => bankLocales.lastOrNull == 'it'
          ? [
              for (final code in _absentCodes)
                {'question_code': code, 'text': 'Domanda $code'},
            ]
          : const [];
    final bankFilter = _MockFilter(bankAnswer);
    var perCodeMaybeSingleCalls = 0;
    when(() => bankFrom.select(any())).thenAnswer((_) => bankFilter);
    when(() => bankFilter.inFilter('question_code', any()))
        .thenAnswer((_) => bankFilter);
    when(() => bankFilter.eq('locale', any())).thenAnswer((invocation) {
      bankLocales.add(invocation.positionalArguments[1] as String);
      return bankFilter;
    });
    when(() => bankFilter.maybeSingle()).thenAnswer((_) {
      perCodeMaybeSingleCalls++;
      return _MockSingle();
    });

    final result = await _HistoryEngine(client).fetchGameHistory();

    final history = result.valueOrNull!;
    expect(history, hasLength(_absentCodes.length));
    expect(
      history.map((h) => h.question).toSet(),
      _absentCodes.map((code) => 'Domanda $code').toSet(),
    );
    expect(bankLocales, ['en', 'it']);
    expect(perCodeMaybeSingleCalls, 0);
  });

  test('a fully translated primary locale stops after a single bank query '
      '(G4)', () async {
    final client = _MockClient();
    final answersFrom = _MockFrom();
    final bankFrom = _MockFrom();

    when(() => client.from('game_answers')).thenAnswer((_) => answersFrom);
    when(() => client.from('game_question_bank')).thenAnswer((_) => bankFrom);

    final answersAnswer = _CannedAnswer()..rows = _historyRows;
    final answersFilter = _MockFilter(answersAnswer);
    when(() => answersFrom.select(any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.inFilter(any(), any()))
        .thenAnswer((_) => answersFilter);
    when(() => answersFilter.eq(any(), any())).thenAnswer((_) => answersFilter);
    when(() => answersFilter.order(any(), ascending: any(named: 'ascending')))
        .thenAnswer((_) => answersFilter);

    final bankLocales = <String>[];
    final bankAnswer = _CannedAnswer()
      ..rows = () => [
            for (final code in _absentCodes)
              {'question_code': code, 'text': 'Question $code'},
          ];
    final bankFilter = _MockFilter(bankAnswer);
    when(() => bankFrom.select(any())).thenAnswer((_) => bankFilter);
    when(() => bankFilter.inFilter('question_code', any()))
        .thenAnswer((_) => bankFilter);
    when(() => bankFilter.eq('locale', any())).thenAnswer((invocation) {
      bankLocales.add(invocation.positionalArguments[1] as String);
      return bankFilter;
    });

    final result = await _HistoryEngine(client).fetchGameHistory();

    final history = result.valueOrNull!;
    expect(
      history.map((h) => h.question).toSet(),
      _absentCodes.map((code) => 'Question $code').toSet(),
    );
    // Everything resolved in `en`: the chain stops before `it`.
    expect(bankLocales, ['en']);
  });
}