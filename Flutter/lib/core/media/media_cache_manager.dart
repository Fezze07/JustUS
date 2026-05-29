import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:justus/all_imports.dart';

/// Custom CacheManager for R2 media files.
/// Intercepts the R2 filename path (e.g. "users/42/image/uuid.jpg"),
/// fetches a fresh signed URL via the Edge Function, then downloads
/// and caches the file locally for up to 30 days.
class MediaCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'justus_media_cache';

  static final MediaCacheManager _instance = MediaCacheManager._();
  factory MediaCacheManager() => _instance;

  MediaCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 300,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: _R2FileService(),
        ));
}

/// Custom FileService: if the "URL" is an R2 filename (starts with "users/"),
/// exchange it for a fresh signed URL before downloading.
class _R2FileService extends HttpFileService {
  final _media = MediaService();

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    // Path validation: Must start with "users/" and have a minimum length to be a valid R2 path
    // (e.g., "users/1/a.jpg" is 13 chars)
    if (!url.startsWith('http') && url.startsWith('users/') && url.length > 10) {
      final signedUrl = await _media.getDownloadUrl(url);
      if (signedUrl != null) {
        return super.get(signedUrl, headers: headers);
      }
    }
    
    return super.get(url, headers: headers);
  }
}
