import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';
import 'package:musafir/models/conversation.dart';
import 'package:musafir/models/message.dart';
import 'package:musafir/models/message_template.dart';
import 'package:musafir/models/user.dart';
import 'package:musafir/models/user_role.dart';
import 'package:musafir/repositories/conversation_repository.dart';
import 'package:musafir/services/booking/booking_lifecycle_service.dart';
import 'package:musafir/services/booking/booking_messaging_coordinator.dart';
import 'package:musafir/services/booking/booking_rules.dart';
import 'package:musafir/services/messaging/booking_conversation_service.dart';
import 'package:musafir/services/messaging/message_template_provider.dart';
import 'package:musafir/services/messaging/messaging_service.dart';

/// In-memory booking store (same pattern as booking_lifecycle_service_test).
class TestBookingStore implements BookingStore {
  final Map<String, Booking> _bookings = {};

  void add(Booking booking) => _bookings[booking.id] = booking;

  @override
  Booking? getBookingById(String id) => _bookings[id];

  @override
  Future<void> updateBooking(Booking booking) async {
    _bookings[booking.id] = booking;
  }
}

/// Conversation repository fake mirroring the production contract:
/// ONE conversation per user pair (Airbnb-style single thread), get-or-create
/// semantics, with the booking context updated to the latest booking.
class RecordingConversationRepository implements ConversationRepository {
  final List<String> archivedIds = [];
  final Map<String, Conversation> byPair = {};

  String _pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  List<Conversation> get all => byPair.values.toList();

  void seed(Conversation conversation) {
    byPair[_pairKey(
      conversation.participantOneId,
      conversation.participantTwoId,
    )] = conversation;
  }

