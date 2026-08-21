import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/host_verifications.dart';

/// Reading the three flags off a `public_profiles` row. The direction that
/// matters is the unsafe one: a missing, null or malformed value must never
/// come out as verified.
void main() {
  group('reading a profile row', () {
    test('carries all three flags through', () {
      final v = HostVerifications.fromJson(const {
        'phone_verified': true,
        'identity_verified': true,
        'address_verified': true,
      });

      expect(v.phoneVerified, isTrue);
      expect(v.identityVerified, isTrue);
      expect(v.addressVerified, isTrue);
      expect(v.hasAny, isTrue);
    });

    test('keeps false false', () {
      final v = HostVerifications.fromJson(const {
        'phone_verified': false,
        'identity_verified': false,
        'address_verified': false,
      });

      expect(v.hasAny, isFalse);
    });

    test('a missing column is not a verification', () {
      // An older deployed build, or a view that has lost a column, must not
      // start awarding badges by omission.
      final v = HostVerifications.fromJson(const {'phone_verified': true});

      expect(v.phoneVerified, isTrue);
      expect(v.identityVerified, isFalse);
      expect(v.addressVerified, isFalse);
    });

    test('a null column is not a verification', () {
      final v = HostVerifications.fromJson(const {
        'phone_verified': null,
        'identity_verified': null,
        'address_verified': null,
      });

      expect(v.hasAny, isFalse);
    });

    test('an empty row verifies nothing', () {
      expect(HostVerifications.fromJson(const {}), HostVerifications.none);
    });
  });

  group('none', () {
    test('claims nothing', () {
      expect(HostVerifications.none.phoneVerified, isFalse);
      expect(HostVerifications.none.identityVerified, isFalse);
      expect(HostVerifications.none.addressVerified, isFalse);
      expect(HostVerifications.none.hasAny, isFalse);
    });
  });

  test('two identical sets of flags are equal', () {
    expect(
      const HostVerifications(phoneVerified: true),
      const HostVerifications(phoneVerified: true),
    );
    expect(
      const HostVerifications(phoneVerified: true),
      isNot(const HostVerifications(identityVerified: true)),
    );
  });
}
