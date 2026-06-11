// =============================================================================
// BucketState - Bucket list screen state management
// =============================================================================

import 'package:justus/all_imports.dart';

class BucketState extends BaseState {
  final BucketRepository _repository;

  BucketState({BucketRepository? repository})
      : _repository = repository ?? BucketRepository();

  List<BucketItem> _items = [];

  List<BucketItem> get items => _items;

  Future<void> init() async {
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: _hasBucketChanges,
      fetchFromNetwork: fetchBucket,
    );
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
}
