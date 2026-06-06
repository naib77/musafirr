import 'package:flutter/foundation.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/conversation.dart';
import '../../models/conversation_participant.dart';
import '../../models/message.dart';
import '../../repositories/conversation_repository.dart';
import 'messaging_service.dart';

/// Result of a booking conversation operation
class BookingConversationResult<T> {
  const BookingConversationResult.success(this.data)
      : error = null,
        isSuccess = true;

  const BookingConversationResult.failure(this.error)
      : data = null,
        isSuccess = false;

  final T? data;
  final String? error;
  final bool isSuccess;
}

/// Service that manages the lifecycle of conversations tied to bookings.
///
/// This service provides a domain-oriented interface for booking-related
/// messaging, handling:
/// - Automatic conversation creation when bookings are confirmed
/// - System messages for booking events
/// - Participant role tracking (host vs guest)
/// - Conversation archival when bookings complete/cancel
///
/// ## Lifecycle Rules
///
/// 1. **Booking Confirmed**: Creates conversation, sends welcome message
/// 2. **Guest Checked In**: Sends check-in notification
/// 3. **Booking Completed**: Sends completion message, optionally archives
/// 4. **Booking Cancelled**: Sends cancellation notice, archives conversation
///
class BookingConversationService {
  BookingConversationService({
    required ConversationRepository conversationRepository,
    required MessagingService messagingService,
  })  : _conversationRepository = conversationRepository,
        _messagingService = messagingService;

  final ConversationRepository _conversationRepository;
  final MessagingService _messagingService;

  /// Get or create a conversation for a booking.
  ///
  /// Returns the conversation between host and guest for this booking.
  /// Creates a new conversation if one doesn't exist.
  Future<BookingConversationResult<Conversation>> getOrCreateForBooking({
    required Booking booking,
    required String hostId,
  }) async {
    final guestId = booking.userId;
    if (guestId == null) {
      return const BookingConversationResult.failure(
        'Booking has no guest user ID',
      );
    }

    final result = await _conversationRepository.create(
      participantOneId: guestId,
      participantTwoId: hostId,
      bookingId: booking.id,
      listingId: booking.listingId,
    );

    if (result.isSuccess && result.data != null) {
      return BookingConversationResult.success(result.data!);
    }

    return BookingConversationResult.failure(
      result.error?.message ?? 'Failed to create conversation',
    );
  }

  /// Find an existing conversation for a booking.
  ///
  /// Returns null if no conversation exists for this booking.
  Future<Conversation?> findForBooking({
    required String bookingId,
    required String userId,
  }) async {
    final result = await _conversationRepository.findForBooking(
      bookingId: bookingId,
      userId: userId,
    );

    if (result.isSuccess) {
      return result.data;
    }

    return null;
  }

  /// Handle booking confirmation - creates conversation and sends welcome.
  ///
  /// Called when a host accepts a booking request.
  Future<BookingConversationResult<Conversation>> onBookingConfirmed({
    required Booking booking,
    required String hostId,
    String? hostMessage,
  }) async {
    // Create the conversation
    final convResult = await getOrCreateForBooking(
      booking: booking,
      hostId: hostId,
    );

    if (!convResult.isSuccess || convResult.data == null) {
      return convResult;
    }

    final conversation = convResult.data!;

    // Send confirmation message from the host
    final confirmationMessage = _buildConfirmationMessage(booking, hostMessage);
    await _sendMessageFromUser(
      conversationId: conversation.id,
      senderId: hostId,
      text: confirmationMessage,
      metadata: BookingCardMetadata(
        bookingId: booking.id,
        listingName: booking.listingTitle ?? 'Booking',
        listingImageUrl: booking.listingImageUrl,
        checkIn: booking.effectiveCheckIn,
        checkOut: booking.effectiveCheckOut,
        totalPrice: booking.totalPrice,
        currency: booking.currency.code,
        status: BookingStatus.confirmed.name,
      ),
    );

    debugPrint('[BookingConversationService] Created conversation for booking ${booking.id}');
    return BookingConversationResult.success(conversation);
  }

