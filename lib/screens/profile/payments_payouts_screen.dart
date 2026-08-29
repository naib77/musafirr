import 'package:flutter/material.dart';

import '../../models/disbursement.dart';
import '../../models/payment_record.dart';
import '../../models/payout_method.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import 'payout_methods_screen.dart';

/// Payments & payouts.
///
/// - Everyone sees their own **payment history** (what they paid for bookings),
///   read from the `payments` table (own-row RLS).
/// - Hosts additionally see a **payouts** summary — money earned (paid bookings)
///   and money still pending — reusing the same realized/pending definition as
///   the Earnings tab ([Booking.isEarnedRevenue] / [Booking.isPendingPayout]).
/// - Everyone sees **where their money goes** (their default payout method) and
///   **what has actually been sent** (the `disbursements` ledger, migration
///   100). Before that ledger existed this screen promised payouts were
///   "settled to your registered account" — an account the system had no
///   record of, and a settlement nothing tracked. Both halves are real now.
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
  late Future<List<Disbursement>> _disbursementsFuture;
  late Future<List<PayoutMethod>> _methodsFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    final userId = widget.authState.currentUser?.id;
    if (userId == null) {
      _paymentsFuture = Future.value(const []);
      _disbursementsFuture = Future.value(const []);
      _methodsFuture = Future.value(const []);
      return;
    }
    _paymentsFuture = widget.repository.fetchUserPayments(userId);
    _disbursementsFuture = widget.repository.fetchDisbursements(userId);
    _methodsFuture = widget.repository.fetchPayoutMethods(userId);
  }

  /// Re-reads the payout method after the user has been to manage them —
  /// otherwise the card still advertises an account they just removed.
  Future<void> _openPayoutMethods() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayoutMethodsScreen(
          repository: widget.repository,
          authState: widget.authState,
        ),
      ),
    );
    if (mounted) setState(_loadAll);
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
          _buildPayoutMethodCard(theme),
          const SizedBox(height: 24),
          _buildDisbursements(theme),
          const SizedBox(height: 24),
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
            'Earned reflects money collected from paid bookings. What has '
            'actually reached you is listed under Payouts received below.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Where the user's money goes. Deliberately shown to guests as well as
  /// hosts: a guest only discovers they need this at the worst possible
  /// moment — when a refund is owed — and asking for bank details mid-dispute
  /// is both slower and more suspicious-looking than having them on file.
  Widget _buildPayoutMethodCard(ThemeData theme) {
    return FutureBuilder<List<PayoutMethod>>(
      future: _methodsFuture,
      builder: (context, snapshot) {
        final methods = snapshot.data ?? const <PayoutMethod>[];
        // The default is what a payout would actually use, so it is the one
        // worth surfacing; the rest are one tap away.
        final primary = methods.where((m) => m.isDefault).firstOrNull ??
            (methods.isEmpty ? null : methods.first);

        final (icon, title, subtitle, tint) = switch (primary) {
          null => (
              Icons.add_card_rounded,
              'Add a payout account',
              'Tell us where to send your earnings and refunds',
              theme.colorScheme.primary,
            ),
          final m when m.status == PayoutMethodStatus.verified => (
              m.channel.icon,
              m.shortDescription,
              'Verified · ${m.accountName}',
              Colors.green.shade700,
            ),
          final m when m.status == PayoutMethodStatus.rejected => (
              Icons.error_rounded,
              m.shortDescription,
              m.rejectionReason ?? 'Rejected — add another account',
              theme.colorScheme.error,
            ),
          final m => (
              m.channel.icon,
              m.shortDescription,
              'Awaiting review — payouts start once approved',
              Colors.orange.shade800,
            ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payout method', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: tint.withValues(alpha: 0.12),
                  child: Icon(icon, size: 20, color: tint),
                ),
                title:
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openPayoutMethods,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Money the platform has actually sent. Hidden entirely when there is none,
  /// rather than showing an empty "Payouts received" heading — for a guest who
  /// has never been refunded, that heading is a question they didn't ask.
  Widget _buildDisbursements(ThemeData theme) {
    return FutureBuilder<List<Disbursement>>(
      future: _disbursementsFuture,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Disbursement>[];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payouts received', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Money we\'ve sent to your payout account.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final d in rows) _disbursementTile(theme, d),
          ],
        );
      },
    );
  }

  Widget _disbursementTile(ThemeData theme, Disbursement d) {
    final (statusColor, statusIcon) = switch (d.status) {
      DisbursementStatus.sent => (
          Colors.green.shade700,
          Icons.north_east_rounded
        ),
      DisbursementStatus.failed => (
          theme.colorScheme.error,
          Icons.error_rounded
        ),
      DisbursementStatus.pending => (
          Colors.orange.shade800,
          Icons.hourglass_top_rounded
        ),
    };

    // The destination is the whole point of the row: "we paid you" is not
    // useful without "…to this account", which is the first thing someone
    // checks when they think the money never arrived.
    final destination = d.method?.shortDescription ?? 'your payout account';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text('${d.kind.label} · $destination',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            _date(d.effectiveDate),
            if (d.reference != null) 'Ref ${d.reference}',
            if (d.status == DisbursementStatus.failed &&
                d.failureReason != null)
              d.failureReason!,
          ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(_money(d.amount, d.currency),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(d.status.label,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: statusColor)),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(
      ThemeData theme, String label, String value, Color color) {
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
                style:
                    theme.textTheme.labelSmall?.copyWith(color: statusColor)),
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
