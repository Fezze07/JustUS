import 'package:justus/all_imports.dart';

class GameQuestionBankRepository extends BaseRepository {
  GameQuestionBankRepository({super.sbClient});

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

  /// Seleziona una nuova domanda per una partita tramite la RPC
  /// `game_pick_question`: il DB restituisce una sola riga del locale
  /// richiesto, preferendo i codici non ancora giocati dalla coppia.
  Future<ResultWrapper<GameQuestionBankItem?>> pickQuestionForGame({
    required int partnershipId,
    required String locale,
  }) async {
    return tryCall(() async {
      final row = await sbClient.rpc('game_pick_question', params: {
        'p_partnership_id': partnershipId,
        'p_locales': LanguageHelper.localeChain(locale),
      });

      if (row == null) return null;
      return GameQuestionBankItem.fromJson(row as Map<String, dynamic>);
    });
  }
}
