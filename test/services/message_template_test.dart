import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/booking_status.dart';
import 'package:musafir/models/message_template.dart';

void main() {
  Booking createBooking({
    String tenantName = 'Plabon',
    int guestCount = 2,
    DateTime? startAt,
    DateTime? endAt,
    String unitLabel = 'night',
  }) {
    return Booking(
      id: 'booking_1',
      listingId: 'listing_1',
      tenantName: tenantName,
      startAt: startAt ?? DateTime(2026, 6, 30),
      endAt: endAt ?? DateTime(2026, 7, 7),
      totalPrice: 700.0,
      unitLabel: unitLabel,
      userId: 'guest_1',
      status: BookingStatus.confirmed,
      createdAt: DateTime(2026, 6, 1),
      guestCount: guestCount,
      listingTitle: 'New Luxury Studio Oasis',
    );
  }

  group('TemplateContext.fromBooking + render', () {
    test('fills every supported variable from the booking', () {
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Madhara Homes',
      );

      const template = 'Hi {{guest_name}}, your reservation at '
          '{{listing_title}} starts on {{check_in_date}} and ends on '
          '{{check_out_date}} — {{nights}} night(s), {{guest_count}} '
          'guest(s). — {{host_name}}';

      expect(
        context.render(template),
        'Hi Plabon, your reservation at New Luxury Studio Oasis starts on '
        'Tuesday, June 30 and ends on Tuesday, July 7 — 7 night(s), 2 '
        'guest(s). — Madhara Homes',
      );
    });

    test('leaves unknown placeholders untouched so mistakes stay visible', () {
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Host',
      );

      expect(context.render('Hello {{door_code}}'), 'Hello {{door_code}}');
    });

    test('{{duration}} respects the booking unit — hourly is not "nights"', () {
      final hourly = TemplateContext.fromBooking(
        createBooking(
          unitLabel: 'hour',
          startAt: DateTime(2026, 7, 3, 2, 39),
          endAt: DateTime(2026, 7, 3, 3, 39),
        ),
        hostName: 'Host',
      );
      expect(hourly.render('for {{duration}}'), 'for 1 hour');

      final weekly = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Host',
      );
      expect(weekly.render('for {{duration}}'), 'for 7 nights');
    });
  });

  group('default templates', () {
    test('booking-confirmed default renders an Airbnb-style welcome', () {
      final template = MessageTemplate.defaultFor(
        'host_1',
        MessageTemplateTrigger.bookingConfirmed,
      );
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Madhara Homes',
      );

      final rendered = context.render(template.content);

      expect(template.enabled, isTrue);
      expect(rendered, contains('Hi Plabon, and thanks for your reservation!'));
      expect(
          rendered,
          contains('your reservation at New Luxury Studio Oasis starting on '
              'Tuesday, June 30 for 7 nights with 2 guest(s)'));
      // Airbnb hosts set expectations up front: read the house rules, and
      // check-in instructions arrive separately a few days before arrival.
      expect(rendered, contains('house rules'));
      expect(rendered,
          contains('I will contact you again a few days before your arrival'));
      expect(rendered, contains('Madhara Homes'));
      expect(rendered, isNot(contains('{{')),
          reason: 'default templates must only use supported variables');
    });

    test('pre-check-in default reads like the Airbnb self-check-in message',
        () {
      final template = MessageTemplate.defaultFor(
        'host_1',
        MessageTemplateTrigger.checkIn,
      );
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Madhara Homes',
      );

      final rendered = context.render(template.content);

      expect(rendered, contains('Thanks again for booking at'));
      expect(rendered, contains('smooth and seamless check-in'));
      expect(rendered, contains('map location'),
          reason: 'the default announces the shared map pin that the cron '
              'sends right after this message');
      expect(rendered, isNot(contains('{{')));
    });

    test('{{listing_address}} renders from the booking city', () {
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Host',
      );
      expect(
        context.render('Address: {{listing_address}}'),
        isNot(contains('{{')),
      );
    });

    test('every default template renders without leftover placeholders', () {
      final context = TemplateContext.fromBooking(
        createBooking(),
        hostName: 'Host',
      );
      for (final trigger in MessageTemplateTrigger.values) {
        final template = MessageTemplate.defaultFor('host_1', trigger);
        expect(context.render(template.content), isNot(contains('{{')),
            reason: '${trigger.name} default has an unsupported variable');
      }
    });
  });
}
