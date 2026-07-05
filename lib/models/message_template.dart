import 'package:intl/intl.dart';

import 'booking.dart';

/// Language a host sends their automated guest messages in.
enum MessageLanguage {
  en,
  bn;

  String toJsonValue() => switch (this) {
        en => 'en',
        bn => 'bn',
      };

  static MessageLanguage fromString(String? value) => switch (value) {
        'bn' => bn,
        _ => en,
      };

  /// Native label for the language selector.
  String get label => switch (this) {
        en => 'English',
        bn => 'বাংলা',
      };
}

/// When a scheduled message is sent, Airbnb-style.
enum MessageTemplateTrigger {
  /// Right after the host accepts a booking.
  bookingConfirmed,

  /// A few days before the guest arrives (see [MessageTemplate.leadDays]).
  checkIn,

  /// When the stay is completed.
  checkOut;

  String toJsonValue() => switch (this) {
        bookingConfirmed => 'booking_confirmed',
        checkIn => 'check_in',
        checkOut => 'check_out',
      };

  static MessageTemplateTrigger fromString(String value) => switch (value) {
        'booking_confirmed' => bookingConfirmed,
        'check_in' => checkIn,
        'check_out' => checkOut,
        _ => bookingConfirmed,
      };

  String get label => switch (this) {
        bookingConfirmed => 'Booking confirmed',
        checkIn => 'Before check-in',
        checkOut => 'After checkout',
      };

  String get description => switch (this) {
        bookingConfirmed => 'Sent right after you accept a booking',
        checkIn => 'Sent a few days before the guest arrives — great for '
            'directions and access details',
        checkOut => 'Sent when the stay is completed',
      };
}

/// A host-authored message sent automatically at a booking milestone.
///
/// The content supports variables that are filled per booking:
/// {{guest_name}}, {{listing_title}}, {{listing_address}}, {{check_in_date}},
/// {{check_out_date}}, {{duration}} (e.g. "2 hours" / "7 nights"),
/// {{nights}}, {{guest_count}}, {{host_name}}.
class MessageTemplate {
  const MessageTemplate({
    required this.hostId,
    required this.trigger,
    required this.content,
    this.enabled = true,
    this.leadDays = 2,
  });

  final String hostId;
  final MessageTemplateTrigger trigger;
  final String content;
  final bool enabled;

  /// How many days before check-in the [MessageTemplateTrigger.checkIn]
  /// message is sent. Ignored for other triggers.
  final int leadDays;

  /// Variables available in template content, for editor UI chips.
  static const variables = [
    '{{guest_name}}',
    '{{listing_title}}',
    '{{listing_address}}',
    '{{check_in_date}}',
    '{{check_out_date}}',
    '{{duration}}',
    '{{guest_count}}',
    '{{host_name}}',
  ];

  /// The out-of-the-box template every host starts with. Hosts can edit or
  /// disable it per trigger.
  factory MessageTemplate.defaultFor(
    String hostId,
    MessageTemplateTrigger trigger, {
    MessageLanguage language = MessageLanguage.en,
  }) {
    return MessageTemplate(
      hostId: hostId,
      trigger: trigger,
      content: defaultContentFor(trigger, language: language),
    );
  }

  /// The out-of-the-box message body for a [trigger] in a given [language].
  /// The Bangla variants mirror the English ones and MUST keep the same
  /// `{{placeholders}}`. Keep in sync with the SQL default in
  /// `send_pre_checkin_messages()` (migration 056).
  static String defaultContentFor(
    MessageTemplateTrigger trigger, {
    MessageLanguage language = MessageLanguage.en,
  }) {
    return switch (language) {
      MessageLanguage.en => _defaultContentEn(trigger),
      MessageLanguage.bn => _defaultContentBn(trigger),
    };
  }

