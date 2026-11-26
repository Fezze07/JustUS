import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

void main() {
  Future<void> pumpAuthScreen(
    WidgetTester tester,
    Widget screen, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: AuthState(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          navigatorKey: ErrorHandler.navigatorKey,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final header = find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).gradient != null,
  );

  void expectHeaderSpacing(WidgetTester tester, String title) {
    final headerBottom = tester.getBottomLeft(header).dy;
    final titleTop = tester.getTopLeft(find.text(title)).dy;
    final taglineBottom = tester
        .getBottomLeft(find.text('Uno spazio privato per la coppia'))
        .dy;

    // Form title starts at least AppSpacing.xl below the header.
    expect(titleTop - headerBottom, greaterThanOrEqualTo(AppSpacing.xl));
    // Tagline stays clear of the decorative curve at the header bottom.
    expect(taglineBottom, lessThanOrEqualTo(headerBottom - AppSpacing.xl));
    expect(tester.takeException(), isNull);
  }

  testWidgets('login keeps the tagline clear of the header curve and the title',
      (tester) async {
    await pumpAuthScreen(
      tester,
      const LoginScreen(),
      size: const Size(800, 600),
    );

    expectHeaderSpacing(tester, 'Bentornato');
  });

  testWidgets('login spacing holds on short screens', (tester) async {
    await pumpAuthScreen(
      tester,
      const LoginScreen(),
      size: const Size(800, 480),
    );

    expectHeaderSpacing(tester, 'Bentornato');
  });

  testWidgets('register keeps the same balanced spacing', (tester) async {
    await pumpAuthScreen(
      tester,
      const RegisterScreen(),
      size: const Size(800, 480),
    );

    expectHeaderSpacing(tester, 'Unisciti a JustUS');
  });
}
