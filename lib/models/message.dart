import 'user.dart';

/// Type of message content
enum MessageContentType {
  text,
  image,
  location,
  bookingCard,
  system,
  file;

  static MessageContentType fromString(String value) {
    switch (value) {
      case 'text':
        return MessageContentType.text;
      case 'image':
        return MessageContentType.image;
      case 'location':
        return MessageContentType.location;
      case 'booking_card':
        return MessageContentType.bookingCard;
      case 'system':
        return MessageContentType.system;
      case 'file':
        return MessageContentType.file;
      default:
        return MessageContentType.text;
    }
  }

  String toJsonValue() {
    switch (this) {
      case MessageContentType.text:
        return 'text';
      case MessageContentType.image:
        return 'image';
      case MessageContentType.location:
        return 'location';
      case MessageContentType.bookingCard:
        return 'booking_card';
      case MessageContentType.system:
        return 'system';
      case MessageContentType.file:
        return 'file';
    }
  }
}

/// Status of a message
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed;

  static MessageStatus fromString(String value) {
    return MessageStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MessageStatus.sent,
    );
  }
}

/// Represents a chat message
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.contentType,
    required this.content,
    this.metadata,
    this.status = MessageStatus.sent,
    this.replyToId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.sender,
    this.replyTo,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final MessageContentType contentType;
  final String content;
  final MessageMetadata? metadata;
  final MessageStatus status;
  final String? replyToId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Sender info (loaded separately)
  final User? sender;

  /// The message being replied to (loaded separately)
  final Message? replyTo;

  /// Check if this is my message
  bool isMine(String currentUserId) => senderId == currentUserId;

  /// Check if message is deleted
  bool get isDeleted => deletedAt != null;

  /// Check if message is a system message
  bool get isSystemMessage => contentType == MessageContentType.system;

  /// Get the display text for the message
  String get displayText {
    if (isDeleted) return 'This message was deleted';

    switch (contentType) {
      case MessageContentType.text:
        return content;
      case MessageContentType.image:
        return 'Sent an image';
      case MessageContentType.location:
        return 'Shared a location';
      case MessageContentType.bookingCard:
        return 'Booking details';
      case MessageContentType.system:
        return content;
      case MessageContentType.file:
        return 'Sent a file';
    }
  }

  /// Get relative time string
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  /// Get time string (HH:mm format)
  String get timeString {
    final hour = createdAt.hour.toString().padLeft(2, '0');
    final minute = createdAt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Get status icon description
  String get statusDescription {
    switch (status) {
      case MessageStatus.sending:
        return 'Sending...';
      case MessageStatus.sent:
        return 'Sent';
      case MessageStatus.delivered:
        return 'Delivered';
      case MessageStatus.read:
        return 'Read';
      case MessageStatus.failed:
        return 'Failed to send';
    }
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    MessageMetadata? metadata;
    if (json['metadata'] != null) {
      final contentType = MessageContentType.fromString(
        json['content_type'] as String? ?? 'text',
      );
      metadata = MessageMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
        contentType,
      );
    }

    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      contentType: MessageContentType.fromString(
        json['content_type'] as String? ?? 'text',
      ),
      content: json['content'] as String,
      metadata: metadata,
      status: MessageStatus.fromString(json['status'] as String? ?? 'sent'),
      replyToId: json['reply_to_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.parse(json['created_at'] as String),
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      sender: json['sender'] != null
          ? User.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      replyTo: json['reply_to'] != null
          ? Message.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content_type': contentType.toJsonValue(),
      'content': content,
      'metadata': metadata?.toJson(),
      'status': status.name,
      'reply_to_id': replyToId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    MessageContentType? contentType,
    String? content,
    MessageMetadata? metadata,
    MessageStatus? status,
    String? replyToId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    User? sender,
    Message? replyTo,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      contentType: contentType ?? this.contentType,
      content: content ?? this.content,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
      replyToId: replyToId ?? this.replyToId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      sender: sender ?? this.sender,
      replyTo: replyTo ?? this.replyTo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Message(id: $id, type: $contentType, content: $content)';
}

/// Base class for message metadata
abstract class MessageMetadata {
  const MessageMetadata();

  Map<String, dynamic> toJson();

  factory MessageMetadata.fromJson(
    Map<String, dynamic> json,
    MessageContentType type,
  ) {
    switch (type) {
      case MessageContentType.image:
        return ImageMetadata.fromJson(json);
      case MessageContentType.location:
        return LocationMetadata.fromJson(json);
      case MessageContentType.bookingCard:
        return BookingCardMetadata.fromJson(json);
      case MessageContentType.file:
        return FileMetadata.fromJson(json);
      default:
        return EmptyMetadata();
    }
  }
}

/// Empty metadata for text/system messages
class EmptyMetadata extends MessageMetadata {
  const EmptyMetadata();

  @override
  Map<String, dynamic> toJson() => {};
}

/// Metadata for image messages
class ImageMetadata extends MessageMetadata {
  const ImageMetadata({
    required this.url,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.sizeBytes,
    this.mimeType,
  });

  final String url;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int? sizeBytes;
  final String? mimeType;

  /// Get aspect ratio
  double get aspectRatio {
    if (width != null && height != null && height! > 0) {
      return width! / height!;
    }
    return 1.0;
  }

  factory ImageMetadata.fromJson(Map<String, dynamic> json) {
    return ImageMetadata(
      url: json['url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      sizeBytes: json['size_bytes'] as int?,
      mimeType: json['mime_type'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'width': width,
      'height': height,
      'size_bytes': sizeBytes,
      'mime_type': mimeType,
    };
  }
}

/// Metadata for location messages
class LocationMetadata extends MessageMetadata {
  const LocationMetadata({
    required this.latitude,
    required this.longitude,
    this.address,
    this.placeName,
    this.staticMapUrl,
  });

  final double latitude;
  final double longitude;
  final String? address;
  final String? placeName;
  final String? staticMapUrl;

  /// Get display name for the location
  String get displayName => placeName ?? address ?? 'Shared Location';

  factory LocationMetadata.fromJson(Map<String, dynamic> json) {
    return LocationMetadata(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String?,
      placeName: json['place_name'] as String?,
      staticMapUrl: json['static_map_url'] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'place_name': placeName,
      'static_map_url': staticMapUrl,
    };
  }
}

/// Metadata for booking card messages
class BookingCardMetadata extends MessageMetadata {
  const BookingCardMetadata({
    required this.bookingId,
    required this.listingName,
    this.listingImageUrl,
    required this.checkIn,
    required this.checkOut,
    required this.totalPrice,
    required this.currency,
    required this.status,
  });

  final String bookingId;
  final String listingName;
  final String? listingImageUrl;
  final DateTime checkIn;
  final DateTime checkOut;
  final double totalPrice;
  final String currency;
  final String status;

  /// Get formatted date range
  String get dateRange {
    final checkInStr = '${checkIn.day}/${checkIn.month}';
    final checkOutStr = '${checkOut.day}/${checkOut.month}';
    return '$checkInStr - $checkOutStr';
  }

  /// Get number of nights
  int get nights => checkOut.difference(checkIn).inDays;

  factory BookingCardMetadata.fromJson(Map<String, dynamic> json) {
    return BookingCardMetadata(
      bookingId: json['booking_id'] as String,
      listingName: json['listing_name'] as String,
      listingImageUrl: json['listing_image_url'] as String?,
      checkIn: DateTime.parse(json['check_in'] as String),
      checkOut: DateTime.parse(json['check_out'] as String),
      totalPrice: (json['total_price'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'BDT',
      status: json['status'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'booking_id': bookingId,
      'listing_name': listingName,
      'listing_image_url': listingImageUrl,
      'check_in': checkIn.toIso8601String(),
      'check_out': checkOut.toIso8601String(),
      'total_price': totalPrice,
      'currency': currency,
      'status': status,
    };
  }
}

/// Metadata for file messages
class FileMetadata extends MessageMetadata {
  const FileMetadata({
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String url;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// Get human-readable file size
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Get file extension
  String get extension {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : 'FILE';
  }

  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    return FileMetadata(
      url: json['url'] as String,
      fileName: json['file_name'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'file_name': fileName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    };
  }
}

/// System message types
enum SystemMessageType {
  conversationCreated,
  bookingCreated,
  bookingConfirmed,
  bookingCancelled,
  userJoined,
  userLeft;

  static SystemMessageType fromString(String value) {
    return SystemMessageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SystemMessageType.conversationCreated,
    );
  }
}

/// Helper to create system messages
class SystemMessage {
  static Message create({
    required String conversationId,
    required SystemMessageType type,
    String? customMessage,
    Map<String, dynamic>? data,
  }) {
    final now = DateTime.now();
    final content = customMessage ?? _getDefaultMessage(type);

    return Message(
      id: 'system_${now.millisecondsSinceEpoch}',
      conversationId: conversationId,
      senderId: 'system',
      contentType: MessageContentType.system,
      content: content,
      status: MessageStatus.sent,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _getDefaultMessage(SystemMessageType type) {
    switch (type) {
      case SystemMessageType.conversationCreated:
        return 'Conversation started';
      case SystemMessageType.bookingCreated:
        return 'Booking request sent';
      case SystemMessageType.bookingConfirmed:
        return 'Booking confirmed';
      case SystemMessageType.bookingCancelled:
        return 'Booking cancelled';
      case SystemMessageType.userJoined:
        return 'User joined the conversation';
      case SystemMessageType.userLeft:
        return 'User left the conversation';
    }
  }
}
