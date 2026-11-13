import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';
import 'test_helpers/settle_helpers.dart';

class _FakeDriveRepository extends DriveRepository {
  _FakeDriveRepository(this.items);

  final List<DriveItem> items;

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
  Future<ResultWrapper<List<DriveItem>>> fetchDriveItemsIncremental() async {
    return const Success([]);
  }
}

DriveItem _item(int id, String type, {int isFavorite = 0}) {
  return DriveItem(
    id: id,
    type: type,
    content: 'uploads/$id/original.bin',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    isFavorite: isFavorite,
  );
}

int _gridCount(WidgetTester tester) {
  final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
  return (grid.delegate as SliverChildBuilderDelegate).estimatedChildCount!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  testWidgets('filter chips narrow the grid and the dead SELECT is gone',
      (tester) async {
    final items = [
      _item(1, 'image'),
      _item(2, 'video'),
      _item(3, 'image', isFavorite: 1),
    ];
    final state = DriveState(repository: _FakeDriveRepository(items));

    await tester.runAsync(() async {
      await StorageService.saveDriveItems(items);
      await CacheService.saveCheckpoint(
          CacheService.kDriveItems, '2026-01-31T00:00:00.000Z');
      await state.initialLoad();
      await settleMicrotasks();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<DriveState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.dark,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          home: DriveScreen(tabIndex: 4, tabNotifier: TabIndexNotifier()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SELEZIONA'), findsNothing);
    expect(_gridCount(tester), 3);

    await tester.tap(find.text('FOTO'));
    await tester.pumpAndSettle();
    expect(_gridCount(tester), 2);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);

    await tester.tap(find.text('VIDEO'));
    await tester.pumpAndSettle();
    expect(_gridCount(tester), 1);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);

    await tester.tap(find.text('LIKE'));
    await tester.pumpAndSettle();
    expect(_gridCount(tester), 1);
    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);

    await tester.tap(find.text('TUTTI'));
    await tester.pumpAndSettle();
    expect(_gridCount(tester), 3);
  });
}
