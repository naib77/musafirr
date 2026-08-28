import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/availability_block.dart';
import '../../models/booking.dart';
import '../../models/booking_status.dart';
import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../widgets/modern_banner.dart';

/// Lets a host mark date ranges on one listing as unavailable.
///
/// Before this existed the only way to say "I'm away next week" was to hide the
/// whole listing — which also hides it from search, drops it out of every
/// guest's results, and relies on the host remembering to un-hide it. A block
/// is scoped to dates and leaves the listing discoverable.
///
/// Booked ranges are shown alongside the blocks, read-only. They are the reason
/// a host most often can't block a range, so showing them here is what makes
/// the refusal ("decline that booking first") comprehensible instead of
/// arbitrary.
class ListingAvailabilityScreen extends StatefulWidget {
  const ListingAvailabilityScreen({
    super.key,
    required this.repository,
    required this.listing,
  });

  final MusafirRepository repository;
  final Listing listing;

  @override
  State<ListingAvailabilityScreen> createState() =>
      _ListingAvailabilityScreenState();
}

class _ListingAvailabilityScreenState extends State<ListingAvailabilityScreen> {
  List<AvailabilityBlock> _blocks = const [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final blocks =
          await widget.repository.listingAvailabilityBlocks(widget.listing.id);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// The listing's live bookings, from the cache the host already has — RLS
  /// admits a host to the bookings on their own listings, so these are present
  /// without an extra fetch.
  List<Booking> get _bookedRanges {
    // startAt/endAt, not checkIn/checkOut: the reserved interval is what
    // bookings_no_overlap keys on and therefore what actually blocks a host
    // from blocking. checkIn/checkOut are the nullable actual-arrival stamps.
    return widget.repository.bookings
        .where((b) => b.listingId == widget.listing.id && b.status.isActive)
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<void> _addBlock() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
      helpText: 'Select dates to block',
    );
    if (range == null || !mounted) return;

    final note = await _askForNote();
    if (!mounted) return;

    // The picker returns whole days; end the block at the START of the day
    // after the one the host picked, so a single-day selection blocks that
    // whole day. Half-open '[)' throughout, matching the schema — a block
    // ending at midnight does not eat a check-in at midnight.
    final startsAt =
        DateTime(range.start.year, range.start.month, range.start.day);
    final endsAt = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));

    setState(() => _saving = true);
    try {
      await widget.repository.blockListingDates(
        listingId: widget.listing.id,
        startsAt: startsAt,
        endsAt: endsAt,
        note: note,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ModernBanner.showSuccess(context, 'Dates blocked');
    } catch (e) {
      if (!mounted) return;
      // The server writes these sentences for the host — "You already have a
      // booking in these dates. Decline or cancel it first." — so show them
      // rather than flattening to a generic failure.
      ModernBanner.showError(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askForNote() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a note?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'e.g. Family visit',
            helperText: 'Only you can see this',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = note?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> _removeBlock(AvailabilityBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unblock these dates?'),
        content: Text(
          '${formatAvailabilityRange(block.startsAt, block.endsAt)} will be bookable again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.repository.unblockListingDates(block.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ModernBanner.showError(
          context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final booked = _bookedRanges;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Availability'),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                widget.listing.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Blocked dates stay off the calendar without hiding your '
                'listing from search.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (_loadError != null)
                _ErrorCard(message: _loadError!, onRetry: _load)
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _SectionHeader(
                    title: 'Blocked', count: _blocks.length, theme: theme),
                if (_blocks.isEmpty)
                  _EmptyHint(
                    text: 'No blocked dates. Your listing is bookable on every '
                        'free date.',
                    theme: theme,
                  )
                else
                  ..._blocks.map(
                    (b) => _BlockTile(
                      block: b,
                      label: formatAvailabilityRange(b.startsAt, b.endsAt),
                      onRemove: _saving ? null : () => _removeBlock(b),
                      theme: theme,
                    ),
                  ),
                const SizedBox(height: 24),
                _SectionHeader(
                    title: 'Booked', count: booked.length, theme: theme),
                if (booked.isEmpty)
                  _EmptyHint(text: 'No upcoming bookings.', theme: theme)
                else
                  ...booked.map(
                    (b) => _BookedTile(
                      label: formatAvailabilityRange(b.startAt, b.endAt),
                      guest: b.tenantName,
                      theme: theme,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving || _loading ? null : _addBlock,
        icon: const Icon(Icons.event_busy),
        label: const Text('Block dates'),
      ),
    );
  }
}

const _months = [
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

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

bool _isMidnight(DateTime d) =>
    d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;

/// Renders a half-open range for a host. Public so the off-by-one below has a
/// test rather than only a comment.
///
/// Two cases, and conflating them renders nonsense. A whole-day range is shown
/// by its last *occupied* day rather than its exclusive end — 2 Sep 00:00 →
/// 10 Sep 00:00 is "2–9 Sep", because 10 Sep is bookable again. But an hourly
/// booking is not whole-day, and subtracting a day from it runs the range
/// backwards ("1 Oct – 30 Sep"), so a sub-day range keeps its real endpoints
/// and shows times instead.
String formatAvailabilityRange(DateTime start, DateTime end) {
  final wholeDays = _isMidnight(start) && _isMidnight(end);

  if (!wholeDays) {
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    return sameDay
        ? '${_day(start)}, ${_time(start)}–${_time(end)}'
        : '${_day(start)} ${_time(start)} – ${_day(end)} ${_time(end)}';
  }

  final lastDay = end.subtract(const Duration(days: 1));
  if (start.year == lastDay.year &&
      start.month == lastDay.month &&
      start.day == lastDay.day) {
    return _day(start);
  }
  if (start.year == lastDay.year && start.month == lastDay.month) {
    return '${start.day}–${lastDay.day} ${_months[start.month - 1]} ${start.year}';
  }
  return '${_day(start)} – ${_day(lastDay)}';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.count, required this.theme});

  final String title;
  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.block,
    required this.label,
    required this.onRemove,
    required this.theme,
  });

  final AvailabilityBlock block;
  final String label;
  final VoidCallback? onRemove;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.event_busy, color: AppColors.warning),
        title: Text(label),
        subtitle: block.note == null ? null : Text(block.note!),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Unblock',
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class _BookedTile extends StatelessWidget {
  const _BookedTile(
      {required this.label, required this.guest, required this.theme});

  final String label;
  final String guest;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.event_available, color: AppColors.success),
        title: Text(label),
        subtitle: Text(guest.isEmpty ? 'Guest' : guest),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
