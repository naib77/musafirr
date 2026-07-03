import 'conversation_participant.dart';
import 'user.dart';

/// Status of a conversation
enum ConversationStatus {
  active,
  archived,
  blocked;

  static ConversationStatus fromString(String value) {
    return ConversationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConversationStatus.active,
    );
  }
}

/// Represents a conversation between two or more users
class Conversation {
  const Conversation({
    required this.id,
    required this.participantOneId,
    required this.participantTwoId,
    this.bookingId,
    this.listingId,
    this.status = ConversationStatus.active,
    this.lastMessageId,
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageSenderId,
    required this.createdAt,
    required this.updatedAt,
    this.otherParticipant,
    this.unreadCount = 0,
    this.participants,
    this.listingTitle,
    this.bookingStart,
    this.bookingEnd,
    this.listingType,
  });

  final String id;
  final String participantOneId;
  final String participantTwoId;
  final String? bookingId;
  final String? listingId;
  final ConversationStatus status;
  final String? lastMessageId;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The other participant in the conversation (loaded separately)
  final User? otherParticipant;

  /// Number of unread messages for the current user
  final int unreadCount;

  /// Participants collection (for N-way support)
  /// This is optional during migration; use participantOneId/participantTwoId for 1:1
  final ConversationParticipants? participants;

  /// Booking context fields (denormalized for display)
  final String? listingTitle;
  final DateTime? bookingStart;
  final DateTime? bookingEnd;
  final String? listingType;

  /// Check if the conversation has any messages
  bool get hasMessages => lastMessageId != null;

  /// Check if there are unread messages
  bool get hasUnread => unreadCount > 0;

  /// Check if conversation is archived (read-only)
  bool get isArchived => status == ConversationStatus.archived;

  /// Check if messaging is allowed (not archived)
  bool get canSendMessages => status == ConversationStatus.active;

  /// Get formatted booking date range for display
  String get bookingDateRange {
    if (bookingStart == null || bookingEnd == null) return '';
    final startStr = '${bookingStart!.day}/${bookingStart!.month}';
    final endStr = '${bookingEnd!.day}/${bookingEnd!.month}';
    return '$startStr - $endStr';
  }

  /// Get display subtitle showing listing type and date range
  String get bookingContextSubtitle {
    final parts = <String>[];
    if (listingType != null) {
      // Capitalize first letter
      parts.add(listingType![0].toUpperCase() + listingType!.substring(1));
    }
    if (bookingDateRange.isNotEmpty) {
      parts.add(bookingDateRange);
    }
    return parts.join(' • ');
  }

  /// Get the display name for the conversation
  String get displayName {
    if (otherParticipant != null) {
      return otherParticipant!.name;
    }
    return 'Unknown User';
  }

  /// Get the avatar URL for the conversation
  String? get avatarUrl => otherParticipant?.photoUrl;

  /// Get relative time for last message
  String get lastMessageRelativeTime {
    if (lastMessageAt == null) return '';

    final now = DateTime.now();
    final diff = now.difference(lastMessageAt!);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    final local = lastMessageAt!.toLocal();
    return '${local.day}/${local.month}';
  }

  /// Check if the current user is participant one
  bool isParticipantOne(String userId) => participantOneId == userId;

  /// Get the other participant's ID
  String getOtherParticipantId(String currentUserId) {
    return currentUserId == participantOneId
        ? participantTwoId
        : participantOneId;
  }

  /// Get the role of a participant in this conversation.
  ///
  /// [userId] The user to get the role for.
  /// [hostId] The host's user ID (from the listing).
  ///
  /// Returns the participant's role based on whether they are the host or guest.
  ParticipantRole getParticipantRole(String userId, String hostId) {
    if (userId == hostId) {
      return ParticipantRole.host;
    }
    return ParticipantRole.guest;
  }

  /// Check if a user is the host in this conversation.
  bool isUserHost(String userId, String hostId) {
    return userId == hostId;
  }

