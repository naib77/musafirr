import 'package:flutter/material.dart';

import '../../models/booking.dart';

/// Screen for hosts to submit a review for a guest.
/// Includes single overall rating and optional text comment.
class HostReviewScreen extends StatefulWidget {
  const HostReviewScreen({
    super.key,
    required this.booking,
    required this.onSubmit,
  });

  final Booking booking;
  final void Function(double rating, String? comment) onSubmit;

  @override
  State<HostReviewScreen> createState() => _HostReviewScreenState();
}

class _HostReviewScreenState extends State<HostReviewScreen> {
  final _commentController = TextEditingController();

  double _rating = 5.0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _isSubmitting = true);

    final comment = _commentController.text.trim();
    widget.onSubmit(_rating, comment.isNotEmpty ? comment : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Guest'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Guest info header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    child: Text(
                      widget.booking.tenantName.isNotEmpty
                          ? widget.booking.tenantName[0].toUpperCase()
                          : 'G',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.booking.tenantName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Stayed at ${widget.booking.listingTitle ?? "your property"}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${_formatDate(widget.booking.effectiveCheckIn)} - ${_formatDate(widget.booking.effectiveCheckOut)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Rating
          Text(
            'How was your experience with this guest?',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _RatingSelector(
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 8),
          Text(
            _getRatingLabel(_rating),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Comment (optional)
          Text(
            'Additional Comments (Optional)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Share your experience with other hosts...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your review will be visible on the guest\'s profile after both you and the guest have submitted reviews, or after 14 days.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Submit button
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit Review'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  String _getRatingLabel(double rating) {
    return switch (rating.round()) {
      1 => 'Poor',
      2 => 'Fair',
      3 => 'Good',
      4 => 'Very Good',
      5 => 'Excellent',
      _ => '',
    };
  }

  String _formatDate(DateTime date) {
    final months = [
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
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _RatingSelector extends StatelessWidget {
  const _RatingSelector({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = index + 1.0;
        final isFilled = value >= starValue;

        return GestureDetector(
          onTap: () => onChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              isFilled ? Icons.star : Icons.star_border,
              size: 48,
              color: isFilled ? Colors.amber : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }),
    );
  }
}
