// =============================================================================
// ProfileState - Profile screen state management
// =============================================================================

import 'dart:io';

import 'package:justus/all_imports.dart';

class ProfileState extends BaseState {
  final PartnershipRepository _partnershipRepo;
  final UserRepository _userRepo;

  ProfileState({
    PartnershipRepository? partnershipRepo,
    UserRepository? userRepo,
  })  : _partnershipRepo = partnershipRepo ?? PartnershipRepository(),
        _userRepo = userRepo ?? UserRepository();

  User? _userProfile;
  User? _partnerProfile;
  String? _localProfileImagePath;
  bool _isUploading = false;
  DateTime? _lastFetch;
  DateTime? _anniversaryDate;

  // Throttling duration to avoid spamming the server
  static const _fetchThrottle = Duration(minutes: 1);

  User? get userProfile => _userProfile;
  User? get partnerProfile => _partnerProfile;
  String? get localProfileImagePath => _localProfileImagePath;
  bool get isUploading => _isUploading;
  DateTime? get anniversaryDate => _anniversaryDate;

  Future<void> loadProfile({bool force = false}) async {
    // 1. Prevent concurrent loads
    if (isLoading) return;

    // 2. Throttling: if not forced and fetched recently, skip server call
    final now = DateTime.now();
    final shouldSkipServer = !force &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < _fetchThrottle;

    await runSafe(() async {
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

      if (!shouldSkipServer) {
        final results = await Future.wait([
          _userRepo.fetchProfile(),
          _partnershipRepo.fetchPartnerProfile(),
          _partnershipRepo.getPartnership(),
        ]);

        final userResult = results[0] as ResultWrapper<User>;
        await handleResult(userResult, onSuccess: (value) async {
          _userProfile = value;
          await StorageService.saveUserProfile(value);
          _lastFetch = DateTime.now();
        });

        final partnerResult = results[1] as ResultWrapper<User>;
        await handleResult(partnerResult, onSuccess: (value) async {
          _partnerProfile = value;
          await StorageService.savePartnerProfile(value);
        });

        final partnershipResult = results[2] as ResultWrapper<PartnershipResponse>;
        if (partnershipResult is Success<PartnershipResponse>) {
          _anniversaryDate = partnershipResult.value.anniversaryDate;
        }
      }
    });
  }

  Future<void> updateBio(String? bio) async {
    await runSafe(() async {
      final result = await _userRepo.updateBio(bio);

      await handleResult(result, onSuccess: (_) async {
        if (_userProfile != null) {
          _userProfile = _userProfile!.copyWith(bio: bio);
          await StorageService.saveUserProfile(_userProfile!);
        }
        setMessage('Bio aggiornata!');
      });
    });
  }

  void setLocalProfileImage(String path) {
    _localProfileImagePath = path;
    notifyListeners();
  }

  Future<void> uploadProfilePhoto(String filePath) async {
    _isUploading = true;
    setMessage('Caricamento foto profilo...');
    notifyListeners();

    await runSafe(() async {
      final result = await _userRepo.uploadProfilePicture(File(filePath));

      await handleResult(result, onSuccess: (value) async {
        if (_userProfile != null) {
          _userProfile = _userProfile!.copyWith(profilePicUrl: value);
          await StorageService.saveUserProfile(_userProfile!);
          await StorageService.saveProfilePicVersion(
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        setMessage('Foto profilo aggiornata!');
      });
      _localProfileImagePath = null;
    }, showLoading: false);

    _isUploading = false;
    notifyListeners();
  }

  Future<void> updateAnniversaryDate(DateTime date) async {
    await runSafe(() async {
      final result = await _partnershipRepo.updateAnniversaryDate(date);

      await handleResult(result, onSuccess: (_) {
        _anniversaryDate = date;
        setMessage('Anniversario aggiornato!');
      });
    });
  }

  Future<bool> wipeAppData() async {
    return runSafe(() async {
      final result = await _userRepo.debugWipeData();
      if (result is Success) {
        await StorageService.clearAppCache();
        setMessage('Data wiped successfully!');
      } else {
        throw result;
      }
    });
  }
}
