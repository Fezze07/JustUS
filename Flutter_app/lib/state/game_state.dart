// =============================================================================
// GameState - Game screen state management
// Dart equivalent of GameViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class GameState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  GameNewQuestionResponse? _currentQuestion;
  int _gameStats = 0;
  String? _message;
  bool _isLoading = false;

  GameNewQuestionResponse? get currentQuestion => _currentQuestion;
  int get gameStats => _gameStats;
  String? get message => _message;
  bool get isLoading => _isLoading;

  void clearMessage() {
    _message = null;
  }

  Future<void> init() async {
    // Load from cache
    final cached = await StorageService.getCachedGameQuestion();
    if (cached != null) {
      _currentQuestion = cached;
    }
    _gameStats = await StorageService.getGameMatches();
    notifyListeners();

    // Fetch fresh data
    await fetchStats();
    await fetchNewQuestion();
  }

  Future<void> fetchNewQuestion() async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.fetchNewGameQuestion();

    switch (result) {
      case Success(:final value):
        // Only update if it's a different question
        if (value.id != _currentQuestion?.id) {
          _currentQuestion = value;
          await StorageService.saveGameQuestion(value);
        }
      case GenericError(:final message):
        _message = message ?? 'Errore generico';
      case NetworkError():
        _message = 'Problema di rete';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> submitAnswer(String votedFor) async {
    if (_currentQuestion == null) return;

    _isLoading = true;
    notifyListeners();

    final result = await _repo.submitGameAnswer(_currentQuestion!.id, votedFor);

    switch (result) {
      case Success():
        _message = 'Risposta inviata! ✨';
        _currentQuestion = _currentQuestion!.copyWith(
          status: 'waiting',
          message: 'Aspetta che il partner risponda',
        );
        await StorageService.saveGameQuestion(_currentQuestion!);
        await fetchStats();
        await fetchNewQuestion();
      case GenericError():
        _message = 'Errore generico';
      case NetworkError():
        _message = 'Problema di rete';
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
      case GenericError(:final message):
        _message = message ?? 'Errore generico';
      case NetworkError():
        _message = 'Problema di rete';
    }
    notifyListeners();
  }
}
