import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/services/listing/party_limits_summary.dart';

void main() {
  group('partyLimitsSentence', () {
    // The common case by far: almost no listing sets any of these, and the
    // caller omits the whole row rather than rendering an empty one.
    test('says nothing when the host stated nothing', () {
      expect(
        partyLimitsSentence(const PartyLimits(), petsAllowed: false),
        isNull,
      );
      expect(
        partyLimitsSentence(const PartyLimits(), petsAllowed: true),
        isNull,
      );
    });

    test('names each stated cap, in the order the panel asks them', () {
      expect(
        partyLimitsSentence(
          const PartyLimits(adults: 2, children: 1, infants: 1, pets: 1),
          petsAllowed: true,
        ),
        'At most 2 adults · 1 child · 1 infant · 1 pet',
      );
    });

    test('omits the categories the host left on "Any"', () {
      expect(
        partyLimitsSentence(const PartyLimits(adults: 2), petsAllowed: false),
        'At most 2 adults',
      );
    });

    // "at most 0 children" is technically true and unsayable. Zero is a rule
    // in its own right and gets its own wording.
    test('zero reads as a prohibition, not as a ceiling of nought', () {
      expect(
        partyLimitsSentence(const PartyLimits(children: 0), petsAllowed: false),
        'At most no children',
      );
    });

    test('singular and plural both come out right', () {
      expect(
        partyLimitsSentence(const PartyLimits(adults: 1), petsAllowed: false),
        'At most 1 adult',
      );
      expect(
        partyLimitsSentence(const PartyLimits(infants: 2), petsAllowed: false),
        'At most 2 infants',
      );
    });

    // pets_allowed is the switch and max_pets only narrows it. A host who set
    // a number and later switched pets off must not still be advertising it —
    // search stops reading that number too, so the page would be describing a
    // rule that no longer applies.
    test('a pet count under a closed toggle is not advertised', () {
      expect(
        partyLimitsSentence(const PartyLimits(pets: 2), petsAllowed: false),
        isNull,
      );
      expect(
        partyLimitsSentence(
          const PartyLimits(adults: 2, pets: 2),
          petsAllowed: false,
        ),
        'At most 2 adults',
      );
    });

    // Permissive toggle, no number = "allowed, no stated limit". There is
    // nothing to say, and "at most null pets" is the failure mode.
    test('pets allowed with no number says nothing about pets', () {
      expect(
        partyLimitsSentence(const PartyLimits(), petsAllowed: true),
        isNull,
      );
    });
  });
}
