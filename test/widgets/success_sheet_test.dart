import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/widgets/success_sheet.dart';

/// Pumps a screen with a button that opens the SuccessSheet.
Future<void> _pumpWithOpener(
  WidgetTester tester, {
  Duration? autoDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => SuccessSheet.show(
                context,
                title: 'Request sent',
                message: 'Awaiting host confirmation.',
                primaryLabel: 'Got it',
                autoDismiss: autoDismiss,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a close (X) button that dismisses the sheet',
      (tester) async {
    await _pumpWithOpener(tester, autoDismiss: null); // no auto-dismiss
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsNothing);
  });

  testWidgets('auto-dismisses after the configured delay (no double-pop)',
      (tester) async {
    await _pumpWithOpener(tester, autoDismiss: const Duration(seconds: 2));
    await tester.tap(find.text('open'));
    await tester.pump(); // start open
    await tester.pump(const Duration(milliseconds: 900)); // entrance anim
    expect(find.text('Request sent'), findsOneWidget);

    // Past the auto-dismiss window.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsNothing);
    expect(tester.takeException(), isNull); // timer never popped twice
  });

  testWidgets('primary button invokes its callback and closes once',
      (tester) async {
    var primaryTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => SuccessSheet.show(
                  context,
                  title: 'Request sent',
                  message: 'Awaiting host confirmation.',
                  primaryLabel: 'Got it',
                  autoDismiss: null,
                  onPrimary: () => primaryTaps++,
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

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    expect(primaryTaps, 1);
    expect(find.text('Request sent'), findsNothing);
  });
}
