/// Configuration for Facebook Messenger API integration
class MessengerConfig {
  const MessengerConfig({
    required this.pageId,
    required this.pageAccessToken,
    required this.appId,
    required this.appSecret,
    this.apiVersion = 'v18.0',
    this.webhookVerifyToken,
  });

  /// Facebook Page ID
  final String pageId;

  /// Page Access Token (long-lived)
  final String pageAccessToken;

  /// Facebook App ID
  final String appId;

  /// Facebook App Secret
  final String appSecret;

  /// Graph API version
  final String apiVersion;

  /// Webhook verification token
  final String? webhookVerifyToken;

  /// Base URL for Facebook Graph API
  String get baseUrl => 'https://graph.facebook.com/$apiVersion';

  /// Messages endpoint
  String get messagesEndpoint => '$baseUrl/me/messages';

  /// Page endpoint
  String get pageEndpoint => '$baseUrl/$pageId';

  /// User profile endpoint
  String userProfileEndpoint(String psid) => '$baseUrl/$psid';

  /// Development/stub configuration
  static const MessengerConfig stub = MessengerConfig(
    pageId: 'STUB_PAGE_ID',
    pageAccessToken: 'STUB_PAGE_ACCESS_TOKEN',
    appId: 'STUB_APP_ID',
    appSecret: 'STUB_APP_SECRET',
    webhookVerifyToken: 'STUB_VERIFY_TOKEN',
  );

  /// Create from environment variables
  factory MessengerConfig.fromEnv() {
    return MessengerConfig(
      pageId: const String.fromEnvironment(
        'MESSENGER_PAGE_ID',
        defaultValue: 'STUB_PAGE_ID',
      ),
      pageAccessToken: const String.fromEnvironment(
        'MESSENGER_PAGE_ACCESS_TOKEN',
        defaultValue: 'STUB_PAGE_ACCESS_TOKEN',
      ),
      appId: const String.fromEnvironment(
        'MESSENGER_APP_ID',
        defaultValue: 'STUB_APP_ID',
      ),
      appSecret: const String.fromEnvironment(
        'MESSENGER_APP_SECRET',
        defaultValue: 'STUB_APP_SECRET',
      ),
      webhookVerifyToken: const String.fromEnvironment(
        'MESSENGER_WEBHOOK_VERIFY_TOKEN',
        defaultValue: 'STUB_VERIFY_TOKEN',
      ),
    );
  }

  /// Check if this is a stub/development configuration
  bool get isStub => pageId == 'STUB_PAGE_ID';

  /// Authorization header
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
      };

  /// Query parameters with access token
  Map<String, String> get authParams => {
        'access_token': pageAccessToken,
      };
}

/// Messenger message types
enum MessengerMessageType {
  text,
  image,
  audio,
  video,
  file,
  template,
  quickReplies,
}

/// Messenger sender action types (typing indicators, etc.)
enum MessengerSenderAction {
  typingOn,
  typingOff,
  markSeen,
}

extension MessengerSenderActionExtension on MessengerSenderAction {
  String get apiValue {
    switch (this) {
      case MessengerSenderAction.typingOn:
        return 'typing_on';
      case MessengerSenderAction.typingOff:
        return 'typing_off';
      case MessengerSenderAction.markSeen:
        return 'mark_seen';
    }
  }
}

/// Messenger template types
enum MessengerTemplateType {
  generic,
  button,
  receipt,
  airline,
}

/// Quick reply content type
enum MessengerQuickReplyType {
  text,
  userPhoneNumber,
  userEmail,
}

/// Messenger quick reply button
class MessengerQuickReply {
  const MessengerQuickReply({
    required this.contentType,
    this.title,
    this.payload,
    this.imageUrl,
  });

  final MessengerQuickReplyType contentType;
  final String? title;
  final String? payload;
  final String? imageUrl;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'content_type': _contentTypeToString(contentType),
    };
    if (title != null) json['title'] = title;
    if (payload != null) json['payload'] = payload;
    if (imageUrl != null) json['image_url'] = imageUrl;
    return json;
  }

  String _contentTypeToString(MessengerQuickReplyType type) {
    switch (type) {
      case MessengerQuickReplyType.text:
        return 'text';
      case MessengerQuickReplyType.userPhoneNumber:
        return 'user_phone_number';
      case MessengerQuickReplyType.userEmail:
        return 'user_email';
    }
  }
}

/// Messenger button types
enum MessengerButtonType {
  webUrl,
  postback,
  phoneNumber,
}

