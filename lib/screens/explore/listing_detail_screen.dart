import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/currency/money.dart';
import '../../models/booking.dart';
import '../../models/booking_conflict_exception.dart';
import '../../models/listing.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../widgets/price_breakdown_card.dart';
import '../../widgets/price_display.dart';
import 'navigation_screen.dart';

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

  bool get _isOwnListing {
    final currentUserId = widget.authState.currentUser?.id;
    return currentUserId != null && widget.listing.hostId == currentUserId;
  }

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

                    // Location & Navigation
                    _LocationSection(listing: listing),
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
                      SizedBox(height: _isOwnListing ? 24 : 100),
                    ] else
                      SizedBox(height: _isOwnListing ? 24 : 100),
                  ]),
                ),
              ),
            ],
          ),

          // Bottom booking bar (hidden for own listings)
          if (!_isOwnListing)
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

class _LocationSection extends StatefulWidget {
  const _LocationSection({required this.listing});

  final Listing listing;

  @override
  State<_LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends State<_LocationSection> {
  GoogleMapController? _mapController;
  bool _mapCreated = false;

  LatLng get _location => LatLng(widget.listing.latitude, widget.listing.longitude);

  Set<Marker> get _markers => {
    Marker(
      markerId: MarkerId(widget.listing.id),
      position: _location,
      infoWindow: InfoWindow(
        title: widget.listing.title,
        snippet: widget.listing.address,
      ),
    ),
  };

  void _openDirections() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigationScreen(listing: widget.listing),
      ),
    );
  }

  Future<void> _openInMaps() async {
    final lat = widget.listing.latitude;
    final lng = widget.listing.longitude;

    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final theme = Theme.of(context);
        messenger.clearMaterialBanners();
        messenger.showMaterialBanner(
          MaterialBanner(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Could not open maps',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: theme.colorScheme.error,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leadingPadding: EdgeInsets.zero,
            actions: [
              TextButton(
                onPressed: () => messenger.hideCurrentMaterialBanner(),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        Future.delayed(const Duration(seconds: 4), () {
          messenger.hideCurrentMaterialBanner();
        });
      }
    }
  }

  @override
  void dispose() {
    // Only dispose controller if map was fully created (fixes web bug)
    if (_mapCreated && _mapController != null) {
      _mapController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Address
        Row(
          children: [
            Icon(
              Icons.location_on,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.listing.address,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Google Map
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _location,
              zoom: 15,
            ),
            markers: _markers,
            onMapCreated: (controller) {
              _mapController = controller;
              _mapCreated = true;
            },
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openInMaps,
                icon: const Icon(Icons.map_outlined),
                label: const Text('View on Map'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _openDirections,
                icon: const Icon(Icons.directions),
                label: const Text('Get Directions'),
              ),
            ),
          ],
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
            review.comment ?? '',
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
  List<Booking> _userConflictingBookings = [];
  bool _isCheckingAvailability = false;

  bool get _hasListingConflict => _conflictingBookings.isNotEmpty;
  bool get _hasUserConflict => _userConflictingBookings.isNotEmpty;
  bool get _hasConflict => _hasListingConflict || _hasUserConflict;

  @override
  void initState() {
    super.initState();
    // Check for conflicts when selection changes
  }

  /// Show a modern error banner at the top
  void _showErrorBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('Dismiss', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  /// Show a modern success banner at the top
  void _showSuccessBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  /// Show a modern warning/info banner at the top
  void _showWarningBanner(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 4), () {
      messenger.hideCurrentMaterialBanner();
    });
  }

  void _checkAvailability() {
    if (!_isSelectionComplete) {
      setState(() {
        _conflictingBookings = [];
        _userConflictingBookings = [];
      });
      return;
    }

    setState(() => _isCheckingAvailability = true);

    // Check listing conflicts (same room/seat already booked)
    final listingConflicts = widget.repository.getConflictingBookings(
      listingId: widget.listing.id,
      checkIn: _checkIn,
      checkOut: _checkOut,
    );

    // Check user conflicts (user already has a booking during this time)
    List<Booking> userConflicts = [];
    final user = widget.authState.currentUser;
    if (user != null) {
      userConflicts = widget.repository.getUserConflictingBookings(
        userId: user.id,
        checkIn: _checkIn,
        checkOut: _checkOut,
      );
    }

    setState(() {
      _conflictingBookings = listingConflicts;
      _userConflictingBookings = userConflicts;
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

  /// Display label for UI (user-friendly)
  String get _rateLabel {
    return switch (_durationType) {
      DurationType.hourly => 'hour',
      DurationType.daily => 'night',
      DurationType.monthly => 'month',
    };
  }

  /// Database pricing_unit value (must match enum: hour, day, month)
  String get _pricingUnit {
    return switch (_durationType) {
      DurationType.hourly => 'hour',
      DurationType.daily => 'day',
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
    final now = DateTime.now();
    final initialDate = _monthlyStartDate ?? DateTime(now.year, now.month, 1);

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(
        initialDate: initialDate,
        firstDate: DateTime(now.year, now.month, 1),
        lastDate: DateTime(now.year + 1, now.month, 1),
      ),
    );

    if (picked != null) {
      // Set to 1st of the selected month
      setState(() => _monthlyStartDate = DateTime(picked.year, picked.month, 1));
      _checkAvailability();
    }
  }

  Future<void> _confirmBooking() async {
    if (!_isSelectionComplete) {
      _showWarningBanner('Please complete your selection');
      return;
    }

    // Double-check availability before booking
    _checkAvailability();
    if (_hasConflict) {
      _showErrorBanner('This time slot is no longer available');
      return;
    }

    final user = widget.authState.currentUser;
    if (user == null) {
      _showWarningBanner('Please log in to book');
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
        unitLabel: _pricingUnit,
      );

      if (mounted) {
        Navigator.pop(context);
        _showSuccessBanner('Booking request sent! Awaiting host confirmation.');
      }
    } on BookingConflictException catch (e) {
      if (mounted) {
        // Refresh conflict check to show updated conflicts
        _checkAvailability();

        String message;
        if (e.conflictType == ConflictType.user) {
          message = 'You already have a booking during this time. You cannot book multiple places at the same time.';
        } else {
          message = 'This time slot was just booked by someone else. Please select different dates.';
        }

        _showErrorBanner(message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Booking failed. Please try again.');
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
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle (tappable to close)
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            // Close button row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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

                    // User conflict warning (you already have a booking)
                    if (_hasUserConflict) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_off,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'You have another booking',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'You cannot book multiple places at the same time',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Show user's conflicting bookings
                      ..._userConflictingBookings.map((booking) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.event_busy,
                                    size: 16,
                                    color: Colors.orange.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${booking.listingTitle ?? 'Your booking'}: ${_formatDateTime(booking.effectiveCheckIn)} - ${_formatDateTime(booking.effectiveCheckOut)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 8),
                    ],

                    // Listing conflict warning (this place is already booked)
                    if (_hasListingConflict) ...[
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
                    if (_isSelectionComplete &&
                        !_hasConflict &&
                        !_isCheckingAvailability) ...[
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
            ),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _hours > 1
                            ? () {
                                setState(() => _hours--);
                                _checkAvailability();
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.remove_circle_outline,
                            size: 28,
                            color: _hours > 1
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
                      ),
                      Text(
                        '$_hours hr${_hours > 1 ? 's' : ''}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: _hours < 12
                            ? () {
                                setState(() => _hours++);
                                _checkAvailability();
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.add_circle_outline,
                            size: 28,
                            color: _hours < 12
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
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
      // Start month
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
              const Icon(Icons.calendar_month),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Month',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _monthlyStartDate != null
                          ? _formatMonthYear(_monthlyStartDate!)
                          : 'Select start month',
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

      // Booking period preview
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
                Icons.date_range,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatMonthYear(_monthlyStartDate!)} - ${_formatMonthYear(DateTime(_monthlyStartDate!.year, _monthlyStartDate!.month + _months - 1, 1))}',
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
                height: 48,
                decoration: BoxDecoration(
                  color: _getBookingTypeColor(booking.unitLabel),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getBookingTypeColor(booking.unitLabel).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getBookingTypeLabel(booking.unitLabel),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _getBookingTypeColor(booking.unitLabel),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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

  String _getBookingTypeLabel(String unitLabel) {
    return switch (unitLabel.toLowerCase()) {
      'hour' => 'Hourly',
      'day' => 'Daily',
      'month' => 'Monthly',
      _ => unitLabel,
    };
  }

  Color _getBookingTypeColor(String unitLabel) {
    return switch (unitLabel.toLowerCase()) {
      'hour' => Colors.orange,
      'day' => Colors.blue,
      'month' => Colors.purple,
      _ => Colors.grey,
    };
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

  String _formatMonthYear(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
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

/// Month picker dialog for monthly bookings
class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  static const _monthNames = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
  }

  bool _isMonthSelectable(int year, int month) {
    final date = DateTime(year, month, 1);
    return !date.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1)) &&
        !date.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1));
  }

  List<int> get _availableYears {
    final years = <int>[];
    for (int year = widget.firstDate.year; year <= widget.lastDate.year; year++) {
      years.add(year);
    }
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select Start Month',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Year selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _availableYears.first < _selectedYear
                      ? () => setState(() => _selectedYear--)
                      : null,
                ),
                Text(
                  '$_selectedYear',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _availableYears.last > _selectedYear
                      ? () => setState(() => _selectedYear++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Month grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final isSelectable = _isMonthSelectable(_selectedYear, month);
                final isSelected = _selectedYear == widget.initialDate.year &&
                    month == _selectedMonth;

                return Material(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : isSelectable
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: isSelectable
                        ? () => setState(() => _selectedMonth = month)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Text(
                        _monthNames[index].substring(0, 3),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : isSelectable
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      DateTime(_selectedYear, _selectedMonth, 1),
                    );
                  },
                  child: const Text('Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
