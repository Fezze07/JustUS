import 'package:justus/all_imports.dart';

class HomepageState extends BaseState {
  HomepageState({MissYouRepository? repository})
      : _repo = repository ?? MissYouRepository();

  final MissYouRepository _repo;

  int _totalMissYou = 0;
  String? _message;
  bool _isLoading = false;

  int get totalMissYou => _totalMissYou;
  @override
  String? get message => _message;
  @override
  bool get isLoading => _isLoading;

  @override
  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: () => CacheService.needsRefresh(
        CacheService.kMissYou,
      ),
      fetchFromNetwork: fetchTotalMissYou,
    );
  }

  Future<void> _loadFromCache() async {
    final cached = await StorageService.getTotalMissYou();
    if (cached != null) {
      _totalMissYou = cached;
      notifyListeners();
    }
  }

  Future<void> fetchTotalMissYou() async {
    final result = await _repo.fetchMissYouTotal();

    switch (result) {
      case Success(:final value):
        _totalMissYou = value.total;
        await StorageService.saveTotalMissYou(value.total);
        await CacheService.saveCheckpoint(
          CacheService.kMissYou,
          DateTime.now().toUtc().toIso8601String(),
        );
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    await fetchTotalMissYou();
  }

  Future<void> sendMissYou() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.sendMissYou();

    switch (result) {
      case Success():
        _totalMissYou += 1;
        await StorageService.saveTotalMissYou(_totalMissYou);
        await CacheService.saveCheckpoint(
          CacheService.kMissYou,
          DateTime.now().toUtc().toIso8601String(),
        );
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
