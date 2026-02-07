// =============================================================================
// StorageService - Local storage wrapper
// Dart equivalent of SharedPrefsManager.kt
// =============================================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StorageService {
  static const String _keyUsername = 'username';
  static const String _keyUserCode = 'user_code';
  static const String _keyToken = 'token';
  static const String _keyPartnerId = 'partner_id';
  static const String _keyPartnerUsername = 'partner_username';
  static const String _keyMissYouTotal = 'miss_you';
  static const String _keyBucketList = 'bucket_list';
  static const String _keyGameMatches = 'game_matches';
  static const String _keyGameQuestion = 'game_question';
  static const String _keyDriveCache = 'drive_cache';
  static const String _keyDriveLastSync = 'drive_last_sync';
  static const String _keyUserProfile = 'user_profile';
  static const String _keyPartnerProfile = 'partner_profile';
  static const String _keyProfilePicVersion = 'profile_pic_version';
  static const String _keyRecentEmojis = 'recent_emojis';
  static const String _keyMoodMe = 'mood_me';
  static const String _keyMoodPartner = 'mood_partner';
  static const String _keyDriveThumbCache = 'drive_thumb_cache';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // -------------------- Username --------------------

  static Future<void> saveUsername(String username) async {
    final p = await prefs;
    await p.setString(_keyUsername, username);
  }

  static Future<String?> getUsername() async {
    final p = await prefs;
    return p.getString(_keyUsername);
  }

  // -------------------- User Code --------------------

  static Future<void> saveUserCode(String code) async {
    final p = await prefs;
    await p.setString(_keyUserCode, code);
  }

  static Future<String?> getUserCode() async {
    final p = await prefs;
    return p.getString(_keyUserCode);
  }

  // -------------------- Token --------------------

  static Future<void> saveToken(String token) async {
    final p = await prefs;
    await p.setString(_keyToken, token);
  }

  static Future<String?> getToken() async {
    final p = await prefs;
    return p.getString(_keyToken);
  }

  // -------------------- Partner --------------------

  static Future<void> savePartner(int partnerId, String username) async {
    final p = await prefs;
    await p.setInt(_keyPartnerId, partnerId);
    await p.setString(_keyPartnerUsername, username);
  }

  static Future<int?> getPartnerId() async {
    final p = await prefs;
    final id = p.getInt(_keyPartnerId);
    return id != null && id != -1 ? id : null;
  }

  static Future<String?> getPartnerUsername() async {
    final p = await prefs;
    return p.getString(_keyPartnerUsername);
  }

  // -------------------- Miss You --------------------

  static Future<void> saveTotalMissYou(int total) async {
    final p = await prefs;
    await p.setInt(_keyMissYouTotal, total);
  }

  static Future<int?> getTotalMissYou() async {
    final p = await prefs;
    return p.containsKey(_keyMissYouTotal)
        ? p.getInt(_keyMissYouTotal)
        : null;
  }

  // -------------------- Bucket List --------------------

  static Future<void> saveBucketList(List<BucketItem> list) async {
    final p = await prefs;
    final json = jsonEncode(list.map((e) => e.toJson()).toList());
    await p.setString(_keyBucketList, json);
  }

  static Future<List<BucketItem>> getBucketList() async {
    final p = await prefs;
    final json = p.getString(_keyBucketList);
    if (json == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded.map((e) => BucketItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  // -------------------- Game --------------------

  static Future<void> saveGameMatches(int total) async {
    final p = await prefs;
    await p.setInt(_keyGameMatches, total);
  }

  static Future<int> getGameMatches() async {
    final p = await prefs;
    return p.getInt(_keyGameMatches) ?? 0;
  }

  static Future<void> saveGameQuestion(GameNewQuestionResponse question) async {
    final p = await prefs;
    final json = jsonEncode(question.toJson());
    await p.setString(_keyGameQuestion, json);
  }

  static Future<GameNewQuestionResponse?> getCachedGameQuestion() async {
    final p = await prefs;
    final json = p.getString(_keyGameQuestion);
    if (json == null) return null;
    try {
      return GameNewQuestionResponse.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  // -------------------- Drive --------------------

  static Future<void> saveDriveItems(List<DriveItem> items) async {
    final p = await prefs;
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    await p.setString(_keyDriveCache, json);
  }

  static Future<List<DriveItem>> getDriveItems() async {
    final p = await prefs;
    final json = p.getString(_keyDriveCache);
    if (json == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded.map((e) => DriveItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLastSync(String lastSync) async {
    final p = await prefs;
    await p.setString(_keyDriveLastSync, lastSync);
  }

  static Future<String?> getLastSync() async {
    final p = await prefs;
    return p.getString(_keyDriveLastSync);
  }

  // -------------------- Profile --------------------

  static Future<void> saveUserProfile(User user) async {
    final p = await prefs;
    final json = jsonEncode(user.toJson());
    await p.setString(_keyUserProfile, json);
  }

  static Future<User?> getUserProfile() async {
    final p = await prefs;
    final json = p.getString(_keyUserProfile);
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePartnerProfile(User user) async {
    final p = await prefs;
    final json = jsonEncode(user.toJson());
    await p.setString(_keyPartnerProfile, json);
  }

  static Future<User?> getPartnerProfile() async {
    final p = await prefs;
    final json = p.getString(_keyPartnerProfile);
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfilePicVersion(int version) async {
    final p = await prefs;
    await p.setInt(_keyProfilePicVersion, version);
  }

  static Future<int?> getProfilePicVersion() async {
    final p = await prefs;
    return p.getInt(_keyProfilePicVersion);
  }

  // -------------------- Mood --------------------

  static Future<void> saveMood(String target, String emoji) async {
    final p = await prefs;
    final key = target == 'me' ? _keyMoodMe : _keyMoodPartner;
    await p.setString(key, emoji);
  }

  static Future<String?> getMood(String target) async {
    final p = await prefs;
    final key = target == 'me' ? _keyMoodMe : _keyMoodPartner;
    return p.getString(key);
  }

  static Future<void> saveRecentEmojis(List<String> emojis) async {
    final p = await prefs;
    await p.setStringList(_keyRecentEmojis, emojis);
  }

  static Future<List<String>> getRecentEmojis() async {
    final p = await prefs;
    return p.getStringList(_keyRecentEmojis) ?? [];
  }

  // -------------------- Clear Cache --------------------

  static Future<void> clearAppCache() async {
    final p = await prefs;
    await p.remove(_keyBucketList);
    await p.remove(_keyGameMatches);
    await p.remove(_keyGameQuestion);
    await p.remove(_keyMissYouTotal);
    await p.remove(_keyRecentEmojis);
    await p.remove(_keyDriveCache);
    await p.remove(_keyDriveLastSync);
    await p.remove(_keyProfilePicVersion);
    await p.remove(_keyDriveThumbCache);
  }

  static Future<void> clearAll() async {
    final p = await prefs;
    await p.clear();
  }
}
