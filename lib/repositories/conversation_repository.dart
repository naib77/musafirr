import '../models/conversation.dart';
import '../models/user.dart';

/// Errors that can occur during conversation operations.
sealed class ConversationError {
  const ConversationError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Conversation was not found.
class ConversationNotFound extends ConversationError {
  const ConversationNotFound(String conversationId)
      : super('Conversation not found: $conversationId');
}

/// User is not authorized to access this conversation.
class ConversationUnauthorized extends ConversationError {
  const ConversationUnauthorized()
      : super('You are not authorized to access this conversation');
}

/// Failed to create conversation.
class ConversationCreationFailed extends ConversationError {
  const ConversationCreationFailed(String reason)
      : super('Failed to create conversation: $reason');
}

/// Network or database error.
class ConversationNetworkError extends ConversationError {
  const ConversationNetworkError(String reason)
      : super('Network error: $reason');
}

/// Result of a conversation operation.
class ConversationResult<T> {
  const ConversationResult.success(this.data) : error = null;

  const ConversationResult.failure(this.error) : data = null;

  final T? data;
  final ConversationError? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  /// Map the success value to another type.
  ConversationResult<R> map<R>(R Function(T data) mapper) {
    if (isSuccess && data != null) {
      return ConversationResult.success(mapper(data as T));
    }
    return ConversationResult.failure(error!);
  }

  /// Execute a callback on success.
  ConversationResult<T> onSuccess(void Function(T data) callback) {
    if (isSuccess && data != null) {
      callback(data as T);
    }
    return this;
  }

  /// Execute a callback on failure.
  ConversationResult<T> onFailure(
      void Function(ConversationError error) callback) {
    if (isFailure && error != null) {
      callback(error!);
    }
    return this;
  }
}

/// A page of conversations with pagination info.
class ConversationPage {
  const ConversationPage({
    required this.conversations,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Conversation> conversations;
  final bool hasMore;
  final String? nextCursor;

  static const empty = ConversationPage(
    conversations: [],
    hasMore: false,
  );
}

/// Domain-oriented repository for conversation operations.
///
/// This interface provides high-level, domain-focused methods for
/// working with conversations, hiding storage details from callers.
///
/// ## Design Principles
///
/// 1. **Domain Language**: Methods use domain terms, not database columns
/// 2. **Typed Errors**: [ConversationError] hierarchy instead of strings
/// 3. **Pagination**: Cursor-based for scalability
/// 4. **Immutability**: Returns new instances, never mutates
///
/// ## Example Usage
///
/// ```dart
/// // Find conversation for a booking
/// final result = await repository.findForBooking(
///   bookingId: 'booking-123',
///   userId: currentUser.id,
/// );
///
/// result.onSuccess((conversation) {
///   // Navigate to chat
/// }).onFailure((error) {
///   if (error is ConversationNotFound) {
///     // Create new conversation
///   }
/// });
/// ```
abstract class ConversationRepository {
  /// Get all conversations for a user.
  ///
  /// Returns conversations sorted by most recent activity.
  Future<ConversationResult<ConversationPage>> getAll({
    required String userId,
    int limit = 20,
    String? cursor,
  });

  /// Get active (non-archived) conversations for a user.
  Future<ConversationResult<ConversationPage>> getActive({
    required String userId,
    int limit = 20,
    String? cursor,
  });

  /// Get archived conversations for a user.
  Future<ConversationResult<ConversationPage>> getArchived({
    required String userId,
    int limit = 20,
    String? cursor,
  });

  /// Get conversations with unread messages.
  Future<ConversationResult<ConversationPage>> getUnread({
    required String userId,
    int limit = 20,
    String? cursor,
  });

  /// Find a specific conversation by ID.
  Future<ConversationResult<Conversation>> findById({
    required String conversationId,
    required String userId,
  });

  /// Find a conversation between two users.
  ///
  /// Returns null if no conversation exists.
  Future<ConversationResult<Conversation?>> findByParticipants({
    required String userOneId,
    required String userTwoId,
  });

  /// Find a conversation for a specific booking.
  ///
  /// Returns null if no conversation exists for this booking.
  Future<ConversationResult<Conversation?>> findForBooking({
    required String bookingId,
    required String userId,
  });

  /// Find conversations for a specific listing.
  Future<ConversationResult<ConversationPage>> findForListing({
    required String listingId,
    required String userId,
    int limit = 20,
    String? cursor,
  });

  /// Create a new conversation between two users.
  ///
  /// If a conversation already exists, returns the existing one.
  /// [listingTitle], [bookingStart], [bookingEnd], [listingType] are
  /// denormalized booking context for display.
  Future<ConversationResult<Conversation>> create({
    required String participantOneId,
    required String participantTwoId,
    String? bookingId,
    String? listingId,
    String? listingTitle,
    DateTime? bookingStart,
    DateTime? bookingEnd,
    String? listingType,
  });

  /// Archive a conversation.
  Future<ConversationResult<void>> archive(String conversationId);

  /// Unarchive a conversation.
  Future<ConversationResult<void>> unarchive(String conversationId);

  /// Block a conversation.
  Future<ConversationResult<void>> block(String conversationId);

  /// Unblock a conversation.
  Future<ConversationResult<void>> unblock(String conversationId);

  /// Get total unread message count across all conversations.
  Future<ConversationResult<int>> getTotalUnreadCount(String userId);

  /// Load the other participant's user info for a conversation.
  Future<ConversationResult<User>> loadOtherParticipant({
    required Conversation conversation,
    required String currentUserId,
  });
}
