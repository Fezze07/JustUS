// app_error.dart
// Modello centralizzato per gli errori dell'applicazione.
// Creato sia a partire dalle risposte API che da eccezioni locali.

import 'dart:async';
import 'dart:io';

import 'package:justus/all_imports.dart';

class AppError implements Exception {
  /// Codice strutturato (es. "AUTH-FAIL-001")
  final String code;

  /// Messaggio tecnico (usato in debug)
  final String message;

  /// Dettagli aggiuntivi (es. issues di validazione)
  final dynamic details;

  /// ID della request backend per correlazione
  final String? requestId;

  /// Severità dell'errore
  final ErrorSeverity severity;

  const AppError({
    required this.code,
    required this.message,
    this.details,
    this.requestId,
    this.severity = ErrorSeverity.low,
  });

  // ---------------------------------------------------------------------------
  // Factory costruttori
  // ---------------------------------------------------------------------------

  /// Crea un AppError da una risposta JSON del backend.
  /// Struttura attesa: { "success": false, "request_id": "...", "error": { "code": "...", "message": "..." } }
  factory AppError.fromJson(Map<String, dynamic> json) {
    final errorObj = json['error'];
    if (errorObj is Map<String, dynamic>) {
      return AppError(
        code: errorObj['code']?.toString() ?? ErrorCodes.localParseError,
        message: errorObj['message']?.toString() ?? 'Unknown error',
        details: errorObj['details'],
        requestId: json['request_id']?.toString(),
        severity: _parseSeverity(errorObj['severity']?.toString()),
      );
    }

    // Fallback: backend ha restituito un errore in formato non standard
    return AppError(
      code: ErrorCodes.localParseError,
      message: errorObj?.toString() ?? 'Malformed error response',
    );
  }

  /// Crea un AppError generico da una eccezione Dart qualsiasi.
  factory AppError.fromException(Object err, [String? code]) {
    if (err is AppError) return err;

    String finalCode = code ?? ErrorCodes.localUnknown;

    if (err is TimeoutException) {
      finalCode = ErrorCodes.localTimeout001;
    } else if (err is SocketException || err is HttpException) {
      finalCode = ErrorCodes.localNetworkError;
    }

    return AppError(
      code: finalCode,
      message: err.toString(),
      severity: ErrorSeverity.medium,
    );
  }

  /// Crea un errore di rete locale (es. SocketException)
  factory AppError.network() => const AppError(
        code: ErrorCodes.localNetworkError,
        message: 'Network unavailable',
        severity: ErrorSeverity.medium,
      );

  /// Crea un errore di timeout locale
  factory AppError.timeout() => const AppError(
        code: ErrorCodes.localTimeout001,
        message: 'Operation timed out',
        severity: ErrorSeverity.medium,
      );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Messaggio da mostrare all'utente in produzione (user-friendly, senza dati tecnici)
  String userMessage(AppLocalizations loc) => ErrorCodes.userMessage(code, loc);

  /// L'errore richiede reautenticazione?
  bool get requiresReauth => ErrorCodes.requiresReauth(code);

  /// L'errore è critico (mostrare Dialog, non Snackbar)?
  bool get isCritical => ErrorCodes.isCritical(code);

  @override
  String toString() => 'AppError($code): $message';

  static ErrorSeverity _parseSeverity(String? s) {
    switch (s?.toUpperCase()) {
      case 'CRITICAL':
        return ErrorSeverity.critical;
      case 'HIGH':
        return ErrorSeverity.high;
      case 'MEDIUM':
        return ErrorSeverity.medium;
      default:
        return ErrorSeverity.low;
    }
  }
}

/// Severità del log (specchio dei livelli backend)
enum ErrorSeverity { low, medium, high, critical }
