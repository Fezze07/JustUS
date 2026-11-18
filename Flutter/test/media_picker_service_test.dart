import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

void main() {
  testWidgets('the default picker sheet keeps all four sources',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                await MediaPickerService.showPickerSheet(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('From Gallery'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Document (PDF)'), findsOneWidget);
  });
}