  /// Check if a user is the guest in this conversation.
  bool isUserGuest(String userId, String hostId) {
    return userId != hostId;
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      participantOneId: json['participant_one_id'] as String,
      participantTwoId: json['participant_two_id'] as String,
      bookingId: json['booking_id'] as String?,
      listingId: json['listing_id'] as String?,
      status: ConversationStatus.fromString(json['status'] as String? ?? 'active'),
      lastMessageId: json['last_message_id'] as String?,
      lastMessageText: json['last_message_text'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      lastMessageSenderId: json['last_message_sender_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.parse(json['created_at'] as String),
      otherParticipant: json['other_participant'] != null
          ? User.fromJson(json['other_participant'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      listingTitle: json['listing_title'] as String?,
      bookingStart: json['booking_start'] != null
          ? DateTime.parse(json['booking_start'] as String)
          : null,
      bookingEnd: json['booking_end'] != null
          ? DateTime.parse(json['booking_end'] as String)
          : null,
      listingType: json['listing_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant_one_id': participantOneId,
      'participant_two_id': participantTwoId,
      'booking_id': bookingId,
      'listing_id': listingId,
      'status': status.name,
      'last_message_id': lastMessageId,
      'last_message_text': lastMessageText,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'last_message_sender_id': lastMessageSenderId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'unread_count': unreadCount,
      'listing_title': listingTitle,
      'booking_start': bookingStart?.toIso8601String(),
      'booking_end': bookingEnd?.toIso8601String(),
      'listing_type': listingType,
    };
  }

  Conversation copyWith({
    String? id,
    String? participantOneId,
    String? participantTwoId,
    String? bookingId,
    String? listingId,
    ConversationStatus? status,
    String? lastMessageId,
    String? lastMessageText,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? otherParticipant,
    int? unreadCount,
    ConversationParticipants? participants,
    String? listingTitle,
    DateTime? bookingStart,
    DateTime? bookingEnd,
    String? listingType,
  }) {
    return Conversation(
      id: id ?? this.id,
      participantOneId: participantOneId ?? this.participantOneId,
      participantTwoId: participantTwoId ?? this.participantTwoId,
      bookingId: bookingId ?? this.bookingId,
      listingId: listingId ?? this.listingId,
      status: status ?? this.status,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherParticipant: otherParticipant ?? this.otherParticipant,
      unreadCount: unreadCount ?? this.unreadCount,
      participants: participants ?? this.participants,
      listingTitle: listingTitle ?? this.listingTitle,
      bookingStart: bookingStart ?? this.bookingStart,
      bookingEnd: bookingEnd ?? this.bookingEnd,
      listingType: listingType ?? this.listingType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conversation &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Conversation(id: $id, participants: [$participantOneId, $participantTwoId])';
}

/// Represents a read cursor for tracking read status
class ReadCursor {
  const ReadCursor({
    required this.id,
    required this.conversationId,
    required this.userId,
    this.lastReadMessageId,
    required this.lastReadAt,
  });

  final String id;
  final String conversationId;
  final String userId;
  final String? lastReadMessageId;
  final DateTime lastReadAt;

  factory ReadCursor.fromJson(Map<String, dynamic> json) {
    return ReadCursor(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      userId: json['user_id'] as String,
      lastReadMessageId: json['last_read_message_id'] as String?,
      lastReadAt: DateTime.parse(json['last_read_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'user_id': userId,
      'last_read_message_id': lastReadMessageId,
      'last_read_at': lastReadAt.toIso8601String(),
    };
  }
}

/// Represents a typing indicator
class TypingIndicator {
  const TypingIndicator({
    required this.conversationId,
    required this.userId,
    required this.startedAt,
    this.userName,
  });

  final String conversationId;
  final String userId;
  final DateTime startedAt;
  final String? userName;

  /// Check if the typing indicator is still valid (within 10 seconds)
  bool get isValid {
    return DateTime.now().difference(startedAt).inSeconds < 10;
  }

  factory TypingIndicator.fromJson(Map<String, dynamic> json) {
    return TypingIndicator(
      conversationId: json['conversation_id'] as String,
      userId: json['user_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      userName: json['user_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'user_id': userId,
      'started_at': startedAt.toIso8601String(),
    };
  }
}
