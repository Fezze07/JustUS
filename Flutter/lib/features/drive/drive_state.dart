// =============================================================================
// DriveState - Drive/Gallery screen state management
// Uses Supabase incremental sync + Cloudflare R2 signed-URL upload
// =============================================================================

import 'package:justus/all_imports.dart';

class DriveState extends BaseState {
  DriveState({DriveRepository? repository})
      : _repo = repository ?? DriveRepository();

  final DriveRepository _repo;

  List<DriveItem> _driveItems = [];
  DriveItem? _singleItem;
  bool _isUploading = false;
  bool _isSyncing = false;
  List<DriveItem> _favoriteItems = [];

  List<DriveItem> get driveItems => _driveItems;
  DriveItem? get singleItem => _singleItem;
  bool get isUploading => _isUploading;
  List<DriveItem> get favoriteItems => _favoriteItems;

  void _rebuildFavorites() {
    _favoriteItems = _driveItems.where((item) => item.isFavorite == 1).toList();
  }

  // ---------------------------------------------------------------------------
  // Initial load: show cache instantly, then run incremental sync
  // ---------------------------------------------------------------------------
  Future<void> initialLoad() async {
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: _hasDriveChanges,
      fetchFromNetwork: syncDriveItems,
    );
  }

  Future<bool> _hasDriveChanges() async {
    final changed = await _repo.hasNewDriveItems();
    if (changed) {
      await CacheService.saveCheckpoint(
          CacheService.kDriveItems, CacheService.kCheckpointEmpty);
    }
    return changed;
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
      final result = await _repo.fetchDriveItemsIncremental();

      await handleResult(result, onSuccess: (value) async {
        if (value.isNotEmpty) {
          // Merge: replace/add changed items, preserve unchanged ones
          final updatedIds = value.map((e) => e.id).toSet();
          final kept =
              _driveItems.where((e) => !updatedIds.contains(e.id)).toList();
          _driveItems = [...kept, ...value]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _rebuildFavorites();
          await StorageService.saveDriveItems(_driveItems);

          // Advance timestamp safely using the server's maximum updated_at
          final latestUpdated = value
              .map((e) => DateTime.tryParse(e.updatedAt))
              .whereType<DateTime>()
              .toList()
            ..sort((a, b) => b.compareTo(a));

          if (latestUpdated.isNotEmpty) {
            await CacheService.saveCheckpoint(
              CacheService.kDriveItems,
              latestUpdated.first.toUtc().toIso8601String(),
            );
          }
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

    return result is Success<String?> ? result.value : null;
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

      await handleResult(result, onSuccess: (value) async {
        _driveItems = [value, ..._driveItems];
        _rebuildFavorites();
        await StorageService.saveDriveItems(_driveItems);
        setMessage('Upload completato ✓');
      });
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
    await StorageService.saveDriveItems(_driveItems);
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.deleteDriveItem(id);

      await handleResult(result, onSuccess: (_) {
        setMessage('Eliminato!');
      });

      if (result is! Success) {
        _driveItems = currentList;
        _rebuildFavorites();
        await StorageService.saveDriveItems(_driveItems);
      }
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Reactions
  // ---------------------------------------------------------------------------
  Future<void> addReaction(int itemId, String emoji) async {
    await runSafe(() async {
      final result = await _repo.addReaction(itemId, emoji);

      await handleResult(result, onSuccess: (_) async {
        _driveItems = _driveItems.map((item) {
          if (item.id == itemId) {
            return item.copyWith(reactions: [...item.reactions, emoji]);
          }

          return item;
        }).toList();
        _rebuildFavorites();
        await StorageService.saveDriveItems(_driveItems);
        if (_singleItem?.id == itemId) {
          _singleItem = _singleItem!.copyWith(
            reactions: [..._singleItem!.reactions, emoji],
          );
        }
      });
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
    await StorageService.saveDriveItems(_driveItems);
    if (_singleItem?.id == itemId) _singleItem = updatedItem;
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.toggleFavorite(itemId, !isCurrentlyFavorite);

      if (result is! Success) {
        _driveItems[idx] = item;
        _rebuildFavorites();
        await StorageService.saveDriveItems(_driveItems);
        if (_singleItem?.id == itemId) _singleItem = item;
        throw result;
      }
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------
  Future<void> clearMediaCache() async {
    await MediaCacheManager().emptyCache();
  }

  void clear() {
    _driveItems = [];
    _rebuildFavorites();
    _singleItem = null;
    notifyListeners();
  }
}