/// Messenger button
class MessengerButton {
  const MessengerButton({
    required this.type,
    required this.title,
    this.url,
    this.payload,
  });

  final MessengerButtonType type;
  final String title;
  final String? url;
  final String? payload;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': _typeToString(type),
      'title': title,
    };
    if (url != null) json['url'] = url;
    if (payload != null) json['payload'] = payload;
    return json;
  }

  String _typeToString(MessengerButtonType type) {
    switch (type) {
      case MessengerButtonType.webUrl:
        return 'web_url';
      case MessengerButtonType.postback:
        return 'postback';
      case MessengerButtonType.phoneNumber:
        return 'phone_number';
    }
  }
}

/// Generic template element
class MessengerGenericElement {
  const MessengerGenericElement({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.defaultAction,
    this.buttons = const [],
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final MessengerButton? defaultAction;
  final List<MessengerButton> buttons;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'title': title};
    if (subtitle != null) json['subtitle'] = subtitle;
    if (imageUrl != null) json['image_url'] = imageUrl;
    if (defaultAction != null) {
      json['default_action'] = defaultAction!.toJson();
    }
    if (buttons.isNotEmpty) {
      json['buttons'] = buttons.map((b) => b.toJson()).toList();
    }
    return json;
  }
}

/// Generic template for rich cards
class MessengerGenericTemplate {
  const MessengerGenericTemplate({
    required this.elements,
    this.sharable = false,
  });

  final List<MessengerGenericElement> elements;
  final bool sharable;

  Map<String, dynamic> toJson() {
    return {
      'template_type': 'generic',
      'sharable': sharable,
      'elements': elements.map((e) => e.toJson()).toList(),
    };
  }
}

/// Button template for text + buttons
class MessengerButtonTemplate {
  const MessengerButtonTemplate({
    required this.text,
    required this.buttons,
  });

  final String text;
  final List<MessengerButton> buttons;

  Map<String, dynamic> toJson() {
    return {
      'template_type': 'button',
      'text': text,
      'buttons': buttons.map((b) => b.toJson()).toList(),
    };
  }
}

/// Pre-defined templates for Musaafir
class MusafirMessengerTemplates {
  /// Listing card template
  static MessengerGenericTemplate listingCard({
    required String title,
    required String subtitle,
    required String imageUrl,
    required String listingUrl,
    required String messagePayload,
  }) {
    return MessengerGenericTemplate(
      elements: [
        MessengerGenericElement(
          title: title,
          subtitle: subtitle,
          imageUrl: imageUrl,
          defaultAction: MessengerButton(
            type: MessengerButtonType.webUrl,
            title: 'View',
            url: listingUrl,
          ),
          buttons: [
            MessengerButton(
              type: MessengerButtonType.webUrl,
              title: 'View Listing',
              url: listingUrl,
            ),
            MessengerButton(
              type: MessengerButtonType.postback,
              title: 'Message Host',
              payload: messagePayload,
            ),
          ],
        ),
      ],
    );
  }

  /// Booking confirmation card
  static MessengerGenericTemplate bookingConfirmation({
    required String propertyName,
    required String propertyImageUrl,
    required String checkInDate,
    required String checkOutDate,
    required String confirmationNumber,
    required String bookingDetailsUrl,
  }) {
    return MessengerGenericTemplate(
      elements: [
        MessengerGenericElement(
          title: 'Booking Confirmed!',
          subtitle:
              '$propertyName\n$checkInDate - $checkOutDate\nConf: $confirmationNumber',
          imageUrl: propertyImageUrl,
          buttons: [
            MessengerButton(
              type: MessengerButtonType.webUrl,
              title: 'View Details',
              url: bookingDetailsUrl,
            ),
          ],
        ),
      ],
    );
  }

  /// Quick replies for common questions
  static List<MessengerQuickReply> commonQuickReplies() {
    return const [
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Check availability',
        payload: 'CHECK_AVAILABILITY',
      ),
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Pricing info',
        payload: 'PRICING_INFO',
      ),
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Contact host',
        payload: 'CONTACT_HOST',
      ),
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Help',
        payload: 'HELP',
      ),
    ];
  }

  /// Get started quick replies
  static List<MessengerQuickReply> getStartedQuickReplies() {
    return const [
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Browse listings',
        payload: 'BROWSE_LISTINGS',
      ),
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'My bookings',
        payload: 'MY_BOOKINGS',
      ),
      MessengerQuickReply(
        contentType: MessengerQuickReplyType.text,
        title: 'Become a host',
        payload: 'BECOME_HOST',
      ),
    ];
  }
}
