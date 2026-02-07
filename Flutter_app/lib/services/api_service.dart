// =============================================================================
// ApiService - HTTP client with all API endpoints
// Dart equivalent of ApiService.kt + RetrofitClient.kt + AuthInterceptor.kt
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/models.dart';
import 'result_wrapper.dart';
import 'storage_service.dart';

class ApiService {
  // Base URLs - switch between debug and release
  static const String debugBaseUrl = 'http://192.168.1.100:5001';
  static const String releaseBaseUrl = 'https://justus.serverfede.eu';
  
  // Set this to false for production
  static const bool isDebug = true;
  
  static String get baseUrl => isDebug ? debugBaseUrl : releaseBaseUrl;

  // HTTP client
  final http.Client _client = http.Client();

  // -------------------- Helper Methods --------------------

  Future<Map<String, String>> _getHeaders({bool skipAuth = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (!skipAuth) {
      final token = await StorageService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    
    return headers;
  }



  Future<ResultWrapper<T>> _safeCall<T>(
    Future<http.Response> Function() call,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final response = await call();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        return Success(fromJson(body));
      } else {
        String? errorMessage;
        try {
          final errorBody = jsonDecode(response.body);
          errorMessage = errorBody['error'] ?? errorBody['message'];
        } catch (_) {}
        return GenericError(code: response.statusCode, message: errorMessage);
      }
    } on SocketException {
      return const NetworkError();
    } on HttpException {
      return const NetworkError();
    } catch (e) {
      return GenericError(message: e.toString());
    }
  }

  // -------------------- Auth --------------------

