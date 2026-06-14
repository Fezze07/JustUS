// =============================================================================
// BucketState - Bucket list screen state management
// =============================================================================

import 'package:justus/all_imports.dart';

class BucketState extends BaseState {
  final BucketRepository _repository;

  BucketState({BucketRepository? repository})
      : _repository = repository ?? BucketRepository();

  List<BucketItem> _items = [];
  bool _isInitLoading = false;

  List<BucketItem> get items => _items;

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
        await StorageService.saveBucketList(_items);
        await _updateBucketCheckpoint();
      });
    });
  }

  Future<void> refreshFromRealtime() async {
    await runSafe(() async {
      final result = await _repository.fetchBucketList();
      await handleResult(result, onSuccess: (value) async {
        _items = value;
        await StorageService.saveBucketList(_items);
        await _updateBucketCheckpoint();
      });
    }, showLoading: false);
  }

  Future<void> addItem(String text, String category) async {
    if (text.trim().isEmpty) {
      setMessage('Inserisci del testo');

      return;
    }

    await runSafe(() async {
      final result = await _repository.addBucketItem(text, category);
      await handleResult(result, onSuccess: (item) async {
        _items = [item, ..._items];
        await StorageService.saveBucketList(_items);
        await _updateBucketCheckpoint();
      });
    });
  }

  Future<void> toggleDone(int id) async {
    await runSafe(() async {
      final item = _items.firstWhere((i) => i.id == id);
      final newDoneStatus = !item.done;

      final result = await _repository.toggleBucketItem(id, newDoneStatus);
      if (result is Success<BucketItem>) {
        _items = _items.map((i) {
          if (i.id == id) {
            return i.copyWith(done: newDoneStatus);
          }

          return i;
        }).toList();
        await StorageService.saveBucketList(_items);
      }
    });
  }

  Future<void> deleteItem(int id) async {
    await runSafe(() async {
      final result = await _repository.deleteBucketItem(id);
      if (result is Success) {
        _items = _items.where((item) => item.id != id).toList();
        await StorageService.saveBucketList(_items);
      }
    });
  }

  Future<void> flushPendingChanges(Map<int, bool> changes) async {
    if (changes.isEmpty) return;
    await runSafe(() async {
      final futures = changes.entries
          .map((entry) => _repository.toggleBucketItem(entry.key, entry.value));
      final results = await Future.wait(futures);
      for (final result in results) {
        if (result is Success<BucketItem>) {
          _items = _items
              .map((i) => i.id == result.value.id ? result.value : i)
              .toList();
        }
      }
      await StorageService.saveBucketList(_items);
      await _updateBucketCheckpoint();
    });
  }

  void clear() {
    _items = [];
    notifyListeners();
  }

  Future<void> applyRealtimeEvent({
    required String eventType,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
  }) async {
    switch (eventType) {
      case 'insert':
        final item = BucketItem.fromJson(newRecord);
        if (_items.any((i) => i.id == item.id)) return;
        _items = [item, ..._items];
        await StorageService.saveBucketList(_items);
        await _updateBucketCheckpoint();
        notifyListeners();
        break;
      case 'update':
        final item = BucketItem.fromJson(newRecord);
        final index = _items.indexWhere((i) => i.id == item.id);
        if (index != -1) {
          _items = _items.toList();
          _items[index] = item;
          await StorageService.saveBucketList(_items);
          notifyListeners();
        }
        break;
      case 'delete':
        final id = (oldRecord['id'] as num?)?.toInt();
        if (id != null) {
          _items = _items.where((i) => i.id != id).toList();
          await StorageService.saveBucketList(_items);
          await _updateBucketCheckpoint();
          notifyListeners();
        }
        break;
    }
  }
}
