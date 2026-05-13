import 'dart:async';

import '../../config/messenger_config.dart';
import '../../config/whatsapp_config.dart';
import '../../models/message.dart';
import 'messenger_service.dart';
import 'messaging_service.dart';
import 'whatsapp_service.dart';

/// Available messaging channels
enum MessagingChannel {
  /// In-app chat (default)
  inApp,

  /// WhatsApp Business API
  whatsApp,

  /// Facebook Messenger
  messenger,
}

extension MessagingChannelExtension on MessagingChannel {
  String get displayName {
    switch (this) {
      case MessagingChannel.inApp:
        return 'In-App';
      case MessagingChannel.whatsApp:
        return 'WhatsApp';
      case MessagingChannel.messenger:
        return 'Messenger';
    }
  }

  String get iconName {
    switch (this) {
      case MessagingChannel.inApp:
        return 'chat';
      case MessagingChannel.whatsApp:
        return 'whatsapp';
      case MessagingChannel.messenger:
        return 'messenger';
    }
  }

  bool get isExternal => this != MessagingChannel.inApp;
}

/// Result wrapper for routing operations
class RoutingResult<T> {
  const RoutingResult.success(this.data, this.channel)
      : error = null,
        fallbackUsed = false;

  const RoutingResult.fallback(this.data, this.channel)
      : error = null,
        fallbackUsed = true;

  const RoutingResult.failure(this.error)
      : data = null,
        channel = null,
        fallbackUsed = false;

  final T? data;
  final String? error;
  final MessagingChannel? channel;
  final bool fallbackUsed;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// User's channel preferences
class UserChannelPreferences {
  const UserChannelPreferences({
    required this.userId,
    this.preferredChannel = MessagingChannel.inApp,
    this.whatsAppNumber,
    this.messengerPsid,
    this.whatsAppOptedIn = false,
    this.messengerOptedIn = false,
    this.lastWhatsAppSession,
    this.lastMessengerInteraction,
  });

  final String userId;
  final MessagingChannel preferredChannel;
  final String? whatsAppNumber;
  final String? messengerPsid;
  final bool whatsAppOptedIn;
  final bool messengerOptedIn;
  final DateTime? lastWhatsAppSession;
  final DateTime? lastMessengerInteraction;

  /// Check if WhatsApp is available for this user
  bool get canUseWhatsApp => whatsAppOptedIn && whatsAppNumber != null;

  /// Check if Messenger is available for this user
  bool get canUseMessenger => messengerOptedIn && messengerPsid != null;

  /// Check if WhatsApp session is within 24-hour window
  bool get hasActiveWhatsAppSession {
    if (lastWhatsAppSession == null) return false;
    final sessionAge = DateTime.now().difference(lastWhatsAppSession!);
    return sessionAge.inHours < 24;
  }

  /// Get available channels for this user
  List<MessagingChannel> get availableChannels {
    final channels = <MessagingChannel>[MessagingChannel.inApp];
    if (canUseWhatsApp) channels.add(MessagingChannel.whatsApp);
    if (canUseMessenger) channels.add(MessagingChannel.messenger);
    return channels;
  }

  UserChannelPreferences copyWith({
    String? userId,
    MessagingChannel? preferredChannel,
    String? whatsAppNumber,
    String? messengerPsid,
    bool? whatsAppOptedIn,
    bool? messengerOptedIn,
    DateTime? lastWhatsAppSession,
    DateTime? lastMessengerInteraction,
  }) {
    return UserChannelPreferences(
      userId: userId ?? this.userId,
      preferredChannel: preferredChannel ?? this.preferredChannel,
      whatsAppNumber: whatsAppNumber ?? this.whatsAppNumber,
      messengerPsid: messengerPsid ?? this.messengerPsid,
      whatsAppOptedIn: whatsAppOptedIn ?? this.whatsAppOptedIn,
      messengerOptedIn: messengerOptedIn ?? this.messengerOptedIn,
      lastWhatsAppSession: lastWhatsAppSession ?? this.lastWhatsAppSession,
      lastMessengerInteraction:
          lastMessengerInteraction ?? this.lastMessengerInteraction,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'preferred_channel': preferredChannel.name,
      'whatsapp_number': whatsAppNumber,
      'messenger_psid': messengerPsid,
      'whatsapp_opted_in': whatsAppOptedIn,
      'messenger_opted_in': messengerOptedIn,
      'last_whatsapp_session': lastWhatsAppSession?.toIso8601String(),
      'last_messenger_interaction': lastMessengerInteraction?.toIso8601String(),
    };
  }

