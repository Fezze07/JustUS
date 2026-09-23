import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

class BucketState extends BaseState
    with CheckpointMixin, WidgetsBindingObserver {
  final BucketRepository _repository;

  BucketState({BucketRepository? repository})
      : _repository = repository ?? BucketRepository() {
    // Flush the pending debounced cache write when the app goes to background,
    // so the last few seconds of realtime changes are not lost (F-SC13).
    WidgetsBinding.instance.addObserver(this);
  }

  List<BucketItem> _items = [];
  final Set<int> _knownIds = {};
  bool _isInitLoading = false;
  Timer? _cacheDebounceTimer;
  final CacheWriteQueue _cacheWriteQueue = CacheWriteQueue();

  /// Monotonic counter bumped by every incremental realtime mutation. A full
  /// snapshot fetch that captured an older value will NOT clobber the list —
  /// the already-applied events are the fresher source of truth (F-RT4).
  int _itemsVersion = 0;

  List<BucketItem> get items => _items;

  @override
  void dispose() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    final epoch = CacheService.checkpointEpoch;
    unawaited(_flushCache(epoch: epoch));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _cacheDebounceTimer?.cancel();
        _cacheDebounceTimer = null;
        final epoch = CacheService.checkpointEpoch;
        unawaited(_flushCache(epoch: epoch));
        break;
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        break;
    }
  }

  // --- Init & Fetch ---

  Future<void> init() async {
    if (_isInitLoading) return;
    _isInitLoading = true;
    final epoch = CacheService.checkpointEpoch;
    try {
      await loadWithChangeDetection(
        loadFromCache: _loadFromCache,
        hasChanges: () => _hasBucketChanges(epoch: epoch),
        fetchFromNetwork: () => fetchBucket(epoch: epoch),
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

  Future<bool> _hasBucketChanges({required int epoch}) async {
    final partnershipData = await _repository.getActivePartnership();
    final partnershipId = partnershipData?['partnership_id'] as int?;
    if (partnershipId == null) return false;

    final changed = await _repository.hasNewBucketItems(partnershipId);
    if (changed) {
      await CacheService.saveCheckpoint(CacheService.kBucketItems,
          CacheService.kCheckpointEmpty,
          epoch: epoch);
    }
    return changed;
  }

  Future<void> _updateBucketCheckpoint({required int epoch}) async {
    await saveMaxTimestampCheckpointFromItems(
      checkpointKey: CacheService.kBucketItems,
      items: _items,
      timestampField: (item) => (item as BucketItem).updatedAt,
      epoch: epoch,
    );
  }

  Future<void> fetchBucket({required int epoch}) async {
    await runSafe(() async {
      final versionAtFetchStart = _itemsVersion;
      final result = await _repository.fetchBucketList();
      await handleResult(result, onSuccess: (value) async {
        if (versionAtFetchStart != _itemsVersion) return;
        _items = value;
        _knownIds
          ..clear()
          ..addAll(_items.map((i) => i.id));
        await _flushCache(epoch: epoch);
      });
    });
  }

  Future<void> refreshFromRealtime() async {
    final epoch = CacheService.checkpointEpoch;
    await runSafe(() async {
      final versionAtFetchStart = _itemsVersion;
      final result = await _repository.fetchBucketList();
      await handleResult(result, onSuccess: (value) async {
        if (versionAtFetchStart != _itemsVersion) return;
        _items = value;
        _knownIds
          ..clear()
          ..addAll(_items.map((i) => i.id));
        await _flushCache(epoch: epoch);
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
      if (result.isError) {
        await handleResult(result);
      }
    });
  }

  Future<void> toggleDone(int id, bool done) async {
    await runSafe(() async {
      final result = await _repository.toggleBucketItem(id, done);
      if (result.isError) {
        await handleResult(result);
      }
    });
  }

  Future<void> deleteItem(int id) async {
    await runSafe(() async {
      final result = await _repository.deleteBucketItem(id);
      if (result.isError) {
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
    final epoch = CacheService.checkpointEpoch;
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
      _itemsVersion++;
      _scheduleCacheSave(epoch);
      notifyListeners();
    }
  }

  // --- Debounced cache ---

  void _scheduleCacheSave(int epoch) {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_flushCache(epoch: epoch));
    });
  }

  Future<void> _flushCache({required int epoch}) {
    final snapshot = List<BucketItem>.from(_items);

    return _cacheWriteQueue.enqueue(() async {
      await StorageService.saveBucketList(snapshot);
      await _updateBucketCheckpoint(epoch: epoch);
    });
  }

  void clear() {
    _cacheDebounceTimer?.cancel();
    _cacheDebounceTimer = null;
    _itemsVersion++;
    _items = [];
    _knownIds.clear();
    notifyListeners();
  }
}
