// error_codes.dart
// Costanti per tutti i codici di errore riconosciuti lato client.
// Devono rispecchiare esattamente i codici emessi dal backend.

class ErrorCodes {
  ErrorCodes._();

  // AUTH
  static const String authFail001       = 'AUTH-FAIL-001'; // Token scaduto / non valido
  static const String authFail002       = 'AUTH-FAIL-002'; // Bearer token mancante
  static const String authFail003       = 'AUTH-FAIL-003'; // Sessione revocata
  static const String authFail004       = 'AUTH-FAIL-004'; // Ruolo non valido
  static const String authFail005       = 'AUTH-FAIL-005'; // Profilo non trovato
  static const String authFail006       = 'AUTH-FAIL-006'; // Device mismatch
  static const String authPermission001 = 'AUTH-PERMISSION-001'; // Capability mancante

  // DB
  static const String dbRead001      = 'DB-READ-001';
  static const String dbWrite001     = 'DB-WRITE-001';
  static const String dbNotFound001  = 'DB-NOT_FOUND-001';
  static const String dbTimeout001   = 'DB-TIMEOUT-001';

  // API
  static const String apiValidation001 = 'API-VALIDATION-001';
  static const String apiNotFound001   = 'API-NOT_FOUND-001';
  static const String apiTimeout001    = 'API-TIMEOUT-001';
  static const String apiFail001       = 'API-FAIL-001';

  // SEC
  static const String secBlock001      = 'SEC-BLOCK-001'; // Rate limit / blocco
  static const String secBlock002      = 'SEC-BLOCK-002'; // Login bloccato
  static const String secPermission001 = 'SEC-PERMISSION-001'; // Origine non consentita

  // SYS
  static const String sysFail001 = 'SYS-FAIL-001'; // Errore interno generico

  // Codice locale (non proviene dal backend)
  static const String localNetworkError  = 'LOCAL-NET-001';   // Nessuna connessione
  static const String localTimeout001    = 'LOCAL-TIMEOUT-001'; // Timeout locale
  static const String localParseError    = 'LOCAL-PARSE-001'; // Risposta non parsabile
  static const String localStorageError  = 'LOCAL-STORAGE-001'; // Errore storage locale
  static const String localConfigError   = 'LOCAL-CONFIG-001';  // Errore configurazione
  static const String localMoodDuplicate = 'LOCAL-MOOD-001';  // Emoji già impostata
  static const String localUnknown       = 'LOCAL-UNKNOWN';   // Errore sconosciuto

  // ---------------------------------------------------------------------------
  // Mappatura codice → messaggio utente (produzione: nessun dettaglio tecnico)
  // ---------------------------------------------------------------------------
  static String userMessage(String code) {
    switch (code) {
      case authFail001:       return 'Sessione scaduta. Effettua di nuovo il login.';
      case authFail002:       return 'Sessione non valida. Effettua il login.';
      case authFail003:       return 'La sessione è stata revocata. Accedi nuovamente.';
      case authFail004:       return 'Accesso non consentito.';
      case authFail005:       return 'Profilo utente non trovato.';
      case authFail006:       return 'Dispositivo non riconosciuto. Accedi di nuovo.';
      case authPermission001: return 'Non hai i permessi per questa operazione.';
      case dbRead001:         return 'Errore durante il caricamento dei dati.';
      case dbWrite001:        return 'Errore durante il salvataggio.';
      case dbNotFound001:     return 'Risorsa non trovata.';
      case dbTimeout001:      return 'Il server è lento. Riprova tra poco.';
      case apiValidation001:  return 'I dati inseriti non sono validi.';
      case apiNotFound001:    return 'Servizio non disponibile.';
      case apiTimeout001:     return 'La richiesta ha impiegato troppo. Riprova.';
      case apiFail001:        return 'Si è verificato un errore. Riprova.';
      case secBlock001:       return 'Troppe richieste. Attendi prima di riprovare.';
      case secBlock002:       return 'Accesso temporaneamente bloccato.';
      case secPermission001:  return 'Accesso negato.';
      case sysFail001:        return 'Errore interno del server.';
      case localNetworkError: return 'Nessuna connessione a Internet.';
      case localTimeout001:   return 'La connessione è troppo lenta. Riprova.';
      case localParseError:   return 'Risposta del server non valida.';
      case localStorageError: return 'Errore nel salvataggio dei dati locali.';
      case localConfigError:  return 'Errore di configurazione dell\'app.';
      case localMoodDuplicate:return 'Hai già impostato questa emoji come mood attuale.';
      default:                return 'Si è verificato un errore imprevisto.';
    }
  }

  /// Restituisce true se il codice indica un errore di autenticazione
  /// che richiede un logout / redirect al login.
  static bool requiresReauth(String code) {
    return code == authFail001 ||
           code == authFail002 ||
           code == authFail003 ||
           code == authFail006;
  }

  /// Restituisce true se l'errore è critico (da mostrare come Dialog)
  static bool isCritical(String code) {
    return requiresReauth(code) ||
           code == secBlock001 ||
           code == secBlock002;
  }
}
