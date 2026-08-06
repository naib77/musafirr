import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../models/booking.dart';
import '../../models/guest_review_ratings.dart';

/// Screen for guests to submit a review for a listing/host.
/// Includes 6 category ratings and optional text comment.
class GuestReviewScreen extends StatefulWidget {
  const GuestReviewScreen({
    super.key,
    required this.booking,
    required this.onSubmit,
  });

  final Booking booking;

  /// Called with the entered ratings and comment. Should return true when the
  /// review was saved; on false the screen re-enables the submit button.
  final Future<bool> Function(GuestReviewRatings ratings, String comment)
      onSubmit;

  @override
  State<GuestReviewScreen> createState() => _GuestReviewScreenState();
}

class _GuestReviewScreenState extends State<GuestReviewScreen> {
  final _commentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Rating values (1-5)
  double _overall = 5.0;
  double _cleanliness = 5.0;
  double _accuracy = 5.0;
  double _communication = 5.0;
  double _location = 5.0;
  double _value = 5.0;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final ratings = GuestReviewRatings(
      overall: _overall,
      cleanliness: _cleanliness,
      accuracy: _accuracy,
      communication: _communication,
      location: _location,
      value: _value,
    );

    final success =
        await widget.onSubmit(ratings, _commentController.text.trim());
    if (!success && mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave a Review'),
      ),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Listing info header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: widget.booking.listingImageUrl != null
                            ? Image.network(
                                widget.booking.listingImageUrl!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _buildPlaceholder(theme),
                              )
                            : _buildPlaceholder(theme),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.booking.listingTitle ?? 'Your Stay',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.booking.listingCity != null)
                              Text(
                                widget.booking.listingCity!,
                                style: theme.textTheme.bodyMedium?.copyWith(
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
              const SizedBox(height: 24),

              // Overall rating
              Text(
                'Overall Experience',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _RatingSelector(
                value: _overall,
                onChanged: (v) => setState(() => _overall = v),
              ),
              const SizedBox(height: 24),

              // Category ratings
              Text(
                'Rate Your Experience',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              _CategoryRating(
                label: 'Cleanliness',
                icon: Icons.cleaning_services,
                value: _cleanliness,
                onChanged: (v) => setState(() => _cleanliness = v),
              ),
              const SizedBox(height: 12),

              _CategoryRating(
                label: 'Accuracy',
                icon: Icons.fact_check,
                value: _accuracy,
                onChanged: (v) => setState(() => _accuracy = v),
                subtitle: 'Listing matched description',
              ),
              const SizedBox(height: 12),

              _CategoryRating(
                label: 'Communication',
                icon: Icons.chat,
                value: _communication,
                onChanged: (v) => setState(() => _communication = v),
              ),
              const SizedBox(height: 12),

              _CategoryRating(
                label: 'Location',
                icon: Icons.location_on,
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 12),

              _CategoryRating(
                label: 'Value',
                icon: Icons.attach_money,
                value: _value,
                onChanged: (v) => setState(() => _value = v),
                subtitle: 'Worth the price',
              ),
              const SizedBox(height: 24),

              // Comment (optional)
              Text(
                'Write a Review (Optional)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _commentController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Share your experience with future guests...',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null &&
                      value.trim().isNotEmpty &&
                      value.trim().length < 10) {
                    return 'Review must be at least 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Your review will be visible after both you and the host have submitted reviews, or after 14 days.',
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
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      width: 64,
      height: 64,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.home,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
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
        final isHalf = value > index && value < starValue;

        return GestureDetector(
          onTap: () => onChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              isHalf
                  ? Icons.star_half
                  : (isFilled ? Icons.star : Icons.star_border),
              size: 40,
              color: isFilled || isHalf
                  ? Colors.amber
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }),
    );
  }
}

class _CategoryRating extends StatelessWidget {
  const _CategoryRating({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: List.generate(5, (index) {
              final starValue = index + 1.0;
              final isFilled = value >= starValue;

              return GestureDetector(
                onTap: () => onChanged(starValue),
                child: Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(
                    isFilled ? Icons.star : Icons.star_border,
                    size: 24,
                    color: isFilled
                        ? Colors.amber
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
