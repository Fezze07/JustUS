import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justus/all_imports.dart';

import 'test_helpers/mock_path_provider.dart';

/// Stands in for the native compressor: writes a real file at the requested
/// target path and records it, so the test can prove cleanup happened.
class _FakeImageCompress extends UnsupportedFlutterImageCompress {
  final List<String> generated = [];

  @override
  Future<XFile?> compressAndGetFile(
    String path,
    String targetPath, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async {
    final target = File(targetPath);
    await target.writeAsBytes(List<int>.filled(1024, 0));
    generated.add(target.path);
    return XFile(target.path);
  }
}

class _FakeApi extends ApiService {
  _FakeApi(this.uploadUrl);

  final String uploadUrl;
  int presignCalls = 0;

  @override
  Future<ResultWrapper<Map<String, dynamic>>> createMediaUploadUrl(
      Map<String, dynamic> body) async {
    presignCalls++;
    return Success<Map<String, dynamic>>({
      'uploadUrl': uploadUrl,
      'filename': 'uploads/1/image/file$presignCalls.jpg',
    });
  }

  @override
  Future<ResultWrapper<Map<String, dynamic>>> completeMediaUpload(
          Map<String, dynamic> body) async =>
      Success<Map<String, dynamic>>({
        'item': {'id': 1, 'name': body['filename']},
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installMockPathProvider);

  tearDown(() {
    FlutterImageCompressPlatform.instance = UnsupportedFlutterImageCompress();
  });

  test('uploadMedia deletes compressed files and thumbnails, keeps original',
      () async {
    final compressor = _FakeImageCompress();
    FlutterImageCompressPlatform.instance = compressor;
    final api = _FakeApi('https://r2.test/upload');

    final tempDir = Directory.systemTemp.createTempSync('justus_upload_source');
    addTearDown(() => tempDir.delete(recursive: true));
    final original = File('${tempDir.path}/original.jpg');
    await original.writeAsBytes(List<int>.filled(10 * 1024 * 1024, 7));

    final result = await MediaService(
      api: api,
      httpClient: MockClient((_) async => http.Response('', 200)),
    ).uploadMedia(
      file: original,
      type: MediaType.image,
      userId: 1,
    );

    expect(result, isNotNull);
    expect(original.existsSync(), isTrue);
    expect(compressor.generated, hasLength(2));
    for (final path in compressor.generated) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
  });

  test('createVideoThumbnail deletes the extracted video frame', () async {
    final compressor = _FakeImageCompress();
    FlutterImageCompressPlatform.instance = compressor;

    final tempDir = Directory.systemTemp.createTempSync('justus_video_source');
    addTearDown(() => tempDir.delete(recursive: true));
    final video = File('${tempDir.path}/clip.mp4')
      ..writeAsBytesSync([1, 2, 3]);
    final frame = File('${tempDir.path}/frame.jpg')
      ..writeAsBytesSync([4, 5, 6]);

    const channel = MethodChannel('light_compressor');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'getVideoThumbnail' ? frame.path : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final thumbnail = await CompressionService.createVideoThumbnail(video);

    expect(frame.existsSync(), isFalse);
    expect(thumbnail.path, compressor.generated.single);
    expect(thumbnail.existsSync(), isTrue);
  });
}
