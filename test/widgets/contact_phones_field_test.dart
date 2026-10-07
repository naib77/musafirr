import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/contact_phone.dart';
import 'package:musafir/widgets/contact_phones_field.dart';

void main() {
  Future<ContactPhonesController> pump(WidgetTester tester) async {
    final c = ContactPhonesController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ContactPhonesField(controller: c)),
      ),
    ));
    return c;
  }

  testWidgets('adds rows up to the cap, then hides Add', (tester) async {
    final c = await pump(tester);
    expect(find.byType(TextFormField), findsOneWidget);
    for (var i = 1; i < maxContactPhones; i++) {
      await tester.tap(find.text('Add another number'));
      await tester.pump();
    }
    expect(find.byType(TextFormField), findsNWidgets(maxContactPhones));
    expect(find.text('Add another number'), findsNothing);
    expect(c.texts.length, maxContactPhones);
  });

  testWidgets('removing a row keeps the others and their text', (tester) async {
    final c = await pump(tester);
    c.setStored(['+8801711165212', '+8801811165212', '+8801911165212']);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Remove contact phone 2'));
    await tester.pump();
    expect(c.texts, ['01711165212', '01911165212']);
    expect(c.normalized(), ['+8801711165212', '+8801911165212']);
  });

  test('removing the only row clears it rather than dropping the field', () {
    final c = ContactPhonesController()..setStored(['+8801711165212']);
    c.removeAt(0);
    expect(c.texts, ['']);
    c.dispose();
  });
}
