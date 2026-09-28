import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing_purpose.dart';
import 'package:musafir/widgets/purpose_picker.dart';

Future<ListingPurpose?> _tapAt(WidgetTester tester, String label,
    {double width = 310}) async {
  ListingPurpose? picked;
  var reported = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PurposePicker(
              selected: null,
              onSelected: (p) {
                picked = p;
                reported = true;
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(label));
  await tester.pump();
  expect(reported, isTrue, reason: 'the tap must reach the callback');
  return picked;
}

void main() {
  group('PurposePicker', () {
    // general is a host default, not something a guest searches for, and
    // "Any purpose" already means no filter.
    testWidgets('offers every purpose except general', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 310,
              child: PurposePicker(selected: null, onSelected: _noop),
            ),
          ),
        ),
      );
      expect(find.text('Any purpose'), findsOneWidget);
      for (final purpose in ListingPurpose.values) {
        if (purpose == ListingPurpose.general) continue;
        expect(find.text(purpose.label), findsOneWidget,
            reason: '${purpose.name} must be offered');
      }
    });

    // The whole reason this stopped being a horizontal ListView: inside a
    // padded card the scroller clipped at the padding, slicing the last pill
    // mid-word with a gap after it. Wrapped, nothing is cut and nothing needs
    // a gesture to reach.
    testWidgets('every pill is fully on screen in a narrow card',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: PurposePicker(selected: null, onSelected: _noop),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final card = tester.getRect(find.byType(PurposePicker));
      for (final purpose in ListingPurpose.values) {
        if (purpose == ListingPurpose.general) continue;
        final pill = tester.getRect(find.text(purpose.label));
        expect(pill.left, greaterThanOrEqualTo(card.left - 0.5),
            reason: '${purpose.name} is cut off on the left');
        expect(pill.right, lessThanOrEqualTo(card.right + 0.5),
            reason: '${purpose.name} is cut off on the right');
      }
    });

    testWidgets('it wraps rather than running off in one row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: PurposePicker(selected: null, onSelected: _noop),
              ),
            ),
          ),
        ),
      );
      final first = tester.getRect(find.text('Any purpose'));
      final last = tester.getRect(find.text(ListingPurpose.values.last.label));
      expect(last.top, greaterThan(first.top),
          reason: 'six pills cannot fit one 240px row');
    });

    // A Wrap hands its children the full line width, so a pill whose Row
    // forgets mainAxisSize.min becomes a full-width bar and the "wrapping"
    // above is satisfied by six stacked rows. That is what shipped first, and
    // the screenshot caught it rather than the test.
    //
    // Measured on the pill's Material, not on the Text: under the bug the Row
    // expands but the label inside it does not move or grow, so the text rect
    // is identical either way. The box is wide (the test font is far wider
    // than the real one, and this is about the pill hugging its label, not
    // about any particular breakpoint).
    testWidgets('a pill hugs its label instead of filling the line',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: PurposePicker(selected: null, onSelected: _noop),
              ),
            ),
          ),
        ),
      );
      final pill = tester.getSize(
        find
            .ancestor(
              of: find.text('Any purpose'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(pill.width, lessThan(400), reason: 'the pill filled the row');

      // ...and with room to spare, two of them share a line.
      expect(
        tester.getRect(find.text(ListingPurpose.medical.label)).top,
        tester.getRect(find.text('Any purpose')).top,
      );
    });

    testWidgets('reports the purpose that was tapped', (tester) async {
      expect(
        await _tapAt(tester, ListingPurpose.medical.label),
        ListingPurpose.medical,
      );
    });

    // Null is the "no filter" answer, and it has to be reachable — clearing a
    // purpose also clears the landmark it anchored on.
    testWidgets('"Any purpose" reports null', (tester) async {
      expect(await _tapAt(tester, 'Any purpose'), isNull);
    });
  });
}

void _noop(ListingPurpose? _) {}
