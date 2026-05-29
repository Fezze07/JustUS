import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:justus/all_imports.dart';

class CaptchaService {
  /// Genera un token Cloudflare Turnstile in modo invisibile tramite un dialog.
  /// Se fallisce o il token è nullo, lancia un AppError.
  static Future<String?> getCaptchaToken() async {
    final siteKey = dotenv.env['TURNSTILE_PUB_SITE_KEY'];
    if (siteKey == null || siteKey.isEmpty) {
      throw const AppError(
        code: ErrorCodes.apiValidation001,
        message: 'Configurazione di sicurezza mancante (Site Key).',
      );
    }

    final context = ErrorHandler.navigatorKey.currentContext;
    if (context == null) return null;

    try {
      final String currentBaseUrl = '${ApiConfig.appOrigin}/';

      if (kDebugMode) {
        print('[CaptchaService] Avvio verifica Managed per $currentBaseUrl...');
      }

      String? captchaToken;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Verifica di sicurezza'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('JustUs sta verificando che tu sia un umano...'),
                const SizedBox(height: 20),
                SizedBox(
                  height: 100,
                  child: CloudflareTurnstile(
                    siteKey: siteKey,
                    baseUrl: currentBaseUrl,
                    onTokenReceived: (token) {
                      captchaToken = token;
                      Navigator.of(context).pop();
                    },
                    onTokenExpired: () {
                      captchaToken = null;
                      Navigator.of(context).pop();
                    },
                    onError: (error) {
                      if (kDebugMode) print('[Turnstile] Errore: $error');
                      captchaToken = null;
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  captchaToken = null;
                  Navigator.of(context).pop();
                },
                child: const Text('Annulla'),
              ),
            ],
          );
        },
      );

      return captchaToken;
    } catch (e) {
      if (kDebugMode) print('[CaptchaService] Errore durante Turnstile: $e');

      return null;
    }
  }
}
