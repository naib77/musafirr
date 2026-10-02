import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/trade_licence.dart';

/// The host-facing side of 152's optional trade licence. What matters most is
/// that nothing unexpected from the database ever reads as verified.
void main() {
  group('TradeLicenceStatus.fromName', () {
    test('reads the database values', () {
      expect(
          TradeLicenceStatus.fromName('pending'), TradeLicenceStatus.pending);
      expect(
          TradeLicenceStatus.fromName('verified'), TradeLicenceStatus.verified);
      expect(
          TradeLicenceStatus.fromName('rejected'), TradeLicenceStatus.rejected);
    });

    test('an unknown or missing value is none, never verified', () {
      expect(TradeLicenceStatus.fromName(null), TradeLicenceStatus.none);
      expect(TradeLicenceStatus.fromName('approved'), TradeLicenceStatus.none);
    });
  });

  group('summary', () {
    test('no licence says it is optional', () {
      expect(TradeLicence.none.summary, contains('Optional'));
      expect(TradeLicence.none.summary, contains('live either way'));
    });

    test('a rejection carries the admin\'s reason', () {
      final licence = TradeLicence.fromJson(
          {'status': 'rejected', 'rejection_reason': 'Blurry'});
      expect(licence.summary, 'Not accepted: Blurry');
      expect(const TradeLicence(status: TradeLicenceStatus.rejected).summary,
          contains('clearer copy'));
    });
  });

  test('refusal messages are chosen by hint, with a fallback', () {
    expect(tradeLicenceRefusalMessage('not_a_hotel'), contains('hotel'));
    expect(tradeLicenceRefusalMessage('document_invalid'), contains('5 MB'));
    expect(tradeLicenceRefusalMessage('something_new'), contains('try again'));
    expect(tradeLicenceRefusalMessage(null), contains('try again'));
  });
}
