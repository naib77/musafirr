import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../../config/whatsapp_config.dart';

/// Result of a WhatsApp API operation
class WhatsAppResult<T> {
  const WhatsAppResult.success(this.data)
      : error = null,
        errorCode = null,
        isSuccess = true;

  const WhatsAppResult.failure(this.error, {this.errorCode})
      : data = null,
        isSuccess = false;

  final T? data;
  final String? error;
  final String? errorCode;
  final bool isSuccess;
}

/// WhatsApp message types
enum WhatsAppMessageType {
  text,
  image,
  document,
  audio,
  video,
  sticker,
  location,
  contacts,
  interactive,
  template,
  reaction,
}

/// WhatsApp message status
enum WhatsAppMessageStatus {
  sent,
  delivered,
  read,
  failed,
}

/// Incoming WhatsApp message
class WhatsAppIncomingMessage {
  const WhatsAppIncomingMessage({
    required this.id,
    required this.from,
    required this.timestamp,
    required this.type,
    this.text,
    this.image,
    this.location,
    this.contacts,
    this.context,
  });

  final String id;
  final String from; // Phone number
  final DateTime timestamp;
  final WhatsAppMessageType type;
  final String? text;
  final WhatsAppMediaInfo? image;
  final WhatsAppLocationInfo? location;
  final List<WhatsAppContact>? contacts;
  final WhatsAppMessageContext? context; // For replies

  factory WhatsAppIncomingMessage.fromWebhook(Map<String, dynamic> json) {
    final type = _parseMessageType(json['type'] as String);

    return WhatsAppIncomingMessage(
      id: json['id'] as String,
      from: json['from'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.parse(json['timestamp'] as String) * 1000,
      ),
      type: type,
      text: json['text']?['body'] as String?,
      image: json['image'] != null
          ? WhatsAppMediaInfo.fromJson(json['image'] as Map<String, dynamic>)
          : null,
      location: json['location'] != null
          ? WhatsAppLocationInfo.fromJson(
              json['location'] as Map<String, dynamic>)
          : null,
      context: json['context'] != null
          ? WhatsAppMessageContext.fromJson(
              json['context'] as Map<String, dynamic>)
          : null,
    );
  }

  static WhatsAppMessageType _parseMessageType(String type) {
    switch (type) {
      case 'text':
        return WhatsAppMessageType.text;
      case 'image':
        return WhatsAppMessageType.image;
      case 'document':
        return WhatsAppMessageType.document;
      case 'audio':
        return WhatsAppMessageType.audio;
      case 'video':
        return WhatsAppMessageType.video;
      case 'sticker':
        return WhatsAppMessageType.sticker;
      case 'location':
        return WhatsAppMessageType.location;
      case 'contacts':
        return WhatsAppMessageType.contacts;
      case 'interactive':
        return WhatsAppMessageType.interactive;
      default:
        return WhatsAppMessageType.text;
    }
  }
}

/// Media info from WhatsApp
class WhatsAppMediaInfo {
  const WhatsAppMediaInfo({
    required this.id,
    this.mimeType,
    this.sha256,
    this.caption,
  });

  final String id;
  final String? mimeType;
  final String? sha256;
  final String? caption;

  factory WhatsAppMediaInfo.fromJson(Map<String, dynamic> json) {
    return WhatsAppMediaInfo(
      id: json['id'] as String,
      mimeType: json['mime_type'] as String?,
      sha256: json['sha256'] as String?,
      caption: json['caption'] as String?,
    );
  }
}

/// Location info from WhatsApp
class WhatsAppLocationInfo {
  const WhatsAppLocationInfo({
    required this.latitude,
    required this.longitude,
    this.name,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? name;
  final String? address;

  factory WhatsAppLocationInfo.fromJson(Map<String, dynamic> json) {
    return WhatsAppLocationInfo(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      name: json['name'] as String?,
      address: json['address'] as String?,
    );
  }
}

/// Contact info from WhatsApp
class WhatsAppContact {
  const WhatsAppContact({
    required this.name,
    this.phones = const [],
  });

  final String name;
  final List<String> phones;

  factory WhatsAppContact.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as Map<String, dynamic>;
    final phones =
        (json['phones'] as List?)?.map((p) => p['phone'] as String).toList() ??
            [];

    return WhatsAppContact(
      name: name['formatted_name'] as String? ?? 'Unknown',
      phones: phones,
    );
  }
}

/// Message context for replies
class WhatsAppMessageContext {
  const WhatsAppMessageContext({
    required this.messageId,
    this.from,
  });

  final String messageId;
  final String? from;

  factory WhatsAppMessageContext.fromJson(Map<String, dynamic> json) {
    return WhatsAppMessageContext(
      messageId: json['id'] as String,
      from: json['from'] as String?,
    );
  }
}

/// WhatsApp session tracking (24-hour window)
class WhatsAppSession {
  const WhatsAppSession({
    required this.phoneNumber,
    required this.lastMessageAt,
    required this.isActive,
  });

