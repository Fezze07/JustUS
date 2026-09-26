import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:justus/all_imports.dart';

class CaptchaService {
  /// Runs a Cloudflare Turnstile challenge and returns the verification token.
  ///
  /// Uses the visible widget in Managed mode: normal users pass automatically
  /// (no interaction needed) while Cloudflare only surfaces an interactive
  /// challenge for suspicious traffic. The token is single-use and is consumed
  /// exclusively by Supabase Auth's native Turnstile integration.
  static Future<String?> getCaptchaToken() async {
    final siteKey = dotenv.env['TURNSTILE_PUB_SITE_KEY'];
    if (siteKey == null || siteKey.isEmpty) {
      throw AppError(
        code: ErrorCodes.apiValidation001,
        message: ErrorHandler
                .navigatorKey.currentContext?.loc.auth_captchaMissingConfig ??
            'Missing security configuration',
      );
    }

    final context = ErrorHandler.navigatorKey.currentContext;
    if (context == null) return null;

    final baseUrl = '${ApiConfig.appOrigin}/';
    AnsiLogger.auth('Avvio verifica per $baseUrl...', tag: 'CaptchaService');

    final completer = Completer<String?>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void close(String? token) {
          if (!completer.isCompleted) completer.complete(token);
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !completer.isCompleted) {
              completer.complete(null);
              Navigator.of(dialogContext).pop();
            }
          },
          child: VPDialog(
            title: context.loc.auth_captchaTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.auth_captchaMessage),
                const SizedBox(height: 16),
                CloudflareTurnstile(
                  siteKey: siteKey,
                  baseUrl: baseUrl,
                  options: TurnstileOptions(),
                  onTokenReceived: (token) {
                    AnsiLogger.auth('Token ricevuto', tag: 'CaptchaService');
                    close(token);
                  },
                  onError: (error) {
                    AnsiLogger.error(
                      'Turnstile error: ${error.message}',
                      tag: 'CaptchaService',
                    );
                    if (!error.retryable) close(null);
                  },
                  onTimeout: () {
                    AnsiLogger.notification(
                      'Turnstile timeout',
                      tag: 'CaptchaService',
                    );
                    close(null);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => close(null),
                child: Text(context.loc.common_cancel),
              ),
            ],
          ),
        );
      },
    );

    if (!completer.isCompleted) completer.complete(null);
    return completer.future
        .timeout(const Duration(seconds: 30), onTimeout: () => null);
  }
}