  @override
  Future<ConversationResult<Conversation>> create({
    required String participantOneId,
    required String participantTwoId,
    String? bookingId,
    String? listingId,
    String? listingTitle,
    DateTime? bookingStart,
    DateTime? bookingEnd,
    String? listingType,
  }) async {
    final key = _pairKey(participantOneId, participantTwoId);
    final existing = byPair[key];
    if (existing != null) {
      // Reuse the pair's thread; refresh booking context to the latest.
      final updated = existing.copyWith(
        bookingId: bookingId,
        listingId: listingId,
        listingTitle: listingTitle,
      );
      byPair[key] = updated;
      return ConversationResult.success(updated);
    }

    final conversation = Conversation(
      id: 'conv_${byPair.length + 1}',
      participantOneId: participantOneId,
      participantTwoId: participantTwoId,
      bookingId: bookingId,
      listingId: listingId,
      listingTitle: listingTitle,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    byPair[key] = conversation;
    return ConversationResult.success(conversation);
  }

  @override
  Future<ConversationResult<Conversation?>> findForBooking({
    required String bookingId,
    required String userId,
  }) async {
    final match = byPair.values
        .where((c) => c.bookingId == bookingId)
        .cast<Conversation?>()
        .firstWhere((_) => true, orElse: () => null);
    return ConversationResult.success(match);
  }

  @override
  Future<ConversationResult<void>> archive(String conversationId) async {
    archivedIds.add(conversationId);
    return const ConversationResult.success(null);
  }

  @override
  Future<ConversationResult<User>> loadOtherParticipant({
    required Conversation conversation,
    required String currentUserId,
  }) async {
    return const ConversationResult.success(
      User(id: 'host_1', name: 'Madhara Homes', role: UserRole.owner),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Template provider fake: returns stored overrides, else the default.
class FakeTemplateProvider implements MessageTemplateProvider {
  final Map<MessageTemplateTrigger, MessageTemplate> overrides = {};

  @override
  Future<MessageTemplate> templateFor(
    String hostId,
    MessageTemplateTrigger trigger,
  ) async {
    return overrides[trigger] ?? MessageTemplate.defaultFor(hostId, trigger);
  }
}

/// Messaging service fake that records every sent message.
class RecordingMessagingService implements MessagingService {
  final List<
      ({
        String conversationId,
        String senderId,
        String content,
        bool hasCard,
      })> sent = [];

  @override
  Future<MessagingResult<Message>> sendMessage(
    SendMessageRequest request,
    String senderId,
  ) async {
    sent.add((
      conversationId: request.conversationId,
      senderId: senderId,
      content: request.content,
      hasCard: request.metadata is BookingCardMetadata,
    ));
    return MessagingResult.success(Message(
      id: 'msg_${sent.length}',
      conversationId: request.conversationId,
      senderId: senderId,
      contentType: request.contentType,
      content: request.content,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void main() {
  late TestBookingStore store;
  late RecordingConversationRepository conversations;
  late RecordingMessagingService messages;
  late FakeTemplateProvider templates;
  late BookingMessagingCoordinator coordinator;

  const hostId = 'host_1';
  const guestId = 'guest_1';

  setUp(() {
    store = TestBookingStore();
    conversations = RecordingConversationRepository();
    messages = RecordingMessagingService();
    templates = FakeTemplateProvider();
    coordinator = BookingMessagingCoordinator(
      lifecycleService: BookingLifecycleService(
        store: store,
        rules: BookingRules(),
      ),
      conversationService: BookingConversationService(
        conversationRepository: conversations,
        messagingService: messages,
        templateProvider: templates,
      ),
    );
  });

  Booking createBooking({
    String id = 'booking_1',
    BookingStatus status = BookingStatus.pending,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    final now = DateTime.now();
    return Booking(
      id: id,
      listingId: 'listing_1',
      listingTitle: 'Listing One',
      tenantName: 'Guest One',
      startAt: startAt ?? now.subtract(const Duration(hours: 1)),
      endAt: endAt ?? now.add(const Duration(days: 2)),
      totalPrice: 100.0,
      unitLabel: 'night',
      userId: guestId,
      status: status,
      createdAt: now.subtract(const Duration(days: 1)),
    );
  }

  /// Seeds a booking plus its existing conversation, as after acceptance.
  Conversation seedBookingWithConversation(Booking booking) {
    store.add(booking);
    final conversation = Conversation(
      id: 'conv_existing',
      participantOneId: guestId,
      participantTwoId: hostId,
      bookingId: booking.id,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    conversations.seed(conversation);
    return conversation;
  }

  group('acceptBookingWithConversation', () {
    test(
        'sends three separate messages, Airbnb-style: the reservation card, '
        'the rendered welcome template, and the host note', () async {
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      final result = await coordinator.acceptBookingWithConversation(
        bookingId: booking.id,
        hostId: hostId,
        message: 'Looking forward to hosting you!',
      );

      expect(result.booking.status, BookingStatus.confirmed);
      expect(result.hasConversation, isTrue);
      expect(conversations.all, hasLength(1));
      expect(conversations.all.single.bookingId, booking.id);

      expect(messages.sent, hasLength(3));

      // 1. The reservation card — a visual summary, not the welcome text.
      final card = messages.sent[0];
      expect(card.senderId, hostId);
      expect(card.hasCard, isTrue);
      expect(card.content, isNot(contains('thanks for your reservation')),
          reason: 'welcome text hidden inside a card message is never '
              'rendered — it must be its own text message');

      // 2. The welcome template, as a plain text message the guest can read.
      final welcome = messages.sent[1];
      expect(welcome.senderId, hostId);
      expect(welcome.hasCard, isFalse);
      expect(welcome.content, contains('thanks for your reservation'));
      expect(welcome.content, contains('Guest One'));
      expect(welcome.content, contains('Madhara Homes'));

      // 3. The host's note is their own words — a separate message, not
      // embedded in the template.
      expect(messages.sent[2].content, 'Looking forward to hosting you!');
      expect(messages.sent[2].senderId, hostId);
      expect(messages.sent[2].hasCard, isFalse);
    });

    test('a custom template is rendered with the booking variables', () async {
      templates.overrides[MessageTemplateTrigger.bookingConfirmed] =
          const MessageTemplate(
        hostId: hostId,
        trigger: MessageTemplateTrigger.bookingConfirmed,
        content: 'Welcome {{guest_name}} — see you at {{listing_title}}!',
      );
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      await coordinator.acceptBookingWithConversation(
        bookingId: booking.id,
        hostId: hostId,
      );

      expect(messages.sent, hasLength(2));
      expect(messages.sent[0].hasCard, isTrue);
      expect(messages.sent[1].content,
          'Welcome Guest One — see you at Listing One!');
    });

    test('a disabled template sends no automatic welcome', () async {
      templates.overrides[MessageTemplateTrigger.bookingConfirmed] =
          const MessageTemplate(
        hostId: hostId,
        trigger: MessageTemplateTrigger.bookingConfirmed,
        content: 'unused',
        enabled: false,
      );
      final booking = createBooking(status: BookingStatus.pending);
      store.add(booking);

      await coordinator.acceptBookingWithConversation(
        bookingId: booking.id,
        hostId: hostId,
        message: 'Just my own note.',
      );

      expect(messages.sent, hasLength(1));
      expect(messages.sent.single.content, 'Just my own note.');
    });

    test(
        'a second booking from the same guest reuses the single '
        'per-pair thread (Airbnb-style) instead of opening a new one',
        () async {
      final first = createBooking(id: 'booking_1');
      final second = createBooking(id: 'booking_2');
      store.add(first);
      store.add(second);

      final resultOne = await coordinator.acceptBookingWithConversation(
        bookingId: first.id,
        hostId: hostId,
      );
      final resultTwo = await coordinator.acceptBookingWithConversation(
        bookingId: second.id,
        hostId: hostId,
      );

      expect(conversations.all, hasLength(1),
          reason: 'one thread per guest-host pair');
      expect(resultTwo.conversation!.id, resultOne.conversation!.id);
      // Thread context follows the latest booking.
      expect(conversations.all.single.bookingId, second.id);
      // Both welcomes (card + text each) land in the same thread.
      expect(messages.sent, hasLength(4));
      expect(messages.sent.map((m) => m.conversationId).toSet(),
          {resultOne.conversation!.id});
    });
  });

  group('checkInGuestWithNotification', () {
    test('checks in the guest and sends the check-in message', () async {
      final booking = createBooking(status: BookingStatus.confirmed);
      final conversation = seedBookingWithConversation(booking);

      final checkedIn = await coordinator.checkInGuestWithNotification(
        bookingId: booking.id,
        hostId: hostId,
      );

      expect(checkedIn.status, BookingStatus.active);
      expect(messages.sent, hasLength(1));
      expect(messages.sent.single.conversationId, conversation.id);
      expect(messages.sent.single.content, contains('checked in'));
    });
  });

  group('single per-pair thread', () {
    test(
        'lifecycle messages reach the pair thread even when it was '
        'created for an earlier booking', () async {
      // The pair's thread exists, but its context points at an old booking.
      final oldBooking = createBooking(id: 'booking_old');
      final thread = seedBookingWithConversation(oldBooking);

      final newBooking = createBooking(
        id: 'booking_new',
        status: BookingStatus.active,
        startAt: DateTime.now().subtract(const Duration(days: 2)),
        endAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      store.add(newBooking);

      await coordinator.completeServiceWithNotification(
        bookingId: newBooking.id,
        hostId: hostId,
      );

      expect(messages.sent, hasLength(1),
          reason: 'the completion message must not be silently dropped');
      expect(messages.sent.single.conversationId, thread.id);
    });
  });

  group('completeServiceWithNotification', () {
    test(
        'completes the booking, sends the thank-you message, '
        'and keeps the conversation writable (never archives)', () async {
      final booking = createBooking(
        status: BookingStatus.active,
        startAt: DateTime.now().subtract(const Duration(days: 2)),
        endAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final conversation = seedBookingWithConversation(booking);

      final completed = await coordinator.completeServiceWithNotification(
        bookingId: booking.id,
        hostId: hostId,
      );

      expect(completed.status, BookingStatus.completed);
      expect(messages.sent, hasLength(1));
      expect(messages.sent.single.conversationId, conversation.id);
      expect(messages.sent.single.senderId, hostId);
      expect(messages.sent.single.content, contains('Thanks for staying'));
      expect(conversations.archivedIds, isEmpty);
    });
  });

  group('cancelBookingWithNotification', () {
    test(
        'sends a cancellation message in the conversation '
        'and keeps the conversation writable (never archives)', () async {
      final booking = createBooking(status: BookingStatus.confirmed);
      final conversation = seedBookingWithConversation(booking);

      final cancelled = await coordinator.cancelBookingWithNotification(
        bookingId: booking.id,
        cancelledBy: hostId,
        isHost: true,
        hostId: hostId,
      );

      expect(cancelled.status, BookingStatus.cancelled);
      expect(messages.sent, hasLength(1));
      expect(messages.sent.single.conversationId, conversation.id);
      expect(messages.sent.single.senderId, hostId);
      expect(messages.sent.single.content, contains('cancelled'));
      expect(conversations.archivedIds, isEmpty,
          reason: 'guest and host can always message, '
              'even after the reservation flow ends');
    });
  });
}