  final String phoneNumber;
  final DateTime lastMessageAt;
  final bool isActive;

  /// Check if session is still valid (within 24 hours)
  bool get isValid {
    final now = DateTime.now();
    final diff = now.difference(lastMessageAt);
    return diff.inHours < 24;
  }

  /// Time remaining in session
  Duration get timeRemaining {
    final expiry = lastMessageAt.add(const Duration(hours: 24));
    final now = DateTime.now();
    if (now.isAfter(expiry)) return Duration.zero;
    return expiry.difference(now);
  }
}

/// Abstract WhatsApp service interface
abstract class WhatsAppService {
  /// Send a text message
  Future<WhatsAppResult<String>> sendTextMessage({
    required String to,
    required String text,
    String? replyToMessageId,
  });

  /// Send an image message
  Future<WhatsAppResult<String>> sendImageMessage({
    required String to,
    required String mediaUrl,
    String? caption,
  });

  /// Send a location message
  Future<WhatsAppResult<String>> sendLocationMessage({
    required String to,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
  });

  /// Send a template message
  Future<WhatsAppResult<String>> sendTemplateMessage({
    required String to,
    required WhatsAppTemplate template,
  });

  /// Mark message as read
  Future<WhatsAppResult<void>> markAsRead(String messageId);

  /// Get media URL from media ID
  Future<WhatsAppResult<String>> getMediaUrl(String mediaId);

  /// Check session status for a phone number
  Future<WhatsAppResult<WhatsAppSession>> getSession(String phoneNumber);

  /// Handle incoming webhook
  Future<void> handleWebhook(Map<String, dynamic> payload);

  /// Stream of incoming messages
  Stream<WhatsAppIncomingMessage> get incomingMessages;

  /// Stream of status updates
  Stream<WhatsAppStatusUpdate> get statusUpdates;
}

/// Status update from WhatsApp
class WhatsAppStatusUpdate {
  const WhatsAppStatusUpdate({
    required this.messageId,
    required this.status,
    required this.timestamp,
    this.recipientId,
  });

  final String messageId;
  final WhatsAppMessageStatus status;
  final DateTime timestamp;
  final String? recipientId;
}

/// Stub implementation for development
class StubWhatsAppService implements WhatsAppService {
  StubWhatsAppService({WhatsAppConfig? config});

  final _incomingController =
      StreamController<WhatsAppIncomingMessage>.broadcast();
  final _statusController = StreamController<WhatsAppStatusUpdate>.broadcast();
  final Map<String, WhatsAppSession> _sessions = {};

  @override
  Stream<WhatsAppIncomingMessage> get incomingMessages =>
      _incomingController.stream;

  @override
  Stream<WhatsAppStatusUpdate> get statusUpdates => _statusController.stream;

  @override
  Future<WhatsAppResult<String>> sendTextMessage({
    required String to,
    required String text,
    String? replyToMessageId,
  }) async {
    debugPrint('[StubWhatsAppService] Sending text to $to: $text');

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Update session
    _sessions[to] = WhatsAppSession(
      phoneNumber: to,
      lastMessageAt: DateTime.now(),
      isActive: true,
    );

    final messageId = 'wamid_stub_${DateTime.now().millisecondsSinceEpoch}';

    // Simulate status updates
    _simulateStatusUpdates(messageId, to);

    return WhatsAppResult.success(messageId);
  }

  @override
  Future<WhatsAppResult<String>> sendImageMessage({
    required String to,
    required String mediaUrl,
    String? caption,
  }) async {
    debugPrint('[StubWhatsAppService] Sending image to $to: $mediaUrl');

    await Future.delayed(const Duration(milliseconds: 800));

    _sessions[to] = WhatsAppSession(
      phoneNumber: to,
      lastMessageAt: DateTime.now(),
      isActive: true,
    );

    final messageId = 'wamid_stub_${DateTime.now().millisecondsSinceEpoch}';
    _simulateStatusUpdates(messageId, to);

    return WhatsAppResult.success(messageId);
  }

  @override
  Future<WhatsAppResult<String>> sendLocationMessage({
    required String to,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
  }) async {
    debugPrint(
        '[StubWhatsAppService] Sending location to $to: ($latitude, $longitude)');

    await Future.delayed(const Duration(milliseconds: 500));

    _sessions[to] = WhatsAppSession(
      phoneNumber: to,
      lastMessageAt: DateTime.now(),
      isActive: true,
    );

    final messageId = 'wamid_stub_${DateTime.now().millisecondsSinceEpoch}';
    _simulateStatusUpdates(messageId, to);

    return WhatsAppResult.success(messageId);
  }

