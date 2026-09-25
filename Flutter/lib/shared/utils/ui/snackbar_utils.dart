import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class UIUtils {
  /// Mostra una SnackBar con logica speciale per il Debug:
  /// Se siamo in debug e c'è un errore, la SnackBar non si chiude finché l'utente non preme "CHIUDI".
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    Color? backgroundColor,
  }) {
    showSnackBarOn(
      ScaffoldMessenger.of(context),
      message,
      isError: isError,
      backgroundColor: backgroundColor,
      closeLabel: context.loc.common_close,
    );
  }

  /// Come [showSnackBar] ma mostra la SnackBar su un messenger esplicito.
  /// Serve per mostrare il feedback DOPO che la route che lo ha generato è
  /// già stata chiusa (es. successo + `Navigator.pop`): il messenger di root
  /// sopravvive al pop, mentre il suo BuildContext no.
  static void showSnackBarOn(
    ScaffoldMessengerState messenger,
    String message, {
    bool isError = false,
    Color? backgroundColor,
    required String closeLabel,
  }) {
    final snackBar = SnackBar(
      content: Text(message, key: UniqueKey()),
      backgroundColor:
          backgroundColor ?? (isError ? AppColors.dangerSurface : null),
      behavior: SnackBarBehavior.floating,
      duration: (isError && kDebugMode)
          ? const Duration(days: 365)
          : const Duration(seconds: 4),
      action: (isError && kDebugMode)
          ? SnackBarAction(
              label: closeLabel,
              textColor: AppColors.contentPrimary,
              onPressed: () {
                messenger.hideCurrentSnackBar();
              },
            )
          : null,
    );

    // Rimuove immediatamente eventuali snackbar precedenti per evitare
    // conflitti di Hero tag (hideCurrentSnackBar lascia l'Hero in fade-out)
    messenger.clearSnackBars();
    messenger.showSnackBar(snackBar);
  }
}
