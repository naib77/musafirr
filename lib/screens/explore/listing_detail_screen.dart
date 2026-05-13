import 'package:flutter/material.dart';

import '../../core/currency/money.dart';
import '../../models/booking.dart';
import '../../models/listing.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../widgets/price_breakdown_card.dart';
import '../../widgets/price_display.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listing,
    required this.repository,
    required this.authState,
    required this.favoritesState,
  });

  final Listing listing;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final PageController _imageController = PageController();
  int _currentImageIndex = 0;

  @override
  void dispose() {
    _imageController.dispose();
    super.dispose();
  }

  void _openBookingSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(
        listing: widget.listing,
        repository: widget.repository,
        authState: widget.authState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    final reviews = widget.repository.getReviewsForListing(listing.id);

    return Scaffold(
      body: Stack(
        children: [
          // Scrollable content
          CustomScrollView(
            slivers: [
              // Image gallery
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1.2,
                      child: listing.imageUrls.isNotEmpty
                          ? PageView.builder(
                              controller: _imageController,
                              onPageChanged: (index) {
                                setState(() => _currentImageIndex = index);
                              },
                              itemCount: listing.imageUrls.length,
                              itemBuilder: (context, index) {
                                return Image.network(
                                  listing.imageUrls[index],
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildImagePlaceholder(theme),
                                );
                              },
                            )
                          : _buildImagePlaceholder(theme),
                    ),
                    // Back button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      child: CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                    // Favorite button
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 16,
                      child: ListenableBuilder(
                        listenable: widget.favoritesState,
                        builder: (context, _) {
                          final isFavorite =
                              widget.favoritesState.isFavorite(listing.id);
                          return CircleAvatar(
                            backgroundColor: Colors.white,
                            child: IconButton(
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Colors.black,
                              ),
                              onPressed: () {
                                widget.favoritesState
                                    .toggleFavorite(listing.id);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    // Page indicators
                    if (listing.imageUrls.length > 1)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            listing.imageUrls.length,
                            (index) => Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index == _currentImageIndex
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Content
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Title
                    Text(
                      listing.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Location & rating
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${listing.city ?? listing.address}, ${listing.country ?? 'Bangladesh'}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (listing.rating != null) ...[
                          const Icon(Icons.star, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${listing.rating!.toStringAsFixed(2)} (${listing.reviewCount} reviews)',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 32),

                    // Host info
                    _HostInfoCard(listing: listing),
                    const Divider(height: 32),

                    // Property details
                    _PropertyDetails(listing: listing),
                    const Divider(height: 32),

                    // Description
                    if (listing.description != null) ...[
                      Text(
                        'About this place',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        listing.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const Divider(height: 32),
                    ],

                    // Amenities
                    _AmenitiesGrid(listing: listing),
                    const Divider(height: 32),

                    // Reviews
                    if (reviews.isNotEmpty) ...[
                      _ReviewsSection(reviews: reviews),
                      const SizedBox(height: 100),
                    ] else
                      const SizedBox(height: 100),
                  ]),
                ),
              ),
            ],
          ),

          // Bottom booking bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PriceDisplay(
                      amount: listing.displayPriceMoney,
                      perUnit: 'night',
                      style: PriceDisplayStyle.normal,
                    ),
                  ),
                  FilledButton(
                    onPressed: _openBookingSheet,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Reserve'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _HostInfoCard extends StatelessWidget {
  const _HostInfoCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: listing.hostAvatarUrl != null
              ? NetworkImage(listing.hostAvatarUrl!)
              : null,
          child: listing.hostAvatarUrl == null
              ? Text(
                  listing.ownerName.isNotEmpty
                      ? listing.ownerName[0].toUpperCase()
                      : 'H',
                  style: theme.textTheme.titleLarge,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hosted by ${listing.ownerName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (listing.isSuperhost)
                Row(
                  children: [
                    Icon(
                      Icons.workspace_premium,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Superhost',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PropertyDetails extends StatelessWidget {
  const _PropertyDetails({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _DetailItem(
          icon: Icons.people,
          value: '${listing.maxGuests}',
          label: 'guests',
          theme: theme,
        ),
        _DetailItem(
          icon: Icons.bed,
          value: '${listing.bedrooms}',
          label: 'bedrooms',
          theme: theme,
        ),
        _DetailItem(
          icon: Icons.king_bed,
          value: '${listing.beds}',
          label: 'beds',
          theme: theme,
        ),
        _DetailItem(
          icon: Icons.bathtub,
          value: '${listing.bathrooms}',
          label: 'baths',
          theme: theme,
        ),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String value;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AmenitiesGrid extends StatelessWidget {
  const _AmenitiesGrid({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What this place offers',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: listing.facilities.map((facility) {
            return Chip(
              avatar: Icon(facility.icon, size: 18),
              label: Text(facility.name),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews});

  final List<Review> reviews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reviews',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...reviews.take(3).map((review) => _ReviewCard(review: review)),
        if (reviews.length > 3)
          TextButton(
            onPressed: () {
              // TODO: Show all reviews
            },
            child: Text('Show all ${reviews.length} reviews'),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: review.userAvatarUrl != null
                    ? NetworkImage(review.userAvatarUrl!)
                    : null,
                child: review.userAvatarUrl == null
                    ? Text(review.userName[0].toUpperCase())
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatDate(review.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    review.rating.toStringAsFixed(1),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

enum DurationType { hourly, daily, monthly }

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({
    required this.listing,
    required this.repository,
    required this.authState,
  });

  final Listing listing;
  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  DurationType _durationType = DurationType.daily;

  // Daily booking
  DateTimeRange? _dateRange;

  // Hourly booking
  DateTime? _hourlyDate;
  TimeOfDay? _startTime;
  int _hours = 1;

  // Monthly booking
  DateTime? _monthlyStartDate;
  int _months = 1;

  int _guestCount = 1;
  bool _isBooking = false;

  // Conflict tracking
  List<Booking> _conflictingBookings = [];
  bool _isCheckingAvailability = false;

  bool get _hasConflict => _conflictingBookings.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Check for conflicts when selection changes
  }

  void _checkAvailability() {
    if (!_isSelectionComplete) {
      setState(() => _conflictingBookings = []);
      return;
    }

    setState(() => _isCheckingAvailability = true);

    final conflicts = widget.repository.getConflictingBookings(
      listingId: widget.listing.id,
      checkIn: _checkIn,
      checkOut: _checkOut,
    );

    setState(() {
      _conflictingBookings = conflicts;
      _isCheckingAvailability = false;
    });
  }

  double get _rate {
    return switch (_durationType) {
      DurationType.hourly => widget.listing.hourlyRate,
      DurationType.daily => widget.listing.dailyRate,
      DurationType.monthly => widget.listing.monthlyRate,
    };
  }

  Money get _rateMoney {
    return switch (_durationType) {
      DurationType.hourly => widget.listing.hourlyRateMoney,
      DurationType.daily => widget.listing.dailyRateMoney,
      DurationType.monthly => widget.listing.monthlyRateMoney,
    };
  }

  String get _rateLabel {
    return switch (_durationType) {
      DurationType.hourly => 'hour',
      DurationType.daily => 'night',
      DurationType.monthly => 'month',
    };
  }

  int get _duration {
    return switch (_durationType) {
      DurationType.hourly => _hours,
      DurationType.daily => _dateRange != null
          ? _dateRange!.end.difference(_dateRange!.start).inDays
          : 0,
      DurationType.monthly => _months,
    };
  }

  double get _totalPrice {
    return _rate * _duration;
  }

  Money get _totalPriceMoney {
    return _rateMoney.multiply(_duration.toDouble());
  }

  bool get _isSelectionComplete {
    return switch (_durationType) {
      DurationType.hourly => _hourlyDate != null && _startTime != null,
      DurationType.daily => _dateRange != null,
      DurationType.monthly => _monthlyStartDate != null,
    };
  }

  DateTime get _checkIn {
    return switch (_durationType) {
      DurationType.hourly => DateTime(
          _hourlyDate!.year,
          _hourlyDate!.month,
          _hourlyDate!.day,
          _startTime!.hour,
          _startTime!.minute,
        ),
      DurationType.daily => _dateRange!.start,
      DurationType.monthly => _monthlyStartDate!,
    };
  }

  DateTime get _checkOut {
    return switch (_durationType) {
      DurationType.hourly => _checkIn.add(Duration(hours: _hours)),
      DurationType.daily => _dateRange!.end,
      DurationType.monthly => DateTime(
          _monthlyStartDate!.year,
          _monthlyStartDate!.month + _months,
          _monthlyStartDate!.day,
        ),
    };
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectHourlyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hourlyDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _hourlyDate = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectMonthlyStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _monthlyStartDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _monthlyStartDate = picked);
      _checkAvailability();
    }
  }

  Future<void> _confirmBooking() async {
    if (!_isSelectionComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete your selection')),
      );
      return;
    }

    // Double-check availability before booking
    _checkAvailability();
    if (_hasConflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This time slot is no longer available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = widget.authState.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to book')),
      );
      return;
    }

    setState(() => _isBooking = true);

    try {
      widget.repository.createMarketplaceBooking(
        listingId: widget.listing.id,
        userId: user.id,
        userName: user.name,
        checkIn: _checkIn,
        checkOut: _checkOut,
        guestCount: _guestCount,
        totalPrice: _totalPrice,
        unitLabel: _rateLabel,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking confirmed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBooking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Reserve',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Duration type selector
            SegmentedButton<DurationType>(
              segments: const [
                ButtonSegment(
                  value: DurationType.hourly,
                  label: Text('Hourly'),
                  icon: Icon(Icons.schedule),
                ),
                ButtonSegment(
                  value: DurationType.daily,
                  label: Text('Daily'),
                  icon: Icon(Icons.today),
                ),
                ButtonSegment(
                  value: DurationType.monthly,
                  label: Text('Monthly'),
                  icon: Icon(Icons.calendar_month),
                ),
              ],
              selected: {_durationType},
              onSelectionChanged: (selected) {
                setState(() => _durationType = selected.first);
              },
            ),
            const SizedBox(height: 16),

            // Rate display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: PriceDisplay(
                  amount: _rateMoney,
                  perUnit: _rateLabel,
                  style: PriceDisplayStyle.large,
                  color: theme.colorScheme.onPrimaryContainer,
                  alignment: CrossAxisAlignment.center,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Existing bookings preview
            _buildExistingBookingsPreview(theme),
            const SizedBox(height: 16),

            // Duration-specific selection UI
            ..._buildDurationSelector(theme),
            const SizedBox(height: 16),

            // Guest count
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guests',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$_guestCount guest${_guestCount > 1 ? 's' : ''}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _guestCount > 1
                            ? () => setState(() => _guestCount--)
                            : null,
                      ),
                      Text(
                        '$_guestCount',
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _guestCount < widget.listing.maxGuests
                            ? () => setState(() => _guestCount++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Conflict warning
            if (_hasConflict) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Time slot not available',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_conflictingBookings.length} existing booking${_conflictingBookings.length > 1 ? 's' : ''} conflict with your selection',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Show conflicting bookings
              ..._conflictingBookings.map((booking) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_busy,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_formatDateTime(booking.effectiveCheckIn)} - ${_formatDateTime(booking.effectiveCheckOut)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
              const SizedBox(height: 8),
            ],

            // Availability indicator
            if (_isSelectionComplete && !_hasConflict && !_isCheckingAvailability) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'This time slot is available',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Price breakdown
            if (_isSelectionComplete && !_hasConflict) ...[
              PriceSummaryRow(
                basePrice: _rateMoney,
                units: _duration,
                unitType: _rateLabel,
                total: _totalPriceMoney,
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _totalPriceMoney.format(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Confirm button
            FilledButton(
              onPressed: (_isBooking || _hasConflict || !_isSelectionComplete)
                  ? null
                  : _confirmBooking,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _hasConflict ? Colors.grey : null,
              ),
              child: _isBooking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_hasConflict
                      ? 'Time Slot Unavailable'
                      : _isSelectionComplete
                          ? 'Confirm Booking'
                          : 'Complete Selection to Continue'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDurationSelector(ThemeData theme) {
    return switch (_durationType) {
      DurationType.hourly => _buildHourlySelector(theme),
      DurationType.daily => _buildDailySelector(theme),
      DurationType.monthly => _buildMonthlySelector(theme),
    };
  }

  List<Widget> _buildHourlySelector(ThemeData theme) {
    return [
      // Date selection
      GestureDetector(
        onTap: _selectHourlyDate,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _hourlyDate != null
                          ? _formatDate(_hourlyDate!)
                          : 'Select date',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Time and hours in a row
      Row(
        children: [
          // Start time
          Expanded(
            child: GestureDetector(
              onTap: _selectStartTime,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Time',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _startTime != null
                              ? _formatTime(_startTime!)
                              : 'Select',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Hours selector
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Duration',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _hours > 1
                            ? () {
                                setState(() => _hours--);
                                _checkAvailability();
                              }
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$_hours hr${_hours > 1 ? 's' : ''}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _hours < 12
                            ? () {
                                setState(() => _hours++);
                                _checkAvailability();
                              }
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // End time preview
      if (_hourlyDate != null && _startTime != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Ends at ${_formatTime(TimeOfDay(hour: (_startTime!.hour + _hours) % 24, minute: _startTime!.minute))}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildDailySelector(ThemeData theme) {
    return [
      GestureDetector(
        onTap: _selectDates,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dates',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _dateRange != null
                          ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                          : 'Select dates',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildMonthlySelector(ThemeData theme) {
    return [
      // Start date
      GestureDetector(
        onTap: _selectMonthlyStartDate,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Date',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _monthlyStartDate != null
                          ? _formatDate(_monthlyStartDate!)
                          : 'Select start date',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Months selector
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Duration',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$_months month${_months > 1 ? 's' : ''}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _months > 1
                      ? () {
                          setState(() => _months--);
                          _checkAvailability();
                        }
                      : null,
                ),
                Text(
                  '$_months',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _months < 12
                      ? () {
                          setState(() => _months++);
                          _checkAvailability();
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),

      // End date preview
      if (_monthlyStartDate != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Ends on ${_formatDate(DateTime(_monthlyStartDate!.year, _monthlyStartDate!.month + _months, _monthlyStartDate!.day))}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildExistingBookingsPreview(ThemeData theme) {
    final activeBookings = widget.repository.getActiveBookingsForListing(
      widget.listing.id,
    );

    // Filter to show only future bookings
    final now = DateTime.now();
    final upcomingBookings = activeBookings
        .where((b) => b.effectiveCheckOut.isAfter(now))
        .take(5)
        .toList();

    if (upcomingBookings.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: Icon(
        Icons.event_note,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'View booked dates',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${upcomingBookings.length} upcoming booking${upcomingBookings.length > 1 ? 's' : ''}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: upcomingBookings.map((booking) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getBookingTimeDescription(booking),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getBookingTimeDescription(Booking booking) {
    final checkIn = booking.effectiveCheckIn;
    final checkOut = booking.effectiveCheckOut;
    final duration = checkOut.difference(checkIn);

    if (duration.inHours < 24) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''} (${_formatTimeFromDateTime(checkIn)} - ${_formatTimeFromDateTime(checkOut)})';
    } else if (duration.inDays < 30) {
      return '${duration.inDays} night${duration.inDays > 1 ? 's' : ''}';
    } else {
      final months = (duration.inDays / 30).round();
      return '$months month${months > 1 ? 's' : ''}';
    }
  }

  String _formatTimeFromDateTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '${months[dateTime.month - 1]} ${dateTime.day}, $hour:$minute $period';
  }
}
