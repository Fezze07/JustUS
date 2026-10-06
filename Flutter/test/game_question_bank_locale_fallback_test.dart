import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:justus/all_imports.dart';

class _MockClient extends Mock implements sb.SupabaseClient {}

class _MockFrom extends Mock implements sb.SupabaseQueryBuilder {}

/// Answers handed to `await`: the builders are `@immutable`, so the mocks keep
/// them in a holder instead of a field of their own.
class _CannedAnswer {
  sb.PostgrestList Function()? rows;
  sb.PostgrestMap? Function()? row;
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
    implements sb.PostgrestTransformBuilder<sb.PostgrestMap?> {
  _MockSingle(this.answer);

  final _CannedAnswer answer;

  @override
  Future<R> then<R>(
    Function(sb.PostgrestMap? value) onValue, {
    Function? onError,
  }) async {
    try {
      return await onValue(answer.row?.call()) as R;
    } catch (error, stackTrace) {
      if (onError == null) rethrow;
      return onError(error, stackTrace) as R;
    }
  }
}

/// The bank query chain exactly as the repository issues it —
/// `from().select().eq(…)` — recording the locales it asks for, so a test can
/// answer differently for `en` (missing translation) and `it` (translated).
class _BankChain {
  _BankChain() {
    filter = _MockFilter(answer);
    single = _MockSingle(answer);

    when(() => client.from('game_question_bank')).thenAnswer((_) => from);
    when(() => from.select(any())).thenAnswer((_) => filter);

    when(() => filter.eq('question_code', any())).thenAnswer((_) => filter);
    when(() => filter.eq('locale', 'en')).thenAnswer((_) {
      locales.add('en');
      return filter;
    });
    when(() => filter.eq('locale', 'it')).thenAnswer((_) {
      locales.add('it');
      return filter;
    });
    when(() => filter.maybeSingle()).thenAnswer((_) => single);

    answer.rows = () => rowsFor(locales.last);
    answer.row = () => textFor(locales.last);
  }

  final _MockClient client = _MockClient();
  final _MockFrom from = _MockFrom();
  final _CannedAnswer answer = _CannedAnswer();
  late final _MockFilter filter;
  late final _MockSingle single;

  /// Locales queried, in order — the fallback is observable through it.
  final List<String> locales = [];

  sb.PostgrestList Function(String locale) rowsFor = (_) => const [];
  sb.PostgrestMap? Function(String locale) textFor = (_) => null;
}

void main() {
  group('LanguageHelper.localeChain', () {
    test('keeps a supported requested locale and appends the app default', () {
      expect(LanguageHelper.localeChain('it'), ['it']);
      expect(LanguageHelper.localeChain('en'), ['en', 'it']);
    });

    test('an unknown or empty code degrades to the app default', () {
      expect(LanguageHelper.localeChain(''), ['it']);
      expect(LanguageHelper.localeChain('fr'), ['it']);
    });
  });

  group('the catalog is only partly translated (bank = it, app = en)', () {
    test('fetchQuestionText falls back to the app default locale', () async {
      final chain = _BankChain()
        ..textFor = (locale) => locale == 'it'
            ? {'text': 'Qual è il mio piatto preferito?'}
            : null;

      final repo = GameQuestionBankRepository(sbClient: chain.client);
      final result = await repo.fetchQuestionText(
        questionCode: 'game_q_000001',
        locale: 'en',
      );

      expect(result.valueOrNull, 'Qual è il mio piatto preferito?');
      expect(chain.locales, ['en', 'it']);
    });

    test('fetchQuestionText does not query the fallback when translated',
        () async {
      final chain = _BankChain()
        ..textFor = (locale) =>
            locale == 'en' ? {'text': 'English text'} : null;

      final repo = GameQuestionBankRepository(sbClient: chain.client);
      final result = await repo.fetchQuestionText(
        questionCode: 'game_q_000001',
        locale: 'en',
      );

      expect(result.valueOrNull, 'English text');
      expect(chain.locales, ['en']);
    });

    test('fetchQuestionText stays null when no locale has the text', () async {
      final chain = _BankChain();

      final repo = GameQuestionBankRepository(sbClient: chain.client);
      final result = await repo.fetchQuestionText(
        questionCode: 'game_q_999999',
        locale: 'en',
      );

      expect(result.valueOrNull, isNull);
      expect(chain.locales, ['en', 'it']);
    });

    test('pickQuestionForGame picks from the fallback locale instead of '
        'throwing', () async {
      final chain = _BankChain()
        ..rowsFor = (locale) => locale == 'it'
            ? [
                {
                  'question_code': 'game_q_000001',
                  'locale': 'it',
                  'text': 'Domanda italiana',
                  'created_at': '2026-10-06T10:00:00Z',
                  'updated_at': '2026-10-06T10:00:00Z',
                },
              ]
            : const [];

      final repo = GameQuestionBankRepository(sbClient: chain.client);
      final result = await repo.pickQuestionForGame(locale: 'en');

      final bankItem = result.valueOrNull;
      expect(bankItem, isNotNull);
      expect(bankItem!.text, 'Domanda italiana');
      expect(bankItem.locale, 'it');
      expect(chain.locales, ['en', 'it']);
    });

    test('pickQuestionForGame still throws when no locale has any row',
        () async {
      final chain = _BankChain();

      final repo = GameQuestionBankRepository(sbClient: chain.client);
      final result = await repo.pickQuestionForGame(locale: 'en');

      expect(result.valueOrNull, isNull);
      expect(result, isA<GenericError<GameQuestionBankItem>>());
      expect(chain.locales, ['en', 'it']);
    });
  });
}
