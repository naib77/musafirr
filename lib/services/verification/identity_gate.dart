import 'package:flutter/material.dart';

import '../../screens/verification/identity_verification_screen.dart';
import '../image_upload_service.dart';

/// The one-time identity gate shared by the hosting and booking flows.
///
/// Policy lives here and nowhere else: *upload is enough*. If the user already
/// has an identity document on file the gated action proceeds immediately;
/// otherwise we push the upload screen and let them through only once the
/// document has been captured. If the rule ever changes (e.g. require admin
/// approval), only [hasDocument] and this method change.
class IdentityGate {
  IdentityGate._();

  /// Whether the user already has an identity document on file. Overridable in
  /// tests so the gate can be exercised without Supabase.
  static Future<bool> Function(String userId) hasDocument =
      (userId) => ImageUploadService.instance.hasIdentityDocument(userId);

  /// Ensures the user has verified identity before a gated action. [reason] is
  /// a short phrase shown on the upload screen, e.g. "to publish a listing".
  /// Returns true if the user may proceed, false if they backed out.
  static Future<bool> ensure(
    BuildContext context,
    String userId, {
    required String reason,
  }) async {
    if (await hasDocument(userId)) return true;
    if (!context.mounted) return false;

    final uploaded = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IdentityVerificationScreen(
          userId: userId,
          reason: reason,
        ),
      ),
    );
    return uploaded == true;
  }
}
