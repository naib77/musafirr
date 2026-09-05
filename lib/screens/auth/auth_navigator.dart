import 'package:flutter/material.dart';

import '../../state/auth_state.dart';
import '../../state/otp_state.dart';
import 'otp_verification_screen.dart';
import 'phone_entry_screen.dart';
import 'profile_completion_screen.dart';

/// Auth screen type for navigation
enum AuthScreen {
  phoneEntry,
  otpVerification,
  profileCompletion,
}

/// Drives the three-step phone login: number → code → profile.
///
/// Lived inside `app.dart` as the `unauthenticated` arm of a top-level switch,
/// which made it the only thing an unregistered visitor could ever see. Now
/// that browsing is public it is also pushed as a route from
/// [AuthFlow.ensureSignedIn], so it lives here where both callers can reach it
/// without `app.dart` and the services layer importing each other.
///
/// It is deliberately not a [Navigator]: the step is owned by
/// [OtpStateNotifier], so a resend or a back-to-number transition is a state
/// change rather than a route, and the OTP state survives it.
class AuthNavigator extends StatefulWidget {
  const AuthNavigator({
    super.key,
    required this.authState,
    this.onCompleted,
    this.onDismiss,
    this.prompt,
  });

  final AuthStateNotifier authState;

  /// Called once login has fully succeeded.
  ///
  /// Null when this is the root of the app — there is nothing to pop, and
  /// `app.dart` rebuilds on the auth state change instead. Non-null when
  /// pushed as a route, where it is what closes the route and hands control
  /// back to the screen that asked for a login.
  final VoidCallback? onCompleted;

  /// Called when the visitor backs out without signing in. Non-null only for
  /// the pushed route: as the app root there is nowhere to go.
  ///
  /// Its presence is also what draws the close button, because the three
  /// screens below have no app bar of their own to hang one on.
  final VoidCallback? onDismiss;

  /// Why the visitor is being asked to log in, e.g. 'to reserve this stay'.
  ///
  /// Shown in place of the generic subtitle. A login prompt that arrives
  /// mid-task should say what it interrupted.
  final String? prompt;

  @override
  State<AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<AuthNavigator> {
  AuthScreen _currentScreen = AuthScreen.phoneEntry;
  final OtpStateNotifier _otpState = OtpStateNotifier();

  @override
  void initState() {
    super.initState();
    // Listen to OTP state changes to handle navigation
    _otpState.addListener(_onOtpStateChanged);
  }

  @override
  void dispose() {
    _otpState.removeListener(_onOtpStateChanged);
    _otpState.dispose();
    super.dispose();
  }

  void _onOtpStateChanged() {
    if (_otpState.currentStep == OtpFlowStep.complete) {
      // As the app root, `app.dart`'s ListenableBuilder swaps the tree on the
      // auth state change and there is nothing to do here. As a pushed route,
      // that rebuild leaves this route sitting on top of a now-signed-in app,
      // so it has to close itself.
      widget.onCompleted?.call();
      return;
    }
    setState(() {
      switch (_otpState.currentStep) {
        case OtpFlowStep.phoneEntry:
          _currentScreen = AuthScreen.phoneEntry;
          break;
        case OtpFlowStep.otpVerification:
          _currentScreen = AuthScreen.otpVerification;
          break;
        case OtpFlowStep.profileCompletion:
          _currentScreen = AuthScreen.profileCompletion;
          break;
        case OtpFlowStep.complete:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen;
    switch (_currentScreen) {
      case AuthScreen.phoneEntry:
        screen = PhoneEntryScreen(
          otpState: _otpState,
          prompt: widget.prompt,
        );
        break;

      case AuthScreen.otpVerification:
        screen = OtpVerificationScreen(otpState: _otpState);
        break;

      case AuthScreen.profileCompletion:
        screen = ProfileCompletionScreen(
          otpState: _otpState,
          authState: widget.authState,
        );
        break;
    }

    if (widget.onDismiss == null) return screen;

    // Overlaid rather than added to the screens themselves: all three build
    // their own Scaffold with no app bar, and giving each one a conditional
    // leading action would spread "am I a route or the app root?" across three
    // files.
    return Stack(
      children: [
        screen,
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Back to browsing',
                onPressed: widget.onDismiss,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
