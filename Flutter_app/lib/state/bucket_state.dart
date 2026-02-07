// =============================================================================
// BucketState - Bucket list screen state management
// Dart equivalent of BucketListViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class BucketState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  List<BucketItem> _items = [];
  String? _message;
  bool _isLoading = false;

  List<BucketItem> get items => _items;
  String? get message => _message;
  bool get isLoading => _isLoading;

  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    // Load from cache first
    _items = await StorageService.getBucketList();
    notifyListeners();
    
    // Then fetch from server
    await fetchBucket();
  }

  Future<void> fetchBucket() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.fetchBucketList();

    switch (result) {
      case Success(:final value):
        if (value.success) {
          _items = value.items;
          await StorageService.saveBucketList(value.items);
        } else {
          _message = 'Errore nel caricamento';
        }
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Offline 😴';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addItem(String text) async {
    if (text.trim().isEmpty) {
      _message = 'Inserisci del testo';
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    final result = await _repo.addBucketItem(text);

    switch (result) {
      case Success():
        await fetchBucket();
      case GenericError():
        _message = 'Errore salvataggio';
      case NetworkError():
        _message = 'Errore di rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleDone(int id) async {
    final result = await _repo.toggleBucketDone(id);

    switch (result) {
      case Success():
        _items = _items.map((item) {
          if (item.id == id) {
            return item.copyWith(done: item.done == 1 ? 0 : 1);
          }
          return item;
        }).toList();
        await StorageService.saveBucketList(_items);
      case GenericError():
        _message = 'Errore aggiornamento';
      case NetworkError():
        _message = 'Errore di rete';
    }
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    final result = await _repo.deleteBucketItem(id);

    switch (result) {
      case Success():
        _items = _items.where((item) => item.id != id).toList();
        await StorageService.saveBucketList(_items);
      case GenericError():
        _message = 'Errore cancellazione';
      case NetworkError():
        _message = 'Errore di rete';
    }
    notifyListeners();
  }
}