  @override
  Future<WhatsAppResult<String>> sendTemplateMessage({
    required String to,
    required WhatsAppTemplate template,
  }) async {
    debugPrint(
        '[StubWhatsAppService] Sending template ${template.name} to $to');

    await Future.delayed(const Duration(milliseconds: 500));

    final messageId = 'wamid_stub_${DateTime.now().millisecondsSinceEpoch}';
    _simulateStatusUpdates(messageId, to);

    return WhatsAppResult.success(messageId);
  }

  @override
  Future<WhatsAppResult<void>> markAsRead(String messageId) async {
    debugPrint('[StubWhatsAppService] Marking message as read: $messageId');

    await Future.delayed(const Duration(milliseconds: 200));
    return const WhatsAppResult.success(null);
  }

  @override
  Future<WhatsAppResult<String>> getMediaUrl(String mediaId) async {
    debugPrint('[StubWhatsAppService] Getting media URL for: $mediaId');

    await Future.delayed(const Duration(milliseconds: 300));
    return WhatsAppResult.success('https://example.com/media/$mediaId');
  }

  @override
  Future<WhatsAppResult<WhatsAppSession>> getSession(String phoneNumber) async {
    final session = _sessions[phoneNumber];
    if (session == null) {
      return WhatsAppResult.success(WhatsAppSession(
        phoneNumber: phoneNumber,
        lastMessageAt: DateTime.now().subtract(const Duration(hours: 25)),
        isActive: false,
      ));
    }
    return WhatsAppResult.success(session);
  }

  @override
  Future<void> handleWebhook(Map<String, dynamic> payload) async {
    debugPrint('[StubWhatsAppService] Received webhook: $payload');
    // In a real implementation, parse and emit to streams
  }

  void _simulateStatusUpdates(String messageId, String recipientId) {
    // Simulate sent -> delivered -> read
    Future.delayed(const Duration(milliseconds: 100), () {
      _statusController.add(WhatsAppStatusUpdate(
        messageId: messageId,
        status: WhatsAppMessageStatus.sent,
        timestamp: DateTime.now(),
        recipientId: recipientId,
      ));
    });

    Future.delayed(const Duration(seconds: 1), () {
      _statusController.add(WhatsAppStatusUpdate(
        messageId: messageId,
        status: WhatsAppMessageStatus.delivered,
        timestamp: DateTime.now(),
        recipientId: recipientId,
      ));
    });

    Future.delayed(const Duration(seconds: 3), () {
      _statusController.add(WhatsAppStatusUpdate(
        messageId: messageId,
        status: WhatsAppMessageStatus.read,
        timestamp: DateTime.now(),
        recipientId: recipientId,
      ));
    });
  }

  /// Simulate receiving an incoming message (for testing)
  void simulateIncomingMessage({
    required String from,
    required String text,
  }) {
    _sessions[from] = WhatsAppSession(
      phoneNumber: from,
      lastMessageAt: DateTime.now(),
      isActive: true,
    );

    _incomingController.add(WhatsAppIncomingMessage(
      id: 'wamid_incoming_${DateTime.now().millisecondsSinceEpoch}',
      from: from,
      timestamp: DateTime.now(),
      type: WhatsAppMessageType.text,
      text: text,
    ));
  }

  void dispose() {
    _incomingController.close();
    _statusController.close();
  }
}

/// Production WhatsApp Cloud API implementation
class CloudWhatsAppService implements WhatsAppService {
  CloudWhatsAppService({required WhatsAppConfig config})
      : _config = config,
        _client = http.Client();

  final WhatsAppConfig _config;
  final http.Client _client;
  final _incomingController =
      StreamController<WhatsAppIncomingMessage>.broadcast();
  final _statusController = StreamController<WhatsAppStatusUpdate>.broadcast();

  @override
  Stream<WhatsAppIncomingMessage> get incomingMessages =>
      _incomingController.stream;

  @override
  Stream<WhatsAppStatusUpdate> get statusUpdates => _statusController.stream;

  @override
  Future<WhatsAppResult<String>> sendTextMessage({
    required String to,
    required String text,
    String? replyToMessageId,
  }) async {
    final body = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': to,
      'type': 'text',
      'text': {'preview_url': true, 'body': text},
      if (replyToMessageId != null) 'context': {'message_id': replyToMessageId},
    };

    return _sendMessage(body);
  }

  @override
  Future<WhatsAppResult<String>> sendImageMessage({
    required String to,
    required String mediaUrl,
    String? caption,
  }) async {
    final body = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': to,
      'type': 'image',
      'image': {
        'link': mediaUrl,
        if (caption != null) 'caption': caption,
      },
    };

