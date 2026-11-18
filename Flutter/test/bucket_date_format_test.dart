import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:justus/all_imports.dart';
import 'test_helpers/mock_secure_storage.dart';

class _FakeBucketRepository extends BucketRepository {}

Future<BucketState> _stateWith(String createdAt) async {
  final state = BucketState(repository: _FakeBucketRepository());
  await state.applyRealtimeEvent(
    eventType: 'insert',
    newRecord: {
      'id': 1,
      'text': 'goal',
      'done': false,
      'created_at': createdAt,
      'updated_at': '2026-05-01T12:00:00.000Z',
      'category': 'Travel',
    },
    oldRecord: const {},
  );
  state.cancelPending();

  return state;
}

Future<void> _pump(
    WidgetTester tester, BucketState state, Locale locale) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<BucketState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: BucketListScreen(tabIndex: 3, tabNotifier: TabIndexNotifier()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installMockSecureStorage();
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
  });

  testWidgets('the created-on line uses the app locale medium date',
      (tester) async {
    final state = await _stateWith('2026-05-01T12:00:00.000Z');

    await _pump(tester, state, const Locale('it'));
    expect(find.textContaining('2026-05-01'), findsNothing);
    expect(find.textContaining('1 mag'), findsOneWidget);

    await _pump(tester, state, const Locale('en'));
    expect(find.textContaining('2026-05-01'), findsNothing);
    expect(find.textContaining('May 1'), findsOneWidget);
  });

  testWidgets('a malformed created-at shows the raw date portion',
      (tester) async {
    final state = await _stateWith('not-a-date');

    await _pump(tester, state, const Locale('en'));

    expect(tester.takeException(), isNull);
    expect(find.text('Created on: not-a-date'), findsOneWidget);
  });
}
