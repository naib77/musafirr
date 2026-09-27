import 'package:flutter/material.dart';

import '../../screens/verification/verification_overview_screen.dart';
import '../../widgets/modern_banner.dart';
import 'face_verification_service.dart';

/// The identity gate shared by the hosting and booking flows.
///
/// Policy lives here and nowhere else: *admin approval is required*. A user may
/// only proceed once an admin has approved both their NID and face review
/// before proceeding. Any other state routes them:
///   * `verified`            → proceed.
///   * `pending`             → already submitted; blocked, "under review".
///   * `none` / `rejected` / `retry` → open the verification steps.
///
/// Uploading no longer unlocks the action on its own — after submitting, the
/// user waits for an admin. If the rule ever changes, only [statusOf] and this
/// method change.
class IdentityGate {
  IdentityGate._();

  /// The user's admin review status. Overridable in tests so the gate
  /// can be exercised without Supabase.
  static Future<String> Function(String userId) statusOf =
      (userId) => FaceVerificationService.instance.gateStatus(userId);

  /// Requires admin approval before a gated action.
  /// [reason] is a short phrase, e.g. "to publish a listing". Returns true only
  /// when the user is already admin-approved; false otherwise (including right after a
  /// fresh submission, which now enters admin review rather than unlocking).
  static Future<bool> ensure(
    BuildContext context,
    String userId, {
    required String reason,
  }) async {
    final status = await statusOf(userId);
    if (status == 'verified') return true;
    if (!context.mounted) return false;

    if (status == 'unavailable') {
      ModernBanner.showInfo(
          context, 'Could not check your review status. Please try again.');
      return false;
    }

    if (status == 'pending') {
      ModernBanner.showInfo(
        context,
        'Your submissions are under review. You can continue once an admin '
        'approves both.',
      );
      return false;
    }

    // 'none' or 'rejected' — let them (re)submit their verification evidence.
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VerificationOverviewScreen(
          userId: userId,
          reason: reason,
        ),
      ),
    );

    if (submitted == true && context.mounted) {
      final current = await statusOf(userId);
      if (current == 'verified') return true;
      if (!context.mounted || current != 'pending') return false;
      ModernBanner.showInfo(
        context,
        'Thanks! Your submissions are now awaiting admin review. We will update you '
        'when a decision is made.',
      );
    }
    return false;
  }
}
