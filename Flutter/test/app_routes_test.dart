import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';
import 'package:justus/main.dart' show generateAppRoute;

void main() {
  testWidgets('a known route name builds its real screen', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<LanguageProvider>.value(
        value: LanguageProvider(),
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) {
              final route = generateAppRoute(
                const RouteSettings(name: AppRoutes.localization),
              ) as MaterialPageRoute<dynamic>;
              return route.builder(context);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LocalizationScreen), findsOneWidget);
  });

  test('unknown route names return null instead of a second splash', () {
    expect(generateAppRoute(const RouteSettings(name: '/callback')), isNull);
  });

  test('the drive item route requires an integer argument', () {
    expect(
      generateAppRoute(
        const RouteSettings(name: AppRoutes.driveItem, arguments: 42),
      ),
      isA<MaterialPageRoute<dynamic>>(),
    );
    expect(
      generateAppRoute(const RouteSettings(name: AppRoutes.driveItem)),
      isNull,
    );
  });
}
