import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/widgets/host/party_limits_fields.dart';

Future<void> _pumpLimits(
  WidgetTester tester, {
  PartyLimits initial = const PartyLimits(),
  int maxGuests = 4,
  required void Function(PartyLimits) record,
}) async {
  var limits = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PartyLimitsFields(
            limits: limits,
            maxGuests: maxGuests,
            onChanged: (next) => setState(() {
              limits = next;
              record(next);
            }),
          ),
        ),
      ),
    ),
  );
}

Finder _more(String label) => find
    .widgetWithIcon(IconButton, Icons.add_circle_outline)
    .at(_indexOf(label));
Finder _fewer(String label) => find
    .widgetWithIcon(IconButton, Icons.remove_circle_outline)
    .at(_indexOf(label));

int _indexOf(String label) =>
    const ['Adults', 'Children', 'Infants'].indexOf(label);

void main() {
  group('PartyLimitsFields', () {
    // Null is the default and the norm: every listing that existed before 118
    // is unset on all four, and a null column drops out of the search
    // predicate rather than defaulting to zero.
    testWidgets('every row starts on "Any"', (tester) async {
      await _pumpLimits(tester, record: (_) {});
      expect(find.text('Any'), findsNWidgets(3));
    });

    testWidgets('stepping up from "Any" lands on the row floor',
        (tester) async {
      PartyLimits? last;
      await _pumpLimits(tester, record: (v) => last = v);

      await tester.tap(_more('Adults'));
      await tester.pump();
      // Adults floor at 1 — a listing admitting no adults is not a stay.
      expect(last!.adults, 1);

      await tester.tap(_more('Children'));
      await tester.pump();
      // Children floor at 0, which is a real rule: an adults-only place.
      expect(last!.children, 0);
    });

    // The thing a plain int stepper cannot express, and the reason these
    // columns are nullable: a host must be able to take a cap back OFF, not
    // just lower it to zero (which means something else entirely).
    testWidgets('stepping down past the floor returns to "Any"',
        (tester) async {
      PartyLimits? last;
      await _pumpLimits(
        tester,
        initial: const PartyLimits(adults: 1),
        record: (v) => last = v,
      );
      await tester.tap(_fewer('Adults'));
      await tester.pump();
      expect(last!.adults, isNull);
      expect(find.text('Any'), findsNWidgets(3));
    });

    testWidgets('zero and "Any" are different states for children',
        (tester) async {
      PartyLimits? last;
      await _pumpLimits(
        tester,
        initial: const PartyLimits(children: 1),
        record: (v) => last = v,
      );
      await tester.tap(_fewer('Children'));
      await tester.pump();
      expect(last!.children, 0, reason: 'one step down from 1 is nought');
      await tester.tap(_fewer('Children'));
      await tester.pump();
      expect(last!.children, isNull, reason: 'one step below nought is Any');
    });

    // A sub-cap above the total could never bind — max_guests refuses the
    // party first — so the control must not offer one.
    testWidgets('a counted row stops at the listing total', (tester) async {
      await _pumpLimits(
        tester,
        initial: const PartyLimits(adults: 2),
        maxGuests: 2,
        record: (_) {},
      );
      expect(tester.widget<IconButton>(_more('Adults')).onPressed, isNull);
    });

    // Infants do not count towards max_guests, so the total has no business
    // limiting them: a one-guest studio may perfectly well take a cot.
    testWidgets('infants are not bounded by the guest total', (tester) async {
      await _pumpLimits(
        tester,
        initial: const PartyLimits(infants: 1),
        maxGuests: 1,
        record: (_) {},
      );
      expect(tester.widget<IconButton>(_more('Infants')).onPressed, isNotNull);
    });
  });

  group('MaxPetsField', () {
    Future<void> pump(WidgetTester tester,
        {required bool allowed, int? maxPets}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MaxPetsField(
              petsAllowed: allowed,
              maxPets: maxPets,
              onChanged: (_) {},
            ),
          ),
        ),
      );
    }

    // A greyed number under an off switch invites the host to wonder what it
    // would do, and the answer is nothing — search checks the toggle first.
    testWidgets('renders nothing while pets are not allowed', (tester) async {
      await pump(tester, allowed: false, maxPets: 2);
      expect(find.text('Maximum pets'), findsNothing);
    });

    testWidgets('appears once the host allows pets', (tester) async {
      await pump(tester, allowed: true);
      expect(find.text('Maximum pets'), findsOneWidget);
      // Unset means "allowed, no stated number" — NOT none. The toggle above
      // already carries none, so this must not read as 0.
      expect(find.text('Any'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('shows the number the host stated', (tester) async {
      await pump(tester, allowed: true, maxPets: 2);
      expect(find.text('2'), findsOneWidget);
    });
  });
}
