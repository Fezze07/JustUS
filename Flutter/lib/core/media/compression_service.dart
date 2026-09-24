import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';
import 'package:path_provider/path_provider.dart';

class CompressionService {
  /// Compresses an image to ~80% quality JPEG
  static Future<File> compressImage(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 80,
    );

    if (result == null) return file;

    return File(result.path);
  }

  /// Produces a small (<=320px) low-res JPEG thumbnail for gallery grids.
  static Future<File> createThumbnail(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: 320,
      minHeight: 320,
      quality: 70,
    );

    if (result == null) return file;

    return File(result.path);
  }

  /// Compresses a video using medium H.264 quality.
  static Future<File> compressVideo(File file) async {
    final result = await LightCompressor().compressVideo(
      path: file.path,
      videoQuality: VideoQuality.medium,
      video: Video(
        videoName: 'compressed_${DateTime.now().millisecondsSinceEpoch}.mp4',
      ),
      android: AndroidConfig(
        isSharedStorage: false,
      ),
      ios: IOSConfig(
        saveInGallery: false,
      ),
    );

    if (result is OnSuccess && result.destinationPath.isNotEmpty) {
      return File(result.destinationPath);
    }

    return file;
  }

  /// Audio: returns original file.
  static Future<File> compressAudio(File file) async {
    return file;
  }

  /// Validates file size before upload (15 MB hard limit)
  static bool isWithinSizeLimit(File file) {
    return file.lengthSync() <= 15 * 1024 * 1024;
  }
}
