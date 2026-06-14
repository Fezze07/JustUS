import 'dart:async';

import 'package:justus/all_imports.dart';

class BucketState extends BaseState {
  final BucketRepository _repository;

  BucketState({BucketRepository? repository})
      : _repository = repository ?? BucketRepository();

  List<BucketItem> _items = [];
  final Set<int> _knownIds = {};
  bool _isInitLoading = false;
  Timer? _cacheDebounceTimer;

  List<BucketItem> get items => _items;

  @override
  void dispose() {
    _cacheDebounceTimer?.cancel();
    unawaited(_flushCache());
    super.dispose();
  }

  // --- Init & Fetch ---

  Future<void> init() async {
    if (_isInitLoading) return;
    _isInitLoading = true;
    try {
      await loadWithChangeDetection(
        loadFromCache: _loadFromCache,
        hasChanges: _hasBucketChanges,
        fetchFromNetwork: fetchBucket,
      );
    } finally {
      _isInitLoading = false;
    }
  }

  Future<void> _loadFromCache() async {
    _items = await StorageService.getBucketList();
    _knownIds.addAll(_items.map((i) => i.id));
    notifyListeners();
  }

  Future<bool> _hasBucketChanges() async {
    final partnershipData = await _repository.getActivePartnership();
    final partnershipId = partnershipData?['partnership_id'] as int?;
    if (partnershipId == null) return false;

    final changed = await _repository.hasNewBucketItems(partnershipId);
    if (changed) {
      await CacheService.saveCheckpoint(CacheService.kBucketItems, CacheService.kCheckpointEmpty);
    }
    return changed;
  }

  Future<void> _updateBucketCheckpoint() async {
    if (_items.isEmpty) {
      await CacheService.saveCheckpoint(
          CacheService.kBucketItems, CacheService.kCheckpointEmpty);
      return;
    }

    final timestamps = _items
        .map((item) => DateTime.tryParse(item.createdAt))
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (timestamps.isNotEmpty) {
      await CacheService.saveCheckpoint(
        CacheService.kBucketItems,
        timestamps.first.toUtc().toIso8601String(),
      );
    }
  }

  Future<void> fetchBucket() async {
    await runSafe(() async {
      final result = await _repository.fetchBucketList();
      await handleResult(result, onSuccess: (value) async {
        _items = value;
        _knownIds
          ..clear()
          ..addAll(_items.map((i) => i.id));
        await _flushCache();
      });
    });
  }

  Future<void> refreshFromRealtime() async {
    await runSafe(() async {
      final result = await _repository.fetchBucketList();
      await handleResult(result, onSuccess: (value) async {
        _items = value;
        _knownIds
          ..clear()
          ..addAll(_items.map((i) => i.id));
        await _flushCache();
      });
    }, showLoading: false);
  }

  // --- Mutations (fire-and-forget, Realtime is source of truth) ---

  Future<void> addItem(String text, String category) async {
    if (text.trim().isEmpty) {
      setMessage('Inserisci del testo');

      return;
    }

    await runSafe(() async {
      final result = await _repository.addBucketItem(text, category);
      if (result is GenericError || result is NetworkError) {
        await handleResult(result);
      }
    });
  }

  Future<void> toggleDone(int id, bool done) async {
    await runSafe(() async {
      final result = await _repository.toggleBucketItem(id, done);
      if (result is GenericError || result is NetworkError) {
        await handleResult(result);
      }
    });
  }

  Future<void> deleteItem(int id) async {
    await runSafe(() async {
      final result = await _repository.deleteBucketItem(id);
      if (result is GenericError || result is NetworkError) {
        await handleResult(result);
      }
    });
  }

  // --- Realtime (single source of truth) ---

  Future<void> applyRealtimeEvent({
    required String eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) async {
    bool changed = false;

    switch (eventType) {
      case 'insert':
        final item = BucketItem.fromJson(newRecord);
        if (!_knownIds.add(item.id)) return;
        _items = [item, ..._items];
        changed = true;
      case 'update':
        final item = BucketItem.fromJson(newRecord);
        if (!_knownIds.contains(item.id)) return;
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index == -1) return;
        _items = _items.toList();
        _items[index] = item;
        changed = true;
      case 'delete':
        final id = (oldRecord['id'] as num?)?.toInt();
        if (id == null || !_knownIds.remove(id)) return;
        _items = _items.where((i) => i.id != id).toList();
        changed = true;
    }

    if (changed) {
      _scheduleCacheSave();
      notifyListeners();
    }
  }

  // --- Debounced cache ---

  void _scheduleCacheSave() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_flushCache());
    });
  }

  Future<void> _flushCache() async {
    await StorageService.saveBucketList(_items);
    await _updateBucketCheckpoint();
  }

  void clear() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = null;
    _items = [];
    _knownIds.clear();
    notifyListeners();
  }
}
