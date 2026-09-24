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

/// Empties every on-disk media cache used by the app: the custom R2 media
/// store ([MediaCacheManager]) and the `flutter_cache_manager` default store
/// (`DefaultCacheManager`, used by `CachedNetworkImage` without an explicit
/// manager). Best-effort — platform failures (e.g. a cache that never existed)
/// are logged and never fail the wipe flow (F-SC11).
Future<void> emptyAppMediaCaches() async {
  try {
    await MediaCacheManager().emptyCache();
  } catch (e) {
    AnsiLogger.error('R2 media cache empty failed: $e', tag: 'MediaCache');
  }
  try {
    await DefaultCacheManager().emptyCache();
  } catch (e) {
    AnsiLogger.error('default media cache empty failed: $e', tag: 'MediaCache');
  }
}

/// Custom FileService: if the "URL" is an R2 filename (starts with "users/"),
/// exchange it for a fresh signed URL before downloading.
class _R2FileService extends HttpFileService {
  final _media = MediaService();

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    // Path validation: Must be a bare R2 key (users/ | uploads/ | profile/)
    // with a minimum length to be a valid R2 path (e.g., "users/1/a.jpg" = 13 chars)
    final prefixes = ['users/', 'uploads/', 'profile/'];
    final isBareKey = !url.startsWith('http') &&
        prefixes.any((p) => url.startsWith(p)) &&
        url.length > 10;
    if (isBareKey) {
      final signedUrl = await _media.getDownloadUrl(url);
      if (signedUrl != null) {
        return super.get(signedUrl, headers: headers);
      }
    }

    return super.get(url, headers: headers);
  }
}
