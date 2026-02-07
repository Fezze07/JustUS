// =============================================================================
// DriveState - Drive/Gallery screen state management
// Dart equivalent of DriveViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';

class DriveState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  List<DriveItem> _driveItems = [];
  DriveItem? _singleItem;
  String? _message;
  bool _isLoading = false;
  bool _isUploading = false;

  List<DriveItem> get driveItems => _driveItems;
  DriveItem? get singleItem => _singleItem;
  String? get message => _message;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;

  List<DriveItem> get favoriteItems => 
      _driveItems.where((item) => item.isFavorite == 1).toList();

  void clearMessage() {
    _message = null;
  }
  
  DriveItem _resolveItemUrl(DriveItem item) {
    if (item.content.startsWith('/')) {
      return item.copyWith(content: '${ApiService.baseUrl}${item.content}');
    }
    return item;
  }

  Future<void> initialLoad() async {
    _isLoading = true;
    notifyListeners();

    // Load from cache first
    final cached = await StorageService.getDriveItems();
    if (cached.isNotEmpty) {
      _driveItems = cached
          .map((item) => _resolveItemUrl(item.copyWith(reactions: item.reactions)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }

    // Fetch from server
    final result = await _repo.fetchDriveItems();

    switch (result) {
      case Success(:final value):
        final items = value.items
            .map((item) => _resolveItemUrl(item.copyWith(reactions: item.reactions)))
            .toList();
        
        // Fetch reactions for each item
        final updatedItems = await Future.wait(
          items.map((item) async {
            final reactionsResult = await _repo.fetchReactions(item.id);
            if (reactionsResult is Success<DriveItemReactionsListResponse>) {
              final reactions = reactionsResult.value.reactions
                  .map((r) => r.emoji)
                  .toList();
              return item.copyWith(reactions: reactions);
            }
            return item;
          }),
        );

        _driveItems = updatedItems
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        await StorageService.saveDriveItems(_driveItems);
        await StorageService.saveLastSync(DateTime.now().toIso8601String());
      case GenericError(:final code, :final message):
        _message = message ?? 'Errore: $code';
      case NetworkError():
        _message = 'Errore rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  void loadSingleItem(int itemId) {
    _singleItem = _driveItems.firstWhere(
      (item) => item.id == itemId,
      orElse: () => _driveItems.first,
    );
    notifyListeners();
  }

  Future<void> syncDriveItems() async {
    final lastSync = await StorageService.getLastSync();
    if (lastSync == null) return;

    final result = await _repo.fetchDriveChanges(lastSync);

    switch (result) {
      case Success(:final value):
        // Apply changes
        for (final change in value.changes) {
          switch (change.action) {
            case 'create':
              if (change.item != null) {
                _driveItems.insert(0, _resolveItemUrl(change.item!));
              }
            case 'update':
              if (change.item != null) {
                final idx = _driveItems.indexWhere((i) => i.id == change.id);
                if (idx != -1) {
                  _driveItems[idx] = _resolveItemUrl(change.item!);
                }
              }
            case 'delete':
              _driveItems.removeWhere((i) => i.id == change.id);
          }
        }
        
        _driveItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await StorageService.saveDriveItems(_driveItems);
        await StorageService.saveLastSync(value.lastSync);
      case GenericError(:final code, :final message):
        _message = message ?? 'Errore: $code';
      case NetworkError():
        _message = 'Errore rete';
    }
    notifyListeners();
  }

  Future<void> addFileItem(
    List<int> fileBytes,
    String fileName,
    int fileSize,
    String mimeType,
  ) async {
    _isUploading = true;
    notifyListeners();

    if (fileSize > 3000000) {
      _message = '⚠️ Attenzione: il file è grande (${fileSize ~/ 1000000} MB), il caricamento potrebbe richiedere tempo';
      notifyListeners();
    }

    _message = 'Caricamento file: $fileName ...';
    notifyListeners();

    final uploadResult = await _repo.uploadDiary(fileBytes, fileName, mimeType);

    if (uploadResult is Success<String>) {
      final url = uploadResult.value;
      final type = switch (true) {
        _ when mimeType.startsWith('image') => 'image',
        _ when mimeType.startsWith('video') => 'video',
        _ when mimeType.startsWith('audio') => 'audio',
        _ => 'file',
      };

      final metadata = {
        'filename': fileName,
        'size': fileSize,
        'mime': mimeType,
      };

      final createResult = await _repo.createDriveItem(type, url, metadata);
      if (createResult is Success) {
        await syncDriveItems();
        _message = 'Upload completato';
      } else {
        _message = 'Errore creazione item';
      }
    } else {
      _message = 'Errore upload file';
    }

    _isUploading = false;
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    // Optimistic update
    final currentList = List<DriveItem>.from(_driveItems);
    _driveItems = _driveItems.where((item) => item.id != id).toList();
    await StorageService.saveDriveItems(_driveItems);
    notifyListeners();

    final result = await _repo.deleteDriveItem(id);

    switch (result) {
      case Success():
        _message = 'Item eliminato!';
      case GenericError():
      case NetworkError():
        // Rollback
        _driveItems = currentList;
        await StorageService.saveDriveItems(_driveItems);
        _message = 'Errore nell\'eliminazione';
    }
    notifyListeners();
  }

  Future<void> addReaction(int itemId, String emoji) async {
    final result = await _repo.addReaction(itemId, emoji);

    switch (result) {
      case Success():
        _driveItems = _driveItems.map((item) {
          if (item.id == itemId) {
            return item.copyWith(reactions: [...item.reactions, emoji]);
          }
          return item;
        }).toList();
        await StorageService.saveDriveItems(_driveItems);
        
        if (_singleItem?.id == itemId) {
          _singleItem = _singleItem!.copyWith(
            reactions: [..._singleItem!.reactions, emoji],
          );
        }
      case GenericError():
        _message = 'Errore aggiunta reaction';
      case NetworkError():
        _message = 'Errore rete';
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(int itemId) async {
    final idx = _driveItems.indexWhere((item) => item.id == itemId);
    if (idx == -1) return;

    final item = _driveItems[idx];
    final isCurrentlyFavorite = item.isFavorite == 1;
    final updatedItem = item.copyWith(isFavorite: isCurrentlyFavorite ? 0 : 1);

    // Optimistic update
    _driveItems[idx] = updatedItem;
    await StorageService.saveDriveItems(_driveItems);
    
    if (_singleItem?.id == itemId) {
      _singleItem = updatedItem;
    }
    notifyListeners();

    final result = isCurrentlyFavorite
        ? await _repo.removeFavorite(itemId)
        : await _repo.addFavorite(itemId);

    if (result is! Success) {
      // Rollback
      _driveItems[idx] = item;
      await StorageService.saveDriveItems(_driveItems);
      
      if (_singleItem?.id == itemId) {
        _singleItem = item;
      }
      _message = 'Errore aggiornamento preferito';
      notifyListeners();
    }
  }
}
