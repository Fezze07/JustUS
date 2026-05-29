import 'package:justus/all_imports.dart';

class MoodRepository extends BaseRepository {
  MoodRepository({super.sbClient});

  Future<ResultWrapper<MoodEntry>> updateMood(String emojiChar) async {
    return withUser((uid) async {
      await sbClient.rpc('set_mood', params: {'p_emoji_char': emojiChar});

      return MoodEntry(
        id: 0,
        userId: uid,
        emoji: emojiChar,
        createdAt: DateTime.now().toIso8601String(),
      );
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

  Future<List<dynamic>> _fetchMoodsForUsers(List<int> userIds, {String select = 'id, user_id, created_at, emojis(emoji_char)', int? limit}) async {
    var query = sbClient
        .from('moods')
        .select(select)
        .inFilter('user_id', userIds)
        .order('created_at', ascending: false);
    
    if (limit != null) {
      query = query.limit(limit);
    }
    
    return await query;
  }

  Future<ResultWrapper<MoodResponse>> fetchMyMood() async {
    return withCouple((uid, _) async {
      final data = await _fetchLatestMood(uid);
      final emojiChar = (data?['emojis'] as Map<String, dynamic>?)?['emoji_char'] as String?;

      return MoodResponse(success: true, emoji: emojiChar);
    });
  }

  Future<ResultWrapper<MoodResponse>> fetchPartnerMood() async {
    return withCouple((_, partnerId) async {
      if (partnerId == null) return MoodResponse(success: true);
      final data = await _fetchLatestMood(partnerId);
      final emojiChar = (data?['emojis'] as Map<String, dynamic>?)?['emoji_char'] as String?;

      return MoodResponse(success: true, emoji: emojiChar);
    });
  }

  Future<ResultWrapper<List<String>>> fetchRecentCoupleEmojis() async {
    return withCouple((uid, partnerId) async {
      final ids = [uid];
      if (partnerId != null) ids.add(partnerId);

      final data = await _fetchMoodsForUsers(ids, select: 'emojis(emoji_char)', limit: 20);

      return data
          .map((m) => (m['emojis'] as Map<String, dynamic>?)?['emoji_char']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    });
  }

  Future<ResultWrapper<List<MoodEntry>>> fetchMoods() async {
    return withCouple((uid, partnerId) async {
      final ids = [uid];
      if (partnerId != null) ids.add(partnerId);

      final data = await _fetchMoodsForUsers(ids);

      return data.map((m) => MoodEntry.fromJson(m as Map<String, dynamic>)).toList();
    });
  }
}
