// error_handler.dart
// Sistema centralizzato di gestione errori per l'intera app Flutter.
//
// Responsabilità:
//   1. Convertire qualsiasi eccezione/risposta API in AppError
//   2. Log differenziato: Debug → completo, Produzione → minimo
//   3. Mostrare la UI corretta (Snackbar / Dialog / full screen)
//   4. Gestire reautenticazione automatica se necessario
//
// Utilizzo:
//   ErrorHandler.handle(err, context: context);           // dal catch
//   ErrorHandler.handleGlobal(err, stackTrace);           // da runZonedGuarded / FlutterError.onError

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:justus/all_imports.dart';

class ErrorHandler {
  ErrorHandler._();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static OverlayEntry? _currentOverlay;

  /// Gestisce un errore con contesto (per UI).
  static void handle(
    Object error, {
    BuildContext? context,
    StackTrace? stackTrace,
    bool showUI = true,
  }) {
    final appError = _toAppError(error);
    _log(appError, stackTrace);

    if (showUI) {
      final ctx = context ?? navigatorKey.currentContext;
      if (ctx != null) {
        _showUI(ctx, appError);
      }
    }
  }

  /// Gestisce errori globali (zona / FlutterError) — senza BuildContext.
  static void handleGlobal(Object error, StackTrace stackTrace) {
    final appError = _toAppError(error);
    _log(appError, stackTrace);

    // Prova a mostrare UI se c'è un contesto disponibile.
    // Defer always to post-frame: handleGlobal is called by FlutterError.onError
    // which fires during the build phase — inserting into Overlay during build crashes.
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ctx.mounted) _showUI(ctx, appError);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Conversione → AppError
  // ---------------------------------------------------------------------------

  static AppError _toAppError(Object error) {
    if (error is AppError) return error;
    
    if (error is GenericError) {
      if (error.details is AppError) {
        return error.details as AppError;
      }

      return AppError(
        code: error.code?.toString() ?? ErrorCodes.localUnknown,
        message: error.message ?? 'Unknown API error',
      );
    }

    // Errori Supabase Auth
    if (error is AuthException) {
      return AppError(
        code: ErrorCodes.authFail001,
        message: error.message,
        severity: ErrorSeverity.high,
      );
    }

    // Errori Supabase Postgres / DB
    if (error is PostgrestException) {
      if (error.code == '404' || error.message.contains('not found')) {
        return AppError(code: ErrorCodes.dbNotFound001, message: error.message);
      }
      if (error.code?.startsWith('23') ?? false) {
        return AppError(code: ErrorCodes.dbWrite001, message: error.message, severity: ErrorSeverity.medium);
      }

      return AppError(code: ErrorCodes.dbRead001, message: error.message, severity: ErrorSeverity.medium);
    }

    // Errori di rete
    if (error is SocketException || error is HttpException) {
      return AppError.network();
    }

    if (error is TimeoutException) {
      return AppError.timeout();
    }

    // Fallback generico
    return AppError.fromException(error);
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  static void _log(AppError err, StackTrace? stackTrace) {
    if (kDebugMode) {
      // In debug: log completo con codice, messaggio, dettagli e stack
      debugPrint('┌── AppError ──────────────────────────────');
      debugPrint('│  code:     ${err.code}');
      debugPrint('│  message:  ${err.message}');
      if (err.requestId != null) debugPrint('│  req_id:   ${err.requestId}');
      if (err.details != null)   debugPrint('│  details:  ${err.details}');
      if (stackTrace != null)    debugPrint('│  stack:\n$stackTrace');
      debugPrint('└──────────────────────────────────────────');
    } else {
      // In produzione: log minimo (nessun dato sensibile o stack)
      debugPrint('[ERROR] ${err.code}: ${err.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  static void _showUI(BuildContext context, AppError err) {
    final message = kDebugMode
        ? '[${err.code}] ${err.message}'   // debug: tecnico
        : err.userMessage(context.loc);                  // produzione: user-friendly

    if (err.requiresReauth) {
      _showReauthDialog(context, err);
    } else if (err.isCritical) {
      _showErrorDialog(context, err, message);
    } else {
      _showSnackBar(context, message);
    }
  }

  // ---- Snackbar (errori lievi) tramite Overlay globale -----------------------
  static void _showSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;

    // Guard: if called during a build/layout/paint phase, defer to next frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    final isMidBuild = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks;
    if (isMidBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _showSnackBar(context, message);
      });
      return;
    }

    // Rimuoviamo l'eventuale toast precedente
    _currentOverlay?.remove();
    _currentOverlay = null;

    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        // Calcola il bottom includendo la tastiera
        final bottomOffset = MediaQuery.viewInsetsOf(context).bottom + 40;
        
        return Positioned(
          bottom: bottomOffset,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.shade800,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message, 
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  if (kDebugMode)
                    TextButton(
                      onPressed: () {
                        if (entry.mounted) {
                          entry.remove();
                          if (_currentOverlay == entry) _currentOverlay = null;
                        }
                      },
                      child: Text(context.loc.common_close.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    _currentOverlay = entry;
    overlay.insert(entry);

    // Rimozione automatica
    if (!kDebugMode) {
      Future.delayed(const Duration(seconds: 4), () {
        if (entry.mounted) {
          entry.remove();
          if (_currentOverlay == entry) _currentOverlay = null;
        }
      });
    }
  }

  // ---- Dialog (errori critici) -----------------------------------------------
  static void _showErrorDialog(BuildContext context, AppError err, String message) {
    if (!context.mounted) return;
    DialogUtils.showError(
      context, 
      message, 
      errorCode: err.code,
      details: err.details?.toString()
    );
  }

  // ---- Dialog di reautenticazione --------------------------------------------
  static void _showReauthDialog(BuildContext context, AppError err) {
    if (!context.mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.loc.error_reauthTitle),
        content: Text(kDebugMode ? '[${err.code}] ${err.message}' : err.userMessage(ctx.loc)),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Naviga al login — l'AuthState gestirà il logout vero e proprio
              final future = navigatorKey.currentState?.pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
              if (future != null) unawaited(future);
            },
            child: Text(ctx.loc.error_reauthAction),
          ),
        ],
      ),
    ));
  }

  // ---------------------------------------------------------------------------
  // Static helper per usarlo inline (throwOnError)
  // ---------------------------------------------------------------------------

  /// Lancia un AppError se il record Supabase contiene un errore.
  static T throwOnError<T>({
    required T? data,
    required dynamic error,
    String errorKey = 'DB_READ_001',
  }) {
    if (error != null) {
      throw AppError.fromException(error as Object, ErrorCodes.dbRead001);
    }
    if (data == null) {
      throw const AppError(code: ErrorCodes.dbNotFound001, message: 'No data returned');
    }

    return data;
  }
}
