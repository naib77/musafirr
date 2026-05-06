import 'package:flutter/material.dart';

import '../../data/facility_catalog.dart';
import '../../data/placeholder_images.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../repositories/in_memory_musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/location_picker.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final InMemoryMusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 5;

  // Form data
  ListingType _propertyType = ListingType.room;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController(text: 'Dhaka, Bangladesh');
  final _cityController = TextEditingController(text: 'Dhaka');
  double _latitude = 23.7806;
  double _longitude = 90.4070;
  int _maxGuests = 2;
  int _bedrooms = 1;
  int _beds = 1;
  int _bathrooms = 1;
  final Set<String> _selectedAmenities = {'Wi-Fi', 'Attached Bath'};
  final _priceController = TextEditingController(text: '1500');

  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0: // Property type
        return true;
      case 1: // Basics
        return _titleController.text.trim().isNotEmpty;
      case 2: // Location
        return _addressController.text.trim().isNotEmpty &&
            _cityController.text.trim().isNotEmpty;
      case 3: // Details
        return _maxGuests > 0 && _bedrooms > 0 && _beds > 0 && _bathrooms > 0;
      case 4: // Pricing
        return double.tryParse(_priceController.text) != null &&
            double.parse(_priceController.text) > 0;
      default:
        return false;
    }
  }

  Future<void> _submitListing() async {
    if (!_canProceed()) return;

    setState(() => _isSubmitting = true);

    try {
      final user = widget.authState.currentUser;
      final price = double.parse(_priceController.text);

      // Get random images for the listing
      final listingIndex = widget.repository.listings.length;
      final images = PlaceholderImages.forListing(listingIndex);

      final listing = Listing(
        id: 'listing_${DateTime.now().millisecondsSinceEpoch}',
        hostId: user?.id,
        ownerName: user?.name ?? 'Host',
        hostAvatarUrl: user?.avatarUrl,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        country: 'Bangladesh',
        type: _propertyType,
        latitude: _latitude,
        longitude: _longitude,
        pricePerNight: price,
        hourlyRate: price / 10,
        dailyRate: price,
        monthlyRate: price * 25,
        imageUrls: images,
        maxGuests: _maxGuests,
        bedrooms: _bedrooms,
        beds: _beds,
        bathrooms: _bathrooms,
        facilities: FacilityCatalog.ownerSelectable
            .where((f) => _selectedAmenities.contains(f.name))
            .toList(),
        rating: null,
        reviewCount: 0,
        isSuperhost: false,
        available: true,
      );

      // Add to repository (we need to add a method for this)
      widget.repository.addListing(listing);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create listing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${_currentStep + 1} of $_totalSteps'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showExitConfirmation(context),
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),

          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentStep = index);
              },
              children: [
                _PropertyTypeStep(
                  selectedType: _propertyType,
                  onTypeSelected: (type) {
                    setState(() => _propertyType = type);
                  },
                ),
                _BasicsStep(
                  titleController: _titleController,
                  descriptionController: _descriptionController,
                  onChanged: () => setState(() {}),
                ),
                _LocationStep(
                  addressController: _addressController,
                  cityController: _cityController,
                  latitude: _latitude,
                  longitude: _longitude,
                  onLocationChanged: (lat, lng, address) {
                    setState(() {
                      _latitude = lat;
                      _longitude = lng;
                      if (address != null) {
                        _addressController.text = address;
                      }
                    });
                  },
                  onChanged: () => setState(() {}),
                ),
                _DetailsStep(
                  maxGuests: _maxGuests,
                  bedrooms: _bedrooms,
                  beds: _beds,
                  bathrooms: _bathrooms,
                  selectedAmenities: _selectedAmenities,
                  onGuestsChanged: (v) => setState(() => _maxGuests = v),
                  onBedroomsChanged: (v) => setState(() => _bedrooms = v),
                  onBedsChanged: (v) => setState(() => _beds = v),
                  onBathroomsChanged: (v) => setState(() => _bathrooms = v),
                  onAmenityToggled: (amenity) {
                    setState(() {
                      if (_selectedAmenities.contains(amenity)) {
                        _selectedAmenities.remove(amenity);
                      } else {
                        _selectedAmenities.add(amenity);
                      }
                    });
                  },
                ),
                _PricingStep(
                  priceController: _priceController,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          ),

          // Bottom navigation
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  TextButton(
                    onPressed: _previousStep,
                    child: const Text('Back'),
                  ),
                const Spacer(),
                if (_currentStep < _totalSteps - 1)
                  FilledButton(
                    onPressed: _canProceed() ? _nextStep : null,
                    child: const Text('Next'),
                  )
                else
                  FilledButton(
                    onPressed:
                        _canProceed() && !_isSubmitting ? _submitListing : null,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create Listing'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'If you leave now, your listing progress will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}

// Step 1: Property Type
class _PropertyTypeStep extends StatelessWidget {
  const _PropertyTypeStep({
    required this.selectedType,
    required this.onTypeSelected,
  });

  final ListingType selectedType;
  final ValueChanged<ListingType> onTypeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What type of place will guests have?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the option that best describes your space.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          ...ListingType.values.map((type) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PropertyTypeCard(
                  type: type,
                  isSelected: selectedType == type,
                  onTap: () => onTypeSelected(type),
                ),
              )),
        ],
      ),
    );
  }
}

