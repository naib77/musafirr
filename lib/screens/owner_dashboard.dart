import 'package:flutter/material.dart';

import '../data/facility_catalog.dart';
import '../models/listing_type.dart';
import '../models/owner_registration_draft.dart';
import '../repositories/musafir_repository.dart';
import '../widgets/app_text_field.dart';
import '../widgets/listing_summary_card.dart';
import '../widgets/location_picker.dart';
import '../widgets/section_title.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key, required this.repository});

  final MusafirRepository repository;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  final _formKey = GlobalKey<FormState>();
  final mobileController = TextEditingController();
  final titleController = TextEditingController();
  final addressController = TextEditingController(text: 'Dhaka, Bangladesh');
  final latController = TextEditingController(text: '23.7806');
  final lngController = TextEditingController(text: '90.4070');
  final hourlyController = TextEditingController(text: '100');
  final dailyController = TextEditingController(text: '1000');
  final monthlyController = TextEditingController(text: '18000');
  ListingType selectedType = ListingType.room;
  final Set<String> selectedFacilities = {'Wi-Fi', 'Attached Bath'};

  @override
  void dispose() {
    mobileController.dispose();
    titleController.dispose();
    addressController.dispose();
    latController.dispose();
    lngController.dispose();
    hourlyController.dispose();
    dailyController.dispose();
    monthlyController.dispose();
    super.dispose();
  }

  Future<void> _pickLocationOnMap() async {
    final result = await LocationPicker.show(
      context,
      initialLatitude: double.tryParse(latController.text) ?? 23.7806,
      initialLongitude: double.tryParse(lngController.text) ?? 90.4070,
    );

    if (result != null) {
      setState(() {
        latController.text = result.latitude.toStringAsFixed(6);
        lngController.text = result.longitude.toStringAsFixed(6);
        if (result.address != null && result.address!.isNotEmpty) {
          addressController.text = result.address!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionTitle(
          title: 'Register a Property',
          subtitle:
              'House owners register with mobile number, map coordinates, facilities, and rates.',
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              AppTextField(
                controller: mobileController,
                label: 'Mobile Number',
                hint: '017XXXXXXXX',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: titleController,
                label: 'Listing Title',
                hint: 'Cozy room in Banani',
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: addressController,
                label: 'Address',
                hint: 'Banani, Dhaka',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ListingType>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Rental Type',
                  border: OutlineInputBorder(),
                ),
                items: ListingType.values
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type.title)),
                    )
                    .toList(),
                onChanged: (type) {
                  if (type != null) {
                    setState(() => selectedType = type);
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: latController,
                      label: 'Latitude',
                      hint: '23.7806',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validatorOverride: _validateNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: lngController,
                      label: 'Longitude',
                      hint: '90.4070',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validatorOverride: _validateNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickLocationOnMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Pick Location on Map'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: hourlyController,
                      label: 'Hourly Rate (BDT)',
                      hint: '100',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validatorOverride: _validateNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: dailyController,
                      label: 'Daily Rate (BDT)',
                      hint: '1000',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validatorOverride: _validateNumber,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: monthlyController,
                label: 'Monthly Rate (BDT)',
                hint: '18000',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validatorOverride: _validateNumber,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Facilities',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FacilityCatalog.ownerSelectable.map((facility) {
                  final selected = selectedFacilities.contains(facility.name);
                  return FilterChip(
                    selected: selected,
                    label: Text(facility.name),
                    avatar: Icon(facility.icon, size: 18),
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          selectedFacilities.add(facility.name);
                        } else {
                          selectedFacilities.remove(facility.name);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Register Listing'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionTitle(
          title: 'Your Listings',
          subtitle: 'Newly registered entries appear immediately from in-memory storage.',
        ),
        const SizedBox(height: 12),
        ...widget.repository.listings.map((listing) => ListingSummaryCard(listing: listing)),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final facilities = FacilityCatalog.ownerSelectable
        .where((item) => selectedFacilities.contains(item.name))
        .toList();

    widget.repository.registerOwnerListing(
      OwnerRegistrationDraft(
        mobile: mobileController.text.trim(),
        title: titleController.text.trim(),
        address: addressController.text.trim(),
        type: selectedType,
        latitude: double.parse(latController.text.trim()),
        longitude: double.parse(lngController.text.trim()),
        hourlyRate: double.parse(hourlyController.text.trim()),
        dailyRate: double.parse(dailyController.text.trim()),
        monthlyRate: double.parse(monthlyController.text.trim()),
        facilities: facilities,
      ),
    );

    titleController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Listing registered successfully.')),
    );
  }

  String? _validateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }
    if (double.tryParse(value.trim()) == null) {
      return 'Enter a valid number';
    }
    return null;
  }
}
