import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void installMockSecureStorage() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    final key = call.arguments['key'] as String?;

    switch (call.method) {
      case 'write':
        if (key != null) {
          values[key] = call.arguments['value'] as String? ?? '';
        }

        return null;
      case 'read':
        return key == null ? null : values[key];
      case 'delete':
        if (key != null) {
          values.remove(key);
        }

        return null;
      case 'deleteAll':
        values.clear();

        return null;
      case 'containsKey':
        return key != null && values.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(values);
      default:
        return null;
    }
  });
}
