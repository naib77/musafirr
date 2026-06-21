import '../../models/booking.dart';
import '../../models/conversation.dart';
import '../messaging/booking_conversation_service.dart';
import 'booking_lifecycle_service.dart';

/// Coordinates booking lifecycle events with messaging.
///
/// This service wraps [BookingLifecycleService] and automatically
/// creates/updates conversations when booking state changes.
///
/// ## Usage
///
/// ```dart
/// final coordinator = BookingMessagingCoordinator(
///   lifecycleService: bookingLifecycleService,
///   conversationService: bookingConversationService,
/// );
///
/// // Accept booking and create conversation
/// final result = await coordinator.acceptBookingWithConversation(
///   bookingId: 'abc123',
///   hostId: 'host-user-id',
///   message: 'Welcome! Looking forward to hosting you.',
/// );
///
/// if (result.conversation != null) {
///   // Navigate to chat
/// }
/// ```
class BookingMessagingCoordinator {
  BookingMessagingCoordinator({
    required BookingLifecycleService lifecycleService,
    required BookingConversationService conversationService,
  })  : _lifecycleService = lifecycleService,
        _conversationService = conversationService;

  final BookingLifecycleService _lifecycleService;
  final BookingConversationService _conversationService;

  /// Accept a booking and create a conversation with the guest.
  ///
  /// Returns both the updated booking and the created conversation.
  Future<BookingWithConversation> acceptBookingWithConversation({
    required String bookingId,
    required String hostId,
    String? message,
  }) async {
    // First, accept the booking — awaited so the 'confirmed' status is
    // committed before we send the welcome messages (RLS gates message inserts
    // on the booking being confirmed/active).
    final booking = await _lifecycleService.acceptBooking(
      bookingId,
      message: message,
    );

    // Then create the conversation
    final convResult = await _conversationService.onBookingConfirmed(
      booking: booking,
      hostId: hostId,
      hostMessage: message,
    );

    return BookingWithConversation(
      booking: booking,
      conversation: convResult.data,
      error: convResult.error,
    );
  }

  /// Check in a guest and notify via the conversation.
  Future<Booking> checkInGuestWithNotification({
    required String bookingId,
    required String hostId,
    DateTime? now,
  }) async {
    final booking = _lifecycleService.checkInGuest(bookingId, now: now);

    // Find the conversation for this booking
    final conversation = await _conversationService.findForBooking(
      bookingId: bookingId,
      userId: hostId,
    );

    if (conversation != null) {
      await _conversationService.onGuestCheckedIn(
        booking: booking,
        conversationId: conversation.id,
        hostId: hostId,
      );
    }

    return booking;
  }

  /// Complete a booking and send thank-you message.
  Future<Booking> completeServiceWithNotification({
    required String bookingId,
    required String hostId,
    bool archiveConversation = false,
    DateTime? now,
  }) async {
    // Send the closing message BEFORE the booking goes terminal: the messages
    // RLS only permits inserts while the booking is confirmed/active, so a
    // message sent after the transition to 'completed' is rejected (42501).
    final current = _lifecycleService.store.getBookingById(bookingId);
    if (current != null) {
      final conversation = await _conversationService.findForBooking(
        bookingId: bookingId,
        userId: hostId,
      );
      if (conversation != null) {
        await _conversationService.onBookingCompleted(
          booking: current,
          conversationId: conversation.id,
          hostId: hostId,
          archiveConversation: archiveConversation,
        );
      }
    }

    // Then perform the transition (the conversation auto-archives via the
    // booking-end trigger once the status lands).
    return _lifecycleService.completeService(bookingId, now: now);
  }

  /// Cancel a booking and notify the other party.
  Future<Booking> cancelBookingWithNotification({
    required String bookingId,
    required String cancelledBy,
    required bool isHost,
    required String hostId,
    DateTime? now,
  }) async {
    // Send the cancellation message BEFORE the booking goes terminal (the
    // messages RLS rejects inserts once the booking is no longer confirmed/
    // active — see completeServiceWithNotification).
    final current = _lifecycleService.store.getBookingById(bookingId);
    if (current != null) {
      final conversation = await _conversationService.findForBooking(
        bookingId: bookingId,
        userId: isHost ? hostId : (current.userId ?? ''),
      );
      if (conversation != null) {
        await _conversationService.onBookingCancelled(
          booking: current,
          conversationId: conversation.id,
          cancelledByUserId: cancelledBy,
          cancelledByHost: isHost,
        );
      }
    }

    return _lifecycleService.cancelBooking(
      bookingId,
      cancelledBy: cancelledBy,
      isHost: isHost,
      now: now,
    );
  }

  /// Start a conversation for an existing booking.
  ///
  /// Use this when a conversation wasn't created during booking confirmation
  /// (e.g., for pre-existing bookings or when messaging was added later).
  Future<BookingConversationResult<Conversation>> startConversationForBooking({
    required Booking booking,
    required String hostId,
  }) {
    return _conversationService.getOrCreateForBooking(
      booking: booking,
      hostId: hostId,
    );
  }

  /// Find an existing conversation for a booking.
  Future<Conversation?> findConversationForBooking({
    required String bookingId,
    required String userId,
  }) {
    return _conversationService.findForBooking(
      bookingId: bookingId,
      userId: userId,
    );
  }
}

/// Result containing both booking and conversation.
class BookingWithConversation {
  const BookingWithConversation({
    required this.booking,
    this.conversation,
    this.error,
  });

  final Booking booking;
  final Conversation? conversation;
  final String? error;

  bool get hasConversation => conversation != null;
  bool get hasError => error != null;
}
