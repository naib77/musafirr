import 'package:flutter/foundation.dart';

import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/conversation.dart';
import '../../models/conversation_participant.dart';
import '../../models/message.dart';
import '../../models/message_template.dart';
import '../../repositories/conversation_repository.dart';
import 'booking_system_messages.dart';
import 'message_template_provider.dart';
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
///
/// ## Lifecycle Rules
///
/// 1. **Booking Confirmed**: Creates conversation, sends welcome message
/// 2. **Guest Checked In**: Sends check-in notification
/// 3. **Booking Completed**: Sends completion message
/// 4. **Booking Cancelled**: Sends cancellation notice
///
/// Conversations are never locked: guests and hosts can keep messaging after
/// the reservation flow completes.
///
class BookingConversationService {
  BookingConversationService({
    required ConversationRepository conversationRepository,
    required MessagingService messagingService,
    MessageTemplateProvider? templateProvider,
  })  : _conversationRepository = conversationRepository,
        _messagingService = messagingService,
        _templates = templateProvider ?? const DefaultMessageTemplateProvider();

  final ConversationRepository _conversationRepository;
  final MessagingService _messagingService;
  final MessageTemplateProvider _templates;

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
      listingTitle: booking.listingTitle,
      bookingStart: booking.effectiveCheckIn,
      bookingEnd: booking.effectiveCheckOut,
      listingType: booking.listingType ?? booking.listing?.type.name,
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

  /// Handle booking confirmation - creates conversation and sends the host's
  /// scheduled welcome (Airbnb-style).
  ///
  /// The welcome is the host's booking-confirmed template rendered with the
  /// booking's details; [hostMessage] — the note typed in the accept dialog —
  /// is the host's own words and goes out as a separate message. With the
  /// template disabled and no note, nothing is auto-sent.
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

    final language = await _templates.languageFor(hostId);
    final template = await _templates.templateFor(
      hostId,
      MessageTemplateTrigger.bookingConfirmed,
    );

    if (template.enabled) {
      // Airbnb-style, two separate messages: the reservation card, then the
      // welcome text. The card renderer ignores message content, so welcome
      // text embedded in a card message is invisible to the guest.
      await _sendMessageFromUser(
        conversationId: conversation.id,
        senderId: hostId,
        text: BookingSystemMessages.reservationConfirmed(
          booking.listingTitle ?? 'your stay',
          language,
        ),
        metadata: BookingCardMetadata(
          bookingId: booking.id,
          listingName: booking.listingTitle ?? 'Booking',
          listingImageUrl: booking.listingImageUrl,
          checkIn: booking.effectiveCheckIn,
          checkOut: booking.effectiveCheckOut,
          totalPrice: booking.totalPrice,
          currency: booking.currency.code,
          status: BookingStatus.confirmed.name,
          durationLabel: booking.durationLabel,
        ),
      );

      final rendered = await _render(
        MessageTemplate.resolveContent(template, language),
        booking,
        conversation,
        language: language,
      );
      await _sendMessageFromUser(
        conversationId: conversation.id,
        senderId: hostId,
        text: rendered,
      );
    }

    final note = hostMessage?.trim();
    if (note != null && note.isNotEmpty) {
      await _sendMessageFromUser(
        conversationId: conversation.id,
        senderId: hostId,
        text: note,
      );
    }

    debugPrint(
        '[BookingConversationService] Created conversation for booking ${booking.id}');
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
    final language = await _templates.languageFor(hostId);
    final message = BookingSystemMessages.checkedIn(language);

    await _sendMessageFromUser(
      conversationId: conversationId,
      senderId: hostId,
      text: message,
    );

    debugPrint(
        '[BookingConversationService] Sent check-in message for booking ${booking.id}');
  }

  /// Handle booking completion.
  ///
  /// Sends the host's checkout template (when enabled). The conversation
  /// stays writable — guests and hosts can keep messaging after the stay.
  Future<void> onBookingCompleted({
    required Booking booking,
    required Conversation conversation,
    required String hostId,
  }) async {
    final language = await _templates.languageFor(hostId);
    final template = await _templates.templateFor(
      hostId,
      MessageTemplateTrigger.checkOut,
    );
    if (!template.enabled) return;

    final rendered = await _render(
      MessageTemplate.resolveContent(template, language),
      booking,
      conversation,
      language: language,
    );
    await _sendMessageFromUser(
      conversationId: conversation.id,
      senderId: hostId,
      text: rendered,
    );

    debugPrint(
        '[BookingConversationService] Sent completion message for booking ${booking.id}');
  }

  /// Handle booking cancellation.
  ///
  /// Called when either host or guest cancels a booking.
  Future<void> onBookingCancelled({
    required Booking booking,
    required String conversationId,
    required String cancelledByUserId,
    required bool cancelledByHost,
    required String hostId,
  }) async {
    // The message language always follows the host's preference, even when the
    // guest is the one cancelling.
    final language = await _templates.languageFor(hostId);
    final message = BookingSystemMessages.cancelled(
      cancelledByHost: cancelledByHost,
      language: language,
    );

    await _sendMessageFromUser(
      conversationId: conversationId,
      senderId: cancelledByUserId,
      text: message,
    );

    debugPrint(
        '[BookingConversationService] Sent cancellation message for booking ${booking.id}');
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

  /// Renders a template's variables with the booking's details. The host
  /// name is resolved from the guest's perspective of the conversation,
  /// falling back to a neutral label when unavailable.
  Future<String> _render(
    String templateContent,
    Booking booking,
    Conversation conversation, {
    MessageLanguage language = MessageLanguage.en,
  }) async {
    var hostName = 'Your host';
    final guestId = booking.userId;
    if (guestId != null) {
      final result = await _conversationRepository.loadOtherParticipant(
        conversation: conversation,
        currentUserId: guestId,
      );
      final name = result.data?.name;
      if (name != null && name.isNotEmpty) hostName = name;
    }

    return TemplateContext.fromBooking(booking, hostName: hostName)
        .render(templateContent, language: language);
  }

  Future<void> _sendMessageFromUser({
    required String conversationId,
    required String senderId,
    required String text,
    MessageMetadata? metadata,
  }) async {
    final request = SendMessageRequest(
      conversationId: conversationId,
      contentType: metadata != null
          ? MessageContentType.bookingCard
          : MessageContentType.text,
      content: text,
      metadata: metadata,
    );

    final result = await _messagingService.sendMessage(request, senderId);
    if (!result.isSuccess) {
      debugPrint(
          '[BookingConversationService] Failed to send message: ${result.error}');
    }
  }
}
