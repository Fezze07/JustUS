// =============================================================================
// MoodState - Mood screen state management
// Dart equivalent of MoodViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class MoodState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  String _userMood = '😐';
  String _partnerMood = '😐';
  List<String> _recentEmojis = [];
  String? _message;
  bool _isLoading = false;

  String get userMood => _userMood;
  String get partnerMood => _partnerMood;
  List<String> get recentEmojis => _recentEmojis;
  String? get message => _message;
  bool get isLoading => _isLoading;

  void clearMessage() {
    _message = null;
  }

  Future<void> loadCache() async {
    final myMood = await StorageService.getMood('me');
    if (myMood != null) {
      _userMood = myMood;
    }
    
    final partnerMood = await StorageService.getMood('partner');
    if (partnerMood != null) {
      _partnerMood = partnerMood;
    }

    final recent = await StorageService.getRecentEmojis();
    if (recent.isNotEmpty) {
      _recentEmojis = recent;
    }

    notifyListeners();
  }

  Future<void> loadPartnerMoodFromCache() async {
    final mood = await StorageService.getMood('partner');
    _partnerMood = mood ?? '😐';
    notifyListeners();
  }

  Future<void> fetchMyMood() async {
    final result = await _repo.fetchMyMood();

    switch (result) {
      case Success(:final value):
        _userMood = value.emoji ?? '😐';
        await StorageService.saveMood('me', _userMood);
      case GenericError():
        _message = 'Errore server nel cercare il mood';
      case NetworkError():
        _message = 'Nessuna connessione';
    }
    notifyListeners();
  }

  Future<void> fetchPartnerMood() async {
    final result = await _repo.fetchPartnerMood();

    switch (result) {
      case Success(:final value):
        _partnerMood = value.emoji ?? '😐';
        await StorageService.saveMood('partner', _partnerMood);
      case GenericError():
        _message = 'Errore server nel cercare il mood';
      case NetworkError():
        _message = 'Nessuna connessione';
    }
    notifyListeners();
  }

  Future<void> fetchRecentEmojis() async {
    final result = await _repo.fetchRecentCoupleEmojis();

    switch (result) {
      case Success(:final value):
        _recentEmojis = value;
        await StorageService.saveRecentEmojis(value);
      case GenericError():
        _message = 'Errore server nel cercare le emoji recenti';
      case NetworkError():
        _message = 'Nessuna connessione';
    }
    notifyListeners();
  }

  Future<void> updateMood(String emoji) async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.setMood(emoji);

    switch (result) {
      case Success(:final value):
        _userMood = value.emoji ?? '😐';
        await StorageService.saveMood('me', _userMood);
        _message = 'Mood aggiornato!';
      case GenericError():
        _message = 'Errore server nel cambio mood';
      case NetworkError():
        _message = 'Nessuna connessione';
    }

    _isLoading = false;
    notifyListeners();
  }
}
