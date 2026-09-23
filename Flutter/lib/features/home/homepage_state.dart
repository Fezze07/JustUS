import 'dart:async';
import 'dart:collection';

import 'package:justus/all_imports.dart';

class HomepageState extends BaseState {
  HomepageState({MissYouRepository? repository})
      : _repo = repository ?? MissYouRepository();

  static const _maxTrackedMissYouKeys = 200;

  final MissYouRepository _repo;

  int _totalMissYou = 0;
  String? _message;
  bool _isLoading = false;

  /// Bumped by every incremental [addMissYou] so an authoritative
  /// [fetchTotalMissYou] snapshot begun before an event cannot overwrite the
  /// increment with a stale server total (F-RT5).
  int _missYouVersion = 0;

  /// Row ids already counted this session — makes [addMissYou] idempotent per
  /// `missyou` row (insert-only table), so a replay past the 80-event dedup
  /// window cannot double-count. Bounded FIFO, oldest evicted.
  final LinkedHashSet<int> _countedMissYouKeys = LinkedHashSet<int>();

  int get totalMissYou => _totalMissYou;
  @override
  String? get message => _message;
  @override
  bool get isLoading => _isLoading;

  @override
  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: () => CacheService.needsRefresh(
        CacheService.kMissYou,
      ),
      fetchFromNetwork: fetchTotalMissYou,
    );
  }

  Future<void> _loadFromCache() async {
    final cached = await StorageService.getTotalMissYou();
    if (cached != null) {
      _totalMissYou = cached;
      notifyListeners();
    }
  }

  Future<void> fetchTotalMissYou() async {
    final epoch = CacheService.checkpointEpoch;
    final versionAtFetchStart = _missYouVersion;
    final result = await _repo.fetchMissYouTotal();

    await result.handleAsync(
      onSuccess: (value) async {
        if (versionAtFetchStart != _missYouVersion) {
          return fetchTotalMissYou();
        }
        _totalMissYou = value.total;
        await StorageService.saveTotalMissYou(value.total);
        await CacheService.saveCheckpoint(
          CacheService.kMissYou,
          DateTime.now().toUtc().toIso8601String(),
          epoch: epoch,
        );
      },
    );
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    await fetchTotalMissYou();
  }

  void addMissYou({int? rowId}) {
    if (rowId != null) {
      if (!_countedMissYouKeys.add(rowId)) return;
      if (_countedMissYouKeys.length > _maxTrackedMissYouKeys) {
        _countedMissYouKeys.remove(_countedMissYouKeys.first);
      }
    }
    _missYouVersion++;
    _totalMissYou += 1;
    unawaited(StorageService.saveTotalMissYou(_totalMissYou));
    notifyListeners();
  }

  DateTime? _lastMissYouSentAt;

  Future<bool> sendMissYou() async {
    final now = DateTime.now();
    if (_isLoading ||
        (_lastMissYouSentAt != null &&
            now.difference(_lastMissYouSentAt!) <
                const Duration(milliseconds: 1500))) {
      return false;
    }

    _lastMissYouSentAt = now;
    _isLoading = true;
    notifyListeners();
    final epoch = CacheService.checkpointEpoch;

    var success = false;
    try {
      final result = await _repo.sendMissYou();

      await result.handleAsync(
        onSuccess: (_) async {
          success = true;
          await CacheService.saveCheckpoint(
            CacheService.kMissYou,
            DateTime.now().toUtc().toIso8601String(),
            epoch: epoch,
          );
          _message = 'Mi manchi inviato!';
        },
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return success;
  }

  void clear() {
    _totalMissYou = 0;
    notifyListeners();
  }
}
