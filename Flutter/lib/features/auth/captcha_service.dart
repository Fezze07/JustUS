import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:justus/all_imports.dart';

class CaptchaService {
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

    String? captchaToken;
    final turnstile = CloudflareTurnstile.invisible(
      siteKey: siteKey,
      baseUrl: baseUrl,
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        unawaited(_runInvisibleChallenge(turnstile).then((token) {
          captchaToken = token;
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        }));

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && captchaToken == null) {
              captchaToken = null;
              Navigator.of(dialogContext).pop();
            }
          },
          child: AlertDialog(
            title: Text(context.loc.auth_captchaTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.auth_captchaMessage),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  captchaToken = null;
                  Navigator.of(dialogContext).pop();
                },
                child: Text(context.loc.common_cancel),
              ),
            ],
          ),
        );
      },
    );

    return captchaToken;
  }

  static Future<String?> _runInvisibleChallenge(
      CloudflareTurnstile turnstile) async {
    try {
      final token = await turnstile
          .getToken()
          .timeout(const Duration(seconds: 30));

      if (token != null && token.isNotEmpty) {
        AnsiLogger.auth('Token ricevuto', tag: 'CaptchaService');
      } else {
        AnsiLogger.notification('Token nullo o vuoto', tag: 'CaptchaService');
      }

      return token;
    } on TurnstileException catch (e) {
      AnsiLogger.error('Turnstile error: ${e.message}', tag: 'CaptchaService');
      return null;
    } on TimeoutException {
      AnsiLogger.notification('Turnstile timeout dopo 30s', tag: 'CaptchaService');
      return null;
    } catch (e) {
      AnsiLogger.error('Errore inaspettato: $e', tag: 'CaptchaService');
      return null;
    } finally {
      unawaited(turnstile.dispose());
    }
  }
}
