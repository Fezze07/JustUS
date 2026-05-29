import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class UIUtils {
  /// Mostra una SnackBar con logica speciale per il Debug:
  /// Se siamo in debug e c'è un errore, la SnackBar non si chiude finché l'utente non preme "CHIUDI".
  static void showSnackBar(
    BuildContext context, 
    String message, {
    bool isError = false,
    Color? backgroundColor,
  }) {
    final messenger = ScaffoldMessenger.of(context);

    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor ?? (isError ? Colors.red.shade800 : null),
      behavior: SnackBarBehavior.floating,
      duration: (isError && kDebugMode) 
          ? const Duration(days: 365)
          : const Duration(seconds: 4),
      action: (isError && kDebugMode)
          ? SnackBarAction(
              label: 'CHIUDI',
              textColor: Colors.white,
              onPressed: () {
                messenger.hideCurrentSnackBar();
              },
            )
          : null,
    );

    // Pulisce eventuali snackbar precedenti e mostra la nuova
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }
}
