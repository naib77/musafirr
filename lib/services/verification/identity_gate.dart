import 'package:flutter/material.dart';

import '../../screens/verification/identity_verification_screen.dart';
import '../../widgets/modern_banner.dart';
import '../image_upload_service.dart';

/// The identity gate shared by the hosting and booking flows.
///
/// Policy lives here and nowhere else: *admin approval is required*. A user may
/// only proceed once an admin has approved their identity
/// (`profiles.verification_status == 'verified'`). Any other state routes them:
///   * `verified`            → proceed.
///   * `pending`             → already submitted; blocked, "under review".
///   * `none` / `rejected`   → push the upload screen so they can (re)submit.
///
/// Uploading no longer unlocks the action on its own — after submitting, the
/// user waits for an admin. If the rule ever changes, only [statusOf] and this
/// method change.
class IdentityGate {
  IdentityGate._();

  /// The user's identity verification status. Overridable in tests so the gate
  /// can be exercised without Supabase.
  static Future<String> Function(String userId) statusOf = (userId) =>
      ImageUploadService.instance.identityVerificationStatus(userId);

  /// Ensures the user's identity is admin-approved before a gated action.
  /// [reason] is a short phrase, e.g. "to publish a listing". Returns true only
  /// when the user is already verified; false otherwise (including right after a
  /// fresh submission, which now enters admin review rather than unlocking).
  static Future<bool> ensure(
    BuildContext context,
    String userId, {
    required String reason,
  }) async {
    final status = await statusOf(userId);
    if (status == 'verified') return true;
    if (!context.mounted) return false;

    if (status == 'pending') {
      ModernBanner.showInfo(
        context,
        'Your identity is under review. You can continue once an admin '
        'approves it.',
      );
      return false;
    }

    // 'none' or 'rejected' — let them (re)submit their documents.
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IdentityVerificationScreen(
          userId: userId,
          reason: reason,
        ),
      ),
    );

    if (submitted == true && context.mounted) {
      ModernBanner.showInfo(
        context,
        'Thanks! Your identity is now under review — an admin will approve it '
        'shortly.',
      );
    }
    return false;
  }
}
