import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/screens/host/listing_availability_screen.dart';

/// Opens the dialog from a button, exactly as the availability screen does, and
/// records what it returned.
Future<void> _pump(WidgetTester tester, List<String?> out) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => out.add(await showBlockNoteDialog(context)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // THE BUG THIS PINS. The first version built the TextEditingController in the
  // caller and disposed it right after `await showDialog(...)`. That future
  // completes the instant Navigator.pop runs, while the route is still mounted
  // for its exit animation — so the controller died under a live TextField, and
  // because the field is autofocused the focus tree went with it. What a host
  // actually saw was a flicker and a wall of framework assertions
  // (`_dependents.isEmpty`, then bogus "Duplicate GlobalKeys"), never a message
  // naming the real cause.
  //
  // pumpAndSettle runs the exit animation to completion, which is precisely the
  // window the old code corrupted; takeException is what catches it.
  testWidgets('saving a note does not outlive its controller', (tester) async {
    final out = <String?>[];
    await _pump(tester, out);

    await tester.enterText(find.byType(TextField), 'Family visit');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(out.single, 'Family visit');
  });

  testWidgets('skipping does not outlive its controller either',
      (tester) async {
    final out = <String?>[];
    await _pump(tester, out);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(out.single, isNull);
  });

  testWidgets('dismissing by tapping outside returns null cleanly',
      (tester) async {
    final out = <String?>[];
    await _pump(tester, out);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(out.single, isNull);
  });

  testWidgets('opening it twice in a row is clean', (tester) async {
    // The controller is per-route. If it were ever hoisted to a field on the
    // screen's State instead, the second open would reuse a disposed one.
    final out = <String?>[];
    await _pump(tester, out);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Second');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(out, [null, 'Second']);
  });

  testWidgets('submitting from the keyboard returns the text', (tester) async {
    // Pressing enter in a one-line field is the obvious gesture and used to do
    // nothing at all, stranding the host in a dialog with no visible effect.
    final out = <String?>[];
    await _pump(tester, out);

    await tester.enterText(find.byType(TextField), 'Maintenance');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(out.single, 'Maintenance');
  });
}
