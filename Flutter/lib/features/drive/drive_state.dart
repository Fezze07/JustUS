// =============================================================================
// DriveState - Drive/Gallery screen state management
// Uses Supabase incremental sync + Cloudflare R2 signed-URL upload
// =============================================================================

import 'package:justus/all_imports.dart';

class DriveState extends BaseState with CheckpointMixin {
  DriveState({DriveRepository? repository})
      : _repo = repository ?? DriveRepository();

  final DriveRepository _repo;

  List<DriveItem> _driveItems = [];
  DriveItem? _singleItem;
  bool _isUploading = false;
  bool _isSyncing = false;
  List<DriveItem> _favoriteItems = [];
  final CacheWriteQueue _cacheWriteQueue = CacheWriteQueue();

  List<DriveItem> get driveItems => _driveItems;
  DriveItem? get singleItem => _singleItem;
  bool get isUploading => _isUploading;
  List<DriveItem> get favoriteItems => _favoriteItems;

  /// Persists the current `_driveItems` snapshot through the serialized write
  /// queue (F-SC12): the snapshot is captured at call time and every write
  /// submitted later is guaranteed to land after it, so a concurrent sync can
  /// never let an older snapshot clobber a newer mutation.
  Future<void> _persistDriveCache() {
    final snapshot = List<DriveItem>.from(_driveItems);

    return _cacheWriteQueue.enqueue(
      () => StorageService.saveDriveItems(snapshot),
    );
  }

  void _rebuildFavorites() {
    _favoriteItems = _driveItems.where((item) => item.isFavorite == 1).toList();
  }

  // ---------------------------------------------------------------------------
  // Initial load: show cache instantly, then run incremental sync
  // ---------------------------------------------------------------------------
  bool _initialLoading = false;

  Future<void> initialLoad() async {
    if (_initialLoading) return;
    _initialLoading = true;
    try {
      await loadWithChangeDetection(
        loadFromCache: _loadFromCache,
        hasChanges: _hasDriveChanges,
        fetchFromNetwork: syncDriveItems,
      );
    } finally {
      _initialLoading = false;
    }
  }

  Future<bool> _hasDriveChanges() async {
    final changed = await _repo.hasNewDriveItems();
    if (changed) {
      await CacheService.saveCheckpoint(
          CacheService.kDriveItems, CacheService.kCheckpointEmpty);
      return true;
    }

    final countResult = await _repo.fetchDriveItemCount();
    final serverCount = countResult.valueOrNull;
    if (serverCount != null &&
        _driveItems.isNotEmpty &&
        serverCount != _driveItems.length) {
      await CacheService.saveCheckpoint(
          CacheService.kDriveItems, CacheService.kCheckpointEmpty);
      return true;
    }

    return false;
  }