  Future<ResultWrapper<LoginResponse>> login(LoginRequestBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders(skipAuth: true);
        return _client.post(
          Uri.parse('$baseUrl/auth/login'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      LoginResponse.fromJson,
    );
  }

  Future<ResultWrapper<RegisterResponse>> register(RegisterRequestBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders(skipAuth: true);
        return _client.post(
          Uri.parse('$baseUrl/auth/register'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      RegisterResponse.fromJson,
    );
  }

  Future<ResultWrapper<RequestCodesResponse>> requestUserCodes(RequestCodesBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders(skipAuth: true);
        return _client.post(
          Uri.parse('$baseUrl/auth/request-code'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      RequestCodesResponse.fromJson,
    );
  }

  Future<ResultWrapper<UpdateTokenResponse>> updateDeviceToken(UpdateTokenRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/auth/device-token'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      UpdateTokenResponse.fromJson,
    );
  }

  // -------------------- Profile --------------------

  Future<ResultWrapper<ProfileResponse>> getProfile() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/profile'),
          headers: headers,
        );
      },
      ProfileResponse.fromJson,
    );
  }

  Future<ResultWrapper<ProfileResponse>> getPartnerProfile() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/profile/partner'),
          headers: headers,
        );
      },
      ProfileResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> updateProfile(UpdateProfileRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.patch(
          Uri.parse('$baseUrl/profile'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> changePassword(ChangePasswordRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/profile/change-password'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  // -------------------- Partnership --------------------

  Future<ResultWrapper<GenericResponse>> sendPartnerRequest(PartnerRequestBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/partnerships/request'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> acceptPartnerRequest(AcceptRequestBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/partnerships/accept'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> rejectPartnerRequest(AcceptRequestBody body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/partnerships/reject'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<SearchPartnerResponse>> searchPartner({String? username, String? code}) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        final queryParams = <String, String>{};
        if (username != null) queryParams['username'] = username;
        if (code != null) queryParams['code'] = code;
        
        final uri = Uri.parse('$baseUrl/partnerships/search')
            .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
        return _client.get(uri, headers: headers);
      },
      SearchPartnerResponse.fromJson,
    );
  }

  Future<ResultWrapper<PartnershipResponse>> getPartnership() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/partnerships'),
          headers: headers,
        );
      },
      PartnershipResponse.fromJson,
    );
  }

  // -------------------- MissYou --------------------

  Future<ResultWrapper<MissYouResponse>> sendMissYou() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/missyou'),
          headers: headers,
        );
      },
      MissYouResponse.fromJson,
    );
  }

  Future<ResultWrapper<MissYouResponse>> getMissYouTotal() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/missyou/total'),
          headers: headers,
        );
      },
      MissYouResponse.fromJson,
    );
  }

  // -------------------- Mood --------------------

  Future<ResultWrapper<MoodResponse>> setMood(MoodRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/mood'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      MoodResponse.fromJson,
    );
  }

  Future<ResultWrapper<MoodResponse>> getMood(String target) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/mood?target=$target'),
          headers: headers,
        );
      },
      MoodResponse.fromJson,
    );
  }

  Future<ResultWrapper<EmojiResponse>> getRecentGlobalEmojis() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/mood/recent/couple'),
          headers: headers,
        );
      },
      EmojiResponse.fromJson,
    );
  }

  // -------------------- Bucket List --------------------

  Future<ResultWrapper<BucketListResponse>> getBucket() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/bucket'),
          headers: headers,
        );
      },
      BucketListResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> addBucketItem(AddBucketRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/bucket'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> toggleBucketDone(int id) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.patch(
          Uri.parse('$baseUrl/bucket/$id'),
          headers: headers,
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> deleteBucketItem(int id) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.delete(
          Uri.parse('$baseUrl/bucket/$id'),
          headers: headers,
        );
      },
      GenericResponse.fromJson,
    );
  }

  // -------------------- Game --------------------

  Future<ResultWrapper<GameNewQuestionResponse>> getNewQuestion() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/game/new'),
          headers: headers,
        );
      },
      GameNewQuestionResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> submitAnswer(GameAnswerRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/game/answer'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GameStatsResponse>> getGameStats() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/game/stats'),
          headers: headers,
        );
      },
      GameStatsResponse.fromJson,
    );
  }

  // -------------------- Drive --------------------

  Future<ResultWrapper<DriveListResponse>> getDriveItems() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/drive'),
          headers: headers,
        );
      },
      DriveListResponse.fromJson,
    );
  }

  Future<ResultWrapper<DriveSingleResponse>> addDriveItem(DriveItemRequest body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/drive'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      DriveSingleResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> deleteDriveItem(int id) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.delete(
          Uri.parse('$baseUrl/drive/$id'),
          headers: headers,
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<DriveItemReactionResponse>> addDriveReaction(int itemId, DriveItemReaction body) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/drive/$itemId/reaction'),
          headers: headers,
          body: jsonEncode(body.toJson()),
        );
      },
      DriveItemReactionResponse.fromJson,
    );
  }

  Future<ResultWrapper<DriveItemReactionsListResponse>> getDriveReactions(int itemId) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.get(
          Uri.parse('$baseUrl/drive/$itemId/reactions'),
          headers: headers,
        );
      },
      DriveItemReactionsListResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> addFavorite(int id) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.post(
          Uri.parse('$baseUrl/drive/$id/favorite'),
          headers: headers,
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<GenericResponse>> removeFavorite(int id) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        return _client.delete(
          Uri.parse('$baseUrl/drive/$id/favorite'),
          headers: headers,
        );
      },
      GenericResponse.fromJson,
    );
  }

  Future<ResultWrapper<DriveSyncResponse>> getDriveChanges({String? lastSync}) async {
    return _safeCall(
      () async {
        final headers = await _getHeaders();
        final uri = lastSync != null
            ? Uri.parse('$baseUrl/drive/changes?since=$lastSync')
            : Uri.parse('$baseUrl/drive/changes');
        return _client.get(uri, headers: headers);
      },
      DriveSyncResponse.fromJson,
    );
  }

  // -------------------- Upload --------------------

  Future<ResultWrapper<FileUploadResponse>> uploadFile({
    required String route,
    required List<int> fileBytes,
    required String fileName,
    required String mimeType,
    void Function(int)? onProgress,
  }) async {
    try {
      final token = await StorageService.getToken();
      final uri = Uri.parse('$baseUrl$route');
      
      final request = http.MultipartRequest('POST', uri);
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final mimeTypeParts = mimeType.split('/');
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
          contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        return Success(FileUploadResponse.fromJson(body));
      } else {
        return GenericError(code: response.statusCode, message: 'Upload failed');
      }
    } on SocketException {
      return const NetworkError();
    } catch (e) {
      return GenericError(message: e.toString());
    }
  }

  // -------------------- App Version --------------------

  Future<ResultWrapper<AppVersionResponse>> getAppVersion() async {
    return _safeCall(
      () async {
        final headers = await _getHeaders(skipAuth: true);
        return _client.get(
          Uri.parse('$baseUrl/app-version'),
          headers: headers,
        );
      },
      AppVersionResponse.fromJson,
    );
  }

  // -------------------- Cleanup --------------------

  void dispose() {
    _client.close();
  }
}
