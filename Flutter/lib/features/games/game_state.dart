import 'package:justus/all_imports.dart';

class GameState extends BaseState with CheckpointMixin {
  GameState({GameRepository? repository})
      : _repo = repository ?? GameRepository();

  final GameRepository _repo;

  GameNewQuestionResponse? _currentQuestion;
  List<GameHistoryItem> _history = [];
  int _gameStats = 0;
  String? _message;
  bool _isLoading = false;
  bool _isFetchingQuestion = false;
  int? _currentUserId;

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
    _currentUserId = await StorageService.getUserId();
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: _hasGameChanges,
      fetchFromNetwork: _fetchAllInBackground,
    );
  }

  Future<void> _loadFromCache() async {
    _currentUserId ??= await StorageService.getUserId();
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

    await _updateGameCheckpoint();
  }

  Future<void> _updateGameCheckpoint() async {
    final uid = await StorageService.getUserId();
    final partnerId = await StorageService.getPartnerId();
    if (uid == null || partnerId == null) return;

    await saveMaxTimestampCheckpoint(
      checkpointKey: CacheService.kGameAnswers,
      timestamps: [
        await _repo.fetchMaxTimestamp(
          table: 'game_answers',
          field: 'created_at',
          filterColumn: 'user_id',
          filterValues: [uid, partnerId],
        ),
      ],
    );
  }

  Future<void> fetchNewQuestion({bool showLoading = true}) async {
    if (_isFetchingQuestion) return;
    _isFetchingQuestion = true;
    if (showLoading) {
      _isLoading = true;
    }
    notifyListeners();

    final result = await _repo.fetchNewGameQuestion();

    await result.handleAsync(
      onSuccess: (value) async {
        if (value.success) {
          _currentQuestion = value;
          await StorageService.saveGameQuestion(value);
        } else {
          _currentQuestion = null;
        }
      },
      onError: (code, message) {
        if (message != 'No questions') {
          ErrorHandler.handle(result);
        } else {
          _currentQuestion = null;
        }
      },
    );

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

    await result.handleAsync(
      onSuccess: (value) async {
        final wasPending = !_currentQuestion!.partnerAnswered;
        _message = 'Risposta inviata! ✨';
        _currentQuestion = _currentQuestion!.copyWith(
          status: 'waiting',
          message: 'Aspetta che il partner risponda',
          hasAnswered: true,
        );
        await StorageService.saveGameQuestion(_currentQuestion!);

        var found = false;
        final newHistory = <GameHistoryItem>[];
        for (final item in _history) {
          if (item.questionId == _currentQuestion!.id) {
            found = true;
            newHistory.add(GameHistoryItem(
              questionId: item.questionId,
              question: item.question,
              userOption: option,
              partnerOption: item.partnerOption,
              createdAt: item.createdAt,
            ));
          } else {
            newHistory.add(item);
          }
        }
        if (!found) {
          newHistory.insert(
              0,
              GameHistoryItem(
                questionId: _currentQuestion!.id,
                question: _currentQuestion!.question,
                userOption: option,
                createdAt: DateTime.now().toIso8601String(),
              ));
        }
        _history = newHistory;
        await StorageService.saveGameHistory(_history);

        if (!wasPending) {
          await _repo.updateQuestionStatus(_currentQuestion!.id, 'both_answered');
          _currentQuestion = null;
          await StorageService.clearCachedGameQuestion();
          await fetchStats();
        }
        await _updateGameCheckpoint();
      },
    );

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchStats() async {
    final result = await _repo.fetchGameStats();

    result.handle(
      onSuccess: (value) async {
        _gameStats = value.totalMatches;
        await StorageService.saveGameMatches(value.totalMatches);
      },
    );
    notifyListeners();
  }

  Future<void> fetchHistory() async {
    final result = await _repo.fetchGameHistory();

    await result.handleAsync(
      onSuccess: (value) async {
        _history = value;
        await StorageService.saveGameHistory(value);
        await _updateGameCheckpoint();
      },
    );
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    await Future.wait([
      fetchStats(),
      fetchHistory(),
    ]);

    await _updateGameCheckpoint();
  }

  Future<void> handleAnswerDelete(Map<String, dynamic> oldRecord) async {
    final gameId = _rowInt(oldRecord, 'game_id');
    final userId = _rowInt(oldRecord, 'user_id');

    if (gameId == null || userId == null) return;

    _currentUserId ??= await StorageService.getUserId();

    if (_currentUserId != null &&
        _currentQuestion != null &&
        _currentQuestion!.id == gameId) {
      if (userId == _currentUserId) {
        _currentQuestion = _currentQuestion!.copyWith(hasAnswered: false);
      } else {
        _currentQuestion = _currentQuestion!.copyWith(partnerAnswered: false);
      }
      await StorageService.saveGameQuestion(_currentQuestion!);
    }

    final newHistory = <GameHistoryItem>[];
    for (final item in _history) {
      if (item.questionId == gameId && _currentUserId != null) {
        final newUser = (userId == _currentUserId) ? null : item.userOption;
        final newPartner =
            (userId != _currentUserId) ? null : item.partnerOption;
        if (newUser == null && newPartner == null) continue;
        newHistory.add(GameHistoryItem(
          questionId: item.questionId,
          question: item.question,
          userOption: newUser,
          partnerOption: newPartner,
          createdAt: item.createdAt,
        ));
      } else {
        newHistory.add(item);
      }
    }

    _history = newHistory;
    await StorageService.saveGameHistory(_history);
    notifyListeners();
  }

  Future<void> handleQuestionDelete(Map<String, dynamic> oldRecord) async {
    final id = _rowInt(oldRecord, 'id');
    if (id == null) return;

    if (_currentQuestion != null && _currentQuestion!.id == id) {
      _currentQuestion = null;
      await StorageService.clearCachedGameQuestion();
    }

    _history.removeWhere((h) => h.questionId == id);
    await StorageService.saveGameHistory(_history);
    notifyListeners();
  }

  Future<void> handleQuestionUpdate(Map<String, dynamic> newRecord) async {
    final id = _rowInt(newRecord, 'id');
    if (id == null || _currentQuestion == null || _currentQuestion!.id != id) {
      return;
    }

    final question = newRecord['question'] as String?;
    final status = newRecord['status'] as String?;

    if (question == null && status == null) return;

    _currentQuestion = _currentQuestion!.copyWith(
      question: question,
      status: status,
    );

    await StorageService.saveGameQuestion(_currentQuestion!);
    notifyListeners();

    if (status == 'both_answered') {
      _currentQuestion = null;
      await StorageService.clearCachedGameQuestion();
      notifyListeners();
    }
  }

  Future<void> handleAnswerInsert(Map<String, dynamic> newRecord) async {
    final gameId = _rowInt(newRecord, 'game_id');
    final userId = _rowInt(newRecord, 'user_id');
    final selectedOption = _rowInt(newRecord, 'selected_option');

    if (gameId == null || userId == null || selectedOption == null) return;

    _currentUserId ??= await StorageService.getUserId();

    final isOwnInsert = _currentUserId != null &&
        userId == _currentUserId &&
        _currentQuestion != null &&
        _currentQuestion!.id == gameId;
    if (isOwnInsert) return;

    if (_currentQuestion != null && _currentQuestion!.id == gameId) {
      _currentQuestion = _currentQuestion!.copyWith(partnerAnswered: true);
      await StorageService.saveGameQuestion(_currentQuestion!);
      notifyListeners();
    }

    var found = false;
    final newHistory = <GameHistoryItem>[];
    for (final item in _history) {
      if (item.questionId == gameId) {
        found = true;
        if (_currentUserId != null) {
          newHistory.add(GameHistoryItem(
            questionId: item.questionId,
            question: item.question,
            userOption:
                userId == _currentUserId ? selectedOption : item.userOption,
            partnerOption:
                userId != _currentUserId ? selectedOption : item.partnerOption,
            createdAt: item.createdAt,
          ));
        } else {
          newHistory.add(item);
        }
      } else {
        newHistory.add(item);
      }
    }

    if (!found) {
      if (_currentQuestion != null && _currentQuestion!.id == gameId) {
        newHistory.insert(
            0,
            GameHistoryItem(
              questionId: gameId,
              question: _currentQuestion!.question,
              userOption: _currentUserId != null && userId == _currentUserId
                  ? selectedOption
                  : null,
              partnerOption: _currentUserId != null && userId != _currentUserId
                  ? selectedOption
                  : null,
              createdAt: DateTime.now().toIso8601String(),
            ));
        _history = newHistory;
        await StorageService.saveGameHistory(_history);
      } else {
        await fetchHistory();
      }
    } else {
      _history = newHistory;
      await StorageService.saveGameHistory(_history);
    }

    if (_currentQuestion != null &&
        _currentQuestion!.hasAnswered &&
        _currentQuestion!.partnerAnswered) {
      await _repo.updateQuestionStatus(_currentQuestion!.id, 'both_answered');
      _currentQuestion = null;
      await StorageService.clearCachedGameQuestion();
      await fetchStats();
      notifyListeners();
    }

    await _updateGameCheckpoint();
  }

  Future<void> handleAnswerUpdate(Map<String, dynamic> newRecord) async {
    final gameId = _rowInt(newRecord, 'game_id');

    if (gameId == null) return;

    if (_currentUserId == null ||
        (_currentQuestion?.id != gameId &&
            _history.every((h) => h.questionId != gameId))) {
      return;
    }

    final result = await _repo.fetchAnswerStatus(gameId);
    result.handle(
      onSuccess: (value) async {
        if (_currentQuestion != null && _currentQuestion!.id == gameId) {
          if (value.hasAnswered && value.partnerAnswered) {
            await _repo.updateQuestionStatus(gameId, 'both_answered');
            _currentQuestion = null;
            await StorageService.clearCachedGameQuestion();
          } else {
            _currentQuestion = _currentQuestion!.copyWith(
              hasAnswered: value.hasAnswered,
              partnerAnswered: value.partnerAnswered,
            );
            await StorageService.saveGameQuestion(_currentQuestion!);
          }
        }

        var updated = false;
        final newHistory = <GameHistoryItem>[];
        for (final item in _history) {
          if (item.questionId == gameId) {
            newHistory.add(GameHistoryItem(
              questionId: item.questionId,
              question: item.question,
              userOption: value.userOption,
              partnerOption: value.partnerOption,
              createdAt: item.createdAt,
            ));
            updated = true;
          } else {
            newHistory.add(item);
          }
        }

        if (!updated &&
            _currentQuestion != null &&
            _currentQuestion!.id == gameId) {
          newHistory.insert(
            0,
            GameHistoryItem(
              questionId: _currentQuestion!.id,
              question: _currentQuestion!.question,
              userOption: value.userOption,
              partnerOption: value.partnerOption,
              createdAt: DateTime.now().toIso8601String(),
            ),
          );
        }

        _history = newHistory;
        await StorageService.saveGameHistory(_history);
        notifyListeners();
      },
    );
  }

  int? _rowInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void clear() {
    _currentQuestion = null;
    _history = [];
    _gameStats = 0;
    notifyListeners();
  }
}
