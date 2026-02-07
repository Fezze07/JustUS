// =============================================================================
// AuthState - Global authentication state
// Manages token, current user, and partner info
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState extends ChangeNotifier {
  String? _token;
  String? _username;
  String? _userCode;
  int? _partnerId;
  String? _partnerUsername;

  String? get token => _token;
  String? get username => _username;
  String? get userCode => _userCode;
  int? get partnerId => _partnerId;
  String? get partnerUsername => _partnerUsername;
  
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get hasPartner => _partnerId != null;
  String get usernameWithCode => '$_username#$_userCode';

  Future<void> init() async {
    _token = await StorageService.getToken();
    _username = await StorageService.getUsername();
    _userCode = await StorageService.getUserCode();
    _partnerId = await StorageService.getPartnerId();
    _partnerUsername = await StorageService.getPartnerUsername();
    notifyListeners();
  }

  Future<void> setLoginData({
    required String token,
    required User user,
  }) async {
    _token = token;
    _username = user.username;
    _userCode = user.code;
    
    await StorageService.saveToken(token);
    await StorageService.saveUsername(user.username);
    await StorageService.saveUserCode(user.code);
    
    notifyListeners();
  }

  Future<void> setPartner({
    required int partnerId,
    required String username,
  }) async {
    _partnerId = partnerId;
    _partnerUsername = username;
    
    await StorageService.savePartner(partnerId, username);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    _userCode = null;
    _partnerId = null;
    _partnerUsername = null;
    
    await StorageService.clearAll();
    notifyListeners();
  }

  /// Retrieves the device token.
  /// - On Android/iOS/Web: Returns the FCM token.
  /// - On Windows (unsupported by FCM): Returns a persistent UUID.
  Future<String> getDeviceToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          kIsWeb) {
        // FCM for supported platforms
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          return fcmToken;
        }
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        // Fallback for Windows: Persistent UUID
        return await _getPersistentUuid();
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error getting device token: $e");
      }
    }
    // Fallback if everything fails
    return 'UNKNOWN_DEVICE_TOKEN';
  }

  Future<String> _getPersistentUuid() async {
    // Check if we already have a generated UUID stored
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString('device_uuid');

    if (uuid == null) {
      // Generate a new UUID and store it
      uuid = const Uuid().v4();
      await prefs.setString('device_uuid', uuid);
    }
    return uuid;
  }
}
