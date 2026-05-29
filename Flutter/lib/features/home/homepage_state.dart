// =============================================================================
// HomepageState - Homepage screen state management
// =============================================================================

import 'package:flutter/foundation.dart';

import 'package:justus/all_imports.dart';

class HomepageState extends ChangeNotifier {
  HomepageState({MissYouRepository? repository}) : _repo = repository ?? MissYouRepository();

  final MissYouRepository _repo;

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
        _totalMissYou = value.total;
        await StorageService.saveTotalMissYou(value.total);
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }
    notifyListeners();
  }

  Future<void> sendMissYou() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.sendMissYou();

    switch (result) {
      case Success(:final value):
        _totalMissYou = value.total;
        await StorageService.saveTotalMissYou(value.total);
        _message = 'Mi manchi inviato!';
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }

    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _totalMissYou = 0;
    notifyListeners();
  }
}
