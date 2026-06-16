import 'dart:async';

import 'package:justus/all_imports.dart';

class MoodRepository extends BaseRepository {
  MoodRepository({super.sbClient});

  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) async {
    final uid = await getUserId();
    if (uid == null) return const GenericError(message: 'User not logged in');

    return tryCall(() async {
      await sbClient.rpc('set_mood', params: {'p_emoji_char': emojiChar});

      unawaited(notifyPartnerOnce(
        notificationKey: 'moodUpdated',
        params: {
          'partnerName': await StorageService.getUsername() ?? '',
          'emojiChar': emojiChar,
        },
      ));

      return MoodEntry.fromJson({
        'user_id': uid,
        'emoji': emojiChar,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, currentUserId: uid);
    });
  }

  Future<Map<String, dynamic>?> _fetchLatestMood(int userId) async {
    return await sbClient
        .from('moods')
        .select('id, created_at, emojis(emoji_char)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<List<dynamic>> _fetchMoodsForUsers(List<int> userIds,
      {String select = 'id, user_id, created_at, emojis(emoji_char)',
      int? limit}) async {
    var query = sbClient
        .from('moods')
        .select(select)
        .maybeFilterIn('user_id', userIds)
        .order('created_at', ascending: false);

    if (limit != null) {
      query = query.limit(limit);
    }

    return await query;
  }

  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return withCouple((uid, _) async {
      final data = await _fetchLatestMood(uid);
      final emojiChar =
          (data?['emojis'] as Map<String, dynamic>?)?['emoji_char'] as String?;

      return MoodResponse(
        success: true,
        emoji: emojiChar,
        createdAt: data?['created_at'] as String?,
      );
    });
  }

  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    return withCouple((_, partnerId) async {
      if (partnerId == null) return MoodResponse(success: true);
      final data = await _fetchLatestMood(partnerId);
      final emojiChar =
          (data?['emojis'] as Map<String, dynamic>?)?['emoji_char'] as String?;

      return MoodResponse(
        success: true,
        emoji: emojiChar,
        createdAt: data?['created_at'] as String?,
      );
    });
  }

  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    return withCouple((uid, partnerId) async {
      final ids = [uid];
      if (partnerId != null) ids.add(partnerId);

      final data = await _fetchMoodsForUsers(ids,
          select: 'emojis(emoji_char)', limit: 10);

      final emojis = data
          .map((m) =>
              (m['emojis'] as Map<String, dynamic>?)?['emoji_char']
                  ?.toString() ??
              '')
          .where((e) => e.isNotEmpty)
          .toList();

      final seen = <String>{};
      final unique = <String>[];
      for (final e in emojis) {
        if (seen.add(e)) unique.add(e);
      }
      return unique;
    });
  }

  Future<ResultWrapper<List<MoodEntry>>> fetchMoods() async {
    return withCouple((uid, partnerId) async {
      final ids = [uid];
      if (partnerId != null) ids.add(partnerId);

      final data = await _fetchMoodsForUsers(ids);

      return data
          .map((m) =>
              MoodEntry.fromJson(m as Map<String, dynamic>, currentUserId: uid))
          .toList();
    });
  }

  Future<bool> hasNewMoods(int uid, int? partnerId) {
    return hasChanges(
      table: 'moods',
      field: 'created_at',
      filterColumn: 'user_id',
      filterValues: [uid, if (partnerId != null) partnerId],
      cacheKey: CacheService.kMoods,
    );
  }

  Future<ResultWrapper<List<MoodEntry>>> fetchTimeline(
      {int limit = 4, int offset = 0}) async {
    return withCouple((uid, partnerId) async {
      final ids = [uid];
      if (partnerId != null) ids.add(partnerId);

      final data = await sbClient
          .from('moods')
          .select('id, user_id, created_at, emojis(emoji_char)')
          .maybeFilterIn('user_id', ids)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return data
          .map((m) => MoodEntry.fromJson(m, currentUserId: uid))
          .toList();
    });
  }
}
