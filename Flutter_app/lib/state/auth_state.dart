// =============================================================================
// AuthState - Global authentication state
// Manages token, current user, and partner info
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/result_wrapper.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = false;
  String? _error;

  String? _accessToken;
  String? _refreshToken;
  String? _username;
  String? _userCode;
  int? _partnerId;
  String? _partnerUsername;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get username => _username;
  String? get userCode => _userCode;
  int? get partnerId => _partnerId;
  String? get partnerUsername => _partnerUsername;
  
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  bool get hasPartner => _partnerId != null;
  String get usernameWithCode => '$_username#$_userCode';

  Future<void> init() async {
    _accessToken = await StorageService.getAccessToken();
    _refreshToken = await StorageService.getRefreshToken();
    _username = await StorageService.getUsername();
    _userCode = await StorageService.getUserCode();
    _partnerId = await StorageService.getPartnerId();
    _partnerUsername = await StorageService.getPartnerUsername();
    notifyListeners();
  }
  
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Step 1: Request User Code
      final codeResult = await _apiService.requestUserCodes(RequestCodesBody(
        username: username,
        password: password,
      ));

      String? userCode;
      
      if (codeResult is Success<RequestCodesResponse>) {
         final codes = codeResult.value.codes;
         if (codes != null && codes.isNotEmpty) {
           userCode = codes.first; // Automatically select the first code
         } else {
           _error = 'User not found or no code available';
           return false;
         }
      } else if (codeResult is GenericError) {
        _error = (codeResult as GenericError).message;
        return false;
      } else {
         _error = 'Network error checking user code';
         return false;
      }

      // Step 2: Perform Actual Login with username#code
      final fullUsername = '$username#$userCode';
      final deviceToken = await getDeviceToken();
      
      final result = await _apiService.login(LoginRequestBody(
        usernameWithCode: fullUsername,
        password: password,
        deviceToken: deviceToken,
      ));
      
      if (result is Success<LoginResponse>) {
        final data = result.value;
        await setLoginData(
          accessToken: data.accessToken!,
          refreshToken: data.refreshToken!,
          user: data.user!,
        );
        if (data.user != null) {
           // Try to fetch partner info separately since it's not in LoginResponse
           final partnerResult = await _apiService.getPartnerProfile();
           if (partnerResult is Success<ProfileResponse>) {
             final partnerData = partnerResult.value;
             if (partnerData.profile != null) {
               await setPartner(
                 partnerId: partnerData.profile!.id,
                 username: partnerData.profile!.username,
               );
             }
           }
        }
        return true;
      } else if (result is GenericError) {
        _error = (result as GenericError).message;
        return false;
      } else {
         _error = 'Network error occurred';
         return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final deviceToken = await getDeviceToken();
      final result = await _apiService.register(RegisterRequestBody(
        email: email,
        password: password,
        username: name,
        deviceToken: deviceToken,
      ));
      
      if (result is Success<RegisterResponse>) {
        // Registration successful, now login automatically
        return await login(email, password);
      } else if (result is GenericError) {
        _error = (result as GenericError).message;
        return false;
      } else {
        _error = 'Network error occurred';
        return false;
      }
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setLoginData({
    required String accessToken,
    required String refreshToken,
    required User user,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _username = user.username;
    _userCode = user.code;
    
    await StorageService.saveAccessToken(accessToken);
    await StorageService.saveRefreshToken(refreshToken);
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
    _accessToken = null;
    _refreshToken = null;
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