  static String _defaultContentEn(MessageTemplateTrigger trigger) {
    switch (trigger) {
      case MessageTemplateTrigger.bookingConfirmed:
        return 'Hi {{guest_name}}, and thanks for your reservation!\n\n'
            'I wanted to confirm your reservation at {{listing_title}} '
            'starting on {{check_in_date}} for {{duration}} with '
            '{{guest_count}} guest(s).\n\n'
            'Please take a moment to go through the house rules. If you need '
            'any additional information, please do not hesitate to ask — I '
            'would be happy to answer any questions you may have.\n\n'
            'I will contact you again a few days before your arrival to give '
            'you some additional instructions for a smooth check-in.\n\n'
            'I look forward to hosting you!\n\n'
            'Thanks,\n{{host_name}}';
      case MessageTemplateTrigger.checkIn:
        return 'Hi {{guest_name}},\n\n'
            'Thanks again for booking at {{listing_title}}!\n\n'
            'Please find the details below for a smooth and seamless '
            'check-in on {{check_in_date}}.\n\n'
            'Address:\n{{listing_address}}\n\n'
            'I am sharing the exact map location below so you can find the '
            'place easily. Please let me know your expected arrival time, '
            'and feel free to reach out if you have any questions before '
            'your stay.\n\n'
            'I hope you will have an enjoyable stay at {{listing_title}}!\n\n'
            'Thanks,\n{{host_name}}';
      case MessageTemplateTrigger.checkOut:
        return 'Hi {{guest_name}},\n\n'
            'Thanks for staying at {{listing_title}} — I hope you enjoyed '
            'your visit! You are welcome back anytime.\n\n'
            'Safe travels!\n\n'
            'Thanks,\n{{host_name}}';
    }
  }

  static String _defaultContentBn(MessageTemplateTrigger trigger) {
    switch (trigger) {
      case MessageTemplateTrigger.bookingConfirmed:
        return 'হ্যালো {{guest_name}}, আপনার রিজার্ভেশনের জন্য ধন্যবাদ!\n\n'
            'আমি আপনার রিজার্ভেশনটি নিশ্চিত করছি — {{listing_title}}, '
            '{{check_in_date}} থেকে শুরু, {{duration}} সময়ের জন্য, '
            '{{guest_count}} জন অতিথির জন্য।\n\n'
            'অনুগ্রহ করে বাড়ির নিয়মগুলো একবার দেখে নিন। কোনো অতিরিক্ত তথ্যের '
            'প্রয়োজন হলে জানাতে দ্বিধা করবেন না — আপনার যেকোনো প্রশ্নের উত্তর '
            'দিতে আমি খুশি হব।\n\n'
            'আপনার আগমনের কয়েক দিন আগে সহজ চেক-ইনের জন্য আমি আবার কিছু '
            'নির্দেশনা পাঠাব।\n\n'
            'আপনাকে আতিথেয়তা জানানোর অপেক্ষায় রইলাম!\n\n'
            'ধন্যবাদ,\n{{host_name}}';
      case MessageTemplateTrigger.checkIn:
        return 'হ্যালো {{guest_name}},\n\n'
            '{{listing_title}}-এ বুকিং করার জন্য আবারও ধন্যবাদ!\n\n'
            '{{check_in_date}} তারিখে সহজ ও ঝামেলাহীন চেক-ইনের জন্য নিচের '
            'তথ্যগুলো দেখুন।\n\n'
            'ঠিকানা:\n{{listing_address}}\n\n'
            'জায়গাটি সহজে খুঁজে পেতে আমি নিচে সঠিক ম্যাপ লোকেশন শেয়ার করছি। '
            'অনুগ্রহ করে আপনার সম্ভাব্য আগমনের সময় জানাবেন, এবং থাকার আগে '
            'কোনো প্রশ্ন থাকলে নির্দ্বিধায় যোগাযোগ করবেন।\n\n'
            'আশা করি {{listing_title}}-এ আপনার থাকা আনন্দদায়ক হবে!\n\n'
            'ধন্যবাদ,\n{{host_name}}';
      case MessageTemplateTrigger.checkOut:
        return 'হ্যালো {{guest_name}},\n\n'
            '{{listing_title}}-এ থাকার জন্য ধন্যবাদ — আশা করি আপনার সময়টা '
            'ভালো কেটেছে! আপনি যেকোনো সময় আবার স্বাগত।\n\n'
            'শুভ যাত্রা!\n\n'
            'ধন্যবাদ,\n{{host_name}}';
    }
  }

