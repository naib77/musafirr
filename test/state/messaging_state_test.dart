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

  @override
  Future<void> initialize() async {}

  @override
  Future<MessagingResult<Conversation>> getConversation(
    String conversationId,
    String currentUserId,
  ) async {
    return MessagingResult.success(_conversation(unreadCount: 2));
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
}
