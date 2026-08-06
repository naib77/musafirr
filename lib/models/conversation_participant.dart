/// Role of a participant in a conversation
enum ParticipantRole {
  /// The person who made the booking (tenant/guest)
  guest,

  /// The property owner/host
  host,

  /// System-generated messages
  system;

  String get displayName {
    switch (this) {
      case ParticipantRole.guest:
        return 'Guest';
      case ParticipantRole.host:
        return 'Host';
      case ParticipantRole.system:
        return 'System';
    }
  }
}

/// Represents a participant in a conversation with their role
class ConversationParticipant {
  const ConversationParticipant({
    required this.userId,
    required this.role,
    this.userName,
    this.avatarUrl,
    this.joinedAt,
  });

  final String userId;
  final ParticipantRole role;
  final String? userName;
  final String? avatarUrl;
  final DateTime? joinedAt;

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      userId: json['user_id'] as String,
      role: ParticipantRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => ParticipantRole.guest,
      ),
      userName: json['user_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'role': role.name,
      'user_name': userName,
      'avatar_url': avatarUrl,
      'joined_at': joinedAt?.toIso8601String(),
    };
  }

  ConversationParticipant copyWith({
    String? userId,
    ParticipantRole? role,
    String? userName,
    String? avatarUrl,
    DateTime? joinedAt,
  }) {
    return ConversationParticipant(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationParticipant &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          role == other.role;

  @override
  int get hashCode => userId.hashCode ^ role.hashCode;

  @override
  String toString() =>
      'ConversationParticipant(userId: $userId, role: ${role.name})';
}

/// A collection of participants in a conversation.
///
/// This class provides a domain-oriented interface for working with
/// conversation participants, supporting both 1:1 and N-way conversations.
///
/// ## Migration Path
///
/// The existing Conversation model uses `participantOneId` and `participantTwoId`.
/// This collection can be built from those fields for backwards compatibility:
///
/// ```dart
/// final participants = ConversationParticipants.fromPair(
///   participantOneId: conv.participantOneId,
///   participantTwoId: conv.participantTwoId,
///   hostId: listing.hostId,
/// );
/// ```
class ConversationParticipants {
  const ConversationParticipants(this._participants);

  final List<ConversationParticipant> _participants;

  /// Create from legacy pair fields.
  factory ConversationParticipants.fromPair({
    required String participantOneId,
    required String participantTwoId,
    required String hostId,
  }) {
    return ConversationParticipants([
      ConversationParticipant(
        userId: hostId,
        role: ParticipantRole.host,
      ),
      ConversationParticipant(
        userId:
            hostId == participantOneId ? participantTwoId : participantOneId,
        role: ParticipantRole.guest,
      ),
    ]);
  }

  /// All participants.
  List<ConversationParticipant> get all => List.unmodifiable(_participants);

  /// Number of participants.
  int get count => _participants.length;

  /// Whether this is a 1:1 conversation.
  bool get isOneToOne => _participants.length == 2;

  /// Whether this is a group conversation.
  bool get isGroup => _participants.length > 2;

  /// Get the host participant.
  ConversationParticipant? get host {
    try {
      return _participants.firstWhere((p) => p.role == ParticipantRole.host);
    } catch (_) {
      return null;
    }
  }

  /// Get all guest participants.
  List<ConversationParticipant> get guests {
    return _participants.where((p) => p.role == ParticipantRole.guest).toList();
  }

  /// Get a participant by user ID.
  ConversationParticipant? getByUserId(String userId) {
    try {
      return _participants.firstWhere((p) => p.userId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Check if a user is a participant.
  bool hasUser(String userId) {
    return _participants.any((p) => p.userId == userId);
  }

  /// Get the other participant in a 1:1 conversation.
  ConversationParticipant? getOther(String currentUserId) {
    if (!isOneToOne) return null;
    try {
      return _participants.firstWhere((p) => p.userId != currentUserId);
    } catch (_) {
      return null;
    }
  }

  /// Get the role of a user.
  ParticipantRole? getRoleOf(String userId) {
    return getByUserId(userId)?.role;
  }

  /// Check if a user is the host.
  bool isHost(String userId) {
    return getRoleOf(userId) == ParticipantRole.host;
  }

  /// Check if a user is a guest.
  bool isGuest(String userId) {
    return getRoleOf(userId) == ParticipantRole.guest;
  }

  /// Add a participant.
  ConversationParticipants add(ConversationParticipant participant) {
    if (hasUser(participant.userId)) {
      return this;
    }
    return ConversationParticipants([..._participants, participant]);
  }

  /// Remove a participant.
  ConversationParticipants remove(String userId) {
    return ConversationParticipants(
      _participants.where((p) => p.userId != userId).toList(),
    );
  }

  /// Get participant IDs as a pair (for legacy compatibility).
  /// Returns null if not a 1:1 conversation.
  ({String participantOneId, String participantTwoId})? toLegacyPair() {
    if (!isOneToOne) return null;
    return (
      participantOneId: _participants[0].userId,
      participantTwoId: _participants[1].userId,
    );
  }

  @override
  String toString() =>
      'ConversationParticipants(${_participants.map((p) => p.userId).join(', ')})';
}
