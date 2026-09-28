import 'package:flutter/material.dart';

import '../../screens/auth/auth_navigator.dart';
import '../../state/auth_state.dart';

/// The one place that turns "you must be signed in" into a login.
///
/// Before browsing was public, nothing needed this: `app.dart` swapped the
/// whole tree for the login flow, so any screen that ran at all had a user.
/// What the screens grew instead were seven variations on a dead end — a
/// `debugPrint` on the wishlist heart, "Please log in to message the host.",
/// "Please log in to book" *after* the guest had picked dates and applied a
/// coupon, and two `if (userId != null)` wrappers that skipped their identity
/// check entirely rather than demanding a login. None of them could actually
/// get anyone to a login screen.
///
/// Deliberately shaped like [IdentityGate.ensure]: same `reason` string, same
/// "false means stop" contract, so the two read as a pair at a call site that
/// needs both —
///
/// ```dart
/// if (!await AuthFlow.ensureSignedIn(context, authState,
///     reason: 'to reserve this stay')) return;
/// if (!await IdentityGate.ensure(context, userId,
///     reason: 'to confirm your booking')) return;
/// ```
class AuthFlow {
  AuthFlow._();

  /// Presents the login flow and completes when it closes, signed in or not.
  ///
  /// Overridable so a call site's gating can be tested without Supabase, the
  /// OTP edge function or the three auth screens — the same seam
  /// [IdentityGate.statusOf] provides. Note that driving the real flow sends a
  /// real SMS, so a test must replace this.
  static Future<void> Function(
    BuildContext context,
    AuthStateNotifier authState,
    String reason,
  ) present = _pushLoginRoute;

  /// True if there is now a signed-in user; false if the visitor backed out.
  ///
  /// Returns immediately when already signed in, so it is cheap enough to put
  /// in front of any action without guarding the call.
  static Future<bool> ensureSignedIn(
    BuildContext context,
    AuthStateNotifier authState, {
    required String reason,
  }) async {
    if (authState.isLoggedIn) return true;

    await present(context, authState, reason);

    // Read the state rather than trusting the route's result: login can also
    // complete through a path that never pops with a value (the auth listener
    // firing first, for instance), and the only thing that matters here is
    // whether a session exists now.
    return authState.isLoggedIn;
  }

  static Future<void> _pushLoginRoute(
    BuildContext context,
    AuthStateNotifier authState,
    String reason,
  ) async {
    // A pushed route, not a tree swap, and that is the whole point. The screen
    // that asked — a listing detail with dates already chosen — stays mounted
    // underneath, so when this future completes the caller simply carries on.
    // That `await` IS the "return the visitor to what they were doing"
    // mechanism; there is no pending-intent store to keep in sync.
    //
    // It works because MainShell has no Navigator of its own (it is a
    // _LazyIndexedStack), so pushes land on the root navigator as siblings of
    // `home:` — and `app.dart` rebuilding `home:` on the auth change cannot
    // disturb a sibling route.
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        // Not a fullscreenDialog: on web that renders as a modal with no
        // affordance to leave, and the close button is already provided.
        builder: (routeContext) => AuthNavigator(
          authState: authState,
          prompt: reason,
          onCompleted: () => Navigator.of(routeContext).pop(),
          onDismiss: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }
}
