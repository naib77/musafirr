import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/update/app_update_decision.dart';

void main() {
  group('minSupportedVersionCodeFromRaw', () {
    test('absent, blank or unparseable means force nobody', () {
      expect(minSupportedVersionCodeFromRaw(null), kNoForcedUpdate);
      expect(minSupportedVersionCodeFromRaw(''), kNoForcedUpdate);
      expect(minSupportedVersionCodeFromRaw('   '), kNoForcedUpdate);
      expect(minSupportedVersionCodeFromRaw('soon'), kNoForcedUpdate);
      expect(minSupportedVersionCodeFromRaw('2.0'), kNoForcedUpdate);
    });

    test('reads a whole number, trimmed', () {
      expect(minSupportedVersionCodeFromRaw('7'), 7);
      expect(minSupportedVersionCodeFromRaw('  7  '), 7);
      expect(minSupportedVersionCodeFromRaw('0'), kNoForcedUpdate);
    });

    test('a value outside Play\'s range forces nobody, it does not clamp', () {
      // Clamping a typo would leave a floor the admin never typed in force.
      expect(minSupportedVersionCodeFromRaw('-1'), kNoForcedUpdate);
      expect(minSupportedVersionCodeFromRaw('2100000001'), kNoForcedUpdate);
      expect(
          minSupportedVersionCodeFromRaw('$kMaxVersionCode'), kMaxVersionCode);
    });
  });

  group('installedVersionCodeFromRaw', () {
    test('unparseable is 0, which means "unknown"', () {
      // buildNumber is an empty string on web, and has been seen to carry a
      // version NAME on locally built APKs.
      expect(installedVersionCodeFromRaw(null), 0);
      expect(installedVersionCodeFromRaw(''), 0);
      expect(installedVersionCodeFromRaw('0.1.0'), 0);
      expect(installedVersionCodeFromRaw('-3'), 0);
    });

    test('reads the versionCode', () {
      expect(installedVersionCodeFromRaw('2'), 2);
      expect(installedVersionCodeFromRaw(' 2 '), 2);
    });
  });

  group('appUpdateActionFor', () {
    AppUpdateAction decide({
      bool updateAvailable = true,
      bool flexibleAllowed = true,
      bool immediateAllowed = true,
      int installedVersionCode = 5,
      int minSupportedVersionCode = kNoForcedUpdate,
    }) =>
        appUpdateActionFor(
          updateAvailable: updateAvailable,
          flexibleAllowed: flexibleAllowed,
          immediateAllowed: immediateAllowed,
          installedVersionCode: installedVersionCode,
          minSupportedVersionCode: minSupportedVersionCode,
        );

    test('no update on Play means do nothing, however old the build is', () {
      // The load-bearing rule. Forcing an update Play cannot supply is a flow
      // that never completes, i.e. an app nobody can open — and the fix would
      // be a release the locked-out users could not reach.
      expect(
        decide(
          updateAvailable: false,
          installedVersionCode: 1,
          minSupportedVersionCode: 9999,
        ),
        AppUpdateAction.none,
      );
    });

    test('a build below the floor is blocked', () {
      expect(
        decide(installedVersionCode: 4, minSupportedVersionCode: 5),
        AppUpdateAction.immediate,
      );
    });

    test('the floor is inclusive: a build AT it is current', () {
      expect(
        decide(installedVersionCode: 5, minSupportedVersionCode: 5),
        AppUpdateAction.flexible,
      );
    });

    test('below the floor but Play refuses immediate: offer, do not give up',
        () {
      expect(
        decide(
          immediateAllowed: false,
          installedVersionCode: 4,
          minSupportedVersionCode: 5,
        ),
        AppUpdateAction.flexible,
      );
      expect(
        decide(
          flexibleAllowed: false,
          immediateAllowed: false,
          installedVersionCode: 4,
          minSupportedVersionCode: 5,
        ),
        AppUpdateAction.none,
      );
    });

    test('an unknown installed version never forces', () {
      // 0 < any floor, so without the guard an unreadable version would read
      // as "ancient" and block the app every time.
      expect(
        decide(installedVersionCode: 0, minSupportedVersionCode: 5),
        AppUpdateAction.flexible,
      );
    });

    test('the default floor forces nobody', () {
      expect(
        decide(installedVersionCode: 1),
        AppUpdateAction.flexible,
      );
    });

    test('a routine update is an offer and never a block', () {
      // Negative control for the branch above: with only the immediate flow
      // available and no floor in force, the answer is still to leave it to
      // Play's own background updater rather than seize the screen.
      expect(
        decide(flexibleAllowed: false),
        AppUpdateAction.none,
      );
      expect(decide(), AppUpdateAction.flexible);
    });
  });
}
