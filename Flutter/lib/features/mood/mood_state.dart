// =============================================================================
// MoodState - Mood screen state management
// =============================================================================

import 'package:justus/all_imports.dart';

class MoodState extends BaseState with CheckpointMixin {
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

  Future<void> initHome() async {
    await loadWithChangeDetection(
      loadFromCache: loadCache,
      hasChanges: _hasMoodChanges,
      fetchFromNetwork: () async {
        await Future.wait([
          fetchMyMood(),
          fetchPartnerMood(),
        ]);
        await _updateMoodsCheckpoint();
      },
    );
  }

  Future<void> initMoodScreen() async {
    await loadWithChangeDetection(
      loadFromCache: _loadMoodScreenCache,
      hasChanges: _hasMoodChanges,
      fetchFromNetwork: () async {
        await Future.wait([
          fetchRecentEmojis(),
          fetchTimeline(),
        ]);
        await _updateMoodsCheckpoint();
      },
    );
  }

  Future<bool> _hasMoodChanges() async {
    final uid = await StorageService.getUserId();
    if (uid == null) return false;

    final changed = await _repo.hasNewMoods(uid, await StorageService.getPartnerId());
    if (changed) {
      // Optimistic checkpoint: prevent redundant fetches during rapid init cycles
      await CacheService.saveCheckpoint(CacheService.kMoods, CacheService.kCheckpointEmpty);
    }
    return changed;
  }

  Future<void> _updateMoodsCheckpoint() async {
    await saveMaxTimestampCheckpoint(
      checkpointKey: CacheService.kMoods,
      timestamps: [
        ..._timeline.map((entry) => entry.createdAt),
        _userMoodUpdatedAt,
        _partnerMoodUpdatedAt,
      ],
    );
  }

  Future<void> _loadMoodScreenCache() async {
    final results = await Future.wait([
      StorageService.getRecentEmojis(),
      StorageService.getTimeline(),
    ]);

    final cachedRecent = results[0] as List<String>;
    if (cachedRecent.isNotEmpty) {
      _recentEmojis = cachedRecent;
    }

    final cachedTimeline = results[1] as List<MoodEntry>;
    if (cachedTimeline.isNotEmpty) {
      const initialPageSize = 4;
      _timeline = cachedTimeline.take(initialPageSize).toList();
      _timelineOffset = _timeline.length;
      _hasMoreTimeline = cachedTimeline.length > initialPageSize;
    }

    notifyListeners();
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

      await result.handleAsync(
        onSuccess: (value) async {
          _userMood = value.emoji ?? '😐';
          _userMoodUpdatedAt = value.createdAt;
          await StorageService.saveMood('me', _userMood);
        },
      );
    }, showLoading: false);
  }

  Future<void> fetchPartnerMood() async {
    await runSafe(() async {
      final result = await _repo.fetchPartnerMood();

      await result.handleAsync(
        onSuccess: (value) async {
          _partnerMood = value.emoji ?? '😐';
          _partnerMoodUpdatedAt = value.createdAt;
          await StorageService.saveMood('partner', _partnerMood);
        },
      );
    }, showLoading: false);
  }

  Future<void> fetchRecentEmojis() async {
    await runSafe(() async {
      final result = await _repo.fetchRecentCoupleEmojis();

      await result.handleAsync(
        onSuccess: (value) async {
          _recentEmojis = value;
          await StorageService.saveRecentEmojis(value);
        },
      );
    }, showLoading: false);
  }

  Future<void> fetchTimeline() async {
    await runSafe(() async {
      final result = await _repo.fetchTimeline();
      await result.handleAsync(
        onSuccess: (value) async {
          _timeline = value;
          _timelineOffset = value.length;
          _hasMoreTimeline = value.length >= 4;
          await StorageService.saveTimeline(value);
          await _updateMoodsCheckpoint();
          notifyListeners();
        },
      );
    }, showLoading: false);
  }

  Future<void> loadMoreTimeline() async {
    await runSafe(() async {
      final result = await _repo.fetchTimeline(offset: _timelineOffset);
      await result.handleAsync(
        onSuccess: (value) async {
          _timeline.addAll(value);
          _timelineOffset += value.length;
          _hasMoreTimeline = value.length >= 4;
          await StorageService.saveTimeline(_timeline);
          await _updateMoodsCheckpoint();
          notifyListeners();
        },
      );
    }, showLoading: false);
  }

  Future<void> refreshFromRealtime({int? changedUserId}) async {
    final uid = await StorageService.getUserId();

    // Own action: optimistic update already handled everything
    if (changedUserId != null && changedUserId == uid) {
      await _updateMoodsCheckpoint();
      return;
    }

    final futures = <Future<void>>[
      fetchRecentEmojis(),
      fetchTimeline(),
    ];

    if (changedUserId != null) {
      // Partner's action: skip our mood, fetch partner's
      futures.add(fetchPartnerMood());
    } else {
      // Unknown: safe fallback — fetch everything
      futures.addAll([fetchMyMood(), fetchPartnerMood()]);
    }

    await Future.wait(futures);
    await _updateMoodsCheckpoint();
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
      await StorageService.saveRecentEmojis(_recentEmojis);
      await StorageService.saveTimeline(_timeline);
      notifyListeners();

      final result = await _repo.updateMood(emoji);

      await result.handleAsync(
        onSuccess: (value) async {
          _userMood = value.emoji;
          _userMoodUpdatedAt = value.createdAt;
          await StorageService.saveMood('me', _userMood);
          await _updateMoodsCheckpoint();
          setMessage('Mood aggiornato!');
        },
      );

      if (result.isError) {
        _userMood = previousMood;
        _userMoodUpdatedAt = previousTimestamp;
        _timeline = previousTimeline;
        _timelineOffset--;
        await StorageService.saveMood('me', previousMood);
        await StorageService.saveRecentEmojis(_recentEmojis);
        await StorageService.saveTimeline(_timeline);
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
