import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

/// Installs an in-memory method-channel implementation of path_provider so
/// flutter_cache_manager (MediaCacheManager / DefaultCacheManager) works in
/// widget tests — used by the wipe-path media-cache clearing (F-SC11).
void installMockPathProvider() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = Directory.systemTemp.createTempSync('justus_path_provider');
  final cacheDir = Directory('${base.path}/cache')..createSync(recursive: true);
  final supportDir = Directory('${base.path}/support')
    ..createSync(recursive: true);

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    switch (call.method) {
      case 'getTemporaryDirectory':
        return cacheDir.path;
      case 'getApplicationSupportDirectory':
        return supportDir.path;
      case 'getApplicationCacheDirectory':
        return cacheDir.path;
      default:
        return base.path;
    }
  });
}
