// =============================================================================
// HomepageState - Homepage screen state management
// Dart equivalent of HomepageViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class HomepageState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  int _totalMissYou = 0;
  String? _message;
  bool _isLoading = false;

  int get totalMissYou => _totalMissYou;
  String? get message => _message;
  bool get isLoading => _isLoading;

  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    // Load from cache first
    final cached = await StorageService.getTotalMissYou();
    if (cached != null) {
      _totalMissYou = cached;
      notifyListeners();
    }
    
    // Then fetch from server
    await fetchTotalMissYou();
  }

  Future<void> fetchTotalMissYou() async {
    final result = await _repo.fetchMissYouTotal();

    switch (result) {
      case Success(:final value):
        _totalMissYou = value;
        await StorageService.saveTotalMissYou(value);
      case GenericError():
        _message = 'Errore server nel calcolo totale';
      case NetworkError():
        _message = 'Nessuna connessione';
    }
    notifyListeners();
  }

  Future<void> sendMissYou() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.sendMissYou();

    switch (result) {
      case Success(:final value):
        _totalMissYou = value;
        await StorageService.saveTotalMissYou(value);
        _message = 'Mi manchi inviato!';
      case GenericError():
        _message = 'Errore server invio Mi manchi';
      case NetworkError():
        _message = 'Problema di rete';
    }

    _isLoading = false;
    notifyListeners();
  }
}
