import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/user.dart';
import 'package:musafir/models/user_role.dart';
import 'package:musafir/services/auth/auth_flow.dart';
import 'package:musafir/services/verification/identity_gate.dart';
import 'package:musafir/services/verification/publish_gate.dart';
import 'package:musafir/state/auth_state.dart';

/// See auth_flow_test for why this `implements` rather than `extends`.
///
/// [currentUser] is derived from [isLoggedIn] rather than set independently,
/// because the real notifier defines `isLoggedIn` AS `currentUser != null`.
/// A fake that lets the two disagree is not a weaker fake, it is a different
/// object — and PublishGate reads `currentUser!` on the strength of that
/// invariant.
class _FakeAuthState extends ChangeNotifier implements AuthStateNotifier {
  _FakeAuthState({this.signedIn = false});

  bool signedIn;

  @override
  bool get isLoggedIn => signedIn;

  @override
  User? get currentUser => signedIn
      ? const User(id: 'u1', name: 'Naib', role: UserRole.owner, isHost: true)
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpGate(
  WidgetTester tester,
  AuthStateNotifier authState, {
  required void Function(bool) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  onResult(await PublishGate.ensure(context, authState)),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Future<void> Function(BuildContext, AuthStateNotifier, String) presenter;
  late Future<String> Function(String) statusOf;
  setUp(() {
    presenter = AuthFlow.present;
    statusOf = IdentityGate.statusOf;
  });
  tearDown(() {
    AuthFlow.present = presenter;
    IdentityGate.statusOf = statusOf;
  });

  // These two cases are the reason PublishGate exists. CreateListingScreen is
  // pushed from three places and two of them — the host dashboard and the
  // profile screen — were bare Navigator.push calls with no checks at all, so
  // an account in either state below reached the publish form and could
  // publish. Migration 114 enforces the same rules in the listings INSERT
  // policy; these pin the client half.

  testWidgets('a signed-out visitor cannot reach the publish form',
      (tester) async {
    // Backs out of the login.
    AuthFlow.present = (_, __, ___) async {};
    var identityChecked = false;
    IdentityGate.statusOf = (_) async {
      identityChecked = true;
      return 'verified';
    };

    bool? result;
    await _pumpGate(tester, _FakeAuthState(), onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    // Order matters: no point asking an unknown person for their documents.
    expect(identityChecked, isFalse);
  });

  testWidgets('a signed-in but unverified host cannot reach the publish form',
      (tester) async {
    AuthFlow.present = (_, __, ___) async =>
        fail('already signed in — should not be asked to log in');
    IdentityGate.statusOf = (_) async => 'none';

    bool? result;
    await _pumpGate(tester, _FakeAuthState(signedIn: true),
        onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // IdentityGate pushed its upload screen, so the gate has not resolved yet
    // — matching identity_gate_test's own 'none' case.
    expect(result, isNull);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('a host whose verification is pending is told to wait',
      (tester) async {
    AuthFlow.present = (_, __, ___) async =>
        fail('already signed in — should not be asked to log in');
    IdentityGate.statusOf = (_) async => 'pending';

    bool? result;
    await _pumpGate(tester, _FakeAuthState(signedIn: true),
        onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  // NOT covered here: the allowed path. Once identity passes, the gate reads
  // AppSettingsService for the address-proof requirement, which needs a live
  // Supabase client — giving that its own seam is worth doing, but it would be
  // a change to AppSettingsService rather than to this gate, and the cases
  // above are the ones that were actually broken.
}
