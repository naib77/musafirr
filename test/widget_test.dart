import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/app.dart';

void main() {
  testWidgets('musafir app renders login screen when not authenticated',
      // MusafirApp constructs Supabase-backed singletons in initState, so it
      // cannot boot in a test environment without Supabase.initialize().
      // Re-enable once the app graph accepts injected fakes.
      skip: true, // Requires Supabase initialization; app has no DI seam yet.
      (tester) async {
    await tester.pumpWidget(const MusafirApp());
    await tester.pumpAndSettle();

    // App should show login screen initially
    expect(find.text('Welcome to Musafir'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
