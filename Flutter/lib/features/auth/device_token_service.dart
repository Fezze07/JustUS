import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:justus/all_imports.dart';

class DeviceTokenService {
  static bool get supportsFcm =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      kIsWeb;

  static Stream<String> get onTokenRefresh {
    if (!supportsFcm) return const Stream.empty();
    return FirebaseMessaging.instance.onTokenRefresh;
  }

  /// Retrieves the device token.
  /// - On Android/iOS/Web: Returns the FCM token.
  /// - On Windows (unsupported by FCM): Returns a persistent UUID.
  static Future<String> getDeviceToken() async {
    try {
      if (supportsFcm) {
        // FCM for supported platforms
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          return fcmToken;
        }
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        // Fallback for Windows: Persistent UUID
        return await getDeviceFingerprint();
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error getting device token: $e");
      }
    }

    // Fallback if everything fails
    return 'UNKNOWN_DEVICE_TOKEN';
  }

  /// Returns a persistent UUID (fingerprint) stored locally.
  static Future<String> getDeviceFingerprint() async {
    return await StorageService.getOrCreateDeviceFingerprint();
  }
}
