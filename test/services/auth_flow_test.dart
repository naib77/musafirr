import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/auth/auth_flow.dart';
import 'package:musafir/state/auth_state.dart';

/// An auth state whose signed-in-ness the test drives directly.
///
/// `implements`, not `extends`, matching the fake in
/// host_dashboard_availability_card_test: [AuthStateNotifier]'s constructor
/// calls `_initializeAuthState`, which reaches `Supabase.instance` and asserts
/// in a test environment.
///
/// Nothing here touches the network, and it must not: a real login goes
/// through the `send-otp` edge function, which would try to text a phone
/// number that isn't ours.
class _FakeAuthState extends ChangeNotifier implements AuthStateNotifier {
  _FakeAuthState({this.signedIn = false});

  bool signedIn;

  @override
  bool get isLoggedIn => signedIn;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Pumps a button that runs [AuthFlow.ensureSignedIn] and records its result.
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
              onPressed: () async {
                final ok = await AuthFlow.ensureSignedIn(
                  context,
                  authState,
                  reason: 'to test',
                );
                onResult(ok);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Future<void> Function(BuildContext, AuthStateNotifier, String) original;
  setUp(() => original = AuthFlow.present);
  tearDown(() => AuthFlow.present = original);

  testWidgets('a signed-in user is not asked to log in again', (tester) async {
    var presented = false;
    AuthFlow.present = (_, __, ___) async => presented = true;

    bool? result;
    await _pumpGate(tester, _FakeAuthState(signedIn: true),
        onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    // Cheap enough to put in front of any action precisely because of this.
    expect(presented, isFalse);
  });

  testWidgets('a visitor who logs in gets a true, so the action continues',
      (tester) async {
    final auth = _FakeAuthState();
    // Stands in for the OTP flow completing: the route closes and a session
    // now exists.
    AuthFlow.present = (_, __, ___) async => auth.signedIn = true;

    bool? result;
    await _pumpGate(tester, auth, onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('a visitor who backs out gets a false, so the action stops',
      (tester) async {
    final auth = _FakeAuthState();
    // The route closed without signing in.
    AuthFlow.present = (_, __, ___) async {};

    bool? result;
    await _pumpGate(tester, auth, onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('the reason reaches the login screen', (tester) async {
    String? seen;
    AuthFlow.present = (_, __, reason) async => seen = reason;

    await _pumpGate(tester, _FakeAuthState(), onResult: (_) {});
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // A login wall that appears mid-task has to say what it interrupted;
    // PhoneEntryScreen renders this as "Log in <reason>".
    expect(seen, 'to test');
  });

  testWidgets('the result is read from the auth state, not the route',
      (tester) async {
    final auth = _FakeAuthState();
    // Login can complete through a path that never pops with a value — the
    // auth listener firing before the route closes, for instance. Only whether
    // a session exists afterwards matters, so a present() that reports nothing
    // must still yield true.
    AuthFlow.present = (_, __, ___) async {
      auth.signedIn = true;
      return;
    };

    bool? result;
    await _pumpGate(tester, auth, onResult: (r) => result = r);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
