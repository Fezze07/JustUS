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
      throw AppError(
        code: ErrorCodes.apiValidation001,
        message: ErrorHandler.navigatorKey.currentContext
                ?.loc
                .auth_captchaMissingConfig ??
            'Missing security configuration',
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
            title: Text(context.loc.auth_captchaTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.auth_captchaMessage),
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
                child: Text(context.loc.common_cancel),
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
