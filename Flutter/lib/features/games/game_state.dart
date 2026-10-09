import 'dart:async';
import 'package:flutter/widgets.dart';

import 'package:justus/all_imports.dart';

class GameState extends BaseState with CheckpointMixin {
  GameState({GameRepository? repository, LanguageProvider? languageProvider})
      : _repo = repository ?? GameRepository(),
        _languageProvider = languageProvider,
        _handledLanguageCode = languageProvider?.locale.languageCode {
    // Refetch the active question in the new locale right after a language
    // change (G3). Uses `fetchActiveQuestion` — read-only, so it never
    // inserts a new question nor notifies the partner.
    _languageProvider?.addListener(_onLanguageChanged);
  }

  final GameRepository _repo;
  final LanguageProvider? _languageProvider;
  String? _handledLanguageCode;

  @override
  void dispose() {
    _languageProvider?.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    final code = _languageProvider?.locale.languageCode;
    if (code == null || code == _handledLanguageCode) return;
    _handledLanguageCode = code;
    unawaited(_refreshForLocaleChange());
  }

  Future<void> _refreshForLocaleChange() async {
    final epoch = CacheService.checkpointEpoch;
    final token = _beginCheckpointToken();
    final result = await _repo.fetchActiveQuestion();
    switch (result) {
      case Success<GameNewQuestionResponse?>(:final value):
        if (value != null) {
          _currentQuestion = value;
          _noQuestionAvailable = false;
          await StorageService.saveGameQuestion(value);
        } else {
          _currentQuestion = null;
          _noQuestionAvailable = true;
          await StorageService.clearCachedGameQuestion();
        }
        notifyListeners();
      default:
        // Keep the previous question: a silent locale refresh should not
        // clobber state on a transient failure.
        break;
    }

    // setLocale already cleared the history cache and the kGameAnswers
    // checkpoint, so the in-memory history keeps the previous language until
    // the next init(). Refetch it here in the new language (with checkpoint)
    // so the change is visible immediately, even while the Game tab is open.
    await fetchHistory(epoch: epoch, token: token);
  }

  GameNewQuestionResponse? _currentQuestion;
  List<GameHistoryItem> _history = [];
  bool _isFetchingQuestion = false;
  bool _noQuestionAvailable = false;
  int? _currentUserId;

  int _checkpointToken = 0;

  int _beginCheckpointToken() => ++_checkpointToken;

  GameNewQuestionResponse? get currentQuestion => _currentQuestion;
  List<GameHistoryItem> get history => _history;
  bool get isFetchingQuestion => _isFetchingQuestion;
  bool get noQuestionAvailable => _noQuestionAvailable;

  Future<void> init() async {
    final epoch = CacheService.checkpointEpoch;
    _currentUserId = await StorageService.getUserId();
    await loadWithChangeDetection(
      loadFromCache: _loadFromCache,
      hasChanges: _hasGameChanges,
      fetchFromNetwork: () => _fetchAllInBackground(epoch: epoch),
    );
  }

  Future<void> _loadFromCache() async {
    _currentUserId ??= await StorageService.getUserId();
    final cached = await StorageService.getCachedGameQuestion();
    if (cached != null) {
      _currentQuestion = await _resolveCachedNames(cached);
    } else {
      // The language change clears the question cache (G3): make sure the
      // in-memory question in the old language does not survive an empty
      // cache, otherwise the screen mixes locales.
      _currentQuestion = null;
    }
    _history = await StorageService.getGameHistory();
    notifyListeners();
  }