class _PropertyTypeCard extends StatelessWidget {
  const _PropertyTypeCard({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final ListingType type;
  final bool isSelected;
  final VoidCallback onTap;

  IconData get _icon => switch (type) {
        ListingType.seat => Icons.chair,
        ListingType.room => Icons.bed,
        ListingType.fullHouse => Icons.home,
      };

  String get _description => switch (type) {
        ListingType.seat =>
          'A shared space with a desk or seating area for work or study.',
        ListingType.room =>
          'A private room within a larger property. Guests may share common areas.',
        ListingType.fullHouse =>
          'An entire property that guests will have to themselves.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(_icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// Step 2: Basics
class _BasicsStep extends StatelessWidget {
  const _BasicsStep({
    required this.titleController,
    required this.descriptionController,
    required this.onChanged,
  });

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell guests about your place',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a title and description that highlights what makes your space special.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: titleController,
            label: 'Listing title',
            hint: 'e.g., Cozy room in the heart of Gulshan',
            onFieldSubmitted: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: descriptionController,
            label: 'Description (optional)',
            hint: 'Describe the unique features of your space...',
            maxLines: 5,
            onFieldSubmitted: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

// Step 3: Location
class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.addressController,
    required this.cityController,
    required this.latitude,
    required this.longitude,
    required this.onLocationChanged,
    required this.onChanged,
  });

  final TextEditingController addressController;
  final TextEditingController cityController;
  final double latitude;
  final double longitude;
  final void Function(double lat, double lng, String? address)
      onLocationChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where\'s your place located?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your address is only shared with guests after they book.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: addressController,
            label: 'Street address',
            hint: 'e.g., Road 27, House 5',
            onFieldSubmitted: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: cityController,
            label: 'City / Area',
            hint: 'e.g., Gulshan, Dhaka',
            onFieldSubmitted: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await LocationPicker.show(
                context,
                initialLatitude: latitude,
                initialLongitude: longitude,
              );
              if (result != null) {
                onLocationChanged(
                  result.latitude,
                  result.longitude,
                  result.address,
                );
              }
            },
            icon: const Icon(Icons.map),
            label: const Text('Pick on Map'),
          ),
          const SizedBox(height: 8),
          Text(
            'Location: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// Step 4: Details
class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.maxGuests,
    required this.bedrooms,
    required this.beds,
    required this.bathrooms,
    required this.selectedAmenities,
    required this.onGuestsChanged,
    required this.onBedroomsChanged,
    required this.onBedsChanged,
    required this.onBathroomsChanged,
    required this.onAmenityToggled,
  });

  final int maxGuests;
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final Set<String> selectedAmenities;
  final ValueChanged<int> onGuestsChanged;
  final ValueChanged<int> onBedroomsChanged;
  final ValueChanged<int> onBedsChanged;
  final ValueChanged<int> onBathroomsChanged;
  final ValueChanged<String> onAmenityToggled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share some details',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell guests about the space and amenities.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          _CounterRow(
            label: 'Guests',
            value: maxGuests,
            onChanged: onGuestsChanged,
            min: 1,
            max: 16,
          ),
          const Divider(),
          _CounterRow(
            label: 'Bedrooms',
            value: bedrooms,
            onChanged: onBedroomsChanged,
            min: 1,
            max: 10,
          ),
          const Divider(),
          _CounterRow(
            label: 'Beds',
            value: beds,
            onChanged: onBedsChanged,
            min: 1,
            max: 20,
          ),
          const Divider(),
          _CounterRow(
            label: 'Bathrooms',
            value: bathrooms,
            onChanged: onBathroomsChanged,
            min: 1,
            max: 10,
          ),
          const SizedBox(height: 24),
          Text(
            'Amenities',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FacilityCatalog.ownerSelectable.map((facility) {
              final selected = selectedAmenities.contains(facility.name);
              return FilterChip(
                selected: selected,
                label: Text(facility.name),
                avatar: Icon(facility.icon, size: 18),
                onSelected: (_) => onAmenityToggled(facility.name),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

// Step 5: Pricing
class _PricingStep extends StatelessWidget {
  const _PricingStep({
    required this.priceController,
    required this.onChanged,
  });

  final TextEditingController priceController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your price',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can change this anytime. Include all fees in your price.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          AppTextField(
            controller: priceController,
            label: 'Price per night (\$)',
            hint: '1500',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text('\$'),
            ),
            onFieldSubmitted: (_) => onChanged(),
          ),
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pricing tips',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Similar listings in your area charge \$800 - \$3000 per night\n'
                    '• New listings often start lower to get initial bookings\n'
                    '• You can adjust prices for weekends or special dates',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
