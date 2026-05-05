import 'package:flutter/material.dart';

import '../models/booking_duration.dart';
import '../models/listing.dart';
import '../repositories/musafir_repository.dart';
import '../widgets/app_text_field.dart';
import '../widgets/area_map_preview.dart';
import '../widgets/info_card.dart';
import '../widgets/listing_card.dart';
import '../widgets/section_title.dart';

class TenantDashboard extends StatefulWidget {
  const TenantDashboard({super.key, required this.repository});

  final MusafirRepository repository;

  @override
  State<TenantDashboard> createState() => _TenantDashboardState();
}

class _TenantDashboardState extends State<TenantDashboard> {
  final areaLatController = TextEditingController(text: '23.8103');
  final areaLngController = TextEditingController(text: '90.4125');
  final areaDeltaController = TextEditingController(text: '0.08');
  final tenantNameController = TextEditingController(text: 'Guest Tenant');
  List<Listing> results = [];

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
    areaLatController.dispose();
    areaLngController.dispose();
    areaDeltaController.dispose();
    tenantNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Find by Area',
          subtitle:
              'Tenants choose a map area and see available seats, rooms, or full houses.',
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: tenantNameController,
          label: 'Tenant Name',
          hint: 'Your name',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: areaLatController,
                label: 'Center Latitude',
                hint: '23.8103',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                controller: areaLngController,
                label: 'Center Longitude',
                hint: '90.4125',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: areaDeltaController,
          label: 'Search Radius Delta',
          hint: '0.08',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.search),
          label: const Text('Search Available Rentals'),
        ),
        const SizedBox(height: 20),
        AreaMapPreview(
          centerLat: double.tryParse(areaLatController.text) ?? 23.8103,
          centerLng: double.tryParse(areaLngController.text) ?? 90.4125,
          listings: results,
        ),
        const SizedBox(height: 20),
        if (results.isEmpty)
          const InfoCard(message: 'No available results in this area.')
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
        centerLat: double.tryParse(areaLatController.text.trim()) ?? 23.8103,
        centerLng: double.tryParse(areaLngController.text.trim()) ?? 90.4125,
        delta: double.tryParse(areaDeltaController.text.trim()) ?? 0.08,
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
                    value: selectedDuration,
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
                  Text('Estimated price: ${estimatedCost.toStringAsFixed(0)} BDT'),
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
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Booked until ${booking.endAt}. Total ${booking.totalPrice.toStringAsFixed(0)} BDT.',
                          ),
                        ),
                      );
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
