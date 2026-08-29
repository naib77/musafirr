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
  const HostVerificationBadges({super.key, required this.verifications});

  /// The flags as the database records them. Null while the lookup is still in
  /// flight — indistinguishable from "nothing verified" on purpose, since both
  /// mean there is no claim to make yet.
  final HostVerifications? verifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = verifications;
    if (v == null || !v.hasAny) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        if (v.phoneVerified) _badge(theme, 'Phone number'),
        if (v.identityVerified) _badge(theme, 'Identity verified'),
        if (v.addressVerified) _badge(theme, 'Address verified'),
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
