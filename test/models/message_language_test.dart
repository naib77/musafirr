import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:musafir/models/message_template.dart';
import 'package:musafir/services/messaging/booking_system_messages.dart';

Set<String> _placeholders(String s) =>
    RegExp(r'\{\{[a-z_]+\}\}').allMatches(s).map((m) => m.group(0)!).toSet();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('bn', null);
  });

  group('defaultContentFor', () {
    for (final trigger in MessageTemplateTrigger.values) {
      test(
          'has a Bangla variant that differs from English but keeps '
          'the same placeholders (${trigger.name})', () {
        final en = MessageTemplate.defaultContentFor(trigger,
            language: MessageLanguage.en);
        final bn = MessageTemplate.defaultContentFor(trigger,
            language: MessageLanguage.bn);

        expect(bn.trim(), isNotEmpty);
        expect(bn, isNot(equals(en)));
        expect(_placeholders(bn), equals(_placeholders(en)));
      });
    }
  });

  group('resolveContent', () {
    test('an un-customized default follows the target language', () {
      const trigger = MessageTemplateTrigger.bookingConfirmed;
      final enDefault = MessageTemplate(
        hostId: 'h',
        trigger: trigger,
        content: MessageTemplate.defaultContentFor(trigger),
      );

      expect(
        MessageTemplate.resolveContent(enDefault, MessageLanguage.bn),
        MessageTemplate.defaultContentFor(trigger,
            language: MessageLanguage.bn),
      );
      // A stored Bangla default also follows the flag (back to English here).
      final bnDefault = enDefault.copyWith(
        content: MessageTemplate.defaultContentFor(trigger,
            language: MessageLanguage.bn),
      );
      expect(
        MessageTemplate.resolveContent(bnDefault, MessageLanguage.en),
        MessageTemplate.defaultContentFor(trigger,
            language: MessageLanguage.en),
      );
    });

    test('a hand-edited template is returned verbatim regardless of language',
        () {
      const custom = MessageTemplate(
        hostId: 'h',
        trigger: MessageTemplateTrigger.checkOut,
        content: 'My own words, {{guest_name}}.',
      );
      expect(MessageTemplate.resolveContent(custom, MessageLanguage.bn),
          'My own words, {{guest_name}}.');
      expect(MessageTemplate.resolveContent(custom, MessageLanguage.en),
          'My own words, {{guest_name}}.');
    });
  });

  group('TemplateContext.render', () {
    final ctx = TemplateContext(
      guestName: 'Rahim',
      listingTitle: 'Sea View',
      listingAddress: 'Cox\'s Bazar',
      checkIn: DateTime(2026, 1, 5), // Monday, January 5
      checkOut: DateTime(2026, 1, 7),
      duration: '2 nights',
      nights: 2,
      guestCount: 3,
      hostName: 'Karim',
    );

    test('English renders English month and duration unit', () {
      final out = ctx.render('{{check_in_date}} · {{duration}}');
      expect(out, contains('January'));
      expect(out, contains('nights'));
    });

    test('Bangla localizes the month name and duration unit', () {
      final out = ctx.render(
        '{{check_in_date}} · {{duration}}',
        language: MessageLanguage.bn,
      );
      expect(out, contains('রাত')); // "nights", localized
      expect(out, isNot(contains('nights')));
      expect(out, isNot(contains('January'))); // date is Bangla, not English
    });
  });

  group('BookingSystemMessages', () {
    test('Bangla notices are non-empty and differ from English', () {
      expect(BookingSystemMessages.checkedIn(MessageLanguage.bn), isNotEmpty);
      expect(
        BookingSystemMessages.checkedIn(MessageLanguage.bn),
        isNot(equals(BookingSystemMessages.checkedIn(MessageLanguage.en))),
      );
      expect(
        BookingSystemMessages.cancelled(
            cancelledByHost: true, language: MessageLanguage.bn),
        isNot(equals(BookingSystemMessages.cancelled(
            cancelledByHost: true, language: MessageLanguage.en))),
      );
      expect(
        BookingSystemMessages.reservationConfirmed('X', MessageLanguage.bn),
        contains('X'),
      );
    });
  });
}
