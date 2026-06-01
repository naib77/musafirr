import 'package:flutter/material.dart';

import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../repositories/musafir_repository.dart';
import '../services/location_service.dart';
import '../widgets/app_text_field.dart';
import '../widgets/info_card.dart';
import '../widgets/listing_card.dart';
import '../widgets/modern_banner.dart';
import '../widgets/musafir_map.dart';
import '../widgets/place_search_field.dart';
import '../widgets/section_title.dart';

class TenantDashboard extends StatefulWidget {
  const TenantDashboard({super.key, required this.repository});

  final MusafirRepository repository;

  @override
  State<TenantDashboard> createState() => _TenantDashboardState();
}

class _TenantDashboardState extends State<TenantDashboard> {
  final tenantNameController = TextEditingController(text: 'Guest Tenant');
  final _locationService = LocationService();

  double _centerLat = 23.8103;
  double _centerLng = 90.4125;
  final double _searchDelta = 0.08;
  List<Listing> results = [];
  bool _isLoadingLocation = false;

  static const durations = [
    BookingDuration(label: '1 Hour', unitLabel: 'hour', multiplier: 1),
    BookingDuration(label: '6 Hours', unitLabel: 'hour', multiplier: 6),
    BookingDuration(label: '1 Day', unitLabel: 'day', multiplier: 1),
    BookingDuration(label: '7 Days', unitLabel: 'day', multiplier: 7),
    BookingDuration(label: '1 Month', unitLabel: 'month', multiplier: 1),
  ];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    tenantNameController.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() => _isLoadingLocation = true);

    final position = await _locationService.getCurrentLocation();

    if (mounted) {
      setState(() => _isLoadingLocation = false);

      if (position != null) {
        setState(() {
          _centerLat = position.latitude;
          _centerLng = position.longitude;
        });
        _search();
      } else {
        ModernBanner.showError(context, 'Could not get your location. Please check permissions.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Find by Area',
          subtitle:
              'Search for available rentals by location. Tap on the map or use your current location.',
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: tenantNameController,
          label: 'Tenant Name',
          hint: 'Your name',
        ),
        const SizedBox(height: 16),
        PlaceSearchField(
          hintText: 'Search for a location...',
          onPlaceSelected: (result) {
            setState(() {
              _centerLat = result.latitude;
              _centerLng = result.longitude;
            });
            _search();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoadingLocation ? null : _useMyLocation,
                icon: _isLoadingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Use My Location'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: const Text('Search'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        MusafirMap(
          centerLat: _centerLat,
          centerLng: _centerLng,
          listings: results,
          height: 280,
          onTap: (lat, lng) {
            setState(() {
              _centerLat = lat;
              _centerLng = lng;
            });
            _search();
          },
          onListingTap: (listing) => _showBookingSheet(context, listing),
        ),
        const SizedBox(height: 8),
        Text(
          'Searching around ${_centerLat.toStringAsFixed(4)}, ${_centerLng.toStringAsFixed(4)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '${results.length} rental${results.length == 1 ? '' : 's'} found',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (results.isEmpty)
          const InfoCard(
              message:
                  'No available results in this area. Try a different location.')
        else
          ...results.map(
            (listing) => ListingCard(
              listing: listing,
              onBook: () => _showBookingSheet(context, listing),
            ),
          ),
      ],
    );
  }

  void _search() {
    setState(() {
      results = widget.repository.searchByArea(
        centerLat: _centerLat,
        centerLng: _centerLng,
        delta: _searchDelta,
      );
    });
  }

  Future<void> _showBookingSheet(BuildContext context, Listing listing) async {
    BookingDuration selectedDuration = durations.first;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final estimatedCost = switch (selectedDuration.unitLabel) {
              'hour' => listing.hourlyRate * selectedDuration.multiplier,
              'day' => listing.dailyRate * selectedDuration.multiplier,
              _ => listing.monthlyRate * selectedDuration.multiplier,
            };
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<BookingDuration>(
                    initialValue: selectedDuration,
                    decoration: const InputDecoration(
                      labelText: 'Booking Duration',
                      border: OutlineInputBorder(),
                    ),
                    items: durations
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => selectedDuration = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                      'Estimated price: ${estimatedCost.toStringAsFixed(0)} BDT'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final booking = widget.repository.createBooking(
                        listing: listing,
                        tenantName: tenantNameController.text.trim().isEmpty
                            ? 'Guest Tenant'
                            : tenantNameController.text.trim(),
                        duration: selectedDuration,
                      );
                      Navigator.pop(context);
                      _search();
                      ModernBanner.showSuccess(this.context, 'Booked until ${booking.endAt}. Total ${booking.totalPrice.toStringAsFixed(0)} BDT.');
                    },
                    child: const Text('Confirm Booking'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
