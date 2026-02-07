import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justus/main.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const JustUsApp());
    
    // Verify it builds without crashing (finds JustUsApp widget)
    expect(find.byType(JustUsApp), findsOneWidget);
    
    // Allow any async operations to settle (like SplashScreen init)
    await tester.pumpAndSettle();
  });
}
