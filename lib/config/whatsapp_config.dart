/// Configuration for WhatsApp Business API integration
class WhatsAppConfig {
  const WhatsAppConfig({
    required this.phoneNumberId,
    required this.businessAccountId,
    required this.accessToken,
    this.apiVersion = 'v18.0',
    this.webhookVerifyToken,
  });

  /// WhatsApp Business Phone Number ID
  final String phoneNumberId;

  /// WhatsApp Business Account ID
  final String businessAccountId;

  /// Facebook Graph API Access Token
  final String accessToken;

  /// Graph API version
  final String apiVersion;

  /// Webhook verification token
  final String? webhookVerifyToken;

  /// Base URL for WhatsApp Cloud API
  String get baseUrl => 'https://graph.facebook.com/$apiVersion';

  /// Messages endpoint
  String get messagesEndpoint => '$baseUrl/$phoneNumberId/messages';

  /// Media endpoint
  String get mediaEndpoint => '$baseUrl/$phoneNumberId/media';

  /// Template endpoint
  String get templateEndpoint =>
      '$baseUrl/$businessAccountId/message_templates';

  /// Development/stub configuration
  static const WhatsAppConfig stub = WhatsAppConfig(
    phoneNumberId: 'STUB_PHONE_NUMBER_ID',
    businessAccountId: 'STUB_BUSINESS_ACCOUNT_ID',
    accessToken: 'STUB_ACCESS_TOKEN',
    webhookVerifyToken: 'STUB_VERIFY_TOKEN',
  );

  /// Create from environment variables
  factory WhatsAppConfig.fromEnv() {
    return WhatsAppConfig(
      phoneNumberId: const String.fromEnvironment(
        'WHATSAPP_PHONE_NUMBER_ID',
        defaultValue: 'STUB_PHONE_NUMBER_ID',
      ),
      businessAccountId: const String.fromEnvironment(
        'WHATSAPP_BUSINESS_ACCOUNT_ID',
        defaultValue: 'STUB_BUSINESS_ACCOUNT_ID',
      ),
      accessToken: const String.fromEnvironment(
        'WHATSAPP_ACCESS_TOKEN',
        defaultValue: 'STUB_ACCESS_TOKEN',
      ),
      webhookVerifyToken: const String.fromEnvironment(
        'WHATSAPP_WEBHOOK_VERIFY_TOKEN',
        defaultValue: 'STUB_VERIFY_TOKEN',
      ),
    );
  }

  /// Check if this is a stub/development configuration
  bool get isStub => phoneNumberId == 'STUB_PHONE_NUMBER_ID';

  /// Authorization header
  Map<String, String> get headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };
}

/// WhatsApp message template configuration
class WhatsAppTemplate {
  const WhatsAppTemplate({
    required this.name,
    required this.language,
    this.components = const [],
  });

  final String name;
  final String language;
  final List<WhatsAppTemplateComponent> components;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'language': {'code': language},
      if (components.isNotEmpty)
        'components': components.map((c) => c.toJson()).toList(),
    };
  }
}

/// Template component (header, body, button)
class WhatsAppTemplateComponent {
  const WhatsAppTemplateComponent({
    required this.type,
    this.parameters = const [],
    this.subType,
    this.index,
  });

  final String type; // header, body, button
  final List<WhatsAppTemplateParameter> parameters;
  final String? subType; // for buttons: quick_reply, url
  final int? index; // button index

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (parameters.isNotEmpty)
        'parameters': parameters.map((p) => p.toJson()).toList(),
      if (subType != null) 'sub_type': subType,
      if (index != null) 'index': index,
    };
  }
}

/// Template parameter
class WhatsAppTemplateParameter {
  const WhatsAppTemplateParameter({
    required this.type,
    this.text,
    this.currency,
    this.dateTime,
    this.image,
    this.document,
    this.video,
  });

  final String type; // text, currency, date_time, image, document, video
  final String? text;
  final WhatsAppCurrency? currency;
  final WhatsAppDateTime? dateTime;
  final WhatsAppMedia? image;
  final WhatsAppMedia? document;
  final WhatsAppMedia? video;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'type': type};
    if (text != null) json['text'] = text;
    if (currency != null) json['currency'] = currency!.toJson();
    if (dateTime != null) json['date_time'] = dateTime!.toJson();
    if (image != null) json['image'] = image!.toJson();
    if (document != null) json['document'] = document!.toJson();
    if (video != null) json['video'] = video!.toJson();
    return json;
  }
}