  /// The content to actually send for [t] in [language]: an un-customized
  /// template (its content still equals a built-in default) follows the
  /// language; a hand-edited template is returned verbatim.
  static String resolveContent(MessageTemplate t, MessageLanguage language) {
    final content = t.content;
    final isKnownDefault =
        content == defaultContentFor(t.trigger, language: MessageLanguage.en) ||
            content == defaultContentFor(t.trigger, language: MessageLanguage.bn);
    return isKnownDefault
        ? defaultContentFor(t.trigger, language: language)
        : content;
  }

  MessageTemplate copyWith({
    String? content,
    bool? enabled,
    int? leadDays,
  }) {
    return MessageTemplate(
      hostId: hostId,
      trigger: trigger,
      content: content ?? this.content,
      enabled: enabled ?? this.enabled,
      leadDays: leadDays ?? this.leadDays,
    );
  }

  factory MessageTemplate.fromJson(Map<String, dynamic> json) {
    return MessageTemplate(
      hostId: json['host_id'] as String,
      trigger:
          MessageTemplateTrigger.fromString(json['trigger'] as String? ?? ''),
      content: json['content'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      leadDays: json['lead_days'] as int? ?? 2,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host_id': hostId,
      'trigger': trigger.toJsonValue(),
      'content': content,
      'enabled': enabled,
      'lead_days': leadDays,
    };
  }
}

/// Per-booking values used to fill a template's variables.
class TemplateContext {
  const TemplateContext({
    required this.guestName,
    required this.listingTitle,
    required this.listingAddress,
    required this.checkIn,
    required this.checkOut,
    required this.duration,
    required this.nights,
    required this.guestCount,
    required this.hostName,
  });

  factory TemplateContext.fromBooking(
    Booking booking, {
    required String hostName,
  }) {
    return TemplateContext(
      guestName: booking.tenantName,
      listingTitle: booking.listingTitle ?? 'your stay',
      // Booking only carries the city; the cron renderer swaps in the full
      // street address from the listings table when it sends pre-check-in.
      listingAddress:
          booking.listingCity ?? booking.listingTitle ?? 'your stay',
      checkIn: booking.effectiveCheckIn,
      checkOut: booking.effectiveCheckOut,
      duration: booking.durationLabel,
      nights: booking.effectiveCheckOut
          .difference(booking.effectiveCheckIn)
          .inDays
          .clamp(1, 1000),
      guestCount: booking.guestCount,
      hostName: hostName,
    );
  }

  final String guestName;
  final String listingTitle;
  final String listingAddress;
  final DateTime checkIn;
  final DateTime checkOut;

  /// Unit-aware length of stay: "2 hours" / "7 nights" / "1 month".
  final String duration;
  final int nights;
  final int guestCount;
  final String hostName;

  /// Replaces the supported {{variables}} in [template]. Unknown placeholders
  /// are left untouched so a typo stays visible to the host. Dates and the
  /// duration unit are localized to [language].
  String render(
    String template, {
    MessageLanguage language = MessageLanguage.en,
  }) {
    final dateFormat = language == MessageLanguage.bn
        ? DateFormat('EEEE, MMMM d', 'bn')
        : DateFormat('EEEE, MMMM d');
    final durationText = language == MessageLanguage.bn
        ? _localizeDurationBn(duration)
        : duration;

    return template
        .replaceAll('{{guest_name}}', guestName)
        .replaceAll('{{listing_title}}', listingTitle)
        .replaceAll('{{listing_address}}', listingAddress)
        .replaceAll('{{check_in_date}}', dateFormat.format(checkIn))
        .replaceAll('{{check_out_date}}', dateFormat.format(checkOut))
        .replaceAll('{{duration}}', durationText)
        .replaceAll('{{nights}}', '$nights')
        .replaceAll('{{guest_count}}', '$guestCount')
        .replaceAll('{{host_name}}', hostName);
  }

  /// Translates the English unit words in a duration label ("7 nights",
  /// "2 hours", "1 month") to Bangla, leaving the number as-is. Plural forms
  /// are replaced before singular so nothing is double-substituted.
  static String _localizeDurationBn(String duration) {
    return duration
        .replaceAll('nights', 'রাত')
        .replaceAll('night', 'রাত')
        .replaceAll('hours', 'ঘণ্টা')
        .replaceAll('hour', 'ঘণ্টা')
        .replaceAll('months', 'মাস')
        .replaceAll('month', 'মাস');
  }
}
