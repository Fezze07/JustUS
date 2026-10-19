import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:justus/all_imports.dart';
import 'package:justus/main.dart' show AuthMessageHost;
import 'package:provider/provider.dart';

/// `StateMessageListener` is the one path that turns a `BaseState.message` into
/// user-visible feedback (used by every feedback screen, plus the global
/// `AuthMessageHost`). A regression here silently drops or duplicates messages
/// app-wide, so the mixin's contract is pinned here against a throwaway host.
class _TestState extends BaseState {}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.state, this.child});

  final BaseState state;
  final Widget? child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host>
    with StateMessageListener<BaseState, _Host> {
  @override
  BaseState get messageSource => widget.state;

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}

Widget _app(_Host host) => MaterialApp(home: host);

void main() {
  testWidgets('a new message is shown once and then cleared', (tester) async {
    final state = _TestState();
    await tester.pumpWidget(_app(_Host(state: state)));

    state.setMessage('hello');
    await tester.pump(); // post-frame notify reaches the listener
    await tester.pump(); // overlay entry builds

    expect(find.text('hello'), findsOneWidget);
    expect(state.message, isNull,
        reason: 'showing the message must clear it, or the next notify '
            'would show it a second time');

    await tester.pump(const Duration(seconds: 5)); // drain auto-dismiss timer
  });

  testWidgets('showPendingMessage surfaces a message set right before a pop',
      (tester) async {
    final state = _TestState();
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_app(_Host(key: key, state: state)));

    // The frame that would deliver the message never runs: the screen pops
    // first, so the screen itself must flush it.
    state.setMessage('queued');
    key.currentState!.showPendingMessage();

    await tester.pump();
    await tester.pump();

    expect(find.text('queued'), findsOneWidget);
    expect(state.message, isNull);

    await tester.pump(const Duration(seconds: 5)); // drain auto-dismiss timer
  });

  testWidgets('a host above the Navigator still reaches the root overlay',
      (tester) async {
    final state = _TestState();
    // Mirrors `AuthMessageHost` in main.dart: the listener lives in
    // `MaterialApp.builder`, ABOVE the Navigator. `Navigator.maybeOf` from
    // there finds no ancestor Navigator, so delivery depends entirely on the
    // `navigatorKey.currentState?.overlay` fallback in
    // `ErrorHandler.showSnackBar` (MaterialApp must get that same key).
    await tester.pumpWidget(MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
      home: const SizedBox.shrink(),
      builder: (context, child) => _Host(state: state, child: child),
    ));

    state.setMessage('hello');
    await tester.pump(); // post-frame notify reaches the listener
    await tester.pump(); // overlay entry builds

    expect(find.text('hello'), findsOneWidget,
        reason: 'a message set on the global AuthState host must be shown '
            'through the navigatorKey fallback, or it is silently dropped');

    await tester.pump(const Duration(seconds: 5)); // drain auto-dismiss timer
  });

  testWidgets('the real AuthMessageHost renders an AuthState message',
      (tester) async {
    // Unlike the mirror above, this pumps the actual host from main.dart, so
    // its `context.read<AuthState>()` lookup and the provider wiring that
    // surrounds MaterialApp in JustUsApp are exercised too.
    final auth = AuthState();
    await tester.pumpWidget(ChangeNotifierProvider<AuthState>.value(
      value: auth,
      child: MaterialApp(
        navigatorKey: ErrorHandler.navigatorKey,
        home: const SizedBox.shrink(),
        builder: (context, child) =>
            AuthMessageHost(child: child ?? const SizedBox.shrink()),
      ),
    ));

    auth.setMessage('hello');
    await tester.pump(); // post-frame notify reaches the listener
    await tester.pump(); // overlay entry builds

    expect(find.text('hello'), findsOneWidget);
    expect(auth.message, isNull);

    await tester.pump(const Duration(seconds: 5)); // drain auto-dismiss timer
  });
}
