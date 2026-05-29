// =============================================================================
// ErrorDialog - Standard error reporting dialog
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ErrorDialog extends StatelessWidget {
  final String message;
  final String title;
  final String? details;
  final String? errorCode;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.message,
    this.title = 'Errore',
    this.details,
    this.errorCode,
    this.onRetry,
  });

  static Future<void> show(
    BuildContext context, {
    required String message,
    String title = 'Errore',
    String? details,
    String? errorCode,
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        message: message,
        title: title,
        details: details,
        errorCode: errorCode,
        onRetry: onRetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (kDebugMode && errorCode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Code: $errorCode',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (kDebugMode && details != null) ...[
              const SizedBox(height: 8),
              Text(
                details!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
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
