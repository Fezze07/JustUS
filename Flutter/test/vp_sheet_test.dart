import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justus/all_imports.dart';

/// Regression tests for the VPSheet layout contract:
/// - a sheet without flexible children hugs its content at the bottom;
/// - `maxHeightFactor` really caps the sheet (it used to be ignored, so a
///   `Column` with the default `MainAxisSize.max` filled the whole screen).
Future<void> _openSheet(
  WidgetTester tester, {
  required Widget sheet,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => sheet,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Size _sheetSize(WidgetTester tester) => tester.getSize(find.byType(VPSheet));

void main() {
  testWidgets('sheet without flexible children stays docked at the bottom',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _openSheet(
      tester,
      sheet: const VPSheet(
        children: [
          ListTile(title: Text('one')),
          ListTile(title: Text('two')),
          ListTile(title: Text('three')),
        ],
      ),
    );

    final sheet = _sheetSize(tester);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(sheet.height, lessThan(screen.height * 0.5),
        reason: 'a 3-tile sheet must not stretch to the top of the screen');
    expect(
      tester.getBottomLeft(find.byType(VPSheet)).dy,
      moreOrLessEquals(screen.height, epsilon: 1),
      reason: 'the sheet must be anchored to the bottom of the screen',
    );
  });

  testWidgets('maxHeightFactor caps a sheet with a flexible child',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _openSheet(
      tester,
      sheet: const VPSheet(
        title: 'Title',
        maxHeightFactor: 0.5,
        children: [
          Expanded(child: SizedBox.expand()),
        ],
      ),
    );

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(_sheetSize(tester).height,
        moreOrLessEquals(screen.height * 0.5, epsilon: 1));
  });
}
