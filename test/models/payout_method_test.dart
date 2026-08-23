import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/disbursement.dart';
import 'package:musafir/models/payout_method.dart';

/// These test the rules the DATABASE also enforces (migration 100's
/// `payout_methods_shape` check and `normalise_bd_msisdn`). Duplicating a rule
/// is normally a smell; here it is the point. The app validates first only so
/// the user gets a sentence instead of a Postgres error, and the two copies
/// are worth nothing if they disagree — so the cases below are deliberately
/// the same cases the constraint accepts and rejects.
void main() {
  group('normaliseBdMsisdn — one wallet must be one row', () {
    test('collapses every way a number gets typed', () {
      // If these produced different strings, one wallet would become several
      // rows, the duplicate index would never fire, and an admin would verify
      // the same account three times.
      for (final input in [
        '01712345678',
        '+8801712345678',
        '8801712345678',
        '+880 1712-345678',
        '01712-345678',
        '  01712 345678  ',
        '1712345678',
      ]) {
        expect(normaliseBdMsisdn(input), '01712345678', reason: input);
      }
    });

    test('leaves something unrecognisable alone for the validator to reject',
        () {
      // Not this function's job to decide; it must not invent a valid-looking
      // number out of a broken one.
      expect(normaliseBdMsisdn('12345'), '12345');
      expect(normaliseBdMsisdn('abc'), '');
    });

    test('does not rescue an invalid operator digit', () {
      // 012… is not a real BD mobile prefix. Stripping the 880 would make it
      // look like one.
      expect(normaliseBdMsisdn('8801212345678'), '8801212345678');
    });
  });

  group('wallet account numbers', () {
    for (final channel in [
      PayoutChannel.bkash,
      PayoutChannel.nagad,
      PayoutChannel.rocket,
    ]) {
      test('${channel.name} accepts a real number in any format', () {
        expect(validatePayoutAccountNumber(channel, '01712345678'), isNull);
        expect(validatePayoutAccountNumber(channel, '+8801912345678'), isNull);
      });

      test('${channel.name} rejects the near-misses people actually type', () {
        // Too short, too long, wrong prefix, wrong operator digit, empty.
        for (final bad in [
          '0171234567',
          '017123456789',
          '11712345678',
          '01212345678',
          '',
          '   '
        ]) {
          expect(validatePayoutAccountNumber(channel, bad), isNotNull,
              reason: '"$bad" must be refused');
        }
      });
    }

    test('every operator prefix 013-019 is accepted', () {
      // Bangladesh has reassigned prefixes before; refusing a live one would
      // silently lock those users out of being paid.
      for (var d = 3; d <= 9; d++) {
        expect(
          validatePayoutAccountNumber(PayoutChannel.bkash, '01${d}12345678'),
          isNull,
          reason: 'prefix 01$d',
        );
      }
    });
  });

  group('bank account numbers', () {
    test('accepts 6 to 20 digits, ignoring spaces and dashes', () {
      expect(validatePayoutAccountNumber(PayoutChannel.bank, '123456'), isNull);
      expect(
        validatePayoutAccountNumber(PayoutChannel.bank, '1234 5678 9012 3456'),
        isNull,
      );
      expect(
        validatePayoutAccountNumber(PayoutChannel.bank, '1' * 20),
        isNull,
      );
    });

    test('rejects too short and too long', () {
      expect(
          validatePayoutAccountNumber(PayoutChannel.bank, '12345'), isNotNull);
      expect(
          validatePayoutAccountNumber(PayoutChannel.bank, '1' * 21), isNotNull);
      expect(validatePayoutAccountNumber(PayoutChannel.bank, ''), isNotNull);
    });

    test('a bank account is not held to the mobile-number shape', () {
      // The one case that would break if the validator forgot to branch on
      // channel: a perfectly good 10-digit account number.
      expect(validatePayoutAccountNumber(PayoutChannel.bank, '0123456789'),
          isNull);
    });
  });

  group('account holder name', () {
    test('requires enough to check against an ID', () {
      expect(validatePayoutAccountName(''), isNotNull);
      expect(validatePayoutAccountName('  '), isNotNull);
      expect(validatePayoutAccountName('ab'), isNotNull);
      expect(validatePayoutAccountName('Md. Rahim Uddin'), isNull);
    });
  });

  group('routing number', () {
    test('is optional, but must be 9 digits when given', () {
      expect(validatePayoutRoutingNumber(''), isNull);
      expect(validatePayoutRoutingNumber('   '), isNull);
      expect(validatePayoutRoutingNumber('090261726'), isNull);
      expect(validatePayoutRoutingNumber('12345'), isNotNull);
      expect(validatePayoutRoutingNumber('1234567890'), isNotNull);
    });
  });

  group('masking', () {
    test('shows only the last four', () {
      expect(maskPayoutAccountNumber('01712345678'), '•••••••5678');
      expect(maskPayoutAccountNumber('12345678901234567890').endsWith('7890'),
          isTrue);
    });

    test('leaves a very short value alone rather than blanking it', () {
      expect(maskPayoutAccountNumber('1234'), '1234');
      expect(maskPayoutAccountNumber(''), '');
    });
  });

  group('PayoutMethod.fromJson', () {
    Map<String, dynamic> row(Map<String, dynamic> overrides) => {
          'id': 'pm-1',
          'user_id': 'u-1',
          'channel': 'bkash',
          'account_name': 'Md. Rahim Uddin',
          'account_number': '01712345678',
          'status': 'verified',
          'is_default': true,
          ...overrides,
        };

    test('parses a verified wallet', () {
      final m = PayoutMethod.fromJson(row(const {}));
      expect(m.channel, PayoutChannel.bkash);
      expect(m.status, PayoutMethodStatus.verified);
      expect(m.canReceivePayouts, isTrue);
      expect(m.shortDescription, 'bKash · •••••••5678');
    });

    test('an unreadable status is never treated as verified', () {
      // The failure that costs money: a status this build does not recognise
      // must not unlock a payout.
      for (final status in [null, 'none', 'PENDING', 'approved', '']) {
        final m = PayoutMethod.fromJson(row({'status': status}));
        expect(m.status, PayoutMethodStatus.pending, reason: '$status');
        expect(m.canReceivePayouts, isFalse, reason: '$status');
      }
    });

    test('a retired method cannot receive payouts even when verified', () {
      final m =
          PayoutMethod.fromJson(row({'retired_at': '2026-08-01T10:00:00Z'}));
      expect(m.isRetired, isTrue);
      expect(m.status, PayoutMethodStatus.verified);
      expect(m.canReceivePayouts, isFalse);
    });

    test('an unknown channel degrades instead of throwing', () {
      // A channel added server-side must not crash an older build looking at
      // its own list of accounts.
      final m = PayoutMethod.fromJson(row({'channel': 'upay'}));
      expect(m.channel, PayoutChannel.bank);
    });

    test('carries a rejection reason so the user can act on it', () {
      final m = PayoutMethod.fromJson(row({
        'status': 'rejected',
        'rejection_reason': 'Name does not match your NID',
      }));
      expect(m.status, PayoutMethodStatus.rejected);
      expect(m.rejectionReason, 'Name does not match your NID');
    });
  });

  group('Disbursement.fromJson', () {
    Map<String, dynamic> row(Map<String, dynamic> overrides) => {
          'id': 'd-1',
          'user_id': 'u-1',
          'payout_method_id': 'pm-1',
          'kind': 'host_payout',
          'status': 'sent',
          'amount': 8000,
          'currency': 'BDT',
          ...overrides,
        };

    test('parses a sent payout with its destination joined in', () {
      final d = Disbursement.fromJson(row({
        'sent_at': '2026-08-20T09:00:00Z',
        'reference': 'TRX9K2L',
        'payout_methods': {
          'id': 'pm-1',
          'user_id': 'u-1',
          'channel': 'bkash',
          'account_name': 'Md. Rahim Uddin',
          'account_number': '01712345678',
          'status': 'verified',
          'is_default': true,
        },
      }));
      expect(d.kind, DisbursementKind.hostPayout);
      expect(d.status, DisbursementStatus.sent);
      expect(d.amount, 8000);
      expect(d.reference, 'TRX9K2L');
      expect(d.method?.channel, PayoutChannel.bkash);
      expect(d.effectiveDate, isNotNull);
    });

    test('an absent joined method is normal, not an error', () {
      final d = Disbursement.fromJson(row(const {}));
      expect(d.method, isNull);
    });

    test('an unknown status never reads as paid', () {
      for (final status in [null, 'SENT', 'settled', '']) {
        expect(Disbursement.fromJson(row({'status': status})).status,
            DisbursementStatus.pending,
            reason: '$status');
      }
    });

    test('falls back to created_at when nothing was sent yet', () {
      final d = Disbursement.fromJson(row({
        'status': 'pending',
        'created_at': '2026-08-19T09:00:00Z',
      }));
      expect(d.sentAt, isNull);
      expect(d.effectiveDate, isNotNull);
    });
  });
}