  Future<GameNewQuestionResponse> _resolveCachedNames(
      GameNewQuestionResponse q) async {
    final uid = _currentUserId;
    if (uid == null) return q;

    final locale = await LanguageHelper.currentLocaleCode();
    final myName = await StorageService.getUsername();
    final partnershipData = await _repo.getActivePartnership();
    final loc = await AppLocalizations.delegate.load(Locale(locale));
    final partnerName = partnershipData?['partner_display_name'] as String?;

    String name(int userId) => resolvePlayerName(
          userId: userId,
          currentUserId: uid,
          myName: myName,
          partnerName: partnerName,
          youFallback: loc.common_youTitle,
          partnerFallback: loc.common_partner,
        );

    return q.copyWith(
      optionA: optionLabelFor(q.userIdA, loc.game_optionA, name),
      optionB: optionLabelFor(q.userIdB, loc.game_optionB, name),
    );
  }

  Future<bool> _hasGameChanges() async {
    final uid = await StorageService.getUserId();
    final partnerId = await StorageService.getPartnerId();
    if (uid == null) return false;
    if (partnerId == null) return true;

    final partnershipId = await StorageService.getPartnershipId();
    return _repo.hasNewGameActivity(uid, partnerId, partnershipId);
  }

  Future<void> _fetchAllInBackground({required int epoch}) async {
    final token = _beginCheckpointToken();
    await Future.wait([
      fetchHistory(epoch: epoch, token: token),
      _fetchActiveQuestion(epoch: epoch, token: token),
    ]);
  }

  /// Read-only fetch of the server's active question.
  ///
  /// Runs inside the background sync because a partner-created question is
  /// invisible from a warm cache while no `game_answers` activity exists yet;
  /// Realtime only delivers live events and never replays a question that was
  /// created while this device was offline. Never inserts and never notifies
  /// the partner.
  Future<void> _fetchActiveQuestion({required int epoch, int? token}) async {
    final result = await _repo.fetchActiveQuestion();

    await result.handleAsync(
      onSuccess: (value) async {
        if (value != null) {
          _currentQuestion = value;
          _noQuestionAvailable = false;
          await StorageService.saveGameQuestion(value);
        } else {
          _currentQuestion = null;
          _noQuestionAvailable = true;
          await StorageService.clearCachedGameQuestion();
        }
        await _updateQuestionCheckpoint(epoch: epoch, token: token);
        notifyListeners();
      },
    );
  }

  Future<void> _updateQuestionCheckpoint(
      {required int epoch, int? token}) async {
    final partnershipId = await StorageService.getPartnershipId();
    if (partnershipId == null) return;

    await saveMaxTimestampCheckpoint(
      checkpointKey: CacheService.kGameQuestions,
      timestamps: [
        await _repo.fetchMaxTimestamp(
          table: 'game_questions',
          field: 'created_at',
          filterColumn: 'partnership_id',
          filterValues: [partnershipId],
        ),
      ],
      epoch: epoch,
      writerToken: token,
      currentToken: token == null ? null : _checkpointToken,
    );
  }

  Future<void> _updateGameCheckpoint({required int epoch, int? token}) async {
    final uid = await StorageService.getUserId();
    final partnerId = await StorageService.getPartnerId();
    if (uid == null || partnerId == null) return;

    await saveMaxTimestampCheckpoint(
      checkpointKey: CacheService.kGameAnswers,
      timestamps: [
        await _repo.fetchMaxTimestamp(
          table: 'game_answers',
          field: 'updated_at',
          filterColumn: 'user_id',
          filterValues: [uid, partnerId],
        ),
      ],
      epoch: epoch,
      writerToken: token,
      currentToken: token == null ? null : _checkpointToken,
    );
  }