  Future<void> _loadFromCache() async {
    final cached = await StorageService.getDriveItems();
    if (cached.isNotEmpty) {
      _driveItems = List.from(cached)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _rebuildFavorites();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Incremental sync: only fetch records with updated_at > last_sync_timestamp
  // ---------------------------------------------------------------------------
  Future<void> syncDriveItems() async {
    if (_isSyncing) return; // Debounce multiple simultaneous sync calls
    _isSyncing = true;

    await runSafe(() async {
      final countResult = await _repo.fetchDriveItemCount();
      final serverCount = countResult.valueOrNull;

      // A row-count mismatch against the local cache means items were deleted
      // server-side — the incremental `updated_at` cursor cannot see deletions,
      // so full-refetch (the merge below then drops the stale local rows).
      final needsFullRefresh = _driveItems.isNotEmpty &&
          serverCount != null &&
          serverCount != _driveItems.length;

      final result = needsFullRefresh
          ? await _repo.fetchDriveItems()
          : await _repo.fetchDriveItemsIncremental();

      await handleResult(result, onSuccess: (value) async {
        if (needsFullRefresh) {
          // Whole-list refetch: the server is the source of truth, so replace
          // instead of merging — otherwise rows deleted server-side would be
          // kept by the `kept + value` incremental merge.
          _driveItems = List<DriveItem>.from(value)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _rebuildFavorites();
          await _persistDriveCache();

          await saveMaxTimestampCheckpointFromItems(
            checkpointKey: CacheService.kDriveItems,
            items: value,
            timestampField: (item) => (item as DriveItem).updatedAt,
          );
          return;
        }

        if (value.isNotEmpty) {
          final updatedIds = value.map((e) => e.id).toSet();
          final kept =
              _driveItems.where((e) => !updatedIds.contains(e.id)).toList();
          _driveItems = [...kept, ...value]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _rebuildFavorites();
          await _persistDriveCache();

          await saveMaxTimestampCheckpointFromItems(
            checkpointKey: CacheService.kDriveItems,
            items: value,
            timestampField: (item) => (item as DriveItem).updatedAt,
          );
        } else if (await CacheService.getCheckpoint(CacheService.kDriveItems) ==
            null) {
          await CacheService.saveCheckpoint(
            CacheService.kDriveItems,
            DateTime.now().toUtc().toIso8601String(),
          );
        }
      });
    }, showLoading: false);

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    if (_isSyncing) return;
    _isSyncing = true;

    await runSafe(() async {
      final result = await _repo.fetchDriveItems();

      await handleResult(result, onSuccess: (value) async {
        _driveItems = value
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _rebuildFavorites();
        if (_singleItem != null) {
          final index =
              _driveItems.indexWhere((item) => item.id == _singleItem!.id);
          _singleItem = index == -1 ? null : _driveItems[index];
        }
        await _persistDriveCache();
        await _updateDriveCheckpointFromItems();
      });
    }, showLoading: false);

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> _updateDriveCheckpointFromItems() async {
    await saveMaxTimestampCheckpointFromItems(
      checkpointKey: CacheService.kDriveItems,
      items: _driveItems,
      timestampField: (item) => (item as DriveItem).updatedAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Load single item into detail view
  // ---------------------------------------------------------------------------
  void loadSingleItem(int itemId) {
    _singleItem = _driveItems.firstWhere(
      (item) => item.id == itemId,
      orElse: () => _driveItems.first,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Get a fresh signed download URL via the Edge Function
  // ---------------------------------------------------------------------------
  Future<String?> getSignedUrl(String filename) async {
    final result = await _repo.getMediaDownloadUrl(filename);

    return result.valueOrNull;
  }

  // ---------------------------------------------------------------------------
  // Upload: compress → R2 → Supabase metadata (NO direct backend upload)
  // ---------------------------------------------------------------------------
  Future<void> addFileItemR2({
    required String filePath,
    required String mimeType,
  }) async {
    _isUploading = true;
    setMessage('Caricamento in corso…');

    await runSafe(() async {
      final type = switch (true) {
        _ when mimeType.startsWith('image') => MediaType.image,
        _ when mimeType.startsWith('video') => MediaType.video,
        _ when mimeType.startsWith('audio') => MediaType.audio,
        _ => MediaType.file,
      };

      final result = await _repo.uploadDriveItemToR2(
        filePath: filePath,
        type: type,
        mimeType: mimeType,
      );

      await result.handleAsync(
        onSuccess: (value) async {
          _driveItems = [value, ..._driveItems];
          _rebuildFavorites();
          await _persistDriveCache();
          setMessage('Upload completato ✓');
        },
      );
    }, showLoading: false);

    _isUploading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Delete: optimistic + server confirm
  // ---------------------------------------------------------------------------
  Future<void> deleteItem(int id) async {
    final currentList = List<DriveItem>.from(_driveItems);
    _driveItems = _driveItems.where((item) => item.id != id).toList();
    _rebuildFavorites();
    await _persistDriveCache();
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.deleteDriveItem(id);

      result.handle(onSuccess: (_) {
        setMessage('Eliminato!');
      });

      if (result.isError) {
        _driveItems = currentList;
        _rebuildFavorites();
        await _persistDriveCache();
      }
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Reactions
  // ---------------------------------------------------------------------------
  Future<void> addReaction(int itemId, String emoji) async {
    await runSafe(() async {
      final result = await _repo.addReaction(itemId, emoji);

      await result.handleAsync(
        onSuccess: (_) async {
          _driveItems = _driveItems.map((item) {
            if (item.id == itemId) {
              return item.copyWith(reactions: [...item.reactions, emoji]);
            }
            return item;
          }).toList();
          _rebuildFavorites();
          await _persistDriveCache();
          if (_singleItem?.id == itemId) {
            _singleItem = _singleItem!.copyWith(
              reactions: [..._singleItem!.reactions, emoji],
            );
          }
        },
      );
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------
  Future<void> toggleFavorite(int itemId) async {
    final idx = _driveItems.indexWhere((item) => item.id == itemId);
    if (idx == -1) return;

    final item = _driveItems[idx];
    final isCurrentlyFavorite = item.isFavorite == 1;
    final updatedItem = item.copyWith(isFavorite: isCurrentlyFavorite ? 0 : 1);

    _driveItems[idx] = updatedItem;
    _rebuildFavorites();
    await _persistDriveCache();
    if (_singleItem?.id == itemId) _singleItem = updatedItem;
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.toggleFavorite(itemId, !isCurrentlyFavorite);

      if (!result.isSuccess) {
        _driveItems[idx] = item;
        _rebuildFavorites();
        await _persistDriveCache();
        if (_singleItem?.id == itemId) _singleItem = item;
        throw result;
      }
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------
  Future<void> clearMediaCache() async {
    await emptyAppMediaCaches();
  }

  void clear() {
    _driveItems = [];
    _rebuildFavorites();
    _singleItem = null;
    notifyListeners();
  }
}
