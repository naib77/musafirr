import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/host_verifications.dart';
import 'package:musafir/widgets/host_verification_badges.dart';

/// The trust badges under "Hosted by …". Every badge is a claim about a real
/// person, so the only thing that may put one on screen is a true flag from
/// the database — these tests exist to keep it that way.
void main() {
  Future<void> pumpBadges(
    WidgetTester tester,
    HostVerifications? verifications,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HostVerificationBadges(verifications: verifications),
        ),
      ),
    );
  }

  final phone = find.text('Phone number');
  final identity = find.text('Identity verified');
  final address = find.text('Address verified');

  group('what the strip claims', () {
    testWidgets('a fully verified host earns all three', (tester) async {
      await pumpBadges(
        tester,
        const HostVerifications(
          phoneVerified: true,
          identityVerified: true,
          addressVerified: true,
        ),
      );

      expect(phone, findsOneWidget);
      expect(identity, findsOneWidget);
      expect(address, findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    });

    testWidgets('each flag brings only its own badge', (tester) async {
      await pumpBadges(
        tester,
        const HostVerifications(phoneVerified: true),
      );

      expect(phone, findsOneWidget);
      expect(identity, findsNothing);
      expect(address, findsNothing);
    });

    testWidgets('an unverified credential is not shown at all, not greyed out',
        (tester) async {
      // Advertising what a host hasn't done belongs nowhere on a page selling
      // their place — and a ticked-but-grey badge reads as verified anyway.
      await pumpBadges(
        tester,
        const HostVerifications(identityVerified: true),
      );

      expect(identity, findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(1));
    });

    testWidgets('a host with nothing verified gets no strip', (tester) async {
      await pumpBadges(tester, HostVerifications.none);

      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('nothing is claimed while the lookup is still in flight',
        (tester) async {
      await pumpBadges(tester, null);

      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('email is never offered as a verification', (tester) async {
      // Email confirmation isn't part of onboarding — phone OTP is — so the
      // badge it used to show was pure decoration. Address proof replaced it.
      await pumpBadges(
        tester,
        const HostVerifications(
          phoneVerified: true,
          identityVerified: true,
          addressVerified: true,
        ),
      );

      expect(find.text('Email'), findsNothing);
      expect(find.textContaining('Email'), findsNothing);
    });
  });
}