    return _sendMessage(body);
  }

  @override
  Future<WhatsAppResult<String>> sendLocationMessage({
    required String to,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
  }) async {
    final body = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': to,
      'type': 'location',
      'location': {
        'latitude': latitude,
        'longitude': longitude,
        if (name != null) 'name': name,
        if (address != null) 'address': address,
      },
    };

    return _sendMessage(body);
  }

  @override
  Future<WhatsAppResult<String>> sendTemplateMessage({
    required String to,
    required WhatsAppTemplate template,
  }) async {
    final body = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': to,
      'type': 'template',
      'template': template.toJson(),
    };

    return _sendMessage(body);
  }

  Future<WhatsAppResult<String>> _sendMessage(Map<String, dynamic> body) async {
    try {
      final response = await _client.post(
        Uri.parse(_config.messagesEndpoint),
        headers: _config.headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = data['messages'] as List;
        final messageId = messages.first['id'] as String;
        return WhatsAppResult.success(messageId);
      } else {
        final error = jsonDecode(response.body);
        return WhatsAppResult.failure(
          error['error']?['message'] ?? 'Unknown error',
          errorCode: error['error']?['code']?.toString(),
        );
      }
    } catch (e) {
      return WhatsAppResult.failure(e.toString());
    }
  }

  @override
  Future<WhatsAppResult<void>> markAsRead(String messageId) async {
    try {
      final response = await _client.post(
        Uri.parse(_config.messagesEndpoint),
        headers: _config.headers,
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'status': 'read',
          'message_id': messageId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return const WhatsAppResult.success(null);
      } else {
        final error = jsonDecode(response.body);
        return WhatsAppResult.failure(
            error['error']?['message'] ?? 'Unknown error');
      }
    } catch (e) {
      return WhatsAppResult.failure(e.toString());
    }
  }

  @override
  Future<WhatsAppResult<String>> getMediaUrl(String mediaId) async {
    try {
      final response = await _client.get(
        Uri.parse('${_config.baseUrl}/$mediaId'),
        headers: _config.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return WhatsAppResult.success(data['url'] as String);
      } else {
        return const WhatsAppResult.failure('Failed to get media URL');
      }
    } catch (e) {
      return WhatsAppResult.failure(e.toString());
    }
  }

  @override
  Future<WhatsAppResult<WhatsAppSession>> getSession(String phoneNumber) async {
    // Sessions are typically tracked server-side
    // This would need to be implemented with your backend
    return WhatsAppResult.success(WhatsAppSession(
      phoneNumber: phoneNumber,
      lastMessageAt: DateTime.now(),
      isActive: true,
    ));
  }

  @override
  Future<void> handleWebhook(Map<String, dynamic> payload) async {
    try {
      final entry = payload['entry'] as List?;
      if (entry == null || entry.isEmpty) return;

      for (final e in entry) {
        final changes = e['changes'] as List?;
        if (changes == null) continue;

        for (final change in changes) {
          final value = change['value'] as Map<String, dynamic>?;
          if (value == null) continue;

          // Handle incoming messages
          final messages = value['messages'] as List?;
          if (messages != null) {
            for (final msg in messages) {
              final message = WhatsAppIncomingMessage.fromWebhook(
                msg as Map<String, dynamic>,
              );
              _incomingController.add(message);
            }
          }

          // Handle status updates
          final statuses = value['statuses'] as List?;
          if (statuses != null) {
            for (final status in statuses) {
              final update = WhatsAppStatusUpdate(
                messageId: status['id'] as String,
                status: _parseStatus(status['status'] as String),
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  int.parse(status['timestamp'] as String) * 1000,
                ),
                recipientId: status['recipient_id'] as String?,
              );
              _statusController.add(update);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CloudWhatsAppService] Error handling webhook: $e');
    }
  }

  WhatsAppMessageStatus _parseStatus(String status) {
    switch (status) {
      case 'sent':
        return WhatsAppMessageStatus.sent;
      case 'delivered':
        return WhatsAppMessageStatus.delivered;
      case 'read':
        return WhatsAppMessageStatus.read;
      case 'failed':
        return WhatsAppMessageStatus.failed;
      default:
        return WhatsAppMessageStatus.sent;
    }
  }

  void dispose() {
    _client.close();
    _incomingController.close();
    _statusController.close();
  }
}

/// Factory to create appropriate WhatsApp service
class WhatsAppServiceFactory {
  static WhatsAppService create({WhatsAppConfig? config}) {
    final effectiveConfig = config ?? WhatsAppConfig.fromEnv();

    if (effectiveConfig.isStub) {
      debugPrint('[WhatsAppServiceFactory] Using stub WhatsApp service');
      return StubWhatsAppService(config: effectiveConfig);
    }

    debugPrint('[WhatsAppServiceFactory] Using Cloud API WhatsApp service');
    return CloudWhatsAppService(config: effectiveConfig);
  }
}
