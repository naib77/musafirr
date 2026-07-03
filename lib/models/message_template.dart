import 'package:intl/intl.dart';

import 'booking.dart';

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
    MessageTemplateTrigger trigger,
  ) {
    return MessageTemplate(
      hostId: hostId,
      trigger: trigger,
      content: defaultContentFor(trigger),
    );
  }

  static String defaultContentFor(MessageTemplateTrigger trigger) {
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

  static final _dateFormat = DateFormat('EEEE, MMMM d');

  /// Replaces the supported {{variables}} in [template]. Unknown placeholders
  /// are left untouched so a typo stays visible to the host.
  String render(String template) {
    return template
        .replaceAll('{{guest_name}}', guestName)
        .replaceAll('{{listing_title}}', listingTitle)
        .replaceAll('{{listing_address}}', listingAddress)
        .replaceAll('{{check_in_date}}', _dateFormat.format(checkIn))
        .replaceAll('{{check_out_date}}', _dateFormat.format(checkOut))
        .replaceAll('{{duration}}', duration)
        .replaceAll('{{nights}}', '$nights')
        .replaceAll('{{guest_count}}', '$guestCount')
        .replaceAll('{{host_name}}', hostName);
  }
}
