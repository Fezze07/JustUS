import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_path_provider.dart';
import 'test_helpers/mock_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    installMockSecureStorage();
    installMockPathProvider();
    StorageService.resetForTest();
    ApiService.clearHeadersCache();
    ApiService.readAccessTokenForTest = () => 'test-token';
  });

  tearDown(() {
    ApiService.readAccessTokenForTest = null;
  });

  testWidgets('media image requests carry auth and device fingerprint headers',
      (tester) async {
    await ApiService.primeDeviceFingerprint();

    await tester.pumpWidget(const MaterialApp(
      home: ProtectedNetworkImage(url: 'uploads/42/pic.jpg'),
    ));

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );

    expect(image.httpHeaders?['Authorization'], 'Bearer test-token');
    expect(image.httpHeaders?['X-Device-Fingerprint'], isNotEmpty);

    await tester.pumpWidget(const SizedBox());
  });
}
