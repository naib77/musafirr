import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/contact_phone.dart';

/// 160: the stored shape is `+880…`, the same as `profiles.mobile` on live,
/// so `get_booking_contacts` can coalesce the two.
void main() {
  group('normalizeContactPhone', () {
    test('blank means no number', () {
      expect(normalizeContactPhone(null), isNull);
      expect(normalizeContactPhone('   '), isNull);
    });

    test('every spelling of a BD mobile lands on +8801…', () {
      for (final s in [
        '01711165212',
        '+8801711165212',
        '8801711165212',
        '1711165212',
        '017 1116 5212',
        '017-1116-5212',
      ]) {
        expect(normalizeContactPhone(s), '+8801711165212', reason: s);
      }
    });

    test('international numbers keep their plus', () {
      expect(normalizeContactPhone('+44 20 7946 0958'), '+442079460958');
    });

    test('refuses what is neither, with a message the form can show', () {
      for (final s in ['12345', '0123456789', '447946095', 'call me']) {
        expect(() => normalizeContactPhone(s), throwsFormatException,
            reason: s);
        expect(contactPhoneValidator(s), isNotNull, reason: s);
      }
      expect(contactPhoneValidator(''), isNull);
      expect(contactPhoneValidator('01711165212'), isNull);
    });
  });

  test('displayContactPhone shows the national spelling for BD', () {
    expect(displayContactPhone('+8801711165212'), '01711165212');
    expect(displayContactPhone('+442079460958'), '+442079460958');
  });

  group('normalizeContactPhones (162)', () {
    test('drops blanks and duplicates, keeps order', () {
      expect(
        normalizeContactPhones(
            ['01711165212', '', '  ', '+44 20 7946 0958', '+8801711165212']),
        ['+8801711165212', '+442079460958'],
      );
      expect(normalizeContactPhones(['', '']), isEmpty);
    });

    test('refuses a bad entry and more than the cap', () {
      expect(() => normalizeContactPhones(['01711165212', 'call me']),
          throwsFormatException);
      final six = [for (var i = 0; i < 6; i++) '0171116521$i'];
      expect(contactPhonesError(six),
          'Add at most $maxContactPhones contact numbers.');
      expect(contactPhonesError(six.take(5)), isNull);
    });
  });

  test('contactPhonesFromJson tolerates null and junk', () {
    expect(contactPhonesFromJson(null), isEmpty);
    expect(contactPhonesFromJson('x'), isEmpty);
    expect(
        contactPhonesFromJson(['+8801711165212', 3, null]), ['+8801711165212']);
  });
}
