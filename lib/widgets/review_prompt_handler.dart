import 'package:flutter/material.dart';

import '../models/booking.dart';
import '../models/review.dart';
import '../repositories/supabase_musafir_repository.dart';
import '../screens/review/guest_review_screen.dart';
import '../services/review/review_prompt_config.dart';
import '../state/auth_state.dart';
import 'modern_banner.dart';

/// Handles showing review prompts for completed bookings.
///
/// Prompts are throttled by [ReviewPromptConfig] (default: at most twice a
/// week) instead of appearing on every app open.
class ReviewPromptHandler extends StatefulWidget {
  const ReviewPromptHandler({
    super.key,
    required this.child,
    required this.repository,
    required this.authState,
  });

  final Widget child;
  final SupabaseMusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<ReviewPromptHandler> createState() => _ReviewPromptHandlerState();
}

class _ReviewPromptHandlerState extends State<ReviewPromptHandler>
    with WidgetsBindingObserver {
  bool _hasCheckedReviews = false;
  List<Booking> _pendingReviews = [];
  int _currentReviewIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check on first load after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingReviews();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Check for pending reviews when app resumes
    if (state == AppLifecycleState.resumed) {
      _hasCheckedReviews = false;
      _checkPendingReviews();
    }
  }

  Future<void> _checkPendingReviews() async {
    if (_hasCheckedReviews) return;
    if (!widget.authState.isLoggedIn) return;

    final userId = widget.authState.currentUser?.id;
    if (userId == null) return;

    _hasCheckedReviews = true;

    // Respect the user's reminder frequency (off / weekly / twice a week)
    // instead of prompting on every app open.
    if (!await ReviewPromptConfig.shouldShowPrompt()) return;

    // Refresh data first to get latest bookings and reviews
    await widget.repository.refresh();

    final pending = widget.repository.getUnreviewedCompletedBookings(userId);

    if (pending.isNotEmpty && mounted) {
      await ReviewPromptConfig.markPromptShown();
      if (!mounted) return;
      setState(() {
        _pendingReviews = pending;
        _currentReviewIndex = 0;
      });
      _showNextReviewPrompt();
    }
  }

  void _showNextReviewPrompt() {
    if (_currentReviewIndex >= _pendingReviews.length) {
      setState(() {
        _pendingReviews = [];
        _currentReviewIndex = 0;
      });
      return;
    }

    final booking = _pendingReviews[_currentReviewIndex];
    final listing = widget.repository.getListingById(booking.listingId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ReviewPromptModal(
        booking: booking,
        listingTitle: listing?.title ?? booking.listingTitle ?? 'Your stay',
        listingImage: listing?.imageUrls.firstOrNull,
        onSkip: () {
          Navigator.pop(context);
          _currentReviewIndex++;
          _showNextReviewPrompt();
        },
        onReview: () {
          Navigator.pop(context);
          _navigateToReview(booking);
        },
        remainingCount: _pendingReviews.length - _currentReviewIndex - 1,
      ),
    );
  }

  void _navigateToReview(Booking booking) {
    final user = widget.authState.currentUser;
    if (user == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuestReviewScreen(
          booking: booking,
          onSubmit: (GuestReviewRatings ratings, String comment) async {
            final hostId = await widget.repository
                .fetchHostIdForListing(booking.listingId);
            if (!context.mounted) return false;
            if (hostId == null || hostId.isEmpty) {
              ModernBanner.showError(
                context,
                'Could not submit review. Please try again later.',
              );
              return false;
            }

            final review = Review.guestReview(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              bookingId: booking.id,
              listingId: booking.listingId,
              reviewerId: user.id,
              reviewerName: user.name,
              reviewerAvatarUrl: user.avatarUrl,
              hostId: hostId,
              ratings: ratings,
              comment: comment,
            );

            final saved = await widget.repository.saveReview(review);
            if (!context.mounted) return saved;
            if (!saved) {
              ModernBanner.showError(
                context,
                'Could not submit review. Please check your connection and try again.',
              );
              return false;
            }

            Navigator.pop(context);
            ModernBanner.showSuccess(context, 'Thank you for your review!');

            // Show next review prompt
            _currentReviewIndex++;
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _showNextReviewPrompt();
            });
            return true;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _ReviewPromptModal extends StatelessWidget {
  const _ReviewPromptModal({
    required this.booking,
    required this.listingTitle,
    this.listingImage,
    required this.onSkip,
    required this.onReview,
    required this.remainingCount,
  });

  final Booking booking;
  final String listingTitle;
  final String? listingImage;
  final VoidCallback onSkip;
  final VoidCallback onReview;
  final int remainingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.rate_review,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'How was your stay?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Listing name
                Text(
                  listingTitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Booking date
                Text(
                  'Completed on ${_formatDate(booking.completedAt ?? booking.effectiveCheckOut)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),

                if (remainingCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '+$remainingCount more to review',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSkip,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: onReview,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Write Review'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: bottomPadding),
        ],
      ),
    );
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
