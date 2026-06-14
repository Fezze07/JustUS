// =============================================================================
// StorageService - Local storage wrapper
// =============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:justus/all_imports.dart';

// --- Isolate helpers for JSON operations ---
// Top-level functions required by compute() for isolate offloading.

Map<String, dynamic> _isolateDecodeMap(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

List<dynamic> _isolateDecodeList(String json) =>
    jsonDecode(json) as List<dynamic>;

String _isolateEncodeMap(Map<String, dynamic> map) => jsonEncode(map);

String _isolateEncodeList(List<Map<String, dynamic>> list) => jsonEncode(list);

class StorageService {
  static const String _keyUsername = 'username';
  static const String _keyUserId = 'user_id';
  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyPartnerId = 'partner_id';
  static const String _keyPartnerDisplayName = 'partner_display_name';
  static const String _keyMissYouTotal = 'miss_you';
  static const String _keyBucketList = 'bucket_list';
  static const String _keyGameMatches = 'game_matches';
  static const String _keyGameQuestion = 'game_question';
  static const String _keyGameHistory = 'game_history';
  static const String _keyDriveCache = 'drive_cache';
  static const String _keyUserProfile = 'user_profile';
  static const String _keyPartnerProfile = 'partner_profile';
  static const String _keyProfilePicVersion = 'profile_pic_version';
  static const String _keyRecentEmojis = 'recent_emojis';
  static const String _keyMoodMe = 'mood_me';
  static const String _keyMoodPartner = 'mood_partner';
  static const String _keyDriveThumbCache = 'drive_thumb_cache';
  static const String _keyDeviceFingerprint = 'device_fingerprint';
  static const String _keyRequestBindingSecret = 'request_binding_secret';
  static const String _keyTimeline = 'mood_timeline';

  static SharedPreferences? _prefs;
  static const _secureStorage = FlutterSecureStorage();

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefsSync {
    assert(_prefs != null, 'SharedPreferences not yet initialized');
    return _prefs!;
  }

  static Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();

    return _prefs!;
  }

  static void resetForTest() {
    _prefs = null;
  }

  // -------------------- Helpers --------------------

  static Future<void> _saveJson(String key, Map<String, dynamic> json) async {
    final p = await prefs;
    final encoded = await compute(_isolateEncodeMap, json);
    await p.setString(key, encoded);
  }

  static Future<T?> _getJson<T>(
      String key, T Function(Map<String, dynamic>) fromJson) async {
    final p = await prefs;
    final raw = p.getString(key);
    if (raw == null) return null;
    try {
      final decoded = await compute(_isolateDecodeMap, raw);
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveJsonList<T>(
      String key, List<T> list, Map<String, dynamic> Function(T) toJson) async {
    final p = await prefs;
    final maps = list.map((e) => toJson(e)).toList();
    final encoded = await compute(_isolateEncodeList, maps);
    await p.setString(key, encoded);
  }

  static Future<List<T>> _getJsonList<T>(
      String key, T Function(Map<String, dynamic>) fromJson) async {
    final p = await prefs;
    final raw = p.getString(key);
    if (raw == null) return [];
    try {
      final decoded = await compute(_isolateDecodeList, raw);
      return decoded
          .map((e) => fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
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

  // -------------------- User ID (DB Integer ID) --------------------

  static Future<void> saveUserId(int id) async {
    await _secureStorage.write(key: _keyUserId, value: id.toString());
  }

  static Future<int?> getUserId() async {
    final val = await _secureStorage.read(key: _keyUserId);

    return val != null ? int.tryParse(val) : null;
  }

  // -------------------- Access Token --------------------

  static Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(key: _keyAccessToken, value: token);
  }

  static Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _keyAccessToken);
  }

  // -------------------- Refresh Token --------------------

  static Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _keyRefreshToken, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _keyRefreshToken);
  }

  // Backward compatibility - deprecated, use saveAccessToken
  static Future<void> saveToken(String token) async {
    await saveAccessToken(token);
  }

  static Future<String?> getToken() async {
    return getAccessToken();
  }

  // -------------------- Device Binding --------------------

  static Future<String> getOrCreateDeviceFingerprint() async {
    final existing = await _secureStorage.read(key: _keyDeviceFingerprint);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = const Uuid().v4();
    await _secureStorage.write(key: _keyDeviceFingerprint, value: created);

    return created;
  }

  static Future<void> saveRequestBindingSecret(String secret) async {
    await _secureStorage.write(key: _keyRequestBindingSecret, value: secret);
    ApiService.setCachedRequestBindingSecret(secret);
  }

  static Future<String?> getRequestBindingSecret() async {
    return _secureStorage.read(key: _keyRequestBindingSecret);
  }

  // -------------------- Partner --------------------

  static Future<void> savePartner(int partnerId, String displayName) async {
    final p = await prefs;
    await _secureStorage.write(key: _keyPartnerId, value: partnerId.toString());
    await p.setString(_keyPartnerDisplayName, displayName);
  }

  static Future<int?> getPartnerId() async {
    final val = await _secureStorage.read(key: _keyPartnerId);
    final id = val != null ? int.tryParse(val) : null;

    return id != null && id != -1 ? id : null;
  }

  static Future<String?> getPartnerDisplayName() async {
    final p = await prefs;

    return p.getString(_keyPartnerDisplayName);
  }

  // -------------------- Miss You --------------------

  static Future<void> saveTotalMissYou(int total) async {
    final p = await prefs;
    await p.setInt(_keyMissYouTotal, total);
  }

  static Future<int?> getTotalMissYou() async {
    final p = await prefs;

    return p.containsKey(_keyMissYouTotal) ? p.getInt(_keyMissYouTotal) : null;
  }

  // -------------------- Bucket List --------------------

  static Future<void> saveBucketList(List<BucketItem> list) async {
    await _saveJsonList(_keyBucketList, list, (e) => e.toJson());
  }

  static Future<List<BucketItem>> getBucketList() async {
    return _getJsonList(_keyBucketList, BucketItem.fromJson);
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
    await _saveJson(_keyGameQuestion, question.toJson());
  }

  static Future<GameNewQuestionResponse?> getCachedGameQuestion() async {
    return _getJson(_keyGameQuestion, GameNewQuestionResponse.fromJson);
  }

  static Future<void> saveGameHistory(List<GameHistoryItem> items) async {
    await _saveJsonList(_keyGameHistory, items, (e) => e.toJson());
  }

  static Future<List<GameHistoryItem>> getGameHistory() async {
    return _getJsonList(_keyGameHistory, GameHistoryItem.fromJson);
  }

  // -------------------- Drive --------------------

  static Future<void> saveDriveItems(List<DriveItem> items) async {
    await _saveJsonList(_keyDriveCache, items, (e) => e.toJson());
  }

  static Future<List<DriveItem>> getDriveItems() async {
    return _getJsonList(_keyDriveCache, DriveItem.fromJson);
  }

  // -------------------- Profile --------------------

  static Future<void> saveUserProfile(User user) async {
    await _saveJson(_keyUserProfile, user.toJson());
  }

  static Future<User?> getUserProfile() async {
    return _getJson(_keyUserProfile, User.fromJson);
  }

  static Future<void> savePartnerProfile(User user) async {
    await _saveJson(_keyPartnerProfile, user.toJson());
  }

  static Future<User?> getPartnerProfile() async {
    return _getJson(_keyPartnerProfile, User.fromJson);
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

  static Future<void> saveTimeline(List<MoodEntry> entries) async {
    await _saveJsonList(_keyTimeline, entries, (e) => e.toJson());
  }

  static Future<List<MoodEntry>> getTimeline() async {
    return _getJsonList(_keyTimeline, MoodEntry.fromJson);
  }

  // -------------------- Clear Cache --------------------

  static Future<void> clearPartner() async {
    final p = await prefs;
    await _secureStorage.delete(key: _keyPartnerId);
    await p.remove(_keyPartnerDisplayName);
  }

  static Future<void> clearAppCache() async {
    final p = await prefs;
    final keysToClear = [
      _keyBucketList,
      _keyGameMatches,
      _keyGameQuestion,
      _keyGameHistory,
      _keyMissYouTotal,
      _keyRecentEmojis,
      _keyDriveCache,
      _keyProfilePicVersion,
      _keyDriveThumbCache,
      _keyUserProfile,
      _keyPartnerProfile,
      _keyMoodMe,
      _keyMoodPartner,
      _keyTimeline,
    ];
    for (final key in keysToClear) {
      await p.remove(key);
    }
  }

  static Future<void> clearAll() async {
    final p = await prefs;
    await p.clear();
    await _secureStorage.deleteAll();
  }
}
