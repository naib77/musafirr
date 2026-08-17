import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/external_launcher.dart';
import '../../models/booking.dart';
import '../../models/listing.dart';
import '../../models/listing_exact_address.dart';
import '../../repositories/musafir_repository.dart';
import '../../widgets/report_sheet.dart';

/// Safety center: one place with the emergency call, stay details to read to
/// a dispatcher, share-my-stay, safety tips, and the report entry point.
/// Opened generically from Profile, or with a [booking] from a trip /
/// reservation for stay-specific actions.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({
    super.key,
    required this.repository,
    this.booking,
  });

  final MusafirRepository repository;
  final Booking? booking;

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  MusafirRepository get repository => widget.repository;
  Booking? get booking => widget.booking;

  /// The stay's real street address and pin.
  ///
  /// `public.listings` only carries the area — enough for browsing, useless to
  /// an emergency dispatcher. A guest on this screen has a booking the host
  /// accepted, so `listing_addresses` RLS lets them have the real thing; this
  /// fetches it rather than reading the redacted line off the listing.
  ListingExactAddress? _exact;

  @override
  void initState() {
    super.initState();
    _loadExactAddress();
  }

  Future<void> _loadExactAddress() async {
    final b = booking;
    if (b == null) return;
    final exact = await repository.fetchListingExactAddress(b.listingId);
    if (exact == null || !mounted) return;
    setState(() => _exact = exact);
  }

  Listing? get _listing =>
      booking == null ? null : repository.getListingById(booking!.listingId);

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// The stay summary a guest can read out to an emergency dispatcher or
  /// send to a trusted contact.
  String _staySummary() {
    final b = booking!;
    final l = _listing;
    // Street address and exact pin where the server allowed them, falling back
    // to the area-level values so the summary is never empty while the fetch is
    // still in flight.
    final address = _exact?.address?.trim();
    final lat = _exact?.latitude ?? l?.latitude;
    final lng = _exact?.longitude ?? l?.longitude;

    final lines = <String>[
      'My stay (Musafir booking):',
      if (b.listingTitle != null) b.listingTitle!,
      if (address != null && address.isNotEmpty)
        address
      else if (l != null && l.address.isNotEmpty)
        l.address
      else if (b.listingCity != null)
        b.listingCity!,
      'From ${_formatDate(b.startAt)} to ${_formatDate(b.endAt)}',
      if (lat != null && lng != null && lat != 0 && lng != 0)
        'Map: https://maps.google.com/?q=$lat,$lng',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = _listing;

    return Scaffold(
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Emergency ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'In an emergency',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Call 999 — Bangladesh\'s national emergency service '
                  '(police, fire, ambulance). Free from any operator.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    // Synchronous inside the tap handler so web browsers
                    // treat it as user navigation (see external_launcher).
                    onPressed: () => openExternalUrl('tel:999'),
                    icon: const Icon(Icons.call),
                    label: const Text('Call 999'),
                  ),
                ),
              ],
            ),
          ),

          // ── Stay context: what to tell the dispatcher + share ──
          if (booking != null) ...[
            const SizedBox(height: 20),
            Text(
              'Your stay',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _staySummary(),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Share.share(
                  _staySummary(),
                  subject: 'My Musafir stay',
                ),
                icon: const Icon(Icons.share_location),
                label: const Text('Share my stay with a trusted contact'),
              ),
            ),
          ],

          // ── Tips ──
          const SizedBox(height: 24),
          Text(
            'Safety tips',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const _SafetyTip(
            icon: Icons.chat_bubble_outline,
            text: 'Keep all communication and payments inside the app — '
                'they create a record we can act on if something goes wrong.',
          ),
          const _SafetyTip(
            icon: Icons.share_location,
            text: 'Share your stay details with someone you trust before '
                'check-in, especially when travelling alone.',
          ),
          const _SafetyTip(
            icon: Icons.payments_outlined,
            text: 'Paying cash? Only pay at check-in, and make sure the host '
                'confirms it in the app so you have a receipt.',
          ),
          const _SafetyTip(
            icon: Icons.verified_user_outlined,
            text: 'Check the host\'s verification badge and reviews before '
                'booking. Hosts: your guests are identity-verified too.',
          ),

          // ── Report ──
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showReportSheet(
                context,
                repository: repository,
                bookingId: booking?.id,
                listingId: booking?.listingId,
                reportedUserId: listing?.hostId,
                subjectLabel: booking?.listingTitle,
              ),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report a problem'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SafetyTip extends StatelessWidget {
  const _SafetyTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
