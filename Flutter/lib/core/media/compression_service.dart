import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

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

  /// Compresses a video to Medium quality
  static Future<File> compressVideo(File file) async {
    final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.MediumQuality,
    );

    if (mediaInfo == null || mediaInfo.file == null) return file;

    return mediaInfo.file!;
  }

  /// Audio: returns original file. Bitrate reduction can be added via ffmpeg if needed.
  static Future<File> compressAudio(File file) async {
    return file;
  }

  /// Validates file size before upload (15 MB hard limit)
  static bool isWithinSizeLimit(File file) {
    return file.lengthSync() <= 15 * 1024 * 1024;
  }
}
