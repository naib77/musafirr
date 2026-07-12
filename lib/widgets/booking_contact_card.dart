import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../models/booking_contacts.dart';
import '../repositories/musafir_repository.dart';
import 'modern_banner.dart';

/// Shows the counterparty's phone for a confirmed booking, with tap-to-call and
/// copy. A host viewer sees the guest's number; a guest viewer sees the host's.
/// Renders nothing until the (confirmed-booking-only) RPC returns a phone, so
/// it's safe to drop into any booking detail view unconditionally.
class BookingContactCard extends StatelessWidget {
  const BookingContactCard({
    super.key,
    required this.repository,
    required this.bookingId,
    required this.viewerIsHost,
  });

  final MusafirRepository repository;
  final String bookingId;

  /// True when the current user is the listing's host (show the guest); false
  /// when the current user is the guest (show the host).
  final bool viewerIsHost;

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri) && context.mounted) {
      ModernBanner.showError(context, 'Could not open the dialer.');
    }
  }

  Future<void> _copy(BuildContext context, String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) {
      ModernBanner.showInfo(context, 'Phone number copied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BookingContacts?>(
      future: repository.fetchBookingContacts(bookingId),
      builder: (context, snapshot) {
        final contacts = snapshot.data;
        if (contacts == null) return const SizedBox.shrink();

        final name = viewerIsHost ? contacts.guestName : contacts.hostName;
        final phone = viewerIsHost ? contacts.guestPhone : contacts.hostPhone;
        if (phone == null || phone.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final label = viewerIsHost ? 'Guest contact' : 'Host contact';

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_rounded, color: AppColors.success, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name != null && name.isNotEmpty ? '$name · $phone' : phone,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: () => _copy(context, phone),
                icon: const Icon(Icons.copy_rounded, size: 20),
              ),
              IconButton.filled(
                tooltip: 'Call',
                onPressed: () => _call(context, phone),
                icon: const Icon(Icons.call_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
