// =============================================================================
// ErrorDialog - Standard error reporting dialog
// =============================================================================

import 'package:flutter/material.dart';

class ErrorDialog extends StatelessWidget {
  final String message;
  final String title;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.message,
    this.title = 'Errore',
    this.onRetry,
  });

  static Future<void> show(
    BuildContext context, {
    required String message,
    String title = 'Errore',
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        message: message,
        title: title,
        onRetry: onRetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
        if (onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry!();
            },
            child: const Text('Riprova'),
          ),
      ],
    );
  }
}
