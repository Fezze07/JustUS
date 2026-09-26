// =============================================================================
// StorageService - Local storage wrapper
// =============================================================================

import 'dart:async';
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
  static const String _keyPartnershipId = 'partnership_id';
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

  static int? _activePartnershipId;

  /// Feature cache keys that hold partnership-scoped data. Namespaced with the
  /// active partnership id (F-SC8) and purged on partnership transitions.
  static const _partnershipScopedCacheKeys = [
    _keyMissYouTotal,
    _keyMoodMe,
    _keyMoodPartner,
    _keyRecentEmojis,
    _keyTimeline,
    _keyBucketList,
    _keyGameMatches,
    _keyGameQuestion,
    _keyGameHistory,
    _keyDriveCache,
    _keyPartnerProfile,
  ];

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
    _activePartnershipId = null;
    CacheService.setPartnership(null);
  }

  // -------------------- Helpers --------------------

  /// Namespaces a partnership-scoped feature cache key with the active
  /// partnership id, so a partnership change never exposes the previous
  /// partner's cached data (F-SC8).
  static String _feat(String base) =>
      _activePartnershipId == null ? base : '$base:$_activePartnershipId';

  /// Sets the active partnership used to namespace feature caches and
  /// checkpoints. Called on cold start (`AuthState.init`) and after every
  /// partnership id write. Does not clear any cached data.
  static void setActivePartnership(int? partnershipId) {
    _activePartnershipId = partnershipId;
    CacheService.setPartnership(partnershipId);
  }

  /// Removes partnership-scoped feature cache and checkpoint variants for the
  /// previous/next scope plus the unscoped legacy variant.
  static Future<void> purgeCacheVariants({int? oldId, int? newId}) async {
    final p = await prefs;
    final oldScope = oldId?.toString();
    final newScope = newId?.toString();
    for (final base in _partnershipScopedCacheKeys) {
      await p.remove(base);
      if (oldScope != null) await p.remove('$base:$oldScope');
      if (newScope != null) await p.remove('$base:$newScope');
    }
    await CacheService.purge(oldId: oldId, newId: newId);
  }

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

  static Future<void> savePartnershipId(int partnershipId) async {
    final oldId = await getPartnershipId();
    await _secureStorage.write(
        key: _keyPartnershipId, value: partnershipId.toString());
    if (oldId != partnershipId) {
      await purgeCacheVariants(oldId: oldId, newId: partnershipId);
    }
    setActivePartnership(partnershipId);
  }

  static Future<int?> getPartnershipId() async {
    final val = await _secureStorage.read(key: _keyPartnershipId);
    final id = val != null ? int.tryParse(val) : null;

    return id != null && id != -1 ? id : null;
  }

  // -------------------- Miss You --------------------

  static Future<void> saveTotalMissYou(int total) async {
    final p = await prefs;
    await p.setInt(_feat(_keyMissYouTotal), total);
  }

  static Future<int?> getTotalMissYou() async {
    final p = await prefs;

    return p.containsKey(_feat(_keyMissYouTotal))
        ? p.getInt(_feat(_keyMissYouTotal))
        : null;
  }

  // -------------------- Bucket List --------------------

  static Future<void> saveBucketList(List<BucketItem> list) async {
    await _saveJsonList(_feat(_keyBucketList), list, (e) => e.toJson());
  }

  static Future<List<BucketItem>> getBucketList() async {
    return _getJsonList(_feat(_keyBucketList), BucketItem.fromJson);
  }

  // -------------------- Game --------------------

  static Future<void> saveGameMatches(int total) async {
    final p = await prefs;
    await p.setInt(_feat(_keyGameMatches), total);
  }

  static Future<int> getGameMatches() async {
    final p = await prefs;

    return p.getInt(_feat(_keyGameMatches)) ?? 0;
  }

  static Future<void> saveGameQuestion(GameNewQuestionResponse question) async {
    await _saveJson(_feat(_keyGameQuestion), question.toJson());
  }

  static Future<GameNewQuestionResponse?> getCachedGameQuestion() async {
    return _getJson(_feat(_keyGameQuestion), GameNewQuestionResponse.fromJson);
  }

  static Future<void> clearCachedGameQuestion() async {
    final p = await prefs;
    await p.remove(_feat(_keyGameQuestion));
  }

  static Future<void> saveGameHistory(List<GameHistoryItem> items) async {
    await _saveJsonList(_feat(_keyGameHistory), items, (e) => e.toJson());
  }

  static Future<List<GameHistoryItem>> getGameHistory() async {
    return _getJsonList(_feat(_keyGameHistory), GameHistoryItem.fromJson);
  }

  // -------------------- Drive --------------------

  static Future<void> saveDriveItems(List<DriveItem> items) async {
    await _saveJsonList(_feat(_keyDriveCache), items, (e) => e.toJson());
  }

  static Future<List<DriveItem>> getDriveItems() async {
    return _getJsonList(_feat(_keyDriveCache), DriveItem.fromJson);
  }

  // -------------------- Profile --------------------

  static Future<void> saveUserProfile(User user) async {
    await _saveJson(_keyUserProfile, user.toJson());
  }

  static Future<User?> getUserProfile() async {
    return _getJson(_keyUserProfile, User.fromJson);
  }

  static Future<void> savePartnerProfile(User user) async {
    await _saveJson(_feat(_keyPartnerProfile), user.toJson());
  }

  static Future<User?> getPartnerProfile() async {
    return _getJson(_feat(_keyPartnerProfile), User.fromJson);
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
    final key = _feat(target == 'me' ? _keyMoodMe : _keyMoodPartner);
    await p.setString(key, emoji);
  }

  static Future<String?> getMood(String target) async {
    final p = await prefs;
    final key = _feat(target == 'me' ? _keyMoodMe : _keyMoodPartner);

    return p.getString(key);
  }

  static Future<void> saveRecentEmojis(List<String> emojis) async {
    final p = await prefs;
    await p.setStringList(_feat(_keyRecentEmojis), emojis);
  }

  static Future<List<String>> getRecentEmojis() async {
    final p = await prefs;

    return p.getStringList(_feat(_keyRecentEmojis)) ?? [];
  }

  static Future<void> saveTimeline(List<MoodEntry> entries) async {
    await _saveJsonList(_feat(_keyTimeline), entries, (e) => e.toJson());
  }

  static Future<List<MoodEntry>> getTimeline() async {
    return _getJsonList(_feat(_keyTimeline), MoodEntry.fromJson);
  }

  // -------------------- Clear Cache --------------------

  static Future<void> clearPartner() async {
    final oldId = await getPartnershipId();
    await purgeCacheVariants(oldId: oldId);
    await _secureStorage.delete(key: _keyPartnerId);
    await _secureStorage.delete(key: _keyPartnershipId);
    final p = await prefs;
    await p.remove(_keyPartnerDisplayName);
    setActivePartnership(null);
  }

  static Future<void> clearAppCache() async {
    final p = await prefs;
    final scope = _activePartnershipId?.toString();
    for (final base in _partnershipScopedCacheKeys) {
      await p.remove(base);
      if (scope != null) await p.remove('$base:$scope');
    }
    for (final base in [
      _keyDriveThumbCache,
      _keyUserProfile,
      _keyProfilePicVersion,
    ]) {
      await p.remove(base);
    }
  }

  static Future<void> clearAll() async {
    final p = await prefs;
    final preserved = <String, String?>{
      LanguageHelper.storageKey: p.getString(LanguageHelper.storageKey),
      ThemeProvider.storageKey: p.getString(ThemeProvider.storageKey),
    };
    await p.clear();
    for (final entry in preserved.entries) {
      final value = entry.value;
      if (value != null) {
        await p.setString(entry.key, value);
      }
    }
    await _secureStorage.deleteAll();
    _activePartnershipId = null;
    CacheService.setPartnership(null);
  }
}

/// Serializes async cache writes so snapshots are persisted in submission
/// order (F-SC12).
///
/// A feature state that mutates and persists concurrently (e.g. drive sync vs
/// optimistic mutations) must not let an older snapshot's write land after a
/// newer one. Each enqueued job runs to completion before the next starts,
/// and errors are forwarded to the submitting caller without stalling the
/// chain.
class CacheWriteQueue {
  Future<void> _tail = Future.value();

  /// Schedules [write]; the returned future completes with its result.
  Future<void> enqueue(Future<void> Function() write) {
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await write();
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });

    return completer.future;
  }
}
