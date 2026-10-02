import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/host_verifications.dart';

/// The host's trust badges on a listing page: one tick per thing the host has
/// actually had verified.
///
/// Only earned badges are drawn. Showing "Phone number" greyed out, or with a
/// cross, would advertise what a host has *not* done on a page whose job is to
/// sell their place — and an all-badges-always strip (which is what this
/// replaced) is worse still, because it claims verifications that never
/// happened.
///
/// Its own widget so it can be tested: [ListingDetailScreen] can't be built in
/// a test at all (it needs a concrete repository wired to Supabase), and "does
/// the right badge appear for the right flag" is exactly what a test should
/// pin down.
class HostVerificationBadges extends StatelessWidget {
  const HostVerificationBadges({
    super.key,
    required this.verifications,
    this.licensedHotel = false,
  });

  /// The flags as the database records them. Null while the lookup is still in
  /// flight — indistinguishable from "nothing verified" on purpose, since both
  /// mean there is no claim to make yet.
  final HostVerifications? verifications;

  /// The listing's own credential, not the host's: an admin verified this
  /// hotel's optional trade licence (152). Drawn in the same strip because a
  /// guest reads it the same way, and only for a hotel (the RPC says so).
  final bool licensedHotel;

  /// Whether the strip draws anything at all.
  static bool showsAny(HostVerifications? v, {bool licensedHotel = false}) =>
      licensedHotel || (v?.hasAny ?? false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = verifications;
    if (!showsAny(v, licensedHotel: licensedHotel)) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        if (v?.phoneVerified ?? false) _badge(theme, 'Phone number'),
        if (v?.identityVerified ?? false) _badge(theme, 'Identity verified'),
        if (v?.addressVerified ?? false) _badge(theme, 'Address verified'),
        if (licensedHotel) _badge(theme, 'Licensed hotel'),
      ],
    );
  }

  Widget _badge(ThemeData theme, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 16, color: AppColors.success),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
