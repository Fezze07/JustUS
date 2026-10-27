import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';

PartnershipInvitation _invite({bool received = true}) => PartnershipInvitation(
      id: 5,
      status: 'pending',
      createdAt: DateTime(2026, 10, 27),
      partnerId: 7,
      partnerDisplayName: 'Alex',
      isReceived: received,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('it'),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('default received tile keeps the invitation copy and actions',
      (tester) async {
    await tester.pumpWidget(
      _host(InvitationTile(invite: _invite(), isReceived: true)),
    );

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Vuole connettersi'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byTooltip('Accetta'), findsOneWidget);
    expect(find.byTooltip('Rifiuta'), findsOneWidget);
  });

  testWidgets('default sent tile keeps the waiting copy and the cancel action',
      (tester) async {
    await tester.pumpWidget(
      _host(InvitationTile(invite: _invite(received: false), isReceived: false)),
    );

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('In attesa di risposta'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.byTooltip('Annulla richiesta'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('custom copy, icon and tooltips override the invitation defaults',
      (tester) async {
    var accepted = 0;
    var rejected = 0;

    await tester.pumpWidget(
      _host(InvitationTile(
        invite: _invite(),
        isReceived: false,
        title: 'End the partnership?',
        subtitle: 'Partnership cancellation',
        leadingIcon: Icons.heart_broken_outlined,
        acceptTooltip: 'End it',
        rejectTooltip: 'Keep it',
        showAccept: true,
        showReject: true,
        onAccept: () => accepted++,
        onReject: () => rejected++,
      )),
    );

    expect(find.text('End the partnership?'), findsOneWidget);
    expect(find.text('Partnership cancellation'), findsOneWidget);
    expect(find.byIcon(Icons.heart_broken_outlined), findsOneWidget);
    expect(find.byTooltip('End it'), findsOneWidget);
    expect(find.byTooltip('Keep it'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);

    await tester.tap(find.byTooltip('End it'));
    await tester.tap(find.byTooltip('Keep it'));

    expect(accepted, 1);
    expect(rejected, 1);
  });
}
