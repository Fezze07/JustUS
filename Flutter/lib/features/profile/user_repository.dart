import 'dart:io' as dart_io;

import 'package:justus/all_imports.dart';

class UserRepository extends BaseRepository {
  final MediaService _mediaService;

  UserRepository({super.sbClient, MediaService? mediaService}) 
    : _mediaService = mediaService ?? MediaService();

  Future<ResultWrapper<User>> fetchProfileByAuthId(String authId) async {
    return tryCall(() async {
      final profile = await sbClient
          .from('users')
          .select('id, email, auth_id, created_at, user_profiles(display_name, profile_pic_url, bio, partnership_code)')
          .eq('auth_id', authId)
          .maybeSingle();

      if (profile == null) throw Exception('Profilo utente non trovato nel database');

      return User.fromJson(profile);
    });
  }

  Future<ResultWrapper<User>> fetchProfile() async {
    return withUser((uid) async {
      final data = await sbClient
          .from('users')
          .select('id, email, auth_id, created_at, user_profiles(display_name, profile_pic_url, bio, partnership_code)')
          .eq('id', uid)
          .maybeSingle();
      if (data == null) throw Exception('Profilo non trovato');

      return User.fromJson(data);
    });
  }

  Future<ResultWrapper<void>> updateBio(String? bio) async {
    return withUser((uid) async {
      await sbClient
          .from('user_profiles')
          .update({'bio': bio})
          .eq('user_id', uid);
    });
  }

  Future<ResultWrapper<void>> updateDisplayName(String displayName) async {
    return withUser((uid) async {
      await sbClient
          .from('user_profiles')
          .update({'display_name': displayName})
          .eq('user_id', uid);
    });
  }

  Future<ResultWrapper<String>> uploadProfilePicture(dart_io.File file) async {
    return withUser((uid) async {
      final r2Path = await _mediaService.uploadProfilePicture(file, uid);
      if (r2Path == null) throw Exception('Upload to R2 failed');

      return r2Path;
    });
  }

  Future<ResultWrapper<void>> debugWipeData() async {
    final api = ApiService();
    final result = await api.wipeUserData();
    
    return switch (result) {
      Success() => const Success(null),
      GenericError(:final message, :final code, :final details) => 
        GenericError(message: message, code: code, details: details),
      NetworkError(:final message) => 
        NetworkError(message: message),
    };
  }
}
