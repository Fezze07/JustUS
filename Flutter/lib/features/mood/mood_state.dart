// =============================================================================
// MoodState - Mood screen state management
// =============================================================================

import 'package:justus/all_imports.dart';

class MoodState extends BaseState {
  MoodState({MoodRepository? repository})
      : _repo = repository ?? MoodRepository();

  final MoodRepository _repo;
  MoodRepository get repository => _repo;

  String _userMood = '😐';
  String _partnerMood = '😐';
  List<String> _recentEmojis = [];
  String? _userMoodUpdatedAt;
  String? _partnerMoodUpdatedAt;
  List<MoodEntry> _timeline = [];
  int _timelineOffset = 0;
  bool _hasMoreTimeline = false;

  String get userMood => _userMood;
  String get partnerMood => _partnerMood;
  List<String> get recentEmojis => _recentEmojis;
  String? get userMoodUpdatedAt => _userMoodUpdatedAt;
  String? get partnerMoodUpdatedAt => _partnerMoodUpdatedAt;
  List<MoodEntry> get timeline => _timeline;
  bool get hasMoreTimeline => _hasMoreTimeline;

  Future<void> init() async {
    await loadCache();
    _timeline = [];
    _timelineOffset = 0;
    _hasMoreTimeline = false;
    notifyListeners();
    await Future.wait([
      fetchMyMood(),
      fetchPartnerMood(),
      fetchRecentEmojis(),
      fetchTimeline(),
    ]);
  }

  Future<void> loadCache() async {
    final results = await Future.wait([
      StorageService.getMood('me'),
      StorageService.getMood('partner'),
      StorageService.getRecentEmojis(),
    ]);

    final myMood = results[0] as String?;
    if (myMood != null) {
      _userMood = myMood;
    }

    final partnerMood = results[1] as String?;
    if (partnerMood != null) {
      _partnerMood = partnerMood;
    }

    final recent = results[2] as List<String>?;
    if (recent != null && recent.isNotEmpty) {
      _recentEmojis = recent;
    }

    notifyListeners();
  }

  Future<void> loadPartnerMoodFromCache() async {
    final mood = await StorageService.getMood('partner');
    _partnerMood = mood ?? '😐';
    notifyListeners();
  }

  Future<void> fetchMyMood() async {
    await runSafe(() async {
      final result = await _repo.fetchMyMood();

      await handleResult(result, onSuccess: (value) async {
        _userMood = value.emoji ?? '😐';
        _userMoodUpdatedAt = value.createdAt;
        await StorageService.saveMood('me', _userMood);
      });
    }, showLoading: false);
  }

  Future<void> fetchPartnerMood() async {
    await runSafe(() async {
      final result = await _repo.fetchPartnerMood();

      await handleResult(result, onSuccess: (value) async {
        _partnerMood = value.emoji ?? '😐';
        _partnerMoodUpdatedAt = value.createdAt;
        await StorageService.saveMood('partner', _partnerMood);
      });
    }, showLoading: false);
  }

  Future<void> fetchRecentEmojis() async {
    await runSafe(() async {
      final result = await _repo.fetchRecentCoupleEmojis();

      await handleResult(result, onSuccess: (value) async {
        _recentEmojis = value;
        await StorageService.saveRecentEmojis(value);
      });
    }, showLoading: false);
  }

  Future<void> fetchTimeline() async {
    await runSafe(() async {
      final result = await _repo.fetchTimeline();
      await handleResult(result, onSuccess: (value) {
        _timeline = value;
        _timelineOffset = value.length;
        _hasMoreTimeline = value.length >= 4;
        notifyListeners();
      });
    }, showLoading: false);
  }

  Future<void> loadMoreTimeline() async {
    await runSafe(() async {
      final result =
          await _repo.fetchTimeline(offset: _timelineOffset);
      await handleResult(result, onSuccess: (value) {
        _timeline.addAll(value);
        _timelineOffset += value.length;
        _hasMoreTimeline = value.length >= 4;
        notifyListeners();
      });
    }, showLoading: false);
  }

  Future<void> updateMood(String emoji) async {
    await runSafe(() async {
      final now = DateTime.now().toUtc().toIso8601String();

      // Optimistic update
      final previousMood = _userMood;
      final previousTimestamp = _userMoodUpdatedAt;
      final previousTimeline = List<MoodEntry>.from(_timeline);
      _userMood = emoji;
      _userMoodUpdatedAt = now;
      _recentEmojis = [emoji, ..._recentEmojis.where((e) => e != emoji)];
      const maxTimelineItems = 5;
      _timeline.insert(
          0,
          MoodEntry(
              id: 0, userId: 0, isMine: true, emoji: emoji, createdAt: now));
      if (_timeline.length > maxTimelineItems) {
        _timeline.removeLast();
      } else {
        _timelineOffset++;
      }
      await StorageService.saveMood('me', emoji);
      notifyListeners();

      final result = await _repo.updateMood(emoji);

      await handleResult(result, onSuccess: (value) async {
        _userMood = value.emoji;
        _userMoodUpdatedAt = value.createdAt;
        await StorageService.saveMood('me', _userMood);
        setMessage('Mood aggiornato!');
      });

      if (result is! Success) {
        _userMood = previousMood;
        _userMoodUpdatedAt = previousTimestamp;
        _timeline = previousTimeline;
        _timelineOffset--;
        await StorageService.saveMood('me', previousMood);
        notifyListeners();
      }
    });
  }

  void clear() {
    _userMood = '😐';
    _partnerMood = '😐';
    _recentEmojis = [];
    notifyListeners();
  }
}
