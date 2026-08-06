import 'package:flutter/material.dart';

import '../../models/payment_record.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';

/// Payments & payouts.
///
/// - Everyone sees their own **payment history** (what they paid for bookings),
///   read from the `payments` table (own-row RLS).
/// - Hosts additionally see a **payouts** summary — money earned (paid bookings)
///   and money still pending — reusing the same realized/pending definition as
///   the Earnings tab ([Booking.isEarnedRevenue] / [Booking.isPendingPayout]).
class PaymentsPayoutsScreen extends StatefulWidget {
  const PaymentsPayoutsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<PaymentsPayoutsScreen> createState() => _PaymentsPayoutsScreenState();
}

class _PaymentsPayoutsScreenState extends State<PaymentsPayoutsScreen> {
  late Future<List<PaymentRecord>> _paymentsFuture;

  @override
  void initState() {
    super.initState();
    final userId = widget.authState.currentUser?.id;
    _paymentsFuture = userId == null
        ? Future.value(const [])
        : widget.repository.fetchUserPayments(userId);
  }

  String _money(num amount, [String currency = 'BDT']) {
    final symbol = currency == 'BDT' ? '৳' : '$currency ';
    return '$symbol${amount.toStringAsFixed(0)}';
  }

  /// Friendly label for a gateway card_type like 'BKASH-BKash' or 'cash'.
  String _method(PaymentRecord p) {
    if (p.isCash) return 'Cash';
    final m = p.method;
    if (m == null || m.isEmpty) return 'Card';
    final parts = m.split('-');
    return parts.length > 1 ? parts.last : m;
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.authState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments & payouts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user?.isHost ?? false) ...[
            _buildPayoutSummary(theme, user!.id),
            const SizedBox(height: 24),
          ],
          Text('Your payments', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Payments you\'ve made for bookings.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<PaymentRecord>>(
            future: _paymentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final payments = snapshot.data ?? const [];
              if (payments.isEmpty) {
                return _emptyPayments(theme);
              }
              return Column(
                children: [for (final p in payments) _paymentTile(theme, p)],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutSummary(ThemeData theme, String userId) {
    // Reuse the Earnings tab's realized/pending definition so the numbers agree.
    final hostListingIds = widget.repository.listings
        .where((l) => l.hostId == userId)
        .map((l) => l.id)
        .toSet();
    final hostBookings = widget.repository.bookings
        .where((b) => hostListingIds.contains(b.listingId))
        .toList();
    final earned = hostBookings
        .where((b) => b.isEarnedRevenue)
        .fold<double>(0, (s, b) => s + b.totalPrice);
    final pending = hostBookings
        .where((b) => b.isPendingPayout)
        .fold<double>(0, (s, b) => s + b.totalPrice);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payouts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                    theme, 'Earned', _money(earned), theme.colorScheme.primary),
              ),
              Expanded(
                child: _summaryStat(theme, 'Pending', _money(pending),
                    theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Earned reflects money collected from paid bookings. Payouts for '
            'completed stays are settled to your registered account; contact '
            'support for payout questions.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(ThemeData theme, String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _paymentTile(ThemeData theme, PaymentRecord p) {
    // Listing title from the user's own bookings cache, if present.
    String? listingTitle;
    for (final b in widget.repository.bookings) {
      if (b.id == p.bookingId) {
        listingTitle = b.listingTitle;
        break;
      }
    }
    final (statusColor, statusIcon) = switch (p.status) {
      'paid' => (Colors.green.shade700, Icons.check_circle_rounded),
      'failed' => (Colors.red.shade700, Icons.error_rounded),
      'refunded' => (Colors.blueGrey.shade600, Icons.undo_rounded),
      _ => (Colors.orange.shade700, Icons.hourglass_top_rounded),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(listingTitle ?? 'Booking payment',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_method(p)} · ${_date(p.effectiveDate)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(p.amount, p.currency),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(p.status,
                style: theme.textTheme.labelSmall?.copyWith(color: statusColor)),
          ],
        ),
      ),
    );
  }

  Widget _emptyPayments(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 44, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No payments yet',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
