import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking_conflict_exception.dart';

/// The server raises SQLSTATE 23P01 for four different situations and the guest
/// needs two different sentences out of them. Before migration 111 that choice
/// was made by matching English prose written in a SQL file — so rewording a
/// `raise exception` silently showed guests the wrong message, with nothing to
/// catch it. These tests are what makes that no longer true.
void main() {
  group('bookingConflictTypeFrom', () {
    test('hint decides, and outranks the message', () {
      expect(
        bookingConflictTypeFrom(hint: 'tenant_overlap', message: null),
        ConflictType.user,
      );
      expect(
        bookingConflictTypeFrom(hint: 'listing_overlap', message: null),
        ConflictType.listing,
      );

      // A hint present alongside contradictory prose must win: the hint is the
      // contract, the prose is incidental.
      expect(
        bookingConflictTypeFrom(
          hint: 'listing_overlap',
          message: 'You already have a booking during this time',
        ),
        ConflictType.listing,
      );
      expect(
        bookingConflictTypeFrom(
          hint: 'tenant_overlap',
          message: 'This time slot is already booked',
        ),
        ConflictType.user,
      );
    });

    test('falls back to the violated constraint name when there is no hint',
        () {
      // Exclusion constraints are raised by Postgres, not by our `raise`, so
      // they carry no hint — but the constraint name is just as stable.
      expect(
        bookingConflictTypeFrom(
          message: 'conflicting key value violates exclusion constraint '
              '"bookings_no_tenant_overlap"',
        ),
        ConflictType.user,
      );
      expect(
        bookingConflictTypeFrom(
          message: 'conflicting key value violates exclusion constraint '
              '"bookings_no_overlap"',
        ),
        ConflictType.listing,
      );
    });

    test('the tenant constraint is not shadowed by the listing one', () {
      // 'bookings_no_tenant_overlap' does not contain 'bookings_no_overlap' as
      // a substring today. This pins that: if either name is ever changed to
      // one that does, this fails instead of silently mislabelling every
      // same-user race as a listing conflict.
      const tenant = 'bookings_no_tenant_overlap';
      expect(tenant.contains('bookings_no_overlap'), isFalse);
      expect(
        bookingConflictTypeFrom(message: 'violates constraint "$tenant"'),
        ConflictType.user,
      );
    });

    test('legacy prose still works, for a client on a pre-111 server', () {
      // App and database deploy separately. A client that ships before the
      // migration lands sees the old un-hinted sentences and must keep
      // behaving, not regress to the default branch.
      expect(
        bookingConflictTypeFrom(
          message: 'You already have a booking during this time',
        ),
        ConflictType.user,
      );
      expect(
        bookingConflictTypeFrom(message: 'This time slot is already booked'),
        ConflictType.listing,
      );
    });

    test('unknown input defaults to a listing conflict', () {
      // The commoner case, and the safer thing to tell a guest: "someone just
      // took this slot" misapplied to a self-overlap is a smaller error than
      // accusing a guest of double-booking themselves when they did not.
      expect(bookingConflictTypeFrom(), ConflictType.listing);
      expect(
          bookingConflictTypeFrom(hint: '', message: ''), ConflictType.listing);
      expect(
        bookingConflictTypeFrom(hint: 'something_new', message: 'who knows'),
        ConflictType.listing,
      );
    });

    test('matching is case-insensitive', () {
      expect(
        bookingConflictTypeFrom(
            message: 'You Already Have A Booking During This Time'),
        ConflictType.user,
      );
    });
  });
}