  /// Handle guest check-in.
  ///
  /// Called when a host marks a guest as arrived.
  Future<void> onGuestCheckedIn({
    required Booking booking,
    required String conversationId,
    required String hostId,
  }) async {
    final message = 'Guest has checked in. Enjoy your stay! 🏠';

    await _sendMessageFromUser(
      conversationId: conversationId,
      senderId: hostId,
      text: message,
    );

    debugPrint('[BookingConversationService] Sent check-in message for booking ${booking.id}');
  }

  /// Handle booking completion.
  ///
  /// Called when a host marks a service as complete.
  Future<void> onBookingCompleted({
    required Booking booking,
    required String conversationId,
    required String hostId,
    bool archiveConversation = false,
  }) async {
    final message = 'Your stay has been completed. '
        'Thank you for choosing us! We hope to see you again. ⭐';

    await _sendMessageFromUser(
      conversationId: conversationId,
      senderId: hostId,
      text: message,
    );

    if (archiveConversation) {
      await _conversationRepository.archive(conversationId);
    }

    debugPrint('[BookingConversationService] Sent completion message for booking ${booking.id}');
  }

  /// Handle booking cancellation.
  ///
  /// Called when either host or guest cancels a booking.
  Future<void> onBookingCancelled({
    required Booking booking,
    required String conversationId,
    required String cancelledByUserId,
    required bool cancelledByHost,
  }) async {
    final cancelledBy = cancelledByHost ? 'I (host)' : 'I';
    final message = '$cancelledBy have cancelled this booking. '
        'If you have any questions, feel free to message.';

    await _sendMessageFromUser(
      conversationId: conversationId,
      senderId: cancelledByUserId,
      text: message,
    );

    // Archive the conversation since the booking is cancelled
    await _conversationRepository.archive(conversationId);

    debugPrint('[BookingConversationService] Sent cancellation message for booking ${booking.id}');
  }

  /// Get participant roles for a booking conversation.
  ///
  /// Returns a map of userId -> ParticipantRole.
  Map<String, ParticipantRole> getParticipantRoles({
    required Booking booking,
    required String hostId,
  }) {
    final roles = <String, ParticipantRole>{};

    if (booking.userId != null) {
      roles[booking.userId!] = ParticipantRole.guest;
    }

    roles[hostId] = ParticipantRole.host;

    return roles;
  }

  /// Check if a user is the host in a booking conversation.
  bool isHost({
    required String userId,
    required String hostId,
  }) {
    return userId == hostId;
  }

  /// Check if a user is the guest in a booking conversation.
  bool isGuest({
    required String userId,
    required Booking booking,
  }) {
    return userId == booking.userId;
  }

  // ============================================
  // Private Helpers
  // ============================================

  String _buildConfirmationMessage(Booking booking, String? hostMessage) {
    final buffer = StringBuffer();
    buffer.writeln('🎉 Booking Confirmed!');
    buffer.writeln();
    buffer.writeln('Your reservation has been accepted.');

    if (hostMessage != null && hostMessage.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Message from host:');
      buffer.writeln('"$hostMessage"');
    }

    return buffer.toString().trim();
  }

  Future<void> _sendMessageFromUser({
    required String conversationId,
    required String senderId,
    required String text,
    MessageMetadata? metadata,
  }) async {
    final request = SendMessageRequest(
      conversationId: conversationId,
      contentType: metadata != null ? MessageContentType.bookingCard : MessageContentType.text,
      content: text,
      metadata: metadata,
    );

    final result = await _messagingService.sendMessage(request, senderId);
    if (!result.isSuccess) {
      debugPrint('[BookingConversationService] Failed to send message: ${result.error}');
    }
  }
}
