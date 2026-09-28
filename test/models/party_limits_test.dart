import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/listing.dart';

void main() {
  group('PartyLimits', () {
    test('is empty by default, which is what every pre-118 listing has', () {
      const limits = PartyLimits();
      expect(limits.hasAny, isFalse);
      expect(limits.adults, isNull);
      expect(limits.children, isNull);
      expect(limits.infants, isNull);
      expect(limits.pets, isNull);
    });

    test('one field is enough to count as set', () {
      expect(const PartyLimits(pets: 0).hasAny, isTrue);
      // Zero is a stated limit, not an absent one — "no children" is a rule a
      // host can mean, and hasAny must not read it as silence.
      expect(const PartyLimits(children: 0).hasAny, isTrue);
    });

    group('copyWith', () {
      test('carries the fields it is not given', () {
        const limits = PartyLimits(adults: 2, children: 1, infants: 1, pets: 1);
        final next = limits.copyWith(adults: 3);
        expect(next.adults, 3);
        expect(next.children, 1);
        expect(next.infants, 1);
        expect(next.pets, 1);
      });

      // Null means "no limit" here, so copyWith cannot read it as "unchanged"
      // the way SearchFilters.copyWith does — a host who could set a cap but
      // never take it off is the bug the clear flags exist to prevent.
      test('a clear flag is the only way back to null', () {
        const limits = PartyLimits(adults: 2, pets: 2);
        expect(limits.copyWith(adults: null).adults, 2, reason: 'unchanged');
        expect(limits.copyWith(clearAdults: true).adults, isNull);
        expect(limits.copyWith(clearPets: true).pets, isNull);
        // And clearing one leaves the others alone.
        expect(limits.copyWith(clearAdults: true).pets, 2);
      });
    });

    group('clampedTo', () {
      // A sub-cap above the total can never bind: max_guests rejects the party
      // before any per-category column is consulted. Hosts reach this state by
      // lowering the total after setting the caps, which is an ordinary edit.
      test('brings counted categories down to the total', () {
        const limits = PartyLimits(adults: 8, children: 6);
        final clamped = limits.clampedTo(4);
        expect(clamped.adults, 4);
        expect(clamped.children, 4);
      });

      test('leaves caps that already fit exactly as they are', () {
        const limits = PartyLimits(adults: 2, children: 1);
        final clamped = limits.clampedTo(4);
        expect(clamped.adults, 2);
        expect(clamped.children, 1);
      });

      // Clamping, not clearing: "at most 4 adults" in a 2-guest place still
      // means the host wants an adult ceiling. Dropping it to "Any" would
      // throw away a stated intent.
      test('never turns a stated cap back into "Any"', () {
        expect(const PartyLimits(adults: 9).clampedTo(1).adults, 1);
      });

      test('an unset cap stays unset', () {
        final clamped = const PartyLimits(children: 5).clampedTo(2);
        expect(clamped.adults, isNull);
        expect(clamped.children, 2);
      });

      // Neither counts towards max_guests, so neither can exceed it and the
      // total has no business trimming them. A host with a 1-guest studio may
      // perfectly well take an infant and a dog.
      test('infants and pets are untouched by the guest total', () {
        const limits = PartyLimits(infants: 3, pets: 2);
        final clamped = limits.clampedTo(1);
        expect(clamped.infants, 3);
        expect(clamped.pets, 2);
      });
    });
  });
}
