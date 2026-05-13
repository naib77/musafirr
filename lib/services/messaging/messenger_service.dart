import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/messenger_config.dart';

/// Result wrapper for Messenger operations
class MessengerResult<T> {
  const MessengerResult.success(this.data)
      : error = null,
        errorCode = null;
  const MessengerResult.failure(this.error, [this.errorCode]) : data = null;

  final T? data;
  final String? error;
  final int? errorCode;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Incoming message from Messenger webhook
class MessengerIncomingMessage {
  const MessengerIncomingMessage({
    required this.senderId,
    required this.recipientId,
    required this.timestamp,
    required this.messageId,
    this.text,
    this.attachments,
    this.quickReply,
    this.referral,
  });

  /// Page-scoped ID of sender
  final String senderId;

  /// Page ID
  final String recipientId;

  /// Message timestamp
  final DateTime timestamp;

  /// Message ID
  final String messageId;

  /// Text content (if text message)
  final String? text;

  /// Attachments (images, files, etc.)
  final List<MessengerAttachment>? attachments;

  /// Quick reply payload (if quick reply was clicked)
  final String? quickReply;

  /// Referral data (if user came from an ad, etc.)
  final MessengerReferral? referral;

  factory MessengerIncomingMessage.fromWebhook(Map<String, dynamic> json) {
    final message = json['message'] as Map<String, dynamic>?;
    final attachments = message?['attachments'] as List<dynamic>?;

    return MessengerIncomingMessage(
      senderId: json['sender']['id'] as String,
      recipientId: json['recipient']['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      messageId: message?['mid'] as String? ?? '',
      text: message?['text'] as String?,
      attachments: attachments
          ?.map((a) => MessengerAttachment.fromJson(a as Map<String, dynamic>))
          .toList(),
      quickReply: message?['quick_reply']?['payload'] as String?,
      referral: json['referral'] != null
          ? MessengerReferral.fromJson(json['referral'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get hasText => text != null && text!.isNotEmpty;
  bool get hasAttachments => attachments != null && attachments!.isNotEmpty;
  bool get isQuickReply => quickReply != null;
}

/// Messenger attachment types
enum MessengerAttachmentType {
  image,
  audio,
  video,
  file,
  location,
  fallback,
}

/// Messenger attachment
class MessengerAttachment {
  const MessengerAttachment({
    required this.type,
    this.url,
    this.title,
    this.coordinates,
  });

  final MessengerAttachmentType type;
  final String? url;
  final String? title;
  final MessengerCoordinates? coordinates;

  factory MessengerAttachment.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final payload = json['payload'] as Map<String, dynamic>?;

    return MessengerAttachment(
      type: _parseType(typeStr),
      url: payload?['url'] as String?,
      title: json['title'] as String?,
      coordinates: payload?['coordinates'] != null
          ? MessengerCoordinates.fromJson(
              payload!['coordinates'] as Map<String, dynamic>)
          : null,
    );
  }

  static MessengerAttachmentType _parseType(String type) {
    switch (type) {
      case 'image':
        return MessengerAttachmentType.image;
      case 'audio':
        return MessengerAttachmentType.audio;
      case 'video':
        return MessengerAttachmentType.video;
      case 'file':
        return MessengerAttachmentType.file;
      case 'location':
        return MessengerAttachmentType.location;
      default:
        return MessengerAttachmentType.fallback;
    }
  }
}

/// Coordinates for location attachments
class MessengerCoordinates {
  const MessengerCoordinates({
    required this.lat,
    required this.lng,
  });

  final double lat;
  final double lng;

  factory MessengerCoordinates.fromJson(Map<String, dynamic> json) {
    return MessengerCoordinates(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['long'] as num).toDouble(),
    );
  }
}

/// Referral data from ads or m.me links
class MessengerReferral {
  const MessengerReferral({
    required this.source,
    required this.type,
    this.ref,
    this.adId,
  });

  final String source;
  final String type;
  final String? ref;
  final String? adId;

  factory MessengerReferral.fromJson(Map<String, dynamic> json) {
    return MessengerReferral(
      source: json['source'] as String,
      type: json['type'] as String,
      ref: json['ref'] as String?,
      adId: json['ad_id'] as String?,
    );
  }
}

/// User profile from Messenger
class MessengerUserProfile {
  const MessengerUserProfile({
    required this.id,
    this.firstName,
    this.lastName,
    this.profilePic,
    this.locale,
    this.timezone,
    this.gender,
  });

  final String id;
  final String? firstName;
  final String? lastName;
  final String? profilePic;
  final String? locale;
  final int? timezone;
  final String? gender;

  String get fullName => [firstName, lastName].whereType<String>().join(' ');

  factory MessengerUserProfile.fromJson(Map<String, dynamic> json) {
    return MessengerUserProfile(
      id: json['id'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      profilePic: json['profile_pic'] as String?,
      locale: json['locale'] as String?,
      timezone: json['timezone'] as int?,
      gender: json['gender'] as String?,
    );
  }
}

/// Postback event from button clicks
class MessengerPostback {
  const MessengerPostback({
    required this.senderId,
    required this.recipientId,
    required this.timestamp,
    required this.payload,
    this.title,
    this.referral,
  });

  final String senderId;
  final String recipientId;
  final DateTime timestamp;
  final String payload;
  final String? title;
  final MessengerReferral? referral;

  factory MessengerPostback.fromWebhook(Map<String, dynamic> json) {
    final postback = json['postback'] as Map<String, dynamic>;

    return MessengerPostback(
      senderId: json['sender']['id'] as String,
      recipientId: json['recipient']['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      payload: postback['payload'] as String,
      title: postback['title'] as String?,
      referral: postback['referral'] != null
          ? MessengerReferral.fromJson(
              postback['referral'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Abstract Messenger service interface
abstract class MessengerService {
  /// Send a text message
  Future<MessengerResult<String>> sendTextMessage({
    required String recipientId,
    required String text,
    List<MessengerQuickReply>? quickReplies,
  });

  /// Send an image
  Future<MessengerResult<String>> sendImage({
    required String recipientId,
    required String imageUrl,
  });

  /// Send a file attachment
  Future<MessengerResult<String>> sendFile({
    required String recipientId,
    required String fileUrl,
  });

  /// Send a generic template (rich cards)
  Future<MessengerResult<String>> sendGenericTemplate({
    required String recipientId,
    required MessengerGenericTemplate template,
  });

  /// Send a button template
  Future<MessengerResult<String>> sendButtonTemplate({
    required String recipientId,
    required MessengerButtonTemplate template,
  });

  /// Send a sender action (typing indicator, mark seen)
  Future<MessengerResult<void>> sendSenderAction({
    required String recipientId,
    required MessengerSenderAction action,
  });

  /// Get user profile
  Future<MessengerResult<MessengerUserProfile>> getUserProfile(
      String userId);

  /// Stream of incoming messages
  Stream<MessengerIncomingMessage> get incomingMessages;

  /// Stream of postback events
  Stream<MessengerPostback> get postbackEvents;

  /// Process webhook payload
  void processWebhook(Map<String, dynamic> payload);

  /// Dispose resources
  void dispose();
}

/// Stub implementation for development
class StubMessengerService implements MessengerService {
  final _messageController =
      StreamController<MessengerIncomingMessage>.broadcast();
  final _postbackController = StreamController<MessengerPostback>.broadcast();
  final _sentMessages = <Map<String, dynamic>>[];

  @override
  Stream<MessengerIncomingMessage> get incomingMessages =>
      _messageController.stream;

  @override
  Stream<MessengerPostback> get postbackEvents => _postbackController.stream;

  @override
  Future<MessengerResult<String>> sendTextMessage({
    required String recipientId,
    required String text,
    List<MessengerQuickReply>? quickReplies,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final messageId = 'stub_msg_${DateTime.now().millisecondsSinceEpoch}';

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║               MESSENGER - STUB MESSAGE SENT                  ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ To PSID: $recipientId');
    print('║ Text: $text');
    if (quickReplies != null && quickReplies.isNotEmpty) {
      print('║ Quick Replies: ${quickReplies.map((q) => q.title).join(', ')}');
    }
    print('║ Message ID: $messageId');
    print('╚══════════════════════════════════════════════════════════════╝');

    _sentMessages.add({
      'type': 'text',
      'recipientId': recipientId,
      'text': text,
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return MessengerResult.success(messageId);
  }

  @override
  Future<MessengerResult<String>> sendImage({
    required String recipientId,
    required String imageUrl,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final messageId = 'stub_img_${DateTime.now().millisecondsSinceEpoch}';

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║               MESSENGER - STUB IMAGE SENT                    ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ To PSID: $recipientId');
    print('║ Image URL: $imageUrl');
    print('║ Message ID: $messageId');
    print('╚══════════════════════════════════════════════════════════════╝');

    _sentMessages.add({
      'type': 'image',
      'recipientId': recipientId,
      'imageUrl': imageUrl,
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return MessengerResult.success(messageId);
  }

  @override
  Future<MessengerResult<String>> sendFile({
    required String recipientId,
    required String fileUrl,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final messageId = 'stub_file_${DateTime.now().millisecondsSinceEpoch}';

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║               MESSENGER - STUB FILE SENT                     ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ To PSID: $recipientId');
    print('║ File URL: $fileUrl');
    print('║ Message ID: $messageId');
    print('╚══════════════════════════════════════════════════════════════╝');

    _sentMessages.add({
      'type': 'file',
      'recipientId': recipientId,
      'fileUrl': fileUrl,
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return MessengerResult.success(messageId);
  }

  @override
  Future<MessengerResult<String>> sendGenericTemplate({
    required String recipientId,
    required MessengerGenericTemplate template,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final messageId = 'stub_tpl_${DateTime.now().millisecondsSinceEpoch}';

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║           MESSENGER - STUB GENERIC TEMPLATE SENT             ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ To PSID: $recipientId');
    print('║ Elements: ${template.elements.length}');
    for (final element in template.elements) {
      print('║   - ${element.title}');
      if (element.subtitle != null) {
        print('║     ${element.subtitle}');
      }
    }
    print('║ Message ID: $messageId');
    print('╚══════════════════════════════════════════════════════════════╝');

    _sentMessages.add({
      'type': 'generic_template',
      'recipientId': recipientId,
      'template': template.toJson(),
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return MessengerResult.success(messageId);
  }

  @override
  Future<MessengerResult<String>> sendButtonTemplate({
    required String recipientId,
    required MessengerButtonTemplate template,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final messageId = 'stub_btn_${DateTime.now().millisecondsSinceEpoch}';

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║           MESSENGER - STUB BUTTON TEMPLATE SENT              ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ To PSID: $recipientId');
    print('║ Text: ${template.text}');
    print('║ Buttons: ${template.buttons.map((b) => b.title).join(', ')}');
    print('║ Message ID: $messageId');
    print('╚══════════════════════════════════════════════════════════════╝');

    _sentMessages.add({
      'type': 'button_template',
      'recipientId': recipientId,
      'template': template.toJson(),
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return MessengerResult.success(messageId);
  }

  @override
  Future<MessengerResult<void>> sendSenderAction({
    required String recipientId,
    required MessengerSenderAction action,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    print('║ MESSENGER STUB: Sender action ${action.apiValue} to $recipientId');

    return const MessengerResult.success(null);
  }

  @override
  Future<MessengerResult<MessengerUserProfile>> getUserProfile(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));

    print('║ MESSENGER STUB: Getting profile for PSID $userId');

    // Return stub profile
    return MessengerResult.success(MessengerUserProfile(
      id: userId,
      firstName: 'Test',
      lastName: 'User',
      profilePic: 'https://via.placeholder.com/150',
      locale: 'en_US',
      timezone: 6, // Bangladesh timezone
    ));
  }

  @override
  void processWebhook(Map<String, dynamic> payload) {
    print('║ MESSENGER STUB: Processing webhook payload');

    final entries = payload['entry'] as List<dynamic>?;
    if (entries == null) return;

    for (final entry in entries) {
      final messaging = entry['messaging'] as List<dynamic>?;
      if (messaging == null) continue;

      for (final event in messaging) {
        if (event['message'] != null) {
          final message = MessengerIncomingMessage.fromWebhook(
              event as Map<String, dynamic>);
          _messageController.add(message);
          print('║ MESSENGER STUB: Received message: ${message.text}');
        } else if (event['postback'] != null) {
          final postback =
              MessengerPostback.fromWebhook(event as Map<String, dynamic>);
          _postbackController.add(postback);
          print('║ MESSENGER STUB: Received postback: ${postback.payload}');
        }
      }
    }
  }

  /// Simulate an incoming message (for testing)
  void simulateIncomingMessage({
    required String senderId,
    required String text,
  }) {
    final message = MessengerIncomingMessage(
      senderId: senderId,
      recipientId: 'page_id',
      timestamp: DateTime.now(),
      messageId: 'sim_msg_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
    );
    _messageController.add(message);

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║         MESSENGER - SIMULATED INCOMING MESSAGE               ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ From PSID: $senderId');
    print('║ Text: $text');
    print('╚══════════════════════════════════════════════════════════════╝');
  }

  /// Get sent messages (for testing)
  List<Map<String, dynamic>> get sentMessages =>
      List.unmodifiable(_sentMessages);

  @override
  void dispose() {
    _messageController.close();
    _postbackController.close();
  }
}

/// Production implementation using Facebook Graph API
class GraphApiMessengerService implements MessengerService {
  GraphApiMessengerService(this.config);

  final MessengerConfig config;
  final http.Client _client = http.Client();
  final _messageController =
      StreamController<MessengerIncomingMessage>.broadcast();
  final _postbackController = StreamController<MessengerPostback>.broadcast();

  @override
  Stream<MessengerIncomingMessage> get incomingMessages =>
      _messageController.stream;

  @override
  Stream<MessengerPostback> get postbackEvents => _postbackController.stream;

  @override
  Future<MessengerResult<String>> sendTextMessage({
    required String recipientId,
    required String text,
    List<MessengerQuickReply>? quickReplies,
  }) async {
    final message = <String, dynamic>{'text': text};
    if (quickReplies != null && quickReplies.isNotEmpty) {
      message['quick_replies'] = quickReplies.map((q) => q.toJson()).toList();
    }

    return _sendMessage(recipientId, message);
  }

  @override
  Future<MessengerResult<String>> sendImage({
    required String recipientId,
    required String imageUrl,
  }) async {
    final message = {
      'attachment': {
        'type': 'image',
        'payload': {'url': imageUrl, 'is_reusable': true},
      },
    };

    return _sendMessage(recipientId, message);
  }

  @override
  Future<MessengerResult<String>> sendFile({
    required String recipientId,
    required String fileUrl,
  }) async {
    final message = {
      'attachment': {
        'type': 'file',
        'payload': {'url': fileUrl, 'is_reusable': true},
      },
    };

    return _sendMessage(recipientId, message);
  }

  @override
  Future<MessengerResult<String>> sendGenericTemplate({
    required String recipientId,
    required MessengerGenericTemplate template,
  }) async {
    final message = {
      'attachment': {
        'type': 'template',
        'payload': template.toJson(),
      },
    };

    return _sendMessage(recipientId, message);
  }

  @override
  Future<MessengerResult<String>> sendButtonTemplate({
    required String recipientId,
    required MessengerButtonTemplate template,
  }) async {
    final message = {
      'attachment': {
        'type': 'template',
        'payload': template.toJson(),
      },
    };

    return _sendMessage(recipientId, message);
  }

  Future<MessengerResult<String>> _sendMessage(
    String recipientId,
    Map<String, dynamic> message,
  ) async {
    try {
      final url = Uri.parse(config.messagesEndpoint).replace(
        queryParameters: config.authParams,
      );

      final body = jsonEncode({
        'recipient': {'id': recipientId},
        'message': message,
        'messaging_type': 'RESPONSE',
      });

      final response = await _client.post(
        url,
        headers: config.headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MessengerResult.success(data['message_id'] as String);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMessage = error['error']?['message'] ?? 'Unknown error';
        return MessengerResult.failure(
          'Messenger API error: $errorMessage',
          response.statusCode,
        );
      }
    } catch (e) {
      return MessengerResult.failure('Network error: $e');
    }
  }

  @override
  Future<MessengerResult<void>> sendSenderAction({
    required String recipientId,
    required MessengerSenderAction action,
  }) async {
    try {
      final url = Uri.parse(config.messagesEndpoint).replace(
        queryParameters: config.authParams,
      );

      final body = jsonEncode({
        'recipient': {'id': recipientId},
        'sender_action': action.apiValue,
      });

      final response = await _client.post(
        url,
        headers: config.headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return const MessengerResult.success(null);
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMessage = error['error']?['message'] ?? 'Unknown error';
        return MessengerResult.failure(
          'Messenger API error: $errorMessage',
          response.statusCode,
        );
      }
    } catch (e) {
      return MessengerResult.failure('Network error: $e');
    }
  }

  @override
  Future<MessengerResult<MessengerUserProfile>> getUserProfile(
      String userId) async {
    try {
      final url = Uri.parse(config.userProfileEndpoint(userId)).replace(
        queryParameters: {
          ...config.authParams,
          'fields': 'id,first_name,last_name,profile_pic,locale,timezone,gender',
        },
      );

      final response = await _client.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MessengerResult.success(MessengerUserProfile.fromJson(data));
      } else {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        final errorMessage = error['error']?['message'] ?? 'Unknown error';
        return MessengerResult.failure(
          'Messenger API error: $errorMessage',
          response.statusCode,
        );
      }
    } catch (e) {
      return MessengerResult.failure('Network error: $e');
    }
  }

  @override
  void processWebhook(Map<String, dynamic> payload) {
    final entries = payload['entry'] as List<dynamic>?;
    if (entries == null) return;

    for (final entry in entries) {
      final messaging = entry['messaging'] as List<dynamic>?;
      if (messaging == null) continue;

      for (final event in messaging) {
        if (event['message'] != null) {
          final message = MessengerIncomingMessage.fromWebhook(
              event as Map<String, dynamic>);
          _messageController.add(message);
        } else if (event['postback'] != null) {
          final postback =
              MessengerPostback.fromWebhook(event as Map<String, dynamic>);
          _postbackController.add(postback);
        }
      }
    }
  }

  @override
  void dispose() {
    _client.close();
    _messageController.close();
    _postbackController.close();
  }
}

/// Factory for creating Messenger service instances
class MessengerServiceFactory {
  /// Create appropriate service based on configuration
  static MessengerService create(MessengerConfig config) {
    if (config.isStub) {
      return StubMessengerService();
    }
    return GraphApiMessengerService(config);
  }

  /// Create from environment
  static MessengerService fromEnv() {
    final config = MessengerConfig.fromEnv();
    return create(config);
  }
}
