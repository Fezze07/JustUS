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

  /// Recupera i testi per i [codes] dati camminando la catena dei locale
  /// dell'app una sola volta (es: 'en' → 'it'), filtrando per locale (1+N).
  /// Interrompe appena tutti i codici sono risolti; i codici che nessun locale
  /// traduce non compaiono nel risultato. Sostituisce il vecchio rifetch
  /// per-codice del path history.
  Future<ResultWrapper<Map<String, String>>> fetchTextsForCodes({
    required Set<String> codes,
    required String locale,
  }) async {
    return tryCall(() async {
      final texts = <String, String>{};
      var pending = codes;
      if (pending.isEmpty) return texts;

      for (final localeCode in LanguageHelper.localeChain(locale)) {
        if (pending.isEmpty) break;

        final data = await sbClient
            .from('game_question_bank')
            .select('question_code, text')
            .inFilter('question_code', pending.toList())
            .eq('locale', localeCode)
            .toList();

        for (final row in data) {
          final code = row['question_code'] as String?;
          final text = row['text'] as String?;
          if (code != null && text != null && text.isNotEmpty) {
            texts[code] = text;
          }
        }

        pending = pending.difference(texts.keys.toSet());
      }

      return texts;
    });
  }

  /// Seleziona una nuova domanda per una partita.
  /// Può escludere codici di domande già giocate se forniti in [excludeQuestionCodes].
  /// Prova prima il locale richiesto e, se non resta nulla, il locale
  /// predefinito dell'app.
  Future<ResultWrapper<GameQuestionBankItem?>> pickQuestionForGame({
    required String locale,
    List<String> excludeQuestionCodes = const [],
  }) async {
    return tryCall(() async {
      final excludeSet = excludeQuestionCodes.toSet();

      for (final localeCode in LanguageHelper.localeChain(locale)) {
        final bankItem = await _pickFromLocale(localeCode, excludeSet);
        if (bankItem != null) return bankItem;
      }

      return null;
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
    final res = await fetchQuestionsByLocale(locale);
    final items = switch (res) {
      Success(value: final v) => v,
      GenericError(:final message) =>
        throw Exception('Failed to fetch questions by locale: $message'),
      NetworkError(:final message) =>
        throw Exception('Network error fetching questions by locale: $message'),
    };

    if (items.isEmpty) return null;

    // Filtra lato client; se esclude tutto, usa l'intero pool (fallback).
    final candidates = excludeSet.isEmpty
        ? items
        : items.where((i) => !excludeSet.contains(i.questionCode)).toList();

    final pool = candidates.isNotEmpty ? candidates : items;
    return pool[Random().nextInt(pool.length)];
  }
}
