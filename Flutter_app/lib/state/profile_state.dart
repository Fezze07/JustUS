// =============================================================================
// ProfileState - Profile screen state management
// Dart equivalent of ProfileViewModel.kt
// =============================================================================

import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/api_repository.dart';
import '../services/result_wrapper.dart';
import '../services/storage_service.dart';

class ProfileState extends ChangeNotifier {
  final ApiRepository _repo = ApiRepository();

  User? _userProfile;
  User? _partnerProfile;
  String? _localProfileImagePath;
  String? _message;
  bool _isLoading = false;
  bool _isUploading = false;

  User? get userProfile => _userProfile;
  User? get partnerProfile => _partnerProfile;
  String? get localProfileImagePath => _localProfileImagePath;
  String? get message => _message;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;

  void clearMessage() {
    _message = null;
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    notifyListeners();

    // Load from cache first
    final cachedUser = await StorageService.getUserProfile();
    final cachedPartner = await StorageService.getPartnerProfile();
    
    if (cachedUser != null) {
      _userProfile = cachedUser;
    }
    if (cachedPartner != null) {
      _partnerProfile = cachedPartner;
    }
    notifyListeners();

    // Fetch user profile from server
    final userResult = await _repo.fetchProfile();
    switch (userResult) {
      case Success(:final value):
        _userProfile = value;
        await StorageService.saveUserProfile(value);
      case GenericError():
        _message = 'Errore server';
      case NetworkError():
        _message = 'Nessuna connessione';
    }

    // Fetch partner profile from server
    final partnerResult = await _repo.fetchPartnerProfile();
    switch (partnerResult) {
      case Success(:final value):
        _partnerProfile = value;
        await StorageService.savePartnerProfile(value);
      case GenericError():
        // Partner might not exist, that's OK
        break;
      case NetworkError():
        _message = 'Nessuna connessione';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateBio(String? bio) async {
    _isLoading = true;
    notifyListeners();

    final result = await _repo.updateProfileBio(bio);

    switch (result) {
      case Success():
        if (_userProfile != null && bio != null) {
          _userProfile = _userProfile!.copyWith(bio: bio);
          await StorageService.saveUserProfile(_userProfile!);
        }
        _message = 'Bio aggiornata!';
      case GenericError():
        _message = 'Errore aggiornamento bio';
      case NetworkError():
        _message = 'Nessuna connessione';
    }

    _isLoading = false;
    notifyListeners();
  }

  void setLocalProfileImage(String path) {
    _localProfileImagePath = path;
    notifyListeners();
  }

  Future<void> uploadProfilePhoto(
    List<int> fileBytes,
    String fileName,
    String mimeType,
  ) async {
    _isUploading = true;
    _message = 'Caricamento foto profilo...';
    notifyListeners();

    final result = await _repo.uploadProfile(fileBytes, fileName, mimeType);

    switch (result) {
      case Success(:final value):
        if (_userProfile != null) {
          _userProfile = _userProfile!.copyWith(profilePicUrl: value);
          await StorageService.saveUserProfile(_userProfile!);
          await StorageService.saveProfilePicVersion(
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        _message = 'Foto profilo aggiornata!';
      case GenericError(:final message):
        _message = 'Errore upload: $message';
      case NetworkError():
        _message = 'Errore di rete';
    }

    _localProfileImagePath = null;
    _isUploading = false;
    notifyListeners();
  }
}
