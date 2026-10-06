import 'dart:math';

import 'package:justus/all_imports.dart';

class GameQuestionBankRepository extends BaseRepository {
  GameQuestionBankRepository({super.sbClient});

  static const _kColumns =
      'question_code, locale, text, created_at, updated_at';

  /// Recupera tutte le domande disponibili dal catalogo per un determinato locale (es: 'it', 'en').
  Future<ResultWrapper<List<GameQuestionBankItem>>> fetchQuestionsByLocale(
      String locale) async {
    return tryCall(() async {
      final data = await sbClient
          .from('game_question_bank')
          .select(_kColumns)
          .eq('locale', locale)
          .toList();

      return data.map((q) => GameQuestionBankItem.fromJson(q)).toList();
    });
  }

  /// Recupera il testo di una specifica domanda data la coppia (questionCode, locale).
  /// Se il locale richiesto non ha righe si riprova sul locale predefinito
  /// dell'app, così una lingua non ancora tradotta non lascia testi vuoti.
  Future<ResultWrapper<String?>> fetchQuestionText({
    required String questionCode,
    required String locale,
  }) async {
    return tryCall(() async {
      for (final localeCode in LanguageHelper.localeChain(locale)) {
        final data = await sbClient
            .from('game_question_bank')
            .select('text')
            .eq('question_code', questionCode)
            .eq('locale', localeCode)
            .maybeSingle();

        final text = data?['text'] as String?;
        if (text != null && text.isNotEmpty) return text;
      }

      return null;
    });
  }

  /// Seleziona una nuova domanda per una partita.
  /// Può escludere codici di domande già giocate se forniti in [excludeQuestionCodes].
  /// Prova prima il locale richiesto e, se non resta nulla, il locale
  /// predefinito dell'app.
  Future<ResultWrapper<GameQuestionBankItem>> pickQuestionForGame({
    required String locale,
    List<String> excludeQuestionCodes = const [],
  }) async {
    return tryCall(() async {
      final excludeSet = excludeQuestionCodes.toSet();

      for (final localeCode in LanguageHelper.localeChain(locale)) {
        final bankItem = await _pickFromLocale(localeCode, excludeSet);
        if (bankItem != null) return bankItem;
      }

      throw Exception(
          'Nessuna domanda trovata nel catalogo (locale richiesto: $locale)');
    });
  }

  /// Recupera tutte le domande per [locale] e ne sceglie una casuale
  /// escludendo i codici in [excludeSet] lato client.
  /// Se dopo il filtro non resta nulla (tutte già giocate) sceglie
  /// dall'intero pool del locale, senza una seconda chiamata al DB.
  Future<GameQuestionBankItem?> _pickFromLocale(
    String locale,
    Set<String> excludeSet,
  ) async {
    final rows = await sbClient
        .from('game_question_bank')
        .select(_kColumns)
        .eq('locale', locale)
        .toList();

    if (rows.isEmpty) return null;

    // Filtra lato client; se esclude tutto, usa l'intero pool (fallback).
    final candidates = excludeSet.isEmpty
        ? rows
        : rows.where((r) => !excludeSet.contains(r['question_code'])).toList();

    final pool = candidates.isNotEmpty ? candidates : rows;
    return GameQuestionBankItem.fromJson(pool[Random().nextInt(pool.length)]);
  }
}
