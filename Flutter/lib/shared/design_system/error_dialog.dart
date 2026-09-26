// =============================================================================
// ErrorDialog - Standard error reporting dialog
// =============================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:justus/all_imports.dart';

class ErrorDialog extends StatelessWidget {
  final String message;
  final String title;
  final String? details;
  final String? errorCode;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.message,
    this.title = '',
    this.details,
    this.errorCode,
    this.onRetry,
  });

  static Future<void> show(
    BuildContext context, {
    required String message,
    String title = '',
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
    final resolvedTitle = title.isEmpty ? context.loc.error_dialogTitle : title;

    return VPDialog(
      title: resolvedTitle,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (kDebugMode && errorCode != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  '${context.loc.error_codePrefix} $errorCode',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.danger,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (kDebugMode && details != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                details!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.neutralText,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.loc.common_close),
        ),
        if (onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry!();
            },
            child: Text(context.loc.common_retry),
          ),
      ],
    );
  }
}