  Future<void> fetchNewQuestion({bool showLoading = true}) async {
    if (_isFetchingQuestion) return;
    _isFetchingQuestion = true;
    if (showLoading) {
      setLoading(true);
    }
    notifyListeners();

    final result = await _repo.fetchNewGameQuestion();

    var noQuestionAvailable = false;

    await result.handleAsync(
      onSuccess: (value) async {
        if (value == null) {
          noQuestionAvailable = true;
          return;
        }
        _noQuestionAvailable = false;
        // Don't save if question text is empty
        if (value.question.isNotEmpty) {
          _currentQuestion = value;
          await StorageService.saveGameQuestion(value);
        } else {
          noQuestionAvailable = true;
          _currentQuestion = null;
          await StorageService.clearCachedGameQuestion();
        }
      },
    );

    // A terminal "there is no question" answer must clear the PERSISTED
    // question too. Nulling only `_currentQuestion` left the stale row in the
    // cache, so the next cold start resurrected a question the server had
    // already retired (every other terminal path here clears the cache).
    if (noQuestionAvailable) {
      _currentQuestion = null;
      _noQuestionAvailable = true;
      await StorageService.clearCachedGameQuestion();
    }

    if (showLoading) {
      setLoading(false);
    }
    _isFetchingQuestion = false;
    notifyListeners();
  }

