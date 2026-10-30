import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

void _noopAudioListen(Object? arguments, MockStreamHandlerEventSink events) {}

/// `DriveItemScreen` eagerly constructs an `AudioPlayer`, which opens the
/// audioplayers platform channels even for non-audio items.
void _mockAudioChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'), (_) async => null);
  messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'), (call) async {
    if (call.method == 'create') {
      final playerId = (call.arguments as Map)['playerId'] as String;
      messenger.setMockStreamHandler(
        EventChannel('xyz.luan/audioplayers/events/$playerId'),
        const MockStreamHandler.inline(onListen: _noopAudioListen),
      );
    }
    return null;
  });
  messenger.setMockStreamHandler(
    const EventChannel('xyz.luan/audioplayers.global/events'),
    const MockStreamHandler.inline(onListen: _noopAudioListen),
  );
}

class _FakeDriveRepository extends DriveRepository {
  _FakeDriveRepository(this.items);

  List<DriveItem> items;

  @override
  Future<ResultWrapper<DriveChangeProbe>> fetchChangeProbe() async {
    return Success(DriveChangeProbe(
      maxUpdatedAt: '2026-01-31T00:00:00.000Z',
      itemCount: items.length,
    ));
  }

  @override
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItems() async {
    return Success(items);
  }

  @override
  Future<ResultWrapper<void>> deleteDriveItem(int id) async {
    items = items.where((item) => item.id != id).toList();
    return const Success<void>(null);
  }
}

DriveItem _fileItem(int id, String filename) {
  return DriveItem(
    id: id,
    type: 'file',
    content: filename,
    metadata: {'filename': filename},
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    isFavorite: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    _mockAudioChannels();
  });

  testWidgets('deleting the open item shows the deleted state, not a spinner',
      (tester) async {
    final item = _fileItem(1, 'notes.pdf');
    final state = DriveState(repository: _FakeDriveRepository([item]));

    await tester.runAsync(() async {
      await StorageService.saveDriveItems([item]);
      await CacheService.saveCheckpoint(
          CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');
      await state.initialLoad();
      await settleMicrotasks();
    });
    state.loadSingleItem(1);

    await tester.pumpWidget(
      ChangeNotifierProvider<DriveState>.value(
        value: state,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('it'),
          home: DriveItemScreen(itemId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('notes.pdf'), findsOneWidget);

    expect(await tester.runAsync(() => state.deleteItem(1)), isTrue);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(LanguageHelper.appLoc.drive_deleted), findsOneWidget);
  });
}
