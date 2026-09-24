import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'package:justus/all_imports.dart';

class MediaService {
  final _api = ApiService();
  final _logger = Logger(
    printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 50,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart),
  );

  // ---------------------------------------------------------------------------
  // GET: Request a temporary signed URL for viewing a file
  // ---------------------------------------------------------------------------
  Future<String?> getDownloadUrl(String filename) async {
    return ApiService.resolveProtectedMediaUrl(filename);
  }

  // ---------------------------------------------------------------------------
  // PUT: Compress → Validate → Get PUT signed URL → Upload to R2 → (Optional) Save metadata
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> uploadMedia({
    required File file,
    required MediaType type,
    required int userId,
    int? partnerId,
    String? mimeType,
    String? customFolder,
    bool skipRegistration = false,
  }) async {
    try {
      // 1. MIME validation
      final mime = mimeType ?? _inferMime(file.path, type);
      final allowed = _allowedMimes[type] ?? [];
      if (allowed.isNotEmpty && !allowed.contains(mime)) {
        throw Exception('Invalid MIME type: $mime');
      }

      // 2. Size guard BEFORE compression (fast-fail)
      if (!CompressionService.isWithinSizeLimit(file)) {
        throw Exception('File exceeds 15 MB limit before compression');
      }

      // 3. Compression
      _logger.i('[MediaService] Starting compression for ${type.name}...');
      File compressed;
      if (type == MediaType.image) {
        compressed = await CompressionService.compressImage(file);
      } else if (type == MediaType.video) {
        compressed = await CompressionService.compressVideo(file);
      } else {
        compressed = file;
      }

      final finalSize = await compressed.length();
      final originalName = file.path.split(RegExp(r'[/\\]')).last;

      // 4. Request PUT Signed URL from Edge Function
      final presignResult = await _api.createMediaUploadUrl({
        'type': type.name,
        'filename': originalName,
        'mimeType': mime,
        'size': finalSize,
        if (customFolder != null) 'folder': customFolder,
      });

      if (presignResult is! Success<Map<String, dynamic>>) {
        final message = presignResult is GenericError<Map<String, dynamic>>
            ? presignResult.message
            : 'Unable to create upload URL';
        throw Exception(message);
      }

      final uploadUrl = presignResult.value['uploadUrl'] as String;
      final r2Filename = presignResult.value['filename'] as String;

      // 5. Upload directly to Cloudflare R2
      _logger.i('[MediaService] Uploading to R2: $r2Filename');
      final uploadResult = await http.put(
        Uri.parse(uploadUrl),
        body: await compressed.readAsBytes(),
        headers: {'Content-Type': mime},
      );

      if (uploadResult.statusCode != 200) {
        throw Exception(
            'R2 upload failed [${uploadResult.statusCode}]: ${uploadResult.body}');
      }

      // 5b. Thumbnail generation + upload (image drive items, best-effort)
      String? thumbnailKey;
      if (!skipRegistration && type == MediaType.image) {
        thumbnailKey = await _uploadThumbnail(
          source: file,
          customFolder: customFolder,
        );
      }

      // 6. Register metadata via backend
      _logger.i('[MediaService] Registering metadata in backend...');
      final completeResult = await _api.completeMediaUpload({
        'kind': skipRegistration ? 'profile' : 'drive',
        'type': type.name,
        'filename': r2Filename,
        'originalName': originalName,
        'mimeType': mime,
        'size': finalSize,
        'metadata': {
          'compressed': type == MediaType.image || type == MediaType.video,
          if (thumbnailKey != null) 'thumbnail': thumbnailKey,
          if (partnerId != null) 'partner_id': partnerId,
        },
      });

      if (completeResult is! Success<Map<String, dynamic>>) {
        final message = completeResult is GenericError<Map<String, dynamic>>
            ? completeResult.message
            : 'Unable to register upload';
        throw Exception(message);
      }

      if (skipRegistration) {
        return {
          'filename': completeResult.value['filename'],
          'size': finalSize
        };
      }

      return completeResult.value['item'] as Map<String, dynamic>?;
    } catch (e, stack) {
      _logger.e('[MediaService] Exception in uploadMedia',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Specialized helper for profile pictures
  Future<String?> uploadProfilePicture(File file, int userId) async {
    final result = await uploadMedia(
      file: file,
      type: MediaType.image,
      userId: userId,
      customFolder: 'profile',
      skipRegistration: true,
    );

    return result?['filename'] as String?;
  }

  /// Generates a low-res thumbnail and uploads it to R2 under the same prefix.
  /// Returns the `uploads/...` storage key of the thumbnail, or `null` on any
  /// failure (best-effort: a failed thumbnail never fails the main upload).
  Future<String?> _uploadThumbnail({
    required File source,
    String? customFolder,
  }) async {
    try {
      final thumbnail = await CompressionService.createThumbnail(source);
      final thumbSize = await thumbnail.length();

      final presignResult = await _api.createMediaUploadUrl({
        'type': 'image',
        'filename': 'thumb.jpg',
        'mimeType': 'image/jpeg',
        'size': thumbSize,
        if (customFolder != null) 'folder': customFolder,
      });

      if (presignResult is! Success<Map<String, dynamic>>) return null;

      final uploadUrl = presignResult.value['uploadUrl'] as String;
      final thumbKey = presignResult.value['filename'] as String;

      final result = await http.put(
        Uri.parse(uploadUrl),
        body: await thumbnail.readAsBytes(),
        headers: {'Content-Type': 'image/jpeg'},
      );

      if (result.statusCode != 200) {
        _logger.e('[MediaService] Thumbnail upload failed [${result.statusCode}]');
        return null;
      }

      return thumbKey;
    } catch (e, st) {
      _logger.e('[MediaService] Thumbnail generation/upload failed',
          error: e, stackTrace: st);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _inferMime(String path, MediaType type) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'wav': 'audio/wav',
      'pdf': 'application/pdf',
    };

    return map[ext] ?? 'application/octet-stream';
  }
}

enum MediaType { image, video, audio, file }

const _allowedMimes = {
  MediaType.image: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
  MediaType.video: ['video/mp4', 'video/quicktime', 'video/x-msvideo'],
  MediaType.audio: ['audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav'],
  MediaType.file: ['application/pdf', 'application/octet-stream'],
};
