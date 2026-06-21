import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';
import 'package:musafir/services/booking/booking_lifecycle_service.dart';
import 'package:musafir/services/booking/booking_rules.dart';

/// In-memory booking store for testing
class TestBookingStore implements BookingStore {
  final Map<String, Booking> _bookings = {};

  void add(Booking booking) {
    _bookings[booking.id] = booking;
  }

  @override
  Booking? getBookingById(String id) => _bookings[id];

  @override
  Future<void> updateBooking(Booking booking) async {
    _bookings[booking.id] = booking;
  }

  Booking? get(String id) => _bookings[id];
}

/// A store whose persist completes only when [gate] does — lets a test assert
/// that a lifecycle mutator awaits the persist before returning.
class GatedBookingStore implements BookingStore {
  GatedBookingStore(this.gate);

  final Future<void> gate;
  final Map<String, Booking> _bookings = {};

  void add(Booking booking) => _bookings[booking.id] = booking;

  @override
  Booking? getBookingById(String id) => _bookings[id];

  @override
  Future<void> updateBooking(Booking booking) async {
    await gate;
    _bookings[booking.id] = booking;
  }
}

void main() {
  late BookingLifecycleService service;
  late TestBookingStore store;
  late BookingRules rules;

  setUp(() {
    store = TestBookingStore();
    rules = BookingRules();
    service = BookingLifecycleService(store: store, rules: rules);
  });

  Booking createBooking({
    String id = 'booking_1',
    BookingStatus status = BookingStatus.pending,
    DateTime? startAt,
    DateTime? endAt,
    String? userId,
    String? listingId,
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return Booking(
      id: id,
      listingId: listingId ?? 'listing_1',
      tenantName: 'Test User',
      startAt: startAt ?? now.add(const Duration(days: 1)),
      endAt: endAt ?? now.add(const Duration(days: 2)),
      totalPrice: 100.0,
      unitLabel: 'night',
      userId: userId ?? 'user_1',
      status: status,
      createdAt: createdAt ?? now,
    );
  }

  group('BookingLifecycleService.acceptBooking', () {
    test('transitions pending booking to confirmed', () async {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = await service.acceptBooking(booking.id);

      expect(result.status, equals(BookingStatus.confirmed));
      expect(store.get(booking.id)?.status, equals(BookingStatus.confirmed));
    });

    test('stores optional acceptance message', () async {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = await service.acceptBooking(
        booking.id,
        message: 'Welcome! Here is the door code: 1234',
      );

      expect(result.hostMessage, equals('Welcome! Here is the door code: 1234'));
    });

    test('throws when booking not found', () {
      expectLater(
        service.acceptBooking('nonexistent'),
        throwsA(isA<BookingNotFoundException>()),
      );
    });

    test('throws when booking is not pending', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      store.add(booking);

      expectLater(
        service.acceptBooking(booking.id),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });

    // Regression: accept must await the status persist before returning, so the
    // welcome messages (gated by RLS on the booking being confirmed/active) are
    // never sent while the DB still shows 'pending' (PostgrestException 42501).
    test('awaits the store persist before returning', () async {
      final gate = Completer<void>();
      final gatedStore = GatedBookingStore(gate.future);
      gatedStore.add(createBooking(status: BookingStatus.pending));
      final gatedService =
          BookingLifecycleService(store: gatedStore, rules: rules);

      var returned = false;
      final future =
          gatedService.acceptBooking('booking_1').then((_) => returned = true);

      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse,
          reason: 'acceptBooking returned before the persist completed');

      gate.complete();
      await future;
      expect(returned, isTrue);
    });
  });

  group('BookingLifecycleService.rejectBooking', () {
    test('transitions pending booking to rejected', () {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = service.rejectBooking(booking.id);

      expect(result.status, equals(BookingStatus.rejected));
      expect(store.get(booking.id)?.status, equals(BookingStatus.rejected));
    });

    test('stores optional rejection reason', () {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = service.rejectBooking(
        booking.id,
        reason: 'Dates not available',
      );

      expect(result.rejectionReason, equals('Dates not available'));
    });

    test('throws when booking is not pending', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      store.add(booking);

      expect(
        () => service.rejectBooking(booking.id),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });
  });

  group('BookingLifecycleService.checkInGuest', () {
    test('transitions confirmed booking to active on start date', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.subtract(const Duration(hours: 1)),
      );
      store.add(booking);

      final result = service.checkInGuest(booking.id, now: now);

      expect(result.status, equals(BookingStatus.active));
      expect(store.get(booking.id)?.status, equals(BookingStatus.active));
    });

    test('records check-in timestamp', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.subtract(const Duration(hours: 1)),
      );
      store.add(booking);

      final result = service.checkInGuest(booking.id, now: now);

      expect(result.actualCheckIn, isNotNull);
    });

    test('throws when before start date', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        startAt: now.add(const Duration(days: 1)),
      );
      store.add(booking);

      expect(
        () => service.checkInGuest(booking.id, now: now),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });

    test('throws when booking not confirmed', () {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      expect(
        () => service.checkInGuest(booking.id),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });
  });

  group('BookingLifecycleService.completeService', () {
    test('transitions active booking to completed', () {
      final booking = createBooking(status: BookingStatus.active);
      store.add(booking);

      final result = service.completeService(booking.id);

      expect(result.status, equals(BookingStatus.completed));
      expect(store.get(booking.id)?.status, equals(BookingStatus.completed));
    });

    test('records completion timestamp', () {
      final booking = createBooking(status: BookingStatus.active);
      store.add(booking);

      final result = service.completeService(booking.id);

      expect(result.completedAt, isNotNull);
    });

    test('throws when booking not active', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      store.add(booking);

      expect(
        () => service.completeService(booking.id),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });
  });

  group('BookingLifecycleService.cancelBooking (guest)', () {
    test('cancels pending booking', () {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = service.cancelBooking(
        booking.id,
        cancelledBy: 'user_1',
        isHost: false,
      );

      expect(result.status, equals(BookingStatus.cancelled));
      expect(result.cancelledBy, equals('user_1'));
    });

    test('cancels confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      store.add(booking);

      final result = service.cancelBooking(
        booking.id,
        cancelledBy: 'user_1',
        isHost: false,
      );

      expect(result.status, equals(BookingStatus.cancelled));
    });

    test('throws when booking is active (checked in)', () {
      final booking = createBooking(status: BookingStatus.active);
      store.add(booking);

      expect(
        () => service.cancelBooking(
          booking.id,
          cancelledBy: 'user_1',
          isHost: false,
        ),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });
  });

  group('BookingLifecycleService.cancelBooking (host)', () {
    test('cancels confirmed booking', () {
      final booking = createBooking(status: BookingStatus.confirmed);
      store.add(booking);

      final result = service.cancelBooking(
        booking.id,
        cancelledBy: 'host_1',
        isHost: true,
      );

      expect(result.status, equals(BookingStatus.cancelled));
      expect(result.cancelledBy, equals('host_1'));
    });

    test('throws for pending booking (should reject instead)', () {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      expect(
        () => service.cancelBooking(
          booking.id,
          cancelledBy: 'host_1',
          isHost: true,
        ),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });

    test('throws when booking is active', () {
      final booking = createBooking(status: BookingStatus.active);
      store.add(booking);

      expect(
        () => service.cancelBooking(
          booking.id,
          cancelledBy: 'host_1',
          isHost: true,
        ),
        throwsA(isA<InvalidBookingStateException>()),
      );
    });
  });

  group('BookingLifecycleService.expireStaleBookings', () {
    test('expires pending bookings older than 24 hours', () {
      final now = DateTime.now();
      final oldBooking = createBooking(
        id: 'old_booking',
        status: BookingStatus.pending,
        createdAt: now.subtract(const Duration(hours: 25)),
      );
      final newBooking = createBooking(
        id: 'new_booking',
        status: BookingStatus.pending,
        createdAt: now.subtract(const Duration(hours: 23)),
      );
      store.add(oldBooking);
      store.add(newBooking);

      final expired = service.expireStaleBookings([oldBooking, newBooking], now: now);

      expect(expired.length, equals(1));
      expect(expired.first.id, equals('old_booking'));
      expect(store.get('old_booking')?.status, equals(BookingStatus.rejected));
      expect(store.get('new_booking')?.status, equals(BookingStatus.pending));
    });

    test('does not expire confirmed bookings', () {
      final now = DateTime.now();
      final booking = createBooking(
        status: BookingStatus.confirmed,
        createdAt: now.subtract(const Duration(hours: 48)),
      );
      store.add(booking);

      final expired = service.expireStaleBookings([booking], now: now);

      expect(expired, isEmpty);
      expect(store.get(booking.id)?.status, equals(BookingStatus.confirmed));
    });
  });
}
