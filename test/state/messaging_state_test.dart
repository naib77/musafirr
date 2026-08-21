import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/conversation.dart';
import 'package:musafir/models/message.dart';
import 'package:musafir/repositories/conversation_repository.dart';
import 'package:musafir/services/messaging/messaging_service.dart';
import 'package:musafir/state/messaging_state.dart';

const _userId = 'user_1';
const _otherId = 'user_2';
const _convId = 'conv_1';

Conversation _conversation({int unreadCount = 0}) {
  return Conversation(
    id: _convId,
    participantOneId: _userId,
    participantTwoId: _otherId,
    unreadCount: unreadCount,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

class FakeConversationRepository implements ConversationRepository {
  int unreadCount;
  FakeConversationRepository({this.unreadCount = 0});

  @override
  Future<ConversationResult<ConversationPage>> getAll({
    required String userId,
    int limit = 20,
    String? cursor,
  }) async {
    return ConversationResult.success(ConversationPage(
      conversations: [_conversation(unreadCount: unreadCount)],
      hasMore: false,
    ));
  }

  @override
  Future<ConversationResult<int>> getTotalUnreadCount(String userId) async {
    return ConversationResult.success(unreadCount);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class FakeMessagingService implements MessagingService {
  final List<String> markedAllRead = [];

  /// Every remote call this fake serves, in order. On a real backend each one
  /// is a sequential network round trip the guest waits out, so the COUNT
  /// before navigation is the thing worth asserting on.
  final List<String> calls = [];

  /// Calls that have actually RETURNED. A call the guest is not waiting on may
  /// be in [calls] and absent here — which is exactly the distinction between
  /// blocking the chat from opening and hydrating behind it.
  final List<String> completed = [];

  /// Held open to prove hydration is off the critical path: while this is
  /// unresolved, getConversation never returns.
  Completer<void>? blockGetConversation;

  /// Same, for the booking-context write.
  Completer<void>? blockPopulateBookingContext;

  @override
  Future<void> initialize() async {}

  @override
  Future<MessagingResult<Conversation>> getConversation(
    String conversationId,
    String currentUserId,
  ) async {
    calls.add('getConversation');
    if (blockGetConversation != null) await blockGetConversation!.future;
    completed.add('getConversation');
    return MessagingResult.success(_conversation(unreadCount: 2));
  }

  @override
  Future<void> populateBookingContext(
    String conversationId,
    String bookingId,
  ) async {
    calls.add('populateBookingContext');
    if (blockPopulateBookingContext != null) {
      await blockPopulateBookingContext!.future;
    }
    completed.add('populateBookingContext');
  }

  @override
  Future<MessagingResult<String>> getOrCreateConversationId({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    calls.add('getOrCreateConversationId');
    completed.add('getOrCreateConversationId');
    return MessagingResult.success(_convId);
  }

  @override
  Future<MessagingResult<Conversation>> getOrCreateConversation({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    // Mirrors SupabaseMessagingService: create, then hydrate. Short-cutting
    // straight to a Conversation here would hide the very round trips these
    // tests exist to count.
    final id = await getOrCreateConversationId(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
      bookingId: bookingId,
      listingId: listingId,
    );
    if (!id.isSuccess || id.data == null) {
      return MessagingResult.failure(id.error ?? 'failed');
    }
    if (bookingId != null) {
      await populateBookingContext(id.data!, bookingId);
    }
    return getConversation(id.data!, currentUserId);
  }

  @override
  Future<MessagingResult<List<Message>>> getMessages(
    String conversationId, {
    int limit = 50,
    MessageFilter? filter,
  }) async {
    return MessagingResult.success([
      Message(
        id: 'msg_1',
        conversationId: conversationId,
        senderId: _otherId,
        contentType: MessageContentType.text,
        content: 'hello',
        createdAt: DateTime(2026, 1, 2),
        updatedAt: DateTime(2026, 1, 2),
      ),
    ]);
  }

  @override
  Future<MessagingResult<void>> markAllAsRead(
    String conversationId,
    String userId,
  ) async {
    markedAllRead.add(conversationId);
    return const MessagingResult.success(null);
  }

  @override
  Stream<Message> subscribeToMessages(String conversationId) =>
      const Stream.empty();

  @override
  Stream<List<TypingIndicator>> subscribeToTypingIndicators(
    String conversationId,
  ) =>
      const Stream.empty();

  @override
  Stream<Conversation> subscribeToConversations(String userId) =>
      const Stream.empty();

  @override
  Stream<int> subscribeToTotalUnreadCount(String userId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'opening a conversation clears its unread count locally — the '
      'Messages badge must not wait for a sent message or a realtime echo',
      () async {
    final repository = FakeConversationRepository(unreadCount: 3);
    final service = FakeMessagingService();
    final state = MessagingStateNotifier(
      conversationRepository: repository,
      messagingService: service,
    );

    await state.initialize(_userId);
    expect(state.totalUnreadCount, 3,
        reason: 'unread arrives from the repository on init');

    await state.openConversation(_convId);

    expect(service.markedAllRead, [_convId],
        reason: 'the read cursor must be advanced server-side');
    expect(state.totalUnreadCount, 0,
        reason: 'opening the chat reads the messages — the local badge '
            'count must clear immediately');
  });

  group('tapping "Message host"', () {
    // The guest waits, staring at an unchanged listing page, for every round
    // trip this makes before the chat can open. One is unavoidable (the
    // conversation has to exist server-side); the rest were free to drop,
    // because ChatScreen loads its own messages and is handed the host's name
    // and avatar by the listing page.
    Future<MessagingStateNotifier> ready(FakeMessagingService service) async {
      final state = MessagingStateNotifier(
        conversationRepository: FakeConversationRepository(),
        messagingService: service,
      );
      await state.initialize(_userId);
      service.calls.clear(); // drop init chatter
      service.completed.clear();
      return state;
    }

    test('waits on exactly one round trip before the chat can open', () async {
      // Hydration is allowed to START during the call — what must not happen
      // is the guest WAITING on it, so the measure is which calls have
      // completed by the time the id is in hand.
      final service = FakeMessagingService()
        ..blockGetConversation = Completer<void>();
      final state = await ready(service);

      final id = await state
          .startConversationId(otherUserId: _otherId)
          .timeout(const Duration(seconds: 2));

      expect(id, _convId);
      expect(service.calls.first, 'getOrCreateConversationId',
          reason: 'the one unavoidable trip: the conversation must exist '
              'server-side before there is anything to open');
      expect(service.completed, ['getOrCreateConversationId'],
          reason: 'any second COMPLETED call is a round trip of frozen UI — '
              'on a remote backend that is ~1s of nothing happening');

      service.blockGetConversation!.complete();
    });

    test('the old hydrated path really did wait on all of them', () async {
      // The differential that proves the fix is a fix: same fake, same
      // blocked hydration — startConversation cannot get past it.
      final service = FakeMessagingService()
        ..blockGetConversation = Completer<void>();
      final state = await ready(service);

      await expectLater(
        state
            .startConversation(otherUserId: _otherId)
            .timeout(const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
      );

      service.blockGetConversation!.complete();
    });

    test('does not wait on hydration to hand back the id', () async {
      // The proof: hold getConversation open forever. If opening the chat
      // waited on it, this test would hang instead of returning.
      final service = FakeMessagingService()
        ..blockGetConversation = Completer<void>();
      final state = await ready(service);

      final id = await state
          .startConversationId(otherUserId: _otherId)
          .timeout(const Duration(seconds: 2));

      expect(id, _convId,
          reason: 'the id must arrive while hydration is still in flight');
    });

    test('still hydrates the Messages list, just afterwards', () async {
      // Off the critical path, but not dropped: a newly created thread has to
      // appear in the list without waiting for the next refresh.
      final service = FakeMessagingService();
      final state = await ready(service);

      await state.startConversationId(otherUserId: _otherId);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(service.calls, contains('getConversation'),
          reason: 'hydration must still happen, after the id is returned');
      expect(state.conversations.any((c) => c.id == _convId), isTrue);
    });

    test('a booking chat also waits on only the one trip', () async {
      // The booking flows were the worst of the lot: create, then read the
      // booking, then write the context onto the conversation, then hydrate —
      // six round trips before the chat appeared.
      final service = FakeMessagingService()
        ..blockGetConversation = Completer<void>()
        ..blockPopulateBookingContext = Completer<void>();
      final state = await ready(service);

      final id = await state
          .startConversationId(otherUserId: _otherId, bookingId: 'booking_1')
          .timeout(const Duration(seconds: 2));

      expect(id, _convId);
      expect(service.completed, ['getOrCreateConversationId'],
          reason: 'booking context is enrichment — the chat must not wait on '
              'it, nor on the hydration behind it');

      service.blockPopulateBookingContext!.complete();
      service.blockGetConversation!.complete();
    });

    test('booking context is still stamped on, in the background', () async {
      final service = FakeMessagingService();
      final state = await ready(service);

      await state.startConversationId(
        otherUserId: _otherId,
        bookingId: 'booking_1',
      );
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(service.calls, contains('populateBookingContext'));
      // Order matters: the row read back for the Messages list has to carry
      // the context that was just written, or the list shows a bare thread.
      expect(
        service.calls.indexOf('populateBookingContext'),
        lessThan(service.calls.indexOf('getConversation')),
        reason: 'enrich first, then read back',
      );
    });

    test('the hydrated path still stamps context before returning', () async {
      // Unchanged for callers that ask for the object: they get one with the
      // booking context already applied.
      final service = FakeMessagingService();
      final state = await ready(service);

      await state.startConversation(
        otherUserId: _otherId,
        bookingId: 'booking_1',
      );

      expect(service.completed, [
        'getOrCreateConversationId',
        'populateBookingContext',
        'getConversation',
      ]);
    });

    test('a failed create yields null rather than a half-open chat', () async {
      final service = FailingMessagingService();
      final state = MessagingStateNotifier(
        conversationRepository: FakeConversationRepository(),
        messagingService: service,
      );
      await state.initialize(_userId);

      expect(await state.startConversationId(otherUserId: _otherId), isNull);
    });

    test('the hydrated path still returns the full conversation', () async {
      // startConversation is unchanged for callers that need the object.
      final service = FakeMessagingService();
      final state = await ready(service);

      final conv = await state.startConversation(otherUserId: _otherId);

      expect(conv?.id, _convId);
    });
  });
}

/// A service whose conversation creation always fails, to pin the null path.
class FailingMessagingService extends FakeMessagingService {
  @override
  Future<MessagingResult<String>> getOrCreateConversationId({
    required String currentUserId,
    required String otherUserId,
    String? bookingId,
    String? listingId,
  }) async {
    return MessagingResult.failure('nope');
  }
}
