// =============================================================================
// DriveState - Drive/Gallery screen state management
// Uses Supabase incremental sync + Cloudflare R2 signed-URL upload
// =============================================================================

import 'package:justus/all_imports.dart';

class DriveState extends BaseState with CheckpointMixin {
  static const int _maxIncrementalPages = 10;

  DriveState({DriveRepository? repository})
      : _repo = repository ?? DriveRepository();

  final DriveRepository _repo;

  List<DriveItem> _driveItems = [];
  int _driveOffset = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  int? _selectedItemId;
  bool _isUploading = false;
  bool _isSyncing = false;
  List<DriveItem> _favoriteItems = [];
  int _favoriteOffset = 0;
  bool _hasMoreFavorites = false;
  bool _isLoadingMoreFavorites = false;
  bool _favoritesLoaded = false;
  bool _pendingFullRefresh = false;
  int? _serverItemCount;
  final CacheWriteQueue _cacheWriteQueue = CacheWriteQueue();
  final Map<int, String> _myReactionEmoji = {};

  List<DriveItem> get driveItems => _driveItems;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  DriveItem? get singleItem {
    final id = _selectedItemId;
    if (id == null) return null;
    for (final item in _driveItems) {
      if (item.id == id) return item;
    }
    for (final item in _favoriteItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool get isUploading => _isUploading;
  List<DriveItem> get favoriteItems => _favoriteItems;
  bool get hasMoreFavorites => _hasMoreFavorites;
  bool get isLoadingMoreFavorites => _isLoadingMoreFavorites;

  int _compareDriveItems(DriveItem a, DriveItem b) {
    final byCreated = b.createdAt.compareTo(a.createdAt);
    return byCreated != 0 ? byCreated : b.id.compareTo(a.id);
  }

  void _mergeDriveItems(List<DriveItem> incoming) {
    final incomingIds = incoming.map((item) => item.id).toSet();
    final kept =
        _driveItems.where((item) => !incomingIds.contains(item.id)).toList();
    _driveItems = [...kept, ...incoming]..sort(_compareDriveItems);
  }

  void _applyToFavorites(Iterable<DriveItem> changed) {
    if (_favoriteItems.isEmpty) return;

    final before = _favoriteItems.length;
    final byId = {for (final item in changed) item.id: item};
    _favoriteItems = _favoriteItems
        .map((item) => byId[item.id] ?? item)
        .where((item) => item.isFavorite == 1)
        .toList()
      ..sort(_compareDriveItems);

    // Removed rows shrink the server-side page window: keep the next offset
    // aligned so a later page does not skip a favorite.
    final removed = before - _favoriteItems.length;
    if (removed > 0) {
      _favoriteOffset -= removed;
      if (_favoriteOffset < 0) _favoriteOffset = 0;
    }
  }

  void _addFavorite(DriveItem item) {
    if (_favoriteItems.any((favorite) => favorite.id == item.id)) {
      _applyToFavorites([item]);
      return;
    }

    final withinLoadedWindow = !_favoritesLoaded ||
        !_hasMoreFavorites ||
        _favoriteItems.isEmpty ||
        _compareDriveItems(item, _favoriteItems.last) <= 0;
    if (!withinLoadedWindow) return;

    _favoriteItems = [..._favoriteItems, item]..sort(_compareDriveItems);
    if (_favoritesLoaded) _favoriteOffset = _favoriteItems.length;
  }

  void _removeFavorite(int itemId) {
    final before = _favoriteItems.length;
    _favoriteItems = _favoriteItems.where((item) => item.id != itemId).toList();
    if (_favoriteItems.length < before && _favoriteOffset > 0) {
      _favoriteOffset--;
    }
  }

  void _updateHasMore({required int pageLength, int? serverCount}) {
    if (pageLength == 0) {
      _hasMore = false;
    } else if (serverCount != null) {
      _hasMore = _driveItems.length < serverCount;
    } else {
      _hasMore = pageLength >= DriveRepository.drivePageSize;
    }
  }

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

  // ---------------------------------------------------------------------------
  // Initial load: show cache instantly, then run incremental sync
  // ---------------------------------------------------------------------------
  bool _initialLoading = false;

  /// Revalidation probe cache. The probe is one RPC instead of the previous
  /// `updated_at` GET + `count()` HEAD pair, and it is memoized for [_probeTtl]
  /// because re-entering the drive/favorites tab re-ran the whole gate on every
  /// visit, while a partner's change is already pushed by realtime.
  static const Duration _probeTtl = Duration(seconds: 10);
  DriveChangeProbe? _probe;
  DateTime? _probeAt;

  void _invalidateProbe() {
    _probe = null;
    _probeAt = null;
  }

  Future<DriveChangeProbe?> _fetchProbe() async {
    final probe = _probe;
    final at = _probeAt;
    if (probe != null &&
        at != null &&
        DateTime.now().difference(at) < _probeTtl) {
      return probe;
    }

    final result = await _repo.fetchChangeProbe();
    final fresh = result.valueOrNull;
    // On error keep serving the cache: an unreachable server must not look like
    // "everything changed" (that would refetch on every tab visit).
    if (fresh == null) return null;

    _probe = fresh;
    _probeAt = DateTime.now();
    return fresh;
  }

  Future<void> initialLoad() async {
    if (_initialLoading) return;
    _initialLoading = true;
    final epoch = CacheService.checkpointEpoch;
    try {
      await loadWithChangeDetection(
        loadFromCache: _loadFromCache,
        hasChanges: _hasDriveChanges,
        fetchFromNetwork: () => syncDriveItems(epoch: epoch),
      );
    } finally {
      _initialLoading = false;
    }
  }

  /// Returns true when the local list must be re-synced.
  ///
  /// The probe's `updated_at` cursor catches inserts/updates; its row count
  /// catches deletions, which the cursor cannot see (F-SC7). A loaded page is
  /// smaller than the server total by design, so only a drop below the loaded
  /// count or the previously known server total is a deletion.
  Future<bool> _hasDriveChanges() async {
    final probe = await _fetchProbe();
    if (probe == null) return false;

    final checkpoint =
        await CacheService.getCheckpoint(CacheService.kDriveItems);
    final serverCount = probe.itemCount;
    final previousServerCount = _serverItemCount;
    if (serverCount != null) _serverItemCount = serverCount;

    final loadedExceedsServer = serverCount != null &&
        _driveItems.isNotEmpty &&
        serverCount < _driveItems.length;
    final serverCountDropped = serverCount != null &&
        previousServerCount != null &&
        serverCount < previousServerCount;
    if (loadedExceedsServer || serverCountDropped) {
      _pendingFullRefresh = true;
    }
    if (serverCount != null) {
      _hasMore = _driveItems.length < serverCount;
    }

    final serverMax = probe.maxUpdatedAt;
    // An empty server has nothing to load, and its EMPTY checkpoint must not
    // force a refetch on every visit.
    if (serverMax == null) return _pendingFullRefresh;

    if (checkpoint == null || checkpoint == CacheService.kCheckpointEmpty) {
      return true;
    }

    final serverDate = DateTime.tryParse(serverMax);
    final checkpointDate = DateTime.tryParse(checkpoint);
    if (serverDate != null &&
        checkpointDate != null &&
        serverDate.isAfter(checkpointDate)) {
      return true;
    }

    return _pendingFullRefresh;
  }

  Future<void> _loadFromCache() async {
    final cached = await StorageService.getDriveItems();
    if (cached.isNotEmpty) {
      _driveItems = List.from(cached)..sort(_compareDriveItems);
      _driveOffset = _driveItems.length;
      _hasMore = cached.length >= DriveRepository.drivePageSize;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Incremental sync: only fetch records with updated_at >= last_sync_timestamp
  // ---------------------------------------------------------------------------
  Future<void> syncDriveItems({int? epoch}) async {
    if (_isSyncing) return; // Debounce multiple simultaneous sync calls
    _isSyncing = true;
    final effectiveEpoch = epoch ?? CacheService.checkpointEpoch;

    await runSafe(() async {
      // Same probe as the change gate: on the initial-load path it is memoized,
      // so the deletion check costs no extra round trip.
      final probe = await _fetchProbe();
      final serverCount = probe?.itemCount;
      final previousServerCount = _serverItemCount;
      if (serverCount != null) _serverItemCount = serverCount;

      final serverCountDropped = serverCount != null &&
          previousServerCount != null &&
          serverCount < previousServerCount;
      final loadedExceedsServer = serverCount != null &&
          _driveItems.isNotEmpty &&
          serverCount < _driveItems.length;
      var needsFullRefresh = _driveItems.isEmpty ||
          _pendingFullRefresh ||
          serverCountDropped ||
          loadedExceedsServer;
      var incrementalCapReached = false;
      _pendingFullRefresh = false;

      if (!needsFullRefresh) {
        final changes = <DriveItem>[];
        var offset = 0;

        for (var page = 0; page < _maxIncrementalPages; page++) {
          final incremental =
              await _repo.fetchDriveItemsIncremental(offset: offset);
          final value = incremental.valueOrNull;
          if (value == null) {
            await handleResult(incremental);
            return;
          }

          changes.addAll(value);
          if (value.length < DriveRepository.drivePageSize) {
            if (changes.isNotEmpty) {
              _mergeDriveItems(changes);
              _applyToFavorites(changes);
              await _persistDriveCache();
              _invalidateProbe();

              await saveMaxTimestampCheckpointFromItems(
                checkpointKey: CacheService.kDriveItems,
                items: changes,
                timestampField: (item) => (item as DriveItem).updatedAt,
                epoch: effectiveEpoch,
              );
            } else if (await CacheService.getCheckpoint(
                    CacheService.kDriveItems) ==
                null) {
              await CacheService.saveCheckpoint(
                CacheService.kDriveItems,
                DateTime.now().toUtc().toIso8601String(),
                epoch: effectiveEpoch,
              );
            }

            if (serverCount != null) {
              _hasMore = _driveItems.length < serverCount;
            }
            return;
          }

          offset += value.length;
        }

        // Do not advance the checkpoint: the cap means some changed rows were
        // not observed. Page one refreshes the visible gallery while a later
        // sync safely retries from the previous cursor.
        incrementalCapReached = true;
        needsFullRefresh = true;
      }

      final result = await _repo.fetchDriveItems();
      await handleResult(result, onSuccess: (value) async {
        _driveItems = List<DriveItem>.from(value)..sort(_compareDriveItems);
        _driveOffset = value.length;
        _updateHasMore(pageLength: value.length, serverCount: serverCount);
        _applyToFavorites(value);
        await _persistDriveCache();
        _invalidateProbe();
        if (!incrementalCapReached) {
          await _saveDriveCheckpointFromProbe(probe, value, effectiveEpoch);
        }
      });
    }, showLoading: false);

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    await runSafe(() async {
      final serverCount = _serverItemCount;
      final result = await _repo.fetchDriveItems(offset: _driveOffset);

      await handleResult(result, onSuccess: (value) async {
        _mergeDriveItems(value);
        _driveOffset += value.length;
        _updateHasMore(pageLength: value.length, serverCount: serverCount);
        _applyToFavorites(value);
        await _persistDriveCache();
        _invalidateProbe();
        notifyListeners();
      });
    }, showLoading: false);

    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> loadFavorites() async {
    if (_isLoadingMoreFavorites) return;
    _isLoadingMoreFavorites = true;
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.fetchFavoriteDriveItems();

      await handleResult(result, onSuccess: (value) async {
        // Refetch the first page on every favorites visit: a partner's toggle
        // can land outside the loaded window, and the reset keeps the list
        // fresh the same way the drive grid resets on realtime events.
        _favoriteItems = List<DriveItem>.from(value)..sort(_compareDriveItems);
        _favoriteOffset = value.length;
        _hasMoreFavorites = value.length >= DriveRepository.drivePageSize;
        _favoritesLoaded = true;
        notifyListeners();
      });
    }, showLoading: false);

    _isLoadingMoreFavorites = false;
    notifyListeners();
  }

  Future<void> loadMoreFavorites() async {
    if (_isLoadingMoreFavorites || !_favoritesLoaded || !_hasMoreFavorites) {
      return;
    }
    _isLoadingMoreFavorites = true;
    notifyListeners();

    await runSafe(() async {
      final result =
          await _repo.fetchFavoriteDriveItems(offset: _favoriteOffset);

      await handleResult(result, onSuccess: (value) async {
        final knownIds = _favoriteItems.map((item) => item.id).toSet();
        _favoriteItems = [
          ..._favoriteItems,
          ...value.where((item) => !knownIds.contains(item.id)),
        ]..sort(_compareDriveItems);
        _favoriteOffset += value.length;
        _hasMoreFavorites = value.length >= DriveRepository.drivePageSize;
        notifyListeners();
      });
    }, showLoading: false);

    _isLoadingMoreFavorites = false;
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    if (_isSyncing) return;
    _isSyncing = true;
    final epoch = CacheService.checkpointEpoch;

    await runSafe(() async {
      final probe = await _fetchProbe();
      final serverCount = probe?.itemCount;
      if (serverCount != null) _serverItemCount = serverCount;

      final result = await _repo.fetchDriveItems();

      await handleResult(result, onSuccess: (value) async {
        _driveItems = List<DriveItem>.from(value)..sort(_compareDriveItems);
        _driveOffset = value.length;
        _updateHasMore(pageLength: value.length, serverCount: serverCount);
        _applyToFavorites(value);
        await _persistDriveCache();
        _invalidateProbe();
        await _saveDriveCheckpointFromProbe(probe, value, epoch);
      });
    }, showLoading: false);

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> _saveDriveCheckpointFromProbe(
    DriveChangeProbe? probe,
    List<DriveItem> fallbackItems,
    int epoch,
  ) async {
    if (probe == null) {
      await saveMaxTimestampCheckpointFromItems(
        checkpointKey: CacheService.kDriveItems,
        items: fallbackItems,
        timestampField: (item) => (item as DriveItem).updatedAt,
        epoch: epoch,
      );
      return;
    }

    await CacheService.saveCheckpoint(
      CacheService.kDriveItems,
      probe.maxUpdatedAt ?? CacheService.kCheckpointEmpty,
      epoch: epoch,
    );
  }

  // ---------------------------------------------------------------------------
  // Load single item into detail view
  // ---------------------------------------------------------------------------
  void loadSingleItem(int itemId) {
    final exists = _driveItems.any((item) => item.id == itemId) ||
        _favoriteItems.any((item) => item.id == itemId);
    if (!exists) return;

    _selectedItemId = itemId;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Upload: compress → R2 → Supabase metadata (NO direct backend upload)
  // ---------------------------------------------------------------------------
  Future<void> addFileItemR2({
    required String filePath,
    required String mimeType,
  }) async {
    _isUploading = true;
    notifyListeners();

    await runSafe(() async {
      setMessage(LanguageHelper.appLoc.drive_uploadInProgress);
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

      await handleResult(
        result,
        onSuccess: (value) async {
          _driveItems = [value, ..._driveItems]..sort(_compareDriveItems);
          _driveOffset++;
          await _persistDriveCache();
          _invalidateProbe();
          setMessage(LanguageHelper.appLoc.drive_uploadComplete);
        },
      );
    }, showLoading: false);

    _isUploading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Delete: optimistic + server confirm
  // ---------------------------------------------------------------------------
  Future<bool> deleteItem(int id) async {
    final currentList = List<DriveItem>.from(_driveItems);
    final currentOffset = _driveOffset;
    final currentFavorites = List<DriveItem>.from(_favoriteItems);
    final currentFavoriteOffset = _favoriteOffset;
    final index = _driveItems.indexWhere((item) => item.id == id);
    final wasInLoadedWindow = index != -1 && index < _driveOffset;

    _driveItems = _driveItems.where((item) => item.id != id).toList();
    if (wasInLoadedWindow && _driveOffset > 0) _driveOffset--;
    _removeFavorite(id);
    await _persistDriveCache();
    _invalidateProbe();
    notifyListeners();

    return runSafe(() async {
      final result = await _repo.deleteDriveItem(id);

      if (result is! Success) {
        _driveItems = currentList;
        _driveOffset = currentOffset;
        _favoriteItems = currentFavorites;
        _favoriteOffset = currentFavoriteOffset;
        await _persistDriveCache();
        _invalidateProbe();
        throw result;
      }

      setMessage(LanguageHelper.appLoc.drive_deleted);
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
          final previous = _myReactionEmoji[itemId];
          _myReactionEmoji[itemId] = emoji;

          DriveItem withReaction(DriveItem item) {
            if (item.id != itemId) return item;
            final reactions = List<String>.from(item.reactions);
            if (previous != null) reactions.remove(previous);
            reactions.add(emoji);
            return item.copyWith(reactions: reactions);
          }

          _driveItems = _driveItems.map(withReaction).toList();
          _favoriteItems = _favoriteItems.map(withReaction).toList();
          await _persistDriveCache();
          _invalidateProbe();
          setMessage(LanguageHelper.appLoc.drive_reactionAdded);
        },
      );
    }, showLoading: false);
  }

  // ---------------------------------------------------------------------------
  // Favorites
  // ---------------------------------------------------------------------------
  Future<void> toggleFavorite(int itemId) async {
    final idx = _driveItems.indexWhere((item) => item.id == itemId);
    final favoriteIdx = _favoriteItems.indexWhere((item) => item.id == itemId);
    // A favorite opened from the Favorites tab may live outside the loaded
    // drive pages, so resolve the item from either list.
    final item = idx != -1
        ? _driveItems[idx]
        : (favoriteIdx != -1 ? _favoriteItems[favoriteIdx] : null);
    if (item == null) return;

    final isCurrentlyFavorite = item.isFavorite == 1;
    final updatedItem = item.copyWith(isFavorite: isCurrentlyFavorite ? 0 : 1);
    final previousFavorites = List<DriveItem>.from(_favoriteItems);
    final previousFavoriteOffset = _favoriteOffset;

    if (idx != -1) _driveItems[idx] = updatedItem;
    if (updatedItem.isFavorite == 1) {
      _addFavorite(updatedItem);
    } else {
      _removeFavorite(itemId);
    }
    await _persistDriveCache();
    _invalidateProbe();
    notifyListeners();

    await runSafe(() async {
      final result = await _repo.toggleFavorite(itemId, !isCurrentlyFavorite);

      if (!result.isSuccess) {
        if (idx != -1) _driveItems[idx] = item;
        _favoriteItems = previousFavorites;
        _favoriteOffset = previousFavoriteOffset;
        await _persistDriveCache();
        _invalidateProbe();
        throw result;
      }

      if (isCurrentlyFavorite) {
        setMessage(LanguageHelper.appLoc.drive_favoriteRemoved);
      } else {
        setMessage(LanguageHelper.appLoc.drive_favoriteAdded);
      }
    }, showLoading: false);
  }

  void clear() {
    _driveItems = [];
    _driveOffset = 0;
    _hasMore = false;
    _isLoadingMore = false;
    _favoriteItems = [];
    _favoriteOffset = 0;
    _hasMoreFavorites = false;
    _isLoadingMoreFavorites = false;
    _favoritesLoaded = false;
    _pendingFullRefresh = false;
    _serverItemCount = null;
    _selectedItemId = null;
    _myReactionEmoji.clear();
    // The memoized probe is user-scoped: never let it survive a logout or a
    // partnership switch.
    _invalidateProbe();
    notifyListeners();
  }
}
