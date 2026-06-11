import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const kGameAnswers = 'chk_game_answers';
  static const kMoods = 'chk_moods';
  static const kBucketItems = 'chk_bucket_items';
  static const kDriveItems = 'chk_drive_items';
  static const kMissYou = 'chk_miss_you';
  static const kCheckpointEmpty = 'EMPTY';

  static const _allKeys = [
    kGameAnswers,
    kMoods,
    kBucketItems,
    kDriveItems,
    kMissYou,
  ];

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveCheckpoint(String key, String isoTimestamp) async {
    final p = await _prefs;
    await p.setString(key, isoTimestamp);
  }

  static Future<String?> getCheckpoint(String key) async {
    final p = await _prefs;

    return p.getString(key);
  }

  static Future<void> clearCheckpoints(List<String> keys) async {
    final p = await _prefs;
    for (final key in keys) {
      await p.remove(key);
    }
  }

  static Future<bool> needsRefresh(String key, {int minSeconds = 60}) async {
    final checkpoint = await getCheckpoint(key);
    if (checkpoint == null) return true;

    final lastRefresh = DateTime.tryParse(checkpoint);
    if (lastRefresh == null) return true;

    final elapsed = DateTime.now().toUtc().difference(lastRefresh.toUtc());

    return elapsed.inSeconds >= minSeconds;
  }

  static Future<void> clearAll() => clearCheckpoints(_allKeys);
}
