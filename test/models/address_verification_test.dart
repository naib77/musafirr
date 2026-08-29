import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/address_verification.dart';

/// The host's own view of their address submission. Two things matter here:
/// nothing may read as verified unless the database said so, and *submitted*
/// must stay distinct from *verified* — publishing waits on the first, the
/// badge on the second.
void main() {
  Map<String, dynamic> row({
    String? status,
    String? path = 'u1/address_proof_1.jpg',
    String? address = 'House 42, Road 7, Banani, Dhaka',
    String? reason,
  }) {
    return {
      'address_verification_status': status,
      'address_proof_path': path,
      'address_line': address,
      'address_rejection_reason': reason,
    };
  }

  group('reading the verdict', () {
    test('a verified address is verified', () {
      final v = AddressVerification.fromJson(row(status: 'verified'));

      expect(v.isVerified, isTrue);
      expect(v.isPending, isFalse);
      expect(v.status, AddressVerificationStatus.verified);
    });

    test('pending is awaiting a visit, not verified', () {
      final v = AddressVerification.fromJson(row(status: 'pending'));

      expect(v.isPending, isTrue);
      expect(v.isVerified, isFalse);
    });

    test('a rejection carries the reason the host must act on', () {
      final v = AddressVerification.fromJson(
        row(status: 'rejected', reason: 'Building number does not exist'),
      );

      expect(v.isRejected, isTrue);
      expect(v.reason, 'Building number does not exist');
      expect(v.isVerified, isFalse);
    });

    test('an unknown status is not a verification', () {
      // A newer database inventing a state must fail closed, not award a badge.
      final v = AddressVerification.fromJson(row(status: 'approved_probably'));

      expect(v.status, AddressVerificationStatus.none);
      expect(v.isVerified, isFalse);
    });

    test('a null status is not a verification', () {
      expect(
        AddressVerification.fromJson(row(status: null)).isVerified,
        isFalse,
      );
    });

    test('none claims nothing', () {
      expect(AddressVerification.none.isVerified, isFalse);
      expect(AddressVerification.none.isSubmitted, isFalse);
      expect(AddressVerification.none.status, AddressVerificationStatus.none);
    });
  });

  group('what unlocks publishing a listing', () {
    // The gate is SUBMITTED, deliberately — a physical visit takes days and a
    // host who has done their part must not be left unable to list.
    test('a pending submission is enough to publish', () {
      expect(
        AddressVerification.fromJson(row(status: 'pending')).isSubmitted,
        isTrue,
      );
    });

    test('so is a rejected one — the host resubmits, it does not lock them out',
        () {
      expect(
        AddressVerification.fromJson(row(status: 'rejected')).isSubmitted,
        isTrue,
      );
    });

    test('a document with no declared address is not a submission', () {
      // Status stays 'none' until the RPC runs, and the RPC requires both.
      expect(
        AddressVerification.fromJson(row(status: 'none')).isSubmitted,
        isFalse,
      );
    });

    test('a declared address with no document is not a submission either', () {
      expect(
        AddressVerification.fromJson(row(status: 'pending', path: null))
            .isSubmitted,
        isFalse,
      );
      expect(
        AddressVerification.fromJson(row(status: 'pending', path: ''))
            .isSubmitted,
        isFalse,
      );
    });
  });

  test('the declared address comes back so a resubmission is not retyped', () {
    final v = AddressVerification.fromJson(
      row(status: 'rejected', address: 'Flat 4B, House 42'),
    );

    expect(v.addressLine, 'Flat 4B, House 42');
  });
}
