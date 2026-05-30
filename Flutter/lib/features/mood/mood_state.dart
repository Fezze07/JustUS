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

  String get userMood => _userMood;
  String get partnerMood => _partnerMood;
  List<String> get recentEmojis => _recentEmojis;

  Future<void> init() async {
    await loadCache();
    await Future.wait([
      fetchMyMood(),
      fetchPartnerMood(),
      fetchRecentEmojis(),
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
        await StorageService.saveMood('me', _userMood);
      });
    }, showLoading: false);
  }

  Future<void> fetchPartnerMood() async {
    await runSafe(() async {
      final result = await _repo.fetchPartnerMood();

      await handleResult(result, onSuccess: (value) async {
        _partnerMood = value.emoji ?? '😐';
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

  Future<void> updateMood(String emoji) async {
    await runSafe(() async {
      // Optimistic update
      final previousMood = _userMood;
      _userMood = emoji;
      await StorageService.saveMood('me', emoji);
      notifyListeners();

      final result = await _repo.updateMood(emoji);

      await handleResult(result, onSuccess: (value) async {
        _userMood = value.emoji;
        await StorageService.saveMood('me', _userMood);
        setMessage('Mood aggiornato!');
      });

      if (result is! Success) {
        _userMood = previousMood;
        await StorageService.saveMood('me', previousMood);
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
