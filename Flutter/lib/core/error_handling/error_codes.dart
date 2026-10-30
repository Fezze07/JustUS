// error_codes.dart
// Costanti per tutti i codici di errore riconosciuti lato client.
// Devono rispecchiare esattamente i codici emessi dal backend.

import 'package:justus/all_imports.dart';

class ErrorCodes {
  ErrorCodes._();

  // AUTH
  static const String authFail001 =
      'AUTH-FAIL-001'; // Token scaduto / non valido
  static const String authFail002 = 'AUTH-FAIL-002'; // Bearer token mancante
  static const String authFail004 = 'AUTH-FAIL-004'; // Ruolo non valido
  static const String authFail005 = 'AUTH-FAIL-005'; // Profilo non trovato
  static const String authFail006 = 'AUTH-FAIL-006'; // Device mismatch
  static const String authFailCred = 'AUTH-FAIL-CRED';
  static const String authFailCurrent =
      'AUTH-FAIL-CURRENT'; // Vecchia password errata nel cambio password
  static const String authPermission001 =
      'AUTH-PERMISSION-001'; // Capability mancante

  // DB
  static const String dbRead001 = 'DB-READ-001';
  static const String dbWrite001 = 'DB-WRITE-001';
  static const String dbNotFound001 = 'DB-NOT_FOUND-001';

  // API
  static const String apiValidation001 = 'API-VALIDATION-001';
  static const String apiValidation002 = 'API-VALIDATION-002';
  static const String apiValidation003 = 'API-VALIDATION-003';
  static const String apiValidation004 = 'API-VALIDATION-004';
  static const String apiValidation005 = 'API-VALIDATION-005';
  static const String apiValidation006 = 'API-VALIDATION-006';
  static const String apiValidation007 = 'API-VALIDATION-007';
  static const String apiValidation010 = 'API-VALIDATION-010';
  static const String apiValidation011 = 'API-VALIDATION-011';
  static const String apiValidation012 = 'API-VALIDATION-012';
  static const String apiValidation013 = 'API-VALIDATION-013';
  static const String apiValidation014 = 'API-VALIDATION-014';
  static const String apiNotFound001 = 'API-NOT_FOUND-001';
  static const String apiTimeout001 = 'API-TIMEOUT-001';
  static const String apiFail001 = 'API-FAIL-001';

  // SEC
  static const String secBlock001 = 'SEC-BLOCK-001'; // Rate limit / blocco
  static const String secBlock002 = 'SEC-BLOCK-002'; // Login bloccato
  static const String secAuth001 = 'SEC-AUTH-001'; // Autorizzazione negata
  static const String secAuth002 = 'SEC-AUTH-002'; // Firma richiesta non valida

  // SYS
  static const String sysFail001 = 'SYS-FAIL-001'; // Errore interno generico
  static const String sysTimeout001 = 'SYS-TIMEOUT-001'; // Timeout interno

  // HTTP
  static const String httpUnauthorized = '401';

  // Codice locale (non proviene dal backend)
  static const String localNetworkError =
      'LOCAL-NET-001'; // Nessuna connessione
  static const String localTimeout001 = 'LOCAL-TIMEOUT-001'; // Timeout locale
  static const String localParseError =
      'LOCAL-PARSE-001'; // Risposta non parsabile
  static const String localStorageError =
      'LOCAL-STORAGE-001'; // Errore storage locale
  static const String localConfigError =
      'LOCAL-CONFIG-001'; // Errore configurazione
  static const String localBindingSecretMissing =
      'LOCAL-BINDING-001'; // Secret di firma non disponibile
  static const String localMoodDuplicate =
      'LOCAL-MOOD-001'; // Emoji già impostata
  static const String localUnknown = 'LOCAL-UNKNOWN'; // Errore sconosciuto

