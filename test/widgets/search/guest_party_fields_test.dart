import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/widgets/search/guest_party_fields.dart';

/// Pumps the rows over a held value, the way both real callers do — the
/// desktop panel through a draft, the mobile sheet through setState.
Future<GuestParty> _pump(
  WidgetTester tester, {
  GuestParty initial = const GuestParty(),
}) async {
  var party = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GuestPartyFields(
            party: party,
            onChanged: (next) => setState(() => party = next),
          ),
        ),
      ),
    ),
  );
  return party;
}

/// The stepper's buttons are labelled per row, which is the only thing that
/// tells four identical +/- pairs apart.
Finder _plus(String label) => find.bySemanticsLabel('One more $label');
Finder _minus(String label) => find.bySemanticsLabel('One fewer $label');

/// Whether a stepper button is live. The button disables by passing a null
/// `onTap` rather than by disappearing — a control that vanishes at its bound
/// moves the number out from under the cursor — so "at the limit" is read off
/// the InkWell inside the labelled Semantics, not off its absence.
bool _enabled(WidgetTester tester, Finder button) {
  final ink = find.descendant(of: button, matching: find.byType(InkWell));
  return tester.widget<InkWell>(ink.first).onTap != null;
}

/// The count sits in a 44px box between the two buttons; the row's own label
/// and description are the other Texts, so match on the digits.
int _valueFor(WidgetTester tester, String label) {
  final row = find.ancestor(of: find.text(label), matching: find.byType(Row));
  final texts = tester
      .widgetList<Text>(
          find.descendant(of: row.first, matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      .where((d) => int.tryParse(d) != null);
  return int.parse(texts.first);
}

void main() {
  group('GuestPartyFields', () {
    // The whole point of the change: the sheet used to have one number, and
    // three of these four categories had nowhere to be said.
    testWidgets('offers all four categories', (tester) async {
      await _pump(tester);
      expect(find.text('Adults'), findsOneWidget);
      expect(find.text('Children'), findsOneWidget);
      expect(find.text('Infants'), findsOneWidget);
      expect(find.text('Pets'), findsOneWidget);
    });

    testWidgets('starts at one adult and nothing else', (tester) async {
      await _pump(tester);
      expect(_valueFor(tester, 'Adults'), 1);
      expect(_valueFor(tester, 'Children'), 0);
      expect(_valueFor(tester, 'Infants'), 0);
      expect(_valueFor(tester, 'Pets'), 0);
    });

    testWidgets('each row steps independently', (tester) async {
      await _pump(tester);
      await tester.tap(_plus('Children'));
      await tester.pump();
      await tester.tap(_plus('Pets'));
      await tester.pump();
      expect(_valueFor(tester, 'Adults'), 1);
      expect(_valueFor(tester, 'Children'), 1);
      expect(_valueFor(tester, 'Pets'), 1);
      expect(_valueFor(tester, 'Infants'), 0);
    });

    // A stay booked by nobody is not a search. guestCountFor floors at 1
    // regardless, so letting the number drop would only be corrected silently
    // somewhere downstream.
    testWidgets('adults cannot go below one', (tester) async {
      await _pump(tester);
      expect(_enabled(tester, _minus('Adults')), isFalse);
    });

    testWidgets('children and infants and pets can go to zero and stop',
        (tester) async {
      await _pump(tester);
      for (final row in ['Children', 'Infants', 'Pets']) {
        expect(
          _enabled(tester, _minus(row)),
          isFalse,
          reason: '$row must not step below zero',
        );
      }
    });

    // The cap belongs to the pair, not to either row: adults + children is
    // what becomes guestCount, so both + buttons have to stop together or the
    // party could be walked past the limit one row at a time.
    testWidgets('adults and children share one budget', (tester) async {
      await _pump(
        tester,
        initial: const GuestParty(adults: maxSearchGuests - 1, children: 1),
      );
      expect(_enabled(tester, _plus('Adults')), isFalse);
      expect(_enabled(tester, _plus('Children')), isFalse);
      expect(
          find.text('Up to $maxSearchGuests guests per stay.'), findsOneWidget);
    });

    // Infants and pets are counted separately by the database and by nobody's
    // idea of a headcount, so a full party must not freeze them.
    testWidgets('a full party still admits infants and pets', (tester) async {
      await _pump(
        tester,
        initial: const GuestParty(adults: maxSearchGuests),
      );
      expect(_enabled(tester, _plus('Infants')), isTrue);
      expect(_enabled(tester, _plus('Pets')), isTrue);
    });

    testWidgets('the cap notice only appears at the cap', (tester) async {
      await _pump(tester);
      expect(find.textContaining('Up to'), findsNothing);
    });

    // A party restored from a wider cap could otherwise be stranded: with
    // max below value the minus button is the only way out and it must work.
    testWidgets('an over-cap party can still be brought down', (tester) async {
      await _pump(
        tester,
        initial: const GuestParty(adults: maxSearchGuests + 4),
      );
      expect(_enabled(tester, _minus('Adults')), isTrue);
      await tester.tap(_minus('Adults'));
      await tester.pump();
      expect(_valueFor(tester, 'Adults'), maxSearchGuests + 3);
    });
  });

  group('GuestParty', () {
    test('guestCount counts adults and children only', () {
      const party = GuestParty(adults: 2, children: 1, infants: 2, pets: 3);
      expect(party.guestCount, 3);
    });

    test('reads a live SearchFilters back without re-splitting it', () {
      const filters = SearchFilters(
          guestCount: 3, adults: 2, children: 1, infants: 1, pets: 2);
      final party = GuestParty.from(filters);
      expect(party.adults, 2);
      expect(party.children, 1);
      expect(party.infants, 1);
      expect(party.pets, 2);
    });

    test('equality covers every field, so a pets-only edit rebuilds', () {
      expect(const GuestParty(pets: 1), isNot(const GuestParty()));
      expect(const GuestParty(infants: 1), isNot(const GuestParty()));
      expect(const GuestParty(adults: 1), const GuestParty());
    });
  });
}