  factory UserChannelPreferences.fromJson(Map<String, dynamic> json) {
    return UserChannelPreferences(
      userId: json['user_id'] as String,
      preferredChannel: MessagingChannel.values.firstWhere(
        (c) => c.name == json['preferred_channel'],
        orElse: () => MessagingChannel.inApp,
      ),
      whatsAppNumber: json['whatsapp_number'] as String?,
      messengerPsid: json['messenger_psid'] as String?,
      whatsAppOptedIn: json['whatsapp_opted_in'] as bool? ?? false,
      messengerOptedIn: json['messenger_opted_in'] as bool? ?? false,
      lastWhatsAppSession: json['last_whatsapp_session'] != null
          ? DateTime.parse(json['last_whatsapp_session'] as String)
          : null,
      lastMessengerInteraction: json['last_messenger_interaction'] != null
          ? DateTime.parse(json['last_messenger_interaction'] as String)
          : null,
    );
  }
}

/// Request for sending a message through the router
class RouteMessageRequest {
  const RouteMessageRequest({
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.content,
    this.contentType = MessageContentType.text,
    this.metadata,
    this.preferredChannel,
    this.forceFallback = false,
  });

  final String conversationId;
  final String senderId;
  final String recipientId;
  final String content;
  final MessageContentType contentType;
  final MessageMetadata? metadata;
  final MessagingChannel? preferredChannel;
  final bool forceFallback;
}

/// Message router that handles channel selection and routing
class MessageRouter {
  MessageRouter({
    required this.messagingService,
    required this.whatsAppService,
    required this.messengerService,
  });

  final MessagingService messagingService;
  final WhatsAppService whatsAppService;
  final MessengerService messengerService;

  /// User preferences cache
  final Map<String, UserChannelPreferences> _preferencesCache = {};

  /// Send a message through the appropriate channel
  Future<RoutingResult<String>> sendMessage(RouteMessageRequest request) async {
    // Get recipient's preferences
    final recipientPrefs = await getPreferences(request.recipientId);

    // Determine which channel to use
    final channel = _selectChannel(
      request: request,
      recipientPrefs: recipientPrefs,
    );

    // Try to send through the selected channel
    switch (channel) {
      case MessagingChannel.whatsApp:
        return _sendViaWhatsApp(request, recipientPrefs);

      case MessagingChannel.messenger:
        return _sendViaMessenger(request, recipientPrefs);

      case MessagingChannel.inApp:
        return _sendViaInApp(request);
    }
  }

  MessagingChannel _selectChannel({
    required RouteMessageRequest request,
    required UserChannelPreferences recipientPrefs,
  }) {
    // If a specific channel is requested and available, use it
    if (request.preferredChannel != null) {
      if (_isChannelAvailable(request.preferredChannel!, recipientPrefs)) {
        return request.preferredChannel!;
      }
    }

    // If force fallback, use in-app
    if (request.forceFallback) {
      return MessagingChannel.inApp;
    }

    // Try recipient's preferred channel
    if (_isChannelAvailable(recipientPrefs.preferredChannel, recipientPrefs)) {
      return recipientPrefs.preferredChannel;
    }

    // Default to in-app
    return MessagingChannel.inApp;
  }

  bool _isChannelAvailable(
    MessagingChannel channel,
    UserChannelPreferences prefs,
  ) {
    switch (channel) {
      case MessagingChannel.inApp:
        return true;
      case MessagingChannel.whatsApp:
        return prefs.canUseWhatsApp;
      case MessagingChannel.messenger:
        return prefs.canUseMessenger;
    }
  }

  Future<RoutingResult<String>> _sendViaWhatsApp(
    RouteMessageRequest request,
    UserChannelPreferences recipientPrefs,
  ) async {
    final phoneNumber = recipientPrefs.whatsAppNumber;
    if (phoneNumber == null) {
      // Fallback to in-app
      final result = await _sendViaInApp(request);
      return RoutingResult.fallback(result.data, MessagingChannel.inApp);
    }

    // Check if we have an active session
    final hasSession = recipientPrefs.hasActiveWhatsAppSession;

    if (hasSession) {
      // Send regular message
      final result = await whatsAppService.sendTextMessage(
        to: phoneNumber,
        text: request.content,
      );

      if (result.isSuccess) {
        // Also save to in-app for record keeping
        await _saveToInApp(request, MessagingChannel.whatsApp);
        return RoutingResult.success(result.data!, MessagingChannel.whatsApp);
      }
    } else {
      // Need to use template message - outside 24-hour window
      // For now, fallback to in-app and notify user
      print(
          '║ MessageRouter: WhatsApp session expired, falling back to in-app');
    }

    // Fallback to in-app
    final fallback = await _sendViaInApp(request);
    return RoutingResult.fallback(fallback.data, MessagingChannel.inApp);
  }

