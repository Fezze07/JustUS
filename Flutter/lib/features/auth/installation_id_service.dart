import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:justus/all_imports.dart';

class InstallationIdService {
  /// Overrides the installation-id lookup in unit tests, where
  /// `FirebaseMessaging` has no platform channel and would always resolve to ''.
  @visibleForTesting
  static Future<String> Function()? installationIdOverride;

  static bool get supportsFcm =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      kIsWeb;

  /// Emits the Firebase Installation ID (FID) whenever this app instance is
  /// registered with FCM: on every manual `register()` and whenever the FID
  /// changes (reinstall, restore, cleared app data).
  static Stream<String> get onRegistered {
    if (!supportsFcm) return const Stream.empty();
    return FirebaseMessaging.instance.onRegistered;
  }

  /// Retrieves the Firebase Installation ID (FID) that FCM direct-send targets.
  /// - On Android/iOS/Web: registers with FCM and awaits the FID event.
  /// - On Windows (unsupported by FCM): returns the persistent device UUID.
  /// - On any failure, or a platform without FCM: returns '' so callers skip
  ///   registration rather than persisting a shared placeholder.
  static Future<String> getInstallationId() async {
    final override = installationIdOverride;
    if (override != null) return override();

    try {
      if (supportsFcm) {
        final fcm = FirebaseMessaging.instance;
        // Subscribe before register(): the FID event can land first.
        final fid = fcm.onRegistered.first
            .timeout(const Duration(seconds: 10), onTimeout: () => '');
        await fcm.register();
        final installationId = await fid;
        if (installationId.isNotEmpty) {
          return installationId;
        }
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        return await getDeviceFingerprint();
      }
    } catch (e) {
      AnsiLogger.error('Error getting installation id: $e',
          tag: 'InstallationIdService');
    }

    return '';
  }

  /// Returns a persistent UUID (fingerprint) stored locally.
  static Future<String> getDeviceFingerprint() async {
    return await StorageService.getOrCreateDeviceFingerprint();
  }
}
