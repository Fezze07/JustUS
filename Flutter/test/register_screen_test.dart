import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:justus/all_imports.dart';

class _FakeAuthState extends AuthState {
  int registerCalls = 0;

  @override
  Future<bool> register(String email, String password, String name) async {
    registerCalls += 1;
    return true;
  }
}

void main() {
  Future<_FakeAuthState> pumpRegister(WidgetTester tester) async {
    final auth = _FakeAuthState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthState>.value(
        value: auth,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('it'),
          navigatorKey: ErrorHandler.navigatorKey,
          home: const RegisterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String password,
    required String confirmation,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Mario');
    await tester.enterText(fields.at(1), 'mario@example.com');
    await tester.enterText(fields.at(2), password);
    await tester.enterText(fields.at(3), confirmation);

    await tester.ensureVisible(find.text('Crea account'));
    await tester.tap(find.text('Crea account'));
    await tester.pumpAndSettle();
  }

  testWidgets('blocks registration when the passwords do not match',
      (tester) async {
    final auth = await pumpRegister(tester);

    await fillAndSubmit(
      tester,
      password: 'Password1!',
      confirmation: 'Password2!',
    );

    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(auth.registerCalls, 0);
  });

  testWidgets('registers when the confirmation matches', (tester) async {
    final auth = await pumpRegister(tester);

    await fillAndSubmit(
      tester,
      password: 'Password1!',
      confirmation: 'Password1!',
    );

    expect(auth.registerCalls, 1);
    expect(find.text('Controlla la tua email'), findsOneWidget);
  });
}