  Future<RoutingResult<String>> _sendViaMessenger(
    RouteMessageRequest request,
    UserChannelPreferences recipientPrefs,
  ) async {
    final psid = recipientPrefs.messengerPsid;
    if (psid == null) {
      // Fallback to in-app
      final result = await _sendViaInApp(request);
      return RoutingResult.fallback(result.data, MessagingChannel.inApp);
    }

    final result = await messengerService.sendTextMessage(
      recipientId: psid,
      text: request.content,
    );

    if (result.isSuccess) {
      // Also save to in-app for record keeping
      await _saveToInApp(request, MessagingChannel.messenger);
      return RoutingResult.success(result.data!, MessagingChannel.messenger);
    }

    // Fallback to in-app
    final fallback = await _sendViaInApp(request);
    return RoutingResult.fallback(fallback.data, MessagingChannel.inApp);
  }

  Future<RoutingResult<String>> _sendViaInApp(
    RouteMessageRequest request,
  ) async {
    final sendRequest = SendMessageRequest(
      conversationId: request.conversationId,
      content: request.content,
      contentType: request.contentType,
      metadata: request.metadata,
    );

    final result = await messagingService.sendMessage(
      sendRequest,
      request.senderId,
    );

    if (result.isSuccess && result.data != null) {
      return RoutingResult.success(result.data!.id, MessagingChannel.inApp);
    }

    return RoutingResult.failure(result.error ?? 'Failed to send message');
  }

  Future<void> _saveToInApp(
    RouteMessageRequest request,
    MessagingChannel externalChannel,
  ) async {
    // Save external messages to in-app for record keeping
    final sendRequest = SendMessageRequest(
      conversationId: request.conversationId,
      content: request.content,
      contentType: request.contentType,
      metadata: request.metadata,
      // Add external channel info to metadata
    );

    await messagingService.sendMessage(sendRequest, request.senderId);
  }

  /// Get user's channel preferences
  Future<UserChannelPreferences> getPreferences(String userId) async {
    // Check cache first
    if (_preferencesCache.containsKey(userId)) {
      return _preferencesCache[userId]!;
    }

    // TODO: Load from database
    // For now, return default preferences
    final prefs = UserChannelPreferences(userId: userId);
    _preferencesCache[userId] = prefs;
    return prefs;
  }

  /// Update user's channel preferences
  Future<void> updatePreferences(UserChannelPreferences preferences) async {
    _preferencesCache[preferences.userId] = preferences;
    // TODO: Save to database
  }

  /// Register WhatsApp number for user
  Future<void> registerWhatsApp({
    required String userId,
    required String phoneNumber,
  }) async {
    final currentPrefs = await getPreferences(userId);
    final updatedPrefs = currentPrefs.copyWith(
      whatsAppNumber: phoneNumber,
      whatsAppOptedIn: true,
    );
    await updatePreferences(updatedPrefs);
  }

  /// Register Messenger PSID for user
  Future<void> registerMessenger({
    required String userId,
    required String psid,
  }) async {
    final currentPrefs = await getPreferences(userId);
    final updatedPrefs = currentPrefs.copyWith(
      messengerPsid: psid,
      messengerOptedIn: true,
    );
    await updatePreferences(updatedPrefs);
  }

  /// Update WhatsApp session timestamp
  Future<void> updateWhatsAppSession({
    required String userId,
    required DateTime sessionTime,
  }) async {
    final currentPrefs = await getPreferences(userId);
    final updatedPrefs = currentPrefs.copyWith(
      lastWhatsAppSession: sessionTime,
    );
    await updatePreferences(updatedPrefs);
  }

  /// Process incoming WhatsApp message
  Future<void> processIncomingWhatsApp(
    WhatsAppIncomingMessage message, {
    required String conversationId,
  }) async {
    // Update session timestamp
    // Note: In production, you'd need to map WhatsApp number to user ID
    print('║ MessageRouter: Processing incoming WhatsApp message');
    print('║   From: ${message.from}');
    print('║   Text: ${message.text ?? "[media]"}');

    // Convert to in-app message for storage
    // TODO: Implement full conversion and storage
  }

  /// Process incoming Messenger message
  Future<void> processIncomingMessenger(
    MessengerIncomingMessage message, {
    required String conversationId,
  }) async {
    print('║ MessageRouter: Processing incoming Messenger message');
    print('║   From PSID: ${message.senderId}');
    print('║   Text: ${message.text ?? "[attachment]"}');

    // Convert to in-app message for storage
    // TODO: Implement full conversion and storage
  }

  /// Dispose resources
  void dispose() {
    _preferencesCache.clear();
  }
}

/// Factory for creating MessageRouter instances
class MessageRouterFactory {
  /// Create message router with all services
  static MessageRouter create({
    required MessagingService messagingService,
    WhatsAppConfig? whatsAppConfig,
    MessengerConfig? messengerConfig,
  }) {
    final waConfig = whatsAppConfig ?? WhatsAppConfig.fromEnv();
    final msgConfig = messengerConfig ?? MessengerConfig.fromEnv();

    return MessageRouter(
      messagingService: messagingService,
      whatsAppService: WhatsAppServiceFactory.create(config: waConfig),
      messengerService: MessengerServiceFactory.create(msgConfig),
    );
  }
}