/// Currency parameter
class WhatsAppCurrency {
  const WhatsAppCurrency({
    required this.code,
    required this.amount1000,
    this.fallbackValue,
  });

  final String code; // BDT, USD, etc.
  final int amount1000; // Amount * 1000
  final String? fallbackValue;

  Map<String, dynamic> toJson() {
    return {
      'currency_code': code,
      'amount_1000': amount1000,
      if (fallbackValue != null) 'fallback_value': fallbackValue,
    };
  }
}

/// DateTime parameter
class WhatsAppDateTime {
  const WhatsAppDateTime({this.fallbackValue});

  final String? fallbackValue;

  Map<String, dynamic> toJson() {
    return {
      if (fallbackValue != null) 'fallback_value': fallbackValue,
    };
  }
}

/// Media parameter
class WhatsAppMedia {
  const WhatsAppMedia({this.id, this.link});

  final String? id; // Media ID from WhatsApp
  final String? link; // Public URL

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (id != null) json['id'] = id;
    if (link != null) json['link'] = link;
    return json;
  }
}

/// Pre-defined templates for Musaafir
class MusafirWhatsAppTemplates {
  static const String defaultLanguage = 'en';

  /// Booking confirmation template
  static WhatsAppTemplate bookingConfirmation({
    required String guestName,
    required String propertyName,
    required String checkInDate,
    required String checkOutDate,
    required String bookingId,
  }) {
    return WhatsAppTemplate(
      name: 'booking_confirmation',
      language: defaultLanguage,
      components: [
        WhatsAppTemplateComponent(
          type: 'body',
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: guestName),
            WhatsAppTemplateParameter(type: 'text', text: propertyName),
            WhatsAppTemplateParameter(type: 'text', text: checkInDate),
            WhatsAppTemplateParameter(type: 'text', text: checkOutDate),
            WhatsAppTemplateParameter(type: 'text', text: bookingId),
          ],
        ),
      ],
    );
  }

  /// Booking reminder template
  static WhatsAppTemplate bookingReminder({
    required String guestName,
    required String propertyName,
    required String checkInDate,
    required String checkInTime,
  }) {
    return WhatsAppTemplate(
      name: 'booking_reminder',
      language: defaultLanguage,
      components: [
        WhatsAppTemplateComponent(
          type: 'body',
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: guestName),
            WhatsAppTemplateParameter(type: 'text', text: propertyName),
            WhatsAppTemplateParameter(type: 'text', text: checkInDate),
            WhatsAppTemplateParameter(type: 'text', text: checkInTime),
          ],
        ),
      ],
    );
  }

  /// Payment received template
  static WhatsAppTemplate paymentReceived({
    required String hostName,
    required String amount,
    required String propertyName,
    required String guestName,
  }) {
    return WhatsAppTemplate(
      name: 'payment_received',
      language: defaultLanguage,
      components: [
        WhatsAppTemplateComponent(
          type: 'body',
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: hostName),
            WhatsAppTemplateParameter(type: 'text', text: amount),
            WhatsAppTemplateParameter(type: 'text', text: propertyName),
            WhatsAppTemplateParameter(type: 'text', text: guestName),
          ],
        ),
      ],
    );
  }

  /// New message notification template
  static WhatsAppTemplate newMessage({
    required String recipientName,
    required String senderName,
  }) {
    return WhatsAppTemplate(
      name: 'new_message',
      language: defaultLanguage,
      components: [
        WhatsAppTemplateComponent(
          type: 'body',
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: recipientName),
            WhatsAppTemplateParameter(type: 'text', text: senderName),
          ],
        ),
      ],
    );
  }

  /// Review request template
  static WhatsAppTemplate reviewRequest({
    required String guestName,
    required String propertyName,
    required String reviewLink,
  }) {
    return WhatsAppTemplate(
      name: 'review_request',
      language: defaultLanguage,
      components: [
        WhatsAppTemplateComponent(
          type: 'body',
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: guestName),
            WhatsAppTemplateParameter(type: 'text', text: propertyName),
          ],
        ),
        WhatsAppTemplateComponent(
          type: 'button',
          subType: 'url',
          index: 0,
          parameters: [
            WhatsAppTemplateParameter(type: 'text', text: reviewLink),
          ],
        ),
      ],
    );
  }
}
