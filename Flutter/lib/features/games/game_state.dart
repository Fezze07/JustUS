import 'package:justus/all_imports.dart';

class GameState extends BaseState {
  GameState({GameRepository? repository})
      : _repo = repository ?? GameRepository();

  final GameRepository _repo;

  GameNewQuestionResponse? _currentQuestion;
  List<GameHistoryItem> _history = [];
  int _gameStats = 0;
  String? _message;
  bool _isLoading = false;
  bool _isFetchingQuestion = false;

  GameNewQuestionResponse? get currentQuestion => _currentQuestion;
  List<GameHistoryItem> get history => _history;
  int get gameStats => _gameStats;
  @override
  String? get message => _message;
  @override
  bool get isLoading => _isLoading;
  bool get isFetchingQuestion => _isFetchingQuestion;

  @override
  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: _hasGameChanges,
      fetchFromNetwork: _fetchAllInBackground,
    );
  }

  Future<void> _loadFromCache() async {
    final cached = await StorageService.getCachedGameQuestion();
    if (cached != null) {
      _currentQuestion = cached;
    }
    _gameStats = await StorageService.getGameMatches();
    _history = await StorageService.getGameHistory();
    notifyListeners();
  }

  Future<bool> _hasGameChanges() async {
    final uid = await StorageService.getUserId();
    final partnerId = await StorageService.getPartnerId();
    if (uid == null) return false;
    if (partnerId == null) return true;

    return _repo.hasNewGameActivity(uid, partnerId);
  }

  Future<void> _fetchAllInBackground() async {
    await Future.wait([
      fetchStats(),
      fetchHistory(),
    ]);

    if (_currentQuestion == null ||
        _currentQuestion!.status == 'both_answered') {
      await fetchNewQuestion();
    }

    await _updateGameCheckpoint();
  }

  Future<void> _updateGameCheckpoint() async {
    final uid = await StorageService.getUserId();
    final partnerId = await StorageService.getPartnerId();
    if (uid == null || partnerId == null) return;

    final maxTimestamp = await _repo.fetchMaxTimestamp(
      table: 'game_answers',
      field: 'created_at',
      filterColumn: 'user_id',
      filterValues: [uid, partnerId],
    );

    if (maxTimestamp != null) {
      await CacheService.saveCheckpoint(CacheService.kGameAnswers, maxTimestamp);
    } else {
      await CacheService.saveCheckpoint(CacheService.kGameAnswers, CacheService.kCheckpointEmpty);
    }
  }

  Future<void> fetchNewQuestion({bool showLoading = true}) async {
    if (_isFetchingQuestion) return;
    _isFetchingQuestion = true;
    if (showLoading) {
      _isLoading = true;
    }
    notifyListeners();

    final result = await _repo.fetchNewGameQuestion();

    switch (result) {
      case Success(:final value):
        if (value.success) {
          _currentQuestion = value;
          await StorageService.saveGameQuestion(value);
        } else {
          _currentQuestion = null;
        }
      case GenericError(:final message):
        if (message != 'No questions') {
          ErrorHandler.handle(result);
        } else {
          _currentQuestion = null;
        }
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }

    if (showLoading) {
      _isLoading = false;
    }
    _isFetchingQuestion = false;
    notifyListeners();
  }

  Future<void> submitAnswer(String votedFor) async {
    if (_currentQuestion == null) return;

    _isLoading = true;
    notifyListeners();
    int? option;
    if (votedFor == 'A') {
      option = _currentQuestion!.userIdA;
    } else if (votedFor == 'B') {
      option = _currentQuestion!.userIdB;
    }
    if (option == null) {
      _message = 'Errore: opzione non valida';
      _isLoading = false;
      notifyListeners();

      return;
    }

    final result = await _repo.submitAnswer(_currentQuestion!.id, option);

    switch (result) {
      case Success():
        _message = 'Risposta inviata! ✨';
        _currentQuestion = _currentQuestion!.copyWith(
          status: 'waiting',
          message: 'Aspetta che il partner risponda',
          hasAnswered: true,
        );
        await StorageService.saveGameQuestion(_currentQuestion!);
        await Future.wait([
          fetchStats(),
          fetchHistory(),
        ]);
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchStats() async {
    final result = await _repo.fetchGameStats();

    switch (result) {
      case Success(:final value):
        _gameStats = value.totalMatches;
        await StorageService.saveGameMatches(value.totalMatches);
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }
    notifyListeners();
  }

  Future<void> fetchHistory() async {
    final result = await _repo.fetchGameHistory();

    switch (result) {
      case Success(:final value):
        _history = value;
        await StorageService.saveGameHistory(value);
        await _updateGameCheckpoint();
      case GenericError():
        ErrorHandler.handle(result);
      case NetworkError():
        ErrorHandler.handle(AppError.network());
    }
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    await Future.wait([
      fetchStats(),
      fetchHistory(),
    ]);

    if (_currentQuestion == null ||
        _currentQuestion!.status == 'both_answered') {
      await fetchNewQuestion(showLoading: false);
    }

    await _updateGameCheckpoint();
  }

  void clear() {
    _currentQuestion = null;
    _history = [];
    _gameStats = 0;
    notifyListeners();
  }
}