  List<GameHistoryItem> _historyWithAnswer({
    required int gameId,
    int? userOption,
    int? partnerOption,
    bool updateExistingOnly = false,
    bool deleteUserOption = false,
    bool deletePartnerOption = false,
    String? questionText,
  }) {
    var found = false;
    final newHistory = <GameHistoryItem>[];

    for (final item in _history) {
      if (item.questionId == gameId) {
        found = true;
        final newUser =
            deleteUserOption ? null : (userOption ?? item.userOption);
        final newPartner =
            deletePartnerOption ? null : (partnerOption ?? item.partnerOption);

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

    if (!found &&
        !updateExistingOnly &&
        (userOption != null || partnerOption != null)) {
      newHistory.insert(
        0,
        GameHistoryItem(
          questionId: gameId,
          question: questionText ?? _currentQuestion?.question ?? '',
          userOption: userOption,
          partnerOption: partnerOption,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }

    return newHistory;
  }

  Future<void> submitAnswer(String votedFor) async {
    final epoch = CacheService.checkpointEpoch;
    final token = _beginCheckpointToken();
    if (_currentQuestion == null) return;

    setLoading(true);
    int? option;
    if (votedFor == 'A') {
      option = _currentQuestion!.userIdA;
    } else if (votedFor == 'B') {
      option = _currentQuestion!.userIdB;
    }
    if (option == null) {
      final loc = await AppLocalizations.delegate.load(
        Locale(await LanguageHelper.currentLocaleCode()),
      );
      setMessage(loc.game_invalidOption);
      setLoading(false);
      notifyListeners();

      return;
    }

    final result = await _repo.submitAnswer(_currentQuestion!.id, option);

    await result.handleAsync(
      onSuccess: (value) async {
        final loc = await AppLocalizations.delegate.load(
          Locale(await LanguageHelper.currentLocaleCode()),
        );
        final wasPending = !_currentQuestion!.partnerAnswered;
        setMessage(loc.game_answerSent);
        _currentQuestion = _currentQuestion!.copyWith(
          status: 'waiting',
          hasAnswered: true,
        );
        await StorageService.saveGameQuestion(_currentQuestion!);

        _history = _historyWithAnswer(
          gameId: _currentQuestion!.id,
          userOption: option,
          questionText: _currentQuestion!.question,
        );
        await StorageService.saveGameHistory(_history);

        if (!wasPending) {
          _currentQuestion = null;
          await StorageService.clearCachedGameQuestion();
        }
        await _updateGameCheckpoint(epoch: epoch, token: token);
      },
    );

    setLoading(false);
    notifyListeners();
  }

  Future<void> fetchHistory(
      {required int epoch, int? token, void Function()? onSuccess}) async {
    final writeToken = token ?? _beginCheckpointToken();
    final result = await _repo.fetchGameHistory();

    await result.handleAsync(
      onSuccess: (value) async {
        _history = value;
        await StorageService.saveGameHistory(value);
        await _updateGameCheckpoint(epoch: epoch, token: writeToken);
        onSuccess?.call();
      },
    );
    notifyListeners();
  }

  Future<void> refreshFromRealtime() async {
    await _fetchAllInBackground(epoch: CacheService.checkpointEpoch);
  }

  Future<void> handleAnswerDelete(Map<String, dynamic> oldRecord) async {
    final gameId = rowInt(oldRecord, 'game_id');
    final userId = rowInt(oldRecord, 'user_id');

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

    if (_currentUserId != null) {
      _history = _historyWithAnswer(
        gameId: gameId,
        deleteUserOption: userId == _currentUserId,
        deletePartnerOption: userId != _currentUserId,
        updateExistingOnly: true,
      );
      await StorageService.saveGameHistory(_history);
    }
    notifyListeners();
  }

  Future<void> handleQuestionInsert(Map<String, dynamic> newRecord) async {
    final id = rowInt(newRecord, 'id');
    // The client's own insert echoes back over Realtime; that question is
    // already `_currentQuestion`, so refetching would issue a duplicate
    // active-question round trip and repaint the same question (UI flicker).
    if (id != null && _currentQuestion?.id == id) return;

    await fetchNewQuestion(showLoading: false);
  }

  Future<void> handleQuestionDelete(Map<String, dynamic> oldRecord) async {
    final id = rowInt(oldRecord, 'id');
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
    final id = rowInt(newRecord, 'id');
    if (id == null || _currentQuestion == null || _currentQuestion!.id != id) {
      return;
    }

    final status = newRecord['status'] as String?;
    if (status == null) return;

    _currentQuestion = _currentQuestion!.copyWith(
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
    final epoch = CacheService.checkpointEpoch;
    final token = _beginCheckpointToken();
    final gameId = rowInt(newRecord, 'game_id');
    final userId = rowInt(newRecord, 'user_id');
    final selectedOption = rowInt(newRecord, 'selected_option');

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

    final isUser = _currentUserId != null && userId == _currentUserId;
    final isPartner = _currentUserId != null && userId != _currentUserId;

    final exists = _history.any((item) => item.questionId == gameId);

    if (exists) {
      _history = _historyWithAnswer(
        gameId: gameId,
        userOption: isUser ? selectedOption : null,
        partnerOption: isPartner ? selectedOption : null,
      );
      await StorageService.saveGameHistory(_history);
    } else {
      if (_currentQuestion != null && _currentQuestion!.id == gameId) {
        _history = _historyWithAnswer(
          gameId: gameId,
          userOption: isUser ? selectedOption : null,
          partnerOption: isPartner ? selectedOption : null,
          questionText: _currentQuestion!.question,
        );
        await StorageService.saveGameHistory(_history);
      } else {
        await fetchHistory(epoch: epoch, token: token);
      }
    }

    await _updateGameCheckpoint(epoch: epoch, token: token);
  }

  Future<void> handleAnswerUpdate(Map<String, dynamic> newRecord) async {
    final gameId = rowInt(newRecord, 'game_id');

    if (gameId == null) return;

    _currentUserId ??= await StorageService.getUserId();

    if (_currentUserId == null ||
        (_currentQuestion?.id != gameId &&
            _history.every((h) => h.questionId != gameId))) {
      return;
    }

    final result = await _repo.fetchAnswerStatus(gameId);
    result.handle(
      onSuccess: (value) async {
        if (_currentQuestion != null && _currentQuestion!.id == gameId) {
          _currentQuestion = _currentQuestion!.copyWith(
            hasAnswered: value.hasAnswered,
            partnerAnswered: value.partnerAnswered,
          );
          await StorageService.saveGameQuestion(_currentQuestion!);
        }

        _history = _historyWithAnswer(
          gameId: gameId,
          userOption: value.userOption,
          partnerOption: value.partnerOption,
        );
        await StorageService.saveGameHistory(_history);
        notifyListeners();
      },
    );
  }

  void clear() {
    _currentQuestion = null;
    _history = [];
    _currentUserId = null;
    _isFetchingQuestion = false;
    _noQuestionAvailable = false;
    notifyListeners();
  }
}