  // ---------------------------------------------------------------------------
  // Codici sollevati dalle funzioni RPC del database.
  // Le funzioni fanno `RAISE EXCEPTION '<CODE>: <testo>';` così il codice
  // viaggia nel messaggio Postgres e il testo resta una nota per lo sviluppatore.
  // ---------------------------------------------------------------------------
  static const List<String> serverCodes = [
    apiValidation003,
    apiValidation004,
    apiValidation005,
    apiValidation006,
    apiValidation007,
    apiValidation010,
    apiValidation011,
    apiValidation012,
    apiValidation013,
    apiValidation014,
  ];

  /// Estrae il codice da un messaggio di eccezione del database
  /// (`'API-VALIDATION-006: Cannot invite yourself'`), o `null` se assente.
  static String? resolveServerCode(String? message) {
    final prefix = message?.split(':').first.trim();
    return prefix != null && serverCodes.contains(prefix) ? prefix : null;
  }

  // ---------------------------------------------------------------------------
  // Mappatura codice → messaggio utente localizzato.
  // ---------------------------------------------------------------------------
  static String userMessage(String code, AppLocalizations loc) {
    switch (code) {
      case authFail001:
        return loc.error_authFail001;
      case authFail002:
        return loc.error_authFail002;
      case authFail004:
        return loc.error_authFail004;
      case authFail005:
        return loc.error_authFail005;
      case authFail006:
        return loc.error_authFail006;
      case authFailCred:
        return loc.error_authFailCred;
      case authPermission001:
        return loc.error_authPermission001;
      case dbRead001:
        return loc.error_dbRead001;
      case dbWrite001:
        return loc.error_dbWrite001;
      case dbNotFound001:
        return loc.error_dbNotFound001;
      case apiValidation001:
        return loc.error_apiValidation001;
      case apiValidation002:
        return loc.error_apiValidation002;
      case apiValidation003:
        return loc.error_apiValidation003;
      case apiValidation004:
        return loc.error_apiValidation004;
      case apiValidation005:
        return loc.error_apiValidation005;
      case apiValidation006:
        return loc.error_apiValidation006;
      case apiValidation007:
        return loc.error_apiValidation007;
      case apiValidation010:
        return loc.error_apiValidation010;
      case apiValidation011:
        return loc.error_apiValidation011;
      case apiValidation012:
        return loc.error_apiValidation012;
      case apiValidation013:
        return loc.error_apiValidation013;
      case apiValidation014:
        return loc.error_apiValidation014;
      case apiNotFound001:
        return loc.error_apiNotFound001;
      case apiTimeout001:
        return loc.error_apiTimeout001;
      case apiFail001:
        return loc.error_apiFail001;
      case httpUnauthorized:
        return loc.error_authFail001;
      case secBlock001:
        return loc.error_secBlock001;
      case secBlock002:
        return loc.error_secBlock002;
      case secAuth001:
        return loc.error_secAuth001;
      case secAuth002:
        return loc.error_secAuth002;
      case sysFail001:
        return loc.error_sysFail001;
      case sysTimeout001:
        return loc.error_sysTimeout001;
      case localNetworkError:
        return loc.error_localNetworkError;
      case localTimeout001:
        return loc.error_localTimeout001;
      case localParseError:
        return loc.error_localParseError;
      case localStorageError:
        return loc.error_localStorageError;
      case localConfigError:
        return loc.error_localConfigError;
      case localBindingSecretMissing:
        return loc.error_localBindingSecretMissing;
      case localMoodDuplicate:
        return loc.error_localMoodDuplicate;
      default:
        return loc.error_unknown;
    }
  }

  /// Restituisce true se il codice indica un errore di autenticazione
  /// che richiede un logout / redirect al login.
  static bool requiresReauth(String code) {
    return code == authFail001 ||
        code == authFail002 ||
        code == authFail006 ||
        code == httpUnauthorized;
  }

  /// Restituisce true se l'errore è critico (da mostrare come Dialog)
  static bool isCritical(String code) {
    return requiresReauth(code) || code == secBlock001 || code == secBlock002;
  }
}
